## Project Context

This is MyLeafy, an iOS campus app.

Core stack:
- SwiftUI
- SwiftData
- URLSession
- Supabase
- Swift Package Manager

Timetable direction:
- The root navigation order is `课表 / 社区 / 日程 / 校园 / 我的`. The Schedule tab owns local memos, user-created schedules, review, tags, statistics, schedule reports, and year overview; it does not merge school exams, courses, or calendar data into the memo feed.
- Schedule memos, memo images, tags, review, and statistics are campus-identity-scoped local data. They are never uploaded, shared, exported, or published to widgets. Voice transcription must remain on-device and raw audio is never persisted.
- The BJFU timetable renders the current natural year from January through December. Calendar weeks are identified by absolute dates, while each fetched school timetable remains a term-scoped 20-week data set. Previously fetched terms that intersect the current year remain cached; course occurrences still come only from the school response and unavailable future terms remain empty.
- Semester end dates and winter/summer break ranges come from semantic runtime calendar events, never from the 20-week timetable container.
- Runtime semester configuration selects the undergraduate semester ID, graduate term code, first-week date, and semantic teaching/vacation timeline without requiring an App Store release. The year view may read previous, active, and future configurations, but school refreshes still target only the active configuration.
- Undergraduate and graduate timetable refreshes must use the same observable cache and error semantics.
- User-created schedules use one editor and one user-facing concept: dates inside the current natural year project directly into the timetable, while dates outside it remain countdowns. School-provided exams remain a separate data source.
- Schedule-report toggles apply immediately. Exam reminders run daily from 7 through 1 days before; important-date reports run 5, 3, and 1 days before.
- Timetable backgrounds support static photos and solid colors with one native SwiftUI root background layer. Disabling the background must preserve the selected photo and visual settings.
- Personalized timetable backgrounds remain local and never appear in timetable share images or widgets.

Campus heatmap direction:
- Do not bundle semester-wide classroom occupancy data. The user explicitly logs in and updates the selected date and periods on demand.
- Keep only the latest successful heatmap data per campus account and overwrite it after each successful update.
- User-facing copy says “更新数据” and “上次更新”; avoid unfamiliar implementation terminology.

Community security direction:
- One `(campus_id, edu_id)` maps to exactly one durable community profile. Multiple replaceable device Supabase Auth sessions may link to that profile, while one Auth session maps to at most one profile.
- School login automatically inherits the matching community profile and content. A verified bound email is notification-only and never participates in school login or community recovery.
- Posts and comments are created through validated RPCs, reports never auto-hide content, and post images require a short-lived single-use server validation receipt. Image posts record the exact expected image count; the final validated attachment publishes the post atomically.
- Community posts support at most two comment levels. Post images and up to two PDF/XLSX/DOCX/Markdown attachments are stored in private Supabase Storage buckets and read only through short-lived signed access. Attachment validation checks structure and type but is not malware scanning.
- Deleted post media is retained for 30 days before cleanup unless an unresolved report or administrative hidden state requires preservation. Incomplete upload drafts expire after 24 hours.
- Ordinary-post composer drafts are account-scoped local files and remain on the device until the user deletes them or the post successfully enters the publish queue. Polls do not use this draft store.
- Community share-card JPEGs are generated locally and never uploaded by the card flow. Draft content enters the community service only after publish validation succeeds and the post is enqueued.
- `posts.status = pending_review` is an upload/publication exception, never a normal editorial queue. Polls may still use `pending_review` for explicit manual approval or rejection.
- School logout clears school credentials and personal caches but does not destroy the durable community profile. Switching school identities hides the previous profile immediately and remaps the current device Auth link through bootstrap.
- Formal users can permanently delete their MyLeafy account in App. Deletion removes the linked community profile, authored content, private media, the current Supabase Auth user, and local MyLeafy data, but never changes the university's official academic account. Review demo identities are installation-unique, bootstrap into `bjfu`, and complete the same real account-deletion flow; only the legacy shared `review-demo` identity remains protected from deletion.

Architecture and performance direction:
- Feature dependencies flow from Presentation to Application to Domain; Data implements narrow application protocols and is wired at the app composition root.
- Preserve existing public type names, repository contracts, SwiftData schema, Supabase interfaces, UI, copy, and navigation during structural refactors.

- Build timetable render input and its signature once per refresh, and consume indexed snapshot data from child views.
- Community rating sections load on demand while retaining per-section state; feed projections and formatters must not be rebuilt per card body evaluation.
- Performance claims require three comparable runs, at least 10% median improvement, no more than 5% peak-memory regression, and no new app-owned leaks. Signposts must never include user content or personal data.

Minimum iOS target:
- iOS 17+

Before changing code:
- Use liquid glass effects if the device is iOS 26+.
- Inspect existing SwiftUI patterns first.
- Do not introduce heavy architecture unless needed.
- Keep campus features stable and user-facing behavior predictable.

Git branch workflow:
- `codex/leafy-ai` is not a maintained product branch and must not be used as the current product baseline.
- `codex/leafy-ai-managed-archive` is an immutable archive of the retired managed quota and subscription implementation. Do not rebase, merge into, force-update, or delete it; consult it only when historical code is needed.
- Before every new task, fetch `origin`, switch to `main`, update it with a fast-forward-only merge from `origin/main`, verify that local `main` matches `origin/main`, and create a dedicated `codex/<task>` branch from that commit. Do not implement task changes directly on `main`.
- After a task is verified, integrate it into `main`, push `origin/main`, switch back to `main`, and verify that local and remote `main` match.
- Delete the completed task's local branch and any same-name remote branch created for that task. Do not delete unrelated collaborators' branches. The maintained long-lived branches are `main` and the immutable `codex/leafy-ai-managed-archive`.
- If the worktree is dirty, `main` has diverged, or a fast-forward update is not possible, preserve existing work and stop for explicit resolution instead of resetting, overwriting, or force-updating `main`.

Principles:

1. **Fail Fast / No Silent Failures**
   Do not swallow errors, hide failures, or add fallback logic that masks real problems. When something breaks, surface it clearly.

2. **Fix Root Causes, Not Symptoms**
   Do not cover bugs with small patches, special cases, or temporary workarounds. Find the real cause and fix it properly.

3. **Make Debugging Possible**
   Critical paths must have enough logging, tracing, or observable state to diagnose failures. When information is insufficient, add instrumentation instead of pretending the issue is fixed.

4. **Keep Documentation in Sync**
   When the project’s core stack, architecture, or product direction changes, update `agents.md`. Documentation must evolve with the code and remain the single source of truth.

5. **Do Not Break Mainline**
   Create a separate branch before large refactors, risky changes, or experiments. Keep the main branch stable and releasable.
