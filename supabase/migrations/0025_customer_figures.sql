-- 0025_customer_figures.sql
-- The facts about a customer, where the decision about that customer is made.
--
-- The Numbers tab will be opened twice and never again. The same figures placed on the customer
-- himself get read every time somebody rings up: how many jobs, what is owed, how long the oldest
-- unpaid charge has been sitting, and how often the gear has come back late.
--
-- NUMBERS, NEVER VERDICTS. There is deliberately no "reliable" flag and no "always pays" — that is
-- a judgment, and the posting choice makes it a wrong one: revenue posts on order CONFIRMATION, so
-- a customer with three confirmed jobs and nothing dispatched owes ₹0 and would read as a model
-- payer. Four numbers and the operator does the judging (docs/decisions.md, "always pays" becomes
-- numbers).

create or replace view v_customer_figures with (security_invoker = on) as
with jobs as (
  select o.customer_id,
         count(*)::int                                          as jobs_total,
         count(*) filter (where o.status = 'closed')::int        as jobs_closed,
         count(*) filter (where o.status = 'cancelled')::int     as jobs_cancelled,
         max(o.out_date)                                         as last_job_on
  from rental_order o
  group by o.customer_id
),
-- LATE MEANS THE GEAR CAME BACK AFTER THE DAY IT WAS PROMISED. Counted per ORDER, not per piece:
-- one job that came back three days late with eleven boxes on it is one late return, not eleven.
-- And it is measured from the movements, never from the order's own dates (rule 2) — an order is
-- not late because a date passed, it is late because the return happened after it.
late_returns as (
  select o.customer_id, count(*)::int as returned_late
  from rental_order o
  where exists (
    select 1 from v_movement_effective m
    where m.order_id = o.id and m.movement_type = 'return'
      and m.moved_on > o.expected_return_date
  )
  group by o.customer_id
),
-- Still out past the promised day, right now. Different question from the one above: that one is
-- history, this one is a phone call to make.
overdue_now as (
  select oo.customer_id, count(distinct oo.order_id)::int as jobs_overdue_now
  from v_order_outstanding oo
  where oo.days_overdue > 0
  group by oo.customer_id
),
-- HOW LONG THE OLDEST UNPAID CHARGE HAS BEEN SITTING. Only meaningful while something is actually
-- owed: a customer who paid last week has an old charge in their history and owes nothing, and
-- reporting "longest unpaid 400 days" about a settled account is a wrong number, not a stale one.
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
  -- NOT coalesced, and that is rule 14. v_customer_balance_visible returns ZERO ROWS without
  -- ledger.view, so coalescing to 0 would report every customer as owing nothing to somebody who
  -- simply cannot see money — which looks like good news and is therefore never investigated. NULL
  -- means "not visible from this account"; 0 means "settled", and the screen says which.
  case when b.receivable > 0 and ou.oldest_due_on is not null
       then (current_date - ou.oldest_due_on)::int end as longest_unpaid_days,
  b.receivable                     as receivable,
  b.deposit_held                   as deposit_held
from customer c
left join jobs j          on j.customer_id = c.id
left join late_returns lr on lr.customer_id = c.id
left join overdue_now od  on od.customer_id = c.id
left join oldest_unpaid ou on ou.customer_id = c.id
-- The MONEY comes from the gated wrapper, so this view inherits ledger.view: without the key the
-- two money columns are null rather than zero, and the job counts still answer (rule 14).
left join v_customer_balance_visible b on b.customer_id = c.id;

comment on view v_customer_figures is
  'Facts about a customer, for the customer screen. Numbers only — no "reliable", no "always pays": a verdict computed from a ledger that posts on confirmation would call somebody with three unstarted jobs a model payer. longest_unpaid_days is null unless something is actually owed. Money is joined through v_customer_balance_visible, so it is null without ledger.view rather than a plausible zero (rule 14).';

revoke all on table v_customer_figures from anon;
grant select on table v_customer_figures to authenticated;
