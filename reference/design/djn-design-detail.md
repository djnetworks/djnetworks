# DJ Network's — design detail

Exact values for spacing, radius, elevation, sizing, states and type. Derived from the EKUM v6
system spec, scoped to this app.

**This file is not authoritative over the build.** Where it and `web/tokens.css` disagree,
`tokens.css` wins — it carries measured contrast figures and this file does not. Where it and
`CLAUDE.md` disagree, `CLAUDE.md` wins. This is a consistency reference, not a mandate to redesign.

**What it deliberately omits.** The EKUM spec also describes that product's navigation, screens,
feed, chat and commerce model — buying feeds, supplier posts, quote cards, chain transparency,
resale masking. None of that applies here. EKUM is a marketplace people browse; this is a tool one
man and his staff operate under time pressure at a van. Same materials, different building. Carry
the values, not the surfaces.

---

## 0 · The colour split — read before using any hex

The EKUM spec lists `--muted #828282` as "secondary text" and `--danger #E5484D` as danger. In this
app **those are fill and rule values only**. Text uses the darkened partners, because the spec's
values fail WCAG AA for text:

| role | fill / rule | text |
|---|---|---|
| muted / neutral | `--muted #828282` — 3.84 on white | `--ink-faint #6B665F` — 5.69 on white, 5.14 on warm |
| danger | `--danger #E5484D` — 3.91 on white | `--bad #B42F33` — 6.19 on white, 5.59 on warm |

`--edge` is `--muted` **on purpose**: 3:1 is the WCAG 1.4.11 bar for the boundary of something you
aim at, and a field or button edge is exactly that. It is not a licence to use `#828282` on a
divider — that is what produced the doubled near-black rules between every list row, fixed on
8 September. Dividers are `--line #E7E8E6`.

Everything else comes from `web/tokens.css`. Do not restate hexes in screen files.

---

## 1 · Typography

Inter throughout. **Legibility floor: any text carrying a decision is ≥ 12px.** 11px is for pure
metadata only.

**Inputs are pinned to 16px, deliberately — do not "fix" this back to the body size.** iOS Safari
zooms the page whenever a focused field is under 16px, on the one device this app is built for.
Body is 14px as specified above; `.field__input`, `.field__select` and `.field__area` set 16px
explicitly rather than inheriting. Decided 8 September after the consistency pass raised it.

| element | size | weight |
|---|---|---|
| Page title | 24–25px | 700 |
| Section head | 20px | 700 |
| Card title | 15–17px | 700 |
| Body | 14px | 500–600 |
| Section label (uppercase, .09em) | 12px | 800 |
| Metadata / timestamp | 11–12px | 500–700 |
| Metric / big count | 22–25px | 700–800, teal |

Line-height: headings 1.05–1.2 with -.02em on large titles; body 1.45–1.55; metadata 1.35–1.45;
prices and counts 1.0 at weight 800–850.

---

## 2 · Elevation and radius

**Elevation law.** Shadow means floating *over* the page — sheets and toasts, and nothing else in
this app. Chrome is attached, not floating: the top bar and bottom nav are solid and hairline-
separated, and cast no shadow. All page content
is flat — solid fill plus a hairline border or divider, never a shadow. This is why the reports
screen has exactly one raised card.

| element | shadow |
|---|---|
| content — cards, rows, tables, forms | **none** |
| top bar | **none** — a bottom hairline in `--line` |
| bottom nav | **none** — a top hairline in `--line`, solid `--surface` |
| bottom sheet | `0 -15px 45px rgba(0,0,0,.12)` |
| toast | `0 6px 24px rgba(0,0,0,.18)` |
| scrim behind a sheet | `rgba(51,39,27,.45)` |

**This app has no floating chrome.** No floating navigation capsule, no raised FAB, no floating
action buttons of any kind. The bottom nav is attached to the bottom edge, solid, separated by a
hairline. Only things that genuinely sit *over* the page — a sheet, a toast — cast a shadow. The
EKUM spec's iOS liquid-glass capsule, its raised teal FAB, and the shadow tokens for both do not
apply here and must not be reintroduced.

