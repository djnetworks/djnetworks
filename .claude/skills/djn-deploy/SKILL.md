---
name: djn-deploy
description: Deploy changes to the DJ Network's rental system — migrations, Edge Functions, the static frontend, and the Google Sheet mirror. Use when shipping a change, when a fix "isn't showing up", or when planning what must be deployed for a given change.
---

# Deploying DJ Network's

Project ref `hjidocpqcrfbjucvqggu`, region `ap-south-1`.

## Frontend hosting — Cloudflare Pages

`web/` is deployed to Cloudflare Pages, connected to the private GitHub repo, auto-deploying on
every push to `main`. **No build step**: build command empty, output directory `web`.

GitHub Pages was rejected, not merely unavailable: it needs the repo public on a free plan, and
publishing the repo would publish `docs/`, the backlog and every migration. The publishable key is
safe to publish — `0017` made membership of `operator` the thing policies test, so a stranger with
the key reads nothing — but that is a reason the *key* is safe, not a reason the *schema* should be.

Cache-busting on deploy, in this order, or the fix does not reach the phone:

1. bump the `?v=` string on every asset link in every HTML file
2. bump `APP_VERSION` in `web/config.js`
3. bump `CACHE` in `web/sw.js` — the shell is cache-first, so a stale service worker outlives
   everything else. `sw.js` itself is served `no-cache` via `web/_headers` so it can always be
   replaced.

`web/_headers` carries the security headers Cloudflare applies. There is deliberately no CSP; see
the comment in that file.

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
