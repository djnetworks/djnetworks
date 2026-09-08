-- dev_teardown.sql
-- Removes exactly what dev_seed.sql inserted, and nothing else — or refuses to run.
--
-- ===========================================================================
--  WHY THIS FILE EXISTS. On 8 September 2026 dev_seed.sql was found loaded into the
--  production database, with its nine invented products and forty-nine invented
--  movements sitting inside every ROI, dead-stock and best-customer figure on the
--  reports screen, and nothing marking them as fiction. Its header said it was
--  never applied to production. The header was wrong because the operator of the
--  tooling — me — ran it there, repeatedly, to reset the fixture between tests.
-- ===========================================================================
--
-- HOW IT KNOWS WHAT IS SEED. Every row dev_seed.sql writes carries an id in the
-- reserved namespace 00000000-0000-4000-8000-............ — see pg_temp.seed_id() in
-- that file. gen_random_uuid() never lands there. This file matches on that prefix.
--
-- WHY IT IS ASSERT-THEN-TRUNCATE AND NOT DELETE-BY-ID, and this is the part to read.
-- Migrations 0004 and 0007–0009 put BEFORE DELETE triggers on movement, unit,
-- rental_order, ledger_entry and repair_job that raise unconditionally, for every
-- role, with no bypass — history is cancelled or retired, never removed (rule 12).
-- A `delete from movement where id like '00000000-…'` therefore cannot run at all.
-- The only sanctioned way to remove a row from those tables is TRUNCATE, which is
-- table-wide by nature.
--
-- So this file does the one thing that makes TRUNCATE safe: it PROVES FIRST that
-- every row in every affected table carries the seed prefix, and aborts — touching
-- nothing — if a single row does not. A database with real records in it is
-- refused, with the table and the count named. Against a database holding only the
-- fixture, TRUNCATE then removes precisely the seed, because the seed was just shown
-- to be all there is. The three tables with no delete guard — product, customer,
-- vendor — are cleared by targeted DELETE on the prefix, as they should be.
--
-- WHAT THIS CANNOT DO: remove the fixture from a database that ALSO holds real rows.
-- That needs either a session-variable bypass built into the five guard functions
-- (a migration, and a deliberate weakening of rule 12's enforcement) or a temporary
-- trigger disable inside a transaction (previously and correctly forbidden). Both
-- are decisions, not defaults. This file refuses instead, which is the honest limit.
--
-- Run as postgres or service_role, by hand, with ON_ERROR_STOP:
--   psql "<conn>" -1 -v ON_ERROR_STOP=1 -f supabase/seed/dev_teardown.sql
-- It is one transaction. If any assertion fails, nothing has changed.

\set ON_ERROR_STOP on

begin;

-- ---------------------------------------------------------------------------
-- 1 · PROVE the database holds nothing but the fixture. Every table the seed
--     writes, every row, must carry the prefix. Otherwise stop here, name the
--     table, and leave everything exactly as it was.
-- ---------------------------------------------------------------------------
do $assert$
declare
  t text; n bigint; bad text := '';
begin
  foreach t in array array['movement','ledger_entry','order_charge','order_line','rental_order',
                           'repair_job','product_image','unit','product','customer','vendor'] loop
    execute format(
      'select count(*) from %I where id::text not like ''00000000-0000-4000-8000-%%''', t) into n;
    if n > 0 then bad := bad || format('  %s: %s row(s) that are NOT seed%s', t, n, E'\n'); end if;
  end loop;
  if bad <> '' then
    raise exception E'dev_teardown refused — this database holds rows that dev_seed.sql did not write:\n%\nNothing was changed. A fixture cannot be removed from a database that also holds real records without weakening rule 12; see the header of this file.', bad;
  end if;
  raise notice 'dev_teardown: every row in all 11 seeded tables carries the seed prefix — safe to proceed';
end $assert$;

-- ---------------------------------------------------------------------------
-- 2 · The guarded tables, in one TRUNCATE. No CASCADE, deliberately: if some future
--     table references one of these, this statement fails loudly instead of quietly
--     emptying a table this file has never heard of.
-- ---------------------------------------------------------------------------
truncate table
  movement,
  ledger_entry,
  order_charge,
  order_line,
  rental_order,
  repair_job,
  product_image,
  unit;

-- ---------------------------------------------------------------------------
-- 3 · The unguarded masters, by prefix. portal_attempt references customer with
--     ON DELETE SET NULL, so an attempt logged against a seed customer keeps its
--     row and loses the link — the log is operational, not fixture.
-- ---------------------------------------------------------------------------
delete from product  where id::text like '00000000-0000-4000-8000-%';
delete from customer where id::text like '00000000-0000-4000-8000-%';
delete from vendor   where id::text like '00000000-0000-4000-8000-%';

-- ---------------------------------------------------------------------------
-- 4 · PROVE it is gone. Numbers, not the absence of an error.
-- ---------------------------------------------------------------------------
do $verify$
declare t text; n bigint; left_over text := '';
begin
  foreach t in array array['movement','ledger_entry','order_charge','order_line','rental_order',
                           'repair_job','product_image','unit','product','customer','vendor'] loop
    execute format('select count(*) from %I', t) into n;
    if n > 0 then left_over := left_over || format('  %s: %s%s', t, n, E'\n'); end if;
  end loop;
  if left_over <> '' then
    raise exception E'dev_teardown: rows remain after teardown:\n%', left_over;
  end if;
  raise notice 'dev_teardown: all 11 tables empty — the fixture is gone';
end $verify$;

commit;
