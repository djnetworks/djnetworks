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

/**
 * A product photo's public URL.
 *
 * `product.image_url` holds a storage PATH, not a link — 0006 keeps it pointed at the primary
 * row in `product_image`. An import can also put a full URL there, so both shapes are accepted.
 * Shared rather than copied because two screens now show the same photograph and a bucket rename
 * must not have to be found in two files.
 */
export const publicUrl = path => !path ? null
  : path.startsWith('http') ? path
  : sb.storage.from('product-images').getPublicUrl(path).data.publicUrl;

/**
 * How a product is tracked, in words the operator uses.
 *
 * `unit`, `pool` and `consumable` are schema words — they are correct in the database and they
 * mean nothing on a screen. The design bible's language rule is the reason this exists: "numbers
 * are familiar; software words are not". A cable is counted stock; a roll of gaffer tape is used
 * up and never comes back; a speaker is a numbered piece.
 *
 * One function, used by every screen that shows the badge, so the three screens cannot drift into
 * three vocabularies for the same three values.
 */
export const trackLabel = m => ({
  unit: 'Numbered pieces',
  pool: 'Counted stock',
  consumable: 'Used up, never comes back',
}[m] ?? m);

// ---------------------------------------------------------------------------
// THE CUSTOMER PICKER.
//
// Both screens that choose a customer used a plain <select> listing every customer. That is fine at
// two and unusable at two hundred, and it fails for the reason that actually matters here: HE WILL
// HAVE THE PHONE NUMBER, NOT THE SPELLING. Names transliterate inconsistently — Priya/Priyaa,
// Rakesh/Rakhesh — and he will not remember which way it was typed the day the customer first rang.
// A number is a number.
//
// So: type-to-filter over name, business name AND both phone numbers, matched on DIGITS ONLY for
// the phone part, so "98250" finds "98250 44556" and a stored "+91 98250-44556" alike.
//
// Renders into `host`, calls onPick(customer|null). `customers` needs id, name, business_name and
// whichever of whatsapp/alt_phone were selected.
// ---------------------------------------------------------------------------
export function customerPicker(host, customers, selected, onPick, opts = {}) {
  const { placeholder = 'Search name or phone number…', required = false, id = 'cp' } = opts;
  let open = false, q = '';

  const digits = v => String(v ?? '').replace(/\D/g, '');
  const label = c => c.business_name ? `${c.business_name} — ${c.name}` : c.name;
  const phones = c => [c.whatsapp, c.alt_phone].filter(Boolean).join(' · ');

  const matches = () => {
    const needle = q.trim().toLowerCase();
    if (!needle) return customers.slice(0, 30);
    const nd = digits(needle);
    return customers.filter(c =>
      [c.name, c.business_name].some(v => (v || '').toLowerCase().includes(needle))
      || (nd.length >= 3 && [c.whatsapp, c.alt_phone].some(v => digits(v).includes(nd)))
    ).slice(0, 30);
  };

  function paint() {
    const rows = matches();
    host.innerHTML = `
      <div class="field" style="margin-bottom:0;position:relative">
        <label class="field__label" for="${id}-q">Customer${required ? ' *' : ''}</label>
        ${selected ? `<div class="row" style="gap:8px;align-items:center">
            <span class="badge badge--unit" style="font-size:14px;padding:6px 10px">${esc(label(selected))}</span>
            <span class="field__hint" style="margin:0">${esc(phones(selected))}</span>
            <button class="btn btn--sm" id="${id}-clear" type="button">Change</button>
          </div>` : ''}
        <input class="field__input" id="${id}-q" type="search" placeholder="${esc(placeholder)}"
               autocapitalize="none" spellcheck="false" inputmode="text"
               value="${esc(q)}" ${selected ? 'hidden' : ''}>
        ${!selected ? `<div class="list" style="margin-top:8px;max-height:280px;overflow:auto">
          ${rows.length ? rows.map(c => `
            <button class="item ${id}-opt" data-id="${esc(c.id)}" type="button">
              <span class="item__main">
                <span class="item__title">${esc(label(c))}</span>
                <span class="item__meta">${esc(phones(c)) || 'no phone number'}${c.city ? ' · ' + esc(c.city) : ''}</span>
              </span></button>`).join('')
          : `<p class="field__hint">No customer matches that.
               ${digits(q).length >= 3 ? 'Try fewer digits, or ' : ''}<a href="customers.html">add them</a> first.</p>`}
        </div>` : ''}
      </div>`;
    $(`#${id}-q`, host)?.addEventListener('input', e => { q = e.target.value; paint(); });
    $(`#${id}-clear`, host)?.addEventListener('click', () => { selected = null; q = ''; paint(); onPick(null); });
    $$(`.${id}-opt`, host).forEach(b => b.addEventListener('click', () => {
      selected = customers.find(c => c.id === b.dataset.id) ?? null;
      q = ''; paint(); onPick(selected);
    }));
  }

  paint();
  return { get value() { return selected?.id ?? ''; }, get customer() { return selected; } };
}

