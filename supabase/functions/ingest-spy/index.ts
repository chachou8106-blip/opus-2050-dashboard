// ingest-spy — ingestion d'historique OHLCV actions (Alpaca Market Data API)
// pour permettre a evaluate_sages() de juger Macro/Technique contre le bon actif (SPY), pas contre BTC.

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SERVICE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};
const json = (d: unknown, s = 200) => new Response(JSON.stringify(d), { status: s, headers: { ...cors, "Content-Type": "application/json" } });

const ALPACA_KEY = "REDACTED";
const ALPACA_SECRET = "REDACTED";
const DEFAULT_SYMBOLS = ["SPY"];

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  try {
    const body = await req.json().catch(() => ({}));
    const symbols: string[] = body.symbols || DEFAULT_SYMBOLS;
    const start: string = body.start || new Date(Date.now() - 45 * 86400000).toISOString();
    const results: Record<string, string> = {};

    for (const sym of symbols) {
      try {
        const url = `https://data.alpaca.markets/v2/stocks/${sym}/bars?timeframe=1Hour&start=${encodeURIComponent(start)}&limit=10000&adjustment=raw`;
        const r = await fetch(url, { headers: { "APCA-API-KEY-ID": ALPACA_KEY, "APCA-API-SECRET-KEY": ALPACA_SECRET } });
        if (!r.ok) { results[sym] = `alpaca http ${r.status}: ${(await r.text()).slice(0,150)}`; continue; }
        const data = await r.json();
        const bars = data.bars || [];
        if (!Array.isArray(bars) || bars.length === 0) { results[sym] = "aucune donnee"; continue; }
        const rows = bars.map((b: any) => ({
          symbol: sym, interval: "1h",
          ts: b.t, open: Number(b.o), high: Number(b.h), low: Number(b.l), close: Number(b.c), volume: Number(b.v),
        }));
        const up = await fetch(`${SUPABASE_URL}/rest/v1/price_history?on_conflict=symbol,interval,ts`, {
          method: "POST",
          headers: {
            apikey: SERVICE_KEY, Authorization: `Bearer ${SERVICE_KEY}`,
            "Content-Type": "application/json",
            Prefer: "resolution=merge-duplicates,return=minimal",
          },
          body: JSON.stringify(rows),
        });
        results[sym] = up.ok ? `ok ${rows.length} bougies` : `db ${up.status}: ${(await up.text()).slice(0,120)}`;
      } catch (e: any) {
        results[sym] = String(e?.message || e);
      }
    }
    return json({ ok: true, results });
  } catch (e: any) {
    return json({ ok: false, error: String(e?.message || e) });
  }
});
