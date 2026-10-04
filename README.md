# mono

多语言个人项目仓库：一个仓库装所有语言的项目。

## 布局

```
<lang>/<project>/   语言命名空间 → 项目（dart / python / go / rust / ts / shell …）
tools/              仓库工具：索引与项目维护脚本
docs/               跨项目文档
scripts/            通用脚本
db.json             项目注册表（数据库式单一数据源）
```

## 项目维护

项目的创建、登记与首页索引一律走 `tools/mono.py`，约定细节见
[AGENTS.md](AGENTS.md)。索引区由程序重写，手改无效。

```bash
python3 tools/mono.py new <lang> <name> --desc "一句话说明"   # 新建项目
python3 tools/mono.py register <lang> <dir> --desc "说明"     # 登记已有目录
python3 tools/mono.py list                                  # 项目 + 未登记目录
python3 tools/mono.py index                                 # 仅重建索引
```

## 项目索引

<!-- MONO:INDEX:BEGIN -->
*本节由 `python3 tools/mono.py index` 生成，请勿手改。*

### dart
| 项目 | 说明 | 创建 |
|---|---|---|
| [pdf_study](dart/pdf_study/) | AI PDF 学习阅读器：批注/笔记 + DeepSeek/Claude/Codex/Devin 问答、讲解与课后复习 | 2026-10-04 |

### ts
| 项目 | 说明 | 创建 |
|---|---|---|
| [grap_page](ts/grap_page/) | 网页原义提取器：WXT 浏览器插件 + 本地后端，网页数据无损提取/传输/存储 | 2026-10-05 |
<!-- MONO:INDEX:END -->
