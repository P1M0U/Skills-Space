---
name: hermes-health-check
description: "Production-grade comprehensive health check for Hermes Agent — config, deps, API connectivity, system resources, gateway, network, security baseline, cron jobs, log hygiene, platform adapters, and profiles isolation."
version: 2.2.0
platforms: [linux]
metadata:
  hermes:
    tags: [hermes, diagnostics, monitoring, health-check, troubleshooting, production]
    related_skills: [hermes-agent, server-security-check]
---

# Hermes Health Check (Production Edition)

Runs a full production-grade diagnostic on the Hermes Agent installation and host system.
Use this when the user asks to check Hermes health, diagnose issues, verify everything is working,
or as a scheduled watchdog via cronjob.

Supports two modes:
- **Interactive mode** (default) — full 9-phase check with structured human-readable report
- **Watchdog mode** (cron-friendly) — lightweight periodic check that only reports on status changes or failures

## Quick Start

Say "run a health check" or "check Hermes health" and the agent will execute all phases below.

## Health Check Phases

Execute these phases **in order**. Do NOT skip phases even if an earlier one shows issues —
collect everything first, THEN summarize.

---

### Phase 1: Hermes Built-in Diagnostics

Run these three commands. They are fast, safe, and cover the majority of Hermes internals.

```bash
hermes doctor 2>&1
hermes status 2>&1
hermes config check 2>&1
```

Parse output for:
- ✓ / ⚠ / ✗ markers (count each category)
- Security advisories (CRITICAL if any)
- Python environment issues (venv active? version mismatch?)
- Directory structure integrity
- Gateway status (running / stopped)
- Missing **required** vs **optional** API keys (required missing = CRITICAL)

### Phase 2: System Resources (Full Scan)

```bash
# Disk
df -h $HOME 2>&1
df -i $HOME 2>&1           # inode usage (can fill up even with space left)

# Memory
free -h 2>&1
cat /proc/meminfo 2>&1 | grep -E "^(MemTotal|MemAvailable|SwapTotal|SwapFree):"

# CPU
uptime 2>&1                # load averages
nproc 2>&1                 # CPU core count
cat /proc/loadavg 2>&1     # precise load

# Process health
ps aux --sort=-%mem 2>&1 | head -8  # top 5 memory consumers
ps aux --sort=-%cpu 2>&1 | head -8  # top 5 CPU consumers
```

Thresholds for production:
| Metric | WARNING | CRITICAL |
|--------|---------|----------|
| Disk usage | > 80% | > 92% |
| Inode usage | > 80% | > 92% |
| Available memory | < 500MB | < 200MB |
| Swap usage | > 50% | > 80% |
| CPU load (1min / nproc) | > 0.8 | > 1.5 |
| Zombie/defunct processes | >= 1 | >= 5 |

### Phase 3: Gateway Deep Dive

```bash
# Core status
hermes gateway status 2>&1

# Per-platform adapter check — extract connected platforms from status
# Look for: Feishu, QQBot, Telegram, Discord etc. and their check/x status

# Memory & CPU of gateway process
ps -p $(systemctl --user show -P MainPID hermes-gateway 2>/dev/null) -o pid,%mem,%cpu,rss,etime --no-headers 2>&1

# Recent log errors (last 24h)
grep -i "error\|fail\|exception\|traceback\|CRITICAL" ~/.hermes/logs/gateway.log 2>&1 | tail -30

# Reconnect analysis — count per adapter in last hour
grep -i "WebSocket closed\|reconnect\|disconnect" ~/.hermes/logs/gateway.log 2>&1 | tail -50

# Gateway log growth rate (bytes per hour)
stat --format="%s" ~/.hermes/logs/gateway.log 2>/dev/null
```

Check for:
- Gateway running vs stopped (stopped when expected running = CRITICAL)
- Per-platform adapter connectivity (known-good platforms disconnected = WARN)
- Error rate in last 24h (>= 10 errors = WARN, >= 50 = CRITICAL)
- Reconnect frequency (known-bad patterns: QQ 4009 every ~30min = INFO, erratic reconnects = WARN)
- Gateway memory growth (sustained > 1GB = WARN, > 2GB = CRITICAL)
- Log file size (> 500MB = WARN, > 1GB = CRITICAL, suggests no rotation)

