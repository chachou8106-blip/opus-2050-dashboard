// reconcile-orders v2 : slippage calculé uniquement sur les ACHATS à notional (sur les ventes en qty la
// comparaison notional demandé/exécuté donnait des valeurs absurdes).
// v1 : réconcilie les ordres non finalisés avec leur statut réel chez Alpaca, quel que soit leur âge (cron horaire).

const cors = { 'Access-Control-Allow-Origin': '*', 'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type' }
const SUPABASE_URL = Deno.env.get('SUPABASE_URL') || 'https://smddzybxebwhfnitxuyp.supabase.co'
const SRK = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') || ''
const ALPACA = 'https://paper-api.alpaca.markets'

const KEYS: Record<string,{key:string,sec:string}> = {
  JU:  { key: 'PK_REDACTED', sec: 'REDACTED' },
  SYL: { key: 'PK_REDACTED', sec: 'REDACTED' },
  GIL: { key: 'PK_REDACTED', sec: 'REDACTED' },
}
const PER_CALL = 120

async function aget(key: string, sec: string, path: string): Promise<any> {
  try {
    const r = await fetch(ALPACA + path, { headers: { 'APCA-API-KEY-ID': key, 'APCA-API-SECRET-KEY': sec }, signal: AbortSignal.timeout(8000) })
    if (r.status === 404) return { __notfound: true }
    if (!r.ok) return null
    return await r.json()
  } catch { return null }
}
async function sbGet(path: string): Promise<any> {
  try {
    const r = await fetch(`${SUPABASE_URL}/rest/v1/${path}`, { headers: { 'apikey': SRK, 'Authorization': `Bearer ${SRK}` }, signal: AbortSignal.timeout(10000) })
    if (!r.ok) return null
    return await r.json()
  } catch { return null }
}
async function sbPatch(id: string, patch: any): Promise<boolean> {
  try {
    const r = await fetch(`${SUPABASE_URL}/rest/v1/oracle_college_orders?id=eq.${id}`, {
      method: 'PATCH',
      headers: { 'apikey': SRK, 'Authorization': `Bearer ${SRK}`, 'Content-Type': 'application/json', 'Prefer': 'return=minimal' },
      body: JSON.stringify(patch), signal: AbortSignal.timeout(10000)
    })
    return r.ok
  } catch { return false }
}

Deno.serve(async (_req) => {
  if (_req.method === 'OPTIONS') return new Response('ok', { headers: cors })
  try {
    if (!SRK) return new Response(JSON.stringify({ error: 'Missing service role key' }), { status: 500, headers: { ...cors, 'Content-Type': 'application/json' } })
    const summary: any = {}
    for (const arch of Object.keys(KEYS)) {
      const { key, sec } = KEYS[arch]
      const rows = await sbGet(`oracle_college_orders?archimage=eq.${arch}&broker_order_id=not.is.null&broker_status=in.(pending_new,accepted,new,partially_filled)&select=id,broker_order_id,notional,side,created_at&order=created_at.asc&limit=${PER_CALL}`)
      if (!Array.isArray(rows) || rows.length === 0) { summary[arch] = { checked: 0, updated: 0 }; continue }
      let updated = 0, filled = 0, expired = 0, notfound = 0
      for (const row of rows) {
        const o = await aget(key, sec, `/v2/orders/${row.broker_order_id}`)
        if (o && o.__notfound) {
          const ok = await sbPatch(row.id, { broker_status: 'expired', broker_response: { note: 'introuvable_alpaca_reconcile', checked_at: new Date().toISOString() } })
          if (ok) { updated++; expired++ }
          continue
        }
        if (!o || !o.status) { notfound++; continue }
        const status = String(o.status).toLowerCase()
        const filledQty = Number(o.filled_qty) || 0
        const fillPrice = Number(o.filled_avg_price) || 0
        const execNotional = (filledQty > 0 && fillPrice > 0) ? Math.round(filledQty * fillPrice * 100) / 100 : 0
        // v2 : slippage uniquement sur les achats
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
          broker_response: { status: o.status, filled_qty: o.filled_qty, filled_avg_price: o.filled_avg_price, symbol: o.symbol, side: o.side, updated_at: o.updated_at, filled_at: o.filled_at || null, reconciled_at: new Date().toISOString() }
        }
        const ok = await sbPatch(row.id, patch)
        if (ok) { updated++; if (status === 'filled') filled++; if (status === 'expired' || status === 'canceled') expired++ }
      }
      summary[arch] = { checked: rows.length, updated, filled, expired_or_canceled: expired, alpaca_unreachable: notfound }
    }
    return new Response(JSON.stringify({ ok: true, summary }), { headers: { ...cors, 'Content-Type': 'application/json' } })
  } catch (e) {
    return new Response(JSON.stringify({ error: String(e) }), { status: 500, headers: { ...cors, 'Content-Type': 'application/json' } })
  }
})
