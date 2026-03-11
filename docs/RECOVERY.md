# OpenClaw Guard - 故障恢复指南

## 快速恢复速查表

| 场景 | 命令 | 预计时间 |
|------|------|---------|
| 配置刚改错 | `openclaw-rollback --immediate` | 1秒 |
| 容器崩溃循环 | 自动恢复，无需操作 | 10-30秒 |
| 回到 2 小时前 | `openclaw-rollback --time 2h` | 10秒 |
| 回到指定快照 | `openclaw-rollback --snapshot 0312-1430` | 10秒 |
| 回到 Git 版本 | `openclaw-rollback --git HEAD~3` | 5秒 |
| 查看历史版本 | `openclaw-rollback --list` | 即时 |
| 服务器彻底丢失 | 从云端下载备份，重新部署 | 5-30分钟 |

## 场景一：AI 改坏了配置

### 症状
- OpenClaw 无法启动
- 容器不断重启
- Web UI 无法访问

### 自动恢复
如果已部署 OpenClaw Guard，系统会自动：
1. 检测到配置损坏
2. 保留崩溃现场
3. 恢复到 last-known-good
4. 发送告警通知

### 手动恢复
```bash
# 进入容器
docker exec -it openclaw-guarded bash

# 方式1：回滚到上次正常配置
openclaw-rollback --immediate

# 方式2：查看可用快照并选择
openclaw-rollback --list
openclaw-rollback --snapshot 0312-1430

# 方式3：使用 Git 回滚
cd /home/node/.openclaw
git log --oneline -10
git checkout <commit-hash> -- openclaw.json

# 重启容器
exit
docker-compose restart openclaw
```

### 排查原因
```bash
# 查看崩溃现场
ls -la /home/node/.openclaw/crash-logs/

# 对比差异
diff /home/node/.openclaw/crash-logs/openclaw.json.crash-0312-1430 \
     /home/node/.openclaw/.last-known-good.json

# 查看 Git 变更历史
cd /home/node/.openclaw
git log --oneline -20
git diff HEAD~1
```

## 场景二：容器无限重启

### 症状
- `docker-compose ps` 显示容器状态为 `Restarting`
- 日志中反复出现启动失败

### 处理步骤
```bash
# 1. 查看日志
docker-compose logs --tail=50 openclaw

# 2. 如果是配置问题，Guard 会自动处理
# 如果 3 次重启后仍失败，容器会停止

# 3. 手动修复
docker-compose stop openclaw

# 4. 直接修复配置文件
docker run --rm -v openclaw_data:/data alpine sh -c \
    "cp /data/.last-known-good.json /data/openclaw.json"

# 5. 重新启动
docker-compose up -d openclaw
```

## 场景三：磁盘空间不足

### 症状
- 告警通知：磁盘使用率 > 80%
- 备份失败

### 处理步骤
```bash
# 1. 查看磁盘使用
df -h

# 2. 查看备份目录大小
du -sh /home/node/openclaw-backups/
du -sh /home/node/.openclaw/auto-backups/

# 3. 手动清理旧备份
find /home/node/openclaw-backups/ -mtime +7 -delete
find /home/node/.openclaw/auto-backups/ -mtime +2 -delete

# 4. 调整保留策略
# 编辑 .env 文件
BACKUP_RETENTION_HOURS=24  # 减少保留时间
BACKUP_COMPRESS=true       # 启用压缩
```

## 场景四：服务器丢失

### 前提
已配置远程备份同步

### 恢复步骤
```bash
# 1. 准备新服务器
apt-get update && apt-get install -y docker.io docker-compose

# 2. 克隆仓库
git clone https://github.com/YOUR_USERNAME/openclaw-guard.git
cd openclaw-guard

# 3. 从云端下载备份
rclone copy r2:openclaw-backups/latest.tar.gz ./

# 4. 解压到数据目录
mkdir -p data
tar xzf latest.tar.gz -C data/

# 5. 配置环境变量
cp .env.example .env
# 编辑 .env

# 6. 启动
cd docker
docker-compose up -d
```

## 场景五：需要查看某次修改的内容

```bash
# 进入容器
docker exec -it openclaw-guarded bash

# 查看 Git 历史
cd /home/node/.openclaw
git log --oneline -20

# 查看某次提交的详细变更
git show <commit-hash>

# 查看两个版本之间的差异
git diff <commit-1> <commit-2>

# 查看修改日志
cat /home/node/.openclaw/auto-backups/changelog.md
```

## 场景六：告警不工作

```bash
# 1. 测试告警
python3 /usr/local/bin/alert.py info "Test" "Testing alert system"

# 2. 检查环境变量
echo $ALERT_WEBHOOK_FEISHU
echo $ALERT_WEBHOOK_DINGTALK
echo $ALERT_WEBHOOK_SLACK

# 3. 检查网络连通性
curl -v https://open.feishu.cn

# 4. 查看告警日志
docker-compose logs openclaw | grep -i alert
```
