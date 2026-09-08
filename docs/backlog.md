# Backlog

Found and deliberately not fixed. Hardening stopped at `0009` on purpose: three migrations deep on
an empty catalogue is what killed the previous builds, and none of them failed on technique. Nothing
here blocks seeding or screens.

Each line is the concrete failure, not the tidy description of it. Anything `guardrail-reviewer`
turns up from here lands in this file and waits.

Every measured finding below was re-confirmed on **2026-09-06 against the current Mumbai database**
(`hjidocpqcrfbjucvqggu`), after the schema was replayed there from scratch. The numbers reproduced
identically to the retired project, which is the only evidence available that the replay carried
behaviour across and not merely row counts — the Cowork session that used to hold a second copy of
the truth can no longer read this database at all.

---

## The decision that removes three entries below

**Before the first real customer is billed — post revenue on dispatch instead of confirmation, and
make the forward book a view over confirmed order lines rather than ledger rows. That removes the
upcoming/due state and the reversal mechanism entirely. Three entries above trace to this one
decision.**

The trigger is the first real bill, not a date. Everything works today on a fixture; none of it has
met a customer who queries an invoice.

What traces to it: the damage charge recorded on return that never reaches the balance; the
`deposit_amount` / `deposit_held` label collision; and the whole reversal apparatus that `0018` had
to make work — a `reversal` now carries its target's state and subtracts in the right bucket, but
the reason it exists at all is that a charge is written to the ledger before the gear has moved.
Post on dispatch and the forward book becomes a query over `order_line` for confirmed orders whose
`out_date` has not passed: nothing to reverse, nothing to keep in step, and no `state` column
carrying a meaning the ledger cannot enforce.

`docs/decisions.md` chose confirmation-time posting deliberately, for a forward book that is useful.
This does not undo that — it keeps the forward book and stops paying for it in ledger rows.

---

## CLOSED by `0017` — kept as the record of what it was

This was the BLOCKING entry. `0017_operator_allowlist.sql` closed it by a different route than the
one proposed below: instead of relying on the signup toggle, every policy on all 16 tables now tests
membership of the `operator` table, so a stranger who self-registers is `authenticated` and still
reads zero rows. Turning signups off is still worth doing — it is one less door — but it is no
longer the thing standing between the key and the data. The README's Status section says the same.

The original text, unedited:

**~~Self-registration is open~~ — CLOSED 2026-09-08, and this time verified from outside.** The
entry stays as a record of how it read, because it was reported done twice before it was true:

    2026-09-07  disable_signup  false      anyone may create an account
    2026-09-08  disable_signup  true       POST /auth/v1/signup -> HTTP 422 signup_disabled,
                                           and no auth.users row created

Checked by making the request with the publishable key, not by reading the dashboard — which is the
only reason it can be believed now, given it had been called done twice already.

`web/config.js` is committed and ships the publishable key to the browser, which is correct and by
design — but it is only safe because the sole route to `authenticated` is supposed to be an account
chachu created. With signups open, the route is a public form. And `authenticated` is not a limited
role here: the `operator_all` policy grants ALL on **all 16 tables**. So publishing the site as it
stands hands the whole database — customers, ledger, movements, orders — to anyone who reads the
page source and confirms an email.

**Fix before any deploy:** Authentication → Sign In / Providers → Email → turn OFF *Allow new users
to sign up*. Then create the one operator account under Authentication → Users → Add user, with
*Auto Confirm* ticked.

This is why GitHub Pages deployment was refused in Batch D rather than done and flagged.

---

## Decisions the owner has to make first

These are not bugs. The answer changes the fix, so writing the fix now would be guessing.

**Pooled repairs — `repair_job.unit_id` is `not null`.** A repair on pooled stock cannot be recorded
at all, so a cable rewired at a shop never appears in `v_product_roi` and its cost is invisible.
Whether pooled items are repaired or simply binned is a question for chachu; if they are binned,
this is correct as it stands and the backlog entry closes.

**Consumables are not restocked through the ledger.** `product.pool_qty` is the opening balance and
`0008` nets `intake`, `found`, `return` and `write_off` on top of it, so restocking works — but
there is no *form* for it, and the first person to hit this will edit `pool_qty` by hand, which is
the stored count rule 10 exists to stop anyone trusting. Needs a screen, not a migration.

