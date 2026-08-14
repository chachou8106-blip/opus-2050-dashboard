// ingest-revx-prices — ingestion des prix Revolut X en bougies horaires.
// PRIORITE REVOLUT X : Revolut est la VRAIE plateforme d'execution de l'Alchimiste, et toujours a jour.
// Son prix ecrase donc la bougie de l'heure COURANTE (merge-duplicates) : une donnee Binance perimee ne
// peut jamais bloquer un prix frais. Binance reste utile pour la PROFONDEUR d'historique : ses bougies
// completes (OHLC reel) des heures DEJA PASSEES sont re-ecrites a l'heure suivante et ne sont pas touchees
// par Revolut (qui n'ecrit que l'heure courante). Resultat : prix frais toujours prioritaire, OHLC Binance
// conserve sur le passe pour les coins qu'il suit.

const cors = { 'Access-Control-Allow-Origin': '*', 'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type' }
const SUPABASE_URL = Deno.env.get('SUPABASE_URL')!
const SERVICE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
const REVX_BASE = 'https://revx.revolut.com'
const API_KEY = (Deno.env.get('REVX_API_KEY') || '').trim()
const PRIVATE_PEM = Deno.env.get('REVX_PRIVATE_KEY') || ''

function pemToPkcs8Bytes(pem: string): Uint8Array {
  const b = pem.replace(/-----BEGIN [A-Z ]+-----/g, '').replace(/-----END [A-Z ]+-----/g, '').replace(/\s+/g, '')
  return Uint8Array.from(atob(b), c => c.charCodeAt(0))
}
function b64(bytes: Uint8Array): string { let s = ''; for (const x of bytes) s += String.fromCharCode(x); return btoa(s) }
const norm = (p: any) => String(p).replace('/', '-').toUpperCase()

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: cors })
  try {
    if (!API_KEY || !PRIVATE_PEM) return new Response(JSON.stringify({ ok: false, error: 'Secrets REVX manquants' }), { status: 200, headers: { ...cors, 'Content-Type': 'application/json' } })
    const key = await crypto.subtle.importKey('pkcs8', pemToPkcs8Bytes(PRIVATE_PEM), { name: 'Ed25519' }, false, ['sign'])
    const timestamp = Date.now().toString()
    const path = '/api/1.0/tickers'
    const message = `${timestamp}GET${path}`
    const sig = new Uint8Array(await crypto.subtle.sign({ name: 'Ed25519' }, key, new TextEncoder().encode(message)))
    const r = await fetch(REVX_BASE + path, { method: 'GET', headers: { 'X-Revx-API-Key': API_KEY, 'X-Revx-Timestamp': timestamp, 'X-Revx-Signature': b64(sig), 'Content-Type': 'application/json' }, signal: AbortSignal.timeout(15000) })
    if (r.status !== 200) return new Response(JSON.stringify({ ok: false, step: 'tickers', status: r.status }), { status: 200, headers: { ...cors, 'Content-Type': 'application/json' } })
    const body = await r.json()
    const tickers = body?.tickers || body?.data || body
    if (!Array.isArray(tickers)) return new Response(JSON.stringify({ ok: false, error: 'format tickers inattendu' }), { status: 200, headers: { ...cors, 'Content-Type': 'application/json' } })

    // bucket heure courante (UTC, minutes/sec a 0)
    const now = new Date(); now.setUTCMinutes(0, 0, 0)
    const ts = now.toISOString()

    const rows: any[] = []
    for (const t of tickers) {
      const paire = norm(t.symbol || t.pair || t.id)
      if (!paire.endsWith('-USD')) continue
      const px = Number(t.last ?? t.last_price ?? t.last_traded_price ?? t.mid ?? t.mid_price ?? t.bid ?? t.best_bid)
      if (!(px > 0)) continue
      rows.push({ symbol: paire, interval: '1h', ts, open: px, high: px, low: px, close: px, volume: 0 })
    }
    if (rows.length === 0) return new Response(JSON.stringify({ ok: true, ingeres: 0, note: 'aucune paire USD valide' }), { headers: { ...cors, 'Content-Type': 'application/json' } })

    // PRIORITE REVOLUT : merge-duplicates => le prix frais de l'heure courante ecrase toute donnee perimee.
    const up = await fetch(`${SUPABASE_URL}/rest/v1/price_history?on_conflict=symbol,interval,ts`, {
      method: 'POST',
      headers: { apikey: SERVICE_KEY, Authorization: `Bearer ${SERVICE_KEY}`, 'Content-Type': 'application/json', Prefer: 'resolution=merge-duplicates,return=minimal' },
      body: JSON.stringify(rows),
    })
    const okUp = up.ok
    return new Response(JSON.stringify({ ok: okUp, source: 'revolut-x', priorite: 'revolut (heure courante)', heure: ts, paires_usd: rows.length, db: okUp ? 'ok' : `${up.status}: ${(await up.text()).slice(0,150)}` }), { headers: { ...cors, 'Content-Type': 'application/json' } })
  } catch (e) {
    return new Response(JSON.stringify({ ok: false, error: String(e) }), { status: 200, headers: { ...cors, 'Content-Type': 'application/json' } })
  }
})
