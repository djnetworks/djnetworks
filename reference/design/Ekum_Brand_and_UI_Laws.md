# Ekum — Design Bible (v6, complete & current)

The single source of truth for how Ekum looks, moves, speaks, and behaves. This version logs **every decision through v6**, including screen-level and flow-level decisions approved after the first bible. Where an old screen or an earlier decision conflicts with this file, **this file wins.** Ground truth = the v6 implementation (`ekum-v6.css` / `ekum-v6.js`) plus the approved change plan.

**The one-line standard:** WhatsApp familiarity, UPI certainty, native-gallery muscle memory, and modern commerce clarity — adapted to textile trade, for a trade-smart but low-tech user on an older phone in a busy market.

---

# PART A — FOUNDATIONS

## A1. Voice
- Plain, warm, direct. Never corporate, never tech-jargon, never condescending.
- **Ring Road test:** would a wholesaler in Ahmedabad/Surat understand this instantly without thinking? If not, rewrite.
- Trade words, not software words: *rate, order, set, piece, metre, dispatch, return, design number, enquiry, catalogue*. Banned: *workflow, permissions, configuration, module, issue, broadcast* (use "Send to buyers").
- **Describe events, not mechanisms.** "Vani Boutique wants rates for 2 designs" — never "no rates are visible to the buyer yet."
- **Name the result on every button.** "Send rates", "Confirm order", "Allow access", "Mark dispatched", "Send to buyers" — never "Submit / Proceed / OK / Broadcast".
- **No mixed-language phrases** (e.g. "Aaj: 3 order to see") unless a bilingual UI is adopted consistently. *(Change from an earlier build that used Hindi-English mixing on Home — removed.)*

