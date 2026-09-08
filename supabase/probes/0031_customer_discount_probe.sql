-- 0031_customer_discount_probe.sql
--
-- Proves the one thing that can quietly break the customer default discount: that changing a
-- customer's default NEVER rewrites a line on an order that already exists (CLAUDE.md rule 5).
--
-- The stacking arithmetic itself — customer default + day-ladder tier, clamped at 100% — lives in
-- the browser and is checked there by driving the screen. What THIS probe proves is the invariant
-- the browser leans on: the database has no trigger, view, default or cascade that recomputes a
-- stored order_line from customer.default_discount_pct. It states each expected number before it
-- reads the actual one, and it ends with a FALSE-POSITIVE CONTROL — after asserting the line did
-- not move when the default changed, it moves the line by hand and asserts it CAN. A database in
-- which every write silently failed would pass the first assertion for entirely the wrong reason;
-- the control is what tells the two apart.
--
-- Ends in ROLLBACK. Nothing it inserts is ever committed, so it leaves no rows behind.

begin;

do $$
declare
  v_cust    uuid;
  v_cat     uuid;
  v_prod    uuid;
  v_order   uuid;
  v_line    uuid;
  r_disc    numeric;
  r_agreed  numeric;
  r_total   numeric;
  r_rows    int;
  v_ceiling jsonb;
begin
  -- The ceiling setting exists and is a number (0032). Expected: present. Then read.
  select value into v_ceiling from app_setting where key = 'max_total_discount_pct';
  if v_ceiling is null then raise exception 'FAIL: max_total_discount_pct not seeded'; end if;
  raise notice 'ok: ceiling setting present = %', v_ceiling;

  insert into customer (name, whatsapp, default_discount_pct)
    values ('ZZ probe customer', '0000000000', 20) returning id into v_cust;
  insert into category (name) values ('ZZ probe category') returning id into v_cat;
  insert into product (short_code, category_id, model_name, tracking_mode, base_rate_per_day)
    values ('ZZ-PROBE', v_cat, 'ZZ probe product', 'unit', 1000) returning id into v_prod;
  insert into rental_order (order_no, customer_id, out_date, expected_return_date, days)
    values ('ZZ-PROBE-0001', v_cust, date '2026-09-01', date '2026-09-08', 8)
    returning id into v_order;

  -- The AGREED snapshot: base 1000, 35% off = 650/day, × 1 × 8 days = 5200. These are the stored
  -- numbers rule 5 protects — the deal struck on this order, whatever the customer default becomes
  -- afterwards.
  insert into order_line (order_id, product_id, qty, days, base_rate, discount_pct, agreed_rate, line_total)
    values (v_order, v_prod, 1, 8, 1000, 35, 650, 5200) returning id into v_line;
  -- The whole probe leans on this row existing. If the insert ever returned no id, every read below
  -- would be against NULL and the control's `NULL <> 99` would be NULL — treated as false, letting
  -- the control pass without a write ever landing. Fail loudly here instead.
  if v_line is null then raise exception 'FAIL: order_line insert returned no id'; end if;

  -- The customer's standing default is now changed AFTER the order exists: 20% becomes 5%.
  update customer set default_discount_pct = 5 where id = v_cust;

  -- EXPECTED: the saved line is exactly what was agreed. Read it back and assert on the numbers.
  select discount_pct, agreed_rate, line_total into r_disc, r_agreed, r_total
    from order_line where id = v_line;
  if r_disc <> 35 or r_agreed <> 650 or r_total <> 5200 then
    raise exception 'FAIL rule 5: line moved when the customer default changed: disc=% agreed=% total=%',
      r_disc, r_agreed, r_total;
  end if;
  raise notice 'ok rule 5: line unchanged after default 20%% -> 5%% (disc=%, agreed=%, total=%)',
    r_disc, r_agreed, r_total;

  -- FALSE-POSITIVE CONTROL: a direct edit to this row MUST land. Without this, the assertion above
  -- would also pass against a database where nothing can be written at all. Assert on the row count
  -- of the write itself, not only on the value read back — a zero-row update followed by a read
  -- would otherwise slip through on stale or NULL data.
  update order_line set discount_pct = 99 where id = v_line;
  get diagnostics r_rows = row_count;
  if r_rows <> 1 then
    raise exception 'FAIL control: the direct edit touched % row(s), not 1 — writes are not landing', r_rows;
  end if;
  select discount_pct into r_disc from order_line where id = v_line;
  if r_disc <> 99 then
    raise exception 'FAIL control: a direct edit did not land (disc=%), so the rule-5 pass proves nothing',
      r_disc;
  end if;
  raise notice 'ok control: a direct edit lands (disc=%), so the unchanged result above is a real result',
    r_disc;

  raise notice 'PROBE PASSED';
end $$;

rollback;
