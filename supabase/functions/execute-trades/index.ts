import { serve } from 'https://deno.land/std@0.168.0/http/server.ts'

// v39 : RACHAT DE VENTE A DECOUVERT EN QUANTITE. Un achat sur un ticker deja vendu a decouvert
//       partait en NOTIONNEL : Alpaca convertissait 50 000 $ en 121,25 titres alors que la position
//       short n'etait que de 22,85, et refusait l'ordre entier (il ne retourne pas une position en
//       un seul ordre). Le short GLD de SYL est reste ouvert, rachat rejete 3 fois en 2 jours :
//       18/08 14:30 (404,14 pour 24,07), 18/08 19:17 (406,38 pour 24,07), 19/08 16:41 (121,25 pour
//       22,85). On envoie desormais la QUANTITE exacte de la position short.
//       Les VERROUS D'UNIVERS sont inchanges et restent evalues AVANT ce bloc : JU actions,
//       SYL ETF, GIL large. Un rachat hors univers reste donc refuse comme avant.
// v38 : GARDE-FOU RENFORT SHORT PERDANT — un `sell` sur un titre non detenu ouvre OU AGRANDIT une
//       vente a decouvert. Le systeme moyennait donc a la baisse sur une position deja perdante :
//       le 19/08/2026, GIL portait un short MSTR de -558 353 $ a -10,4 % de perte latente, et l'a
//       renforce deux fois dans la journee (14 952 $ puis 2 963 $). Desormais, si un short existe
//       deja sur le ticker et perd plus de RENFORT_SHORT_PERTE_MAX, l'ordre est refuse et journalise.
//       N'empeche NI l'ouverture d'un nouveau short, NI le rachat (buy) qui debouclerait la position,
//       NI la vente d'une position reellement detenue.
// v37 : VERROU ACTIONS/ETF — chaque archimage reste dans sa voie à l'ACHAT. JU (actions individuelles)
//       ne peut plus acheter d'ETF ; SYL (paniers ETF) ne peut plus acheter d'action individuelle.
//       GIL est EXEMPTÉ (son univers CRYPTO_TACTICAL_DERIVATIVES est large : proxies, ETF tactiques,
//       shorts). Les VENTES restent libres (débouclage). Complète le verrou crypto=GIL de v34.
// v36 : REVERT du volet "GIL crypto-only" de v35 — le prompt réel de GIL est CRYPTO_TACTICAL_DERIVATIVES
//       (proxies MSTR/COIN, ETF tactiques SQQQ/TQQQ, défensifs XLU/XLP, shorts contrarian) : GIL DOIT
//       pouvoir trader ces instruments. On CONSERVE l'interdiction de crypto pour les non-GIL (déjà en v34).
// v34 : garde anti-double-vente — une vente est ignorée si un ordre est déjà ouvert sur le même ticker
//       (JU revendait des positions déjà verrouillées par un ordre en attente -> rejets 'insufficient qty available')
// v33 : (1) découpage des gros ordres en tranches <= 190k$ (2) garde anti-poussière (3) run_id fallback Paris

const cors = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

const SUPABASE_URL = Deno.env.get('SUPABASE_URL') || 'https://smddzybxebwhfnitxuyp.supabase.co'
const SUPABASE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') || ''
const ALPACA = 'https://paper-api.alpaca.markets'

const MIN_BUYING_POWER = 500
const EXPOSURE_PCT = 0.25
const EXPOSURE_FALLBACK = 18000
const DELEVERAGE_TARGET_CASH = 3000
const DELEVERAGE_MAX_SELLS = 12
const BUY_CASH_FRACTION = 0.9
const MAX_ORDER_PCT = 0.15
const TAKE_PROFIT_PCT = 0.35
const STOP_LOSS_PCT = 0.15
const MOM_LOOKBACK_DAYS = 90
const MOM_BUY_MIN = -0.10
const MOM_SHORT_MAX = 0
const SELL_SAFETY_STOCK = 0.999
const SELL_SAFETY_CRYPTO = 0.995
const POUSSIERE_SEUIL_USD = 2
const MAX_NOTIONAL_PER_ORDER = 190000
const DUST_QTY_MIN = 1e-8
const DUST_USD_MIN = 1
// Perte latente au-dela de laquelle un short existant ne peut plus etre renforce (-5 %).
const RENFORT_SHORT_PERTE_MAX = -0.05

