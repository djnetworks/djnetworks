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

**Derived views (15)** — `v_movement_effective`, `v_unit_location`, `v_unit_status`,
`v_unit_history`, `v_order_outstanding`, `v_order_fulfilment`, `v_pool_stock`, `v_product_stock`,
`v_customer_balance`, `v_customer_figures`, `v_unit_utilisation`, `v_product_roi`, plus the three
permission-gated wrappers `v_customer_balance_visible`, `v_product_roi_visible` and
`v_unit_utilisation_visible`, and the functions `fn_availability(product, from, to)` and
`fn_today()`

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
| 1 · Categories and subcategories | — | seeded by `0005`, no screen and none planned; chachu has not pruned the 187 |
| 2 · Product master | `products.html` | built, driven signed in |
| 3 · Unit intake | `units.html` | built, bulk create is the primary path |
| 4 · Locations | — | seeded by `0004`, no screen yet |
| 5 · Customers | `customers.html` | built, issues the portal code |
| 6 · Order | `orders.html` | built |
| 7 · Dispatch | `dispatch.html` | built, offline-capable with explicit prefetch |
| 8 · Return | `return.html` | built — condition, deduction, write-off, and damage photographs (`0028`) |
| 9 · Internal transfer | `transfer.html` | built — "Load the van", one action for a whole load |
| 10 · Repair | — | **not built** — the one gap |
| 11 · Payments and ledger | `ledger.html` | built |
| 12 · Customer portal | `portal.html` | built |

Plus four screens that are not forms:

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
- `reports.html` — **Reports**, one read-only dashboard: money (billed and received as two numbers,
  never one), what earns, how each product is working, best customers, what breaks. It replaced
  `analysis.html`, which was deleted rather than left beside it — two report screens drift.
- `team.html` — **Team**. Who has an account and what each of them may do. Nine toggles over
  `0021`'s eleven keys: nobody should be asked eleven questions, and the two that bundle are the two
  that always travel together. Money is the one place the granularity survives, because seeing a
  balance and posting to it are different jobs. It **cannot create an account** — that needs the
  service key, and a key that can create an account can create an admin, so the screen says where to
  do it instead of failing quietly.

## Navigation and density

**The nav is at the bottom and it is permission-shaped.** Ten destinations in a horizontally
scrolling top strip put five of them off screen at 375px with no affordance saying so, and all of
them at the far end of a one-handed reach. `chrome()` now renders a slim top bar carrying identity
and the connection state only; everything you navigate to is a fixed bottom bar sized by
`--nav-slots`, with anything past the fifth under **More**.

**It is re-flowed at login, not hidden with CSS.** `MODULES` in `web/app.js` names the permission
key behind each destination; `paintNav()` runs once `loadPermissions()` resolves and rebuilds the
bar from what this person holds, so a hidden module closes up rather than leaving a gap. A gap
reads as a broken app and, worse, teaches the thumb the wrong position.

**Granting somebody a module needs a page reload before it appears.** The nav is built once, at
login. The Team screen says so next to the toggle.

**Browse-first, not search-first.** Customers, Orders, Products and Equipment arrive as cards and
search FILTERS them. Equipment used to show a dropdown and the words "Pick a product" — nothing at
all until you already knew what you wanted, on the screen whose job is telling you what you own.
`cardList()` in `app.js` is the one place the row shape is defined.

**A card carries what identifies the thing and what needs attention, and nothing else.** The order
number is subtext with tap-to-copy, because its job is being pasted into a WhatsApp message — the
briefing requires an ID in every message, so it is demoted rather than deleted.

**The five nav slots never change.** A bottom bar exists so the thumb stops reading; a slot that
swaps identity depending on the screen destroys the only thing it is for. When the current screen
lives under **More**, More is what lights up and the sheet says *you are here*. Two earlier versions
were wrong — the first overwrote slot five and lost a destination entirely, the second swapped and
kept everything reachable while still moving the target, which was the actual harm.

**The connection pill opens the queue.** `flush()` replays oldest-first and stops at the first
failure, and that is correct: a return replayed before its own dispatch makes the movement ledger
read backwards. The consequence is that one poison item halts everything behind it, so the queue is
inspectable — what is waiting, the REAL error verbatim, how many attempts — and can be dropped
deliberately with a reason that is kept in a `discarded` store rather than deleted. Same reasoning
as `0019`'s corrections, one layer up.

