-- 0019_movement_correction.sql
-- A movement can now be undone without being deleted.
--
-- This is 0018's shape applied to the movement ledger, and for the same reason. There, a charge
-- posted in error could not be removed — DELETE on ledger_entry is blocked — so a `reversal` row
-- names the entry it undoes and v_customer_balance nets it out. Here the identical problem exists
-- one table over and has no answer at all: DELETE on `movement` is blocked by 0004 and 0007, and
-- UPDATE by the append-only guard, so a return recorded in error is permanent and uncorrectable.
--
-- WHY IT MATTERS NOW. The return screen is about to grow a one-tap "All 6 back". That is the right
-- thing to build — gear comes back at 2am after a wedding and a system filled in from memory on
-- Sunday is wrong in the same direction, only later. But without this migration the tap is a
-- one-way door: mark six back while holding five, and the sixth reads AVAILABLE while it sits in a
-- hall. That is CLAUDE.md rule 2 arriving from the inside, with the system's confidence behind it,
-- and the only route out today is to record a `dispatch` that never physically happened — a lie
-- written into the ledger every other number in this database is derived from.
--
-- Five changes. The fourth is the one that makes the other four safe.

-- ---------------------------------------------------------------------------
-- 1 · The movement type, and what it points at.
--
-- A correction row is an ANNOTATION. It is never location-bearing: it does not move anything, it
-- says that something recorded as having moved did not. from_kind/to_kind are forced to 'none' by
-- the trigger below, which the existing movement_from_kind_check already allows.
-- ---------------------------------------------------------------------------

alter table movement drop constraint if exists movement_movement_type_check;
alter table movement add constraint movement_movement_type_check
  check (movement_type in ('intake','dispatch','return','transfer',
                           'repair_out','repair_in','write_off','found','correction'));

alter table movement
  add column if not exists corrects_movement_id uuid references movement(id) on delete restrict;

create index if not exists idx_movement_corrects on movement(corrects_movement_id);

comment on column movement.corrects_movement_id is
  'For a correction, the movement it undoes. Required on every correction, must be the most recent EFFECTIVE movement for that piece (or for that product on that order, for counted stock), and cannot be corrected twice — enforced by fn_correction_matches_target. Read through v_movement_effective, never by filtering movement by hand.';

-- ---------------------------------------------------------------------------
-- 2 · The guards.
--
-- The state is SET rather than checked wherever the right value is already knowable, which is
-- 0018's rule: an error message where a correct value could have been written is a worse screen.
--
-- THE MOST-RECENT RULE, and what "most recent" means. Correcting mid-history makes every derived
-- span ambiguous — v_unit_location picks the last movement, v_unit_utilisation pairs dispatches
-- with the next return — and it turns an append-only ledger into an editable one through the back
-- door. So a correction may only ever name the CURRENT TIP.
--
-- "Most recent" is measured over v_movement_effective, not over the raw table, and that is a
-- deliberate reading rather than a shortcut. Measured over the raw table the rule is a dead end:
-- after any correction the newest row for that piece is the correction itself, which can never be
-- a valid target, so nothing on that piece could ever be corrected again.
--
-- So the guarantee is precisely this: YOU MAY PEEL THE TIP, YOU MAY NEVER REACH INTO THE MIDDLE.
-- Correct a return while it is the last thing that happened and it comes off; try to correct the
-- dispatch underneath it while that return still stands and you are refused. Correct the return
-- first and the dispatch becomes the tip, at which point it can be peeled too — one visible,
-- audited row per step, never a silent edit, and never a jump past something that is still
-- standing. That distinction is easy to mistake: the first draft of this migration's probe used
-- piece 3's own dispatch as its "mid-history" control and it was correctly ACCEPTED, because by
-- then it was the tip. The control now uses a different piece whose return is still standing.
--
-- The cost of allowing the peel is that a piece's whole history can be walked back one row at a
-- time. The cost of forbidding it is worse and concrete: mark a piece back that never went out and
-- then find the dispatch was wrong too, and the piece is stuck reading `out` for ever with no
-- honest way to say so. Corrections do not hide anything — that is what makes the peel safe and
-- it is the reason 5 exists.
-- ---------------------------------------------------------------------------

