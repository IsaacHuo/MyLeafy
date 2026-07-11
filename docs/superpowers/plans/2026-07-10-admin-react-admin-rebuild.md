# MyLeafy Admin React-admin Rebuild Implementation Plan

> **For agentic workers:** Use test-driven development for production changes. Preserve the existing admin action names and all unrelated user files.

**Goal:** Replace `/admin` with a secure React-admin application while preserving all current operations and adding global search, controlled export, session management, and runtime configuration.

**Architecture:** The Vite site lazy-loads React-admin at `/admin/*`. A Cloudflare Pages Function acts as a same-origin BFF and stores the existing Supabase admin token in an HttpOnly cookie. Supabase Edge Functions remain the authorization boundary and are split into domain modules without breaking action names.

**Tech Stack:** React 18, React-admin 5.15.1, MUI, ECharts 6.1.0, Cloudflare Pages Functions, Supabase Edge Functions/Postgres, Vitest, Testing Library, Playwright.

## Global Constraints

- Keep username/password login, 12-hour sessions, `viewer`/`operator`/`super_admin`, campus scoping, and every existing admin operation.
- Do not expose `service_role`, raw SQL, arbitrary table access, or the admin token to browser JavaScript.
- Only HTTP 401 logs the browser out; 403 and transient errors remain visible without clearing the session.
- Use pessimistic mutations for moderation and destructive actions.
- Replace `/admin` directly; do not add `/admin-next` or `/admin-legacy`.
- Do not change iOS client contracts or ordinary App RLS policies.
- Preserve `.hermes/`, the untracked root `AGENTS.md`, and unrelated worktree state.

---

### Task 1: Contract and Test Foundation

- Pin React-admin, ECharts, Vitest, Testing Library, Playwright, jsdom, and Wrangler in `site/package.json` and the lockfile.
- Add `typecheck`, unit-test, and E2E scripts plus Vitest/Playwright configuration.
- Extract the exact legacy admin action list and create a failing contract test for the future resource/action registry.
- Add shared frontend contracts for admin roles, permissions, API metadata, structured errors, global search, and export requests.
- Keep the public website build green.

### Task 2: Database Security and Runtime Migrations

- Add a forward-only migration for `admin_login_attempts`, dual 15-minute rate limits, 90-day retention, audit metadata columns, search indexes, and atomic semester/national-calendar activation RPCs.
- Restrict new tables/functions to `service_role` and preserve existing RLS.
- Add SQL tests for role grants, rate limits, active-row invariants, and migration replay.
- Update the schema ledger.

### Task 3: Admin Edge Contracts and Domain Split

- Centralize role-to-resource permissions so login, me, actions, and export share one server-side source of truth.
- Extend login/me responses additively with permissions and session expiry.
- Split `admin-community` into domain modules while preserving all 60 legacy action names and response data.
- Return `{ data, meta: { request_id, audit_logged, duration_ms } }` and record authenticated failures without silently swallowing audit failures.
- Add Deno tests for registry parity, authorization, validation, and error metadata.

### Task 4: New Actions and Controlled Export

- Add `globalSearch`, `listAdminSessions`, `revokeAdminSession`, `listNationalCalendarRuntimeConfigs`, and `upsertNationalCalendarRuntimeConfig`.
- Enforce query length 2-100, at most 8 results per resource and 40 overall, role/campus filtering, and non-sensitive summaries.
- Add `admin-export` with fixed resource/column allowlists, a 10,000-row limit, UTF-8 BOM CSV, role/campus filtering, and audit logging.
- Add focused Deno tests for each new boundary.

### Task 5: Cloudflare Same-Origin Admin BFF

- Add `/api/admin/login`, `/me`, `/logout`, `/actions`, and `/export` in a Pages Function.
- Store `leafy_admin_session` as `HttpOnly; Secure; SameSite=Strict; Path=/api/admin` and never return the raw token.
- Require same-origin `Origin` and `X-Leafy-Admin-CSRF: 1`, generate a UUID request ID, and proxy structured errors.
- Add unit tests for cookies, CSRF/origin checks, request routing, 401/403 behavior, and CSV proxying.
- Add local Wrangler scripts and update `_routes.json`.

### Task 6: React-admin Shell and Existing Resources

- Replace the monolithic `AdminConsole` with modular app, provider, resource, component, and contract folders.
- Implement custom auth/data/access-control providers and a local Chinese message dictionary.
- Use the Leafy `#249361`/`#3ecf8e` compact desktop theme and real `/admin/*` routes.
- Rebuild dashboard/manual, campuses, posts, polls, comments, reports, profiles, feedback, announcements, postgraduate, suggestions, teachers, courses, dishes, ratings, admins, and audit logs.
- Replace every native prompt/confirm with validated MUI dialogs; keep page size 20 with 20/50/100 options.
- Add component tests for all resource mappings and representative high-risk flows.

### Task 7: Dashboard and Global Tools

- Rebuild the existing 7/30/90-day overview with tree-shaken, lazy-loaded ECharts without inventing new metrics.
- Add campus-aware global search navigation, controlled CSV downloads, admin-session management, semester configuration, and national-calendar configuration.
- Enforce the viewer/operator/super-admin export matrix in both UI and server.
- Add Playwright flows for authentication, campus switching, moderation, catalog editing, configuration, search, export, and session revocation.

### Task 8: Verification, Documentation, and Release Readiness

- Run typecheck, unit tests, E2E tests, production build, Deno tests, and local Supabase migration/database tests.
- Add CI jobs for the new checks without weakening existing jobs.
- Update admin setup/deployment docs, `schema-ledger.md`, and tracked project agent documentation where applicable.
- Document CLI and Supabase Dashboard fallback steps, ordered deployment, production smoke checks, and forward-compatible rollback.
- Perform whole-branch code review and resolve all critical/important findings before handoff.
