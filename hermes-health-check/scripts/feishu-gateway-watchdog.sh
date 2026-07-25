#!/bin/bash
# Feishu Gateway Watchdog — no_agent cron mode
# Checks gateway health and reports on failures.
# For no_agent cron: script returns non-empty stdout → delivered; exit 0 + no stdout → silent.
# shellcheck disable=SC2312
set -euo pipefail

WARN_DISK_PCT="${WARN_DISK_PCT:-85}"
CRIT_DISK_PCT="${CRIT_DISK_PCT:-92}"
WARN_MEM_MB="${WARN_MEM_MB:-500}"
CRIT_MEM_MB="${CRIT_MEM_MB:-200}"
HERMES_HOME="${HERMES_HOME:-$HOME/.hermes}"

ALERTS=""
NOW=$(date '+%Y-%m-%d %H:%M:%S')

alert() {
    local level="$1"
    local msg="$2"
    ALERTS="${ALERTS}
[${level}] ${msg}"
    # CAUTION: do NOT use a bare test-and-assign ([ expr ] && var=1) here.
    # With set -e, a failed [ test exits the script. Always use if/then.
    if [ "$level" = "CRIT" ]; then
        HAS_ALERT=1
    fi
}

# 1. Gateway status
if systemctl --user is-active hermes-gateway.service &>/dev/null; then
    GATEWAY_OK=1
else
    alert "CRIT" "Gateway service is NOT running"
    GATEWAY_OK=0
fi

# 2. Disk usage
DISK_PCT=$(df / | tail -1 | awk '{print $5}' | sed 's/%//')
if [ "$DISK_PCT" -gt "$CRIT_DISK_PCT" ]; then
    alert "CRIT" "Disk usage ${DISK_PCT}% (threshold: ${CRIT_DISK_PCT}%)"
elif [ "$DISK_PCT" -gt "$WARN_DISK_PCT" ]; then
    alert "WARN" "Disk usage ${DISK_PCT}% (threshold: ${WARN_DISK_PCT}%)"
fi

# 3. Memory
MEM_AVAIL=$(free -m | awk '/Mem:/ {print $7}')
if [ "$MEM_AVAIL" -lt "$CRIT_MEM_MB" ]; then
    alert "CRIT" "Available memory ${MEM_AVAIL}MB (threshold: ${CRIT_MEM_MB}MB)"
elif [ "$MEM_AVAIL" -lt "$WARN_MEM_MB" ]; then
    alert "WARN" "Available memory ${MEM_AVAIL}MB (threshold: ${WARN_MEM_MB}MB)"
fi

# 4. Recent gateway errors (today only — skip old history to avoid false positives)
if [ "$GATEWAY_OK" -eq 1 ]; then
    TODAY=$(date '+%Y-%m-%d')
    # CAUTION: grep -c returns 0 with exit code 1 when no matches.
    # Using || echo 0 produces the string "0\n0". Use || true instead.
    ERRORS_TODAY=$(grep "^${TODAY}" "${HERMES_HOME}/logs/gateway.log" 2>/dev/null \
        | grep -ci "error\|exception\|traceback\|CRITICAL" 2>/dev/null || true)
    # If log file didn't exist or was empty, ERRORS_TODAY is empty string — coerce to 0.
    : "${ERRORS_TODAY:=0}"
    if [ "$ERRORS_TODAY" -gt 20 ]; then
        alert "CRIT" "Gateway: ${ERRORS_TODAY} errors today"
    elif [ "$ERRORS_TODAY" -gt 5 ]; then
        alert "WARN" "Gateway: ${ERRORS_TODAY} errors today"
    fi
fi

# 5. Report if anything is wrong (WARN or CRIT — always report actionable info)
if [ -n "$ALERTS" ]; then
    echo "🔔 Feishu Gateway Watchdog Report - ${NOW}"
    echo ""
    echo -e "$ALERTS" | sed '/^$/d'
    echo ""
    echo "(Gateway: $( [ "$GATEWAY_OK" -eq 1 ] && echo '✅ running' || echo '❌ stopped'))"
    echo "Disk: ${DISK_PCT}% | Memory: ${MEM_AVAIL}MB available"
    exit 0
fi

# Silent on success — no news is good news
exit 0
