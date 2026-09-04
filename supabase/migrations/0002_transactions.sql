-- 0002_transactions.sql
-- Orders, the movement ledger, repairs, and the customer ledger.
-- The movement table is the spine of the whole system: location, availability and utilisation
-- are all derived from it. See CLAUDE.md rules 1, 2, 5, 6, 9, 10.

-- ---------------------------------------------------------------------------
-- Orders. There is no quote stage — an order exists once the job is agreed.
-- ---------------------------------------------------------------------------

create table if not exists rental_order (
  id                    uuid primary key default gen_random_uuid(),
  order_no              text not null unique,
  customer_id           uuid not null references customer(id) on delete restrict,

  status                text not null default 'confirmed'
                        check (status in ('confirmed','dispatched','partially_returned',
                                          'returned','closed','cancelled')),

  event_type            text,
  venue_name            text,
  venue_address         text,
  -- The man who booked the job is rarely the man standing at the hall at six in the morning.
  venue_contact_name    text,
  venue_contact_phone   text,

  out_date              date not null,
  expected_return_date  date not null,
  -- Chargeable days. Written at order time using the convention in app_setting, then editable.
  -- Not a generated column: the convention is a setting and must not silently rewrite history.
  days                  int not null check (days >= 1),

  deposit_amount        numeric(12,2) not null default 0,

  -- Availability is date-level. Same-day turnaround is possible but must be a deliberate,
  -- recorded act rather than a silent one.
  availability_override        boolean not null default false,
  availability_override_reason text,

  notes                 text,
  created_at            timestamptz not null default now(),
  closed_at             timestamptz,

  constraint order_dates_sane check (expected_return_date >= out_date)
);

create index if not exists idx_order_customer on rental_order(customer_id);
create index if not exists idx_order_dates    on rental_order(out_date, expected_return_date);
create index if not exists idx_order_status   on rental_order(status);

-- ---------------------------------------------------------------------------
-- Order lines. Reserved at PRODUCT level; physical units attach at dispatch.
-- A specific unit may be pinned when there is a reason to.
-- Rule 5: agreed_rate and line_total are stored, never recomputed on read.
-- ---------------------------------------------------------------------------

create table if not exists order_line (
  id                uuid primary key default gen_random_uuid(),
  order_id          uuid not null references rental_order(id) on delete cascade,
  product_id        uuid not null references product(id) on delete restrict,

  qty               int not null check (qty >= 1),
  days              int not null check (days >= 1),

  base_rate         numeric(12,2) not null default 0,   -- snapshot of product rate at agreement
  discount_pct      numeric(5,2)  not null default 0,
  agreed_rate       numeric(12,2) not null default 0,   -- what was actually agreed, per day
  line_total        numeric(12,2) not null default 0,   -- what was actually charged

  pinned_unit_id    uuid references unit(id) on delete set null,

  is_subhired       boolean not null default false,
  subhire_vendor_id uuid references vendor(id) on delete set null,
  subhire_cost      numeric(12,2),

  constraint subhire_needs_vendor
    check (not is_subhired or subhire_vendor_id is not null)
);

create index if not exists idx_line_order   on order_line(order_id);
create index if not exists idx_line_product on order_line(product_id);

-- ---------------------------------------------------------------------------
-- Job-level charges, kept apart from rental revenue so ROI stays honest.
-- Transport and misc cannot be attributed to a product; including them in ROI would flatter
-- heavy gear, which travels most.
-- ---------------------------------------------------------------------------

create table if not exists order_charge (
  id          uuid primary key default gen_random_uuid(),
  order_id    uuid not null references rental_order(id) on delete cascade,
  type        text not null check (type in ('transport','labour','misc','damage')),
  description text,
  amount      numeric(12,2) not null default 0,
  created_at  timestamptz not null default now()
);

create index if not exists idx_charge_order on order_charge(order_id);

-- ---------------------------------------------------------------------------
-- Repair jobs.
-- A unit at a repair shop is simply not at an internal location, so it leaves availability
-- with no extra rule.
-- ---------------------------------------------------------------------------

