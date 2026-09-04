-- 0004_rls_and_settings.sql
-- Row level security, and the business conventions that live as settings rather than as code.

-- ---------------------------------------------------------------------------
-- RLS.
--
-- There is exactly one operator. There is no team, no roles to separate, and nobody to hand a
-- partial view to. So the model is deliberately simple: an authenticated user is the operator
-- and can do everything; anonymous traffic can do nothing.
--
-- The customer portal is NOT built on anon table access. It reads through a SECURITY DEFINER
-- function keyed on a per-customer token, added when portal authentication is settled
-- (see docs/open-questions.md). Do not open anon SELECT on these tables to make a portal work.
-- ---------------------------------------------------------------------------

do $$
declare t text;
begin
  foreach t in array array[
    'category','subcategory','product','unit','location','vendor','customer',
    'discount_tier','app_setting','rental_order','order_line','order_charge',
    'repair_job','movement','ledger_entry'
  ]
  loop
    execute format('alter table %I enable row level security', t);

    execute format('drop policy if exists operator_all on %I', t);
    execute format($f$
      create policy operator_all on %I
        for all
        to authenticated
        using (true)
        with check (true)
    $f$, t);
  end loop;
end $$;

-- ---------------------------------------------------------------------------
-- Guard: the movement ledger is append-only.
--
-- Rule 12, and the reason every derived view can be trusted. Correcting a mistake means adding
-- a compensating movement, not editing history.
-- ---------------------------------------------------------------------------

create or replace function fn_movement_is_append_only()
returns trigger
language plpgsql
as $$
begin
  raise exception
    'movement is append-only — record a compensating movement instead of editing or deleting (CLAUDE.md rule 12)';
end $$;

drop trigger if exists movement_no_update on movement;
create trigger movement_no_update
  before update or delete on movement
  for each row execute function fn_movement_is_append_only();

-- ---------------------------------------------------------------------------
-- Settings.
--
-- These are conventions that could change and must not be buried in code. The day-count
-- convention in particular changes the price of every job and has not yet been confirmed by
-- the owner in his own words — see docs/open-questions.md.
-- ---------------------------------------------------------------------------

insert into app_setting (key, value, description) values
  ('day_count_mode',
   '"inclusive_both_ends"'::jsonb,
   'Out on the 2nd, back on the 4th = 3 days. UNCONFIRMED with the owner. Changes every price.'),

  ('availability_granularity',
   '"date"'::jsonb,
   'Date-level. A unit due back on a date is not offered on that date. Same-day turnaround requires an explicit, logged override on the order.'),

  ('order_no_prefix',
   '"DJN"'::jsonb,
   'Order numbers read DJN-YYMM-NNNN and appear in every WhatsApp message about the job.'),

  ('revenue_posts_on',
   '"order_confirmation"'::jsonb,
   'Rental charges hit the ledger when the order is confirmed, marked state=upcoming until dispatch.'),

  ('loss_charge_basis',
   '"unit_purchase_cost"'::jsonb,
   'A lost unit proposes its own purchase cost. Editable at the point of charging — it will understate older gear.'),

  ('deposit_scope',
   '"order"'::jsonb,
   'Security deposit is taken against the order, not per product. Held as a liability, never revenue.')
on conflict (key) do nothing;

-- ---------------------------------------------------------------------------
-- Discount ladder.
--
-- PLACEHOLDER PERCENTAGES. The tier boundaries came from an earlier planning document, not
-- from the owner. The percentages below are invented and must be replaced before go-live.
-- ---------------------------------------------------------------------------

insert into discount_tier (min_days, max_days, discount_pct) values
  (1, 1,    0),
  (2, 3,    0),
  (4, 7,    0),
  (8, null, 0)
on conflict do nothing;

-- ---------------------------------------------------------------------------
-- Starting locations. Names to be confirmed with the owner.
-- ---------------------------------------------------------------------------

insert into location (name, type) values
  ('Shop',   'shop'),
  ('Godown', 'godown'),
  ('Van 1',  'van')
on conflict (name) do nothing;
