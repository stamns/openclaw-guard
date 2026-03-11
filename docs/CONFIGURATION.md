# OpenClaw Guard - 配置参考

## 环境变量

### 基础配置

| 变量名 | 默认值 | 说明 |
|--------|--------|------|
| `TZ` | `Asia/Shanghai` | 时区 |
| `GUARD_ENABLED` | `true` | 是否启用防护系统 |
| `DEBUG` | `false` | 调试模式 |
| `LOG_LEVEL` | `info` | 日志级别 (debug/info/warning/error) |

### 告警配置

| 变量名 | 默认值 | 说明 |
|--------|--------|------|
| `ALERT_WEBHOOK_FEISHU` | - | 飞书机器人 Webhook URL |
| `ALERT_WEBHOOK_DINGTALK` | - | 钉钉机器人 Webhook URL |
| `ALERT_WEBHOOK_SLACK` | - | Slack Webhook URL |
| `ALERT_LEVEL_THRESHOLD` | `warning` | 告警级别阈值 |

### 备份配置

| 变量名 | 默认值 | 说明 |
|--------|--------|------|
| `BACKUP_RETENTION_HOURS` | `48` | 增量快照保留时间（小时） |
| `BACKUP_RETENTION_DAYS` | `7` | 每日归档保留天数 |
| `BACKUP_RETENTION_MONTHS` | `3` | 每月归档保留月数 |
| `BACKUP_COMPRESS` | `true` | 是否压缩备份 |

### Git 配置

| 变量名 | 默认值 | 说明 |
|--------|--------|------|
| `GIT_AUTO_COMMIT` | `true` | 是否启用 Git 自动提交 |
| `GIT_COMMIT_INTERVAL` | `5` | 自动提交间隔（分钟） |
| `GIT_USER_NAME` | `OpenClaw Guard` | Git 用户名 |
| `GIT_USER_EMAIL` | `guard@openclaw.local` | Git 邮箱 |

### 健康检查配置

| 变量名 | 默认值 | 说明 |
|--------|--------|------|
| `HEALTH_CHECK_INTERVAL` | `30` | 检查间隔（秒） |
| `HEALTH_CHECK_TIMEOUT` | `10` | 超时时间（秒） |
| `HEALTH_CHECK_RETRIES` | `3` | 重试次数 |
| `HEALTH_CHECK_ENDPOINT` | `http://localhost:3000/health` | 健康检查端点 |

### 远程同步配置

| 变量名 | 默认值 | 说明 |
|--------|--------|------|
| `REMOTE_SYNC_ENABLED` | `false` | 是否启用远程同步 |
| `RCLONE_REMOTE` | `s3:openclaw-backups` | Rclone 远程目标 |
| `REMOTE_SYNC_INTERVAL` | `3600` | 同步间隔（秒） |

### Docker 资源限制

| 变量名 | 默认值 | 说明 |
|--------|--------|------|
| `DOCKER_CPU_LIMIT` | `2` | CPU 限制 |
| `DOCKER_MEMORY_LIMIT` | `4G` | 内存限制 |
| `DOCKER_CPU_RESERVATION` | `0.5` | CPU 预留 |
| `DOCKER_MEMORY_RESERVATION` | `512M` | 内存预留 |

## 告警级别说明

| 级别 | 触发场景 | 建议操作 |
|------|---------|---------|
| `debug` | 调试信息 | 无需操作 |
| `info` | 正常操作（如成功恢复） | 了解即可 |
| `warning` | 配置逻辑错误、磁盘空间不足 | 关注并计划处理 |
| `error` | 配置损坏已自动恢复 | 检查崩溃现场 |
| `critical` | 连续重启失败、无法自动恢复 | 立即人工介入 |

## 文件路径说明

| 路径 | 说明 |
|------|------|
| `/home/node/.openclaw/openclaw.json` | 主配置文件 |
| `/home/node/.openclaw/.last-known-good.json` | 上次正常配置备份 |
| `/home/node/.openclaw/auto-backups/` | inotify 自动备份目录 |
| `/home/node/.openclaw/crash-logs/` | 崩溃现场保存目录 |
| `/home/node/.openclaw/.git/` | Git 版本库 |
| `/home/node/openclaw-backups/` | 增量快照目录 |
| `/var/log/inotify-watch.log` | 文件监控日志 |
