-- 0017_operator_allowlist.sql
-- Being signed in is no longer the same thing as owning the business.
--
-- Every policy since 0004 has read `to authenticated using (true)`. That made a dashboard checkbox
-- — "Allow new users to sign up" — the only thing standing between a stranger and the whole
-- database, because the publishable key ships in the page source and is public by design. Measured
-- on 2026-09-07: POST /auth/v1/signup with nothing but that key returned HTTP 200 and created an
-- account. One toggle, in a web console, load-bearing for every customer record and every rupee in
-- the ledger. That is not a security model, it is a habit.
--
-- Now membership is a row in a table this migration creates, and the toggle is a convenience again.
-- A stranger who self-registers gets a valid session and an empty database.
--
-- ---------------------------------------------------------------------------
-- THE TWO WAYS THIS FIX GOES WRONG, both avoided deliberately below.
--
-- 1. If `operator` is writable by `authenticated`, the fix is circular: register, insert yourself,
--    own everything. So `operator` has RLS, no INSERT/UPDATE/DELETE policy whatsoever, and its
--    grants are revoked. Membership is granted by postgres or service_role and by nothing else —
--    a migration, or the SQL editor, never the app.
--
-- 2. If `operator` has RLS enabled and NO SELECT policy, the `exists (...)` subquery inside every
--    other policy returns no rows FOR EVERYONE, and the whole database locks out — including
--    chachu. A policy that refuses everybody looks identical to one that works until somebody tries
--    to sign in. So there is exactly one SELECT policy, letting a user see their OWN membership row
--    and nothing else. That is enough for `exists (...)` to answer, and it leaks nothing: you can
--    learn whether you are an operator, which you already knew.
-- ---------------------------------------------------------------------------

create table if not exists operator (
  user_id    uuid primary key references auth.users(id) on delete cascade,
  note       text,
  created_at timestamptz not null default now()
);

comment on table operator is
  'Who owns this business''s data. Membership here — not merely holding a session — is what every RLS policy tests. Rows are added by postgres or service_role only: there is deliberately no INSERT policy, so the application can never grant access to itself.';

alter table operator enable row level security;

-- The ONLY policy on this table. Read your own row; write nothing, ever.
drop policy if exists operator_sees_self on operator;
create policy operator_sees_self on operator
  for select to authenticated
  using (user_id = auth.uid());

-- Defence in depth: even without a policy, no grant.
revoke all on table operator from anon, authenticated;
grant select on table operator to authenticated;

-- ---------------------------------------------------------------------------
-- Rewrite every policy. `to authenticated` stays — it narrows the audience before the predicate is
-- even evaluated — but the predicate is now membership rather than `true`.
--
-- The subquery is uncorrelated with the row being checked, so Postgres evaluates it once per
-- statement as an InitPlan rather than per row. On a table with one row and a primary key, the cost
-- of this is not measurable.
-- ---------------------------------------------------------------------------

do $$
declare t text;
begin
  foreach t in array array[
    'category','subcategory','product','unit','location','vendor','customer',
    'discount_tier','app_setting','rental_order','order_line','order_charge',
    'repair_job','movement','ledger_entry','product_image'
  ]
  loop
    execute format('alter table %I enable row level security', t);
    execute format('drop policy if exists operator_all on %I', t);
    execute format($f$
      create policy operator_all on %I
        for all
        to authenticated
        using      (exists (select 1 from operator o where o.user_id = auth.uid()))
        with check (exists (select 1 from operator o where o.user_id = auth.uid()))
    $f$, t);
  end loop;
end $$;

-- ---------------------------------------------------------------------------
-- Product images live in storage, not in a table, and 0006's write policy was `to authenticated`
-- with no further test — so a self-registered stranger could upload into the bucket and delete
-- every product photo. Same flaw, same fix. Read stays public: the bucket is public by design
-- because the customer portal shows these.
-- ---------------------------------------------------------------------------

drop policy if exists product_images_write on storage.objects;
create policy product_images_write on storage.objects
  for all to authenticated
  using      (bucket_id = 'product-images'
              and exists (select 1 from operator o where o.user_id = auth.uid()))
  with check (bucket_id = 'product-images'
              and exists (select 1 from operator o where o.user_id = auth.uid()));
