// sheet-mirror — the OUT lane of the Google Sheet link.
//
// Returns every mirrored tab as rows of plain values, for DataSync.gs to write into the Sheet.
//
// READ-ONLY IS THE WHOLE POINT. This function performs no writes and has no code path that could.
// If the Sheet could write back, the Sheet and the database would disagree and there would be no
// way to tell which was right — see the djn-sheet-sync skill. The IN lane is a separate, validated
// catalogue importer and is deliberately not this function.
//
// Every push is a FULL REPLACE of the mirrored range, never a merge: a merge leaves deleted rows
// behind for ever, and a mirror that quietly keeps rows the database no longer has is worse than no
// mirror at all.
//
// Auth: a shared token in the x-mirror-token header, checked against MIRROR_TOKEN. The service role
// key lives only in this function's environment — never in the Sheet, never in web/.

import { createClient } from 'jsr:@supabase/supabase-js@2';

const SUPABASE_URL = Deno.env.get('SUPABASE_URL')!;
const SERVICE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
const MIRROR_TOKEN = Deno.env.get('MIRROR_TOKEN') ?? '';

const cors = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type, x-mirror-token',
};

/** Turn an array of objects into [header row, ...value rows] — the shape a Sheet range wants. */
function toRows(items: Record<string, unknown>[], columns: string[]): unknown[][] {
  return [columns, ...items.map(it => columns.map(c => {
    const v = it[c];
    if (v === null || v === undefined) return '';
    if (typeof v === 'object') return JSON.stringify(v);
    return v;
  }))];
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: cors });

  if (!MIRROR_TOKEN || req.headers.get('x-mirror-token') !== MIRROR_TOKEN) {
    return new Response(JSON.stringify({ error: 'Not authorised.' }), {
      status: 401, headers: { ...cors, 'content-type': 'application/json' },
    });
  }

  const sb = createClient(SUPABASE_URL, SERVICE_KEY, { auth: { persistSession: false } });

  try {
    const [products, cats, subs, units, locs, orders, custs, lines, ledger, balances, roi, util] =
      await Promise.all([
        sb.from('product').select('*').order('short_code'),
        sb.from('category').select('id,name'),
        sb.from('subcategory').select('id,name'),
        sb.from('v_unit_status').select('*'),
        sb.from('location').select('id,name'),
        sb.from('rental_order').select('*').order('out_date', { ascending: false }),
        sb.from('customer').select('id,name,business_name,whatsapp,city'),
        sb.from('order_line').select('order_id,product_id,qty,line_total'),
        sb.from('ledger_entry').select('*').order('entry_date', { ascending: false }),
        sb.from('v_customer_balance').select('*'),
        sb.from('v_product_roi').select('*'),
        sb.from('v_unit_utilisation').select('*'),
      ]);

    for (const r of [products, cats, subs, units, locs, orders, custs, lines, ledger, balances, roi, util]) {
      if (r.error) throw r.error;
    }

    const catName = new Map((cats.data ?? []).map(c => [c.id, c.name]));
    const subName = new Map((subs.data ?? []).map(c => [c.id, c.name]));
    const locName = new Map((locs.data ?? []).map(c => [c.id, c.name]));
    const custName = new Map((custs.data ?? []).map(c => [c.id, c.business_name || c.name]));
    const prodCode = new Map((products.data ?? []).map(p => [p.id, p.short_code]));

    // Portal code hashes are NEVER mirrored. Nor is anything resembling an ID number — the customer
    // tab carries a name, a phone and a city, and that is all the Sheet needs to be useful.
    const tabs: Record<string, unknown[][]> = {
      Products: toRows((products.data ?? []).map(p => ({
        ...p,
        category: catName.get(p.category_id) ?? '',
        subcategory: subName.get(p.subcategory_id) ?? '',
      })), ['short_code', 'brand', 'model_name', 'model_number', 'category', 'subcategory',
            'tracking_mode', 'rentable', 'base_rate_per_day', 'default_purchase_cost', 'pool_qty',
            'active', 'specs', 'inclusions']),

      Units: toRows((units.data ?? []).map(u => ({
        ...u,
        product: prodCode.get(u.product_id) ?? '',
        // at_id means a location, a customer or a vendor depending on at_kind. Only resolve the
        // location case — labelling a customer id as a location name would be a lie (rule 7).
        location: u.at_kind === 'location' ? (locName.get(u.at_id) ?? '') : '',
        at: u.at_kind === 'customer' ? 'with a customer'
          : u.at_kind === 'vendor' ? 'at a repair shop'
          : u.at_kind === 'location' ? (locName.get(u.at_id) ?? 'a location')
          : 'no movement recorded',
      })), ['product', 'piece_no', 'status', 'condition', 'lifecycle', 'at', 'location',
            'last_moved_on', 'days_in_place']),

      Orders: toRows((orders.data ?? []).map(o => ({
        ...o,
        customer: custName.get(o.customer_id) ?? '',
        lines: (lines.data ?? []).filter(l => l.order_id === o.id).length,
        rental_value: (lines.data ?? []).filter(l => l.order_id === o.id)
          .reduce((n, l) => n + Number(l.line_total ?? 0), 0),
      })), ['order_no', 'customer', 'status', 'event_type', 'venue_name', 'out_date',
            'expected_return_date', 'days', 'lines', 'rental_value', 'deposit_amount',
            'availability_override', 'availability_override_reason']),

      Ledger: toRows((ledger.data ?? []).map(e => ({
        ...e, customer: custName.get(e.customer_id) ?? '',
      })), ['entry_date', 'customer', 'type', 'amount', 'state', 'payment_mode', 'reference', 'notes']),

      // Receivable, upcoming and deposit_held stay THREE columns here too. A mirror that helpfully
      // totalled them would be the one place rule 6 got broken, and it would be believed because it
      // came out of a spreadsheet.
      Balances: toRows(balances.data ?? [],
        ['name', 'business_name', 'receivable', 'upcoming', 'deposit_held']),

      ROI: toRows(roi.data ?? [],
        ['short_code', 'model_name', 'rental_revenue', 'repair_cost', 'purchase_cost',
         'units_active', 'units_ever', 'units_missing_cost', 'net_return', 'roi_pct']),

      Utilisation: toRows((util.data ?? []).map(u => ({
        ...u, product: prodCode.get(u.product_id) ?? '',
      })), ['product', 'piece_no', 'times_hired', 'days_out', 'days_owned', 'utilisation_pct']),
    };

    return new Response(JSON.stringify({ generated_at: new Date().toISOString(), tabs }), {
      headers: { ...cors, 'content-type': 'application/json' },
    });
  } catch (err) {
    return new Response(JSON.stringify({ error: String((err as Error)?.message ?? err) }), {
      status: 500, headers: { ...cors, 'content-type': 'application/json' },
    });
  }
});
