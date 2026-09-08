# Decisions

Every entry records what was chosen and what it cost. Most of these were argued. Before proposing a
change to one, read why it was made — several are the second or third answer to the same question.

Dated 4 September 2026 unless noted.

---

### Build a real application, not a spreadsheet
Reverses an earlier deliberate choice of formulas over Apps Script. That choice was made so the
owner could navigate and customise the whole flow himself, and giving it up is a real loss.
**Bought:** refusing a double-booking instead of warning about it, generated order IDs, a customer
portal, and a location that is not fiction. Excel becomes a read-only mirror plus a bulk import
lane, not the system.

### Supabase + static HTML, Maitri pattern
Reuses a stack already running in production, including the Google Sheet two-way link. No build
step, so the owner can still read the frontend.

### A kit is the unit
The Shure BLXR-14 rents as "01 SYSTEM (body pack + receiver + headon)" — four components, one
sticker, one number. Components are not separately numbered.
**Cost:** the same receiver cannot be rented as a headworn set one week and a lavalier set the next
without two product records. Mitigated by treating the microphone as an editable *inclusion* on the
unit. If mics turn out to be swapped constantly, this will hurt and should be revisited.

### Stickers stay as bare piece numbers
Chachu already numbers identical units 1, 2, 3 with stickers on the cases, with no product code.
**Consequence:** every screen must be product-first — pick the product, then the number. No
re-stickering of hundreds of boxes, and no flow may begin with a unit ID.

### Reservation at product level, allocation at dispatch
An order reserves "2 × 15-inch top". Physical numbers attach when the van is loaded. A unit may be
pinned when there is a reason.
**Why:** unit-level booking three weeks out means re-shuffling allocations across every future order
whenever a box goes for repair, and it fragments availability for no gain. Damage and non-returns
happen after dispatch, which is where unit tracking actually earns its keep.

### Three tracking modes
`unit` for numbered boxes; `pool` for Cable, Mic accessory, Stand & rigging and Tool & spare;
`consumable` for fog fluid, tape and batteries. Tools and spares get `product.rentable = false`,
which keeps them out of the availability check and the order picker — but that is a per-product
tick with no category-level default, so nothing applies it automatically. See open-questions 8.
**Why:** numbering 200 XLR cables is a fantasy nobody sustains, and a system abandoned in one corner
gets distrusted everywhere. Consumables are charged and never come back, which is a third case, not
a kind of pool.

### Purchase cost per unit, seeded from a product default
A 2019 box and its 2024 replacement cost different amounts, so the schema holds cost per unit.
Intake seeds every unit from a product-level default so nothing is ever blank.
**Why the compromise:** demanding a rupee figure for every box during the godown walk is exactly the
task that stalls at unit 40 and leaves a half-filled column that poisons the ROI report.

### Pricing: per-day base, one global discount ladder, everything overridable
`order_line.agreed_rate` and `line_total` are stored, never recomputed.
**Why stored:** raising a rate next March must not rewrite what was charged last March.
**Open:** the actual discount percentages are placeholders.

### Deposit is taken against the order
Not per product. Held as a liability, never counted as revenue. Receivable and deposit held are two
separate numbers on every screen.

### Day count: both ends count
Out on the 2nd, back on the 4th is 3 days. Held in `app_setting`, not hard-coded.
**Unconfirmed** with the owner in his own words, and it changes the price of every job.

### Availability is date-level, with a logged override
A unit due back on the 4th is not offered on the 4th, because somebody has to go and collect it.
Same-day turnaround is possible through `rental_order.availability_override`, which is recorded.
**Rejected:** slot-level availability (morning/afternoon/evening). It would model same-day turnaround
precisely, but the owner says it happens rarely, and the complexity would spread through the order,
dispatch, return and availability code.

### No quote stage
Negotiation happens on WhatsApp; an order exists once the job is agreed.

### Sub-hire is a line-level flag
`is_subhired` plus vendor and payable cost. No inventory impact.
**Why so light:** it happens rarely. A full sub-hire model has defeated three previous designs, and
this gets the margin roughly right without bending anything else.

### Damage comes out of the deposit
The return screen proposes a deduction; anything above the deposit is billed as a charge. A lost unit
proposes its own purchase cost, editable at the point of charging.
**Known weakness:** purchase cost understates an old box. Editing at the moment of the conversation
is the mitigation, chosen over adding a separate replacement-cost field.

