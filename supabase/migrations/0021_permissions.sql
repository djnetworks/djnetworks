-- 0021_permissions.sql
-- Authenticated stops meaning "may do everything".
--
-- 0017 made membership of `operator` the thing every policy tests, which stopped a stranger who
-- self-registers from reading anything. It did not distinguish between the two people who will
-- actually hold accounts: the owner, and the man who carries the boxes. Today they are the same
-- policy, so the labourer who is given a login to record a return can also read every customer's
-- ledger, delete nothing but rewrite anything, and — since 0019 — undo a movement.
--
-- THE MODEL is Maitri's, which runs this in production:
--
--   · permissions is JSONB on the operator row, with GRANULAR keys. Granular in the database,
--     grouped into module toggles in the UI — nobody should have to tick eleven boxes.
--   · ONE choke point. Maitri routes every action through requireActionPermission() and its rule
--     is that an action missing from the map is unprotected. This app has no admin Edge Function,
--     so the equivalent is RLS, and the choke point is fn_has_permission(key) — called by EVERY
--     policy and by nothing else. The DO block below builds the policies from a MAP, and then
--     asserts that no table with RLS is missing from it. A table nobody remembered is the way this
--     goes wrong, and it cannot go wrong silently.
--   · UI hiding is convenience. It is never the boundary.
--   · A `grant select` to `authenticated` grants it to EVERY signed-in person, staff included.
--     That is how Maitri's catalogue was exposed once, and it is why 0017 exists here.
--
-- THE ELEVEN KEYS
--
--   orders.write       create and change orders, lines and charges
--   sendout.write      record a dispatch
--   returns.write      record a return
--   movement.correct   undo a movement (0019). NOT something the man carrying boxes can do.
--   products.write     the catalogue: products, photos, categories
--   equipment.write    pieces, locations, vendors, repairs, transfers, write-offs
--   customers.write    customer records
--   ledger.view        SEE money: the ledger and every balance
--   ledger.write       post to the ledger
--   numbers.view       the reports — ROI, utilisation
--   admin.team         manage people, and the business settings that change arithmetic
--
-- A key that is absent is DENIED. There is no implication and no wildcard: admin.team does not
-- confer ledger.view. Explicit beats clever when the question is who can read somebody's money.

-- ---------------------------------------------------------------------------
-- 1 · operator, extended. NOT replaced — it is 0017's foundation and its rows are live.
-- ---------------------------------------------------------------------------

alter table operator
  add column if not exists permissions  jsonb   not null default '{}'::jsonb,
  add column if not exists display_name text,
  add column if not exists active       boolean not null default true;

comment on column operator.permissions is
  'Granular permission keys, {"orders.write": true, ...}. Absent means denied — there is no wildcard and no implication. Read only through fn_has_permission(); never test this column directly in a policy, or the choke point stops being one.';
comment on column operator.active is
  'Turned off instead of deleted, so the movements and ledger entries this person wrote keep a valid author (rule 12). An inactive operator fails every permission test.';

-- ---------------------------------------------------------------------------
-- 2 · THE CHOKE POINT.
--
-- security definer, because the alternative recurses: a policy on `operator` that called a
-- function that selected from `operator` would re-enter its own policy for ever. Pinned
-- search_path, and execute revoked from anon — the portal has no business asking this.
-- ---------------------------------------------------------------------------

create or replace function fn_has_permission(p_key text)
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select exists (
    select 1 from operator o
    where o.user_id = auth.uid()
      and o.active
      and coalesce((o.permissions ->> p_key)::boolean, false)
  );
$$;

create or replace function fn_is_operator()
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select exists (select 1 from operator o where o.user_id = auth.uid() and o.active);
$$;

revoke execute on function fn_has_permission(text) from public, anon;
revoke execute on function fn_is_operator() from public, anon;
grant execute on function fn_has_permission(text) to authenticated;
grant execute on function fn_is_operator() to authenticated;

comment on function fn_has_permission(text) is
  'The single gate. Every policy in this database calls this and nothing else tests permissions directly. security definer so that a policy on `operator` cannot recurse into itself.';

