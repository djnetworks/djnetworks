-- 0008_pool_stock.sql
-- What pooled stock is. One concept, in one place, read by everything else.
--
-- `unit` was built first and `pool` was bolted on beside it, so almost every derived object in
-- 0003 and 0007 begins by joining v_unit_status. A pooled product owns no unit rows, so those
-- joins match nothing and the view reports ZERO — not "no answer", but a confident 0 sitting next
-- to a product the operator can see two hundred of on the shelf. That is CLAUDE.md rule 13, and
-- it had four faces at once. They were never four bugs; they were one design decision showing
-- through in four places, which is why they are fixed in one file rather than four.
--
-- Measured on a replay of 0001-0007 with data anchored to 2026-09-05, before this migration:
--
--   CBL-XLR   pool, 200 owned, 40 out, 25 back, 15 written off at the venue
--             v_product_stock said units_on_hand = 0.  fn_availability said 185.
--             Two screens, two numbers, and nothing anywhere recording that 15 are gone.
--   CBL-SIL   pool, 100 owned, then intake 50, write_off 20, repair_out 10
--             fn_availability said 100 after all three. Every one of those movements was
--             accepted by the 0007 trigger and then discarded by the 0007 arithmetic, which
--             matched only ('dispatch','return'). The operator records a write-off, sees no
--             change, and cannot tell which of the two numbers he is supposed to edit.
--   CBL-FAT   pool, 200 owned, 40 out, a fat-fingered return of 60
--             fn_availability said 220 available out of a fleet of 200.
--   STND-T    pool, pool_qty never entered, one stray return of 8
--             fn_availability said 8 stands that were never bought.
--   FOG-5L    consumable, 60 in stock: issue 20 -> 40. Return 5 unopened -> still 40. Intake 60
--             -> still 40. Issue 55 -> -15, permanently, with no movement that could correct it.
--   DJN-2609-0003 cancelled with a speaker still at the customer: v_unit_status showed the box
--             at the customer, v_order_outstanding_units showed nothing, because it ended
--             `where o.status not in ('cancelled')`.
--
-- Rule 10 is untouched: nothing here is stored. Every figure below is counted on read from the
-- movement ledger, and the ledger is still append-only. Rule 12 is untouched: this file adds no
-- delete path. Rule 2 is untouched and is the reason the on-hand arithmetic reads no date at all
-- — not current_date, not out_date, not expected_return_date. A dispatch that has not been
-- returned is out because no return movement exists, never because a date has or has not passed.

