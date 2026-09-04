-- 0001_masters.sql
-- DJ Network's rental system — master tables.
-- See CLAUDE.md. Rules 1, 3, 4, 7, 10, 11 are enforced or deliberately un-enforceable here.

create extension if not exists "pgcrypto";

-- ---------------------------------------------------------------------------
-- Taxonomy
-- ---------------------------------------------------------------------------

create table if not exists category (
  id          uuid primary key default gen_random_uuid(),
  name        text not null unique,
  sort_order  int  not null default 0,
  active      boolean not null default true
);

create table if not exists subcategory (
  id          uuid primary key default gen_random_uuid(),
  category_id uuid not null references category(id) on delete restrict,
  name        text not null,
  sort_order  int  not null default 0,
  active      boolean not null default true,
  unique (category_id, name)
);

create index if not exists idx_subcategory_category on subcategory(category_id);

-- ---------------------------------------------------------------------------
-- Product — one row per rentable thing. A kit counts as ONE product.
-- ---------------------------------------------------------------------------

create table if not exists product (
  id                    uuid primary key default gen_random_uuid(),
  short_code            text not null unique,
  category_id           uuid not null references category(id) on delete restrict,
  subcategory_id        uuid references subcategory(id) on delete set null,

  brand                 text,
  model_name            text not null,
  model_number          text,
  description           text,

  -- Specs vary wildly by category (a speaker has wattage and SPL, a moving head has gobos and
  -- DMX channels). Fixed columns would produce a mostly-empty table that grows a column every
  -- time a new category is bought.
  specs                 jsonb not null default '{}'::jsonb,

  -- Things that travel with the unit but are not separately numbered: power cable, quick start
  -- guide, the microphone in a wireless kit. Drives the dispatch and return checklist.
  inclusions            jsonb not null default '[]'::jsonb,

  -- Descriptive list of what a kit is made of, for the customer-facing description.
  kit_contents          jsonb not null default '[]'::jsonb,

  image_url             text,

  -- unit       : numbered pieces, full per-box history (speakers, mics, moving heads)
  -- pool       : counted, never numbered (cables, mic accessories, stands, tools)
  -- consumable : issued and charged, never expected back (fog fluid, tape, batteries)
  tracking_mode         text not null default 'unit'
                        check (tracking_mode in ('unit','pool','consumable')),

  -- Tools and spares move between locations but never appear on a customer order.
  rentable              boolean not null default true,

  base_rate_per_day     numeric(12,2),
  default_purchase_cost numeric(12,2),

  -- Only meaningful for pool / consumable.
  pool_qty              int,

  active                boolean not null default true,
  created_at            timestamptz not null default now(),
  updated_at            timestamptz not null default now(),

  constraint product_pool_qty_only_for_pools
    check ( (tracking_mode = 'unit' and pool_qty is null)
         or (tracking_mode in ('pool','consumable')) )
);

create index if not exists idx_product_category    on product(category_id);
create index if not exists idx_product_subcategory on product(subcategory_id);
create index if not exists idx_product_tracking    on product(tracking_mode);

-- ---------------------------------------------------------------------------
-- Unit — one row per numbered physical box.
-- Rule 4: piece numbers are never reused. Enforced by the unique constraint plus the fact that
-- retired and lost units are never deleted.
-- Rule 1: there is deliberately NO current_location column.
-- Rule 3: condition (assessed) is separate from status (derived).
-- ---------------------------------------------------------------------------

create table if not exists unit (
  id            uuid primary key default gen_random_uuid(),
  product_id    uuid not null references product(id) on delete restrict,
  piece_no      int  not null check (piece_no > 0),

  serial_number text,
  purchase_date date,
  purchase_cost numeric(12,2),

  condition     text not null default 'good'
                check (condition in ('good','minor_wear','needs_attention','damaged','not_working')),

  ownership     text not null default 'owned'
                check (ownership in ('owned','sub_hired')),

  inclusions    jsonb not null default '[]'::jsonb,

  lifecycle     text not null default 'active'
                check (lifecycle in ('active','retired','lost')),

  notes         text,
  created_at    timestamptz not null default now(),

  unique (product_id, piece_no)
);

create index if not exists idx_unit_product   on unit(product_id);
create index if not exists idx_unit_lifecycle on unit(lifecycle);

-- ---------------------------------------------------------------------------
-- Locations — INTERNAL places only. Rule 7.
-- A workshop is ours; a repair shop is somebody else's and belongs in vendor.
-- ---------------------------------------------------------------------------

create table if not exists location (
  id     uuid primary key default gen_random_uuid(),
  name   text not null unique,
  type   text not null check (type in ('shop','godown','van','workshop')),
  active boolean not null default true
);

-- ---------------------------------------------------------------------------
-- Vendors — repair shops and occasional sub-hire partners.
-- ---------------------------------------------------------------------------

create table if not exists vendor (
  id      uuid primary key default gen_random_uuid(),
  name    text not null,
  type    text not null default 'repair' check (type in ('repair','subhire','both')),
  phone   text,
  address text,
  notes   text,
  active  boolean not null default true
);

-- ---------------------------------------------------------------------------
-- Customers.
-- Rule 11: there is deliberately NO column for an Aadhaar or PAN number. The document lives in
-- cloud storage and this table holds a URL. Do not add one.
-- ---------------------------------------------------------------------------

create table if not exists customer (
  id                 uuid primary key default gen_random_uuid(),
  name               text not null,
  business_name      text,
  type               text not null default 'individual'
                     check (type in ('individual','dj','decorator','event_company','corporate')),

  whatsapp           text not null,
  alt_phone          text,
  email              text,

  address            text,
  city               text,
  pincode            text,

  id_proof_type      text,
  id_proof_url       text,

  -- Portal identity. Authentication method still undecided — see docs/open-questions.md.
  portal_identifier  text unique,

  active             boolean not null default true,
  created_at         timestamptz not null default now()
);

create index if not exists idx_customer_whatsapp on customer(whatsapp);

-- ---------------------------------------------------------------------------
-- Pricing ladder and settings.
-- One global discount ladder by length of hire. Everything is overridable per order line.
-- ---------------------------------------------------------------------------

create table if not exists discount_tier (
  id           uuid primary key default gen_random_uuid(),
  min_days     int not null check (min_days >= 1),
  max_days     int,                            -- null means "and above"
  discount_pct numeric(5,2) not null default 0 check (discount_pct >= 0 and discount_pct <= 100),
  check (max_days is null or max_days >= min_days)
);

-- Business conventions that could change live here, not in code.
create table if not exists app_setting (
  key         text primary key,
  value       jsonb not null,
  description text
);