### Phase 4: Skills, Memory & Plugin Integrity

```bash
# Skills
ls -d ~/.hermes/skills/*/  2>&1 | wc -l
ls ~/.hermes/skills/*/SKILL.md 2>&1 | wc -l   # skills that have valid SKILL.md

# Check for broken skills (no SKILL.md)
comm -23 <(ls -d ~/.hermes/skills/*/ | sed 's|/$||') <(ls -d ~/.hermes/skills/*/SKILL.md 2>/dev/null | xargs -I{} dirname {})

# Memory files
wc -c ~/.hermes/memories/MEMORY.md ~/.hermes/memories/USER.md 2>&1

# Session DB
hermes sessions stats 2>&1

# Check session DB integrity
sqlite3 ~/.hermes/state.db "PRAGMA integrity_check;" 2>&1

# Cron jobs
hermes cron list 2>&1 || ls ~/.hermes/cron/ 2>&1

# Check for plugins
ls ~/.hermes/plugins/ 2>&1
```

Check for:
- Skills directory count vs valid SKILL.md count (discrepancy = broken skills)
- Memory files non-empty and < 100KB (overgrown memory = WARN)
- Session DB integrity check passes
- Cron job directory non-empty if jobs were scheduled
- Plugin directory status

### Phase 5: API Connectivity Matrix

Test ALL configured model providers, not just the primary one.
Extract available providers from `hermes status` output first.

```bash
# 1. Test DeepSeek API (list models endpoint — doesn't consume tokens)
DEEPSEEK_KEY=$(grep -oP '^DEEPSEEK_API_KEY=\K.*' ~/.hermes/.env 2>/dev/null | head -1)
if [ -n "$DEEPSEEK_KEY" ]; then
  HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" -m 10 \
    -H "Authorization: Bearer ***" \
    https://api.deepseek.com/v1/models 2>&1)
  echo "DeepSeek API: HTTP $HTTP_CODE ($([ "$HTTP_CODE" = "200" ] && echo 'OK' || echo 'FAIL'))"
fi

# 2. Test GitHub API (no auth needed for /zen)
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" -m 10 https://api.github.com/zen 2>&1)
echo "GitHub API: HTTP $HTTP_CODE ($([ "$HTTP_CODE" = "200" ] && echo 'OK' || echo 'FAIL'))"

# 3. Network latency to primary provider
ping -c 2 -W 3 api.deepseek.com 2>&1 | tail -1
```

Only test providers that have keys configured (parse from `hermes status` or `.env`).
Flag:
- HTTP 200-299 -> OK
- HTTP 401/403 -> CREDENTIAL_ERROR (key expired/revoked)
- HTTP 429 -> RATE_LIMITED
- Timeout / connection refused -> NETWORK_ERROR
- Primary model provider failed = CRITICAL
- Secondary provider failed = WARN

If curl-based testing is not possible, fall back to `hermes doctor` connectivity results.

### Phase 6: Network & Security Baseline

Quick security posture — cross-reference with `server-security-check` skill for full scan.

```bash
# Firewall status
sudo ufw status 2>&1 || sudo iptables -L -n --line-numbers 2>&1 | head -20

# Listening ports (unexpected open ports?)
ss -tlnp 2>&1 | grep -v "127.0.0.1\|::1"

# SSH config
ss -tlnp 2>&1 | grep ":22"
cat /etc/ssh/sshd_config 2>/dev/null | grep -E "^(PermitRootLogin|PasswordAuthentication|Port )" | grep -v "^#"

# Failed SSH login attempts (last 24h)
sudo journalctl -u sshd --since "24 hours ago" 2>/dev/null | grep "Failed password" | wc -l

# Check for suspicious crontabs
crontab -l 2>/dev/null
sudo cat /etc/crontab 2>/dev/null
ls -la /etc/cron.d/ 2>/dev/null

# System updates available
which apt-get >/dev/null 2>&1 && apt-get --just-print upgrade 2>&1 | grep -c "upgraded\|installed" | tail -1

# Last system boot
who -b 2>&1
```

