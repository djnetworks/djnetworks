> # ⚠ SUPERSEDED — 2026-09-08
>
> **The Brand Kit arrived.** `reference/design/Ekum_Brand_and_UI_Laws.md` (Design Bible v6) is now
> the source of truth for colour, type, elevation, radius, components, shell and copy. It is the
> document this file kept saying was missing.
>
> Everything below was **derived provisionally** from the Phase 1 interactive bible precisely
> because v6 did not exist. Read it for the *reasoning* — the measured contrast ratios, why
> `--border` was split from `--edge`, why a hex outside `tokens.css` is a bug — all of which still
> holds. Do **not** read it for values.
>
> The one thing that carries over unchanged is the rule at the top: `web/tokens.css` is the only
> file that names a colour, so replacing the palette is a one-file change. That is what made this
> supersession cheap, and it is why the rule was written.
>
> **What v6 governs, and what it does not:** Parts A, B, E, F and G apply to this app. Parts C, D
> and H are Ekum's own navigation, screens and product architecture — a textile trading network
> with followers, resale chains and quote cards. They are not this business and are deliberately
> not imported. See the plan in `docs/decisions.md`.
>
> Where this file and v6 disagree, **v6 wins**, with two measured exceptions recorded in
> `docs/decisions.md`: v6's `muted #828282` fails AA for body text at 3.47:1, and its
> `danger #E5484D` fails at 3.53:1. Both are kept for fills and borders and replaced for *text*.

# Design — where the look comes from, and what is still provisional

## The one thing to know

`web/tokens.css` is the only file in `web/` that names a colour. Every other file reads a
variable. When a real Brand Kit arrives it replaces that file and nothing else moves.

A hex anywhere outside `tokens.css` is a bug, not a special case:

```bash
grep -rnE '#[0-9a-fA-F]{3,8}\b' web/*.css web/*.html web/app.js | grep -v tokens.css
```

Two exceptions the grep will find, both deliberate: the `theme-color` meta tag in each page's
`<head>`, which a browser reads before any stylesheet exists, and `web/manifest.webmanifest`,
which is JSON and cannot read CSS.

## Provenance

The source is `reference/design/Ekum_Design_Bible_Interactive_Phase_1.html` and
`web/assets/ekum-icon-1024.png`.

**The bible does not own the look, and says so twice** — "Interaction architecture · not visual
styling", and "The Brand Kit owns visual specifications and components". The Brand Kit is not in
this repo. So there was no visual source of truth to implement, and every value in `tokens.css` is
derived from two things only:

1. the bible's own `:root` block — its document CSS, not its guidance
2. the icon, sampled by pixel: ground `#138F93`→`#0E969E`, disc `#F8A12C`, letters `#FFFFFF`

The icon confirms the teal-plus-orange-on-white grammar. Its own teal is not used: white on
`#0E969E` measures 3.0:1 and these screens are read in a godown.

**Everything in `tokens.css` is provisional and labelled so in the file.** Nobody should later find
this palette and mistake it for a settled system.

## Where the palette departs from the bible

Three of the bible's values cannot carry text on this app's grounds. Each is kept under its own
name — it is right for what the bible uses it for, a chip fill or a dot — with a text-safe partner
beside it.

| Bible value | On `#F7F3EA` | Used here as text? | Partner |
|---|---|---|---|
| `--grey #828282` | 3.47:1 | no | `--ink-faint #6B665F` — 5.14:1 |
| `--success #22C55E` | 2.06:1 | no | `--ok #146C38` — 5.87:1 |
| `--error #E5484D` | 3.53:1 | no | `--bad #B42F33` — 5.59:1 |

The first is not theoretical. `--ink-faint` is the colour of every `.field__hint` at 12px, and the
hints are where the explanations live. It had already been moved once, from `#8b939d` at 3.1:1,
because they were being read in poor light. Adopting the bible's grey verbatim would have quietly
undone a fix already paid for.