**Which system is authoritative for receivables.** Still open, still blocking the ledger and portal.
See `docs/open-questions.md` item 1 — this is the oldest unanswered question in the project.

**Revenue posting and reversal entries do not exist.** `decisions.md` says rental charges post on
order confirmation as `state = 'upcoming'` and become `due` at dispatch, and names reversal entries
as the acknowledged cost. Nothing writes any of it — no code posts a charge, moves it to `due`, or
reverses it. `0009` guards the consequence rather than the cause: an order line's money cannot be
deleted or changed while its order carries a non-zero net posted charge, so a stale charge can never
silently overstate the customer. That guard is inert today (no ledger rows exist) and arms itself
the moment posting is built. **The migration that implements posting must revisit it** — the shape
of a reversal, whether charges post per order or per line, and the `upcoming` → `due` transition are
all still undecided, and the guard deliberately assumes none of them.

---

## Correctness, ranked by what it costs when it fires

**A same-day dispatch and return written in one transaction makes `v_unit_status` arbitrary.**
`v_unit_location` picks a unit's current position with `distinct on (unit_id) ... order by moved_on
desc, created_at desc`. `created_at` defaults to `now()`, which is transaction-scoped, so every
movement written in one transaction shares a timestamp — and when `moved_on` matches too, the
tiebreak has nothing left to break and the winner is arbitrary. Measured: a piece dispatched and
returned on the same day in one transaction reads `out` while it sits in the godown; the same tie
can resolve the other way and report a piece `available` while it is at a wedding, which is rule 2's
six-out-five-back bug arriving through a new door. Reachable in production because `structure.md`
form 7 queues dispatch offline and syncs — a flush lands both rows in one transaction. Separate
transactions are safe (timestamps differ), which is why it has not shown up before. Fix needs a
monotonic tiebreak the table does not currently have: a `bigserial` sequence column on `movement`,
ordered last. Note this also silently affects `v_order_outstanding`, `v_product_stock` and rule 9,
all of which read unit position through this view.

**Prompt 8 (dispatch) — the pin is validated but not yet honoured.** `0011` made
`order_line.pinned_unit_id` trustworthy: a pinned piece must belong to the line's product, and one
box cannot be pinned to two overlapping orders (nor twice on one order), enforced on the line and
again when an order's dates move. What it deliberately did NOT do is make anything *act* on the pin.
`fn_availability` still ignores it, correctly — pinning constrains WHICH piece goes, not HOW MANY
are free, so the aggregate is genuinely unaffected and teaching availability about pins would only
let a pin double-count against its own line. Honouring it belongs to the dispatch screen: offer the
pinned piece first, and say so plainly when it is not on the shelf. Until that exists, a pin is a
recorded intention that no screen reads.

**Prompt 11 (payments and ledger) — a deposit can be refunded beyond what is held.**
`deposit_in` 1000 followed by `deposit_out` 4000 leaves `v_customer_balance.deposit_held` at
**-3000.00** with no error and no flag. Rule 6 survives — `receivable` was unaffected at 3000.00, so
the two numbers never blend — but a negative liability is not a state the business can be in, and on
the portal it reads as the company owing the customer money it never took. Deliberately left to the
payments screen rather than fixed in the schema: that is where the number is typed, where the
operator can see what is already held, and where refusing is a sentence rather than a stack trace. A
database guard would be the fallback if the screen ever writes ledger rows some other way.

**BLOCKED ON A DECISION — lost units stay in the ROI cost denominator; retired units do
not.** `v_product_roi`'s cost CTE filters `where u.lifecycle <> 'retired'`, so a piece marked `lost`
keeps contributing its purchase cost. Measured on MIC-BLX: `purchase_cost` 126500.00 with one piece
retired; mark another piece lost and it stays 126500.00, while `v_product_stock.units_on_hand` and
`fn_availability` both correctly drop from 4 to 3. Including a lost box makes ROI look *worse*, not
better, so this understates rather than flatters — but two lifecycles answering the same question
differently is undocumented, and `v_product_roi` was deliberately not touched.

**The question for the owner is what that report means.** *Lifetime return* — everything ever bought
stays in the denominator, so the number answers "was buying this kind of gear a good idea", and
retired pieces should be put back in. *Current-fleet return* — only what he still owns counts, so
the number answers "is what I have now earning", and lost pieces should come out alongside retired
ones. Both are defensible and they give different answers; the fix is opposite depending on which he
means. Do not guess.

**`from_kind` / `to_kind` are not validated against `movement_type`.** This is the price of `0008`'s
ledger model and it is written into that migration. A dispatch of 12 recorded with `to_kind = 'none'`
takes both on-hand and owned from 185 to 173, leaves `qty_at_customer` at 0, produces no outstanding
row, and `has_ledger_error` does **not** catch it — nothing arithmetically impossible happened. Fix
is a trigger tying each movement type to its legal kind pairs, which changes what the ledger accepts.

**`0007`'s movement trigger reports a stale `product_id` as an RLS failure.** `before insert` row
triggers fire before foreign key checks, so a movement naming a product that does not exist hits the
fail-closed branch and reports *"that product cannot be read from this session"* instead of the true
foreign key violation. The concrete case: an offline dispatch queue syncs after a product edit,
chachu is at the van, and the error tells him it is an access problem. Two extra lines to
distinguish `not exists` from readable-but-hidden.

**`v_unit_status.on_hand` is NULL, not false, for a unit with no movement.** `(lifecycle = 'active'
and at_kind = 'location')` is `true and NULL`. With 7 units, `where on_hand` returns 3 and
`where not on_hand` returns 3 — piece 7 is in neither bucket and vanishes from both sides of every
screen that filters on it. `days_in_place` is NULL on the same row and will render blank or zero.
The row shape is real: it is the half-finished intake that `0007` cites as its reason for guarding
unit deletes. Wrap both in `coalesce(..., false)`.

**Flipping `tracking_mode` from `unit` to `pool` silently collapses availability.** Permitted with
`pool_qty` left NULL, so a product with 6 numbered boxes, 3 on the shelf and 3 committed, goes from
`3 / 3 / 0` to `0 / 3 / -3` on one dropdown change. Histories survive, which is what `0007`'s comment
promises, but the number on the screen does not. The reverse flip is loudly rejected by the CHECK.
Wants a trigger refusing the flip while `unit` rows exist.

**`availability_override` is read by nothing.** `rental_order.availability_override` and its reason
column exist, `decisions.md` describes them as the recorded escape hatch for same-day turnaround,
and `fn_availability` has never consulted either. If the frontend implements the override in
JavaScript, the screen and the database will disagree about what is bookable.

**An order can be born `closed`.** `0009`'s rule 9 guard is a `before update` trigger, so
`insert ... status = 'closed'` followed by dispatching against it produces a closed order with gear
at a customer. Pre-existing; `0010` is what made it visible. `supabase/seed/dev_seed.sql` routes
around it deliberately — it inserts `confirmed` and updates to `closed` after the returns — so the
fixture exercises the guard rather than dodging it. Fix is an insert branch on that trigger.

**`v_pool_stock` counts consumed stock as still owned and still at the customer.** Fog fluid issued
9 of 24 reads `qty_owned = 24` and `qty_at_customer = 9` — the litres were burned, not held, and
nobody is going to telephone the customer about them. Harmless where it matters (`qty_on_hand` is
right at 15, and `v_order_outstanding` correctly reports 0 for consumables, so rule 9 does not block
the order), but the two columns read as nonsense on a screen. Noted in `0008` and `0010`'s comments;
the honest fix is either separate columns for consumables or suppressing those two for that mode.

**A negative pooled outstanding is invisible in `v_order_outstanding`.** The `> 0` filter is correct
per spec, but it means an over-return (25 dispatched, 30 returned) shows nothing there. It surfaces
as `has_ledger_error` in `v_pool_stock` instead, which is a different screen nobody may be looking at.

**`v_unit_utilisation.days_owned` is 1 for a unit with no purchase date and no movements.**
`greatest(NULL, 1)` is 1. Harmless while `days_out` is also 0, but the first hire of such a unit
divides by 1 and produces a three-figure utilisation percentage.

**`v_unit_utilisation` under-counts a same-day re-dispatch.** `back_on` takes the earliest return at
or after the dispatch, so dispatch → return → dispatch on one day binds the second span to a
zero-length return. Same-day turnaround is the case `decisions.md` explicitly deferred, so fixing
this pre-empts a decision that has not been made.

**Two foreign key actions are now dead code.** `movement.order_id on delete set null` and
`order_line.pinned_unit_id on delete set null` can no longer fire, because neither parent can be
deleted. Harmless, but they read as live paths to anyone tracing what a delete would do.

---

## Screens (prompt 6 and after)

**No Content-Security-Policy, because every screen's code is an inline `<script type="module">`.**
A `script-src` would have to allow `'unsafe-inline'`, which permits exactly the injection a CSP
exists to prevent — a header that looks like protection and is not. Product names arrive from a
Google Sheet import, so the injection surface is real, and `esc()` on every interpolation is
currently the only thing holding it. Fixing it properly means moving each page's module into its
own `.js` file, then a strict `script-src 'self'`. Worth doing before the importer ships.



**A damage charge recorded on return never reaches the customer's balance.** The return screen writes
an `order_charge` for the excess over the deposit — verified, ₹2,000 on DJN-2609-0007 — but revenue
posts to `ledger_entry` only at order confirmation, so the charge exists on the order and is invisible
to `receivable`. The customer was billed ₹10,800 and owes ₹12,800.

**`rental_order.deposit_amount` and `v_customer_balance.deposit_held` share a label and are different
quantities.** The order form's "Deposit held" is the *agreed* figure typed when the job was booked;
the ledger's is money actually received as `deposit_in`. On a fresh order the first says ₹8,000 and
the second says ₹0. Renaming the order field to "Deposit agreed" would cost nothing and remove the
collision.

**No way to remove a product photo.** A blurry first shot in a dark godown becomes the primary image
and the product's face on the portal permanently. Needs a decision about deleting the storage object
and about `0006`'s sync trigger when the primary row goes.

**A pooled write-off proposes ₹0.** `decisions.md` says a lost *unit* proposes its own purchase cost;
pooled stock has no per-piece cost, though `product.default_purchase_cost` exists. Whether a customer
is charged for lost cables is chachu's call.

**The portal ledger shows unsigned amounts** — "Payment received ₹5,000.00" sits beside "Equipment
hire ₹10,800.00" with direction carried only by the label. The operator ledger signs them. May be
deliberate for a customer view.

**"Cancel order" is a full-width red button, first in the sticky bar, the same weight as Save.** It is
`confirm()`-guarded, so this is layout judgement rather than a defect — but one-handed at a van it is
the most dangerous button on the screen and the easiest to hit.

**Creating a product closes the sheet**, so photographing the box you are standing next to means
finding it in the list and reopening it.



**The Sheet's IN lane does not exist yet.** `sheet/DataSync.gs` and the `sheet-mirror` function are
the read-only mirror OUT. The bulk catalogue importer — the lane that actually matters, because the
catalogue is empty (torn down to empty on 8 Sep 2026 after the fixture was found in production) and the fleet runs to hundreds of items — is still to build, with validation
before import and per-row rejection reasons. See the `djn-sheet-sync` skill.



**Offline is unimplemented end to end, and the CDN is a hard dependency at boot.** Every screen's
code is a module whose first line imports the Supabase client from jsdelivr; with the CDN
unreachable the browser discards the whole module graph in silence. `web/boot.js` now turns that
into a sentence the operator can act on, but it cannot make the app work — there is no service
worker and no local copy of the client. `docs/structure.md` form 7 requires dispatch and return to
queue offline in IndexedDB and sync on reconnect, so this blocks prompt 9. Vendoring the client
conflicts with keeping it pinned on a CDN, and a service worker is an architecture decision rather
than a fix.

**No per-piece edit and no lifecycle transitions.** Bulk intake applies one condition, one cost and
one note to every piece it creates, which is the point of bulk — but nothing anywhere can then edit
a single piece. A serial number can never be entered (form 3 lists it as a field), a condition can
never be updated after intake, and nothing can be retired, marked lost, or found. Rules 4 and 12
both assume those transitions exist.

**`publicUrl()` still accepts an external `http` image URL.** `docs/decisions.md` says product
images are stored, never linked — a WhatsApp or Drive URL rots and the customer portal then shows a
broken product. The branch presumably exists for the Sheet importer. Decide whether the importer
fetches and stores, in which case this branch should go.

**Editing `specs` coerces jsonb values to strings.** Values are read into text inputs and saved back
with `isNaN(Number(v)) ? v : Number(v)`, so a nested object becomes the literal `[object Object]`
and the `powered` boolean in the Speaker template becomes the string `"true"`. Silent lossy editing
of a jsonb column; the right shape depends on what the catalogue importer actually produces.

**`v_product_roi` has no cost basis for pooled or consumable products.** Purchase cost is summed
from `unit` rows, and pool and consumable products have none — so CBL-XLR reads
`rental_revenue 8160.00` against `purchase_cost 0` and `roi_pct` NULL, and always will. `pool_qty ×
default_purchase_cost` is the obvious denominator. This is rule 13 arriving in the ROI report, and
it was not touched by `0012`, which was scoped to the lifetime-versus-current-fleet question.

---

## Housekeeping

**Nothing answers "where was this piece on date X".** Every position view is current-state only —
`v_unit_location` takes the last movement, full stop. Reconstructing a past position means querying
`movement` by hand with `order by moved_on desc, created_at desc limit 1`, which is what verification
had to do to prove a piece was on the shelf between two hires. Fine for now: no report needs it, and
utilisation counts spans rather than sampling dates. It becomes real the first time someone asks what
was available last Tuesday, or wants to audit a disputed hire.

**`product.updated_at` has no maintaining trigger.** Only `0006`'s image sync ever sets it, so the
column is stale everywhere else and cannot be used to detect edits — which the Sheet mirror will
eventually want.

**A from-scratch replay onto an existing database fails at `0003`.** `0003_views.sql:117` errors with
*cannot change data type of view column "units_active" from integer to bigint*, because `0008`
recreated `v_product_stock` with `int`. Normal pushes are unaffected — each file applies once — and a
clean-slate replay is fine. It only bites re-running the whole series over a database that already
has `0008`, which is what a "reset and replay" would do.

**Four unindexed foreign keys**, flagged INFO by the performance advisor:
`movement.repair_job_id`, `order_line.pinned_unit_id`, `order_line.subhire_vendor_id`,
`repair_job.vendor_id`. Meaningless at zero rows; revisit once there is traffic.

**The 187-subcategory taxonomy has never been walked by the owner.** `open-questions.md` item 6.
The product master currently offers 187 choices for a fleet that probably spans 40, and every one of
them is a chance to file a speaker under the wrong heading.

**The seed fixture creates no product photographs, so the pick list's photo path is only ever
exercised by hand.** `dispatch.html` leads each line with the product photo and carries the image
into the offline record as a Blob — verified on 2026-09-07 by uploading one JPEG through
`products.html` and reading a 9,361-byte Blob back out of IndexedDB under the job's own cache key.
But `dev_seed.sql` writes no `product_image` rows, so after every reset the pick list shows the
short-code fallback tile for every product and nobody looking at the fixture would know the feature
exists. Seeding an image means either committing a binary to the repo or generating one at seed
time in SQL, and neither is obviously right.

**`web/tokens.css` is provisional and nothing enforces that.** The palette is derived from a
behavioural document that explicitly does not own visual styling, because the Brand Kit it defers to
is not in this repo. Three of its semantic colours are fills that fail as text and carry derived
partners here. There is a contrast checker in `docs/design.md` but nothing runs it — a future edit
that puts `--grey` back on a hint would be caught by a person or not at all.

---

## From the design pass (2026-09-07), raised and not fixed

**Borders are too faint to aim at, and this pass made them ~8% fainter.** `--line` `#E7E8E6` on the
page ground measures **1.11:1** (was 1.20 with the old `#dfe3e8` on `#f6f7f9`); an input border on
white is **1.23:1** (was 1.29). WCAG 1.4.11 asks for **3.0:1** on the boundary of a control you have
to hit. Both the old and the new palette fail it — the change is a small regression on an existing
failure, not a new one — but the fields and the `.piece` tiles are exactly what gets aimed at
one-handed in sunlight. Fixing it means overruling the bible's own `--border`, which is a token
decision, so it is recorded rather than taken: `web/tokens.css`.