const CRYPTO_EXCLUSIF_GIL = ['BTCUSD','ETHUSD','SOLUSD','AVAXUSD','LINKUSD','XRPUSD','DOGEUSD','LTCUSD']
const INTERDIT_GIL = ['SPY','QQQ']
// Liste ETF de référence (couvre l'univers de SYL + ETF sectoriels/levier/vol usuels). Sert au verrou
// d'univers : JU ne peut pas ACHETER un de ces ETF ; SYL ne peut acheter QUE ceux-ci (ou crypto=jamais).
// GIL est exempté du verrou. Un ticker hors de cette liste (et non-crypto) est considéré action individuelle.
const ETF_REF = ['SPY','QQQ','IWM','DIA','VOO','VTI','XLK','XLF','XLV','XLU','XLE','XLP','XLY','XLI','XLC','XLB','XLRE',
  'SMH','EEM','EWJ','EFA','VEA','VWO','EWZ','INDA','FXI','VGK','EWG','EWL','GLD','SLV','GDX','TLT','IEF','SHY','BND',
  'AGG','TIP','PDBC','DBA','USO','UNG','BITO','SCHD','VYM','DVY','IWD','HYG','JNK','LQD','EMB','TQQQ','SQQQ','UPRO',
  'SPXS','VXX','UVXY','ARKK','XBI','KRE','XRT','ITB']

function normSym(s: string): string { return String(s || '').toUpperCase().replace(/[^A-Z0-9]/g, '') }

function parisRunId(): string {
  const s = new Date().toLocaleString('sv-SE', { timeZone: 'Europe/Paris' })
  return s.slice(0,10).replace(/-/g,'') + '-' + s.slice(11,16).replace(':','')
}

function numClean(v: any): number {
  if (typeof v === 'number') return isFinite(v) ? v : 0
  let s = String(v == null ? '' : v).trim()
  if (!s) return 0
  if (/^-?\d+(\.\d+)?[eE][+\-]?\d+$/.test(s)) { const n = parseFloat(s); return isFinite(n) ? n : 0 }
  s = s.replace(/[\s ]/g, '').replace(/h/gi, '.').replace(/,/g, '.')
  const f = s.indexOf('.')
  if (f !== -1) s = s.slice(0, f + 1) + s.slice(f + 1).replace(/\./g, '')
  const n = parseFloat(s.replace(/[^0-9.\-]/g, ''))
  return isFinite(n) ? n : 0
}
function qtyStr(n: number): string {
  if (!isFinite(n)) return '0'
  if (Math.abs(n) < 1e-6 && n !== 0) return n.toFixed(12).replace(/0+$/,'').replace(/\.$/,'')
  return String(n)
}

async function alpacaGet(key: string, secret: string, path: string): Promise<any> {
  try {
    const r = await fetch(ALPACA + path, { headers: { 'APCA-API-KEY-ID': key, 'APCA-API-SECRET-KEY': secret }, signal: AbortSignal.timeout(8000) })
    if (!r.ok) return null
    return await r.json()
  } catch { return null }
}

async function dbg(row: any) {
  if (!SUPABASE_KEY) return
  try {
    await fetch(`${SUPABASE_URL}/rest/v1/oracle_exec_debug`, { method: 'POST', headers: { 'apikey': SUPABASE_KEY, 'Authorization': `Bearer ${SUPABASE_KEY}`, 'Content-Type': 'application/json', 'Prefer': 'return=minimal' }, body: JSON.stringify(row) })
  } catch {}
}

async function getConcentrationCroisee(tickers: string[], archimageActuel: string): Promise<Record<string, { long: number, short: number }>> {
  const out: Record<string, { long: number, short: number }> = {}
  if (!SUPABASE_KEY || tickers.length === 0) return out
  try {
    const uniq = Array.from(new Set(tickers.filter(Boolean)))
    const u = `${SUPABASE_URL}/rest/v1/oracle_positions_live?ticker=in.(${uniq.map(t=>encodeURIComponent(t)).join(',')})&archimage=neq.${encodeURIComponent(archimageActuel)}&select=ticker,side,archimage`
    const r = await fetch(u, { headers: { apikey: SUPABASE_KEY, Authorization: `Bearer ${SUPABASE_KEY}` }, signal: AbortSignal.timeout(6000) })
    if (!r.ok) return out
    const rows = await r.json()
    if (Array.isArray(rows)) for (const row of rows) {
      const t = normSym(row.ticker)
      if (!out[t]) out[t] = { long: 0, short: 0 }
      if (row.side === 'short') out[t].short++
      else out[t].long++
    }
  } catch {}
  return out
}

