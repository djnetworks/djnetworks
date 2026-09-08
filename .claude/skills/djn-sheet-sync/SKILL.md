---
name: djn-sheet-sync
description: The Google Sheet link for DJ Network's — read-only mirror out, bulk catalogue import in. Use when adding a table or column to the mirror, building or debugging the catalogue importer, or when a push or pull fails.
---

# Google Sheet link

Two lanes, opposite directions, deliberately asymmetric.

## Out — read-only mirror

Inventory, orders, ledger and the `v_` analysis views pushed to a Sheet so the owner can pivot and
slice freely without touching the app.

**Read-only is the whole point.** If the Sheet could write back, the Sheet and the database would
disagree, and there would be no way to know which was right. Every push is a full replace of the
mirrored range, never a merge.

Mirror these:

| Sheet tab | Source |
|---|---|
| Products | `product` joined to category/subcategory |
| Units | `v_unit_status` joined to location names |
| Orders | `rental_order` with customer name and line count |
| Ledger | `ledger_entry` with customer name |
| Balances | `v_customer_balance` |
| ROI | `v_product_roi` |
| Utilisation | `v_unit_utilisation` |

## In — bulk catalogue import

This is the important lane. The catalogue is empty, the fleet runs to hundreds of items, and typing
them through a web form one at a time will stall. The Sheet is the realistic path.

A staging tab, validated before anything is written:

**Products tab** — `short_code`, `category`, `subcategory`, `brand`, `model_name`, `model_number`,
`tracking_mode`, `rentable` (optional, default true), `base_rate_per_day`, `default_purchase_cost`,
`pieces` (how many units to create), `image_url` (optional), plus free-form spec columns folded into
`specs` jsonb.

**Validation before import, not after:**
- `short_code` unique, and not already used by a different product
- `category` / `subcategory` exist in the taxonomy — reject rather than silently creating
- `tracking_mode` is one of unit / pool / consumable
- `pieces` is only meaningful for `tracking_mode = unit`
- `rentable` parses as a boolean — accept `TRUE`/`FALSE`, `yes`/`no`, `1`/`0` and blank, because a
  Sheet column typed by a person will contain all of them. **Blank is not false**, it is "use the
  default below"; a row that means false has to say so.
- money columns parse as numbers, including when the Sheet has formatted them as text with ₹

**`rentable` defaults to FALSE for the `Tool & spare` category, and true everywhere else.** The
database column defaults to `true` (`0001`), which is right for a form where a person is looking at
one product — and wrong for an import of two hundred rows, where the ladders and the spanners
arrive silently offered for hire. `ask.html` would then quote a customer a stepladder, and nothing
on any screen would look wrong.

Two things this rule is deliberately not:

- **Not consumables.** Fog fluid, tape and batteries are issued, charged and never expected back —
  genuinely rentable, and the `consumable` tracking mode already says the rest. Only `Tool & spare`.
- **Not a database default that varies by category.** That was considered and rejected: a rule
  living in a schema default is invisible at the call site and nobody can see why their spanner
  came back unhireable. In the importer it is overridable — a row that says `TRUE` wins — and it
  gets reported, which is the point below.

**Report the defaulted rows, do not just apply the default.** The import summary names every row
where `rentable` was left blank and set false by category, e.g. *"14 Tool & spare rows imported as
not for hire — set rentable TRUE in the sheet and re-import any you do hire out."* A default that
happens silently is a rule nobody can see, which is the objection to putting it in the schema; a
default that announces itself is a suggestion the operator can overrule.

Report every rejected row with its reason, and import the rest. An all-or-nothing import of 200 rows
that fails on row 3 is how people give up.

**Units are generated, not listed.** A product row saying `pieces: 6` creates units 1 to 6, each
with an opening `intake` movement to the stated location. Never ask the operator to type 200 unit
rows — that is the exact task that has stalled every previous attempt.

**Images.** An `image_url` in the import is fetched, stored in the `product-images` bucket, and
recorded in `product_image` with `source = 'import'`. It is never stored as an external link; a
WhatsApp or Drive URL will rot and the customer portal would show a broken product.

## Platform facts, tested rather than assumed

These were established by experiment during earlier work on this business. Several contradict
common advice.

| Finding | Detail |
|---|---|
| xlsx → Sheets import preserves | formulas, named ranges, cross-sheet refs, validation, conditional formatting |
| **ARRAYFORMULA does NOT survive** the import | every such cell becomes `#ERROR!`. Confirmed twice. Anything using it must be created in Sheets, not imported. |
| Table structured references work | `EQUIPMENT[Status]` syntax is supported |
| `#This Row` is NOT supported | per Google's own docs — a formula cannot reference its own row through a table reference |
| Table refs do not work in conditional formatting, charts or pivots | named ranges have neither limitation |
| List-validation ignores blank cells | so a source range can be oversized without showing empty options |
| Google Forms can only be created by Apps Script | no remote API in this environment |
| A Google Form cannot validate before submitting | it can report a double-booking afterwards, never refuse one |
| The Drive connector carries files inline as text | binary files corrupt in transit — spreadsheets must be delivered to the local machine or uploaded by hand |
| Apps Script free tier | ~90 minutes runtime, 100 emails/day — far above this business's needs |
