# 🔧 git-collab-workflow

标准化 Git 协作流程 Skill — 分支管理、代码检查、格式化、提交、推送、创建 PR。

## 🎯 功能

完整的 8 阶段 Git 协作工作流：

- **Phase 1:** 分支管理（切换主分支、拉取最新、冲突处理）
- **Phase 2:** 创建功能分支（语义化命名、前缀规范）
- **Phase 3:** 代码修改（用户/agent 完成）
- **Phase 4:** 代码检查与格式化（pre-commit / ruff / eslint / shellcheck）
- **Phase 5:** 提交代码（Conventional Commits 规范）
- **Phase 6:** 推送与创建 PR（MCP / API / 手动链接三种方式）
- **Phase 7:** 通知用户审核
- **Phase 8:** 分支清理（PR 合并后删除本地+远程分支）

## 📦 安装

### 方式一：手动安装

```bash
git clone https://gitee.com/P1M0U/Skills-Space.git /tmp/Skills-Space
cp -r /tmp/Skills-Space/git-collab-workflow ~/.hermes/skills/
rm -rf /tmp/Skills-Space
```

### 方式二：给智能体的安装提示词

```bash
请帮我安装 git-collab-workflow skill，从 https://gitee.com/P1M0U/Skills-Space 仓库
```

## 🚀 使用

在 Hermes 会话中说：

```
帮我提交代码
```

或

```
创建一个 PR
```

或

```
检查代码格式
```

## 📋 提交信息规范

采用 [Conventional Commits](https://www.conventionalcommits.org/) 规范：

| type | 说明 |
|------|------|
| `feat` | 新功能 |
| `fix` | 修复 bug |
| `refactor` | 重构（不改变功能） |
| `docs` | 文档更新 |
| `test` | 测试相关 |
| `chore` | 构建/工具/依赖 |
| `style` | 代码格式（不影响逻辑） |
| `perf` | 性能优化 |

## 📁 文件结构

```
git-collab-workflow/
├── SKILL.md    # 主技能文件（v1.1.0）
└── README.md   # 本文件
```

## ⚠️ 注意事项

- 永远不在主分支直接改代码
- 永远不跳过 lint/format 检查
- 永远不自行合并 PR
- commit 前用 `git diff --staged` 确认变更范围
- 敏感信息和大文件不能提交

## 📄 License

[MIT](../LICENSE) — Copyright (c) 2026 P1M0U
