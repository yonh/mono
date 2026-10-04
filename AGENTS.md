# AGENTS.md

mono 是多语言个人项目仓库：一个仓库装所有语言的项目。

## 目录约定

- 项目一律放在 `<lang>/<project>/` 两级目录，`lang` 为小写语言名
  （`dart`、`python`、`go`、`rust`、`ts`、`shell` …）。
- 每个项目目录必须含 `mono.json`（`name`/`lang`/`description`/`created`）
  和自己的 `README.md`；`mono.json` 是"该目录是项目"的唯一标记。
- `tools/`、`docs/`、`scripts/`、隐藏目录不进索引，不是语言命名空间。
- 项目可以带着自己的历史纳入：先用 `git merge --allow-unrelated-histories`
  并入，再用 `register` 登记索引（见 `ts/grap_page` 先例）。

## 项目创建与索引：只用脚本，不手改

首页 `README.md` 的索引区（`<!-- MONO:INDEX -->` 之间）由程序维护。
**不要**手工建项目目录、手改索引区或在 README 里补行 —— 一律走命令：

```bash
python3 tools/mono.py new <lang> <name> --desc "一句话说明"  # 建项目骨架 + 刷新索引
python3 tools/mono.py list                                   # 查看现有项目
python3 tools/mono.py index                                  # 仅重建索引
```

`new` 会生成 `<lang>/<name>/mono.json` 和项目 README，并把项目写进首页索引；
之后在该项目内正常开发即可。删除项目：删目录后跑一次 `index`。

```bash
python3 tools/mono.py register <lang> <dir> --desc "说明"   # 登记已存在的目录
```

## 提交

- 提交说明 `<type>: 说明`，type 用 `feat`/`fix`/`docs`/`chore`。
- 脚本本身改动后跑一次 `python3 tools/mono.py index` 验证索引仍正确。
