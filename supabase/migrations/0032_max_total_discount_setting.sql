-- 0032_max_total_discount_setting.sql
--
-- A soft ceiling on a line's STACKED discount (customer default + day-ladder tier + any hand edit).
-- It is a WARNING, not a block. When a line's discount exceeds it, the orders screen shows a visible
-- warning next to that line and the order still saves. A deliberate 60%-off is the owner's call to
-- make; the ceiling only makes an ACCIDENTAL one — a fat-fingered 55 for 5.5, a customer default
-- stacked onto a tier nobody remembered — visible before the money posts.
--
-- It lives in app_setting, not in code, because it is a business convention the owner may want to
-- move without a deploy (same reason day_count_mode and the availability buffer live here).
--
-- This is SEPARATE from the hard 100% clamp the client applies to the arithmetic itself: the
-- ceiling is advisory and adjustable; the 100% clamp is a floor under the price that exists so no
-- stacked discount can ever invert an agreed rate, and it is not configurable.
--
-- 40 is a starting figure, not a measured one — there is no history of real discounts to derive it
-- from yet. It is deliberately low enough that the first genuinely large discount trips it, so the
-- warning is seen working at least once rather than sitting silent until it is needed.

insert into app_setting (key, value, description) values
  ('max_total_discount_pct',
   '40'::jsonb,
   'Soft ceiling on a line''s total discount %. Above it the orders screen warns but still saves. '
   'Advisory and adjustable, unlike the hard 100% clamp the client puts under the agreed rate.')
on conflict (key) do nothing;
