# OrbitDesk：截图与现场 Demo

OrbitDesk 是虚构 SaaS，产品规则是演示数据；模型回答、知识库检索、日期工具和历史保存都真实运行。

## 直接截图

打开 [本次完整会话](http://127.0.0.1:5174/chat/5c82f33b-a733-4e6f-8002-fa5c5079a5ba)。从第一条问题往下，分五段截图，不要把整段长聊天缩小成一张图。

- 浏览器窗口放大，缩放保持 100%；字太小时调到 110% 或 125%。
- 每张保留“用户问题 + 最终回答”，尽量让关键数字完整可见。
- 点击绿色 `KnowledgeTool` 或 `getDate` 左侧箭头，可展开真实工具返回；证据单独截一张。
- macOS 按 `Shift + Command + 4` 框选网页内容；不要把旧截图反复压缩放大。
- 历史默认可能停在底部，鼠标放在聊天正文区域往上滚动即可找到第一问。

| 顺序 | 要截的重点 | 预期事实 |
| --- | --- | --- |
| 01 推荐套餐 | 用户的 8 人需求、Team 推荐、价格 | CSV exports + Slack alerts；8 × $18 = $144/月 |
| 02 连续追问 | 从 8 人扩到 12 人后的回答 | 12 × $18 = $216/月；增加 $72 |
| 03 调用工具 | 展开的 getDate、14 天规则、到期日 | 工具日期 + 14 天；当天重跑会变化 |
| 04 未知信息 | SAML SSO 回答 | 手册未说明，需向产品团队确认；不是“确定不支持” |
| 05 回复草稿 | 汇总后的客户回复 | 12 人月费、到期日、SSO 待确认；未发送 |

知识库原文见 [orbitdesk-handbook.md](./orbitdesk-handbook.md)。第一节对应套餐和价格，第二节对应试用规则，第四节对应 SSO 和仅生成草稿的范围。

## 现场演示：同一会话依次问五次

打开 [已准备好的空白 Demo 会话](http://127.0.0.1:5174/chat/8f1b1bbd-761d-4357-9f11-19990310c4b2)，已绑定 `OrbitDesk Support Copilot`。逐条发送下列问题；等待回答完成，再发送下一条。不要每问一次就新建聊天，否则不能展示上下文。

### 1. 查资料并推荐套餐

```text
We are an 8-person team and need CSV exports and Slack alerts. Search the handbook, recommend a plan, and calculate our monthly cost.
```

讲解：“客户提出业务需求，助手查产品手册，推荐 Team，并计算八人的费用。”

### 2. 修改人数

```text
The same team grows to 12 people next month. What would the new monthly cost be?
```

讲解：“不用重复产品和套餐，它沿用前面的上下文重新计算。”

### 3. 使用日期工具

```text
If we start a free trial today, on what date does it expire? Use the date tool and the handbook. Show dates as YYYY-MM-DD.
```

讲解：“日期来自工具，14 天来自知识库，助手把两者结合起来。”

### 4. 检查知识边界

```text
Does OrbitDesk support SAML SSO? Check the handbook before answering.
```

讲解：“资料没有明确说明时，回答应保留不确定性，并建议确认。”

### 5. 生成客服回复

```text
Draft a short customer reply summarizing the Team plan price for our 12-person team, the trial expiry date, and what still needs confirmation about SAML SSO. Do not send it.
```

讲解：“最后把前面的信息整理成客服回复草稿，没有发送邮件。”

结尾刷新页面，展示聊天与工具结果仍在，说明会话已保存。

## 本次复现说明（2026-09-27）

- 五个业务步骤已真实运行，结果保存在完整会话中；原来的历史会话未删除。
- 日期工具返回 `2026-09-27`，按手册的 14 天规则得到 `2026-10-11`。这次日期步骤复用了前面检索过的手册内容，没有再次调用 KnowledgeTool。
- 第二步总价 $216 正确，但原回答将旧价 $144 混入了新价格算式。保留原回答，并在五步之后追加了真实的简短价格校对请求；价格截图可使用末尾的校对结果，展示时说明它是一次追问。
- 回答措辞和工具调用顺序可能变化。演示的是实际结果，不是固定播放稿。

## 服务启动

```bash
cd '/Users/wanghongxiang/Documents/管家 2/jchatmind-local'
bash scripts/start-local.sh
```

本地地址：<http://127.0.0.1:5174>。本地服务运行期间可使用；该地址不代表公网 Demo。
