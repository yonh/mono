# AGENTS.md

mono 是多语言个人项目仓库：一个仓库装所有语言的项目。

## 目录约定

- 项目一律放在 `<lang>/<project>/` 两级目录，`lang` 为小写语言名
  （`dart`、`python`、`go`、`rust`、`ts`、`shell` …）。
- `db.json` 是唯一的项目注册表（数据库式单一数据源）："该目录是项目"
  的唯一标记就是 `db.json` 里有它的条目。不要手改 db.json，走命令。
- `tools/`、`docs/`、`scripts/`、隐藏目录不进索引，不是语言命名空间。
- 项目可以带着自己的历史纳入：先用 `git merge --allow-unrelated-histories`
  并入，再用 `register` 登记（见 `ts/grap_page` 先例）。

## 项目创建与索引：只用脚本，不手改

首页 `README.md` 的索引区（`<!-- MONO:INDEX -->` 之间）由程序维护。
**不要**手工建项目目录、手改索引区或在 README 里补行 —— 一律走命令：

```bash
python3 tools/mono.py new <lang> <name> --desc "一句话说明"  # 建项目骨架 + 刷新索引
python3 tools/mono.py list                                   # 查看现有项目
python3 tools/mono.py index                                  # 仅重建索引
```

`new` 会生成 `<lang>/<name>/` 和项目 README，并把项目写进 `db.json` 与首页索引；
之后在该项目内正常开发即可。

```bash
python3 tools/mono.py register <lang> <dir> --desc "说明"   # 登记已存在的目录
python3 tools/mono.py remove <lang> <dir> [--rmdir]         # 移除条目（可选连目录一起删）
```

`index` / `list` 会顺带报告"未登记目录"：手动建的二级目录不在 db.json 里时
会被程序发现并提示登记，而不是静默进索引 —— 这正是程序维护的意义。

## 提交

- 提交说明 `<type>: 说明`，type 用 `feat`/`fix`/`docs`/`chore`。
- 脚本本身改动后跑一次 `python3 tools/mono.py index` 验证索引仍正确。
