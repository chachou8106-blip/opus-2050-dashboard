// revolut-x-trade v8 — HARNAIS DE SECURITE + DRY-RUN (la crypte de JU / Revolut X)
// L'envoi reel (placeRealOrder) est ecrit par JU. Cadenas: kill_switch='ON' requis.
//
// v8 (03/09/2026) : JOURNALISATION SEULEMENT. Le chemin d'envoi n'est pas touche —
//       memes cadenas, meme corps d'ordre, memes plafonds, meme ordre des controles.
//       Constat du 03/09 : l'ordre reel de 15:49 est passe, et le prix paye n'existait
//       NULLE PART. ju_crypte_orders n'avait aucune colonne de prix, et placeRealOrder
//       jetait toute la reponse de Revolut sauf venue_order_id et state.
//       1) On garde la reponse brute (colonne reponse) : on ne devine pas le schema
//          de Revolut, on le MESURE. Le prix et la quantite sont extraits par balayage
//          des cles ; si rien ne correspond, ils restent NULL. Jamais de valeur inventee.
//       2) logOrder ne peut plus echouer en silence (regle du 31/08) : il rend le code
//          HTTP. Mais il ne LEVE JAMAIS d'exception apres qu'un ordre est parti — sinon
//          l'appelant croirait l'ordre refuse alors que l'argent a bouge. L'echec de
//          journal est signale dans la reponse (log_ok / log_error).
//       3) Toutes les lignes inserees portent les MEMES cles, a null quand la valeur
//          manque (regle du 31/08 sur les inserts heterogenes).
//       4) proposition_id optionnel : relie enfin l'ordre a la proposition qui l'a cause.
//
// v7 : le gate allowed_pairs devient une whitelist OPTIONNELLE. "*" ou vide => on suit
//       la realite (univers -USD + spot-check des soldes ci-dessous). Une liste explicite
//       reste respectee. Corrige le blocage "paire non autorisee" sur des paires pourtant
//       tradables/detenues (l'ancienne liste ne contenait que des coins stakes).
//       Les 4 cadenas monetaires sont INCHANGES.
//
// 4 cadenas independants avant qu'un centime bouge :
//   1) filtre [OFF] de la route Make   2) dry_run=true par defaut
//   3) kill_switch != 'ON'             4) spot-only dans placeRealOrder

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SERVICE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

async function sb(path: string, init?: RequestInit): Promise<any> {
  const r = await fetch(`${SUPABASE_URL}/rest/v1/${path}`, {
    ...init,
    headers: {
      apikey: SERVICE_KEY,
      Authorization: `Bearer ${SERVICE_KEY}`,
      "Content-Type": "application/json",
      Prefer: "return=minimal",
      ...(init?.headers || {}),
    },
  });
  try { return await r.json(); } catch { return null; }
}

const json = (data: unknown, status = 200) =>
  new Response(JSON.stringify(data), { status, headers: { ...cors, "Content-Type": "application/json" } });

// Toutes les lignes portent les memes cles (insert homogene, regle du 31/08).
type OrderRow = {
  pair: string; side: string; amount_usd: number;
  order_id: string; status: string; dry_run: boolean;
  prix_exec: number | null; qty_exec: number | null;
  proposition_id: number | null; reponse: unknown | null;
};

// NE LEVE JAMAIS. Un ordre parti reste un ordre parti, meme si le journal echoue :
// remonter une exception ici ferait passer un ordre execute pour un ordre refuse.
async function logOrder(row: OrderRow): Promise<{ ok: boolean; status: number; error: string | null }> {
  try {
    const r = await fetch(`${SUPABASE_URL}/rest/v1/ju_crypte_orders`, {
      method: "POST",
      headers: {
        apikey: SERVICE_KEY,
        Authorization: `Bearer ${SERVICE_KEY}`,
        "Content-Type": "application/json",
        Prefer: "return=minimal",
      },
      body: JSON.stringify(row),
    });
    if (r.ok) return { ok: true, status: r.status, error: null };
    let detail = ""; try { detail = await r.text(); } catch { /* corps illisible */ }
    return { ok: false, status: r.status, error: `${r.status} ${detail}`.trim() };
  } catch (e: any) {
    return { ok: false, status: 0, error: String(e?.message || e) };
  }
}

// Balayage de la reponse Revolut : on cherche un prix et une quantite SANS supposer
// le nom des champs. Priorite aux moyennes d'execution. Rien trouve -> null.
function pickNum(rec: any, patterns: RegExp[], depth = 3): number | null {
  for (const re of patterns) {
    const found = scan(rec, re, depth);
    if (found !== null) return found;
  }
  return null;
}
function scan(node: any, re: RegExp, depth: number): number | null {
  if (!node || typeof node !== "object" || depth < 0) return null;
  for (const [k, v] of Object.entries(node)) {
    // quote_size est le montant en USD qu'on a NOUS-MEMES envoye, pas une quantite
    // recue. Le prendre pour une quantite donnerait un prix de 1,00.
    if (/quote/i.test(k)) continue;
    if (re.test(k)) {
      const n = Number(v);
      if (Number.isFinite(n) && n > 0) return n;
    }
  }
  for (const v of Object.values(node)) {
    const n = scan(v, re, depth - 1);
    if (n !== null) return n;
  }
  return null;
}
const REVX_BASE = "https://revx.revolut.com";
const REVX_API_KEY = (Deno.env.get("REVX_API_KEY") || "").trim();
const REVX_PRIVATE_PEM = Deno.env.get("REVX_PRIVATE_KEY") || "";

