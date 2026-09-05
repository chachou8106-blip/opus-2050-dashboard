// revolut-x-read v15 : LECTURE SEULE cote Revolut. Aucun ordre, jamais.
//
// v15 (05/09/2026) — LE PRIX DE REVIENT DES LIGNES DONT LE JOURNAL COUVRE TOUT.
//   Chachou : « j ai achete que 68,95$ soit 33095 fai le 12 juin et 25$ le 22 juillet
//   10035 fai je t ai donne plusieurs fois les ordres pourquoi tu les voit pas ! ».
//   L'achat du 22/07 manquait au journal : les deux extraits d'ecran de la journee sautent
//   juillet, et je n'avais recopie que ce que j'avais sous les yeux. Ajoute.
//   FAI passe alors de 77 % a 100,1 % de couverture : 93,95 $ pour 43 160 FAI, prix de
//   revient 0,00217678, cours 0,002399, soit +10,2 %. La ligne devient exploitable.
//   Ne sont transmises QUE les lignes ou complet = true (le journal couvre la quantite
//   detenue a 3 % pres ET tous les achats sont en USD). Une ligne partielle ferait croire
//   a l'agent qu'il gagne ou perd la ou il n'en sait rien : elle reste hors du texte.
//   Aujourd'hui : FAI et OSMO. Les autres s'ajouteront d'elles-memes.
//
// v14 (05/09/2026) — PLUS RIEN A SAISIR : LE PLAN D'ACHATS RECURRENTS EST DEDUIT.
//   « je ne modifie rien seul tout doit etre automatique !!! et si ca gene je supprime
//     l achat recurrent !! » — Chachou. La v13 lui demandait de tenir une ligne de table a
//     jour : c'est encore de la saisie, donc c'est encore quelque chose qui peut mentir.
//
//   A chaque appel, cette fonction journalise /api/1.0/transactions dans
//   alc_revolut_transactions (cle = l'id Revolut, aucun doublon possible). L'API n'expose
//   que 7 jours et 50 lignes, sans page suivante — mesure du 05/09, metadata.next_cursor
//   est la chaine vide — mais elle est appelee ~6 fois par jour : rien ne peut etre manque,
//   et le journal, lui, garde tout pour toujours.
//   La vue v_alc_achats_recurrents_detectes en DEDUIT les plans : trois achats de la meme
//   devise au meme jour de semaine et a la meme heure. Aucune coincidence ne tient trois fois.
//   Verifie sur les donnees reelles : {BCH,TRX,XLM,XRP}, 6,74 $, hebdomadaire, ecart median
//   7,0 jours, prochain attendu le 07/09 — exactement la date qu'affiche son ecran Revolut,
//   qu'aucune de nos donnees ne contenait.
//   S'il supprime son plan, il n'a rien a faire : apres deux periodes sans prelevement la
//   vue passe actif=false et la phrase disparait toute seule du contexte de l'Alchimiste.
//
// v13 : la phrase venait d'une table que Chachou devait tenir a jour. Remplacee par la vue.
//
// v12 : valeur en dollars et poids en % par ligne, total, cash, % de cash. L'agent recoit la
//       MESURE au lieu d'aller chercher un prix dans une ligne de 8 122 caracteres — exercice
//       ou il s'est trompe trois fois les 03 et 04/09 (il attrapait la paire VOISINE).
//       Le champ garde son NOM (soldes_texte) et le tableau `soldes` est INCHANGE : alc-auto,
//       qui lit `soldes`, n'est pas affecte.
// v11 : mode {"raw":"/api/1.0/xxx"} pour explorer l'API en GET signe.
// v10 : mode {"probe":true}. Mesure du 05/09 sur les huit chemins :
//         /api/1.0/balances      200
//         /api/1.0/transactions  200   <- le seul historique accessible (50 lignes, 7 jours,
//                                         next_cursor vide : il n'y a pas de page suivante)
//         /api/1.0/trades        401   /api/1.0/orders     401   /api/1.0/fills   401
//         /api/1.0/positions     401   /api/1.0/portfolio  401   /api/1.0/statements 401
//       L'ecran « Ordres » de l'application n'a donc PAS d'equivalent API sur cette cle.
// v9  : separe l'USD (seul pouvoir d'achat pour les paires -USD) des autres devises.

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
  const r = await fetch(url, { method: 'GET', headers: { 'X-Revx-API-Key': API_KEY, 'X-Revx-Timestamp': timestamp, 'X-Revx-Signature': b64(sig), 'Content-Type': 'application/json' }, signal: AbortSignal.timeout(15000) })
  let body: any; try { body = await r.json() } catch { body = await r.text() }
  return { status: r.status, body }
}

