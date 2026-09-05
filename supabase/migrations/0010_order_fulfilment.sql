-- 0010_order_fulfilment.sql
-- rental_order.status stops pretending to know what has physically happened.
--
-- 0002 gave the column six values: confirmed, dispatched, partially_returned, returned, closed,
-- cancelled. Three of those six are countable from the movement ledger. They are stored counts
-- wearing an enum, which rule 10 forbids and rule 1 exists to prevent, and they rot for exactly
-- the reason a current_location column rots: the van gets loaded, the movement is written, the
-- dropdown is not, and the order list lies. There is one operator and nobody to catch it.
--
-- Worse than drift: one enum was carrying a TWO-DIMENSIONAL state. How much has gone out, and how
-- much has come back, are independent axes. There was no value for "4 ordered, 2 loaded" because
-- partial dispatch has no slot, and docs/structure.md calls partial dispatch normal in the
-- dispatch form. An order with 4 ordered / 2 dispatched / 1 returned is genuinely BOTH partly
-- dispatched and partly returned, and no single label can say so.
--
-- So:
--   1 · status narrows to confirmed | closed | cancelled — the only three a human decides.
--   2 · v_order_fulfilment counts the rest from the ledger, quantities first, label second.
--   3 · every reader of the old values is audited, and what happened to each is written down.
--
-- Measured on a replay of 0001-0009 with data anchored to 2026-09-05, not reasoned about. The
-- numbers appear beside the code they justify.
--
-- Nothing here stores anything that can be counted (rule 10). No column is added to unit (rule 1).
-- No delete path is added for orders, units or movements (rule 12). No date is allowed to imply a
-- return (rule 2) — nothing below reads current_date or expected_return_date to decide whether
-- something is back. condition and status stay separate axes (rule 3): this file does not touch
-- unit.condition and does not touch v_unit_status, whose `status` column is the DERIVED position
-- of a numbered piece and has nothing to do with rental_order.status. agreed_rate and line_total
-- are read as historical facts and never recomputed (rule 5). All three tracking modes are handled
-- and pooled quantities are read through the views that already know them, never re-derived
-- (rule 13).
--
-- No function's privileges change in this file, so there is no revoke/grant pair whose order could
-- matter. The one new object is a view, and it carries security_invoker.