### An order cannot close while a unit is out
Hard block. Closing requires an explicit found, write-off or loss.
**Why:** the single most expensive bug found in an earlier build — six out, five back, and the sixth
quietly offered for hire while it sat in a hall.

### Revenue posts on order confirmation
So the receivable includes jobs that have not happened yet, which is useful as a forward book.
**Cost:** cancellations and short dispatches need reversal entries, and the ledger carries a
`state` (upcoming / due) so the portal does not tell a wedding customer they owe money three weeks
early.

### This system is not the books
No GST, no tax invoices, no journal entries. Accounts live in separate software; this system exports
rather than posting.
**Unresolved:** which system is authoritative for receivables when the two disagree.

### Schema changes come only from this repo
A Cowork chat also has the Supabase connection but is read-only. Two agents with write access to one
database produces a schema that no longer matches its own migration history.

### Product images are stored, never linked
Three entry routes — phone camera, Excel import, direct upload — all landing in the same bucket.
An external WhatsApp or Drive URL would rot and break the customer portal.

### The palette is derived, and labelled provisional
The Ekum design bible owns behaviour and says twice that it does not own visual styling — the Brand
Kit does, and the Brand Kit is not in this repo. Rather than wait or invent silently, every token in
`web/tokens.css` is derived from the bible's own document CSS plus the icon, and the file says
`PROVISIONAL` in three places.
**Cost:** three of the bible's semantic colours are fills, not inks, and fail as text on these
grounds — `#828282` at 3.47:1 is the one that mattered, because it is every `.field__hint`. Each
keeps its name for fills and gains a measured text-safe partner. Those three values are the only
thing a real Brand Kit has to overrule. See `docs/design.md`.

### DJ Network's is the brand; EKUM appears once
"Built by EKUM" sits under the operator sign-in button and nowhere else — never on `portal.html`.
**Why:** the portal is opened by a wedding family on a WhatsApp link. A second brand on that page is
a question they have to answer, with nobody there to answer it.
The DJ Network's mark is typographic. The flyer logo is not used: it carries a visible AI watermark
and its shield is misspelt "EVENTS & RENTAL EQUIPE".

### Four of the bible's rules were imported, and only four
Icons need labels; software words are replaced with trade words; the dispatch pick list leads with
the photograph; intake and dispatch are counted in taps. The bible's roles, collections and
navigation model belong to a textile trading app with suppliers and buyers, and were left there.
**Cost:** the wording table in `docs/design.md` has to be kept in step with the schema. `unit`,
`pool` and `consumable` are still the column values; only their labels changed, through
`trackLabel` / `trackBadge` / `fulfilLabel` in `app.js` so no screen can invent its own vocabulary.

### A correction must say why
`0020` makes `movement.notes` mandatory on a correction — at least a few words, enforced in the
trigger rather than in the screen that happens to write it.
**Why:** the mechanism can walk a piece's history back one row at a time, and the only thing that
makes that safe rather than merely auditable is that each step carries a sentence somebody wrote.
`0019`'s own worked example is the argument: *return (CORRECTED: the sub never left the hall)* is a
history somebody can read three weeks later; *return (CORRECTED)* is not.
**Cost:** an eight-character floor is a floor, not a quality test. It stops the empty string, a
space and a full stop; it cannot stop "asdfghjk" and does not pretend to.

### A movement is corrected, never deleted
`0019` adds a `correction` movement type naming the movement it undoes, and
`v_movement_effective` — which every derived view and `fn_availability` now read instead of
`movement`. Same shape as `0018`'s ledger reversal, one table over.
**Why it was needed:** the return screen's one-tap "All 6 back" is right — gear comes back at 2am and
a system filled in from memory on Sunday is wrong in the same direction, only later — but without a
way out, marking six back while holding five puts a piece on the shelf that is sitting in a hall,
permanently, with the system's confidence behind it.
**Cost:** a correction may only ever name the current tip. You may peel; you may not reach into the
middle. A piece's whole history can therefore be walked back one visible row at a time — accepted,
because forbidding it strands a piece reading `out` for ever when both its dispatch and its return
were wrong, and because a correction hides nothing (`v_unit_history` shows it flagged, with the
reason).

### A job is a date, a person and a venue
Every screen leads with those three and demotes the order number to the reference line beside them.
`jobLine()` in `web/app.js` is the only place that decides it.
**Why the number stays:** it is the one identifier the operator and the customer share — she quotes
it back on WhatsApp and the portal prints it. The source briefing requires it in every message. It
is demoted, not deleted.

