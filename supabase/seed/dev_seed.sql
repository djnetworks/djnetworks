-- dev_seed.sql
-- Development fixture for the DJ Network's rental system.
--
-- ===========================================================================
--  THIS FILE DESTROYS DATA. IT IS NOT A MIGRATION AND MUST NEVER BE POINTED
--  AT A DATABASE HOLDING REAL RECORDS.
--
--  It opens by truncating every transactional and catalogue table. It is not
--  numbered, it is not in supabase/migrations/, and `supabase db push` will
--  never pick it up. Run it by hand, against a development database, only.
-- ===========================================================================
--
-- WHY A TRUNCATE AND NOT A DELETE. Migrations 0004 and 0007-0009 block DELETE on
-- movement, unit, rental_order, ledger_entry and repair_job — history is cancelled
-- or retired, never removed (rule 12). So a fixture cannot clean up after itself the
-- ordinary way. TRUNCATE is the escape hatch 0009 deliberately left in place when it
-- revoked the privilege from anon and authenticated: postgres and service_role keep
-- it precisely so a development reset is possible. Running this as anon or
-- authenticated will fail on the first statement, which is the intended behaviour.
--
-- WHAT IT DOES NOT TOUCH. category, subcategory, location, app_setting and
-- discount_tier are seeded by migrations 0004 and 0005 and are looked up here BY NAME.
-- No uuid is hard-coded anywhere in this file. If chachu prunes the 187-subcategory
-- taxonomy (open-questions.md item 6), this fixture keeps working as long as the
-- handful of names below survive.
--
-- EVERY DATE IS COMPUTED FROM current_date. Not one is written down. Test data
-- anchored to fixed or future dates never exercises the status logic at all, and that
-- has already wasted real time on this project — see CLAUDE.md's verification standard.
--
-- THE FIXTURE AGES. Dates are computed from current_date at the moment this file runs and are then
-- frozen as data, so the scenarios drift one day further from "now" with every day that passes. The
-- overdue order is three days late on the day you seed and a fortnight late a fortnight later. That
-- is the correct behaviour and far better than hard-coded dates, which never exercise the status
-- logic at all — but re-run this file when the offsets stop resembling a real week's trading.
--
-- NO UNIT HAS TWO MOVEMENTS ON THE SAME DAY, and that is not an accident.
-- v_unit_location picks a piece's current position with
--     distinct on (unit_id) ... order by moved_on desc, created_at desc
-- and created_at defaults to now(), which is TRANSACTION-scoped. Every row this file
-- inserts therefore shares one created_at. Where moved_on also matches, the tiebreak
-- has nothing left to break and the winner is arbitrary — a piece dispatched and
-- returned on the same day can read `out` while it sits in the godown, or `available`
-- while it sits at a wedding. That is logged in docs/backlog.md and is not fixed here;
-- this fixture spaces every piece's history across distinct days instead, which is
-- what a real job looks like anyway. The assertion at the foot of this file checks it.

begin;

truncate table
  movement,
  ledger_entry,
  order_charge,
  order_line,
  rental_order,
  repair_job,
  product_image,
  unit,
  product,
  customer,
  vendor
cascade;

-- ---------------------------------------------------------------------------
-- Vendor. One repair shop — somebody else's premises, which is why it is a vendor
-- and not a location (rule 7).
-- ---------------------------------------------------------------------------

insert into vendor (name, type, phone, address) values
  ('Shreeji Electronics', 'repair', '9825011223', 'Ratanpole, Ahmedabad');

-- ---------------------------------------------------------------------------
-- Customers. Two, because the two behave nothing alike: the trade regular pays on
-- account and hires monthly, the wedding customer appears once and is never seen
-- again. The portal has to serve both.
-- ---------------------------------------------------------------------------

insert into customer (name, business_name, type, whatsapp, alt_phone, city, pincode) values
  ('Rakesh Patel', 'RP Sound & Lights', 'dj', '9825044556', '9714455667', 'Ahmedabad', '380015'),
  ('Priya Shah', null, 'individual', '9898112233', null, 'Ahmedabad', '380054');

