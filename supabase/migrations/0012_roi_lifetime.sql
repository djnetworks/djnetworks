-- 0012_roi_lifetime.sql
-- v_product_roi answers LIFETIME return, and now says so.
--
-- The cost denominator excluded retired units and included lost ones — two lifecycles answering the
-- same question differently, with nothing in any comment explaining why. Verification measured it:
-- MIC-BLX read purchase_cost 126500.00 with one piece retired, and stayed at 126500.00 when a
-- second piece was marked lost.
--
-- The owner has now decided which question this report answers: LIFETIME. Everything ever bought
-- stays in the denominator. A box that worked four years and was then scrapped still cost money and
-- still earned money, and dropping it once it leaves the fleet flatters the number in exactly the
-- direction that causes bad buying — the gear that broke most disappears from its own ROI, and the
-- report recommends buying more of it.
--
-- The alternative was current-fleet return: only what he still owns, answering "is what I have now
-- earning". That is a different and also useful question. It is not this view. If it is ever wanted
-- it belongs beside this one under its own name, not as a flag on this one, because the moment two
-- meanings share a column somebody reads the wrong one.
--
-- units_active is added so fleet size is visible without conflating the two. Reading purchase_cost
-- alone, there is no way to tell nine working boxes from three working and six scrapped; the ROI is
-- the same number and the buying decision is not.
--
-- Nothing else in the view changes. revenue still excludes cancelled orders and sub-hired lines
-- (0011 — borrowed gear must not inflate the return on gear he owns), and roi_pct is still NULL
-- rather than zero when no cost is recorded, with units_missing_cost saying how much of the answer
-- is missing.

-- Dropped and recreated rather than replaced: `create or replace view` can only APPEND columns, and
-- units_active belongs beside the other unit counts rather than tacked on after roi_pct. Verified
-- on the live database that nothing depends on this view — no other view, no function — so the drop
-- is clean. Same approach 0008 took when it reshaped v_product_stock.
drop view if exists v_product_roi;

create or replace view v_product_roi with (security_invoker = on) as
with revenue as (
  -- Sub-hired lines are excluded: that revenue was earned on somebody else's gear and belongs to
  -- no product of his. Cancelled orders never happened.
  select ol.product_id, coalesce(sum(ol.line_total), 0) as rental_revenue
  from order_line ol
  join rental_order o on o.id = ol.order_id
  where o.status <> 'cancelled'
    and ol.is_subhired = false
  group by ol.product_id
),
repairs as (
  select u.product_id, coalesce(sum(rj.actual_cost), 0) as repair_cost
  from repair_job rj
  join unit u on u.id = rj.unit_id
  group by u.product_id
),
cost as (
  -- LIFETIME: every unit ever bought, whatever its lifecycle. There is deliberately no
  -- `where u.lifecycle <> 'retired'` here any more — that filter is what made a scrapped box
  -- vanish from its own ROI and left lost boxes counted, inconsistently, alongside active ones.
  select
    u.product_id,
    coalesce(sum(coalesce(u.purchase_cost, p.default_purchase_cost)), 0) as purchase_cost,
    count(*) filter (where u.purchase_cost is null and p.default_purchase_cost is null) as units_missing_cost,
    count(*) filter (where u.lifecycle = 'active')                                      as units_active,
    count(*)                                                                            as units_ever
  from unit u
  join product p on p.id = u.product_id
  group by u.product_id
)
select
  p.id as product_id,
  p.short_code,
  p.model_name,
  coalesce(r.rental_revenue, 0)     as rental_revenue,
  coalesce(rp.repair_cost, 0)       as repair_cost,
  coalesce(c.purchase_cost, 0)      as purchase_cost,
  coalesce(c.units_missing_cost, 0) as units_missing_cost,
  -- Fleet size, so "what is this earning" and "how much of it do I still own" stay separate
  -- questions with separate columns.
  coalesce(c.units_active, 0)       as units_active,
  coalesce(c.units_ever, 0)         as units_ever,
  (coalesce(r.rental_revenue,0) - coalesce(rp.repair_cost,0)) as net_return,
  case
    when coalesce(c.purchase_cost, 0) = 0 then null
    else round(
      100.0 * (coalesce(r.rental_revenue,0) - coalesce(rp.repair_cost,0))
            / c.purchase_cost
    , 1)
  end as roi_pct
from product p
left join revenue r  on r.product_id  = p.id
left join repairs rp on rp.product_id = p.id
left join cost c     on c.product_id  = p.id;

comment on view v_product_roi is
  'LIFETIME return per product, not current-fleet return. purchase_cost is every unit ever bought — active, retired and lost alike — because a box that earned for four years and was then scrapped still cost money and still earned it, and dropping it once it leaves the fleet flatters the number in the direction that causes bad buying. units_active and units_ever carry fleet size separately, so "what is this earning" and "how much of it do I still own" never share a column. Revenue excludes cancelled orders and sub-hired lines (0011): gear he does not own must not inflate the return on gear he does. Transport, labour and misc are job-level and deliberately excluded — attributing them to a product would flatter heavy gear, which travels most. roi_pct is NULL, never zero, where no purchase cost is recorded; units_missing_cost says how much of the answer is missing. If current-fleet return is ever wanted it belongs beside this view under its own name, never as a flag on this one.';
