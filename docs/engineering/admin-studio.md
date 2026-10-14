# Admin Studio implementation

The `/admin` frontend uses React, React Router, Tailwind, Radix primitives, TanStack Query/Table, React Hook Form and ECharts. Its shared layout and controls follow Supabase Studio patterns; Cloudflare remains the data and authentication authority. The public site still loads the admin bundle lazily. The leading data column remains pinned alongside bulk-selection controls when scrolling a wide table.

## Data contracts

All browser management requests use the existing same-origin Pages proxy, HttpOnly cookie, CSRF header and private Worker AdminAPI binding. Client permissions hide controls; Worker role and state guards authorize operations. The school selector changes query scope and is not a school ACL.

The resource registry exposes 82 actions. Lists use server-side filtering, stable sorting and pagination. Saved views store only view state in the current browser, keyed by admin ID and resource. Search results identify an object and link to its details. Query keys include admin, school, resource and filters; inactive requests can be aborted.

The overview completeProfiles metric counts completed profiles. The admin does not expose App usage/activity metrics. New profiles mean profile creation, and content trends mean record creation regardless of later moderation status. Current hidden inventory and recorded hide transitions are separate measurements. Feedback and reports both include `open` and `reviewed` in pending work.

`overview.analyticsMeta` supplies the IANA timezone, UTC start/end boundaries, date range, generation timestamp and moderation collection start. Lists, export and metric drilldowns use these boundaries; end-date filters exclude the following midnight. Server-side conversion uses Temporal, including DST transitions.

Teacher/course/dish ratings have distinct composite IDs, target filters and raw-row aggregates. Hydrated posts include actual image/attachment counts; publication recovery requires both declared counts to match. Report details include post and comment evidence. Configuration forms use native calendar fields, with server validation of dates, IDs, titles and event kinds.

## Operational tools

- Work queue: reports, feedback, poll review/deletion, publication exceptions, school requests, catalog suggestions and postgraduate leads. Global approval queues remain global when a school is selected.
- Super-admin diagnostics: environment, deployed commit, backend mode, scheduled runs, pending change signals and media deletion jobs. Filters and record details use bounded queries. Request logs and performance measurements show “not collected”.
- Super-admin quality checks: rating count/average/star counters, post interaction counters, declared media quantity, active-semester uniqueness, comment relationships and native calendar shape. Each check exposes at most twenty object IDs. Missing media declarations are identified separately. No SQL editor, repair button or automatic historical data mutation is exposed.

## Audit and verification

The resource/metric provenance checklist is [admin-data-provenance.md](admin-data-provenance.md). The publication receipt is [admin-studio-delivery.json](admin-studio-delivery.json).

`backend/scripts/audit-admin-data.ts` runs the same quality checks through an owner-operated SELECT-only D1 adapter. The receipt in `admin-data-audit.json` records environment, UTC check time, aggregate mismatch counts and unverifiable counts, without personal records or credentials. Before deployment and again at 2026-10-13T16:26:49Z after the final publication, all eight production checks reported zero mismatches and zero unverifiable media rows. This is a read-only consistency snapshot.

Focused backend tests exercise DST boundaries, filters, rating deletion, role gates, moderation transitions and removal-migration isolation. Browser tests exercise every resource in both themes, plus view saving, column visibility, detail evidence, confirmations, unsaved changes, search and viewer restrictions. Production operations are never used as test fixtures.

Deployment follows `operations/delivery.md`: task-commit CI, main integration, D1 forward migrations, Worker and site on staging. Production deployment requires the owner; Android candidate acceptance and iOS App Store publication remain separate.

App foreground telemetry was removed at the owner's request. D1 0014 removes its tables while preserving moderation collection metadata and all business records. Native clients no longer own an uploader or activity timer; upgrades discard only the retired pending-activity keys. Applied historical migration files remain immutable. The 1.2.5 private candidate contains retired code; a separate 1.2.6/code 10 candidate is required instead of replacing its immutable APK.
