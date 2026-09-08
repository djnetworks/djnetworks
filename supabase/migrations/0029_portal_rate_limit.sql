-- 0029_portal_rate_limit.sql
-- The portal gate was a phone number and eight characters over an unthrottled RPC.
--
-- That was a known gap while the repository was private. It became a DOCUMENTED gap the day the
-- repository went public: 0016's own comment on fn_portal_view says "there is no rate limiting; an
-- eight-character code over an unthrottled RPC is guessable given enough attempts", and anybody can
-- now read that sentence, the function body, the alphabet the code is drawn from and the exact
-- shape of the request. Publishing did not create the weakness. It removed the only thing that was
-- ever protecting it, which was nobody having looked.
--
-- Three things here: a log, two throttles, and a lockout.

-- ---------------------------------------------------------------------------
-- 1 · WHOSE IP, AND THE HEADER THAT LIES.
--
-- Measured against this project rather than assumed, because the naive version of this is
-- bypassable with one curl flag:
--
--   cf-connecting-ip   CANNOT be forged. Sending your own gets HTTP 403 (Cloudflare error 1000)
--                      before the request ever reaches Postgres. Verified.
--   sb-forwarded-for   stayed correct while x-forwarded-for was being forged. Verified.
--   x-forwarded-for    IS forgeable, by PREPENDING. A request sent with `x-forwarded-for: 1.2.3.4`
--                      arrived as `1.2.3.4,171.61.165.229`. The true address is the LAST element.
--
-- So the usual implementation — split on comma, take element ONE — reads the attacker's chosen
-- value and lets them present a fresh IP on every single request, which defeats an IP throttle
-- completely while testing perfectly clean against an honest client. Rule 16: the probe has to
-- reproduce the real call shape, and the real call shape here includes a hostile header.
-- ---------------------------------------------------------------------------

create or replace function fn_portal_client_ip()
returns inet
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare h jsonb; v text;
begin
  h := nullif(current_setting('request.headers', true), '')::jsonb;
  if h is null then return null; end if;

  v := coalesce(
         h ->> 'cf-connecting-ip',                       -- set by Cloudflare, unforgeable
         h ->> 'sb-forwarded-for',                       -- set by Supabase's own edge
         -- LAST element, never the first: anything a client prepends sits in front of the truth.
         nullif(trim(split_part(h ->> 'x-forwarded-for', ',',
                array_length(string_to_array(h ->> 'x-forwarded-for', ','), 1))), '')
       );
  begin
    return v::inet;
  exception when others then
    -- A malformed address must not take the portal down. Null means "unknown", and the phone
    -- throttle below still applies — the two limits are deliberately independent for this reason.
    return null;
  end;
end $$;

comment on function fn_portal_client_ip() is
  'The caller''s IP, from cf-connecting-ip (unforgeable — Cloudflare 403s a request that supplies its own) then sb-forwarded-for, and only then the LAST element of x-forwarded-for. Never the first element: a client can prepend to that header and did, in testing (0029).';

-- ---------------------------------------------------------------------------
-- 2 · THE LOG.
--
-- Never the code, not even hashed. Storing attempted codes would build the exact dictionary this
-- migration exists to defend against, and a wrong code is often a customer's RIGHT code for a
-- different service.
--
-- The phone is stored normalised to its last ten digits, which is what the gate compares anyway —
-- so nothing is recorded here that `customer.whatsapp` does not already hold.
-- ---------------------------------------------------------------------------

create table if not exists portal_attempt (
  id           bigint generated always as identity primary key,
  at           timestamptz not null default now(),
  phone_last10 text,
  ip           inet,
  ok           boolean not null,
  outcome      text not null
               check (outcome in ('ok','bad_code','no_match','malformed','locked_phone','locked_ip')),
  customer_id  uuid references customer(id) on delete set null
);

comment on table portal_attempt is
  'Every portal sign-in attempt, successful or not. Never stores the code attempted — that would build the dictionary this table exists to defend against, and a wrong code is often the customer''s right code somewhere else (0029).';

create index if not exists portal_attempt_phone_at on portal_attempt (phone_last10, at desc);
create index if not exists portal_attempt_ip_at    on portal_attempt (ip, at desc);
create index if not exists portal_attempt_at       on portal_attempt (at);

alter table portal_attempt enable row level security;

-- anon writes these through the security definer function and may never read them back: the table
-- holds phone numbers and IP addresses, which is precisely what an attacker would like.
revoke all on table portal_attempt from anon, authenticated;
grant select on table portal_attempt to authenticated;

drop policy if exists portal_attempt_read on portal_attempt;
create policy portal_attempt_read on portal_attempt
  for select to authenticated
  using (public.fn_has_permission('admin.team'));

-- No INSERT policy for anybody. Rows arrive only through fn_portal_view, which is security definer
-- and therefore bypasses RLS. Anything else writing here would be forging an audit trail.