**Three tap rules, fixed once in `style.css` rather than discovered per screen.** A card opens the
detail and an inline `.card-action` stops the event and looks like a separate control; `.tappable`
is the only thing that reads as live, so a container never gets a handler; and every write control
shows a pressed state, disables in flight and carries an idempotency key (`0022`) — the offline
queue makes a second arrival likelier, not rarer, because a replay is one by construction.

**`--edge` and `--border` are different jobs.** `--border` (#E7E8E6, 1.11:1) separates a row from
the next row, where faint is right. `--edge` (#828282, 3.47:1 on the page) is the boundary of
something you AIM at — a field, a tile, a button — where WCAG 1.4.11 asks for 3.0. It is the bible's
own `--grey`, rejected for 12px text at 3.47:1 and exactly right for a 2px line hit with a thumb
in sunlight.

---

## Permissions

`0021`. `authenticated` no longer means "may do everything". The `operator` row carries a JSONB
`permissions` object with eleven granular keys, and **`fn_has_permission(key)` is the single choke
point** — every policy on every table calls it and nothing else tests permissions directly. An
absent key is denied: there is no wildcard and no implication, so `admin.team` does not confer
`ledger.view`.

| key | what it opens |
|---|---|
| `orders.write` | orders, lines and charges |
| `sendout.write` | recording a dispatch |
| `returns.write` | recording a return |
| `movement.correct` | undoing a movement (`0019`) |
| `products.write` | the catalogue: products, photos, categories |
| `equipment.write` | pieces, locations, vendors, repairs, transfers, write-offs |
| `customers.write` | customer records |
| `ledger.view` | **seeing** money — the ledger and every balance |
| `ledger.write` | posting to the ledger |
| `numbers.view` | the reports |
| `admin.team` | people, and the settings that change arithmetic |

Reading is open to any active operator **except the ledger**: knowing an order exists is part of
doing the work, and knowing what a customer owes is not. `movement` is the one table where the key
depends on the row — dispatch, return and correction each test a different one, because the man
loading the van may record what he did and may not erase it.

The policies are built from a MAP in the migration, and the migration then **asserts that no table
with row level security is missing from it**. A table nobody remembered is how this goes wrong, and
it can no longer go wrong quietly.

`v_customer_balance`, `v_product_roi` and `v_unit_utilisation` are revoked from `authenticated` and
reached through `_visible` wrappers carrying the permission predicate. They return **zero rows**
without the key rather than every customer at ₹0.00 — a refusal, not a wrong number. The ungated
`v_customer_balance` stays for `fn_portal_snapshot`, which is `security definer`: a predicate inside
it would evaluate `auth.uid()` as NULL on an anon portal request and break the customer portal.

**Invitation only.** `fn_admin_set_operator` records who somebody is and what they may do, is
`security definer`, and is executable by nobody holding a browser session. Nothing in the app can
grant a permission. Turning off self-registration is a project setting, not SQL — the Today screen
checks `/auth/v1/settings` and tells whoever holds `admin.team` if the door is still open.

**The client's `can(key)` is convenience, never the boundary.** Hiding a button spares somebody a
refusal; the refusal comes from the database either way.

---

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

A correction must say **why** (`0020`): at least a few words, refused at the trigger. The mechanism
can walk history back, and the sentence is the only record of what actually happened.

This is what makes the return screen's **"All 6 back"** safe to have. The count is on the button,
never the bare word — tapping something that says 6 while holding 5 is a different mistake from
tapping a word — and the ticks are still separate from the commit. Send-out mirrors it with
**"Load all N"**, where N is what pressing it will actually add rather than the size of the order:
a partly-dispatched job, a short shelf or a piece pinned elsewhere all make those differ, and a
button that says 8 and adds 5 has lied once and will not be trusted again. Send-out needs no
correction machinery — a dispatch recorded in error is undone by the return that follows it — but
it needs the same stage-then-commit separation, and it has it.

**WhatsApp drafts.** `waMessage()` in `web/app.js` builds the five predictable messages — booking
confirmed, on its way with the driver's number, came back short, payment pending, and the overdue
reminder on Today. A share button **opens a prefilled draft and never sends**; the send button
belongs to the person, and on a message about somebody's money that is not a detail. Every message
carries an order number to quote. The payment chaser sits behind two rule 6 guards: never offered
when `receivable <= 0` (a credit balance is reachable since `0018`), and the deposit is named
separately or not at all — it is the customer's own money and is never part of what is owed.

**9 · Internal transfer — "Load the van".** Gear in the van between jobs is the NORMAL state of
this business, not an exception: two jobs on a Saturday and the speakers never come back to the
godown in between. One action for a whole load — pick where it is going, tap the pieces, commit —
never one transfer per box.

*Availability needs no new rule,* which is worth saying because it looks like it should. A van is
one of OUR locations, so a piece in it is `at_kind = 'location'` and `v_unit_status` already calls
it available. What DID need fixing is the send-out screen's "Loading from", which defaulted to the
first location alphabetically — Godown — so a job whose gear was already in the van showed an empty
pick list that read as the pieces being lost. It now defaults to wherever most of THAT JOB's gear is
standing, names the count in each option, and when nothing is at the chosen place it says where the
rest is instead of leaving an empty list to be interpreted.

**`fn_today()`, and `current_date` is banned.** Every date this system stores is a calendar day on
the Indian calendar — `movement.moved_on` comes from the phone, `out_date` is typed by a person in
Ahmedabad. The server's `current_date` is UTC, so between midnight and 05:30 IST they are different
days, and four views and a function were off by one for the five and a half hours when a van is
actually loaded. A piece moved that morning read *(-1 days)*; Today said "4 days overdue" while the
portal, reading the view, said 3 — the operator and the customer seeing different numbers for the
same job. `0026` gives them one source.

**The numbers live on the entity.** A reports tab gets opened twice; the same facts where the
decision happens get read daily. A product shows how often it is hired, how long it is out, how
often it is repaired and what it has earned back — gated on `numbers.view`, and absent it says so
rather than showing zeros. A customer shows jobs, owed now, oldest unpaid, returns late and overdue
right now, from `v_customer_figures` — **numbers, never verdicts**: no "reliable" and no "always
pays", because revenue posts on confirmation and somebody with three unstarted jobs would read as a
model payer. A piece shows where it is, who has it, and everything that has happened to it including
corrections, from `v_unit_history`. Dead stock stays a report — forgotten gear surfaces nowhere else
by definition.

**Damage photographs, and the second bucket (`0028`).** `movement.photos` existed from `0002` and
nothing ever wrote to it. It now takes a key inside a **private** bucket, `return-photos`, and the
privacy is the point rather than a precaution: `product-images` is public because the portal shows
it, and a photograph of a cracked cabinet is taken inside somebody's wedding hall. It is their
property and their event, and a public bucket is world-readable at a URL that only has to be
guessed once.

Two permissions open it — `returns.write`, because the man recording the return is holding the
phone, and `ledger.view`, because the deduction gets argued about a week later over the telephone
and the person defending the number has to be able to open the picture. Every look is a signed URL
with a two-minute life. **The portal never serves them**, and `0028` fails at apply time if
`fn_portal_snapshot` ever names the column.

The photograph is taken *in the row, under the deduction*, because that is the only moment anybody
is looking at the damage. It uploads immediately and the path is held until "Record returns" — it
has to work that way, since `movement` is append-only and a photograph therefore lands in the INSERT
or never lands at all. That draws a line worth naming: **until a movement points at a key it is a
draft, and after that it is evidence.** Unattached, the man who took it may retake or remove it;
attached, nobody can, and the correction path is the only way to say the record is wrong. Same shape
as `0019`.

Rule 14 applies to a picture as much as to a rupee: `photo_count` is visible to everybody, `photos`
is **NULL** rather than `[]` without one of the two keys. "Two photos, not visible from this
account" is a refusal a screen can explain; an empty list says nobody photographed the damage, which
is a different and far more comfortable claim.

**10 · Repair.** Unit, vendor, date sent, fault, estimated cost, then date back, actual cost,
outcome. A unit at a repair shop leaves availability with no extra rule. **Not built** — the only
form of the twelve that has no screen and no substitute.

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