## A2. Colour system
Ekum Teal is the identity; Tangerine is the single attention accent, used sparingly; everything else is quiet and warm. **These are the brand-aligned hexes — the earlier v6 draft used an off-brand teal (#287b80); corrected to #2B7379.**

| Token | Hex | Use |
|---|---|---|
| **Teal (primary)** | `#2B7379` | Counts, active nav, primary buttons, central New, links, active tabs |
| Teal dark | `#1F5559` | Pressed, gradient depth |
| Foam / teal-soft | `#E8F2F1` | Active-nav pill, icon circles, soft fills, selected rows |
| **Tangerine (accent)** | `#FF9700` | One attention highlight per screen, max — genuinely pending work only |
| Charcoal / ink | `#33271B` | Primary text |
| Warm paper | `#F7F3EA` | App background |
| Line / border | `#E7E8E6` | Hairlines, dividers, card borders |
| Muted | `#828282` | Secondary text, metadata |
| Success / live | `#1B7F43` (bg `#E9F8EF`) | Live, confirmed |
| Warning / draft | `#9B5C00` (bg `#FFF3D1`) | Draft, needs-attention, overdue |
| Danger / error | `#E5484D` | Destructive, failure |
| Info / scheduled | `#2B7379` (bg `#E8F2F1`) | Scheduled, informational |
| Neutral | `#828282` (bg `#F1F1EE`) | Inactive |
| Lemon | `#DEDE6E` | Rare tertiary, sparing |

- **Semantic colour is absolute:** live=green, draft=amber, scheduled/info=teal, restriction/warning=amber-red, neutral=grey. A colour never means two things.
- **Tangerine discipline:** ≤1 full-tangerine element per screen; soft tints (#FFF3D1) and the notification dot don't count. On Home, task counts use **teal, not tangerine** — tangerine is reserved for the single most-urgent signal, and Home CTAs are bold-when-content / dull-at-0 with no orange. *(Change: the orange Orders underline / orange tiles were replaced with an unambiguous dot/badge and teal counts.)*

## A3. Typography
- **Inter, everywhere.** No second typeface.
- **Legibility floor: interactive/decision-bearing text ≥ 12px.** 11px and below is only for pure metadata (timestamps, counts, tag chips). *(Change: the v6.2 compact pass pushed several labels to 10–11px; supplier names, chips, tabs, switch buttons, and profile-context buttons were raised back to ≥12px.)*
- Weights: 700–850 labels/CTAs, 600 body, 750–800 section labels (uppercase, `.09em`).
- H1 ~22–25px/700 · section label 12px/800 uppercase muted · card title 15–17px/700 · body 13–15px/500–600 · metric 22–25px/700–800 teal · metadata 11–12px.

## A4. Iconography
- One consistent modern SVG set, 2px stroke, rounded joins. **No placeholder/improvised glyphs.** *(Change: v6 replaced improvised symbols with a consistent set — filter, repost, send, users, box, store, buyer, archive, mute, pin, image, chevron, etc.)*
- Icons follow WhatsApp/Instagram/UPI conventions. Ambiguous glyphs get a label or are dropped.

## A5. Elevation & material
- **Elevation law:** shadows belong only to *floating* things — the bottom nav, sheets, the FAB, a sticky selection bar. All page content is flat: solid surface + hairline border/divider, no drop shadow. Shadow = hovering; flat = content.
- **Radius scale (concentric):** 16 card / 12–14 inner & buttons / pill (999) chips & counts / 11 inputs. Never a sharp corner inside a rounded one.
- **Content is flat, full-width, divider-separated** (v6 direction): Home tasks, catalogue rows, order rows, posts, detail summaries, and upload sections use hairline dividers edge-to-edge, not floating rounded cards. Rounded bordered cards are used for *info/section* blocks and forms only.

---

# PART B — UI LAWS (non-negotiable)

1. **Elevation law** — floating = shadow, content = flat.
2. **One attention colour per screen** — tangerine only, genuine pending work only; Home counts are teal.
3. **Legibility floor** — decision-bearing text ≥12px.
4. **Motion = certainty** — every motion answers "did it work?" or "where did I go?"; success = drawn checkmark + durable confirmation w/ timestamp; no confetti/bounce/parallax.
5. **Switcher grammar (strict):** *segmented* = which side/scope (Discover/My catalogue, Buying/Selling, Collections/Products) · *tabs* = status/stage (Pending/Active/Completed) · *chips* = content filter/selection. Never mix roles.
6. **Tabs archive, Home triages** — Home shows only what needs action now and empties as you work; Chats/Orders/Catalogue are permanent archives; the bell/notification centre holds passive awareness. No surface duplicates another's job.
7. **One priority per screen** — one primary action, one attention colour, clear hierarchy. Product screens prioritise images; relationship/record screens prioritise the business/person.
8. **Placement rule** — ≤1 primary + 2 secondary visible; the rest in an overflow "⋯" or Settings; destructive always in overflow, never a standing red button.
9. **Card segmentation** — many decisions become summarised cards/sections, not one long form; first section required, later ones optional/collapsed with a one-line state summary so nothing hides; ~5 max per screen.
10. **Commercial certainty (UPI-grade)** — before an important action show who/what/quantity-rate/visibility/consequence; after, a durable success state with status + timestamp.
11. **Interruption & weak networks** — preserve drafts/selections/filters/scroll; repeated taps safe/idempotent; the user never wonders whether it worked.
12. **Don't underestimate the user** — trade-smart, phone-comfortable; remove friction without looking outdated, childish, or oversimplified.
13. **Visibility always legible** — the user is never unsure who can see/do a thing; visibility & permission shown where the thing lives.
14. **New concepts via the closest familiar metaphor** — quote = a UPI-style request; "allow to resell" not "grant module"; teach through use, never a settings matrix.
15. **Status states the real state** — "Visible to VIP buyers", "Tier 2 opens in 18h", "Ready to dispatch" — never a bare "Active/Configured/Confirmed" without the next action.

---

# PART C — GLOBAL STRUCTURE & NAVIGATION

## C1. Root navigation
- Five fixed slots, stable positions, never reorder: **Home · Collections · New(+) · Chats · Orders.**
- iOS = liquid glass (see F1); Android = elevated solid. Active = teal icon + label with a soft-teal pill behind the icon. The centre **New** is a raised solid-teal circular FAB.
- Badges: numeric unread on Chats only; a dot on Orders when action is needed. Nothing else badged.
- Search & Profile are secondary, in the top bar; not primary destinations.

## C2. The New (+) menu
- A bold **2×2 grid** of large icons + short labels + large touch targets. **Four actions:** *Add collection · Add product · Order from supplier · Create order for buyer.*
- Removed: the ambiguous generic "Create order", and "Refer buyer" (now contextual on a supplier profile).
- **Order from supplier** flow: Supplier → Collection/products → Review order.
- **Create order for buyer** flow: Buyer → Source (own catalogue / curated / connected supplier) → Collection/products → commercial settings (buyer-facing rate/markup, source visibility) → Review & send. Products from multiple suppliers create separate supplier-wise orders.
- Shows only actions permitted for the signed-in staff member (unified business profile, permission-scoped).
- No fifth central action for curation — curation is contextual (starts from a supplier collection/product so source is preserved).

---

# PART D — SCREEN SPECIFICATIONS

## D1. Home — the work surface ("what needs me now")
- **Home is the control centre that empties.** It shows only pending work; it is not analytics. As tasks are done, they leave Home.
- **Identity header** (compact): business name, city · GST verified, bell (dot when unread). Profile & search stay secondary. No duplicate profile shortcut. **No "Aaj:" summary line** (removed).
- **Three large task buttons in one row: Orders · Enquiries · Returns.** Plain label + pending count; teal count, bold when >0 and dull at 0; no tangerine; recognizable icon only where it aids recognition. Access requests live in Chats — **no fourth button.** Tapping a button opens that task list.
- **"Pending work"** section (renamed from "Needs you") — a prioritised queue of the actual action items, not counters:
  - Row = required action + business name + useful quantity/status, opens the relevant task. Copy: **"Confirm order", "Dispatch order", "Share rate", "Review return".** Quantities/units come exactly from source data.
  - Priority tiers: money-in-motion (confirm/dispatch/accept quote) → people/problems (rate request, return, complaint) → admin (access request, sample decision); oldest-first within a tier; capped with "See all".
  - Rows are clearly tappable with a strong directional affordance (chevron).
  - Empty state: **"No pending work."**
- **Removed from Home:** the Recent/awareness feed (moved entirely to the bell/notification centre) and the Followed/new-drops strip (moved to Discover). Home = work only.
- Owners and staff share the same Home structure; permissions decide which tasks appear.
- Home can surface assigned/incomplete catalogue work, e.g. "Add rates · Summer Georgette Vol 3."

## D2. Collections — Discover (buying feed)
- **Full-height, Instagram-inspired feed**, full-width divider-separated post sections (not floating cards).
- **Thin full-width top switch:** Discover / My catalogue (segmented; the switch *is* the header — no separate big "Discover" title).
- **Next row:** Collections / Products toggle on the left; **Saved** + **Filter** icons on the right (no labels for now).
- **Supplier circles** strip (profile shortcuts, not stories — no seen/unseen semantics; tap → supplier profile). No added section label for now.
- **Post structure (Instagram order):** header (supplier avatar + name + freshness + city; **three-dot ⋯ opens a post menu** — View supplier / Share / Mute updates / Copy link / Report / Hide) → full-bleed media (2×2 for a collection with design-count + NEW TODAY; single image for a product) → **lightweight icon action row** (relationship/share actions on the left, **Save** aligned right) → compact info row (collection/product name + price/rate). **No large Order/Repost buttons on posts** — opening the post/collection handles deeper browsing and ordering.
- **Feed data priority** (show the most relevant buying info first, keep secondary quieter or one tap deeper):
  - *Collection:* supplier, freshness, name, price/rate range, unit, design count, selectable/full-catalogue type, stock state, MOQ rule, dispatch time, useful taxonomy.
  - *Product:* supplier, parent collection, freshness, design reference, price/rate, unit, stock state, MOQ, dispatch time, useful taxonomy.
  - Tag only what speeds recognition or changes a buying decision — don't turn every field into a chip.
- Muted/paused suppliers and drafts never appear. Feed clears the bottom navigation.
- **Filter sheet (redesigned — no wall of chips):** Sort as a simple single-choice control; Category, Price range, Suppliers as compact rows showing the current selection + chevron, each opening a focused selection view; Suppliers gets search + checkbox list; **Clear all** + a sticky **Show results**. Transactional: selections stay temporary until Show results.

## D3. My Catalogue (selling management)
- Rename **Mine → My catalogue**, **All products → Products**. This is an at-a-glance **management workspace, not a social feed.**
- **Remove standalone Broadcast** and the word "Broadcast" from this flow (replaced by "Send to buyers").
- Compact catalogue filters: **All · Live · Draft · Scheduled · Hidden**, plus search & filter. Detailed filters: Own/Curated, Category, Stock status, Audience, Schedule, Resharing allowed/blocked, Rate shown/hidden, recently updated/stale, product-level overrides. Sort: newest, recently updated, name. Detailed filters use compact selection rows, not chip walls.
- **Compact full-width collection rows** show important config without opening: status, design count, freshness, audience, schedule/next rollout, resharing permission, selectable/full-catalogue type, rate visibility, stock state, key exceptions. Keep inherited/default settings quiet; emphasise restrictions, overrides, scheduled changes, warnings. Hierarchy: identity → commercial state → access/distribution → exceptions.
- Status chips + polished icons, consistent meaning/size/spacing/colour; semantic colours for live/draft/scheduled/restriction. Prevent wrapping, clipping, badge collisions, bottom-nav overlap on older phones.
- Overflow "⋯" per row: edit, share, visibility, schedule, resharing, delete.
- **Products view:** two-column grid — image, reference, price/rate state, parent collection, stock, visibility, product-level overrides. **Open/Locked → Visible/Hidden**; show a visibility badge mainly when a product differs from its collection.
- Tapping a collection/product opens full details/editing; the summary stays read-first.
- **Selection:** a visible **Select** action where Broadcast used to be; long-press also enters selection; selection shows Cancel, count, Select all, clear checkmarks; **scroll-preserving**. Collections and Products select separately. After selection → contextual bottom bar: **Share · Send to buyers · More** (+ Edit for a single item). Share = external (WhatsApp/Copy link/system Share/Download). Send to buyers = internal chats/buyer groups/individual buyers → preview + recipient-count confirmation ("Send to 24 buyers" → "Sent to 24 buyers").
- **+ Add** action above the Collections/Products content: in Collections view it starts Add collection; in Products view, Add product (intentionally duplicates the global New for discoverability).

## D4. Collection detail
### Owned collection
- Remove Full/Grid view controls — one consistent **two-column product grid.**
- Header: name, Live/Draft/Scheduled state, product count, last updated.
- At-a-glance settings: audience, schedule/next rollout, resharing restriction, rate state.
- Primary contextual actions: **+ Add products** and **Send to buyers.** Secondary labelled: Share, Edit, Select, More (More: visibility, schedule, resharing, duplicate, archive, delete).
- Product cards: image, reference, rate, stock, key exceptions.
- **No permanent "0 selected" area** — selection UI appears only after Select or long-press. Selected → Share / Send to buyers / More bar. **"Broadcast" → "Send to buyers"** throughout.
### Market (buying) collection
- Compact 2-line header: supplier (tap → profile) + collection name·count·price; **Details** tap for returns/MOQ/dispatch. Save/Share as header icons.
- Large product presentation; **WhatsApp-style multi-select** (long-press or a **Select** button) → floating action bar to order/enquire; back/gesture while selecting cancels selection.
- Detail top bar shows the **collection name** (not a generic "Collection").

## D5. Orders list & detail
- **Thin full-width Buying / Selling switch.** Search & filter near the title. One status row: **Pending · Active · Completed.** Remove the competing Orders/Samples toggle — show standard orders, photo orders, and samples together by recency with a small type label only when needed.
- Order rows: product thumbnail, order number, company, item/quantity summary, amount/rate state, current state, next action, route (direct/via trader), assigned staff, overdue warning where relevant.
- **Never show ₹0 when the real state is "Rate needed / Not priced."** Action-based pending copy: **Confirm order · Add rates · Waiting for buyer · Ready to dispatch · Mark received.** Never a bare "Confirmed" in Pending without the next action.
- Detailed filters: order type, supplier/buyer, direct/via trader, assigned staff, date, amount, overdue, status.
- Full row opens details; important pending rows may show one small contextual action. Orders = a **working queue**, not just a record list.
- **Order detail:** one shared timeline both sides see (received → rate confirmed → dispatch → delivered); the single primary button is always the next action for whoever is looking. Dispatch = transporter + LR number.

## D6. Chats
- Keep as close to **WhatsApp** as possible while retaining Ekum branding.
- Replace a large "New group" button with a compact **circular + in the top area**; + opens a small sheet: New chat / New group.
- **One seamless, recency-based list** — no separate company/group sections, no row cards. Full-width search field. Compact filters: **All · Unread · Orders · Enquiries · Requests · Groups.** Remove explanatory copy ("One thread per company relationship").
- Real timestamps + specific previews for messages, shared collections/products, orders, rates, returns, access requests. Support unread/pinned/muted/draft/archived/paused/group states without clutter.
- **Swipe:** right = Mark unread/read; left = Mute · Archive; smooth motion, clear icons+labels, restrained semantic colours, contained behind the row (never covers the screen). **No swipe-delete** (trade records are permanent). Reversible actions (Archive) offer brief **Undo.** Pin/Pause and rarer controls live in long-press/More. Swipe actions are also reachable via long-press/overflow — gestures are shortcuts, not the only path.
- **Inside a chat:** familiar bubbles + composer with inline **trade cards** for collections, products, orders, rates, returns, requests — structured actions live on the trade card, not as ambiguous plain messages. Attachments: Collection · Product · Order · Photo · Camera · Document (where permitted). Conversation search; business/relationship context in the header.

## D7. Profile
- Instagram-style: avatar + stats (Collections · Designs · Trading since — **no follower counts**), bio, action row, Collections|Products grid.
- One condensed **Contact details** button → POC sheet (role + name + tagged-chat button; phone number only if the supplier double-opted-in per team member). Unconnected viewers see no contact button; they see the **preview collection** + Request access.
- **My profile** uses the same renderer as a supplier profile ("this is how others see you") with layer-preview chips (Public / Approved buyers / My suppliers) and **Edit profile / Settings / Share** actions.
- Private CRM layer (visible only to the viewer's team) condensed into one collapsed card: notes, my tags, assigned-to-my-buyers (trader-only), handled-by.

## D8. Upload / create & edit (team-aware)
- **One scrolling screen** of segmented sections (not a wizard): Photos (native gallery / camera / save-from-chat) → Basics (name, category, unit) → Pricing (rate visibility; price range **auto from product rates**, or manual, or on-request) → Trade details / bulk-assign (MOQ, GST, dispatch, COD, fabric/work/occasion — "applies to all products") → Refine products (per-design overrides, inherited values shown "From collection") → sticky **Save draft / Publish** bar.
- **Two outcomes always: Save as draft · Publish now.** Publish is available when the minimum is complete; optional trade info never blocks publishing. Draft summaries explain what's missing ("Price needed", "Details needed", "Ready to publish"). Work **autosaves** so multiple permitted staff can contribute over time; cards show last editor + last updated. First publish ever = one lifetime consent.

---

# PART E — COMPONENT & INTERACTION PATTERNS

## E1. Buttons
Primary: solid teal, 48px in CTAs, 14px radius, result-naming label. Secondary: white + teal border. Tertiary: teal text. Destructive: red text in overflow only. Instant press feedback (iOS opacity-dim / Android ripple). Base ≥46px, chips ≥32px.

## E2. Cards & rows
Streams (feed, chats, notifications, tasks, orders) = flat full-width hairline-divider rows, whole row tappable. Info/section cards (details, forms) = white, hairline border, 16px radius, flat. Media (posts) = full-bleed, borderless, flowing.

## E3. Sheets (one component for all)
Grab handle, rounded top, spring-up, drag-to-dismiss, dimmed/blurred backdrop. **Transactional filter pattern:** temporary until "Show results"; Close/Cancel/outside-tap/Back/Esc/navigation all dismiss; every redraw removes the previous sheet layer (no stale overlays). **Share sheet:** Copy link · WhatsApp · Share · Download row, then "Send in Ekum" contacts list. **Post overflow (⋯) menu:** View supplier · Share · Mute · Copy link · Report · Hide.

## E4. Selection & multi-select
Long-press enters selection; a visible **Select** action is the discoverable twin. Shows Cancel, count, Select all, clear checkmarks. **Scroll-preserving.** Contextual bottom bar after selection (Share · Send to buyers · More; Edit for one). **Trim-from-all pattern** where an action targets many products: open with all included, remove the irrelevant, continue.

## E5. Switcher grammar in practice
Segmented for scope (main switch, Collections/Products, Buying/Selling); tabs for status (Pending/Active/Completed, catalogue Live/Draft/…); chips for filters/selection. Consistent teal active states.

---

# PART F — PLATFORM / NATIVE SHELL

## F1. Chrome
- **iOS liquid glass:** frosted translucent top header (blur+saturate, hairline bottom border); bottom nav as a **floating glass capsule** (inset margins, ~31px radius, blur, float shadow + inset highlight) with content padding reserving its space so it never covers content; centre **New** = raised solid-teal circular FAB (gradient, no blur). *(Change: v6.2 had flattened all chrome to solid in-flow bars to stop content-covering; v6.3 restored the glass while reserving space so it's both premium and non-obstructing.)*
- **Android:** same structure, opaque surfaces, Material elevation + ripple, no blur.
- Chrome floats/reserves space and never covers content; content padding accounts for the floating nav; safe-area insets for notch/home indicator; `viewport-fit=cover`; PWA meta (Add-to-Home-Screen launches chromeless, teal theme colour); full-bleed on real devices; respect `prefers-reduced-motion` and `prefers-reduced-transparency` (glass → solid fallback).

## F2. Reliability rules (v6.2)
- All filter/action sheets use one transactional lifecycle; every redraw removes the prior sheet layer before creating the next (no invisible/stale overlays trapping the UI).
- Root headers, bottom nav, selection bars, and upload bars reserve their own space; obsolete floating-nav bottom padding removed.
- Prototype-only Dev controls live in the header, excluded from product/visual reviews.

---

# PART G — CONTENT & COPY RULES
Plain trade language, short direct labels, no technical/config terms. Every status explains the real state, not just a colour. Restrictions state their effect ("Resharing blocked", "Rates hidden from buyers"). Never ₹0 when it's "Rate needed". Action-based pending copy. Empty states explain what will appear + one next action. Confirmations name the action + effect. Errors explain what was preserved, what failed, and how to recover. Avoid repetition across name/metadata/chips/helper text. Units/rates/stock/terminology come from shared source data — screens never redefine them. Review every string for clarity, tone, grammar, truncation before shipping.

---

# PART H — PRODUCT ARCHITECTURE THE UI MUST EXPRESS

## H1. Unified profile & capabilities
- **One unified business profile** carrying buyer, supplier, and trader capabilities. No role accounts, no role-based navigation; roles are contextual per connection. Onboarding never asks "what are you?"
- **Capabilities unlock by behaviour, not configuration** — selling tools appear on first publish (one lifetime consent), reselling on first re-list. Buying needs no gate.
- **Identity unifies; relationships separate.** One profile everywhere; each connection decides what the other side sees (visibility layers: Public / Approved buyers / My suppliers / per-connection overrides).
- **Permission > Capability > Preference.** Owner-set team permissions cap capabilities; personal display prefs (My Tools) sit beneath both. Hiding removes entry points, never events.
- Staff see only what their permissions allow, in the same Home/screen structure as owners; staff appear as the business, though a staff member's name may show on their messages.

## H2. Access modules (per-follower grants)
- At follow-request acceptance the supplier grants a multi-select set: **View catalogue · See rates · Order · Resell/repost · Private collections · Full chain visibility.** (Chat is not a grant — non-followers reach chat via the Requests inbox.) Bundles: **Buyer** (View+Rates+Order), **Trader** (Buyer+Resell).
- Requester picks desired modules on the request; supplier edits/accepts; editable anytime from the follower's profile; a follower can request more later. Product-level **repost lock** at publish; a locked product needs per-product approval even from a trader. **Locked-action popup** offers "Request access" (full) or "Request just this product".

## H3. Chain transparency (per-relationship, origin-governed)
- Every cross-party visibility setting is **per-relationship, mutually visible, and shown to the trader before re-listing.** The origin supplier's settings govern the whole downstream chain.
- **Re-list:** default = supplier sees "resold via [trader] · qty"; optional **end-buyer visibility** (the buyer of orders carrying *his* product only) and **chain visibility** (downstream reposts). **Order routing:** multiple independent listings, no merged picker; ordering on a listing routes to that listing's owner. **Dispatch:** via-trader (masked) or direct-to-buyer (with a source-reveal warning); rare trader-labelled drop-ship as an advanced opt-in. **Returns/complaints:** buyer→trader (never sees supplier); trader optionally raises a linked upstream; stuck state honestly shown, Phase 1 doesn't arbitrate. **Chat identity:** one thread per company relationship; staff name visible; masking survives forwards. **Mutual contacts:** only open, non-masked, mutual relationships qualify; masked links never surface; opt-out per connection.

## H4. Quote cards, samples, groups
- **Quote card** is the order-confirmation primitive: buyer sends an ask (designs + quantities, no rates); supplier replies with a quote card (rate, qty, validity); accepting the quote confirms the order for both sides. Rendered inside the chat thread, mirrored in Orders.
- **Samples are tagged orders** (mini order lifecycle: request → dispatch w/ LR → receive → decide/convert), filtered by a Samples chip in Orders, with aging follow-up nudges; never pollute revenue/order counts.
- **Groups** are universal (anyone can create), coordination-only (orders stay in bilateral threads; a bilateral card can be shared in as a read-only reference); bridging unconnected parties needs an exposure warning + join consent; group visibility is group-scoped (no auto-connect); no group orders/broadcasts.
- **Product library:** every design in any collection is auto-created as an individual product at upload; collections are arrangements referencing library products; editing a product updates it everywhere.

---

# PART I — CHANGE LOG (what evolved after the first bible)
- **Teal corrected** from an off-brand #287b80 to the Brand-Kit **#2B7379**; all v6 tokens reconciled to the brand palette (paper #F7F3EA, line #E7E8E6, semantics).
- **Liquid-glass chrome removed then restored:** v6.1/v6.2 flattened headers/nav to solid in-flow bars to fix content-covering; **v6.3 restored the iOS glass + raised FAB** with reserved space so it's premium *and* non-obstructing.
- **Legibility floor re-enforced** after the compact v6.2 pass pushed labels below 12px.
- **Home:** "Needs you" → **"Pending work"**; the "Aaj:" mixed-language line **removed**; task buttons standardised to **Orders/Enquiries/Returns** with teal (not tangerine) counts; Recent/Followed sections removed (awareness → bell, drops → Discover); orange Orders underline → dot/badge.
- **Discover posts:** moved from large Order/Repost pill buttons to **lightweight Instagram-style icons** (Repost/Inquiry/Share + Save right); ordering happens on tap-in. **Three-dot ⋯ now opens a real post menu** (was dead on product posts). **Share is a real sheet** everywhere (was a toast). Filter sheet redesigned to rows-with-chevrons (no chip wall).
- **My Catalogue / collection detail:** "Broadcast" replaced by **"Send to buyers"** everywhere; Select action added where Broadcast was; Open/Locked → **Visible/Hidden**; permanent "0 selected" area removed.
- **Chats:** unified recency list (no group/company split), compact + action, swipe grammar, contained swipe layer.
- **Orders:** Buying/Selling switch, Pending/Active/Completed, Orders/Samples toggle removed, action-based pending copy, no ₹0 for unpriced.
- **New menu:** four clear actions (Add collection / Add product / Order from supplier / Create order for buyer); removed generic Create order and Refer buyer.
- **Working format:** moved from a single monolithic HTML with duplicate override functions to a **modular `ekum-v6` structure** (HTML base + `ekum-v6.css` + `ekum-v6.js` + this bible + change plan) — the source of truth going forward.

---

*Version: Design Bible v6 · Aligns to Brand Kit (Teal #2B7379, Tangerine #FF9700, Inter) + the accumulated approved v5/v6 change plan + the v6 implementation. Update this file whenever a law, screen, or flow decision changes — it is the log of record.*
