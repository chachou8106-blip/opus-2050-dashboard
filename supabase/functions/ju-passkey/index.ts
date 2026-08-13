// ju-passkey — enregistrement + verification WebAuthn (Face ID) pour ARMER le kill_switch.
// Le PIN (ju-killswitch) reste en secours : ceci n'ajoute qu'une methode d'armement.
// verify_jwt=false ; clef service cote serveur ; origin/rpID verrouilles sur le domaine Netlify.
import {
  generateRegistrationOptions,
  verifyRegistrationResponse,
  generateAuthenticationOptions,
  verifyAuthenticationResponse,
} from "npm:@simplewebauthn/server@13";
import { isoBase64URL } from "npm:@simplewebauthn/server@13/helpers";

const RP_ID = "oracle-financier.netlify.app";
const ORIGIN = "https://oracle-financier.netlify.app";
const RP_NAME = "AETHER — OPUS 2050";

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "GET, POST, OPTIONS",
};
const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SERVICE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const json = (d: unknown, s = 200) =>
  new Response(JSON.stringify(d), { status: s, headers: { ...cors, "Content-Type": "application/json" } });

const H = { apikey: SERVICE_KEY, Authorization: `Bearer ${SERVICE_KEY}`, "Content-Type": "application/json" };
async function sbSelect(path: string): Promise<any[]> {
  const r = await fetch(`${SUPABASE_URL}/rest/v1/${path}`, { headers: H });
  const j = await r.json().catch(() => []);
  return Array.isArray(j) ? j : [];
}
async function setChallenge(purpose: string, challenge: string) {
  await fetch(`${SUPABASE_URL}/rest/v1/killswitch_webauthn`, {
    method: "POST",
    headers: { ...H, Prefer: "resolution=merge-duplicates,return=minimal" },
    body: JSON.stringify({ purpose, challenge, created_at: new Date().toISOString() }),
  });
}
async function getChallenge(purpose: string): Promise<string | null> {
  const rows = await sbSelect(`killswitch_webauthn?purpose=eq.${purpose}&select=challenge`);
  return rows[0]?.challenge ?? null;
}
async function listCreds(): Promise<any[]> {
  return await sbSelect("killswitch_passkeys?select=credential_id,public_key,counter,transports");
}
async function setKillSwitch(val: "ON" | "OFF") {
  await fetch(`${SUPABASE_URL}/rest/v1/ju_crypte_config?key=eq.kill_switch`, {
    method: "PATCH",
    headers: { ...H, Prefer: "return=minimal" },
    body: JSON.stringify({ value: val }),
  });
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  try {
    const body = await req.json().catch(() => ({}));
    const action = String(body?.action || "").toLowerCase();

    if (action === "list") {
      const creds = await listCreds();
      return json({ ok: true, count: creds.length, registered: creds.length > 0 });
    }

    if (action === "reg-options") {
      const creds = await listCreds();
      const opts = await generateRegistrationOptions({
        rpName: RP_NAME,
        rpID: RP_ID,
        userName: "JU — Alchimiste",
        userID: new TextEncoder().encode("ju-killswitch"),
        attestationType: "none",
        excludeCredentials: creds.map((c) => ({ id: c.credential_id })),
        authenticatorSelection: { residentKey: "preferred", userVerification: "preferred", authenticatorAttachment: "platform" },
      });
      await setChallenge("reg", opts.challenge);
      return json({ ok: true, options: opts });
    }

    if (action === "reg-verify") {
      const expectedChallenge = await getChallenge("reg");
      if (!expectedChallenge) return json({ ok: false, error: "challenge expire, reessaie" });
      const v = await verifyRegistrationResponse({
        response: body.response,
        expectedChallenge,
        expectedOrigin: ORIGIN,
        expectedRPID: RP_ID,
        requireUserVerification: false,
      });
      if (!v.verified || !v.registrationInfo) return json({ ok: false, error: "verification enregistrement echouee" });
      const cred = v.registrationInfo.credential;
      const transports = (body.response?.response?.transports || []).join(",");
      await fetch(`${SUPABASE_URL}/rest/v1/killswitch_passkeys`, {
        method: "POST",
        headers: { ...H, Prefer: "resolution=merge-duplicates,return=minimal" },
        body: JSON.stringify({
          credential_id: cred.id,
          public_key: isoBase64URL.fromBuffer(cred.publicKey),
          counter: cred.counter ?? 0,
          transports,
          label: body.label || "Face ID",
        }),
      });
      return json({ ok: true, registered: true });
    }

    if (action === "auth-options") {
      const creds = await listCreds();
      if (!creds.length) return json({ ok: false, error: "aucune passkey enregistree" });
      const opts = await generateAuthenticationOptions({
        rpID: RP_ID,
        userVerification: "preferred",
        allowCredentials: creds.map((c) => ({ id: c.credential_id, transports: c.transports ? c.transports.split(",").filter(Boolean) : undefined })),
      });
      await setChallenge("auth", opts.challenge);
      return json({ ok: true, options: opts });
    }

    if (action === "auth-verify") {
      const expectedChallenge = await getChallenge("auth");
      if (!expectedChallenge) return json({ ok: false, error: "challenge expire, reessaie" });
      const creds = await listCreds();
      const cred = creds.find((c) => c.credential_id === body.response?.id || c.credential_id === body.response?.rawId);
      if (!cred) return json({ ok: false, error: "passkey inconnue" });
      const v = await verifyAuthenticationResponse({
        response: body.response,
        expectedChallenge,
        expectedOrigin: ORIGIN,
        expectedRPID: RP_ID,
        requireUserVerification: false,
        credential: {
          id: cred.credential_id,
          publicKey: isoBase64URL.toBuffer(cred.public_key),
          counter: Number(cred.counter) || 0,
          transports: cred.transports ? cred.transports.split(",").filter(Boolean) : undefined,
        },
      });
      if (!v.verified) return json({ ok: false, error: "Face ID non verifie" });
      await fetch(`${SUPABASE_URL}/rest/v1/killswitch_passkeys?credential_id=eq.${encodeURIComponent(cred.credential_id)}`, {
        method: "PATCH", headers: { ...H, Prefer: "return=minimal" },
        body: JSON.stringify({ counter: v.authenticationInfo.newCounter }),
      });
      await setKillSwitch("ON"); // Face ID valide -> on ARME
      return json({ ok: true, armed: true, kill_switch: "ON" });
    }

    return json({ ok: false, error: `action invalide: ${action}` });
  } catch (e: any) {
    return json({ ok: false, error: String(e?.message || e) }, 200);
  }
});
