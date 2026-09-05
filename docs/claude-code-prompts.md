# Prompts for Claude Code

Run these in order from `~/dj-networks`. Each one is self-contained — paste it whole.

Two habits worth keeping throughout:

- **Say what "done" looks like.** Every prompt below ends with acceptance criteria. Claude Code will
  otherwise declare victory on something that compiles.
- **Never accept "tests pass" as an answer.** Ask for the numbers.

---

## 0 · Open the project

The repo already lives in `~/Documents/Dj-Networks`. Add only that folder in Claude Code.

```bash
cd ~/Documents/Dj-Networks && claude
```

`reference/` holds the source material: the three product flyers, the old planning workbook the
taxonomy came from, the MIS requirement PDF, and the original context document. It is input, not
code — nothing there is authoritative over `docs/`.

---

## 1 · Bootstrap the database

```
Read CLAUDE.md, docs/structure.md and docs/decisions.md before doing anything.

Link this repo to Supabase project ghylakhhsdvnkopmjteo and apply the six migrations in
supabase/migrations/. They have never been run — expect errors and fix them by editing the
migration files (nothing is applied yet, so editing them now is correct; once applied, they
are frozen).

Use the migration-writer agent for any SQL you change.

Then verify by hand, not by trusting the push:
- list every table, view and function that now exists and compare against docs/structure.md
- run fn_availability against a product with no units and confirm it returns 0, not null or an error
- confirm the movement append-only trigger actually refuses an UPDATE and a DELETE
- run get_advisors for security and performance and report everything it says

Done when: all six migrations are applied, the object list matches the doc, and you have shown
me the advisor output rather than summarising it.
```

---

## 2 · GitHub

```
Create a private GitHub repo called dj-networks, add it as the remote, and push.

Do not commit .env or any key. Confirm .gitignore covers it before pushing.
```

---

## 3 · Harden the schema — migration 0007

Bootstrapping surfaced four things worth fixing before any data exists. Do them now: the first is a
live hole in rule 12, and the second makes the availability screen lie the moment a cable goes on an
order.

```
Write migration 0007 fixing four things you found. Use the migration-writer agent. Do not touch
0001-0006 — they are applied and frozen.

1. Block DELETE on rental_order and on unit, the same way movement is guarded. History is
   cancelled or retired, never removed (CLAUDE.md rule 12). Right now a confirmed but
   undispatched order can be hard-deleted, its lines and charges cascade away and its ledger
   entries orphan to order_id = null. Every order passes through that state.

2. Make fn_availability handle all three tracking modes. It currently returns 0 forever for
   pool and consumable products, which means the screen will lie the moment cables go on an
   order. Branch on product.tracking_mode:
     - unit       : current logic, unchanged
     - pool       : pool_qty, less net quantity currently out (dispatch qty minus return qty),
                    less quantity committed on overlapping confirmed orders
     - consumable : pool_qty less total quantity issued. No date overlap logic — consumables
                    are never expected back, so there is nothing to return and nothing to
                    reserve against a future date.
   Keep the same return shape so existing callers do not break.

3. Fix movement_unit_or_qty. It is a tautology — qty is already NOT NULL CHECK (qty >= 1), so
   it can never fail and does not enforce what its comment claims. Either make it enforce the
   real invariant (unit-tracked movements carry a unit_id, pooled ones do not) or drop it and
   remove the misleading comment. Tell me which you chose and why. A constraint that cannot
   fail while claiming to enforce something is worse than no constraint.

4. Set search_path = public, pg_temp on all three functions to clear the advisor warnings.

Then: fix the README table count (it says 15, there are 16 — product_image arrived in 0006),
and renumber docs/claude-code-prompts.md so this becomes prompt 3 and seeding becomes prompt 4.

Verify by hand afterwards, with numbers:
- prove DELETE is refused on both tables, with a probe that rolls itself back
- prove fn_availability returns a sensible non-zero figure for a pool product with pool_qty set
- re-run get_advisors and show me that security is clean

Done when: 0007 is applied, all four are demonstrated with actual output, and the security
advisor shows no findings.
```

