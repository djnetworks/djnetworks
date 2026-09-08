# Open questions

Ordered by what they block. Items 1 and 3 are blocking; the rest can be answered while building.
Items 9-11 were exposed by drafting the seven questions for chachu, not by building — asking is
cheaper than discovering.

---

## 1. Which system is authoritative for receivables — BLOCKING the ledger and portal

The owner says accounts live on separate software. This system also records payments and shows
customers a live balance. That is two systems recording the same receipt, and they will disagree
within a month.

**Proposed:** this system owns the operational receivable and feeds the accounts package by export
rather than by parallel typing. Not yet confirmed.

**Also needed:** what the accounting software actually is. If it is Tally, the export shape is a
solved problem.

---

## 2. Portal authentication

Static ID and password was requested. The cost is stored credentials, a reset flow, and a stream of
one-off wedding customers who will never remember a password and will message chachu instead — at
which point the portal goes unused.

**Alternative on the table:** phone number as the identifier, one-time code as the password. Same
gate, nothing to remember or reset, no credentials to leak.

Until this is settled, the portal is built on a `security definer` function keyed on a per-customer
token. Do not implement it with anonymous table access under any circumstances.

---

## 3. The catalogue does not exist — BLOCKING everything downstream

Hundreds of items physically. Three marketing flyers. No list, no spec sheets, no inventory record
of any kind. Three previous builds died here, and none of them failed on technique.

**First pass should capture almost nothing:** product, piece count, location. Serial numbers,
purchase dates and specifications are all optional and all slow, and a half-finished serial-number
column abandoned at unit 40 is worth less than none.

**The stickers matter more than the spreadsheet.** If the number is not physically on the case,
unit-level tracking collapses back into guesswork.

---

## 4. Confirm the day-count convention with chachu, in his own words

Currently `inclusive_both_ends` in `app_setting`: out on the 2nd, back on the 4th is 3 days.
It changes the price of every job and has never been confirmed by the person who quotes.

---

## 5. Actual discount percentages

The tier boundaries (1 / 2–3 / 4–7 / 8+) came from an earlier planning document. The percentages
seeded in `0004` are all zero placeholders.

**Two things now hang off this unanswered question, added with the customer default discount
(`0031` / `0032`, 8 Sep 2026):**

- **The ladder now stacks with a per-customer default.** `customer.default_discount_pct` is a
  starting point copied onto each order line and added to the tier for that line's length of hire
  (20% customer + 15% for eight days = 35% off). While the ladder is four zeros the customer default
  is the only discount in play — but the first real tier percentage typed here reprices every future
  order *on top of* whatever customer defaults exist by then. Fill it in knowing that, not as an
  isolated number.
- **`max_total_discount_pct` = 40 is an invented ceiling.** `0032` seeds a soft ceiling: the orders
  screen warns (never blocks) when a line's total discount passes it. 40 is a placeholder chosen low
  enough to fire at least once, not a figure from the business. It needs the same confirmation as the
  tier percentages — and if the tiers land high, 40 may be too low and become noise.

---

## 6. Prune the taxonomy

187 subcategories were drafted in an earlier planning session, not by the owner. He needs to walk the
list and strike out what the business does not own, or the product master offers 187 choices for a
fleet that probably spans 40.

---

## 7. Are microphones swapped between kits

The kit-is-the-unit decision assumes a body pack, receiver and mic stay together. The two Shure
flyers differ *only* in the microphone, which suggests they might not. If mics move between kits
routinely, the inclusion-list workaround will start to hurt.

---

## 8. Does chachu hire out tools, ladders and generators

`product.rentable` exists (`0001`, `boolean not null default true`) and is wired end to end: a
checkbox on the product form, a badge in the list, and filtered out of both `ask.html`'s
availability check and `orders.html`'s line picker. So the answer costs a tick per product, not a
migration.

**What is NOT true, and this line used to say it was:** nothing is currently flagged. `0005`'s
"Tool & spare is additionally flagged not rentable" is a *comment recording intent*, not a
statement that runs — `rentable` lives on `product` and `Tool & spare` is a **category**, and
`category` has no such column. Every product in the fixture is `rentable = true`. Whoever creates
a tool or a ladder has to untick the box by hand, and nothing reminds him.

**The import half is now answered, and the answer is not a schema default.** The bulk importer
defaults `rentable` to FALSE for `Tool & spare` and true everywhere else, and reports every row it
did that to; the product form starts a NEW product in that category unticked and says on screen
what either answer means. Consumables are untouched — fog fluid is charged to the customer and is
genuinely rentable. A category-varying **database** default was considered and rejected: a rule
living in a column default is invisible at the call site, and nobody can see why their spanner came
back unhireable. In the importer it is overridable, visible and announced. See the `djn-sheet-sync`
skill and `openEditor` in `products.html`.

**What is still open:** does he hire out generators, ladders and tool kits at all? Power is
unit-tracked and rentable today, which is probably right, but the boundary is a guess — and it is
the boundary, not the mechanism, that only he can settle.

---

## 9. "On the order but not counted" has no tracking mode

Asking chachu how to hold cables, stands and clamps exposed a third answer the schema cannot
express. `pool` counts them and `consumable` charges them and never expects them back; "write it on
the order so it is priced and remembered, but do not keep a running count" is neither. The nearest
thing available — a pooled product with no stock recorded — reports **zero available** and blocks
the order, which is the opposite of what he would mean.

If that is how he actually works for the low-value long tail, it is a fourth mode or a
`counts_stock` flag on `pool`, not a workaround.

---

## 10. Should `discount_tier` exist at all

Item 5 asks what the percentages are. That assumes the answer is a number, and it may not be. If
long-hire pricing is negotiated per party rather than by slab, the table is dead weight: rule 5
already writes the agreed rate onto `order_line`, so nothing is lost by deleting it and quite a lot
of confusion is avoided by not carrying a rate card that nobody applies.

Ask which of the two it is **before** asking for percentages, because "har party se alag" is not a
variant of the same answer — it deletes the table.

---

## 11. "Gujarati mein chahiye" is two questions, and one of them is a project

- **His vocabulary.** Trade words instead of software words — already the standing rule, and
  already partly done ("Send out", "Came back", "Equipment"). More of it is a copy pass, an
  afternoon.
- **Translating the app.** Gujarati strings across 13 HTML files and `app.js`, with no i18n layer of
  any kind today — every string is inline in markup. That is a project, and it also raises a
  question nobody has asked: does the *customer portal* change language too, and per customer?

Find out which he means before agreeing to it. They cost two different things.

---

## Parked — may never matter

Crew and operator assignment · quotations before a booking exists · delivery challans ·
preventive maintenance schedules.