-- ---------------------------------------------------------------------------
-- 3 · The map, and the policies built from it.
--
-- Reading is open to any active operator EXCEPT the ledger: knowing that an order exists is part
-- of doing the work, and knowing what a customer owes is not.
-- ---------------------------------------------------------------------------

do $policies$
declare
  r record;
  t text;
  missing text[];
begin
  -- table -> (read key or null for "any operator", write key)
  create temporary table _perm_map (tbl text primary key, read_key text, write_key text) on commit drop;
  insert into _perm_map values
    ('rental_order',  null,         'orders.write'),
    ('order_line',    null,         'orders.write'),
    ('order_charge',  null,         'orders.write'),
    ('product',       null,         'products.write'),
    ('product_image', null,         'products.write'),
    ('category',      null,         'products.write'),
    ('subcategory',   null,         'products.write'),
    ('unit',          null,         'equipment.write'),
    ('location',      null,         'equipment.write'),
    ('vendor',        null,         'equipment.write'),
    ('repair_job',    null,         'equipment.write'),
    ('customer',      null,         'customers.write'),
    -- Money. The only table whose READ is gated, and the reason the key exists.
    ('ledger_entry',  'ledger.view','ledger.write'),
    -- Business conventions that change arithmetic: the day-count rule, the availability buffer,
    -- the discount ladder. Changing one silently re-prices the business, so it sits with the owner.
    ('app_setting',   null,         'admin.team'),
    ('discount_tier', null,         'admin.team');

  for r in select * from _perm_map loop
    execute format('drop policy if exists operator_all on %I', r.tbl);
    execute format('drop policy if exists %I on %I', r.tbl || '_read',   r.tbl);
    execute format('drop policy if exists %I on %I', r.tbl || '_insert', r.tbl);
    execute format('drop policy if exists %I on %I', r.tbl || '_update', r.tbl);
    execute format('drop policy if exists %I on %I', r.tbl || '_delete', r.tbl);

    execute format(
      'create policy %I on %I for select to authenticated using (%s)',
      r.tbl || '_read', r.tbl,
      case when r.read_key is null then 'fn_is_operator()'
           else format('fn_has_permission(%L)', r.read_key) end);

    -- movement is built by hand below: which key applies depends on the row.
    if r.tbl <> 'movement' then
      execute format(
        'create policy %I on %I for insert to authenticated with check (fn_has_permission(%L))',
        r.tbl || '_insert', r.tbl, r.write_key);
      execute format(
        'create policy %I on %I for update to authenticated using (fn_has_permission(%L)) with check (fn_has_permission(%L))',
        r.tbl || '_update', r.tbl, r.write_key, r.write_key);
      execute format(
        'create policy %I on %I for delete to authenticated using (fn_has_permission(%L))',
        r.tbl || '_delete', r.tbl, r.write_key);
    end if;
  end loop;

  -- THE ASSERTION THAT MAKES THE MAP A CHOKE POINT. Maitri's rule is that an action missing from
  -- its map is unprotected; here a TABLE missing from the map would keep whatever policy it had,
  -- or none. Adding a table and forgetting this file must fail loudly, and now it does.
  select array_agg(c.relname order by c.relname) into missing
  from pg_class c
  join pg_namespace n on n.oid = c.relnamespace
  where n.nspname = 'public' and c.relkind = 'r' and c.relrowsecurity
    and c.relname not in (select tbl from _perm_map)
    and c.relname not in ('movement', 'operator');   -- both written by hand below
  if missing is not null then
    raise exception
      'TABLE(S) WITH ROW LEVEL SECURITY AND NO ENTRY IN THE PERMISSION MAP: %. Every table must name the key that guards it. Add it to _perm_map in 0021 (or to the hand-written section) — a table nobody remembered is how this goes wrong, and it must not go wrong quietly.',
      array_to_string(missing, ', ');
  end if;
end
$policies$;

