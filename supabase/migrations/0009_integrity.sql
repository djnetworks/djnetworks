-- 0009_integrity.sql
-- The last hardening pass before seeding and screens. Six things, all of them measured on a
-- replay of 0001-0008 with data anchored to 2026-09-05, not reasoned about:
--
--   1 · fn_availability double-books a partially dispatched order. 6 speakers owned, an order for
--       4, 2 physically loaded: on status 'confirmed' it answers available = 0, on status
--       'dispatched' it answers available = 4. The true answer is 2. Both wrong numbers come from
--       the same line — `committed` is filtered by ORDER STATUS instead of by what has actually
--       left the godown.
--
--   2 · Four child tables still hard-delete. 0002's own comment says of ledger_entry that "rows
--       are never deleted (rule 12)" and nothing enforced it: deleting a single 20,000 payment row
--       moved v_customer_balance.receivable from 31,000 to 51,000, silently.
--
--   3 · TRUNCATE walks past every BEFORE DELETE trigger in this schema and past RLS as well.
--       `set role authenticated; truncate movement cascade;` emptied the movement ledger — the
--       spine every derived view is counted from — with no error and no trace.
--
--   4 · fn_availability with a null date reports the whole fleet free. A blank <input type="date">
--       posts an empty string, PostgREST turns that into null, `o.out_date <= null` matches no
--       rows, and `committed` comes back 0. Measured: 6 owned with 4 booked answered 6 / 0 / 6.
--       CLAUDE.md's verification standard names exactly this — a clean run that is silently wrong.
--
--   5 · Rule 9 exists only in prose. An order with three boxes standing at a customer was moved to
--       'closed' with no error at all.
--
--   6 · Revenue posts on order confirmation (docs/decisions.md), so a confirmed order's line
--       already carries a ledger entry before anything is dispatched — and nothing stops that line
--       being edited or removed out from under the posted charge. The charge stays on the
--       customer's balance and the receivable is overstated by the amount of a line that no longer
--       exists. Section 2's conditional delete makes that reachable; UPDATE was never guarded at
--       all, so `update order_line set qty = 1` did the same damage with no message.
--
-- Sections below follow that order, except that 1 and 4 are the same function and are fixed
-- together in section 1, so section 5 is rule 9 and section 6 is the posted-charge freeze.
--
-- Nothing here stores anything that can be counted (rule 10). Nothing here adds a delete path for
-- orders, units or movements (rule 12) — the two conditional deletes in section 2 are for lines on
-- a draft order that has never moved, and the reasoning is written out there. No column is added
-- to unit (rule 1), no date is allowed to imply a return (rule 2), condition and status stay
-- separate (rule 3), receivable and deposit stay separate (rule 6), and order_line.agreed_rate and
-- line_total are never recomputed from the current product rate anywhere in this file — section 6
-- exists precisely to stop them being quietly rewritten after they have been billed (rule 5).


