-- 0007_guards_and_availability.sql
-- Four holes, all of them already open.
--
--   1. rental_order and unit can be hard-deleted. movement has been guarded since 0004; these
--      two never were, and every order passes through the state where the delete succeeds.
--   2. movement_unit_or_qty is a constraint that cannot fail while its comment claims it
--      enforces something. Replaced by a trigger that enforces the rule for real.
--   3. fn_availability only understands numbered boxes. Every pooled and consumable product has
--      been reporting zero — and, the moment an order exists, a negative number.
--   4. Three functions resolve their table names against the caller's search_path.
--
-- Nothing here stores anything that can be counted (rule 10), and nothing here adds a delete
-- path (rule 12).

-- ---------------------------------------------------------------------------
-- 1 · Orders and units are never deleted.
--
-- Rule 12. The movement ledger has had this guard since 0004 and these two tables did not, which
-- is not a theoretical gap. An order sits in `confirmed` from the moment the job is agreed until
-- the van is loaded — days, often weeks — and in that whole window a DELETE goes through
-- cleanly. order_line and order_charge are `on delete cascade`, so the lines and the transport
-- charge go with it. ledger_entry.order_id is `on delete set null`, so the rental charge and the
-- deposit do NOT go with it: they stay on the customer's balance with order_id = null, money
-- owed against a job that no longer exists anywhere in the system. There is one operator and
-- nobody to catch it, and what he would eventually see is a receivable that ties to nothing.
--
-- An order that already has movements is refused today, but only by accident. movement.order_id
-- is `on delete set null`, that SET NULL is an UPDATE on movement, and the append-only trigger
-- rejects it. The operator gets an error about the movement ledger that never mentions the
-- order, on some orders and not others, depending on whether the van has left. A guard that
-- fires half the time and explains the wrong thing is not a guard.
--
-- unit is mostly protected already for the same accidental reason — movement.unit_id and
-- repair_job.unit_id are both `on delete restrict` — but a unit created by an intake that failed
-- before writing its opening movement has neither, and deletes. And when the restrict does fire
-- it reports a foreign key violation, which tells the operator nothing about retiring.
--
-- UPDATE stays allowed on both tables, and must. Cancelling an order and retiring a unit are
-- updates; they are the escape hatches these two messages point at.
-- ---------------------------------------------------------------------------

create or replace function fn_rental_order_is_never_deleted()
returns trigger
language plpgsql
set search_path = public, pg_temp
as $$
begin
  raise exception
    'order % is never deleted — cancel it instead, by setting status = ''cancelled'' (CLAUDE.md rule 12). Deleting it would cascade away its lines and its charges and leave its ledger entries sitting on the customer balance with order_id = null.',
    old.order_no;
end $$;

drop trigger if exists rental_order_no_delete on rental_order;
create trigger rental_order_no_delete
  before delete on rental_order
  for each row execute function fn_rental_order_is_never_deleted();

create or replace function fn_unit_is_never_deleted()
returns trigger
language plpgsql
set search_path = public, pg_temp
as $$
declare
  v_code text;
begin
  -- Product first, then the number. A bare piece number identifies nothing (rule 8) — that is
  -- the whole reason every screen is product-first — and an error message reading "piece 3"
  -- would be exactly as useless as chachu's stickers are on their own.
  select p.short_code into v_code from product p where p.id = old.product_id;

  raise exception
    'unit % piece % is never deleted — retire it instead, by setting lifecycle = ''retired'' or ''lost'' (CLAUDE.md rule 12). Its piece number dies with it and is never reissued (rule 4); a replacement box takes the next free number. Deleting the row would strand its movements and its repair jobs and quietly change every utilisation and ROI figure that was ever read.',
    coalesce(v_code, '(unknown product)'), old.piece_no;
end $$;

drop trigger if exists unit_no_delete on unit;
create trigger unit_no_delete
  before delete on unit
  for each row execute function fn_unit_is_never_deleted();