-- ===========================================================================
-- 1 · v_pool_stock — the one place that knows what pooled stock is.
-- ===========================================================================
--
-- THE MODEL, AND WHY THIS ONE.
--
-- The specification given was "pool_qty less net quantity out (dispatch minus return minus
-- write_off)". Taken literally it is wrong, and the owner has been told so:
--
--     pool_qty 200, dispatch 40, return 25, write_off 15
--     net_out  = 40 - 25 - 15 = 0
--     on_hand  = 200 - 0      = 200      <- but only 185 cables still exist
--
-- Subtracting a write-off from "out" alone leaves the lost stock as phantom on-hand. A write-off
-- has to come off BOTH what is owned and what is out, because both of those things stopped being
-- true when the cable was left at the venue.
--
-- Two ways to fix it were on the table.
--
--   (a) Full ledger arithmetic keyed on from_kind / to_kind rather than on movement_type.
--       Stock at our own locations is everything that arrived at a location minus everything that
--       left one, with product.pool_qty as the opening balance. Every movement type is handled by
--       the same three sums, including the ones nobody has thought of yet.
--
--   (b) Keep product.pool_qty authoritative for what is owned and use the ledger only for what is
--       out — and then make the 0007 trigger REFUSE intake, write_off, found, repair_out and
--       repair_in on pooled products, so the operator gets an error instead of silence.
--
-- (a) is implemented. (b) keeps one number simple at the cost of forbidding five legitimate
-- physical events, and the operator would then have to record a lost cable by hand-editing
-- product.pool_qty — a stored count, edited by a human, which is precisely what rule 10 exists to
-- prevent and precisely the field that rots. It also cannot express "10 cables are at the repair
-- shop", because there would be nowhere for them to be.
--
-- The rule either way: no movement type may be accepted by the schema and then silently discarded
-- by the arithmetic. Under (a) none is, and that is checkable by reading the three sums.
--
-- WHICH MOVEMENTS AFFECT WHICH COLUMN. Nothing here reads movement_type except qty_written_off,
-- which is informational; the arithmetic reads only the two kinds.
--
--   movement_type  usual shape             qty_in  qty_out  at_customer  at_vendor  qty_owned
--   -------------  ----------------------  ------  -------  -----------  ---------  ---------
--   intake         none     -> location      +        .          .           .          +
--   found          none     -> location      +        .          .           .          +
--   dispatch       location -> customer      .        +          +           .          =
--   return         customer -> location      +        .          -           .          =
--   transfer       location -> location      +        +          .           .          =
--   repair_out     location -> vendor        .        +          .           +          =
--   repair_in      vendor   -> location      +        .          .           -          =
--   write_off      location -> none          .        +          .           .          -
--   write_off      customer -> none          .        .          -           .          -
--   write_off      vendor   -> none          .        .          .           -          -
--
-- The invariant that makes this readable: ownership changes ONLY when one end of the movement is
-- `none`. Everything with a real place at both ends moves stock between positions and leaves
-- qty_owned alone. A transfer touches qty_in and qty_out by the same amount and nets to zero, so
-- shuffling cables from the godown to the van cannot change availability — which is the correct
-- answer and was also the correct answer before, by accident, because transfers were ignored.
--
-- WHAT THIS COSTS, STATED PLAINLY.
--
--   pool_qty is now an OPENING BALANCE, not the current truth. It is what was counted on the shelf
--   when the product was set up, or what came in through the bulk Google Sheet import. After that,
--   changes are movements. Do NOT edit pool_qty to record a purchase or a loss: the ledger already
--   has it and the two would be added together. This is the one number on the product form whose
--   meaning changed today, and it is why the column below is called qty_opening rather than
--   qty_pool — a column named qty_pool sitting beside qty_on_hand invites the operator to correct
--   the wrong one, which is the exact confusion this migration was written to end.
--
--   The arithmetic now depends on from_kind / to_kind being recorded correctly, where before it
--   depended on movement_type. That is two fields instead of one, and nothing in the schema
--   enforces that a dispatch actually reads location -> customer. The dispatch, return and
--   transfer screens must set both ends; they are not free-text fields the operator fills in. A
--   dispatch recorded with to_kind = 'none' reads as stock that left our shelf and went nowhere —
--   shrinkage, not a hire — and has_ledger_error does NOT catch it, because nothing arithmetically
--   impossible has happened; measured on a replay, a 12-cable dispatch written that way takes
--   on_hand and qty_owned from 185 to 173, leaves qty_at_customer at 0 and produces no
--   v_order_outstanding row. Left as a known dependency rather than fixed here: a trigger tying
--   movement_type to the legal kind pairs is a real change to what the ledger accepts and belongs
--   in its own migration with the owner's agreement.
--
--   `vendor` in this ledger means somebody else's premises holding OUR stock — a repair shop
--   (rule 7). A purchase from a supplier is an intake from 'none', because the cable was not ours
--   before it arrived. Recording a purchase as vendor -> location would drive qty_at_vendor
--   negative; has_ledger_error will say so rather than the number quietly being wrong.
--
-- THE CLAMP, AND WHY THE RAW FIGURE SURVIVES BESIDE IT.
--
-- Two real data-entry errors inflate stock above the fleet. A return of 60 against a dispatch of
-- 40 gave 220 out of 200. A stray return of 8 on a product with no pool_qty gave 8 stands that
-- were never bought. So qty_on_hand is clamped: never below zero, never above qty_owned. But a
-- clamp that hides the error is only half a fix — the operator would see a plausible 200 and never
-- learn that his return was wrong. So qty_on_hand_raw carries the unclamped signed figure,
-- qty_at_customer and qty_at_vendor are allowed to go negative, and has_ledger_error is true
-- whenever any of those three says something physically impossible. The clamp protects the
-- promise made to a customer; the raw columns protect the operator from himself.
--
-- Note what makes the clamp work: qty_owned is derived from the same raw figures, so a phantom
-- return of 8 adds 8 to on-hand AND subtracts 8 from at-customer, leaving qty_owned = 0 and
-- clamping on-hand to 0. The error cancels itself out of the number that gets quoted.
--
-- WHY CONSUMABLES ARE IN HERE TOO. Rule 13 says pooled quantities are read from v_pool_stock and
-- never re-derived. Fog fluid and tape are counted stock with no numbered pieces, exactly like
-- cables; the only difference is that what leaves for a customer is not coming back. That is a
-- difference in how the columns are READ, not in how they are computed, so one view serves both
-- and the per-mode reading is documented on v_product_stock below. Two views would be two
-- arithmetics, and this migration exists because there were four.
--
-- WHY UNIT PRODUCTS ARE NOT IN HERE. A numbered box already has a per-piece answer in
-- v_unit_status. Summing its movements into a second quantity would create exactly the parallel
-- truth this file is removing. v_pool_stock returns no row at all for a unit-tracked product, and
-- callers must fall back to the unit views rather than reading a zero.
-- ---------------------------------------------------------------------------
-- security_invoker is not optional, on this view or any other in this file. A view runs with its
-- OWNER's rights by default; the owner is `postgres`, which carries BYPASSRLS on Supabase, and
-- Supabase separately grants SELECT in `public` to `anon`. Left at the default, this view hands
-- anonymous traffic the entire fleet and walks straight past the row level security 0004 puts on
-- product and movement. The chain matters too: v_product_stock and v_order_outstanding below read
-- this view, and a chain is only as tight as its loosest link.
-- ---------------------------------------------------------------------------

