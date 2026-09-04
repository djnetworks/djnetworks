# DJ Network's — System Context

A briefing document. It describes the business, how it actually operates, what the
system has to cope with, and what has already been learned the hard way about the
platform. It deliberately contains **no proposed structure** — no schemas, no sheet
layouts, no column lists. That is left open on purpose.

---

## 1. The business

**DJ Network's** — equipment rental for DJs and events. Based near **CG Road /
Chandra Colony, Ahmedabad**. Run by Tanmay Bothra's chachu (paternal uncle), who is
himself a DJ. Tanmay is building the system for him; he is not the day-to-day operator.

The business hires out sound, DJ, lighting, effects and staging equipment for
weddings, functions, corporate events and parties. Revenue comes from renting
physical boxes for a number of days, plus delivery, plus damage recovery.

There is no public web presence of any use — searches surface nothing, and Indian
local directories do not index it. Everything known about the business has come from
Tanmay directly.

### Who actually uses the system

This is the single most important operational fact, and it invalidates a lot of
otherwise-sensible design:

- **One person** manages the business and does **all** the data entry.
- **One staff member** does the physical labour — loading, carrying, setting up —
  and does **no data entry at all**.

There are no departments. There is no second data-entry user. There is nobody to
separate permissions between, nobody to hand a partial view to, and nobody to catch
another person's mistake. Anything that assumes a team is wrong.

---

## 2. Source material

Tanmay supplied an **MIS Functional Requirement & Implementation Roadmap v1.0**
(September 2026, 20 sections) covering intended database structure, availability
logic, a status machine, a WhatsApp messaging standard, dashboard requirements, and
a list of **19 test scenarios** the system should satisfy. It is a requirements
document, not a working system.

Two things in it have already been contradicted by how the business really works,
and the real-world behaviour should win:

- It models equipment as **quantity pools** ("Qty: 2" on one row). Chachu tracks
  individual physical boxes and numbers them.
- It assumes staff will submit data from phones. In practice one person enters
  everything.

---

## 3. How the business physically operates

These are the facts any system has to survive. Each one has bitten a previous
attempt.

### Equipment is individual boxes, not quantities
Chachu already numbers identical units **1, 2, 3, 4…** and puts **physical stickers
on the cases** so he can tell them apart. This numbering exists today, independent of
any software. Any system that invents a parallel numbering scheme forces people to
translate between the shelf and the screen, and they will stop doing it.

Consequence: it must be possible to answer "which specific box came back damaged",
not just "how many are out".

### Numbers are never reused
When a box is lost or retired, its number dies with it. A replacement takes the next
free number. This keeps every piece of history attached to the physical object it
actually happened to.

### Equipment goes for repair, gets lost, gets replaced
Boxes leave for a repair shop and come back — sometimes fixed, sometimes not,
sometimes not at all. Some are lost at venues and charged to the customer. This is
routine, not exceptional, and the system has to have somewhere to put it.

### Stock lives in more than one place
There is a shop, a godown, and at least one van. Gear moves between them constantly,
and it also leaves entirely — to a customer, or to a repair shop. Tanmay explicitly
wants **every internal transfer recorded** so that "where is it right now" is
answerable at any moment.

The known weakness: without automation, a move only gets recorded if someone types
it, and the location becomes fiction within a week if they don't.

### Partial returns are normal, and they are dangerous
An order goes out with six boxes and five come back. **A box that physically went out
and has not been recorded back is still out — regardless of what its expected return
date said.** Getting this wrong means the system quietly offers that box for hire
while it is sitting in a hall somewhere. This has been found as a real bug in a
previous build and is the single most expensive failure mode identified so far.

### Every rental has an identity
Each order needs an ID that goes into every WhatsApp message about it. WhatsApp is
the actual communication channel with customers and staff.

### The rental-day convention
The start date counts. Out on the 2nd, back on the 4th, is **2 days**. A box due back
on the 4th is **not** available on the 4th, because somebody physically has to go and
collect it. This convention should be confirmed with chachu before going live —
it changes every price.

### Deposits are not income
A security deposit is the customer's money being held. Counting it as revenue
overstates earnings. It has to be tracked, and tracked separately.

### Pricing is unresolved
Whether chachu prices per day, in tiers by length of hire, by package, or simply by
what the customer will bear, is **not established**. This is an open question and it
materially affects the design. Do not assume a rate card exists.

### Sub-hiring is unaddressed
Rental firms this size routinely take jobs bigger than their own fleet and hire the
gap from another vendor. Whether chachu does this, and how often, has never been
confirmed. If he does, no previous design has been able to represent it: an order
containing gear that is not his has the wrong cost, the wrong margin, and no record
of what is owed to the other vendor.

---

## 4. The data situation

**There is no existing data of any kind.**

- No product list.
- No spec sheets.
- No inventory record.
- Nothing organised in any form.

Everything has to be created from nothing. This is the real work — not the software.
Getting a godown full of gear into any system means someone walking it, listing what
is there, counting pieces, and putting numbers on cases.

Practical notes on that exercise, learned from planning it:

- **The first pass should skip detail.** Serial numbers, purchase dates, purchase
  costs and specifications are all optional and all slow. The list is worth most of
  its value the moment it exists at all; a half-finished serial number column that
  people abandoned at unit 40 is worth nothing and undermines trust in the rest.