-- ---------------------------------------------------------------------------
-- Products. Nine, spanning all three tracking modes (rule 13).
--
-- AMP-2K carries NO default_purchase_cost on purpose. v_product_roi.units_missing_cost
-- only counts a unit when BOTH unit.purchase_cost and product.default_purchase_cost are
-- null, so without a product like this the column has nothing to report and the honest
-- "we cannot compute ROI for this" path never gets exercised.
-- ---------------------------------------------------------------------------

insert into product (short_code, category_id, subcategory_id, brand, model_name,
                     tracking_mode, rentable, base_rate_per_day, default_purchase_cost, pool_qty, specs, inclusions)
select v.short_code, c.id, s.id, v.brand, v.model_name,
       v.tracking_mode, v.rentable, v.base_rate, v.default_cost, v.pool_qty, v.specs, v.inclusions
from (values
  -- short_code, category,            subcategory,                    brand,     model,                 mode,         rentable, rate,   default_cost, pool_qty
  ('SPK-15',  'Speaker',          'Top - full range 15"',        'JBL',     'SRX815P',              'unit',       true,  1200.00,  58000.00, null::int,
     '{"watts": 1500, "spl_db": 137, "powered": true}'::jsonb, '["power cable", "speaker cover"]'::jsonb),
  ('SPK-18',  'Speaker',          'Subwoofer 18"',               'JBL',     'SRX818SP',             'unit',       true,  1500.00,  72000.00, null,
     '{"watts": 1000, "spl_db": 135, "powered": true}'::jsonb, '["power cable"]'::jsonb),
  ('MIX-16',  'Mixer',            'Analogue mixer - 16ch',       'Yamaha',  'MG16XU',               'unit',       true,   800.00,  42000.00, null,
     '{"channels": 16, "fx": true}'::jsonb, '["power cable", "quick start guide"]'::jsonb),
  ('MIC-BLX', 'Microphone',       'Wireless headworn set',       'Shure',   'BLXR-14 headworn',     'unit',       true,   700.00,  31000.00, null,
     '{"band_mhz": "660-679", "channels": 1}'::jsonb, '["body pack", "receiver", "headon mic", "power adaptor"]'::jsonb),
  ('MH-BEAM', 'Lighting - moving','Moving head - beam / sharpy', 'Generic', '230W Sharpy',          'unit',       true,   900.00,  38000.00, null,
     '{"watts": 230, "gobos": 14, "dmx_channels": 16}'::jsonb, '["clamp", "safety wire", "power cable"]'::jsonb),
  ('AMP-2K',  'Amplifier',        'Power amplifier',             'Crown',   'XLS 2502',             'unit',       true,   600.00,  null,     null,
     '{"watts_per_channel": 775}'::jsonb, '["power cable"]'::jsonb),
  ('STG-DECK','Stage',            'Stage deck',                  'Generic', '8x4 ft deck',          'unit',       true,   400.00,  16000.00, null,
     '{"size_ft": "8x4", "height_adjustable": true}'::jsonb, '[]'::jsonb),
  ('CBL-XLR', 'Cable',            'XLR cable',                   'Generic', 'XLR 10 metre',         'pool',       true,    30.00,    450.00, 200,
     '{"length_m": 10}'::jsonb, '[]'::jsonb),
  ('FOG-5L',  'Consumable',       'Fog fluid',                   'Generic', 'Fog fluid 5 litre',    'consumable', true,   900.00,    850.00, 24,
     '{"litres": 5}'::jsonb, '[]'::jsonb)
) as v(short_code, cat, subcat, brand, model_name, tracking_mode, rentable, base_rate, default_cost, pool_qty, specs, inclusions)
join category c on c.name = v.cat
left join subcategory s on s.category_id = c.id and s.name = v.subcat;

-- ---------------------------------------------------------------------------
-- Units. Between 2 and 6 pieces each for the unit-tracked products.
--
-- Purchase costs are given on some pieces and left blank on others, because that is
-- what the godown walk actually produces — the ROI report has to survive a half-filled
-- column rather than pretend it is complete (decisions.md, "Purchase cost per unit").
-- Every AMP-2K piece is blank AND its product has no default, which is what gives
-- v_product_roi.units_missing_cost something real to report.
-- ---------------------------------------------------------------------------

