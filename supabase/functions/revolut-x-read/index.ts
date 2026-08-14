// revolut-x-read v9 : LECTURE SEULE + texte lisible cash/liquide/stake pour l'IA. Aucun ordre.
// v9: separe l'USD (seul pouvoir d'achat pour les paires -USD) des autres devises (USDT/EUR...).

const cors = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}
const REVX_BASE = 'https://revx.revolut.com'
const API_KEY = (Deno.env.get('REVX_API_KEY') || '').trim()
const PRIVATE_PEM = Deno.env.get('REVX_PRIVATE_KEY') || ''

function pemToPkcs8Bytes(pem: string): Uint8Array {
  const b64s = pem.replace(/-----BEGIN [A-Z ]+-----/g, '').replace(/-----END [A-Z ]+-----/g, '').replace(/\s+/g, '')
  return Uint8Array.from(atob(b64s), c => c.charCodeAt(0))
}
async function importKey(): Promise<CryptoKey> {
  return await crypto.subtle.importKey('pkcs8', pemToPkcs8Bytes(PRIVATE_PEM), { name: 'Ed25519' }, false, ['sign'])
}
function b64(bytes: Uint8Array): string { let s = ''; for (const x of bytes) s += String.fromCharCode(x); return btoa(s) }
async function signedGet(path: string, query: string, key: CryptoKey) {
  const timestamp = Date.now().toString()
  const message = `${timestamp}GET${path}${query}`
  const sig = new Uint8Array(await crypto.subtle.sign({ name: 'Ed25519' }, key, new TextEncoder().encode(message)))
  const url = REVX_BASE + path + (query ? ('?' + query) : '')
  const r = await fetch(url, { method: 'GET', headers: { 'X-Revx-API-Key': API_KEY, 'X-Revx-Timestamp': timestamp, 'X-Revx-Signature': b64(sig), 'Content-Type': 'application/json' }, signal: AbortSignal.timeout(12000) })
  let body: any; try { body = await r.json() } catch { body = await r.text() }
  return { status: r.status, body }
}

const CASH = ['USD', 'USDT', 'USDC', 'EUR', 'GBP']
const num = (x: any) => Number(x) || 0

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: cors })
  try {
    if (!API_KEY || !PRIVATE_PEM) return new Response(JSON.stringify({ ok: false, error: 'Secrets manquants' }), { status: 500, headers: { ...cors, 'Content-Type': 'application/json' } })
    let key: CryptoKey
    try { key = await importKey() } catch (e) { return new Response(JSON.stringify({ ok: false, error: 'importKey a echoue', detail: String(e) }), { status: 200, headers: { ...cors, 'Content-Type': 'application/json' } }) }
    const res = await signedGet('/api/1.0/balances', '', key)
    if (res.status !== 200) return new Response(JSON.stringify({ ok: false, step: 'balances', status: res.status, response: res.body }), { status: 200, headers: { ...cors, 'Content-Type': 'application/json' } })
    let balances = Array.isArray(res.body) ? res.body : (res.body?.balances || res.body)
    let clean: any[] = []
    if (Array.isArray(balances)) {
      clean = balances.filter((b: any) => num(b.total) > 0 || num(b.available) > 0 || num(b.staked) > 0).map((b: any) => ({ devise: b.currency, disponible: b.available, reserve: b.reserved || '0', stake: b.staked || '0', total: b.total }))
    }
    const isCash = (b: any) => CASH.includes(String(b.devise).toUpperCase())
    const cash = clean.filter(isCash)
    const usd = cash.filter((b: any) => String(b.devise).toUpperCase() === 'USD')
    const autresCash = cash.filter((b: any) => String(b.devise).toUpperCase() !== 'USD')
    const liquide = clean.filter((b: any) => !isCash(b) && num(b.disponible) > 0)
    const stake = clean.filter((b: any) => num(b.stake) > 0)
    const fmtD = (b: any) => `${b.devise}=${b.disponible}`
    const fmtS = (b: any) => `${b.devise}=${b.stake}`
    const usdTxt = usd.length ? usd.map(fmtD).join(' , ') : 'USD=0'
    const soldes_texte = `POUVOIR D'ACHAT USD (SEUL cash utilisable pour ACHETER une paire -USD): ${usdTxt} || AUTRES DEVISES CASH (NON utilisables comme pouvoir d'achat pour les paires -USD -- ne PAS les compter pour un achat -USD): ${autresCash.length ? autresCash.map(fmtD).join(' , ') : 'aucune'} || POSITIONS LIQUIDES (vendables): ${liquide.length ? liquide.map(fmtD).join(' | ') : 'aucune'} || EN STAKE (VERROUILLE - NON vendable tant que non destake): ${stake.length ? stake.map(fmtS).join(' | ') : 'aucun'}`
    return new Response(JSON.stringify({ ok: true, count: clean.length, soldes: clean, soldes_texte }), { headers: { ...cors, 'Content-Type': 'application/json' } })
  } catch (e) {
    return new Response(JSON.stringify({ ok: false, error: String(e) }), { status: 500, headers: { ...cors, 'Content-Type': 'application/json' } })
  }
})