// ---------------------------------------------------------------------------
// WHATSAPP.
//
// The source briefing: "Each order needs an ID that goes into every WhatsApp message about it.
// WhatsApp is the actual communication channel with customers and staff." Until now nothing
// generated those messages, so the operator wrote them by hand AND looked up the number — work
// this app added rather than saved, which is the worst way for a requirement to go missing.
//
// A share button OPENS A PREFILLED DRAFT. It never sends. wa.me hands the text to WhatsApp and
// stops; the send button belongs to the person, and on a message about somebody's money that is
// not a detail.
// ---------------------------------------------------------------------------

/** wa.me wants digits only, with a country code. Indian numbers are stored ten-digit. */
export function waNumber(phone) {
  const d = String(phone ?? '').replace(/\D/g, '');
  if (!d) return null;
  if (d.length === 10) return '91' + d;
  if (d.length === 12 && d.startsWith('91')) return d;
  if (d.length === 11 && d.startsWith('0')) return '91' + d.slice(1);
  return d;                                  // already carries a country code, or is unusual
}

export function waLink(phone, text) {
  const n = waNumber(phone);
  const t = encodeURIComponent(text);
  // No number: still useful — WhatsApp opens the share sheet and he picks the chat himself.
  return n ? `https://wa.me/${n}?text=${t}` : `https://wa.me/?text=${t}`;
}

const rupees = v => '\u20B9' + Number(v || 0).toLocaleString('en-IN', { maximumFractionDigits: 0 });
const dash = s => (s == null || s === '' ? '' : String(s));

/**
 * The four messages, plus the overdue chase. Each returns plain text, and each one carries the
 * ORDER NUMBER, because that is the only identifier the operator and the customer share.
 *
 * `kind` is one of: confirmed · on_its_way · came_back_short · payment_pending · overdue.
 */
