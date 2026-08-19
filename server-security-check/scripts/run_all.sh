#!/bin/bash
# ═══════════════════════════════════════════════════════════
# Server Security Check — 统一入口
# 调用 system/security/services 三个子脚本，合并为 JSON 数组
# shellcheck disable=SC2312
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

echo "["
first=true
for script in check_system.sh check_security.sh check_services.sh; do
    result=$(bash "${SCRIPT_DIR}/${script}" 2>/dev/null)
    if [ -n "$result" ]; then
        [ "$first" = true ] && first=false || echo ","
        echo "$result"
    fi
done
echo "]"
