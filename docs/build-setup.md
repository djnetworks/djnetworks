# Build setup — environments, the database, and the fixture

**This file did not exist before 8 September 2026.** It was referred to as if it did, and the fact
it recorded — that the catalogue was empty — was wrong for the two days before it was written. It
exists now so the next claim about the state of the database has somewhere to be checked.

---

## There is one database

Supabase project `hjidocpqcrfbjucvqggu`, `ap-south-1` (Mumbai). It is production. There is no
staging project and no local Postgres. Every migration, every probe and — until 8 September — every
run of the development fixture went against it.

That last part is the reason this file exists.

## What happened

`supabase/seed/dev_seed.sql` opens with a TRUNCATE and its header says it must never be pointed at a
database holding real records. Between 6 and 8 September it was run against the production database
repeatedly, to reset the fixture between tests, because there was nowhere else to run it. The
database held nine invented products, twenty-six invented pieces, two invented customers with
real-format Indian mobile numbers, six invented orders and forty-nine invented movements — and the
reports screen built on 8 September computed ROI, dead stock and best customers over all of it with
nothing marking any of it as fiction.

## What was done about it

1. **Every phone number in the fixture was moved to a reserved range** — ten digits beginning with
   `1`, which no Indian mobile can — in the live rows that permit UPDATE and in the seed file itself,
   so a future run cannot reintroduce a number that might ring a stranger. The two numbers that sat
   on `movement` rows could not be updated (append-only, rule 12); they left with the teardown.

2. **The seed now tags every row it writes.** Ids come from a temp sequence in the reserved
   namespace `00000000-0000-4000-8000-000000000NNN`. `gen_random_uuid()` never lands there, so a
   seed row is recognisable by its prefix for as long as it exists. Category, subcategory, location
   and settings are still looked up by name — those are migration-seeded and are not fixture.

3. **`supabase/seed/dev_teardown.sql` removes exactly those rows.** It first proves that every row
   in all eleven affected tables carries the prefix and refuses — touching nothing — if one does
   not. Only then does it TRUNCATE the seven tables whose delete-guards permit nothing else, and
   DELETE by prefix from the three that have no guard. `supabase/probes/dev_teardown_probe.sql`
   shows the refusal firing on a planted real-looking row and passing on a clean database.

4. **It was run.** As of 8 September 2026 the eleven fixture tables hold zero rows. The migration-
   seeded masters — operator, location, category, subcategory, app_setting, discount_tier — are
   untouched.

## The rule that follows

**Do not run `dev_seed.sql` against `hjidocpqcrfbjucvqggu`.** If a fixture is needed for testing, it
needs a second project or a local Supabase, and that is a decision to make before the first real
catalogue row lands — after which the teardown will refuse to run, correctly, and there is no
sanctioned way to remove fixture rows from among real ones without weakening rule 12's enforcement.

## What the teardown cannot do, and why that is right

It cannot remove the fixture from a database that also holds real rows. `movement`, `unit`,
`rental_order`, `ledger_entry` and `repair_job` carry BEFORE DELETE triggers that raise
unconditionally, for every role, with no bypass — that is rule 12, and it is the reason a
`delete ... where id like '00000000-…'` cannot run on those tables at all. The alternatives are a
session-variable bypass baked into the five guard functions (a migration, and a deliberate weakening)
or a temporary trigger disable (forbidden). Both are decisions. The teardown refuses instead.

## Checking the state

```bash
set -a && . ./.env && set +a && PGPASSWORD="$DB_PASSWORD" psql \
  "host=aws-0-ap-south-1.pooler.supabase.com port=5432 dbname=postgres user=postgres.hjidocpqcrfbjucvqggu sslmode=require" \
  -c "select 'product',count(*) from product union all select 'movement',count(*) from movement union all select 'customer',count(*) from customer;"
```

Anything non-zero there that does not carry the seed prefix is real, and the fixture may never be
run there again.