**No seeded order has a numbered line and a counted line both still to go out, so the Send-out
screen's most dangerous path is not covered by the fixture.** That gap hid a real bug: "Pick N"
re-rendered the counted-stock box to `0` while `POOLPICK` still held the typed number, and the
POST carried the number the box no longer showed — seven cables leaving the godown under a box
reading zero. Found by `ui-reviewer` injecting a pooled line on the wire, not by the walk, because
the walk cannot reach it. Fixed in `dispatch.html`, but the fixture still cannot catch a
regression. `dev_seed.sql` needs an order with both.

**`errorBlock` shows the operator the raw Postgres message.** With a 500 injected, all nine screens
rendered *"Could not load — relation "v_thing" does not exist"* verbatim. Defensible while the
operator is also the developer, and it is the opposite of every other rule in `docs/design.md`.
Pre-existing; `web/app.js`.

**`dispatch.html` says "No connection." for any failure**, a 500 on a good link included. Measured.

**Two empty states are wrong on day one.** Send out says *"Every live order has been fully sent
out"* and Return says *"Everything that went out has come back"* when in fact nothing has ever gone
out. On an empty catalogue both read as a completed day's work.

**`orders.html` "no customers yet" is the one empty state with no button.** Every other one offers
the fix; this one says *"Add a customer first"* and leaves the operator to find the tab.

