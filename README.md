# DJ Network's — Rental System

Equipment rental management for DJ Network's, Ahmedabad. Supabase + static HTML.

- **Start here:** `CLAUDE.md` — the rules that are not negotiable, and why each one exists.
- **The design:** `docs/structure.md` — 16 tables, 12 forms, the derived views.
- **What was decided and what it cost:** `docs/decisions.md`
- **What is still unanswered:** `docs/open-questions.md`
- **Found and not fixed:** `docs/backlog.md`

## Status

Ten migrations (`0001`-`0010`) and a development fixture (`supabase/seed/dev_seed.sql`) exist and
were verified against the previous Supabase project. **The project has since moved to a new account
— ref `hkzgxsgokqphthdmbras`, region `ap-southeast-2` — and that database is still empty.** Until it
is replayed, nothing above is live anywhere. No screen exists yet.

**The catalogue is empty** — hundreds of items exist physically, none are listed. Bulk import through
the Google Sheet is the intended path, and it matters more than any screen in the application. The
seed fixture is development data and is not the catalogue.

## Verification, and why it is weaker than it was

The Cowork chat's Supabase connector is bound to the OLD account and cannot reach this database —
not to write, not even to read a number back. It was the independent session that could confirm a
view returned what this repo claimed. It cannot any more.

Everything now happens in one place, so **whoever writes a migration is also the only one who checks
it.** A clean run proves only that the code agrees with itself. See `CLAUDE.md`, "Who applies schema
changes", for what to do instead — assert on numbers, replay locally as a second construction, roll
probes back, and hand `guardrail-reviewer` and `logic-verifier` a failure to hunt rather than a
question about whether the code looks right.

The publishable key in the frontend is **public by design**. RLS is the only thing protecting the
data.

## Layout

`docs/` is authoritative. `reference/` is source material — flyers, the old planning
workbook the taxonomy was seeded from, the MIS requirement document. Read it for context, never
as a spec: two of its assumptions have already been contradicted by how the business really works.

## Setup

```bash
supabase link --project-ref hkzgxsgokqphthdmbras
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
