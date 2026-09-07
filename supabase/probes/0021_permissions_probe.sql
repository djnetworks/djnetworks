-- 0021 · BOTH DIRECTIONS, PER TABLE, WITH NUMBERS.
--
-- "A policy that refuses everybody looks identical to one that works." So every table is tested
-- twice: an identity that SHOULD be able to read and write, and one that should not. A test that
-- only ever shows refusals proves nothing.
--
-- Rolls itself back, including the two throwaway auth.users rows the staff identity needs.
begin;

create temporary table _probe (
  ord serial, who text, tbl text, reads int, wrote text
) on commit drop;
-- The probe switches role to `authenticated` to ask its questions as a real signed-in person, and
-- then has to write its own answers down. Granting on the scratch table only.
grant all on table _probe to authenticated;
grant usage, select on all sequences in schema pg_temp to authenticated;

do $setup$
declare v_owner uuid; v_staff uuid := gen_random_uuid(); v_stranger uuid := gen_random_uuid();
begin
  select user_id into v_owner from operator
   where coalesce((permissions->>'admin.team')::boolean,false) limit 1;

  -- Throwaway identities. auth.users has a foreign key from operator, so the staff row needs one;
  -- the stranger deliberately gets an auth account and NO operator row, which is exactly what a
  -- self-registration would have produced before invite-only.
  insert into auth.users (id, instance_id, aud, role, email, encrypted_password,
                          email_confirmed_at, created_at, updated_at)
  values (v_staff, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
          'probe-staff@example.invalid', '', now(), now(), now()),
         (v_stranger, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
          'probe-stranger@example.invalid', '', now(), now(), now());

  -- The man who carries the boxes: he may send out and record returns, and nothing else.
  perform fn_admin_set_operator(v_staff, 'Probe Staff',
    '{"sendout.write": true, "returns.write": true}'::jsonb, true);

  create temporary table _ids (owner uuid, staff uuid, stranger uuid) on commit drop;
  insert into _ids values (v_owner, v_staff, v_stranger);
end $setup$;

do $run$
declare
  ids record; r record; v_who text; uid uuid; n int; msg text;
  v_cust uuid; v_prod uuid; v_unit uuid; v_order uuid; v_cat uuid; v_loc uuid;