Security thresholds:
| Check | WARNING | CRITICAL |
|-------|---------|----------|
| SSH root login enabled | - | Yes |
| Password auth enabled | Yes | - |
| SSH on non-standard port | N/A | - |
| Failed SSH (24h) | > 50 | > 200 |
| Open non-local ports (unexpected) | 1-2 | >= 3 |
| Pending security updates | > 10 | > 30 |
| Firewall inactive | - | Yes |

### Phase 7: Log Hygiene & Storage

```bash
# Log directory size
du -sh ~/.hermes/logs/ 2>&1

# Per-logfile sizes
ls -lh ~/.hermes/logs/ 2>&1

# Session DB size
ls -lh ~/.hermes/state.db 2>&1

# Check for log rotation
ls -la ~/.hermes/logs/*.gz ~/.hermes/logs/*.old ~/.hermes/logs/*.[0-9] 2>&1 | head -5

# Hermes home total size
du -sh ~/.hermes/ 2>&1
```

Thresholds:
| Metric | WARNING | CRITICAL |
|--------|---------|----------|
| gateway.log | > 200MB | > 500MB |
| All logs total | > 500MB | > 1GB |
| Session DB | > 100MB | > 500MB |
| ~/.hermes total | > 2GB | > 5GB |

### Phase 8: Environment & Deployment Info

```bash
# Kernel & arch
uname -a 2>&1

# OS release
cat /etc/os-release 2>&1 | head -5

# Cloud metadata (if on cloud VM)
curl -s -m 2 http://100.100.100.200/latest/meta-data/instance-id 2>&1 || echo "(not Alibaba Cloud)"
curl -s -m 2 http://169.254.169.254/latest/meta-data/instance-id 2>&1 || echo "(not AWS)"

# Python & venv info
which python3 2>&1
python3 --version 2>&1
echo "$VIRTUAL_ENV" 2>&1

# Hermes version
hermes --version 2>&1 || head -1 ~/.hermes/hermes-agent/hermes_cli/__init__.py 2>/dev/null

# Network info
hostname -I 2>&1 | awk '{print $1}'
ip route show default 2>&1 | head -1

# DNS resolution test
nslookup api.deepseek.com 2>&1 | tail -3
```

### Phase 9: Profile Health Check

Check all Hermes profiles (including the default) for integrity, resource usage, and anomalies.

