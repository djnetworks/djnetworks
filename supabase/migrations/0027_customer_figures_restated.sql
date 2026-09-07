-- 0027_customer_figures_restated.sql
-- Restating v_customer_figures, and writing down why it needed restating.
--
-- WHAT HAPPENED. 0025 shipped v_customer_figures with the two money columns wrapped in
-- coalesce(..., 0). The money is joined through v_customer_balance_visible, which returns zero
-- ROWS to an account without ledger.view — so the coalesce turned "you may not see this" into
-- "this customer owes nothing". That is rule 14, broken inside the migration whose own comment
-- cites rule 14. Every customer owing ₹0.00 looks like good news, so nobody investigates it.
--
-- WHAT I DID ABOUT IT, WHICH WAS ALSO WRONG. I edited 0025 in place after it had already been
-- applied, reasoning that it was uncommitted, unpushed, and there is one database. That reasoning
-- is convenient rather than sound. An applied migration is a record of what ran. Editing one makes
-- the schema stop matching its own history, and it does so INDEPENDENTLY of whether the end state
-- is correct — the Supabase CLI keeps a `statements` array per applied migration precisely so that
-- a file which no longer matches what ran can be detected. A correct view reached by a false
-- history is still a false history, and it bites the next person, not this one.
--
-- HOW THE TWO ROADS MEET. 0025 is deliberately left in its CORRECTED form, so a fresh replay from
-- 0001 is right the first time and never runs the broken text at all. This migration restates the
-- view so a database that DID run the broken text converges to the same definition. Whichever road
-- a database took, it ends here.
--
-- A NOTE ON WHAT THIS PROJECT CAN AND CANNOT DETECT. On checking, `statements` is null for every
-- migration from 0019 onward: those were applied through a path that records the version and the
-- name but not the text. So for 0025 there was nothing to diverge from — the edit is not detected,
-- it is simply unrecorded, which is worse for anybody trying to reconstruct what happened later.
-- I have NOT backfilled those rows. Writing statements I merely believe ran would be fabricating
-- the very record whose absence is the problem. This file is the record instead.
--
-- 0026 already restates this view with fn_today(); this restatement is therefore belt and braces
-- for the view itself. Its real work is the paragraph above and the assertion below.

create or replace view v_customer_figures with (security_invoker = on) as
with jobs as (
  select o.customer_id,
         count(*)::int                                      as jobs_total,
         count(*) filter (where o.status = 'closed')::int    as jobs_closed,
         count(*) filter (where o.status = 'cancelled')::int as jobs_cancelled,
         max(o.out_date)                                     as last_job_on
  from rental_order o
  group by o.customer_id
),
-- Late means the gear came back after the day it was promised, counted per ORDER: one job that
-- came back three days late with eleven boxes on it is one late return, not eleven. Measured from
-- the movements, never from a date passing (rule 2).
late_returns as (
  select o.customer_id, count(*)::int as returned_late
  from rental_order o
  where exists (
    select 1 from v_movement_effective m
    where m.order_id = o.id and m.movement_type = 'return'
      and m.moved_on > o.expected_return_date)
  group by o.customer_id
),
overdue_now as (
  select oo.customer_id, count(distinct oo.order_id)::int as jobs_overdue_now
  from v_order_outstanding oo
  where oo.days_overdue > 0
  group by oo.customer_id
),
oldest_unpaid as (
  select le.customer_id, min(le.entry_date) as oldest_due_on
  from ledger_entry le
  where le.state = 'due'
    and le.type in ('rental','transport','labour','misc','damage')
  group by le.customer_id
)
select
  c.id as customer_id,
  c.name,
  c.business_name,
  coalesce(j.jobs_total, 0)        as jobs_total,
  coalesce(j.jobs_closed, 0)       as jobs_closed,
  coalesce(j.jobs_cancelled, 0)    as jobs_cancelled,
  j.last_job_on,
  coalesce(lr.returned_late, 0)    as returned_late,
  coalesce(od.jobs_overdue_now, 0) as jobs_overdue_now,
  -- fn_today(), not current_date (0026): current_date is UTC and names yesterday before 05:30 IST.
  case when b.receivable > 0 and ou.oldest_due_on is not null
       then (fn_today() - ou.oldest_due_on)::int end as longest_unpaid_days,
  -- THE TWO COLUMNS THIS MIGRATION EXISTS FOR. Never coalesced. NULL means "not visible from this
  -- account", 0 means "settled", and the screen is required to say which. Counting jobs still
  -- works without ledger.view, so the row is useful either way — it is only the money that goes
  -- quiet, and it goes quiet loudly.
  b.receivable                     as receivable,
  b.deposit_held                   as deposit_held
from customer c
left join jobs j           on j.customer_id = c.id
left join late_returns lr  on lr.customer_id = c.id
left join overdue_now od   on od.customer_id = c.id
left join oldest_unpaid ou on ou.customer_id = c.id
left join v_customer_balance_visible b on b.customer_id = c.id;

comment on view v_customer_figures is
  'Facts about a customer, for the customer screen. Numbers only — no "reliable", no "always pays": a verdict computed from a ledger that posts on confirmation would call somebody with three unstarted jobs a model payer. Money is joined through v_customer_balance_visible and is NEVER coalesced, so it reads null without ledger.view rather than a plausible zero (rule 14). Restated by 0027 after 0025 was edited post-application; see that file.';

revoke all on table v_customer_figures from anon;
grant select on table v_customer_figures to authenticated;

-- ---------------------------------------------------------------------------
-- THE ASSERTION. State the expectation, then read the actual, and fail loudly.
--
-- The bug was structural — a coalesce that converts null to zero — so the deployed definition is
-- the thing to interrogate, not a sample row: a sample read by an account that CAN see money shows
-- a real number under either definition and proves nothing (rule 16 — a check that does not
-- reproduce the failing shape runs clean).
--
-- The numeric half of this, read as an account that cannot see money, is
-- supabase/probes/0027_customer_figures_probe.sql. It rolls itself back and carries its own false
-- positive control.
-- ---------------------------------------------------------------------------
do $assert$
declare def text;
begin
  select pg_get_viewdef('v_customer_figures'::regclass, true) into def;

  if def ~* 'coalesce\s*\(\s*b\.receivable' or def ~* 'coalesce\s*\(\s*b\.deposit_held' then
    raise exception
      'v_customer_figures still coalesces a gated money column to zero. Expected: receivable and deposit_held selected bare, so an account without ledger.view reads null. Actual: a coalesce wraps one of them, which reports every customer as owing nothing to anybody who cannot see the ledger (rule 14).';
  end if;

  if def ~* '\mcurrent_date\M' then
    raise exception
      'v_customer_figures compares current_date against a stored date. Expected: fn_today(). Actual: current_date, which is UTC and names yesterday between midnight and 05:30 IST — the hours a van is loaded in (0026).';
  end if;

  raise notice '0027 ok: v_customer_figures selects receivable and deposit_held bare, and uses fn_today().';
end $assert$;