**Radius, concentric — never a sharp corner inside a rounded one.**

```
card / info block ........ 16px      button ................... 14px
inner block / control .... 12px      input / field ............ 11px
thumb / media tile ....... 12px      chip / badge / count ..... 999px
bottom sheet top ......... 22px      icon circle / avatar ..... 50%
```

Content is flat, full-width and divider-separated: job lists, equipment rows, ledger entries,
customer lists. Rounded bordered cards are for info blocks and forms — not for list items.

---

## 2b · Chrome and density

**Content gets the screen. Chrome takes as little as it can.** On a 375×667 phone, every pixel of
header is a row of real work pushed below the fold.

- **One header row.** Wordmark or screen name, and the account control. Nothing else lives there.
  A screen does not print its own name twice — if the nav slot already says Jobs, the header does
  not repeat it.
- **Total chrome above content: 96px maximum**, including any department strip. If a strip pushes
  past that, the strip scrolls away with the content rather than pinning.
- **No sub-headers that only announce.** A section label earns its place when it separates two
  kinds of thing on one screen; it does not earn it as a caption over the only list present.
- **No helper text.** Not under headings, not under fields, not beside buttons. The exceptions are
  counted and deliberate: a caveat that changes how a number should be read (billed includes
  jobs not yet dispatched), an empty state saying what will appear here, a loading state, and an
  error saying what was preserved and what failed. Everything else goes.
- **No decorative counts, no greetings, no dates printed for their own sake.** A number appears
  because someone acts on it.
- **Fields carry their label and nothing else.** Constraints go in the placeholder.

The test: cover the chrome with a thumb. If the screen still tells the operator what to do, the
chrome was doing nothing.

---

## 3 · Spacing

| context | padding / spacing |
|---|---|
| Screen horizontal margin | 16px; 0 for edge-to-edge row lists |
| Info card / form section | 14px all sides |
| Detail card | 14px (16px horizontal, edge-to-edge variant) |
| Metric card | 13px 12px, min-height 72px |
| Task row (Home pending work) | 13px vertical, 16px horizontal; grid `40px 1fr 20px`, gap 11px |
| List row with thumbnail | 10px 16px; grid `104px 1fr`, gap 12px |
| Order / job row | 13px 16px |
| Button | 0 16px (primary CTA 0 18px) |
| Input / field | 11px all sides |
| Chip | 6–8px vertical, 10–12px horizontal |
| Badge | 3–5px vertical, 8px horizontal |
| Bottom sheet | 10–12px top, 18px sides, `20px + safe-area` bottom |
| Section label | 16px above, 8px below |
| Gap between stacked cards | 9–12px |
| Gap in 2-column grids | 12px × 8px |

---

## 4 · Sizing

```
Avatar / icon circle .... row 48px · compact 39–41px · task icon circle 38px (21px glyph)
Icon glyph .............. nav 23–25px · action row 23–25px · mini 14px · inline 18px
Icon button (tap) ....... 34–42px circle
TOUCH TARGET FLOOR ...... 46px  — this app's figure, enforced; chips ≥ 32px
Chrome .................. top bar 48px · bottom nav 60px · nav item 56px
                          department strip 40px, and only where a department has >1 screen
                          total chrome above content: 96px maximum
Progress / stepper ...... 4px tall, pill
```

`min-height` does not apply to `display: inline`. Any `<a class="btn">` needs an explicit display
or it silently misses the 46px floor — that shipped once, on the only route from a customer to
their money.

---

## 5 · Interactive states

| state | treatment |
|---|---|
| Hover (desktop) | primary → `--teal-dark`; rows → `#F6F5F1` |
| Pressed | scale .94–.97; iOS opacity-dim .6 over 90ms; Android ripple |
| Selected row | `--foam` fill + teal checkmark, 26px circle, white bg, teal tick |
| Active nav | teal icon and label, soft-teal pill behind the icon |
| Active tab | 2px teal underline |
| Active chip | foam background, teal text |
| Disabled | reduced opacity, no press feedback, not tappable |
| Input focus | 3px ring `rgba(43,115,121,.20)`, teal border |
| Count at zero | dull grey, never tangerine; bold teal above zero |

