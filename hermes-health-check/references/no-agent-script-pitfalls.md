# No-Agent Script Pitfalls (set -euo pipefail Edition)

Writing shell scripts for `no_agent: true` cron jobs is deceptively simple.
The `set -euo pipefail` strict mode catches real bugs but introduces
subtle traps that are invisible in interactive testing.

## Trap 1: Bare test-and-assign in functions

```bash
# ❌ BROKEN — exits silently when level != CRIT
alert() {
    local level="$1"
    [ "$level" = "CRIT" ] && HAS_ALERT=1
}
```

With `set -e`, a bare `[` that returns false (exit 1) aborts the script.
The `&&` chain does NOT protect the test the way `if` does.

```bash
# ✅ FIXED
alert() {
    local level="$1"
    if [ "$level" = "CRIT" ]; then
        HAS_ALERT=1
    fi
}
```

**Rule:** Any `[` / `test` that can return false MUST live inside `if`, `while`, `until`, or a `||` chain. Never bare `[ expr ] && stmt`.

## Trap 2: `grep -c || echo 0` produces two-line values

```bash
# ❌ BROKEN — ERRORS_TODAY becomes "0\n0"
ERRORS_TODAY=$(grep "pattern" file 2>/dev/null | grep -ci "err" || echo 0)
```

When `grep -c` finds zero matches, it outputs "0" AND exits with code 1.
The `|| echo 0` then runs, outputting another "0".
Result: `ERRORS_TODAY="0\n0"` → `[ "$ERRORS_TODAY" -gt 5 ]` → "integer expression expected".

```bash
# ✅ FIXED — suppress exit code without adding extra output
ERRORS_TODAY=$(grep "pattern" file 2>/dev/null | grep -ci "err" 2>/dev/null || true)
```

**Rule:** `grep -c || echo 0` is always wrong. Use `grep -ci ... || true` to get a single-line count with a clean exit code.

## Trap 3: Empty pipeline produces no variable

```bash
# ❌ BROKEN — if first grep matches nothing, second grep runs on empty stdin → count=0, exit=1
ERRORS_TODAY=$(grep "^${DATE}" largefile.log 2>/dev/null | grep -ci "err" || true)
```

This actually works (the `|| true` catches exit 1 from the second grep when count is 0).
But combine with Trap 2 and it compounds. The fix is the same: `|| true` not `|| echo 0`.

## Testing checklist

Before deploying a no_agent script, run:

```bash
# Dry run with tracing to find silent exits
bash -x /path/to/script.sh 2>&1 | tail -20

# Verify exit code
/path/to/script.sh; echo "EXIT_CODE=$?"

# Verify no output when healthy (should be silent)
# Verify expected output when issues exist
```
