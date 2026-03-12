#!/bin/bash
# uninstall.sh - 卸载 OpenClaw Guard（不删除备份数据）

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${YELLOW}==========================================${NC}"
echo -e "${YELLOW}  OpenClaw Guard - 卸载${NC}"
echo -e "${YELLOW}==========================================${NC}"
echo ""

# 停止并禁用服务
echo "停止服务..."
systemctl stop openclaw-guard.service 2>/dev/null || true
systemctl stop openclaw-guard-check.timer 2>/dev/null || true
systemctl stop openclaw-guard-snapshot.timer 2>/dev/null || true
systemctl stop openclaw-guard-docker-watcher.service 2>/dev/null || true
systemctl disable openclaw-guard.service 2>/dev/null || true
systemctl disable openclaw-guard-check.timer 2>/dev/null || true
systemctl disable openclaw-guard-snapshot.timer 2>/dev/null || true
systemctl disable openclaw-guard-docker-watcher.service 2>/dev/null || true

# 删除 systemd 文件
rm -f /etc/systemd/system/openclaw-guard.service
rm -f /etc/systemd/system/openclaw-guard-check.service
rm -f /etc/systemd/system/openclaw-guard-check.timer
rm -f /etc/systemd/system/openclaw-guard-snapshot.service
rm -f /etc/systemd/system/openclaw-guard-snapshot.timer
rm -f /etc/systemd/system/openclaw-guard-docker-watcher.service
systemctl daemon-reload
echo -e "${GREEN}✓${NC} systemd 服务已移除"

# 删除 cron
rm -f /etc/cron.d/openclaw-guard
echo -e "${GREEN}✓${NC} cron 任务已移除"

# 删除脚本
rm -f /usr/local/bin/openclaw-guard-watch.sh
rm -f /usr/local/bin/openclaw-guard-check.sh
rm -f /usr/local/bin/openclaw-guard-snapshot.sh
rm -f /usr/local/bin/openclaw-guard-rollback.sh
rm -f /usr/local/bin/openclaw-guard-docker-watcher.sh
rm -f /usr/local/bin/alert.py
echo -e "${GREEN}✓${NC} 脚本已移除"

echo ""
echo -e "${GREEN}卸载完成！${NC}"
echo ""
echo -e "${YELLOW}以下数据已保留（需手动删除）：${NC}"
echo "  备份数据:   /opt/openclaw-guard-backups/"
echo "  环境配置:   /etc/openclaw-guard.env"
echo "  项目目录:   /opt/openclaw-guard/"
echo "  Git 历史:   数据目录中的 .git/"
echo ""
echo "如需彻底清理，请手动删除以上目录"