---

## 6 · Laws that apply here

1. **Elevation law** — floating things cast a shadow; content is flat.
2. **One attention colour per screen** — tangerine at most once, for genuinely urgent work only.
   Counts are teal.
3. **Legibility floor** — decision text ≥ 12px.
4. **Motion means certainty** — every animation answers *did it work?* or *where did I go?*
   Success is a drawn checkmark plus a **durable confirmation carrying a timestamp**. No confetti,
   bounce or parallax. *The ledger still uses a 3.5-second toast; that is a live violation.*
5. **Switcher grammar** — segmented = scope, tabs = status, chips = filter. Never mixed.
6. **One priority per screen** — one primary action, and a hierarchy under it.
7. **Placement — amended for this app.** A list row carries **at most one inline action**;
   everything else lives on the detail screen. The EKUM spec sends the remainder to an overflow
   "⋯" menu. We removed overflow menus: a closed `<details>` still laid out an absolutely
   positioned child that was invisible and tappable. Do not reintroduce one.
8. **Card segmentation** — many decisions become summarised sections, not one long form; the first
   is required, the rest collapse with a state summary; at most five.
9. **Commercial certainty** — before an action, show who, what, quantity and rate, and the
   consequence. After it, a durable success with a timestamp.
10. **Interruption and weak networks** — preserve drafts, filters and scroll position; taps are
    idempotent; never leave the operator unsure whether something saved.
11. **Don't underestimate the user** — simple, not childish. Chachu runs a business.
12. **Chrome is attached and minimal** — no floating nav, no FAB, no floating buttons. One header
    row, 96px of chrome at most, and no text on screen that the operator does not act on.
13. **Status states the real state** — never a bare "Active" or "Confirmed" without the next
    action, and **never ₹0 for something unpriced**. Show what is actually true: "Rate needed",
    "Cost not recorded".

---

## 7 · Information hierarchy

Do not give every field equal weight. Lead with what changes a decision; keep the rest quieter or
one tap deeper. Tag only what speeds recognition.

| surface | order of prominence |
|---|---|
| Home count button | label → pending count (teal) |
| Home pending row | action verb → customer → quantity/status → chevron |
| Job row | customer → product summary → dates → state → next action; **order ID is subtext** |
| Equipment row | product → piece number → location → state; **overdue louder than out or at repair** |
| Ledger row | customer → amount → what it was for → date; receivable and deposit never blended |
| Product card | image → name → rate → category |
| Reports row | product → the figure → what qualifies it (pieces unpriced, days idle) |

Keep defaults quiet and emphasise exceptions: overrides, restrictions, warnings, overdue. Avoid
repeating the same fact across name, metadata, chip and helper text. Validate every dense, sparse,
long-name, empty, refused and offline state at 320px and 375px before calling a screen done.

---

## 8 · Checklist

1. Values taken from `tokens.css`; no hex restated in a screen file.
2. `--muted`/`--danger` on fills and rules only; text on `--ink-faint`/`--bad`.
3. `--edge` on controls only. Dividers are `--line`.
4. Decision text ≥ 12px; tap targets ≥ 46px, including `<a class="btn">`.
5. Content flat; only chrome, sheets and toasts cast a shadow.
6. Switcher grammar correct.
7. One primary action; one inline action per row; no overflow menus.
8. Status states the real state; never ₹0, never 0% for a missing cost.
9. Durable confirmation with a timestamp for anything that writes.
10. No horizontal overflow and nothing trapped under the nav at full scroll, at 320px and 375px.
11. No floating nav, no FAB, no floating buttons. Nav and header are attached, solid, hairline-
    separated, and cast no shadow.
12. Chrome above content ≤ 96px. Header does not repeat the nav slot's name.
13. Every remaining sentence on the screen is a caveat, an empty state, a loading state or an
    error. If it is none of those, delete it.