-- ===========================================================================
-- 1 · status narrows to the three values a human actually decides.
-- ===========================================================================
--
-- confirmed  the job is agreed. docs/decisions.md: there is no quote stage, so this is the state
--            an order is born in and stays in for days or weeks while gear goes out and comes back.
-- closed     the operator has decided the job is finished. Rule 9 and 0009 section 5 guard the
--            transition: it cannot happen while anything is still at the customer.
-- cancelled  the job is off. Rule 12: an order is cancelled, never deleted, and 0007's delete
--            guard tells the operator so in as many words.
--
-- The three that go are the three the ledger already knows: dispatched, partially_returned and
-- returned. Nothing is lost — v_order_fulfilment below reports all of it, and reports the two
-- dimensions the single label could not.
--
-- THE REMAP RUNS FIRST, AND IT RAN AGAINST ZERO ROWS HERE.
--
-- rental_order holds zero rows on this database today; checked before writing, not assumed. So the
-- UPDATE below changes nothing in practice. It is written anyway because a migration that is only
-- correct against an empty table is a trap for whoever replays this series onto a database that
-- has data — a restored backup, a staging copy, a future branch. A CHECK constraint added to a
-- populated table validates every existing row and fails the whole migration if one does not
-- satisfy it, and the failure would arrive as a constraint violation naming a row nobody was
-- thinking about.
--
-- 'confirmed' is the correct target for all three. None of dispatched, partially_returned or
-- returned is a closed order or a cancelled one: each is a live job at some stage of physically
-- happening, which is precisely what confirmed means now. An order that was sitting in 'returned'
-- is not closed — closing is a decision, and rule 9 says it requires an explicit act. Remapping it
-- to 'closed' would manufacture that decision on the operator's behalf for every finished job in
-- the table, and would do it without the rule 9 check, since a bare UPDATE of the column is not
-- how that guard is reached. So: confirmed, and the operator closes what he means to close.
--
-- THE TRIGGER ORDERING, CHECKED RATHER THAN ASSUMED.
--
-- 0009 section 5 put a BEFORE UPDATE trigger on rental_order for rule 9. A bulk status UPDATE must
-- not trip it. It does not, and here is why: the trigger carries
--
--     when (new.status = 'closed' and old.status is distinct from 'closed')
--
-- so it fires only on the transition INTO closed. This UPDATE moves rows INTO 'confirmed', so
-- new.status is never 'closed' and the function body never runs. Verified on the replay rather
-- than reasoned about: an order sitting in 'dispatched' with three speakers standing at a customer
-- was remapped to 'confirmed' with no error, and the same order still refused to close afterwards
-- with the rule 9 message naming all three pieces. Both halves matter — the remap must pass, and
-- the guard must survive it.
--
-- Ordering within this file matters too. The UPDATE runs BEFORE the constraint is swapped, so it
-- is validated against the OLD constraint, and 'confirmed' is a member of the old six. Swapping
-- first and updating second would fail on the ALTER, because the rows would still hold values the
-- new constraint rejects.
--
-- RE-RUNNING THIS FILE IS A NO-OP. The UPDATE matches nothing the second time (no row holds a
-- retired value any more). The drop-then-add pair removes the constraint this file created and
-- lays down an identical one; `if exists` on the drop covers both the first run, where the 0002
-- constraint is being removed, and every run after. The constraint is named explicitly rather than
-- left to Postgres so that name is stable across replays — 0002 got the same name by convention,
-- which is why the drop finds it.
--
-- The ALTER takes an ACCESS EXCLUSIVE lock and validates every row. At zero rows that is
-- instantaneous; on a populated database it is a full scan of a small table, and there is one
-- operator, so there is no concurrency to plan around.
--
-- CHECK CONSTRAINTS REJECT WRITES SILENTLY from the client's point of view — CLAUDE.md says so and
-- it is the first thing to suspect when a save "does nothing". After this migration, any client
-- still POSTing status = 'dispatched' will simply fail. Nothing in this repo does: web/ is empty,
-- and a search of the whole schema and the whole repo found the three retired values only inside
-- migration files, listed in section 3 below.
-- ---------------------------------------------------------------------------

update rental_order
   set status = 'confirmed'
 where status in ('dispatched', 'partially_returned', 'returned');

alter table rental_order drop constraint if exists rental_order_status_check;

alter table rental_order
  add constraint rental_order_status_check
  check (status in ('confirmed', 'closed', 'cancelled'));

comment on column rental_order.status is
  'The operator''s decision about the job, and only that: confirmed | closed | cancelled. What has physically gone out and come back is counted from the movement ledger by v_order_fulfilment and is deliberately NOT stored here — dispatched, partially_returned and returned were stored counts wearing an enum (CLAUDE.md rule 10) and drifted exactly as a current_location column would (rule 1). Closing is guarded by rule 9; cancelling is how an order is removed from play, because history is never deleted (rule 12).';