The bible had solved this for itself and the answer is borrowed rather than invented: its `.chip`
rules pair each semantic fill with a darker ink — `.chip.error{color:#B42F33}`,
`.chip.warning{color:#765300}`, `.chip.orange{color:#A65B00}`, `.chip.info{color:#1559BB}`. Those
are used verbatim. Only `--ok` had no partner in the bible, so `#146C38` is the one value on the
page with no source but arithmetic.

### Re-measuring after a change

Change a token and re-run this. It asserts on numbers; a "looks fine" is not a result.

```bash
python3 - <<'PY'
def lin(c):
    c = c / 255
    return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4
def L(h):
    h = h.lstrip('#'); r, g, b = (int(h[i:i+2], 16) for i in (0, 2, 4))
    return 0.2126 * lin(r) + 0.7152 * lin(g) + 0.0722 * lin(b)
def cr(a, b):
    la, lb = L(a), L(b); hi, lo = max(la, lb), min(la, lb)
    return (hi + 0.05) / (lo + 0.05)

WARM, WHITE = '#F7F3EA', '#FFFFFF'
# text, background, what it is
PAIRS = [
    ('#33271B', WARM,      'ink on the page'),
    ('#3D3A37', WHITE,     'ink-soft in a card'),
    ('#6B665F', WHITE,     'ink-faint — every .field__hint'),
    ('#6B665F', WARM,      'ink-faint on the page'),
    ('#2B7379', WHITE,     'accent as text'),
    ('#FFFFFF', '#2B7379', 'white on the primary button'),
    ('#146C38', '#E6F4EC', 'ok on its badge tint'),
    ('#765300', '#FDF0E3', 'warn on its badge tint'),
    ('#B42F33', '#FDECEA', 'bad on its badge tint'),
    ('#1E595E', '#E8F2F1', 'teal-deep on foam'),
    ('#3D3A37', '#ECEAE1', 'muted badge'),
    ('#FFFFFF', '#B42F33', 'white on the danger button'),
]
bad = 0
for t, b, what in PAIRS:
    r = cr(t, b)
    ok = r >= 4.5
    bad += not ok
    print(f'{"PASS" if ok else "FAIL"}  {r:5.2f}  {what}')
print('\n' + ('all pairs clear 4.5:1' if not bad else f'{bad} PAIR(S) BELOW 4.5:1 — fix before shipping'))
PY
```

## Type

The bible declares `Inter` with a system fallback and ships no font file. That declaration is
copied exactly and **no webfont is loaded**. A font from a third-party host would be the only
remaining public-internet dependency in the app — `web/vendor/supabase.js` exists precisely because
the CDN import was removed — it would not be in the service worker's shell, and on a dead 3G link
at a venue it buys a repaint or invisible text in exchange for nothing anyone can see. Inter
renders where it is installed.

## The mark

**Typographic. There is no logo file.** The flyer artwork is not used anywhere: it carries a
visible AI watermark and its shield reads "EVENTS & RENTAL EQUIPE". A misspelling on the sign-in
screen of the system that runs the business is worse than no mark at all.

The lockup — an orange dot, then the name, `DJ` heavier than `Network's` — is the bible's own
`.brand` grammar (`.brand-dot`, `.brand-name`). One size control, `--wm`; the topbar sets it small
and sign-in large, and the dot, the tracking and the gap all scale off it.

The favicon and PWA icons in `web/assets/djn-icon-*.png` are built from that wordmark, not from
the EKUM icon. Regenerate them with the script in the commit that added them; the content sits
inside the centred 80% circle so a launcher that crops to a circle cannot clip the letters.

**EKUM appears exactly once: "Built by EKUM" under the operator sign-in button.** Never on
`portal.html`. That page is opened by a wedding family on a WhatsApp link, and a second brand there
is a question they have to answer — who is EKUM, and why do they have my ledger — with nobody to
answer it.

## The four laws that were applied

The bible has nine laws, nine patterns, three roles and a navigation model. Most of it belongs to a
different product — a textile trading app with suppliers, buyers and collections. Four rules
transfer whole, and only those four were imported.