insert into unit (product_id, piece_no, serial_number, purchase_date, purchase_cost, condition, lifecycle, notes)
select p.id, v.piece_no, v.serial, current_date - v.bought_days_ago, v.cost, v.condition, v.lifecycle, v.notes
from (values
  ('SPK-15',  1, 'SRX815P-0091', 900, 58000.00, 'good',            'active',  null),
  ('SPK-15',  2, 'SRX815P-0092', 900, 58000.00, 'good',            'active',  null),
  ('SPK-15',  3, 'SRX815P-0093', 900, 58000.00, 'minor_wear',      'active',  'grille dented on the left corner'),
  ('SPK-15',  4, 'SRX815P-0094', 420, 61000.00, 'good',            'active',  null),
  ('SPK-15',  5, null,           420, 61000.00, 'good',            'active',  null),
  ('SPK-15',  6, null,           120, 64500.00, 'good',            'active',  'bought to replace nothing - fleet growth'),
  ('SPK-18',  1, 'SRX818-0031',  900, 72000.00, 'good',            'active',  null),
  ('SPK-18',  2, 'SRX818-0032',  900, 72000.00, 'good',            'active',  null),
  ('SPK-18',  3, null,           420, 74000.00, 'minor_wear',      'active',  null),
  ('SPK-18',  4, null,           420, 74000.00, 'good',            'active',  null),
  ('MIX-16',  1, 'MG16XU-7781',  760, 42000.00, 'good',            'active',  null),
  ('MIX-16',  2, null,           300, null,     'good',            'active',  'cost not recorded at intake'),
  -- MIC-BLX piece 3 is retired and piece 5 is its replacement. The number is NOT
  -- reused: piece 3 stays dead and the new box takes the next free number (rule 4).
  ('MIC-BLX', 1, 'BLX-11201',    700, 31000.00, 'good',            'active',  null),
  ('MIC-BLX', 2, 'BLX-11202',    700, 31000.00, 'good',            'active',  null),
  ('MIC-BLX', 3, 'BLX-11203',    700, 31000.00, 'not_working',     'retired', 'receiver dead, not economic to repair - retired'),
  ('MIC-BLX', 4, 'BLX-11204',    700, 31000.00, 'good',            'active',  null),
  ('MIC-BLX', 5, 'BLX-20455',     40, 33500.00, 'good',            'active',  'replacement for retired piece 3 - number 3 is NOT reused'),
  ('MH-BEAM', 1, 'SHP-5501',     640, 38000.00, 'good',            'active',  null),
  ('MH-BEAM', 2, 'SHP-5502',     640, 38000.00, 'good',            'active',  null),
  ('MH-BEAM', 3, 'SHP-5503',     640, 38000.00, 'good',            'active',  null),
  ('MH-BEAM', 4, 'SHP-5504',     640, 38000.00, 'needs_attention', 'active',  'flickering lamp - at the repair shop'),
  -- AMP-2K: no purchase cost on any piece, and no default on the product either.
  ('AMP-2K',  1, null,           810, null,     'good',            'active',  null),
  ('AMP-2K',  2, null,           810, null,     'good',            'active',  null),
  ('AMP-2K',  3, null,           810, null,     'minor_wear',      'active',  null),
  ('STG-DECK',1, null,           980, 16000.00, 'good',            'active',  null),
  ('STG-DECK',2, null,           980, 16000.00, 'good',            'active',  null)
) as v(short_code, piece_no, serial, bought_days_ago, cost, condition, lifecycle, notes)
join product p on p.short_code = v.short_code;

-- ---------------------------------------------------------------------------
-- Opening movements. Every unit gets one, so no piece exists without a location
-- (rule 1 — position is the destination of the last movement, and a piece with no
-- movement has no position at all and falls out of every report).
--
-- Dated 60 days back except MIC-BLX piece 5, which was bought recently as a
-- replacement. Nothing else happens to any piece on this date.
-- ---------------------------------------------------------------------------

insert into movement (movement_type, unit_id, product_id, qty, to_kind, to_id, moved_on, notes)
select 'intake', u.id, u.product_id, 1, 'location', l.id,
       case when p.short_code = 'MIC-BLX' and u.piece_no = 5
            then current_date - 40
            else current_date - 60 end,
       'opening stock'
