#!/usr/bin/env python3
"""mono 仓库项目管理器 —— 项目与首页索引的唯一权威入口。

用法:
    python3 tools/mono.py new <lang> <name> [--desc "一句话说明"] [--dir <dirname>]
    python3 tools/mono.py list
    python3 tools/mono.py index

约定:
    - 项目位于 <lang>/<project>/ 两级目录;lang 为小写语言名
      (dart / python / go / rust / ts / shell ...)。
    - 每个项目目录必须含 mono.json(由 `new` 生成),它是"这是一个项目"的标记。
    - README.md 首页中 <!-- MONO:INDEX --> 之间的内容只由本脚本重写。
    - tools/ docs/ 与隐藏目录不参与索引;语言目录只在该目录下
      至少有一个含 mono.json 的项目时才出现在索引里。
"""
import argparse
import json
import re
import sys
from datetime import date
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
README = ROOT / "README.md"
BEGIN = "<!-- MONO:INDEX:BEGIN -->"
END = "<!-- MONO:INDEX:END -->"

# 非语言命名空间的顶层目录
RESERVED = {"tools", "docs", "scripts", ".github", "grap_page"}

NAME_RE = re.compile(r"^[a-z0-9][a-z0-9._-]*$", re.IGNORECASE)


def iter_projects():
    """yield (lang, dir, meta) for every dir containing mono.json."""
    for lang_dir in sorted(ROOT.iterdir()):
        if not lang_dir.is_dir() or lang_dir.name.startswith("."):
            continue
        if lang_dir.name in RESERVED:
            continue
        for proj_dir in sorted(lang_dir.iterdir()):
            meta_file = proj_dir / "mono.json"
            if proj_dir.is_dir() and meta_file.is_file():
                yield lang_dir.name, proj_dir, json.loads(
                    meta_file.read_text(encoding="utf-8")
                )


def render_index():
    lines = ["*本节由 `python3 tools/mono.py index` 生成，请勿手改。*", ""]
    by_lang: dict[str, list] = {}
    for lang, proj_dir, meta in iter_projects():
        by_lang.setdefault(lang, []).append((proj_dir, meta))
    if not by_lang:
        lines.append("*暂无项目。*")
    for lang, items in by_lang.items():
        lines.append(f"### {lang}")
        for proj_dir, meta in items:
            name = meta.get("name", proj_dir.name)
            desc = meta.get("description", "").strip()
            created = meta.get("created", "")
            suffix = " · ".join(x for x in (desc, created) if x)
            link = f"[{name}]({lang}/{proj_dir.name}/)"
            lines.append(f"- {link}" + (f" — {suffix}" if suffix else ""))
        lines.append("")
    return "\n".join(lines).rstrip() + "\n"


def cmd_index(_args):
    text = README.read_text(encoding="utf-8") if README.exists() else "# mono\n\n"
    block = f"{BEGIN}\n{render_index()}{END}"
    if BEGIN in text and END in text:
        head, rest = text.split(BEGIN, 1)
        _, tail = rest.split(END, 1)
        new_text = head + block + tail
    else:
        new_text = text.rstrip() + "\n\n" + block + "\n"
    README.write_text(new_text, encoding="utf-8")
    print(f"索引已更新 → {README.relative_to(ROOT)}")


def cmd_new(args):
    lang = args.lang.lower()
    name = args.name
    dirname = args.dir or name.lower()
    if not NAME_RE.match(lang) or lang in RESERVED:
        sys.exit(f"非法语言名: {lang!r}（需小写字母/数字/连字符，且非保留目录）")
    if not NAME_RE.match(dirname):
        sys.exit(f"非法目录名: {dirname!r}")
    proj = ROOT / lang / dirname
    if proj.exists():
        sys.exit(f"已存在: {proj.relative_to(ROOT)}")
    proj.mkdir(parents=True)
    (proj / "mono.json").write_text(
        json.dumps(
            {
                "name": name,
                "lang": lang,
                "description": args.desc or "",
                "created": date.today().isoformat(),
            },
            ensure_ascii=False,
            indent=2,
        )
        + "\n",
        encoding="utf-8",
    )
    (proj / "README.md").write_text(
        f"# {name}\n\n{args.desc or '待补充。'}\n", encoding="utf-8"
    )
    cmd_index(args)
    print(f"已创建 {lang}/{dirname}/")


def cmd_list(_args):
    found = False
    for lang, proj_dir, meta in iter_projects():
        found = True
        desc = meta.get("description", "")
        print(f"{lang}/{proj_dir.name}" + (f" — {desc}" if desc else ""))
    if not found:
        print("暂无项目")


def main():
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = p.add_subparsers(dest="cmd", required=True)

    p_new = sub.add_parser("new", help="创建项目并刷新索引")
    p_new.add_argument("lang", help="语言命名空间，如 dart / python / go / rust / ts")
    p_new.add_argument("name", help="项目显示名")
    p_new.add_argument("--desc", help="一句话说明，进索引")
    p_new.add_argument("--dir", help="目录名（默认取 name 小写）")
    p_new.set_defaults(fn=cmd_new)

    sub.add_parser("list", help="列出全部项目").set_defaults(fn=cmd_list)
    sub.add_parser("index", help="只重建 README 索引").set_defaults(fn=cmd_index)

    args = p.parse_args()
    args.fn(args)


if __name__ == "__main__":
    main()
