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
// BROWSE-FIRST LISTS.
//
// Every list screen used to show NOTHING until you searched or picked a name from a dropdown. That
// assumes you already know what you are looking for, which is exactly backwards for a man who
// opens Customers to remind himself who the decorator from last month was. A screen that answers
// only questions you can already phrase is not a browsable system, it is a lookup table.
//
// So: cards arrive on load, search FILTERS them, and tapping one opens the detail. This helper is
// the one place that shape is defined, so eleven screens cannot each invent a slightly different
// row that behaves slightly differently under a thumb.
//
// It also owns tap rule 1: the card opens the detail, and anything marked `.card-action` inside it
// stops the event and does its own thing. Both halves live here so neither can be forgotten.
// ---------------------------------------------------------------------------

/**
 * @param host      element to render into
 * @param rows      array of data
 * @param render    row => { thumb?, title, sub?, ref?, right?, id }
 * @param onOpen    (row) => void — the card's own tap
 */
export function cardList(host, rows, render, onOpen) {
  host.className = 'card-list';
  host.innerHTML = rows.map((r, i) => {
    const c = render(r, i);
    return `<div class="card-row tappable" data-i="${i}" role="button" tabindex="0">
      ${c.thumb !== undefined ? `<span class="card-row__thumb">
        ${c.thumb ? `<img src="${esc(c.thumb)}" alt="" loading="lazy">` : ''}
        <span class="card-row__code">${esc(c.code ?? '')}</span></span>` : ''}
      <span class="card-row__main">
        <span class="card-row__title">${c.title}</span>
        ${c.sub ? `<span class="card-row__sub">${c.sub}</span>` : ''}
        ${c.ref ? `<button class="card-row__ref card-action" data-copy="${esc(c.ref)}"
                     type="button" title="Copy ${esc(c.ref)}">${esc(c.ref)}</button>` : ''}
      </span>
      ${c.right ? `<span class="card-row__right">${c.right}</span>` : ''}
    </div>`;
  }).join('');

  host.onclick = (e) => {
    // TAP RULE 1. An inline action is a separate control: it handles itself and the card does not
    // also fire. Without this one tap does two different things depending on the pixel.
    const action = e.target.closest('.card-action');
    if (action) {
      e.stopPropagation();
      if (action.dataset.copy) copyRef(action);
      return;
    }
    const row = e.target.closest('.card-row');
    if (row) onOpen(rows[Number(row.dataset.i)]);
  };
  host.onkeydown = (e) => {
    if (e.key !== 'Enter' && e.key !== ' ') return;
    const row = e.target.closest('.card-row');
    if (row && !e.target.closest('.card-action')) { e.preventDefault(); onOpen(rows[Number(row.dataset.i)]); }
  };
}

/** The order number's real job is being pasted into a WhatsApp message. */
async function copyRef(btn) {
  try { await navigator.clipboard.writeText(btn.dataset.copy); }
  catch { /* insecure context or refused: the number is still on screen to read */ }
  btn.classList.add('is-copied');
  setTimeout(() => btn.classList.remove('is-copied'), 1400);
}

// ---------------------------------------------------------------------------
// TAP RULE 3, the half that is not CSS.
//
// A control that writes disables itself for the duration and carries an idempotency key. The key
// is generated ONCE, here, before the work starts — not inside the retry, and not regenerated when
// the offline queue replays, because a fresh id on every attempt is precisely the duplicate that
// 0022's unique index exists to refuse.
// ---------------------------------------------------------------------------
export const newRequestId = () => (crypto.randomUUID
  ? crypto.randomUUID()
  : 'r-' + Date.now() + '-' + Math.random().toString(16).slice(2));

/** Runs `fn` with the button visibly busy and un-tappable. Returns whatever fn returns. */
export async function guardedWrite(btn, busyLabel, fn) {
  if (!btn) return fn();
  if (btn.dataset.busy === '1') return;                 // the second tap, arriving anyway
  const was = btn.textContent;
  btn.dataset.busy = '1';
  btn.classList.add('is-busy');
  btn.disabled = true;
  if (busyLabel) btn.textContent = busyLabel;
  try {
    return await fn();
  } finally {
    delete btn.dataset.busy;
    btn.classList.remove('is-busy');
    btn.disabled = false;
    if (busyLabel) btn.textContent = was;
  }
}