-- ---------------------------------------------------------------------------
-- 2 · movement_unit_or_qty is dropped and replaced by a trigger that enforces what it claimed.
--
-- The constraint read `check (unit_id is not null or qty >= 1)` under a comment saying
-- "unit-tracked movements name a unit; pooled ones use qty". It said that and did nothing: qty
-- is `not null` and separately carries `check (qty >= 1)`, so the right-hand side of that OR is
-- true on every row that is capable of existing, and the constraint could never reject anything.
-- That is worse than having no constraint, because the next person to read the table believes
-- the rule is held somewhere and stops looking.
--
-- The real rule needs product.tracking_mode, which a CHECK cannot reach — a CHECK sees only its
-- own row — so it becomes a trigger. Three things are enforced:
--
--   a. A movement of a `unit` product must name a unit. This is the one that matters.
--      v_unit_location filters on `unit_id is not null`, so a speaker dispatch written without a
--      unit_id moves nothing at all: the box still reads as sitting in the godown while it is at
--      a wedding, and v_unit_status will happily offer it for hire from there. That is rule 2's
--      six-out-five-back bug arriving through a different door, and there is no second data
--      entry person to notice the row.
--
--   b. A movement of a `pool` or `consumable` product must NOT name a unit. Those products have
--      no numbered pieces, so a unit_id on one is either a typo or a piece belonging to something
--      else — and either way it drags a real box's recorded location around behind a bundle of
--      cables.
--
--   c. If a movement names a unit, that unit must belong to the movement's own product. Nothing
--      stopped movement(unit_id = <a speaker>, product_id = <a cable>) before, and it breaks both
--      readings at once: v_unit_location keys on unit_id and would relocate the speaker, while
--      the pooled arithmetic added in section 3 below sums movement.qty by movement.product_id
--      and would count that speaker as cable stock.
--
-- Every legitimate movement shape passes. Pooled and consumable intake, transfer, dispatch,
-- return, write_off, found and repair_out/repair_in all carry qty with unit_id null, which is (b).
-- Unit-tracked intake, dispatch, return, transfer, repair_out, repair_in, write_off and found all
-- carry the piece, which is (a) — bulk intake writes one movement per unit, not one row with
-- qty = 6, and sub-hire is a line-level flag that writes no movement at all.
--
-- INSERT only, deliberately, and this was measured rather than assumed. UPDATE on movement is
-- rejected outright by movement_no_update from 0004, so a BEFORE UPDATE branch here could never
-- do any useful work — it would only put a second BEFORE trigger on the same event. Postgres
-- fires BEFORE row triggers in alphabetical order by trigger name, so which of the two messages
-- the operator sees would be decided by spelling: declared "before insert or update" under the
-- name below, `update movement set unit_id = null` reports the append-only message; rename the
-- trigger to anything sorting before `movement_no_update` and the same statement reports the
-- tracking-mode message instead. Both are true and one is beside the point, and nobody should
-- have to know the alphabet to predict which one they get. DELETE is refused by the 0004 trigger
-- for the same reason and needs nothing here either.
--
-- Existing rows are not revalidated and none need to be: movement holds zero rows on this
-- database today. If a product's tracking_mode is ever changed from `unit` to `pool` after its
-- boxes already have histories, those histories stay exactly as written (rule 12) and only new
-- movements are held to the new mode.
-- ---------------------------------------------------------------------------

alter table movement drop constraint if exists movement_unit_or_qty;

create or replace function fn_movement_matches_tracking_mode()
returns trigger
language plpgsql
set search_path = public, pg_temp
as $$
declare
  v_mode         text;
  v_code         text;
  v_unit_product uuid;
begin
  select p.tracking_mode, p.short_code
    into v_mode, v_code
  from product p
  where p.id = new.product_id;

  if v_mode is null then
    -- The foreign key guarantees the product row exists, so arriving here means it is not
    -- readable from this session. Fail closed: a movement whose tracking mode cannot be checked
    -- is a movement whose effect on every derived view cannot be predicted.
    raise exception
      'movement names product % but that product cannot be read from this session, so the unit/qty rule cannot be checked — refusing the write rather than guessing.',
      new.product_id;
  end if;

  if v_mode = 'unit' and new.unit_id is null then
    raise exception
      'product % is unit-tracked, so this % must name the piece that moved. A movement with no unit_id is invisible to v_unit_location: the box would keep reading as on hand at its old location while it sits somewhere else (CLAUDE.md rules 1 and 2).',
      v_code, new.movement_type;
  end if;

  if v_mode in ('pool','consumable') and new.unit_id is not null then
    raise exception
      'product % is %-tracked and has no numbered pieces, so this % must carry qty and leave unit_id null. A unit_id here would move some other product''s box (CLAUDE.md rule 1).',
      v_code, v_mode, new.movement_type;
  end if;

  if new.unit_id is not null then
    select u.product_id into v_unit_product from unit u where u.id = new.unit_id;

    if v_unit_product is distinct from new.product_id then
      raise exception
        'this movement is filed under product % but names a piece that belongs to a different product. v_unit_location keys on unit_id and the pooled counts key on product_id, so the two would disagree about the same physical box (CLAUDE.md rule 1).',
        v_code;
    end if;
  end if;

  return new;
