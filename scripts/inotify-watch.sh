#!/bin/bash
# inotify-watch.sh - 文件系统监控脚本
# 功能：监控配置文件变化，任何修改前自动快照

CONFIG="/home/node/.openclaw/openclaw.json"
WORKSPACE_DIR="/home/node/.openclaw/workspace"
BACKUP_DIR="/home/node/.openclaw/auto-backups"
LOG_FILE="$BACKUP_DIR/watch.log"

mkdir -p "$BACKUP_DIR"

log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

log "File system monitor started"
log "Watching: $CONFIG, $WORKSPACE_DIR"

# 监控配置文件和 workspace 目录
inotifywait -m -e modify,move_self,create,delete \
    --format '%T %w%f %e' \
    --timefmt '%Y-%m-%d %H:%M:%S' \
    "$CONFIG" "$WORKSPACE_DIR" 2>/dev/null | while read timestamp file event; do
    
    # 生成唯一时间戳（精确到纳秒）
    NANO_TIMESTAMP=$(date +%m%d-%H%M%S-%N)
    
    # 根据文件类型决定备份策略
    if [[ "$file" == *"openclaw.json"* ]]; then
        # 配置文件：立即备份
        BACKUP_FILE="$BACKUP_DIR/config-pre-modify-${NANO_TIMESTAMP}.json"
        cp "$CONFIG" "$BACKUP_FILE" 2>/dev/null
        log "Config pre-modify snapshot: $BACKUP_FILE (event: $event)"
        
    elif [[ "$file" == *".md"* ]]; then
        # Workspace Markdown 文件：备份
        FILENAME=$(basename "$file")
        BACKUP_FILE="$BACKUP_DIR/workspace-${FILENAME}-${NANO_TIMESTAMP}"
        cp "$file" "$BACKUP_FILE" 2>/dev/null
        log "Workspace file snapshot: $BACKUP_FILE (event: $event)"
    fi
    
    # 清理超过 48 小时的自动备份
    find "$BACKUP_DIR" -name "*.json" -mtime +2 -delete 2>/dev/null
    find "$BACKUP_DIR" -name "workspace-*" -mtime +2 -delete 2>/dev/null
done
