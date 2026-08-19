#!/bin/bash
# Server Security Check — 服务与配置检查
# shellcheck disable=SC2312
set -uo pipefail

NOW=$(date '+%Y-%m-%d %H:%M:%S')
NOW_EPOCH=$(date +%s)
HOSTNAME=$(hostname 2>/dev/null || echo "unknown")

DOCKER_INSTALLED="false"; DOCKER_VERSION=""; DOCKER_TCP_EXPOSED="false"
DOCKER_RUNNING=0; DOCKER_TOTAL=0
if command -v docker &>/dev/null; then
    DOCKER_INSTALLED="true"
    DOCKER_VERSION=$(docker --version 2>/dev/null | awk '{print $3}' | tr -d ',' || echo "unknown")
    DOCKER_TCP=$(ss -tlnp 2>/dev/null | grep ":2375" || true)
    [ -n "$DOCKER_TCP" ] && DOCKER_TCP_EXPOSED="true"
    DOCKER_RUNNING=$(docker ps -q 2>/dev/null | wc -l)
    DOCKER_TOTAL=$(docker ps -aq 2>/dev/null | wc -l)
fi

SERVICES=""
for svc in ssh sshd nginx mysql mariadb redis docker postgresql chrony ntpd auditd; do
    if systemctl list-unit-files 2>/dev/null | grep -q "^${svc}\\.service"; then
        STATUS=$(systemctl is-active "$svc" 2>/dev/null || echo "inactive")
        ENABLED=$(systemctl is-enabled "$svc" 2>/dev/null || echo "disabled")
        SERVICES="${SERVICES}{\"name\":\"${svc}\",\"active\":\"${STATUS}\",\"enabled\":\"${ENABLED}\"},"
    fi
done
SERVICES="[${SERVICES%,}]"

SECURITY_MODULE="none"; SECURITY_STATUS="unknown"
if command -v getenforce &>/dev/null; then
    SECURITY_MODULE="selinux"; SECURITY_STATUS=$(getenforce 2>/dev/null || echo "unknown")
elif command -v aa-status &>/dev/null; then
    SECURITY_MODULE="apparmor"
    SECURITY_STATUS=$(sudo -n aa-status --enabled 2>/dev/null && echo "enforcing" || echo "disabled")
fi

KERNEL_PARAMS=""
for param in net.ipv4.ip_forward net.ipv4.conf.all.accept_redirects net.ipv4.conf.all.send_redirects net.ipv4.conf.all.accept_source_route net.ipv4.tcp_syncookies kernel.randomize_va_space fs.suid_dumpable; do
    case "$param" in
        net.ipv4.ip_forward) expected="0" ;; net.ipv4.conf.all.accept_redirects) expected="0" ;;
        net.ipv4.conf.all.send_redirects) expected="0" ;; net.ipv4.conf.all.accept_source_route) expected="0" ;;
        net.ipv4.tcp_syncookies) expected="1" ;; kernel.randomize_va_space) expected="2" ;; fs.suid_dumpable) expected="0" ;;
    esac
    actual=$(sysctl -n "$param" 2>/dev/null || echo "N/A")
    [ "$actual" = "N/A" ] && continue
    ok=$([ "$actual" = "$expected" ] && echo "true" || echo "false")
    KERNEL_PARAMS="${KERNEL_PARAMS}{\"param\":\"${param}\",\"expected\":\"${expected}\",\"actual\":\"${actual}\",\"ok\":${ok}},"
done
KERNEL_PARAMS="[${KERNEL_PARAMS%,}]"

AUDITD_STATUS="not_installed"
if command -v auditctl &>/dev/null; then
    AUDITD_STATUS=$(systemctl is-active auditd 2>/dev/null || echo "inactive")
fi

cat <<EOF
{
  "timestamp": "${NOW}",
  "epoch": ${NOW_EPOCH},
  "hostname": "${HOSTNAME}",
  "category": "services",
  "docker": {
    "installed": ${DOCKER_INSTALLED},
    "version": "${DOCKER_VERSION}",
    "tcp_2375_exposed": ${DOCKER_TCP_EXPOSED},
    "containers_running": ${DOCKER_RUNNING},
    "containers_total": ${DOCKER_TOTAL}
  },
  "systemd_services": ${SERVICES},
  "security_module": {
    "type": "${SECURITY_MODULE}",
    "status": "${SECURITY_STATUS}"
  },
  "kernel_params": ${KERNEL_PARAMS},
  "auditd": {
    "status": "${AUDITD_STATUS}"
  }
}
EOF
