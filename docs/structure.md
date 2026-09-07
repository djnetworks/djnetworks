# Structure v1.0

Agreed form by form, 4 September 2026. The SQL in `supabase/migrations/` is the authoritative
schema; this document is the narrative behind it.

## Scope

A working application for a single-operator equipment rental business. One person manages
everything and does all data entry; one staff member does the physical labour and enters nothing.
No departments, no second data-entry user, nobody to catch another person's mistake.

**Authoritative for:** what equipment exists, where each piece physically is, what went out on which
job at what agreed price, what extras were added, what money came in, what is outstanding.

**Not:** the books. No GST, no tax invoices, no journal entries. Accounts live elsewhere; this
system exports.

---

## Tables

**Masters** — `category`, `subcategory`, `product`, `unit`, `location`, `vendor`, `customer`,
`discount_tier`, `app_setting`

**Transactions** — `rental_order`, `order_line`, `order_charge`, `movement`, `repair_job`,
`ledger_entry`, `product_image`

**Derived views (11)** — `v_movement_effective`, `v_unit_location`, `v_unit_status`,
`v_unit_history`, `v_order_outstanding`, `v_order_fulfilment`, `v_pool_stock`, `v_product_stock`,
`v_customer_balance`, `v_unit_utilisation`, `v_product_roi`, and the function
`fn_availability(product, from, to)`

`v_pool_stock` is the one place that knows what pooled stock is; `v_product_stock` and
`fn_availability` read it rather than re-deriving quantities. `v_order_outstanding` replaced
`v_order_outstanding_units` in `0008` — it reports pieces *and* quantities, because a cable that
never came back is as outstanding as a speaker (rule 13).

`v_order_fulfilment` arrived in `0010`, when `rental_order.status` was narrowed to the three things
a person actually decides — `confirmed`, `closed`, `cancelled`. How much has gone out and how much
has come back is derived from movements, never stored: it is two quantities, not one label, and an
enum holding both would drift the way a `current_location` column drifts. The view exposes
`qty_ordered`, `qty_dispatched`, `qty_returned`, `qty_outstanding` and `qty_undispatched` first, and
a convenience `fulfilment_state` label computed from them — because an order with 4 ordered, 2 gone
and 1 back is genuinely both partly dispatched and partly returned, and no single label says so.

**The portal reads through two functions, split on purpose.** `fn_portal_snapshot(customer_id)` is
the query and is callable by nobody; `fn_portal_view(phone, code)` is the gate and is the only thing
`anon` may execute. Replacing the static access code with a one-time code changes the gate and
leaves the query untouched — see `docs/open-questions.md` item 2. Opening anon SELECT on any table
to make the portal work would publish that table to everyone holding the publishable key, which
ships in the page source.

The three-tier product model matters and is easy to get wrong:

- **Product** — the rentable thing, priced, with specs. Sometimes a single item, sometimes a kit.
- **Unit** — the numbered physical object that gets a sticker and carries a history.
- **Inclusions** — accessories that travel with a unit and are not separately numbered. The power
  cable, the quick start guide, the microphone in a wireless kit. Checked at dispatch and at
  return, which is how you catch that the cable did not come back.

---

## The twelve forms

Build order is dependency order. Built so far, as static pages under `web/`:

| Form | Screen | State |
|---|---|---|
| 1 · Categories and subcategories | — | seeded by `0005`, no screen; chachu has not pruned the 187 |
| 2 · Product master | `products.html` | built, not driven signed in |
| 3 · Unit intake | `units.html` | built, bulk create is the primary path |
| 4 · Locations | — | seeded by `0004`, no screen yet |
| 5 · Customers | `customers.html` | built, issues the portal code |
| 6 · Order | `orders.html` | built |
| 7 · Dispatch | `dispatch.html` | built, offline-capable with explicit prefetch |
| 8 · Return | `return.html` | built |
| 9 · Internal transfer | — | not built |
| 10 · Repair | — | not built |
| 11 · Payments and ledger | `ledger.html` | built |
| 12 · Customer portal | `portal.html` | built |

Plus three screens that are not forms:

- `index.html` — **Today**. The app is organised by entity; his day is organised by date. Three
  sections lead — going out today, coming back today, late — and the counts follow them. The counts
  were never wrong; they answer a question nobody asks at 7am.
- `ask.html` — **Can I say yes**. The phone-call screen. "20th ko 4 speaker mil jayenge?" needs an
  answer in ten seconds while the customer is on the line, and the only way to get one used to be to
  build a whole order and see whether it was refused. It **writes nothing**: it reads
  `fn_availability`, and a shortfall names the jobs holding the stock, by date, person and venue,
  because an unexplained no is a no he overrides. One tap hands the dates and the basket to
  `orders.html`, which regenerates every rate from today's rate card (rule 5) rather than carrying
  a number across.
- `analysis.html` — the reports below.

**All of these have now been operated by a signed-in operator** — a complete job was walked end to
end in a browser on 2026-09-07, and the offline dispatch path was exercised with the network down.
Access is enforced by membership of the `operator` table (`0017`), not by whether a Supabase signup
toggle happens to be off: a stranger who self-registers gets a valid session and reads zero rows.

The development fixture in `supabase/seed/dev_seed.sql` is the reset button. It truncates the tables
it owns and re-seeds them, which is the only way to clear test data — `DELETE` is blocked on
`movement`, `unit`, `rental_order`, `ledger_entry` and `repair_job` by design, and the append-only
guard should never be disabled to tidy up. `0009` kept `TRUNCATE` for `postgres` and `service_role`
for exactly this.

