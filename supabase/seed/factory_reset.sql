-- factory_reset.sql
-- Removes ALL business data from the one database, so chachu's practice entries — made to learn
-- the app — do not survive into the real catalogue. Leaves the migration-seeded masters and every
-- login intact.
--
-- ===========================================================================
--  THIS IS A ONE-TIME, PRE-GO-LIVE OPERATION. IT IS NOT A MAINTENANCE TOOL.
--
--  It deletes orders, movements, ledger entries and repairs outright — which
--  CLAUDE.md rule 12 forbids for real data ("history is never deleted"). That is
--  a deliberate, scoped exception, and it is only defensible in the window BEFORE
--  the first real row exists. docs/decisions.md records why. After go-live this
--  file must never run again, and it enforces that itself (see the go-live latch
--  below) rather than trusting this comment.
-- ===========================================================================
--
--  HOW TO ARM AND RUN IT. It refuses unless a token is set in the same session, so
--  it cannot go off by accident or by a stray `\i`. Set the token with -c and run
--  the file with -f in ONE psql invocation — a session-level SET from -c persists
--  into the -f that follows on the same connection:
--
--    set -a && . ./.env && set +a
--    PGPASSWORD="$DB_PASSWORD" psql \
--      "host=aws-0-ap-south-1.pooler.supabase.com port=5432 dbname=postgres user=postgres.hjidocpqcrfbjucvqggu sslmode=require" \
--      -v ON_ERROR_STOP=1 \
--      -c "set factory_reset.arm = 'WIPE-ALL-BUSINESS-DATA'" \
--      -f supabase/seed/factory_reset.sql
--
--  Run as postgres or service_role: the tables it clears carry BEFORE DELETE
--  triggers (rule 12) that block every other role, and TRUNCATE — which bypasses
--  those triggers — is granted only to those two (migration 0009).
--
--  IT IS ONE TRANSACTION. Any failure, including a failed arming check, changes
--  nothing.
--
--  WHAT IT DOES NOT REACH, and you must handle separately before go-live:
--    · Storage. product-images and return-photos hold files keyed on product and
--      order ids; SQL here cannot delete a storage object (storage.protect_delete),
--      and clearing the tables orphans whatever practice photos exist. Empty the
--      two buckets through the Storage API.
--    · The offline queue on chachu's phone. IndexedDB `djn` holds unsynced practice
--      writes that will REPLAY into the clean database on his next reconnect. This
--      file runs on the server and cannot touch it. Clear it on the device first.
--    See docs/build-setup.md for both.

\set ON_ERROR_STOP on

begin;

-- ---------------------------------------------------------------------------
-- 1 · ARM, and the go-live latch. Both must pass, or nothing happens.
-- ---------------------------------------------------------------------------
do $arm$
begin
  if current_setting('factory_reset.arm', true) is distinct from 'WIPE-ALL-BUSINESS-DATA' then
    raise exception
      'factory_reset is not armed. This deletes every product, order, movement and ledger entry in the database. If that is genuinely what you want, set the token in the SAME session and run again — see the header of this file. Nothing was changed.';
  end if;

  -- THE GO-LIVE LATCH. The go-live procedure sets app_setting key 'go_live'. Once it is set, this
  -- file refuses — the exception in rule 12 closes the moment real data has been declared live, and
  -- that is enforced here rather than left to whoever remembers the comment.
  if exists (select 1 from app_setting where key = 'go_live') then
    raise exception
      'factory_reset REFUSED: app_setting.go_live is set, so this database has gone live and its rows are real. This tool exists only for the window before the first real row. Deleting now would destroy business records; that is what rule 12 forbids and what this latch is here to stop. Nothing was changed.';
  end if;

  raise notice 'factory_reset armed, and go_live is not set — proceeding.';
end $arm$;

