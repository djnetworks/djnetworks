-- 0026_today_is_local.sql
-- The database's idea of today was a different day from the app's.
--
-- Every date this system stores is a CALENDAR day on the Indian calendar: movement.moved_on comes
-- from the phone via todayLocal(), out_date and expected_return_date are typed by a person in
-- Ahmedabad. But `current_date` on the server is UTC, and between midnight and 05:30 IST those are
-- different days.
--
-- So for five and a half hours every morning — which is exactly when a van is loaded — four views
-- and one function compared a UTC today against an Indian calendar date and were off by one:
--
--   v_unit_status.days_in_place    a piece moved this morning read (-1 days)
--   v_order_outstanding.days_overdue  clamped at 0, so it under-reported by a day
--   v_unit_utilisation.days_out    a piece still out counted one day short
--   v_customer_figures             longest_unpaid_days one day short
--   fn_availability                consumables committed "from today" used yesterday's today
--
-- Found by opening a piece that had just been moved to the van and reading "(-1 days)". CLAUDE.md's
-- date convention already covers the client half of this; this is the server half, and the same
-- mistake.
--
-- ONE FUNCTION, so this cannot drift back. Nothing in this database should write `current_date`
-- against a stored date again.

create or replace function fn_today()
returns date
language sql
stable
set search_path = public, pg_temp
as $$ select (now() at time zone 'Asia/Kolkata')::date $$;

comment on function fn_today() is
  'Today on the calendar this business keeps. NOT current_date, which is UTC and names yesterday between midnight and 05:30 IST — the hours a van is loaded in. Every comparison against a stored date uses this (0026).';

revoke execute on function fn_today() from public, anon;
grant execute on function fn_today() to authenticated;

-- ---------------------------------------------------------------------------
-- The four views and the function, each with only its date source changed.
-- ---------------------------------------------------------------------------

create or replace view v_unit_status with (security_invoker = on) as
select u.id as unit_id, u.product_id, u.piece_no, u.condition, u.lifecycle, u.ownership,
  l.at_kind, l.at_id, l.last_moved_on, l.last_order_id,
  case
    when u.lifecycle = 'lost' then 'lost'
    when u.lifecycle = 'retired' then 'retired'
    when l.at_kind = 'customer' then 'out'
    when l.at_kind = 'vendor' then 'at_repair'
    when l.at_kind = 'location' then 'available'
    else 'not_recorded'
  end as status,
  u.lifecycle = 'active' and l.at_kind = 'location' as on_hand,
  fn_today() - l.last_moved_on as days_in_place
from unit u
left join v_unit_location l on l.unit_id = u.id;

create or replace view v_order_outstanding with (security_invoker = on) as
with unit_rows as (
  select s.last_order_id as order_id, s.product_id, s.unit_id, s.piece_no,
         1 as qty_outstanding, s.last_moved_on as dispatched_on
  from v_unit_status s
  where s.status = 'out' and s.last_order_id is not null
),
pool_rows as (
  select
    m.order_id, m.product_id, null::uuid as unit_id, null::int as piece_no,
    (coalesce(sum(m.qty) filter (where m.to_kind = 'customer'), 0)
     - coalesce(sum(m.qty) filter (where m.from_kind = 'customer'), 0))::int as qty_outstanding,
    min(m.moved_on) filter (where m.to_kind = 'customer') as dispatched_on
  from v_movement_effective m
  join product p_1 on p_1.id = m.product_id
  where p_1.tracking_mode = 'pool' and m.unit_id is null and m.order_id is not null
  group by m.order_id, m.product_id
  having (coalesce(sum(m.qty) filter (where m.to_kind = 'customer'), 0)
          - coalesce(sum(m.qty) filter (where m.from_kind = 'customer'), 0)) > 0
)
select
  o.id as order_id, o.order_no, o.status as order_status, o.customer_id,
  o.out_date, o.expected_return_date,
  x.product_id, p.short_code, p.model_name, p.tracking_mode,
  x.unit_id, x.piece_no, x.qty_outstanding, x.dispatched_on,
  greatest(fn_today() - o.expected_return_date, 0) as days_overdue
from (select * from unit_rows union all select * from pool_rows) x
join rental_order o on o.id = x.order_id
join product p on p.id = x.product_id;

create or replace view v_unit_utilisation with (security_invoker = on) as
with spans as (
  select d.unit_id, d.moved_on as out_on,
    (select min(r.moved_on) from v_movement_effective r
      where r.unit_id = d.unit_id and r.movement_type = 'return' and r.moved_on >= d.moved_on) as back_on
  from v_movement_effective d
  where d.movement_type = 'dispatch' and d.unit_id is not null
),
owned as (
  select u_1.id as unit_id,
         coalesce(u_1.purchase_date,
                  (select min(m.moved_on) from v_movement_effective m where m.unit_id = u_1.id)) as owned_from
  from unit u_1
)
select
  u.id as unit_id, u.product_id, u.piece_no,
  count(s.out_on)::int as times_hired,
  coalesce(sum(coalesce(s.back_on, fn_today()) - s.out_on + 1), 0)::int as days_out,
  greatest(fn_today() - o.owned_from + 1, 1) as days_owned,
  round(100.0 * coalesce(sum(coalesce(s.back_on, fn_today()) - s.out_on + 1), 0)::numeric
        / greatest(fn_today() - o.owned_from + 1, 1)::numeric, 1) as utilisation_pct
