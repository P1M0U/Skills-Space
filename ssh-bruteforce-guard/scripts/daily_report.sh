#!/bin/bash
# SSH 每日攻击统计报告
# 功能：统计前一天8:00到当天8:00的SSH暴力破解数据，生成汇总报告
# 用于每天早上8点发送给用户

LOG_FILE="/var/log/auth.log"
BAN_LOG="/var/log/ssh-guard.log"
REPORT_DATE=$(date '+%Y-%m-%d')

# 计算精确的时间范围：前一天8:00 到 当天8:00
START_TS=$(date -d 'yesterday 08:00:00' '+%Y-%m-%dT%H:%M:%S')
END_TS=$(date -d 'today 08:00:00' '+%Y-%m-%dT%H:%M:%S')
START_LABEL=$(date -d 'yesterday 08:00:00' '+%m-%d %H:%M')
END_LABEL=$(date -d 'today 08:00:00' '+%m-%d %H:%M')

# 开始输出 markdown 代码块
echo '```'

echo "📊 SSH 安全日报 — ${REPORT_DATE}"
echo "================================"
echo "⏰ 统计时段：${START_LABEL} ~ ${END_LABEL}"
echo ""

# 过滤指定时间范围内的失败登录记录
FAILED_LINES=$(grep -E "Failed password|Invalid user" "$LOG_FILE" 2>/dev/null | \
    awk -v start="$START_TS" -v end="$END_TS" '{
        ts = substr($0, 1, 19)
        if (ts >= start && ts < end) print
    }')

TEMP_FAILED=$(mktemp)
echo "$FAILED_LINES" > "$TEMP_FAILED"

TOTAL_FAILED=$(wc -l < "$TEMP_FAILED" 2>/dev/null || echo "0")
UNIQUE_IPS=$(grep -oP 'from \K[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+' "$TEMP_FAILED" 2>/dev/null | \
    sort -u | wc -l)

echo "📈 总体数据"
echo "  失败登录尝试：${TOTAL_FAILED} 次"
echo "  涉及独立IP数：${UNIQUE_IPS} 个"
echo ""

# TOP 10 攻击IP
echo "🎯 攻击来源 TOP 10"
grep -oP 'from \K[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+' "$TEMP_FAILED" 2>/dev/null | \
    sort | uniq -c | sort -rn | head -10 | \
    awk '{printf "  %-5s 次  %s\n", $1, $2}'
if [ "$TOTAL_FAILED" -eq 0 ]; then
    echo "  暂无数据"
fi
echo ""

# 封禁统计
BANNED_TODAY=$(grep -c "ufw已封禁" "$BAN_LOG" 2>/dev/null || echo "0")
UFW_BAN_COUNT=$(sudo -S -p '' ufw status 2>/dev/null | grep -c "DENY" || echo "0")
FAIL2BAN_BAN_COUNT=$(sudo -S -p '' fail2ban-client status sshd 2>/dev/null | grep "Currently banned" | awk '{print $NF}' || echo "0")

echo "🔒 封禁状态"
echo "  今日自动封禁：${BANNED_TODAY} 个IP"
echo "  ufw 当前封禁：${UFW_BAN_COUNT} 条规则"
echo "  fail2ban 封禁：${FAIL2BAN_BAN_COUNT} 个IP"
echo ""

# 最近 TOP 10 封禁IP列表
if [ "$UFW_BAN_COUNT" -gt 0 ]; then
    echo "📋 最近封禁 TOP 10"
    sudo -S -p '' ufw status 2>/dev/null | grep "DENY" | sed 's/^[[:space:]]*//' | awk '{print $3}' | sort -u | tail -10 | awk '{print "  " $1}'
    echo ""
fi

# 攻击时段分析
echo "⏰ 攻击时段分布"
HAS_HOUR_DATA=0

echo "  — 前一天8:00-23:59 —"
for HOUR in 08 09 10 11 12 13 14 15 16 17 18 19 20 21 22 23; do
    COUNT=$(grep -c "T${HOUR}:" "$TEMP_FAILED" 2>/dev/null)
    if [ "$COUNT" -gt 0 ] 2>/dev/null; then
        printf "    %s:00 — %d 次\n" "$HOUR" "$COUNT"
        HAS_HOUR_DATA=1
    fi
done

echo "  — 当天0:00-8:00 —"
for HOUR in 00 01 02 03 04 05 06 07; do
    COUNT=$(grep -c "T${HOUR}:" "$TEMP_FAILED" 2>/dev/null)
    if [ "$COUNT" -gt 0 ] 2>/dev/null; then
        printf "    %s:00 — %d 次\n" "$HOUR" "$COUNT"
        HAS_HOUR_DATA=1
    fi
done

if [ "$HAS_HOUR_DATA" -eq 0 ]; then
    echo "  暂无数据"
fi
echo ""

# 安全建议
if [ "$TOTAL_FAILED" -gt 100 ]; then
    echo "⚠️  安全提醒"
    echo "  过去24小时攻击频繁，建议："
    echo "  1. 检查是否有IP反复被封禁"
    echo "  2. 确认密钥认证正常工作"
    echo ""
fi

echo "================================"
echo "报告生成时间：$(date '+%Y-%m-%d %H:%M:%S')"

# 关闭 markdown 代码块
echo '```'

# 清理临时文件
rm -f "$TEMP_FAILED"
