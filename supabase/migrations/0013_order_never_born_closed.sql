-- 0013_order_never_born_closed.sql
-- An order cannot be born `closed`.
--
-- 0009 enforced rule 9 with a BEFORE UPDATE trigger: an order cannot MOVE to `closed` while
-- v_order_outstanding returns anything for it. That guard has always had a door beside it —
-- `insert into rental_order (..., status) values (..., 'closed')` never touches an UPDATE and so
-- never touches the trigger. Verification measured the consequence: insert a closed order, dispatch
-- three boxes against it, and the result is `order_status = closed, qty_outstanding = 3,
-- fulfilment_state = fully_out`. Gear at a customer on a job the system considers finished, which
-- is precisely the state rule 9 exists to make impossible.
--
-- It was theoretical while the only writer was a seed file. The order screen makes it reachable:
-- a form that posts a status field, a bad default, or an import that carries a status column
-- straight from a spreadsheet, and the hole is open.
--
-- THE FIX IS THE NARROW ONE. An order is born `confirmed` — docs/decisions.md, "No quote stage":
-- an order exists once the job is agreed, and at that moment nothing has gone out and nothing has
-- come back. Closing is a decision taken later, and it goes through the UPDATE path where 0009's
-- guard is waiting.
--
-- `cancelled` is deliberately still allowed at insert. Backdating a job that was called off before
-- anything moved is a real thing to record, it has no outstanding stock by construction, and
-- supabase/seed/dev_seed.sql relies on it. Only `closed` is refused, because only `closed` carries
-- the promise that everything came back.

create or replace function fn_order_is_born_confirmed()
returns trigger
language plpgsql
set search_path = public, pg_temp
as $$
begin
  if new.status = 'closed' then
    raise exception
      'order % cannot be created already closed. An order is born confirmed and is closed later, once every piece is back — closing is checked against v_order_outstanding by a BEFORE UPDATE trigger (CLAUDE.md rule 9), and an INSERT walks straight past it. Create the order as ''confirmed'', record the dispatches and the returns, then close it.',
      new.order_no;
  end if;
  return new;
end $$;

drop trigger if exists rental_order_born_confirmed on rental_order;
create trigger rental_order_born_confirmed
  before insert on rental_order
  for each row execute function fn_order_is_born_confirmed();
