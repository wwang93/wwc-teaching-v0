# AskAboutEdu WWC V0.3

独立运行、无需注册的 Shiny 产品：从教学问题找到 WWC 实践建议，查看原文，进行有来源约束的 AI 对话，再写下自己的行动与判断。

## 当前交付

- 30 份完整 Practice Guides，151 条建议、14 个分项、600 个实施组件；3 份概览作为补充阅读。33 份原始 PDF 随包提供。
- 跨读写、数学、行为、学校改进与高等教育检索；可按年级、角色和领域筛选，也可展开全部指南。
- 每条行动连接来源页、原始证据等级及 PDF。现有人工核对合集中的 action drafts 已作为当前产品内容接入；内部仍保留实际审核状态和内容版本，不把尚未进行的人工审核标记为完成。
- AI 支持问题检索、多轮解释、情境调整和可编辑计划；回答区分 From the guide 与 Suggested adaptation。服务端核查来源 ID 和引文是否存在，拒绝不存在的来源、伪造引文和模型生成的网址。
- 教师可以 Try / Adapt / Set aside，写下行动和理由，保存到当前工作区并下载 TXT。
- 交互记录默认关闭；同意后才保存后续事件，支持停止记录、重试、下载与删除当前会话的数据。无账号、无跨设备身份。

**当前修订为 0.3.1：增加分类错误诊断、可配置推理强度及超时，默认输出预算提高到 4000。** 此前公网 0.3.0 已成功完成一次 gpt-5.6-sol 教学调整请求；这不代表长期可靠性或研究数据持久化已经完成验收。具体测试边界见 [VALIDATION.md](VALIDATION.md)，更新已有部署见 [DEPLOYMENT.md](DEPLOYMENT.md)。

## 本地 / Posit Cloud 开发

将本目录作为 RStudio 项目根目录，在 Console 运行：

```r
source("install.R")   # 首次运行安装依赖
shiny::runApp()
```

无需 API 即可浏览所有内容和编辑计划。可将 `.Renviron.example` 复制为本地 `.Renviron`，私下填写模型配置，再重启应用。实际 `.Renviron` 不进入 Git 或部署包。

公开运行的步骤在 [DEPLOYMENT.md](DEPLOYMENT.md)。本地 SQLite 仅用于开发；公开模式要求 Supabase，避免把需要保留的交互记录放在应用实例本地。

## 验证

在本目录分别启动独立 R 进程：

```sh
Rscript tests/check_v03.R
Rscript tests/check_async.R
Rscript tests/check_ai_errors.R
Rscript scripts/preflight.R
```

第一组覆盖全量内容渲染、检索、来源校验、计划、会话隔离和本地存储；第二组以测试 HTTP 响应覆盖实际异步调用、解析和显示流程，包含多轮上下文、错误引用、同意时点和清空对话时的竞争情况。第二组不是模型质量测试。完整边界见 [VALIDATION.md](VALIDATION.md)。

## 产品与论文

WWC 已承担证据组织与传播功能。本版在其基础上支持“我的问题 → 建议和原文 → 情境调整 → 我的行动及理由”，研究重点可以落在教师如何解释证据、判断适用性和作出决定。没有加入空的 Intervention Reports 或 ERIC 搜索入口。

当前是可用性与需求探索版本。正式研究可配置研究说明、同意版本和研究编号；后续 DBR 可继续使用同一事件契约。是否需要登录取决于跨次追踪需求，V0 的免注册会话不能自动识别同一个人。

## 文件

- `app.R`：入口；`modules/`：界面、检索、AI、存储与会话行为。
- `data/actions.json`：当前行动内容；`data/passages.json`：1,161 个相关原文页面；`data/catalog.json`：来源目录。
- `www/sources/`：原始 PDF；`www/styles.css`、`www/interactions.js`：样式和交互。
- `deploy/supabase.sql`：专用数据表和服务端 RPC；`deploy/analysis-queries.sql`：研究导出示例。
- `manifest.json`：由 Posit 官方 rsconnect 生成的运行时依赖和文件清单。

应用运行只需 R。原项目的 `scripts/build_action_corpus.py` 用于将 30 份核对草稿编译为当前 JSON；重新编译需要原审核资料，部署包不依赖这些生成过程。人工修订时保留 action ID，更新内容版本并重新生成语料，研究数据保留当时版本。
