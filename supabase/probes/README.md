# Probes

Rolled-back verification scripts. They are not migrations, they are not run by `supabase db push`,
and every one of them ends in `rollback`.

They exist because of the rule in `CLAUDE.md`: **there is no second pair of eyes on this database.**
Whoever writes the migration is the only person who checks it, so a clean run proves only that the
code agrees with itself. A probe is the mitigation — it states the expected value before reading the
actual one, asserts on numbers rather than on the absence of an error, and includes a **false
positive control**, because a policy that refuses everybody looks identical to one that works.

Run one against the development database:

```bash
set -a && . ./.env && set +a && PGPASSWORD="$DB_PASSWORD" psql \
  "host=aws-0-ap-south-1.pooler.supabase.com port=5432 dbname=postgres user=postgres.hjidocpqcrfbjucvqggu sslmode=require" \
  -f supabase/probes/0021_permissions_probe.sql
```

`0028` is a shell script rather than SQL, because the thing it has to prove — that an outsider is
refused — only exists over HTTP. Reading the policy would prove nothing; `product-images` carries a
policy that looks almost identical and is world-readable on purpose. It reads `.env` itself:

```bash
./supabase/probes/0028_return_photos_probe.sh
```

| Probe | What it proves |
|---|---|
| `0021_permissions_probe.sql` | Every table, both directions: an owner reads and writes; a staff account holding two keys reads 0 ledger rows and is refused everywhere it should be; an account with no operator row reads 0 rows from all seventeen. It creates two throwaway `auth.users` rows and rolls them back. |
| `0027_customer_figures_probe.sql` | Rule 14 on money that is joined, not selected. The owner reads a real receivable for a customer who owes something; an account holding only `sendout.write`/`returns.write` reads **NULL** for the same customer while still reading the job counts. It refuses to run at all against a database with no customer owing money — against a settled account, "hidden" and "settled" are indistinguishable and it would pass while the bug was present. |
| `0028_return_photos_probe.sh` | The private bucket, in real HTTP. Anonymous with no key, anonymous holding the publishable key, the guessed `/object/public/` URL and a signed-in account with neither permission are all refused; the operator uploads, reads, mints a signed URL that serves the bytes with no key at all, and that link stops working when it expires. Builds and destroys its own throwaway identity — including the `auth.identities` row without which GoTrue answers 500 and the arm degrades into a skip — and proves that identity is a *working* account by reading orders with it. Removes its test object through the Storage API, which is also the assertion that an unattached photo may be removed and an attached one may not. |
| `factory_reset.sql` (not a probe — a tool) | Not in this directory: `supabase/seed/factory_reset.sql`. Listed here only so nobody goes looking for a probe that tests it. It was verified by hand against the live database on 8 Sep 2026: unarmed → refused; armed with `app_setting.go_live` set → refused; armed on a seeded database → all 12 business tables to 0 with masters intact. It is destructive and self-arming; there is deliberately no rolled-back probe that runs it, because a probe that truncates is a contradiction. |
| `dev_teardown_probe.sql` | `dev_teardown.sql`'s refusal, both directions. On a clean database its assertion passes (the control — a check that refuses everything looks identical to one that works); then a real-looking customer row is planted with an ordinary `gen_random_uuid()` id, the teardown's own assertion is run verbatim, and the exception must fire. Rolls back. Exists because the seed was found loaded in production and an untagged fixture cannot be safely removed later. |