-- ===========================================================================
-- 1 · fn_availability — the undispatched remainder, and an argument guard.
-- ===========================================================================
--
-- THE DOUBLE-BOOKING.
--
-- Since 0003 `committed` has been "the quantity on order lines belonging to orders in status
-- 'confirmed'". 0007 and 0008 both carry a comment explaining why that is safe: once an order is
-- dispatched its stock is physically gone and already absent from on-hand, so counting it in both
-- places would halve the fleet on paper. The reasoning is right. The implementation does not do
-- what the reasoning describes, because dispatch is not an event that happens to a whole order.
-- Partial dispatch is normal — docs/structure.md says so in the dispatch form — and an order
-- carries ONE status for stock that is in two different physical states.
--
-- Measured, 6 owned, an order for 4, 2 boxes loaded into the van:
--
--   status        units_on_hand   committed   available    what is actually true
--   ------------  --------------  ----------  -----------  ---------------------------------
--   confirmed          4              4            0       4 on the shelf, 2 of them promised
--   dispatched         4              0            4       so the answer is 2
--
-- On 'confirmed' the two dispatched boxes are subtracted twice — once because they are no longer
-- at a location, and again because their line still counts in full. The screen says sold out while
-- four boxes stand in the godown, and the operator turns down a job he could take.
--
-- On 'dispatched' the two boxes that have NOT been loaded vanish entirely, and all four remaining
-- speakers are offered to somebody else. That is the more expensive direction: it is the same
-- shape as the bug rule 2 exists to prevent — stock that is spoken for being quietly offered for
-- hire — arriving through the reservation side instead of the return side.
--
-- THE FIX. `committed` becomes the UNDISPATCHED REMAINDER of each order: what was agreed, less
-- what has actually left against it, clamped at zero. That makes the two sources of unavailability
-- genuinely disjoint, which is what the old comment claimed the status filter was doing:
--
--     dispatched stock  -> already absent from on-hand, counted nowhere else
--     undispatched stock -> committed, and still sitting on the shelf
--
-- Status now decides only whether an order commits ANYTHING. Cancelled and closed commit nothing.
-- Every other status contributes its remainder, which is naturally 0 once the line is fully
-- dispatched, so nothing else needs special-casing — and an order left in 'confirmed' after the
-- van has gone (there is one operator and nobody to remind him to change a dropdown) now reports
-- the truth instead of double-counting.
--
-- AGGREGATE PER ORDER FIRST, THEN SUBTRACT. order_line has no unique constraint on
-- (order_id, product_id) and legitimately should not have one — the same product can appear twice
-- on one order at two agreed rates, which is exactly what happens when four tops are quoted and
-- two of them are discounted, and rule 5 says each line keeps the price it was agreed at. So the
-- lines are summed per (order_id, product_id) BEFORE the dispatched quantity is taken off. Doing
-- it per line subtracts the same dispatched quantity once for every line and under-reports
-- committed: measured on two lines of 2 with 2 boxes loaded, per-line arithmetic gives
-- max(2-2,0) + max(2-2,0) = 0 committed and offers all four remaining boxes away, where the right
-- answer is 2.
--
-- RETURNS ARE NOT NETTED OFF, DELIBERATELY. "Dispatched" here means EVER dispatched, not
-- "currently out". An order for 4 that sent 4 and got all 4 back is finished; its remainder is 0
-- and it commits nothing. If this counted "currently out" instead, every returned order would spring
-- back to committing its full quantity and re-reserve stock for a job that is over — measured:
-- 4 owned, 4 out, 4 back, committed would read 4 and available 0 on a completely free fleet.
-- The clamp at zero also absorbs the other direction: a piece dispatched, returned and dispatched
-- again produces more dispatch movements than the line has qty, and greatest(...,0) keeps that at
-- 0 rather than turning it into negative commitment.
--
-- HOW "DISPATCHED" IS COUNTED, per (order, product):
--   unit               the number of dispatch movements with unit_id is not null — one row per
--                      numbered piece, which is how bulk dispatch writes them (0007 section 2).
--   pool, consumable   the summed qty of dispatch movements with unit_id is null.
-- Both figures are computed and the tracking mode chooses between them, which keeps a mis-filed
-- row from being counted on the wrong side.
--
-- WHAT IS NOT CHANGED, and this was checked by diffing against 0008 rather than assumed:
--   * the date predicates. unit and pool keep the inclusive overlap
--     (o.out_date <= p_to and o.expected_return_date >= p_from) — a box due back on the 4th is not
--     offered on the 4th, because somebody has to go and collect it. consumable keeps 0008's
--     o.out_date >= current_date with no window at all, because a consumable is committed on the
--     way out rather than held over a window; there is nothing to hold, since nothing comes back.
--   * p_exclude_order_id, honoured in every branch, so the order being edited never counts against
--     itself.
--   * the unit on-hand count: pieces whose LAST movement put them at one of our own locations.
--     Nothing here reads a date to decide that. A unit with a dispatch and no matching return is
--     out whatever the calendar says (rule 2), and a unit at a repair shop leaves availability with
--     no extra rule.
--   * pooled and consumable on-hand still comes from v_pool_stock and is never re-derived here
--     (rule 13).
--   * `available` is still not clamped. Over-commitment is a real state and the operator needs to
--     see how far over he is, not a zero that reads like "just sold out".
--
-- THE ARGUMENT GUARD (item 4 of this migration).
--
-- `o.out_date <= p_to` with p_to null is not an error in SQL, it is simply false for every row, so
-- committed collapsed to 0 and the function answered "everything is free" with complete
-- confidence. Measured: 6 owned, 4 booked, p_to null -> 6 / 0 / 6. This function is callable as a
-- PostgREST RPC and a blank date input posts an empty string that arrives as null, so it is one
-- unfilled field on an order screen away, and the failure is a double-booking rather than an
-- error message. A reversed range is the same class: p_from > p_to silently matches only orders
-- that span the inversion.
--
-- So the function is now plpgsql: a guard block, then the same set-returning query. The signature,
-- the four output columns, and `stable` are unchanged, so existing grants and any caller survive.
--
-- NOT declared STRICT, deliberately. A STRICT set-returning function called with a null argument
-- returns zero rows instead of raising, and a caller doing a plain join reads zero rows as blank —
-- which is the identical bug wearing a different hat, and harder to spot because nothing at all
-- appears. Raising is the only outcome that reaches the operator.
--
-- p_product_id is guarded too, and that is not scope creep: it is the same blank-form failure (an
-- unselected product posts null), and without it the FIRST output column comes back null, which
-- breaks this function's own never-null contract. That contract is otherwise intact — every CTE is
-- an unfiltered aggregate or a coalesced scalar subquery with no GROUP BY, so a valid call always
-- returns exactly one row with no nulls, including for a product_id that does not exist, which
-- answers (id, 0, 0, 0) rather than no row at all.
--
-- Permissions are not touched here, so there is no revoke/grant pair to order. CREATE OR REPLACE
-- keeps the existing ACL exactly as it stands.
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
language plpgsql
stable
set search_path = public, pg_temp
as $fn$
begin
  -- ---- argument guard ------------------------------------------------------
  if p_product_id is null then
    raise exception
      'fn_availability was called with no product: p_product_id is null. Every screen is product-first (CLAUDE.md rule 8) — pick the product, then the dates. Answering this call would report 0 available for a product nobody named.';
  end if;

  if p_from is null and p_to is null then
    raise exception
      'fn_availability was called with no dates: p_from and p_to are both null. Availability is date-level; with a null date the overlap test matches no orders at all and the whole fleet reports free (6 owned with 4 booked answered 6 / 0 / 6). Refusing rather than answering.';
  elsif p_from is null then
    raise exception
      'fn_availability was called with p_from = null (p_to = %). A blank date field posts an empty string that arrives here as null; with it the overlap test matches no orders and every booked item reports free. Refusing rather than answering.',
      p_to;
  elsif p_to is null then
    raise exception
      'fn_availability was called with p_to = null (p_from = %). A blank date field posts an empty string that arrives here as null; with it the overlap test matches no orders and every booked item reports free. Refusing rather than answering.',
      p_from;
  end if;

  if p_from > p_to then
    raise exception
      'fn_availability was called with the dates the wrong way round: p_from = % is after p_to = %. An inverted window matches only orders that span the inversion, so the answer would be quietly too high rather than obviously wrong.',
      p_from, p_to;
  end if;

  -- ---- the answer ----------------------------------------------------------
  return query
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
    -- re-derived here. v_pool_stock has no row for a unit-tracked or non-existent product,
    -- hence the coalesce.
    select coalesce(
             (select ps.qty_on_hand from v_pool_stock ps where ps.product_id = p_product_id),
             0
           )::int as n
  ),
  line_totals as (
    -- One row per ORDER, not per line. order_line has no unique constraint on
    -- (order_id, product_id) and one order can carry the same product twice at two agreed rates;
    -- summing first is what stops the dispatched quantity being subtracted once per line.
    select ol.order_id, sum(ol.qty)::int as qty_ordered
    from order_line ol
    where ol.product_id = p_product_id
    group by ol.order_id
  ),
  dispatched as (
    -- What has EVER left against each order for this product. Returns are deliberately not netted
    -- off: an order that sent everything and got everything back is finished and commits nothing.
    select
      m.order_id,
      count(*) filter (where m.unit_id is not null)::int            as pieces_dispatched,
      coalesce(sum(m.qty) filter (where m.unit_id is null), 0)::int as qty_dispatched
    from movement m
    where m.product_id = p_product_id
      and m.movement_type = 'dispatch'
      and m.order_id is not null
    group by m.order_id
  ),
  remainder as (
    -- Per order: agreed less loaded, floored at zero. A cancelled or closed order commits
    -- nothing; every other status contributes a remainder that is naturally 0 once the line is
    -- fully dispatched, so no other status needs a rule of its own.
    select
      o.out_date,
      o.expected_return_date,
      greatest(
        lt.qty_ordered
        - case prod.track_mode
            when 'unit' then coalesce(d.pieces_dispatched, 0)
            else             coalesce(d.qty_dispatched, 0)
          end,
        0
      )::int as qty_remaining
    from line_totals lt
    join rental_order o on o.id = lt.order_id
    cross join prod
    left join dispatched d on d.order_id = lt.order_id
    where o.status not in ('cancelled','closed')
      and (p_exclude_order_id is null or o.id <> p_exclude_order_id)
  ),
  committed_window as (
    -- unit and pool: held over the requested window. Inclusive overlap — the return date is not a
    -- free day, because somebody has to go and collect the gear on it.
    select coalesce(sum(r.qty_remaining), 0)::int as n
    from remainder r
    where r.out_date <= p_to
      and r.expected_return_date >= p_from
  ),
  committed_outbound as (
    -- consumable: committed on the way OUT, not held over a window, so p_from and p_to are not
    -- consulted in this branch at all. Unchanged in substance from 0008; what is new is that a
    -- part-issued order now commits only the bottles that have not gone yet.
    select coalesce(sum(r.qty_remaining), 0)::int as n
    from remainder r
    where r.out_date >= current_date
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
        when 'unit'       then committed_window.n
        when 'pool'       then committed_window.n
        when 'consumable' then committed_outbound.n
        else 0                                     -- product does not exist
      end as committed_n
    from prod, unit_on_hand, pool_on_hand, committed_window, committed_outbound
  )
  select
    p_product_id,
    answer.on_hand_n,
    answer.committed_n,
    (answer.on_hand_n - answer.committed_n)
  from answer;
