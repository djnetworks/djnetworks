-- 0030_team_create_rate_limit.sql
-- The attempt log behind the team-create Edge Function, so an account-creation endpoint on a public
-- repo cannot be hammered. Mirrors 0029's portal_attempt exactly — same shape, same reasoning, same
-- IP handling (the function computes the client IP the way fn_portal_client_ip does: cf-connecting-ip,
-- then sb-forwarded-for, then the LAST element of x-forwarded-for, never the first, because a client
-- can prepend to that header).
--
-- The endpoint already refuses anyone without an active admin.team JWT before it does anything. This
-- limit is the second wall: a stolen or malicious admin token, or a script, cannot create accounts
-- without bound. Two windows, an admin's own and the IP's.
--
-- Additive: no existing query, view or permission key is touched. The function writes here as
-- service_role (which bypasses RLS); nobody writes it directly, and only admin.team may read it.

create table if not exists team_create_attempt (
  id           bigint generated always as identity primary key,
  at           timestamptz not null default now(),
  actor        uuid references auth.users(id) on delete set null,  -- the admin who called, once verified
  email_tried  text,                                               -- the account being created; never the password
  ip           inet,
  ok           boolean not null,
  outcome      text not null
               check (outcome in ('ok','no_jwt','bad_jwt','not_admin','rate_limited',
                                  'bad_input','email_exists','create_failed','grant_failed'))
);

comment on table team_create_attempt is
  'Every call to the team-create Edge Function, successful or not. Never stores the password. Written by the function as service_role; readable only by admin.team (0030).';

create index if not exists team_create_attempt_actor_at on team_create_attempt (actor, at desc);
create index if not exists team_create_attempt_ip_at    on team_create_attempt (ip, at desc);

alter table team_create_attempt enable row level security;
revoke all on table team_create_attempt from anon, authenticated;
grant select on table team_create_attempt to authenticated;

drop policy if exists team_create_attempt_read on team_create_attempt;
create policy team_create_attempt_read on team_create_attempt
  for select to authenticated
  using (public.fn_has_permission('admin.team'));
-- No insert/update/delete policy for anyone. Rows arrive only through the function's service_role
-- client, which bypasses RLS; anything else writing here would be forging the audit trail (0029).

insert into app_setting (key, value) values
  ('team_create_actor_max',      '10'::jsonb),   -- an admin: 10 new accounts per window
  ('team_create_ip_max',         '20'::jsonb),   -- one address: 20 attempts per window
  ('team_create_window_minutes', '60'::jsonb)
on conflict (key) do nothing;
