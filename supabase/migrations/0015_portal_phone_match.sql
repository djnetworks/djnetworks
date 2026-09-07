-- 0015_portal_phone_match.sql
-- The portal gate refused a customer typing their own phone number with a country code.
--
-- 0014 matched with `stored_digits LIKE '%' || typed_digits`, which is backwards. The stored number
-- is the SHORT one — `9898112233` as entered in the office — and the typed one is the LONG one,
-- because a customer reading their number off their own phone types `+91 98981-12233`. So the test
-- asked whether `9898112233` ends with `919898112233`, which it never can.
--
-- Measured on 0014 before this fix:
--   fn_portal_view('9898112233',     <code>)  -> accepted
--   fn_portal_view('+91 98981-12233', <code>) -> REFUSED
--
-- The refusal is indistinguishable from a wrong code, by design, so the customer has no way to
-- work out what they did wrong. They would message chachu — which is the exact failure the portal
-- exists to prevent, and docs/open-questions.md item 2 already names it as the risk that makes a
-- portal go unused.
--
-- Compare the LAST TEN DIGITS of each instead. Indian mobile numbers are ten digits, and this makes
-- the comparison indifferent to a leading 0, a +91, a 91, spaces, dashes and brackets on either
-- side. Nothing else about the gate changes, and fn_portal_snapshot is untouched — which is the
-- point of having split them.

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
  v_typed text;
begin
  if p_phone is null or p_code is null then
    raise exception 'Enter your phone number and your access code.';
  end if;

  v_typed := right(regexp_replace(p_phone, '\D', '', 'g'), 10);
  if length(v_typed) < 10 then
    raise exception 'That phone number and access code do not match. Ask DJ Network''s for a new code.';
  end if;

  -- Last ten digits on both sides: indifferent to +91, a leading 0, spaces, dashes and brackets,
  -- whichever side they appear on.
  select c.id, c.portal_code_hash into v_id, v_hash
  from customer c
  where right(regexp_replace(c.whatsapp, '\D', '', 'g'), 10) = v_typed
    and c.active
  limit 1;

  -- One message for "no such number" and "wrong code" alike. Distinguishing them would turn this
  -- into a way of discovering which numbers are customers.
  if v_id is null or v_hash is null
     or extensions.crypt(p_code, v_hash) <> v_hash then
    raise exception 'That phone number and access code do not match. Ask DJ Network''s for a new code.';
  end if;

  return fn_portal_snapshot(v_id);
end $$;

revoke all on function fn_portal_view(text, text) from public;
grant execute on function fn_portal_view(text, text) to anon, authenticated;