end
$fn$;

comment on function fn_availability is
  'Date-level availability for all three tracking modes. committed is the UNDISPATCHED REMAINDER of each order (agreed less ever-dispatched, clamped at zero), aggregated per order before subtraction because one order may carry the same product on two lines; cancelled and closed orders commit nothing and no other status is special-cased. Dispatched stock is absent from on-hand and committed stock is still on the shelf, so the two are disjoint and a partial dispatch is no longer counted twice. Returns are not netted off ever-dispatched — a completed order must not re-reserve stock. Never consults expected_return_date to decide whether a dispatched unit is back (CLAUDE.md rule 2). Pooled and consumable on-hand comes from v_pool_stock and is never re-derived (rule 13). Raises on a null product, a null date or a reversed range rather than reporting the fleet free; deliberately not STRICT, since a strict SRF would return zero rows and read as blank. available is deliberately unclamped.';


-- ===========================================================================
-- 2 · DELETE guards on the four remaining child tables.
-- ===========================================================================
--
-- movement, rental_order and unit have been guarded since 0004 and 0007. ledger_entry, repair_job,
-- order_line and order_charge never were, and all four delete cleanly today.
--
-- ledger_entry is the one that has already been measured doing damage. 0002's comment on the table
-- says "Cancellations and short dispatches produce `reversal` entries; rows are never deleted
-- (rule 12)" — a rule described in a comment and enforced nowhere. Deleting a single 20,000 payment
-- row took v_customer_balance.receivable from 31,000 to 51,000 with no error, no trace and no
-- second pair of eyes: the customer's payment history simply loses a payment, and the number the
-- operator chases him for is 20,000 too high. The compensating action already exists in the CHECK
-- constraint — a `reversal` entry — and it leaves both rows visible, which is the entire point.
--
-- repair_job is unconditional for the same reason. UPDATE stays allowed, so a mistyped fault, cost
-- or outcome is corrected in place; there is never a reason to remove the row. Deleting one takes
-- its actual_cost out of v_product_roi and quietly RAISES the reported return on whichever product
-- breaks most often, which is the opposite of the number that report exists to produce.
--
-- WHY order_line AND order_charge ARE CONDITIONAL, AND THE OTHER FIVE ARE NOT.
--
-- This is a decision the owner made explicitly, and it is narrower than it looks. Rule 12 protects
-- HISTORY. A draft order that has not moved is not history — it is a form still being filled in.
-- Blocking these two outright would mean a line added by mistake could never be removed at all:
-- UPDATE can fix qty and rate, but order_line.qty carries check (qty >= 1) so a line cannot be
-- zeroed out, and the order form would have no way to drop a row. The operator's only escape would
-- be to cancel a perfectly good order and retype it.
--
-- So DELETE is allowed on exactly one state and refused everywhere else:
--
--     parent rental_order.status = 'confirmed'
--       AND nothing has been dispatched against it
--       AND the order carries no posted charge on the customer ledger (section 6)
--
--   order_line     nothing dispatched = no movement row with this order_id AND this product_id.
--                  Scoped to the product, so removing the cable line from an order whose speakers
--                  have already gone is still allowed — that line has genuinely not moved.
--   order_charge   nothing dispatched = no movement row for this order_id at all. A charge is
--                  job-level, not product-level, so it has no product to scope to; once anything
--                  on the job has left, the transport charge is part of what happened.
--
-- The third condition is the one added last and it is the subtle one: revenue posts on order
-- CONFIRMATION, so "confirmed and nothing dispatched" is exactly the window in which a charge has
-- already hit the customer's balance. Deleting the line there strands the charge and overstates the
-- receivable. The test and the whole argument live in section 6, next to the matching UPDATE guard,
-- because the two doors are one rule and splitting the reasoning across two places is how the
-- second copy drifts. The functions below call fn_order_net_posted_charge, which section 6 defines
-- LATER in this file: the whole migration is one transaction and no trigger can fire until it has
-- committed, so definition order does not matter to Postgres — reading order matters to people, and
-- the reasoning belongs beside the tripwire it explains.
--
-- The moment the order leaves 'confirmed' — dispatched, partially_returned, returned, closed,
-- cancelled — or the moment the van loads, the line stops being a draft and becomes the record of
-- what was agreed and what went out. From then on the answer is to cancel the order, which is what
-- 0007's rental_order guard already tells the operator to do, and the messages below point at the
-- same exit so the two guards do not give contradictory advice.
--
-- These triggers return OLD. A BEFORE DELETE trigger that returns NULL cancels the delete
-- SILENTLY, and the client sees a successful call that removed nothing — the same class of
-- invisible failure as a CHECK constraint rejecting a write, which CLAUDE.md already warns about.
-- Every refusal here raises.
--
-- One interaction worth stating: order_line and order_charge are `on delete cascade` from
-- rental_order, so in principle deleting an order would delete lines without these triggers seeing
-- a reason to complain. It cannot happen — 0007's rental_order_no_delete raises before any cascade
-- is evaluated — but if that guard is ever removed these two will fire on the cascade and refuse
-- it, which is the right answer.
-- ---------------------------------------------------------------------------