```bash
# List all profiles
ls -d ~/.hermes/profiles/*/ 2>/dev/null | xargs -I{} basename {}

# Default profile location
echo "Default: ~/.hermes/"

# Per-profile disk usage
for d in ~/.hermes/profiles/*/; do
    name=$(basename "$d")
    size=$(du -sh "$d" 2>/dev/null | cut -f1)
    echo "$name: $size"
done

# Per-profile breakdown: config, skills, memories, sessions, logs, home/cache
for d in ~/.hermes/profiles/*/; do
    name=$(basename "$d")
    echo "=== $name ==="
    for sub in skills memories sessions logs home/.cache home/.npm cron; do
        target="$d$sub"
        if [ -d "$target" ] || [ -f "$target" ]; then
            s=$(du -sh "$target" 2>/dev/null | cut -f1)
            echo "  $sub: $s"
        fi
    done
done

# Check for broken skills per profile (no SKILL.md)
for d in ~/.hermes/profiles/*/skills/*/; do
    [ -d "$d" ] || continue
    profile=$(echo "$d" | awk -F/ '{print $(NF-1)}')
    skill=$(basename "$d")
    [ ! -f "$d/SKILL.md" ] && echo "BROKEN: $profile/$skill (no SKILL.md)"
done

# Profile gateway status (if running)
for d in ~/.hermes/profiles/*/; do
    name=$(basename "$d")
    pid_file="$d/../gateway_${name}.pid" 2>/dev/null
    # Check via ps if profile has its own gateway process
    ps aux 2>/dev/null | grep -v grep | grep "hermes.*--profile $name" | head -1
done

# Default profile large directories
du -sh ~/.hermes/state-snapshots/ ~/.hermes/lsp/ ~/.hermes/node/ ~/.hermes/hermes-agent/ 2>/dev/null

# --- Extended checks (v2.2.0 additions) ---

# Per-profile config.yaml validity
for d in ~/.hermes ~/.hermes/profiles/*/; do
    name=$(basename "$d")
    [ "$d" = "$HOME/.hermes/" ] && name="default"
    cfg="$d/config.yaml"
    if [ -f "$cfg" ]; then
        python3 -c "import yaml; yaml.safe_load(open('$cfg'))" 2>/dev/null \
            && echo "$name config.yaml: OK" \
            || echo "$name config.yaml: INVALID YAML"
    else
        echo "$name config.yaml: MISSING"
    fi
done

# Per-profile .env check (non-default profiles)
for d in ~/.hermes/profiles/*/; do
    name=$(basename "$d")
    [ -f "$d/.env" ] && echo "$name .env: OK" || echo "$name .env: MISSING"
done

# Per-profile session DB integrity
for db in ~/.hermes/state.db ~/.hermes/profiles/*/state.db; do
    [ -f "$db" ] || continue
    profile=$(echo "$db" | sed 's|.*/profiles/\([^/]*\)/.*|\1|; s|.*/\.hermes/state\.db|default|')
    size=$(stat --format="%s" "$db" 2>/dev/null)
    echo "$profile session.db: ${size:-?} bytes"
    [ "${size:-0}" -gt 104857600 ] && echo "  ⚠ > 100MB"
    result=$(sqlite3 "$db" "PRAGMA integrity_check;" 2>/dev/null)
    [ "$result" != "ok" ] && echo "  ⚠ Integrity: $result"
done

# Cross-profile isolation: external symlinks
find ~/.hermes/profiles/ -maxdepth 3 -type l 2>/dev/null | while read link; do
    target=$(readlink -f "$link" 2>/dev/null)
    profile=$(echo "$link" | awk -F/ '{print $(NF-2)}')
    if [[ "$target" != "$HOME/.hermes/profiles/"* ]] && [[ "$target" != "/tmp/"* ]]; then
        echo "⚠ $profile external symlink: $link -> $target"
    fi
done

# Per-profile cron jobs
for d in ~/.hermes/profiles/*/; do
    name=$(basename "$d")
    if [ -d "$d/cron/" ]; then
        count=$(ls "$d/cron/" 2>/dev/null | wc -l)
        echo "$name cron: $count jobs"
    fi
done
```

Check for:
- Profiles with excessive disk usage (> 500MB = WARN, > 1GB = CRITICAL)
- Broken skills (missing SKILL.md) per profile
- Profile `home/.cache` and `home/.npm` bloat (safe to clean)
- Profile logs growing unbounded
- Profiles without gateway process when expected running
- Orphaned profiles (no config.yaml or empty)
- config.yaml present and valid YAML per profile (broken config = CRITICAL)
- .env present for non-default profiles (missing = WARN, may use default credentials)
- Session DB integrity per profile ( corruption = CRITICAL)
- External symlinks crossing profile boundaries (isolation violation = WARN)
- Cron jobs present per profile

Thresholds per profile:
| Check | WARNING | CRITICAL |
|-------|---------|----------|
| Disk usage | > 500MB | > 1GB |
| config.yaml missing | - | Yes |
| config.yaml invalid YAML | - | Yes |
| .env missing (non-default) | Yes | - |
| Broken skills (no SKILL.md) | >= 1 | >= 5 |
| home/.cache bloat | > 200MB | > 500MB |
| Session DB > 100MB | Yes | > 500MB |
| External symlinks | >= 1 | - |

---

## Scoring System

Each check produces a numeric score. The overall health is computed as a weighted sum:

