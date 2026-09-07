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

## BLOCKING — do not deploy until this is done

**Self-registration is open, and the publishable key is about to become public.** Measured
2026-09-07 against `hjidocpqcrfbjucvqggu`:

    disable_signup      false          anyone may create an account
    email provider      enabled
    mailer_autoconfirm  false          they confirm from an inbox they control
    auth.users          0 rows         no operator account exists yet either

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



**A `reversal` cannot undo an `upcoming` charge, so the documented compensating mechanism only half
works.** `decisions.md` accepts reversal entries as the price of posting revenue on confirmation.
But `v_customer_balance.upcoming` counts only billed types (`rental`, `transport`, `labour`, `misc`,
`damage`) at `state = 'upcoming'`, and `reversal` is not one of them — so a reversal posted against
an upcoming charge changes neither `receivable` nor `upcoming`, and a reversal posted as `due` drives
`receivable` negative instead. Measured while trying to undo three stray rows: an `upcoming` of
43,060.00 could not be reduced by any ledger entry the schema permits. Deleting is blocked by the
append-only guard, correctly. Whatever posting looks like, it needs a way to be undone that the
balance view actually honours.

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



**The portal code has no rate limiting, and that is the weak point of the portal.** `fn_portal_view`
is callable by `anon` over `/rest/v1/rpc/fn_portal_view` with no throttle. The code is eight
characters from a 32-symbol alphabet — about 10^12 combinations, which is far too many to guess by
hand and not obviously too many for a script left running. The phone number narrows nothing, since
a customer's WhatsApp number is not secret. Mitigations, roughly in order of effort: a per-IP rate
limit in front of the function, a lockout counter on `customer` after N failures, or the change that
makes this moot — replacing the static code with a one-time code, which `docs/open-questions.md`
item 2 already prefers. The gate was deliberately built as a separate function from the query so
that swap touches nothing else.

**The Sheet's IN lane does not exist yet.** `sheet/DataSync.gs` and the `sheet-mirror` function are
the read-only mirror OUT. The bulk catalogue importer — the lane that actually matters, because the
catalogue is empty and the fleet runs to hundreds of items — is still to build, with validation
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
