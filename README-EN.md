# 🛠️ Skills Space

Production-grade Hermes Agent skills repository — maintained by [P1M0U](https://gitee.com/P1M0U).

> [中文版本](./README.md)

---

## 📦 Skills Directory

| Skill | Version | Description |
|-------|---------|-------------|
| [🤖 hermes-health-check](./hermes-health-check/) | v2.2.1 | Production-grade Hermes Agent health check — 9-phase diagnostics, weighted scoring, watchdog cron monitoring |
| [🛡️ server-security-check](./server-security-check/) | v2.6.1 | Production-grade server security audit — 20 CIS-aligned checks, SSH hardening, malware scan, Docker security, TLS certificate check |
| [🔒 ssh-bruteforce-guard](./ssh-bruteforce-guard/) | v1.0.0 | SSH brute-force auto-ban monitoring — detect IPs exceeding threshold, auto-ban via fail2ban and ufw |
| [🌟 weekly-oss-recommend](./weekly-oss-recommend/) | v1.0.0 | Weekly open source project recommendations — covering Python AI Agent, Go, Vue3 and more |
| [🔧 git-collab-workflow](./git-collab-workflow/) | v1.3.0 | Standardized Git collaboration workflow — branch management, code checks, Conventional Commits, PR creation, branch cleanup |
| [🔍 pr-review](./pr-review/) | v1.1.0 | PR code review — 8-dimension evaluation, batch strategy, scoring, never merge |

---

## 🤖 hermes-health-check

**Production-grade Hermes Agent health check** — 9-phase diagnostics + weighted scoring:

- **Phase 1:** Hermes Core Diagnostics (doctor / status / config check)
- **Phase 2:** System Resources (disk, inode, memory, CPU load, process health)
- **Phase 3:** Gateway Deep Dive (adapter health, reconnect patterns, memory growth)
- **Phase 4:** Skills & Memory Integrity (skill validation, session DB integrity)
- **Phase 5:** API Connectivity Matrix (multi-provider test, network latency)
- **Phase 6:** Security Baseline (firewall, SSH config, brute force detection, crontab audit)
- **Phase 7:** Log Hygiene (log size, rotation, storage usage)
- **Phase 8:** Environment Info (kernel, cloud platform, DNS, network)
- **Phase 9:** Profiles Integrity (config validation, session DB integrity, cross-profile isolation, cache bloat)

### Quick Start

```bash
# Interactive check (inside Hermes session — say "health check")

# Scheduled Watchdog (every 6 hours, LLM-driven)
hermes cron create --name health-watchdog \
  --schedule "0 */6 * * *" \
  --skill hermes-health-check \
  --prompt "Run full health check. Only report if UNHEALTHY."

# Lightweight script (every 30 min, zero token cost)
hermes cron create --name health-watchdog-quiet \
  --schedule "*/30 * * * *" \
  --script health_watchdog.sh \
  --no-agent
```

---

## 🛡️ server-security-check

**Production-grade server security audit** covering **20 inspection domains**:

| Phase | Check | Severity |
|-------|-------|----------|
| 1 | Firewall Status (UFW / iptables / nftables) | 🔴 CRITICAL |
| 2 | Listening Port Audit (exposed services) | 🟠 WARN |
| 3 | SSH Hardening (7 CIS baselines + socket activation) | 🔴 CRITICAL |
| 4 | SSH Brute Force Detection (Top 10 IP + fail2ban) | 🔴 CRITICAL |
| 5 | Malware & Rootkit Scan | 🔴 CRITICAL |
| 6 | User Account Audit (UID 0, empty passwords, sudo) | 🔴 CRITICAL |
| 7 | SUID/SGID Privilege Escalation Detection | 🔴 CRITICAL |
| 8 | Crontab Security Check | 🔴 CRITICAL |
| 9 | Systemd Service Health | 🟠 WARN |
| 10 | Docker Security Check | 🔴 CRITICAL |
| 11 | SELinux / AppArmor Status | 🟠 WARN |
| 12 | Kernel Parameter Hardening (8 CIS) | 🟠 WARN |
| 13 | Disk & Inode | 🟠 WARN |
| 14 | Memory & Swap | 🟠 WARN |
| 15 | Recent Logins & Auth Logs | ℹ️ INFO |
| 16 | SSH Authorized Keys Audit | 🟠 WARN |
| 17 | System Updates Status | 🟠 WARN |
| 18 | Auditd Status | ℹ️ INFO |
| 19 | **TLS Certificate Expiry** *(v2.6.1)* | 🟠 WARN |
| 20 | **Auto-Update Configuration** *(v2.6.1)* | ℹ️ INFO |

### Quick Start

```bash
# Interactive check (inside Hermes session — say "security check")

# Scheduled full check (daily at 10:00/22:00)
hermes cron create --name "full-security-check" \
  --schedule "0 10,22 * * *" \
  --skill server-security-check \
  --prompt "Run full security health check. Alert if any CRITICAL item or score below 70."
```

---

## 🔒 ssh-bruteforce-guard

**SSH brute-force auto-ban monitoring**:

- Analyze /var/log/auth.log for failed login attempts
- Count attacks per IP in the last hour
- Auto-ban IPs exceeding threshold (default 30/hour) via fail2ban and ufw
- Detailed ban logging

### Quick Start

```bash
# Manual run
sudo ~/.hermes/scripts/ssh-guard/monitor.sh

# Scheduled (every hour)
hermes cron create --name "SSH brute-force monitor" \
  --schedule "0 * * * *" \
  --script ssh-guard/monitor.sh \
  --no-agent
```

---

## 🌟 weekly-oss-recommend

**Weekly open source project recommendations** — 5 tech directions, 28 search keywords:

- Python AI Agent (9 keywords)
- Python Others (3 keywords)
- Go Language (8 keywords)
- Vue3 Frontend (5 keywords)
- Mainstream Frameworks (3 keywords)

### Quick Start

```bash
# Weekly recommendation (Saturday + Sunday 10:00 AM, deliver to Feishu)
hermes cron create --name "weekly-oss-recommend" \
  --schedule "0 2 * * 6" \
  --skill weekly-oss-recommend \
  --prompt "推荐一个优秀开源项目" \
  --deliver "feishu:oc_92c9b46accd79149769c935fed40c9a4"
```

---

## 🚀 Deployment Guide

### Option 1: One-click install (recommended)

Tell your Hermes Agent:

> Please install the hermes-health-check skill from the Skills-Space repo

### Option 2: Manual install

```bash
# Clone the repo
git clone https://gitee.com/P1M0U/Skills-Space.git /tmp/Skills-Space

# Install skills
cp -r /tmp/Skills-Space/hermes-health-check ~/.hermes/skills/
cp -r /tmp/Skills-Space/server-security-check ~/.hermes/skills/

# Cleanup
rm -rf /tmp/Skills-Space
```

---

## 📄 License

[MIT](./LICENSE) — Copyright (c) 2026 P1M0U
