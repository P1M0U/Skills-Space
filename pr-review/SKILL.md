---
name: pr-review
description: "PR 代码审查：用户发 PR 链接，自动拉取 diff，多维度评估，输出合并建议。绝不执行合并。"
version: 1.1.0
platforms: [linux, macos, windows]
metadata:
  hermes:
    tags: [pr, code-review, gitee, github, merge, diff, security]
    related_skills: [code-review, git-collab-workflow, gitee-pr-workflow]
---

# PR Code Review Skill

用户发送 PR 链接 → 自动审查 → 输出评估报告 + 合并建议。

## 触发条件

用户发送以下内容时加载此 skill：
- PR 链接（gitee.com/.../pulls/ 或 github.com/.../pull/）
- "审查 PR" / "review PR" / "看看这个 PR"
- "能不能合并" / "是否可以合入"

## 绝对铁律

1. **永远不执行合并操作** — 只审查、只建议，合并由用户决定
2. **永远不 push 代码** — 只读取，不写入远程仓库
3. **本地克隆必须清理** — 审查完成后立即删除临时克隆目录
4. **标记不确定性** — 不确定的问题标注 `[待确认]`
5. **不暴露敏感信息** — token、密钥等用 `***` 截断

## Phase 1: 识别平台与获取 PR 信息

### 解析 PR 链接

从用户消息中提取：
- **平台**：Gitee 或 GitHub
- **owner/repo**
- **PR 编号**

链接格式示例：
```
https://gitee.com/owner/repo/pulls/123
https://github.com/owner/repo/pull/123
```

### 获取 PR 详情

#### GitHub（优先使用 MCP）

```python
# PR 详情
mcp__github__get_pull_request(owner, repo, pull_number)

# PR 变更文件列表
mcp__github__get_pull_request_files(owner, repo, pull_number)

# PR 已有评论
mcp__github__get_pull_request_comments(owner, repo, pull_number)

# PR 已有 Review
mcp__github__get_pull_request_reviews(owner, repo, pull_number)
```

#### Gitee（使用 REST API）

```bash
# PR 详情
curl -s "https://gitee.com/api/v5/repos/<owner>/<repo>/pulls/<number>?access_token=<token>" | python3 -m json.tool

# PR 变更文件
curl -s "https://gitee.com/api/v5/repos/<owner>/<repo>/pulls/<number>/files?access_token=<token>" | python3 -m json.tool

# PR 评论
curl -s "https://gitee.com/api/v5/repos/<owner>/<repo>/pulls/<number>/comments?access_token=<token>" | python3 -m json.tool

# PR Review 评论
curl -s "https://gitee.com/api/v5/repos/<owner>/<repo>/pulls/<number>/reviews?access_token=<token>" | python3 -m json.tool
```

**Token 获取**：从远程仓库 URL 中提取（`https://用户名:token@gitee.com/...`），或向用户索要。

### 读取已有 Review（重要）

在审查代码前，先读取 PR 已有的评论和 review：
- 避免重复指出已讨论过的问题
- 关注已标记为 "outdated" 的评论（代码可能已修复）
- 记录已有的建议，审查时参考

### 若需要本地 Diff

当远程 API 无法获取完整 diff（如大型 PR、需要对比上下文）时，临时克隆到本地：

```bash
# 克隆到临时目录
CLONE_DIR=$(mktemp -d)
trap "rm -rf $CLONE_DIR" EXIT
git clone --depth=1 --branch <pr-branch> <repo-url> "$CLONE_DIR"

# ... 执行 diff 分析 ...

# ⚠️ 审查结束后必须清理（由 trap 兜底）
```

---

## Phase 2: 代码审查（7 个维度）

### 维度 1：安全性（权重 25%）

| 检查项 | 严重程度 |
|--------|----------|
| 硬编码 API Key / 密码 / Token | 🔴 CRITICAL |
| SQL 注入（字符串拼接 SQL） | 🔴 CRITICAL |
| XSS 漏洞（未转义的用户输入） | 🔴 CRITICAL |
| 路径遍历（未校验的文件路径） | 🔴 CRITICAL |
| 命令注入（eval/exec/os.system） | 🔴 CRITICAL |
| 不安全的反序列化（pickle/yaml.load） | 🟡 WARNING |
| 敏感信息日志输出 | 🟡 WARNING |
| CORS 配置过于宽松 | 🟡 WARNING |

