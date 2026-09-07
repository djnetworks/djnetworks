# DJ Network's — Rental System

Equipment rental management for DJ Network's, Ahmedabad. Supabase + static HTML.

- **Start here:** `CLAUDE.md` — the rules that are not negotiable, and why each one exists.
- **The design:** `docs/structure.md` — 17 tables, 12 forms, the derived views.
- **What was decided and what it cost:** `docs/decisions.md`
- **What is still unanswered:** `docs/open-questions.md`
- **Found and not fixed:** `docs/backlog.md`
- **Where the look comes from:** `docs/design.md` — provisional tokens, and what is still missing.
- **Verification that rolls itself back:** `supabase/probes/` — three, each asserting on numbers or status codes and each carrying a false-positive control.

## Status

**Access control is granular permissions, not a role and not a signup toggle.** `0017` made
membership of the `operator` table the thing every policy tests; `0021` made *which* permission the
thing they test. Eleven keys, one `fn_has_permission()` choke point, every table. Measured both
ways: the owner reads and writes everywhere, a staff account holding only `sendout.write` and
`returns.write` reads **0** ledger rows and is refused on all fifteen other tables, and an account
with no `operator` row reads **0** rows from every one of the seventeen. That is what makes the
publishable key safe to ship in the page source, which it must be. It is not a reason to publish the
repo — see Hosting below.

**A movement can be taken back, and taking it back is itself a record.** `0019` added a
`correction` movement that names the row it undoes; nothing is ever deleted and nothing is ever
edited, because `DELETE` on `movement` is blocked and `UPDATE` is refused by the append-only guard.
A correction may only name the **current tip** for that piece — you may peel the tip, you may never
reach into the middle — and `0020` makes the reason mandatory, because a mechanism that can walk
history backwards indefinitely is protected by one sentence. `v_movement_effective` is the single
place that knows what still counts, and every derived view reads it.

**Damage photographs live in a second, private bucket.** `0028`. The catalogue bucket is public
because the portal shows it; a photograph taken inside a customer's wedding hall is not ours to
publish at a guessable URL. Opened by `returns.write` or `ledger.view` only, through signed URLs
that last two minutes, and never by the portal — the migration fails at apply time if the portal
function ever names the column. Proved with real HTTP rather than by reading the policy: anonymous
with no key, anonymous holding the publishable key, the guessed public-object URL, and a signed-in
account with neither permission are all refused, while the operator uploads, signs and reads — and
the signed link stops working when it expires. `supabase/probes/0028_return_photos_probe.sh`, 14
assertions, self-cleaning.

**Driven end to end by a signed-in operator on 2026-09-07.** A complete job was walked through the
browser — product, six pieces, customer with a portal code, an order for four, a dispatch of two,
availability reading 2 (not 0, not 4), a damaged return with the deposit deduction and the excess
billed as a charge, a close refused while a piece was still out, the close, a payment, and the portal
at phone width showing receivable and deposit as separate figures. Offline was exercised for real:
prefetch in signal, dispatch with no connection, queue surviving a page teardown, replay on
reconnect, movements landing. Access control is enforced by an `operator` allowlist (`0017`), not by
a signup toggle — a stranger who self-registers reads zero rows from every table.

**Hosting: Cloudflare Pages**, connected to this private repo, auto-deploying on push to `main`.
No build step — build command empty, output directory `web`. GitHub Pages was rejected rather than
merely unavailable: on a free plan it requires the repo to be public, and publishing the repo would
publish `docs/`, the backlog and every migration. `0017` makes the publishable key safe to ship;
that is not a reason to ship the schema. Cache-busting on every deploy is in the `djn-deploy` skill
and it has three steps, not one.

What exists:

| | |
|---|---|
| Database | 17 tables, 15 views, 31 functions, 2 storage buckets — one public catalogue, one private for damage evidence. Migrations `0001`–`0028`, applied to `hjidocpqcrfbjucvqggu` (ap-south-1). |
| Screens | 13 static pages under `web/`, no build step. Twelve behind an operator sign-in, plus the customer portal. Eleven of the twelve forms have a screen — repair is the one that does not. Bottom navigation, re-flowed at login to the modules each person holds. |
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
