# 免注册公开部署：V0.3

当前修订为 0.3.1。此前发布的 0.3.0 已在公网完成一次真实 gpt-5.6-sol 调用；本次修订的离线验证和线上验证范围见 VALIDATION.md。

## 1. 先配置服务器

在独立 Supabase 项目 SQL Editor 执行 `deploy/supabase.sql`。它创建两张表与四个 RPC，启用 RLS，不给 anon/authenticated 角色访问权。浏览器不直接访问数据表。

在本地 `.Renviron` 或云端环境变量中设置：

| 变量 | 设置 |
| --- | --- |
| `WWC_APP_MODE` | `public` |
| `OPENAI_API_KEY` | 专用于这个产品的 API key |
| `WWC_AI_MODEL` | 你的 API 账号可用且支持 Responses API 结构化输出的模型 ID |
| `WWC_STORAGE_BACKEND` | `supabase` |
| `SUPABASE_URL` | 项目的 HTTPS URL，不含 `/rest/v1` |
| `SUPABASE_SECRET_KEY` | 新版 `sb_secret_...` 服务端密钥；不是 anon/publishable key |

在 Supabase 的 Settings → API Keys 中取得服务端密钥，在 Connect 对话框取得 Project URL。当前包兼容新版密钥及旧版 JWT：若使用旧版 `service_role`，改填 `SUPABASE_SERVICE_ROLE_KEY`；两者同时配置时优先使用 `SUPABASE_SECRET_KEY`。新版密钥通过 `apikey` 请求头发送，不当作 JWT。Supabase 当前推荐新版密钥。[Supabase API keys](https://supabase.com/docs/guides/getting-started/api-keys)

复制 `.Renviron.example` 可得到其余默认配置。不要将真实密钥放进 `www/`、代码、Git 或 ZIP。模型名称没有默认值，避免使用账号无法访问的型号。每会话默认最多 15 次 AI 请求，全项目每天默认 150 次；失败调用也占用额度。公开访问可能被反复建立新会话，因此全局额度由 Supabase 原子更新，各实例共享。该额度不是精确金额上限。

执行：

```r
source("scripts/preflight.R")
source("scripts/live_smoke.R")
```

preflight 仅显示配置是否存在及存储探测结果，不输出密钥。live_smoke 会创建和删除本脚本生成的测试事件，核对幂等写入，并发送一次真实模型请求；会消耗少量 API 用量。没有配置时立即停止，不返回模拟通过。

### 从 0.3.0 更新到 0.3.1

更新 GitHub 代码后，在 Connect Cloud 重新部署。若云端已经显式设置 `WWC_AI_MAX_OUTPUT_TOKENS=1800`，代码更新不会覆盖该值；建议将它改为 `4000` 再测试相同问题。0.3.1 的默认值为 4000，允许范围仍为 500–4000。该上限包含推理与答案输出，提高上限不代表每次必然用满，但可能增加实际用量。

| 新增配置 | 默认值 | 用法 |
| --- | --- | --- |
| `WWC_AI_REASONING_EFFORT` | 空白，使用模型默认值 | 可选 none / low / medium / high / xhigh / max；必须受所选模型支持。gpt-5.6-sol 默认为 medium，可单独比较 low 的延迟和回答质量。 |
| `WWC_AI_TIMEOUT_SECONDS` | 60 | 每次 HTTP 请求等待秒数，允许 15–180。先保持默认，不把所有失败都当作超时。 |

新增变量只有部署 0.3.1 后才会生效。模型与引用规则保持不变，没有自动重试或自动切换模型。环境变量修改后需重启或重新部署应用。成功答案和已同意记录的错误事件包含 request_settings，便于比较参数；空白 reasoning_effort 表示模型默认值。

失败时界面提供可报告的 Reference，Posit Logs 中有对应 `[wwc-ai]` 分类。日志只写入分类、HTTP 状态和已知错误码，不写原始服务商错误消息、密钥、用户问题或会话身份。

| Reference | 如何处理 |
| --- | --- |
| AI-OUTPUT-LIMIT | API 明确返回输出额度耗尽；核对云端预算值，缩小请求或调节受支持的推理强度。不会展示不完整答案。 |
| AI-TIMEOUT / AI-NETWORK | 分别检查等待时间或服务连通性。 |
| AI-AUTHENTICATION / AI-MODEL-ACCESS | 分别检查产品 API key，或账号是否有权调用配置的模型。不要在聊天中发送密钥。 |
| AI-BILLING / AI-RATE-LIMIT | 分别检查 API 项目额度，或等待请求速率恢复。 |
| AI-REQUEST-CONFIG | 检查参数和结构化输出配置；Logs 可能包含 unsupported_parameter 等安全错误码。 |
| AI-UPSTREAM / AI-INCOMPLETE / AI-INVALID-RESPONSE / AI-INTERNAL | 分别为服务商错误、其他未完成、不可解析响应或应用内部错误。报告 Reference 及发生时间。 |

官方依据：[GPT-5.6 Sol](https://developers.openai.com/api/docs/models/gpt-5.6-sol)、[Responses 输出预算](https://developers.openai.com/api/reference/cli/resources/responses/methods/create)。

## 2. 从 Posit Cloud 开发，向 Connect Cloud 发布

Posit Cloud 中可上传本包、解压为独立项目，运行 `source("install.R")` 后开发预览。公开托管使用 **Posit Connect Cloud**。官方 GitHub 发布流程使用 `manifest.json` 指定 R 版本、依赖和入口。[Shiny 发布指南](https://docs.posit.co/connect-cloud/how-to/r/shiny-r.html)

1. 将本包放入独立代码仓库，保持 `app.R` 在应用目录根部。仓库不包含真实 `.Renviron`、`private/` 和本地 `.r-library/`。
2. 修改应用或依赖后，从应用根目录运行 `source("scripts/build_manifest.R")`。当前包已附生成的 manifest。
3. 在 Connect Cloud 选择 Publish → Shiny，选仓库、分支及 `app.R`；展开 Advanced settings，用 + Add variable 逐项填写上表变量，再发布。后续可在该应用 Settings → Variables 中修改。变量由平台加密保存，不作为 Git 文件上传。[变量设置](https://docs.posit.co/connect-cloud/user/publish/02-advanced.html)
4. 在分享设置中开启 Public Access，教师可通过网址直接访问。是否显示开关取决于套餐。[公开访问说明](https://docs.posit.co/connect-cloud/user/share/)
5. 用新的浏览器会话完成下面的验收，确认云端服务和持久化后再把网址用于实际招募。

## 3. 上线验收

在未同意记录时搜索 reading、fractions、behavior、college advising；打开行动和 PDF，确认未写入互动事件。发送真实 AI 问题及追问，核对来源页是否支持回答、年级与证据等级是否准确。要求库外结论时检查系统是否承认不足。

在测试会话同意记录后，再提问、查看来源、保存计划。核对 Supabase 中的 session_id、事件顺序、内容版本及同意版本。重复写入不能产生重复 event_id；停止后不再新增，删除只影响当前会话。重新打开应用应产生新会话，并保留先前已同意记录的数据，除非此前选择删除。

核查页面没有 API key，手机布局可用，无登录要求；查看 Posit 构建日志中是否有依赖或外部服务错误。本地测试和模拟 API 测试不能替代这些线上检查。

## 4. 独立域名

先取得平台网址，再绑定你拥有的域名。Connect Cloud 当前的自定义域名功能适用于 Enhanced、Advanced、Enterprise；在后台 Domains 添加域名，按平台返回的 DNS 值配置并验证，随后在该应用 URL 设置中分配。当前没有购买域名或修改 DNS。[域名官方说明](https://docs.posit.co/connect-cloud/user/share/custom-domains.html)

## 5. 研究设置与分析

默认 `WWC_RESEARCH_ENABLED=false`，使用产品反馈说明。正式研究时配置最终同意文本 `WWC_CONSENT_TEXT`、版本 `WWC_CONSENT_VERSION`，再启用研究模式，界面显示 Study code。不提供账号认证，研究编号是否唯一以及与参与者的对应关系需由研究流程管理。

从 Supabase 的 `wwc_events` 导出数据；`deploy/analysis-queries.sql` 提供读取查询。分析时区分 product_feedback、study 和 system_test，保留版本字段。不会把发布平台自身的访问统计当作本应用已获同意的研究数据。

## 6. 后续更新

内容修订保留稳定 action/source IDs，更新语料和内容版本；更新代码后重新生成 manifest、运行两组测试，再重新发布。Shiny 界面、检索、AI 与记录已分模块，未来可将前端改为 Vercel 应用并继续使用 Supabase；届时仍需实现新服务端，不能只更改部署地址。