function pemToPkcs8Bytes(pem: string): Uint8Array {
  const b = pem.replace(/-----BEGIN [A-Z ]+-----/g, "")
    .replace(/-----END [A-Z ]+-----/g, "").replace(/\s+/g, "");
  return Uint8Array.from(atob(b), (c) => c.charCodeAt(0));
}
async function importRevxKey(): Promise<CryptoKey> {
  return await crypto.subtle.importKey(
    "pkcs8", pemToPkcs8Bytes(REVX_PRIVATE_PEM),
    { name: "Ed25519" }, false, ["sign"]);
}
function b64(bytes: Uint8Array): string {
  let s = ""; for (const x of bytes) s += String.fromCharCode(x); return btoa(s);
}

async function revxSigned(
  method: "GET" | "POST", path: string, key: CryptoKey,
  query = "", bodyStr = "",
): Promise<{ status: number; body: any }> {
  const timestamp = Date.now().toString();
  const message = `${timestamp}${method}${path}${query}${bodyStr}`;
  const sig = new Uint8Array(await crypto.subtle.sign(
    { name: "Ed25519" }, key, new TextEncoder().encode(message)));
  const url = REVX_BASE + path + (query ? "?" + query : "");
  const r = await fetch(url, {
    method,
    headers: {
      "X-Revx-API-Key": REVX_API_KEY,
      "X-Revx-Timestamp": timestamp,
      "X-Revx-Signature": b64(sig),
      "Content-Type": "application/json",
      "Accept": "application/json",
    },
    ...(method === "POST" ? { body: bodyStr } : {}),
    signal: AbortSignal.timeout(12000),
  });
  let body: any; try { body = await r.json(); } catch { body = await r.text(); }
  return { status: r.status, body };
}