const CASH = ['USD', 'USDT', 'USDC', 'EUR', 'GBP']
const num = (x: any) => Number(x) || 0
const CHEMINS = ['/api/1.0/balances','/api/1.0/trades','/api/1.0/orders','/api/1.0/transactions','/api/1.0/fills','/api/1.0/positions','/api/1.0/portfolio','/api/1.0/statements']

// Prix mid par paire -USD. NE LEVE JAMAIS : si ca echoue, on repart sur le format v9.
async function prixParDevise(): Promise<Record<string, number>> {
  const out: Record<string, number> = {}
  try {
    const r = await fetch(`${SUPABASE_URL}/functions/v1/revolut-x-prices`, {
      method: 'POST', headers: { 'Content-Type': 'application/json' }, body: '{}',
      signal: AbortSignal.timeout(12000),
    })
    if (!r.ok) return out
    const j = await r.json()
    for (const p of (Array.isArray(j?.prix) ? j.prix : [])) {
      const paire = String(p?.paire || '')
      if (!paire.endsWith('-USD')) continue
      const mid = num(p.mid) || num(p.last) || ((num(p.bid) + num(p.ask)) / 2)
      if (mid > 0) out[paire.slice(0, -4).toUpperCase()] = mid
    }
  } catch { /* silencieux : l'absence de prix ne doit jamais empecher la lecture des soldes */ }
  return out
}
const d2 = (x: number) => (Math.round(x * 100) / 100).toFixed(2)

const sb = (chemin: string, init: RequestInit = {}) =>
  fetch(`${SUPABASE_URL}/rest/v1/${chemin}`, {
    ...init,
    headers: { apikey: SERVICE_KEY, Authorization: `Bearer ${SERVICE_KEY}`, 'Content-Type': 'application/json', ...(init.headers || {}) },
    signal: AbortSignal.timeout(10000),
  })

// v14 — journalise /api/1.0/transactions. L'API n'en garde que 7 jours ; le journal garde tout.
// C'est ce journal qui permet de DEDUIRE les plans d'achat recurrents sans que Chachou saisisse
// quoi que ce soit. Ne bloque jamais la lecture des soldes, mais ne se tait pas non plus :
// aucun .catch vide sur une ecriture (regle du 31/08) — le resultat est renvoye a l'appelant.
async function journaliserTransactions(key: CryptoKey): Promise<any> {
  try {
    if (!SUPABASE_URL || !SERVICE_KEY) return { fait: false, motif: 'secrets absents' }
    const r = await signedGet('/api/1.0/transactions', '', key)
    if (r.status !== 200) return { fait: false, motif: `transactions HTTP ${r.status}` }
    const data = (r.body as any)?.data
    if (!Array.isArray(data)) return { fait: false, motif: 'corps inattendu' }
    const w = await sb('rpc/alc_ingest_transactions', { method: 'POST', body: JSON.stringify({ p_data: data }) })
    if (!w.ok) return { fait: false, motif: `ingest HTTP ${w.status}`, detail: (await w.text()).slice(0, 200) }
    return { fait: true, recues: data.length, ecrites: await w.json() }
  } catch (e) { return { fait: false, motif: String(e).slice(0, 160) } }
}