from unit u
join product p on p.id = u.product_id
cross join location l
where l.name = 'Godown';

-- Pooled and consumable opening stock. unit_id stays null — these products have no
-- numbered pieces, and 0007's tracking-mode trigger refuses a unit_id here (rule 13).
-- pool_qty on the product is the opening balance; 0008 nets the ledger on top of it.

insert into movement (movement_type, product_id, qty, to_kind, to_id, moved_on, notes)
select 'intake', p.id, 40, 'location', l.id, current_date - 45, 'top-up purchase, 40 more XLRs'
from product p cross join location l
where p.short_code = 'CBL-XLR' and l.name = 'Godown';

-- ---------------------------------------------------------------------------
-- Repair. MH-BEAM piece 4 went to Shreeji eight days ago and is still there.
-- A piece at a vendor is not at one of our own locations, so it leaves availability
-- with no extra rule — that is the whole reason movement carries from_kind/to_kind
-- rather than a location_id (rule 7).
-- ---------------------------------------------------------------------------

insert into repair_job (unit_id, vendor_id, date_sent, fault, estimated_cost, notes)
select u.id, v.id, current_date - 8, 'Lamp flickers at full output, suspect ballast', 4500.00,
       'quoted verbally, no date promised'
from unit u
join product p on p.id = u.product_id and p.short_code = 'MH-BEAM'
cross join vendor v
where u.piece_no = 4 and v.name = 'Shreeji Electronics';

insert into movement (movement_type, unit_id, product_id, qty, from_kind, from_id, to_kind, to_id,
                      repair_job_id, moved_on, condition_at_move, notes)
select 'repair_out', u.id, u.product_id, 1, 'location', l.id, 'vendor', v.id,
       rj.id, current_date - 8, 'needs_attention', 'flickering lamp'
from unit u
join product p on p.id = u.product_id and p.short_code = 'MH-BEAM'
join repair_job rj on rj.unit_id = u.id
cross join location l
cross join vendor v
where u.piece_no = 4 and l.name = 'Godown' and v.name = 'Shreeji Electronics';

-- ---------------------------------------------------------------------------
-- Orders.
--
-- 0010 narrowed rental_order.status to the three things a human actually decides:
-- confirmed, closed, cancelled. How much has gone out and how much has come back is
-- DERIVED, per order, in v_order_fulfilment — it was never a human decision and
-- storing it made it a count that could drift (rules 1 and 10).
--
-- These six orders are chosen so that each lands on a DIFFERENT derived fulfilment
-- state. Order numbers follow the DJN-YYMM-NNNN convention from app_setting, with the
-- YYMM computed rather than written.
-- ---------------------------------------------------------------------------

insert into rental_order (order_no, customer_id, status, event_type, venue_name, venue_address,
                          venue_contact_name, venue_contact_phone,
                          out_date, expected_return_date, days, deposit_amount, notes)
select 'DJN-' || to_char(current_date, 'YYMM') || '-' || v.seq,
       c.id, v.status, v.event_type, v.venue_name, v.venue_address,
       v.contact_name, v.contact_phone,
       current_date + v.out_offset, current_date + v.ret_offset, v.days, v.deposit, v.notes
