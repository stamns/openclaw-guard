#!/bin/bash
# install-for-1panel.sh - 一键安装 Guard 到 1Panel 环境
# 用法: bash install-for-1panel.sh
# 前提: 已编辑 /etc/openclaw-guard.env 填入正确的 OPENCLAW_DATA_DIR

set -e

# 加载配置
ENV_FILE="/etc/openclaw-guard.env"
if [ ! -f "$ENV_FILE" ]; then
    echo "错误：未找到 $ENV_FILE"
    echo "请先执行: cp /opt/openclaw-guard/.env.example /etc/openclaw-guard.env"
    echo "然后编辑填入 OPENCLAW_DATA_DIR"
    exit 1
fi

source "$ENV_FILE"

DATA_DIR="${OPENCLAW_DATA_DIR:-/opt/1panel/apps/openclaw/openclaw/data/conf}"
WORKSPACE_DIR="${OPENCLAW_WORKSPACE_DIR:-/opt/1panel/apps/openclaw/openclaw/data/workspace}"
BACKUP_DIR="/opt/openclaw-guard-backups"
CONTAINER_NAME=$(docker ps --format '{{.Names}}' | grep -i claw | head -1)

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${GREEN}==========================================${NC}"
echo -e "${GREEN}  OpenClaw Guard - 1Panel 安装向导${NC}"
echo -e "${GREEN}==========================================${NC}"
echo ""

# ============================================
# 前置检查
# ============================================

# 检查数据目录
if [ ! -d "$DATA_DIR" ]; then
    echo -e "${RED}错误：数据目录不存在: $DATA_DIR${NC}"
    echo ""
    echo "请先运行以下命令找到正确路径："
    echo "  docker inspect \$(docker ps --format '{{.Names}}' | grep -i claw) | grep -A5 Mounts"
    echo ""
    echo "然后编辑 /etc/openclaw-guard.env 修改 OPENCLAW_DATA_DIR"
    exit 1
fi

echo -e "配置目录:   ${GREEN}$DATA_DIR${NC}"
echo -e "工作区目录: ${GREEN}$WORKSPACE_DIR${NC}"
echo -e "容器名称:   ${GREEN}${CONTAINER_NAME:-未找到}${NC}"
echo -e "备份目录:   ${GREEN}$BACKUP_DIR${NC}"
echo ""

if [ -z "$CONTAINER_NAME" ]; then
    echo -e "${YELLOW}警告：未找到运行中的 OpenClaw 容器${NC}"
    echo "Guard 仍会安装，容器启动后自动生效"
    echo ""
fi

# 检查依赖
echo "检查依赖..."
MISSING_DEPS=""
for dep in inotifywait git jq python3 rsync; do
    if ! command -v $dep &>/dev/null; then
        MISSING_DEPS="$MISSING_DEPS $dep"
    fi
done

if [ -n "$MISSING_DEPS" ]; then
    echo -e "${YELLOW}安装缺失依赖:${MISSING_DEPS}${NC}"
    apt-get update -qq
    apt-get install -y -qq inotify-tools git jq python3 python3-pip rsync
    pip3 install requests -q
fi
echo -e "${GREEN}✓${NC} 依赖检查完成"

# ============================================
# 初始化
# ============================================

# 创建备份目录
mkdir -p "$BACKUP_DIR"
mkdir -p "$DATA_DIR/auto-backups"
mkdir -p "$DATA_DIR/crash-logs"
echo -e "${GREEN}✓${NC} 目录结构已创建"

# 初始化 Git
if [ ! -d "$DATA_DIR/.git" ]; then
    git -C "$DATA_DIR" init -q
    git -C "$DATA_DIR" config user.email "guard@openclaw.local"
    git -C "$DATA_DIR" config user.name "OpenClaw Guard"
    git -C "$DATA_DIR" add .
    git -C "$DATA_DIR" commit -m "guard: initial snapshot" -q
    echo -e "${GREEN}✓${NC} Git 版本控制已初始化"
else
    echo -e "${GREEN}✓${NC} Git 已存在，跳过"
fi

# 创建 last-known-good 备份
if [ -f "$DATA_DIR/openclaw.json" ]; then
    cp "$DATA_DIR/openclaw.json" "$DATA_DIR/.last-known-good.json"
    echo -e "${GREEN}✓${NC} last-known-good 备份已创建"
fi

# ============================================
# 生成适配脚本
# ============================================

echo ""
echo "生成适配脚本..."

# ---------- 1. 文件监控脚本 ----------
cat > /usr/local/bin/openclaw-guard-watch.sh << 'WATCHEOF'
#!/bin/bash
# openclaw-guard-watch.sh - 实时文件监控
# 适配 1Panel 双目录挂载：conf + workspace