export function waMessage(kind, ctx = {}) {
  const o = ctx.order ?? {};
  const who = ctx.customerName || o.customer?.business_name || o.customer?.name || '';
  const hi = who ? `Namaste ${who},` : 'Namaste,';
  // fmtDate returns an em dash for nothing, which is right on a screen and wrong in a sentence —
  // the account-level reminder read "outstanding on your account (—)". Nothing means nothing here.
  const when = o.out_date ? fmtDate(o.out_date) : '';
  const job = [when, o.venue_name].filter(Boolean).join(' · ');
  // Every message carries something the customer can quote back. Usually one order number; for an
  // account-level reminder, the orders the balance is actually made of.
  const refs = ctx.orderRefs?.length ? ctx.orderRefs : (o.order_no ? [o.order_no] : []);
  const ref = refs.length ? `\n\nRef: ${refs.join(', ')}` : '';
  const sign = '\n\n— DJ Network\u2019s';

  switch (kind) {
    case 'confirmed': {
      const lines = (ctx.lines ?? []).map(l => `\u2022 ${l.qty} \u00D7 ${l.name}`).join('\n');
      const dep = Number(o.deposit_amount || 0) > 0
        ? `\nDeposit: ${rupees(o.deposit_amount)}` : '';
      return `${hi}\n\nYour booking is confirmed.\n\n`
        + `Date: ${fmtDate(o.out_date)} to ${fmtDate(o.expected_return_date)}`
        + (o.days ? ` (${o.days} day${o.days === 1 ? '' : 's'})` : '')
        + (o.venue_name ? `\nVenue: ${o.venue_name}` : '')
        + (lines ? `\n\n${lines}` : '')
        + dep + ref + sign;
    }
    case 'on_its_way': {
      const carrier = [dash(ctx.carrierName), dash(ctx.carrierPhone)].filter(Boolean).join(' \u2013 ');
      const veh = ctx.vehicle ? `\nVehicle: ${ctx.vehicle}` : '';
      return `${hi}\n\nYour equipment is on its way`
        + (job ? ` for ${job}` : '') + '.\n\n'
        + (ctx.count ? `${ctx.count} item${ctx.count === 1 ? '' : 's'} sent.\n` : '')
        + (carrier ? `Coming with: ${carrier}${veh}\n` : '')
        + `\nPlease check everything on arrival and tell us straight away if anything is missing.`
        + ref + sign;
    }
    case 'came_back_short': {
      const items = (ctx.missing ?? []).map(m => `\u2022 ${m}`).join('\n');
      return `${hi}\n\nThe gear from ${job || 'your job'} has come back, but these are still with you:\n\n`
        + `${items}\n\nCould you check and let us know? Nothing is charged for yet \u2014 we would `
        + `rather find it.` + ref + sign;
    }
    case 'payment_pending': {
      // RULE 6, twice. Deposit is the customer's own money being held and is NEVER added to what
      // is owed, and nothing is chased when the balance is zero or in credit — 0018 made the
      // credit case reachable, and dunning somebody who has overpaid is how a regular is lost.
      const owed = Number(ctx.receivable || 0);
      const held = Number(ctx.depositHeld || 0);
      return `${hi}\n\nA gentle reminder \u2014 ${rupees(owed)} is outstanding on your account`
        + (job ? ` (${job})` : '') + '.\n\n'
        + (held > 0
            ? `This is separate from the ${rupees(held)} deposit we are holding, which comes back to you.\n\n`
            : '')
        + `Please let us know when it suits you to settle.` + ref + sign;
    }
    case 'overdue': {
      const items = (ctx.missing ?? []).map(m => `\u2022 ${m}`).join('\n');
      const d = Number(ctx.daysLate || 0);
      return `${hi}\n\nJust a reminder about the gear from ${job || 'your job'} \u2014 it was due back on `
        + `${fmtDate(o.expected_return_date)}`
        + (d > 0 ? `, ${d} day${d === 1 ? '' : 's'} ago` : '') + '.\n\n'
        + (items ? `Still with you:\n${items}\n\n` : '')
        + `When can we collect?` + ref + sign;
    }
    default:
      return `${hi}${ref}${sign}`;
  }
}

/** Can a payment chaser honestly be offered? Rule 6: never at zero, never in credit. */
export const canChasePayment = receivable => Number(receivable || 0) > 0;

/**
 * HOW A JOB IS NAMED, everywhere it appears.
 *
 * His identity for a job is a DATE, a PERSON and a VENUE. "DJN-2609-0004" is not how anybody
 * holds a job in their head — "the Patel job at the stadium on the 28th" is — and a list of order
 * numbers is a list he has to decode one row at a time before he can decide anything.
 *
 * The number is NOT dropped, and that is deliberate against the first instinct: it is the only
 * identifier he and the customer share. She quotes it back on WhatsApp, the portal prints it, and
 * every message this app generates has to carry something she can quote. So it is demoted to the
 * reference line rather than deleted from the screen.
 *
 * Returns { title, meta }. Both are already escaped and go straight into innerHTML.
 */
export function jobLine(o, { showDays = true } = {}) {
  const who = o?.customer?.business_name || o?.customer?.name
           || o?.business_name || o?.customer_name || '';
  const when = fmtDate(o?.out_date);
  const title = [when, who, o?.venue_name].filter(Boolean).map(esc).join(' · ');
  const span = o?.out_date && o?.expected_return_date
    ? `${fmtDate(o.out_date)} → ${fmtDate(o.expected_return_date)}` : '';
  const days = showDays && o?.days ? `${o.days} day${o.days === 1 ? '' : 's'}` : '';
  const meta = [esc(o?.order_no ?? ''), esc(span), esc(days)].filter(Boolean).join(' · ');
  return { title: title || esc(o?.order_no ?? 'a job'), meta };
}

