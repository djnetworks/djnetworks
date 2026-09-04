# Open questions

Ordered by what they block. Items 1 and 3 are blocking; the rest can be answered while building.

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

Tool & spare is currently flagged not rentable. Power (generators, distribution boxes, stabilisers)
is unit-tracked and rentable, which is probably right — but the boundary is a guess.

---

## Parked — may never matter

Crew and operator assignment · quotations before a booking exists · delivery challans ·
preventive maintenance schedules.