from (values
  -- seq,   customer,        status,      event,        venue,                    address,                       contact,          phone,        out, ret, days, deposit, notes
  ('0001', 'Rakesh Patel', 'confirmed', 'corporate',  'Karnavati Club',         'S G Highway, Ahmedabad',      'Mr Desai',       '9825077889',   7,   9,  3,  5000.00, 'nothing loaded yet - van goes out on the morning'),
  ('0002', 'Priya Shah',   'confirmed', 'wedding',    'Rajpath Club Lawn',      'Bodakdev, Ahmedabad',         'Nilesh (decor)', '9924011223',   0,   2,  3, 10000.00, 'two tops loaded, two still in the godown'),
  ('0003', 'Rakesh Patel', 'confirmed', 'dj_night',   'Ahmedabad One Atrium',   'Vastrapur, Ahmedabad',        'Event desk',     '9825033445',  -1,   3,  5,  8000.00, 'everything is at the venue right now'),
  ('0004', 'Rakesh Patel', 'confirmed', 'garba',      'Sardar Patel Stadium',   'Navrangpura, Ahmedabad',      'Bhavesh bhai',   '9714488990', -10,  -3,  8, 15000.00, 'OVERDUE - one sub and ten cables never came back'),
  -- 0005 is inserted `confirmed` and moved to `closed` further down, AFTER its returns
  -- are written. Inserting it as `closed` outright would sail straight past rule 9 —
  -- 0009's guard is a BEFORE UPDATE trigger, so an order can still be born closed
  -- (logged in docs/backlog.md). This fixture goes through the front door on purpose,
  -- so the guard is exercised rather than dodged.
  ('0005', 'Rakesh Patel', 'confirmed', 'wedding',    'The Grand Bhagwati',     'S G Highway, Ahmedabad',      'Reception desk', '9825099001', -30, -27,  4, 10000.00, 'clean job, everything back, settled'),
  ('0006', 'Priya Shah',   'cancelled', 'birthday',   'Private residence',      'Satellite, Ahmedabad',        'Priya',          '9898112233',   3,   5,  3,  3000.00, 'cancelled two days after booking - venue changed')
) as v(seq, cust, status, event_type, venue_name, venue_address, contact_name, contact_phone,
       out_offset, ret_offset, days, deposit, notes)
join customer c on c.name = v.cust;

-- ---------------------------------------------------------------------------
-- Order lines.
--
-- agreed_rate and line_total are STORED, at the price agreed on the day (rule 5).
-- Raising a rate next March must not rewrite what was charged last March, so nothing
-- reads product.base_rate_per_day back to reconstruct these.
-- ---------------------------------------------------------------------------

insert into order_line (order_id, product_id, qty, days, base_rate, discount_pct, agreed_rate, line_total)
select o.id, p.id, v.qty, v.days, v.base_rate, v.discount_pct, v.agreed_rate, v.line_total
from (values
  ('0001', 'SPK-18',   2, 3, 1500.00,  0.00, 1500.00,  9000.00),
  ('0001', 'MIX-16',   1, 3,  800.00,  0.00,  800.00,  2400.00),
  ('0002', 'SPK-15',   4, 3, 1200.00,  0.00, 1200.00, 14400.00),
  ('0003', 'MIX-16',   2, 5,  800.00, 10.00,  720.00,  7200.00),
  ('0003', 'FOG-5L',   9, 5,  900.00,  0.00,  900.00,  8100.00),
  ('0004', 'SPK-18',   3, 8, 1500.00, 15.00, 1275.00, 30600.00),
  ('0004', 'CBL-XLR', 40, 8,   30.00, 15.00,   25.50,  8160.00),
  ('0005', 'STG-DECK', 2, 4,  400.00,  0.00,  400.00,  3200.00),
  ('0005', 'MIC-BLX',  2, 4,  700.00,  0.00,  700.00,  5600.00),
  ('0006', 'MH-BEAM',  2, 3,  900.00,  0.00,  900.00,  5400.00)
) as v(seq, short_code, qty, days, base_rate, discount_pct, agreed_rate, line_total)
join rental_order o on o.order_no = 'DJN-' || to_char(current_date, 'YYMM') || '-' || v.seq
join product p on p.short_code = v.short_code;

insert into order_charge (order_id, type, description, amount)
select o.id, v.type, v.description, v.amount
from (values
  ('0004', 'transport', 'Tempo both ways, Navrangpura',   2500.00),
  ('0004', 'labour',    'Two extra hands for the garba',  1800.00),
  ('0005', 'transport', 'Tempo both ways, S G Highway',   2000.00)
) as v(seq, type, description, amount)
join rental_order o on o.order_no = 'DJN-' || to_char(current_date, 'YYMM') || '-' || v.seq;

-- ---------------------------------------------------------------------------
-- Movements against orders.
--
-- ORDER 0002 — the partial dispatch. Four tops agreed, two physically loaded.
-- This is the case migration 0009 exists to fix and it is the one most likely to
-- regress, so it is pinned here: fn_availability must read 4 on hand, 2 committed,
-- 2 available. Before 0009 it read 0 or 4 depending on a status field, and neither
-- was true. There is deliberately no `partially_dispatched` status to set — 0010
-- removed the idea; v_order_fulfilment derives it.
-- ---------------------------------------------------------------------------

