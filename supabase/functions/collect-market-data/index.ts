import { serve } from 'https://deno.land/std@0.168.0/http/server.ts'

// v3.3 — ajoute result.world (contexte marches mondiaux depuis la vue v_world_context) :
//        regime risk-on/off + variations des grands indices, injecte a CHAQUE archimage
//        via le contexte partage, SANS toucher au scenario Make. Bloc defensif (ne casse jamais le reste).
// v3.2 — cle Perplexity valide. v3.1 — completeness_pct retiree. v3 — sante par source.
const ENV = (k: string, fb: string) => Deno.env.get(k) || fb
const FRED_KEY = ENV('FRED_KEY', 'REDACTED')
const FINNHUB_KEY = ENV('FINNHUB_KEY', 'REDACTED')
const PLEX_KEY = ENV('PLEX_KEY', 'REDACTED')
const ALPACA_KEY = ENV('ALPACA_DATA_KEY', 'REDACTED')
const ALPACA_SECRET = ENV('ALPACA_DATA_SECRET', 'REDACTED')
const SUPABASE_URL = Deno.env.get('SUPABASE_URL') || 'https://smddzybxebwhfnitxuyp.supabase.co'
const SRK = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') || ''

const DATA = 'https://data.alpaca.markets'
const PAPER = 'https://paper-api.alpaca.markets'

const UNIVERSE: Record<string, string[]> = {
  tech: ['AAPL','MSFT','NVDA','AVGO','AMD','CRM','ORCL','ADBE','QCOM','MU','PLTR','NOW','SMCI','ARM','PANW'],
  comm: ['GOOGL','META','NFLX','DIS','TMUS','T','VZ','SPOT'],
  cons_disc: ['AMZN','TSLA','HD','NKE','MCD','SBUX','LOW','BKNG','CMG','ABNB'],
  cons_staples: ['WMT','COST','PG','KO','PEP','PM','MO','MDLZ'],
  health: ['UNH','JNJ','LLY','ABBV','MRK','PFE','TMO','ABT','ISRG','VRTX'],
  financials: ['JPM','BAC','WFC','GS','MS','BLK','V','MA','AXP','SCHW','C'],
  energy: ['XOM','CVX','COP','SLB','EOG','MPC','PSX'],
  industrials: ['CAT','BA','GE','HON','UPS','RTX','DE','LMT','UBER'],
  materials: ['LIN','FCX','NEM','APD','NUE'],
  utilities: ['NEE','DUK','SO','SRE','VST'],
  real_estate: ['PLD','AMT','O','SPG','EQIX']
}
const BROAD_ETF = ['SPY','QQQ','IWM','DIA','VTI']
const SECTOR_ETF = ['XLK','XLF','XLE','XLV','XLY','XLP','XLU','XLI','XLB','XLRE','XLC']
const MACRO_ETF = ['TLT','IEF','HYG','LQD','GLD','SLV','USO','UNG','DBC']
const INTL_ETF = ['EFA','VEA','VWO','EEM','FXI','EWZ','INDA','EWJ']
const CRYPTO_FALLBACK = ['BTC','ETH','SOL','DOGE','AVAX','LINK','LTC','BCH','UNI','AAVE','XRP','DOT','SHIB','MKR','GRT','SUSHI','YFI','BAT','XTZ','CRV']

function rotate<T>(arr: T[], offset: number): T[] {
  if (!arr.length) return arr
  const o = ((offset % arr.length) + arr.length) % arr.length
  return arr.slice(o).concat(arr.slice(0, o))
}

async function safeFetch(url: string, options: RequestInit = {}): Promise<any> {
  try {
    const r = await fetch(url, { ...options, signal: AbortSignal.timeout(8000) })
    if (!r.ok) return { error: r.status, url: url.substring(0, 60) }
    return await r.json()
  } catch(e) { return { error: String(e) } }
}

