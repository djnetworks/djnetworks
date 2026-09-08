// team-create — the ONLY thing in this system that creates a login.
//
// Why it is an Edge Function and not a browser call: creating an auth user needs the service_role
// key, and a key that can create an account can create an admin. That key must never reach the
// browser, config.js, or this public repo. It lives ONLY in this function's Supabase secrets
// (SUPABASE_SERVICE_ROLE_KEY, auto-injected). team.html says the same at the point of use.
//
// TRUST NOTHING FROM THE BODY. The caller is resolved from their verified JWT, never from an id in
// the request. The new account's id comes from the auth admin API's response, never from the body.
// A body that names a different user id changes nothing — no code path reads one.
//
// Fail closed on every path: an unverifiable caller, a non-admin caller, a rate-limited caller and
// a malformed body all create nothing and return before the service_role key touches anything.
//
// Account creation and permission granting are SEPARATE and permissions have exactly ONE writer:
//   1. service_role calls the auth admin API to make the login (email-confirmed, no invite mail).
//   2. the CALLER's own JWT calls fn_team_add — the same admin.team choke point every other write
//      goes through (0021/0023). If step 2 fails, step 1 is rolled back so no orphan login is left.

import { createClient } from 'jsr:@supabase/supabase-js@2';

const SUPABASE_URL = Deno.env.get('SUPABASE_URL')!;
const SERVICE_KEY  = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;

// The eleven keys, and only these, may be granted. A closed allowlist so a body cannot smuggle an
// unknown or future-sensitive key past fn_team_add. Same list as 0021's policy map, 0023, team.html
// and isVanOnly(); a twelfth key added anywhere must be added here too.
const KNOWN_KEYS = new Set([
  'orders.write', 'sendout.write', 'returns.write', 'movement.correct',
  'products.write', 'equipment.write', 'customers.write',
  'ledger.view', 'ledger.write', 'numbers.view', 'admin.team',
]);

const cors = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};
const json = (status: number, body: Record<string, unknown>) =>
  new Response(JSON.stringify(body), { status, headers: { ...cors, 'content-type': 'application/json' } });

/** The caller's IP, exactly as fn_portal_client_ip does it (0029): cf-connecting-ip (unforgeable),
 *  then sb-forwarded-for, then the LAST element of x-forwarded-for — never the first, because a
 *  client can prepend one and did, in testing. */
function clientIp(req: Request): string | null {
  const cf = req.headers.get('cf-connecting-ip');
  if (cf) return cf.trim();
  const sb = req.headers.get('sb-forwarded-for');
  if (sb) return sb.trim();
  const xff = req.headers.get('x-forwarded-for');
  if (xff) { const parts = xff.split(','); const last = parts[parts.length - 1].trim(); if (last) return last; }
  return null;
}

const service = createClient(SUPABASE_URL, SERVICE_KEY, { auth: { persistSession: false } });

