// oracle-inbox v24 — SEPARATION DE L'ALCHIMISTE REEL ET DU VIRTUEL. Le meme identifiant
// 'ALCHIMISTE' designait le portefeuille VIRTUEL dans v_comparaison (et ses 5 vues derivees)
// et le compte REEL dans v_equity_points. Les deux series s'appellent desormais ALC_VIRT et
// ALC_REEL, et plus rien ne s'appelle 'ALCHIMISTE' tout court.
// oracle-inbox v23 — un Sharpe absent n'est plus transmis comme 0. Voir le commentaire
// au-dessus de la construction de la table `sharpe`.
// oracle-inbox v22 — transmet la DUREE et la NATURE de chaque serie de performance.
// v_perf_resume : + depuis, jours, nature (simulation / virtuel). Sans ces colonnes, le +17,42 %
// de l'Alchimiste (7 jours de portefeuille VIRTUEL) s'affichait a cote du +4,56 % de JU
// (54 jours de simulation) comme s'ils etaient comparables.
// v_gains_traders : + mesure (usd / pct). Les series virtuelles tradent des montants symboliques :
// leur gain vaut 1 € la ou les comptes Alpaca font 44 000 €.
// oracle-inbox v21 — v_equity_points declare son unite (usd / pct) et son rendement ; le bloc
// suivi les transmet via equityUnite. Voir le commentaire au-dessus de la requete.
// oracle-inbox v20 — canal Chachou <-> robot.
// [19/08] PAGINATION : PostgREST plafonne à 1000 lignes côté serveur (un &limit= plus grand ne sert
// à rien). v_comparaison (1204 lignes) perdait donc URTH/USO/XRP-USD et amputait SYL de moitié.
// v_comparaison, v_equity_points et v_rendements_periodes passent par sbAll() qui pagine.
// suivi : traders, perf, perf_avancee, stats_indice, mensuel, rendements, periodes, equity, comparaison,
//         sharpe, contexte, fx, gains (v_gains_traders), + alc_virtuel + marees_virtuel (positions forex)
//         + live_crypto (crypto des Sages en direct 24/7) + alc_reel_live (Alchimiste RÉEL Revolut X
//         valorisé en direct au dernier cours) + vigie (santé du Collège : PANNE/FIGÉ par composant).
//         Tout en 100% lecture.
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

