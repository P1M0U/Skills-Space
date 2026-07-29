#!/bin/bash
# ═══════════════════════════════════════════════════════════
# Server Security Watchdog — no_agent cron mode
# Outputs structured JSON for agent analysis.
# Silent on success (empty stdout), JSON when issues detected.
# shellcheck disable=SC2312
# ═══════════════════════════════════════════════════════════
set -euo pipefail

NOW=$(date '+%Y-%m-%d %H:%M:%S')
NOW_EPOCH=$(date +%s)
TODAY=$(date '+%Y-%m-%d')
HOSTNAME=$(hostname 2>/dev/null || echo "unknown")

# ── Thresholds ──
CRIT_DISK_PCT="${CRIT_DISK_PCT:-92}"
CRIT_MEM_MB="${CRIT_MEM_MB:-200}"
SSH_FAIL_THRESHOLD="${SSH_FAIL_THRESHOLD:-50}"

# ── Detect SSH service name (Ubuntu=ssh, CentOS=sshd) ──
SSH_UNIT="ssh"
if systemctl list-units --type=service 2>/dev/null | grep -q " sshd\\.service"; then
    SSH_UNIT="sshd"
fi

# ── Collect metrics ──

# 1. SSH brute force (last 30 min)
SSH_FAILS=0
SSH_INVALID=0
SSH_TOP_IPS=""
SSH_TOP_USERS=""
FAIL2BAN_BANNED="0"
FAIL2BAN_TOTAL="0"
if command -v journalctl &>/dev/null; then
    SSH_FAILS=$(sudo -n journalctl -u "$SSH_UNIT" --since "30 min ago" 2>/dev/null | grep -c "Failed password" || true)
    : "${SSH_FAILS:=0}"
    SSH_INVALID=$(sudo -n journalctl -u "$SSH_UNIT" --since "30 min ago" 2>/dev/null | grep -c "Invalid user" || true)
    : "${SSH_INVALID:=0}"
    if [ "$((SSH_FAILS + SSH_INVALID))" -gt 0 ]; then
        SSH_TOP_IPS=$(sudo -n journalctl -u "$SSH_UNIT" --since "30 min ago" 2>/dev/null \
            | grep "Failed password" | grep -oP 'from \K[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+' \
            | sort | uniq -c | sort -rn | head -5 \
            | awk '{printf "{\"count\":%s,\"ip\":\"%s\"},", $2, $1}' | sed 's/,$//')
        SSH_TOP_USERS=$(sudo -n journalctl -u "$SSH_UNIT" --since "30 min ago" 2>/dev/null \
            | grep "Failed password" | grep -oP '(for|for invalid user) \K\S+' \
            | sort | uniq -c | sort -rn | head -5 \
            | awk '{printf "{\"count\":%s,\"user\":\"%s\"},", $2, $1}' | sed 's/,$//')
    fi
    if command -v fail2ban-client &>/dev/null; then
        FAIL2BAN_BANNED=$(sudo -n fail2ban-client status "$SSH_UNIT" 2>/dev/null | grep -oP "Currently banned:\s+\K[0-9]+" || echo "0")
        FAIL2BAN_TOTAL=$(sudo -n fail2ban-client status "$SSH_UNIT" 2>/dev/null | grep -oP "Total banned:\s+\K[0-9]+" || echo "0")
    fi
fi
SSH_TOTAL=$((SSH_FAILS + SSH_INVALID))

# 2. Malware scan
MALWARE_LIST=""
MALWARE_PROCS=$(ps aux 2>/dev/null \
    | grep -iE "xmrig|cryptonight|minerd|stratum|kinsing|kdevtmpfsi|pwnrig|masscan|sustes|watchbog|gates|lady|ddgs|kthreaddi|ld-linux|XMrig" \
    | grep -v grep || true)
if [ -n "$MALWARE_PROCS" ]; then
    MALWARE_LIST=$(echo "$MALWARE_PROCS" | awk '{printf "{\"pid\":%s,\"user\":\"%s\",\"cmd\":\"%s\"},", $2, $1, $11}' | sed 's/,$//')
fi