end $$;

drop trigger if exists movement_tracking_mode on movement;
create trigger movement_tracking_mode
  before insert on movement
  for each row execute function fn_movement_matches_tracking_mode();

-- ---------------------------------------------------------------------------
-- 3 · Availability for a product over a date range, for all three tracking modes.
--
-- Since 0003 this function counted rows in v_unit_status and nothing else, which is right for a
-- numbered box and wrong for everything else. A `pool` product has no unit rows to count, so it
-- reported units_on_hand = 0 forever; put a single confirmed order on it and it reported a
-- NEGATIVE available while two hundred cables sat on the shelf. The catalogue is still empty so
-- nothing has been misquoted yet, but the first cable line on the first order would have done it,
-- and the screen would have been lying with complete confidence.
--
-- Availability is DATE-LEVEL: a box due back on the 4th is not offered on the 4th, because
-- somebody physically has to go and collect it. Same-day turnaround is possible but requires
-- rental_order.availability_override, which is recorded rather than silent.
--
-- Common to every mode: `committed` counts only orders in status 'confirmed'. Once an order is
-- dispatched its stock is physically gone and is already absent from on-hand, and counting it in
-- both places would halve the fleet on paper.
--
-- unit
--   Unchanged from 0003, deliberately, down to the rows it counts. on_hand is the number of
--   pieces whose LAST movement put them at one of our own locations, so a unit at a repair shop
--   leaves availability with no extra rule. expected_return_date is not consulted and never will
--   be: a unit with a dispatch and no matching return is out, whatever the date says (rule 2).
--   Six boxes went out, five came back, and the sixth was offered for hire while it sat in a
--   hall. That is the bug this line refuses to reintroduce.
--
-- pool
--   Nothing is numbered, so on-hand is arithmetic over the ledger: pool_qty less what has gone
--   out and not come back. The dispatch/return pairing is scoped to `unit_id is null` because
--   that is the pooled side of the ledger — a numbered piece is already counted by the unit
--   branch and must not be counted a second time here.
--
-- consumable
--   Fog fluid, tape and batteries are charged and never come back, so there is nothing to pair a
--   dispatch with and no date filter that would mean anything: everything ever dispatched is
--   simply gone. committed is 0 for the same reason, and that is a real trade-off, written down
--   here rather than left to be discovered:
--
--     TENSION, KNOWINGLY ACCEPTED. With committed = 0, a confirmed order for 50 bottles does not
--     reduce availability until it is dispatched, so the same 50 bottles can be promised to two
--     customers three weeks apart and nothing objects. docs/decisions.md lists "refusing a
--     double-booking instead of warning about it" as one of the things bought by building an
--     application instead of a spreadsheet, and this branch does not deliver that for
--     consumables. It is what the owner asked for and it is what is implemented. If it bites,
--     the fix is to count confirmed lines whose out_date has not yet passed — a consumable is
--     committed on the way out, not held over a window — and it belongs in a migration of its
--     own with the owner's agreement, not a quiet edit to this one.
--
-- Never NULL, in any column, in any mode. pool_qty is nullable on product, so it is coalesced to
-- zero: a pooled product whose quantity has not been entered yet reads as "none available",
-- which is a safe lie, where a NULL would travel into the caller's arithmetic and come out the
-- other side as a blank on a screen. Each CTE is an unfiltered aggregate with no GROUP BY, so
-- each returns exactly one row even when the product owns nothing at all — that is what makes
-- the cross join answer (id, 0, 0, 0) for a product_id that does not exist rather than returning
-- no row, which a caller doing a plain join would read as "no answer" and render as blank.
--
-- `available` is allowed to go negative and is deliberately not clamped. Over-commitment is a
-- real state and the operator needs to see how far over he is, not a zero that reads like
-- "just sold out".
--
-- The SET search_path below stops the planner inlining this function into a calling query. It
-- was never going to inline a five-CTE body usefully, and an explicit search_path on anything
-- reachable through PostgREST is not optional.
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
    -- Exactly one row, always, including for a product_id that does not exist — the two scalar
    -- subqueries return NULL and the coalesces turn that into ('missing', 0), which falls to the
    -- zero branch below. 'missing' is a sentinel here and is never a value of tracking_mode.
    select
      coalesce((select p.tracking_mode from product p where p.id = p_product_id), 'missing') as track_mode,
      coalesce((select p.pool_qty      from product p where p.id = p_product_id), 0)::int    as qty_owned
  ),
  unit_on_hand as (
    -- Numbered pieces physically at one of our own locations. Nothing here reads a date.
    select count(*)::int as n
    from v_unit_status s
    where s.product_id = p_product_id
      and s.status = 'available'
  ),
  pool_net_out as (
    -- Pooled stock gone and not yet back. Scoped to unit_id is null: this is the pooled ledger,
    -- and a numbered piece belongs to unit_on_hand above.
    select coalesce(sum(
             case m.movement_type
               when 'dispatch' then  m.qty
               when 'return'   then -m.qty
             end
           ), 0)::int as n
    from movement m
    where m.product_id = p_product_id
      and m.unit_id is null
      and m.movement_type in ('dispatch','return')
  ),
  consumable_issued as (
    -- Everything ever issued, with no date filter and no return to net off, because a consumable
    -- that left the godown is not coming back. Unscoped by unit_id on purpose: however it was
    -- recorded, it is gone.
    select coalesce(sum(m.qty), 0)::int as n
    from movement m
    where m.product_id = p_product_id
      and m.movement_type = 'dispatch'
  ),
  committed_qty as (
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
  answer as (
    select
      case prod.track_mode
        when 'unit'       then unit_on_hand.n
        when 'pool'       then prod.qty_owned - pool_net_out.n
        when 'consumable' then prod.qty_owned - consumable_issued.n
        else 0                                     -- product does not exist
      end as on_hand_n,
      case prod.track_mode
        when 'unit' then committed_qty.n
        when 'pool' then committed_qty.n
        else 0                                     -- consumable (see the tension above), missing
      end as committed_n
    from prod, unit_on_hand, pool_net_out, consumable_issued, committed_qty
  )
  select
    p_product_id,
    answer.on_hand_n,
    answer.committed_n,
    (answer.on_hand_n - answer.committed_n)
  from answer;
$$;

comment on function fn_availability is
  'Date-level availability for all three tracking modes. Never consults expected_return_date to decide whether a dispatched unit is back (CLAUDE.md rule 2). Consumables report committed = 0 and can therefore be promised twice — see the comment block above the definition in 0007.';

-- ---------------------------------------------------------------------------
-- 4 · An explicit search_path on every function in public.
--
-- A function with no search_path setting resolves its table names against whatever the caller's
-- search_path happens to be at the time. On a database reachable through PostgREST that is not a
-- theoretical concern: it is how a function gets pointed at a table that is not the one its
-- author meant, and it is why the Supabase security advisor flags every one of these. Not one of
-- them is security definer, so none is a privilege escalation today — but fn_availability is
-- callable over the API and the trigger functions run on every write to their tables, so all six
-- get pinned. pg_temp goes last so a temporary object can never shadow a real one.
--
-- The three guard functions written above and fn_availability carry the setting in their own
-- definitions. The two carried over from 0004 and 0006 are pinned with ALTER FUNCTION rather
-- than by pasting their bodies into this file: two copies of the same body in two migrations is
-- how the copies drift, and the next person to edit one of them will edit the wrong one.
--
-- ALTER FUNCTION has no IF EXISTS. Both functions are created by applied migrations, so a re-run
-- of this file is still a no-op.
-- ---------------------------------------------------------------------------

alter function fn_movement_is_append_only()    set search_path = public, pg_temp;
alter function fn_sync_primary_product_image() set search_path = public, pg_temp;
