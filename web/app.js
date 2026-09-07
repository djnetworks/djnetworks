// app.js — the shared bits every screen needs: the client, the session gate, and small helpers.
//
// Business logic does NOT live here. The client never decides whether a unit is available, what a
// line costs, or what a customer owes — it asks the database and renders the answer. See the
// djn-architecture skill, "Where logic goes".

import { SUPABASE_URL, SUPABASE_PUBLISHABLE_KEY } from './config.js';
import * as store from './db.js';

// The client is VENDORED at web/vendor/supabase.js and loaded by boot.js as a classic script.
//
// It used to be imported from jsdelivr, and that was a permanent failure point: with the CDN
// unreachable the browser discarded this entire module graph in silence and every screen was a
// blank grey rectangle, and even when it worked it cost 3.1s of blank on a cold cache. A godown is
// where both of those happen. There is no CDN in this app now — nothing here needs the public
// internet except Supabase itself.
if (!window.supabase?.createClient) {
  throw new Error('vendor/supabase.js did not load — boot.js reports this to the operator.');
}
export const sb = window.supabase.createClient(SUPABASE_URL, SUPABASE_PUBLISHABLE_KEY, {
  auth: { persistSession: true, autoRefreshToken: true },
});
export { store };

// ---------------------------------------------------------------------------
// Tiny DOM helpers. No framework, on purpose: the operator has to be able to
// open these files and read them.
// ---------------------------------------------------------------------------

export const $ = (sel, root = document) => root.querySelector(sel);
export const $$ = (sel, root = document) => Array.from(root.querySelectorAll(sel));

