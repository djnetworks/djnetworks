# DJ Network's — Rental System

Equipment rental management for DJ Network's, Ahmedabad. Supabase + static HTML.

- **Start here:** `CLAUDE.md` — the rules that are not negotiable, and why each one exists.
- **The design:** `docs/structure.md` — 16 tables, 12 forms, the derived views.
- **What was decided and what it cost:** `docs/decisions.md`
- **What is still unanswered:** `docs/open-questions.md`
- **Found and not fixed:** `docs/backlog.md`

## Status

**Not deployed, and deliberately so.** See the BLOCKING entry at the top of `docs/backlog.md`:
self-registration is open on the Supabase project and `authenticated` has full access to all 16
tables, so publishing the page — which necessarily publishes the publishable key — would hand the
database to anyone who reads the source. Turn signups off first, then create the one operator
account.

**Nothing has been driven by a signed-in user yet.** There is no account in `auth.users`. Every
screen's read path, write path and offline behaviour is argued from code and verified at the
database level; none of it has been watched working end to end. Treat it as unproven.

What exists:

| | |
|---|---|
| Database | 16 tables, 9 views, 21 functions. Migrations `0001`–`0016`, applied to `hjidocpqcrfbjucvqggu` (ap-south-1). |
| Screens | 10 static pages under `web/`, no build step. Nine behind an operator sign-in, plus the customer portal. |
| Offline | Vendored Supabase client, service worker for the app shell, IndexedDB for queued writes, explicit per-job prefetch. |
| Sheet | Read-only mirror OUT, deployed as the `sheet-mirror` Edge Function with `sheet/DataSync.gs`. The bulk import lane is NOT built. |
| Fixture | `supabase/seed/dev_seed.sql` — development data, not the catalogue. |

**The catalogue is still empty** — hundreds of items exist physically, none are listed. Bulk import
through the Google Sheet is the intended path and it matters more than any screen. The seed fixture
is test data and is not the catalogue.

## Layout

`docs/` is authoritative. `reference/` is source material — flyers, the old planning
workbook the taxonomy was seeded from, the MIS requirement document. Read it for context, never
as a spec: two of its assumptions have already been contradicted by how the business really works.

## Setup

```bash
supabase link --project-ref hjidocpqcrfbjucvqggu
supabase db push
```

## Agents

| Agent | Use it for |
|---|---|
| `migration-writer` | any schema change |
| `logic-verifier` | availability, returns, day counting, ledger — asserts on numbers |
| `guardrail-reviewer` | reviewing a diff against bugs that have already shipped here |
| `ui-reviewer` | loading, empty and error states, navigation, phone flows |

## Skills

`djn-architecture` (where logic belongs) · `djn-deploy` (shipping) · `djn-sheet-sync` (the Sheet link)
