-- 0014_portal_and_deposit_guard.sql
-- The customer portal's data path, and a guard on refunding a deposit that was never taken.
--
-- Three things, and the first two are one design:
--   1. A per-customer portal access code, stored HASHED and shown exactly once.
--   2. The portal read: a SECURITY DEFINER function, deliberately split into a GATE and a QUERY.
--   3. A deposit refund can no longer exceed the deposit held.

-- ---------------------------------------------------------------------------
-- 1 · The access code.
--
-- Stored as a bcrypt hash, never in the clear. It is a password to one customer's account history:
-- what they hired, what they owe, what deposit is held. A plaintext column would mean a leak of the
-- customer table is a leak of every portal login at once.
--
-- Generated INSIDE the database, on purpose. If the browser generated it and posted it here, the
-- plaintext would travel over the wire and sit in a request log; this way it exists in one response
-- and nowhere else. The screen shows it once, chachu pastes it into WhatsApp, and after that
-- nobody — including him — can read it back. Reissuing is the only recovery, which is the correct
-- shape for a code and the wrong shape for a secret nobody can replace.
--
-- Rule 11 is untouched and stays untouched: there is still no column here for an Aadhaar or PAN
-- number, and this is not one. The ID document remains a URL to cloud storage.
-- ---------------------------------------------------------------------------

alter table customer add column if not exists portal_code_hash text;
alter table customer add column if not exists portal_code_issued_at timestamptz;

comment on column customer.portal_code_hash is
  'bcrypt hash of the portal access code. Never the code itself — this is a password to one customer''s whole account history. Issued by fn_issue_portal_code, which returns the plaintext exactly once.';

create or replace function fn_issue_portal_code(p_customer_id uuid)
returns text
language plpgsql
security definer
set search_path = public, extensions, pg_temp
as $$
declare
  v_alphabet constant text := 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';  -- no O/0, no I/1: it is read aloud
  v_code text := '';
  i int;
begin
  if not exists (select 1 from customer where id = p_customer_id) then
    raise exception 'No such customer.';
  end if;

  -- Two groups of four, which is how a person reads a code down a telephone.
  for i in 1..8 loop
    v_code := v_code || substr(v_alphabet,
      1 + floor(random() * length(v_alphabet))::int, 1);
    if i = 4 then v_code := v_code || '-'; end if;
  end loop;

  update customer
     set portal_code_hash = extensions.crypt(v_code, extensions.gen_salt('bf')),
         portal_code_issued_at = now()
   where id = p_customer_id;

  return v_code;   -- the only time this value exists outside the customer's phone
end $$;