// ---------------------------------------------------------------------------
// PERMISSIONS, IN THE CLIENT.
//
// READ THIS BEFORE USING IT: what is below is CONVENIENCE, NOT THE BOUNDARY. Every key is enforced
// by row level security in 0021, on every table, through one function; hiding a button here only
// spares somebody the discomfort of being refused. If this file were edited in a browser's console
// to return true for everything, the database would refuse exactly as much as it does now — and
// that is the property that matters. Never move a check out of a policy and into here.
//
// The permissions come from the operator's own row, which they may read and nobody holding a
// browser session may write.
// ---------------------------------------------------------------------------

let PERMS = null;

export async function loadPermissions() {
  if (PERMS) return PERMS;
  const { data, error } = await sb.from('operator')
    .select('permissions,display_name,active').maybeSingle();
  // A failure here must not read as "you may do everything". An empty object denies every key,
  // which is the safe direction and matches what the database would do anyway.
  PERMS = (error || !data || data.active === false) ? {} : (data.permissions ?? {});
  // The name came back in the same select. whoAmI() used to fetch it again, one more serial round
  // trip in front of the first paint of every screen, for a column already sitting in `data`.
  operatorName = (error || !data) ? '' : (data.display_name ?? '');
  return PERMS;
}

/** True if this operator holds the key. Absent means denied — no wildcard, no implication. */
export const can = key => PERMS?.[key] === true;

/** The operator's name for the top bar. Filled by loadPermissions() from the same row. */
export let operatorName = '';
/** Kept for callers outside this file; it no longer costs a request. */
export async function whoAmI() { await loadPermissions(); return operatorName; }

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
  // CREATE THE HOST IF IT IS NOT THERE. Only five of twelve pages carry a #sheet-host div, and
  // this used to throw on null — silently, because the click handler had nothing to catch it. It
  // surfaced when the connection pill became a control: the pill is in the top bar of EVERY page,
  // tapping it on Today did nothing at all, and nothing was logged. Owning the host here means no
  // future screen has to remember a div in order for a sheet to open on it.
  let host = $('#sheet-host');
  if (!host) {
    host = document.createElement('div');
    host.id = 'sheet-host';
    document.body.appendChild(host);
  }
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
      // THE PERMISSION READ HAPPENS BEHIND THE WAITING STATE, NOT IN FRONT OF IT.
      //
      // This used to hide #gate and reveal an EMPTY #app first and read permissions second, so on
      // a slow link the screen was a blank cream rectangle with no text for the whole round trip —
      // measured at 1.2s with a deliberately slowed read, and a godown link is worse. Worse than
      // the blank: boot.js's nine-second net checks `!!placeholder && app.hidden`, and this line
      // had just deleted the placeholder and un-hidden #app, so the one thing that would have
      // turned an endless wait into a sentence was disarmed at exactly the moment it was needed.
      //
      // The "Starting up…" block in the HTML stays up until there is something to replace it with.
      await loadPermissions();
      // THE NAV IS PAINTED HERE, once, from the permissions this person actually holds. chrome()
      // runs at module top level, before any of them are known, and paints an empty bar of the
      // right height rather than a guess that re-flows. Granting somebody a module therefore needs
      // a page reload before it shows — see docs/structure.md, and the Team screen says so next to
      // the toggle.
      paintNav();
      initNav();
      // Already fetched by loadPermissions() — the same row, in the same select. It was read a
      // second time here, which put another serial round trip in front of the first paint.
      $('#who').textContent = operatorName || session.user.email || '';
      gate.hidden = true;
      gate.innerHTML = '';
      app.hidden = false;
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