// PostgREST plafonne les réponses à 1000 lignes CÔTÉ SERVEUR : un &limit= plus grand ne change rien.
// v_comparaison compte 1204 lignes -> URTH (MSCI World), USO (Pétrole) et XRP-USD ne remontaient pas du
// tout et la courbe de SYL était coupée en deux. On pagine donc explicitement. [19/08]
async function sbAll(path: string, pageSize = 1000): Promise<any[]> {
  const out: any[] = []
  for (let off = 0; off <= 50000; off += pageSize) {
    const sep = path.includes('?') ? '&' : '?'
    const r = await sb(`${path}${sep}offset=${off}&limit=${pageSize}`)
    const rows = arr(r.body)
    out.push(...rows)
    if (rows.length < pageSize) break
  }
  return out
}

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
      const perf = await sb('v_perf_resume?select=trader,rendement_pct,drawdown_max_pct,reussite_pct,statut,periode,depuis,jours,nature')
      const av = await sb('v_perf_avancee?select=serie,volatilite,sortino,calmar,drawdown_max,meilleur_mois,pire_mois,pct_mois_positifs')
      const si = await sb('v_stats_indice?select=serie,correlation,beta,alpha_annualise')
      const men = await sb('v_rendements_mensuels?select=serie,mois,rendement_pct&order=serie.asc,mois.asc&limit=1000')
      const rpRows = await sbAll('v_rendements_periodes?select=serie,granularite,periode,rendement_pct&serie=in.(OPUS,SYL,JU,GIL,ALC_VIRT,ALC_REEL,MAREES)&order=serie.asc,periode.asc')
      // v21 : v_equity_points melangeait trois unites dans sa colonne equity (un GAIN en $ pour
      // les archimages, une VALEUR en $ pour l'Alchimiste, un nombre sans unite pour Marees) et
      // la console l'affichait partout comme « Valeur $ ». La vue declare desormais son unite ;
      // on la transmet telle quelle pour que la page trace chaque agent dans la sienne au lieu
      // de pretendre que Marees « n'a pas encore de courbe » alors qu'il a 39 points.
      const eqRows = await sbAll('v_equity_points?select=trader,ts,equity,unite,rendement_pct&order=trader.asc,ts.asc')
      const equity: Record<string, any[]> = {}
      const equityUnite: Record<string, string> = {}
      for (const p of eqRows) {
        equityUnite[p.trader] = p.unite || 'usd'
        ;(equity[p.trader] = equity[p.trader] || []).push({ t: p.ts, v: Number(p.equity), pct: p.rendement_pct == null ? null : Number(p.rendement_pct) })
      }
      for (const k of Object.keys(equity)) { if (equity[k].length > 90) equity[k] = equity[k].slice(-90) }
      const cmpRows = await sbAll('v_comparaison?select=serie,jour,ret&order=serie.asc,jour.asc')
      const comparaison: Record<string, any[]> = {}
      for (const p of cmpRows) { (comparaison[p.serie] = comparaison[p.serie] || []).push({ j: p.jour, r: Number(p.ret) }) }
      const shr = await sb('v_sharpe?select=serie,sharpe')
      // v_sharpe renvoie NULL quand la serie est trop courte pour qu'un Sharpe ait un sens
      // (ALCHIMISTE 6 observations, MAREES 5 ; le seuil est de 20). Number(null) vaut 0 :
      // la console affichait donc « 0 », un chiffre qui a l'air d'une mesure. On garde null,
      // et l'ecran affiche « — ».
      const sharpe: Record<string, number | null> = {}
      for (const p of arr(shr.body)) sharpe[p.serie] = (p.sharpe == null ? null : Number(p.sharpe))
      const avance: Record<string, any> = {}; for (const p of arr(av.body)) avance[p.serie] = p
      const stats: Record<string, any> = {}; for (const p of arr(si.body)) stats[p.serie] = p
      const mensuel: Record<string, any[]> = {}; for (const p of arr(men.body)) { (mensuel[p.serie] = mensuel[p.serie] || []).push({ mois: p.mois, r: Number(p.rendement_pct) }) }
      const ctx = await sb('oracle_contexte?select=section,cle,valeur&order=section.asc,id.asc')
      // Taux de change live (pour afficher les gains en euros)
      const fxr = await sb('price_history?symbol=in.(EUR-USD,GBP-USD)&interval=eq.1h&select=symbol,close,ts&order=ts.desc&limit=60')
      const fx: Record<string, number> = {}
      for (const p of arr(fxr.body)) { const k = p.symbol === 'EUR-USD' ? 'EURUSD' : p.symbol === 'GBP-USD' ? 'GBPUSD' : null; if (k && !(k in fx)) fx[k] = Number(p.close) }
      // Gains par trader (jour/semaine/mois/annee) en % + USD + EUR
      const gns = await sb('v_gains_traders?select=serie,label,ordre,horizon,gain_pct,gain_usd,gain_eur,mesure&order=ordre.asc')
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
      // Alchimiste RÉEL (Revolut X, argent réel) valorisé EN DIRECT au dernier cours — même principe que
      // le virtuel. On revalorise le dernier snapshot revolut_portfolio_daily coin par coin (47/49 + cash).
      const alr = await sb('v_alc_reel_live_resume?select=*')
      const alrp = await sb('v_alc_reel_live_positions?select=devise,qty,en_stake,valeur_snapshot_usd,prix_live,est_live,valeur_live_usd&order=valeur_live_usd.desc&limit=20')
      const alc_reel_live = { resume: (arr(alr.body)[0] || null), positions: arr(alrp.body) }
      // 🔭 LA VIGIE — santé du Collège : détecte un composant en PANNE (ne produit plus) ou FIGÉ
      // (même valeur en boucle). Recalculé toutes les 15 min par pg_cron (fonction vigie_scan).
      const vgr = await sb('v_vigie_resume?select=*')
      const vgd = await sb('v_vigie_detail?select=composant,categorie,etat,detail,derniere_sortie,run_auditee')
      const vigie = { resume: (arr(vgr.body)[0] || null), detail: arr(vgd.body) }
      return json({ ok: true, snapshot_at: row?.snapshot_at || null, traders, perf: arr(perf.body), avance, stats, mensuel, rendements: rpRows, equity, equityUnite, comparaison, sharpe, contexte: arr(ctx.body), fx, gains: arr(gns.body), alc_virtuel, marees_virtuel, live_crypto, alc_reel_live, vigie })
    }

    const jrn = await sb('oracle_journal?select=jour,resume,snapshot,problemes_traites,created_at&order=created_at.desc&limit=150')
    const prb = await sb('oracle_problemes?select=id,created_at,message,statut,diagnostic,recommandation&order=created_at.desc&limit=100')
    const rpl = await sb('oracle_rappels?select=id,date_rappel,creneau,titre,message,done&order=date_rappel.asc')
    return json({ ok: true, journal: arr(jrn.body), problemes: arr(prb.body), rappels: arr(rpl.body) })
  } catch (e) {
    return json({ ok: false, error: String(e) })
  }
})
