-- 0016_portal_least_privilege.sql
-- fn_portal_view is for anonymous customers only. Signed-in staff have no use for it.
--
-- 0014 granted EXECUTE to both `anon` and `authenticated`. The anon grant IS the portal — it is the
-- one thing an unauthenticated visitor may call, and CLAUDE.md requires exactly that shape. The
-- authenticated grant was reflex, and nothing uses it: web/portal.html builds its own client with
-- `persistSession: false`, so it always calls as anon even when the operator happens to be signed
-- in on the same phone.
--
-- Revoking it is small but real. A signed-in session already has full table access, so this is not
-- a privilege boundary — it is surface. One fewer route into a function that takes a guessable
-- eight-character code, and one fewer advisor finding to read past when looking for a real one.
--
-- The two findings that REMAIN after this are structural and correct, and should not be silenced:
--   · fn_portal_view executable by anon — that is the portal. The alternative is anon SELECT on
--     ledger_entry, which publishes every customer's account to every other customer.
--   · fn_issue_portal_code executable by authenticated — that is the operator issuing a code.
-- Both are security definer because they must be. A future review should read them and move on.

revoke execute on function fn_portal_view(text, text) from authenticated;

comment on function fn_portal_view is
  'The customer portal gate, callable by anon and by nothing else (0016 revoked the reflexive authenticated grant; web/portal.html always calls as anon). Replace the authentication half with a one-time code when docs/open-questions.md item 2 is settled — fn_portal_snapshot does not change, because it never knew how the caller was authenticated. NOTE: there is no rate limiting; an eight-character code over an unthrottled RPC is guessable given enough attempts, and that is recorded in docs/backlog.md.';
