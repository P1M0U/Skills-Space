#!/bin/bash
# Feishu Gateway Watchdog — no_agent cron mode
# Outputs structured JSON for agent analysis.
# For no_agent cron: non-empty stdout → delivered; empty stdout → silent.
# shellcheck disable=SC2312
set -euo pipefail

HERMES_HOME="${HERMES_HOME:-$HOME/.hermes}"
NOW=$(date '+%Y-%m-%d %H:%M:%S')
NOW_EPOCH=$(date +%s)
TODAY=$(date '+%Y-%m-%d')

# ── Thresholds (override via env) ──
WARN_DISK_PCT="${WARN_DISK_PCT:-85}"
CRIT_DISK_PCT="${CRIT_DISK_PCT:-92}"
WARN_MEM_MB="${WARN_MEM_MB:-500}"
CRIT_MEM_MB="${CRIT_MEM_MB:-200}"
WARN_ERRORS="${WARN_ERRORS:-5}"
CRIT_ERRORS="${CRIT_ERRORS:-20}"

# ── Collect metrics ──

# 1. Gateway status
GATEWAY_STATUS="unknown"
GATEWAY_PID=""
GATEWAY_RSS_KB=""
GATEWAY_UPTIME=""
if systemctl --user is-active hermes-gateway.service &>/dev/null; then
    GATEWAY_STATUS="running"
    GATEWAY_PID=$(systemctl --user show -P MainPID hermes-gateway.service 2>/dev/null || echo "")
    if [ -n "$GATEWAY_PID" ] && [ "$GATEWAY_PID" != "0" ] && [ -d "/proc/$GATEWAY_PID" ]; then
        GATEWAY_RSS_KB=$(awk '/VmRSS/{print $2}' /proc/"$GATEWAY_PID"/status 2>/dev/null || echo "")
        GATEWAY_UPTIME=$(ps -p "$GATEWAY_PID" -o etime= 2>/dev/null | xargs || echo "")
    fi
else
    GATEWAY_STATUS="stopped"
fi

# 2. Disk usage
DISK_USED_PCT=$(df / | tail -1 | awk '{print $5}' | sed 's/%//')
DISK_AVAIL=$(df -h / | tail -1 | awk '{print $4}')
DISK_TOTAL=$(df -h / | tail -1 | awk '{print $2}')

# 3. Inode usage
INODE_USED_PCT=$(df -i / | tail -1 | awk '{print $5}' | sed 's/%//')

# 4. Memory
MEM_TOTAL_MB=$(free -m | awk '/Mem:/ {print $2}')
MEM_AVAIL_MB=$(free -m | awk '/Mem:/ {print $7}')
MEM_USED_MB=$((MEM_TOTAL_MB - MEM_AVAIL_MB))
SWAP_TOTAL_MB=$(free -m | awk '/Swap:/ {print $2}')
SWAP_USED_MB=$(free -m | awk '/Swap:/ {print $3}')

# 5. CPU load
LOAD_1=$(awk '{print $1}' /proc/loadavg)
LOAD_5=$(awk '{print $2}' /proc/loadavg)
LOAD_15=$(awk '{print $3}' /proc/loadavg)
NPROC=$(nproc 2>/dev/null || echo "1")

# 6. Gateway log errors (today)
ERRORS_TODAY=0
WARNINGS_TODAY=0
LOG_SIZE=""
if [ -f "${HERMES_HOME}/logs/gateway.log" ]; then
    LOG_SIZE=$(stat --format="%s" "${HERMES_HOME}/logs/gateway.log" 2>/dev/null || echo "0")
    ERRORS_TODAY=$(grep "^${TODAY}" "${HERMES_HOME}/logs/gateway.log" 2>/dev/null \
        | grep -ci "error\|exception\|traceback\|CRITICAL" 2>/dev/null || true)
    : "${ERRORS_TODAY:=0}"
    WARNINGS_TODAY=$(grep "^${TODAY}" "${HERMES_HOME}/logs/gateway.log" 2>/dev/null \
        | grep -ci "warning\|warn" 2>/dev/null || true)
    : "${WARNINGS_TODAY:=0}"
fi

# 7. Top memory consumers (top 3)
TOP_MEM=$(ps aux --sort=-%mem 2>/dev/null | awk 'NR>1 && NR<=4 {printf "%s(%s%%) ", $11, $4}' || echo "")

# 8. Uptime
UPTIME_STR=$(uptime -p 2>/dev/null || uptime | sed 's/.*up /up /' | sed 's/,.*load.*//')

# ── Build JSON output ──
# Always output JSON (agent analyzes severity; script only collects)

cat <<EOF
{
  "timestamp": "${NOW}",
  "epoch": ${NOW_EPOCH},
  "hermes_home": "${HERMES_HOME}",
  "gateway": {
    "status": "${GATEWAY_STATUS}",
    "pid": "${GATEWAY_PID}",
    "rss_kb": "${GATEWAY_RSS_KB}",
    "uptime": "${GATEWAY_UPTIME}"
  },
  "disk": {
    "used_pct": ${DISK_USED_PCT},
    "avail": "${DISK_AVAIL}",
    "total": "${DISK_TOTAL}",
    "inode_used_pct": ${INODE_USED_PCT}
  },
  "memory": {
    "total_mb": ${MEM_TOTAL_MB},
    "used_mb": ${MEM_USED_MB},
    "avail_mb": ${MEM_AVAIL_MB},
    "swap_total_mb": ${SWAP_TOTAL_MB},
    "swap_used_mb": ${SWAP_USED_MB}
  },
  "cpu": {
    "load_1m": ${LOAD_1},
    "load_5m": ${LOAD_5},
    "load_15m": ${LOAD_15},
    "cores": ${NPROC}
  },
  "gateway_log": {
    "errors_today": ${ERRORS_TODAY},
    "warnings_today": ${WARNINGS_TODAY},
    "log_size_bytes": ${LOG_SIZE:-0}
  },
  "system": {
    "uptime": "${UPTIME_STR}",
    "top_mem": "${TOP_MEM}"
  }
}
EOF
