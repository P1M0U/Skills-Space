# 🔍 pr-review

PR 代码审查 Skill — 自动审查 diff、多维度评估、输出合并建议，绝不执行合并。

## 🎯 功能

完整的 5 阶段 PR 审查流程：

- **Phase 1:** 识别平台 + 获取 PR 信息（GitHub MCP / Gitee API / curl）
- **Phase 2:** 8 维度代码审查（安全/功能/质量/性能/测试/文档/规范/二进制文件）
- **Phase 2.5:** 大型 PR 分批策略（>300 行按目录分组）
- **Phase 3:** 评分（100 分制，3 档合并建议）
- **Phase 4:** 输出报告（完整版 + 一句话快速摘要）
- **Phase 5:** 清理临时克隆目录

## 📦 安装

```bash
git clone https://gitee.com/P1M0U/Skills-Space.git /tmp/Skills-Space
cp -r /tmp/Skills-Space/pr-review ~/.hermes/skills/
rm -rf /tmp/Skills-Space
```

## 🚀 使用

```
帮我审查这个 PR：https://github.com/owner/repo/pull/123
```

或

```
这个 PR 能不能合并？
```

## 📋 审查维度

| 维度 | 权重 | 说明 |
|------|------|------|
| 安全性 | 25% | 硬编码密钥、注入漏洞、路径遍历 |
| 功能正确性 | 20% | 空指针、边界条件、异常处理 |
| 代码质量 | 20% | 函数长度、复杂度、命名规范 |
| 性能 | 10% | N+1 查询、循环计算、阻塞调用 |
| 测试覆盖 | 10% | 新功能无测试、断言不充分 |
| 规范合规 | 10% | Conventional Commits、PR 描述 |
| 文档 | 5% | 注释、API 文档、README |
| 二进制文件 | 0% | 文件大小检查、大文件告警 |

## 📁 文件结构

```
pr-review/
├── SKILL.md    # 主技能文件（v1.1.0）
└── README.md   # 本文件
```

## ⚠️ 铁律

- 永远不执行合并
- 永远不 push 代码
- 本地克隆必须清理
- 标记不确定性
- 不暴露敏感信息

## 📄 License

[MIT](../LICENSE) — Copyright (c) 2026 P1M0U