create or replace view v_pool_stock with (security_invoker = on) as
with pooled_movement as (
  -- The pooled side of the ledger. `unit_id is null` is what makes it the pooled side: since 0007
  -- a pooled product cannot have a movement naming a unit, but history is never rewritten
  -- (rule 12), so the filter stays and any pre-0007 row is excluded rather than double-counted.
  select m.product_id, m.movement_type, m.qty, m.from_kind, m.to_kind
  from movement m
  join product p on p.id = m.product_id
  where p.tracking_mode in ('pool','consumable')
    and m.unit_id is null
),
ledger as (
  select
    pm.product_id,
    coalesce(sum(pm.qty) filter (where pm.to_kind   = 'location'), 0)::int as qty_in,
    coalesce(sum(pm.qty) filter (where pm.from_kind = 'location'), 0)::int as qty_out,
    coalesce(sum(pm.qty) filter (where pm.to_kind   = 'customer'), 0)::int
      - coalesce(sum(pm.qty) filter (where pm.from_kind = 'customer'), 0)::int as qty_at_customer,
    coalesce(sum(pm.qty) filter (where pm.to_kind   = 'vendor'), 0)::int
      - coalesce(sum(pm.qty) filter (where pm.from_kind = 'vendor'), 0)::int as qty_at_vendor,
    -- Informational only. Write-offs are already inside the three sums above, on whichever side
    -- the stock was standing when it was written off — do not subtract this column again.
    coalesce(sum(pm.qty) filter (where pm.movement_type = 'write_off'), 0)::int as qty_written_off
  from pooled_movement pm
  group by pm.product_id
),
figures as (
  -- Left join, so a pooled product with no movements at all still returns a row reading
  -- qty_opening = pool_qty and everything else zero, rather than vanishing from the view and
  -- being rendered as a blank by a caller doing a plain join.
  select
    p.id            as product_id,
    p.short_code,
    p.model_name,
    p.tracking_mode,
    coalesce(p.pool_qty, 0)::int   as qty_opening,
    coalesce(l.qty_in, 0)          as qty_in,
    coalesce(l.qty_out, 0)         as qty_out,
    coalesce(l.qty_at_customer, 0) as qty_at_customer,
    coalesce(l.qty_at_vendor, 0)   as qty_at_vendor,
    coalesce(l.qty_written_off, 0) as qty_written_off
  from product p
  left join ledger l on l.product_id = p.id
  where p.tracking_mode in ('pool','consumable')
),
positions as (
  select
    f.*,
    (f.qty_opening + f.qty_in - f.qty_out) as qty_on_hand_raw,
    greatest(
      (f.qty_opening + f.qty_in - f.qty_out) + f.qty_at_customer + f.qty_at_vendor,
      0
    ) as qty_owned
  from figures f
)
select
  pos.product_id,
  pos.short_code,
  pos.model_name,
  pos.tracking_mode,
  pos.qty_opening,                                    -- product.pool_qty: the opening count
  pos.qty_in,                                         -- everything that arrived at a location
  pos.qty_out,                                        -- everything that left a location
  pos.qty_on_hand_raw,                                -- signed, unclamped: shows data-entry error
  least(greatest(pos.qty_on_hand_raw, 0), pos.qty_owned) as qty_on_hand,
  pos.qty_at_customer,                                -- signed: negative means more back than out
  pos.qty_at_vendor,                                  -- signed: negative means a purchase logged
                                                      -- as vendor -> location
  pos.qty_written_off,                                -- informational, already in the sums above
  pos.qty_owned,                                      -- on hand + at customer + at repair
  (    pos.qty_on_hand_raw < 0
    or pos.qty_on_hand_raw > pos.qty_owned
    or pos.qty_at_customer < 0
    or pos.qty_at_vendor   < 0 ) as has_ledger_error