create table if not exists repair_job (
  id             uuid primary key default gen_random_uuid(),
  unit_id        uuid not null references unit(id) on delete restrict,
  vendor_id      uuid references vendor(id) on delete set null,
  date_sent      date not null,
  fault          text,
  estimated_cost numeric(12,2),
  date_back      date,
  actual_cost    numeric(12,2),
  outcome        text check (outcome in ('repaired','not_repairable','replaced','lost_at_shop')),
  notes          text,
  created_at     timestamptz not null default now(),
  constraint repair_dates_sane check (date_back is null or date_back >= date_sent)
);

create index if not exists idx_repair_unit on repair_job(unit_id);

-- ---------------------------------------------------------------------------
-- MOVEMENT — the spine. Append-only.
--
-- Rule 1: a unit's current location is the destination of its last movement.
-- Rule 2: a unit with a dispatch and no matching return is OUT, whatever the date says.
-- Rule 7: destination is one of location | customer | vendor, never mixed into one table.
--
-- unit_id is null for pooled and consumable products, where qty carries the meaning.
-- ---------------------------------------------------------------------------

create table if not exists movement (
  id            uuid primary key default gen_random_uuid(),

  movement_type text not null
                check (movement_type in ('intake','dispatch','return','transfer',
                                         'repair_out','repair_in','write_off','found')),

  unit_id       uuid references unit(id) on delete restrict,
  product_id    uuid not null references product(id) on delete restrict,
  qty           int  not null default 1 check (qty >= 1),

  from_kind     text not null default 'none' check (from_kind in ('location','customer','vendor','none')),
  from_id       uuid,
  to_kind       text not null default 'none' check (to_kind   in ('location','customer','vendor','none')),
  to_id         uuid,

  order_id      uuid references rental_order(id) on delete set null,
  repair_job_id uuid references repair_job(id) on delete set null,

  moved_on      date not null default current_date,

  -- Dispatch method is chosen per dispatch — porter, self-collection, delivered by chachu.
  -- There is deliberately no staff master: a list for one employee and a rotating cast of hired
  -- porters would be stale within a month.
  dispatch_method   text,
  carrier_name      text,
  carrier_phone     text,
  vehicle_no        text,
  receiver_name     text,
  receiver_phone    text,

  condition_at_move  text,
  inclusions_checked jsonb not null default '[]'::jsonb,
  photos             jsonb not null default '[]'::jsonb,
  notes              text,

  created_at    timestamptz not null default now(),

  -- A movement to or from somewhere must say where.
  constraint movement_from_id_present check (from_kind = 'none' or from_id is not null),
  constraint movement_to_id_present   check (to_kind   = 'none' or to_id   is not null),
  -- Unit-tracked movements name a unit; pooled ones use qty.
  constraint movement_unit_or_qty     check (unit_id is not null or qty >= 1)
);

create index if not exists idx_movement_unit    on movement(unit_id, moved_on desc, created_at desc);
create index if not exists idx_movement_product on movement(product_id);
create index if not exists idx_movement_order   on movement(order_id);
create index if not exists idx_movement_type    on movement(movement_type);
create index if not exists idx_movement_date    on movement(moved_on);

-- ---------------------------------------------------------------------------
-- Customer ledger.
--
-- Rule 6: deposit entries are a liability and are never counted as revenue. v_customer_balance
-- returns receivable and deposit_held as two separate numbers.
--
-- Rental charges post on ORDER CONFIRMATION, so the receivable includes jobs that have not
-- happened yet. `state` separates an upcoming booking from money actually due, which is what
-- the customer portal reads. Cancellations and short dispatches produce `reversal` entries;
-- rows are never deleted (rule 12).
-- ---------------------------------------------------------------------------

create table if not exists ledger_entry (
  id           uuid primary key default gen_random_uuid(),
  customer_id  uuid not null references customer(id) on delete restrict,
  order_id     uuid references rental_order(id) on delete set null,

  entry_date   date not null default current_date,

  type         text not null
               check (type in ('rental','transport','labour','misc','damage',
                               'deposit_in','deposit_out','deposit_forfeit',
                               'payment','discount','write_off','reversal')),

  amount       numeric(12,2) not null,

  state        text not null default 'due' check (state in ('upcoming','due')),

  payment_mode text check (payment_mode in ('cash','upi','bank','cheque','adjustment')),
  reference    text,
  notes        text,
  created_at   timestamptz not null default now()
);

create index if not exists idx_ledger_customer on ledger_entry(customer_id, entry_date);
create index if not exists idx_ledger_order    on ledger_entry(order_id);
create index if not exists idx_ledger_type     on ledger_entry(type);