| Component | Weight |
|-----------|--------|
| Phase 1 (Hermes core) | 18% |
| Phase 2 (System) | 10% |
| Phase 3 (Gateway) | 22% |
| Phase 4 (Skills/Memory) | 8% |
| Phase 5 (API) | 18% |
| Phase 6 (Security) | 8% |
| Phase 7 (Logs) | 3% |
| Phase 8 (Env) | 2% |
| Phase 9 (Profiles) | 11% |

Each check yields 0 (CRITICAL), 1 (WARN), or 2 (OK). Weighted sum / max possible = health %.

Final severity:
| Score | Severity |
|-------|----------|
| >= 95% | **HEALTHY** ✓ |
| >= 75% | **NEEDS ATTENTION** ⚠ |
| < 75% | **UNHEALTHY** ✗ |
| Any CRITICAL check | Auto-downgrade to UNHEALTHY |

---

## Output Format

After all phases complete, present a structured summary:

```
═══════════════════════════════════════════════════════════════
          HERMES HEALTH CHECK REPORT
          {timestamp}
═══════════════════════════════════════════════════════════════

OVERALL STATUS: {HEALTHY ✓ | NEEDS ATTENTION ⚠ | UNHEALTHY ✗}
SCORE: {score}% ({weighted_points}/{max_points})

───────────────────────────────────────────────────────────────
PHASE 1: HERMES CORE                         [{score}/20]
───────────────────────────────────────────────────────────────
✓ Doctor: {x} passed, {y} warnings, {z} critical
✓ Config: {status}
✓ Gateway: {status}
{list of any issues found}

... (similar for phases 2-8) ...

───────────────────────────────────────────────────────────────
PHASE 9: PROFILES                            [{score}/11]
───────────────────────────────────────────────────────────────
✓ Profiles found: {n} (default + {m} named)
✓ Total profile size: {size}
✓ Broken skills: {n}
✓ Profiles > 500MB: {list or "none"}
✓ config.yaml valid: {n}/{total}
✓ Session DB integrity: {n}/{total} passed
✓ External symlinks: {n or "none"}
{list of any issues found per profile}

───────────────────────────────────────────────────────────────
SUMMARY
───────────────────────────────────────────────────────────────
✓ Healthy: {n} checks
⚠ Warning: {n} checks  
✗ Critical: {n} checks

TOP ISSUES (action items):
1. {issue}
2. {issue}
...
═══════════════════════════════════════════════════════════════
```

---

## Watchdog Mode (Cron Scheduling)

> **时区说明**：系统时区为 **Asia/Shanghai (CST, UTC+8)**，Hermes 直接按北京时间解释 cron 表达式。

### Option A: LLM-driven (default cron)

```bash
hermes cron create --name health-watchdog \
  --schedule "0 */6 * * *" \
  --skill hermes-health-check \
  --prompt "Run a full health check in watchdog mode. Only report if overall status is UNHEALTHY or if any CRITICAL check fails. If HEALTHY or NEEDS ATTENTION, stay silent."
```

⚠️ **CRITICAL**: The `hermes-health-check` SKILL.md is ~450 lines (~25K tokens when loaded). In LLM-driven cron mode, the full skill content is injected into the system prompt, which can cause the API streaming to stall. If you see `[Errno 32] Broken pipe` with `stale_stream_kill` after 180s, the cron job is choking on the oversized context. **For daily scheduled health checks, prefer Option B (no_agent script) — zero tokens, no API dependency, no timeout risk.** If you must use Option A, pare the prompt down to a few lines of self-contained instructions and do NOT pass `--skill hermes-health-check`.

### Option B: no_agent script (lightweight, zero tokens)

Uses a standalone shell script. Two scripts are bundled with this skill:

**`scripts/health_watchdog.sh`** — basic system-level watchdog (disk, memory, malware).

**`scripts/feishu-gateway-watchdog.sh`** — enhanced for Feishu (or any) gateway deployments. Adds gateway service status check and gateway log error counting alongside disk/memory checks.