**Icons need labels.** Every icon-only control now carries a visible word: six `✕` sheet-close
buttons became `Close`, the spec-row and charge-row `✕` became `Remove`. The `aria-label` came off
with the glyph, because the text is now the name. The chevrons on list rows stayed — the row itself
is the labelled control and the chevron is an affordance, not a control.

**Numbers are familiar; software words are not.** See the table below. `unit` / `pool` /
`consumable` and the `fulfilment_state` values are rendered through `trackLabel`, `trackBadge` and
`fulfilLabel` in `app.js`, so the filter dropdown and the badge on the row it returns cannot say
two different things about the same order. They did: the dropdown offered "Part sent" and the row
was labelled "part dispatched".

**Image recognition beats reading.** The dispatch pick list leads with the product photograph.
`DJN-SPK-15` and `DJN-SPK-18` are two strings that differ by one character; the two photographs do
not. The photographs are fetched as Blobs into the *same* IndexedDB record as the job, so they are
there in a godown with no signal — a picture that is blank exactly where recognition matters is
decoration. The short code stays underneath the image, so a missing photo, a slow photo and a
failed photo all degrade to the same readable tile rather than a broken-image glyph.

**Under two minutes.** Tap counts are in the table below.

**Not imported:** the three roles, the collection model, the 3-tab vs 5-tab navigation question,
the supplier/buyer permission patterns. One operator, one job, one nav.

## Copy: the words that changed

| Was | Now | Why |
|---|---|---|
| Dispatch *(tab, screen, button)* | Send out / **Send these out** | A courier's word. The screen's own prose already said "loading", "loaded", "still to go". |
| Dispatch method | How is it going out? | |
| Analysis *(tab, screen)* | Numbers | The bible's anti-pattern list names "Dashboard" by name. |
| Utilisation *(column, tab)* | How hard it works | |
| Dispatches *(column)* | Times sent out | |
| Hire frequency / Dead stock / Damage rate *(tabs)* | How often it goes out / Not moving / Breakages | |
| Reversal of a charge | Cancel a charge | The portal already rendered `reversal` as "Charge cancelled". |
| Pieces & intake | Pieces | "Intake" is warehouse software. |
| Counted (pool) / Consumable | Counted stock / Used up, never comes back | `pool` is a column value. |
| badges `unit` `pool` `consumable` | numbered · counted · used up | |
| Nothing dispatched / Partly dispatched / Fully out / Partly returned / All returned | Nothing sent yet · Part sent · All sent, none back · Part back · All back | |
| Partial dispatch is normal | Sending part of a job is normal | |

**Kept, deliberately.** *Ledger* — a khata is what the business already calls it, and it is
accounting language, not software language. *Sub-hired*, *written off*, *deposit*, *piece*,
*godown* — all trade words. *Return* — already plain.

## Tap counts

Counted as deliberate finger contacts. Opening a native `<select>` and choosing from it is two.
Typing is counted separately, because a keyboard on a phone is not one tap — it is a keyboard
covering the half of the screen that explains what is about to happen.

### Intake — six speakers arrive, product already in the catalogue

| | Before | After |
|---|---|---|
| Pieces tab | 1 | 1 |
| Product select (open, choose) | 2 | 2 |
| Add pieces | 1 | 1 |
| How many | 1 tap **+ keyboard**: clear the `1`, type `6` | 1 tap on the `6` chip |
| Where they live | 0 — first location prefilled | 0 |
| Cost / date / condition / ownership | 0 — inherited from the product | 0 |
| Create pieces | 1 | 1 |
| **Total** | **6 taps + 2 keystrokes** | **6 taps, no keyboard** |

Driven signed in: six pieces created, numbered 4–9, no keyboard opened. The tap count did not move
and the honest claim is not that it did — what moved is that the on-screen keyboard no longer
covers the preview that says what is about to be created.

### Send out — six pieces on one job

