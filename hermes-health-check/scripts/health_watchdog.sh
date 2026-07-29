#!/bin/bash
# Hermes Health Watchdog — no_agent cron mode
# Outputs structured JSON for agent analysis.
# Silent on success (empty stdout), JSON on any issue.
# shellcheck disable=SC2312
set -euo pipefail

HERMES_HOME="${HERMES_HOME:-$HOME/.hermes}"
NOW=$(date '+%Y-%m-%d %H:%M:%S')
NOW_EPOCH=$(date +%s)

# ── Thresholds ──
WARN_DISK_PCT="${WARN_DISK_PCT:-85}"
CRIT_DISK_PCT="${CRIT_DISK_PCT:-92}"
WARN_MEM_MB="${WARN_MEM_MB:-500}"
CRIT_MEM_MB="${CRIT_MEM_MB:-200}"

# ── Collect metrics ──

# 1. Disk
DISK_USED_PCT=$(df / | tail -1 | awk '{print $5}' | sed 's/%//')
DISK_AVAIL=$(df -h / | tail -1 | awk '{print $4}')

# 2. Inode
INODE_USED_PCT=$(df -i / | tail -1 | awk '{print $5}' | sed 's/%//')

# 3. Memory
MEM_TOTAL_MB=$(free -m | awk '/Mem:/ {print $2}')
MEM_AVAIL_MB=$(free -m | awk '/Mem:/ {print $7}')
MEM_USED_MB=$((MEM_TOTAL_MB - MEM_AVAIL_MB))

# 4. Swap
SWAP_TOTAL_MB=$(free -m | awk '/Swap:/ {print $2}')
SWAP_USED_MB=$(free -m | awk '/Swap:/ {print $3}')

# 5. CPU
LOAD_1=$(awk '{print $1}' /proc/loadavg)
NPROC=$(nproc 2>/dev/null || echo "1")

# 6. Zombie processes
ZOMBIES=$(ps aux 2>/dev/null | awk '$8~/Z/' | wc -l)

# 7. Malware scan
MALWARE=""
MALWARE_PROCS=$(ps aux 2>/dev/null | grep -iE "xmrig|cryptonight|minerd|kinsing|kdevtmpfsi|kworkerds" | grep -v grep || true)
if [ -n "$MALWARE_PROCS" ]; then
    MALWARE=$(echo "$MALWARE_PROCS" | awk '{print $11}' | tr '\n' ',' | sed 's/,$//')
fi

# 8. Hermes gateway process
GW_STATUS="unknown"
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

# ── Determine if we need to report ──
HAS_ISSUE=0
[ "$DISK_USED_PCT" -gt "$WARN_DISK_PCT" ] && HAS_ISSUE=1
[ "$MEM_AVAIL_MB" -lt "$WARN_MEM_MB" ] && HAS_ISSUE=1
[ -n "$MALWARE" ] && HAS_ISSUE=1
[ "$GW_STATUS" != "running" ] && HAS_ISSUE=1
[ "$ZOMBIES" -gt 0 ] && HAS_ISSUE=1

# ── Output JSON only if there are issues ──
if [ "$HAS_ISSUE" -eq 1 ]; then
cat <<EOF
{
  "timestamp": "${NOW}",
  "epoch": ${NOW_EPOCH},
  "hermes_home": "${HERMES_HOME}",
  "disk": {
    "used_pct": ${DISK_USED_PCT},
    "avail": "${DISK_AVAIL}",
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
    "cores": ${NPROC}
  },
  "processes": {
    "zombies": ${ZOMBIES},
    "malware": "${MALWARE:-none}"
  },
  "gateway": {
    "status": "${GW_STATUS}",
    "rss_kb": "${GW_RSS:-}"
  }
}
EOF
else
    # Silent on success
    exit 0
fi
