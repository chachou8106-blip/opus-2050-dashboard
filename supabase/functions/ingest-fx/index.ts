// ingest-fx v2 — bougies 1h forex (Yahoo Finance) -> price_history (format EUR-USD).
// Isole : n'alimente QUE les paires forex. Anti-429 : User-Agent + delai + retry.
import "jsr:@supabase/functions-js/edge-runtime.d.ts";

const cors = { 'Access-Control-Allow-Origin':'*','Access-Control-Allow-Headers':'authorization, x-client-info, apikey, content-type' };
const SUPABASE_URL = Deno.env.get('SUPABASE_URL') || 'https://smddzybxebwhfnitxuyp.supabase.co';
const SRK = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') || '';
const UA = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0 Safari/537.36';
const sleep = (ms: number) => new Promise((r) => setTimeout(r, ms));

const PAIRS: Record<string,string> = {
  'EUR-USD':'EURUSD=X','GBP-USD':'GBPUSD=X','USD-JPY':'USDJPY=X','USD-CHF':'USDCHF=X',
  'AUD-USD':'AUDUSD=X','USD-CAD':'USDCAD=X','NZD-USD':'NZDUSD=X','EUR-JPY':'EURJPY=X',
  'GBP-JPY':'GBPJPY=X','EUR-GBP':'EURGBP=X'
};

async function yahoo(ysym: string, range: string): Promise<any> {
  const url = `https://query1.finance.yahoo.com/v8/finance/chart/${ysym}?interval=60m&range=${range}`;
  for (let attempt = 0; attempt < 3; attempt++) {
    const r = await fetch(url, { headers: { 'User-Agent': UA, 'Accept': 'application/json' }, signal: AbortSignal.timeout(12000) });
    if (r.ok) return await r.json();
    if (r.status === 429) { await sleep(2500 * (attempt + 1)); continue; }
    return { __err: 'http ' + r.status };
  }
  return { __err: 'http 429 (retries epuises)' };
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: cors });
  const range = new URL(req.url).searchParams.get('range') || '3mo';
  const summary: Record<string, unknown> = {};
  let total = 0;
  let first = true;
  for (const [sym, ysym] of Object.entries(PAIRS)) {
    try {
      if (!first) await sleep(1300);
      first = false;
      const j = await yahoo(ysym, range);
      if (j?.__err) { summary[sym] = j.__err; continue; }
      const res = j?.chart?.result?.[0];
      const ts: number[] = res?.timestamp || [];
      const q = res?.indicators?.quote?.[0] || {};
      const rows: Array<Record<string, unknown>> = [];
      for (let i = 0; i < ts.length; i++) {
        const o = q.open?.[i], h = q.high?.[i], l = q.low?.[i], c = q.close?.[i];
        if (o == null || h == null || l == null || c == null) continue;
        rows.push({ symbol: sym, interval: '1h', ts: new Date(ts[i] * 1000).toISOString(), open: o, high: h, low: l, close: c, volume: 0 });
      }
      if (rows.length) {
        const up = await fetch(`${SUPABASE_URL}/rest/v1/price_history?on_conflict=symbol,interval,ts`, {
          method: 'POST',
          headers: { apikey: SRK, Authorization: `Bearer ${SRK}`, 'Content-Type': 'application/json', Prefer: 'resolution=merge-duplicates,return=minimal' },
          body: JSON.stringify(rows), signal: AbortSignal.timeout(20000)
        });
        summary[sym] = up.ok ? rows.length : ('insert ' + up.status);
        if (up.ok) total += rows.length;
      } else summary[sym] = 0;
    } catch (e) { summary[sym] = 'err:' + String(e).slice(0, 60); }
  }
  return new Response(JSON.stringify({ ok: true, range, total_upserted: total, par_paire: summary }), { headers: { ...cors, 'Content-Type': 'application/json' } });
});
