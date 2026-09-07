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

| Probe | What it proves |
|---|---|
| `0021_permissions_probe.sql` | Every table, both directions: an owner reads and writes; a staff account holding two keys reads 0 ledger rows and is refused everywhere it should be; an account with no operator row reads 0 rows from all seventeen. It creates two throwaway `auth.users` rows and rolls them back. |
