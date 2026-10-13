# Admin Studio implementation

The `/admin` frontend uses React, React Router, Tailwind, Radix primitives, TanStack Query/Table, React Hook Form and ECharts. Its shared layout and controls follow Supabase Studio patterns; Cloudflare remains the data and authentication authority. The public site still loads the admin bundle lazily. The leading data column remains pinned alongside bulk-selection controls when scrolling a wide table.

## Data contracts

All browser management requests use the existing same-origin Pages proxy, HttpOnly cookie, CSRF header and private Worker AdminAPI binding. Client permissions hide controls; Worker role and state guards authorize operations. The school selector changes query scope and is not a school ACL.

The resource registry exposes 83 actions. Lists use server-side filtering, stable sorting and pagination. Saved views store only view state in the current browser, keyed by admin ID and resource. Search results identify an object and link to its details. Query keys include admin, school, resource and filters; inactive requests can be aborted.

`overview.operations.completeProfiles` counts completed profiles. `overview.operations.activity` contains actual foreground-event distinct profile counts for today, seven days, thirty days and the selected period, plus daily counts and collection coverage. New profiles mean profile creation, and content trends mean record creation regardless of later moderation status. Current hidden inventory and recorded hide transitions are separate measurements. Feedback and reports both include `open` and `reviewed` in pending work.

`overview.analyticsMeta` supplies the IANA timezone, UTC start/end boundaries, date range, generation timestamp and collection start. Lists, export and metric drilldowns use these boundaries; end-date filters exclude the following midnight. Activity daily aggregation uses indexed UTC intervals rather than downloading every heartbeat. Server-side conversion uses Temporal, including DST transitions.

Teacher/course/dish ratings have distinct composite IDs, target filters and raw-row aggregates. Hydrated posts include actual image/attachment counts; publication recovery requires both declared counts to match. Report details include post and comment evidence. Configuration forms use native calendar fields, with server validation of dates, IDs, titles and event kinds.

## Foreground activity

`POST /v1/activity` accepts 1–100 events containing `id`, `occurredAt`, `platform`, and `appVersion`. Clients also send an expected `profileID`; the server independently resolves the authenticated profile and rejects identity drift. A transaction checks the live session/link and rejects event IDs belonging to another profile. Replayed IDs do not produce another row. Demo events are acknowledged but do not count.

The native foreground lifecycle records on entry and every five minutes. The first event can wait for the existing profile bootstrap. Identity-scoped queues retain at most seven days and remove only acknowledged events. Background transitions and identity changes cancel the caller's task; recreated profiles do not inherit the previous profile's queue. Guest and demo modes do not create a recorder network request. Data excludes school passwords, local timetable/grade/memo content, background jobs and widget activity.

D1 0012 creates minimal activity records with account-deletion cascade; the daily retention job removes records older than ninety days. Collection metadata and supported versions are visible: iOS 3.2.5 and Android 1.2.5/code 9. Versions without instrumentation are not observed; an absent event is not proof of inactivity. D1 0013 records subsequent hide transitions without inventing earlier action history.

## Operational tools

- Work queue: reports, feedback, poll review/deletion, publication exceptions, school requests, catalog suggestions and postgraduate leads. Global approval queues remain global when a school is selected.
- Super-admin diagnostics: environment, deployed commit, backend mode, scheduled runs, pending change signals and media deletion jobs. Filters and record details use bounded queries. Request logs and performance measurements show “not collected”.
- Super-admin quality checks: rating count/average/star counters, post interaction counters, declared media quantity, active-semester uniqueness, comment relationships and native calendar shape. Each check exposes at most twenty object IDs. Missing media declarations are identified separately. No SQL editor, repair button or automatic historical data mutation is exposed.

## Audit and verification

The resource/metric provenance checklist is [admin-data-provenance.md](admin-data-provenance.md). The publication receipt is [admin-studio-delivery.json](admin-studio-delivery.json).

`backend/scripts/audit-admin-data.ts` runs the same quality checks through an owner-operated SELECT-only D1 adapter. The receipt in `admin-data-audit.json` records environment, UTC check time, aggregate mismatch counts and unverifiable counts, without personal records or credentials. Before deployment and again at 2026-10-13T16:26:49Z after the final publication, all eight production checks reported zero mismatches and zero unverifiable media rows. This is a read-only consistency snapshot; it does not prove uncollected historical app activity.

Focused backend tests exercise activity replay, offline time, scope changes, demo/session rejection, D1-sized batches, DST boundaries, filters, rating deletion, role gates and moderation transitions. Native tests cover queue retention, acknowledgement and identity isolation. Browser tests exercise every resource in both themes, plus view saving, column visibility, detail evidence, confirmations, unsaved changes, search and viewer restrictions. Production operations are never used as test fixtures.

Deployment follows `operations/delivery.md`: task-commit CI, main integration, D1 forward migrations, Worker and site on staging. Production deployment requires the owner; Android candidate acceptance and iOS App Store publication remain separate.

The implemented source passed CI (backend 79 business tests and 12 migration tests; site 65 unit tests and 45 browser cases; iOS 17 build and 629 passed/1 skipped XCTest; Android unit/build/lint and screenshot checks). Staging run 38429643166 passed six deployment checks, including the isolated foreground activity/replay/identity/account-deletion smoke. Owner-authorized production run 38430130223 published the same source and passed five public checks. Worker health and site release metadata independently matched the receipt. Production admin HTML returned 200 and unauthenticated /api/admin/me returned 401. Browser role/workflow acceptance uses controlled fixtures; this does not claim a production authenticated write test or formal mobile publication.

The final deployed source is baf17b4be3f799e58f1b883e8b0aee7c9462e526; the primary-column correction also passed 65 unit and 45 browser tests. Android 1.2.5/code 9 has a registered private signed candidate from ab6c18d (prepare run 38427876245, draft android-candidate-9); its bytes are reused by subsequent preparation runs. Current formal Android remains 1.2.4/code 8. iOS 3.2.5 source passed the macOS gate; this task did not publish either new mobile client formally.
