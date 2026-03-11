#!/bin/bash
# smart-snapshot.sh - 智能快照脚本
# 功能：只在 OpenClaw 健康时创建增量快照，避免备份脏数据

SOURCE_DIR="/home/node/.openclaw"
BACKUP_BASE="/home/node/openclaw-backups"
LOG_FILE="$BACKUP_BASE/snapshot.log"
HEALTH_ENDPOINT="${HEALTH_CHECK_ENDPOINT:-http://localhost:3000/health}"
RETENTION_HOURS="${BACKUP_RETENTION_HOURS:-48}"

mkdir -p "$BACKUP_BASE"

log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

# 健康检查
check_health() {
    if curl -sf "$HEALTH_ENDPOINT" > /dev/null 2>&1; then
        return 0
    else
        return 1
    fi
}

log "Starting smart snapshot..."

# 检查 OpenClaw 是否健康
if ! check_health; then
    log "⚠️  OpenClaw is unhealthy, skipping snapshot to avoid backing up corrupted state"
    exit 0
fi

log "✓ Health check passed"

# 生成时间戳
TIMESTAMP=$(date +%m%d-%H%M)
NEW_BACKUP="$BACKUP_BASE/$TIMESTAMP"

# 查找最新的备份（用于增量链接）
LATEST_BACKUP=$(find "$BACKUP_BASE" -maxdepth 1 -type d -name "[0-9]*" | sort -r | head -1)

# 创建增量快照
if [ -n "$LATEST_BACKUP" ]; then
    log "Creating incremental snapshot (linked to: $(basename $LATEST_BACKUP))"
    rsync -a --link-dest="$LATEST_BACKUP" "$SOURCE_DIR/" "$NEW_BACKUP/"
else
    log "Creating first full snapshot"
    rsync -a "$SOURCE_DIR/" "$NEW_BACKUP/"
fi

if [ $? -eq 0 ]; then
    log "✓ Snapshot created: $NEW_BACKUP"
    
    # 记录快照元数据
    echo "timestamp: $(date)" > "$NEW_BACKUP/.snapshot-meta"
    echo "type: incremental" >> "$NEW_BACKUP/.snapshot-meta"
    echo "source: $SOURCE_DIR" >> "$NEW_BACKUP/.snapshot-meta"
    
    # 可选：压缩归档
    if [ "$BACKUP_COMPRESS" = "true" ]; then
        log "Compressing snapshot..."
        tar czf "$NEW_BACKUP.tar.gz" -C "$BACKUP_BASE" "$(basename $NEW_BACKUP)"
        rm -rf "$NEW_BACKUP"
        log "✓ Compressed: $NEW_BACKUP.tar.gz"
    fi
else
    log "✗ Snapshot failed"
    exit 1
fi

# 清理过期快照
log "Cleaning up old snapshots (retention: ${RETENTION_HOURS}h)..."

if [ "$BACKUP_COMPRESS" = "true" ]; then
    # 清理压缩文件
    find "$BACKUP_BASE" -name "*.tar.gz" -mmin +$((RETENTION_HOURS * 60)) -delete
else
    # 清理目录
    find "$BACKUP_BASE" -maxdepth 1 -type d -name "[0-9]*" -mmin +$((RETENTION_HOURS * 60)) -exec rm -rf {} \;
fi

REMAINING=$(find "$BACKUP_BASE" -maxdepth 1 \( -type d -name "[0-9]*" -o -name "*.tar.gz" \) | wc -l)
log "✓ Cleanup complete. Remaining snapshots: $REMAINING"

# 磁盘空间检查
DISK_USAGE=$(df -h "$BACKUP_BASE" | awk 'NR==2 {print $5}' | sed 's/%//')
if [ "$DISK_USAGE" -gt 80 ]; then
    log "⚠️  WARNING: Backup disk usage is ${DISK_USAGE}%"
    
    # 发送告警
    if [ -f "/usr/local/bin/alert.py" ]; then
        python3 /usr/local/bin/alert.py "warning" "Backup Disk Usage High" \
            "Backup directory is ${DISK_USAGE}% full. Consider increasing retention policy or disk space."
    fi
fi

log "Smart snapshot completed successfully"