# 3. Disk
DISK_USED_PCT=$(df / | tail -1 | awk '{print $5}' | sed 's/%//')
DISK_AVAIL=$(df -h / | tail -1 | awk '{print $4}')
DISK_TOP_DIRS=""
if [ "$DISK_USED_PCT" -gt "$CRIT_DISK_PCT" ]; then
    DISK_TOP_DIRS=$(du -sh /* 2>/dev/null | sort -rh | head -5 \
        | awk '{printf "{\"dir\":\"%s\",\"size\":\"%s\"},", $2, $1}' | sed 's/,$//')
fi

# 4. Inode
INODE_USED_PCT=$(df -i / | tail -1 | awk '{print $5}' | sed 's/%//')

# 5. Memory
MEM_TOTAL_MB=$(free -m | awk '/Mem:/ {print $2}')
MEM_AVAIL_MB=$(free -m | awk '/Mem:/ {print $7}')
MEM_USED_MB=$((MEM_TOTAL_MB - MEM_AVAIL_MB))

# 6. OOM Killer
OOM_EVENTS=0
if command -v dmesg &>/dev/null; then
    OOM_EVENTS=$(dmesg 2>/dev/null | grep -c "Out of memory" || true)
    : "${OOM_EVENTS:=0}"
elif command -v journalctl &>/dev/null; then
    OOM_EVENTS=$(sudo -n journalctl -k --since "24 hours ago" 2>/dev/null | grep -c "Out of memory" || true)
    : "${OOM_EVENTS:=0}"
fi

# 7. Malicious SUID files
BAD_SUID=""
SUID_FILES=$(find /tmp /dev/shm /var/tmp -perm -4000 -type f 2>/dev/null || true)
if [ -n "$SUID_FILES" ]; then
    BAD_SUID=$(echo "$SUID_FILES" | awk '{printf "\"%s\",", $0}' | sed 's/,$//')
fi

# 8. Docker TCP exposure
DOCKER_EXPOSED="false"
if command -v docker &>/dev/null; then
    DOCKER_CHECK=$(ss -tlnp 2>/dev/null | grep ":2375" || true)
    if [ -n "$DOCKER_CHECK" ]; then
        DOCKER_EXPOSED="true"
    fi
fi

# 9. Gateway status
GW_STATUS="unknown"
if systemctl --user is-active hermes-gateway.service &>/dev/null; then
    GW_STATUS="running"
else
    GW_STATUS="stopped"
fi

# 10. Open ports (non-local)
OPEN_PORTS=""
OPEN_PORTS_RAW=$(ss -tlnp 2>/dev/null | grep -v "127.0.0.1\|::1" | awk 'NR>1 {print $4}' | sed 's/.*://' | sort -un | head -20)
if [ -n "$OPEN_PORTS_RAW" ]; then
    OPEN_PORTS=$(echo "$OPEN_PORTS_RAW" | awk '{printf "%s,", $1}' | sed 's/,$//')
fi

# 11. Failed SSH today (for summary)
SSH_FAILS_TODAY=0
if command -v journalctl &>/dev/null; then
    SSH_FAILS_TODAY=$(sudo -n journalctl -u "$SSH_UNIT" --since "today 00:00" 2>/dev/null | grep -c "Failed password" || true)
    : "${SSH_FAILS_TODAY:=0}"
fi

# ── Build JSON ──
cat <<EOF
{
  "timestamp": "${NOW}",
  "epoch": ${NOW_EPOCH},
  "hostname": "${HOSTNAME}",
  "ssh": {
    "service": "${SSH_UNIT}",
    "fails_30min": ${SSH_FAILS},
    "invalid_30min": ${SSH_INVALID},
    "total_30min": ${SSH_TOTAL},
    "fails_today": ${SSH_FAILS_TODAY},
    "top_ips": [${SSH_TOP_IPS}],
    "top_users": [${SSH_TOP_USERS}],
    "fail2ban_banned": ${FAIL2BAN_BANNED},
    "fail2ban_total": ${FAIL2BAN_TOTAL}
  },
  "malware": {
    "detected": $([ -n "$MALWARE_LIST" ] && echo "true" || echo "false"),
    "processes": [${MALWARE_LIST}]
  },
  "disk": {
    "used_pct": ${DISK_USED_PCT},
    "avail": "${DISK_AVAIL}",
    "inode_used_pct": ${INODE_USED_PCT},
    "top_dirs": [${DISK_TOP_DIRS}]
  },
  "memory": {
    "total_mb": ${MEM_TOTAL_MB},
    "used_mb": ${MEM_USED_MB},
    "avail_mb": ${MEM_AVAIL_MB}
  },
  "oom": {
    "events": ${OOM_EVENTS}
  },
  "suid": {
    "malicious": $([ -n "$BAD_SUID" ] && echo "true" || echo "false"),
    "files": [${BAD_SUID}]
  },
  "docker": {
    "tcp_2375_exposed": ${DOCKER_EXPOSED}
  },
  "gateway": {
    "status": "${GW_STATUS}"
  },
  "network": {
    "open_ports": "${OPEN_PORTS}"
  }
}
EOF
