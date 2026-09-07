-- 0023_team_admin.sql
-- Somebody has to be able to see the team in order to manage it.
--
-- 0021 gave `operator` one policy: you may read your own row. That is right for everybody except
-- the person holding admin.team, who cannot manage a list they cannot see. And 0021's granting
-- function is service_role only on purpose, which is correct for CREATING an account and wrong as
-- the only way to change a permission — it would mean every toggle on the Team screen needs the
-- service key in a browser, which is the one thing that must never happen.
--
-- So: an admin may READ the team through a policy, and change permissions through a function whose
-- first act is to check admin.team. The gate stays fn_has_permission either way; nothing new tests
-- permissions directly, and the choke point is still a choke point.

-- ---------------------------------------------------------------------------
-- 1 · An admin sees the team. Everybody else still sees exactly themselves.
-- ---------------------------------------------------------------------------

drop policy if exists operator_read on operator;
create policy operator_read on operator
  for select to authenticated
  using (user_id = auth.uid() or fn_has_permission('admin.team'));

-- Writes stay revoked at the GRANT, not merely at the policy. A policy can be added by mistake; a
-- missing privilege cannot be worked around by adding one.
revoke insert, update, delete on table operator from anon, authenticated;

-- ---------------------------------------------------------------------------
-- 2 · Changing what somebody may do, from the Team screen.
--
-- security definer, and the FIRST thing it does is ask whether the caller may manage the team. It
-- cannot create an account — that needs the auth admin API and the service key, which a browser
-- must never hold — so it only ever changes a row that already exists.
-- ---------------------------------------------------------------------------

create or replace function fn_team_set_permissions(
  p_user_id uuid, p_permissions jsonb, p_display_name text default null, p_active boolean default null
) returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_bad text[];
  v_perms jsonb := coalesce(p_permissions, '{}'::jsonb);
  v_keys constant text[] := array[
    'orders.write','sendout.write','returns.write','movement.correct','products.write',
    'equipment.write','customers.write','ledger.view','ledger.write','numbers.view','admin.team'];
begin
  if not fn_has_permission('admin.team') then
    raise exception 'only somebody who manages the team can change what another person may do.';
  end if;

  select array_agg(k) into v_bad
  from jsonb_object_keys(v_perms) k
  where k <> all (v_keys);
  if v_bad is not null then
    raise exception 'unknown permission key(s): %. The eleven keys are: %',
      array_to_string(v_bad, ', '), array_to_string(v_keys, ', ');
  end if;

  -- Posting to the ledger without being able to see it is a state nobody means to create: the
  -- screen refuses to load and the entry form is unreachable. Implied rather than refused, because
  -- a refusal here would be a puzzle and this is the one place that can solve it.
  if coalesce((v_perms ->> 'ledger.write')::boolean, false) then
    v_perms := v_perms || '{"ledger.view": true}'::jsonb;
  end if;

  update operator
     set permissions  = v_perms,
         display_name = coalesce(p_display_name, display_name),
         active       = coalesce(p_active, active)
   where user_id = p_user_id;

  if not found then
    raise exception
      'there is no operator row for that account yet. An account is created in the Supabase dashboard first — nothing in this app can create one, deliberately — and then added here.';
  end if;
  -- The last-admin guard is 0021's trigger and fires on the UPDATE above, so it cannot be dodged
  -- by coming through this function instead of writing the row directly.
end $$;

revoke execute on function fn_team_set_permissions(uuid, jsonb, text, boolean) from public, anon;
grant execute on function fn_team_set_permissions(uuid, jsonb, text, boolean) to authenticated;

-- ---------------------------------------------------------------------------
-- 3 · Adding somebody who already has an account.
-- ---------------------------------------------------------------------------

create or replace function fn_team_add(
  p_user_id uuid, p_display_name text, p_permissions jsonb
) returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  if not fn_has_permission('admin.team') then
    raise exception 'only somebody who manages the team can add a person.';
  end if;
  if not exists (select 1 from auth.users u where u.id = p_user_id) then
    raise exception
      'there is no account with that id. Create it in the Supabase dashboard under Authentication → Users, with Auto Confirm ticked, then paste the user id here. Nothing in this app can create an account, and that is deliberate — it would need the service key to do it.';
  end if;
  insert into operator (user_id, display_name, permissions, active, note)
  values (p_user_id, p_display_name, coalesce(p_permissions, '{}'::jsonb), true, 'added from the Team screen')
  on conflict (user_id) do nothing;
  perform fn_team_set_permissions(p_user_id, coalesce(p_permissions, '{}'::jsonb), p_display_name, true);
end $$;

revoke execute on function fn_team_add(uuid, text, jsonb) from public, anon;
grant execute on function fn_team_add(uuid, text, jsonb) to authenticated;