```bash
# 快速安全扫描
grep -rn "password\|secret\|api_key\|token\|eval\|exec\|system(" <changed-files> 2>/dev/null
```

### 维度 2：功能正确性（权重 20%）

| 检查项 | 严重程度 |
|--------|----------|
| 空指针 / None 未处理 | 🔴 CRITICAL |
| 边界条件缺失 | 🟡 WARNING |
| 异常被静默吞掉（bare except / catch all） | 🟡 WARNING |
| 资源未释放（文件/连接/锁） | 🟡 WARNING |
| 并发安全问题 | 🟡 WARNING |
| 返回值不一致 | 🟡 WARNING |

### 维度 3：代码质量（权重 20%）

| 检查项 | 严重程度 |
|--------|----------|
| 函数过长（>100 行） | 🟡 WARNING |
| 圈复杂度过高（嵌套 >4 层） | 🟡 WARNING |
| 代码重复（DRY 违规） | 🟢 INFO |
| 命名不规范 | 🟢 INFO |
| 魔法数字 / 魔法字符串 | 🟢 INFO |
| 未使用的导入 / 变量 | 🟢 INFO |

### 维度 4：性能（权重 10%）

| 检查项 | 严重程度 |
|--------|----------|
| N+1 查询 | 🟡 WARNING |
| 循环内重复计算 | 🟡 WARNING |
| 不必要的全表扫描 | 🟡 WARNING |
| 大列表未分页 | 🟢 INFO |
| 同步阻塞调用在异步上下文中 | 🟡 WARNING |

### 维度 5：测试覆盖（权重 10%）

| 检查项 | 严重程度 |
|--------|----------|
| 新增功能无测试 | 🟡 WARNING |
| Bug 修复无回归测试 | 🟡 WARNING |
| 测试只覆盖 happy path | 🟢 INFO |
| 测试断言不充分 | 🟢 INFO |

### 维度 6：文档与注释（权重 5%）

| 检查项 | 严重程度 |
|--------|----------|
| 关键逻辑无注释 | 🟢 INFO |
| 公共 API 无文档 | 🟡 WARNING |
| README 未更新 | 🟢 INFO |
| CHANGELOG 未更新 | 🟢 INFO |

### 维度 7：规范合规（权重 10%）

| 检查项 | 严重程度 |
|--------|----------|
| 提交信息不符合 Conventional Commits | 🟢 INFO |
| 文件组织不符合项目结构 | 🟢 INFO |
| 分支命名不规范 | 🟢 INFO |
| 变更超出 PR 描述范围 | 🟡 WARNING |
| PR 描述未填写或过于简略 | 🟡 WARNING |
| 未关联 Issue | 🟢 INFO |

### 维度 8：二进制文件检查（权重 0%，仅记录）

| 检查项 | 严重程度 |
|--------|----------|
| 二进制文件 > 5MB | 🟡 WARNING |
| 二进制文件 > 10MB | 🔴 CRITICAL |
| 意外的大文件（截图/未压缩资源） | 🟡 WARNING |
| 二进制文件无对应说明 | 🟢 INFO |

```bash
# 检查二进制文件大小
git diff --stat <base>...<head> | grep -E "\.(png|jpg|jpeg|gif|svg|pdf|zip|tar|exe|dll|so|dylib)"
```

---

## Phase 2.5: 大型 PR 分批策略

当 PR 变更超过 **300 行**时，启用分批审查：

### 分批规则

1. **按目录/模块分组**：同一目录下的文件归为一批
2. **优先级排序**：
   - 第 1 批：安全相关文件（auth、crypto、config、.env）
   - 第 2 批：核心业务逻辑
   - 第 3 批：工具/辅助代码
   - 第 4 批：测试/文档
3. **每批独立评分**，最终加权汇总

### 分批示例

```
PR 变更 500 行，涉及 8 个文件：

批次 1（安全）: config/auth.py, .env.example → 审查安全性
批次 2（核心）: api/users.py, api/orders.py → 审查功能正确性 + 性能
批次 3（工具）: utils/helpers.py, utils/validators.py → 审查代码质量
批次 4（测试）: tests/test_users.py, README.md → 审查测试覆盖 + 文档
```

---

## Phase 3: 评分与结论

### 评分规则

| 问题等级 | 扣分 |
|----------|------|
| 🔴 CRITICAL | -15 分/个 |
| 🟡 WARNING | -5 分/个 |
| 🟢 INFO | -1 分/个 |

基础分 100 分，扣完为止。

### 合并建议