---

## 4 · Seed realistic test data

Do this *before* any screen. Every screen you build after this will be built against data that
exercises the logic, instead of an empty table.

```
Create supabase/seed/dev_seed.sql with realistic test data. This is dev data, never applied to
production.

Requirements, all of which matter:
- 8-10 products across several categories, including at least one pool product (XLR cable) and
  one consumable (fog fluid), so every tracking_mode is exercised
- units for the unit-tracked products, 2 to 6 pieces each
- 2 customers: one trade regular, one one-off wedding customer
- 5 orders spanning: one confirmed but not dispatched, one fully out right now, one PARTIALLY
  returned with a unit still outstanding, one closed cleanly, one cancelled
- one unit currently at a repair shop
- one unit retired, with a replacement unit that must NOT reuse its piece number

Every date must be computed from current_date. Do not hard-code future dates — test data anchored
to the wrong dates never exercises the status logic, and that has already wasted real time on this
project.

Done when: you show me, as actual query output, the row from v_unit_status for the outstanding
unit proving it reads 'out'.
```

---

## 5 · Verify the logic before building anything on it

```
Run the logic-verifier agent against the seeded database. Work through every scenario in its
brief and report actual numbers for each — setup, expected, got, pass or fail.

I do not want a summary that says tests passed. I want the values.

Pay particular attention to the partial return: the unit that went out and was never recorded
back must read as out even after its expected return date has passed, and fn_availability must
exclude it.

If any scenario cannot be constructed, say so rather than marking it green.
```

---

## 6 · Product and unit screens

```
Build web/products.html and web/product.html — the product master list and detail/edit form,
per docs/structure.md form 2, and unit intake per form 3.

Read the djn-architecture skill first. All reads go through views. Static HTML, no build step,
Supabase JS client from CDN, pinned version.

Requirements:
- specs is JSON, prompted by category — do not build a fixed spec column set
- tracking_mode drives the form: pool and consumable products have a quantity and no piece numbers
- unit intake has BULK CREATE: enter the product, enter "how many pieces", and it creates that
  many units with sequential piece numbers, all at one chosen location, each inheriting the
  product's default_purchase_cost and each writing an opening intake movement
- piece numbers must skip any number already used by a retired or lost unit
- product images: upload from file or phone camera, straight into the product-images bucket

Then run the ui-reviewer agent on both screens and fix what it finds.

Done when: I can add a product, create 6 units in one action, and see all 6 in v_unit_status
as available at the location I picked.
```

---

## 7 · The catalogue import lane

This is the highest-value thing in the whole project. Hundreds of items, no list, three previous
builds dead at exactly this point.

```
Read the djn-sheet-sync skill.

Build the bulk catalogue importer: a CSV/Sheet paste lane that creates products and generates
their units in one pass.

Columns: short_code, category, subcategory, brand, model_name, model_number, tracking_mode,
base_rate_per_day, default_purchase_cost, pieces, location, image_url, plus any extra columns
folded into specs jsonb.

Validation happens BEFORE anything is written:
- short_code unique and not already taken by a different product
- category and subcategory must already exist — reject the row, never silently create taxonomy
- tracking_mode is one of unit / pool / consumable
- pieces only meaningful when tracking_mode = unit
- money columns parse even when the sheet has them as text with a rupee sign

Then import the valid rows and report every rejected row with its reason. Do NOT make it
all-or-nothing: an import of 200 rows that fails on row 3 is how people give up and go back to
paper.

Units are generated from the pieces count, never listed row by row.

Done when: I can paste 20 messy rows including 3 deliberately broken ones, and get 17 products
with their units created plus a clear list of the 3 failures and why.
```

---

## 8 · Orders and availability