begin
  select * into ids from _ids;
  select id into v_cust  from customer limit 1;
  select id into v_prod  from product where tracking_mode='unit' limit 1;
  select id into v_unit  from unit limit 1;
  select id into v_order from rental_order limit 1;
  select id into v_cat   from category limit 1;
  select id into v_loc   from location limit 1;

  -- READ PASS FIRST, for all three, before anybody writes anything. Run interleaved, the owner's
  -- own probe inserts showed up in the staff read counts one row later and made every number look
  -- like an off-by-one instead of a fact.
  for v_who, uid in select * from (values ('owner', ids.owner), ('staff', ids.staff), ('stranger', ids.stranger)) v(a,b) loop
    execute 'set local role authenticated';
    perform set_config('request.jwt.claims',
      json_build_object('sub', uid, 'role', 'authenticated')::text, true);

    -- ---- READS -------------------------------------------------------------
    for r in select * from (values
        ('rental_order'),('order_line'),('order_charge'),('product'),('product_image'),
        ('category'),('subcategory'),('unit'),('location'),('vendor'),('repair_job'),
        ('customer'),('ledger_entry'),('app_setting'),('discount_tier'),('movement'),('operator')
      ) t(tbl) loop
      execute format('select count(*)::int from %I', r.tbl) into n;
      insert into _probe (who, tbl, reads) values (v_who, r.tbl, n);
    end loop;
    execute 'select count(*)::int from v_customer_balance_visible' into n;
    insert into _probe (who, tbl, reads) values (v_who, 'v_customer_balance_visible', n);
    execute 'select count(*)::int from v_product_roi_visible' into n;
    insert into _probe (who, tbl, reads) values (v_who, 'v_product_roi_visible', n);
    execute 'select count(*)::int from v_unit_utilisation_visible' into n;
    insert into _probe (who, tbl, reads) values (v_who, 'v_unit_utilisation_visible', n);

    execute 'reset role';
    perform set_config('request.jwt.claims', null, true);
  end loop;

  -- WRITE PASS.
  for v_who, uid in select * from (values ('owner', ids.owner), ('staff', ids.staff), ('stranger', ids.stranger)) v(a,b) loop
    execute 'set local role authenticated';
    perform set_config('request.jwt.claims',
      json_build_object('sub', uid, 'role', 'authenticated')::text, true);

    -- ---- WRITES ------------------------------------------------------------
    -- Each is a minimal VALID row, so a refusal can only be the policy.
    for r in select * from (values
      ('rental_order',  format('insert into rental_order (order_no,customer_id,out_date,expected_return_date,days) values (%L,%L,current_date,current_date,1)', 'PROBE-'||v_who, v_cust)),
      ('order_line',    format('insert into order_line (order_id,product_id,qty,days,base_rate,discount_pct,agreed_rate,line_total) values (%L,%L,1,1,10,0,10,10)', v_order, v_prod)),
      ('order_charge',  format('insert into order_charge (order_id,type,description,amount) values (%L,''misc'',''probe'',1)', v_order)),
      ('product',       format('insert into product (short_code,category_id,model_name,tracking_mode) values (%L,%L,''probe'',''unit'')', 'PRB-'||left(v_who,3), v_cat)),
      ('product_image', format('insert into product_image (product_id,storage_path) values (%L,''probe/x.jpg'')', v_prod)),
      ('category',      format('insert into category (name) values (%L)', 'probe-'||v_who)),
      ('subcategory',   format('insert into subcategory (category_id,name) values (%L,%L)', v_cat, 'probe-'||v_who)),
      ('unit',          format('insert into unit (product_id,piece_no) values (%L,9%s)', v_prod, 100+length(v_who))),
      ('location',      format('insert into location (name,type) values (%L,''godown'')', 'probe-'||v_who)),
      ('vendor',        format('insert into vendor (name) values (%L)', 'probe-'||v_who)),
      ('repair_job',    format('insert into repair_job (unit_id,date_sent) values (%L,current_date)', v_unit)),
      ('customer',      format('insert into customer (name,whatsapp) values (%L,''9000000000'')', 'probe-'||v_who)),
      ('ledger_entry',  format('insert into ledger_entry (customer_id,type,amount,state) values (%L,''misc'',1,''due'')', v_cust)),
      ('app_setting',   format('insert into app_setting (key,value) values (%L,''1''::jsonb)', 'probe-'||v_who)),
      ('discount_tier', format('insert into discount_tier (min_days,discount_pct) values (%s,1)', 900+length(v_who))),
      ('operator',      format('insert into operator (user_id,permissions) values (%L,''{"admin.team":true}''::jsonb)', gen_random_uuid()))
    ) t(tbl, stmt) loop
      begin
        execute r.stmt;
        update _probe p set wrote = 'wrote' where p.who = v_who and p.tbl = r.tbl;
      exception when others then
        get stacked diagnostics msg = message_text;
        update _probe p set wrote = case when msg ilike '%row-level security%' or msg ilike '%violates row-level%'
                                         then 'REFUSED' else 'refused:' || left(msg, 18) end
         where p.who = v_who and p.tbl = r.tbl;
      end;
    end loop;

    -- movement, by type, because the key depends on the row
    for r in select * from (values
      ('movement/dispatch',   format('insert into movement (movement_type,unit_id,product_id,qty,from_kind,from_id,to_kind,to_id,order_id,moved_on) values (''dispatch'',%L,%L,1,''location'',%L,''customer'',%L,%L,current_date)', v_unit, (select product_id from unit where id=v_unit), v_loc, v_cust, v_order)),
      ('movement/return',     format('insert into movement (movement_type,unit_id,product_id,qty,from_kind,from_id,to_kind,to_id,moved_on) values (''return'',%L,%L,1,''customer'',%L,''location'',%L,current_date)', v_unit, (select product_id from unit where id=v_unit), v_cust, v_loc)),
      ('movement/transfer',   format('insert into movement (movement_type,unit_id,product_id,qty,from_kind,from_id,to_kind,to_id,moved_on) values (''transfer'',%L,%L,1,''location'',%L,''location'',%L,current_date)', v_unit, (select product_id from unit where id=v_unit), v_loc, v_loc)),
      -- A DIFFERENT unit per identity, and its OWN tip, ordered exactly as fn_correction_matches_target
      -- orders (moved_on, created_at, id). Sharing one target made the second and third attempts fail
      -- on 0019's tip rule before RLS was ever consulted — a refusal that proves nothing about
      -- permissions. Each identity now gets a target that is genuinely correctable.
      ('movement/correction', format('insert into movement (movement_type,corrects_movement_id,qty,from_kind,to_kind,moved_on,notes) values (''correction'',%L,1,''none'',''none'',current_date,''probe reason here'')',
        (select m.id from v_movement_effective m
          where m.unit_id = (select u.id from unit u order by u.piece_no offset (case v_who when 'owner' then 0 when 'staff' then 1 else 2 end) limit 1)
          order by m.moved_on desc, m.created_at desc, m.id desc limit 1)))
    ) t(tbl, stmt) loop
      begin
        execute r.stmt;
        insert into _probe (who, tbl, wrote) values (v_who, r.tbl, 'wrote');
      exception when others then
        get stacked diagnostics msg = message_text;
        insert into _probe (who, tbl, wrote) values (v_who, r.tbl,
          case when msg ilike '%row-level security%' then 'REFUSED' else 'refused:' || left(msg, 22) end);
      end;
    end loop;

    execute 'reset role';
    perform set_config('request.jwt.claims', null, true);
  end loop;
end $run$;

reset role;

select rpad(tbl, 28) || ' | ' ||
       rpad(coalesce(max(reads) filter (where who='owner')::text,'-') || '/' || coalesce(max(wrote) filter (where who='owner'),'-'), 22) || ' | ' ||
       rpad(coalesce(max(reads) filter (where who='staff')::text,'-') || '/' || coalesce(max(wrote) filter (where who='staff'),'-'), 22) || ' | ' ||
       coalesce(max(reads) filter (where who='stranger')::text,'-') || '/' || coalesce(max(wrote) filter (where who='stranger'),'-')
  as "table                        | OWNER reads/writes    | STAFF reads/writes     | STRANGER"
from _probe group by tbl order by min(ord);

rollback;
