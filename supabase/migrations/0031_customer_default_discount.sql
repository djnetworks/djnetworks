-- 0031_customer_default_discount.sql
--
-- A default discount carried on the customer, used as the STARTING POINT for each new order line's
-- discount. Chachu gives his regular decorators a standing rate off; today that lives in his head
-- and gets re-typed per line. This is the one place it is written down.
--
-- IT IS A PREFILL, NOTHING MORE. order_line.discount_pct / agreed_rate / line_total stay the
-- stored, agreed numbers written at the time of agreement (CLAUDE.md rule 5). There is no trigger,
-- no view and no read path that recomputes a saved line from this column, so raising or lowering a
-- customer's default can never rewrite what was charged on a job that already exists. The orders
-- screen copies this value onto a NEW or unedited line and never onto a loaded one.
--
-- IT STACKS ADDITIVELY on top of the discount_tier day-length ladder: a 20% customer default and a
-- 15% eight-day tier make 35% off that line. The client clamps the stacked total at 100% so no
-- arithmetic can drive an agreed rate below zero.
--
-- THE LADDER IS SEEDED ALL ZEROS. Every discount_tier row from 0004 is 0.00 — placeholders from an
-- earlier planning document, not the owner's numbers. So until someone fills the ladder in, the
-- tier half of the stack adds nothing and this column is the only discount in play. The moment the
-- first tier percentage is typed, every FUTURE order that reaches that tier is repriced by it (a
-- past order is untouched — rule 5). That is the intended behaviour of a day-length ladder; it is
-- written here so it is a decision the next person meets, not a surprise.
--
-- numeric(5,2), matching order_line.discount_pct and discount_tier.discount_pct, with the same
-- 0..100 CHECK the other two carry.

alter table customer
  add column if not exists default_discount_pct numeric(5,2) not null default 0
    check (default_discount_pct >= 0 and default_discount_pct <= 100);

comment on column customer.default_discount_pct is
  'Default per-day discount %, the starting point for each new order line. Prefill only — never '
  'rewrites a saved order_line (rule 5). Stacks additively with the discount_tier day-length ladder.';