| | Before | After |
|---|---|---|
| Send out tab | 1 | 1 |
| Open the job | 1 | 1 |
| Loading from | 0 — first location prefilled | 0 |
| Choose the pieces | 6 — one tile each | **1** — "Pick 6" |
| How is it going out | 0 — "Delivered by chachu" prefilled | 0 |
| Received by | 0 — prefilled from the venue contact | 0 |
| Send these out | 1 | 1 |
| **Total** | **9 taps** | **4 taps** |

The six-piece row is arithmetic. What was actually driven, signed in, was `DJN-2609-0001`, which
owed two: "Pick 2" selected exactly two of the three pieces on the shelf, the summary read
"2 piece(s) selected", and the write landed — "2 item(s) sent out", then "2 of 2 loaded". Five taps
became four there; the saving is one per piece beyond the first, so it grows with the size of the
job, which is the direction that matters.

`Pick N` is capped by **both** what the order still owes and what is on that shelf, and takes the
tiles in the order they are shown — pinned piece first — so what gets selected is what is being
read. The tiles still light up individually, any one can be tapped off, and the sticky button is
still a separate deliberate press. Counted-stock lines get the same thing as `All N`, which fills
the quantity box rather than defaulting it: **a quantity that arrives without anybody choosing it
is a quantity nobody checked.**

## What the review changed after the pass

`ui-reviewer` was given the failures to hunt for rather than asked whether it looked right, and it
found four defects. Two were mine:

- **"Pick N" wiped the counted-stock box while still sending the number.** `renderLines()` re-emitted
  the pooled input with a literal `value="0"`; `POOLPICK` was untouched and `doDispatch()` reads
  `POOLPICK`. Measured: type 7 cables, tap "Pick 2" on the speakers, box reads **0**, POST carries
  **7**. Seven cables leave the godown under a box saying zero. The input now renders `POOLPICK`'s
  own value. First render is still `0`, because `POOLPICK` is empty — the rule that a quantity must
  be chosen still holds.
- **`.spec-row` stacked on a phone**, which the `✕` → `Remove` swap had forced. It tripled the
  product specs block: the sheet measured **2834px** at 375px. Only the four-control charge row
  stacks now; the sheet is **2444px**, and the charge row's Remove is no longer the widest, lowest
  control in it.

Two were pre-existing and are worth knowing because this pass leans on both:

- **`db.js`'s `tx()` resolved a cache MISS to the `IDBRequest` object**, which is truthy, so
  `dispatch.html`'s carefully written "This job is not on this phone" state block was unreachable and
  the operator got `Cannot destructure property 'order' of 'c.data'` instead. Offline dispatch is
  this pass's headline feature and its failure path had never worked.
- **`return.html` had no loading state** — six seconds of blank warm page under the heading,
  measured, on the screen used standing at the van.

It also found that `<td data-label="Dispatches">` is the row label below 620px where `<thead>` is
hidden, so the phone said DISPATCHES while the laptop said "Times sent out" — the copy sweep had
missed the mobile half of the table. Six other schema words were still visible and are now fixed,
and the operator's ledger list, which rendered `e.type.replace(/_/g, ' ')` raw, now goes through
`entryLabel` in `app.js`: chachu read `rental` and `deposit in` while the customer read
"Equipment hire" on the same row.

**Contrast held.** All fifteen ratios claimed in `tokens.css` were recomputed independently and
match to ±0.01, and 38 further pairs the CSS renders but the file does not claim are all above 4.5
(tightest: the photo-fallback tile at 4.72). Two non-text findings are in `docs/backlog.md`: the
skeleton shimmer was 1.036:1 and invisible — now 1.22:1 — and `--line` is 1.11:1 against the ground
where WCAG 1.4.11 wants 3.0, which is a token decision and not one to take unilaterally.

## Density, measured

Pixels from the top of a 375px viewport to the first row of real content — the cost of chrome,
heading and blurb before anything useful appears. Measured before and after Pass G.

