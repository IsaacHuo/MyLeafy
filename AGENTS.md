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

Timetable direction:
- MyLeafy supports Simplified Chinese and American English. The in-App preference offers Follow System, Simplified Chinese, and English under Personalization, and synchronizes the chosen language to Widget and Share extensions. App-generated interface text, notifications, widgets, and share text follow this preference; user content, community content, course names, teacher names, and school-source data remain in their original language. System-owned permission prompts, pickers, and share sheets continue to follow the device language.
- The root navigation order is `课表 / 社区 / 日迹 / 校园 / 我的`. The 日迹 tab exposes `随记 / 日程 / 推送` directly at the top; its 日程 section uses the personal schedule list rather than a separate natural-year week view. The memo inputer supports focus expansion and zoomed editing when the text reaches four visual lines. The plus menu does not create new articles; existing non-audio memos use one Markdown source/preview editor with cursor-aware formatting and inline local image or attachment markers. Memo cards remain plain summaries, while detail and locally rendered share cards resolve Markdown and local resources. The memo action menu may compose a submission in the user's default mail app to the configured editorial address; it never sends automatically or attaches local files automatically. School exams, courses, and calendar data never enter the memo feed or personal schedule list.
- Schedule memos, Markdown writing source, memo images, up to three common-document attachments, user-created audio memos, tags, review, and statistics are campus-identity-scoped local data. Attachment source URLs are copied through their security-scoped access into the active identity directory; deleting a memo or resetting local data deletes its attachment or audio rows and files. These records and files are never uploaded, shared, exported, or published to widgets. Share cards may contain rendered text, local photos, and attachment names only. Voice transcription remains on-device and never persists its raw input; only the explicit audio-memo flow may save a local recording.
- The BJFU timetable is browsed one academic year at a time, from the fall-semester start through the day before the next academic year begins. The final week of summer vacation stops at that academic-year boundary; the next academic year is entered through the academic-year/date selector. Calendar weeks are identified by absolute dates, while each fetched school timetable remains a term-scoped 20-week data set. Previously fetched terms that intersect the current academic year remain cached; course occurrences still come only from the school response and unavailable future terms remain empty.
- Semester end dates and winter/summer break ranges come from semantic runtime calendar events, never from the 20-week timetable container.
- Runtime semester configuration selects the undergraduate semester ID, graduate term code, first-week date, and semantic teaching/vacation timeline without requiring an App Store release. The year view may read previous, active, and future configurations, but school refreshes still target only the active configuration.
- Undergraduate and graduate timetable refreshes must use the same observable cache and error semantics.
- User-created schedules use one editor and one user-facing concept. The personal schedule view browses unlimited natural years, while dates inside the current academic year also project into the school timetable; dates outside it remain personal countdowns. School-provided exams remain a separate data source.
- Schedule-report toggles apply immediately. Exam reminders run daily from 7 through 1 days before; important-date reports run 5, 3, and 1 days before.
- Timetable backgrounds support static photos and solid colors with one native SwiftUI root background layer. Disabling the background must preserve the selected photo and visual settings.
- Personalized timetable backgrounds remain local and never appear in timetable share images or widgets.
- The native system `TabView` is the root navigation surface. Do not layer page transparency over it to imitate a fade-in transition.
- 日迹 cards use a white system surface. Tags use white text in a theme-colored capsule; tag filtering shows the active tag and offers “全部随记”. The 日迹 inputer supports focus expansion and zoomed editing when the text reaches four visual lines; the plus menu no longer offers new-article creation, while existing articles remain viewable and editable. The “记录” sidebar group places “记录日迹” above “每日回顾”; it shows natural-year monthly memo counts and recording days, a recent-30-day heatmap, streaks, weekday/time habits, common tags, and milestones. Dates in the heatmap open that day’s memos. Statistics images are rendered locally, contain aggregate numbers only without memo text or tag names, use the system share sheet, and are never uploaded. Rating detail stars are centered.

Campus information architecture:
- The first-level domains include `自习安排` and `学习空间`. `空闲教室` remains an internal tool under `自习安排`; library seat reservations and the campus heatmap also belong there. Focus records belong to `学习空间`.

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
- Preserve current UI, copy, navigation, deep links, SwiftData model names, and current Supabase contracts during structural refactors. Remove obsolete aliases, legacy storage keys, deprecated decoding paths, and compatibility-only interfaces when the current implementation replaces them.

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
- Before every new task, fetch `origin`, switch to `main`, update it with a fast-forward-only merge from `origin/main`, verify that local `main` matches `origin/main`, and create a dedicated `codex/<task>` branch from that commit. Do not implement task changes directly on `main`.
- After a task is verified, integrate it into `main`, push `origin/main`, switch back to `main`, and verify that local and remote `main` match.
- Pull requests are optional. Verified task branches may be fast-forwarded directly into `main`; CI must run on pushes to `main` so direct integration keeps automated checks without requiring a PR.
- Delete the completed task's local branch and any same-name remote branch created for that task. Do not delete unrelated collaborators' branches. The maintained long-lived branch is `main`.
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
