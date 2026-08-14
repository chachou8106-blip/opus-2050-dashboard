// fx-context v1 — contexte forex dedie pour L'Archimage des Marees.
// Sources VERIFIEES : Frankfurter (FX), FRED (Fed FEDFUNDS, ECB ECBDFR, DXY DTWEXBGS,
// taux 10a DE/JP/GB via IRLTLT01, US DGS10). Aucune serie non testee.
import "jsr:@supabase/functions-js/edge-runtime.d.ts";

const cors = { 'Access-Control-Allow-Origin':'*','Access-Control-Allow-Headers':'authorization, x-client-info, apikey, content-type' };
const FRED_KEY = Deno.env.get('FRED_KEY') || 'REDACTED';
const SUPABASE_URL = Deno.env.get('SUPABASE_URL') || 'https://smddzybxebwhfnitxuyp.supabase.co';
const SRK = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') || '';

async function sf(url: string): Promise<any> {
  try { const r = await fetch(url, { signal: AbortSignal.timeout(8000) }); if (!r.ok) return { error: r.status }; return await r.json(); }
  catch (e) { return { error: String(e) }; }
}
const fv = (j: any) => { const n = parseFloat(j?.observations?.[0]?.value); return isFinite(n) ? n : null; };

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: cors });
  const F = `https://api.stlouisfed.org/fred/series/observations?api_key=${FRED_KEY}&file_type=json&limit=1&sort_order=desc&series_id=`;
  const [fx, fed, ecb, dxy, de10, jp10, gb10, us10] = await Promise.all([
    sf('https://api.frankfurter.app/latest?from=USD&to=EUR,JPY,GBP,CHF,AUD,CAD,NZD'),
    sf(F + 'FEDFUNDS'), sf(F + 'ECBDFR'), sf(F + 'DTWEXBGS'),
    sf(F + 'IRLTLT01DEM156N'), sf(F + 'IRLTLT01JPM156N'), sf(F + 'IRLTLT01GBM156N'), sf(F + 'DGS10')
  ]);
  const us10y = fv(us10), de10y = fv(de10), jp10y = fv(jp10), gb10y = fv(gb10);
  const diff = (a: number|null, b: number|null) => (a != null && b != null) ? Math.round((a - b) * 100) / 100 : null;
  const result: any = {
    snapshot_at: new Date().toISOString(),
    fx_rates: { usd_eur: fx?.rates?.EUR ?? null, usd_jpy: fx?.rates?.JPY ?? null, usd_gbp: fx?.rates?.GBP ?? null, usd_chf: fx?.rates?.CHF ?? null, usd_aud: fx?.rates?.AUD ?? null, usd_cad: fx?.rates?.CAD ?? null, usd_nzd: fx?.rates?.NZD ?? null },
    taux_directeurs: { fed: fv(fed), ecb: fv(ecb) },
    taux_10a: { us: us10y, allemagne: de10y, japon: jp10y, uk: gb10y },
    differentiels_10a: { us_vs_allemagne: diff(us10y, de10y), us_vs_japon: diff(us10y, jp10y), us_vs_uk: diff(us10y, gb10y) },
    dxy_indice_dollar: fv(dxy),
    directive: 'Contexte forex : privilegie les paires portees par le differentiel de taux (carry) et le biais du dollar (DXY). Tiens compte du spread/frais : pas de micro-trade que le cout mange.'
  };
  const dq = [result.fx_rates.usd_eur, result.taux_directeurs.fed, result.taux_directeurs.ecb, result.taux_10a.us, result.dxy_indice_dollar].filter((x) => x != null).length;
  result.data_quality = dq * 20;
  if (SRK) {
    fetch(`${SUPABASE_URL}/rest/v1/oracle_datasource_health`, {
      method: 'POST', headers: { apikey: SRK, Authorization: `Bearer ${SRK}`, 'Content-Type': 'application/json', Prefer: 'return=minimal' },
      body: JSON.stringify([{ source_name: 'fx_context', status: dq > 0 ? 'ok' : 'down', fields_populated: dq, fields_expected: 5 }]),
      signal: AbortSignal.timeout(5000)
    }).catch(() => {});
  }
  return new Response(JSON.stringify(result), { headers: { ...cors, 'Content-Type': 'application/json' } });
});