// The modules, in fixed order. Each names the permission key that makes it real — the nav is
// re-flowed at login to what this person actually holds, and a hidden module must not leave a gap
// where it was (Maitri's lesson: fixed positions with holes read as a broken app, and the thumb
// learns the wrong place).
//
// `key: null` means every active operator sees it: Today and the enquiry screen answer questions
// rather than change anything.
const MODULES = [
  { href: 'index.html',     label: 'Today',     icon: '\u25C9', key: null },
  { href: 'ask.html',       label: 'Can I?',    icon: '\u2713', key: null },
  { href: 'orders.html',    label: 'Orders',    icon: '\u2637', key: 'orders.write' },
  { href: 'dispatch.html',  label: 'Send out',  icon: '\u2191',  key: 'sendout.write' },
  { href: 'return.html',    label: 'Return',    icon: '\u2193',  key: 'returns.write' },
  { href: 'products.html',  label: 'Products',  icon: '\u25A6', key: 'products.write' },
  { href: 'units.html',     label: 'Equipment', icon: '\u25A3', key: 'equipment.write' },
  { href: 'customers.html', label: 'Customers', icon: '\u263A', key: 'customers.write' },
  { href: 'ledger.html',    label: 'Ledger',    icon: '\u20B9',  key: 'ledger.view' },
  { href: 'analysis.html',  label: 'Numbers',   icon: '\u2211', key: 'numbers.view' },
  { href: 'team.html',      label: 'Team',      icon: '\u2687', key: 'admin.team' },
];

// How many fit across the bottom before it stops being thumb-sized. Beyond this the rest go under
// "More", which is one tap for the things done weekly and keeps the daily ones at a fixed position.
const NAV_SLOTS = 5;

/**
 * Page chrome. A slim top bar carrying identity and the connection state, and the navigation at
 * the BOTTOM where a thumb is.
 *
 * The top tab strip this replaces put ten destinations in a horizontally scrolling row: at 375px
 * five of them were off screen with no affordance saying so, and all of them were at the far end
 * of a one-handed reach. That problem is retired here rather than patched.
 *
 * WHAT IS SHOWN IS DECIDED AT LOGIN, from permissions already in memory. Granting somebody a
 * module therefore needs a page reload before it appears — documented in docs/structure.md, and
 * the Team screen says so where the toggle is.
 */
let NAV_ACTIVE = 'index.html';

export function chrome(active) {
  NAV_ACTIVE = active;
  return `
  <header class="topbar">
    <span class="topbar__brand">${wordmark({ href: 'index.html' })}</span>
    <span class="conn" id="conn" hidden></span>
    <span class="topbar__who" id="who"></span>
    <button class="btn btn--ghost btn--sm" id="signout" hidden>Sign out</button>
  </header>
  <div id="nav-host">${navMarkup()}</div>
  <div class="toast" id="toast" role="status" aria-live="polite"></div>`;
}

/** Re-render the nav in place once permissions are known. */
export function paintNav() {
  navReady();
  const host = $('#nav-host');
  if (host) host.innerHTML = navMarkup();
}

// False until loadPermissions() has answered. Until then this file does not know which modules
// this person holds, and GUESSING MOVES THE THUMB TARGET. chrome() runs at module top level, so
// the bar used to paint Today + Can I? at 195px each and then re-flow to six items at 65px: with
// a 1.2s permission read — an ordinary godown round trip — "Today" travelled 65px left and
// "Can I?" landed exactly where "Today" had been, so a tap made during the wait opened the wrong
// screen. An empty bar of the right height reserves the space without offering a target that is
// about to move. Nothing shifts when the answer arrives.
let NAV_KNOWN = false;
export function navReady() { NAV_KNOWN = true; }

