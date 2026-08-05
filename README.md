# 🛠️ Skills Space

Agent 生产级技能仓库 — 由 [P1M0U](https://gitee.com/P1M0U) 维护。

> [English Version](./README-EN.md)

---

## 📦 技能目录

| 技能 | 版本 | 描述 |
|------|------|------|
| [🤖 hermes-health-check](./hermes-health-check/) | v2.2.1 | Hermes Agent 生产级健康检查 — 9 阶段诊断、加权评分、Watchdog 定时监控 |
| [🛡️ server-security-check](./server-security-check/) | v2.6.1 | 服务器生产级安全审计 — 20 项 CIS 级别检查、SSH 加固、恶意进程扫描、Docker 安全、TLS 证书检查 |
| [🔒 ssh-bruteforce-guard](./ssh-bruteforce-guard/) | v1.0.0 | SSH暴力破解自动封禁监控 — 检测每小时攻击超过阈值的IP，自动通过fail2ban和ufw封禁 |
| [🌟 weekly-oss-recommend](./weekly-oss-recommend/) | v1.0.0 | 每周优秀开源项目推荐 — 覆盖 Python AI Agent、Go、Vue3 等 5 个方向 28 个搜索关键词 |
| [🔧 git-collab-workflow](./git-collab-workflow/) | v1.1.0 | 标准化 Git 协作流程 — 分支管理、代码检查、Conventional Commits、PR 创建、分支清理 |

---

## 🤖 hermes-health-check

**生产级 Hermes Agent 健康检查**，9 阶段诊断 + 加权评分：

- **Phase 1:** Hermes 核心诊断（doctor / status / config check）
- **Phase 2:** 系统资源（磁盘、Inode、内存、CPU 负载、进程健康）
- **Phase 3:** Gateway 深度分析（适配器健康、重连模式、内存增长）
- **Phase 4:** Skills & Memory 完整性（Skill 校验、Session DB 完整性）
- **Phase 5:** API 连通性矩阵（多 Provider 测试、网络延迟）
- **Phase 6:** 安全基线（防火墙、SSH 配置、暴力破解检测、Crontab 审计）
- **Phase 7:** 日志卫生（日志大小、轮转、存储用量）
- **Phase 8:** 环境信息（内核、云平台、DNS、网络）
- **Phase 9:** Profiles 完整性（config 校验、Session DB 完整性、跨 profile 隔离检测、缓存膨胀）

### 快速开始

```bash
# 交互式检查（在 Hermes 会话中说 "健康检查"）

# 定时 Watchdog（每 6 小时，LLM 驱动）
hermes cron create --name health-watchdog \
  --schedule "0 */6 * * *" \
  --skill hermes-health-check \
  --prompt "Run full health check. Only report if UNHEALTHY."

# 轻量脚本（每 30 分钟，0 token 消耗）
hermes cron create --name health-watchdog-quiet \
  --schedule "*/30 * * * *" \
  --script health_watchdog.sh \
  --no-agent
```

---

## 🛡️ server-security-check

**生产级服务器安全审计**，覆盖 **20 个安全检查领域**：

- 防火墙状态、监听端口审计
- SSH 安全加固（7 项 CIS 基线）+ Socket 激活诊断
- SSH 暴力破解检测、恶意进程 & Rootkit 扫描
- 用户账户审计、SUID/SGID 提权攻击检测
- Crontab 安全检查、Docker 安全检查
- SELinux / AppArmor、内核参数加固
- 磁盘 & Inode、内存 & Swap、系统更新状态
- **[v2.6.1]** TLS 证书过期检查、自动更新配置检查

### 快速开始

```bash
# 交互式检查（在 Hermes 会话中说 "安全检查"）
# 全量定时检查（每天 10:00/22:00）
hermes cron create --name "安全全量检查" \
  --schedule "0 10,22 * * *" \
  --skill server-security-check \
  --prompt "执行完整安全健康检查。如有 CRITICAL 项或评分低于 70，明确告警。"
```

---

## 🔒 ssh-bruteforce-guard

**SSH暴力破解自动封禁监控**，功能：

- 自动分析 /var/log/auth.log 中的失败登录记录
- 统计每个IP在过去1小时内的攻击次数
- 超过阈值（默认30次/小时）的IP自动通过 fail2ban 和 ufw 封禁
- 详细的封禁日志记录

### 快速开始

```bash
# 手动运行
sudo ~/.hermes/scripts/ssh-guard/monitor.sh

# 定时任务（每小时运行一次）
hermes cron create --name "SSH暴力破解监控" \
  --schedule "0 * * * *" \
  --script ssh-guard/monitor.sh \
  --no-agent \
  --deliver "qqbot:你的chat_id"
```

---

## 🌟 weekly-oss-recommend

**每周优秀开源项目推荐**，覆盖 **5 个技术方向**，共 **28 个搜索关键词**：

- Python AI Agent（9 个关键词）
- Python 其他（3 个关键词）
- Go 语言（8 个关键词）
- Vue3 前端（5 个关键词）
- 主流框架/生态（3 个关键词）

### 快速开始

```bash
# 定时推荐（周六 + 周日早上 10:00，推送到飞书）
hermes cron create --name "优秀开源项目推荐（周六）" \
  --schedule "0 2 * * 6" \
  --skill weekly-oss-recommend \
  --prompt "推荐一个优秀开源项目" \
  --deliver "feishu:oc_92c9b46accd79149769c935fed40c9a4"
```

---

## 🚀 部署指南

### 方式一：一键安装（推荐）

告诉你的 Hermes Agent：

> 请帮我安装 Skills-Space 仓库中的 hermes-health-check skill

### 方式二：手动安装

```bash
# 克隆仓库
git clone https://gitee.com/P1M0U/Skills-Space.git /tmp/Skills-Space

# 安装所需 skill
cp -r /tmp/Skills-Space/hermes-health-check ~/.hermes/skills/
cp -r /tmp/Skills-Space/server-security-check ~/.hermes/skills/

# 清理
rm -rf /tmp/Skills-Space
```

### 方式三：给智能体的安装提示词

```bash
# 复制以下内容发给你的 AI Agent，它会自动完成安装
curl -fsSL https://gitee.com/P1M0U/Skills-Space/raw/main/hermes-health-check/SKILL.md -o ~/.hermes/skills/hermes-health-check/SKILL.md
```

---

## 📄 License

[MIT](./LICENSE) — Copyright (c) 2026 P1M0U