**The tab strip hides five tabs behind a scroll with no affordance.** At 375px the nav measures
`scrollWidth 752` inside `clientWidth 252`: Ledger and Numbers, among others, are off-screen with
nothing on screen saying so. The bar is correctly one row and 59px; the scroll is the deliberate
trade from an earlier pass, but it needs an edge fade or a chevron.

**`portal.html` builds a second GoTrue client.** It creates its own (session-free) client and also
imports `app.js`, which creates one at module load under the same storage key — hence *"Multiple
GoTrueClient instances detected"* in the console. Harmless today. The fix is splitting the helpers
out of `app.js` so a page can import `esc`/`money`/`fmtDate` without instantiating a client, which
is the same refactor the CSP entry above wants.

**`units.html` does not return focus after the bulk sheet closes.** `openBulk` sets
`trigger.disabled = true` while it fetches the next piece number, which blurs the button, so
`openSheet` captures `document.body` as the opener. Products, customers and orders all return focus
correctly.

**Writing a correction is not gated on a permission, because there is no permission table.** `0019`
lets any operator write a `correction`, which undoes a movement everywhere it is counted. `0017`
gives one undifferentiated operator role, so there is nothing finer to test — and a policy that
grants everybody the right while pretending to check one is worse than none. When a permission pass
lands, `movement.correct` is the gate, and `fn_correction_matches_target` is where it goes.

