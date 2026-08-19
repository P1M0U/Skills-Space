#!/bin/bash
# ═══════════════════════════════════════════════════════════
# Server Security Check — 安全检查
# 输出结构化 JSON，由 Agent 分析汇总
# 覆盖：防火墙、端口、SSH、暴力破解、恶意进程、用户、SUID、Crontab
# shellcheck disable=SC2312
set -uo pipefail

NOW=$(date '+%Y-%m-%d %H:%M:%S')
NOW_EPOCH=$(date +%s)
HOSTNAME=$(hostname 2>/dev/null || echo "unknown")

# ═══════ 1. 防火墙 ═══════
FW_TYPE="none"
FW_STATUS="inactive"
FW_RULES=""
if command -v ufw &>/dev/null; then
    FW_TYPE="ufw"
    FW_STATUS=$(sudo -n ufw status 2>/dev/null | head -1 | awk '{print $2}' || echo "inactive")
    FW_RULES=$(sudo -n ufw status numbered 2>/dev/null | grep -v "^Status:" | head -20 || true)
elif command -v firewall-cmd &>/dev/null; then
    FW_TYPE="firewalld"
    FW_STATUS=$(firewall-cmd --state 2>/dev/null || echo "inactive")
    FW_RULES=$(firewall-cmd --list-all 2>/dev/null | head -20 || true)
elif command -v iptables &>/dev/null; then
    FW_TYPE="iptables"
    FW_RULES=$(sudo -n iptables -L -n 2>/dev/null | head -20 || true)
    [ -n "$FW_RULES" ] && FW_STATUS="active"
fi

# ═══════ 2. 监听端口 ═══════
EXPOSED_PORTS=""
ALL_PORTS=""
if command -v ss &>/dev/null; then
    ALL_PORTS=$(ss -tlnp 2>/dev/null | awk 'NR>1 {print $4}' || true)
    EXPOSED_PORTS=$(ss -tlnp 2>/dev/null | grep -vE "127\.0\.0\.1|::1:|172\.(17|18)\." | awk 'NR>1 {print $4}' | sed 's/.*://' | sort -un | head -20 | tr '\n' ',' | sed 's/,$//' || true)
fi

# 检查高危端口
CRITICAL_PORTS=""
for port in 3306 6379 2375 9200 27017; do
    if echo "$ALL_PORTS" | grep -q ":${port}"; then
        # 检查是否绑定到 0.0.0.0
        if ss -tlnp 2>/dev/null | grep ":${port}" | grep -q "0.0.0.0"; then
            CRITICAL_PORTS="${CRITICAL_PORTS}${port},"
        fi
    fi
done
CRITICAL_PORTS=$(echo "$CRITICAL_PORTS" | sed 's/,$//')

# ═══════ 3. SSH 配置 ═══════
SSH_PORT="22"
SSH_PERMIT_ROOT=""
SSH_PASSWORD_AUTH=""
SSH_MAX_AUTH=""
SSH_PUBKEY_AUTH=""
SSH_ALLOW_USERS=""

if [ -f /etc/ssh/sshd_config ]; then
    SSH_PORT=$(grep -E "^Port " /etc/ssh/sshd_config 2>/dev/null | awk '{print $2}' | head -1 || echo "22")
    : "${SSH_PORT:=22}"
    SSH_PERMIT_ROOT=$(grep -E "^PermitRootLogin" /etc/ssh/sshd_config 2>/dev/null | awk '{print $2}' | head -1 || echo "not set")
    SSH_PASSWORD_AUTH=$(grep -E "^PasswordAuthentication" /etc/ssh/sshd_config 2>/dev/null | awk '{print $2}' | head -1 || echo "not set")
    SSH_MAX_AUTH=$(grep -E "^MaxAuthTries" /etc/ssh/sshd_config 2>/dev/null | awk '{print $2}' | head -1 || echo "not set")
    SSH_PUBKEY_AUTH=$(grep -E "^PubkeyAuthentication" /etc/ssh/sshd_config 2>/dev/null | awk '{print $2}' | head -1 || echo "not set")
    SSH_ALLOW_USERS=$(grep -E "^AllowUsers" /etc/ssh/sshd_config 2>/dev/null | awk '{print $2}' | head -1 || echo "not set")
fi

# ═══════ 4. SSH 暴力破解（最近24h） ═══════
SSH_FAILS_24H=0
SSH_INVALID_24H=0
SSH_TOP_IPS=""
SSH_UNIT="ssh"
if systemctl list-units --type=service 2>/dev/null | grep -q " sshd\\.service"; then
    SSH_UNIT="sshd"
fi

if command -v journalctl &>/dev/null; then
    SSH_FAILS_24H=$(sudo -n journalctl -u "$SSH_UNIT" --since "24 hours ago" 2>/dev/null | grep -c "Failed password" || true)
    : "${SSH_FAILS_24H:=0}"
    SSH_INVALID_24H=$(sudo -n journalctl -u "$SSH_UNIT" --since "24 hours ago" 2>/dev/null | grep -c "Invalid user" || true)
    : "${SSH_INVALID_24H:=0}"
    if [ "$((SSH_FAILS_24H + SSH_INVALID_24H))" -gt 0 ]; then
        SSH_TOP_IPS=$(sudo -n journalctl -u "$SSH_UNIT" --since "24 hours ago" 2>/dev/null \
            | grep "Failed password" | grep -oP 'from \K[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+' \
            | sort | uniq -c | sort -rn | head -5 \
            | awk '{printf "{\"count\":%s,\"ip\":\"%s\"},", $2, $1}' | sed 's/,$//')
    fi