revoke all on function fn_issue_portal_code(uuid) from public, anon;
grant execute on function fn_issue_portal_code(uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- 2 · The portal read.
--
-- SPLIT IN TWO, DELIBERATELY, and this is the load-bearing part of the design.
--
--   fn_portal_snapshot(customer_id)  — the QUERY. Knows nothing about how the caller proved who
--                                      they are. NOT granted to anon: it takes a customer_id and
--                                      would hand over anybody's account to anybody who guessed one.
--   fn_portal_view(phone, code)      — the GATE. The only thing anon may call. Checks the code,
--                                      then calls the query.
--
-- The gate is expected to be replaced. docs/open-questions.md item 2 is still open: a static code
-- means a stream of one-off wedding customers who never remember it, and a phone number with a
-- one-time code is the alternative on the table. When that is decided, only fn_portal_view changes.
-- The query it protects does not, because it never knew how authentication worked.
--
-- WHY NOT ANON TABLE ACCESS. Opening SELECT on ledger_entry to make this screen work would publish
-- every customer's account to every other customer, and to anybody with the publishable key — which
-- ships in the page source. CLAUDE.md says this in as many words. A security definer function is
-- the only shape that returns one customer's rows and nothing else.
-- ---------------------------------------------------------------------------

create or replace function fn_portal_snapshot(p_customer_id uuid)
returns jsonb
language sql
security definer
stable
set search_path = public, pg_temp
as $$
  select jsonb_build_object(
    'customer', (
      select jsonb_build_object('name', c.name, 'business_name', c.business_name, 'city', c.city)
      from customer c where c.id = p_customer_id
    ),
    -- Rule 6, and the portal is where it matters most: receivable, upcoming and deposit_held are
    -- three separate figures and are never added together. A deposit is the customer's own money.
    'balance', (
      select jsonb_build_object(
        'receivable', b.receivable, 'upcoming', b.upcoming, 'deposit_held', b.deposit_held)
      from v_customer_balance b where b.customer_id = p_customer_id
    ),
    'orders', coalesce((
      select jsonb_agg(jsonb_build_object(
        'order_no', o.order_no, 'status', o.status,
        'out_date', o.out_date, 'expected_return_date', o.expected_return_date,
        'days', o.days, 'venue_name', o.venue_name,
        'deposit_amount', o.deposit_amount,
        'fulfilment_state', f.fulfilment_state,
        'qty_ordered', f.qty_ordered, 'qty_outstanding', f.qty_outstanding,
        -- PRODUCT NAMES, NEVER PIECE NUMBERS (rule 8). A customer has no idea what "piece 3" is;
        -- the sticker means something only in the godown.
        'lines', coalesce((
          select jsonb_agg(jsonb_build_object(
            'product', coalesce(p.brand || ' ', '') || p.model_name,
            'qty', ol.qty, 'days', ol.days, 'line_total', ol.line_total)
            order by p.model_name)
          from order_line ol join product p on p.id = ol.product_id
          where ol.order_id = o.id), '[]'::jsonb)
      ) order by o.out_date desc)
      from rental_order o
      left join v_order_fulfilment f on f.order_id = o.id
      where o.customer_id = p_customer_id), '[]'::jsonb),
    'out_now', coalesce((
      select jsonb_agg(jsonb_build_object(
        'order_no', oo.order_no,
        'product', coalesce(p.brand || ' ', '') || p.model_name,
        'qty', oo.qty_outstanding,
        'expected_return_date', oo.expected_return_date,
        'days_overdue', oo.days_overdue))
      from v_order_outstanding oo
      join product p on p.id = oo.product_id
      where oo.customer_id = p_customer_id), '[]'::jsonb),
    'ledger', coalesce((
      select jsonb_agg(jsonb_build_object(
        'entry_date', le.entry_date, 'type', le.type, 'amount', le.amount,
        'state', le.state, 'payment_mode', le.payment_mode,
        'reference', le.reference, 'notes', le.notes,
        'order_no', o.order_no)
        order by le.entry_date desc, le.created_at desc)
      from ledger_entry le
      left join rental_order o on o.id = le.order_id
      where le.customer_id = p_customer_id), '[]'::jsonb)
  );
$$;

-- The query is never callable directly. It trusts its argument completely, which is safe only
-- because nothing untrusted can reach it.
revoke all on function fn_portal_snapshot(uuid) from public, anon, authenticated;

create or replace function fn_portal_view(p_phone text, p_code text)
returns jsonb
language plpgsql
security definer
stable
set search_path = public, extensions, pg_temp
as $$
declare
  v_id uuid;
  v_hash text;
begin
  if p_phone is null or p_code is null then
    raise exception 'Enter your phone number and your access code.';
  end if;

  -- Matched on the digits only, so +91, spaces and dashes all work. A customer typing their own
  -- number will not type it the way it was entered in the office.
  select c.id, c.portal_code_hash into v_id, v_hash
  from customer c
  where regexp_replace(c.whatsapp, '\D', '', 'g') like '%' || regexp_replace(p_phone, '\D', '', 'g')
    and c.active
  limit 1;

  -- One message for "no such number" and "wrong code" alike. Distinguishing them turns this into
  -- a way to discover which numbers are customers.
  if v_id is null or v_hash is null
     or extensions.crypt(p_code, v_hash) <> v_hash then
    raise exception 'That phone number and access code do not match. Ask DJ Network''s for a new code.';
  end if;

  return fn_portal_snapshot(v_id);
end $$;

revoke all on function fn_portal_view(text, text) from public;
grant execute on function fn_portal_view(text, text) to anon, authenticated;

comment on function fn_portal_view is
  'The customer portal gate. Anon may call this and nothing else. Replace the authentication half with a one-time code when docs/open-questions.md item 2 is settled — fn_portal_snapshot does not need to change, because it never knew how the caller was authenticated. NOTE: there is no rate limiting here; an eight-character code over an unthrottled RPC is guessable given enough attempts, and that is recorded in docs/backlog.md.';

-- ---------------------------------------------------------------------------
-- 3 · A deposit cannot be refunded beyond what is held.
--
-- Measured before this migration: deposit_in 1000 followed by deposit_out 4000 left
-- v_customer_balance.deposit_held at -3000.00, with no error and no flag. Rule 6 survived —
-- receivable was untouched, so the two numbers never blended — but a negative liability is not a
-- state this business can be in, and on the portal it reads as the company owing the customer money
-- it never took.
--
-- The guard is in the database rather than only on the payments screen because the ledger is
-- reachable from the Sheet importer and from any future screen, and this is an arithmetic
-- impossibility rather than a form-validation nicety. The screen still says it first, in a
-- sentence; this is what makes the sentence true.
-- ---------------------------------------------------------------------------

create or replace function fn_deposit_not_overdrawn()
returns trigger
language plpgsql
set search_path = public, pg_temp
as $$
declare
  v_held numeric(12,2);
  v_name text;
begin
  if new.type not in ('deposit_out', 'deposit_forfeit') then
    return new;
  end if;

  -- Computed exactly as v_customer_balance computes it, so the guard and the screen can never
  -- disagree about what is held.
  select coalesce(sum(
           case le.type
             when 'deposit_in'      then  le.amount
             when 'deposit_out'     then -le.amount
             when 'deposit_forfeit' then -le.amount
             else 0
           end), 0)
    into v_held
  from ledger_entry le
  where le.customer_id = new.customer_id;

  if new.amount > v_held then
    select c.name into v_name from customer c where c.id = new.customer_id;
    raise exception
      'Only % is held as a deposit for %, so % cannot be %. A deposit is the customer''s own money and the amount held can never go below zero (CLAUDE.md rule 6). Check the figure, or record the difference as a payment or a damage charge instead — those are revenue, and a deposit is not.',
      to_char(v_held, 'FM999,999,990.00'),
      coalesce(v_name, 'this customer'),
      to_char(new.amount, 'FM999,999,990.00'),
      case new.type when 'deposit_out' then 'refunded' else 'forfeited' end;
  end if;

  return new;
end $$;

drop trigger if exists ledger_deposit_not_overdrawn on ledger_entry;
create trigger ledger_deposit_not_overdrawn
  before insert on ledger_entry
  for each row execute function fn_deposit_not_overdrawn();