**Nothing generates the WhatsApp messages the order number exists for.** The source briefing
requires an ID in every message about a job; `docs/structure.md` now records that requirement again
after it was lost in the spec. Until the messages are generated, the operator types them by hand and
looks the number up himself — work this app added rather than saved. Booking confirmed, on its way
with the driver's number, came back short, payment pending, and a one-tap overdue reminder are all
predictable from data already on screen. Two guards when it is built, both from rule 6: never offer
a payment chaser when `receivable <= 0` (a credit balance is reachable since `0018`), and never
blend deposit held into what is owed.

**~~Self-registration is still open~~ — DONE 2026-09-08.** `disable_signup` is `true`;
`POST /auth/v1/signup` answers HTTP 422 `signup_disabled` and creates nothing. `0021` had already
made it harmless — a signed-in account with no `operator` row reads 0 rows from all 17 tables and is
refused on every write — but the front door is now shut as well as guarded, and the Today and Team
warnings go quiet on their own because they read the live auth settings rather than a constant.

**`numbers.view` does not protect the cost columns themselves.** The reports are gated, but
`unit.purchase_cost` and `repair_job.actual_cost` are still readable by any active operator, because
the operational screens select whole rows. Closing it means column-level grants, which break
PostgREST's `select *`. Worth doing only if somebody without `numbers.view` ever holds an account.

