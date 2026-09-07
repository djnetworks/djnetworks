# DJ Network's — Rental System

Equipment rental for DJs and events, Ahmedabad. Run by one person who does **all** data entry;
one labour staff member does the physical work and enters nothing. There are no departments, no
second data-entry user, and nobody to catch another person's mistake. Every design decision
assumes that.

Read `docs/structure.md` before designing anything. Read `docs/decisions.md` before proposing a
change to a decision already made — each one records what it cost, and most were argued.

---

## Stack

- **Supabase** (Postgres + Auth + Edge Functions) — project ref `hjidocpqcrfbjucvqggu`, region `ap-south-1`
- **Static HTML frontend**, no build step, same pattern as the Maitri exhibition app
- **Google Sheets** two-way link: read-only mirror out, bulk catalogue import in

**The publishable key is public, and RLS is the only thing behind it.** Supabase now issues a
`sb_publishable_...` key rather than an anon JWT. It ships inside the static frontend, so anyone who
opens the page source has it — it is not a secret and there is no version of this system where it
becomes one. Every protection this database has is a row level security policy. That is the reason
the portal is built on a `security definer` function keyed on a per-customer token and never on
anonymous table access: opening anon SELECT on any table to make a screen work publishes that table
to the internet. The real key lives in `.env`, which is gitignored; `.env.example` carries the shape
only.

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

14. **A gated view returns zero ROWS, not zero rupees.** Any aggregate over a permission-gated
    table must fail loudly rather than return a plausible number. `v_customer_balance` left-joins
    `ledger_entry`, so letting RLS hide those rows would have shown every customer owing ₹0.00 —
    and every customer owing nothing looks like good news, so nobody investigates it. Zero rows is
    a refusal a screen can recognise and explain; zero rupees is a lie with a decimal point. This is
    why `0021`'s gated views are wrappers carrying an explicit permission test.

15. **A fallback that assumes one cause hides every other cause.** `dispatch.html` reported a code
    bug as "no signal" for a whole commit, because its catch assumed offline and logged nothing —
    and the bug it was hiding was a wrong quantity leaving the godown. A fallback logs the real
    error and only claims a cause it has evidence for: if `navigator.onLine` is true, it is not the
    signal.

16. **A probe must reproduce the real call shape** — same batch size, same transaction boundary,
    same page state. `0022`'s probe inserted one row per statement while the app inserts a batch,
    so it proved the constraint worked on a shape the app never uses, and shipped a bug that told
    the operator a write had already happened when nothing had been written. A test that does not
    reproduce the real conditions runs clean and proves nothing. This is rule 10's lesson wearing
    new clothes: the danger is never the failure you can see, it is the confident wrong answer.

17. **When a shared helper's contract changes, grep every caller and DRIVE one of each.**
    `openSheet` has now broken its callers twice — once when three screens passed the wrong markup
    shape and could never save, once when it required a `#sheet-host` div that five of twelve pages
    carry and threw on null inside a click handler, silently. Each file still parsed both times.
    Only running one shows the break.

---

## Who applies schema changes

**Only this repo.** Migrations live in `supabase/migrations/` and are applied from here.

Two agents with write access to one database produces a schema that no longer matches its own
migration history. Do not apply ad-hoc DDL from anywhere else.

**There is no second pair of eyes on this database any more.** The Cowork chat's Supabase connector
is bound to the OLD account and cannot reach project `hjidocpqcrfbjucvqggu` at all — not to write,
not to read, not to check a number. It used to be the independent read-only session that could
confirm a view returned what this repo claimed it returned. It cannot do that now.

So all schema work and all verification happen in one place, which means **whoever writes the
migration is also the only one who checks it.** That changes what a passing test is worth. A clean
run now proves only that the code agrees with itself — the same assumption that produced the wrong
answer will produce the wrong assertion, and there is nobody holding a different copy of the truth.

The mitigations, and they are weaker than a second session:
- Assert on **numbers**, never on the absence of an error. A previous workbook recalculated with
  zero errors while silently reading the wrong rows.
- Verify against a **throwaway local replay** of the migrations, not only against the live database,
  so at least the two are independently constructed.
- Prefer probes that **roll themselves back** and state the expected value before reading the actual
  one, so a wrong expectation is visible rather than absorbed.
- When a result matters, reconstruct it a **second way** — hand-count the rows the view aggregates.
- Treat `guardrail-reviewer` and `logic-verifier` as the substitute for the second session, and give
  them the failure to hunt for rather than asking whether the code looks right.

---

## Conventions

- Migrations are numbered `NNNN_short_name.sql`, never renumbered, never edited once applied.
- Prefer `text` + `CHECK` over Postgres enums — the operator wants to add and remove values himself,
  and altering an enum in Postgres is painful.
- All money is `numeric(12,2)`. Never float.
- All dates that mean a calendar day are `date`, not `timestamptz`. The rental day convention is a
  calendar convention, not a clock one.
- **In the client, a calendar day comes from `todayLocal()`, never `new Date().toISOString()`.**
  `toISOString()` is UTC: before 05:30 IST it names *yesterday*, and 6am is exactly when a job gets
  booked. It shipped once in `orders.html` and defaulted a new order's out date to the day before;
  it was found by reading the date on a repeated job, not by a test. The same applies to
  `current_date` in SQL called from the browser — that is UTC too, which is why every movement
  carries the phone's local date.
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