- **Cheap, high-count items need a decision made up front.** Numbering 200 XLR
  cables individually is a fantasy — nobody sustains it. Either leave them out of the
  system entirely, or track them as a pooled count and accept that. Half-doing it is
  the bad option, because a system people abandon in one corner gets distrusted
  everywhere.
- **Wireless microphone sets should be counted by the receiver**, which is the
  expensive part and the part that does or does not come back.
- **The stickers matter more than the spreadsheet.** If the ID is not physically on
  the case, nobody can look a unit up, and unit-level tracking collapses back into
  guesswork.

Different product types have genuinely different specifications — a speaker has
wattage and SPL, a keyboard has key count and polyphony, a moving head has gobos and
DMX channels. Any approach that gives every attribute its own fixed column produces a
table that is mostly empty and grows a column every time a new category is bought.

---

## 5. Platform facts — tested, not assumed

These were established by direct experiment during earlier attempts. They are
non-obvious and several contradict common advice found online.

| Finding | Detail |
|---|---|
| xlsx → Google Sheets import **preserves** | formulas, named ranges, cross-sheet references, data validation, conditional formatting, 2-D SUMPRODUCT |
| **ARRAYFORMULA does NOT survive** the import | every such cell becomes `#ERROR!`. Confirmed twice. |
| Google Sheets **does** support table structured references | `EQUIPMENT[Status]` syntax works |
| …but **`#This Row` is not supported** | per Google's own documentation. A formula on row 47 cannot refer to its own row through a table reference. |
| …and table references **do not work in conditional formatting**, charts or pivot tables | |
| Named ranges have neither limitation | they read similarly, work in conditional formatting, and survive import reliably |
| Sheets list-validation **ignores blank cells** in the source range | so a list range can be over-sized without showing empty options |
| **Google Forms can only be created by Apps Script** | there is no remote API available in this environment |
| A Google Form **cannot validate before submitting** | it cannot refuse a double-booking; it can only report one afterwards |
| Formulas cannot write | no formula can generate an ID, refuse an entry, or append a row. Only a script can. |
| The Drive connector carries files inline as text | **binary files corrupt in transit.** Spreadsheets cannot be pushed to Drive this way; they must be delivered to the local machine or uploaded by hand. |
| Apps Script free-tier limits | roughly 90 minutes of runtime and 100 emails per day — far above what this business would use |

---

## 6. What has been tried, and what happened

Three builds have been attempted. None is in production. This history matters mainly
so the same ground is not re-covered.

1. **A formula-only workbook.** Could flag a clash but not prevent one.
2. **An Apps Script engine.** Fully working, 107 automated tests passing, with
   availability enforcement, generated IDs, seven Google Forms, a movement ledger,
   and repair/replace handling. Retired by choice.
3. **A second formula-only workbook**, chosen deliberately after being told what
   would be lost.

### The trade that was made, explicitly

Tanmay chose **formulas over scripts**, knowing the cost, because he wants to
understand, navigate and customise the entire flow himself — including adding and
removing fields as relevant. He should not be talked out of this without new
information; it was an informed decision, not an oversight.

What that choice gives up:

- No refusal of a double-booking — only a warning after the fact.
- No generated IDs.
- No forms.
- Location accuracy depends entirely on discipline.

He has since said he intends to use **Google Forms built with Apps Script** for data
entry, which reintroduces scripting. Whether the script should also enforce rules, or
only capture data, is an open question worth settling early.

### Lessons that cost real time

- **A clean recalculation is not proof of correctness.** A previous workbook
  recalculated with zero errors while silently reading the wrong rows. The bug was
  only found by hand-checking values. Verification has to include reading the numbers,
  not just checking for error cells.
- **A blank date falling through to zero renders as `00:00:00`** and silently means
  1900. Blank has to be tested for explicitly; `IFERROR` does not catch it.
- **Test data anchored to the wrong dates proves nothing.** Sample records dated in
  the future never exercised the status logic at all.

---

## 7. Constraints that are not negotiable

- **Never sign into his Google account.** Never accept OAuth codes, tokens, or
  passwords. He performs all authentication himself.
- **No full Aadhaar or PAN numbers stored in any shared spreadsheet.** Anyone the
  sheet is shared with can read them. The ID photograph goes in cloud storage and only
  a link is stored.
- **History is never deleted.** Orders get cancelled, not removed.

---

## 8. How Tanmay wants to be worked with

Stated directly: **be direct and critical, pressure-test reasoning rather than
validating it, and check claims against data before agreeing.**

In practice this has meant: contradicting him when a request would make the system
worse, verifying platform claims by experiment rather than recall, and naming the
cost of a decision before implementing it. That has been useful more than once —
including catching a request that would have broken transactional integrity, and one
where his stated requirement was impossible on the platform for reasons neither of us
had checked.

---

## 9. Open questions

1. **How does chachu actually price a job?** Per day, tiered by length, packaged, or
   negotiated per customer.
2. **Does he sub-hire from other vendors?** If so, how often, and how is that money
   handled.
3. **Is the day convention right** — start date counts, same-day equals one day.
4. **Which cheap high-count items are in scope at all**, and are they tracked as
   pools or ignored.
5. **Should the Apps Script layer enforce rules, or only capture data.**
6. **What are the actual products?** Nothing has been catalogued. Product images and
   details have been referred to several times but have never reached the working
   folder, so no real product data exists yet.
7. Crew and operator assignment, quotations before a booking exists, delivery
   challans, and preventive maintenance are all unaddressed and may or may not matter.