**No Team screen.** `fn_admin_set_operator` is the only way to grant a permission and it is not
callable from a browser, so today a person is added by hand with the service key. The screen comes
with Pass G's navigation, which re-flows to the modules a person actually holds.

## From Pass G

**The fifth navigation slot changes identity.** On Today, Orders, Send out, Return and Can I say
yes it is *Return*; on Products, Equipment, Customers, Ledger, Numbers and Team it is that screen,
because the active destination is swapped onto the bar so it can be highlighted. Every module stays
reachable — verified, all eleven from all eleven — but the thumb learns a position that moves. The
two alternatives are a sixth fixed slot, or highlighting **More** when the active screen lives
inside it and leaving the bar alone.

**"11 late" on Orders and "4d late" on Today are the same word for different things** — one counts
pieces, the other counts days. Same order, two screens, one label.

**Nothing lists what is queued offline.** The pill says `Offline · 1 waiting` and is an inert
`<span>`; `db.js` has `allPending()` and `discard()` with no screen behind them. `flush()` stops at
the first failure with a single transient toast, so a permanently-failing write shows as a pill
that never clears and cannot be inspected or dropped.

**Five copies of `friendly()`.** orders, products, units, dispatch and return each translate
Postgres errors their own way and only one calls `networkMessage()`. It belongs in `app.js`; it is
a five-file refactor and was not worth doing inside this pass.

