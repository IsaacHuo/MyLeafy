# logs/

`logs/` 只保存 **有长期复用价值的 investigation / debugging knowledge**（调查、根因分析、踩坑经验）。它不是工作流水账。

## 什么可以写入

只有当一次问题调查产生了值得未来开发者复用的知识时，才创建 log，例如：

- UI Hang / 崩溃 / 数据丢失的根因分析与修复链路；
- 教务解析、SwiftData 生命周期、Swift Concurrency 隔离等踩坑经验；
- 真机与模拟器差异、约束冲突、审核崩溃等难复现问题的排查方法。

推荐单条 log 的结构：

```markdown
# Problem Name

## Symptom
## Investigation
## Root Cause
## Fix
## Verification
## Remaining Issues
```

## 什么不要写入

- 普通代码修改、成功 build、每次 Agent 做了什么；
- commit history（Git 已记录）；
- 很快就能从 Git 或代码中重新获得的信息；
- 无意义的尝试过程。

只有一次问题调查产出了可复用知识，才创建 log。

## 维护规则

- 文件名使用短横线小写，例如 `article-layout-width-conflict.md`。
- log 内的日期/版本信息保留历史现场，不代表当前行为；需要当前事实时看 `state/` 与 `docs/`。
- 已有类似 log 时，优先更新旧文件，不重复建新文件。
- 排查知识只写“确认的事实”，不写猜测。