from positions pos;

comment on view v_pool_stock is
  'The single source of truth for pooled and consumable quantities (CLAUDE.md rule 13 — never re-derive these anywhere else). Ledger arithmetic keyed on movement.from_kind / to_kind, with product.pool_qty as an OPENING BALANCE: after setup, stock changes are movements, not edits to pool_qty. qty_on_hand is clamped to [0, qty_owned] because a mistyped return once put 220 cables on a fleet of 200; qty_on_hand_raw keeps the unclamped figure and has_ledger_error flags the row, so the clamp never hides the mistake. Returns no row for unit-tracked products by design.';

-- ===========================================================================
-- 2 · v_product_stock — one row per product, real numbers in all three modes.
-- ===========================================================================
--
-- Before this migration every pooled and consumable product reported 0 in every column, while
-- fn_availability reported a real quantity for the same product. Two screens, two numbers, and
-- the operator with no way to tell which one to believe. Nothing reads this view yet, so the
-- column NAMES are kept exactly as 0003 wrote them — renaming buys nothing and costs a diff —
-- but what they MEAN now depends on the tracking mode, and they do not mean the same thing for a
-- cable as for a speaker:
--
--   column           unit                      pool                        consumable
--   ---------------  ------------------------  --------------------------  -----------------------
--   units_active     pieces not retired/lost   qty_owned: on hand + out    qty_on_hand: consumed
--                                              + at repair, all still ours stock is not an asset
--   units_on_hand    pieces at our locations   qty_on_hand (clamped)       qty_on_hand (clamped)
--   units_out        pieces at a customer      qty_at_customer, expected   qty_at_customer: issued
--                                              back                        and gone, cumulative
--   units_at_repair  pieces at a vendor        qty_at_vendor               qty_at_vendor (rarely
--                                                                          anything but zero)
--   units_lost       lifecycle = 'lost'        qty_written_off             qty_written_off
--   units_retired    lifecycle = 'retired'     0 — no pieces to retire     0 — same
--
-- units_active for a consumable is deliberately NOT qty_owned. A litre of fog fluid that went to a
-- wedding is not an asset waiting to come back, and reporting it as active stock would overstate
-- the store cupboard by everything ever sold. For a cable it is the opposite: a cable at a
-- customer is still ours and still on the books, so pool keeps qty_owned.
--
-- units_on_hand is clamped and units_out is not, and that asymmetry is deliberate. units_on_hand
-- is what a quote is made against, and a promise must never be made on stock that does not exist.
-- units_out is read to decide who to telephone; a negative there is a visible data-entry error and
-- is more useful than a tidy zero. When it looks wrong, v_pool_stock has the full arithmetic and
-- has_ledger_error.
--
-- A tracking mode this view does not recognise reads NULL, not 0. Rule 13's whole point is that a
-- confident wrong number is worse than a blank, and 0003 already set this precedent by returning a
-- NULL roi_pct rather than a zero. (fn_availability keeps its separate never-null contract from
-- 0007 — a caller doing arithmetic on the result needs a number, and 'missing' there means the
-- product does not exist at all.)
--
-- If a product's tracking_mode is ever changed after its pieces already have histories, this view
-- reports it by its CURRENT mode. The piece history is not lost — it stays in v_unit_status, where
-- it was written (rule 12).
--
-- Dropped and recreated rather than replaced: the count() columns were bigint in 0003 and are int
-- here, and CREATE OR REPLACE VIEW cannot change a column's type. No CASCADE, deliberately — if
-- something ever does come to depend on this view, the migration should fail loudly here rather
-- than quietly take the dependent object with it.
-- ---------------------------------------------------------------------------

drop view if exists v_product_stock;

