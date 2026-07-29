#!/bin/bash
# Feishu Gateway Watchdog — no_agent cron mode
# Hermes Agent 专属健康检查：Gateway 状态 + 日志 + 进程内存。
# 系统级指标（磁盘/内存/CPU/安全）由 server-security-check 覆盖。
# Silent on success (exit 0 + no stdout).
# shellcheck disable=SC2312
set -euo pipefail

HERMES_HOME="${HERMES_HOME:-$HOME/.hermes}"
NOW=$(date '+%Y-%m-%d %H:%M:%S')
NOW_EPOCH=$(date +%s)
TODAY=$(date '+%Y-%m-%d')

# ── Thresholds ──
WARN_LOG_ERRORS="${WARN_LOG_ERRORS:-5}"
CRIT_LOG_ERRORS="${CRIT_LOG_ERRORS:-20}"
WARN_GW_RSS_KB="${WARN_GW_RSS_KB:-1048576}"   # 1GB
CRIT_GW_RSS_KB="${CRIT_GW_RSS_KB:-2097152}"   # 2GB
WARN_LOG_SIZE="${WARN_LOG_SIZE:-209715200}"     # 200MB
CRIT_LOG_SIZE="${CRIT_LOG_SIZE:-524288000}"     # 500MB

# ── Collect Hermes-specific metrics ──

# 1. Gateway status
GW_STATUS="unknown"
GW_PID=""
GW_RSS_KB=""
GW_UPTIME=""
if systemctl --user is-active hermes-gateway.service &>/dev/null; then
    GW_STATUS="running"
    GW_PID=$(systemctl --user show -P MainPID hermes-gateway.service 2>/dev/null || echo "")
    if [ -n "$GW_PID" ] && [ "$GW_PID" != "0" ] && [ -d "/proc/$GW_PID" ]; then
        GW_RSS_KB=$(awk '/VmRSS/{print $2}' /proc/"$GW_PID"/status 2>/dev/null || echo "")
        GW_UPTIME=$(ps -p "$GW_PID" -o etime= 2>/dev/null | xargs || echo "")
    fi
else
    GW_STATUS="stopped"
fi

# 2. Gateway log errors (today)
ERRORS_TODAY=0
WARNINGS_TODAY=0
LOG_SIZE=0
LOG_RECONNECTS=0
if [ -f "${HERMES_HOME}/logs/gateway.log" ]; then
    LOG_SIZE=$(stat --format="%s" "${HERMES_HOME}/logs/gateway.log" 2>/dev/null || echo "0")
    ERRORS_TODAY=$(grep "^${TODAY}" "${HERMES_HOME}/logs/gateway.log" 2>/dev/null \
        | grep -ci "error\|exception\|traceback\|CRITICAL" 2>/dev/null || true)
    : "${ERRORS_TODAY:=0}"
    WARNINGS_TODAY=$(grep "^${TODAY}" "${HERMES_HOME}/logs/gateway.log" 2>/dev/null \
        | grep -ci "warning\|warn" 2>/dev/null || true)
    : "${WARNINGS_TODAY:=0}"
    LOG_RECONNECTS=$(grep "^${TODAY}" "${HERMES_HOME}/logs/gateway.log" 2>/dev/null \
        | grep -ci "reconnect\|WebSocket closed\|disconnect" 2>/dev/null || true)
    : "${LOG_RECONNECTS:=0}"
fi

# 3. Per-platform adapter status (from gateway state JSON)
ADAPTERS=""
if [ -f "${HERMES_HOME}/gateway_state.json" ]; then
    ADAPTERS=$(python3 -c "
import json, sys
try:
    d = json.load(open('${HERMES_HOME}/gateway_state.json'))
    platforms = d.get('platforms', {})
    for name, info in platforms.items():
        state = info.get('state', 'unknown')
        print(f'{{\"name\":\"{name}\",\"state\":\"{state}\"}}', end=',')
except: pass
" 2>/dev/null || echo "")
    ADAPTERS="[${ADAPTERS%,}]"
fi

# 4. Session DB size
SESSION_DB_SIZE=0
if [ -f "${HERMES_HOME}/state.db" ]; then
    SESSION_DB_SIZE=$(stat --format="%s" "${HERMES_HOME}/state.db" 2>/dev/null || echo "0")
fi

# 5. Skills & plugins count
SKILL_COUNT=0
PLUGIN_COUNT=0
if [ -d "${HERMES_HOME}/skills" ]; then
    SKILL_COUNT=$(find "${HERMES_HOME}/skills" -maxdepth 1 -mindepth 1 -type d 2>/dev/null | wc -l)
fi
if [ -d "${HERMES_HOME}/plugins" ]; then
    PLUGIN_COUNT=$(find "${HERMES_HOME}/plugins" -maxdepth 1 -mindepth 1 -type d 2>/dev/null | wc -l)
fi

# ── Build JSON ──
cat <<EOF
{
  "timestamp": "${NOW}",
  "epoch": ${NOW_EPOCH},
  "hermes_home": "${HERMES_HOME}",
  "gateway": {
    "status": "${GW_STATUS}",
    "pid": "${GW_PID}",
    "rss_kb": "${GW_RSS_KB}",
    "uptime": "${GW_UPTIME}"
  },
  "gateway_log": {
    "errors_today": ${ERRORS_TODAY},
    "warnings_today": ${WARNINGS_TODAY},
    "reconnects_today": ${LOG_RECONNECTS},
    "log_size_bytes": ${LOG_SIZE}
  },
  "adapters": ${ADAPTERS},
  "session_db_size_bytes": ${SESSION_DB_SIZE},
  "skills_count": ${SKILL_COUNT},
  "plugins_count": ${PLUGIN_COUNT}
}
EOF
