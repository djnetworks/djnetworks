# DJ Network's — Rental System

Equipment rental for DJs and events, Ahmedabad. Run by one person who does **all** data entry;
one labour staff member does the physical work and enters nothing. There are no departments, no
second data-entry user, and nobody to catch another person's mistake. Every design decision
assumes that.

Read `docs/structure.md` before designing anything. Read `docs/decisions.md` before proposing a
change to a decision already made — each one records what it cost, and most were argued.

---

## Stack

- **Supabase** (Postgres + Auth + Edge Functions) — project ref `ghylakhhsdvnkopmjteo`, region `ap-south-1`
- **Static HTML frontend**, no build step, same pattern as the Maitri exhibition app
- **Google Sheets** two-way link: read-only mirror out, bulk catalogue import in

---

## Rules that are not negotiable

These are not style preferences. Each one exists because breaking it has already cost a real build.

1. **Location is derived, never stored.** A unit's current location is the destination of its last
   `movement` row. Never add a `current_location` column to `unit`. There is no field to forget to
   update, so the location cannot rot.

2. **An unreturned unit is out, whatever the date says.** A unit with a `dispatch` movement and no
   matching `return` is unavailable, regardless of `expected_return_date`. Never infer a return from
   a date passing. This is the single most expensive bug found in a previous build: six boxes went
   out, five came back, and the sixth was quietly offered for hire while it sat in a hall.

3. **Condition and status are separate axes.** `unit.condition` is a hand-assessed physical state.
   Status is derived from movements plus `unit.lifecycle`. A unit can be out on rental *and* showing
   minor wear. Never merge them into one dropdown.

4. **Piece numbers are never reused.** When a unit is lost or retired its `piece_no` dies with it.
   A replacement takes the next free number. History stays attached to the physical object.

5. **The order line stores its agreed price.** `order_line.agreed_rate` and `line_total` are written
   at the time of agreement. Rates on `product` generate a *default*; they are never a lookup for a
   historical read. Raising a rate must not rewrite what was charged last year.

6. **Receivable and deposit held are never merged.** A deposit is the customer's money being held —
   a liability, not revenue. Two separate numbers on every screen and on the portal.

7. **Customers and vendors are not locations.** `movement.from_kind` / `to_kind` is one of
   `location`, `customer`, `vendor`. Never insert a customer into the `location` table.

8. **Every screen is product-first.** Chachu's stickers carry a bare piece number (`3`) with no
   product code, so a sticker alone cannot identify a unit. Pick the product, then the number.
   Never design a flow that starts with scanning or typing a unit ID.

9. **An order cannot close while a unit is outstanding.** Closing requires an explicit found,
   write-off, or loss. Never a side effect of a date passing or a bulk action.

10. **Nothing is stored that can be counted.** Pieces owned, available now, customer balance, days
    out — all views. A stored count and its source will disagree, and the wrong one will be believed.

11. **Never store full Aadhaar or PAN numbers.** There is deliberately no column for them. ID
    documents live in cloud storage; the database holds a URL. Do not add an ID-number column.

12. **History is never deleted.** Orders are cancelled, not removed. Units are retired, not deleted.

13. **Every path that touches inventory handles all three tracking modes.** A view, a query or a
    screen that assumes `unit_id` is present will lie about cables. Pooled and consumable products
    have no numbered pieces, so anything joining `v_unit_status` finds nothing and reports *zero*
    rather than reporting *nothing* — a confident wrong number, which is the worst kind. Migration
    `0008` exists because four places had this same bug at once: `fn_availability`,
    `v_product_stock`, `v_order_outstanding_units`, and a shrinkage path that did not exist at all.
    They were one design flaw, not four — `unit` was built first and `pool` was bolted on beside it.
    Read pooled quantities through `v_pool_stock` and never re-derive them somewhere else.

---

## Who applies schema changes

**Only this repo.** Migrations live in `supabase/migrations/` and are applied from here.

A Cowork chat also has the Supabase connection, but it is **read-only** for that session: querying
data, checking a view returns the right numbers, running analysis. If a schema change is needed
there, it is written as a migration file in this repo and applied from here.

Two agents with write access to one database produces a schema that no longer matches its own
migration history. Do not apply ad-hoc DDL from anywhere else.

---

## Conventions

- Migrations are numbered `NNNN_short_name.sql`, never renumbered, never edited once applied.
- Prefer `text` + `CHECK` over Postgres enums — the operator wants to add and remove values himself,
  and altering an enum in Postgres is painful.
- All money is `numeric(12,2)`. Never float.
- All dates that mean a calendar day are `date`, not `timestamptz`. The rental day convention is a
  calendar convention, not a clock one.
- Views are prefixed `v_`, functions `fn_`.
- Business conventions that could change (day counting, availability buffer) live in `app_setting`,
  not in code.

---

## Conventions that carry over from the Maitri app

- Migrations are create-or-replace where possible, so re-running is safe.
- Revoke before grant when changing function permissions.
- CHECK constraints silently reject writes — when a write "does nothing", check the constraint first.
- Static frontend needs cache-busting on deploy or staff see an old version.

---

## Verification standard

**A clean run is not proof of correctness.** A previous workbook recalculated with zero errors while
silently reading the wrong rows; the bug was only found by hand-checking values. Any test of the
availability engine, the return logic, or the ledger must assert on *numbers*, not on the absence of
errors.

Test data must be anchored to dates around today. Sample records dated in the future never exercise
the status logic at all — this has already wasted real time.

---

## Current state

The catalogue is **empty**. Hundreds of items exist physically; nothing is listed. Bulk import
through the Google Sheet is the intended path. Do not build features that assume a populated
catalogue without seeding realistic test data first.
