# OpenClaw Guard - 部署指南

## 前置要求

- Docker 20.10+
- Docker Compose 2.0+
- Git 2.30+
- 至少 2GB 可用磁盘空间

## 方式一：Docker Compose 部署（推荐）

### 1. 克隆仓库

```bash
git clone https://github.com/YOUR_USERNAME/openclaw-guard.git
cd openclaw-guard
```

### 2. 配置环境变量

```bash
cp .env.example .env
```

编辑 `.env` 文件，填入实际配置：

```bash
# 必填：时区
TZ=Asia/Shanghai

# 可选：告警 Webhook（至少配置一个）
ALERT_WEBHOOK_FEISHU=https://open.feishu.cn/open-apis/bot/v2/hook/YOUR_KEY
ALERT_WEBHOOK_DINGTALK=https://oapi.dingtalk.com/robot/send?access_token=YOUR_TOKEN
ALERT_WEBHOOK_SLACK=https://hooks.slack.com/services/YOUR/WEBHOOK/URL
```

### 3. 创建数据目录

```bash
mkdir -p data backups
```

### 4. 启动服务

```bash
cd docker
docker-compose up -d
```

### 5. 验证部署

```bash
# 查看容器状态
docker-compose ps

# 查看日志
docker-compose logs -f openclaw

# 检查健康状态
curl http://localhost:3000/health
```

### 6. 启用远程备份同步（可选）

```bash
# 配置 rclone
rclone config  # 按提示配置 S3/R2/OSS

# 启动备份同步服务
docker-compose --profile remote-sync up -d
```

## 方式二：手动部署（不使用 Docker）

### 1. 安装依赖

```bash
# Ubuntu/Debian
apt-get install -y git inotify-tools rsync cron curl python3 python3-pip jq
pip3 install requests

# CentOS/RHEL
yum install -y git inotify-tools rsync cronie curl python3 python3-pip jq
pip3 install requests
```

### 2. 安装脚本

```bash
git clone https://github.com/YOUR_USERNAME/openclaw-guard.git
cd openclaw-guard

# 复制脚本到系统目录
cp scripts/*.sh /usr/local/bin/
cp scripts/alert.py /usr/local/bin/
cp config/mcp-safe-config.py /usr/local/bin/
chmod +x /usr/local/bin/*.sh
```

### 3. 初始化 Git 版本控制

```bash
cd /home/node/.openclaw
git init
git add .
git commit -m "Initial commit"
```

### 4. 配置 cron 任务

```bash
crontab config/crontab
```

### 5. 启动文件监控

```bash
nohup /usr/local/bin/inotify-watch.sh > /var/log/inotify-watch.log 2>&1 &
```

### 6. 配置 systemd 服务（可选）

```bash
cat > /etc/systemd/system/openclaw-guard.service << 'EOF'
[Unit]
Description=OpenClaw Guard File Monitor
After=network.target

[Service]
Type=simple
ExecStart=/usr/local/bin/inotify-watch.sh
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

systemctl enable openclaw-guard
systemctl start openclaw-guard
```

## 验证部署

### 测试回滚功能

```bash
# 模拟配置损坏
echo "INVALID JSON" > /home/node/.openclaw/openclaw.json

# 重启容器（Docker 方式）
docker-compose restart openclaw

# 查看日志，确认自动恢复
docker-compose logs --tail=20 openclaw
```

### 测试告警功能

```bash
python3 /usr/local/bin/alert.py info "Test Alert" "This is a test alert"
```

### 测试快照功能

```bash
/usr/local/bin/smart-snapshot.sh
ls -la /home/node/openclaw-backups/
```

## 升级

```bash
cd openclaw-guard
git pull origin main
docker-compose build
docker-compose up -d
```

## 卸载

```bash
docker-compose down -v
# 注意：-v 会删除数据卷，请确保已备份重要数据
```