// v14 — le plan d'achats recurrents, DEDUIT par la vue. Rien n'est saisi, rien n'est ecrit ici.
// NE LEVE JAMAIS : si la vue est injoignable ou ne detecte rien, on renvoie '' et le texte
// redevient exactement celui de la v12.
async function achatsRecurrentsTexte(): Promise<string> {
  try {
    if (!SUPABASE_URL || !SERVICE_KEY) return ''
    const r = await sb('v_alc_achats_recurrents_detectes?actif=is.true&select=devises,montant,devise_montant,frequence,occurrences,derniere,prochain_attendu')
    if (!r.ok) return ''
    const rows = await r.json()
    if (!Array.isArray(rows) || rows.length === 0) return ''
    const phrases: string[] = []
    for (const p of rows) {
      const devises = Array.isArray(p?.devises) ? p.devises.map((d: any) => String(d).toUpperCase()) : []
      if (devises.length === 0) continue
      const montant = num(p?.montant)
      const dev = String(p?.devise_montant || '').toUpperCase()
      const freq = String(p?.frequence || 'periodique')
      let t = `${devises.join(', ')} rachetes automatiquement par Revolut`
      if (montant > 0 && dev) t += ` (${montant} ${dev} au total par prelevement, ${freq}, repartis entre ces ${devises.length} lignes)`
      else t += ` (${freq})`
      if (p?.occurrences) t += `, ${p.occurrences} prelevements observes`
      if (p?.prochain_attendu) t += `, prochain attendu le ${p.prochain_attendu}`
      phrases.push(t)
    }
    if (phrases.length === 0) return ''
    return ` || ACHATS RECURRENTS PROGRAMMES PAR LE PROPRIETAIRE, HORS ROBOT, DEDUITS DE L'HISTORIQUE (Revolut les execute seul, tu n'en es ni l'auteur ni le destinataire ; c'est une information de contexte, pas une consigne): ${phrases.join(' ; ')}`
  } catch { return '' }
}