create or replace view v_product_stock with (security_invoker = on) as
with unit_counts as (
  select
    u.product_id,
    count(*) filter (where u.lifecycle = 'active')  ::int as units_active,
    count(*) filter (where s.status = 'available')  ::int as units_on_hand,
    count(*) filter (where s.status = 'out')        ::int as units_out,
    count(*) filter (where s.status = 'at_repair')  ::int as units_at_repair,
    count(*) filter (where u.lifecycle = 'lost')    ::int as units_lost,
    count(*) filter (where u.lifecycle = 'retired') ::int as units_retired
  from unit u
  left join v_unit_status s on s.unit_id = u.id
  group by u.product_id
)
select
  p.id as product_id,
  p.short_code,
  p.model_name,
  p.tracking_mode,
  case p.tracking_mode
    when 'unit'       then coalesce(uc.units_active, 0)
    when 'pool'       then coalesce(ps.qty_owned, 0)
    when 'consumable' then coalesce(ps.qty_on_hand, 0)
  end as units_active,
  case p.tracking_mode
    when 'unit'       then coalesce(uc.units_on_hand, 0)
    when 'pool'       then coalesce(ps.qty_on_hand, 0)
    when 'consumable' then coalesce(ps.qty_on_hand, 0)
  end as units_on_hand,
  case p.tracking_mode
    when 'unit'       then coalesce(uc.units_out, 0)
    when 'pool'       then coalesce(ps.qty_at_customer, 0)
    when 'consumable' then coalesce(ps.qty_at_customer, 0)
  end as units_out,
  case p.tracking_mode
    when 'unit'       then coalesce(uc.units_at_repair, 0)
    when 'pool'       then coalesce(ps.qty_at_vendor, 0)
    when 'consumable' then coalesce(ps.qty_at_vendor, 0)
  end as units_at_repair,
  case p.tracking_mode
    when 'unit'       then coalesce(uc.units_lost, 0)
    when 'pool'       then coalesce(ps.qty_written_off, 0)
    when 'consumable' then coalesce(ps.qty_written_off, 0)
  end as units_lost,
  case p.tracking_mode
    when 'unit'       then coalesce(uc.units_retired, 0)
    when 'pool'       then 0
    when 'consumable' then 0
  end as units_retired
from product p
left join unit_counts uc on uc.product_id = p.id
left join v_pool_stock ps on ps.product_id = p.id;

comment on view v_product_stock is
  'Physical stock per product in all three tracking modes (CLAUDE.md rule 13). Pooled and consumable figures are read from v_pool_stock, never re-derived. The columns keep their 0003 names but mean different things per mode — units_active is qty_owned for a pool and qty_on_hand for a consumable, because issued fog fluid is not an asset; units_out is a cumulative issued-and-gone total for a consumable, not something coming back. See the comment block above the definition in 0008.';

-- ===========================================================================
-- 3 · v_order_outstanding — what is still at the customer, pieces AND quantities.
-- ===========================================================================
--
-- v_order_outstanding_units could not be repaired in place because its shape was the bug. It
-- returned one row per numbered piece, and a pooled item is a quantity, not a piece; there was no
-- row shape in which "15 XLR cables are still at the venue" could be written down. So the report
-- that answers "who has my gear" was silently blind to every cable, stand and mic accessory in
-- the fleet, and rule 9 — an order cannot close while a unit is outstanding — could only ever see
-- half of what was outstanding.
--
-- Dropped and recreated under a new name. Verified before writing this: pg_depend through
-- pg_rewrite returns zero dependent objects, and nothing in the repo reads it. The name loses the
-- word "units" because that word was the false assumption.
--
-- The shape, as specified: order_id, product_id, unit_id (NULL for pooled), qty_outstanding.
-- A unit row carries a unit_id and qty_outstanding = 1. A pooled row carries unit_id = NULL and a
-- real quantity. Rule 13 in one view: no consumer of this view may assume unit_id is present.
--
-- CANCELLED ORDERS ARE NOT EXCLUDED, and this is a change of behaviour. The old view ended
-- `where o.status not in ('cancelled')`, so cancelling an order emptied this report while
-- v_unit_status still showed the boxes standing at a customer — and 0007's delete guard actively
-- tells the operator to cancel the order when he tries to delete one. Cancel the order, lose the
-- gear from the only report that chases it. Cancelled-with-gear-still-out is not a state to hide;
-- it is the state that most needs chasing, because nobody is going to be invoiced into
-- remembering it. order_status is carried as a column so the reader decides: a close-the-order
-- screen filters it out, a what-is-out-there screen does not.
--
-- Consumables never appear here, in any state. Fog fluid was sold, not lent; there is nothing
-- outstanding to chase and nothing that could ever be returned to clear it. Including them would
-- park 55 litres in the report forever and, under rule 9, make the order impossible to close —
-- the same permanent-outstanding failure as the lost cable in section 4, arriving from the other
-- direction.
--
-- days_overdue is reported and never acted upon. Nothing in this view filters on a date, and rule
-- 2 is why: a dispatch is outstanding because no return movement exists, not because a date has
-- not passed and not because one has. Six boxes went out, five came back, and the sixth was
-- offered for hire while it sat in a hall.
-- ---------------------------------------------------------------------------

