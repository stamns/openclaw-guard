#!/bin/bash
# entrypoint-guard.sh - OpenClaw 启动守卫脚本
# 功能：容器启动时校验配置合法性，损坏自动回滚

set -e

CONFIG="/home/node/.openclaw/openclaw.json"
GOOD_BACKUP="/home/node/.openclaw/.last-known-good.json"
CRASH_DIR="/home/node/.openclaw/crash-logs"
ALERT_SCRIPT="/usr/local/bin/alert.py"

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1"
}

warn() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] WARNING:${NC} $1"
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ERROR:${NC} $1"
}

# 创建必要目录
mkdir -p "$CRASH_DIR"
mkdir -p "/home/node/.openclaw/auto-backups"
mkdir -p "/home/node/openclaw-backups"

# 初始化 Git 仓库（如果未初始化）
if [ ! -d "/home/node/.openclaw/.git" ]; then
    log "Initializing Git repository..."
    cd /home/node/.openclaw
    git init
    git add .
    git commit -m "Initial commit by guard" || true
fi

# 如果没有 last-known-good 备份，创建一个
if [ ! -f "$GOOD_BACKUP" ]; then
    if [ -f "$CONFIG" ]; then
        log "Creating initial last-known-good backup..."
        cp "$CONFIG" "$GOOD_BACKUP"
    else
        error "No openclaw.json found and no backup available!"
        exit 1
    fi
fi

# 校验函数：JSON 语法检查
validate_json_syntax() {
    if python3 -c "import json; json.load(open('$1'))" 2>/dev/null; then
        return 0
    else
        return 1
    fi
}

# 校验函数：配置逻辑检查（检查关键字段）
validate_config_logic() {
    local config_file=$1
    
    # 检查必须存在的关键字段
    local required_fields=("version" "server")
    
    for field in "${required_fields[@]}"; do
        if ! jq -e ".$field" "$config_file" > /dev/null 2>&1; then
            warn "Missing required field: $field"
            return 1
        fi
    done
    
    return 0
}

# 发送告警
send_alert() {
    local level=$1
    local title=$2
    local message=$3
    
    if [ -f "$ALERT_SCRIPT" ] && [ "$GUARD_ENABLED" = "true" ]; then
        python3 "$ALERT_SCRIPT" "$level" "$title" "$message" || true
    fi
}

# 主校验流程
log "Starting OpenClaw Guard entrypoint..."
log "Config file: $CONFIG"

if [ ! -f "$CONFIG" ]; then
    error "Configuration file not found!"
    
    if [ -f "$GOOD_BACKUP" ]; then
        warn "Restoring from last-known-good backup..."
        cp "$GOOD_BACKUP" "$CONFIG"
        send_alert "critical" "Config Missing - Restored" "openclaw.json was missing, restored from backup"
    else
        error "No backup available. Cannot start."
        exit 1
    fi
fi

# 第1步：JSON 语法校验
log "Step 1/3: Validating JSON syntax..."
if ! validate_json_syntax "$CONFIG"; then
    error "Invalid JSON syntax detected!"
    
    # 保存崩溃现场
    CRASH_FILE="$CRASH_DIR/openclaw.json.crash-$(date +%m%d-%H%M%S)"
    cp "$CONFIG" "$CRASH_FILE"
    log "Crash dump saved to: $CRASH_FILE"
    
    # 恢复 last-known-good
    warn "Restoring from last-known-good backup..."
    cp "$GOOD_BACKUP" "$CONFIG"
    
    # 发送告警
    send_alert "critical" "Config Corrupted - Auto Recovered" \
        "JSON syntax error detected. Crash dump: $CRASH_FILE. Restored from last-known-good backup."
    
    log "Configuration restored successfully."
else
    log "✓ JSON syntax valid"
fi

# 第2步：配置逻辑校验
log "Step 2/3: Validating configuration logic..."
if ! validate_config_logic "$CONFIG"; then
    warn "Configuration logic validation failed!"
    
    # 保存崩溃现场
    CRASH_FILE="$CRASH_DIR/openclaw.json.logic-error-$(date +%m%d-%H%M%S)"
    cp "$CONFIG" "$CRASH_FILE"
    
    # 恢复 last-known-good
    warn "Restoring from last-known-good backup..."
    cp "$GOOD_BACKUP" "$CONFIG"
    
    # 发送告警
    send_alert "warning" "Config Logic Error - Auto Recovered" \
        "Missing required fields. Crash dump: $CRASH_FILE. Restored from backup."
    
    log "Configuration restored successfully."
else
    log "✓ Configuration logic valid"
fi

# 第3步：保存为新的 last-known-good
log "Step 3/3: Saving as last-known-good..."
cp "$CONFIG" "$GOOD_BACKUP"
log "✓ Backup updated"

# 启动 inotify 监控（后台运行）
if [ "$GUARD_ENABLED" = "true" ] && [ -f "/usr/local/bin/inotify-watch.sh" ]; then
    log "Starting file system monitor..."
    nohup /usr/local/bin/inotify-watch.sh > /var/log/inotify-watch.log 2>&1 &
    log "✓ File monitor started (PID: $!)"
fi

# 设置 cron 任务（Git 自动提交 + 智能快照）
if [ "$GIT_AUTO_COMMIT" = "true" ]; then
    log "Setting up cron jobs..."
    
    # Git 自动提交（每 N 分钟）
    echo "*/${GIT_COMMIT_INTERVAL:-5} * * * * cd /home/node/.openclaw && git diff --quiet HEAD || (git add -A && git commit -m \"auto: \$(date +\%m\%d-\%H\%M)\")" | crontab -
    
    # 智能快照（每小时）
    echo "0 * * * * /usr/local/bin/smart-snapshot.sh" | crontab -
    
    # 启动 cron
    service cron start || true
    log "✓ Cron jobs configured"
fi

log "=========================================="
log "OpenClaw Guard initialization complete!"
log "=========================================="
log "Starting OpenClaw..."

# 执行原始启动命令
exec "$@"
