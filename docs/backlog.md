# Backlog

Found and deliberately not fixed. Hardening stopped at `0009` on purpose: three migrations deep on
an empty catalogue is what killed the previous builds, and none of them failed on technique. Nothing
here blocks seeding or screens.

Each line is the concrete failure, not the tidy description of it. Anything `guardrail-reviewer`
turns up from here lands in this file and waits.

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

## Housekeeping

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