source /etc/openclaw-guard.env
DATA_DIR="${OPENCLAW_DATA_DIR:-/opt/1panel/apps/openclaw/openclaw/data/conf}"
WORKSPACE_DIR="${OPENCLAW_WORKSPACE_DIR:-/opt/1panel/apps/openclaw/openclaw/data/workspace}"
BACKUP_DIR="${DATA_DIR}/auto-backups"
LOG_FILE="${BACKUP_DIR}/watch.log"

mkdir -p "$BACKUP_DIR"

log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

log "OpenClaw Guard 文件监控已启动"
log "监控配置目录: $DATA_DIR"
log "监控工作区:   $WORKSPACE_DIR"

# 同时监控 conf 和 workspace 两个目录
inotifywait -m -r -e modify,move_self,create,delete \
    --exclude '(\.git|auto-backups|crash-logs)' \
    --format '%w%f|%e' \
    "$DATA_DIR" "$WORKSPACE_DIR" 2>/dev/null | while IFS='|' read file event; do

    NANO_TS=$(date +%m%d-%H%M%S-%N)

    # 配置文件变更：立即快照
    if [[ "$file" == *"openclaw.json" ]] && [[ "$file" != *".last-known-good"* ]]; then
        BACKUP_FILE="$BACKUP_DIR/pre-modify-${NANO_TS}.json"
        cp "$DATA_DIR/openclaw.json" "$BACKUP_FILE" 2>/dev/null
        log "Config snapshot: $BACKUP_FILE (event: $event)"
    fi

    # Workspace 文件变更：快照（包括 .md 和其他重要文件）
    if [[ "$file" == "$WORKSPACE_DIR"* ]] && [[ "$file" != *"auto-backups"* ]]; then
        FNAME=$(basename "$file")
        cp "$file" "$BACKUP_DIR/ws-${FNAME}-${NANO_TS}" 2>/dev/null
        log "Workspace snapshot: $FNAME (event: $event)"
    fi

    # 清理过期备份
    find "$BACKUP_DIR" -name "pre-modify-*" -mmin +$((${BACKUP_RETENTION_HOURS:-48} * 60)) -delete 2>/dev/null
    find "$BACKUP_DIR" -name "ws-*" -mmin +$((${BACKUP_RETENTION_HOURS:-48} * 60)) -delete 2>/dev/null
done
WATCHEOF
chmod +x /usr/local/bin/openclaw-guard-watch.sh
echo -e "${GREEN}✓${NC} 文件监控脚本"

# ---------- 2. 健康检查 + 崩溃恢复脚本 ----------
cat > /usr/local/bin/openclaw-guard-check.sh << 'CHECKEOF'
#!/bin/bash
# openclaw-guard-check.sh - 健康检查 + 崩溃自动恢复
# 每分钟由 systemd timer 触发

source /etc/openclaw-guard.env
DATA_DIR="${OPENCLAW_DATA_DIR:-/opt/1panel/apps/openclaw/openclaw/data/conf}"
CONFIG="$DATA_DIR/openclaw.json"
GOOD="$DATA_DIR/.last-known-good.json"
CRASH_DIR="$DATA_DIR/crash-logs"
CONTAINER_NAME=$(docker ps -a --format '{{.Names}}' | grep -i claw | head -1)

mkdir -p "$CRASH_DIR"

log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1"
}

# 检查配置文件是否存在
if [ ! -f "$CONFIG" ]; then
    log "ERROR: openclaw.json 不存在！"
    if [ -f "$GOOD" ]; then
        cp "$GOOD" "$CONFIG"
        log "已从 last-known-good 恢复"
        [ -n "$CONTAINER_NAME" ] && docker restart "$CONTAINER_NAME"
        python3 /usr/local/bin/alert.py critical "配置文件丢失" \
            "openclaw.json 不存在，已从 last-known-good 恢复并重启容器" 2>/dev/null || true
    fi
    exit 1
fi

# JSON 语法校验
if ! python3 -c "import json; json.load(open('$CONFIG'))" 2>/dev/null; then
    log "ERROR: openclaw.json JSON 语法错误！"

    # 保留崩溃现场
    CRASH_FILE="$CRASH_DIR/openclaw.json.crash-$(date +%m%d-%H%M%S)"
    cp "$CONFIG" "$CRASH_FILE"
    log "崩溃现场已保存: $CRASH_FILE"

    # 恢复
    if [ -f "$GOOD" ]; then
        cp "$GOOD" "$CONFIG"
        log "已恢复到 last-known-good"

        # 重启容器
        if [ -n "$CONTAINER_NAME" ]; then
            docker restart "$CONTAINER_NAME"
            log "容器 $CONTAINER_NAME 已重启"
        fi

        # 发送告警
        python3 /usr/local/bin/alert.py critical "OpenClaw 配置损坏已自动恢复" \
            "JSON语法错误。崩溃现场: $CRASH_FILE。已恢复 last-known-good 并重启容器。" 2>/dev/null || true
    else
        log "ERROR: 没有 last-known-good 备份，无法自动恢复！"
        python3 /usr/local/bin/alert.py critical "OpenClaw 配置损坏且无法自动恢复" \
            "JSON语法错误且没有 last-known-good 备份，需要人工介入！" 2>/dev/null || true
    fi
    exit 1
