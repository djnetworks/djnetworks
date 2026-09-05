---
name: djn-deploy
description: Deploy changes to the DJ Network's rental system — migrations, Edge Functions, the static frontend, and the Google Sheet mirror. Use when shipping a change, when a fix "isn't showing up", or when planning what must be deployed for a given change.
---

# Deploying DJ Network's

Project ref `hjidocpqcrfbjucvqggu`, region `ap-south-1`.

## Order of operations

Always in this order. Skipping it produces a frontend calling a view that does not exist yet.

1. **Migrations** — schema first.
2. **Edge Functions** — anything the frontend calls.
3. **Frontend** — last, with cache-busting.
4. **Sheet mirror** — re-run after any schema change that adds or renames a mirrored column.

## Migrations

```bash
supabase link --project-ref hjidocpqcrfbjucvqggu
supabase db push
```

Never edit an applied migration. Never renumber. If something is wrong, write the next migration.

Before pushing, check what is actually applied — the files on disk are not proof:

```bash
supabase migration list
```

After pushing, run the advisors and read them:

```
mcp__Supabase__get_advisors  (security, then performance)
```

## Frontend

Static HTML, no build step, served from GitHub Pages.

**Cache-busting is not optional.** The operator will otherwise open an old version, report a bug
that was fixed, and lose trust in the fix. Every deploy bumps the version query string on script and
style tags:

```html
<script type="module" src="./app.js?v=2026-09-04-1"></script>
```

If the operator reports that a change "isn't there", check this before debugging anything else.
It is the cause more often than not.

## The check list before you deploy

- `guardrail-reviewer` has read the diff.
- `logic-verifier` has run if the change touched movement, availability, orders, pricing or the
  ledger — and reported actual numbers, not "tests passed".
- Migration list matches `supabase/migrations/`.
- Cache-bust string bumped.
- If a mirrored column changed, the Sheet push has been re-run.

## After deploying

Open the app on a phone-width viewport and walk one real flow end to end — create an order,
dispatch it, return it partially. The screens that break are almost never the ones that changed.
