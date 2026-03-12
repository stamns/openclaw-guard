# OpenClaw Guard

🛡️ 生产级 OpenClaw 防护系统 —— 五层架构确保 AI 配置变更安全可控

[![Docker](https://img.shields.io/badge/Docker-Ready-blue)](https://docker.com)
[![License](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)

## 核心特性

- **五层防护架构**：从强制约束到远程容灾，层层兜底
- **自动崩溃恢复**：配置损坏时 10 秒内自动回滚
- **完整版本历史**：Git 追踪 + 增量快照，精确到任意时间点
- **实时告警通知**：飞书/钉钉/Slack 多渠道告警
- **开箱即用**：Docker Compose 一键部署

## 快速开始

### 方式一：1Panel 用户（推荐）

如果你的 OpenClaw 通过 1Panel 管理，使用宿主机 Sidecar 模式安装，不动 OpenClaw 容器本身：

```bash
# 1. SSH 登录服务器，克隆仓库
cd /opt
git clone https://github.com/stamns/openclaw-guard.git

# 如果 GitHub 访问慢，使用镜像：
# git clone https://ghproxy.com/https://github.com/stamns/openclaw-guard.git

# 2. 使用预填好路径的 1Panel 配置（直接可用）
cp /opt/openclaw-guard/env-1panel.conf /etc/openclaw-guard.env
# 如果路径不同，编辑: nano /etc/openclaw-guard.env

# 3. 如果 apt 报 Google Chrome 源错误：
# mv /etc/apt/sources.list.d/google*.list /tmp/

# 4. 一键安装
bash /opt/openclaw-guard/install-for-1panel.sh

# 5. 验证五层防护
systemctl status openclaw-guard.service          # 服务状态
openclaw-guard-check.sh                          # 健康检查
openclaw-guard-snapshot.sh                       # 手动快照
openclaw-guard-rollback.sh --list                # 查看快照
git -C /opt/1panel/apps/openclaw/openclaw/data/conf log --oneline  # Git 历史
```

卸载：`bash /opt/openclaw-guard/uninstall.sh`

### 方式二：Docker Compose 部署

如果你自己管理 Docker Compose：

```bash
git clone https://github.com/stamns/openclaw-guard.git
cd openclaw-guard
cp .env.example .env
# 编辑 .env，填入告警 webhook 等配置
cd docker && docker-compose up -d
```

### 方式三：裸机部署

详见 [部署指南](docs/DEPLOYMENT.md)

## 架构概览

```
┌─────────────────────────────────────────────────────────────┐
│  第1层：强制约束层  │  MCP 安全工具 + inotify 监控            │
├─────────────────────────────────────────────────────────────┤
│  第2层：启动守卫层  │  entrypoint-guard.sh（崩溃自动恢复）     │
├─────────────────────────────────────────────────────────────┤
│  第3层：版本控制层  │  Git 自动提交 + 增量快照                 │
├─────────────────────────────────────────────────────────────┤
│  第4层：健康检查层  │  Watchdog + 自动重启策略                 │
├─────────────────────────────────────────────────────────────┤
│  第5层：远程容灾层  │  云存储同步 + 多机热备                   │
└─────────────────────────────────────────────────────────────┘
```

## 详细文档

- [架构设计](docs/ARCHITECTURE.md) - 完整五层架构说明
- [部署指南](docs/DEPLOYMENT.md) - 详细部署步骤
- [配置参考](docs/CONFIGURATION.md) - 环境变量与配置项
- [故障恢复](docs/RECOVERY.md) - 各类故障场景恢复指南
- [开发指南](docs/DEVELOPMENT.md) - 本地开发与测试

## 目录结构

```
openclaw-guard/
├── install-for-1panel.sh          # 1Panel 一键安装脚本
├── uninstall.sh                   # 一键卸载脚本
├── docker/
│   ├── Dockerfile                 # 主镜像构建文件
│   └── docker-compose.yml         # 完整编排配置
├── scripts/
│   ├── entrypoint-guard.sh        # 启动守卫脚本
│   ├── inotify-watch.sh           # 文件监控脚本
│   ├── smart-snapshot.sh          # 智能快照脚本
│   ├── openclaw-rollback.sh       # 一键回滚脚本
│   └── alert.py                   # 告警通知脚本
├── config/
│   ├── mcp-safe-config.py         # MCP 安全修改工具
│   └── crontab                    # 定时任务配置
├── tests/
│   └── test-all.sh                # 测试套件
├── docs/                          # 详细文档
├── .env.example                   # 环境变量示例
├── .gitignore                     # Git 忽略规则
├── LICENSE                        # MIT 许可证
└── README.md                      # 本文件
```

## 恢复场景速查

| 场景 | 命令 | 预计时间 |
|------|------|---------|
| 配置刚改错 | `openclaw-guard-rollback.sh --immediate` | 1秒 |
| 容器崩溃循环 | 自动恢复，无需操作 | 10-60秒 |
| 回到指定快照 | `openclaw-guard-rollback.sh --snapshot 0312-1430` | 10秒 |
| 查看历史版本 | `openclaw-guard-rollback.sh --list` | 即时 |
| 对比配置差异 | `openclaw-guard-rollback.sh --diff` | 即时 |
| Git 回滚 | `openclaw-guard-rollback.sh --git <commit>` | 5秒 |
| 服务器彻底丢失 | 从云端下载备份，重新部署 | 5-30分钟 |

## 贡献

欢迎 Issue 和 PR！请阅读 [贡献指南](CONTRIBUTING.md)。

## 许可证

MIT License - 详见 [LICENSE](LICENSE) 文件。
