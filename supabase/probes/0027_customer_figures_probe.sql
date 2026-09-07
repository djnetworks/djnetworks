-- 0027 · A HIDDEN BALANCE READS NULL, NOT ZERO.
--
-- Rule 14 in one sentence: a gated view returns zero ROWS, not zero rupees. v_customer_figures
-- joins its money through v_customer_balance_visible, so an account without ledger.view must see
-- the job counts and a BLANK where the money goes. If it sees 0.00 instead, every customer appears
-- to owe nothing — which looks like good news and is therefore never chased.
--
-- BOTH DIRECTIONS, because a view that returns null to everybody would pass the first half of this
-- probe perfectly. The owner pass is the false positive control: it must read a real, non-null,
-- non-zero receivable for the same customer the staff pass reads blank. One identity, two answers,
-- same row.
--
-- Rolls itself back, including the throwaway auth.users row.
begin;

create temporary table _p (ord serial, who text, fact text, val text) on commit drop;
grant all on table _p to authenticated;
grant usage, select on all sequences in schema pg_temp to authenticated;

do $setup$
declare v_owner uuid; v_staff uuid := gen_random_uuid(); v_cust uuid;
begin
  select user_id into v_owner from operator
   where coalesce((permissions->>'admin.team')::boolean, false) limit 1;
  if v_owner is null then
    raise exception 'No operator holding admin.team. The control half of this probe needs an identity that CAN see money, or a pass proves nothing.';
  end if;

  -- THE CUSTOMER THE WHOLE PROBE TURNS ON: one who actually owes something. Testing against a
  -- customer with a zero balance cannot tell "hidden" from "settled" — which is the exact
  -- confusion being probed (rule 16: reproduce the shape that fails).
  select b.customer_id into v_cust
    from v_customer_balance b where b.receivable > 0
    order by b.receivable desc limit 1;
  if v_cust is null then
    raise exception 'No customer with receivable > 0 in this database. Seed one before running this probe: against a settled account, null and 0.00 are indistinguishable and the probe would pass while the bug was present.';
  end if;

  insert into auth.users (id, instance_id, aud, role, email, encrypted_password,
                          email_confirmed_at, created_at, updated_at)
  values (v_staff, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
          'probe-figures@example.invalid', '', now(), now(), now());

  -- The man at the van: he sends out and records returns. He must never see what anybody owes.
  perform fn_admin_set_operator(v_staff, 'Probe Figures',
    '{"sendout.write": true, "returns.write": true}'::jsonb, true);

  create temporary table _ids (owner uuid, staff uuid, cust uuid) on commit drop;
  insert into _ids values (v_owner, v_staff, v_cust);
end $setup$;

do $run$
declare
  ids record; n int; v_recv numeric; v_dep numeric; v_jobs int; v_null boolean;
begin
  select * into ids from _ids;

  -- ---- CONTROL: the owner, who holds ledger.view -------------------------------------------
  set local role authenticated;
  perform set_config('request.jwt.claims',
    json_build_object('sub', ids.owner, 'role', 'authenticated')::text, true);

  select f.receivable, f.deposit_held, f.jobs_total
    into v_recv, v_dep, v_jobs
    from v_customer_figures f where f.customer_id = ids.cust;

  insert into _p (who, fact, val) values
    ('owner', 'receivable',   coalesce(v_recv::text, 'NULL')),
    ('owner', 'deposit_held', coalesce(v_dep::text,  'NULL')),
    ('owner', 'jobs_total',   coalesce(v_jobs::text, 'NULL'));

  reset role;
  perform set_config('request.jwt.claims', null, true);

  if v_recv is null then
    raise exception 'CONTROL FAILED. Expected: the owner reads a real receivable for this customer. Actual: null. The probe cannot tell a working gate from a view that is blank for everybody, so the staff half below would pass meaninglessly.';
  end if;
  if v_recv = 0 then
    raise exception 'CONTROL FAILED. Expected: a customer owing more than zero. Actual: 0.00. Against a settled account, hidden and settled look identical.';
  end if;

  -- ---- THE TEST: the same row, read by somebody without ledger.view --------------------------
  set local role authenticated;
  perform set_config('request.jwt.claims',
    json_build_object('sub', ids.staff, 'role', 'authenticated')::text, true);

  select count(*)::int into n from v_customer_figures;

  select f.receivable, f.deposit_held, f.jobs_total
    into v_recv, v_dep, v_jobs
    from v_customer_figures f where f.customer_id = ids.cust;

  insert into _p (who, fact, val) values
    ('staff', 'rows_visible', n::text),
    ('staff', 'receivable',   coalesce(v_recv::text, 'NULL')),
    ('staff', 'deposit_held', coalesce(v_dep::text,  'NULL')),
    ('staff', 'jobs_total',   coalesce(v_jobs::text, 'NULL'));

  reset role;
  perform set_config('request.jwt.claims', null, true);

  -- The row must still be there. Rule 14 hides the MONEY, not the customer: a screen that loses
  -- the whole customer teaches the operator that the list is unreliable.
  if v_jobs is null then
    raise exception 'Expected: the staff account still reads this customer''s job counts. Actual: no row at all. The gate is meant to blank the money, not delete the customer.';
  end if;

  if v_recv is not null then
    raise exception 'RULE 14 BROKEN. Expected: receivable is NULL for an account without ledger.view. Actual: %. If that is 0.00 then every customer reads as owing nothing and nobody is ever chased.', v_recv;
  end if;
  if v_dep is not null then
    raise exception 'RULE 14 BROKEN. Expected: deposit_held is NULL for an account without ledger.view. Actual: %. A deposit is the customer''s money being held; reporting zero of it is reporting that we hold none.', v_dep;
  end if;

  raise notice '0027 probe ok: owner reads a real balance, staff reads NULL for the same customer, and the customer row survives.';
end $run$;

select ord, who, fact, val from _p order by ord;

rollback;