/**
 * What a ledger entry IS, in the operator's words.
 *
 * The ledger list rendered `e.type.replace(/_/g, ' ')`, so chachu read `rental` and `deposit in`
 * in the list while the form directly above it offered "Payment received" and "Deposit taken" and
 * the customer, on the same entry, read "Equipment hire". Three vocabularies for one row, on the
 * screen that is about money — the same drift fulfilLabel exists to kill.
 *
 * portal.html keeps its OWN map on purpose and must not be pointed at this one. It is not a
 * translation of this, it is a different reading of the same fact: `deposit_in` is "Deposit taken"
 * to the person taking it and "Deposit received" to the person handing it over, and `write_off`
 * must never reach a customer as "Written off".
 */
export const entryLabel = t => ({
  rental:          'Equipment hire',
  transport:       'Transport',
  labour:          'Labour',
  misc:            'Other charge',
  damage:          'Damage charge',
  payment:         'Payment received',
  deposit_in:      'Deposit taken',
  deposit_out:     'Deposit returned',
  deposit_forfeit: 'Deposit kept against damage',
  discount:        'Discount given',
  write_off:       'Written off',
  reversal:        'Charge cancelled',
}[t] ?? String(t ?? '').replace(/_/g, ' '));

/**
 * v_order_fulfilment.fulfilment_state, in words rather than in schema.
 *
 * `part_dispatched` is a column value; "part sent" is what somebody says. Shared so the filter
 * dropdown and the badge on the row it filters cannot say two different things about the same
 * order — which they did until this existed: the dropdown offered "Part sent" and the row it
 * returned was labelled "part dispatched".
 */
export const fulfilLabel = s => ({
  nothing_dispatched: 'nothing sent yet',
  part_dispatched:    'part sent',
  fully_out:          'all sent, none back',
  part_returned:      'part back',
  all_returned:       'all back',
}[s] ?? String(s ?? '').replace(/_/g, ' '));

/** The same three, short enough for a badge in a table cell. */
export const trackBadge = m => ({
  unit: 'numbered', pool: 'counted', consumable: 'used up',
}[m] ?? m);

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
      <h1 class="signin__title">${wordmark({ large: true })}</h1>
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
      <p class="builtby">Built by <strong>EKUM</strong></p>
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
// The wordmark.
//
// DJ Network's mark is TYPOGRAPHIC. There is no logo file in this app and there is not going to
// be one until somebody draws a clean shield: the flyer artwork carries a visible AI watermark
// and spells the trade "EVENTS & RENTAL EQUIPE". Shipping that on the sign-in screen would put a
// misspelling in front of the only person who uses this system, every morning.
//
// The apostrophe is the typographic one (’). It appears in the mark only — page titles and
// prose keep the plain quote, because those get searched, copied and pasted.
// ---------------------------------------------------------------------------
export function wordmark({ large = false, invert = false, href = null } = {}) {
  const cls = `wordmark${large ? ' wordmark--lg' : ''}${invert ? ' wordmark--invert' : ''}`;
  // The space between DJ and Network's is a REAL space, not the flex gap. With the gap doing the
  // work the name read "DJNetwork's" to a screen reader and to anything that copied the text —
  // the two words were separate text nodes with nothing between them.
  const inner = '<span class="wordmark__dot" aria-hidden="true"></span>'
    + '<span class="wordmark__name"><span class="wordmark__lead">DJ</span> '
    + '<span class="wordmark__rest">Network\u2019s</span></span>';
  return href
    ? `<a class="${cls}" href="${href}">${inner}</a>`
    : `<span class="${cls}">${inner}</span>`;
}

// ---------------------------------------------------------------------------
// Page chrome shared by every screen.
// ---------------------------------------------------------------------------

export function chrome(active) {
  const tabs = [
    ['index.html', 'Today'],
    // The phone-call screen sits second, right after Today: it is the single most common
    // interaction in a rental business and it must be reachable while a customer is talking.
    ['ask.html', 'Can I say yes'],
    ['orders.html', 'Orders'],
    ['dispatch.html', 'Send out'],
    ['return.html', 'Return'],
    ['products.html', 'Products'],
    ['units.html', 'Pieces'],
    ['customers.html', 'Customers'],
    ['ledger.html', 'Ledger'],
    ['analysis.html', 'Numbers'],
  ];
  return `
  <header class="topbar">
    <span class="topbar__brand">${wordmark({ href: 'index.html' })}</span>
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
