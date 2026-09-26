# Admin backend reliability

The current `/admin` site calls the private Worker `AdminAPI` through a Pages service binding.
`backend/src/admin-router.ts` registers 73 actions; `backend/scripts/check-client-contracts.ts` checks the website's action names against that registry. Registration checks complement business tests and do not prove all behavior.

## Write boundaries

- `backend/src/db.ts` and admin write modules use D1 atomic batches with current role, session and state guards. Related business changes, audit records and change signals commit together.
- Catalog approval reuses normalized campus-scoped rows. Null initial ratings create no rating.
- Reports never hide content implicitly. Content changes only through explicit moderation.
- Author-deleted posts and comments remain terminal.
- Publication recovery requires every declared image and attachment; attachment-only posts are supported.
- Poll deletion uses the website's `decision` field and only reviews pending requests.

## Request and error contract

Browser traffic passes through same-origin Pages Functions with HttpOnly cookies, Origin and CSRF checks. The private service binding replaces the former shared proxy secret. Public Worker HTTP routes cannot reach admin actions.

Expected validation and state failures return 400/404/409 responses, with sanitized infrastructure failures and a request ID. Import mode blocks admin reads and writes. Read-only mode prevents mutations. Unknown action names are rejected before dispatch.

## Verification and release

Run backend type checks, client contract checks, business tests, migration tests and the Worker dry-run build. Deploy required forward D1 migrations before the Worker and dependent website. Never overwrite active data with an old import snapshot or automatically approve real pending content as a test.

The old Supabase service remains independent for old clients. Current backend deployment instructions are in [Cloudflare migration](cloudflare-migration.md).

## User counting scope

Operational profile lists, exact pagination totals, search, CSV exports, overview cards and daily trends exclude `profiles.is_demo`. The generated classification covers legacy and installation review identities and is not client-editable. Demo accounts remain available to authentication and community workflows.