function navMarkup() {
  const active = NAV_ACTIVE;
  if (!NAV_KNOWN) return `<nav class="nav nav--pending" aria-hidden="true"></nav>`;
  const mine = MODULES.filter(m => !m.key || can(m.key));
  const bar = mine.slice(0, NAV_SLOTS);
  const more = mine.slice(NAV_SLOTS);
  // The active destination is always ON the bar, even if it lives under More — otherwise the
  // screen you are looking at is not highlighted anywhere.
  //
  // THE FIVE SLOTS NEVER CHANGE. A bottom bar exists so the thumb stops reading — you learn that
  // Return is the fifth position and go there without looking. A slot that swaps identity depending
  // on which screen you happen to be on destroys the only thing the bar is for.
  //
  // Two earlier versions were both wrong and the second was subtler: the first OVERWROTE slot five
  // with the active module and dropped what was there, so "Return" vanished from the navigation
  // entirely on six of twelve screens. The fix swapped instead of overwriting, which kept every
  // module reachable — and still moved the target, which is the actual harm.
  //
  // So the bar is a pure function of the permissions, computed once. When the current screen lives
  // under More, MORE is what lights up. Nothing moves, ever.
  const activeIsUnderMore = more.some(m => m.href === active);
  const item = (m) => `<a class="nav__item${m.href === active ? ' is-active' : ''}" href="${m.href}"${
    m.href === active ? ' aria-current="page"' : ''}>
      <span class="nav__icon" aria-hidden="true">${m.icon}</span>
      <span class="nav__label">${esc(m.label)}</span></a>`;

  return `
  <nav class="nav" aria-label="Screens" style="--nav-slots:${bar.length + (more.length ? 1 : 0)}">
    ${bar.map(item).join('')}
    ${more.length ? `<button class="nav__item${activeIsUnderMore ? ' is-active' : ''}" id="nav-more"
        type="button" aria-haspopup="true" aria-expanded="false"${activeIsUnderMore ? ' aria-current="page"' : ''}>
        <span class="nav__icon" aria-hidden="true">\u22EF</span><span class="nav__label">More</span></button>` : ''}
  </nav>
  ${more.length ? `<div class="nav-more" id="nav-more-sheet" hidden>
      <div class="nav-more__panel">${more.map(m => `<a class="item${m.href === active ? ' is-active' : ''}"
        href="${m.href}"${m.href === active ? ' aria-current="page"' : ''}>
        <span class="item__main"><span class="item__title">${esc(m.label)}</span></span>
        ${m.href === active ? '<span class="item__right">you are here</span>' : ''}</a>`).join('')}
      </div></div>` : ''}`;
}

/** Wires the More sheet. Called by every screen right after chrome() is written into the DOM. */
export function initNav() {
  const btn = $('#nav-more'), sheet = $('#nav-more-sheet');
  if (!btn || !sheet) return;
  const close = () => { sheet.hidden = true; btn.setAttribute('aria-expanded', 'false'); };
  btn.addEventListener('click', () => {
    sheet.hidden = !sheet.hidden;
    btn.setAttribute('aria-expanded', String(!sheet.hidden));
  });
  sheet.addEventListener('click', e => { if (e.target === sheet) close(); });
  document.addEventListener('keydown', e => { if (e.key === 'Escape') close(); });
}

// The scrolling tab strip is gone, so nothing has to be scrolled into view any more. Kept as a
// no-op for one release because every screen calls it; remove when they have all been touched.
export function revealActiveTab() {}

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
  // TAPPABLE. It was an inert <span> reporting a number nobody could act on, and flush() stops at
  // the first failure on purpose — ordered replay is correct, because a return replayed before its
  // own dispatch makes the movement ledger read backwards. The consequence is that ONE poison item
  // halts everything behind it, so the queue must be inspectable or the pill becomes a permanent
  // badge with no way in. This is the feature whose failure mode is a box leaving the godown with
  // no record; a silent dead end here is the worst place in the app for one.
  el.className = 'conn conn--tap ' + (online ? 'conn--sync' : 'conn--off');
  el.setAttribute('role', 'button');
  el.setAttribute('tabindex', '0');
  el.textContent = online
    ? `${pending} to send`
    : (pending ? `Offline · ${pending} waiting` : 'Offline');
  el.title = 'Tap to see what is waiting to be sent.';
  el.onclick = openQueue;
  el.onkeydown = (e) => { if (e.key === 'Enter' || e.key === ' ') { e.preventDefault(); openQueue(); } };
}

