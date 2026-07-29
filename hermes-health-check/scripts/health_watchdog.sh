#!/bin/bash
# Hermes Health Watchdog — no_agent cron mode
# 极简版：仅检查 Hermes Gateway 状态。
# 系统级检查（磁盘/内存/CPU/安全）由 server-security-check 覆盖。
# Silent on success (exit 0 + no stdout).
# shellcheck disable=SC2312
set -euo pipefail

HERMES_HOME="${HERMES_HOME:-$HOME/.hermes}"
NOW=$(date '+%Y-%m-%d %H:%M:%S')
NOW_EPOCH=$(date +%s)

# ── Collect Hermes-specific metrics ──

# 1. Gateway status
GW_STATUS="unknown"
GW_PID=""
GW_RSS=""
if systemctl --user is-active hermes-gateway.service &>/dev/null; then
    GW_STATUS="running"
    GW_PID=$(systemctl --user show -P MainPID hermes-gateway.service 2>/dev/null || echo "")
    if [ -n "$GW_PID" ] && [ "$GW_PID" != "0" ] && [ -d "/proc/$GW_PID" ]; then
        GW_RSS=$(awk '/VmRSS/{print $2}' /proc/"$GW_PID"/status 2>/dev/null || echo "")
    fi
else
    GW_STATUS="stopped"
fi

# 2. Gateway log errors (today)
TODAY=$(date '+%Y-%m-%d')
ERRORS_TODAY=0
if [ -f "${HERMES_HOME}/logs/gateway.log" ]; then
    ERRORS_TODAY=$(grep "^${TODAY}" "${HERMES_HOME}/logs/gateway.log" 2>/dev/null \
        | grep -ci "error\|exception\|traceback\|CRITICAL" 2>/dev/null || true)
    : "${ERRORS_TODAY:=0}"
fi

# 3. Session DB size
SESSION_DB_SIZE=0
if [ -f "${HERMES_HOME}/state.db" ]; then
    SESSION_DB_SIZE=$(stat --format="%s" "${HERMES_HOME}/state.db" 2>/dev/null || echo "0")
fi

# ── Output only if there are issues ──
HAS_ISSUE=0
[ "$GW_STATUS" != "running" ] && HAS_ISSUE=1
[ "${ERRORS_TODAY}" -gt 20 ] && HAS_ISSUE=1
[ "${SESSION_DB_SIZE}" -gt 104857600 ] && HAS_ISSUE=1   # > 100MB

if [ "$HAS_ISSUE" -eq 1 ]; then
cat <<EOF
{
  "timestamp": "${NOW}",
  "epoch": ${NOW_EPOCH},
  "hermes_home": "${HERMES_HOME}",
  "gateway": {
    "status": "${GW_STATUS}",
    "pid": "${GW_PID}",
    "rss_kb": "${GW_RSS}"
  },
  "gateway_log": {
    "errors_today": ${ERRORS_TODAY}
  },
  "session_db_size_bytes": ${SESSION_DB_SIZE}
}
EOF
else
    exit 0
fi
