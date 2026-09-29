# VPS 部署与交接

更新：2026-09-30（Asia/Shanghai）

## 访问

- 公网体验：http://204.152.213.21/demo
- 完整原版管理界面：先建立下方 SSH tunnel，再打开 http://127.0.0.1:18082。
- 管理登录信息仅存于服务器 `.local/cloud/admin-login.env`；本机副本 `.local/vps-deployment/admin-login.env`，权限 600，不提交 Git。
- 当前公网为 HTTP，仅开放隔离的访客 Demo。完整管理功能已部署，通过加密 SSH tunnel 使用，避免 Basic Auth 凭据经过公网明文 HTTP。
- HTTPS 和 Portfolio 内嵌接入尚未配置；需要用户提供域名并设置 DNS。不要将 HTTP Demo 嵌入 HTTPS Portfolio。

## 架构

浏览器 → 现有主机 Nginx → 127.0.0.1:8082 → Compose web（React/Nginx）→ api（原 Spring Boot）→ PostgreSQL/pgvector。

知识库 embedding 使用本机 Ollama/bge-m3；对话使用现有 DeepSeek API 配置。没有重写替代后端。GLM、SMTP 属于可选服务，当前未启用。

- Debian 12，2 vCPU，约 2 GiB RAM；保留原 1 GiB swap，新增独立 2 GiB swap。适合低并发演示。
- Compose 根目录 `/opt/jchatmind`，文件 `compose.cloud.yaml`。
- named volumes：`jchatmind-cloud_cloud-postgres`、`jchatmind-cloud_cloud-documents`、`jchatmind-cloud_cloud-ollama`。
- 数据库、API、Ollama 不发布公网端口。web 仅监听 loopback 8082。
- 密钥保存在 `.local/cloud/secrets.env`（600），未提交 Git。
- Nginx 站点 `/www/server/panel/vhost/nginx/jchatmind-demo.conf`，保留原 BaoTa/Nginx 配置。
- Docker、Nginx、`jchatmind.service` 已设置开机启动；容器 restart policy 为 unless-stopped。

## SSH

原 22 端口在本次测试中直连超时、经现有代理在认证前关闭；无法仅凭此确定运营商根因。用户单独批准临时 2222，只允许出口 `23.172.40.55`。

Mac 连接（沿用现有 Clash，不改变配置）：

```sh
ssh -p 2222 -o 'ProxyCommand=nc -X 5 -x 127.0.0.1:7897 %h %p' root@204.152.213.21
```

加密管理 tunnel：

```sh
ssh -N -p 2222 -L 127.0.0.1:18082:127.0.0.1:8082 \
  -o ServerAliveInterval=20 \
  -o 'ProxyCommand=nc -X 5 -x 127.0.0.1:7897 %h %p' root@204.152.213.21
```

2222 的 sshd 为临时进程，**VPS 重启后不会自行恢复**，原22仍保留。需要时可在已登录 VNC 执行 `sshd -t`，然后 `/usr/sbin/sshd -p2222 -o pidfile=/run/jchatmind-ssh-test.pid`。Clash 出口改变后，旧的源 IP 白名单也不再适用。应用的开机启动不依赖 SSH。

## 运维

在服务器 `/opt/jchatmind` 执行：

```sh
bash scripts/cloud-compose.sh ps
bash scripts/cloud-compose.sh logs --tail 100 api
bash scripts/cloud-verify.sh --admin
# 更新代码及应用；不会删除持久卷
 git pull --ff-only origin main
 bash scripts/cloud-compose.sh build api web
 bash scripts/cloud-compose.sh up -d --wait
```

不要使用 `down -v`，它会删除数据库等持久卷。

## 备份与迁移

`bash scripts/cloud-backup.sh` 会短暂停止 API 写入，生成数据库、上传文档、私密配置、commit 和校验和，再恢复服务。备份**包含密钥**，只能私密保存。

本次备份 `/opt/jchatmind/.local/backups/20260929T193505Z`；本机副本 `.local/vps-deployment/backup-20260929T193505Z`。

迁移到新 VPS：

1. 安装 Docker/Compose，克隆此仓库，切到备份记录的 commit。
2. 在私有目录解包 `private-config.tar.gz`；保持 `.local/cloud` 700、密钥文件600。
3. 启动 postgres；在全新的目标数据库用 `pg_restore --clean --if-exists` 恢复 `database.dump`。不要对已有重要数据库执行覆盖恢复。
4. 创建/挂载文档卷，将 `documents.tar.gz` 解包到卷根目录，保留文件权限。
5. 启动 Ollama，执行 `ollama pull bge-m3`；模型也可通过单独备份模型卷迁移。
6. build/start api、web，再运行 `cloud-verify.sh --admin`。
7. 按新服务器已有端口规划安装 Nginx 和 systemd；更换域名时先 DNS 后申请证书。

## 已验证及限制

- 五轮真实模型链路通过：8人144美元、12人216美元、日期工具+14天、SSO未知边界、未发送的回复草稿。
- Chrome 公网 UI 实际发送提问并显示真实答案、知识检索证据、计算工具。
- 独立访客会话隔离、管理鉴权、原管理 API/SSE 检查通过。
- 备份恢复到临时数据库验证：4条向量、84条聊天记录；原数据库未覆盖。
- 修复两个原代码问题：截断工具调用的孤立结果；“最近消息”SQL误取最早消息。
- 自动启动配置和应用 stop/start 检查；**未重启整台 VPS**。
- 访客限制：每会话8轮、1小时有效、并发2、每日100轮；计数在进程内，API重启会重置。当前无访客自上传功能，上传知识库使用管理界面。
- HTTPS、域名及 Portfolio 的线上 Demo URL 是后续阶段。