fi

# 检查容器状态
if [ -n "$CONTAINER_NAME" ]; then
    CONTAINER_STATUS=$(docker inspect -f '{{.State.Status}}' "$CONTAINER_NAME" 2>/dev/null)
    RESTART_COUNT=$(docker inspect -f '{{.RestartCount}}' "$CONTAINER_NAME" 2>/dev/null)

    if [ "$CONTAINER_STATUS" = "restarting" ] && [ "$RESTART_COUNT" -gt 2 ]; then
        log "WARNING: 容器连续重启 ${RESTART_COUNT} 次！尝试恢复..."

        # 保留当前配置
        CRASH_FILE="$CRASH_DIR/openclaw.json.restart-loop-$(date +%m%d-%H%M%S)"
        cp "$CONFIG" "$CRASH_FILE"

        # 恢复 last-known-good
        if [ -f "$GOOD" ]; then
            cp "$GOOD" "$CONFIG"
            docker restart "$CONTAINER_NAME"
            log "已恢复 last-known-good 并重启"

            python3 /usr/local/bin/alert.py error "OpenClaw 重启循环已修复" \
                "容器连续重启 ${RESTART_COUNT} 次，已恢复 last-known-good。崩溃现场: $CRASH_FILE" 2>/dev/null || true
        fi
        exit 0
    fi
fi

# 一切正常，更新 last-known-good
log "✓ 健康检查通过"
cp "$CONFIG" "$GOOD"
CHECKEOF
chmod +x /usr/local/bin/openclaw-guard-check.sh
echo -e "${GREEN}✓${NC} 健康检查脚本"

# ---------- 3. 智能快照脚本 ----------
cat > /usr/local/bin/openclaw-guard-snapshot.sh << 'SNAPEOF'
#!/bin/bash
# openclaw-guard-snapshot.sh - 智能增量快照
# 只在容器健康时创建快照，避免备份脏数据

source /etc/openclaw-guard.env
DATA_DIR="${OPENCLAW_DATA_DIR:-/opt/1panel/apps/openclaw/openclaw/data/conf}"
WORKSPACE_DIR="${OPENCLAW_WORKSPACE_DIR:-/opt/1panel/apps/openclaw/openclaw/data/workspace}"
BACKUP_BASE="/opt/openclaw-guard-backups"
CONTAINER_NAME=$(docker ps --format '{{.Names}}' | grep -i claw | head -1)
RETENTION_HOURS="${BACKUP_RETENTION_HOURS:-48}"

mkdir -p "$BACKUP_BASE"

log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1" | tee -a "$BACKUP_BASE/snapshot.log"
}

log "开始智能快照..."

# 检查容器是否健康
if [ -n "$CONTAINER_NAME" ]; then
    STATUS=$(docker inspect -f '{{.State.Status}}' "$CONTAINER_NAME" 2>/dev/null)
    if [ "$STATUS" != "running" ]; then
        log "⚠️ 容器状态: $STATUS，跳过快照"
        exit 0
    fi
fi

# JSON 校验
if ! python3 -c "import json; json.load(open('$DATA_DIR/openclaw.json'))" 2>/dev/null; then
    log "⚠️ openclaw.json 语法错误，跳过快照"
    exit 0
fi

log "✓ 健康检查通过"

# 创建增量快照
TIMESTAMP=$(date +%m%d-%H%M)
NEW_BACKUP="$BACKUP_BASE/$TIMESTAMP"
LATEST=$(find "$BACKUP_BASE" -maxdepth 1 -type d -name "[0-9]*" 2>/dev/null | sort -r | head -1)

if [ -n "$LATEST" ]; then
    log "创建增量快照 (基于: $(basename $LATEST))"
    mkdir -p "$NEW_BACKUP/conf" "$NEW_BACKUP/workspace"
    rsync -a --link-dest="$LATEST/conf" \
        --exclude='.git' \
        --exclude='auto-backups' \
        --exclude='crash-logs' \
        "$DATA_DIR/" "$NEW_BACKUP/conf/"
    rsync -a --link-dest="$LATEST/workspace" \
        "$WORKSPACE_DIR/" "$NEW_BACKUP/workspace/"
