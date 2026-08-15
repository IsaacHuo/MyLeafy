## Repository Knowledge System

这个仓库的知识由四个来源承担，职责互不重叠：

```text
docs/   → What we intend to build, and why.   （设计与规划）
state/  → What exists now.                    （当前真实状态）
logs/   → What we learned while debugging.    （可复用的排查知识）
git     → What changed.                       （普通改动历史）
```

进入仓库后按以下顺序理解项目：

1. `AGENTS.md`（本文件）：工程原则、协作流程与导航规则。
2. `state/CURRENT.md`：当前阶段、重点、最近完成、已知问题与下一步。
3. `state/ARCHITECTURE.md`：当前代码结构、分层、数据流与行为约束（权威）。
4. 与任务相关的 `docs/`：设计、方案、规划与 rationale。
5. 与问题相关的 `logs/`：可复用的调查、根因与踩坑经验。
6. actual code。

维护规则：

- `state/` 只描述当前真实状态，必须基于代码验证；未来设计进入 `docs/`。
- 判断是否需要更新 `state/`：

  ```text
  Did this change alter how a future agent understands the repository?
  YES → update state (CURRENT.md / ARCHITECTURE.md)
  NO  → do not update state
  ```

- 架构、模块边界或主要功能状态变化的任务结束后，更新 `state/` 是收尾的一部分。
- `logs/` 只保存有长期复用价值的排查知识，不记录普通改动、成功 build 或 commit history。
- 不要在 Markdown 中重复 Git commit log。

## Engineering Principles

### 1. Prefer Simplicity

Choose the simplest implementation that fully meets the current requirements. Avoid speculative abstractions, unnecessary configuration, indirection, and infrastructure that is not required by the current product. Complexity must justify itself.

### 2. Build in Working Layers

Grow the system incrementally. Start with the smallest version that works end to end, then add each new capability on top of a product that already works. Never trade a working product for unfinished complexity. Each development step should leave the system in a usable state.

### 3. Do Not Preserve Obsolete Compatibility

Do not preserve backward compatibility unless explicitly required. When an old path, API, implementation, or architecture becomes obsolete, remove it instead of adding compatibility layers, fallbacks, adapters, migrations, or duplicated behavior. Prefer one clear current implementation over multiple historical paths.

### 4. Keep Responsibilities Separated

Keep components modular and concerns clearly separated. Each module, type, service, or component should have a clear responsibility and a minimal interface. Avoid tightly coupling unrelated behavior. Do not introduce abstraction solely for the sake of abstraction; modularity should make the system easier to understand, modify, and verify.

### 5. Reuse Existing Dependencies First

Lean on the dependencies already present in the project before writing custom implementations or adding new packages. Do not assume an existing library lacks a required capability without checking its documentation, APIs, and types first. Avoid duplicating functionality that the project already has.

### 6. Prefer Established Libraries

Prefer established, well-maintained libraries when they reduce overall complexity or improve reliability. Do not reimplement common functionality without a clear technical or product reason. Before adding a dependency, verify that it meaningfully simplifies the implementation and does not introduce disproportionate maintenance cost.

### 7. Design for the Long Term

Make architectural decisions that remain sound as the product grows. Do not accept temporary stopgaps that are intentionally meant to be replaced later. A simple implementation is preferred, but it should still have a clean path for extension. Avoid accumulating known structural debt for short-term convenience.

### 8. Study Proven Products First

Before designing a solution, study how established products solve the same or similar problem. Prefer proven interaction patterns, architectural conventions, terminology, and workflows over inventing a new approach from scratch. Understand why existing patterns work before deviating from them. Introduce a novel approach only when the product has a concrete requirement that established patterns do not adequately address.

---

## Project Context

This is MyLeafy, an iOS campus app.

Core stack:
- SwiftUI
- SwiftData
- URLSession
- Supabase
- Swift Package Manager

Current state (read first):
- [`state/CURRENT.md`](state/CURRENT.md) — current stage, focus, known problems, next steps.
- [`state/ARCHITECTURE.md`](state/ARCHITECTURE.md) — current code structure, layering, data flow, and behavioral invariants (root navigation order, timetable academic-year boundary, memo local-only rules, community security invariants, campus capability model, performance constraints).

The behavioral invariants that must hold while editing code live in `state/ARCHITECTURE.md` §11 (当前行为约束). If a change alters those invariants, update `state/ARCHITECTURE.md` in the same change.

## Minimum iOS target

- iOS 17+

## Before changing code

- Use liquid glass effects if the device is iOS 26+.
- Inspect existing SwiftUI patterns first.
- Do not introduce heavy architecture unless needed.
- Keep campus features stable and user-facing behavior predictable.

## Git branch workflow

- Before every new task, fetch `origin`, switch to `main`, update it with a fast-forward-only merge from `origin/main`, verify that local `main` matches `origin/main`, and create a dedicated `codex/<task>` branch from that commit. Do not implement task changes directly on `main`.
- After a task is verified, integrate it into `main`, push `origin/main`, switch back to `main`, and verify that local and remote `main` match.
- Pull requests are optional. Verified task branches may be fast-forwarded directly into `main`; CI must run on pushes to `main` so direct integration keeps automated checks without requiring a PR.
- Delete the completed task's local branch and any same-name remote branch created for that task. Do not delete unrelated collaborators' branches. The maintained long-lived branch is `main`.
- If the worktree is dirty, `main` has diverged, or a fast-forward update is not possible, preserve existing work and stop for explicit resolution instead of resetting, overwriting, or force-updating `main`.

## Principles

1. **Fail Fast / No Silent Failures**
   Do not swallow errors, hide failures, or add fallback logic that masks real problems. When something breaks, surface it clearly.

2. **Fix Root Causes, Not Symptoms**
   Do not cover bugs with small patches, special cases, or temporary workarounds. Find the real cause and fix it properly.

3. **Make Debugging Possible**
   Critical paths must have enough logging, tracing, or observable state to diagnose failures. When information is insufficient, add instrumentation instead of pretending the issue is fixed.

4. **Keep Documentation in Sync**
   When the project’s core stack, architecture, or product direction changes, update `state/` (CURRENT/ARCHITECTURE) and the relevant `docs/`. Documentation must evolve with the code and remain the single source of truth. Reusable debugging knowledge belongs in `logs/`.

5. **Do Not Break Mainline**
   Create a separate branch before large refactors, risky changes, or experiments. Keep the main branch stable and releasable.
