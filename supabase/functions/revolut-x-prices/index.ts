// revolut-x-prices v2 : LECTURE SEULE des prix + champ texte lisible pour l'IA. Aucun ordre.

const cors = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

const REVX_BASE = 'https://revx.revolut.com'
const API_KEY = (Deno.env.get('REVX_API_KEY') || '').trim()
const PRIVATE_PEM = Deno.env.get('REVX_PRIVATE_KEY') || ''

function pemToPkcs8Bytes(pem: string): Uint8Array {
  const b = pem.replace(/-----BEGIN [A-Z ]+-----/g, '').replace(/-----END [A-Z ]+-----/g, '').replace(/\s+/g, '')
  return Uint8Array.from(atob(b), c => c.charCodeAt(0))
}
async function importKey(): Promise<CryptoKey> {
  return await crypto.subtle.importKey('pkcs8', pemToPkcs8Bytes(PRIVATE_PEM), { name: 'Ed25519' }, false, ['sign'])
}
function b64(bytes: Uint8Array): string {
  let s = ''; for (const x of bytes) s += String.fromCharCode(x); return btoa(s)
}
async function signedGet(path: string, query: string, key: CryptoKey) {
  const timestamp = Date.now().toString()
  const message = `${timestamp}GET${path}${query}`
  const sig = new Uint8Array(await crypto.subtle.sign({ name: 'Ed25519' }, key, new TextEncoder().encode(message)))
  const url = REVX_BASE + path + (query ? ('?' + query) : '')
  const r = await fetch(url, { method: 'GET', headers: { 'X-Revx-API-Key': API_KEY, 'X-Revx-Timestamp': timestamp, 'X-Revx-Signature': b64(sig), 'Content-Type': 'application/json' }, signal: AbortSignal.timeout(12000) })
  let body: any; try { body = await r.json() } catch { body = await r.text() }
  return { status: r.status, body }
}

const norm = (p: any) => String(p).replace('/', '-').toUpperCase()

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: cors })
  try {
    if (!API_KEY || !PRIVATE_PEM) return new Response(JSON.stringify({ ok: false, error: 'Secrets manquants' }), { status: 500, headers: { ...cors, 'Content-Type': 'application/json' } })
    const url = new URL(req.url)
    let symbols = url.searchParams.get('symbols') || ''
    if (!symbols && req.method === 'POST') {
      try { const b = await req.json(); if (Array.isArray(b?.symbols)) symbols = b.symbols.join(','); else if (Array.isArray(b?.devises)) symbols = b.devises.map((d: string) => `${d}-USD`).join(',') } catch { /* vide */ }
    }
    let key: CryptoKey
    try { key = await importKey() } catch (e) { return new Response(JSON.stringify({ ok: false, error: 'importKey a echoue', detail: String(e) }), { status: 200, headers: { ...cors, 'Content-Type': 'application/json' } }) }
    const query = symbols ? `symbols=${encodeURIComponent(symbols)}` : ''
    const res = await signedGet('/api/1.0/tickers', query, key)
    if (res.status !== 200) return new Response(JSON.stringify({ ok: false, step: 'tickers', status: res.status, response: res.body }), { status: 200, headers: { ...cors, 'Content-Type': 'application/json' } })
    let tickers = res.body?.tickers || res.body?.data || res.body
    let clean: any[] = []
    if (Array.isArray(tickers)) {
      clean = tickers.map((t: any) => ({ paire: norm(t.symbol || t.pair || t.id), bid: t.bid ?? t.best_bid ?? null, ask: t.ask ?? t.best_ask ?? null, mid: t.mid ?? t.mid_price ?? null, last: t.last ?? t.last_price ?? t.last_traded_price ?? null }))
    }
    // Champ texte lisible : uniquement les paires -USD avec bid/ask. Format PAIRE:bid/ask
    const usd = clean.filter((t: any) => t.paire.endsWith('-USD') && (t.bid != null || t.ask != null))
    const prix_texte = usd.map((t: any) => `${t.paire}:${t.bid ?? '?'}/${t.ask ?? '?'}`).join(' | ')
    return new Response(JSON.stringify({ ok: true, count: clean.length, count_usd: usd.length, prix: clean, prix_texte }), { headers: { ...cors, 'Content-Type': 'application/json' } })
  } catch (e) {
    return new Response(JSON.stringify({ ok: false, error: String(e) }), { status: 500, headers: { ...cors, 'Content-Type': 'application/json' } })
  }
})