### The enquiry screen writes nothing
`ask.html` answers "20th ko 4 speaker mil jayenge?" by reading `fn_availability`, and creates no
order until one tap hands the dates and the basket to `orders.html`.
**Why:** the only way to answer that call used to be to build a whole order and see whether it was
refused, so every enquiry that came to nothing left a half-made order behind and every enquiry that
took two minutes was answered from memory instead.
**Cost:** two screens can now start a booking-shaped thing. Kept honest by `ask.html` never writing:
`orders.html` is still the only place an order is created, and it regenerates every rate from the
current rate card rather than accepting one across the URL (rule 5).

### Permissions are granular in the database and grouped in the UI
Eleven keys on the operator row, one `fn_has_permission()` called by every policy. Grouping into
module toggles is the Team screen's job (Pass G); nobody should tick eleven boxes.
**Why granular:** the two people who will hold accounts are the owner and the man who carries the
boxes, and the interesting line between them is not a role — it is that he may record a return and
must not be able to undo one.
**Cost:** eleven keys is eleven things to get right on every new table, so the migration asserts
that no RLS table is missing from the map rather than trusting anybody to remember.

### The gated report views return nothing, not zero
`v_customer_balance` and the two report views are revoked from `authenticated` and read through
`_visible` wrappers that carry the permission test.
**Why not just let RLS empty the ledger:** `v_customer_balance` left-joins it, so a staff member
without `ledger.view` would have seen every customer at ₹0.00. That is a wrong number stated
confidently, which this system treats as worse than a refusal.
**Cost:** one extra object per gated view, and the ungated `v_customer_balance` must stay for
`fn_portal_snapshot` — a permission predicate inside it evaluates `auth.uid()` as NULL on an anon
portal request and would break the customer portal for everybody.

### The navigation is at the bottom and re-flows at login
Fixed grid columns sized to the modules this person holds, so a hidden destination closes up rather
than leaving a gap.
**Why:** a gap where a destination used to be reads as a broken app and teaches the thumb the wrong
position — Maitri's lesson. And ten destinations in a scrolling top strip put five off screen at
375px with no affordance, at the far end of a one-handed reach.
**Cost:** the nav is built once, at login, so granting somebody a module needs a page reload before
it appears. Said on the Team screen next to the toggle rather than left to be discovered.

### Lists arrive full; search filters
**Why:** a screen that shows nothing until you type assumes you can already phrase the question.
Equipment was the worst of it — a dropdown and the words "Pick a product" on the screen whose whole
job is telling you what you own.
**Cost:** every list screen now loads its rows on arrival. At this fleet size that is nothing; at
ten thousand pieces it becomes a paging problem, and the card shape is where paging would go.

### A tap that writes carries an idempotency key
One `request_id` per tap, shared by every row in the batch, generated before the work starts and
carried unchanged through the offline queue (`0022`).
**Why:** tap, nothing visibly happens on a bad link, tap again — and six pieces are recorded as
having gone out twelve times, with nothing deletable to fix it. The offline queue makes this more
likely rather than less: a replayed write is a second arrival by construction.
**Cost:** a batch is all-or-nothing on replay. That is what the operator meant by one tap.

### The idempotency key is (request_id, request_seq), not request_id alone
`0024`. One id per tap, and the rows within that tap are numbered.
**Why:** `0022` put a UNIQUE index on `request_id` alone and asserted in its own comment that a
six-piece batch would therefore roll back as a unit on replay. It did the opposite — the batch
collided with ITSELF on the first insert, so a two-piece send-out wrote nothing and told the
operator "This was already sent". Found by tapping the real button twice and reading the row count:
zero. The migration's probe missed it because it inserted one row per statement.
**Cost:** the client has to number the rows. That is one line in each of the two write paths, and
it is the line that makes all-or-nothing true rather than merely claimed.

### The five bottom-nav slots are fixed, and More lights up instead
**Why:** the bar exists so the thumb stops reading. Highlighting the active screen by moving it onto
the bar kept every destination reachable and still moved the target, which is the harm the fixed
grid was for.
**Cost:** on six of eleven screens nothing in the bar is highlighted except More. The More sheet
says "you are here" against the current one.

### A blocked queue is inspectable, and dropping one needs a reason
**Why:** `flush()` stops at the first failure and must — a return replayed before its own dispatch
makes the ledger read backwards. So one poison item halts everything behind it, and the pill that
reported it was an inert span. In the one feature whose failure mode is a box leaving the godown
with no record, a dead end nobody can open is the worst possible place for one.
**Cost:** a `discarded` IndexedDB store and a database version bump. Discarding does not undo
anything physical, which the confirm says in as many words.