create or replace function fn_ledger_entry_is_never_deleted()
returns trigger
language plpgsql
set search_path = public, pg_temp
as $$
declare
  v_customer text;
begin
  select c.name into v_customer from customer c where c.id = old.customer_id;

  raise exception
    'ledger entries are never deleted — post a `reversal` entry instead (CLAUDE.md rule 12, and 0002 says so on this table). Refusing to delete the % of % dated % on %''s account. Deleting a ledger row moves v_customer_balance with no error and no trace: a single 20,000 payment removed this way took a receivable from 31,000 to 51,000, and there is nobody to notice.',
    old.type, old.amount, old.entry_date, coalesce(v_customer, '(unknown customer)');
end $$;

drop trigger if exists ledger_entry_no_delete on ledger_entry;
create trigger ledger_entry_no_delete
  before delete on ledger_entry
  for each row execute function fn_ledger_entry_is_never_deleted();

create or replace function fn_repair_job_is_never_deleted()
returns trigger
language plpgsql
set search_path = public, pg_temp
as $$
declare
  v_code     text;
  v_piece_no int;
begin
  -- Product first, then the number. A bare piece number identifies nothing (rule 8).
  select p.short_code, u.piece_no
    into v_code, v_piece_no
  from unit u
  join product p on p.id = u.product_id
  where u.id = old.unit_id;

  raise exception
    'repair jobs are never deleted — correct this one in place with an UPDATE, or record its outcome and leave it standing (CLAUDE.md rule 12). Refusing to delete the job on % piece % sent on %. Deleting it takes its cost out of v_product_roi and quietly raises the reported return on whatever breaks most, which is the opposite of what that report is for.',
    coalesce(v_code, '(unknown product)'), coalesce(v_piece_no, 0), old.date_sent;
