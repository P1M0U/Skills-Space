# Gateway 7×24 Longevity Assessment

Systematic methodology for checking whether a gateway platform (e.g. Feishu, Telegram, Discord) is configured to run continuously without human intervention.

## Phase 1: Current State

```bash
# Gateway state JSON
cat ~/.hermes/gateway_state.json

# Process check
ps aux | grep -E 'hermes.*gateway|gateway' | grep -v grep

# systemd service status
systemctl --user status hermes-gateway.service
```

## Phase 2: Auto-Recovery Mechanism

Check that the gateway runs under systemd with `Restart=always`:

```bash
cat ~/.config/systemd/user/hermes-gateway.service
```

Key fields to verify:
- `Restart=always` — auto-restart on crash
- `RestartSec=5` — quick recovery (not 30+ seconds)
- `TimeoutStopSec=210` — enough time for agent drain
- `KillSignal=SIGTERM` — graceful shutdown, not SIGKILL
- `ExecReload=/bin/kill -USR1 $MAINPID` — hot reload support

## Phase 3: Resource Analysis

```bash
# Gateway process memory/CPU
ps -p $(systemctl --user show -P MainPID hermes-gateway 2>/dev/null) -o pid,%mem,%cpu,rss,etime --no-headers

# System memory headroom
free -h

# File descriptor limits
ulimit -n

# Process limits
ulimit -u
```

**Watch for:**
- Memory growing monotonically (>10% per hour for hours = probable leak)
- Peak vs current memory gap (small gap = stable; large gap = maybe not)
- RSS > 1GB on a system with < 2GB free = risk

## Phase 4: Log Analysis — Distinguish Planned Restarts from Crashes

The gateway logs explicitly mark planned restarts:

```bash
# Planned restarts (NOT crashes)
grep -a "Stopping gateway for restart" ~/.hermes/logs/gateway.log

# Actual errors
grep -a -i "ERROR\|CRITICAL\|Traceback\|exception" ~/.hermes/logs/gateway.log | grep -v "WARNING"

# Feishu disconnection events (all are planned if preceded by "Stopping gateway")
grep -a "feishu.*Disconnect" ~/.hermes/logs/gateway.log
```

**Key insight**: Every "feishu.*Disconnected" log entry that follows a "Stopping gateway for restart" is **planned**, not a crash. Only count unplanned disconnects (those NOT preceded by a stop signal within 5 seconds) as incidents.

## Phase 5: WSL/Host Stability (WSL-specific)

```bash
# WSL uptime
uptime

# WSL config
cat /etc/wsl.conf

# Windows-side config
cat /mnt/c/Users/*/.wslconfig 2>/dev/null

# OOM history
dmesg 2>/dev/null | grep -i -E 'oom|killed|out of memory'
```

**WSL risk factors:**
- No `.wslconfig` = default memory limit (50% of Windows RAM), no swap config
- `systemd=true` in wsl.conf is REQUIRED for systemd user services
- Ubuntu-24.04 recommended over 22.04 for better systemd support
- Windows reboot = WSL shutdown = gateway stops. systemd `Restart=always` picks it up on next WSL boot but won't auto-start WSL.

## Phase 6: Calculating Longest Continuous Uptime

```bash
# Extract all start/stop pairs
python3 << 'PYEOF'
import re
with open('/home/pimou/.hermes/logs/gateway.log', 'rb') as f:
    text = f.read().decode('utf-8', errors='replace')

starts = [m.start() for m in re.finditer(r'Gateway running with \d+ platform', text)]
stops = [m.start() for m in re.finditer(r'Gateway stopped', text)]

# Extract timestamps
import datetime
ts_pattern = re.compile(r'(\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2})')

def get_ts(text, pos):
    before = text[max(0,pos-30):pos]
    m = ts_pattern.search(before)
    return datetime.datetime.fromisoformat(m.group(1)) if m else None

for s, e in zip(starts, stops):
    start = get_ts(text, s)
    end = get_ts(text, e)
    if start and end:
        delta = end - start
        print(f"  {start} → {end} = {delta}")
PYEOF
```

## Phase 7: Check cronjob Delivery Wiring

When a gateway health watchdog was created from CLI (not from within the platform chat), verify it delivers correctly:

```bash
hermes cron list
```

Check the `deliver` field — should show `feishu:oc_XXXX` not `local`. Fix with:

```
cronjob(action='update', job_id='XXXX', deliver='feishu:oc_XXXX')
```

## Key Thresholds for "Can Run 7×24"

| Dimension | PASS | WARNING | FAIL |
|-----------|------|---------|------|
| Auto-restart | systemd with Restart=always | systemd without Restart=always | No systemd service |
| Memory trend | Stable within ±10% over 8h | Slow growth <5%/hour | Continuous growth >10%/hour |
| Crash rate | 0 unplanned crashes/7d | 1-2 unplanned/7d | 3+ unplanned/7d |
| Log errors | 0 errors/day | 1-5 errors/day | 5+ errors/day |
| WSL uptime | > 7 days | > 24 hours | < 24 hours |
| Max proven uptime | > 24h (was stopped by planned restart, not crash) | > 8h (no data beyond) | < 8h or crash-ended |
