#!/bin/bash
# Hermes Health Watchdog — no_agent cron mode
# NOTE: Uses if/then, not bare [ expr ] && var syntax.
# With set -euo pipefail, a bare false test exits the script.
set -euo pipefail

WARN_DISK_PCT="${WARN_DISK_PCT:-85}"
CRIT_DISK_PCT="${CRIT_DISK_PCT:-92}"
WARN_MEM_MB="${WARN_MEM_MB:-500}"
CRIT_MEM_MB="${CRIT_MEM_MB:-200}"
HERMES_HOME="${HERMES_HOME:-$HOME/.hermes}"

ALERTS=""
HAS_ALERT=0
NOW=$(date '+%Y-%m-%d %H:%M:%S')

alert() {
    local level="$1"
    local msg="$2"
    ALERTS="${ALERTS}
[${level}] ${msg}"
    if [ "$level" = "CRIT" ]; then
        HAS_ALERT=1
    fi
}

DISK_PCT=$(df / | tail -1 | awk '{print $5}' | sed 's/%//')
if [ "$DISK_PCT" -gt "$CRIT_DISK_PCT" ]; then
    alert "CRIT" "Disk ${DISK_PCT}%"
elif [ "$DISK_PCT" -gt "$WARN_DISK_PCT" ] && [ "$HAS_ALERT" -eq 0 ]; then
    alert "WARN" "Disk ${DISK_PCT}%"
fi

MEM_AVAIL=$(free -m | awk '/Mem:/ {print $7}')
if [ "$MEM_AVAIL" -lt "$CRIT_MEM_MB" ]; then
    alert "CRIT" "Memory ${MEM_AVAIL}MB"
elif [ "$MEM_AVAIL" -lt "$WARN_MEM_MB" ] && [ "$HAS_ALERT" -eq 0 ]; then
    alert "WARN" "Memory ${MEM_AVAIL}MB"
fi

MALWARE=$(ps aux 2>/dev/null | grep -iE "xmrig|cryptonight|minerd|kinsing|kdevtmpfsi" | grep -v grep || true)
if [ -n "$MALWARE" ]; then
    alert "CRIT" "Malware process detected!"
fi

if [ "$HAS_ALERT" -eq 1 ]; then
    echo "🚨 Hermes Watchdog Alert - ${NOW}"
    echo -e "$ALERTS"
else
    exit 0
fi