else
    log "创建首次全量快照"
    mkdir -p "$NEW_BACKUP/conf" "$NEW_BACKUP/workspace"
    rsync -a \
        --exclude='.git' \
        --exclude='auto-backups' \
        --exclude='crash-logs' \
        "$DATA_DIR/" "$NEW_BACKUP/conf/"
    rsync -a \
        "$WORKSPACE_DIR/" "$NEW_BACKUP/workspace/"
fi

if [ $? -eq 0 ]; then
    # 记录元数据
    echo "timestamp: $(date)" > "$NEW_BACKUP/.snapshot-meta"
    echo "container: ${CONTAINER_NAME:-unknown}" >> "$NEW_BACKUP/.snapshot-meta"
    echo "type: $([ -n "$LATEST" ] && echo incremental || echo full)" >> "$NEW_BACKUP/.snapshot-meta"

    SIZE=$(du -sh "$NEW_BACKUP" | cut -f1)
    log "✓ 快照完成: $NEW_BACKUP ($SIZE)"
else
    log "✗ 快照失败"
    exit 1
fi

# 清理过期快照
BEFORE_COUNT=$(find "$BACKUP_BASE" -maxdepth 1 -type d -name "[0-9]*" | wc -l)
find "$BACKUP_BASE" -maxdepth 1 -type d -name "[0-9]*" -mmin +$((RETENTION_HOURS * 60)) -exec rm -rf {} \;
AFTER_COUNT=$(find "$BACKUP_BASE" -maxdepth 1 -type d -name "[0-9]*" | wc -l)
CLEANED=$((BEFORE_COUNT - AFTER_COUNT))

if [ $CLEANED -gt 0 ]; then
    log "清理了 $CLEANED 个过期快照，剩余 $AFTER_COUNT 个"
fi

# 磁盘空间检查
DISK_USAGE=$(df "$BACKUP_BASE" | awk 'NR==2 {print int($5)}')
if [ "$DISK_USAGE" -gt 80 ]; then
    log "⚠️ 磁盘使用率 ${DISK_USAGE}%"
    python3 /usr/local/bin/alert.py warning "备份磁盘空间不足" \
        "磁盘使用率 ${DISK_USAGE}%，请清理或扩容" 2>/dev/null || true
fi

log "快照流程完成"
SNAPEOF
chmod +x /usr/local/bin/openclaw-guard-snapshot.sh
echo -e "${GREEN}✓${NC} 智能快照脚本"

# ---------- 4. 一键回滚脚本 ----------
cat > /usr/local/bin/openclaw-guard-rollback.sh << 'ROLLEOF'
#!/bin/bash
# openclaw-guard-rollback.sh - 一键回滚工具

source /etc/openclaw-guard.env
DATA_DIR="${OPENCLAW_DATA_DIR}"
GOOD="$DATA_DIR/.last-known-good.json"
BACKUP_BASE="/opt/openclaw-guard-backups"
AUTO_BACKUP="$DATA_DIR/auto-backups"
CONTAINER_NAME=$(docker ps -a --format '{{.Names}}' | grep -i claw | head -1)

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