-- ---------------------------------------------------------------------------
-- 4 · movement, by hand, because WHICH key applies depends on the row.
--
-- The man loading the van may record a dispatch and a return. He may not undo one: a correction
-- nets a movement out of every derived view, and the person who made the mistake is not
-- necessarily the person who should be allowed to erase its effect.
-- ---------------------------------------------------------------------------

drop policy if exists operator_all       on movement;
drop policy if exists movement_read      on movement;
drop policy if exists movement_insert    on movement;
drop policy if exists movement_update    on movement;
drop policy if exists movement_delete    on movement;

create policy movement_read on movement
  for select to authenticated using (fn_is_operator());

create policy movement_insert on movement
  for insert to authenticated
  with check (
    case movement_type
      when 'dispatch'   then fn_has_permission('sendout.write')
      when 'return'     then fn_has_permission('returns.write')
      when 'correction' then fn_has_permission('movement.correct')
      -- intake, transfer, repair_out, repair_in, write_off, found: moving our own gear about.
      else fn_has_permission('equipment.write')
    end
  );

-- UPDATE and DELETE are refused outright by 0004/0007 triggers whatever the policy says. The
-- policies exist so that the refusal does not depend on a trigger nobody can see from here.
create policy movement_update on movement
  for update to authenticated using (false) with check (false);
create policy movement_delete on movement
  for delete to authenticated using (false);

-- ---------------------------------------------------------------------------
-- 5 · operator itself. Readable to self only, writable by NOBODY holding a browser session.
--
-- Granting a permission is not a thing an operator does to their own row; it is an admin path
-- running as service_role. If `authenticated` could write here, every key in this file would be
-- one UPDATE away from meaningless.
-- ---------------------------------------------------------------------------

drop policy if exists operator_sees_self on operator;
drop policy if exists operator_read      on operator;
create policy operator_read on operator
  for select to authenticated using (user_id = auth.uid());

revoke all       on table operator from anon, authenticated;
grant  select    on table operator to authenticated;

-- ---------------------------------------------------------------------------
-- 6 · There is always at least one admin.team holder.
--
-- A database whose last administrator has just removed their own admin key is a database nobody
-- can grant anything in again — recoverable only with the service key, at the moment when the
-- person who has it is the one who just locked themselves out.
-- ---------------------------------------------------------------------------

create or replace function fn_operator_keep_one_admin()
returns trigger
language plpgsql
set search_path = public, pg_temp
as $$
declare
  v_others int;
  v_was_admin boolean;
  v_still_admin boolean;
begin
  v_was_admin := old.active and coalesce((old.permissions ->> 'admin.team')::boolean, false);
  if not v_was_admin then return coalesce(new, old); end if;

  v_still_admin := tg_op = 'UPDATE'
                   and new.active
                   and coalesce((new.permissions ->> 'admin.team')::boolean, false);
  if v_still_admin then return new; end if;

  select count(*)::int into v_others
  from operator o
  where o.user_id <> old.user_id
    and o.active
    and coalesce((o.permissions ->> 'admin.team')::boolean, false);

  if v_others = 0 then
    raise exception
      'this is the last person who can manage the team, and removing that leaves nobody able to grant anything to anybody. Give admin.team to someone else first, then take it away here.';
  end if;
  return coalesce(new, old);
end $$;

drop trigger if exists operator_keep_one_admin on operator;
create trigger operator_keep_one_admin
  before update or delete on operator
  for each row execute function fn_operator_keep_one_admin();

-- ---------------------------------------------------------------------------
-- 7 · The reports, gated so they return NOTHING rather than a misleading zero.
--
-- These are owner-rights views (no security_invoker) carrying an explicit permission predicate,
-- and the shape is deliberate. The alternative — leaving them security_invoker and letting RLS on
-- the base tables empty them out — makes v_customer_balance report every customer as owing ₹0.00,
-- which is not a refusal, it is a wrong number stated confidently. Zero rows is a refusal a screen
-- can recognise and say so.
--
-- v_customer_balance itself is left exactly as it is and revoked from authenticated instead: it is
-- read by fn_portal_snapshot, which is security definer and runs as the owner, and a permission
-- predicate inside it would evaluate auth.uid() as NULL on a portal request and break the customer
-- portal for everybody. The gate goes in a wrapper; the arithmetic stays in one place.
-- ---------------------------------------------------------------------------

