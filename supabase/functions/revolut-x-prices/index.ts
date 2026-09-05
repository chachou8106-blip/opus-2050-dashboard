// revolut-x-prices v3 : LECTURE SEULE des prix + champ texte lisible pour l'IA. Aucun ordre.
//
// v3 (05/09/2026) — L'ALCHIMISTE RECOIT ENFIN DE QUOI CHOISIR SA PAIRE.
//   Constat de Chachou : « normalement on a beaucoup plus de donnees dispo sur les crypto,
//   regarde mon scenario ». Verifie, et il a raison sur toute la ligne.
//
//   MESURE AVANT/APRES, 05/09 :
//     - Les 302 paires lui arrivaient en bid/ask INSTANTANE. Rien d'autre. Devant
//       « ABC-USD:0.0271/0.0273 », aucune paire ne se distingue d'une autre.
//     - Resultat mesure sur 81 propositions : 19 paires nommees sur 302, dont 16 deja
//       detenues. Il ne choisissait pas, il repetait ce qu'il avait sous les yeux.
//     - Et collect-market-data produisait DEJA universe.crypto_gainers, .crypto_losers,
//       .crypto_top_mcap (25 coins avec pct24h) et .tradeable_crypto : ZERO module du
//       blueprint ne les mappe. Fabriques a chaque run, jetes a chaque run.
//
//   CE QUE v3 AJOUTE, ET SUR QUEL PRINCIPE :
//   prix_texte porte desormais, POUR CHACUNE DES 302 PAIRES et sans aucune selection de ma
//   main, la variation 24 h, la variation 7 j et le volume 24 h en dollars — lus dans
//   v_alc_paires_variation, c'est-a-dire dans price_history, qui couvre les 302 paires en
//   horaire depuis 2022. Couverture mesuree : 302/302 sur les trois mesures.
//   Je n'envoie PAS un top 15 : un classement serait MON choix de candidats, et c'est
//   exactement ce que la regle du 26/08 interdit. Je transmets la mesure sur tout l'univers,
//   la selection reste la sienne.
//
//   Le champ garde son NOM et son ORDRE (paire, puis bid/ask en tete de ligne) : le module
//   Make 10011 et le prompt du 10012 ne changent pas d'une ligne.
//   Si la vue est injoignable, on retombe EXACTEMENT sur la sortie v2.
//
// v2 : champ texte lisible, uniquement les paires -USD avec bid/ask.

const cors = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

const REVX_BASE = 'https://revx.revolut.com'
const API_KEY = (Deno.env.get('REVX_API_KEY') || '').trim()
const PRIVATE_PEM = Deno.env.get('REVX_PRIVATE_KEY') || ''
const SUPABASE_URL = Deno.env.get('SUPABASE_URL') || ''
const SERVICE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') || ''

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

type Mesure = { v24: number | null; v7: number | null; liq: number | null }

// Variation 24 h / 7 j / volume 24 h en $, par paire. NE LEVE JAMAIS : si la vue est
// injoignable, on renvoie une carte vide et prix_texte redevient exactement celui de v2.
async function mesuresParPaire(): Promise<Record<string, Mesure>> {
  const out: Record<string, Mesure> = {}
  try {
    if (!SUPABASE_URL || !SERVICE_KEY) return out
    const r = await fetch(
      `${SUPABASE_URL}/rest/v1/v_alc_paires_variation?select=paire,dernier_close,var_24h_pct,var_7j_pct,volume_24h&limit=2000`,
      { headers: { apikey: SERVICE_KEY, Authorization: `Bearer ${SERVICE_KEY}` }, signal: AbortSignal.timeout(10000) },
    )
    if (!r.ok) return out
    const rows = await r.json()
    if (!Array.isArray(rows)) return out
    for (const x of rows) {
      const p = String(x?.paire || '').toUpperCase()
      if (!p) continue
      const close = Number(x?.dernier_close)
      const vol = Number(x?.volume_24h)
      out[p] = {
        v24: x?.var_24h_pct == null ? null : Number(x.var_24h_pct),
        v7: x?.var_7j_pct == null ? null : Number(x.var_7j_pct),
        liq: Number.isFinite(close) && Number.isFinite(vol) ? close * vol : null,
      }
    }
  } catch { /* silencieux : l'absence de mesures ne doit jamais empecher la lecture des prix */ }
  return out
}

const pct = (x: number | null) => (x == null ? '?' : `${x > 0 ? '+' : ''}${x.toFixed(1)}%`)
const liq = (x: number | null) => {
  if (x == null) return '?'
  if (x >= 1e9) return `${(x / 1e9).toFixed(1)}G$`
  if (x >= 1e6) return `${(x / 1e6).toFixed(1)}M$`
  if (x >= 1e3) return `${Math.round(x / 1e3)}k$`
  return `${Math.round(x)}$`
}

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

    // Champ texte lisible : uniquement les paires -USD avec bid/ask.
    // v2  : PAIRE:bid/ask
    // v3  : PAIRE:bid/ask 24h=<var> 7j=<var> liq=<volume 24 h en $>
    const usd = clean.filter((t: any) => t.paire.endsWith('-USD') && (t.bid != null || t.ask != null))
    const mes = await mesuresParPaire()
    const enrichi = Object.keys(mes).length > 0
    for (const t of usd) {
      const m = mes[t.paire]
      t.var_24h_pct = m?.v24 ?? null
      t.var_7j_pct = m?.v7 ?? null
      t.liquidite_24h_usd = m?.liq == null ? null : Math.round(m.liq)
    }
    const legende = enrichi
      ? 'LEGENDE: PAIRE:meilleur_achat/meilleure_vente 24h=variation sur 24h 7j=variation sur 7 jours liq=volume echange en dollars sur 24h (0 = aucun volume rapporte, la paire peut etre tres difficile a revendre). Ces mesures portent sur TOUTES les paires cotees, sans selection prealable : le choix est le tien. || '
      : ''
    const prix_texte = legende + usd.map((t: any) => {
      const base = `${t.paire}:${t.bid ?? '?'}/${t.ask ?? '?'}`
      if (!enrichi) return base
      const m = mes[t.paire]
      if (!m) return base
      return `${base} 24h=${pct(m.v24)} 7j=${pct(m.v7)} liq=${liq(m.liq)}`
    }).join(' | ')

    return new Response(JSON.stringify({ ok: true, count: clean.length, count_usd: usd.length, mesures_jointes: enrichi, prix: clean, prix_texte }), { headers: { ...cors, 'Content-Type': 'application/json' } })
  } catch (e) {
    return new Response(JSON.stringify({ ok: false, error: String(e) }), { status: 500, headers: { ...cors, 'Content-Type': 'application/json' } })
  }
})
