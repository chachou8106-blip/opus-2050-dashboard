// ju-killswitch v2 — lit / bascule le kill_switch de l'Alchimiste (Revolut X argent reel).
// SECURITE:
//   - action "status" et "off" : LIBRES (desarmer va toujours dans le sens sur -> jamais de lockout).
//   - action "on" (ARMER argent reel) : exige un PIN correct, compare au secret stocke
//     dans ju_crypte_config.arm_pin (jamais expose au client). PIN modifiable en base.
// Service key cote serveur, verify_jwt=false.
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

async function cfg(): Promise<Record<string, string>> {
  const r = await fetch(`${SUPABASE_URL}/rest/v1/ju_crypte_config?select=key,value`, {
    headers: { apikey: SERVICE_KEY, Authorization: `Bearer ${SERVICE_KEY}` },
  });
  const rows = await r.json().catch(() => []);
  return Object.fromEntries((Array.isArray(rows) ? rows : []).map((x: any) => [x.key, x.value]));
}

async function setKS(val: "ON" | "OFF"): Promise<Response | null> {
  const r = await fetch(`${SUPABASE_URL}/rest/v1/ju_crypte_config?key=eq.kill_switch`, {
    method: "PATCH",
    headers: { apikey: SERVICE_KEY, Authorization: `Bearer ${SERVICE_KEY}`, "Content-Type": "application/json", Prefer: "return=minimal" },
    body: JSON.stringify({ value: val }),
  });
  return r.ok ? null : json({ ok: false, error: `patch ${r.status} ${await r.text()}` }, 200);
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  try {
    let action = "status", pin = "";
    if (req.method === "POST") {
      const b = await req.json().catch(() => ({}));
      action = String(b?.action || "status").toLowerCase();
      pin = String(b?.pin ?? "");
    } else {
      action = String(new URL(req.url).searchParams.get("action") || "status").toLowerCase();
    }

    const c = await cfg();

    if (action === "on") {
      const expected = String(c.arm_pin ?? "");
      if (!expected) return json({ ok: false, error: "aucun PIN configure cote serveur", need_pin: true }, 200);
      if (pin !== expected) return json({ ok: false, error: "PIN incorrect ou manquant", need_pin: true }, 200);
      const err = await setKS("ON");
      if (err) return err;
    } else if (action === "off") {
      const err = await setKS("OFF");
      if (err) return err;
    } else if (action !== "status") {
      return json({ ok: false, error: `action invalide: ${action} (attendu on|off|status)` }, 200);
    }

    const current = (await cfg()).kill_switch ?? null;
    return json({ ok: true, kill_switch: current, arme: String(current).toLowerCase() === "on" });
  } catch (e: any) {
    return json({ ok: false, error: String(e?.message || e) }, 200);
  }
});