-- ---------------------------------------------------------------------------
-- 2 · COUNTS BEFORE. A result set, not a comment — so the operator sees exactly
--     what is about to go, and the after-block below can be compared to it.
-- ---------------------------------------------------------------------------
select 'before' as when, t, n from (
  select 'product' t, count(*) n from product
  union all select 'unit', count(*) from unit
  union all select 'customer', count(*) from customer
  union all select 'vendor', count(*) from vendor
  union all select 'rental_order', count(*) from rental_order
  union all select 'order_line', count(*) from order_line
  union all select 'order_charge', count(*) from order_charge
  union all select 'movement', count(*) from movement
  union all select 'ledger_entry', count(*) from ledger_entry
  union all select 'repair_job', count(*) from repair_job
  union all select 'product_image', count(*) from product_image
  union all select 'portal_attempt', count(*) from portal_attempt
) x order by t;

-- ---------------------------------------------------------------------------
-- 3 · THE WIPE. One TRUNCATE, every business table named, NO CASCADE — so if some
--     future migration adds a table that references one of these, this fails loudly
--     rather than silently emptying a table this file has never heard of. Every
--     current referencer (portal_attempt → customer) is already in the list, which
--     is checked: `select ... where confrelid in (...) and conrelid not in (...)`
--     returned only portal_attempt when this was written.
--
--     TRUNCATE, not DELETE, because rule 12's BEFORE DELETE triggers block DELETE on
--     movement, unit, rental_order, ledger_entry and repair_job for everyone. This is
--     the one sanctioned escape 0009 left, for exactly this kind of reset.
--
--     Masters are NOT here and are never touched: location, category, subcategory,
--     discount_tier, app_setting, operator, and every auth.users row.
-- ---------------------------------------------------------------------------
truncate table
  movement,
  ledger_entry,
  order_charge,
  order_line,
  rental_order,
  repair_job,
  product_image,
  portal_attempt,
  unit,
  product,
  customer,
  vendor;

-- ---------------------------------------------------------------------------
-- 4 · COUNTS AFTER, and a hard assertion. Every business table must read 0; the
--     masters must be untouched. Numbers, not the absence of an error.
-- ---------------------------------------------------------------------------
select 'after' as when, t, n from (
  select 'product' t, count(*) n from product
  union all select 'unit', count(*) from unit
  union all select 'customer', count(*) from customer
  union all select 'vendor', count(*) from vendor
  union all select 'rental_order', count(*) from rental_order
  union all select 'order_line', count(*) from order_line
  union all select 'order_charge', count(*) from order_charge
  union all select 'movement', count(*) from movement
  union all select 'ledger_entry', count(*) from ledger_entry
  union all select 'repair_job', count(*) from repair_job
  union all select 'product_image', count(*) from product_image
  union all select 'portal_attempt', count(*) from portal_attempt
) x order by t;

do $verify$
declare t text; n bigint; left_over text := '';
begin
  foreach t in array array['product','unit','customer','vendor','rental_order','order_line',
                           'order_charge','movement','ledger_entry','repair_job','product_image','portal_attempt'] loop
    execute format('select count(*) from %I', t) into n;
    if n > 0 then left_over := left_over || format('  %s: %s%s', t, n, E'\n'); end if;
  end loop;
  if left_over <> '' then
    raise exception E'factory_reset: rows remain after the wipe:\n%', left_over;
  end if;

  -- The masters must still be here. A reset that quietly ate the locations or the taxonomy would
  -- leave a database that looks clean and cannot take a single order.
  if (select count(*) from location) = 0 then raise exception 'factory_reset: locations are gone — masters must survive a reset (they are seeded by 0004, not by the fixture).'; end if;
  if (select count(*) from category) = 0 then raise exception 'factory_reset: categories are gone — masters must survive a reset.'; end if;
  if (select count(*) from operator) = 0 then raise exception 'factory_reset: no operator rows left — nobody could sign in. Masters and logins are never touched by this file.'; end if;

  raise notice 'factory_reset complete: all 12 business tables empty; locations, taxonomy, settings, discount tiers and every login untouched.';
  raise notice 'NEXT: empty the product-images and return-photos buckets, clear the offline queue on any phone that has used the app, then set app_setting.go_live to close this door.';
end $verify$;

commit;
