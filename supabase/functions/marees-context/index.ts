// marees-context v1 — assemble TOUT ce que L'Archimage des Marees doit voir en 1 appel :
// switch + paires + plafonds (marees_config), le Conseil (5 Sages + actions JU/SYL/GIL + Alchimiste Revolut),
// et le contexte forex (fx-context). Lecture seule, service_role. Rien touche d'autre.
import "jsr:@supabase/functions-js/edge-runtime.d.ts";

const cors = { 'Access-Control-Allow-Origin':'*','Access-Control-Allow-Headers':'authorization, x-client-info, apikey, content-type' };
const SUPABASE_URL = Deno.env.get('SUPABASE_URL') || 'https://smddzybxebwhfnitxuyp.supabase.co';
const SRK = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') || '';

async function sb(path: string): Promise<any> {
  try { const r = await fetch(`${SUPABASE_URL}/rest/v1/${path}`, { headers: { apikey: SRK, Authorization: `Bearer ${SRK}` }, signal: AbortSignal.timeout(8000) }); return await r.json(); }
  catch { return null; }
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: cors });
  const cfgRows = await sb('marees_config?select=key,value');
  const cfg: Record<string,string> = Object.fromEntries((cfgRows || []).map((r: any) => [r.key, r.value]));
  const [sages, college, alch, fx] = await Promise.all([
    sb('oracle_sages_report?select=sage_name,sage_output,created_at&order=created_at.desc&limit=5'),
    sb('oracle_college_orders?select=archimage,symbol,side,rationale,created_at&order=created_at.desc&limit=24'),
    sb('alchimiste_crypte_propositions?select=paire,side,confidence,raison&statut=eq.proposee&order=proposed_at.desc&limit=10'),
    fetch(`${SUPABASE_URL}/functions/v1/fx-context`, { headers: { apikey: SRK, Authorization: `Bearer ${SRK}` }, signal: AbortSignal.timeout(12000) }).then((r) => r.json()).catch(() => ({ error: 'fx-context indisponible' }))
  ]);
  const body = {
    switch: (cfg.kill_switch || 'OFF'),
    armed: (cfg.kill_switch || '').toUpperCase() === 'ON',
    allowed_pairs: (cfg.allowed_pairs || '').split(',').map((s) => s.trim()).filter(Boolean),
    max_poids_pct: parseFloat(cfg.max_poids_pct || '5'),
    max_gross_pct: parseFloat(cfg.max_gross_pct || '50'),
    conseil: {
      sages: sages || [],
      archimages_actions: college || [],
      alchimiste_revolut: alch || []
    },
    fx_context: fx,
    directive: "Tu es L'ARCHIMAGE DES MAREES, mage forex du College. Tu vois tout le Conseil (5 Sages + les actions de JU/SYL/GIL + les propositions de l'Alchimiste Revolut) et le contexte forex. Propose des trades UNIQUEMENT sur allowed_pairs (format EUR-USD), portes par le differentiel de taux (carry) et le biais du dollar (DXY). Respecte max_poids_pct par position et max_gross_pct d'exposition brute. Tiens compte du spread/frais : ne propose PAS de micro-trade que le cout mange. Sortie STRICTEMENT JSON : {\"propositions\":[{\"paire\":\"EUR-USD\",\"side\":\"buy|sell\",\"poids_pct\":2.0,\"confidence\":6.5,\"raison\":\"...\",\"tp_pct\":1.0,\"sl_pct\":0.8}]}"
  };
  return new Response(JSON.stringify(body), { headers: { ...cors, 'Content-Type': 'application/json' } });
});