// ---------------------------------------------------------------------------
// WHAT IS WAITING, AND WHY IT IS STUCK.
//
// The real error, verbatim. Rule 15: the queue used to report every failure through one transient
// toast that said what stopped it and then vanished, and `#conn` afterwards said only a number.
// A row that cannot replay shows the message the database actually returned, the number of
// attempts, and when it was made — and can be dropped, deliberately, with a reason that is kept.
// ---------------------------------------------------------------------------
export async function openQueue() {
  const rows = (await store.allPending())
    .sort((a, b) => a.created_at.localeCompare(b.created_at));
  const blocked = rows.find(r => r.last_error);

  const sheet = openSheet(`
  <div class="sheet" id="sheet">
    <div class="sheet__panel" role="dialog" aria-modal="true" aria-labelledby="q-title" tabindex="-1">
      <div class="sheet__head">
        <h2 class="sheet__title" id="q-title">Waiting to be sent</h2>
        <button class="btn btn--ghost btn--sm" data-sheet-close type="button">Close</button>
      </div>
      ${!rows.length ? '<p class="field__hint">Nothing is waiting. Everything you have recorded is on the server.</p>' : `
      <p class="field__hint" style="margin-top:0">These are sent in the order you made them and the
        queue stops at the first one that fails — a return that reached the server before its own
        dispatch would make the history read backwards. So the first row below is the one holding
        up the rest.</p>
      ${blocked ? `<div class="note note--bad">
        <strong>Stuck on “${esc(blocked.label ?? blocked.kind)}”.</strong>
        <div style="margin-top:4px">${esc(blocked.last_error)}</div>
        <div class="field__hint" style="margin-top:4px">${esc(blocked.tries)} attempt${blocked.tries === 1 ? '' : 's'}.
          Everything after it is waiting on this.</div>
      </div>` : ''}
      <div class="card-list" id="q-list">${rows.map((r, i) => `
        <div class="card-row">
          <span class="card-row__main">
            <span class="card-row__title">${esc(r.label ?? r.kind)}</span>
            <span class="card-row__sub">${esc(fmtDate(new Date(r.created_at).toLocaleDateString('en-CA')))}${
              r.last_error ? ` · <strong style="color:var(--bad)">${esc(r.last_error)}</strong>`
                           : (i === 0 ? ' · next to go' : ' · waiting')}</span>
          </span>
          <span class="card-row__right">
            <button class="card-action q-drop" data-id="${esc(r.id)}"
                    data-label="${esc(r.label ?? r.kind)}" type="button">Discard</button>
          </span>
        </div>`).join('')}</div>
      <p class="field__hint">Discarding does not undo anything physical. If the gear went out, it
        went out — record it again by hand afterwards, or it is a box with no history.</p>`}
      <div class="sheet__foot">
        <button class="btn" data-sheet-close type="button">Close</button>
        ${rows.length ? '<button class="btn btn--primary" id="q-retry" type="button">Try again now</button>' : ''}
      </div>
    </div>
  </div>`);

  $('#q-retry')?.addEventListener('click', () => guardedWrite($('#q-retry'), 'Sending…', async () => {
    await syncNow(false);
    sheet.close();
    openQueue();
  }));

  $$('.q-drop').forEach(b => b.addEventListener('click', async () => {
    const what = b.dataset.label;
    if (!confirm(`Discard “${what}”?\n\nThis removes it from the queue. It does NOT undo anything `
               + `that physically happened — if the gear went out, it went out and will have no `
               + `record until you enter it again.`)) return;
    const why = (prompt('Why is it being dropped? Kept with the record so this can be answered later.',
                        'entered again by hand') || '').trim();
    if (!why) return;
    await store.discard(Number(b.dataset.id), why);
    paintConn(await store.pendingCount());
    sheet.close();
    openQueue();
  }));
}

/** Replay the queue. Safe to call often; does nothing when there is nothing to send. */
export async function syncNow(quiet = true) {
  if (!navigator.onLine) return;
  const n = await store.pendingCount();
  if (!n) { paintConn(0); return; }
  const res = await store.flush(queueHandlers);
  paintConn(await store.pendingCount());
  if (res.failed) {
    // The toast is transient and this is a blockage, not an event: it says where to look and the
    // pill stays tappable behind it. The full error lives in the queue sheet, which does not vanish
    // after four seconds.
    toast(`${res.done} of ${res.total} sent. Stuck on “${res.failed.label ?? res.failed.kind}”. `
        + `Tap the pill in the top bar to see why.`, 'error');
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