async function getPrices(key: string, secret: string, stockSyms: string[], cryptoSyms: string[]): Promise<Record<string, number>> {
  const out: Record<string, number> = {}
  const H = { 'APCA-API-KEY-ID': key, 'APCA-API-SECRET-KEY': secret }
  const uniq = (a: string[]) => Array.from(new Set(a.filter(Boolean)))
  try {
    const ss = uniq(stockSyms)
    if (ss.length) {
      const u = 'https://data.alpaca.markets/v2/stocks/trades/latest?symbols=' + encodeURIComponent(ss.join(','))
      const r = await fetch(u, { headers: H, signal: AbortSignal.timeout(6000) })
      if (r.ok) { const d = await r.json(); const tr = d.trades || {}; for (const s in tr) { const p = Number(tr[s] && tr[s].p); if (p > 0) out[normSym(s)] = p } }
    }
  } catch {}
  try {
    const cs = uniq(cryptoSyms).map(s => s.toUpperCase().replace('/', '').replace('USD', '') + '/USD')
    if (cs.length) {
      const u = 'https://data.alpaca.markets/v1beta3/crypto/us/latest/trades?symbols=' + encodeURIComponent(cs.join(','))
      const r = await fetch(u, { headers: H, signal: AbortSignal.timeout(6000) })
      if (r.ok) { const d = await r.json(); const tr = d.trades || {}; for (const s in tr) { const p = Number(tr[s] && tr[s].p); if (p > 0) out[normSym(s)] = p } }
    }
  } catch {}
  return out
}

async function getMomentum(key: string, secret: string, stockSyms: string[], cryptoSyms: string[]): Promise<Record<string, number>> {
  const out: Record<string, number> = {}
  const H = { 'APCA-API-KEY-ID': key, 'APCA-API-SECRET-KEY': secret }
  const start = new Date(Date.now() - MOM_LOOKBACK_DAYS*86400000).toISOString().slice(0,10)
  const uniq = (a: string[]) => Array.from(new Set(a.filter(Boolean)))
  const calc = (bars: any) => { if (!Array.isArray(bars) || bars.length < 2) return undefined; const f = Number(bars[0].c), l = Number(bars[bars.length-1].c); return (f>0 && l>0) ? (l-f)/f : undefined }
  try {
    const ss = uniq(stockSyms)
    if (ss.length) {
      const u = 'https://data.alpaca.markets/v2/stocks/bars?timeframe=1Day&limit=1000&adjustment=raw&start=' + start + '&symbols=' + encodeURIComponent(ss.join(','))
      const r = await fetch(u, { headers: H, signal: AbortSignal.timeout(8000) })
      if (r.ok) { const d = await r.json(); const bb = d.bars || {}; for (const s in bb) { const m = calc(bb[s]); if (m !== undefined) out[normSym(s)] = m } }
    }
  } catch {}
  try {
    const cs = uniq(cryptoSyms).map(s => s.toUpperCase().replace('/', '').replace('USD', '') + '/USD')
    if (cs.length) {
      const u = 'https://data.alpaca.markets/v1beta3/crypto/us/bars?timeframe=1Day&limit=1000&start=' + start + '&symbols=' + encodeURIComponent(cs.join(','))
      const r = await fetch(u, { headers: H, signal: AbortSignal.timeout(8000) })
      if (r.ok) { const d = await r.json(); const bb = d.bars || {}; for (const s in bb) { const m = calc(bb[s]); if (m !== undefined) out[normSym(s)] = m } }
    }
  } catch {}
  return out
}

async function placeOrder(alpacaKey: string, alpacaSecret: string, order: any, marketOpen: boolean): Promise<any> {
  try {
    const isCrypto = order.asset_type === 'crypto'
    const body: any = {
      symbol: order.ticker.toUpperCase().replace('/', '-'),
      side: order.side.toLowerCase(),
      type: 'market',
      time_in_force: isCrypto ? 'gtc' : 'day',
      client_order_id: `${order.archimage_prefix}-${order.ticker.replace('-','')}-${Date.now()}-${Math.floor(Math.random()*999)}`.substring(0, 48)
    }
    const notional = Math.round(numClean(order.notional))
    if (notional >= 1) { body.notional = String(notional) } else if (!(numClean(order.qty) > 0)) { return { error: 'notional < 1', ticker: order.ticker, raw_qty_in: (order.qty != null ? String(order.qty) : null), status: 'rejected', alpaca_status: null } }

    const _advanced = false

    const _sellQty = numClean(order.qty)
    // v39 : order._cover ajoute — sans lui, la quantite d'un rachat de short serait ignoree
    // et l'ordre repartirait en notionnel, c'est-a-dire exactement le bug corrige.
    if (_sellQty > 0 && (order.side.toLowerCase() === 'sell' || order._auto || order._short || order._cover)) {
      delete body.notional
      body.qty = qtyStr(_sellQty)
    }

    const resp = await fetch(ALPACA + '/v2/orders', { method: 'POST', headers: { 'APCA-API-KEY-ID': alpacaKey, 'APCA-API-SECRET-KEY': alpacaSecret, 'Content-Type': 'application/json' }, body: JSON.stringify(body), signal: AbortSignal.timeout(10000) })
    const data = await resp.json()
    if (resp.ok) console.log('ORDER_OK ' + JSON.stringify({ t: order.ticker, raw_qty: order.qty, qty: body.qty||null, notional: body.notional||null, type: body.type, cls: 'simple', alpaca: data.status, chunk: order._chunk || null }))
    else console.log('ORDER_REJECT ' + JSON.stringify({ t: order.ticker, raw_qty: order.qty, body, alpaca: data }))
    return { ticker: order.ticker, side: order.side, notional: notional, order_type: body.type, order_class: 'simple', qty: body.qty || null, raw_qty_in: (order.qty != null ? String(order.qty) : null), auto: order._auto || null, short: order._short || null, cover: order._cover || null, plpc: order._plpc != null ? order._plpc : null, chunk: order._chunk || null, status: resp.ok ? 'accepted' : 'rejected', alpaca_id: data.id || null, alpaca_status: data.status || null, error: resp.ok ? null : (data.message || data.code || 'error') }
  } catch(e) { return { ticker: order.ticker, status: 'error', error: String(e), raw_qty_in: (order.qty != null ? String(order.qty) : null) } }
}

serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: cors })
  try {
    const payload = await req.json()
    const { archimage, alpaca_key, alpaca_secret, market_phase,
      trade_1_ticker, trade_1_side, trade_1_notional, trade_1_asset_type, trade_1_time_in_force, trade_1_conviction,
      trade_1_qty, trades_extended } = payload
    const run_id = (payload.run_id && payload.run_id !== 'ND') ? payload.run_id : parisRunId()

    if (!alpaca_key || !alpaca_secret) return new Response(JSON.stringify({ error: 'Missing Alpaca credentials' }), { status: 400, headers: { ...cors, 'Content-Type': 'application/json' } })

    const allTrades: any[] = []
    const prefix = (archimage || 'XX').toUpperCase().substring(0, 3)
    if (trade_1_ticker && trade_1_ticker !== 'ND' && trade_1_ticker !== '') {
      allTrades.push({ ticker: trade_1_ticker, side: trade_1_side || 'buy', notional: Number(trade_1_notional) || 300, asset_type: trade_1_asset_type || 'etf', time_in_force: trade_1_time_in_force || 'day', conviction: Number(trade_1_conviction) || 5, archimage_prefix: prefix, qty: trade_1_qty || null })
    }
    let extended = trades_extended
    if (typeof extended === 'string') { try { extended = JSON.parse(extended) } catch { extended = [] } }
    if (Array.isArray(extended)) {
      for (const t of extended.slice(0, 49)) {
        if (t.ticker && t.ticker !== 'ND' && t.ticker !== '' && t.side && ['buy','sell'].includes(t.side.toLowerCase()) && Number(t.notional) >= 1) {
          allTrades.push({ ticker: t.ticker, side: t.side.toLowerCase(), notional: Number(t.notional), asset_type: t.asset_type || 'etf', time_in_force: t.asset_type === 'crypto' ? 'gtc' : (t.time_in_force || 'day'), conviction: Number(t.conviction) || 5, archimage_prefix: prefix, qty: t.qty || null, intent: t.intent || null })
        }
      }
    }

    const [acct, clock, positions, openOrders] = await Promise.all([
      alpacaGet(alpaca_key, alpaca_secret, '/v2/account'),
      alpacaGet(alpaca_key, alpaca_secret, '/v2/clock'),
      alpacaGet(alpaca_key, alpaca_secret, '/v2/positions'),
      alpacaGet(alpaca_key, alpaca_secret, '/v2/orders?status=open&limit=200')
    ])
    const buyingPower = acct ? Number(acct.buying_power) : null
    const cash = acct ? Number(acct.cash) : null
    const equity = acct ? (Number(acct.equity) || Number(acct.portfolio_value) || 0) : 0
    const exposureCap = equity > 0 ? equity * EXPOSURE_PCT : EXPOSURE_FALLBACK
    const marketOpen = clock ? !!clock.is_open : true
    const heldMV: Record<string, number> = {}
    const heldQty: Record<string, number> = {}
    const heldPx: Record<string, number> = {}
    const heldPlpc: Record<string, number> = {}
    if (Array.isArray(positions)) for (const p of positions) {
      const s = normSym(p.symbol)
      heldMV[s] = Number(p.market_value) || 0
      heldQty[s] = Number(p.qty) || 0
      const _plpc = Number(p.unrealized_plpc)
      if (isFinite(_plpc)) heldPlpc[s] = _plpc
      const px = Number(p.current_price) || (Number(p.qty) ? Math.abs((Number(p.market_value)||0) / Number(p.qty)) : 0)
      heldPx[s] = px || 0
    }
    const pending = new Set<string>()
    if (Array.isArray(openOrders)) for (const o of openOrders) pending.add(normSym(o.symbol))
    const accountFrozen = (buyingPower !== null && buyingPower < MIN_BUYING_POWER) || (cash !== null && cash < 0)
    let buyBudget = Math.max(0, (cash || 0)) * BUY_CASH_FRACTION
    const buyBudgetStart = Math.round(buyBudget)

    const _stockSyms: string[] = []; const _cryptoSyms: string[] = []
    for (const t of allTrades) { if (t.asset_type === 'crypto') _cryptoSyms.push(t.ticker); else _stockSyms.push(t.ticker) }
    const _mightShort = allTrades.some((t: any) => t.intent === 'short' || (t.side === 'sell' && t.asset_type !== 'crypto' && (heldQty[normSym(t.ticker)] || 0) <= 0))
    const priceMap = _mightShort ? await getPrices(alpaca_key, alpaca_secret, _stockSyms, _cryptoSyms) : {}
    const momMap = await getMomentum(alpaca_key, alpaca_secret, _stockSyms, _cryptoSyms)
    const concentration = await getConcentrationCroisee(allTrades.map(t => t.ticker), archimage || '')

    const toExec: any[] = []
    const skipped: any[] = []
    const selling = new Set<string>()

    const autoExits: any[] = []
    if (Array.isArray(positions)) {
      for (const pos of positions) {
        const sym = normSym(pos.symbol)
        const q = Number(pos.qty) || 0
        if (q === 0) continue
        if (pending.has(sym)) continue
        const plpc = Number(pos.unrealized_plpc)
        if (!isFinite(plpc)) continue
        const isShortP = q < 0
        const isCryptoP = (pos.asset_class === 'crypto')
        const mv = Math.abs(Number(pos.market_value) || 0)
        let reason: string | null = null
        if (mv > 0 && mv < POUSSIERE_SEUIL_USD) reason = 'poussiere'
        else if (plpc >= TAKE_PROFIT_PCT) reason = 'take_profit'
        else if (plpc <= -STOP_LOSS_PCT) reason = 'stop_loss'
        if (reason === 'poussiere' && (mv < DUST_USD_MIN || Math.abs(q) < DUST_QTY_MIN)) {
          skipped.push({ ticker: pos.symbol, side: isShortP ? 'buy' : 'sell', reason: 'dust_unsellable', qty: String(q), mv })
          continue
        }
        if (reason) {
          const _qClose = reason === 'poussiere' ? Math.abs(q) : Math.abs(q) * (isCryptoP ? SELL_SAFETY_CRYPTO : SELL_SAFETY_STOCK)
          autoExits.push({ ticker: pos.symbol, side: isShortP ? 'buy' : 'sell', qty: qtyStr(_qClose), notional: Math.max(1, Math.floor(mv)), asset_type: isCryptoP ? 'crypto' : 'etf', archimage_prefix: prefix, _auto: reason, _plpc: Math.round(plpc*10000)/10000 })
          selling.add(sym)
        }
      }
    }
    for (const s of autoExits) toExec.push(s)

    const archUpper = (archimage || '').toUpperCase()
    for (const t of allTrades) {
      const sym = normSym(t.ticker)
      const isBuy = t.side === 'buy'
      const isCryptoT = t.asset_type === 'crypto'
      const _mom = momMap[sym]
      t._mom = (_mom !== undefined ? Math.round(_mom*1000)/10 : null)
      if (selling.has(sym)) { skipped.push({ ticker: t.ticker, side: t.side, reason: 'auto_exit_priority' }); continue }

      // v34 : une vente sur un ticker ayant déjà un ordre ouvert est ignorée (position verrouillée chez Alpaca)
      if (!isBuy && pending.has(sym)) { skipped.push({ ticker: t.ticker, side: t.side, reason: 'sell_blocked_pending_order' }); continue }

      if (isBuy) {
        const estCrypto = isCryptoT || CRYPTO_EXCLUSIF_GIL.includes(sym)
        const estETF = ETF_REF.includes(sym)
        // Crypto = domaine EXCLUSIF de GIL : un non-GIL ne peut pas en ACHETER.
        if (archUpper !== 'GIL' && estCrypto) {
          skipped.push({ ticker: t.ticker, side: t.side, reason: 'univers_crypto_reserve_gil' }); continue
        }
        // VERROU ACTIONS/ETF (17/08) — GIL EXEMPTÉ (univers large). Les ventes ne passent pas ici.
        // JU = actions individuelles : interdit d'ACHETER un ETF (domaine SYL).
        if (archUpper === 'JU' && estETF) {
          skipped.push({ ticker: t.ticker, side: t.side, reason: 'univers_etf_reserve_syl' }); continue
        }
        // SYL = paniers ETF : interdit d'ACHETER une action individuelle (domaine JU).
        if (archUpper === 'SYL' && !estETF && !estCrypto) {
          skipped.push({ ticker: t.ticker, side: t.side, reason: 'univers_action_reserve_ju' }); continue
        }
        // GIL : conserve seulement l'interdit historique SPY/QQQ en direct.
        if (archUpper === 'GIL' && INTERDIT_GIL.includes(sym)) {
          skipped.push({ ticker: t.ticker, side: t.side, reason: 'univers_spy_qqq_interdit_gil' }); continue
        }
      }

      if (!isBuy && t.intent !== 'short') {
        const _heldNow = heldQty[sym] || 0
        if (_heldNow <= 0) {
          if (isCryptoT) { skipped.push({ ticker: t.ticker, side: t.side, reason: 'crypto_short_not_supported' }); continue }
          t.intent = 'short'
        }
      }

      if (!isBuy && t.intent === 'short') {
        // GIL peut shorter (rôle contrarian), sauf SPY/QQQ en direct (garde historique).
        if (archUpper === 'GIL' && INTERDIT_GIL.includes(sym)) {
          skipped.push({ ticker: t.ticker, side: t.side, reason: 'univers_spy_qqq_interdit_gil' }); continue
        }
      }

      if (isBuy && !isCryptoT && !marketOpen) { skipped.push({ ticker: t.ticker, side: t.side, reason: 'us_market_closed_equity_buy' }); continue }

      // v39 — RACHAT D'UNE VENTE A DECOUVERT : on solde en QUANTITE, jamais en notionnel.
      // Place APRES les verrous d'univers (lignes plus haut), donc un rachat hors univers reste
      // refuse. Place AVANT le controle accountFrozen : racheter un short REDUIT l'exposition,
      // c'est l'operation qu'il faut justement pouvoir faire quand la marge est saturee.
      if (isBuy && (heldQty[sym] || 0) < 0) {
        if (pending.has(sym)) { skipped.push({ ticker: t.ticker, side: t.side, reason: 'rachat_short_ordre_deja_ouvert' }); continue }
        const _qCover = Math.abs(heldQty[sym] || 0)
        const _pxCover = heldPx[sym] || priceMap[sym] || 0
        const _notionnelDemande = Math.round(numClean(t.notional))
        if (!(_qCover > 0)) { skipped.push({ ticker: t.ticker, side: t.side, reason: 'rachat_short_quantite_nulle' }); continue }
        t.qty = qtyStr(_qCover)
        t.notional = _pxCover > 0 ? Math.max(1, Math.round(_qCover * _pxCover)) : Math.max(1, _notionnelDemande)
        t._cover = true
        // trace : ce que le modele demandait avant qu'on le ramene a la taille reelle du short
        if (_notionnelDemande !== t.notional) t._clamped_from = _notionnelDemande
        toExec.push(t)
        continue
      }

      if (isBuy && accountFrozen) { skipped.push({ ticker: t.ticker, side: t.side, reason: 'account_frozen_buying_power' }); continue }
      if (isBuy && pending.has(sym)) { skipped.push({ ticker: t.ticker, side: t.side, reason: 'duplicate_open_order' }); continue }
      if (isBuy && (heldMV[sym] || 0) >= exposureCap) { skipped.push({ ticker: t.ticker, side: t.side, reason: 'max_ticker_exposure', held: heldMV[sym], cap: Math.round(exposureCap) }); continue }
      if (isBuy) {
        if (_mom !== undefined && _mom <= MOM_BUY_MIN) { skipped.push({ ticker: t.ticker, side: t.side, reason: 'momentum_downtrend', mom: t._mom }); continue }
        const _want = Math.round(Number(t.notional) || 0)
        const _concLong = (concentration[sym]?.long) || 0
        const _pctEff = _concLong >= 2 ? MAX_ORDER_PCT / 2 : MAX_ORDER_PCT
        const _maxOrder = equity > 0 ? Math.floor(equity * _pctEff) : _want
        const _room = Math.floor(exposureCap - (heldMV[sym] || 0))
        let _n = Math.min(_want, _maxOrder, _room, MAX_NOTIONAL_PER_ORDER)
        if (_n < 1) { skipped.push({ ticker: t.ticker, side: t.side, reason: 'risk_no_room', want: _want, max_order: _maxOrder, room: _room }); continue }
        if (_n > buyBudget) { skipped.push({ ticker: t.ticker, side: t.side, reason: 'cash_budget_per_run', budget: Math.round(buyBudget), wanted: _n }); continue }
        if (_n < _want) t._clamped_from = _want
        if (_concLong >= 2) t._concentration_reduit = true
        t.notional = _n
        buyBudget -= _n
      }

      if (!isBuy && t.intent === 'short' && !isCryptoT) {
        if (_mom !== undefined && _mom >= MOM_SHORT_MAX) { skipped.push({ ticker: t.ticker, side: t.side, reason: 'short_not_downtrend', mom: t._mom }); continue }
        const _px = priceMap[sym] || heldPx[sym] || 0
        if (!marketOpen) { skipped.push({ ticker: t.ticker, side: t.side, reason: 'short_market_closed' }); continue }
        if (_px <= 0) { skipped.push({ ticker: t.ticker, side: t.side, reason: 'short_no_price' }); continue }
        if (pending.has(sym) || (heldMV[sym] || 0) > 0) { skipped.push({ ticker: t.ticker, side: t.side, reason: 'short_blocked_position' }); continue }
        // v38 — GARDE-FOU : interdiction de renforcer un short deja perdant.
        // heldMV est NEGATIF sur un short, donc le test ci-dessus ne l'attrapait pas : l'ordre
        // passait et agrandissait la position. On refuse desormais si la perte latente depasse
        // le seuil. Ouvrir un nouveau short (aucune position) reste autorise.
        const _qShort = heldQty[sym] || 0
        const _plShort = heldPlpc[sym]
        if (_qShort < 0 && _plShort !== undefined && _plShort <= RENFORT_SHORT_PERTE_MAX) {
          skipped.push({ ticker: t.ticker, side: t.side, reason: 'renfort_short_perdant_bloque',
            perte_pct: Math.round(_plShort*10000)/100, seuil_pct: Math.round(RENFORT_SHORT_PERTE_MAX*10000)/100,
            exposition_usd: Math.round(heldMV[sym] || 0) })
          continue
        }
        const _wantS = Math.round(Number(t.notional) || 0)
        const _concShort = (concentration[sym]?.short) || 0
        const _pctEffS = _concShort >= 2 ? MAX_ORDER_PCT / 2 : MAX_ORDER_PCT
        const _maxS = equity > 0 ? Math.floor(equity * _pctEffS) : _wantS
        const _nS = Math.min(_wantS, _maxS, Math.floor(exposureCap), MAX_NOTIONAL_PER_ORDER)
        const _shares = Math.floor(_nS / _px)
        if (_shares < 1) { skipped.push({ ticker: t.ticker, side: t.side, reason: 'short_too_small', want: _wantS, px: Math.round(_px) }); continue }
        if (_nS < _wantS) t._clamped_from = _wantS
        if (_concShort >= 2) t._concentration_reduit = true
        t.qty = String(_shares)
        t.notional = Math.round(_shares * _px)
        t._short = true
      }

      if (!isBuy && t.intent !== 'short') {
        const _heldNow = heldQty[sym] || 0
        if (_heldNow > 0) {
          if (isCryptoT) {
            const _px = heldPx[sym] || 0
            let _q = numClean(t.qty)
            if (_q <= 0 && _px > 0 && numClean(t.notional) > 0) _q = numClean(t.notional) / _px
            if (_q <= 0) _q = _heldNow
            _q = Math.min(_q, _heldNow) * SELL_SAFETY_CRYPTO
            t.qty = qtyStr(_q)
            delete t.notional
          } else {
            const _mv = heldMV[sym] || 0
            if (_mv > 0 && Number(t.notional) > _mv) t.notional = Math.floor(_mv * SELL_SAFETY_STOCK)
          }
        }
      }

      if (!isBuy) selling.add(sym)
      toExec.push(t)
    }

    const autoSells: any[] = []
    if (accountFrozen && Array.isArray(positions) && positions.length > 0) {
      let need = DELEVERAGE_TARGET_CASH - (cash || 0)
      if (need > 0) {
        const longs = positions
          .filter((p:any) => Number(p.qty) > 0 && p.asset_class !== 'crypto' && (Number(p.market_value)||0) >= 1)
          .sort((a:any,b:any) => (Number(b.market_value)||0) - (Number(a.market_value)||0))
        let raised = 0
        for (const p of longs) {
          if (raised >= need || autoSells.length >= DELEVERAGE_MAX_SELLS) break
          const sym = normSym(p.symbol)
          if (pending.has(sym) || selling.has(sym)) continue
          const mv = Number(p.market_value) || 0
          autoSells.push({ ticker: p.symbol, side: 'sell', qty: qtyStr(Math.abs(Number(p.qty)||0) * SELL_SAFETY_STOCK), notional: Math.floor(mv), asset_type: 'etf', archimage_prefix: prefix, _auto: 'deleverage' })
          selling.add(sym)
          raised += mv
        }
      }
    }
    for (const s of autoSells) toExec.push(s)

    const toExecFinal: any[] = []
    for (const t of toExec) {
      const sym = normSym(t.ticker)
      const q = numClean(t.qty)
      if (q > 0) {
        const px = heldPx[sym] || priceMap[sym] || 0
        const est = px > 0 ? q * px : numClean(t.notional)
        if (q < DUST_QTY_MIN || (px > 0 && est < DUST_USD_MIN)) {
          skipped.push({ ticker: t.ticker, side: t.side, reason: 'dust_unsellable', qty: String(q), est_usd: Math.round(est*100)/100 })
          continue
        }
        if (px > 0 && est > MAX_NOTIONAL_PER_ORDER) {
          const parts = Math.min(6, Math.ceil(est / MAX_NOTIONAL_PER_ORDER))
          const qPart = q / parts
          for (let i = 0; i < parts; i++) {
            toExecFinal.push({ ...t, qty: qtyStr(qPart), notional: Math.floor(est / parts), _chunk: `${i+1}/${parts}` })
          }
          continue
        }
      }
      toExecFinal.push(t)
    }

    if (toExecFinal.length === 0) {
      console.log('RUN_EMPTY ' + JSON.stringify({ archimage, run_id, market_open: marketOpen, total: allTrades.length, skipped: skipped.length, skipped_detail: skipped }))
      await dbg({ archimage: archimage || 'ND', run_id, market_open: marketOpen, total: allTrades.length, accepted: 0, rejected: 0, skipped: skipped.length, payload: { skipped_detail: skipped, results: [] } })
      return new Response(JSON.stringify({ archimage, run_id, market_phase: market_phase || 'ND', account: { buying_power: buyingPower, cash, equity, exposure_cap: Math.round(exposureCap), buy_budget: buyBudgetStart, market_open: marketOpen, frozen: accountFrozen, positions: Array.isArray(positions)?positions.length:null }, total_trades: allTrades.length, executed: 0, rejected: 0, skipped: skipped.length, skipped_detail: skipped, take_profit: 0, stop_loss: 0, deleverage_sells: 0, results: [], message: marketOpen ? 'Aucune action (achats filtres momentum/risque, aucune sortie declenchee)' : 'Marche US ferme: run crypto uniquement' }), { headers: { ...cors, 'Content-Type': 'application/json' } })
    }

    const tradesToExec = toExecFinal.slice(0, 60)
    const results = await Promise.allSettled(tradesToExec.map(t => placeOrder(alpaca_key, alpaca_secret, t, marketOpen)))
    const executed = results.map((r, i) => ({ ...tradesToExec[i], ...(r.status === 'fulfilled' ? r.value : { status: 'error', error: String(r.reason) }) }))
    const accepted = executed.filter(e => e.status === 'accepted').length
    const rejected = executed.filter(e => e.status === 'rejected' || e.status === 'error').length
    const tpCount = executed.filter(e => e.auto === 'take_profit' && e.status === 'accepted').length
    const slCount = executed.filter(e => e.auto === 'stop_loss' && e.status === 'accepted').length
    const deleverageCount = executed.filter(e => e.auto === 'deleverage' && e.status === 'accepted').length
    const shortCount = executed.filter(e => e.short && e.status === 'accepted').length
    const coverCount = executed.filter(e => e.cover && e.status === 'accepted').length

    console.log('RUN_DONE ' + JSON.stringify({ archimage, run_id, market_open: marketOpen, cash, buying_power: buyingPower, total: allTrades.length, accepted, rejected, skipped: skipped.length }))
    await dbg({ archimage: archimage || 'ND', run_id, market_open: marketOpen, total: allTrades.length, accepted, rejected, skipped: skipped.length, payload: { skipped_detail: skipped, results: executed.map(e => ({ t:e.ticker, side:e.side, raw_qty: (e.raw_qty_in != null ? e.raw_qty_in : null), qty:e.qty, notional:e.notional, type:e.order_type, status:e.status, alpaca:e.alpaca_status, err:e.error, clamped_from: (e._clamped_from != null ? e._clamped_from : null), short: (e.short || null), cover: (e.cover || null), mom: (e._mom != null ? e._mom : null), chunk: (e.chunk || null) })) } })

    if (SUPABASE_KEY) {
      const ordersToSave = executed.filter(e => e.status === 'accepted').map(e => ({ run_id, archimage: archimage || 'ND', symbol: e.ticker, side: e.side, asset_class: e.asset_type || 'etf', notional: e.notional, broker: 'alpaca', broker_order_id: e.alpaca_id || null, broker_status: e.alpaca_status || 'accepted', validated: true }))
      if (ordersToSave.length > 0) {
        await fetch(`${SUPABASE_URL}/rest/v1/oracle_college_orders`, { method: 'POST', headers: { 'apikey': SUPABASE_KEY, 'Authorization': `Bearer ${SUPABASE_KEY}`, 'Content-Type': 'application/json', 'Prefer': 'return=minimal' }, body: JSON.stringify(ordersToSave) }).catch(() => {})
      }
    }

    return new Response(JSON.stringify({ archimage, run_id, market_phase: market_phase || 'ND', account: { buying_power: buyingPower, cash, equity, exposure_cap: Math.round(exposureCap), buy_budget: buyBudgetStart, market_open: marketOpen, frozen: accountFrozen, positions: Array.isArray(positions)?positions.length:null }, total_trades: allTrades.length, executed: accepted, rejected, skipped: skipped.length, skipped_detail: skipped, take_profit: tpCount, stop_loss: slCount, deleverage_sells: deleverageCount, shorts: shortCount, covers: coverCount, results: executed }), { headers: { ...cors, 'Content-Type': 'application/json' } })
  } catch(e) {
    return new Response(JSON.stringify({ error: String(e) }), { status: 500, headers: { ...cors, 'Content-Type': 'application/json' } })
  }
})