drop view if exists v_order_outstanding_units;
drop view if exists v_order_outstanding;

create or replace view v_order_outstanding with (security_invoker = on) as
with unit_rows as (
  -- Unchanged in substance from 0003: a piece whose last movement left it at a customer, filed
  -- under the order that movement carried.
  select
    s.last_order_id  as order_id,
    s.product_id,
    s.unit_id,
    s.piece_no,
    1::int           as qty_outstanding,
    s.last_moved_on  as dispatched_on
  from v_unit_status s
  where s.status = 'out'
    and s.last_order_id is not null
),
pool_rows as (
  -- Per order and product: what this order still has standing at the customer. Keyed on the same
  -- kinds as v_pool_stock, so a write-off recorded AT the customer clears the order here for
  -- exactly the reason it reduces qty_owned there — one arithmetic, two readings.
  select
    m.order_id,
    m.product_id,
    null::uuid as unit_id,
    null::int  as piece_no,
    ( coalesce(sum(m.qty) filter (where m.to_kind   = 'customer'), 0)
    - coalesce(sum(m.qty) filter (where m.from_kind = 'customer'), 0) )::int as qty_outstanding,
    min(m.moved_on) filter (where m.to_kind = 'customer') as dispatched_on
  from movement m
  join product p on p.id = m.product_id
  where p.tracking_mode = 'pool'
    and m.unit_id is null
    and m.order_id is not null
  group by m.order_id, m.product_id
  having ( coalesce(sum(m.qty) filter (where m.to_kind   = 'customer'), 0)
         - coalesce(sum(m.qty) filter (where m.from_kind = 'customer'), 0) ) > 0
)
select
  o.id       as order_id,
  o.order_no,
  o.status   as order_status,
  o.customer_id,
  o.out_date,
  o.expected_return_date,
  x.product_id,
  p.short_code,
  p.model_name,
  p.tracking_mode,
  x.unit_id,
  x.piece_no,
  x.qty_outstanding,
  x.dispatched_on,
  greatest(current_date - o.expected_return_date, 0) as days_overdue
from ( select * from unit_rows
       union all
       select * from pool_rows ) x
join rental_order o on o.id = x.order_id
join product p      on p.id = x.product_id;

comment on view v_order_outstanding is
  'What each order still has at the customer, as pieces AND as quantities (CLAUDE.md rule 13 — unit_id is NULL on a pooled row and no caller may assume it is present). Replaces v_order_outstanding_units. Cancelled orders are NOT excluded: order_status is a column and the reader decides, because cancelling an order used to empty this report while the gear was still in a hall. Consumables never appear — they were sold, not lent. days_overdue is displayed, never acted on: outstanding means no return movement exists, not that a date passed (rule 2).';

