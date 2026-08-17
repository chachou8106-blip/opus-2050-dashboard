// oracle-inbox v16 — canal Chachou <-> robot.
// suivi : traders, perf, perf_avancee, stats_indice, mensuel, rendements, periodes, equity, comparaison,
//         sharpe, contexte, fx, gains (v_gains_traders), + alc_virtuel + marees_virtuel (positions forex)
//         + live_crypto (valorisation crypto en direct 24/7, week-end compris — 100% lecture).
// journal (défaut) : journal (historique étendu), problemes, rappels (pour le calendrier).

const SUPABASE_URL = Deno.env.get('SUPABASE_URL')!
const SRK = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
const cors = { 'Access-Control-Allow-Origin': '*', 'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type', 'Access-Control-Allow-Methods': 'POST, OPTIONS' }
const json = (d: unknown, s = 200) => new Response(JSON.stringify(d), { status: s, headers: { ...cors, 'Content-Type': 'application/json' } })

async function sb(path: string, init?: RequestInit) {
  const r = await fetch(`${SUPABASE_URL}/rest/v1/${path}`, { ...init, headers: { apikey: SRK, Authorization: `Bearer ${SRK}`, 'Content-Type': 'application/json', ...(init?.headers || {}) } })
  try { return { ok: r.ok, status: r.status, body: await r.json() } } catch { return { ok: r.ok, status: r.status, body: null } }
}
const arr = (b: any) => Array.isArray(b) ? b : []

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: cors })
  try {
    const b = await req.json().catch(() => ({}))
    const action = b.action || 'journal'

    if (action === 'report') {
      const message = (b.message || '').toString().trim()
      if (!message) return json({ ok: false, error: 'message vide' })
      const ins = await sb('oracle_problemes', { method: 'POST', headers: { Prefer: 'return=representation' }, body: JSON.stringify({ message, source: b.source || 'telephone' }) })
      return json({ ok: ins.ok, enregistre: ins.ok, probleme: Array.isArray(ins.body) ? ins.body[0] : ins.body })
    }

    if (action === 'suivi') {
      const dash = await sb('oracle_dashboard?select=snapshot_at,archimages&order=snapshot_at.desc&limit=1')
      const row = Array.isArray(dash.body) ? dash.body[0] : null
      let traders: any[] = []
      if (row && row.archimages && typeof row.archimages === 'object') traders = Object.entries(row.archimages).map(([nom, v]: any) => ({ nom, ...(v || {}) }))
      const perf = await sb('v_perf_resume?select=trader,rendement_pct,drawdown_max_pct,reussite_pct,statut,periode')
      const av = await sb('v_perf_avancee?select=serie,volatilite,sortino,calmar,drawdown_max,meilleur_mois,pire_mois,pct_mois_positifs')
      const si = await sb('v_stats_indice?select=serie,correlation,beta,alpha_annualise')
      const men = await sb('v_rendements_mensuels?select=serie,mois,rendement_pct&order=serie.asc,mois.asc')
      const rp = await sb('v_rendements_periodes?select=serie,granularite,periode,rendement_pct&serie=in.(OPUS,SYL,JU,GIL,ALCHIMISTE,MAREES)&order=serie.asc,periode.asc')
      const eqr = await sb('v_equity_points?select=trader,ts,equity&order=trader.asc,ts.asc')
      const equity: Record<string, any[]> = {}
      for (const p of arr(eqr.body)) { (equity[p.trader] = equity[p.trader] || []).push({ t: p.ts, v: Number(p.equity) }) }
      for (const k of Object.keys(equity)) { if (equity[k].length > 90) equity[k] = equity[k].slice(-90) }
      const cmp = await sb('v_comparaison?select=serie,jour,ret&order=serie.asc,jour.asc')
      const comparaison: Record<string, any[]> = {}
      for (const p of arr(cmp.body)) { (comparaison[p.serie] = comparaison[p.serie] || []).push({ j: p.jour, r: Number(p.ret) }) }
      const shr = await sb('v_sharpe?select=serie,sharpe')
      const sharpe: Record<string, number> = {}
      for (const p of arr(shr.body)) sharpe[p.serie] = Number(p.sharpe)
      const avance: Record<string, any> = {}; for (const p of arr(av.body)) avance[p.serie] = p
      const stats: Record<string, any> = {}; for (const p of arr(si.body)) stats[p.serie] = p
      const mensuel: Record<string, any[]> = {}; for (const p of arr(men.body)) { (mensuel[p.serie] = mensuel[p.serie] || []).push({ mois: p.mois, r: Number(p.rendement_pct) }) }
      const ctx = await sb('oracle_contexte?select=section,cle,valeur&order=section.asc,id.asc')
      // Taux de change live (pour afficher les gains en euros)
      const fxr = await sb('price_history?symbol=in.(EUR-USD,GBP-USD)&interval=eq.1h&select=symbol,close,ts&order=ts.desc&limit=60')
      const fx: Record<string, number> = {}
      for (const p of arr(fxr.body)) { const k = p.symbol === 'EUR-USD' ? 'EURUSD' : p.symbol === 'GBP-USD' ? 'GBPUSD' : null; if (k && !(k in fx)) fx[k] = Number(p.close) }
      // Gains par trader (jour/semaine/mois/annee) en % + USD + EUR
      const gns = await sb('v_gains_traders?select=serie,label,ordre,horizon,gain_pct,gain_usd,gain_eur&order=ordre.asc')
      // Portefeuille virtuel de l'Alchimiste
      const avr = await sb('v_alc_virtuel_resume?select=*')
      const avj = await sb('v_alc_virtuel_jour?select=jour,n_trades,gagnants,wr_pct,ret_pct,cumul_pct&order=jour.asc')
      const avp = await sb('v_alc_virtuel_positions?select=paire,side,prix_entree,montant,prix_actuel,unreal_pct&order=montant.desc')
      const alc_virtuel = { resume: (arr(avr.body)[0] || null), jours: arr(avj.body), positions: arr(avp.body) }
      // Marées — portefeuille virtuel forex (positions ouvertes valorisées au dernier cours)
      const mvr = await sb('v_marees_virtuel_resume?select=*')
      const mvp = await sb('v_marees_virtuel_positions?select=paire,side,prix_entree,prix_actuel,unreal_pct,montant,tp_pct,sl_pct,age_h&order=unreal_pct.desc')
      const marees_virtuel = { resume: (arr(mvr.body)[0] || null), positions: arr(mvp.body) }
      // Valorisation crypto EN DIRECT (24/7, week-end compris) — recalculée à la lecture depuis price_history.
      // Seule la crypto bouge quand le scénario Make est éteint ; actions/ETF/forex restent au dernier close.
      const lcr = await sb('v_live_crypto_resume?select=archimage,n_crypto,tout_live,dernier_cours,valo_crypto_usd,valo_crypto_eur,pnl_latent_usd&order=valo_crypto_usd.desc')
      const lcp = await sb('v_live_crypto_positions?select=archimage,ticker,qty,prix_entree,prix_actuel,valo_usd,unreal_pct,unreal_usd,live_ts&order=valo_usd.desc')
      const live_crypto = { resume: arr(lcr.body), positions: arr(lcp.body) }
      return json({ ok: true, snapshot_at: row?.snapshot_at || null, traders, perf: arr(perf.body), avance, stats, mensuel, rendements: arr(rp.body), equity, comparaison, sharpe, contexte: arr(ctx.body), fx, gains: arr(gns.body), alc_virtuel, marees_virtuel, live_crypto })
    }

    const jrn = await sb('oracle_journal?select=jour,resume,snapshot,problemes_traites,created_at&order=created_at.desc&limit=150')
    const prb = await sb('oracle_problemes?select=id,created_at,message,statut,diagnostic,recommandation&order=created_at.desc&limit=100')
    const rpl = await sb('oracle_rappels?select=id,date_rappel,creneau,titre,message,done&order=date_rappel.asc')
    return json({ ok: true, journal: arr(jrn.body), problemes: arr(prb.body), rappels: arr(rpl.body) })
  } catch (e) {
    return json({ ok: false, error: String(e) })
  }
})