**1 · Categories and subcategories.** Two editable lists, seeded. The work is chachu striking out
what he does not own.

**2 · Product master.** Identity, description, specs (JSON, prompted by category), inclusions, kit
contents, image, tracking mode, base rate per day, default purchase cost. Specs are JSON because a
speaker has wattage and SPL while a moving head has gobos and DMX channels, and fixed columns would
produce a mostly-empty table that grows every time a new category is bought.

**3 · Unit intake.** Product, piece number, serial (optional), purchase date (optional), purchase
cost, condition, ownership, inclusions, notes.

*Bulk create is what makes intake survivable.* Enter the product once, answer "how many pieces?",
and six units appear numbered 1 to 6 at a location set once, each inheriting the product's cost.
Hundreds of units become roughly 150 product rows and a number. Intake writes each unit's opening
movement, so no unit ever exists without a location.

**4 · Locations.** Name, type (shop / godown / van / workshop), active. Internal places only — a
workshop is ours, a repair shop is somebody else's.

**5 · Customers.** Name, business name, type, WhatsApp, alternate phone, email, address, city,
pincode, ID document type and link. WhatsApp is the primary contact and the portal identity. No full
Aadhaar or PAN digits are stored anywhere.

**6 · Order.** Order number, customer, event type, venue name and address, venue contact name and
phone, out date, expected return date, days, deposit, lines, charges. Venue contact is separate from
the customer because the man who booked the job is rarely the man at the hall at six in the morning.

*The order number exists to be quoted.* The source briefing is explicit: **"Each order needs an ID
that goes into every WhatsApp message about it. WhatsApp is the actual communication channel with
customers and staff."** That requirement was dropped when this spec was written and is restored
here, because losing it made the app worse in a way nobody could see: nothing generates those
messages, so the operator writes them by hand, and the order number he has to look up is work the
app ADDED rather than saved. Message generation is not built yet.

It follows that the number is never the HEADLINE either. A job is held in mind as a DATE, a PERSON
and a VENUE — "the Patel job at the stadium on the 28th" — so every screen leads with those three
and demotes the number to the reference line beside them. `jobLine()` in `web/app.js` is the one
place that decides how a job is named; nothing should format one by hand.

**7 · Dispatch.** The phone-at-the-van screen; everything about it is subordinate to being fast.
Opens from the order, never the catalogue, so chachu taps six piece numbers from a filtered list of
eight rather than searching three hundred. Dispatch method chosen each time — porter,
self-collection, delivered by chachu — with a name and number captured whichever it is. Partial
dispatch is normal. Offline entry queues locally and syncs.

**8 · Return.** Each dispatched unit ticked back individually with a condition and an inclusions
check. An unticked unit is still out. Returns are plural, and the return location may differ from
where the gear left. Damage proposes a deduction from the deposit; a lost unit proposes its own
purchase cost.

**Corrections (`0019`).** A movement recorded in error is never deleted — `DELETE` on `movement` is
blocked and `UPDATE` is refused by the append-only guard. A `correction` row names the movement it
undoes through `corrects_movement_id`, and **`v_movement_effective` is the one place that knows what
still counts**: it drops corrections and anything they name, and every derived view and
`fn_availability` read it rather than `movement`. Same shape as `0018`'s ledger reversal, one table
over.

A correction may only ever name the **current tip** — the most recent effective movement for that
piece, or for that product on that job for counted stock. You may peel the tip; you may never reach
into the middle while something newer still stands, because a span with a hole in it is ambiguous
everywhere it is read. Corrections are never location-bearing and never silent: `v_unit_history`
shows the corrected movement flagged, with the reason, alongside the annotation that undid it.

This is what makes the return screen's **"All 6 back"** safe to have. The count is on the button,
never the bare word — tapping something that says 6 while holding 5 is a different mistake from
tapping a word — and the ticks are still separate from the commit.

**9 · Internal transfer.** From, to, date, units, moved by, notes. That is the whole form.

**10 · Repair.** Unit, vendor, date sent, fault, estimated cost, then date back, actual cost,
outcome. A unit at a repair shop leaves availability with no extra rule.

**11 · Payments and ledger.** One ledger per customer, typed entries. Rental charges post on order
confirmation as `upcoming` and become `due` at dispatch. Payments need not attach to an order —
trade regulars pay on account.

**12 · Customer portal.** One link per customer. Current and past orders, what is out and when it is
due, the ledger, receivable and deposit held separately, payment history. Product names, not piece
numbers.

---

## Analysis

| Report | Definition | Depends on |
|---|---|---|
| ROI per product | rental revenue − repair cost, over purchase cost | per-unit cost. Transport and misc excluded — job-level, and including them would flatter heavy gear |
| Utilisation | days out over days owned | movements only; needs no cost data |
| Hire frequency | times hired per period | movements |
| Dead stock | owned, not hired in N days | movements |
| Damage rate | damage and repair events per product per hire | returns and repair jobs |

---

## Source material

Working folder on the operator's Mac: `~/Downloads/Dj Niraj`.

- `DJ_Networks_Inventory.xlsx` — template only, **zero real records**, but carries the 27-category /
  187-subcategory taxonomy now seeded in `0005`.
- `dj_networks/products/` — three marketing flyers (JBL EON ONE MK2; Shure BLXR-14 headworn; Shure
  BLXR-14 lavalier), a logo, six marketing videos. No spec sheets.
- The flyer finding that set the kit decision: the rental option reads "01 SYSTEM (body pack +
  receiver + headon)" with four listed components, and the two Shure flyers differ only in the
  microphone.

Business contact: 9824083533 · info.djnetworks@gmail.com · www.djnetworks.com