create or replace function fn_correction_matches_target()
returns trigger
language plpgsql
set search_path = public, pg_temp
as $$
declare
  t          movement%rowtype;
  v_tip      uuid;
  v_left     int;
  v_already  int;
begin
  if new.movement_type <> 'correction' then
    -- Only a correction may name a target. Any other row pointing at one would read as a
    -- correction to anyone scanning the column and would be counted as neither.
    if new.corrects_movement_id is not null then
      raise exception
        'only a correction may name the movement it undoes; this is a %. Record the mistake as a correction, or leave corrects_movement_id empty.',
        new.movement_type;
    end if;
    return new;
  end if;

  if new.corrects_movement_id is null then
    raise exception
      'a correction must name the movement it undoes (corrects_movement_id). A correction that floats free cannot be netted out of anything, and leaves nobody able to say why a piece is where the screen says it is.';
  end if;

  select * into t from movement where id = new.corrects_movement_id;
  if t.id is null then
    raise exception 'the movement this correction names does not exist.';
  end if;

  -- A correction is not itself a movement of goods and has nothing to undo.
  if t.movement_type = 'correction' then
    raise exception
      'a correction cannot correct another correction. If the first correction was itself a mistake, record the movement again as a fresh entry — that is what actually happened.';
  end if;

  select count(*)::int into v_already
  from movement c
  where c.movement_type = 'correction' and c.corrects_movement_id = new.corrects_movement_id;
  if v_already > 0 then
    raise exception
      'that movement has already been corrected. Correcting it twice would net it out twice and drive the arithmetic below zero.';
  end if;

  -- ---- the tip test ----
  if t.unit_id is not null then
    -- Numbered piece: the tip is that piece's own last effective movement. Scoping per piece is
    -- what makes "All 6 back" correctable at all — six returns written in one transaction share a
    -- created_at, but each belongs to a different piece, so none of them ties with another.
    select e.id into v_tip
    from v_movement_effective e
    where e.unit_id = t.unit_id
    order by e.moved_on desc, e.created_at desc, e.id desc
    limit 1;

    -- A piece must never be left with no movement at all: intake writes the opening one precisely
    -- so that no unit exists without a location (docs/structure.md, form 3). Correcting the last
    -- one standing would make v_unit_location return no row and v_unit_status read
    -- `not_recorded` — a piece that exists and is nowhere.
    select count(*)::int into v_left from v_movement_effective e where e.unit_id = t.unit_id;
    if v_left <= 1 then
      raise exception
        'this is the only movement left on that piece, and correcting it would leave the piece with no location at all. Record where it actually is instead — an intake or a transfer.';
    end if;
  else
    -- Counted and used-up stock (rule 13): there are no piece numbers, so the tip is scoped to the
    -- product on the same job. Pool arithmetic is a SUM and is order-independent, so nothing here
    -- is ambiguous the way a unit's span is — the rule is narrower because it only has to stop the
    -- ledger becoming editable, not to keep a span unambiguous.
    select e.id into v_tip
    from v_movement_effective e
    where e.product_id = t.product_id
      and e.unit_id is null
      and e.order_id is not distinct from t.order_id
    order by e.moved_on desc, e.created_at desc, e.id desc
    limit 1;
  end if;

  if v_tip is distinct from t.id then
    raise exception
      'only the most recent movement can be corrected, and that one is not it — something has happened since. Correcting mid-history would leave every date span and every location derived from it ambiguous. Undo what came after first, or record what actually happened as a new movement.';
  end if;

  -- ---- what the correction row itself is ----
  -- Set, not checked. A correction annotates one movement; every one of these values is already
  -- knowable from the target, and asking a caller to repeat them is asking it to get one wrong.
  new.unit_id    := t.unit_id;
  new.product_id := t.product_id;
  new.order_id   := t.order_id;
  new.qty        := t.qty;          -- descriptive only; every view ignores a correction's numbers
  new.from_kind  := 'none';
  new.from_id    := null;
  new.to_kind    := 'none';
  new.to_id      := null;
  return new;