serve(async (req) => {
  const cors = {
    'Access-Control-Allow-Origin': '*',
    'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  }
  if (req.method === 'OPTIONS') return new Response('ok', { headers: cors })

  try {
    const fredBase = `https://api.stlouisfed.org/fred/series/observations?api_key=${FRED_KEY}&file_type=json&limit=1&sort_order=desc&series_id=`
    const alpacaH = { 'APCA-API-KEY-ID': ALPACA_KEY, 'APCA-API-SECRET-KEY': ALPACA_SECRET }
    const plexH = { 'Authorization': `Bearer ${PLEX_KEY}`, 'Content-Type': 'application/json' }

    const [vix, fed, cpi, t10y, t2y, unemp, spy, btcFh, crypto, fg, fx, alpAcc, alpPos, newsM, newsC, newsF,
           mostActives, moversStocks, moversCrypto, cryptoAssets, cgBroad] = await Promise.all([
      safeFetch(fredBase + 'VIXCLS'),
      safeFetch(fredBase + 'FEDFUNDS'),
      safeFetch(fredBase + 'CPIAUCSL'),
      safeFetch(fredBase + 'DGS10'),
      safeFetch(fredBase + 'DGS2'),
      safeFetch(fredBase + 'UNRATE'),
      safeFetch(`https://finnhub.io/api/v1/quote?symbol=SPY&token=${FINNHUB_KEY}`),
      safeFetch(`https://finnhub.io/api/v1/quote?symbol=BINANCE:BTCUSDT&token=${FINNHUB_KEY}`),
      safeFetch('https://api.coingecko.com/api/v3/coins/markets?vs_currency=usd&ids=bitcoin,ethereum,solana,dogecoin,avalanche-2&order=market_cap_desc&sparkline=false&price_change_percentage=24h'),
      safeFetch('https://api.alternative.me/fng/?limit=1'),
      safeFetch('https://api.frankfurter.app/latest?from=USD&to=EUR,JPY,GBP,CHF,AUD'),
      safeFetch(PAPER + '/v2/account', { headers: alpacaH }),
      safeFetch(PAPER + '/v2/positions', { headers: alpacaH }),
      fetch('https://api.perplexity.ai/chat/completions', { method:'POST', headers:plexH,
        body: JSON.stringify({ model:'sonar-pro', temperature:0.01, max_tokens:600,
          messages:[{role:'system',content:'Search web for top 5 breaking financial market headlines NOW. Return ONLY JSON no markdown: {"headlines":["h1","h2","h3","h4","h5"],"market_sentiment":"bullish|bearish|neutral","key_catalyst":"80chars","urgency":"high|medium|low"}'},
          {role:'user',content:`Date: ${new Date().toISOString()}. Top 5 financial headlines.`}]})
      }).then(r=>r.ok?r.json():{error:r.status}).catch(e=>({error:String(e)})),
      fetch('https://api.perplexity.ai/chat/completions', { method:'POST', headers:plexH,
        body: JSON.stringify({ model:'sonar-pro', temperature:0.01, max_tokens:500,
          messages:[{role:'system',content:'Search for top 5 crypto news. Return ONLY JSON: {"crypto_headlines":["h1","h2","h3","h4","h5"],"btc_sentiment":"bullish|bearish|neutral","whale_activity":"high|low|none","defi_signal":"active|quiet"}'},
          {role:'user',content:`Date: ${new Date().toISOString()}. Latest crypto news.`}]})
      }).then(r=>r.ok?r.json():{error:r.status}).catch(e=>({error:String(e)})),
      fetch('https://api.perplexity.ai/chat/completions', { method:'POST', headers:plexH,
        body: JSON.stringify({ model:'sonar', temperature:0.01, max_tokens:300,
          messages:[{role:'system',content:'Forex and macro central bank news. Return ONLY JSON: {"forex_headlines":["h1","h2","h3"],"usd_bias":"strong|weak|neutral","central_bank_news":"80chars","macro_shock":"yes|no"}'},
          {role:'user',content:`Date: ${new Date().toISOString()}. Forex macro news.`}]})
      }).then(r=>r.ok?r.json():{error:r.status}).catch(e=>({error:String(e)})),
      safeFetch(DATA + '/v1beta1/screener/stocks/most-actives?top=30', { headers: alpacaH }),
      safeFetch(DATA + '/v1beta1/screener/stocks/movers?top=20', { headers: alpacaH }),
      safeFetch(DATA + '/v1beta1/screener/crypto/movers?top=20', { headers: alpacaH }),
      safeFetch(PAPER + '/v2/assets?asset_class=crypto&status=active', { headers: alpacaH }),
      safeFetch('https://api.coingecko.com/api/v3/coins/markets?vs_currency=usd&order=market_cap_desc&per_page=25&page=1&sparkline=false&price_change_percentage=24h')
    ])

    const parseAI = (resp: any) => {
      try { const t = resp?.choices?.[0]?.message?.content||'{}'; return JSON.parse(t.replace(/```json/g,'').replace(/```/g,'').trim()) }
      catch { return {} }
    }
    const nM = parseAI(newsM), nC = parseAI(newsC), nF = parseAI(newsF)

    const now = new Date()
    const doy = Math.floor((now.getTime() - Date.UTC(now.getUTCFullYear(),0,0)) / 86400000)
    const off = doy * 24 + now.getUTCHours()
    const flat: any[] = []
    for (const [sec, arr] of Object.entries(UNIVERSE)) for (const t of arr) flat.push({ t, sector: sec })
    const rotating_focus = rotate(flat, off).slice(0, 32)

    const pickMover = (x:any) => ({ symbol: x?.symbol, pct: x?.percent_change ?? null, price: x?.price ?? null })
    const gainers = Array.isArray(moversStocks?.gainers) ? moversStocks.gainers.slice(0,12).map(pickMover) : []
    const losers  = Array.isArray(moversStocks?.losers)  ? moversStocks.losers.slice(0,12).map(pickMover)  : []
    const cgainers = Array.isArray(moversCrypto?.gainers) ? moversCrypto.gainers.slice(0,8).map(pickMover) : []
    const closers  = Array.isArray(moversCrypto?.losers)  ? moversCrypto.losers.slice(0,8).map(pickMover)  : []
    const most_active = Array.isArray(mostActives?.most_actives) ? mostActives.most_actives.slice(0,15).map((x:any)=>x?.symbol).filter(Boolean) : []

    let tradeable_crypto = CRYPTO_FALLBACK
    if (Array.isArray(cryptoAssets)) {
      const syms = cryptoAssets.filter((a:any)=>a?.tradable).map((a:any)=> String(a?.symbol||'').replace('/USD','').replace(/USD$/,'')).filter(Boolean)
      if (syms.length >= 5) tradeable_crypto = Array.from(new Set(syms)).slice(0, 35)
    }
    const crypto_top_mcap = Array.isArray(cgBroad) ? cgBroad.slice(0,25).map((c:any)=>({ sym: String(c?.symbol||'').toUpperCase(), price: c?.current_price ?? null, pct24h: c?.price_change_percentage_24h ?? null })) : []

    const result: any = {
      snapshot_at: new Date().toISOString(),
      macro: {
        vix: vix?.observations?.[0]?.value ?? null,
        fed_rate: fed?.observations?.[0]?.value ?? null,
        cpi: cpi?.observations?.[0]?.value ?? null,
        t10y: t10y?.observations?.[0]?.value ?? null,
        t2y: t2y?.observations?.[0]?.value ?? null,
        unemployment: unemp?.observations?.[0]?.value ?? null,
      },
      equities: {
        spy_price: spy?.c ?? null,
        spy_change_pct: spy?.dp ?? null,
        spy_prev_close: spy?.pc ?? null,
      },
      crypto: {
        btc_price: btcFh?.c ?? crypto?.[0]?.current_price ?? null,
        btc_24h_pct: crypto?.[0]?.price_change_percentage_24h ?? null,
        eth_price: crypto?.[1]?.current_price ?? null,
        eth_24h_pct: crypto?.[1]?.price_change_percentage_24h ?? null,
        sol_price: crypto?.[2]?.current_price ?? null,
        doge_price: crypto?.[3]?.current_price ?? null,
        avax_price: crypto?.[4]?.current_price ?? null,
        fear_greed: parseInt(fg?.data?.[0]?.value ?? '50'),
        fear_greed_label: fg?.data?.[0]?.value_classification ?? 'Neutral',
      },
      forex: {
        usd_eur: fx?.rates?.EUR ?? null,
        usd_jpy: fx?.rates?.JPY ?? null,
        usd_gbp: fx?.rates?.GBP ?? null,
        usd_chf: fx?.rates?.CHF ?? null,
        usd_aud: fx?.rates?.AUD ?? null,
      },
      portfolio: {
        cash: parseFloat(alpAcc?.cash ?? '80000'),
        portfolio_value: parseFloat(alpAcc?.portfolio_value ?? '80000'),
        buying_power: parseFloat(alpAcc?.buying_power ?? '80000'),
        equity: parseFloat(alpAcc?.equity ?? '80000'),
        positions_count: Array.isArray(alpPos) ? alpPos.length : 0,
        positions: Array.isArray(alpPos) ? alpPos.map((p:any) => ({
          symbol: p.symbol, qty: p.qty, side: p.side,
          market_value: parseFloat(p.market_value ?? '0'),
          unrealized_pnl: parseFloat(p.unrealized_pl ?? '0'),
          current_price: parseFloat(p.current_price ?? '0')
        })) : []
      },
      news: {
        market_headlines: nM?.headlines ?? [],
        market_sentiment: nM?.market_sentiment ?? 'neutral',
        key_catalyst: nM?.key_catalyst ?? 'ND',
        urgency: nM?.urgency ?? 'low',
        crypto_headlines: nC?.crypto_headlines ?? [],
        btc_sentiment: nC?.btc_sentiment ?? 'neutral',
        whale_activity: nC?.whale_activity ?? 'none',
        defi_signal: nC?.defi_signal ?? 'quiet',
        forex_headlines: nF?.forex_headlines ?? [],
        usd_bias: nF?.usd_bias ?? 'neutral',
        central_bank_news: nF?.central_bank_news ?? 'ND',
        macro_shock: nF?.macro_shock ?? 'no',
      },
      universe: {
        rotating_focus,
        movers_gainers: gainers,
        movers_losers: losers,
        most_active,
        crypto_gainers: cgainers,
        crypto_losers: closers,
        crypto_top_mcap,
        tradeable_crypto,
        broad_etf: BROAD_ETF,
        sector_etf: SECTOR_ETF,
        macro_etf: MACRO_ETF,
        intl_etf: INTL_ETF,
        directive: 'Pioche DANS cet univers. Chaque archimage doit varier ses choix et se differencier des deux autres. Interdiction de te limiter a SPY/GLD/QQQ ou aux 5 memes cryptos. Justifie chaque ligne par une donnee (mover, secteur, catalyseur news, regime macro).'
      },
      data_quality: Math.round([
        vix?.observations?.[0]?.value, fed?.observations?.[0]?.value,
        cpi?.observations?.[0]?.value, t10y?.observations?.[0]?.value,
        spy?.c, btcFh?.c ?? crypto?.[0]?.current_price,
        fg?.data?.[0]?.value, alpAcc?.cash,
        nM?.market_sentiment, nC?.btc_sentiment
      ].filter(x => x != null && x !== undefined).length * 10),
      universe_quality: Math.round([
        rotating_focus.length>0, gainers.length>0, most_active.length>0,
        tradeable_crypto.length>5, crypto_top_mcap.length>0
      ].filter(Boolean).length * 20)
    }

    // v3.3 : contexte marches mondiaux (indices + regime) injecte a chaque archimage. Bloc defensif.
    try {
      const wr = await fetch(`${SUPABASE_URL}/rest/v1/v_world_context?select=contexte_mondial`, { headers: { apikey: SRK, Authorization: `Bearer ${SRK}` }, signal: AbortSignal.timeout(5000) })
      if (wr.ok) { const wj = await wr.json(); if (Array.isArray(wj) && wj[0]?.contexte_mondial) result.world = wj[0].contexte_mondial }
    } catch { /* le monde est optionnel : ne casse jamais le contexte */ }

    if (SRK) {
      const cnt = (arr: any[]) => arr.filter(x => x != null).length
      const mkRow = (name: string, popul: number, expected: number, err: any) => ({
        source_name: name,
        status: popul > 0 ? 'ok' : 'down',
        fields_populated: popul,
        fields_expected: expected,
        error_message: popul > 0 ? null : String(err?.error ?? 'no data').slice(0, 150)
      })
      const healthRows = [
        mkRow('fred', cnt([result.macro.vix, result.macro.fed_rate, result.macro.cpi, result.macro.t10y, result.macro.t2y, result.macro.unemployment]), 6, vix),
        mkRow('finnhub_spy', cnt([result.equities.spy_price, result.equities.spy_change_pct, result.equities.spy_prev_close]), 3, spy),
        mkRow('coingecko', cnt([result.crypto.btc_price, result.crypto.eth_price, result.crypto.sol_price, result.crypto.doge_price, result.crypto.avax_price]), 5, crypto),
        mkRow('fear_greed', cnt([fg?.data?.[0]?.value]), 1, fg),
        mkRow('frankfurter_fx', cnt([result.forex.usd_eur, result.forex.usd_jpy, result.forex.usd_gbp, result.forex.usd_chf, result.forex.usd_aud]), 5, fx),
        mkRow('alpaca_account', cnt([alpAcc?.cash, alpAcc?.portfolio_value]), 2, alpAcc),
        mkRow('alpaca_screener', cnt([gainers.length || null, most_active.length || null, (tradeable_crypto.length > 5 ? 1 : null)]), 3, moversStocks),
        mkRow('perplexity_news', cnt([nM?.market_sentiment, nC?.btc_sentiment, nF?.usd_bias]), 3, newsM),
      ]
      await fetch(`${SUPABASE_URL}/rest/v1/oracle_datasource_health`, {
        method: 'POST',
        headers: { apikey: SRK, Authorization: `Bearer ${SRK}`, 'Content-Type': 'application/json', Prefer: 'return=minimal' },
        body: JSON.stringify(healthRows),
        signal: AbortSignal.timeout(5000)
      }).catch(() => {})
    }

    return new Response(JSON.stringify(result), {
      headers: { ...cors, 'Content-Type': 'application/json' }
    })
  } catch(e) {
    return new Response(JSON.stringify({ error: String(e), snapshot_at: new Date().toISOString(), data_quality: 0 }), {
      status: 500, headers: { ...cors, 'Content-Type': 'application/json' }
    })
  }
})