case "${1:-}" in
    --immediate)
        echo -e "${YELLOW}回滚到 last-known-good...${NC}"
        if [ ! -f "$GOOD" ]; then
            echo -e "${RED}错误：没有 last-known-good 备份${NC}"
            exit 1
        fi
        # 保存当前状态
        cp "$DATA_DIR/openclaw.json" "$DATA_DIR/openclaw.json.before-rollback-$(date +%m%d-%H%M%S)"
        # 恢复
        cp "$GOOD" "$DATA_DIR/openclaw.json"
        # 重启容器
        if [ -n "$CONTAINER_NAME" ]; then
            docker restart "$CONTAINER_NAME"
            echo -e "${GREEN}✓ 回滚完成，容器 $CONTAINER_NAME 已重启${NC}"
        else
            echo -e "${GREEN}✓ 回滚完成（未找到容器，请手动重启）${NC}"
        fi
        ;;

    --snapshot)
        if [ -z "$2" ]; then
            echo -e "${RED}请指定快照名称${NC}"
            echo "用法: openclaw-guard-rollback.sh --snapshot 0312-1430"
            exit 1
        fi
        SNAP="$BACKUP_BASE/$2"
        if [ ! -d "$SNAP" ]; then
            echo -e "${RED}快照不存在: $2${NC}"
            exit 1
        fi
        echo -e "${YELLOW}回滚到快照: $2${NC}"
        # 保存当前状态
        BEFORE="$BACKUP_BASE/before-rollback-$(date +%m%d-%H%M%S)"
        mkdir -p "$BEFORE/conf" "$BEFORE/workspace"
        rsync -a --exclude='.git' --exclude='auto-backups' --exclude='crash-logs' "$DATA_DIR/" "$BEFORE/conf/"
        rsync -a "$WORKSPACE_DIR/" "$BEFORE/workspace/"
        # 恢复（快照中有 conf/ 和 workspace/ 子目录）
        [ -d "$SNAP/conf" ] && rsync -a "$SNAP/conf/" "$DATA_DIR/" --exclude='.git' --exclude='auto-backups' --exclude='crash-logs'
        [ -d "$SNAP/workspace" ] && rsync -a "$SNAP/workspace/" "$WORKSPACE_DIR/"
        if [ -n "$CONTAINER_NAME" ]; then
            docker restart "$CONTAINER_NAME"
        fi
        echo -e "${GREEN}✓ 已恢复到快照 $2${NC}"
        echo -e "回滚前状态保存在: $BEFORE"
        ;;

    --auto-backup)
        if [ -z "$2" ]; then
            echo -e "${RED}请指定备份文件名${NC}"
            exit 1
        fi
        BACKUP_FILE="$AUTO_BACKUP/$2"
        if [ ! -f "$BACKUP_FILE" ]; then
            echo -e "${RED}备份文件不存在: $2${NC}"
            exit 1
        fi
        echo -e "${YELLOW}从自动备份恢复: $2${NC}"
        cp "$DATA_DIR/openclaw.json" "$DATA_DIR/openclaw.json.before-rollback-$(date +%m%d-%H%M%S)"
        cp "$BACKUP_FILE" "$DATA_DIR/openclaw.json"
        if [ -n "$CONTAINER_NAME" ]; then
            docker restart "$CONTAINER_NAME"
        fi
        echo -e "${GREEN}✓ 已恢复${NC}"
        ;;

    --git)
        if [ -z "$2" ]; then
            echo -e "${BLUE}=== Git 历史 ===${NC}"
            git -C "$DATA_DIR" log --oneline --graph -20
            echo ""
            echo "用法: openclaw-guard-rollback.sh --git <commit-hash>"
        else
            echo -e "${YELLOW}回滚到 Git 提交: $2${NC}"
            git -C "$DATA_DIR" stash push -m "before-rollback-$(date +%m%d-%H%M%S)" 2>/dev/null || true
            git -C "$DATA_DIR" checkout "$2" -- openclaw.json
            if [ -n "$CONTAINER_NAME" ]; then
                docker restart "$CONTAINER_NAME"
            fi
            echo -e "${GREEN}✓ 已恢复到 $2${NC}"
            echo "撤销: git -C $DATA_DIR stash pop"
        fi
        ;;

    --list)
        echo -e "${BLUE}========================================${NC}"
        echo -e "${BLUE}  可用备份列表${NC}"
        echo -e "${BLUE}========================================${NC}"
        echo ""

        echo -e "${GREEN}1. Last-Known-Good:${NC}"
        if [ -f "$GOOD" ]; then
            ls -lh "$GOOD" | awk '{printf "   %s (%s)\n", $NF, $5}'
        else
            echo "   (无)"
        fi

        echo ""
        echo -e "${GREEN}2. 自动备份 (最近 10 个):${NC}"
        ls -lt "$AUTO_BACKUP"/pre-modify-*.json 2>/dev/null | head -10 | awk '{printf "   %s (%s)\n", $NF, $5}'
        [ $? -ne 0 ] && echo "   (无)"

        echo ""
        echo -e "${GREEN}3. 增量快照:${NC}"
        for snap in $(ls -d "$BACKUP_BASE"/[0-9]* 2>/dev/null | sort -r | head -10); do
            SIZE=$(du -sh "$snap" 2>/dev/null | cut -f1)
            echo "   $(basename $snap) ($SIZE)"
        done
        [ $? -ne 0 ] && echo "   (无)"

        echo ""
        echo -e "${GREEN}4. Git 历史 (最近 10 个):${NC}"
        cd "$DATA_DIR" && git log --oneline -10 2>/dev/null | sed 's/^/   /'

        echo ""
        echo -e "${GREEN}5. 崩溃现场:${NC}"
        ls -lt "$DATA_DIR/crash-logs"/*.crash-* 2>/dev/null | head -5 | awk '{printf "   %s (%s)\n", $NF, $5}'
        ls -lt "$DATA_DIR/crash-logs"/*.restart-loop-* 2>/dev/null | head -5 | awk '{printf "   %s (%s)\n", $NF, $5}'
        echo ""
        ;;

    --diff)
        if [ -z "$2" ]; then
            echo "对比当前配置与 last-known-good 的差异："
            diff --color "$GOOD" "$DATA_DIR/openclaw.json" || true
        else
            echo "对比当前配置与 $2："
            if [ -f "$AUTO_BACKUP/$2" ]; then
                diff --color "$AUTO_BACKUP/$2" "$DATA_DIR/openclaw.json" || true
            else
                echo -e "${RED}文件不存在: $2${NC}"
            fi
        fi
        ;;

    --help|*)
        echo -e "${BLUE}OpenClaw Guard 回滚工具${NC}"
        echo ""
        echo "用法:"
        echo "  openclaw-guard-rollback.sh --immediate              立即回滚到上次正常配置"
        echo "  openclaw-guard-rollback.sh --snapshot 0312-1430     回滚到指定快照"
        echo "  openclaw-guard-rollback.sh --auto-backup <文件名>    从自动备份恢复"
        echo "  openclaw-guard-rollback.sh --git [commit]           查看/回滚 Git 历史"
        echo "  openclaw-guard-rollback.sh --list                   列出所有可用备份"
        echo "  openclaw-guard-rollback.sh --diff [文件名]           对比配置差异"
        echo "  openclaw-guard-rollback.sh --help                   显示帮助"
        ;;
esac
ROLLEOF
chmod +x /usr/local/bin/openclaw-guard-rollback.sh
echo -e "${GREEN}✓${NC} 一键回滚脚本"

# ---------- 5. 告警脚本 ----------
cp /opt/openclaw-guard/scripts/alert.py /usr/local/bin/alert.py
echo -e "${GREEN}✓${NC} 告警通知脚本"

# ============================================
# 创建 systemd 服务
# ============================================

echo ""
echo "配置 systemd 服务..."

# 文件监控服务
cat > /etc/systemd/system/openclaw-guard.service << EOF
[Unit]
Description=OpenClaw Guard - File Monitor
After=docker.service
Requires=docker.service

[Service]
Type=simple
EnvironmentFile=/etc/openclaw-guard.env
ExecStart=/usr/local/bin/openclaw-guard-watch.sh
Restart=always
RestartSec=5
StandardOutput=journal
StandardError=journal
SyslogIdentifier=openclaw-guard

[Install]
WantedBy=multi-user.target
EOF
echo -e "${GREEN}✓${NC} openclaw-guard.service"

# 健康检查服务 + 定时器
cat > /etc/systemd/system/openclaw-guard-check.service << EOF
[Unit]
Description=OpenClaw Guard - Health Check

[Service]
Type=oneshot
EnvironmentFile=/etc/openclaw-guard.env
ExecStart=/usr/local/bin/openclaw-guard-check.sh
StandardOutput=journal
StandardError=journal
SyslogIdentifier=openclaw-guard-check
EOF

cat > /etc/systemd/system/openclaw-guard-check.timer << EOF
[Unit]
Description=OpenClaw Guard - Health Check Timer

[Timer]
OnBootSec=60
OnUnitActiveSec=60

[Install]
WantedBy=timers.target
EOF
echo -e "${GREEN}✓${NC} openclaw-guard-check.timer (每分钟)"

# 快照服务 + 定时器
cat > /etc/systemd/system/openclaw-guard-snapshot.service << EOF
[Unit]
Description=OpenClaw Guard - Smart Snapshot

[Service]
Type=oneshot
EnvironmentFile=/etc/openclaw-guard.env
ExecStart=/usr/local/bin/openclaw-guard-snapshot.sh
StandardOutput=journal
StandardError=journal
SyslogIdentifier=openclaw-guard-snapshot
EOF

cat > /etc/systemd/system/openclaw-guard-snapshot.timer << EOF
[Unit]
Description=OpenClaw Guard - Snapshot Timer

[Timer]
OnBootSec=300
OnUnitActiveSec=3600

[Install]
WantedBy=timers.target
EOF
echo -e "${GREEN}✓${NC} openclaw-guard-snapshot.timer (每小时)"

# Docker 事件监听服务（核心：秒级崩溃恢复）
cat > /usr/local/bin/openclaw-guard-docker-watcher.sh << 'DOCKERWATCHEOF'
#!/bin/bash
# openclaw-guard-docker-watcher.sh - Docker 事件监听器
# 核心功能：容器一 die 就立刻校验配置并恢复，不等定时器
# 解决问题：check.timer 每分钟才跑一次，Docker 重启循环是秒级的

source /etc/openclaw-guard.env
DATA_DIR="${OPENCLAW_DATA_DIR:-/opt/1panel/apps/openclaw/openclaw/data/conf}"
GOOD="$DATA_DIR/.last-known-good.json"
CONFIG="$DATA_DIR/openclaw.json"
CRASH_DIR="$DATA_DIR/crash-logs"
LOG="/var/log/openclaw-guard-docker-watcher.log"

# 重启循环检测
RESTART_COUNT=0
LAST_RESTART_TIME=0
COOLDOWN_ACTIVE=false

mkdir -p "$CRASH_DIR"

log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG"
}

recover_config() {
    log "🔧 开始配置恢复..."

    # 1. 校验 JSON 语法
    if ! python3 -c "import json; json.load(open('$CONFIG'))" 2>/dev/null; then
        log "❌ JSON 语法错误，立即恢复"

        # 保存崩溃现场
        CRASH_FILE="$CRASH_DIR/openclaw.json.crash-$(date +%m%d-%H%M%S)"
        cp "$CONFIG" "$CRASH_FILE" 2>/dev/null
        log "崩溃现场: $CRASH_FILE"

        # 恢复 last-known-good
        if [ -f "$GOOD" ]; then
            cp "$GOOD" "$CONFIG"
            log "✅ 已恢复 last-known-good"
            python3 /usr/local/bin/alert.py critical "OpenClaw 崩溃循环已修复" \
                "JSON语法错误导致容器反复重启。已自动恢复 last-known-good。崩溃现场: $CRASH_FILE" 2>/dev/null || true
            return 0
        else
            log "❌ 没有 last-known-good 备份！"
            return 1
        fi
    fi

    # 2. 检查必需字段
    if ! python3 -c "
import json
with open('$CONFIG') as f:
    d = json.load(f)
# 基本完整性检查：文件不能为空对象
assert len(d) > 0, 'Empty config'
" 2>/dev/null; then
        log "❌ 配置逻辑错误，恢复 last-known-good"
        CRASH_FILE="$CRASH_DIR/openclaw.json.logic-error-$(date +%m%d-%H%M%S)"
        cp "$CONFIG" "$CRASH_FILE" 2>/dev/null
        if [ -f "$GOOD" ]; then
            cp "$GOOD" "$CONFIG"
            log "✅ 已恢复 last-known-good"
            return 0
        fi
        return 1
    fi

    log "✓ 配置校验通过，崩溃可能是其他原因"
    return 0
}

log "=========================================="
log "Docker 事件监听器启动"
log "监听容器: *claw*"
log "=========================================="

# 监听 Docker 事件流（容器 die 事件）
docker events --filter 'event=die' --format '{{.Actor.Attributes.name}} {{.time}}' 2>/dev/null | while read CONTAINER_NAME EVENT_TIME; do

    # 只关心 OpenClaw 容器
    if [[ "$CONTAINER_NAME" != *claw* ]] && [[ "$CONTAINER_NAME" != *Claw* ]] && [[ "$CONTAINER_NAME" != *CLAW* ]]; then
        continue
    fi

    NOW=$(date +%s)
    log "⚠️ 容器 $CONTAINER_NAME 死亡 (event_time: $EVENT_TIME)"

    # 重启循环检测：5 分钟内超过 3 次 die = 重启循环
    if [ $((NOW - LAST_RESTART_TIME)) -lt 300 ]; then
        RESTART_COUNT=$((RESTART_COUNT + 1))
    else
        RESTART_COUNT=1
    fi
    LAST_RESTART_TIME=$NOW

    log "重启计数: $RESTART_COUNT (5分钟窗口)"

    if [ "$RESTART_COUNT" -ge 3 ]; then
        if [ "$COOLDOWN_ACTIVE" = "false" ]; then
            log "🚨 检测到重启循环！($RESTART_COUNT 次/5分钟) 立即介入"
            COOLDOWN_ACTIVE=true

            # 立即恢复配置
            recover_config

            # 等 Docker 自动重启容器（已恢复好的配置）
            log "等待 Docker 重启容器（配置已修复）..."
            sleep 10

            # 检查容器是否恢复
            CONTAINER_STATUS=$(docker inspect -f '{{.State.Status}}' "$CONTAINER_NAME" 2>/dev/null || echo "unknown")
            if [ "$CONTAINER_STATUS" = "running" ]; then
                log "✅ 容器已恢复运行！"
                RESTART_COUNT=0
                COOLDOWN_ACTIVE=false
            else
                log "⚠️ 容器仍未恢复 (status: $CONTAINER_STATUS)，尝试手动重启..."
                docker restart "$CONTAINER_NAME" 2>/dev/null || true
                sleep 15
                CONTAINER_STATUS=$(docker inspect -f '{{.State.Status}}' "$CONTAINER_NAME" 2>/dev/null || echo "unknown")
                if [ "$CONTAINER_STATUS" = "running" ]; then
                    log "✅ 手动重启成功！"
                else
                    log "❌ 仍然失败，需要人工介入"
                    python3 /usr/local/bin/alert.py critical "OpenClaw 无法自动恢复" \
                        "容器 $CONTAINER_NAME 反复崩溃，自动恢复失败，需要人工介入！" 2>/dev/null || true
                fi
                RESTART_COUNT=0
                COOLDOWN_ACTIVE=false
            fi
        else
            log "冷却中，跳过（等待上次恢复生效）"
        fi
    else
        # 首次或第二次 die，可能是正常重启，只做校验不介入
        log "首次/偶发死亡，校验配置..."
        recover_config
    fi
done

log "Docker 事件监听器退出（异常）"
DOCKERWATCHEOF
chmod +x /usr/local/bin/openclaw-guard-docker-watcher.sh
echo -e "${GREEN}✓${NC} openclaw-guard-docker-watcher.sh (Docker 事件监听器)"

# Docker 事件监听 systemd 服务
cat > /etc/systemd/system/openclaw-guard-docker-watcher.service << EOF
[Unit]
Description=OpenClaw Guard - Docker Event Watcher (instant crash recovery)
After=docker.service
Requires=docker.service

[Service]
Type=simple
EnvironmentFile=/etc/openclaw-guard.env
ExecStart=/usr/local/bin/openclaw-guard-docker-watcher.sh
Restart=always
RestartSec=5
StandardOutput=journal
StandardError=journal
SyslogIdentifier=openclaw-guard-docker-watcher

[Install]
WantedBy=multi-user.target
EOF
echo -e "${GREEN}✓${NC} openclaw-guard-docker-watcher.service (秒级崩溃恢复)"

# ============================================
# Git 自动提交 cron
# ============================================

cat > /etc/cron.d/openclaw-guard << CRONEOF
# OpenClaw Guard - Git 自动提交（每 5 分钟）
# 同时追踪 conf 和 workspace 目录的变更
*/5 * * * * root source /etc/openclaw-guard.env && cd \${OPENCLAW_DATA_DIR} && (rsync -a --delete \${OPENCLAW_WORKSPACE_DIR}/ \${OPENCLAW_DATA_DIR}/workspace-mirror/ 2>/dev/null; git diff --quiet HEAD 2>/dev/null || (git add -A && git commit -m "auto: \$(date +\%m\%d-\%H\%M)" -q 2>/dev/null))