/** Escape anything before it goes near innerHTML. Product names come from a Google Sheet import. */
export function esc(v) {
  if (v === null || v === undefined) return '';
  return String(v).replace(/[&<>"']/g, c =>
    ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
}

export function money(v) {
  if (v === null || v === undefined || v === '') return '—';
  return '₹' + Number(v).toLocaleString('en-IN', { minimumFractionDigits: 2, maximumFractionDigits: 2 });
}

const MONTHS = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

/**
 * A `date` column arrives from PostgREST as '2026-09-07'. Rendered raw it is an ISO string, which
 * is not how anybody reads a date off a screen in a hurry. Parsed by hand rather than through
 * `new Date(s)`, because that treats a bare date as UTC and can render the previous day in IST.
 */
export function fmtDate(v) {
  if (!v) return '—';
  const m = /^(\d{4})-(\d{2})-(\d{2})/.exec(String(v));
  if (!m) return String(v);
  return `${Number(m[3])} ${MONTHS[Number(m[2]) - 1]} ${m[1]}`;
}

/** Today as the phone sees it. Never `new Date().toISOString()` — that is UTC, and before 05:30
 *  IST it names yesterday. A movement date is a calendar day (CLAUDE.md, conventions). */
export function todayLocal() {
  const d = new Date();
  const p = n => String(n).padStart(2, '0');
  return `${d.getFullYear()}-${p(d.getMonth() + 1)}-${p(d.getDate())}`;
}

let toastTimer;
export function toast(message, kind = 'ok') {
  const t = $('#toast');
  if (!t) return;
  t.textContent = message;
  t.className = `toast toast--${kind} toast--show`;
  // A failed save must interrupt a screen reader, not queue politely behind whatever else is
  // being read. Anything else can wait its turn.
  t.setAttribute('role', kind === 'error' ? 'alert' : 'status');
  t.setAttribute('aria-live', kind === 'error' ? 'assertive' : 'polite');
  clearTimeout(toastTimer);
  // Errors stay put until dismissed or replaced. A message about a failed write that
  // vanishes after three seconds is worse than no message.
  if (kind !== 'error') toastTimer = setTimeout(() => t.classList.remove('toast--show'), 3500);
}
export function dismissToast() { $('#toast')?.classList.remove('toast--show'); }

/** Errors never time out, so without this an error toast sits over the bottom of the screen for
 *  the rest of the session — and at 375px that is where the primary button is. */
document.addEventListener('click', e => {
  if (e.target.closest?.('#toast')) dismissToast();
});

/**
 * Turn a transport failure into a sentence. supabase-js surfaces a dead connection as
 * "Failed to fetch" / "Load failed", which tells the operator nothing and looks like a bug in
 * the system rather than a bar of signal. Returns null when the error is something else.
 */
export function networkMessage(e) {
  const m = (e?.message || String(e ?? '')).toLowerCase();
  if (navigator.onLine === false) return 'This phone has no internet. Check the signal and try again.';
  if (m.includes('failed to fetch') || m.includes('load failed') || m.includes('networkerror')
      || m.includes('fetch failed') || m.includes('timeout')) {
    return 'Could not reach the server. Check the signal and try again — nothing was saved.';
  }
  return null;
}

/**
 * Render a block-level state (loading / empty / error) into a container.
 * Every screen uses this, so the three states look the same everywhere and none of them
 * can be forgotten — an empty grid with no explanation is the failure mode this exists to stop.
 */
export function stateBlock({ icon = '', title, body = '', actionLabel = '', actionId = '' }) {
  return `<div class="state">
    <div class="state__icon" aria-hidden="true">${esc(icon)}</div>
    <h2 class="state__title">${esc(title)}</h2>
    ${body ? `<p class="state__body">${esc(body)}</p>` : ''}
    ${actionLabel ? `<button class="btn btn--primary" id="${esc(actionId)}">${esc(actionLabel)}</button>` : ''}
  </div>`;
}

/**
 * A failed read must never look like an empty list. The catalogue is legitimately empty on day
 * one, so "no rows" and "the query died" would otherwise be the same picture — and the operator
 * would conclude his gear had vanished, or worse, that it had never saved.
 */
export function errorBlock(err, retryId = 'retry') {
  const raw = err?.message || String(err);
  const msg = networkMessage(err)
    ?? (err?.code === '42501' || raw.includes('row-level security')
        ? 'The session has expired. Sign in again and this will load.'
        : raw);
  return `<div class="state state--error">
    <div class="state__icon" aria-hidden="true">!</div>
    <h2 class="state__title">Could not load</h2>
    <p class="state__body">${esc(msg)}</p>
    <button class="btn" id="${esc(retryId)}" type="button">Try again</button>
  </div>`;
}

// ---------------------------------------------------------------------------
// Sheets (the modal used by the product editor and by bulk intake).
//
// Both screens grew their own copy of open/close, and they had drifted: products handled Escape
// and leaked a listener every time the sheet was closed some other way; bulk intake had no
// Escape at all. Neither moved focus, so a keyboard or screen-reader user opened a dialog and
// was left standing outside it. One implementation, so they cannot drift again.
// ---------------------------------------------------------------------------

/**
 * @param html      the .sheet markup, already built by the caller
 * @param onClose   optional, runs after the sheet is torn down
 * @returns {{close: function}}
 */
export function openSheet(html, onClose) {
  const host = $('#sheet-host');
  const opener = document.activeElement;
  host.innerHTML = html;

  const panel = $('.sheet__panel', host);
  const focusables = () => $$(
    'button, [href], input:not([type=hidden]), select, textarea, [tabindex]:not([tabindex="-1"])',
    panel).filter(el => !el.disabled && el.offsetParent !== null);

  const onKey = (e) => {
    if (e.key === 'Escape') { e.preventDefault(); close(); return; }
    if (e.key !== 'Tab') return;
    // Without a trap, Tab walks straight out of an aria-modal dialog and into the page behind it.
    const f = focusables();
    if (!f.length) return;
    const first = f[0], last = f[f.length - 1];
    if (e.shiftKey && document.activeElement === first) { e.preventDefault(); last.focus(); }
    else if (!e.shiftKey && document.activeElement === last) { e.preventDefault(); first.focus(); }
  };

  let closed = false;
  const close = () => {
    if (closed) return;
    closed = true;
    document.removeEventListener('keydown', onKey);
    host.innerHTML = '';
    // Put focus back where it came from, or it lands on <body> and the next Tab restarts the
    // page from the top bar.
    if (opener && document.contains(opener)) opener.focus();
    onClose?.();
  };

  document.addEventListener('keydown', onKey);
  $('.sheet', host).addEventListener('mousedown', e => { if (e.target.classList.contains('sheet')) close(); });
  $$('[data-sheet-close]', host).forEach(b => b.addEventListener('click', close));

  // The first field a person can actually change, not the close button: the point of opening the
  // sheet is to type in it. Readonly and disabled fields are skipped — on an existing order the
  // first input is the order number, which is readonly, so the cursor landed somewhere that
  // ignores every keystroke and the next Tab had to walk past it again.
  const firstField = $$('input:not([type=hidden]), select, textarea', panel)
    .find(el => !el.readOnly && !el.disabled && el.offsetParent !== null);
  (firstField ?? panel).focus?.();

  return { close };
}

/** Move focus to a field the operator has to fix, and bring it into view. A validation message
 *  in a toast at the bottom of a scrolling sheet does not say WHICH field is wrong. */
export function focusField(sel) {
  const el = $(sel);
  if (!el) return;
  el.setAttribute('aria-invalid', 'true');
  el.addEventListener('input', () => el.removeAttribute('aria-invalid'), { once: true });
  el.scrollIntoView({ block: 'center' });
  el.focus();
}

// ---------------------------------------------------------------------------
// Session gate.
//
// RLS gives `authenticated` everything and `anon` nothing, so an unauthenticated page can read
// no rows at all — it does not error, it silently returns []. That is the trap this guards:
// without a session check, every screen would render a convincing empty state and the operator
// would think the catalogue had been wiped. So the gate runs BEFORE any query.
// ---------------------------------------------------------------------------

/**
 * Show the sign-in panel and resolve once signed in. Renders into #gate, hides #app.
 * One operator, one account. No sign-up, no roles, no invitations, no reset flow —
 * a password reset for a single user is a dashboard job, not a screen.
 */
export async function requireSession(onReady) {
  const gate = $('#gate');
  const app = $('#app');

  const paint = async (session) => {
    if (session) {
      gate.hidden = true;
      gate.innerHTML = '';
      app.hidden = false;
      $('#who').textContent = session.user.email ?? '';
      $('#signout').hidden = false;
      try {
        await onReady(session);
      } catch (err) {
        // Without this the screen keeps its skeleton shimmering forever and the failure only
        // exists in a console nobody has open. A skeleton that never resolves is the worst of
        // the loading states: it looks like the system is still trying.
        app.innerHTML = errorBlock(err, 'boot-retry');
        $('#boot-retry')?.addEventListener('click', () => location.reload());
      }
    } else {
      // Signed out: the screens show nothing rather than erroring or showing a
      // misleading empty catalogue.
      app.hidden = true;
      app.innerHTML = '';
      // A session can expire while a sheet is open. Left alone the sheet floats over the
      // sign-in form with the operator's half-typed product still in it, and Save would fail
      // with a row-level-security error he did not cause.
      const host = $('#sheet-host');
      if (host) host.innerHTML = '';
      dismissToast();
      $('#who').textContent = '';
      $('#signout').hidden = true;
      gate.hidden = false;
      renderSignIn(gate);
    }
  };

  // supabase-js fires onAuthStateChange with INITIAL_SESSION as well as on real changes, so
  // without this guard onReady would run twice on every load — two sets of listeners, two fetches.
  let lastUser = undefined;
  const paintOnce = async (session) => {
    const id = session?.user?.id ?? null;
    if (id === lastUser) return;
    lastUser = id;
    await paint(session);
  };

  // getSession() goes to the network when a stored refresh token needs renewing, so on a bad
  // link this is where the page hangs. Failing here has to show the sign-in form, not nothing:
  // a blank screen is indistinguishable from a broken system.
  let session = null;
  try {
    ({ data: { session } } = await sb.auth.getSession());
  } catch (err) {
    session = null;
  }
  await paintOnce(session);

  sb.auth.onAuthStateChange((_event, s) => { paintOnce(s); });

  $('#signout')?.addEventListener('click', async () => {
    try {
      await sb.auth.signOut();
      toast('Signed out.');
    } catch (err) {
      toast(networkMessage(err) ?? 'Could not sign out. Try again.', 'error');
    }
  });
}

function renderSignIn(gate) {
  gate.innerHTML = `
    <form class="signin" id="signin-form" autocomplete="on">
      <h1 class="signin__title">DJ Network's</h1>
      <p class="signin__sub">Rental system. Sign in to continue.</p>
      <label class="field">
        <span class="field__label">Email</span>
        <input class="field__input" type="email" id="email" name="email" required autocomplete="username"
               inputmode="email" autocapitalize="none" spellcheck="false" enterkeyhint="next">
      </label>
      <label class="field">
        <span class="field__label">Password</span>
        <input class="field__input" type="password" id="password" name="password" required
               autocomplete="current-password" enterkeyhint="go">
      </label>
      <button class="btn btn--primary btn--block" type="submit" id="signin-btn">Sign in</button>
      <p class="signin__err" id="signin-err" role="alert" hidden></p>
    </form>`;

  const form = $('#signin-form', gate);
  form.addEventListener('submit', async (e) => {
    e.preventDefault();
    const btn = $('#signin-btn', gate);
    const err = $('#signin-err', gate);
    err.hidden = true;
    btn.disabled = true;
    btn.textContent = 'Signing in…';
    let error = null;
    try {
      ({ error } = await sb.auth.signInWithPassword({
        email: $('#email', gate).value.trim(),
        password: $('#password', gate).value,
      }));
    } catch (thrown) {
      error = thrown;
    }
    if (error) {
      // Deliberately does not distinguish "no such account" from "wrong password". It DOES
      // distinguish a dead connection: measured with the Supabase host blocked, this box read
      // "Failed to fetch", which reads as a broken system rather than a missing bar of signal —
      // and standing at a van, that is the difference between waiting and giving up.
      err.hidden = false;                                  // unhidden before the text, so the
      err.textContent = networkMessage(error)               // role="alert" actually announces
        ?? (error.message || 'Sign in failed. Try again.');
      btn.disabled = false;
      btn.textContent = 'Sign in';
      $('#password', gate).focus();
    }
    // On success onAuthStateChange repaints; no need to touch the button.
  });
}

// ---------------------------------------------------------------------------
// Page chrome shared by every screen.
// ---------------------------------------------------------------------------

export function chrome(active) {
  const tabs = [
    ['index.html', 'Home'],
    ['orders.html', 'Orders'],
    ['dispatch.html', 'Dispatch'],
    ['return.html', 'Return'],
    ['products.html', 'Products'],
    ['units.html', 'Pieces'],
    ['customers.html', 'Customers'],
    ['ledger.html', 'Ledger'],
    ['analysis.html', 'Analysis'],
  ];
  return `
  <header class="topbar">
    <a class="topbar__brand" href="index.html">DJ Network's</a>
    <nav class="topbar__nav" aria-label="Screens">
      ${tabs.map(([href, label]) =>
        // aria-current, not just a colour: the active tab has to say where he is to a screen
        // reader as well as to an eye.
        `<a class="topbar__tab${href === active ? ' is-active' : ''}" href="${href}"${
          href === active ? ' aria-current="page"' : ''}>${label}</a>`).join('')}
    </nav>
    <span class="conn" id="conn" hidden></span>
    <span class="topbar__who" id="who"></span>
    <button class="btn btn--ghost" id="signout" hidden>Sign out</button>
  </header>
  <div class="toast" id="toast" role="status" aria-live="polite"></div>`;
}

// The tab strip scrolls sideways on a phone, so the tab you are on can start off screen.
// Called by every screen right after chrome() is written into the DOM.
export function revealActiveTab() {
  const el = $('.topbar__tab.is-active');
  el?.scrollIntoView({ block: 'nearest', inline: 'center' });
}

// ---------------------------------------------------------------------------
// Connection and the write queue.
//
// The indicator is never decoration. Two facts have to be visible at all times on a screen used
// where the signal dies: whether this phone can currently reach the database, and how many writes
// it is still holding. An operator who cannot see the second one will close the tab on the way out
// of the godown with six dispatches in it.
// ---------------------------------------------------------------------------

let queueHandlers = {};
export function registerQueueHandlers(h) { queueHandlers = { ...queueHandlers, ...h }; }

export function paintConn(pending) {
  const el = $('#conn');
  if (!el) return;
  const online = navigator.onLine;
  if (online && !pending) { el.hidden = true; return; }
  el.hidden = false;
  el.className = 'conn ' + (online ? 'conn--sync' : 'conn--off');
  el.textContent = online
    ? `${pending} to send`
    : (pending ? `Offline · ${pending} waiting` : 'Offline');
  el.title = online
    ? 'Connected. Queued writes are being sent.'
    : 'No connection. Anything you record is kept on this phone and sent when the signal returns.';
}

/** Replay the queue. Safe to call often; does nothing when there is nothing to send. */
export async function syncNow(quiet = true) {
  if (!navigator.onLine) return;
  const n = await store.pendingCount();
  if (!n) { paintConn(0); return; }
  const res = await store.flush(queueHandlers);
  paintConn(await store.pendingCount());
  if (res.failed) {
    toast(`${res.done} of ${res.total} sent. Stopped at “${res.failed.label ?? res.failed.kind}”: `
        + `${res.failed.last_error}`, 'error');
  } else if (res.done && !quiet) {
    toast(`${res.done} queued ${res.done === 1 ? 'change' : 'changes'} sent.`);
  }
}

export async function initOffline() {
  store.onQueueChange(paintConn);
  paintConn(await store.pendingCount());
  window.addEventListener('online', () => { paintConn(0); syncNow(false); });
  window.addEventListener('offline', async () => paintConn(await store.pendingCount()));
  if ('serviceWorker' in navigator) {
    try { await navigator.serviceWorker.register('sw.js'); } catch { /* shell stays online-only */ }
  }
  await syncNow(true);
}
