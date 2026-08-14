// ingest-gate-prices — historique OHLC crypto depuis Gate.io (public, sans cle).
// Sert de source pour les coins que Binance a DELISTES/n'a pas (vrai OHLC, contrairement au spot Revolut).
// Sans 'symbols' : parcourt tout l'univers crypto propose. Format Gate v4 candlesticks :
// [ts, quote_vol, close, high, low, open, base_vol, closed].

const SUPABASE_URL = Deno.env.get('SUPABASE_URL')!
const SERVICE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
const cors = { 'Access-Control-Allow-Origin': '*', 'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type' }
const json = (d: unknown, s = 200) => new Response(JSON.stringify(d), { status: s, headers: { ...cors, 'Content-Type': 'application/json' } })
const CHUNK = 6

async function sbGet(path: string): Promise<any> {
  try {
    const r = await fetch(`${SUPABASE_URL}/rest/v1/${path}`, { headers: { apikey: SERVICE_KEY, Authorization: `Bearer ${SERVICE_KEY}` } })
    if (!r.ok) return null
    return await r.json()
  } catch { return null }
}

async function ingestOne(sym: string, limit: number): Promise<string> {
  try {
    const base = sym.replace('-USD', '')
    const url = `https://api.gateio.ws/api/v4/spot/candlesticks?currency_pair=${base}_USDT&interval=1h&limit=${limit}`
    const r = await fetch(url)
    if (r.status !== 200) return `gate ${r.status}`
    const kl = await r.json()
    if (!Array.isArray(kl) || kl.length === 0) return 'aucune donnee'
    const rows = kl.map((k: any[]) => ({
      symbol: sym, interval: '1h',
      ts: new Date(Number(k[0]) * 1000).toISOString(),
      open: Number(k[5]), high: Number(k[3]), low: Number(k[4]), close: Number(k[2]), volume: Number(k[6]),
    })).filter((x: any) => x.open > 0 && x.close > 0)
    if (rows.length === 0) return 'valeurs nulles'
    const up = await fetch(`${SUPABASE_URL}/rest/v1/price_history?on_conflict=symbol,interval,ts`, {
      method: 'POST',
      headers: { apikey: SERVICE_KEY, Authorization: `Bearer ${SERVICE_KEY}`, 'Content-Type': 'application/json', Prefer: 'resolution=merge-duplicates,return=minimal' },
      body: JSON.stringify(rows),
    })
    return up.ok ? `ok ${rows.length}` : `db ${up.status}`
  } catch (e: any) { return String(e?.message || e).slice(0, 80) }
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: cors })
  try {
    const body = await req.json().catch(() => ({}))
    const limit = Math.min(Number(body.limit) || 1000, 1000)
    let symbols: string[]
    if (Array.isArray(body.symbols) && body.symbols.length > 0) symbols = body.symbols
    else {
      const univ = await sbGet('v_crypto_univers?select=paire')
      symbols = Array.isArray(univ) ? univ.map((r: any) => r.paire).filter(Boolean) : []
    }
    const results: Record<string, string> = {}
    let ok_count = 0, miss_count = 0
    for (let i = 0; i < symbols.length; i += CHUNK) {
      const batch = symbols.slice(i, i + CHUNK)
      const settled = await Promise.all(batch.map((s) => ingestOne(s, limit)))
      settled.forEach((res, j) => { results[batch[j]] = res; if (res.startsWith('ok')) ok_count++; else miss_count++ })
    }
    return json({ ok: true, source: 'gate.io', symboles_total: symbols.length, ingeres: ok_count, absents: miss_count, results })
  } catch (e: any) { return json({ ok: false, error: String(e?.message || e) }) }
})
