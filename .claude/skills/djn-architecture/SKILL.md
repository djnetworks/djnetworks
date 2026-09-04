---
name: djn-architecture
description: Load-bearing architecture for the DJ Network's rental system (Supabase + static HTML). Use when adding a feature, designing a screen, writing a query or function, or deciding where logic belongs. Read this BEFORE designing anything that touches inventory, orders, movements, pricing or the ledger.
---

# DJ Network's — where things belong

## The shape

```
Static HTML (web/)  →  Supabase Postgres
                       ├── tables      : facts, append-only where it matters
                       ├── v_* views   : everything derived
                       └── fn_* funcs  : the few things that need parameters
Google Sheet        ←  read-only mirror out
                    →  bulk catalogue import in
```

No build step. No framework. The operator wanted to be able to read and change the system himself,
and that constraint is why the frontend is plain HTML and why the business logic lives in the
database rather than scattered through JavaScript.

## Where logic goes

**In the database, as a view** — anything that answers "what is true right now". Location, status,
availability, balances, utilisation, ROI. If two screens would otherwise each compute it, it is a
view. This is not a preference; a number computed in two places will eventually be computed two
different ways.

**In the database, as a function** — anything that needs parameters. `fn_availability(product, from,
to)` is a function because dates come from the caller. Keep them `stable` or `immutable` where
possible.

**In the client** — presentation, form state, offline queueing, and nothing else. The client must
never decide whether a unit is available, what a line costs, or what a customer owes. It asks.

**In a trigger** — only invariants that must hold no matter who writes. Currently two: the
movement append-only guard, and keeping `product.image_url` pointed at the primary image. Resist
adding more; triggers are invisible at the call site and hard to debug at 6am.

## The movement ledger is the spine

Almost every question this business asks is a question about movements:

| Question | Answered by |
|---|---|
| Where is unit 3 | last movement's destination |
| Is it available | last movement destination is one of our locations |
| What is still out on this order | dispatch with no matching return |
| How hard does this product work | dispatch/return spans over days owned |
| What has not moved in six months | last movement date |

So when a new requirement arrives, the first question is always: **is this a new kind of movement, or
a new way of reading the existing ones?** Usually the second. Adding a movement type is cheap;
adding a parallel record of where things are is how the system starts lying.

## Reservation vs allocation

These are two different moments and conflating them is the most common design error here.

- **Reservation** happens at order time, at *product* level. "Two 15-inch tops for Saturday."
  It affects availability arithmetic and nothing physical.
- **Allocation** happens at dispatch, at *unit* level, when someone physically picks boxes off a
  shelf. It creates movements.

An order line may optionally pin a unit, but that is an exception for a reason, not the norm.
Never design a flow that asks which physical box will go out three weeks from now.

## Three tracking modes

`product.tracking_mode` decides how a product behaves everywhere:

- `unit` — numbered pieces, movements carry `unit_id`, full per-box history.
- `pool` — a count. Movements carry `qty` and a null `unit_id`. Cables, stands, clamps, tools.
- `consumable` — issued and charged, never expected back. No return is owed.

Any code path that touches inventory must handle all three. A screen that assumes `unit_id` is
present will break the moment someone puts XLR cables on an order.

## Frontend conventions

- One HTML file per screen, plain `<script type="module">`, no bundler.
- Supabase JS client from CDN, pinned version.
- All reads go through views. A screen that selects from `movement` directly is a smell.
- Screens are product-first. Never a unit-ID entry point (stickers carry bare piece numbers).
- Dispatch and return must work offline: queue in IndexedDB, sync on reconnect, show pending state.

## Customer portal

Public by link, but **not** built on anonymous table access. A `security definer` function keyed on
a per-customer token returns that customer's data and nothing else. Opening anon SELECT on
`ledger_entry` to make a portal work would expose every customer's account to every other customer.

The portal always shows receivable and deposit held as two separate figures, and separates upcoming
bookings from money actually due.
