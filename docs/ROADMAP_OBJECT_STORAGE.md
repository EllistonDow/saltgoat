# 对象存储与备份一体化（草案）

目标：为 SaltGoat 集成自托管 MinIO（或兼容 S3 的对象存储）组件，统一备份、监控、自愈与通知能力。

### 规划要点

1. **部署与配置**
   - 提供 `salt/states/optional/minio/*.sls`：创建 systemd service、用户、数据目录、TLS/凭据引导。
   - 扩展 `salt/pillar/minio.sls`，支持集群/单节点、凭据、SSE 配置。
   - 在 `scripts/` 下补充 `saltgoat minio install|status|backup` 辅助脚本。

2. **备份整合**
   - 在现有 `modules/lib/backup_notify.py` 中增加对象存储目标的事件标识，并可复用通知队列。
   - 让 `modules/magetools/backup-restic.sh` 支持将 Restic repository 指向 MinIO（s3 backend），并主动写 `runtime` JSON。
   - 补充自动化测试：模拟 MinIO endpoint（例如 `minio server --address` 本地运行）验证备份成功。

3. **监控与自愈**
   - `modules/monitoring/resource_alert.py` 新增 MinIO 健康检测：磁盘容量、后台进程状态、Bucket 可写。
   - `saltgoat monitor auto-sites` 扩展 Pillar 生成 `minio` Beacon，以 Beacon/Event 形式向 Telegram/webhook 报警。
   - 自愈策略：服务崩溃自动重启、磁盘阈值触发通知+扩容提示。

4. **文档 & CLI**
   - 在 `docs/OPS_TOOLING.md` 增加 “对象存储” 专章，列出安装、升级、备份验证、灾备恢复操作。
   - `saltgoat doctor`/`goat_pulse` 添加 MinIO 状态摘要。

5. **后续扩展**
   - 统一 `saltgoat magetools backup` 中的目标类型（filesystem / MinIO / S3）。
   - 评估将静态资源同步至对象存储（前端构建 artifact、媒体库）并自动刷新 CDN。

> 提示：当前阶段仅完成规划，后续迭代时可逐项落地并伴随单元/集成测试。