end $$;

drop trigger if exists repair_job_no_delete on repair_job;
create trigger repair_job_no_delete
  before delete on repair_job
  for each row execute function fn_repair_job_is_never_deleted();

create or replace function fn_order_line_delete_is_draft_only()
returns trigger
language plpgsql
set search_path = public, pg_temp
as $$
declare
  v_order_no text;
  v_status   text;
  v_code     text;
  v_moved    int;
  v_net      numeric(12,2);
begin
  select o.order_no, o.status into v_order_no, v_status
  from rental_order o where o.id = old.order_id;

  select p.short_code into v_code from product p where p.id = old.product_id;

  if v_status is distinct from 'confirmed' then
    raise exception
      'order % is %, so its lines are the record of what was agreed and what went out, not a draft — the % line cannot be deleted (CLAUDE.md rule 12). Cancel the order instead, by setting status = ''cancelled''. A line may be deleted only while the order is still confirmed and nothing has been dispatched against it.',
      coalesce(v_order_no, '(unknown order)'), coalesce(v_status, 'missing'), coalesce(v_code, '(unknown product)');
  end if;

  select count(*)::int into v_moved
  from movement m
  where m.order_id = old.order_id
    and m.product_id = old.product_id;

  if v_moved > 0 then
    raise exception
      'the % line on order % has % movement(s) recorded against it — the van has already loaded, so this line is history and is not deleted (CLAUDE.md rule 12). Correct the quantity or the rate with an UPDATE, record a return or a write-off for what went out, or cancel the whole order. qty cannot be set to 0: order_line carries check (qty >= 1), and that is deliberate.',
      coalesce(v_code, '(unknown product)'), coalesce(v_order_no, '(unknown order)'), v_moved;
  end if;

  -- Third condition: the money may already have been posted. See section 6.
  v_net := fn_order_net_posted_charge(old.order_id);

  if v_net <> 0 then
    raise exception
      'the % line on order % cannot be deleted: % of charges are already posted to the customer ledger against this order, net of reversals. Removing the line would leave that charge standing and OVERSTATE the receivable — the operator would chase money for a line that no longer exists (CLAUDE.md rule 6; docs/decisions.md, "Revenue posts on order confirmation"). Record a ledger_entry of type ''reversal'' for the amount being removed, and then delete the line: the reversal is what unlocks it.',
      coalesce(v_code, '(unknown product)'), coalesce(v_order_no, '(unknown order)'), v_net;
  end if;

  -- Still confirmed, nothing has moved, and no money has been posted: this is a draft, and rule 12
  -- protects history, not drafts. Returning OLD lets the delete through; returning NULL would
  -- cancel it silently.
  return old;
end $$;

drop trigger if exists order_line_draft_delete_only on order_line;
create trigger order_line_draft_delete_only
  before delete on order_line
  for each row execute function fn_order_line_delete_is_draft_only();

create or replace function fn_order_charge_delete_is_draft_only()
returns trigger
language plpgsql
set search_path = public, pg_temp
as $$
declare
  v_order_no text;
  v_status   text;
  v_moved    int;
  v_net      numeric(12,2);
begin
  select o.order_no, o.status into v_order_no, v_status
  from rental_order o where o.id = old.order_id;

  if v_status is distinct from 'confirmed' then
    raise exception
      'order % is %, so its charges are part of what was billed, not a draft — the % charge of % cannot be deleted (CLAUDE.md rule 12). Cancel the order instead, or post a compensating ledger entry if it has already been billed.',
      coalesce(v_order_no, '(unknown order)'), coalesce(v_status, 'missing'), old.type, old.amount;
  end if;

  -- A charge is job-level and has no product to scope to, so ANY movement on the order closes the
  -- window. Once something has physically gone out, the transport charge is part of the job.
  select count(*)::int into v_moved
  from movement m
  where m.order_id = old.order_id;

  if v_moved > 0 then
    raise exception
      'order % has % movement(s) recorded against it, so the % charge of % is part of a job that has already started and is not deleted (CLAUDE.md rule 12). Correct the amount with an UPDATE, or cancel the order.',
      coalesce(v_order_no, '(unknown order)'), v_moved, old.type, old.amount;
  end if;

  -- Third condition, as on order_line. See section 6.
  v_net := fn_order_net_posted_charge(old.order_id);

  if v_net <> 0 then
    raise exception
      'the % charge of % on order % cannot be deleted: % of charges are already posted to the customer ledger against this order, net of reversals. Removing it would leave that charge standing and OVERSTATE the receivable (CLAUDE.md rule 6; docs/decisions.md, "Revenue posts on order confirmation"). Record a ledger_entry of type ''reversal'' for the amount being removed, and then delete the charge.',
      old.type, old.amount, coalesce(v_order_no, '(unknown order)'), v_net;
  end if;

  return old;
end $$;

drop trigger if exists order_charge_draft_delete_only on order_charge;
create trigger order_charge_draft_delete_only
  before delete on order_charge
  for each row execute function fn_order_charge_delete_is_draft_only();