-- ===========================================================================
-- 2 · v_order_fulfilment — the two dimensions, counted, with the label last.
-- ===========================================================================
--
-- QUANTITIES FIRST, LABEL SECOND, and that ordering is the whole design.
--
-- The five states the owner named — nothing dispatched, partly dispatched, fully out, partly
-- returned, all returned — are a ONE-dimensional projection of a two-dimensional state. An order
-- with 4 ordered / 2 dispatched / 1 returned is honestly both partly dispatched and partly
-- returned, and collapsing that into a single label inside this view would re-commit the exact
-- error being removed from the column. So the five numbers are the view's product and
-- fulfilment_state is a convenience computed from them. Every screen should read the numbers; the
-- label exists so an order list has something short to print.
--
-- The label is lossy BY CONSTRUCTION and that is stated here so nobody discovers it later. Two
-- worked examples, both real rows from the replay:
--
--   20 cables out, 5 back, 15 written off at the venue -> label 'all_returned', because nothing is
--   at the customer and nothing is left to send. Only 5 came back. The numbers on the row say
--   dispatched 20 / returned 5 and the operator can see the 15; the word cannot.
--
--   50 litres of fog fluid issued -> label 'all_returned', for the same reason and with the same
--   wart. A consumable is discharged at dispatch.
--
-- COLUMNS
--
--   qty_ordered       sum of order_line.qty
--   qty_dispatched    what has EVER left against this order
--   qty_returned      what has EVER come back against this order
--   qty_outstanding   what is still standing at the customer, now
--   qty_undispatched  agreed less ever-dispatched, clamped at zero
--
-- order_status rides along as a column. That is a deliberate addition to the shape asked for, and
-- 0008 set the precedent on v_order_outstanding for the same reason: the reader decides. This
-- migration's whole point is that the enum no longer tells you what happened physically, so an
-- order list needs BOTH the human decision and the derived fulfilment, and carrying it here means
-- the screen does one read instead of joining back to the table it just came from.
--
-- WHERE qty_outstanding COMES FROM, AND WHY IT IS NOT dispatch-minus-return.
--
-- The obvious definition is qty_dispatched - qty_returned, clamped at zero. It is wrong, and the
-- replay says by how much. Measured on 2026-09-05:
--
--   order          what happened                              dispatch-minus-return   really out
--   -------------  -----------------------------------------  ---------------------  ----------
--   DJN-2609-0003  40 cables out, 25 back                                        15          15
--   DJN-2609-0009  20 cables out, 5 back, 15 written off at
--                  the venue (0008 section 4)                                    15           0
--   DJN-2609-0010  50 litres of fog fluid issued                                 50           0
--
-- Two of those three are wrong, and wrong in the direction that matters. Stock leaves the loop by
-- three routes that are not a return movement:
--
--   a. pooled stock written off AT the customer. 0008 section 4 is the shrinkage path, and it is
--      recorded from_kind = 'customer', to_kind = 'none' precisely so the shelf is not deducted
--      twice. It clears v_order_outstanding. Counting movement_type only, it clears nothing, and
--      the order shows 15 cables outstanding forever.
--   b. a numbered piece marked unit.lifecycle = 'lost'. That takes it out of
--      v_unit_status.status = 'out' and therefore out of v_order_outstanding; its dispatch
--      movement stays exactly where it was written (rule 12) and would count forever.
--   c. a consumable. It was sold, not lent. 0008 excludes consumables from v_order_outstanding in
--      any state and explains why: including them would park 55 litres in the report permanently
--      and, under rule 9, make the order impossible to close.
--
-- All three are the three legitimate exits rule 9 names — found, write-off, loss — plus the
-- consumable case. And rule 9's guard, fn_order_close_requires_everything_back, tests
-- v_order_outstanding. So a movement_type-only qty_outstanding would put this view into open
-- disagreement with the close guard: the order list would read "partly returned" on a job that
-- closes without complaint. Two numbers for one concept, and the operator with no way to tell
-- which to believe — the disease this codebase keeps being treated for. 0008's header states the
-- cure in one line: one concept, in one place, read by everything else. Rule 13 says the same
-- about pooled quantities specifically.
--
-- So qty_outstanding is READ FROM v_order_outstanding and never re-derived. That view already
-- knows all three tracking modes, already handles the write-off and the lost piece, already
-- refuses to consult a date, and is already what rule 9 tests. In the ordinary case — dispatch,
-- return, nothing lost — it equals clamp(qty_dispatched - qty_returned) exactly, which is the case
-- on every rentable order in the replay. Where it differs, the difference is the answer:
--
--     qty_dispatched - qty_returned - qty_outstanding
--       = stock that left and did not come back by returning
--       = written off at the customer, or marked lost, or a consumable.
--
-- That identity is worth knowing and is why qty_dispatched and qty_returned stay raw and honest
-- rather than being bent to make the subtraction come out. A reader who checks the arithmetic and
-- finds a gap has found something real, not a bug in this view.
--
-- CONSUMABLES, SPECIFICALLY, since they are the case that has bitten this schema twice.
--   qty_ordered      counts them. The customer agreed to 50 litres; the order says 50.
--   qty_dispatched   counts them. 50 litres physically left the godown.
--   qty_returned     counts only genuine `return` movements. For a consumable that is the rare
--                    unopened bottle coming back, which 0008 already nets into stock. It is
--                    normally 0, and 0 is the truthful number: nothing came back.
--   qty_outstanding  is 0 the moment they are dispatched, inherited from v_order_outstanding.
--                    Fog fluid is not outstanding; it is sold. Anything else makes the order
--                    uncloseable under rule 9, permanently.
--   qty_undispatched counts them, and this is the one that earns its keep for a consumable: an
--                    order for 50 with 20 issued still has 30 to load, and that is real work.
--   fulfilment_state a consumables-only order reads 'nothing_dispatched', then 'part_dispatched',
--                    then 'all_returned' when everything has gone. The last word is inherited from
--                    the rentable case and is wrong about consumables in English while being right
--                    about the state: nothing is outstanding and nothing is left to send.
--
-- COUNTING, PER TRACKING MODE (rule 13). A path that assumes unit_id is present lies about cables:
-- it joins nothing, reports zero rather than reporting nothing, and a confident wrong number is
-- the worst kind. So:
--
--   unit               a dispatch is one movement ROW per piece — that is how bulk dispatch writes
--                      them (0007 section 2) — so it is counted, not summed. Same for returns.
--   pool, consumable   the movement's qty, summed, on rows with unit_id null.
--
-- Both figures are computed for every (order, product) and tracking_mode chooses between them,
-- which is 0009's approach and keeps a mis-filed row from being counted on the wrong side.
--
-- Counting ROWS rather than distinct pieces is deliberate. A piece dispatched, returned, and
-- dispatched again on the same order gives dispatched 2 / returned 1 / outstanding 1, which is
-- correct — the box is at the customer. Counting distinct pieces would give 1 and 1 and report it
-- as back, which is rule 2's failure exactly: gear at a customer reading as available.
--
-- AGGREGATE PER (order_id, product_id) FIRST, THEN CLAMP, THEN SUM. 0002 puts no unique constraint
-- on that pair and should not: the same product legitimately appears twice on one order at two
-- agreed rates, which is what happens when four tops are quoted and two are discounted, and rule 5
-- says each line keeps the price it was agreed at. 0009 had to handle this in fn_availability and
-- the same arithmetic applies here, in two places:
--
--   qty_undispatched   per line, an order of 2 + 2 with 2 pieces loaded gives
--                      max(2-2,0) + max(2-2,0) = 0 and the order reads as fully dispatched with
--                      two speakers still in the godown. Per (order, product) it gives
--                      max(4-2,0) = 2, which is the truth. Measured on DJN-2609-0008 in the replay.
--   the clamp itself   clamping only at the order level would let an over-dispatch on one product
--                      cancel out an undispatched quantity on another: 4 speakers untouched and 12
--                      cables sent against 10 ordered would net to 2 rather than reporting the 4
--                      speakers that have not left. Clamping per product reports 4.
--
-- THE KEY SET IS A UNION, not the order lines alone. A dispatch can exist for a product that is on
-- no line — chachu adds a spare top at the van and the paperwork catches up later — and that stock
-- is genuinely out. Taking (order_id, product_id) from the lines only would drop it from
-- qty_dispatched while v_order_outstanding still reported it, and the row would contradict itself.
-- Taking it from movements only would drop every line that has not moved yet, which is most of
-- them. So both, unioned.
--
-- EVERY ORDER GETS A ROW. The outer join starts from rental_order, so an order with no lines and no
-- movements — one just created, the form still open — appears reading all zeros and
-- 'nothing_dispatched' rather than vanishing. A caller doing a plain join would render a missing
-- row as blank, and 0003 and 0008 both set the precedent that a blank is worse than a number.
-- Every quantity column is coalesced and none can be null.
--
-- CANCELLED ORDERS ARE NOT EXCLUDED, and this is not an oversight. 0008 learned it on
-- v_order_outstanding: the old view ended `where o.status not in ('cancelled')`, so cancelling an
-- order emptied the only report that chases gear while v_unit_status still showed the boxes
-- standing in a hall — and 0007's delete guard actively tells the operator to cancel the order.
-- Cancel the order, lose the gear. A cancelled order with stock still out is not a state to hide;
-- it is the state that most needs chasing, because nobody is going to be invoiced into remembering
-- it. order_status is a column and the reader decides. Measured: DJN-2609-0005, cancelled with two
-- LED pars at a customer, reports ordered 2 / dispatched 2 / outstanding 2 and reads 'fully_out'.
--
-- NO DATE IS READ ANYWHERE IN THIS VIEW. Not current_date, not out_date, not
-- expected_return_date. Rule 2: a unit with a dispatch and no matching return is out whatever the
-- date says. Six boxes went out, five came back, and the sixth was quietly offered for hire while
-- it sat in a hall. Nothing here will infer a return from a date passing.
--
-- security_invoker is not optional. A view runs with its OWNER's rights by default; the owner is
-- `postgres`, which carries BYPASSRLS on Supabase, and Supabase separately grants SELECT in
-- `public` to `anon`. Left at the default this view would hand anonymous traffic every order,
-- every customer_id and the whole physical position of the fleet, walking straight past the row
-- level security 0004 puts on rental_order, order_line and movement. It reads v_order_outstanding,
-- which reads v_unit_status, which reads v_unit_location, and all three already carry the setting:
-- the chain is only as tight as its loosest link.
--
-- Dropped before create even though the view is new, matching 0008's handling of v_product_stock.
-- CREATE OR REPLACE VIEW cannot change a column's name, type or order, so a bare replace would
-- refuse a future edit to this file with a message about column types that reads like a bug in
-- Postgres. No CASCADE, deliberately: if something ever does come to depend on this view, the
-- migration should fail loudly here rather than quietly take the dependent object with it.
-- ---------------------------------------------------------------------------