| screen | before | after | |
|---|---|---|---|
| Today | 372 | **211** | −43% |
| Orders | 336 | **217** | −35% |
| Can I say yes | 512 | **407** | −21% |
| Send out | 176 | **141** | −20% |
| Return | 152 | **121** | −20% |
| Customers | 198 | **165** | −17% |
| Ledger | 254 | **213** | −16% |
| Products | 254 | **217** | −15% |
| Numbers | 555 | **484** | −13% |
| Equipment | *nothing rendered* | **173** | a dead end became a list |

Equipment is the one that matters most and has no percentage: it showed a dropdown and the words
"Pick a product" until you already knew what you wanted, on the screen whose job is telling you
what you own.

Where the height went: card padding 16px → 11px, list gaps 10px → 6px, row padding 12px → 9px,
`h1` 22px → 19px, field margins 14px → 10px, and the top bar from 59px of scrolling tab strip to
40px of identity. On Today the four count tiles moved below the three date sections, and on Orders
the day-count convention moved from the subtitle to the field it governs.

**Nothing under 44px moved.** `.nav__item` is 63×52, `.btn` 44, `.card-action` 44 — it was 36 after
the first cut and was put back. The reference chip is the exception and it is deliberate: it stays
21px tall because it is subtext, and its TAP AREA is 44px, extended past the text with a
pseudo-element. The thing you see and the thing you hit are allowed to differ; the thing you hit
is the one that has to be 44.

## What a real Brand Kit would replace

`web/tokens.css`, and the three derived values in it that exist only because the bible's semantic
colours are fills rather than inks. Nothing else. The wordmark would become a component if a real
mark is ever drawn; until then it is text, which is the honest state.

---

## A finding for the Brand Kit's owner

**v6 sets two colours as text without giving them an ink partner, and both fail its own Law 3.**

Law 3 is a legibility floor. A2 states four semantics as ink-on-fill pairs — success `#1B7F43` on
`#E9F8EF`, warning `#9B5C00` on `#FFF3D1`, info `#2B7379` on `#E8F2F1`, neutral `#828282` on
`#F1F1EE` — which is the right construction. Measured (WCAG 2.1, sRGB):

| pair | ratio | AA body text (4.5:1) |
|---|---|---|
| success `#1B7F43` on `#E9F8EF` | 4.60 | pass |
| warning `#9B5C00` on `#FFF3D1` | 4.84 | pass |
| info `#2B7379` on `#E8F2F1` | 4.80 | pass |
| **neutral `#828282` on `#F1F1EE`** | **3.40** | **fail** |
| **muted `#828282`** on paper `#F7F3EA` / white | **3.47 / 3.84** | **fail** |
| **danger `#E5484D`** on paper / white | **3.53 / 3.91** | **fail** |
| white on `#E5484D` (a solid danger button) | 3.91 | fail |

`muted` is specified as "secondary text, metadata" and `danger` is put into text by E1
("Destructive: red text in overflow only"). At 11–12px — which A3 permits for metadata — neither
clears AA on either of v6's own grounds. The neutral **pair** fails as stated.

This is not a style disagreement. v6's own one-line standard is *"a trade-smart but low-tech user on
an older phone in a busy market"*. An older phone means a dimmer, lower-gamut panel; a busy market
means glare. Those are the conditions under which 3.4:1 stops being readable, and they are the
conditions the document names for itself.

**The fix is the pattern v6 already uses,** applied twice more — keep the hex as the fill, add a
darker ink. What this app uses, and what it measured:

    v6 muted  #828282  →  ink #6B665F   5.14 paper · 5.69 white · 5.03 on #F1F1EE
    v6 danger #E5484D  →  ink #B42F33   5.59 paper · 6.19 white · 5.41 on a #FDECEA tint

Both keep the hue and the semantic; neither changes the fill, the border or the icon stroke. A
solid-danger button also needs ink text rather than white, or a darker fill.

*Raised from the DJ Network's implementation, 2026-09-08. Ratios reproducible with the checker
described above.*