end $$;

-- INSERT only. UPDATE on movement is already refused outright by fn_movement_is_append_only, so
-- corrects_movement_id cannot be repointed after the fact and there is no update path to guard.
drop trigger if exists movement_correction_matches_target on movement;
create trigger movement_correction_matches_target
  before insert on movement
  for each row execute function fn_correction_matches_target();

-- ---------------------------------------------------------------------------
-- 3 · v_movement_effective — the ONE place that knows what still counts.
--
-- 0008 exists because four separate paths each re-derived pooled quantities and each got it wrong
-- in its own way. The same mistake is available here: six views and a function read `movement`,
-- and six hand-written "and not corrected" clauses would be six chances to forget one — and the
-- one that got forgotten would report a piece as available while it sat in a hall.
--
-- So nothing below reads `movement` for arithmetic ever again. It reads this.
-- ---------------------------------------------------------------------------

create or replace view v_movement_effective with (security_invoker = on) as
select m.*
from movement m
where m.movement_type <> 'correction'
  and not exists (
    select 1 from movement c
    where c.movement_type = 'correction' and c.corrects_movement_id = m.id
  );

comment on view v_movement_effective is
  'Movements that still count: the correction rows themselves are dropped, and so is anything a correction names. Every derived view and fn_availability read this rather than `movement`. A path that reads `movement` directly for arithmetic is a bug — it will report a corrected dispatch as if the van had actually left (0019).';

-- ---------------------------------------------------------------------------
-- 4 · Everything derived now reads it.
--
-- Column lists are unchanged, so these are replaces and the dependency chain
-- v_unit_location -> v_unit_status -> v_order_outstanding -> v_order_fulfilment survives intact.
-- ---------------------------------------------------------------------------

create or replace view v_unit_location with (security_invoker = on) as
select distinct on (unit_id)
  unit_id,
  id           as last_movement_id,
  movement_type as last_movement_type,
  moved_on     as last_moved_on,
  to_kind      as at_kind,
  to_id        as at_id,
  order_id     as last_order_id
from v_movement_effective m
where unit_id is not null
order by unit_id, moved_on desc, created_at desc;

create or replace view v_pool_stock with (security_invoker = on) as
with pooled_movement as (
  select m.product_id, m.movement_type, m.qty, m.from_kind, m.to_kind
  from v_movement_effective m
  join product p on p.id = m.product_id
  where p.tracking_mode in ('pool','consumable') and m.unit_id is null
),
ledger as (
  select
    pm.product_id,
    coalesce(sum(pm.qty) filter (where pm.to_kind = 'location'), 0)::int as qty_in,
    coalesce(sum(pm.qty) filter (where pm.from_kind = 'location'), 0)::int as qty_out,
    coalesce(sum(pm.qty) filter (where pm.to_kind = 'customer'), 0)::int
      - coalesce(sum(pm.qty) filter (where pm.from_kind = 'customer'), 0)::int as qty_at_customer,
    coalesce(sum(pm.qty) filter (where pm.to_kind = 'vendor'), 0)::int
      - coalesce(sum(pm.qty) filter (where pm.from_kind = 'vendor'), 0)::int as qty_at_vendor,
    coalesce(sum(pm.qty) filter (where pm.movement_type = 'write_off'), 0)::int as qty_written_off
  from pooled_movement pm
  group by pm.product_id
),
figures as (
  select
    p.id as product_id, p.short_code, p.model_name, p.tracking_mode,
    coalesce(p.pool_qty, 0) as qty_opening,
    coalesce(l.qty_in, 0) as qty_in,
    coalesce(l.qty_out, 0) as qty_out,
    coalesce(l.qty_at_customer, 0) as qty_at_customer,
    coalesce(l.qty_at_vendor, 0) as qty_at_vendor,
    coalesce(l.qty_written_off, 0) as qty_written_off
  from product p
  left join ledger l on l.product_id = p.id
  where p.tracking_mode in ('pool','consumable')
),
positions as (
  select
    f.*,
    f.qty_opening + f.qty_in - f.qty_out as qty_on_hand_raw,
    greatest(f.qty_opening + f.qty_in - f.qty_out + f.qty_at_customer + f.qty_at_vendor, 0) as qty_owned
  from figures f
)
select
  product_id, short_code, model_name, tracking_mode,
  qty_opening, qty_in, qty_out, qty_on_hand_raw,
  least(greatest(qty_on_hand_raw, 0), qty_owned) as qty_on_hand,
  qty_at_customer, qty_at_vendor, qty_written_off, qty_owned,
  qty_on_hand_raw < 0 or qty_on_hand_raw > qty_owned or qty_at_customer < 0 or qty_at_vendor < 0
    as has_ledger_error
