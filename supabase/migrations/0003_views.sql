-- 0003_views.sql
-- Everything derived. Rule 10: nothing is stored that can be counted.
--
-- These views are the whole reason the movement table is append-only. If any of them is ever
-- replaced by a stored column, the column and the ledger will disagree and the wrong one will
-- be believed.

-- ---------------------------------------------------------------------------
-- Every view below is declared security_invoker, and that is not optional.
--
-- A view runs with its OWNER's rights by default. The owner here is `postgres`, which on
-- Supabase carries BYPASSRLS, and Supabase separately grants SELECT on everything in `public`
-- to `anon`. Left at the default, these views hand anonymous traffic every customer balance,
-- every deposit held and the whole fleet — walking straight past the row level security that
-- 0004 puts on the base tables, which is the exact opposite of what 0004 says it does.
-- security_invoker makes each view read as its caller, so the operator_all policy decides.
-- v_unit_status reads v_unit_location, so the inner view needs the setting too: the chain is
-- only as tight as its loosest link.
-- ---------------------------------------------------------------------------

-- ---------------------------------------------------------------------------
-- Where is every unit right now.
-- Rule 1: current location is the destination of the last movement, full stop.
-- ---------------------------------------------------------------------------

create or replace view v_unit_location with (security_invoker = on) as
select distinct on (m.unit_id)
  m.unit_id,
  m.id            as last_movement_id,
  m.movement_type as last_movement_type,
  m.moved_on      as last_moved_on,
  m.to_kind       as at_kind,
  m.to_id         as at_id,
  m.order_id      as last_order_id
from movement m
where m.unit_id is not null
order by m.unit_id, m.moved_on desc, m.created_at desc;

-- ---------------------------------------------------------------------------
-- Status of every unit.
--
-- Rule 2: a unit whose last movement delivered it to a customer is OUT. The expected return
-- date is not consulted and must never be. A unit is only back when a return movement says so.
--
-- Rule 3: this is status. unit.condition is a separate, hand-assessed axis and is carried
-- alongside rather than folded in.
-- ---------------------------------------------------------------------------

create or replace view v_unit_status with (security_invoker = on) as
select
  u.id            as unit_id,
  u.product_id,
  u.piece_no,
  u.condition,
  u.lifecycle,
  u.ownership,
  l.at_kind,
  l.at_id,
  l.last_moved_on,
  l.last_order_id,
  case
    when u.lifecycle = 'lost'      then 'lost'
    when u.lifecycle = 'retired'   then 'retired'
    when l.at_kind   = 'customer'  then 'out'
    when l.at_kind   = 'vendor'    then 'at_repair'
    when l.at_kind   = 'location'  then 'available'
    else 'not_recorded'
  end as status,
  -- Only counts as on-hand stock if it is physically at one of our own locations.
  (u.lifecycle = 'active' and l.at_kind = 'location') as on_hand,
  -- How long it has been sitting where it is. Feeds the overdue and dead-stock reports.
  (current_date - l.last_moved_on) as days_in_place
from unit u
left join v_unit_location l on l.unit_id = u.id;

-- ---------------------------------------------------------------------------
-- Units still out on an order.
-- Rule 9: an order cannot close while this returns anything for it.
-- ---------------------------------------------------------------------------

create or replace view v_order_outstanding_units with (security_invoker = on) as
select
  o.id                  as order_id,
  o.order_no,
  o.customer_id,
  o.expected_return_date,
  s.unit_id,
  s.product_id,
  s.piece_no,
  s.last_moved_on       as dispatched_on,
  greatest(current_date - o.expected_return_date, 0) as days_overdue
from rental_order o
join v_unit_status s
  on s.last_order_id = o.id
 and s.status = 'out'
where o.status not in ('cancelled');

-- ---------------------------------------------------------------------------
-- What is physically on hand, per product.
-- ---------------------------------------------------------------------------