// v15 — le prix de revient, UNIQUEMENT pour les lignes dont le journal couvre tout.
// NE LEVE JAMAIS. Une ligne partielle n'apparait pas : mieux vaut rien qu'un chiffre faux.
async function prixRevientTexte(): Promise<string> {
  try {
    if (!SUPABASE_URL || !SERVICE_KEY) return ''
    const r = await sb('v_alc_prix_revient?complet=is.true&select=devise,cout_usd,qte_nette_journal,prix_revient_moyen_usd,plus_value_pct,premier_achat&order=cout_usd.desc')
    if (!r.ok) return ''
    const rows = await r.json()
    if (!Array.isArray(rows) || rows.length === 0) return ''
    const parts = rows.map((x: any) => {
      const pv = x?.plus_value_pct
      const signe = pv == null ? '' : `, ${Number(pv) > 0 ? '+' : ''}${pv}% par rapport a ton prix d achat`
      const jour = x?.premier_achat ? String(x.premier_achat).slice(0, 10) : null
      return `${String(x.devise).toUpperCase()}: paye ${num(x.cout_usd).toFixed(2)}$ au total`
        + (jour ? ` depuis le ${jour}` : '')
        + `, prix de revient moyen ${x.prix_revient_moyen_usd}$${signe}`
    })
    return ` || PRIX DE REVIENT MESURE (uniquement les lignes dont l historique d achat est complet ; les autres lignes n ont PAS de prix de revient connu, n en invente aucun): ${parts.join(' | ')}`
  } catch { return '' }
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: cors })
  try {
    if (!API_KEY || !PRIVATE_PEM) return new Response(JSON.stringify({ ok: false, error: 'Secrets manquants' }), { status: 500, headers: { ...cors, 'Content-Type': 'application/json' } })
    let key: CryptoKey
    try { key = await importKey() } catch (e) { return new Response(JSON.stringify({ ok: false, error: 'importKey a echoue', detail: String(e) }), { status: 200, headers: { ...cors, 'Content-Type': 'application/json' } }) }

    const body = await req.json().catch(() => ({}))
    if (body && typeof body.raw === 'string' && body.raw.startsWith('/api/')) {
      const r = await signedGet(body.raw, typeof body.query === 'string' ? body.query : '', key)
      return new Response(JSON.stringify({ ok: true, mode: 'brut', chemin: body.raw, status: r.status, corps: r.body }), { headers: { ...cors, 'Content-Type': 'application/json' } })
    }
    if (body && body.probe === true) {
      const out: any[] = []
      for (const p of CHEMINS) {
        try {
          const r = await signedGet(p, '', key)
          const t = typeof r.body === 'string' ? r.body : JSON.stringify(r.body)
          out.push({ chemin: p, status: r.status, taille: t ? t.length : 0, apercu: t ? t.slice(0, 220) : null })
        } catch (e) { out.push({ chemin: p, status: null, erreur: String(e).slice(0, 120) }) }
      }
      return new Response(JSON.stringify({ ok: true, mode: 'sonde', resultats: out }), { headers: { ...cors, 'Content-Type': 'application/json' } })
    }

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

    // --- v12 : la valeur en dollars, mesuree, jamais calculee par l'agent ---
    const px = await prixParDevise()
    const val = (dev: string, q: number) => {
      const D = String(dev).toUpperCase()
      if (D === 'USD') return q
      const p = px[D]
      return p && p > 0 ? q * p : NaN
    }
    let total = 0, valeurCash = 0, valeurStake = 0
    for (const b of clean) {
      const v = val(b.devise, num(b.disponible) + num(b.stake))
      if (Number.isFinite(v)) total += v
      if (isCash(b)) { const c = val(b.devise, num(b.disponible)); if (Number.isFinite(c)) valeurCash += c }
      const s = val(b.devise, num(b.stake)); if (Number.isFinite(s)) valeurStake += s
    }
    const cashUSD = num((usd[0] || {}).disponible)
    const pctCash = total > 0 ? (cashUSD / total) * 100 : 0
    const prixDispo = Object.keys(px).length > 0 && total > 0

    // Une ligne = QUANTITE (valeur$, poids%). Triees par valeur decroissante : les lignes qui
    // pesent vraiment arrivent en premier, au lieu de l'ordre arbitraire de l'API.
    const ligne = (b: any, q: number) => {
      const v = val(b.devise, q)
      if (!prixDispo || !Number.isFinite(v)) return `${b.devise}=${q}`
      return `${b.devise}=${q} (${d2(v)}$, ${d2((v / total) * 100)}%)`
    }
    const parValeur = (q: (b: any) => number) => (a: any, b: any) => {
      const va = val(a.devise, q(a)), vb = val(b.devise, q(b))
      return (Number.isFinite(vb) ? vb : -1) - (Number.isFinite(va) ? va : -1)
    }
    const qDispo = (b: any) => num(b.disponible)
    const qStake = (b: any) => num(b.stake)
    const fmtD = (b: any) => ligne(b, qDispo(b))
    const fmtS = (b: any) => ligne(b, qStake(b))
    const usdTxt = usd.length ? usd.map((b: any) => `${b.devise}=${b.disponible}`).join(' , ') : 'USD=0'

    const entete = prixDispo
      ? `PORTEFEUILLE (valorise au prix du marche, tu n'as AUCUN calcul a refaire): total=${d2(total)}$ | cash USD=${d2(cashUSD)}$ soit ${d2(pctCash)}% du portefeuille | investi=${d2(total - cashUSD)}$ | en stake=${d2(valeurStake)}$ | ${clean.length} lignes || `
      : ''
    // Le journal d'abord (il alimente la detection), la phrase ensuite.
    const journal = await journaliserTransactions(key)
    const recurrents = await achatsRecurrentsTexte()
    const revient = await prixRevientTexte()
    const soldes_texte = `${entete}POUVOIR D'ACHAT USD (SEUL cash utilisable pour ACHETER une paire -USD): ${usdTxt} || AUTRES DEVISES CASH (NON utilisables comme pouvoir d'achat pour les paires -USD -- ne PAS les compter pour un achat -USD): ${autresCash.length ? autresCash.map(fmtD).join(' , ') : 'aucune'} || POSITIONS LIQUIDES (vendables, de la plus grosse a la plus petite): ${liquide.length ? liquide.slice().sort(parValeur(qDispo)).map(fmtD).join(' | ') : 'aucune'} || EN STAKE (VERROUILLE - NON vendable tant que non destake): ${stake.length ? stake.slice().sort(parValeur(qStake)).map(fmtS).join(' | ') : 'aucun'}${revient}${recurrents}`

    const portefeuille = prixDispo
      ? { total_usd: Number(d2(total)), cash_usd: Number(d2(cashUSD)), pct_cash: Number(d2(pctCash)),
          investi_usd: Number(d2(total - cashUSD)), stake_usd: Number(d2(valeurStake)), nb_lignes: clean.length }
      : null

    return new Response(JSON.stringify({ ok: true, count: clean.length, soldes: clean, soldes_texte, portefeuille, journal }), { headers: { ...cors, 'Content-Type': 'application/json' } })
  } catch (e) {
    return new Response(JSON.stringify({ ok: false, error: String(e) }), { status: 500, headers: { ...cors, 'Content-Type': 'application/json' } })
  }
})