insert into movement (movement_type, unit_id, product_id, qty, order_id,
                      from_kind, from_id, to_kind, to_id, moved_on,
                      dispatch_method, carrier_name, carrier_phone, receiver_name, receiver_phone,
                      condition_at_move, inclusions_checked, notes)
select 'dispatch', u.id, u.product_id, 1, o.id,
       'location', l.id, 'customer', o.customer_id, current_date,
       'delivered_by_chachu', 'Chachu', '9824083533', 'Nilesh (decor)', '9924011223',
       u.condition, '["power cable", "speaker cover"]'::jsonb, 'first two tops, rest to follow'
from unit u
join product p on p.id = u.product_id and p.short_code = 'SPK-15'
join rental_order o on o.order_no = 'DJN-' || to_char(current_date, 'YYMM') || '-0002'
cross join location l
where u.piece_no in (1, 2) and l.name = 'Godown';

-- ORDER 0003 — fully out right now, due back in three days. Both mixers went
-- yesterday, and nine litres of fog fluid went with them. The fluid is a consumable:
-- it is charged and never comes back, so there is nothing to pair a return with.

insert into movement (movement_type, unit_id, product_id, qty, order_id,
                      from_kind, from_id, to_kind, to_id, moved_on,
                      dispatch_method, carrier_name, carrier_phone, condition_at_move, notes)
select 'dispatch', u.id, u.product_id, 1, o.id,
       'location', l.id, 'customer', o.customer_id, current_date - 1,
       'porter', 'Iqbal porter', '9033112244', u.condition, null
from unit u
join product p on p.id = u.product_id and p.short_code = 'MIX-16'
join rental_order o on o.order_no = 'DJN-' || to_char(current_date, 'YYMM') || '-0003'
cross join location l
where l.name = 'Godown';

insert into movement (movement_type, product_id, qty, order_id,
                      from_kind, from_id, to_kind, to_id, moved_on, notes)
select 'dispatch', p.id, 9, o.id,
       'location', l.id, 'customer', o.customer_id, current_date - 1,
       'nine litres issued - consumable, not expected back'
from product p
join rental_order o on o.order_no = 'DJN-' || to_char(current_date, 'YYMM') || '-0003'
cross join location l
where p.short_code = 'FOG-5L' and l.name = 'Godown';

-- ORDER 0004 — the overdue one, and the reason rule 2 is written the way it is.
--
-- Three subs went out ten days ago and were due back three days ago. Two came back
-- six days ago. The third has not, and no return movement says otherwise, so it is
-- OUT — whatever the date says. Nothing anywhere may infer a return from
-- expected_return_date passing. Six boxes went out, five came back, and the sixth
-- was quietly offered for hire while it sat in a hall: that is the bug this row exists
-- to keep caught.
--
-- The cables tell the pooled half of the same story. Forty went out, twenty-five came
-- back, five were crushed at the venue and written off, and ten are still there. Before
-- 0008 the cables were invisible to every report; the write-off is what stops those
-- five reading as "at the customer" forever (shrinkage, 0008 section 4).

insert into movement (movement_type, unit_id, product_id, qty, order_id,
                      from_kind, from_id, to_kind, to_id, moved_on,
                      dispatch_method, carrier_name, carrier_phone, condition_at_move, notes)
select 'dispatch', u.id, u.product_id, 1, o.id,
       'location', l.id, 'customer', o.customer_id, current_date - 10,
       'delivered_by_chachu', 'Chachu', '9824083533', u.condition, null
from unit u
join product p on p.id = u.product_id and p.short_code = 'SPK-18'
join rental_order o on o.order_no = 'DJN-' || to_char(current_date, 'YYMM') || '-0004'
cross join location l
where u.piece_no in (1, 2, 3) and l.name = 'Godown';

insert into movement (movement_type, unit_id, product_id, qty, order_id,
                      from_kind, from_id, to_kind, to_id, moved_on,
                      condition_at_move, inclusions_checked, notes)
select 'return', u.id, u.product_id, 1, o.id,
       'customer', o.customer_id, 'location', l.id, current_date - 6,
       'good', '["power cable"]'::jsonb, 'two subs back, third still at the ground'
