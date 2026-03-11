# OpenClaw Guard - 开发指南

## 本地开发环境

### 前置要求
- Docker 20.10+
- Docker Compose 2.0+
- Python 3.8+
- Git 2.30+

### 快速开始

```bash
# 克隆仓库
git clone https://github.com/YOUR_USERNAME/openclaw-guard.git
cd openclaw-guard

# 安装 Python 依赖
pip3 install requests

# 运行测试
./tests/test-all.sh
```

## 项目结构

```
openclaw-guard/
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
│   ├── test-all.sh                # 运行所有测试
│   ├── test-guard.sh              # 测试启动守卫
│   ├── test-rollback.sh           # 测试回滚功能
│   ├── test-snapshot.sh           # 测试快照功能
│   └── test-alert.sh              # 测试告警功能
├── docs/
│   ├── ARCHITECTURE.md            # 架构设计
│   ├── DEPLOYMENT.md              # 部署指南
│   ├── CONFIGURATION.md           # 配置参考
│   ├── RECOVERY.md                # 故障恢复
│   └── DEVELOPMENT.md             # 本文件
├── .env.example                   # 环境变量示例
├── .gitignore                     # Git 忽略规则
├── LICENSE                        # MIT 许可证
└── README.md                      # 项目说明
```

## 添加新的告警渠道

在 `scripts/alert.py` 中添加新的发送方法：

```python
def _send_new_channel(self, level, title, message, context, timestamp):
    """发送到新渠道"""
    payload = {
        # 构建消息体
    }
    
    try:
        response = requests.post(
            self.channels['new_channel'],
            json=payload,
            timeout=5
        )
        if response.status_code == 200:
            print(f"✓ Alert sent to NewChannel")
    except Exception as e:
        print(f"✗ NewChannel alert error: {e}")
```

然后在 `__init__` 中添加渠道配置，在 `send` 方法中调用。

## 添加新的配置验证规则

在 `config/mcp-safe-config.py` 的 `_validate_config_logic` 方法中添加：

```python
def _validate_config_logic(self, config):
    # 现有规则...
    
    # 添加新规则
    if 'port' in config:
        if not (1 <= config['port'] <= 65535):
            return {"valid": False, "error": "Port must be between 1 and 65535"}
    
    return {"valid": True}
```

## 代码规范

- Shell 脚本：使用 `shellcheck` 检查
- Python 代码：遵循 PEP 8
- 提交信息：遵循 Conventional Commits
- 文档：使用 Markdown 格式

## 发布流程

1. 更新版本号
2. 更新 CHANGELOG
3. 创建 Git tag
4. 推送到 GitHub
5. 构建并推送 Docker 镜像
