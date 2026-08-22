// oracle-tests v12 — DRAWDOWN. La porte « aucun drawdown au-dessus de 5 % » de l'onglet Réel lisait
// oracle_brain_state.current_drawdown, colonne figée : GIL y restait à 6,26 %, soit exactement son
// drawdown MAXIMUM historique. La colonne alimentée par le broker, alpaca_drawdown_from_peak, disait
// 0,59 %. L'onglet Collège lisait déjà la bonne (dashboard_snapshot fait le coalesce), l'onglet Réel la
// mauvaise : le même drawdown s'affichait 6,26 % ici et 0,59 % là, et bloquait le verdict à 2/4.
// hero, archimage_detail et learning renvoient désormais un current_drawdown déjà résolu
// (alpaca_drawdown_from_peak si présent, sinon current_drawdown) et exposent les deux sources brutes.
// alchimiste : rendement_pct porte le cumul journalier pondéré (17,4 %) ; le composé trade par trade
// (59,7 %, qui suppose 100 % du capital sur chaque trade) est renommé rendement_compose_theorique_pct.
// positions des archimages : les résidus Alpaca (prix d'entrée négatif) sont écartés.
// v11 — positions : le limit=60 + tri market_value.desc masquait TOUTES les positions
// vendeuses (valeur negative, donc classees en dernier). Passe a 300 + side expose. Idem archimage_detail
// (limit 20 -> 60). Sinon identique v10. [19/08/2026]

const cors = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}
const SUPABASE_URL = Deno.env.get('SUPABASE_URL') || 'https://smddzybxebwhfnitxuyp.supabase.co'
const SRK = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') || ''

async function rpc(fn: string, args: any = {}): Promise<any> {
  const r = await fetch(`${SUPABASE_URL}/rest/v1/rpc/${fn}`, {
    method: 'POST',
    headers: { apikey: SRK, Authorization: `Bearer ${SRK}`, 'Content-Type': 'application/json' },
    body: JSON.stringify(args),
    signal: AbortSignal.timeout(60000)
  })
  if (!r.ok) return { error: `${fn}: ${r.status} ${(await r.text()).slice(0,200)}` }
  return await r.json()
}
async function rest(path: string, init: any = {}): Promise<any> {
  const r = await fetch(`${SUPABASE_URL}/rest/v1/${path}`, {
    ...init,
    headers: { apikey: SRK, Authorization: `Bearer ${SRK}`, 'Content-Type': 'application/json', ...(init.headers || {}) },
    signal: AbortSignal.timeout(30000)
  })
  if (init.method === 'POST') return { ok: r.ok, status: r.status, txt: r.ok ? null : (await r.text()).slice(0,150) }
  if (!r.ok) return { error: `${path}: ${r.status}` }
  return await r.json()
}
async function compte(table: string): Promise<number> {
  try {
    const r = await fetch(`${SUPABASE_URL}/rest/v1/${table}?select=*`, {
      method: 'HEAD',
      headers: { apikey: SRK, Authorization: `Bearer ${SRK}`, Prefer: 'count=exact' },
      signal: AbortSignal.timeout(10000)
    })
    return Number((r.headers.get('content-range') || '').split('/')[1]) || 0
  } catch (_e) { return 0 }
}
const tronque = (s: any, n = 90) => (s == null ? null : (String(s).length > n ? String(s).slice(0, n) + '…' : String(s)))

