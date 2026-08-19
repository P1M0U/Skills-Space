#!/bin/bash
# ═══════════════════════════════════════════════════════════
# Server Security Check — 系统资源检查
# 输出结构化 JSON，由 Agent 分析汇总
# 覆盖：磁盘/Inode、内存/Swap、CPU、OOM、进程
# shellcheck disable=SC2312
set -uo pipefail

NOW=$(date '+%Y-%m-%d %H:%M:%S')
NOW_EPOCH=$(date +%s)
HOSTNAME=$(hostname 2>/dev/null || echo "unknown")

# ── 磁盘 ──
DISK_USED_PCT=$(df / | tail -1 | awk '{print $5}' | sed 's/%//')
DISK_AVAIL=$(df -h / | tail -1 | awk '{print $4}')
DISK_TOTAL=$(df -h / | tail -1 | awk '{print $2}')
INODE_USED_PCT=$(df -i / | tail -1 | awk '{print $5}' | sed 's/%//')

# 磁盘大目录 Top5
DISK_TOP_DIRS=$(du -sh /* 2>/dev/null | sort -rh | head -5 \
    | awk '{printf "{\"dir\":\"%s\",\"size\":\"%s\"},", $2, $1}' | sed 's/,$//')

# ── 内存 ──
MEM_TOTAL_MB=$(free -m | awk '/Mem:/ {print $2}')
MEM_AVAIL_MB=$(free -m | awk '/Mem:/ {print $7}')
MEM_USED_MB=$((MEM_TOTAL_MB - MEM_AVAIL_MB))
SWAP_TOTAL_MB=$(free -m | awk '/Swap:/ {print $2}')
SWAP_USED_MB=$(free -m | awk '/Swap:/ {print $3}')

# ── CPU ──
LOAD_1=$(awk '{print $1}' /proc/loadavg)
LOAD_5=$(awk '{print $2}' /proc/loadavg)
LOAD_15=$(awk '{print $3}' /proc/loadavg)
NPROC=$(nproc 2>/dev/null || echo "1")

# ── OOM Killer ──
OOM_EVENTS=0
if command -v dmesg &>/dev/null; then
    OOM_EVENTS=$(dmesg 2>/dev/null | grep -c "Out of memory" || true)
    : "${OOM_EVENTS:=0}"
elif command -v journalctl &>/dev/null; then
    OOM_EVENTS=$(sudo -n journalctl -k --since "24 hours ago" 2>/dev/null | grep -c "Out of memory" || true)
    : "${OOM_EVENTS:=0}"
fi

# ── 僵尸进程 ──
ZOMBIES=$(ps aux 2>/dev/null | awk '$8~/Z/' | wc -l)

# ── Top 内存进程 ──
TOP_MEM=$(ps aux --sort=-%mem 2>/dev/null | awk 'NR>1 && NR<=6 {printf "{\"pid\":%s,\"user\":\"%s\",\"mem\":\"%s%%\",\"cmd\":\"%s\"},", $2, $1, $4, $11}' | sed 's/,$//')

# ── Top CPU 进程 ──
TOP_CPU=$(ps aux --sort=-%cpu 2>/dev/null | awk 'NR>1 && NR<=6 {printf "{\"pid\":%s,\"user\":\"%s\",\"cpu\":\"%s%%\",\"cmd\":\"%s\"},", $2, $1, $3, $11}' | sed 's/,$//')

# ── 系统运行时间 ──
UPTIME_STR=$(uptime -p 2>/dev/null || echo "unknown")

cat <<EOF
{
  "timestamp": "${NOW}",
  "epoch": ${NOW_EPOCH},
  "hostname": "${HOSTNAME}",
  "category": "system",
  "disk": {
    "used_pct": ${DISK_USED_PCT},
    "avail": "${DISK_AVAIL}",
    "total": "${DISK_TOTAL}",
    "inode_used_pct": ${INODE_USED_PCT},
    "top_dirs": [${DISK_TOP_DIRS}]
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
  "oom": {
    "events": ${OOM_EVENTS}
  },
  "processes": {
    "zombies": ${ZOMBIES},
    "top_mem": [${TOP_MEM}],
    "top_cpu": [${TOP_CPU}]
  },
  "system": {
    "uptime": "${UPTIME_STR}"
  }
}
EOF