-- ---------------------------------------------------------------------------
-- 3 · THE LIMITS, in app_setting, because the operator may need to loosen them at 9pm on a
-- Saturday when a customer cannot get in and the answer cannot be "wait for a deploy".
--
-- Two windows, deliberately different:
--   PHONE  5 failures / 15 min. Tight. Guessing a code means guessing against one number.
--   IP    20 failures / 15 min. Looser on purpose — a wedding hall, an office and a shared mobile
--         network put many legitimate customers behind one address, and a throttle that locks a
--         venue full of people out of their own bookings is a worse failure than a slow attacker.
-- ---------------------------------------------------------------------------

insert into app_setting (key, value) values
  ('portal_phone_max_failures', '5'::jsonb),
  ('portal_ip_max_failures',    '20'::jsonb),
  ('portal_window_minutes',     '15'::jsonb),
  ('portal_lockout_minutes',    '15'::jsonb)
on conflict (key) do nothing;

-- ---------------------------------------------------------------------------
-- 4 · THE GATE.
--
-- IT RETURNS ITS REFUSAL, IT NO LONGER RAISES IT, and that is not a style change — it is the whole
-- reason the log works. PostgREST runs each request in one transaction, so a RAISE aborts the
-- function and takes every INSERT it made with it. The obvious implementation — write the attempt
-- row, then raise on a bad code — produces a log containing successes and nothing else, and looks
-- completely correct while doing it. Postgres has no autonomous transaction to escape with.
--
-- So a refusal is a normal return carrying an `error` key, and web/portal.html reads that.
--
-- ONE MESSAGE for "no such number" and "wrong code" still, so the portal cannot be used to discover
-- which numbers are customers. The LOCKOUT message is deliberately different and honest: a customer
-- who has mistyped five times must be told to wait, or they message chachu, which is the exact
-- failure the portal exists to prevent (open-questions item 2). It reveals only that this phone or
-- this address has been trying — which whoever is trying already knows.
-- ---------------------------------------------------------------------------

create or replace function fn_portal_view(p_phone text, p_code text)
returns jsonb
language plpgsql
volatile                       -- was `stable`; it writes the attempt log now
security definer
set search_path = public, extensions, pg_temp
as $$
declare
  v_id uuid; v_hash text; v_typed text; v_ip inet;
  v_win int; v_lock int; v_max_phone int; v_max_ip int;
  v_fail_phone int; v_fail_ip int; v_recent timestamptz;
  c_bad constant text := 'That phone number and access code do not match. Ask DJ Network''s for a new code.';