create or replace view v_product_stock with (security_invoker = on) as
select
  p.id  as product_id,
  p.short_code,
  p.model_name,
  p.tracking_mode,
  count(u.id) filter (where u.lifecycle = 'active')                     as units_active,
  count(u.id) filter (where s.status = 'available')                     as units_on_hand,
  count(u.id) filter (where s.status = 'out')                           as units_out,
  count(u.id) filter (where s.status = 'at_repair')                     as units_at_repair,
  count(u.id) filter (where u.lifecycle = 'lost')                       as units_lost,
  count(u.id) filter (where u.lifecycle = 'retired')                    as units_retired
from product p
left join unit u          on u.product_id = p.id
left join v_unit_status s on s.unit_id = u.id
group by p.id, p.short_code, p.model_name, p.tracking_mode;

-- ---------------------------------------------------------------------------
-- Availability for a product over a date range.
--
-- Availability is DATE-LEVEL: a box due back on the 4th is not offered on the 4th, because
-- somebody physically has to go and collect it. Same-day turnaround is possible but requires
-- rental_order.availability_override, which is recorded rather than silent.
--
-- Two independent sources of unavailability, deliberately not double-counted:
--   1. Units physically out or at a repair shop right now (regardless of any date).
--   2. Quantity committed on CONFIRMED orders whose dates overlap the window. Once an order is
--      dispatched its units are physically out and counted by (1), so only 'confirmed' orders
--      are counted here.
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
as $$
  -- The CTE is committed_qty, not committed, because `committed` is also one of the RETURNS
  -- TABLE output columns and those are in scope inside the body as parameters. A real range
  -- table entry does win over a parameter here, so the shorter name resolved correctly, but it
  -- reads like a bug and invites a "fix" from whoever edits this next. Both CTEs are unfiltered
  -- aggregates with no GROUP BY, so each returns exactly one row even when the product has no
  -- units and no lines — that is what makes the cross join below return (id, 0, 0, 0) rather
  -- than no row at all. count(*) cannot be null and the sum is coalesced, so neither can the
  -- answer be null.
  with on_hand as (
    select count(*)::int as n
    from v_unit_status s
    where s.product_id = p_product_id
      and s.status = 'available'
  ),
  committed_qty as (
    select coalesce(sum(ol.qty), 0)::int as n
    from order_line ol
    join rental_order o on o.id = ol.order_id
    where ol.product_id = p_product_id
      and o.status = 'confirmed'
      and (p_exclude_order_id is null or o.id <> p_exclude_order_id)
      -- inclusive overlap: the return date is not a free day
      and o.out_date <= p_to
      and o.expected_return_date >= p_from
  )
  select
    p_product_id,
    on_hand.n,
    committed_qty.n,
    (on_hand.n - committed_qty.n)
  from on_hand, committed_qty;
$$;

comment on function fn_availability is
  'Date-level availability. Never consults expected_return_date to decide whether a dispatched unit is back — see CLAUDE.md rule 2.';

-- ---------------------------------------------------------------------------
-- Customer balance.
-- Rule 6: receivable and deposit held are two numbers and are never merged.
-- ---------------------------------------------------------------------------

create or replace view v_customer_balance with (security_invoker = on) as
select
  c.id as customer_id,
  c.name,
  c.business_name,
  -- Money the customer owes for work billed and due.
  coalesce(sum(
    case
      when le.state = 'due' and le.type in ('rental','transport','labour','misc','damage') then le.amount
      when le.state = 'due' and le.type in ('payment','discount','write_off','reversal')   then -le.amount
      else 0
    end
  ), 0) as receivable,
  -- Billed but not yet delivered — the forward book, shown separately on the portal.
  coalesce(sum(
    case when le.state = 'upcoming'
          and le.type in ('rental','transport','labour','misc','damage')
         then le.amount else 0 end
  ), 0) as upcoming,
  -- The customer's own money, held. A liability, never revenue.
  coalesce(sum(
    case
      when le.type = 'deposit_in'      then le.amount
      when le.type = 'deposit_out'     then -le.amount
      when le.type = 'deposit_forfeit' then -le.amount
      else 0
    end
  ), 0) as deposit_held