drop view if exists v_order_fulfilment;

create or replace view v_order_fulfilment with (security_invoker = on) as
with line_qty as (
  -- Per (order, product): what was agreed. Summed here, because one order may carry the same
  -- product on two lines at two agreed rates and rule 5 keeps them apart.
  select
    ol.order_id,
    ol.product_id,
    sum(ol.qty)::int as qty_ordered
  from order_line ol
  group by ol.order_id, ol.product_id
),
moved as (
  -- Per (order, product): what has EVER left and what has EVER come back, filed under this order.
  -- Both the piece count and the pooled quantity are computed; tracking_mode picks below.
  -- write_off is deliberately absent: it is not a return, and stock lost at the venue is taken out
  -- of qty_outstanding by v_order_outstanding, which reads the from_kind / to_kind ledger.
  select
    m.order_id,
    m.product_id,
    count(*) filter (where m.movement_type = 'dispatch' and m.unit_id is not null)::int
      as pieces_dispatched,
    coalesce(sum(m.qty) filter (where m.movement_type = 'dispatch' and m.unit_id is null), 0)::int
      as pooled_dispatched,
    count(*) filter (where m.movement_type = 'return' and m.unit_id is not null)::int
      as pieces_returned,
    coalesce(sum(m.qty) filter (where m.movement_type = 'return' and m.unit_id is null), 0)::int
      as pooled_returned
  from movement m
  where m.order_id is not null
    and m.movement_type in ('dispatch', 'return')
  group by m.order_id, m.product_id
),
pairs as (
  -- The union, not the lines alone: a product dispatched but never ordered is still out, and a
  -- product ordered but never dispatched is still owed.
  select order_id, product_id from line_qty
  union
  select order_id, product_id from moved
),
per_product as (
  select
    x.order_id,
    coalesce(lq.qty_ordered, 0) as qty_ordered,
    case p.tracking_mode
      when 'unit' then coalesce(mv.pieces_dispatched, 0)
      else             coalesce(mv.pooled_dispatched, 0)
    end as qty_dispatched,
    case p.tracking_mode
      when 'unit' then coalesce(mv.pieces_returned, 0)
      else             coalesce(mv.pooled_returned, 0)
    end as qty_returned
  from pairs x
  join product p on p.id = x.product_id
  left join line_qty lq on lq.order_id = x.order_id and lq.product_id = x.product_id
  left join moved    mv on mv.order_id = x.order_id and mv.product_id = x.product_id
),
per_order as (
  -- Clamp per product, then sum. Clamping only after summing would let an over-dispatch on one
  -- product hide an undispatched quantity on another.
  select
    pp.order_id,
    sum(pp.qty_ordered)::int                                       as qty_ordered,
    sum(pp.qty_dispatched)::int                                    as qty_dispatched,
    sum(pp.qty_returned)::int                                      as qty_returned,
    sum(greatest(pp.qty_ordered - pp.qty_dispatched, 0))::int      as qty_undispatched
  from per_product pp
  group by pp.order_id
),
at_customer as (
  -- The one place that knows what is still at a customer (rule 13, and 0008's whole argument).
  -- Not re-derived here: this is what fn_order_close_requires_everything_back tests for rule 9,
  -- and a second copy of the arithmetic would eventually disagree with it.
  select
    oo.order_id,
    sum(oo.qty_outstanding)::int as qty_outstanding
  from v_order_outstanding oo
  group by oo.order_id
)
select
  o.id        as order_id,
  o.order_no,
  o.customer_id,
  o.status    as order_status,
  coalesce(po.qty_ordered, 0)      as qty_ordered,
  coalesce(po.qty_dispatched, 0)   as qty_dispatched,
  coalesce(po.qty_returned, 0)     as qty_returned,
  coalesce(ac.qty_outstanding, 0)  as qty_outstanding,
  coalesce(po.qty_undispatched, 0) as qty_undispatched,
  -- THE PRECEDENCE, in the order the branches are written, because an order can satisfy more than
  -- one of them at once and something has to win:
  --
  --   1. nothing_dispatched  qty_dispatched = 0. Nothing has left. Unambiguous, so it goes first,
  --                          and it also catches the order with no lines at all.
  --   2. part_returned       something is still at the customer AND something has come back.
  --   3. part_dispatched     something is still to load.
  --   4. fully_out           everything ordered has gone and none of it is back.
  --   5. all_returned        nothing is at the customer and nothing is left to send.
  --
  -- 2 BEATS 3, and that is the load-bearing choice. An order of 4 with 2 loaded and 1 back is both
  -- partly dispatched and partly returned. The two ways of getting it wrong are not symmetrical:
  --
  --   label it part_dispatched  the operator reads "the van still has to go out" and does not
  --                             notice a box sitting in a hall. That is rule 2's failure — gear at
  --                             a customer, invisible — and nobody complains, so it is found
  --                             months later or never. It is the single most expensive bug this
  --                             project has on record.
  --   label it part_returned    the operator reads "chase the return" and does not notice two more
  --                             boxes still need loading. The customer telephones within hours.
  --                             It is self-correcting, and qty_undispatched is sitting on the same
  --                             row saying 2.
  --
  -- Unreturned gear is the expensive direction and the silent one, so what is still AT the
  -- customer outranks what has not yet left. Note that branch 2 requires qty_returned > 0, not
  -- merely qty_outstanding < qty_dispatched: stock that left the loop by a write-off or a loss did
  -- not come back, and calling that "partly returned" would be a plain lie. Such an order stays on
  -- the dispatch axis until something genuinely returns.
  case
    when coalesce(po.qty_dispatched, 0)   = 0 then 'nothing_dispatched'
    when coalesce(ac.qty_outstanding, 0)  > 0
     and coalesce(po.qty_returned, 0)     > 0 then 'part_returned'
    when coalesce(po.qty_undispatched, 0) > 0 then 'part_dispatched'
    when coalesce(ac.qty_outstanding, 0)  > 0 then 'fully_out'
    else                                           'all_returned'
  end as fulfilment_state
from rental_order o
left join per_order   po on po.order_id = o.id
left join at_customer ac on ac.order_id = o.id;

comment on view v_order_fulfilment is
  'What has physically happened on each order, counted from the movement ledger rather than stored on it (CLAUDE.md rule 10). Replaces the dispatched / partially_returned / returned values that 0002 kept in rental_order.status, which were stored counts and drifted as a current_location column would (rule 1). Read the QUANTITIES; fulfilment_state is a lossy one-dimensional label over a two-dimensional state and is provided for order lists. qty_outstanding is read from v_order_outstanding and never re-derived — it is what rule 9 tests, and it is deliberately NOT qty_dispatched less qty_returned, because pooled stock written off at the customer, a piece marked lost, and a consumable all leave the loop without a return movement. All three tracking modes are counted (rule 13): a unit dispatch is one movement row per piece, a pooled or consumable dispatch is its qty. Quantities are aggregated per (order, product) and clamped there before summing, because one order may carry the same product on two lines. Cancelled orders are NOT excluded and report honestly, for the reason 0008 gives on v_order_outstanding. No date is read anywhere (rule 2).';


-- ===========================================================================
-- 3 · Every reader of rental_order.status, audited.
-- ===========================================================================
--
-- Found by searching the live catalog — pg_proc.prosrc, pg_get_viewdef, pg_get_constraintdef,
-- pg_get_triggerdef, pg_get_indexdef, pg_policy — not by grepping this repo from memory, and then
-- cross-checked against the repo and against web/ (which is empty). Every hit is listed, including
-- the ones that needed no change, because "I checked and it was fine" is only useful if the next
-- reader can see what was checked.
--
-- CHANGED
--
--   rental_order_status_check (0002)   replaced in section 1. The only DDL change to an existing
--                                      object in this file.
--
-- DELIBERATELY NOT CHANGED, with the reason in each case
--
--   fn_availability (0009)
--     The `committed` calculation filters `where o.status not in ('cancelled','closed')`. Under the
--     narrowed set that leaves exactly 'confirmed', so behaviour is identical today — verified on
--     the replay, where the 0009 acceptance case (6 owned, 4 ordered, 2 dispatched) still answers
--     4 / 2 / 2 before and after this migration.
--
--     It is NOT rewritten to `= 'confirmed'`, and the temptation should be resisted permanently.
--     The exclusion list encodes the rule — an order commits its undispatched remainder UNLESS it
--     is cancelled or closed — and CLAUDE.md's conventions say the operator wants to add and remove
--     status values himself, which is the reason this schema uses text and CHECK rather than an
--     enum. Add 'on_hold' next year against an equality test and every order in that state
--     silently commits nothing, so stock already promised is offered to somebody else. That is the
--     expensive direction and the same shape as the bug 0009 section 1 was written to remove. The
--     exclusion list fails safe under exactly the change this schema is designed to permit;
--     `= 'confirmed'` fails dangerous. Shorter is not clearer here.
--
--   fn_order_line_delete_is_draft_only (0009)
--   fn_order_charge_delete_is_draft_only (0009)
--     Both begin `if v_status is distinct from 'confirmed' then raise`, then check that nothing has
--     been dispatched, then check that no charge has been posted.
--
--     THE STATUS HALF IS NOT REDUNDANT and is not being dropped. It still refuses a delete on a
--     'closed' or a 'cancelled' order, and neither of those necessarily has any movement against
--     it — a job cancelled before the van ever loaded has none at all, so the movement half would
--     pass it. Without the status test, the lines of a cancelled order would become deletable,
--     which is rule 12 straight through the side door.
--
--     What DID change is how much of the work it does. Before narrowing, an order the operator had
--     flipped to 'dispatched' was refused on the status test alone. Now it reads 'confirmed' and
--     the movement test does the refusing. Verified on the replay, both directions: a line on an
--     order with dispatch movements against that product is still REFUSED, and a line on a
--     genuinely untouched confirmed order with no movements and no posted charge is still ALLOWED.
--
--     One behaviour genuinely changes, and it is a fix rather than a regression. The order_line
--     movement test is scoped to the product, and 0009's own comment says why: "removing the cable
--     line from an order whose speakers have already gone is still allowed — that line has
--     genuinely not moved." The old status test blocked that the moment the dropdown was flipped,
--     so 0009's stated intent was unreachable in practice. It is reachable now. The money is still
--     guarded by fn_order_net_posted_charge, and a line that produced no movement is a draft, not
--     history. order_charge is unaffected: a charge is job-level, so ANY movement on the order
--     closes its window, and that test never depended on the status.
--
--     NOTE FOR THE NEXT READER: 0009's comment block says "the moment the order leaves 'confirmed'
--     — dispatched, partially_returned, returned, closed, cancelled". Three of those five no longer
--     exist. 0009 is applied and frozen and is not edited (that is the convention, and editing it
--     would put the file out of step with what was applied); the sentence should now be read as
--     "closed or cancelled", with the dispatch half of the guard doing the work the other three
--     used to do.
--
--   fn_order_close_requires_everything_back (0009), and its trigger
--     Reads 'closed', which survives narrowing untouched, and tests v_order_outstanding rather than
--     any status. Rule 9 is unaffected. Verified on the replay after this migration: an order with
--     gear still at the customer is refused with the pieces named, and an order whose stock has all
--     come back closes cleanly. The trigger's WHEN clause is also what makes section 1's bulk
--     UPDATE inert — see the argument there.
--
--   v_order_outstanding (0008)
--     Carries `o.status as order_status` as a passthrough and filters on nothing. It reads the
--     column live, so it cannot hold a stale value; the domain simply shrinks from six to three.
--     Its deliberate inclusion of cancelled orders is unchanged and is inherited by
--     v_order_fulfilment above.
--
--   v_product_roi (0003)
--     Filters `where o.status <> 'cancelled'`. The set of orders it includes is IDENTICAL before
--     and after: everything that is not cancelled. The three retired values were all inside that
--     set and all map to 'confirmed', which is also inside it. status is NOT NULL, so there is no
--     three-valued-logic hole in the `<>`. Revenue figures are unchanged, which matters because
--     rule 5 says line_total is a historical fact and this migration must not move a single rupee.
--
--   fn_rental_order_is_never_deleted (0007)
--     Names 'cancelled' in its error message as the escape hatch. Still the correct advice, and
--     more so now that it is one of only three values. No change.
--
--   idx_order_status (0002)
--     A plain btree on rental_order(status). Still valid; its cardinality drops from six to three.
--     Meaningless at zero rows either way.
--
-- SEARCHED AND FOUND NOT TO BE READERS AT ALL
--
--   v_unit_status, v_product_stock
--     Both matched a search for `status` and neither has anything to do with rental_order.status.
--     v_unit_status.status is the DERIVED position of a numbered piece — out, available, at_repair,
--     lost, retired, not_recorded — and v_product_stock reads it. This is rule 3: condition and
--     status are separate axes, and unit position and order state are separate again. Recorded here
--     because the next person to grep for "status" will hit them and should not spend an afternoon
--     on it.
--
--   RLS policies, grants, generated columns, other constraints
--     None reference the column. The only policy on rental_order is 0004's operator_all, which is
--     `using (true) with check (true)`.
--
--   Anything outside the database
--     web/ is empty — there is no frontend yet. docs/ describes order states in prose but hard-codes
--     none of the six values. The three retired literals appear nowhere in this repo except inside
--     migration files 0002 and 0009, both of which are applied and frozen and are discussed above.
-- ---------------------------------------------------------------------------