**`label > button` at `dispatch.html`.** The "All N" button on a counted-stock line is a labelable
descendant of a `<label>` that is not its control — an invalid content model. Chrome behaves
correctly (focus stays, the quantity sets, no keyboard appears); iOS Safari is the device that
matters and was not testable here. The fix is moving the button out of the label.

---

## From the return-photos pass (`0028`)

**A damage photograph can only be taken on a NUMBERED piece, not on counted stock.** `movement.photos`
accepts a photo on any row and the return screen writes write-offs for pooled products — twenty
cables lost at a venue is a money conversation like any other. But `v_unit_history`, the only view
that reads photos back, filters `unit_id is not null`, so a photograph attached to a pooled row
would be uploaded, charged against a deposit, and viewable on no screen. The control is therefore
hidden on counted-stock rows rather than offered and quietly useless — rule 13, honoured by
declining rather than by pretending. The fix is a `v_order_history` that reads
`v_movement_effective` for a whole job, pooled rows included, which is also the read path a repair
screen will want.

**A photograph cannot be added to a return after it is recorded.** `movement` is append-only, so
`photos` lands in the INSERT or not at all. The only way in afterwards is `0019`'s correction — undo
the return, record it again with the picture — which is a heavy instrument for "I forgot to
photograph it". Accepted for now because the camera sits in the row under the deduction and the
summary warns when money comes off a deposit with no photograph. If it turns out to bite, the answer
is a `movement_attachment` table rather than making `photos` updatable, because a mutable evidence
column on an append-only row is the worst of both.

**Nothing sweeps orphaned photographs.** A picture uploads the moment it is taken; if the return is
then abandoned the file stays in the bucket with no movement pointing at it. The path starts with
the order id so an orphan is traceable, and `0028`'s policy lets an unattached file be removed — but
there is no job that does it, and nothing on any screen shows that these exist.

**A photograph needs signal; the return does not.** The return itself queues offline and replays,
but there is no offline path for the file — the screen says so in as many words rather than failing
into a red box, which is the improvement over saying nothing. Holding the blob in IndexedDB and
uploading on reconnect is the fix, and it means the queue carrying binary rather than JSON.

**`photos` has a `caption` in its contract and nothing writes one.** The shape allows
`{path, at, caption}` and the return screen sends only the first two. A caption is what turns "a
photograph of a speaker" into "the crack on the back panel, left corner" a week later on the phone.

**GitHub Pages drops five of the six headers in `web/_headers`, and one of them mattered.**
Measured on our own live origin, which corrected an earlier measurement taken on a different
`github.io` site: **`Strict-Transport-Security: max-age=31556952` IS sent** — that one is not lost.
`X-Frame-Options`, `Referrer-Policy`, `Permissions-Policy`, `X-Content-Type-Options` and both
`Cache-Control` rules are, and a CSP `frame-ancestors` cannot be set either. `portal.html`
now defends itself in-page — hidden by default, revealed only when it confirms it is the top window
— because that page takes an access code and a framed copy under a transparent overlay harvests it.
The operator screens have no such guard and rely on the sign-in gate. The real fix is a host that
sends headers; `web/_headers` is kept for exactly that.