-- ===========================================================================
-- 3 · TRUNCATE is revoked from anon and authenticated.
-- ===========================================================================
--
-- Every guard in this schema is a BEFORE DELETE trigger, and TRUNCATE does not fire BEFORE DELETE
-- triggers. It does not evaluate row level security either. So the whole append-only story — 0004's
-- movement guard, 0007's order and unit guards, section 2 above — is bypassed by one statement.
--
-- Measured on the replay: `set role authenticated; truncate movement cascade;` emptied the movement
-- ledger completely. That is the spine (0002's own word for it) from which location, availability,
-- utilisation and outstanding stock are all counted; with it gone every one of those views answers
-- zero, confidently, and there is no compensating movement that can bring it back.
--
-- This is not reachable through PostgREST, which never issues TRUNCATE. It is reachable from any
-- direct Postgres connection using the anon or authenticated role — a psql session, a script, a
-- future agent with the connection string — and the reason the privilege is there at all is that
-- Supabase grants ALL on tables in public to anon and authenticated, and ALL includes TRUNCATE.
-- Nobody chose it; it arrived with the default grant.
--
-- Only the TRUNCATE bit is removed. select, insert, update, delete, references and trigger are
-- untouched, so RLS and the triggers keep deciding everything they decided before, and nothing is
-- granted back — there is no revoke/grant pair here whose order could matter. service_role and
-- postgres keep TRUNCATE: service_role is the escape hatch for a real reset and postgres owns the
-- schema, and taking it from either would make the database harder to fix rather than safer.
--
-- The second statement is the one that matters six months from now. The first only covers tables
-- that exist TODAY; a table created by a future migration would be granted ALL again by Supabase's
-- default privileges and would silently get TRUNCATE back. ALTER DEFAULT PRIVILEGES amends the
-- stored default so new tables never carry it.
--
-- `for role postgres` is explicit rather than implied. ALTER DEFAULT PRIVILEGES without it targets
-- whatever role happens to be running the migration, and the entry that needs amending is the one
-- Supabase registered against postgres — the role that owns this schema and creates its tables. If
-- migrations are ever applied by a different owner, this line has to be repeated for that owner,
-- because default privileges are per-owner and there is no wildcard.
-- ---------------------------------------------------------------------------

revoke truncate on all tables in schema public from anon, authenticated;

alter default privileges for role postgres in schema public
  revoke truncate on tables from anon, authenticated;


-- ===========================================================================
-- 5 · Rule 9 — an order cannot close while anything is still at the customer.
-- ===========================================================================
--
-- Rule 9 has been in CLAUDE.md and in docs/decisions.md since the schema was designed and has
-- never existed in the database. Confirmed on the replay: an order with three boxes standing at a
-- customer moved to status 'closed' with no error at all. docs/decisions.md calls it a hard block
-- and records why — "the single most expensive bug found in an earlier build: six out, five back,
-- and the sixth quietly offered for hire while it sat in a hall". A closed order drops off the
-- chase list, and the box that never came back stops being anybody's problem.
--
-- The block fires only on the TRANSITION into closed. Ordinary edits to an already-closed order —
-- a note, a corrected venue — are untouched, which matters because otherwise the operator would
-- find a closed order permanently uneditable the moment anything about it looked outstanding.
--
-- v_order_outstanding is the test, and since 0008 that view reports pooled quantities as well as
-- numbered pieces. So this covers cables, and that is the point: an order whose speakers all came
-- back but whose fifteen XLR cables did not is not a finished job. The view does not filter on
-- status, so it still answers correctly while the order sits in any state, and it does not filter
-- on a date either — outstanding means no return movement exists, never that a date has or has not
-- passed (rule 2).
--
-- The three legitimate exits are named in the message because a block with no way out is a block
-- that gets worked around. All three are explicit acts, and all three are recordable today:
--   found      — the box turns up: a `return` or `found` movement.
--   write-off  — pooled stock left at the venue: a `write_off` movement from_kind = 'customer'
--                (0008 section 4 writes this path out in full).
--   loss       — a numbered piece is gone: unit.lifecycle = 'lost', which takes it out of
--                v_unit_status.status = 'out' and therefore out of this view. Rule 4 still holds,
--                its piece number dies with it.
-- What is NOT an exit: a date passing, or a bulk action over a list of orders.
--
-- The message counts what is out and names an item or two, because "something is still out" sends
-- the operator hunting through a list. Products are named, not bare piece numbers (rule 8).
--
-- KNOWN DEPENDENCY, stated rather than discovered later: this trigger reads v_order_outstanding as
-- the CALLER, because the view is security_invoker and this function is deliberately not security
-- definer. A caller who could update rental_order but not read movement would see an empty view and
-- the close would go through. No such role exists — under 0004 the only role that can write
-- rental_order is `authenticated`, which reads everything — and making this security definer to
-- close a gap nobody can reach would add a privilege escalation surface for no gain.
-- ---------------------------------------------------------------------------

create or replace function fn_order_close_requires_everything_back()
returns trigger
language plpgsql
set search_path = public, pg_temp
as $$
declare
  v_rows     int;
  v_examples text;
begin
  -- The trigger's WHEN clause already restricts this to the transition into 'closed'. Repeated
  -- here so the function is safe if it is ever attached to anything else.
  if not (new.status = 'closed' and old.status is distinct from 'closed') then
    return new;
  end if;

  select count(*)::int into v_rows
  from v_order_outstanding oo
  where oo.order_id = new.id;

  if v_rows = 0 then
    return new;
  end if;

  select string_agg(x.label, ', ')
    into v_examples
  from (
    select case
             when oo.unit_id is not null then oo.short_code || ' piece ' || oo.piece_no
             else oo.qty_outstanding || ' x ' || oo.short_code
           end as label
    from v_order_outstanding oo
    where oo.order_id = new.id
    order by oo.unit_id nulls last, oo.short_code, oo.piece_no
    limit 2
  ) x;

  if v_rows > 2 then
    v_examples := v_examples || format(', and %s more', v_rows - 2);
  end if;

  raise exception
    'order % cannot be closed: % item(s) are still at the customer (%). An order closes only after an explicit found, a write-off, or a recorded loss — never because a date passed and never as a side effect of a bulk action (CLAUDE.md rule 9). Record the return, write the pooled stock off from the customer, or mark the piece lost, and then close.',
    new.order_no, v_rows, coalesce(v_examples, 'see v_order_outstanding');
end $$;

drop trigger if exists rental_order_close_needs_return on rental_order;
create trigger rental_order_close_needs_return
  before update on rental_order
  for each row
  when (new.status = 'closed' and old.status is distinct from 'closed')
  execute function fn_order_close_requires_everything_back();


-- ===========================================================================
-- 6 · A posted charge freezes the money on a line.
-- ===========================================================================
--
-- THE GAP. docs/decisions.md, "Revenue posts on order confirmation": rental charges hit the ledger
-- when the order is confirmed, marked state = 'upcoming' until dispatch. So the window section 2
-- opens for editing a draft — confirmed, nothing dispatched — is EXACTLY the window in which the
-- customer's balance already carries the charge for that line. Three doors led to the same damage:
--
--   delete the line      section 2 permits it while the order is confirmed and undispatched
--   reduce qty           UPDATE was never guarded on order_line at all
--   edit agreed_rate     same, and line_total with it
--
-- All three leave the posted ledger_entry standing against a line that no longer says what it said.
-- The receivable is then overstated by the difference, and there is nobody to catch it: one
-- operator, no second pair of eyes, and the number he reads on the portal and chases the customer
-- for is simply wrong. This is rule 6 territory specifically — receivable and deposit held are two
-- separate numbers, and it is the receivable that rots here. decisions.md already names reversal
-- entries as the acknowledged cost of posting on confirmation ("Cost: cancellations and short
-- dispatches need reversal entries"), and nothing in the schema made anybody write one.
--
-- THE RULE. An order line's money may not be deleted or changed while its order carries a NON-ZERO
-- NET POSTED CHARGE.
--
--     net posted charge (order) = sum of ledger_entry.amount for type in
--                                   ('rental','transport','labour','misc','damage')
--                                 minus sum of amount for type 'reversal',
--                                 scoped by ledger_entry.order_id
--
-- WHAT IS DELIBERATELY NOT IN THAT SUM. payment, discount and write_off are settlement, not
-- billing. deposit_in, deposit_out and deposit_forfeit are the customer's own money being held —
-- a liability, never revenue (rule 6). A customer who has paid a 5,000 deposit on a job that has
-- not been billed yet must still be able to have his order corrected; freezing the form because
-- money arrived would merge the two numbers that rule 6 exists to keep apart.
--
-- WHY NET RATHER THAN EXISTENCE, and this is the load-bearing part. `exists (select 1 from
-- ledger_entry where order_id = ...)` looks equivalent and is not: it never unlocks. Rule 12 means
-- the original entry survives the reversal — both rows stay visible, that is the whole point — so
-- an existence test would keep the line frozen forever, and the error message telling the operator
-- to write a reversal would be a lie he discovers only after writing one. With NET, the reversal IS
-- the unlock:
--
--     insert the reversal   -> net returns to 0
--     edit or delete the line
--     post the new charge   -> net is whatever the line is now worth
--
-- and all three happen inside ONE transaction, because by the time the UPDATE on order_line runs
-- the trigger reads net 0. Measured: rental 6,000 posted, receivable 6,000, qty edit refused;
-- reversal 6,000 in the same transaction, receivable 0, the same qty edit allowed.
--
-- BOTH DOORS, and that is why there is a new BEFORE UPDATE trigger here as well as an extra
-- condition in section 2. Guarding only DELETE would leave `update order_line set qty = 1` doing
-- identical damage with no message at all — and the order form is far more likely to edit a line
-- than to remove one.
--
-- WHICH COLUMNS ARE FROZEN, and which are not:
--
--   order_line    frozen: qty, base_rate, discount_pct, agreed_rate, line_total, product_id
--                 free:   pinned_unit_id, is_subhired, subhire_vendor_id, subhire_cost
--                 Pinning a specific box, or flagging the line as sub-hired and recording what the
--                 vendor charges US, moves no money on the customer's side. Allocation must stay
--                 editable right up to dispatch — that is the reservation model in decisions.md.
--   order_charge  frozen: type, amount, description
--                 description is in the list because it is what the customer is told the charge was
--                 for; changing it after the money has posted makes the statement and the order
--                 disagree about the same rupees.
--
-- Compared with `is distinct from`, not `<>`, so an update that rewrites a NULL as NULL — which is
-- what a form does when it PATCHes every column it rendered — is not treated as a change. Otherwise
-- opening and saving an order without touching anything would be refused, and the operator would
-- learn to distrust the message.
--
-- WHAT THIS COSTS TODAY: nothing at all. ledger_entry holds zero rows on this database and nothing
-- posts to it yet, so the net is 0 for every order and the order form stays completely editable.
-- This is a tripwire, not a restriction — it arms itself on the day the ledger-posting side is
-- built, and converts a silently wrong balance into a loud error at the exact moment somebody
-- builds the thing that could cause it. The migration that implements posting on confirmation is
-- expected to come back here: the honest end state is that confirming, editing and cancelling an
-- order write their own reversal entries, and the operator never sees this message at all. Until
-- that exists, the message tells him what to type.
--
-- Nothing here is stored (rule 10) — the net is counted from the ledger on every check, so it
-- cannot disagree with the ledger. Nothing here deletes anything (rule 12). Nothing here recomputes
-- agreed_rate or line_total from the current product rate; it refuses to let them be rewritten
-- after they have been billed, which is rule 5 with teeth.
-- ---------------------------------------------------------------------------

create or replace function fn_order_net_posted_charge(p_order_id uuid)
returns numeric
language sql
stable
set search_path = public, pg_temp
as $$
  -- Billed amounts less reversals, for one order. Payments, discounts, write-offs and every kind of
  -- deposit are excluded on purpose: settlement and held money are not billing, and a deposit must
  -- never freeze a line (CLAUDE.md rule 6).
  select coalesce(sum(
           case
             when le.type in ('rental','transport','labour','misc','damage') then  le.amount
             when le.type = 'reversal'                                       then -le.amount
             else 0
           end
         ), 0)::numeric(12,2)
  from ledger_entry le
  where le.order_id = p_order_id;
$$;

comment on function fn_order_net_posted_charge is
  'Charges posted to the customer ledger against one order, net of reversals. Deposits, payments, discounts and write-offs are excluded — they are settlement or held money, not billing (CLAUDE.md rule 6). Used by the order_line and order_charge guards: a non-zero net freezes the money on the order, and posting a reversal is what unlocks it.';

create or replace function fn_order_line_money_is_frozen_by_posting()
returns trigger
language plpgsql
set search_path = public, pg_temp
as $$
declare
  v_net      numeric(12,2);
  v_order_no text;
  v_code     text;
begin
  -- Only money-bearing columns. Allocation and sub-hire fields stay editable.
  if new.qty          is distinct from old.qty
  or new.base_rate    is distinct from old.base_rate
  or new.discount_pct is distinct from old.discount_pct
  or new.agreed_rate  is distinct from old.agreed_rate
  or new.line_total   is distinct from old.line_total
  or new.product_id   is distinct from old.product_id
  then
    v_net := fn_order_net_posted_charge(old.order_id);

    if v_net <> 0 then
      select o.order_no into v_order_no from rental_order o where o.id = old.order_id;
      select p.short_code into v_code   from product p      where p.id = old.product_id;

      raise exception
        'the % line on order % cannot be repriced or resized: % of charges are already posted to the customer ledger against this order, net of reversals. Changing qty, the rate or the line total now would leave the posted charge standing and OVERSTATE the receivable (CLAUDE.md rule 6; docs/decisions.md, "Revenue posts on order confirmation"). Record a ledger_entry of type ''reversal'' for the amount being removed, then edit the line and post the new charge — all three in one transaction if you like; the reversal is what unlocks it. Pinning a unit, or flagging sub-hire, is not blocked.',
        coalesce(v_code, '(unknown product)'), coalesce(v_order_no, '(unknown order)'), v_net;
    end if;
  end if;

  return new;
end $$;

drop trigger if exists order_line_money_frozen on order_line;
create trigger order_line_money_frozen
  before update on order_line
  for each row execute function fn_order_line_money_is_frozen_by_posting();

create or replace function fn_order_charge_money_is_frozen_by_posting()
returns trigger
language plpgsql
set search_path = public, pg_temp
as $$
declare
  v_net      numeric(12,2);
  v_order_no text;
begin
  if new.type        is distinct from old.type
  or new.amount      is distinct from old.amount
  or new.description is distinct from old.description
  then
    v_net := fn_order_net_posted_charge(old.order_id);

    if v_net <> 0 then
      select o.order_no into v_order_no from rental_order o where o.id = old.order_id;

      raise exception
        'the % charge on order % cannot be changed: % of charges are already posted to the customer ledger against this order, net of reversals. Editing the amount or what it says it is for would leave the posted charge standing and OVERSTATE the receivable (CLAUDE.md rule 6; docs/decisions.md, "Revenue posts on order confirmation"). Record a ledger_entry of type ''reversal'' for the amount being removed, then edit the charge and post the new one.',
        old.type, coalesce(v_order_no, '(unknown order)'), v_net;
    end if;
  end if;

  return new;
end $$;

drop trigger if exists order_charge_money_frozen on order_charge;
create trigger order_charge_money_frozen
  before update on order_charge
  for each row execute function fn_order_charge_money_is_frozen_by_posting();