| 评分 | 建议 | 说明 |
|------|------|------|
| ≥ 85 分 | ✅ 建议合并 | 无 CRITICAL，少量 WARNING |
| 70-84 分 | ⚠️ 建议修改后合并 | 有 WARNING 需处理 |
| < 70 分 | ❌ 不建议合并 | 有 CRITICAL 或大量 WARNING |
| 有 CRITICAL | ❌ 不建议合并 | 无论总分多少 |

---

## Phase 4: 输出报告

### 完整报告

```
═══════════════════════════════════════════════════════════════
          PR CODE REVIEW REPORT
          PR #<number>: <title>
          作者: <author> | 分支: <head> → <base>
═══════════════════════════════════════════════════════════════

📊 总体评估: ✅ 建议合并 / ⚠️ 建议修改后合并 / ❌ 不建议合并
评分: <score>/100

───────────────────────────────────────────────────────────────
🔴 严重问题 (必须修复) — <N> 个
───────────────────────────────────────────────────────────────
1. [安全/功能/性能] <file>:<line> — <description>
2. ...

───────────────────────────────────────────────────────────────
🟡 建议改进 (非阻塞) — <N> 个
───────────────────────────────────────────────────────────────
1. [质量/测试/文档] <file>:<line> — <description>
2. ...

───────────────────────────────────────────────────────────────
🟢 亮点 — <N> 个
───────────────────────────────────────────────────────────────
1. <description>
2. ...

───────────────────────────────────────────────────────────────
📋 变更摘要
───────────────────────────────────────────────────────────────
文件变更: +<additions> / -<deletions>
新增文件: <N> | 删除文件: <N>
涉及模块: <list>
二进制文件: <list or "无">

───────────────────────────────────────────────────────────────
💬 已有 Review 摘要
───────────────────────────────────────────────────────────────
已有 <N> 条评论，<M> 个 Review
本次审查已参考已有意见，未重复指出已讨论问题。

═══════════════════════════════════════════════════════════════
⚠️ 本报告为 AI 审查意见，最终合并决定由维护者做出。
═══════════════════════════════════════════════════════════════
```

### 快速摘要（一句话版本）

审查完成后，先输出一句话结论：

```
PR #123: ✅ 建议合并（92/100）— 无严重问题，2 个建议改进
PR #456: ⚠️ 建议修改后合并（78/100）— 1 个 WARNING 需处理：api/users.py 有 N+1 查询
PR #789: ❌ 不建议合并（45/100）— 2 个 CRITICAL：硬编码密钥 + SQL 注入
```

用户追问时再输出完整报告。

---

## Phase 5: 清理

无论审查是否成功，结束后执行：

```bash
# 清理临时克隆目录（trap 已兜底）
[ -d "$CLONE_DIR" ] && rm -rf "$CLONE_DIR" && echo "临时目录已清理"

# 验证清理
[ ! -d "$CLONE_DIR" ] && echo "✅ 清理完成" || echo "❌ 清理失败，请手动删除: $CLONE_DIR"
```

---

## 降级策略

| 情况 | 处理方式 |
|------|----------|
| GitHub MCP 不可用 | 用 `gh pr view` / `gh pr diff` CLI |
| gh CLI 不可用 | 用 `curl` 调 GitHub REST API |
| Gitee API | 用 `curl` 调 Gitee REST API |
| API 都不可用 | 请用户手动复制 diff 内容 |
| PR 太大（>300 行） | 启用分批策略，按目录/模块分组审查 |
| 二进制文件变更 | 跳过内容审查，检查文件大小，记录变更 |

---

## Pitfalls

### Token 安全
- 克隆时使用的 token 不能出现在日志或输出中
- 用 `git clone https://<token>@gitee.com/...` 时，确保 token 不被打印

### 清理遗漏
- 异常退出可能跳过清理 → 用 `trap` 兜底
- 清理失败（权限问题）→ 提示用户手动删除

### 大型 PR
- 超过 300 行变更时，启用分批策略
- 按目录/模块分组，每组独立评分
- 优先审查安全维度

### 二进制文件
- 图片、编译产物等二进制文件无法做代码审查
- 检查文件大小：>5MB WARNING，>10MB CRITICAL
- 仅记录"新增/修改了二进制文件"，建议用户确认是否必要

### 已有 Review
- 审查前先读取已有评论和 review
- 避免重复指出已讨论过的问题
- 关注 "outdated" 标记（代码可能已修复）