-- ===========================================================================
-- 4 · The shrinkage path: a cable that never comes back.
-- ===========================================================================
--
-- This section adds no DDL. The path is the `write_off` movement, which 0002 has always accepted,
-- and sections 1 and 3 are what finally make it mean something. It is written down here because
-- the operator needs to know which row to enter, and because "it works now" is not a claim anyone
-- should have to take on trust.
--
-- Cables lost at a venue never come back. Before today there was nothing to record: net-out stayed
-- elevated forever, the report showed 15 cables sitting at a customer permanently, and under rule
-- 9 that order could never be closed. The fix is one movement:
--
--     movement_type = 'write_off'
--     from_kind     = 'customer'   from_id = the customer     <- NOT from a location
--     to_kind       = 'none'
--     qty           = 15
--     order_id      = the order the cables went out on
--
-- from_kind matters more than movement_type here. The cables left the godown at dispatch and never
-- came back to it, so nothing about our shelf changes — writing them off FROM a location would
-- deduct them from the godown a second time, and the godown would end up 15 short of what is
-- actually standing in it. Written off from the customer, the loop closes exactly:
--
--   pool_qty 200, dispatch 40, return 25, then write_off 15 at the venue
--
--                          before the write-off      after the write-off
--     qty_opening                       200                      200
--     qty_in                             25                       25
--     qty_out                            40                       40
--     qty_on_hand_raw                   185                      185
--     qty_on_hand                       185                      185   <- the shelf is unchanged
--     qty_at_customer                    15                        0   <- nobody to telephone
--     qty_written_off                     0                       15
--     qty_owned                         200                      185   <- the fleet is smaller
--     v_order_outstanding                15                  no row    <- the order can close
--
-- The owner's example asked for on_hand 200 -> 185 and owned 185. Both are here; the 15 came off
-- on_hand at DISPATCH, which is when it physically left, and off owned at the WRITE-OFF, which is
-- when it stopped being ours. Under 0007 the write-off changed nothing at all — the arithmetic
-- matched only ('dispatch','return') — so the operator saw the same 185 before and after and had
-- no way to tell whether the system had understood him.
--
-- Cables binned in the godown are the other case and are recorded from_kind = 'location',
-- to_kind = 'none': they come off the shelf and off the fleet at the same moment.
--
-- Nothing about a write-off deletes anything (rule 12). The dispatch and the return stay exactly
-- as written; a third row says what happened next.
--
-- For a numbered box the equivalent path is unchanged and untouched: set unit.lifecycle = 'lost',
-- which takes it out of v_unit_status.status = 'out' and therefore out of v_order_outstanding.
-- Rule 4 still holds — its piece number dies with it and is never reissued.

-- ===========================================================================
-- 5 · fn_availability — pooled on-hand from v_pool_stock, and the end of the
--     consumable double-promise.
-- ===========================================================================
--
-- Three changes, and one deliberate non-change.
--
-- pool: on-hand now comes from v_pool_stock.qty_on_hand instead of being computed here. It is the
--   same number the stock screen shows, because it is literally the same expression, evaluated
--   once (rule 13). The old inline `pool_qty - (dispatch - return)` is gone, and with it the four
--   silently-discarded movement types and the unbounded 220-out-of-200.
--
-- consumable, on-hand: also v_pool_stock.qty_on_hand. 0007 counted every dispatch ever and nothing
--   else, so the only thing that could ever increase stock was hand-editing product.pool_qty.
--   Measured before this change: 60 in stock, issue 20 -> 40, return 5 unopened -> still 40,
--   intake 60 -> still 40, issue 55 more -> -15 forever, with no movement the operator could
--   record to correct it. Now intake, return, found and write_off all net in, and the only route
--   to a negative number is genuine over-commitment.
--
-- consumable, committed: was hard-coded to 0, which meant the same 50 bottles could be promised to
--   two customers three weeks apart and nothing objected. 0007 wrote that tension down and left
--   the fix to a migration with the owner's agreement; this is that migration. A consumable is
--   committed on the way OUT, not held over a window — there is nothing to hold, because nothing
--   comes back — so there is no overlap predicate here and p_from / p_to are not consulted in this
--   branch at all. The test is `o.status = 'confirmed' and o.out_date >= current_date`: still
--   agreed, not yet gone. Once it is dispatched the stock is physically gone and is already absent
--   from on-hand; counting it in both places would halve the store cupboard on paper.
--   p_exclude_order_id is honoured exactly as the other branches honour it, so the order being
--   edited does not count against itself.
--
-- unit: NOT CHANGED. The CTE below is the 0007 text, unaltered, down to the rows it counts.
--   on_hand is the number of pieces whose LAST movement put them at one of our own locations, so
--   a box at a repair shop leaves availability with no extra rule, and expected_return_date is
--   not consulted and never will be (rule 2). Verified by replaying 0001-0007 and 0001-0008 side
--   by side against identical data and diffing the results for every unit product over a grid of
--   date windows: byte-identical.
--
-- Unchanged and still true: `available` is deliberately not clamped. Over-commitment is a real
-- state and the operator needs to see how far over he is, not a zero that reads like "just sold
-- out". Every column is still non-null in every mode — each CTE is an unfiltered aggregate or a
-- coalesced scalar subquery with no GROUP BY, so each returns exactly one row even for a
-- product_id that does not exist, which is what makes the cross join answer (id, 0, 0, 0) rather
-- than no row at all. The signature and the four output columns are unchanged, so CREATE OR
-- REPLACE is enough and existing grants survive untouched — nothing about the privilege set
-- changes here, so there is no revoke/grant pair to order correctly.
--
-- The SET search_path stops the planner inlining this function into a calling query and, more to
-- the point, is not optional on anything reachable through PostgREST. pg_temp goes last so a
-- temporary object can never shadow a real one.
-- ---------------------------------------------------------------------------