fi

# fail2ban 状态
F2B_BANNED="0"
F2B_TOTAL="0"
if command -v fail2ban-client &>/dev/null; then
    F2B_BANNED=$(sudo -n fail2ban-client status "$SSH_UNIT" 2>/dev/null | grep -oP "Currently banned:\s+\K[0-9]+" || echo "0")
    F2B_TOTAL=$(sudo -n fail2ban-client status "$SSH_UNIT" 2>/dev/null | grep -oP "Total banned:\s+\K[0-9]+" || echo "0")
fi

# ═══════ 5. 恶意进程 ═══════
MALWARE_LIST=""
MALWARE_PROCS=$(ps aux 2>/dev/null \
    | grep -iE "xmrig|cryptonight|minerd|stratum|kinsing|kdevtmpfsi|pwnrig|masscan|sustes|watchbog|gates|lady|ddgs|kthreaddi|XMrig" \
    | grep -v grep || true)
if [ -n "$MALWARE_PROCS" ]; then
    MALWARE_LIST=$(echo "$MALWARE_PROCS" | awk '{printf "{\"pid\":%s,\"user\":\"%s\",\"cmd\":\"%s\"},", $2, $1, $11}' | sed 's/,$//')
fi

# ═══════ 6. 用户审计 ═══════
UID0_USERS=""
UID0_LIST=$(awk -F: '$3==0 && $1!="root" {print $1}' /etc/passwd 2>/dev/null || true)
if [ -n "$UID0_LIST" ]; then
    UID0_USERS=$(echo "$UID0_LIST" | awk '{printf "\"%s\",", $0}' | sed 's/,$//')
fi

EMPTY_PASS_USERS=""
EMPTY_PASS_LIST=$(awk -F: '($2=="" || $2=="!" || $2=="*") && $1!="root" {print $1}' /etc/shadow 2>/dev/null || true)
if [ -n "$EMPTY_PASS_LIST" ]; then
    EMPTY_PASS_USERS=$(echo "$EMPTY_PASS_LIST" | awk '{printf "\"%s\",", $0}' | sed 's/,$//')
fi

# ═══════ 7. SUID 文件 ═══════
SUID_COUNT=0
SUID_RISKY=""
SUID_FILES=$(find /tmp /dev/shm /var/tmp /home -perm -4000 -type f 2>/dev/null || true)
if [ -n "$SUID_FILES" ]; then
    SUID_RISKY=$(echo "$SUID_FILES" | awk '{printf "\"%s\",", $0}' | sed 's/,$//')
    SUID_COUNT=$(echo "$SUID_FILES" | wc -l)
fi

# ═══════ 8. Crontab 安全 ═══════
USER_CRON=""
if command -v crontab &>/dev/null; then
    USER_CRON=$(crontab -l 2>/dev/null | grep -v "^#" | grep -v "^$" | head -10 || true)
fi
SYS_CRON=$(ls /etc/cron.d/ 2>/dev/null | head -10 || true)

cat <<EOF
{
  "timestamp": "${NOW}",
  "epoch": ${NOW_EPOCH},
  "hostname": "${HOSTNAME}",
  "category": "security",
  "firewall": {
    "type": "${FW_TYPE}",
    "status": "${FW_STATUS}",
    "rules_preview": $(if [ -n "$FW_RULES" ]; then echo "$FW_RULES" | head -5 | awk '{printf "\"%s\",", $0}' | sed 's/,$//' | xargs -I{} echo "[{}]"; else echo "[]"; fi)
  },
  "ports": {
    "exposed": "${EXPOSED_PORTS}",
    "critical_exposed": "${CRITICAL_PORTS}"
  },
  "ssh": {
    "port": "${SSH_PORT}",
    "permit_root": "${SSH_PERMIT_ROOT}",
    "password_auth": "${SSH_PASSWORD_AUTH}",
    "max_auth_tries": "${SSH_MAX_AUTH}",
    "pubkey_auth": "${SSH_PUBKEY_AUTH}",
    "allow_users": "${SSH_ALLOW_USERS}",
    "service": "${SSH_UNIT}"
  },
  "ssh_bruteforce": {
    "fails_24h": ${SSH_FAILS_24H},
    "invalid_24h": ${SSH_INVALID_24H},
    "top_ips": [${SSH_TOP_IPS}],
    "fail2ban_banned": ${F2B_BANNED},
    "fail2ban_total": ${F2B_TOTAL}
  },
  "malware": {
    "detected": $([ -n "$MALWARE_LIST" ] && echo "true" || echo "false"),
    "processes": [${MALWARE_LIST}]
  },
  "users": {
    "non_root_uid0": [${UID0_USERS}],
    "empty_password": [${EMPTY_PASS_USERS}]
  },
  "suid": {
    "count": ${SUID_COUNT},
    "risky_locations": [${SUID_RISKY}]
  },
  "crontab": {
    "user_entries": "$(echo "$USER_CRON" | head -5 | tr '\n' '|' | sed 's/|$//')",
    "system_entries": "$(echo "$SYS_CRON" | tr '\n' '|' | sed 's/|$//')"
  }
}
EOF
