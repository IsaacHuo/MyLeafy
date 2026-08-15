# state/

`state/` 是这个仓库的 Current Truth：它描述 **当前代码实际是什么样**，而不是我们希望它以后是什么样。

## 定位

仓库的知识由四个来源承担，职责互不重叠：

```text
docs/   → What we intend to build, and why.   （设计与规划）
state/  → What exists now.                    （当前真实状态）
logs/   → What we learned while debugging.    （可复用的排查知识）
git     → What changed.                       （普通改动历史）
```

- `state/` 回答“现在这个仓库是什么样”，未来 AI Agent 进入仓库时首先阅读这里。
- `docs/` 回答“我们打算建什么、为什么这么设计”，允许与 `state/` 存在差异。
- `logs/` 只保存有长期复用价值的调查与根因，不是工作流水账。
- Git 已经记录普通改动历史，Markdown 不重复 commit log。

## 文件职责

| 文件 | 职责 |
|---|---|
| `state/CURRENT.md` | 开发进度：当前阶段、重点、最近完成、进行中、已知问题、下一步 |
| `state/ARCHITECTURE.md` | 当前代码结构：入口、模块、分层、数据流、依赖方向与行为约束 |

## 维护原则

1. **内容必须基于当前代码验证**。代码是判断当前真实状态的最高优先级依据，不要照抄 `docs/` 的设想。
2. **不记录长期愿景**。未来设计进入 `docs/`，`state/` 只描述现状。
3. **不复制 `docs/`**。需要细节时用相对链接引用，不整段重复。
4. **不记录普通 commit history**。Git 已经承担这个职责。
5. **判断是否更新 state**，使用下面的规则：

   ```text
   Did this change alter how a future agent understands the repository?

   YES → update state
   NO  → do not update state
   ```

   典型的“需要更新”：

   - 架构、模块边界或主要功能状态发生变化；
   - 根导航、分层、数据流或行为约束被改变；
   - 当前开发重点发生实质转移。

   典型的“不需要更新”：

   - 普通 UI 调整、小型 bug fix、重命名、文档措辞。

6. 当一次架构或主要功能变更结束后，同步更新 `state/CURRENT.md`（和必要的 `state/ARCHITECTURE.md`），这是任务收尾的一部分。