# OpenClaw Guard - 清理过期崩溃日志（每天凌晨 3 点）
0 3 * * * root source /etc/openclaw-guard.env && find \${OPENCLAW_DATA_DIR}/crash-logs -name "*.crash-*" -mtime +7 -delete 2>/dev/null; find \${OPENCLAW_DATA_DIR}/crash-logs -name "*.restart-loop-*" -mtime +7 -delete 2>/dev/null
CRONEOF
echo -e "${GREEN}✓${NC} cron 定时任务"

# ============================================
# 启动所有服务
# ============================================

echo ""
echo "启动服务..."

systemctl daemon-reload
systemctl enable openclaw-guard.service 2>/dev/null
systemctl enable openclaw-guard-check.timer 2>/dev/null
systemctl enable openclaw-guard-snapshot.timer 2>/dev/null
systemctl enable openclaw-guard-docker-watcher.service 2>/dev/null
systemctl start openclaw-guard.service
systemctl start openclaw-guard-check.timer
systemctl start openclaw-guard-snapshot.timer
systemctl start openclaw-guard-docker-watcher.service

echo -e "${GREEN}✓${NC} 所有服务已启动"

# ============================================
# 验证
# ============================================

echo ""
echo -e "${GREEN}==========================================${NC}"
echo -e "${GREEN}  安装完成！${NC}"
echo -e "${GREEN}==========================================${NC}"
echo ""
echo "运行中的服务："