from positions pos;

create or replace view v_order_outstanding with (security_invoker = on) as
with unit_rows as (
  -- Inherits the correction through v_unit_status -> v_unit_location, which now reads effective.
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
  greatest(current_date - o.expected_return_date, 0) as days_overdue
from (select * from unit_rows union all select * from pool_rows) x
join rental_order o on o.id = x.order_id
join product p on p.id = x.product_id;

create or replace view v_order_fulfilment with (security_invoker = on) as
with line_qty as (
  select ol.order_id, ol.product_id, sum(ol.qty)::int as qty_ordered
  from order_line ol group by ol.order_id, ol.product_id
),
moved as (
  select
    m.order_id, m.product_id,
    count(*) filter (where m.movement_type = 'dispatch' and m.unit_id is not null)::int as pieces_dispatched,
    coalesce(sum(m.qty) filter (where m.movement_type = 'dispatch' and m.unit_id is null), 0)::int as pooled_dispatched,
    count(*) filter (where m.movement_type = 'return' and m.unit_id is not null)::int as pieces_returned,
    coalesce(sum(m.qty) filter (where m.movement_type = 'return' and m.unit_id is null), 0)::int as pooled_returned
  from v_movement_effective m
  where m.order_id is not null and m.movement_type in ('dispatch','return')
  group by m.order_id, m.product_id
),
pairs as (
  select order_id, product_id from line_qty
  union
  select order_id, product_id from moved
),
per_product as (
  select
    x.order_id,
    coalesce(lq.qty_ordered, 0) as qty_ordered,
    case p.tracking_mode when 'unit' then coalesce(mv.pieces_dispatched, 0)
                         else coalesce(mv.pooled_dispatched, 0) end as qty_dispatched,
    case p.tracking_mode when 'unit' then coalesce(mv.pieces_returned, 0)
                         else coalesce(mv.pooled_returned, 0) end as qty_returned
  from pairs x
  join product p on p.id = x.product_id
  left join line_qty lq on lq.order_id = x.order_id and lq.product_id = x.product_id
  left join moved mv on mv.order_id = x.order_id and mv.product_id = x.product_id
),
per_order as (
  select
    pp.order_id,
    sum(pp.qty_ordered)::int as qty_ordered,
    sum(pp.qty_dispatched)::int as qty_dispatched,
    sum(pp.qty_returned)::int as qty_returned,
    sum(greatest(pp.qty_ordered - pp.qty_dispatched, 0))::int as qty_undispatched
  from per_product pp group by pp.order_id
),
at_customer as (
  select oo.order_id, sum(oo.qty_outstanding)::int as qty_outstanding
  from v_order_outstanding oo group by oo.order_id
)
select
  o.id as order_id, o.order_no, o.customer_id, o.status as order_status,
  coalesce(po.qty_ordered, 0) as qty_ordered,
  coalesce(po.qty_dispatched, 0) as qty_dispatched,
  coalesce(po.qty_returned, 0) as qty_returned,
  coalesce(ac.qty_outstanding, 0) as qty_outstanding,
  coalesce(po.qty_undispatched, 0) as qty_undispatched,
  case
    when coalesce(po.qty_dispatched, 0) = 0 then 'nothing_dispatched'
    when coalesce(ac.qty_outstanding, 0) > 0 and coalesce(po.qty_returned, 0) > 0 then 'part_returned'
    when coalesce(po.qty_undispatched, 0) > 0 then 'part_dispatched'
    when coalesce(ac.qty_outstanding, 0) > 0 then 'fully_out'
    else 'all_returned'
  end as fulfilment_state
from rental_order o
left join per_order po on po.order_id = o.id
left join at_customer ac on ac.order_id = o.id;

create or replace view v_unit_utilisation with (security_invoker = on) as
with spans as (
  select
    d.unit_id, d.moved_on as out_on,
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
  coalesce(sum(coalesce(s.back_on, current_date) - s.out_on + 1), 0)::int as days_out,
  greatest(current_date - o.owned_from + 1, 1) as days_owned,
  round(100.0 * coalesce(sum(coalesce(s.back_on, current_date) - s.out_on + 1), 0)::numeric
        / greatest(current_date - o.owned_from + 1, 1)::numeric, 1) as utilisation_pct
from unit u
join owned o on o.unit_id = u.id
left join spans s on s.unit_id = u.id
group by u.id, u.product_id, u.piece_no, o.owned_from;

-- fn_availability: only its `dispatched` CTE touches the table. Everything else it reads
-- (v_unit_status, v_pool_stock) is already corrected upstream.
create or replace function fn_availability(
  p_product_id uuid, p_from date, p_to date, p_exclude_order_id uuid default null
) returns table (product_id uuid, units_on_hand int, committed int, available int)
language plpgsql stable
set search_path = public, pg_temp
as $$
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
    where r.out_date >= current_date
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
end $$;

-- ---------------------------------------------------------------------------
-- 5 · A correction must be VISIBLE. A silent gap is worse than the mistake.
--
-- v_movement_effective is deliberately blind to corrections, which is right for arithmetic and
-- wrong for a person. Somebody looking at a piece has to be able to see that a return was recorded
-- and then taken back, by whom and when — otherwise the history has a hole in it and the operator
-- is left doubting the screen rather than reading it.
--
-- This is also what the equipment-item screen needs: where it is, who has it, and what has
-- happened to it.
-- ---------------------------------------------------------------------------

create or replace view v_unit_history with (security_invoker = on) as
select
  m.id                as movement_id,
  m.unit_id,
  m.product_id,
  m.movement_type,
  m.moved_on,
  m.created_at,
  m.from_kind, m.from_id, m.to_kind, m.to_id,
  m.order_id,
  o.order_no,
  m.condition_at_move,
  m.notes,
  m.corrects_movement_id,
  -- Was this row taken back? The screen shows "returned (corrected)", never nothing at all.
  (c.id is not null)  as is_corrected,
  c.id                as corrected_by_id,
  c.moved_on          as corrected_on,
  c.notes             as correction_reason,
  -- And is this row itself the annotation rather than a movement of goods?
  (m.movement_type = 'correction') as is_correction
from movement m
left join movement c
  on c.movement_type = 'correction' and c.corrects_movement_id = m.id
left join rental_order o on o.id = m.order_id
where m.unit_id is not null;

comment on view v_unit_history is
  'Every movement ever recorded against a numbered piece, INCLUDING corrected ones and the corrections themselves, flagged rather than hidden. This is the human view; v_movement_effective is the arithmetic one. Never use this to compute a location or a count (0019).';

-- ---------------------------------------------------------------------------
-- 6 · Permissions. Same shape as every other view: security_invoker means RLS on the underlying
-- tables decides, and anon is refused outright rather than relying on that.
-- ---------------------------------------------------------------------------

revoke all on table v_movement_effective from anon;
revoke all on table v_unit_history from anon;
grant select on table v_movement_effective to authenticated;
grant select on table v_unit_history to authenticated;

-- NOTE, for whoever builds the permission pass: writing a correction should be gated on a
-- `movement.correct` permission rather than on being an operator. There is no permission table to
-- hook into yet — 0017 gives one undifferentiated operator role — so today any operator may write
-- one. Recorded in docs/backlog.md rather than faked with a policy that grants everybody the
-- right and pretends otherwise.