### `fn_today()`, and `current_date` is never compared to a stored date
`0026`. The server's `current_date` is UTC; every date this system stores is an Indian calendar day.
**Why:** four views and a function were off by one between midnight and 05:30 IST — the hours a van
is loaded in. A piece moved that morning read "(-1 days)", and Today said "4 days overdue" while the
portal said 3 about the same job, because one was computed in the client from the local date and the
other in a view from UTC.
**Cost:** the timezone is hard-coded to Asia/Kolkata in one function. A second branch in another
country would need it to come from a setting, and would have bigger problems first.

### Queue handlers live in app.js, not on the screen that made the write
**Why:** a queued dispatch sitting on Today reported *No handler for "dispatch"* and stayed stuck
until the operator happened to walk back to Send out. Visible rather than silent since the queue got
a sheet, and still the offline path failing in the one feature whose failure is a box leaving with
no record.
**Cost:** two insert bodies moved out of the screens that own them, so a change to what a dispatch
writes has to be made in `app.js` as well.

### The numbers go on the entity; dead stock stays a report
**Why:** he will open a Numbers tab twice. The same facts on the product, the customer and the piece
get read every time somebody rings up.
**Cost:** three more queries on three detail views. Dead stock is the exception and stays a report,
because gear he has forgotten he owns surfaces nowhere else by definition.


### 0027 restates a view that 0025 already got right, because the history was wrong
`0025` shipped `v_customer_figures` with `coalesce(receivable, 0)` — rule 14 broken inside the
migration that cites rule 14, since the money is joined through a gated wrapper that returns zero
*rows*, so the coalesce reported every customer as owing nothing to anybody without `ledger.view`.
That was fixed by **editing `0025` after it had already been applied**, on the reasoning that it was
uncommitted and there is one database.
**Why 0027 exists anyway:** that reasoning is convenient rather than sound. An applied migration is
a record of what ran, and editing one makes the schema stop matching its own history *independently*
of whether the end state is correct — the CLI keeps a `statements` array per migration exactly so
that divergence can be detected. `0025` stays in its corrected form so a fresh replay from `0001` is
right first time; `0027` restates the view so a database that ran the broken text converges to the
same place. Whichever road a database took, it ends at `0027`.
**Cost:** a migration whose SQL is redundant — `0026` had already restated the view. Its real
content is the note and an assertion that fails if either mistake comes back. And on checking,
`statements` is null for everything from `0019` on, so for `0025` there was nothing to diverge from:
the edit was not detected, merely unrecorded, which is worse. Those rows were **not** backfilled —
writing statements one merely believes ran would fabricate the record whose absence is the problem.

### Damage photographs go in a second, private bucket
`0028`. `product-images` is public because the customer portal shows it.
**Why not reuse it:** a photograph of a cracked cabinet is taken inside somebody's wedding hall —
their property, their event, their guests in the background. A public bucket is world-readable at a
URL that has to be guessed only once, and that is not our picture to publish. Two buckets with
opposite defaults means nothing has to be remembered at upload time.
**Cost:** every look is a signed URL and therefore a round trip, and `getPublicUrl` must never be
called on it — the call succeeds and returns a link that answers 400, which is the worst failure
available: something that looks like a link.

### A photograph is a draft until a movement points at it, and evidence afterwards
**Why:** the first version granted neither UPDATE nor DELETE on the bucket, citing rule 12. That
applied one rule to two different things. Before the return is recorded, a blurry picture of a floor
taken one-handed in a hall is a draft and the retake is the normal case; after it, the photograph is
attached to an append-only row and must not move. The policy asks that question directly — *is any
movement pointing at this key?*
**Cost:** a `jsonb` containment test on every storage write, which needs a GIN index on
`movement.photos` to not be a sequential scan over every movement ever recorded.

### Photos are attached at INSERT or not at all
**Why:** `movement` is append-only, so there is no later moment to attach one. The upload therefore
happens when the picture is taken and the path is held until "Record returns".
**Cost:** a forgotten photograph needs `0019`'s correction path to get in — the movement has to be
undone and rewritten. Judged acceptable because the screen puts the camera in the row, under the
deduction, which is the only moment anybody is looking at the damage. The counterweight is on
screen: money coming off a deposit with no photograph shows a warning until there is one.