# 检查服务状态
for svc in openclaw-guard.service openclaw-guard-check.timer openclaw-guard-snapshot.timer; do
    STATUS=$(systemctl is-active $svc 2>/dev/null)
    if [ "$STATUS" = "active" ]; then
        echo -e "  ${GREEN}✓${NC} $svc"
    else
        echo -e "  ${RED}✗${NC} $svc ($STATUS)"
    fi
done

echo ""
echo "防护能力："
echo "  ✓ 实时文件监控      - 任何修改前自动快照"
echo "  ✓ 每分钟健康检查    - 配置损坏/容器重启循环自动恢复"
echo "  ✓ 每小时增量快照    - 只在健康时备份，不备份脏数据"
echo "  ✓ 每 5 分钟 Git 提交 - 完整变更历史可追溯"
echo ""
echo "常用命令："
echo -e "  ${BLUE}查看状态${NC}    systemctl status openclaw-guard"
echo -e "  ${BLUE}查看日志${NC}    journalctl -u openclaw-guard -f"
echo -e "  ${BLUE}一键回滚${NC}    openclaw-guard-rollback.sh --immediate"
echo -e "  ${BLUE}列出备份${NC}    openclaw-guard-rollback.sh --list"
echo -e "  ${BLUE}对比差异${NC}    openclaw-guard-rollback.sh --diff"
echo -e "  ${BLUE}手动快照${NC}    openclaw-guard-snapshot.sh"
echo -e "  ${BLUE}手动检查${NC}    openclaw-guard-check.sh"
echo ""
echo -e "${YELLOW}提示：如果告警没配置，编辑 /etc/openclaw-guard.env 添加 Webhook${NC}"