from customer c
left join ledger_entry le on le.customer_id = c.id
group by c.id, c.name, c.business_name;

-- ---------------------------------------------------------------------------
-- Utilisation. Needs no cost data at all, and is the number that says what to buy more of.
-- Days out is counted from actual dispatch and return movements, never from planned dates.
-- ---------------------------------------------------------------------------

create or replace view v_unit_utilisation with (security_invoker = on) as
with spans as (
  select
    d.unit_id,
    d.moved_on as out_on,
    (
      select min(r.moved_on)
      from movement r
      where r.unit_id = d.unit_id
        and r.movement_type = 'return'
        and r.moved_on >= d.moved_on
    ) as back_on
  from movement d
  where d.movement_type = 'dispatch'
    and d.unit_id is not null
),
owned as (
  select
    u.id as unit_id,
    coalesce(u.purchase_date, (select min(m.moved_on) from movement m where m.unit_id = u.id)) as owned_from
  from unit u
)
select
  u.id            as unit_id,
  u.product_id,
  u.piece_no,
  count(s.out_on)::int as times_hired,
  coalesce(sum( (coalesce(s.back_on, current_date) - s.out_on) + 1 ), 0)::int as days_out,
  greatest((current_date - o.owned_from) + 1, 1) as days_owned,
  round(
    100.0 * coalesce(sum( (coalesce(s.back_on, current_date) - s.out_on) + 1 ), 0)
          / greatest((current_date - o.owned_from) + 1, 1)
  , 1) as utilisation_pct
from unit u
join owned o on o.unit_id = u.id
left join spans s on s.unit_id = u.id
group by u.id, u.product_id, u.piece_no, o.owned_from;

-- ---------------------------------------------------------------------------
-- ROI per product.
--
-- Rental revenue less repair cost, over purchase cost. Transport, labour and misc charges are
-- job-level and are deliberately EXCLUDED — they cannot be attributed to a product, and
-- including them would flatter heavy gear, which travels most.
-- ---------------------------------------------------------------------------

create or replace view v_product_roi with (security_invoker = on) as
with revenue as (
  select ol.product_id, coalesce(sum(ol.line_total), 0) as rental_revenue
  from order_line ol
  join rental_order o on o.id = ol.order_id
  where o.status <> 'cancelled'
    and ol.is_subhired = false
  group by ol.product_id
),
repairs as (
  select u.product_id, coalesce(sum(rj.actual_cost), 0) as repair_cost
  from repair_job rj
  join unit u on u.id = rj.unit_id
  group by u.product_id
),
cost as (
  select
    u.product_id,
    coalesce(sum(coalesce(u.purchase_cost, p.default_purchase_cost)), 0) as purchase_cost,
    count(*) filter (where u.purchase_cost is null and p.default_purchase_cost is null) as units_missing_cost
  from unit u
  join product p on p.id = u.product_id
  where u.lifecycle <> 'retired'
  group by u.product_id
)
select
  p.id as product_id,
  p.short_code,
  p.model_name,
  coalesce(r.rental_revenue, 0)                as rental_revenue,
  coalesce(rp.repair_cost, 0)                  as repair_cost,
  coalesce(c.purchase_cost, 0)                 as purchase_cost,
  coalesce(c.units_missing_cost, 0)            as units_missing_cost,
  (coalesce(r.rental_revenue,0) - coalesce(rp.repair_cost,0)) as net_return,
  case
    when coalesce(c.purchase_cost, 0) = 0 then null
    else round(
      100.0 * (coalesce(r.rental_revenue,0) - coalesce(rp.repair_cost,0))
            / c.purchase_cost
    , 1)
  end as roi_pct
from product p
left join revenue r  on r.product_id  = p.id
left join repairs rp on rp.product_id = p.id
left join cost c     on c.product_id  = p.id;

comment on view v_product_roi is
  'roi_pct is NULL where no purchase cost is recorded. units_missing_cost says how much of the answer is missing — never present a NULL ROI as zero.';
