// ingest-klines — ingestion d'historique OHLCV crypto (Binance klines, public, sans cle).
// v3 : AUTO-DECOUVERTE + PARALLELISATION PAR LOTS (evite le timeout sur un grand univers).
// Sans 'symbols', ingere tout l'univers crypto propose (vue v_crypto_univers).
// limit=1000 -> 1000 dernieres bougies -> prix toujours frais. A appeler regulierement (pg_cron).

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SERVICE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};
const json = (d: unknown, s = 200) => new Response(JSON.stringify(d), { status: s, headers: { ...cors, "Content-Type": "application/json" } });

const DEFAULT_SYMBOLS = ["BTC-USD", "ETH-USD", "SOL-USD", "TON-USD", "ATOM-USD", "TRX-USD"];
const toBinance = (sym: string) => sym.replace("-USD", "") + "USDT";
const CHUNK = 8;

async function sbGet(path: string): Promise<any> {
  try {
    const r = await fetch(`${SUPABASE_URL}/rest/v1/${path}`, {
      headers: { apikey: SERVICE_KEY, Authorization: `Bearer ${SERVICE_KEY}` },
    });
    if (!r.ok) return null;
    return await r.json();
  } catch { return null; }
}

async function ingestOne(sym: string, interval: string, limit: number): Promise<string> {
  try {
    const bs = toBinance(sym);
    const url = `https://api.binance.com/api/v3/klines?symbol=${bs}&interval=${interval}&limit=${limit}`;
    const r = await fetch(url);
    if (!r.ok) return `binance http ${r.status}`;
    const kl = await r.json();
    if (!Array.isArray(kl) || kl.length === 0) return "aucune donnee";
    const rows = kl.map((k: any[]) => ({
      symbol: sym, interval,
      ts: new Date(k[0]).toISOString(),
      open: Number(k[1]), high: Number(k[2]), low: Number(k[3]), close: Number(k[4]), volume: Number(k[5]),
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
    return up.ok ? `ok ${rows.length}` : `db ${up.status}`;
  } catch (e: any) {
    return String(e?.message || e).slice(0, 80);
  }
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  try {
    const body = await req.json().catch(() => ({}));
    const interval: string = body.interval || "1h";
    const limit = Math.min(Number(body.limit) || 1000, 1000);

    let symbols: string[];
    if (Array.isArray(body.symbols) && body.symbols.length > 0) {
      symbols = body.symbols;
    } else {
      const univ = await sbGet("v_crypto_univers?select=paire");
      const fromUniv = Array.isArray(univ) ? univ.map((r: any) => r.paire).filter(Boolean) : [];
      symbols = Array.from(new Set([...DEFAULT_SYMBOLS, ...fromUniv]));
    }

    const results: Record<string, string> = {};
    let ok_count = 0, miss_count = 0;
    // traitement par lots paralleles pour eviter le timeout
    for (let i = 0; i < symbols.length; i += CHUNK) {
      const batch = symbols.slice(i, i + CHUNK);
      const settled = await Promise.all(batch.map((s) => ingestOne(s, interval, limit)));
      settled.forEach((res, j) => {
        results[batch[j]] = res;
        if (res.startsWith("ok")) ok_count++; else miss_count++;
      });
    }
    return json({ ok: true, interval, symboles_total: symbols.length, ingeres: ok_count, absents: miss_count, results });
  } catch (e: any) {
    return json({ ok: false, error: String(e?.message || e) });
  }
});
