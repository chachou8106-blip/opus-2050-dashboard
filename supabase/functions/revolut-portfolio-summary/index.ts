// revolut-portfolio-summary v5 : point quotidien + post Discord.
// v5 : durcissement — le repli prix (v_dernier_prix) est borne (limit) et garde-fou Array.isArray,
//      pour ne JAMAIS crasher ("fallback is not iterable") si la vue repond lentement/en erreur.
// v4 : repli prix sur price_history (vue v_dernier_prix) quand le ticker Revolut X ne couvre pas une ligne.

const SUPABASE_URL = Deno.env.get('SUPABASE_URL')!
const SERVICE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
const DISCORD_WEBHOOK = Deno.env.get('DISCORD_CRYPTE_WEBHOOK') || ''
const cors = { 'Access-Control-Allow-Origin': '*', 'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type' }
const json = (d: unknown, s = 200) => new Response(JSON.stringify(d), { status: s, headers: { ...cors, 'Content-Type': 'application/json' } })
const CASH = ['USD', 'USDT', 'USDC', 'EUR', 'GBP']
const n = (x: any) => Number(x) || 0
const r2 = (x: number) => Math.round(x * 100) / 100
const q8 = (x: number) => Math.round(x * 1e8) / 1e8

async function callFn(slug: string): Promise<any> {
  const r = await fetch(`${SUPABASE_URL}/functions/v1/${slug}`, { method: 'POST', headers: { apikey: SERVICE_KEY, Authorization: `Bearer ${SERVICE_KEY}`, 'Content-Type': 'application/json' }, body: '{}' })
  try { return await r.json() } catch { return null }
}
async function sbGet(path: string): Promise<any> {
  try { const r = await fetch(`${SUPABASE_URL}/rest/v1/${path}`, { headers: { apikey: SERVICE_KEY, Authorization: `Bearer ${SERVICE_KEY}` } }); return await r.json() } catch { return null }
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: cors })
  try {
    const read = await callFn('revolut-x-read')
    const prices = await callFn('revolut-x-prices')
    if (!read?.ok) return json({ ok: false, error: 'lecture soldes echouee', read })
    const pmap: Record<string, number> = {}
    // 1) source primaire : ticker Revolut X (le plus frais pour les paires tradees)
    for (const p of (prices?.prix || [])) {
      const base = String(p.paire).replace('-USD', '').replace('/USD', '').toUpperCase()
      const px = n(p.mid) || n(p.last) || n(p.ask) || n(p.bid)
      if (base && px) pmap[base] = px
    }
    // 2) repli : dernier close de price_history (borne + garde-fou anti-crash)
    const fbRaw = await sbGet('v_dernier_prix?select=base,prix&limit=2000')
    const fallback: any[] = Array.isArray(fbRaw) ? fbRaw : []
    let repares = 0
    for (const f of fallback) {
      const base = String(f.base).toUpperCase()
      if (base && !pmap[base] && n(f.prix) > 0) { pmap[base] = n(f.prix); repares++ }
    }
    let cash_usd = 0, liquide_usd = 0, stake_usd = 0
    const sansPrix: string[] = []
    const detail: any[] = []
    for (const b of (read.soldes || [])) {
      const dev = String(b.devise).toUpperCase()
      const dispo = n(b.disponible), stake = n(b.stake), reserve = n(b.reserve)
      const qty = dispo + stake + reserve
      let val = 0
      if (CASH.includes(dev)) { val = qty; cash_usd += qty }
      else { const px = pmap[dev] || 0; if (!px && qty > 0) sansPrix.push(dev); val = qty * px; liquide_usd += dispo * px; stake_usd += stake * px }
      detail.push({ devise: dev, qty: q8(qty), dispo: q8(dispo), stake: q8(stake), prix_usd: pmap[dev] ? r2(pmap[dev]) : (CASH.includes(dev) ? 1 : null), valeur_usd: r2(val) })
    }
    const total = cash_usd + liquide_usd + stake_usd
    detail.sort((a, b) => b.valeur_usd - a.valeur_usd)
    const top = detail.filter(d => d.valeur_usd >= 1).slice(0, 12).map(d => `${d.devise} ${d.valeur_usd}$`).join(' | ')
    const poussiere = detail.filter(d => d.valeur_usd < 1).length
    const alerte = sansPrix.length ? `\n[!] Sans prix (a sourcer): ${sansPrix.join(', ')}` : ''
    const resume = `POINT PORTEFEUILLE REVOLUT X\nValeur totale estimee: ${r2(total)}$\n- Cash: ${r2(cash_usd)}$\n- Positions liquides: ${r2(liquide_usd)}$\n- En stake (verrouille): ${r2(stake_usd)}$\nPrincipales lignes: ${top}\n(+ ${poussiere} micro-lignes < 1$)${alerte}`
    await fetch(`${SUPABASE_URL}/rest/v1/revolut_portfolio_daily`, { method: 'POST', headers: { apikey: SERVICE_KEY, Authorization: `Bearer ${SERVICE_KEY}`, 'Content-Type': 'application/json', Prefer: 'return=minimal' }, body: JSON.stringify({ total_usd: r2(total), cash_usd: r2(cash_usd), liquide_usd: r2(liquide_usd), stake_usd: r2(stake_usd), nb_lignes: detail.length, resume_texte: resume, detail }) })
    let discord = 'non configure'
    if (DISCORD_WEBHOOK) {
      try { const dr = await fetch(DISCORD_WEBHOOK, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ content: '**Point quotidien - ta crypte JU (Revolut X)**\n' + resume }) }); discord = dr.ok ? 'poste' : ('err ' + dr.status) } catch (e) { discord = 'err ' + String(e) }
    }
    return json({ ok: true, total_usd: r2(total), cash_usd: r2(cash_usd), liquide_usd: r2(liquide_usd), stake_usd: r2(stake_usd), prix_repares: repares, sans_prix: sansPrix, discord, resume })
  } catch (e: any) {
    return json({ ok: false, error: String(e?.message || e) })
  }
})