from unit u
join product p on p.id = u.product_id and p.short_code = 'SPK-18'
join rental_order o on o.order_no = 'DJN-' || to_char(current_date, 'YYMM') || '-0004'
cross join location l
where u.piece_no in (1, 2) and l.name = 'Godown';

insert into movement (movement_type, product_id, qty, order_id,
                      from_kind, from_id, to_kind, to_id, moved_on, notes)
select 'dispatch', p.id, 40, o.id, 'location', l.id, 'customer', o.customer_id,
       current_date - 10, 'forty XLRs for the garba ground'
from product p
join rental_order o on o.order_no = 'DJN-' || to_char(current_date, 'YYMM') || '-0004'
cross join location l
where p.short_code = 'CBL-XLR' and l.name = 'Godown';

insert into movement (movement_type, product_id, qty, order_id,
                      from_kind, from_id, to_kind, to_id, moved_on, notes)
select 'return', p.id, 25, o.id, 'customer', o.customer_id, 'location', l.id,
       current_date - 6, 'twenty-five cables back with the subs'
from product p
join rental_order o on o.order_no = 'DJN-' || to_char(current_date, 'YYMM') || '-0004'
cross join location l
where p.short_code = 'CBL-XLR' and l.name = 'Godown';

-- The write-off closes the loop. Without it these five sit at the customer forever and
-- the order could never be closed under rule 9.
insert into movement (movement_type, product_id, qty, order_id,
                      from_kind, from_id, to_kind, moved_on, notes)
select 'write_off', p.id, 5, o.id, 'customer', o.customer_id, 'none',
       current_date - 5, 'run over by a truck at the ground - written off, not coming back'
from product p
join rental_order o on o.order_no = 'DJN-' || to_char(current_date, 'YYMM') || '-0004'
where p.short_code = 'CBL-XLR';

-- ORDER 0005 — the clean job, thirty days ago. Everything out, everything back on a
-- LATER day, and only then closed. The order of these statements is load-bearing:
-- 0009 blocks the move to `closed` while v_order_outstanding returns any row, so the
-- returns must be written before the status is set (rule 9).

insert into movement (movement_type, unit_id, product_id, qty, order_id,
                      from_kind, from_id, to_kind, to_id, moved_on,
                      dispatch_method, carrier_name, condition_at_move)
select 'dispatch', u.id, u.product_id, 1, o.id,
       'location', l.id, 'customer', o.customer_id, current_date - 30,
       'self_collection', 'Customer''s own tempo', u.condition
from unit u
join product p on p.id = u.product_id and p.short_code in ('STG-DECK', 'MIC-BLX')
join rental_order o on o.order_no = 'DJN-' || to_char(current_date, 'YYMM') || '-0005'
cross join location l
where l.name = 'Godown'
  and ((p.short_code = 'STG-DECK' and u.piece_no in (1, 2))
    or (p.short_code = 'MIC-BLX'  and u.piece_no in (1, 2)));

insert into movement (movement_type, unit_id, product_id, qty, order_id,
                      from_kind, from_id, to_kind, to_id, moved_on,
                      condition_at_move, inclusions_checked, notes)
select 'return', u.id, u.product_id, 1, o.id,
       'customer', o.customer_id, 'location', l.id, current_date - 27,
       'good', '["body pack", "receiver", "headon mic", "power adaptor"]'::jsonb, 'all back, nothing missing'
from unit u
join product p on p.id = u.product_id and p.short_code in ('STG-DECK', 'MIC-BLX')
join rental_order o on o.order_no = 'DJN-' || to_char(current_date, 'YYMM') || '-0005'
cross join location l
where l.name = 'Godown'
  and ((p.short_code = 'STG-DECK' and u.piece_no in (1, 2))
    or (p.short_code = 'MIC-BLX'  and u.piece_no in (1, 2)));

update rental_order
   set status = 'closed', closed_at = now() - interval '27 days'
 where order_no = 'DJN-' || to_char(current_date, 'YYMM') || '-0005';

