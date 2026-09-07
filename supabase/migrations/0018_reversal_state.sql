-- 0018_reversal_state.sql
-- A reversal can now undo the thing it reverses.
--
-- docs/decisions.md accepts reversal entries as the price of posting revenue on order confirmation:
-- "cancellations and short dispatches need reversal entries". They worked for half of it.
--
-- v_customer_balance.upcoming counted only the billed types at `state = 'upcoming'`, and `reversal`
-- is not a billed type — so a reversal posted against an upcoming charge moved NEITHER number.
-- Posting it as `due` instead reduced `receivable`, which had never been increased, driving it
-- negative. Measured while trying to undo three stray rows written by a review agent: an `upcoming`
-- of 43,060.00 could not be reduced by any ledger entry the schema permitted, and deleting was
-- refused by the append-only guard, correctly. The only way out was to truncate and re-seed, which
-- is available on a development fixture and will never be available on a real customer's account.
--
-- Three changes, and the third is the one that makes the other two auditable.

-- ---------------------------------------------------------------------------
-- 1 · reverses_entry_id — what undid what.
--
-- A ledger where reversals float free is a ledger where nobody can answer "why is this figure what
-- it is". Naming the entry makes the pair readable, and it is what lets the trigger below enforce
-- the state and the amount without guessing.
-- ---------------------------------------------------------------------------

alter table ledger_entry
  add column if not exists reverses_entry_id uuid references ledger_entry(id) on delete restrict;

create index if not exists idx_ledger_reverses on ledger_entry(reverses_entry_id);

comment on column ledger_entry.reverses_entry_id is
  'For a reversal, the billed entry it undoes. Required on every reversal, must belong to the same customer, and cannot be over-reversed — enforced by fn_reversal_matches_target.';

-- ---------------------------------------------------------------------------
-- 2 · A reversal carries the state of the entry it reverses, and cannot exceed it.
--
-- The state is SET from the target rather than merely checked. A reversal whose state disagrees
-- with its target is never a thing anyone means to write, and validating it would only produce an
-- error message where a correct value was already knowable.
--
-- The amount ceiling is slightly beyond the letter of the brief, and it is what makes "neither
-- goes negative" true rather than merely true of the cases tested: without it, reversing 5,000 of a
-- 3,000 charge drives its bucket below zero exactly as posting a reversal as `due` used to.
-- Partial reversals are allowed and can be repeated — a short dispatch is the ordinary case — so
-- the ceiling is the target's amount less whatever has already been reversed against it.
-- ---------------------------------------------------------------------------

create or replace function fn_reversal_matches_target()
returns trigger
language plpgsql
set search_path = public, pg_temp
as $$
declare
  v_type      text;
  v_state     text;
  v_amount    numeric(12,2);
  v_customer  uuid;
  v_already   numeric(12,2);
  v_left      numeric(12,2);
begin
  if new.type <> 'reversal' then
    -- Only a reversal may name a target. A payment pointing at a charge would read as a reversal
    -- to anyone scanning the column and would be counted as neither.
    if new.reverses_entry_id is not null then
      raise exception
        'only a reversal may name the entry it reverses; this is a %. Record the correction as a reversal, or leave reverses_entry_id empty.',
        new.type;
    end if;
    return new;
  end if;

  if new.reverses_entry_id is null then
    raise exception
      'a reversal must name the entry it reverses (reverses_entry_id). A reversal that floats free cannot be checked against what it undoes, and leaves nobody able to say why a balance is what it is.';
  end if;

  select le.type, le.state, le.amount, le.customer_id
    into v_type, v_state, v_amount, v_customer
  from ledger_entry le
  where le.id = new.reverses_entry_id;

  if v_type is null then
    raise exception 'the entry this reversal names does not exist.';
  end if;

  -- Same customer. Reversing across accounts would move two balances and reconcile neither.
  if v_customer is distinct from new.customer_id then
    raise exception
      'this reversal is on one customer''s account but names an entry on another''s. A reversal belongs to the same ledger as the charge it undoes.';
  end if;

  -- Only a billed charge can be reversed. Reversing a payment is a refund, reversing a deposit is
  -- a deposit_out — both are their own entry types with their own arithmetic and their own guards.
  if v_type not in ('rental','transport','labour','misc','damage') then
    raise exception
      'a % entry cannot be reversed. Only a billed charge can — rental, transport, labour, misc or damage. To return money take a payment back out, and to return a deposit record a deposit_out, which is checked against what is actually held.',
      v_type;
  end if;

  select coalesce(sum(le.amount), 0) into v_already
  from ledger_entry le
  where le.reverses_entry_id = new.reverses_entry_id
    and le.type = 'reversal'
    and (tg_op = 'INSERT' or le.id <> new.id);

  v_left := v_amount - v_already;
  if new.amount > v_left then
    raise exception
      'that reverses more than is left. The charge was %, % has already been reversed, so at most % can be. Reversing more than was charged drives the balance below zero, which is not a state this business can be in (CLAUDE.md rule 6).',
      to_char(v_amount, 'FM999,999,990.00'),
      to_char(v_already, 'FM999,999,990.00'),
      to_char(v_left, 'FM999,999,990.00');
  end if;

  -- THE FIX. Same state as the target, set rather than checked: an `upcoming` charge is undone in
  -- the upcoming column, a `due` charge in the receivable column, and neither can be undone in the
  -- wrong one.
  new.state := v_state;
  return new;
end $$;

drop trigger if exists ledger_reversal_matches_target on ledger_entry;
create trigger ledger_reversal_matches_target
  before insert or update on ledger_entry
  for each row execute function fn_reversal_matches_target();

-- ---------------------------------------------------------------------------
-- 3 · v_customer_balance counts a reversal in whichever bucket its state names.
--
-- Previously `reversal` appeared only in the `due` arm, so an upcoming reversal was arithmetic
-- nobody performed. Now each bucket subtracts the reversals that belong to it.
--
-- Note what is deliberately still absent from `upcoming`: payment, discount and write_off. You
-- cannot pay for a job that has not gone out, and a discount on an unbilled job is a change to the
-- agreed rate rather than a ledger entry. If one is ever written at `state = 'upcoming'` it is
-- counted nowhere, which is the safe direction — but it is also the next thing to guard if the
-- posting mechanism is ever rebuilt.
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
  -- Billed but not yet delivered — the forward book, shown separately on the portal so a wedding
  -- customer opening it three weeks early sees a booking rather than a debt. A reversal at this
  -- state now subtracts here, which is the whole point of 0018.
  coalesce(sum(
    case
      when le.state = 'upcoming' and le.type in ('rental','transport','labour','misc','damage') then le.amount
      when le.state = 'upcoming' and le.type = 'reversal'                                       then -le.amount
      else 0
    end
  ), 0) as upcoming,
  -- The customer's own money, held. A liability, never revenue (rule 6).
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

comment on view v_customer_balance is
  'Receivable, upcoming and deposit_held as three separate figures that are never added together (CLAUDE.md rule 6). A reversal subtracts from whichever bucket its own state names — 0018; before that it could only affect `due`, so an upcoming charge could not be undone at all. Deposits are the customer''s own money and sit on their own axis.';