async function log(row: { actor?: string | null; email?: string | null; ip: string | null; ok: boolean; outcome: string }) {
  try {
    await service.from('team_create_attempt').insert({
      actor: row.actor ?? null, email_tried: row.email ?? null, ip: row.ip, ok: row.ok, outcome: row.outcome,
    });
  } catch { /* the log must never be the reason a refusal fails to return */ }
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: cors });
  const ip = clientIp(req);
  if (req.method !== 'POST') return json(405, { error: 'POST only.' });

  // ---- 1 · the caller's JWT, and NOTHING proceeds without it -------------------------------------
  const authHeader = req.headers.get('authorization') ?? '';
  const apikey = req.headers.get('apikey') ?? '';
  const token = authHeader.toLowerCase().startsWith('bearer ') ? authHeader.slice(7).trim() : '';
  if (!token || !apikey) {
    await log({ ip, ok: false, outcome: 'no_jwt' });
    return json(401, { error: 'Sign in as somebody who manages the team.' });
  }

  // The caller's own client: the public apikey plus their JWT, exactly the pair the frontend uses.
  // Every check below runs AS THE CALLER, through the same choke point as the rest of the app —
  // service_role is used only to create the login and to write the audit row.
  const caller = createClient(SUPABASE_URL, apikey, {
    global: { headers: { Authorization: authHeader } },
    auth: { persistSession: false, autoRefreshToken: false },
  });

  const { data: who, error: whoErr } = await caller.auth.getUser();
  if (whoErr || !who?.user) {
    await log({ ip, ok: false, outcome: 'bad_jwt' });
    return json(401, { error: 'That sign-in could not be verified. Sign in again.' });
  }
  const actor = who.user.id;

  // ---- 2 · admin.team, via fn_has_permission — the choke point, not a reimplementation -----------
  const { data: isAdmin, error: permErr } = await caller.rpc('fn_has_permission', { p_key: 'admin.team' });
  if (permErr || isAdmin !== true) {
    await log({ actor, ip, ok: false, outcome: 'not_admin' });
    return json(403, { error: 'Only somebody who manages the team can add a person.' });
  }

  // ---- 3 · rate limit, per admin and per IP, over a window from app_setting (0029/0030) ----------
  const setNum = async (key: string, dflt: number) => {
    const { data } = await service.from('app_setting').select('value').eq('key', key).maybeSingle();
    const n = Number(data?.value); return Number.isFinite(n) ? n : dflt;
  };
  const win = await setNum('team_create_window_minutes', 60);
  const since = new Date(Date.now() - win * 60_000).toISOString();
  const actorCount = await service.from('team_create_attempt')
    .select('id', { count: 'exact', head: true }).eq('actor', actor).gte('at', since);
  const ipCount = ip
    ? await service.from('team_create_attempt').select('id', { count: 'exact', head: true }).eq('ip', ip).gte('at', since)
    : { count: 0 };
  if ((actorCount.count ?? 0) >= await setNum('team_create_actor_max', 10)
      || (ipCount.count ?? 0) >= await setNum('team_create_ip_max', 20)) {
    await log({ actor, ip, ok: false, outcome: 'rate_limited' });
    return json(429, { error: 'Too many new accounts in a short time. Wait a while and try again.' });
  }

  // ---- 4 · the body. Email, name, password, and a permissions object of KNOWN keys only ----------
  let body: Record<string, unknown>;
  try { body = await req.json(); } catch { body = {}; }
  const email = String(body.email ?? '').trim().toLowerCase();
  const name = String(body.name ?? '').trim();
  const password = String(body.password ?? '');
  const permsIn = (body.permissions && typeof body.permissions === 'object') ? body.permissions as Record<string, unknown> : {};
  const perms: Record<string, boolean> = {};
  for (const [k, v] of Object.entries(permsIn)) {
    if (KNOWN_KEYS.has(k) && v === true) perms[k] = true;
  }
  const okEmail = /^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(email);
  if (!okEmail || name.length < 1 || password.length < 8) {
    await log({ actor, email: email || null, ip, ok: false, outcome: 'bad_input' });
    return json(400, { error: 'Need a valid email, a name, and a password of at least 8 characters.' });
  }

  // ---- 5 · create the login (service_role, email-confirmed, no invite mail) ----------------------
  const created = await service.auth.admin.createUser({ email, password, email_confirm: true });
  if (created.error || !created.data?.user) {
    const dup = (created.error?.message ?? '').toLowerCase().includes('already');
    await log({ actor, email, ip, ok: false, outcome: dup ? 'email_exists' : 'create_failed' });
    return json(dup ? 409 : 400, { error: dup ? 'An account with that email already exists.' : 'The account could not be created.' });
  }
  const newId = created.data.user.id;

  // ---- 6 · grant permissions AS THE CALLER, through fn_team_add (the one writer) ------------------
  //      If this fails, the login just made is deleted, so a failed grant never leaves an orphan
  //      account that can sign in with no operator row.
  const grant = await caller.rpc('fn_team_add', { p_user_id: newId, p_display_name: name, p_permissions: perms });
  if (grant.error) {
    await service.auth.admin.deleteUser(newId);
    await log({ actor, email, ip, ok: false, outcome: 'grant_failed' });
    return json(500, { error: 'The account was rolled back — its permissions could not be written. Nothing was created.' });
  }

  await log({ actor, email, ip, ok: true, outcome: 'ok' });
  return json(200, { ok: true, user_id: newId, email });
});