```
Build the order screen per docs/structure.md form 6.

Read docs/decisions.md on pricing before you start. The rules that will bite you:
- lines reserve at PRODUCT level with a quantity — no piece numbers on an order
- base rate comes from the product, the discount ladder suggests a percentage, and every number
  after that is editable
- agreed_rate and line_total are STORED. Never recompute them from the current product rate on
  read. Changing a rate must not alter a past order.
- day count comes from app_setting.day_count_mode, not from hard-coded arithmetic
- availability is date-level via fn_availability. If the requested quantity is not available,
  block the save unless the user sets availability_override with a reason.
- deposit is on the order, not the product

Rental charges post to ledger_entry on confirmation with state='upcoming'.

Then run guardrail-reviewer on the diff.

Done when: I can create an order that is refused for over-booking, then override it with a
reason, and see the override recorded on the order.
```

---

## 9 · Dispatch and return

The two screens the whole system lives or dies on.

```
Build web/dispatch.html and web/return.html per docs/structure.md forms 7 and 8.

This is a phone screen used one-handed at a van in a godown, often with no signal. Design for
that, not for a desk.

Dispatch:
- opens FROM the order — never from the catalogue
- for each unit-tracked line, show only units of that product that are available at the chosen
  location, so it is tapping 6 from 8 rather than searching 300
- inclusions checklist per unit (the power cable is what goes missing)
- dispatch method chosen each time: porter / self-collection / delivered by chachu / other,
  with a name and phone captured whichever it is
- receiver name and phone pre-filled from the order's venue contact, editable
- partial dispatch must work — speakers Friday, lights Saturday
- writes one movement per unit, from a location to the customer
- flips the order's ledger entries from upcoming to due

Return:
- each dispatched unit ticked back individually, with condition and inclusions check
- an unticked unit stays OUT. Not overdue — out. Never infer a return from a date.
- return location may differ from where it left
- damage proposes a deduction from the deposit; excess becomes an order_charge
- a lost unit proposes its own purchase_cost, editable
- the order cannot be closed while v_order_outstanding returns anything for it, pooled stock included

Offline: queue both forms in IndexedDB, show pending entries clearly, sync on reconnect, and
survive a page refresh without losing the queue.

Run ui-reviewer and then logic-verifier when both screens are done.

Done when: I can dispatch 6 units, return 5, and the 6th still reads out and is excluded from
availability after its return date has passed.
```

---

## 10 · Ledger, payments, portal

```
Build the customer ledger and payments screen (form 11), then the customer portal (form 12).

Ledger:
- receivable and deposit held are TWO separate numbers, everywhere, never blended
- upcoming is shown separately from due
- payments need not attach to an order

Portal:
- do NOT build this on anonymous table access. Use a security definer function keyed on a
  per-customer token that returns only that customer's data. Anon SELECT on ledger_entry would
  show every customer every other customer's account.
- authentication method is still undecided (see docs/open-questions.md). Build the token-based
  data access now and leave the gate pluggable.
- product names, not piece numbers

Run guardrail-reviewer specifically on the portal data access before you consider it done.
```

---

## 11 · Sheet mirror and analysis

```
Build the read-only Google Sheet mirror per the djn-sheet-sync skill, then the analysis screen
covering ROI, utilisation, hire frequency, dead stock and damage rate.

For ROI: roi_pct is NULL where purchase cost is missing. Show it as unknown and show
units_missing_cost alongside. Never render a null ROI as 0% — that would tell me a product loses
money when the truth is that I have not entered its cost.
```

---

## Prompts worth reusing

**Before any deploy**

```
Run guardrail-reviewer on everything changed since the last deploy, then walk the djn-deploy
check list. Confirm the cache-bust string is bumped.
```

**When something "isn't showing up"**

```
Check the cache-bust version string before debugging anything else. Then compare
supabase migration list against the files in supabase/migrations/.
```

**When you want an honest read**

```
Argue against this design. What breaks first when the fleet doubles, and what have I decided
that you think is wrong?
```
