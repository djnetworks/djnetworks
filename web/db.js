// db.js — IndexedDB. Two jobs, and they are not the same job.
//
//   queue : writes made with no signal, replayed when there is one.
//   cache : reads PRE-FETCHED while there was signal, so there is something to work from later.
//
// The second one is the half that gets forgotten. Queueing writes makes a form submittable
// offline; it does nothing for a dispatch screen, because dispatch is mostly a READ — which of
// these eight boxes am I allowed to send. With no signal and no prefetch there is nothing to tap.
// So offline is a workflow, not a toggle: the order is loaded deliberately while there is signal,
// and the screen says plainly whether it holds that job or not. No screen here claims to work
// everywhere.

const DB_NAME = 'djn';
const DB_VERSION = 1;

let dbp;
function db() {
  if (dbp) return dbp;
  dbp = new Promise((resolve, reject) => {
    const req = indexedDB.open(DB_NAME, DB_VERSION);
    req.onupgradeneeded = () => {
      const d = req.result;
      if (!d.objectStoreNames.contains('queue')) {
        const q = d.createObjectStore('queue', { keyPath: 'id', autoIncrement: true });
        q.createIndex('created_at', 'created_at');
      }
      if (!d.objectStoreNames.contains('cache')) {
        d.createObjectStore('cache', { keyPath: 'key' });
      }
    };
    req.onsuccess = () => resolve(req.result);
    req.onerror = () => reject(req.error);
  });
  return dbp;
}

function tx(store, mode, fn) {
  return db().then(d => new Promise((resolve, reject) => {
    const t = d.transaction(store, mode);
    const s = t.objectStore(store);
    let out;
    try { out = fn(s); } catch (e) { reject(e); return; }
    // `out` is an IDBRequest, so ALWAYS unwrap it — never fall back to the request object.
    // The old test was `out.result !== undefined ? out.result : out`, and a get() that finds
    // nothing has result === undefined, so a cache MISS resolved to the IDBRequest itself. That
    // object is truthy, so `if (c)` passed and `c.data` was undefined: opening a job on
    // dispatch.html with no signal and no prefetch printed "Could not load — Cannot destructure
    // property 'order' of 'c.data' as it is undefined" instead of the "This job is not on this
    // phone" state block, which was unreachable. getAll() still resolves to its array, empty or
    // not; add/put still resolve to the key; delete resolves to undefined and nothing reads it.
    t.oncomplete = () => resolve(out instanceof IDBRequest ? out.result : out);
    t.onerror = () => reject(t.error);
    t.onabort = () => reject(t.error);
  }));
}

// ---------------------------------------------------------------------------
// Queue
// ---------------------------------------------------------------------------

/**
 * Record a write to be replayed later. `kind` names a handler; `payload` must be plain JSON —
 * it has to survive the phone being locked, the tab being killed, and the browser restarting.
 * `label` is what the operator sees in the pending list, so it says what the write MEANS
 * ("Dispatch 4 pieces on DJN-2609-0002"), never which table it touches.
 */
export async function enqueue(kind, payload, label) {
  const row = { kind, payload, label, created_at: new Date().toISOString(), tries: 0, last_error: null };
  await tx('queue', 'readwrite', s => s.add(row));
  notify();
  return row;
}

export function allPending() {
  return tx('queue', 'readonly', s => s.getAll());
}

export async function pendingCount() {
  return (await allPending()).length;
}

async function remove(id) { return tx('queue', 'readwrite', s => s.delete(id)); }
async function update(row) { return tx('queue', 'readwrite', s => s.put(row)); }

/**
 * Replay everything queued, oldest first, STOPPING at the first failure.
 *
 * Order matters and parallelism would break it: a return recorded after a dispatch must reach the
 * database after that dispatch, or the movement ledger reads backwards and v_unit_location — which
 * breaks ties on moved_on then created_at — resolves the pair arbitrarily. One at a time, in the
 * order they were made.
 *
 * A failure leaves the item in place with its error recorded rather than discarding it. A queued
 * dispatch that cannot be replayed is a box that physically left the godown; losing that row
 * silently is the six-out-five-back bug with extra steps.
 */
export async function flush(handlers, onProgress) {
  const rows = (await allPending()).sort((a, b) => a.created_at.localeCompare(b.created_at));
  let done = 0, failed = null;
  for (const row of rows) {
    const handler = handlers[row.kind];
    if (!handler) {
      row.tries += 1;
      row.last_error = `No handler for "${row.kind}" — this version of the app cannot replay it.`;
      await update(row);
      failed = row; break;
    }
    try {
      await handler(row.payload);
      await remove(row.id);
      done += 1;
      onProgress?.(done, rows.length);
    } catch (err) {
      row.tries += 1;
      row.last_error = err?.message || String(err);
      await update(row);
      failed = row; break;
    }
  }
  notify();
  return { done, total: rows.length, failed };
}

export async function discard(id) { await remove(id); notify(); }

const listeners = new Set();
export function onQueueChange(fn) { listeners.add(fn); return () => listeners.delete(fn); }
function notify() { pendingCount().then(n => listeners.forEach(f => f(n))); }

// ---------------------------------------------------------------------------
// Prefetch cache
// ---------------------------------------------------------------------------

export async function cachePut(key, data) {
  await tx('cache', 'readwrite', s => s.put({ key, data, cached_at: new Date().toISOString() }));
}

export async function cacheGet(key) {
  const row = await tx('cache', 'readonly', s => s.get(key));
  return row ?? null;
}

export async function cacheKeys(prefix = '') {
  const rows = await tx('cache', 'readonly', s => s.getAll());
  return rows.filter(r => r.key.startsWith(prefix));
}

export async function cacheDrop(key) { await tx('cache', 'readwrite', s => s.delete(key)); }