create or replace function fn_availability(
  p_product_id uuid,
  p_from       date,
  p_to         date,
  p_exclude_order_id uuid default null
)
returns table (
  product_id       uuid,
  units_on_hand    int,
  committed        int,
  available        int
)
language sql
stable
set search_path = public, pg_temp
as $$
  with prod as (
    -- Exactly one row, always, including for a product_id that does not exist — the subquery
    -- returns NULL and the coalesce turns that into 'missing', which falls to the zero branch
    -- below. 'missing' is a sentinel here and is never a value of tracking_mode.
    select coalesce(
             (select p.tracking_mode from product p where p.id = p_product_id),
             'missing'
           ) as track_mode
  ),
  unit_on_hand as (
    -- Numbered pieces physically at one of our own locations. Nothing here reads a date.
    select count(*)::int as n
    from v_unit_status s
    where s.product_id = p_product_id
      and s.status = 'available'
  ),
  pool_on_hand as (
    -- Pooled and consumable stock, read from the one place that knows (rule 13). Never
    -- re-derived here: two copies of this arithmetic is the bug 0008 was written to remove.
    -- v_pool_stock has no row for a unit-tracked or non-existent product, hence the coalesce.
    select coalesce(
             (select ps.qty_on_hand from v_pool_stock ps where ps.product_id = p_product_id),
             0
           )::int as n
  ),
  committed_qty as (
    -- Rentable stock promised on orders that have not gone out yet, over the requested window.
    -- Only 'confirmed': once an order is dispatched its stock is physically gone and is already
    -- absent from on-hand, and counting it in both places would halve the fleet on paper.
    --
    -- The CTE is committed_qty, not committed, because `committed` is also one of the RETURNS
    -- TABLE output columns and those are in scope inside the body as parameters. A real range
    -- table entry does win over a parameter here, so the shorter name resolved correctly, but it
    -- reads like a bug and invites a "fix" from whoever edits this next.
    select coalesce(sum(ol.qty), 0)::int as n
    from order_line ol
    join rental_order o on o.id = ol.order_id
    where ol.product_id = p_product_id
      and o.status = 'confirmed'
      and (p_exclude_order_id is null or o.id <> p_exclude_order_id)
      -- inclusive overlap: the return date is not a free day
      and o.out_date <= p_to
      and o.expected_return_date >= p_from
  ),
  consumable_committed as (
    -- A consumable is committed on the way out, not held over a window, so this branch reads no
    -- window at all: p_from and p_to are not consulted. An order agreed for the 20th commits its
    -- fifty bottles today, and keeps committing them until it goes out or is cancelled.
    select coalesce(sum(ol.qty), 0)::int as n
    from order_line ol
    join rental_order o on o.id = ol.order_id
    where ol.product_id = p_product_id
      and o.status = 'confirmed'
      and (p_exclude_order_id is null or o.id <> p_exclude_order_id)
      and o.out_date >= current_date
  ),
  answer as (
    select
      case prod.track_mode
        when 'unit'       then unit_on_hand.n
        when 'pool'       then pool_on_hand.n
        when 'consumable' then pool_on_hand.n
        else 0                                     -- product does not exist
      end as on_hand_n,
      case prod.track_mode
        when 'unit'       then committed_qty.n
        when 'pool'       then committed_qty.n
        when 'consumable' then consumable_committed.n
        else 0                                     -- product does not exist
      end as committed_n
    from prod, unit_on_hand, pool_on_hand, committed_qty, consumable_committed
  )
  select
    p_product_id,
    answer.on_hand_n,
    answer.committed_n,
    (answer.on_hand_n - answer.committed_n)
  from answer;
$$;

comment on function fn_availability is
  'Date-level availability for all three tracking modes (CLAUDE.md rule 13). Pooled and consumable on-hand is read from v_pool_stock and never re-derived. Never consults expected_return_date to decide whether a dispatched unit is back (rule 2). Consumables now commit on out_date rather than reporting committed = 0, so the same fifty bottles can no longer be promised to two customers — the tension recorded in 0007 is closed. available is deliberately unclamped: over-commitment is a real state and the operator needs to see how far over he is.';
