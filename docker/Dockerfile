FROM openclaw/openclaw:latest

LABEL maintainer="OpenClaw Guard <guard@openclaw.local>"
LABEL description="Production-grade OpenClaw with 5-layer protection system"

USER root

# 安装系统依赖
RUN apt-get update && apt-get install -y \
    git \
    inotify-tools \
    rsync \
    cron \
    curl \
    python3 \
    python3-pip \
    jq \
    && rm -rf /var/lib/apt/lists/*

# 安装 Python 依赖
RUN pip3 install --no-cache-dir requests

# 创建必要目录
RUN mkdir -p \
    /home/node/openclaw-backups \
    /home/node/.openclaw/auto-backups \
    /usr/local/bin/openclaw-guard

# 复制防护脚本
COPY scripts/entrypoint-guard.sh /usr/local/bin/
COPY scripts/inotify-watch.sh /usr/local/bin/
COPY scripts/smart-snapshot.sh /usr/local/bin/
COPY scripts/openclaw-rollback.sh /usr/local/bin/
COPY scripts/alert.py /usr/local/bin/
COPY config/mcp-safe-config.py /usr/local/bin/

# 设置执行权限
RUN chmod +x /usr/local/bin/*.sh

# 初始化 Git 配置
RUN git config --global user.email "${GIT_USER_EMAIL:-guard@openclaw.local}" && \
    git config --global user.name "${GIT_USER_NAME:-OpenClaw Guard}" && \
    git config --global init.defaultBranch main

# 设置工作目录
WORKDIR /home/node

# 健康检查
HEALTHCHECK --interval=30s --timeout=10s --retries=3 --start-period=60s \
    CMD curl -f ${HEALTH_CHECK_ENDPOINT:-http://localhost:3000/health} || exit 1

# 设置 entrypoint
ENTRYPOINT ["/usr/local/bin/entrypoint-guard.sh"]

# 默认命令（会被原镜像的 CMD 覆盖）
CMD ["node", "server.js"]