**~~`config.js` is fetched twice on every page load~~ — FIXED 2026-09-08.** It was `db.js` as well,
which the first report missed: `app.js` imported both bare while all thirteen HTML files asked for
`./config.js?v=<bust>`, and a module's identity is its resolved URL. Both now carry the version, so
the deploy sed reaches them and `grep -ro "<old>" web/` returns 0. The lesson is recorded in the
`djn-deploy` skill rather than only here: it survived the whole build because nothing about it is
visible locally, and it appeared as two lines in the live network panel the first time the app was
served from a real origin.

---

## From the v6 Brand Kit pass

**The raised central New (+) FAB — PARKED, not rejected.** v6 Part C puts a raised solid-teal
circular FAB at the centre of the bottom nav, opening a 2x2 grid of large icons. Part C's *contents*
do not apply here, but the pattern is worth having: for this business the four would be **New order ·
New customer · Send out · Add equipment**, replacing four journeys that today each begin by
navigating to the right screen first.

Two caveats, both real, and the reason it is parked rather than built:
- **It makes the nav six slots where five were fixed.** The five fixed slots were themselves a fix
  for a bar that re-flowed and moved the target under a moving thumb. A centre FAB is a sixth
  position and needs deciding, not assuming.
- **The grid must hide what the person cannot do.** "Send out" needs `sendout.write`. Offering it to
  somebody who will then be refused teaches them the app is unreliable — and it is the same mistake
  as a permissions matrix, one screen later.

Navigation has been rebuilt twice in one day. A third rebuild for a user who has not yet opened the
app is speculation, and it should wait until chachu has used the nav that exists.

**Preserving an in-progress form draft is not done.** v6 Law 11 asks for drafts, selections, filters
and scroll. Scroll is preserved (in `cardList`), filters and search are preserved for the orders list
(`rememberFilters`, sessionStorage so they do not silently persist to tomorrow), and repeated taps
have been idempotent since `0024`. **Drafts are not**: a half-filled order sheet is still lost on
reload. It is the largest of the four and touches five sheets; doing it properly means deciding what
counts as a draft worth restoring and what is a stale form somebody abandoned on purpose.

**Durable confirmations exist on two screens, not everywhere.** `confirmBlock` (v6 Laws 4/10) is
wired into send-out and return — the two writes that move stock, and the two whose "did that work?"
ends in a phone call from a venue. The ledger, orders, customers and equipment screens still confirm
with a toast that is gone in 3.5 seconds. That is defensible for "Customer saved" and not for
"Payment recorded"; the ledger is the next one to do.

**"All 12" staged one piece.** On send-out for DJN-2609-0001 the button read *All 12* and dispatching
recorded a single item. The button's own comment says its number is "what WOULD be added by pressing
it — not the size of the order", precisely so it cannot lie; if only one piece was available at the
selected location then the count is wrong, and if twelve were staged then the write is. Found while
driving the v6 pass, not chased — it predates it, and it needs the availability numbers checked
against the pick list at a known location rather than a guess.

**Pooled ROI is computable and currently isn't.** `v_product_roi` sums `purchase_cost` over `unit`
rows, and counted stock has no pieces — so for CBL-XLR it reports `purchase_cost` 0 and `roi_pct`
null even though `product.default_purchase_cost` is ₹450 and chachu typed it. The reports screen
therefore says *"not tracked for counted stock"*, which is honest about the view and understates the
data: the number exists. Pooled ROI is `default_purchase_cost × quantity owned`, against the same
rental revenue. It is a view change and therefore a migration, so it was not done in the reports
pass — recorded here so it does not come to be believed impossible.

**~~The flat "no measurement" bar has no token of its own~~ — RESOLVED by deleting the bar.** The
hunt for a grey between `#D8D5C6` and `#828282` was the wrong question. A bar is a mark for a value;
when the return is unknown there is no value, so the row now carries no track at all. A short flat
bar reads as *a small number* and a full one reads as *complete* — both are the lie rule 3 exists to
stop, and no colour fixes that. It also leaves the only near-empty bar on the screen meaning an
honest zero.

**No in-app "clear this phone" control for the offline queue.** `factory_reset.sql` wipes the
server, but the IndexedDB `djn` queue on a device replays unsynced writes on reconnect — so a
practice dispatch made offline can reappear after a pre-go-live wipe. Today the only ways to clear
it are to let it drain online or to clear site data in the browser. A one-tap "this phone has no
pending work / clear it" action in the account menu would make the pre-go-live checklist safe
without depending on browser settings. Small, and it matters specifically at go-live.