from unit u
join owned o on o.unit_id = u.id
left join spans s on s.unit_id = u.id
group by u.id, u.product_id, u.piece_no, o.owned_from;

create or replace view v_customer_figures with (security_invoker = on) as
with jobs as (
  select o.customer_id,
         count(*)::int as jobs_total,
         count(*) filter (where o.status = 'closed')::int as jobs_closed,
         count(*) filter (where o.status = 'cancelled')::int as jobs_cancelled,
         max(o.out_date) as last_job_on
  from rental_order o group by o.customer_id
),
late_returns as (
  select o.customer_id, count(*)::int as returned_late
  from rental_order o
  where exists (
    select 1 from v_movement_effective m
    where m.order_id = o.id and m.movement_type = 'return'
      and m.moved_on > o.expected_return_date)
  group by o.customer_id
),
overdue_now as (
  select oo.customer_id, count(distinct oo.order_id)::int as jobs_overdue_now
  from v_order_outstanding oo where oo.days_overdue > 0 group by oo.customer_id
),
oldest_unpaid as (
  select le.customer_id, min(le.entry_date) as oldest_due_on
  from ledger_entry le
  where le.state = 'due' and le.type in ('rental','transport','labour','misc','damage')
  group by le.customer_id
)
select
  c.id as customer_id, c.name, c.business_name,
  coalesce(j.jobs_total, 0) as jobs_total,
  coalesce(j.jobs_closed, 0) as jobs_closed,
  coalesce(j.jobs_cancelled, 0) as jobs_cancelled,
  j.last_job_on,
  coalesce(lr.returned_late, 0) as returned_late,
  coalesce(od.jobs_overdue_now, 0) as jobs_overdue_now,
  case when b.receivable > 0 and ou.oldest_due_on is not null
       then (fn_today() - ou.oldest_due_on)::int end as longest_unpaid_days,
  b.receivable as receivable,
  b.deposit_held as deposit_held
from customer c
left join jobs j on j.customer_id = c.id
left join late_returns lr on lr.customer_id = c.id
left join overdue_now od on od.customer_id = c.id
left join oldest_unpaid ou on ou.customer_id = c.id
left join v_customer_balance_visible b on b.customer_id = c.id;

-- fn_availability: one comparison, same source.
CREATE OR REPLACE FUNCTION public.fn_availability(p_product_id uuid, p_from date, p_to date, p_exclude_order_id uuid DEFAULT NULL::uuid)
 RETURNS TABLE(product_id uuid, units_on_hand integer, committed integer, available integer)
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'public', 'pg_temp'
AS $function$
begin
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

  return query
  with prod as (
    select coalesce((select p.tracking_mode from product p where p.id = p_product_id), 'missing') as track_mode
  ),
  unit_on_hand as (
    select count(*)::int as n from v_unit_status s
    where s.product_id = p_product_id and s.status = 'available'
  ),
  pool_on_hand as (
    select coalesce((select ps.qty_on_hand from v_pool_stock ps where ps.product_id = p_product_id), 0)::int as n
  ),
  line_totals as (
    select ol.order_id, sum(ol.qty)::int as qty_ordered
    from order_line ol
    where ol.product_id = p_product_id and ol.is_subhired = false
    group by ol.order_id
  ),
  dispatched as (
    -- 0019: effective, not raw. A dispatch that was corrected never happened, so its quantity is
    -- still owed by the order and must go on committing stock — reading `movement` here would
    -- report the remainder as already gone and quietly free up gear nobody has sent.
    select
      m.order_id,
      count(*) filter (where m.unit_id is not null)::int as pieces_dispatched,
      coalesce(sum(m.qty) filter (where m.unit_id is null), 0)::int as qty_dispatched
    from v_movement_effective m
    where m.product_id = p_product_id and m.movement_type = 'dispatch' and m.order_id is not null
    group by m.order_id
  ),
  remainder as (
    select
      o.out_date, o.expected_return_date,
      greatest(
        lt.qty_ordered - case prod.track_mode
          when 'unit' then coalesce(d.pieces_dispatched, 0)
          else coalesce(d.qty_dispatched, 0) end, 0)::int as qty_remaining
    from line_totals lt
    join rental_order o on o.id = lt.order_id
    cross join prod
    left join dispatched d on d.order_id = lt.order_id
    where o.status not in ('cancelled','closed')
      and (p_exclude_order_id is null or o.id <> p_exclude_order_id)
  ),
  committed_window as (
    select coalesce(sum(r.qty_remaining), 0)::int as n from remainder r
    where r.out_date <= p_to and r.expected_return_date >= p_from
  ),
  committed_outbound as (
    select coalesce(sum(r.qty_remaining), 0)::int as n from remainder r
    -- fn_today(), not current_date: a consumable booked for TODAY stopped being
    -- committed five and a half hours before the day was over (0026).
    where r.out_date >= fn_today()
  ),
  answer as (
    select
      case prod.track_mode
        when 'unit' then unit_on_hand.n when 'pool' then pool_on_hand.n
        when 'consumable' then pool_on_hand.n else 0 end as on_hand_n,
      case prod.track_mode
        when 'unit' then committed_window.n when 'pool' then committed_window.n
        when 'consumable' then committed_outbound.n else 0 end as committed_n
    from prod, unit_on_hand, pool_on_hand, committed_window, committed_outbound
  )
  select p_product_id, answer.on_hand_n, answer.committed_n, (answer.on_hand_n - answer.committed_n)
  from answer;
end $function$;