revoke all on table v_customer_balance from anon, authenticated;

create or replace view v_customer_balance_visible as
  select * from v_customer_balance where fn_has_permission('ledger.view');

comment on view v_customer_balance_visible is
  'v_customer_balance, gated on ledger.view. Owner-rights on purpose: without ledger.view it returns ZERO ROWS, where letting RLS empty the underlying ledger would have returned every customer at ₹0.00 — a wrong number, not a refusal. Screens read this; fn_portal_snapshot reads the ungated view as the definer it is.';

create or replace view v_product_roi_visible as
  select * from v_product_roi where fn_has_permission('numbers.view');
create or replace view v_unit_utilisation_visible as
  select * from v_unit_utilisation where fn_has_permission('numbers.view');

revoke all on table v_product_roi, v_unit_utilisation from anon, authenticated;
revoke all on table v_customer_balance_visible, v_product_roi_visible, v_unit_utilisation_visible
  from anon, authenticated;
grant select on table v_customer_balance_visible, v_product_roi_visible, v_unit_utilisation_visible
  to authenticated;

-- Every other view is security_invoker and inherits the table policies above, which is what we
-- want: they answer operational questions and any active operator may ask them.
revoke all on table v_movement_effective, v_unit_history, v_unit_location, v_unit_status,
                    v_order_outstanding, v_order_fulfilment, v_pool_stock, v_product_stock
  from anon;

-- ---------------------------------------------------------------------------
-- 8 · The existing operator keeps everything.
--
-- There is exactly one account today and it is the owner's. Migrating him to an empty permissions
-- object would lock him out of his own business between this migration and the Team screen, which
-- is not built until Pass G.
-- ---------------------------------------------------------------------------

update operator
set permissions = '{
      "orders.write": true, "sendout.write": true, "returns.write": true,
      "movement.correct": true, "products.write": true, "equipment.write": true,
      "customers.write": true, "ledger.view": true, "ledger.write": true,
      "numbers.view": true, "admin.team": true
    }'::jsonb,
    display_name = coalesce(display_name, 'Owner')
where permissions = '{}'::jsonb;

-- ---------------------------------------------------------------------------
-- 9 · Creating a person. The only route in, and it is not a signup form.
--
-- Invitation only: disable_signup is turned ON in the project alongside this migration, so nobody
-- self-registers. An admin creates the account server-side with the auth admin API and then calls
-- this to record who they are and what they may do. It runs as service_role, never from a browser.
-- ---------------------------------------------------------------------------

create or replace function fn_admin_set_operator(
  p_user_id uuid, p_display_name text, p_permissions jsonb, p_active boolean default true
) returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_bad text[];
  v_keys constant text[] := array[
    'orders.write','sendout.write','returns.write','movement.correct','products.write',
    'equipment.write','customers.write','ledger.view','ledger.write','numbers.view','admin.team'];
begin
  -- A typo'd key is a permission that silently never grants anything, and the person it was meant
  -- for reports that the app is broken rather than that they lack a right.
  select array_agg(k) into v_bad
  from jsonb_object_keys(coalesce(p_permissions, '{}'::jsonb)) k
  where k <> all (v_keys);
  if v_bad is not null then
    raise exception 'unknown permission key(s): %. The eleven keys are: %',
      array_to_string(v_bad, ', '), array_to_string(v_keys, ', ');
  end if;

  insert into operator (user_id, display_name, permissions, active, note)
  values (p_user_id, p_display_name, coalesce(p_permissions, '{}'::jsonb), p_active, 'created by fn_admin_set_operator')
  on conflict (user_id) do update
    set display_name = excluded.display_name,
        permissions  = excluded.permissions,
        active       = excluded.active;
end $$;

-- NOT executable from a browser. This is the function that grants rights; a session that could
-- call it could grant itself everything, which is the whole thing 0021 exists to stop.
revoke execute on function fn_admin_set_operator(uuid, text, jsonb, boolean)
  from public, anon, authenticated;
