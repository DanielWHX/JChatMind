# 修改日志

记录 JChatMind 对使用者有影响的功能新增、调整和修复，最新记录在前。历史条目依据 Git 提交整理；提交日期不等同于线上发布日期。

## 未发布

暂无未发布的功能变更。

## 2026-10-15

### 文档
- 新增修改日志，集中查看每次新增、调整和修复了什么。
- 在 README 添加日志入口，并约定后续功能变更同步维护此文件。

## 2026-09-30

### 新增
- 增加 VPS 主机 Nginx 配置模板和 systemd 服务，支持反向代理及应用开机启动。
- 增加备份脚本，备份 PostgreSQL、上传文档及私密配置，便于恢复和迁移。

### 修复
- 修复聊天历史截断后工具调用与结果不配对的问题，避免多轮对话中模型请求失败；保留数据库中的原聊天记录。
- 修复“最近消息”查询误取最早消息的问题，让模型收到最新问题及上下文。

### 文档
- 补充 VPS 部署、访问、备份恢复、迁移和 HTTPS 待办说明。

提交：[d79c564](https://github.com/DanielWHX/JChatMind/commit/d79c564)、[47f4d1e](https://github.com/DanielWHX/JChatMind/commit/47f4d1e)、[540c69e](https://github.com/DanielWHX/JChatMind/commit/540c69e)。

## 2026-09-28

### 新增
- 增加公开访客 Demo：预设选方案、开始试用、处理咨询三条引导链路，引导用户输入问题并获得实时 AI 回答。
- 展示知识检索和工具返回的证据；增加价格计算工具，支持按人数计算月费。
- 增加访客会话隔离、有效期、轮次与并发限制，分离访客接口和管理接口。
- 增加 OrbitDesk 示例知识库、初始化数据脚本，以及演示与录制指南。
- 增加 Docker Compose 云端部署配置，组合 React/Nginx、Spring Boot、PostgreSQL/pgvector 与 Ollama，使用持久卷和独立私密配置。
- 增加本地启动、停止及云端初始化、构建启动、数据导入、验证脚本。

### 文档
- 记录当时的 VPS 连接检查与部署状态；历史连接问题不代表当前服务状态。

提交：[a83455c](https://github.com/DanielWHX/JChatMind/commit/a83455c)、[0951570](https://github.com/DanielWHX/JChatMind/commit/0951570)。

## 维护约定

- 每次新增、调整或修复功能，在同一 PR / commit 中更新本文件；只涉及文档时归入“文档”。
- 开发中的改动先写入“未发布”，发布时移入实际日期或版本号下面。
- 按“新增 / 调整 / 修复 / 文档”分类，每条说明用户可感知的变化，不直接粘贴全部 Git log。
- 只记录已实现的内容，不把计划写成已完成；同一天多次改动合并到对应日期下。
- 不记录密码、API key、私密配置内容或用户对话数据。

更早版本可查看 [完整提交历史](https://github.com/DanielWHX/JChatMind/commits/main/)。