async function placeRealOrder(
  pair: string, side: string, amount: number,
): Promise<{ order_id: string; status: string; prix: number | null; qty: number | null; rec: any }> {
  if (!REVX_API_KEY || !REVX_PRIVATE_PEM) {
    throw new Error("Secrets Revolut X manquants (REVX_API_KEY / REVX_PRIVATE_KEY)");
  }
  const sideNorm = String(side).toLowerCase();
  if (sideNorm !== "buy" && sideNorm !== "sell") {
    throw new Error(`side invalide (spot-only buy|sell), recu: ${side}`);
  }
  const symbol = String(pair).trim().toUpperCase().replace("/", "-");
  const [base, quote] = symbol.split("-");
  if (!base || !quote) throw new Error(`pair mal forme (BASE-QUOTE): ${pair}`);

  const key = await importRevxKey();
  const num = (x: any) => Number(x) || 0;

  const bal = await revxSigned("GET", "/api/1.0/balances", key);
  if (bal.status !== 200) {
    throw new Error(`spot-check balances echoue: ${bal.status} ${JSON.stringify(bal.body)}`);
  }
  const balances = Array.isArray(bal.body) ? bal.body : (bal.body?.data || []);
  if (sideNorm === "buy") {
    const availQuote = balances
      .filter((b: any) => String(b.currency).toUpperCase() === quote)
      .reduce((s: number, b: any) => s + num(b.available), 0);
    if (availQuote < amount) {
      throw new Error(`SPOT-ONLY refuse: ${quote} dispo ${availQuote} < ${amount} USD (pas de levier)`);
    }
  } else {
    const availBase = balances
      .filter((b: any) => String(b.currency).toUpperCase() === base)
      .reduce((s: number, b: any) => s + num(b.available), 0);
    if (availBase <= 0) {
      throw new Error(`SPOT-ONLY refuse: aucune position ${base} a vendre (pas de short)`);
    }
  }

  const clientOrderId = crypto.randomUUID();
  const orderBody = {
    client_order_id: clientOrderId,
    symbol,
    side: sideNorm,
    order_configuration: { market: { quote_size: String(amount) } },
  };
  const bodyStr = JSON.stringify(orderBody);

  const res = await revxSigned("POST", "/api/1.0/orders", key, "", bodyStr);
  if (res.status < 200 || res.status >= 300) {
    throw new Error(`ordre refuse par Revolut X: ${res.status} ${JSON.stringify(res.body)}`);
  }

  const d = res.body?.data;
  const rec = Array.isArray(d) ? d[0] : (d || res.body);
  const order_id = rec?.venue_order_id;
  const status = rec?.state || "unknown";
  if (!order_id) {
    throw new Error(`reponse sans venue_order_id: ${JSON.stringify(res.body)}`);
  }

  // Lecture seule de la reponse deja recue : n'influence pas l'ordre, qui est parti.
  let prix = pickNum(rec, [
    /average.*price|avg.*price|fill.*price|executed.*price/i,
    /(^|_)price($|_)/i,
  ]);
  // Motifs volontairement ETROITS : mieux vaut un NULL honnete qu'une quantite fausse,
  // qui donnerait un prix faux et fausserait la mesure du spread. La reponse brute est
  // gardee en base : au premier ordre reel on lira les vrais noms de champs.
  const qty = pickNum(rec, [
    /(filled|executed).*(size|qty|quantity)/i,
    /(^|_)(base_size|base_quantity|base_qty)($|_)/i,
  ]);
  // A defaut de prix publie : le montant en USD divise par la quantite recue.
  // C'est de l'arithmetique sur deux valeurs mesurees, pas une estimation.
  if (prix === null && qty !== null && qty > 0) prix = amount / qty;

  return { order_id, status, prix, qty, rec };
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  try {
    const { pair, side, amount, dry_run = true, proposition_id = null } = await req.json();
    // Attention : Number(null) vaut 0, et 0 est fini. Sans le test > 0, chaque ordre
    // sans proposition serait lie a une proposition n0 qui n'existe pas.
    const nProp = Number(proposition_id);
    const propId = Number.isFinite(nProp) && nProp > 0 ? nProp : null;

    if (!pair || !side || !(Number(amount) > 0)) {
      return json({ ok: false, reason: "params invalides (pair / side / amount)" });
    }
    const amt = Number(amount);
    const symbolNorm = String(pair).trim().toUpperCase().replace("/", "-");

    const cfgRows = await sb("ju_crypte_config?select=key,value");
    const cfg: Record<string, string> = Object.fromEntries((cfgRows || []).map((r: any) => [r.key, r.value]));

    if ((cfg.kill_switch || "").toLowerCase() !== "on") {
      return json({ ok: false, reason: `kill_switch = ${cfg.kill_switch || "?"} (doit valoir 'ON' pour armer)` });
    }

    // Whitelist OPTIONNELLE : "*" ou vide => pas de filtre statique (on suit la realite).
    const rawAllowed = (cfg.allowed_pairs || "").trim();
    if (rawAllowed !== "" && rawAllowed !== "*") {
      const allowed = rawAllowed.split(",").map((s: string) => s.trim());
      if (!allowed.includes(symbolNorm)) {
        return json({ ok: false, reason: `paire ${pair} hors whitelist allowed_pairs` });
      }
    }
    // Contrainte structurelle spot : uniquement des paires -USD.
    if (!symbolNorm.endsWith("-USD")) {
      return json({ ok: false, reason: `paire ${pair} non -USD (spot USD uniquement)` });
    }

    const maxOrder = parseFloat(cfg.max_order_usd || "0");
    if (amt > maxOrder) {
      return json({ ok: false, reason: `montant ${amt} > plafond ordre ${maxOrder}` });
    }

    const today = new Date().toISOString().split("T")[0];
    const todayRows = await sb(`ju_crypte_orders?select=amount_usd&dry_run=eq.false&created_at=gte.${today}T00:00:00Z`);
    const dailyTotal = (todayRows || []).reduce((s: number, o: any) => s + Number(o.amount_usd || 0), 0);
    const maxDaily = parseFloat(cfg.max_daily_usd || "0");
    if (dailyTotal + amt > maxDaily) {
      return json({ ok: false, reason: `plafond journalier atteint (${dailyTotal}/${maxDaily})` });
    }

    if (dry_run !== false) {
      const logSim = await logOrder({
        pair: symbolNorm, side, amount_usd: amt,
        order_id: "DRY-" + Date.now(), status: "simulated", dry_run: true,
        prix_exec: null, qty_exec: null, proposition_id: propId, reponse: null,
      });
      return json({
        ok: true, dry_run: true, simulated: { pair: symbolNorm, side, amount: amt },
        reason: "dry_run=true, rien envoye",
        log_ok: logSim.ok, log_error: logSim.error,
      });
    }

    const order = await placeRealOrder(symbolNorm, side, amt);
    const logReel = await logOrder({
      pair: symbolNorm, side, amount_usd: amt,
      order_id: order.order_id, status: order.status, dry_run: false,
      prix_exec: order.prix, qty_exec: order.qty, proposition_id: propId,
      reponse: order.rec ?? null,
    });
    // ok:true meme si le journal a echoue — l'ordre EST parti, l'appelant doit le savoir.
    return json({
      ok: true, order_id: order.order_id, status: order.status,
      prix_exec: order.prix, qty_exec: order.qty,
      log_ok: logReel.ok, log_error: logReel.error,
    });
  } catch (e: any) {
    return json({ ok: false, error: String(e?.message || e) });
  }
});
