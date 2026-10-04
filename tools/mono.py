#!/usr/bin/env python3
"""mono 仓库项目管理器 —— db.json 注册表与首页索引的唯一权威入口。

用法:
    python3 tools/mono.py new <lang> <name> [--desc "一句话说明"] [--dir <dirname>]
    python3 tools/mono.py register <lang> <dir> [--name <name>] [--desc "说明"]
    python3 tools/mono.py list
    python3 tools/mono.py index

约定:
    - 项目位于 <lang>/<dir>/ 两级目录;lang 为小写语言名
      (dart / python / go / rust / ts / shell ...)。
    - db.json 是唯一的项目注册表（相当于数据库表），索引由它生成。
      手工建目录不会进索引 —— index 时会被程序发现并按"未登记"警告。
    - README.md 中 <!-- MONO:INDEX --> 之间的内容只由本脚本重写。
    - tools/ docs/ scripts/ 与隐藏目录不是语言命名空间。
"""
import argparse
import json
import re
import sys
from datetime import date
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
README = ROOT / "README.md"
DB = ROOT / "db.json"
BEGIN = "<!-- MONO:INDEX:BEGIN -->"
END = "<!-- MONO:INDEX:END -->"

# 非语言命名空间的顶层目录
RESERVED = {"tools", "docs", "scripts", ".github"}

NAME_RE = re.compile(r"^[a-z0-9][a-z0-9._-]*$", re.IGNORECASE)


def load_db():
    if not DB.exists():
        return {"projects": []}
    return json.loads(DB.read_text(encoding="utf-8"))