```bash
# Basic watchdog (any platform)
hermes cron create --name "health-watchdog-quiet" \
  --schedule "*/30 * * * *" \
  --script health_watchdog.sh \
  --no-agent

# Gateway-aware watchdog (Feishu/TG/etc)
hermes cron create --name "gateway-health" \
  --schedule "0 8 * * *" \
  --script feishu-gateway-watchdog.sh \
  --no-agent
```

⚠️ **Writing no_agent scripts is error-prone with `set -euo pipefail`.** See `references/no-agent-script-pitfalls.md` for the traps encountered in production: bare test-and-assign in functions (`[ expr ] && var` → silent exit when false), `grep -c || echo 0` producing two-line values instead of a single number, and empty-pipe edge cases. Always read that reference before authoring or debugging a no_agent script.

### Watchdog behavior
- HEALTHY -> silent (no notification)
- NEEDS ATTENTION -> silent (unless user asked for all reports)
- UNHEALTHY -> full report delivered to configured channel

### ⚠️ Critical Pitfall: Cron delivery when creating from CLI

When using `hermes cron create` via the `cronjob` tool, **if the session is NOT a platform session** (e.g. you're in CLI, or inside another tool like terminal/execute_code), the `deliver` parameter defaults to `"local"` — meaning **no delivery to any external platform**. The job runs silently and nobody sees the results.

**Fix**: Always explicitly pass `deliver` when creating health watchdog cronjobs from CLI:

```python
# If inside a Feishu session, omit deliver to auto-detect:
cronjob(action='create', ..., schedule="0 8 * * *", skills=["hermes-health-check"], prompt="...")

# If NOT inside the target platform (CLI, terminal, another tool), explicit deliver is REQUIRED:
cronjob(action='create', ..., schedule="0 8 * * *", skills=["hermes-health-check"],
        prompt="...", deliver="feishu:oc_acf63dc8b93a11a1d777f535f8844ab4")
```

To find the correct chat_id: check `grep -a "feishu.*chat" ~/.hermes/logs/gateway.log | tail -5` or inspect `gateway_state.json` for the home channel.

See `references/gateway-longevity-assessment.md` for the methodology for checking if a gateway platform can run 7×24 continuously.

---

## Pitfalls & Production Gotchas

### Command Failures
- `hermes chat -q` blocks indefinitely if the model provider is down. Use `timeout 30`.
- `hermes gateway status` calls `systemctl --user`. If DBUS not set, check PID file.
- `ufw status` may be inactive on cloud VMs; fallback to `iptables -L -n`.
- `journalctl` may require sudo. Skip gracefully if unavailable.
- `sqlite3` may not be installed; skip DB integrity check.

### Cron & Large Skills
- **Don't load this skill into LLM-driven cron jobs.** The SKILL.md is ~25K tokens. When loaded via `--skill hermes-health-check`, the cron's system prompt balloons, and the API streaming stalls after 180s → `stale_stream_kill` → `[Errno 32] Broken pipe`. Always prefer **Option B (no_agent script)** for scheduled health checks.
- If you see `Stream stale for 180s` followed by `[Errno 32] Broken pipe` in a cron job, the fix is NOT to increase timeouts — it's to switch to no_agent mode or write a self-contained prompt that doesn't load any skill.

### Platform Differences
- macOS: No `free -h`, use `vm_stat`. No `ss`, use `lsof -i`.
- Alibaba Cloud / Tencent Cloud: Metadata endpoints differ from AWS. Check both.
- Container environments: `systemctl` won't work; check process directly with `ps`.

### Edge Cases
- Gateway log empty if never started — not an error.
- No swap on cloud VMs is normal.
- `.env` file special chars in API keys — use `source ~/.hermes/.env` style.
- `ps` output on Alpine has different flags. Use `ps -o pid,pcpu,pmem,rss,etime`.

### Security
- Do NOT echo full API keys. Always truncate: `sk-8...1873`.
- `iptables -L -n` output can be very long; limit to INPUT/FORWARD.
- Do NOT expose cloud metadata tokens in output.
