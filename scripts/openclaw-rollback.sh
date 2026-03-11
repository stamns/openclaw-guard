#!/bin/bash
# openclaw-rollback.sh - 一键回滚脚本
# 功能：快速恢复到指定时间点或最近的正常状态

set -e

SOURCE_DIR="/home/node/.openclaw"
BACKUP_BASE="/home/node/openclaw-backups"
AUTO_BACKUP_DIR="/home/node/.openclaw/auto-backups"
GOOD_BACKUP="/home/node/.openclaw/.last-known-good.json"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

usage() {
    cat << EOF
${GREEN}OpenClaw Rollback Tool${NC}

Usage: openclaw-rollback [OPTIONS]

Options:
    --immediate         回滚到 last-known-good（最快，1秒）
    --time <duration>   回滚到 N 时间前（如：2h, 30m, 1d）
    --list              列出所有可用的快照
    --snapshot <name>   回滚到指定快照
    --git <commit>      回滚到指定 Git 提交
    --help              显示此帮助信息

Examples:
    openclaw-rollback --immediate           # 回滚到上次正常配置
    openclaw-rollback --time 2h             # 回滚到 2 小时前
    openclaw-rollback --snapshot 0312-1430  # 回滚到指定快照
    openclaw-rollback --git HEAD~3          # 回滚到 3 个提交前
    openclaw-rollback --list                # 列出所有快照

EOF
    exit 0
}

log() {
    echo -e "${GREEN}[$(date +'%H:%M:%S')]${NC} $1"
}

warn() {
    echo -e "${YELLOW}[$(date +'%H:%M:%S')] WARNING:${NC} $1"
}

error() {
    echo -e "${RED}[$(date +'%H:%M:%S')] ERROR:${NC} $1"
    exit 1
}

# 列出所有快照
list_snapshots() {
    echo -e "${BLUE}=== Available Snapshots ===${NC}\n"
    
    echo -e "${GREEN}1. Incremental Snapshots:${NC}"
    if [ "$BACKUP_COMPRESS" = "true" ]; then
        ls -lh "$BACKUP_BASE"/*.tar.gz 2>/dev/null | awk '{print "   " $9 " (" $5 ")"}'
    else
        ls -ld "$BACKUP_BASE"/*/ 2>/dev/null | awk '{print "   " $9}'
    fi
    
    echo -e "\n${GREEN}2. Auto Backups (pre-modify):${NC}"
    ls -lh "$AUTO_BACKUP_DIR"/*.json 2>/dev/null | tail -10 | awk '{print "   " $9 " (" $5 ")"}'
    
    echo -e "\n${GREEN}3. Git History:${NC}"
    cd "$SOURCE_DIR"
    git log --oneline -10 2>/dev/null | sed 's/^/   /'
    
    echo -e "\n${GREEN}4. Last Known Good:${NC}"
    if [ -f "$GOOD_BACKUP" ]; then
        ls -lh "$GOOD_BACKUP" | awk '{print "   " $9 " (" $5 ")"}'
    else
        echo "   Not available"
    fi
}

# 回滚到 last-known-good
rollback_immediate() {
    log "Rolling back to last-known-good..."
    
    if [ ! -f "$GOOD_BACKUP" ]; then
        error "No last-known-good backup found!"
    fi
    
    # 备份当前状态
    cp "$SOURCE_DIR/openclaw.json" "$SOURCE_DIR/openclaw.json.before-rollback-$(date +%m%d-%H%M%S)"
    
    # 恢复
    cp "$GOOD_BACKUP" "$SOURCE_DIR/openclaw.json"
    
    log "✓ Rollback completed in 1 second"
    log "Current config restored from last-known-good"
}

# 回滚到指定时间前
rollback_time() {
    local duration=$1
    log "Rolling back to $duration ago..."
    
    # 解析时间（支持 2h, 30m, 1d）
    local minutes=0
    if [[ $duration =~ ^([0-9]+)h$ ]]; then
        minutes=$((${BASH_REMATCH[1]} * 60))
    elif [[ $duration =~ ^([0-9]+)m$ ]]; then
        minutes=${BASH_REMATCH[1]}
    elif [[ $duration =~ ^([0-9]+)d$ ]]; then
        minutes=$((${BASH_REMATCH[1]} * 1440))
    else
        error "Invalid time format. Use: 2h, 30m, 1d"
    fi
    
    # 查找最接近的快照
    local target_snapshot=$(find "$BACKUP_BASE" -maxdepth 1 -type d -name "[0-9]*" -mmin +$minutes | sort -r | head -1)
    
    if [ -z "$target_snapshot" ]; then
        error "No snapshot found from $duration ago"
    fi
    
    log "Found snapshot: $(basename $target_snapshot)"
    
    # 备份当前状态
    rsync -a "$SOURCE_DIR/" "$SOURCE_DIR.before-rollback-$(date +%m%d-%H%M%S)/"
    
    # 恢复
    rsync -a --delete "$target_snapshot/" "$SOURCE_DIR/"
    
    log "✓ Rollback completed"
    log "Restored from: $(basename $target_snapshot)"
}

# 回滚到指定快照
rollback_snapshot() {
    local snapshot_name=$1
    log "Rolling back to snapshot: $snapshot_name..."
    
    local snapshot_path="$BACKUP_BASE/$snapshot_name"
    
    # 检查是否是压缩文件
    if [ -f "$snapshot_path.tar.gz" ]; then
        log "Extracting compressed snapshot..."
        tar xzf "$snapshot_path.tar.gz" -C /tmp/
        snapshot_path="/tmp/$snapshot_name"
    fi
    
    if [ ! -d "$snapshot_path" ]; then
        error "Snapshot not found: $snapshot_name"
    fi
    
    # 备份当前状态
    rsync -a "$SOURCE_DIR/" "$SOURCE_DIR.before-rollback-$(date +%m%d-%H%M%S)/"
    
    # 恢复
    rsync -a --delete "$snapshot_path/" "$SOURCE_DIR/"
    
    # 清理临时文件
    [ -d "/tmp/$snapshot_name" ] && rm -rf "/tmp/$snapshot_name"
    
    log "✓ Rollback completed"
    log "Restored from snapshot: $snapshot_name"
}

# 回滚到指定 Git 提交
rollback_git() {
    local commit=$1
    log "Rolling back to Git commit: $commit..."
    
    cd "$SOURCE_DIR"
    
    # 检查提交是否存在
    if ! git rev-parse "$commit" > /dev/null 2>&1; then
        error "Invalid Git commit: $commit"
    fi
    
    # 备份当前状态
    git stash push -m "before-rollback-$(date +%m%d-%H%M%S)"
    
    # 回滚
    git checkout "$commit" -- .
    
    log "✓ Rollback completed"
    log "Restored from Git commit: $commit"
    log "To undo: git stash pop"
}

# 主逻辑
case "${1:-}" in
    --immediate)
        rollback_immediate
        ;;
    --time)
        [ -z "$2" ] && error "Missing time duration"
        rollback_time "$2"
        ;;
    --list)
        list_snapshots
        ;;
    --snapshot)
        [ -z "$2" ] && error "Missing snapshot name"
        rollback_snapshot "$2"
        ;;
    --git)
        [ -z "$2" ] && error "Missing Git commit"
        rollback_git "$2"
        ;;
    --help|*)
        usage
        ;;
esac

# 重启 OpenClaw 容器（如果在容器内运行）
if [ -f "/.dockerenv" ]; then
    warn "Restarting OpenClaw container..."
    # 这里需要容器有权限重启自己，或者通过外部脚本触发
    log "Please manually restart the container: docker-compose restart openclaw"
fi
