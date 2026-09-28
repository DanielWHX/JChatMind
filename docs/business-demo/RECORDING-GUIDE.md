# JChatMind：SaaS 客服助手逐段录屏指南

## 这次展示的业务故事

你是 SaaS 产品 OrbitDesk 的客服。客户想知道：8 人团队该买什么套餐、扩到 12 人多少钱、今天开始试用何时到期，以及是否支持 SAML SSO。你把产品手册交给 JChatMind，让助手查资料、算价格、调用日期工具，并写一份客户回复草稿。

OrbitDesk 是虚构产品，规则是演示资料；模型请求、Java 工具调用、向量检索和数据库保存都真实执行。画面开头可放小字：**Fictional SaaS scenario · Live AI and RAG workflow**。

## 先直接用起来

直接进入 [空白录制会话](http://127.0.0.1:5174/chat/fd3a5515-cf38-4dcc-8622-661747e7ba22)，或先看 [已验证的完整演示](http://127.0.0.1:5174/chat/0e9a2ccf-9dc5-4a3d-9af8-9701b2329b22)。已准备好：

- Agent：**OrbitDesk Support Copilot**
- 知识库：**OrbitDesk Product Handbook**
- 产品文档：本目录 `orbitdesk-handbook.md`
- 完整 System Prompt：本目录 `agent-prompt.txt`

左边选择 **聊天记录 → 新聊天**，在主区域顶部的下拉框选择 **OrbitDesk Support Copilot**。输入下文第一条问题，点向上箭头发送。每次等待回答和工具结果完成后再发下一条。

**注意：左侧 Agent 卡片目前不会直接进入聊天，用顶部下拉框选 Agent。** 如果新建内容没有出现，刷新一次。预先创建的空白录制会话可以直接打开，避免录制时首次 SSE 建连时序影响。

服务关闭后，在 Terminal 执行：

```bash
cd '/Users/wanghongxiang/Documents/管家 2/jchatmind-local'
bash scripts/start-local.sh
```

## 镜头安排：逐条录，不用一镜到底

建议录 7 段，剪成约 2–3 分钟。表格时长是最终保留的画面长度；等待模型时可以多录，剪辑时删掉空白等待。每段操作前、结果出来后各停 2–3 秒，方便拼接。不要剪成误导观众的延迟性能对比。

| 镜头 | 最终时长 | 操作与画面重点 | 英文字幕 |
| --- | --- | --- | --- |
| 01 产品介绍与 Agent 配置 | 15–20 秒 | 左栏智能体助手 → OrbitDesk 卡片右侧 ⋯ → 编辑；展示名称、提示词、deepseek-chat、已绑定知识库；关闭弹窗 | Configure a support agent with a role, a language model, and a product knowledge base. |
| 02 知识库 | 15–20 秒 | 左栏知识库 → OrbitDesk Product Handbook → 展示 Markdown 文档列表；需要从零上传的操作见后文 | Product documentation becomes a searchable knowledge base using local embeddings and pgvector. |
| 03 业务问题与 RAG | 25–35 秒 | 输入问题 1；结果出现后展开绿色 KnowledgeTool 结果行；停在 Team / $144 的答案 | Retrieve product rules, recommend a plan, and calculate a customer-specific quote. |
| 04 连续追问 | 15–20 秒 | 同一个会话输入问题 2；停在 12 人 / $216 的答案 | Keep the conversation context when the customer's requirements change. |
| 05 多工具协作 | 25–35 秒 | 输入问题 3；展开 getDate 与 KnowledgeTool 结果，展示日期与试用规则 | Combine a real date tool with retrieved trial rules to calculate an expiry date. |
| 06 未知信息与回复草稿 | 25–35 秒 | 先录问题 4 的“不确定”回答，再录问题 5 的完整回复草稿 | Identify missing policy information and draft a grounded customer reply. |
| 07 历史记录 | 10–15 秒 | 回答完成后刷新页面，点击聊天记录中的本次会话，展示问题、工具结果、回复还在 | Persist conversations and tool results so the workflow can be resumed later. |

镜头 03–06 属于同一段业务会话，要保留上下文。可以分别停止/开始录屏，页面和聊天不用重置。

## 每一段输入什么

### 问题 1：推荐套餐与计算价格

```text
We are an 8-person team and need CSV exports and Slack alerts. Search the handbook, recommend a plan, and calculate our monthly cost.
```

操作：发送 → 等待 → 找到绿色 **KnowledgeTool** 工具结果行 → 点左边的小箭头展开 → 停留在最终回答。

应看到：**Team plan / USD 18 per user per month / 8 × 18 = USD 144 per month**。Starter 最多 5 人且没有所需功能。价格是演示手册中的样例价，不是真实销售报价。

这段证明：模型确实调用知识库，然后把资料用于具体客户问题。

### 问题 2：同一个客户的连续追问

```text
The same team grows to 12 people next month. What would the new monthly cost be?
```

不用重新说明套餐，继续在同一个输入框发送。

应看到：沿用 Team 套餐，**12 × 18 = USD 216 per month**。这是下个月完整月费，不涉及手册未规定的月中折算。

这段证明：会话历史参与后续回答。

### 问题 3：当前日期 + 试用规则

```text
If we start a free trial today, on what date does it expire? Use the date tool and the handbook. Show dates as YYYY-MM-DD.
```

应看到：**getDate** 获取当天日期，**KnowledgeTool** 检索 14 天规则；到期日为工具返回日期 + 14 天。两个工具出现的先后顺序可能不同。

**不要写死录制日期。** 例如 2026-09-21 开始，按样例手册定义应在 2026-10-05 到期。实际录制日变化时，答案日期也应变化。

这段只是算日期，不会创建真实试用账号。

### 问题 4：手册没有答案时怎么处理

```text
Does OrbitDesk support SAML SSO? Check the handbook before answering.
```

应看到：手册没有说明是否支持，应向产品团队确认。**不能把“没写支持”说成“确定不支持”。** 具体措辞可能不同，这一次演示显示的是该问题的实际表现，不保证任何问题都不会产生错误回答。

这段证明：助手可以区分查到的事实和仍需确认的信息。

### 问题 5：把结果整理成客服回复

```text
Draft a short customer reply summarizing the Team plan price for our 12-person team, the trial expiry date, and what still needs confirmation about SAML SSO. Do not send it.
```

应看到：一份客户可读的回复草稿，包含 **USD 216/month**、问题 3 中的到期日，以及 SAML SSO 仍待确认。

画面字幕要用 **Draft a customer reply**，不要写成 **Send an email**：这个演示不会发邮件。

## 如果想亲手录制“从零创建”

已经准备好的 Agent 适合直接拍业务演示。若要展示创建过程，可另建带 `Recording` 后缀的知识库和 Agent，保留现有已验证版本。

1. **知识库 → 新建知识库**。
   - 名称：`OrbitDesk Handbook Recording`
   - 描述：`Fictional SaaS product plans, trials, onboarding, and support policies.`
   - 点 **创建**，然后刷新页面。
2. 点击刚建的库 → **选择文件上传**。
   - 选择本目录的 `orbitdesk-handbook.md`。
   - 等“文档上传成功”，确认文档列表有它。完整 RAG 的证明仍是问题 1 能查到正文并回答正确。
3. **智能体助手 → ＋ 智能体助手 → 基础设置**。
   - 名称：`OrbitDesk Support Recording`
   - 描述：`A support copilot grounded in a fictional SaaS product handbook.`
   - 提示词：复制本目录 `agent-prompt.txt` 全文。
4. **模型设置**：选择 `deepseek-chat`。
5. **知识库设置**：勾选 `OrbitDesk Handbook Recording`，确认选中。
6. **模型设置 → 消息窗口长度**：将滑块设为 `60`，让这段短演示保留足够的工具与消息上下文。
7. **工具调用**：可选项先不选。`KnowledgeTool` 和日期工具已经内置，不需要额外勾选。
8. 点 **保存**，刷新。进入 **聊天记录 → 新聊天**，在顶部选择刚建的 Agent，开始上述问题。

如果首次发送后一直无响应，先停录，检查后端日志；可刷新、进入已有会话再重试。不要反复连点发送。尚未修复的首次 SSE 建连竞争可能影响这一步。

## 怎么录屏

- 浏览器单独打开 JChatMind，关闭无关标签，把窗口放大；建议横屏 16:9，字号保持清楚可读。
- macOS 按 **Shift + Command + 5** → 录制选定区域 → 框住 JChatMind 页面 → 开始录制。无需麦克风。
- 按镜头表分段。录制时不要切去带配置或密钥的 Terminal。
- 保存为 `01-agent-config.mov`、`02-knowledge-base.mov`、`03-rag-pricing.mov`、`04-follow-up.mov`、`05-tools-trial.mov`、`06-customer-draft.mov`、`07-history.mov`。
- 等待回答时让光标停在空白处。工具结果展开后停 2–3 秒，给观众时间阅读。

## 这套演示覆盖什么

覆盖 Agent 配置、知识库管理与 Markdown 导入、真实 RAG、DeepSeek 对话、工具调用、多轮上下文、回复草稿、SSE 消息推送和数据库历史记录。

当前不演示邮件发送、模型生成 SQL、GLM 模型切换、天气/城市查询或 PDF 解析。前两者未在本地启用验证，GLM 尚未配置，天气/城市是固定样例，实际文档索引链路只支持 Markdown。也不把当前消息级 SSE 说成逐 token Streaming，不把 Temperature/Top P 滑杆变化说成已验证生效。

## 本次验证记录

2026-09-21 已用真实 DeepSeek 顺序验证上述 5 个问题，收到 23 条 SSE 事件。验证覆盖价格计算、12 人连续追问、日期 + 知识库、未知功能回应、客户草稿。未发送邮件或修改外部业务账号。