begin
  v_ip    := fn_portal_client_ip();
  v_typed := right(regexp_replace(coalesce(p_phone,''), '\D', '', 'g'), 10);

  select (value #>> '{}')::int into v_win       from app_setting where key = 'portal_window_minutes';
  select (value #>> '{}')::int into v_lock      from app_setting where key = 'portal_lockout_minutes';
  select (value #>> '{}')::int into v_max_phone from app_setting where key = 'portal_phone_max_failures';
  select (value #>> '{}')::int into v_max_ip    from app_setting where key = 'portal_ip_max_failures';
  v_win := coalesce(v_win,15); v_lock := coalesce(v_lock,15);
  v_max_phone := coalesce(v_max_phone,5); v_max_ip := coalesce(v_max_ip,20);

  if p_phone is null or p_code is null or length(v_typed) < 10 then
    insert into portal_attempt (phone_last10, ip, ok, outcome)
    values (nullif(v_typed,''), v_ip, false, 'malformed');
    return jsonb_build_object('error', c_bad);
  end if;

  -- ---- LOCKOUT CHECKED FIRST, BEFORE ANY BCRYPT ----------------------------------------------
  -- Ordering matters twice. A locked-out caller must not get free bcrypt work out of us, and a
  -- locked-out caller must not be able to tell a right code from a wrong one by timing.
  --
  -- Counted on the TYPED number, not on a matched customer: throttling only numbers that turn out
  -- to be real would leave somebody enumerating numbers completely unthrottled, which is the
  -- cheaper attack and the one that finds out who the customers are.
  -- COUNT REAL ATTEMPTS ONLY, never the refusals a lockout itself wrote. Counting those makes the
  -- lockout self-extending: every tap while locked pushes the unlock time out again, so a customer
  -- who mistyped five times and then tapped three more in frustration can never get back in, and
  -- the message telling them to wait fifteen minutes is a lie. An attacker is still limited to five
  -- guesses per window either way — which is the whole point — so the strictness bought nothing and
  -- cost the legitimate case everything.
  select count(*), max(at) into v_fail_phone, v_recent
  from portal_attempt
  where phone_last10 = v_typed and not ok
    and outcome in ('bad_code','no_match','malformed')
    and at > now() - make_interval(mins => v_win);

  if v_fail_phone >= v_max_phone then
    insert into portal_attempt (phone_last10, ip, ok, outcome)
    values (v_typed, v_ip, false, 'locked_phone');
    return jsonb_build_object(
      'error', format('Too many tries with this number. Wait %s minutes and try again, or ask DJ Network''s for a new code.', v_lock),
      'locked', true,
      'retry_after_seconds', greatest(0, extract(epoch from (v_recent + make_interval(mins => v_lock)) - now())::int));
  end if;

  if v_ip is not null then
    select count(*), max(at) into v_fail_ip, v_recent
    from portal_attempt
    where ip = v_ip and not ok
      and outcome in ('bad_code','no_match','malformed')
      and at > now() - make_interval(mins => v_win);

    if v_fail_ip >= v_max_ip then
      insert into portal_attempt (phone_last10, ip, ok, outcome)
      values (v_typed, v_ip, false, 'locked_ip');
      return jsonb_build_object(
        'error', format('Too many tries from this connection. Wait %s minutes and try again.', v_lock),
        'locked', true,
        'retry_after_seconds', greatest(0, extract(epoch from (v_recent + make_interval(mins => v_lock)) - now())::int));
    end if;
  end if;

  -- ---- THE GATE ITSELF, unchanged from 0015 ---------------------------------------------------
  select c.id, c.portal_code_hash into v_id, v_hash
  from customer c
  where right(regexp_replace(c.whatsapp, '\D', '', 'g'), 10) = v_typed
    and c.active
  limit 1;

  if v_id is null or v_hash is null then
    insert into portal_attempt (phone_last10, ip, ok, outcome)
    values (v_typed, v_ip, false, 'no_match');
    return jsonb_build_object('error', c_bad);
  end if;

  if extensions.crypt(p_code, v_hash) <> v_hash then
    insert into portal_attempt (phone_last10, ip, ok, outcome, customer_id)
    values (v_typed, v_ip, false, 'bad_code', v_id);
    return jsonb_build_object('error', c_bad);
  end if;

  insert into portal_attempt (phone_last10, ip, ok, outcome, customer_id)
  values (v_typed, v_ip, true, 'ok', v_id);

  -- A SUCCESS CLEARS THE STREAK for this number. Without it a customer who fumbled four times on
  -- Tuesday is one typo away from being locked out on Friday, and the failures that locked them
  -- out were their own.
  delete from portal_attempt
  where phone_last10 = v_typed and not ok
    and outcome in ('bad_code','no_match','malformed')
    and at > now() - make_interval(mins => v_win);

  -- Housekeeping, on a fraction of calls so the portal is not paying for a DELETE every time.
  if random() < 0.02 then
    delete from portal_attempt where at < now() - interval '30 days';
  end if;

  return fn_portal_snapshot(v_id);
end $$;

comment on function fn_portal_view is
  'The customer portal gate, callable by anon and nothing else. Throttled since 0029: 5 failures per phone and 20 per IP in a 15-minute window, then a cooling period, with every attempt logged to portal_attempt and the code never stored. It RETURNS its refusal in an "error" key rather than raising, because PostgREST runs the request in one transaction and a RAISE would roll the log entry back — producing a log of successes only, which looks correct. Replace the authentication half with a one-time code when open-questions item 2 is settled; fn_portal_snapshot never knew how the caller was authenticated.';

revoke execute on function fn_portal_view(text, text) from public, authenticated;
grant execute on function fn_portal_view(text, text) to anon;
revoke execute on function fn_portal_client_ip() from public, anon;

-- ---------------------------------------------------------------------------
-- The assertion. States what it expects before reading what is there.
-- ---------------------------------------------------------------------------
do $assert$
declare def text; n int;
begin
  select pg_get_functiondef(oid) into def from pg_proc
   where proname = 'fn_portal_view' and pronamespace = 'public'::regnamespace;

  if def ~* 'raise\s+exception' then
    raise exception
      'fn_portal_view still raises. Expected: it returns an error key. Actual: a RAISE, which aborts the PostgREST transaction and rolls back the portal_attempt row with it — leaving a log that records successes only and looks perfectly healthy (0029).';
  end if;
  if def !~ 'provolatile' and (select provolatile from pg_proc where proname='fn_portal_view' and pronamespace='public'::regnamespace) <> 'v' then
    raise exception 'fn_portal_view is not VOLATILE, so it cannot write the attempt log.';
  end if;

  select count(*) into n from pg_policies where tablename = 'portal_attempt' and cmd = 'INSERT';
  if n <> 0 then
    raise exception 'portal_attempt has an INSERT policy (% found). Expected none: rows arrive only through the security definer gate, and anything else writing here is forging an audit trail.', n;
  end if;

  raise notice '0029 ok: gate returns rather than raises, is volatile, and portal_attempt takes writes from nobody directly.';
end $assert$;