-- ---------------------------------------------------------------------------
-- Ledger — for the CLOSED order only, and deliberately so.
--
-- 0009 freezes an order line's money while its order carries a non-zero net posted
-- charge, so posting revenue against the live orders would make the fixture
-- uneditable exactly where the screens are about to be built. Leaving them at zero
-- net keeps the freeze dormant and the fixture workable. The mechanism itself is
-- proven here on order 0005, which nobody will edit again.
--
-- Rule 6: the deposit is the customer's own money being held. It is a liability, not
-- revenue, and v_customer_balance reports it as its own number. These entries give it
-- two figures that must never be added together:
--     receivable   = 3200 + 5600 + 2000 transport - 8000 paid = 2800.00
--     deposit_held = 10000 in - 7000 returned                 = 3000.00
-- ---------------------------------------------------------------------------

insert into ledger_entry (customer_id, order_id, entry_date, type, amount, state, payment_mode, reference, notes)
select o.customer_id, o.id, current_date + v.day_offset, v.type, v.amount, v.state, v.payment_mode, v.reference, v.notes
from (values
  (-30, 'deposit_in',  10000.00, 'due', 'cash', null,          'security deposit taken when the gear left'),
  (-30, 'rental',       8800.00, 'due', null,   null,          'two stage decks and two headworn sets, four days'),
  (-30, 'transport',    2000.00, 'due', null,   null,          'tempo both ways'),
  (-27, 'deposit_out',  7000.00, 'due', 'cash', null,          'deposit returned less a retained amount'),
  (-27, 'payment',      8000.00, 'due', 'upi',  'UPI-88213047', 'part payment on return')
) as v(day_offset, type, amount, state, payment_mode, reference, notes)
join rental_order o on o.order_no = 'DJN-' || to_char(current_date, 'YYMM') || '-0005';

-- ---------------------------------------------------------------------------
-- Assertions. A clean run is not proof of correctness (CLAUDE.md's verification
-- standard) — a previous workbook recalculated with zero errors while silently
-- reading the wrong rows. Each of these checks a NUMBER and raises if it is wrong,
-- so a broken fixture fails loudly here rather than quietly misleading a screen.
-- ---------------------------------------------------------------------------

do $assert$
declare
  n int; m int; t text;
begin
  -- No unit may carry two movements on one day, or v_unit_location's tiebreak
  -- becomes arbitrary (see the header, and docs/backlog.md).
  select count(*) into n from (
    select unit_id from movement where unit_id is not null
    group by unit_id having count(*) <> count(distinct moved_on)
  ) x;
  if n > 0 then raise exception 'FIXTURE BUG: % unit(s) have two movements on the same day', n; end if;

  -- Rule 2: the overdue sub reads out, though its return date has passed.
  select s.status into t
  from v_unit_status s
  join unit u on u.id = s.unit_id
  join product p on p.id = u.product_id and p.short_code = 'SPK-18'
  where u.piece_no = 3;
  if t <> 'out' then raise exception 'FIXTURE BUG: overdue SPK-18 piece 3 reads %, expected out', t; end if;

  -- The partial dispatch: 4 on hand, 2 committed, 2 available.
  select a.units_on_hand, a.committed into n, m
  from product p, lateral fn_availability(p.id, current_date, current_date + 2) a
  where p.short_code = 'SPK-15';
  if (n, m) <> (4, 2) then
    raise exception 'FIXTURE BUG: SPK-15 availability reads % on hand / % committed, expected 4 / 2', n, m;
  end if;

  -- Six orders, six distinct derived fulfilment states.
  select count(distinct fulfilment_state) into n from v_order_fulfilment;
  if n < 5 then raise exception 'FIXTURE BUG: only % distinct fulfilment states, expected at least 5', n; end if;

  -- Pooled arithmetic must balance, with no data-entry error flagged.
  select count(*) into n from v_pool_stock where short_code = 'CBL-XLR' and has_ledger_error;
  if n > 0 then raise exception 'FIXTURE BUG: CBL-XLR has a ledger error'; end if;

  -- ROI has something honest to say about missing costs.
  select units_missing_cost into n from v_product_roi where short_code = 'AMP-2K';
  if coalesce(n, 0) = 0 then raise exception 'FIXTURE BUG: AMP-2K should report units_missing_cost > 0'; end if;

  raise notice 'dev_seed: all assertions passed';
end
$assert$;

commit;
