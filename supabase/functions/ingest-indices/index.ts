// ingest-indices : historique OHLCV d'indices/ETF via Alpaca AVEC pagination (next_page_token).
const SUPABASE_URL = Deno.env.get('SUPABASE_URL')!;
const SERVICE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
const cors = { 'Access-Control-Allow-Origin': '*', 'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type' };
const json = (d: unknown, s = 200) => new Response(JSON.stringify(d), { status: s, headers: { ...cors, 'Content-Type': 'application/json' } });
const AK = 'PK_REDACTED';
const AS = 'REDACTED';

async function upsert(rows: any[]): Promise<boolean> {
  const r = await fetch(`${SUPABASE_URL}/rest/v1/price_history?on_conflict=symbol,interval,ts`, {
    method: 'POST',
    headers: { apikey: SERVICE_KEY, Authorization: `Bearer ${SERVICE_KEY}`, 'Content-Type': 'application/json', Prefer: 'resolution=merge-duplicates,return=minimal' },
    body: JSON.stringify(rows),
  });
  return r.ok;
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: cors });
  try {
    const body = await req.json().catch(() => ({}));
    const symbols: string[] = body.symbols || ['SPY'];
    const start: string = body.start || new Date(Date.now() - 90 * 86400000).toISOString();
    const results: Record<string, any> = {};
    for (const sym of symbols) {
      let total = 0, pages = 0, err = '';
      let token: string | null = null;
      try {
        do {
          const u = new URL(`https://data.alpaca.markets/v2/stocks/${sym}/bars`);
          u.searchParams.set('timeframe', '1Hour');
          u.searchParams.set('start', start);
          u.searchParams.set('limit', '10000');
          u.searchParams.set('adjustment', 'raw');
          if (token) u.searchParams.set('page_token', token);
          const r = await fetch(u.toString(), { headers: { 'APCA-API-KEY-ID': AK, 'APCA-API-SECRET-KEY': AS }, signal: AbortSignal.timeout(15000) });
          if (!r.ok) { err = `http ${r.status}: ${(await r.text()).slice(0,120)}`; break; }
          const data = await r.json();
          const bars = data.bars || [];
          if (bars.length) {
            const rows = bars.map((b: any) => ({ symbol: sym, interval: '1h', ts: b.t, open: Number(b.o), high: Number(b.h), low: Number(b.l), close: Number(b.c), volume: Number(b.v) }));
            for (let i = 0; i < rows.length; i += 2000) { await upsert(rows.slice(i, i + 2000)); }
            total += rows.length;
          }
          token = data.next_page_token || null;
          pages++;
        } while (token && pages < 30);
        results[sym] = { bougies: total, pages, err: err || undefined };
      } catch (e: any) { results[sym] = { err: String(e?.message || e), bougies: total }; }
    }
    return json({ ok: true, results });
  } catch (e: any) { return json({ ok: false, error: String(e?.message || e) }); }
});