// Drawdown courant qui fait foi : celui calcule par le broker depuis le plus haut du compte.
// current_drawdown est une colonne applicative qui peut rester collee sur le drawdown maximum
// (cas de GIL, fige a 6,26 %) et n'est donc utilisee qu'a defaut. On conserve les deux sources
// brutes a cote pour que l'ecart reste verifiable depuis la console.
function ddResolu(b: any) {
  const alpaca = b?.alpaca_drawdown_from_peak
  return {
    ...b,
    current_drawdown: (alpaca == null ? b?.current_drawdown : alpaca),
    dd_source: (alpaca == null ? 'current_drawdown' : 'alpaca_drawdown_from_peak'),
    dd_applicatif: b?.current_drawdown,
    dd_broker: alpaca ?? null
  }
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: cors })
  try {
    if (!SRK) return new Response(JSON.stringify({ error: 'service key manquante' }), { status: 500, headers: { ...cors, 'Content-Type': 'application/json' } })
    const body = await req.json().catch(() => ({}))
    const action = String(body.action || '')
    const p = body.params || {}
    let data: any
    switch (action) {
      case 'hero': {
        const [brainsRaw, spyRow, leadsCount] = await Promise.all([
          rest('oracle_brain_state?archimage=in.(JU,SYL,GIL)&select=archimage,cumulative_pnl,win_rate,alpaca_portfolio_value,current_drawdown,alpaca_drawdown_from_peak'),
          rpc('equity_series'),
          compte('oracle_leads')
        ])
        const brains = Array.isArray(brainsRaw) ? brainsRaw.map(ddResolu) : brainsRaw
        let gain = 0, wr = 0, valeur = 0
        if (Array.isArray(brains)) for (const b of brains) { gain += Number(b.cumulative_pnl)||0; wr += Number(b.win_rate)||0; valeur += Number(b.alpaca_portfolio_value)||0 }
        const spy = (spyRow && spyRow.spy && spyRow.spy.length) ? spyRow.spy[spyRow.spy.length-1].pct : null
        data = {
          gain_total: Math.round(gain),
          valeur_totale: Math.round(valeur),
          win_rate_moyen: Array.isArray(brains) && brains.length ? Math.round(wr/brains.length*1000)/10 : null,
          spy_periode_pct: spy,
          alpha_moyen_pct: (spy != null && valeur > 0) ? Math.round((gain/30000 - spy)*100)/100 : null,
          jours: Math.max(1, Math.round((Date.now() - new Date('2026-06-05').getTime())/86400000)),
          leads_count: leadsCount,
          brains
        }
        break }
      case 'alchimiste': {
        const [stats, cfg, bt, virt] = await Promise.all([
          rpc('alc_stats'),
          rest('ju_crypte_config?key=in.(kill_switch,tp_optimal_backtest,sl_optimal_backtest,max_daily_usd)&select=key,value'),
          rest('oracle_backtest_cache?kind=eq.alchimiste&select=tp_pct,sl_pct,win_rate,avg_ret_pct,total_ret_pct&order=total_ret_pct.desc&limit=1'),
          rest('v_alc_virtuel_resume?select=cumul_pct')
        ])
        const conf: any = {}
        if (Array.isArray(cfg)) for (const c of cfg) conf[c.key] = c.value
        const st: any = (stats && !stats.error ? { ...stats } : {})
        const composeTheorique = st.rendement_compose_pct ?? null
        delete st.rendement_compose_pct   // retire du flux : plus personne ne peut l'afficher par megarde
        data = {
          ...st,
          // Deux rendements coexistaient dans la console pour le MEME portefeuille :
          // alc_stats.rendement_compose_pct (59,7 %) compose trade par trade, comme si chaque
          // trade mobilisait 100 % du capital — impossible ; v_alc_virtuel_jour.cumul_pct
          // (17,4 %) compose jour par jour, pondere par les montants reellement engages.
          // rendement_pct porte desormais le seul chiffre defendable, et l'autre est renomme
          // en clair pour qu'on ne puisse plus le prendre pour une performance.
          rendement_pct: (Array.isArray(virt) && virt[0] ? virt[0].cumul_pct : null),
          rendement_compose_theorique_pct: composeTheorique,
          kill_switch: conf.kill_switch || null,
          tp_pct: conf.tp_optimal_backtest || null, sl_pct: conf.sl_optimal_backtest || null,
          plafond_jour_usd: conf.max_daily_usd || null,
          backtest: Array.isArray(bt) && bt[0] ? bt[0] : null
        }
        break }
      case 'marees':
        data = await rpc('marees_resume'); break
      case 'runs': {
        const rows = await rest('oracle_college_runs?select=run_at,market_phase,orders_count,orders_buy,orders_sell,status&order=run_at.desc&limit=40')
        data = rows; break }
      case 'equity':
        data = await rpc('equity_series'); break
      case 'positions': {
        // limite 300 (et tri par |valeur|) : avec limit=60 + tri sur market_value desc, les positions
        // VENDEUSES (market_value negatif) tombaient toutes hors de la fenetre -> invisibles en console. [19/08]
        const rows = await rest('oracle_positions_live?select=archimage,ticker,side,qty,market_value,unrealized_pl,unrealized_pl_pct,days_held&order=archimage.asc,market_value.desc.nullslast&limit=300')
        data = Array.isArray(rows) ? rows.map((r: any) => ({ ...r, market_value: Math.round(r.market_value), unrealized_pl: Math.round(r.unrealized_pl) })) : rows
        break }
      case 'lead': {
        const email = String(p.email || '').trim().toLowerCase()
        const source = tronque(String(p.source || 'pdf'), 40)
        if (!/^[^@\s]+@[^@\s]+\.[^@\s]{2,}$/.test(email) || email.length > 120) { data = { ok: false, raison: 'email invalide' }; break }
        const ins = await rest('oracle_leads', { method: 'POST', headers: { Prefer: 'resolution=ignore-duplicates,return=minimal' }, body: JSON.stringify({ email, source }) })
        data = { ok: ins.ok || ins.status === 409, merci: true }
        break }
      case 'sages':
        data = await rpc('evaluate_sages', { p_hold_hours: Number(p.hold_hours) || 24, p_seuil: Number(p.seuil) || 0.5 }); break
      case 'sage_detail': {
        const s = String(p.sage || '')
        if (!['Macro','Technique','Flash','Risque','Memoire'].includes(s)) { data = { error: 'sage inconnu' }; break }
        const d = await rpc('sage_detail', { p_sage: s })
        if (d && Array.isArray(d.historique)) d.historique = d.historique.map((h: any) => ({ ...h, extrait: tronque(h.extrait, 220), signal: tronque(h.signal, 60) }))
        data = d
        break }
      case 'coaching':
        data = await rpc('sages_coaching'); break
      case 'bt_alchimiste': {
        const rows = await rest('oracle_backtest_cache?kind=eq.alchimiste&select=tp_pct,sl_pct,trades,win_rate,avg_ret_pct,total_ret_pct,computed_at&order=total_ret_pct.desc&limit=48')
        data = Array.isArray(rows) && rows.length ? rows : { error: 'cache vide — relance refresh_backtest_cache()' }
        break }
      case 'bt_exits': {
        const rows = await rest('oracle_backtest_cache?kind=eq.exits_crypto&select=tp_pct,sl_pct,trades,win_rate,avg_ret_pct,total_ret_pct,computed_at&order=total_ret_pct.desc&limit=48')
        data = Array.isArray(rows) && rows.length ? rows : { error: 'cache vide — relance refresh_backtest_cache()' }
        break }
      case 'bt_archimages': {
        const rows = await rest('oracle_backtest_cache?kind=eq.archimages&select=archimage,trades,win_rate,avg_ret_pct,total_ret_pct,profit_factor,computed_at&order=total_ret_pct.desc')
        data = Array.isArray(rows) && rows.length ? rows : { error: 'cache vide — relance refresh_backtest_cache()' }
        break }
      case 'kelly':
        data = await rpc('compute_kelly_real'); break
      case 'directional':
        data = await rpc('evaluate_directional_accuracy', {}); break
      case 'breakers':
        await rpc('check_circuit_breakers')
        data = await rest('oracle_circuit_breakers?auto_resolved=eq.false&select=archimage,breaker_type,trigger_value,action_taken,fired_at&order=fired_at.desc'); break
      case 'friction':
        data = await rest('v_couts_friction?select=*'); break
      case 'sante_sources':
        data = await rest('oracle_datasource_health?select=source_name,status,fields_populated,fields_expected,completeness_pct,checked_at&order=checked_at.desc&limit=16'); break
      case 'learning': {
        const fb = await rest('learning_feedback?select=evaluated_at,run_id,predicted_phase,actual_phase_next_run,phase_correct,direction_correct,accuracy_score&order=evaluated_at.desc&limit=10')
        const cerv = await rest('oracle_brain_state?select=archimage,win_rate,directional_accuracy,kelly_fraction,current_drawdown,alpaca_drawdown_from_peak,consecutive_losses,current_bias&order=archimage')
        data = {
          cerveaux: Array.isArray(cerv) ? cerv.map((c: any) => ({ ...ddResolu(c), current_bias: tronque(c.current_bias, 80) })) : cerv,
          feedback: Array.isArray(fb) ? fb.map((f: any) => ({ ...f, predicted_phase: tronque(f.predicted_phase, 28), actual_phase_next_run: tronque(f.actual_phase_next_run, 28) })) : fb
        }; break }
      case 'archimage_detail': {
        const a = String(p.archimage || '').toUpperCase()
        if (!['JU','SYL','GIL'].includes(a)) { data = { error: 'archimage inconnu' }; break }
        const [brain, pos] = await Promise.all([
          rest(`oracle_brain_state?archimage=eq.${a}&select=archimage,win_rate,directional_accuracy,kelly_fraction,current_drawdown,alpaca_drawdown_from_peak,max_drawdown,cumulative_pnl,alpaca_portfolio_value,consecutive_losses,current_bias,learnings,mistakes_history`),
          // avg_entry_price > 0 : ecarte les residus Alpaca (qty 1e-9, prix d'entree negatif,
          // unrealized_pl aberrant a +188 325 $ sur SOLUSD) qui ne sont pas des positions.
          rest(`oracle_positions_live?archimage=eq.${a}&avg_entry_price=gt.0&select=ticker,side,qty,market_value,unrealized_pl,unrealized_pl_pct,days_held&order=market_value.desc.nullslast&limit=60`)
        ])
        const b = Array.isArray(brain) && brain[0] ? ddResolu(brain[0]) : {}
        data = {
          ...b,
          current_bias: tronque(b.current_bias, 800),
          learnings: Array.isArray(b.learnings) ? b.learnings.slice(-5).map((l: any) => ({ eval: tronque(l.eval, 500), bias: tronque(l.bias, 300), pnl: l.pnl })) : [],
          mistakes_history: Array.isArray(b.mistakes_history) ? b.mistakes_history.slice(-4).map((m: any) => ({ quand: m.at, phase: m.phase, delta: m.pnl_delta, eval: tronque(m.eval, 500) })) : [],
          positions: Array.isArray(pos) ? pos.map((r: any) => ({ ...r, market_value: Math.round(r.market_value), unrealized_pl: Math.round(r.unrealized_pl) })) : []
        }
        break }
      case 'snapshot': {
        const s = await rpc('dashboard_snapshot')
        const kpi: any[] = []
        try {
          const st = s.stats || {}
          kpi.push({ indicateur: 'Runs totaux', valeur: st.runs_total })
          kpi.push({ indicateur: 'Ordres totaux', valeur: st.ordres_total })
          kpi.push({ indicateur: 'Kill switch (Revolut réel)', valeur: st.kill_switch })
          kpi.push({ indicateur: 'Minutes depuis dernier run', valeur: st.minutes_depuis_dernier_run })
          kpi.push({ indicateur: 'Bougies de prix en base', valeur: st.bougies })
          kpi.push({ indicateur: 'Propositions Alchimiste', valeur: st.propositions_total })
          for (const c of (s.cerveau || [])) {
            kpi.push({ indicateur: `${c.archimage} — gain cumulé $`, valeur: c.cumulative_pnl })
            kpi.push({ indicateur: `${c.archimage} — win rate`, valeur: c.win_rate })
            kpi.push({ indicateur: `${c.archimage} — valeur du compte $`, valeur: c.alpaca_portfolio_value })
          }
          for (const sg of (s.sages || [])) {
            kpi.push({ indicateur: `Sage ${sg.sage} — taux de réussite %`, valeur: sg.taux_reussite })
          }
          const au = s.audit || {}
          kpi.push({ indicateur: 'Doctrine JU (extrait)', valeur: tronque(au.ju_doctrine_actuelle, 110) })
        } catch (_e) { }
        data = kpi.length ? kpi : s
        break }
      default:
        return new Response(JSON.stringify({ error: 'action inconnue', actions: ['hero','alchimiste','marees','runs','equity','positions','lead','archimage_detail','sages','sage_detail','coaching','bt_alchimiste','bt_exits','bt_archimages','kelly','directional','breakers','friction','sante_sources','learning','snapshot'] }), { status: 400, headers: { ...cors, 'Content-Type': 'application/json' } })
    }
    return new Response(JSON.stringify({ ok: true, action, at: new Date().toISOString(), data }), { headers: { ...cors, 'Content-Type': 'application/json' } })
  } catch (e) {
    return new Response(JSON.stringify({ error: String(e) }), { status: 500, headers: { ...cors, 'Content-Type': 'application/json' } })
  }
})
