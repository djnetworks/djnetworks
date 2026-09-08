---
name: djn-deploy
description: Deploy changes to the DJ Network's rental system — migrations, Edge Functions, the static frontend, and the Google Sheet mirror. Use when shipping a change, when a fix "isn't showing up", or when planning what must be deployed for a given change.
---

# Deploying DJ Network's

Project ref `hjidocpqcrfbjucvqggu`, region `ap-south-1`.

## Frontend hosting — GitHub Pages, deployed by Actions

Live at **https://djnetworks.github.io/djnetworks/**. Every push to `main` runs
`.github/workflows/pages.yml`, which uploads `web/` as the Pages artifact and deploys it. **No build
step and nothing to run locally.** Pages' built-in source can only serve the repository root or
`/docs`, and this site is in `web/` — pointing it at `docs/` would publish the backlog as a website
and still not serve the app — so the workflow builds the artifact instead. Pages' source is set to
**GitHub Actions**, not to a branch.

The repository is public. It was audited first: every blob in the history, not just `HEAD`, scanned
for JWT-shaped tokens, `sb_secret_` values and service-role keys, with none found, and `.env` present
in no commit on any ref.

**The site is served from a SUBPATH**, `/djnetworks/`. Everything in `web/` must stay relative —
`sw.js` registered as `'sw.js'`, the manifest's `"scope": "./"`, the whole `SHELL` list, every
`href` and `src`. One leading slash produces a site that loads and then silently fails to cache.

### Cache-busting on deploy, or the fix does not reach the phone

The version string is one literal replaced everywhere at once. Do it globally, not file by file:

```bash
grep -rl "<old>" web/ | xargs sed -i '' 's/<old>/<new>/g'
```

That must reach all four places, and the fourth is the one that was missed for the whole build:

1. the `?v=` on every asset link in every HTML file
2. `APP_VERSION` in `web/config.js`
3. `CACHE` in `web/sw.js` — the shell is cache-first, so a stale service worker outlives everything
4. **the import specifiers inside `web/app.js`** — `./config.js?v=…` and `./db.js?v=…`

Afterwards, prove it took: `grep -ro "<old>" web/ | wc -l` must be **0**.

**`web/_headers` IS NOT APPLIED.** GitHub Pages sends no custom headers. It is kept for a host that
can. Measured on the live origin: `Strict-Transport-Security` is sent by Pages itself;
`X-Frame-Options`, `X-Content-Type-Options`, `Referrer-Policy`, `Permissions-Policy` and both
`Cache-Control` rules are not, and a CSP `frame-ancestors` cannot be set either. The one that
mattered is framing, because the portal takes an access code — `portal.html` therefore hides itself
and reveals only on confirming it is the top window. Do not delete that guard while the site is on
Pages.

### A LIVE NETWORK LOG SHOWS WHAT LOCAL TESTING CANNOT

`app.js` imported `./config.js` and `./db.js` **bare**, while all thirteen HTML files asked for
`./config.js?v=<bust>`. A module's identity is its resolved URL, so those were two resources: two
network round trips for the same file on every page load, and two module instances of `config.js`.
Two unversioned entries sitting inside the one mechanism this section exists to protect.

It survived the entire build. Nothing about it is visible locally — both spellings come off the same
dev server in a millisecond, no error, no warning, and reading the source shows two import lines
that look ordinary. It appeared the first time the app was served from a real origin, as two lines
in the browser's network panel:

```
GET /djnetworks/config.js?v=2026-09-08-15 → 200
GET /djnetworks/config.js                 → 200
```

So: **after deploying, read the network log, not just the screen.** A screen that renders correctly
proves the code ran; the network log is the only place duplicate fetches, unversioned URLs, an
off-origin request that should not exist, and a 404 the app quietly swallowed are visible at all.
Check specifically that every same-origin JavaScript and CSS request carries the current `?v=`, and
that nothing is requested twice.

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

Static HTML, no build step, served from GitHub Pages at `/djnetworks/`.

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
- Cache-bust string bumped, and `grep -ro "<old>" web/ | wc -l` returns 0 — including inside
  `app.js`, whose import specifiers carry it too.
- If a mirrored column changed, the Sheet push has been re-run.

## After deploying

Open the app **on the live URL**, at a phone-width viewport, and walk one real flow end to end —
create an order, dispatch it, return it partially. The screens that break are almost never the ones
that changed.

Then open the network panel and read it. Localhost cannot show you a subpath problem, a duplicate
fetch, an unversioned URL or a missing header, and every one of those has been found here only after
the app was served from a real origin.