def save_db(db):
    DB.write_text(
        json.dumps(db, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
    )


def find_project(db, lang, dirname):
    return next(
        (p for p in db["projects"]
         if p["lang"] == lang and p["dir"] == dirname),
        None,
    )


def unregistered_dirs(db):
    """Second-level dirs under non-reserved top dirs that aren't in db.json."""
    known = {(p["lang"], p["dir"]) for p in db["projects"]}
    stray = []
    for lang_dir in sorted(ROOT.iterdir()):
        if (not lang_dir.is_dir() or lang_dir.name.startswith(".")
                or lang_dir.name in RESERVED):
            continue
        for proj_dir in sorted(lang_dir.iterdir()):
            if proj_dir.is_dir() and (lang_dir.name, proj_dir.name) not in known:
                stray.append(f"{lang_dir.name}/{proj_dir.name}")
    return stray


def render_index(db):
    lines = ["*本节由 `python3 tools/mono.py index` 生成，请勿手改。*", ""]
    if not db["projects"]:
        lines.append("*暂无项目。*")
    by_lang: dict[str, list] = {}
    for p in db["projects"]:
        by_lang.setdefault(p["lang"], []).append(p)
    for lang in sorted(by_lang):
        lines.append(f"### {lang}")
        lines.append("| 项目 | 说明 | 创建 |")
        lines.append("|---|---|---|")
        for p in sorted(by_lang[lang], key=lambda x: x["dir"]):
            link = f"[{p['name']}]({lang}/{p['dir']}/)"
            desc = p.get("description", "")
            created = p.get("created", "")
            lines.append(f"| {link} | {desc} | {created} |")
        lines.append("")
    return "\n".join(lines).rstrip() + "\n"


def cmd_index(_args):
    text = README.read_text(encoding="utf-8") if README.exists() else "# mono\n\n"
    block = f"{BEGIN}\n{render_index(load_db())}{END}"
    if BEGIN in text and END in text:
        head, rest = text.split(BEGIN, 1)
        _, tail = rest.split(END, 1)
        new_text = head + block + tail
    else:
        new_text = text.rstrip() + "\n\n" + block + "\n"
    README.write_text(new_text, encoding="utf-8")
    print(f"索引已更新 → {README.relative_to(ROOT)}")
    stray = unregistered_dirs(load_db())
    if stray:
        print("未登记目录（不在 db.json，可用 register 登记）:")
        for s in stray:
            print(f"  - {s}")


def _add_entry(args, lang, dirname):
    db = load_db()
    if find_project(db, lang, dirname):
        sys.exit(f"已登记: {lang}/{dirname}")
    db["projects"].append(
        {
            "name": args.name or dirname,
            "lang": lang,
            "dir": dirname,
            "description": args.desc or "",
            "created": date.today().isoformat(),
        }
    )
    save_db(db)


def cmd_new(args):
    lang = args.lang.lower()
    dirname = (args.dir or args.name).lower()
    if not NAME_RE.match(lang) or lang in RESERVED:
        sys.exit(f"非法语言名: {lang!r}（需小写字母/数字/连字符，且非保留目录）")
    if not NAME_RE.match(dirname):
        sys.exit(f"非法目录名: {dirname!r}")
    proj = ROOT / lang / dirname
    if proj.exists():
        sys.exit(f"已存在: {proj.relative_to(ROOT)}")
    proj.mkdir(parents=True)
    (proj / "README.md").write_text(
        f"# {args.name}\n\n{args.desc or '待补充。'}\n", encoding="utf-8"
    )
    _add_entry(args, lang, dirname)
    cmd_index(args)
    print(f"已创建 {lang}/{dirname}/")


def cmd_register(args):
    """登记一个已存在的 <lang>/<dir>/ 目录（例如刚并入的外部项目）。"""
    lang = args.lang.lower()
    proj = ROOT / lang / args.dir
    if not proj.is_dir():
        sys.exit(f"目录不存在: {proj.relative_to(ROOT)}")
    _add_entry(args, lang, args.dir)
    cmd_index(args)
    print(f"已登记 {lang}/{args.dir}/")


def cmd_remove(args):
    """从 db.json 移除项目条目并刷新索引；--rmdir 时同时删除目录。"""
    lang = args.lang.lower()
    db = load_db()
    entry = find_project(db, lang, args.dir)
    if not entry:
        sys.exit(f"未登记: {lang}/{args.dir}")
    db["projects"].remove(entry)
    save_db(db)
    proj = ROOT / lang / args.dir
    removed_dir = False
    if args.rmdir and proj.is_dir():
        import shutil

        shutil.rmtree(proj)
        removed_dir = True
    cmd_index(args)
    if removed_dir:
        print(f"已删除目录 {lang}/{args.dir}/")
    elif proj.is_dir():
        print(f"条目已移除；目录仍在: {lang}/{args.dir}/（加 --rmdir 一并删除）")


def cmd_list(_args):
    db = load_db()
    for p in db["projects"]:
        desc = p.get("description", "")
        print(f"{p['lang']}/{p['dir']}" + (f" — {desc}" if desc else ""))
    if not db["projects"]:
        print("暂无项目")
    for s in unregistered_dirs(db):
        print(f"未登记: {s}（可用 register 登记）")


def main():
    p = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter
    )
    sub = p.add_subparsers(dest="cmd", required=True)

    p_new = sub.add_parser("new", help="创建项目并刷新索引")
    p_new.add_argument("lang", help="语言命名空间，如 dart / python / go / rust / ts")
    p_new.add_argument("name", help="项目显示名")
    p_new.add_argument("--desc", help="一句话说明，进索引")
    p_new.add_argument("--dir", help="目录名（默认取 name 小写）")
    p_new.set_defaults(fn=cmd_new)

    p_reg = sub.add_parser("register", help="把已存在的 <lang>/<dir> 登记为项目")
    p_reg.add_argument("lang")
    p_reg.add_argument("dir", help="已存在的目录名")
    p_reg.add_argument("--name", help="项目显示名（默认取目录名）")
    p_reg.add_argument("--desc", help="一句话说明，进索引")
    p_reg.set_defaults(fn=cmd_register)

    p_rm = sub.add_parser("remove", help="移除项目条目（--rmdir 同时删目录）")
    p_rm.add_argument("lang")
    p_rm.add_argument("dir")
    p_rm.add_argument("--rmdir", action="store_true", help="同时删除项目目录")
    p_rm.set_defaults(fn=cmd_remove)

    sub.add_parser("list", help="列出全部项目与未登记目录").set_defaults(fn=cmd_list)
    sub.add_parser("index", help="只重建 README 索引").set_defaults(fn=cmd_index)

    args = p.parse_args()
    args.fn(args)


if __name__ == "__main__":
    main()
