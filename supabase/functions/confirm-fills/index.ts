const cors = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

const SUPABASE_URL = Deno.env.get('SUPABASE_URL') || 'https://smddzybxebwhfnitxuyp.supabase.co'
const SUPABASE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') || ''
const ALPACA = 'https://paper-api.alpaca.markets'

// confirm-fills v3 : le slippage n'est calculé que sur les ACHATS à notional (sur les ventes en qty,
// comparer executed_notional au champ notional donnait des valeurs absurdes de -20%).
// v2 : le filtre run_id est SUPPRIME. On confirme TOUS les ordres non finalisés de l'archimage sur 24h.
// Body attendu : { archimage, alpaca_key, alpaca_secret }

async function alpacaGet(key: string, secret: string, path: string): Promise<any> {
  try {
    const r = await fetch(ALPACA + path, { headers: { 'APCA-API-KEY-ID': key, 'APCA-API-SECRET-KEY': secret }, signal: AbortSignal.timeout(10000) })
    if (!r.ok) return null
    return await r.json()
  } catch { return null }
}

async function sbGet(path: string): Promise<any> {
  try {
    const r = await fetch(`${SUPABASE_URL}/rest/v1/${path}`, { headers: { 'apikey': SUPABASE_KEY, 'Authorization': `Bearer ${SUPABASE_KEY}` }, signal: AbortSignal.timeout(10000) })
    if (!r.ok) return null
    return await r.json()
  } catch { return null }
}

async function sbPatch(id: string, patch: any): Promise<boolean> {
  try {
    const r = await fetch(`${SUPABASE_URL}/rest/v1/oracle_college_orders?id=eq.${id}`, {
      method: 'PATCH',
      headers: { 'apikey': SUPABASE_KEY, 'Authorization': `Bearer ${SUPABASE_KEY}`, 'Content-Type': 'application/json', 'Prefer': 'return=minimal' },
      body: JSON.stringify(patch), signal: AbortSignal.timeout(10000)
    })
    return r.ok
  } catch { return false }
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: cors })
  try {
    if (!SUPABASE_KEY) return new Response(JSON.stringify({ error: 'Missing service role key' }), { status: 500, headers: { ...cors, 'Content-Type': 'application/json' } })
    const { archimage, alpaca_key, alpaca_secret } = await req.json()
    if (!alpaca_key || !alpaca_secret || !archimage) return new Response(JSON.stringify({ error: 'Missing archimage or Alpaca credentials' }), { status: 400, headers: { ...cors, 'Content-Type': 'application/json' } })

    const since = new Date(Date.now() - 24*3600*1000).toISOString()
    const q = `oracle_college_orders?archimage=eq.${encodeURIComponent(archimage)}&broker_order_id=not.is.null&created_at=gte.${encodeURIComponent(since)}&select=id,broker_order_id,broker_status,side,notional&order=created_at.desc&limit=300`
    const rows = await sbGet(q)
    if (!Array.isArray(rows) || rows.length === 0) {
      return new Response(JSON.stringify({ archimage, checked: 0, updated: 0, message: 'Aucun ordre a confirmer' }), { headers: { ...cors, 'Content-Type': 'application/json' } })
    }

    const FINAL = new Set(['filled','canceled','cancelled','rejected','expired','done_for_day','replaced'])
    const toCheck = rows.filter((r: any) => !FINAL.has(String(r.broker_status || '').toLowerCase()))
    if (toCheck.length === 0) {
      return new Response(JSON.stringify({ archimage, checked: rows.length, updated: 0, message: 'Tous les ordres deja finalises' }), { headers: { ...cors, 'Content-Type': 'application/json' } })
    }

    const after = new Date(Date.now() - 24*3600*1000).toISOString()
    const alpacaOrders = await alpacaGet(alpaca_key, alpaca_secret, `/v2/orders?status=all&limit=500&after=${encodeURIComponent(after)}`)
    const byId: Record<string, any> = {}
    if (Array.isArray(alpacaOrders)) for (const o of alpacaOrders) byId[o.id] = o

    let updated = 0
    let notFound = 0
    const details: any[] = []
    for (const row of toCheck) {
      let o = byId[row.broker_order_id]
      if (!o) o = await alpacaGet(alpaca_key, alpaca_secret, `/v2/orders/${row.broker_order_id}`)
      if (!o || !o.status) { notFound++; details.push({ id: row.broker_order_id, note: 'introuvable_alpaca' }); continue }

      const status = String(o.status).toLowerCase()
      const filledQty = Number(o.filled_qty) || 0
      const fillPrice = Number(o.filled_avg_price) || 0
      const execNotional = (filledQty > 0 && fillPrice > 0) ? Math.round(filledQty * fillPrice * 100) / 100 : 0

      // v3 : slippage uniquement sur les achats à notional (seul cas où la comparaison a un sens)
      let slippage: number | null = null
      const wantN = Number(row.notional) || 0
      if (String(row.side || '').toLowerCase() === 'buy' && wantN > 0 && execNotional > 0) {
        slippage = Math.round(((execNotional - wantN) / wantN) * 10000) / 100
      }

      const patch: any = {
        broker_status: status,
        fill_price: fillPrice > 0 ? fillPrice : null,
        executed_notional: execNotional,
        slippage_pct: slippage,
        broker_response: { status: o.status, filled_qty: o.filled_qty, filled_avg_price: o.filled_avg_price, symbol: o.symbol, side: o.side, updated_at: o.updated_at, filled_at: o.filled_at || null }
      }
      const ok = await sbPatch(row.id, patch)
      if (ok) updated++
      details.push({ symbol: o.symbol, side: o.side, status, filled_qty: filledQty, fill_price: fillPrice, executed_notional: execNotional })
    }

    const filled = details.filter(d => d.status === 'filled').length
    return new Response(JSON.stringify({ archimage, checked: toCheck.length, updated, filled, not_found: notFound, details }), { headers: { ...cors, 'Content-Type': 'application/json' } })
  } catch(e) {
    return new Response(JSON.stringify({ error: String(e) }), { status: 500, headers: { ...cors, 'Content-Type': 'application/json' } })
  }
})
