import { serve } from 'https://deno.land/std@0.168.0/http/server.ts'

// v16 : lecons EPINGLEES (pinned:true) preservees en tete de learnings (jamais rognees) ->
//        une lecon manuelle reste lue en permanence par le prompt via learnings[1].bias.
// v15 : (SYL fige) current_drawdown = drawdown COURANT (pic -> derniere valeur, se repare) ;
//        max_drawdown reste le pire creux historique (stat separee). La ponderation utilise
//        desormais le drawdown COURANT -> un trader revenu pres de son pic n'est plus penalise
//        pour un creux deja recupere (bug SYL fige a 5.04% depuis le 29/07 corrige).
// v14 : (weighting) drawdown 5% n'est plus un cap dur a 0.5 ; ddPenalty adoucie (*3) ;
//        bonus edge long terme (cumBonus sur PnL cumule) ; cap dur maintenu a 8%.
// v13 : mistakes_history alimente ; run_id fallback Paris ; cerveau accumule ; orders_count reel

const cors = { 'Access-Control-Allow-Origin': '*', 'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type' }
const SUPABASE_URL = Deno.env.get('SUPABASE_URL') || 'https://smddzybxebwhfnitxuyp.supabase.co'
const SRK = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') || ''
const ALPACA = 'https://paper-api.alpaca.markets'

const KEYS: Record<string,{key:string,sec:string}> = {
  JU:  { key: 'PK_REDACTED', sec: 'REDACTED' },
  SYL: { key: 'PK_REDACTED', sec: 'REDACTED' },
  GIL: { key: 'PK_REDACTED', sec: 'REDACTED' },
}

function parisRunId(): string {
  const s = new Date().toLocaleString('sv-SE', { timeZone: 'Europe/Paris' })
  return s.slice(0,10).replace(/-/g,'') + '-' + s.slice(11,16).replace(':','')
}

async function aget(key: string, sec: string, path: string): Promise<any> {
  try {
    const r = await fetch(ALPACA + path, { headers: { 'APCA-API-KEY-ID': key, 'APCA-API-SECRET-KEY': sec }, signal: AbortSignal.timeout(8000) })
    if (!r.ok) return null
    return await r.json()
  } catch { return null }
}
async function sbGet(path: string): Promise<any> {
  try {
    const r = await fetch(`${SUPABASE_URL}/rest/v1/${path}`, { headers: { 'apikey': SRK, 'Authorization': `Bearer ${SRK}` }, signal: AbortSignal.timeout(8000) })
    if (!r.ok) return null
    return await r.json()
  } catch { return null }
}
async function sbWrite(path: string, body: any, prefer: string): Promise<string> {
  try {
    const r = await fetch(`${SUPABASE_URL}/rest/v1/${path}`, { method: 'POST', headers: { 'apikey': SRK, 'Authorization': `Bearer ${SRK}`, 'Content-Type': 'application/json', 'Prefer': prefer }, body: JSON.stringify(body), signal: AbortSignal.timeout(8000) })
    if (r.ok) return 'ok'
    return `err ${r.status}: ${(await r.text()).substring(0,200)}`
  } catch (e) { return 'exc ' + String(e).substring(0,120) }
}
// max drawdown : pire creux pic->creux sur toute la fenetre (stat historique)
function maxDrawdownOf(hist: any): number {
  try {
    const eq = (hist && Array.isArray(hist.equity)) ? hist.equity.filter((x:number)=>x>0) : []
    if (eq.length < 2) return 0
    let peak = eq[0], maxdd = 0
    for (const v of eq) { if (v > peak) peak = v; const dd = peak>0 ? (peak - v)/peak : 0; if (dd > maxdd) maxdd = dd }
    return Math.round(maxdd * 10000)/10000
  } catch { return 0 }
}
// current drawdown : recul depuis le pic all-time jusqu'a la DERNIERE valeur (se repare quand ca remonte)
function currentDrawdownOf(hist: any): number {
  try {
    const eq = (hist && Array.isArray(hist.equity)) ? hist.equity.filter((x:number)=>x>0) : []
    if (eq.length < 2) return 0
    let peak = eq[0]
    for (const v of eq) { if (v > peak) peak = v }
    const last = eq[eq.length-1]
    const cur = peak>0 ? (peak - last)/peak : 0
    return Math.round(Math.max(0,cur) * 10000)/10000
  } catch { return 0 }
}
const r2 = (x:number) => Math.round(x*100)/100

serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: cors })
  try {
    const p = await req.json()
    const run_id = (p.run_id && p.run_id !== 'ND') ? p.run_id : parisRunId()
    const market_phase = p.market_phase || 'ND'
    const accounts = [
      { a: 'JU',  key: KEYS.JU.key,  sec: KEYS.JU.sec,  bias: p.ju_bias,  w: Number(p.ju_weight)||0.33, evalTxt: p.ju_eval },
      { a: 'SYL', key: KEYS.SYL.key, sec: KEYS.SYL.sec, bias: p.syl_bias, w: Number(p.syl_weight)||0.33, evalTxt: p.syl_eval },
      { a: 'GIL', key: KEYS.GIL.key, sec: KEYS.GIL.sec, bias: p.gil_bias, w: Number(p.gil_weight)||0.34, evalTxt: p.gil_eval },
    ]

    const since3h = new Date(Date.now() - 3*3600*1000).toISOString()
    const stats: any[] = []
    for (const ac of accounts) {
      const [acct, hist, prevArr, ordersArr] = await Promise.all([
        aget(ac.key, ac.sec, '/v2/account'),
        aget(ac.key, ac.sec, '/v2/account/portfolio/history?period=1M&timeframe=1D'),
        sbGet(`oracle_brain_state?archimage=eq.${ac.a}&select=cumulative_pnl,total_runs,wins,losses,max_drawdown,learnings,mistakes_history,baseline_equity,consecutive_wins,consecutive_losses,current_streak_type`),
        sbGet(`oracle_college_orders?archimage=eq.${ac.a}&created_at=gte.${encodeURIComponent(since3h)}&select=id,broker_status`)
      ])
      const equity = acct ? Number(acct.equity || acct.portfolio_value || 0) : null
      const prev = (Array.isArray(prevArr) && prevArr[0]) ? prevArr[0] : { cumulative_pnl: 0, total_runs: 0, wins: 0, losses: 0, max_drawdown: 0, learnings: [], mistakes_history: [], baseline_equity: 0, consecutive_wins: 0, consecutive_losses: 0, current_streak_type: 'none' }
      const prevBase = Number(prev.baseline_equity) || 0
      const isCapture = !(prevBase > 0)
      const baseline = isCapture ? (equity || 100000) : prevBase
      const pnl = equity !== null ? r2(equity - baseline) : 0
      const curDd = currentDrawdownOf(hist)
      const maxDd = maxDrawdownOf(hist)
      const ordersCount = Array.isArray(ordersArr) ? ordersArr.length : 0
      stats.push({ ...ac, equity, baseline, pnl, dd: curDd, maxDd, isCapture, prev, ordersCount })
    }

    const notes: string[] = []
    let weights = stats.map((s) => {
      const eqRef = s.equity || s.baseline || 100000
      const D = Math.max(1000, 0.005 * eqRef)
      const lossPenalty = s.pnl < 0 ? 1/(1 + (-s.pnl)/D) : 1 + Math.min(0.5, (s.pnl/D)*0.25)
      const ddPenalty = 1/(1 + s.dd*3)
      const cumBonus = 1 + Math.max(0, Math.min(0.5, (s.pnl||0)/150000))
      let factor = lossPenalty * ddPenalty * cumBonus
      if (s.dd >= 0.08) { factor = Math.min(factor, 0.15); notes.push(`${s.a} drawdown courant ${Math.round(s.dd*100)}% >= seuil dur 8% -> poids plancher`) }
      else if (s.dd >= 0.05) { notes.push(`${s.a} drawdown courant ${Math.round(s.dd*100)}% (>=5%, surveille, pas de coupe dure)`) }
      if (s.pnl < 0) notes.push(`${s.a} perte ${Math.round(s.pnl)} -> facteur ${r2(factor)}`)
      else if (s.pnl > 0) notes.push(`${s.a} gain ${Math.round(s.pnl)} -> facteur ${r2(factor)}`)
      return Math.max(0.02, Math.max(0.01, s.w) * factor)
    })
    const maxI = weights.indexOf(Math.max(...weights))
    if (stats[maxI].pnl < 0) {
      const best = stats.reduce((b, s, i) => (s.pnl > stats[b].pnl ? i : b), 0)
      if (best !== maxI) { const t = weights[maxI]; weights[maxI] = weights[best]; weights[best] = t; notes.push(`poids max transfere au moins mauvais ${stats[best].a}`) }
    }
    const sum = weights.reduce((a,b)=>a+b,0) || 1
    weights = weights.map(w => r2(w/sum))

    const now = new Date().toISOString()
    const brainRows: any[] = []
    const perfRows: any[] = []
    stats.forEach((s, i) => {
      const prevPnl = Number(s.prev.cumulative_pnl) || 0
      const win = s.pnl > prevPnl
      const addW = s.isCapture ? 0 : (win ? 1 : 0)
      const addL = s.isCapture ? 0 : (win ? 0 : 1)
      const wins = (Number(s.prev.wins)||0) + addW
      const losses = (Number(s.prev.losses)||0) + addL
      const total = (Number(s.prev.total_runs)||0) + 1
      const denom = wins + losses
      const wr = denom > 0 ? r2(wins/denom) : 0
      const maxdd = Math.max(Number(s.prev.max_drawdown)||0, s.maxDd)
      const prevStreakType = s.prev.current_streak_type || 'none'
      const prevConsecW = Number(s.prev.consecutive_wins) || 0
      const prevConsecL = Number(s.prev.consecutive_losses) || 0
      let consecutive_wins = 0, consecutive_losses = 0, current_streak_type = 'none'
      if (!s.isCapture) {
        if (win) { consecutive_wins = prevStreakType === 'win' ? prevConsecW + 1 : 1; consecutive_losses = 0; current_streak_type = 'win' }
        else { consecutive_losses = prevStreakType === 'loss' ? prevConsecL + 1 : 1; consecutive_wins = 0; current_streak_type = 'loss' }
      }
      // Lecons EPINGLEES (pinned:true) : jamais rognees, gardees en tete -> lues par le prompt via learnings[1].bias
      const _all = Array.isArray(s.prev.learnings) ? s.prev.learnings : []
      const _pinned = _all.filter((e:any) => e && e.pinned)
      let _rolling = _all.filter((e:any) => !e || !e.pinned)
      _rolling.push({ run: run_id, pnl: s.pnl, dd: s.dd, eval: (s.evalTxt||'').toString().substring(0,120), bias: (s.bias||'').toString().substring(0,80) })
      if (_rolling.length > 30) _rolling = _rolling.slice(-30)
      let learn = [..._pinned, ..._rolling]
      let mistakes = Array.isArray(s.prev.mistakes_history) ? s.prev.mistakes_history : []
      if (!s.isCapture && !win) {
        mistakes.push({ run: run_id, at: now, pnl_delta: r2(s.pnl - prevPnl), pnl: s.pnl, dd: s.dd, phase: market_phase, consec_losses: consecutive_losses, eval: (s.evalTxt||'').toString().substring(0,140) })
        if (mistakes.length > 30) mistakes = mistakes.slice(-30)
      }
      brainRows.push({ archimage: s.a, last_run_at: now, last_run_id: run_id, total_runs: total, wins, losses, win_rate: wr, cumulative_pnl: s.pnl, current_drawdown: s.dd, max_drawdown: maxdd, synthesis_weight: weights[i], current_bias: (s.bias||'neutral').toString().substring(0,260), learnings: learn, mistakes_history: mistakes, baseline_equity: s.baseline, updated_at: now, consecutive_wins, consecutive_losses, current_streak_type })
      perfRows.push({ run_id, archimage: s.a, actual_pnl: s.pnl, accuracy_score: wr, market_phase, orders_count: s.ordersCount, win, notes: (s.isCapture ? 'calibration baseline' : notes.filter(n=>n.startsWith(s.a)).join('; ')).substring(0,200), evaluated_at: now })
    })
    const prevCerveauArr = await sbGet(`oracle_brain_state?archimage=eq.cerveau&select=learnings`)
    let cerveauLearn = (Array.isArray(prevCerveauArr) && prevCerveauArr[0] && Array.isArray(prevCerveauArr[0].learnings)) ? prevCerveauArr[0].learnings : []
    cerveauLearn.push({ run: run_id, at: now, notes: (notes.join('; ')||'aucune correction').substring(0,220), weights: { JU: weights[0], SYL: weights[1], GIL: weights[2] } })
    if (cerveauLearn.length > 50) cerveauLearn = cerveauLearn.slice(-50)
    const cerveauRow = { archimage: 'cerveau', last_run_at: now, last_run_id: run_id, total_runs: 0, wins: 0, losses: 0, win_rate: 0, cumulative_pnl: 0, current_drawdown: 0, max_drawdown: 0, synthesis_weight: 1, current_bias: (notes.join('; ')||'aucune correction').substring(0,260), learnings: cerveauLearn, baseline_equity: null, updated_at: now }

    const wBrain = await sbWrite('oracle_brain_state?on_conflict=archimage', brainRows, 'resolution=merge-duplicates,return=minimal')
    const wCerveau = await sbWrite('oracle_brain_state?on_conflict=archimage', [cerveauRow], 'resolution=merge-duplicates,return=minimal')
    const wPerf = await sbWrite('oracle_performance', perfRows, 'return=minimal')

    return new Response(JSON.stringify({ run_id, corrected_weights: { JU: weights[0], SYL: weights[1], GIL: weights[2] }, meta_notes: notes, stats: stats.map(s=>({ a: s.a, equity: s.equity, baseline: s.baseline, pnl: s.pnl, dd: s.dd, max_dd: s.maxDd, orders_3h: s.ordersCount, capture: s.isCapture })), writes: { brain: wBrain, cerveau: wCerveau, performance: wPerf } }), { headers: { ...cors, 'Content-Type': 'application/json' } })
  } catch (e) {
    return new Response(JSON.stringify({ error: String(e) }), { status: 500, headers: { ...cors, 'Content-Type': 'application/json' } })
  }
})
