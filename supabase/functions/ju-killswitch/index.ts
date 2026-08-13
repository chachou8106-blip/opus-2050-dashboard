// ju-killswitch — lit / bascule le kill_switch de l'Alchimiste (Revolut X argent reel).
// GET (ou POST {action:"status"}) -> etat courant.
// POST {action:"on"|"off"} -> arme / desarme. Service key cote serveur, verify_jwt=false.
import "jsr:@supabase/functions-js/edge-runtime.d.ts";

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "GET, POST, OPTIONS",
};
const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SERVICE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const json = (d: unknown, s = 200) =>
  new Response(JSON.stringify(d), { status: s, headers: { ...cors, "Content-Type": "application/json" } });

async function getKS(): Promise<string | null> {
  const r = await fetch(`${SUPABASE_URL}/rest/v1/ju_crypte_config?key=eq.kill_switch&select=value`, {
    headers: { apikey: SERVICE_KEY, Authorization: `Bearer ${SERVICE_KEY}` },
  });
  const j = await r.json().catch(() => []);
  return Array.isArray(j) && j[0] ? String(j[0].value) : null;
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  try {
    let action = "status";
    if (req.method === "POST") {
      const b = await req.json().catch(() => ({}));
      action = String(b?.action || "status").toLowerCase();
    } else {
      action = String(new URL(req.url).searchParams.get("action") || "status").toLowerCase();
    }

    if (action === "on" || action === "off") {
      const val = action === "on" ? "ON" : "OFF";
      const r = await fetch(`${SUPABASE_URL}/rest/v1/ju_crypte_config?key=eq.kill_switch`, {
        method: "PATCH",
        headers: { apikey: SERVICE_KEY, Authorization: `Bearer ${SERVICE_KEY}`, "Content-Type": "application/json", Prefer: "return=minimal" },
        body: JSON.stringify({ value: val }),
      });
      if (!r.ok) return json({ ok: false, error: `patch ${r.status} ${await r.text()}` }, 200);
    } else if (action !== "status") {
      return json({ ok: false, error: `action invalide: ${action} (attendu on|off|status)` }, 200);
    }

    const current = await getKS();
    return json({ ok: true, kill_switch: current, arme: String(current).toLowerCase() === "on" });
  } catch (e: any) {
    return json({ ok: false, error: String(e?.message || e) }, 200);
  }
});
