// alc-auto v7 — EXECUTION SPOT ALIGNEE SUR LA REALITE REVOLUT X (buy + sell)
// -----------------------------------------------------------------------------
// v7 (03/09/2026) : LA BOUCLE SE REFERME. Aucune regle d'execution n'est touchee.
//   Constat du run de 15:45 : l'ordre BTC de 2,50 $ est passe pour de vrai, et la
//   proposition qui l'avait cause est restee avec oui_at = NULL et prix_exec = NULL.
//   Rien ne reliait la ligne de ju_crypte_orders a sa proposition.
//   1) On transmet proposition_id a revolut-x-trade.
//   2) Apres un ordre REEL accepte, on ecrit sur la proposition : oui_at, order_id,
//      et prix_exec quand Revolut l'a publie. Jamais de prix invente : si le prix
//      n'est pas mesure, la colonne reste NULL.
//   3) Le champ statut n'est TOUJOURS PAS touche : alc_rebuild_virtual ne lit que
//      les statuts 'proposee' et 'expiree', le portefeuille virtuel reste intact.
//   4) Garde-fou d'idempotence : en mode reel, une proposition qui porte deja un
//      oui_at est sautee. Ce garde-fou ne peut que RETENIR un ordre, jamais en
//      declencher un. Il protege du rejeu d'un meme run.
//   5) L'ecriture verifie son code HTTP et le remonte (regle du 31/08, aucun echec
//      muet). Elle ne peut pas faire echouer un ordre deja parti.
//
// v6 : corrige le bug repete "l'Alchimiste trade ce qui n'est pas tradable".
//
// Change vs v5 :
//  - SUPPRIME le garde-fou "sell-only" (v5). Revolut X est SPOT : l'action naturelle
//    est d'ACHETER avec le cash USD et de VENDRE ce qu'on detient de LIQUIDE. On
//    execute donc buy ET sell (cf oracle_contexte EXECUTION/revolut_x_spot +
//    oracle_problemes #2 : "reecrire la logique en long/flat adaptee au comptant").
//  - La TRADABILITE n'est plus la liste statique allowed_pairs (qui pointait des coins
//    STAKES = invendables). Elle vient de la REALITE LIVE :
//       * univers  -> revolut-x-prices (paires -USD reellement cotees bid/ask)
//       * soldes   -> revolut-x-read   (cash USD + positions detenues dispo/stake)
//    Regles :
//       * BUY  : paire -USD cotee ET cash USD dispo > 0  -> montant plafonne au cash restant
//       * SELL : actif de base DETENU et LIQUIDE (dispo>0, HORS stake) -> montant plafonne
//                a la valeur liquide detenue (dispo * bid)
//       * STAKING : un actif 100% stake est INVENDABLE tant que non destake. Le staking
//                n'est PAS automatisable (API Revolut X = 401 sur tous les endpoints staking,
//                cf revx-staking-probe). On le trace avec le delai de deblocage connu.
//  - allowed_pairs devient une whitelist OPTIONNELLE : "*" ou vide = tout l'univers -USD.
//    Une liste non-vide reste respectee comme restriction supplementaire.
//  - Money-locks INCHANGES (kill_switch, max_order_usd, max_daily_usd).
//  - dry_run / kill_switch ne sont JAMAIS modifies ici (geste reserve a Chachou).
//  - NE MODIFIE JAMAIS le statut des propositions (portefeuille virtuel intact).
//
// Schema de reponse conserve pour le message Discord (module lit resultats[].statut,
// side, paire, montant_execute, raison ; + kill_switch, a_executer, proposees).
import "jsr:@supabase/functions-js/edge-runtime.d.ts";

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
      ...(init?.headers || {}),
    },
  });
  try { return await r.json(); } catch { return null; }
}
// Ecriture qui rend son code HTTP. NE LEVE JAMAIS : elle intervient apres qu'un ordre
// est parti, et une exception ici ferait passer un ordre execute pour un ordre refuse.
async function sbPatch(path: string, patch: Record<string, unknown>): Promise<{ ok: boolean; status: number; error: string | null }> {
  try {
    const r = await fetch(`${SUPABASE_URL}/rest/v1/${path}`, {
      method: "PATCH",
      headers: {
        apikey: SERVICE_KEY,
        Authorization: `Bearer ${SERVICE_KEY}`,
        "Content-Type": "application/json",
        Prefer: "return=minimal",
      },
      body: JSON.stringify(patch),
    });
    if (r.ok) return { ok: true, status: r.status, error: null };
    let detail = ""; try { detail = await r.text(); } catch { /* corps illisible */ }
    return { ok: false, status: r.status, error: `${r.status} ${detail}`.trim() };
  } catch (e: any) {
    return { ok: false, status: 0, error: String(e?.message || e) };
  }
}
async function fn(slug: string, body: unknown): Promise<any> {
  const r = await fetch(`${SUPABASE_URL}/functions/v1/${slug}`, {
    method: "POST",
    headers: { apikey: SERVICE_KEY, Authorization: `Bearer ${SERVICE_KEY}`, "Content-Type": "application/json" },
    body: JSON.stringify(body ?? {}),
  });
  try { return await r.json(); } catch { return null; }
}
const json = (d: unknown, s = 200) =>
  new Response(JSON.stringify(d), { status: s, headers: { ...cors, "Content-Type": "application/json" } });

const num = (x: any) => Number(x) || 0;
const baseOf = (paire: string) => String(paire).toUpperCase().split("-")[0];
// GRAM = ex-Toncoin (TON). Meme actif -> on mappe la base sur le solde detenu.
const soldeKey = (dev: string) => (dev === "GRAM" ? "TON" : dev);

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  try {
    const body = await req.json().catch(() => ({}));
    const run_id: string | null = body.run_id ?? null;
    const dry_run: boolean = body.dry_run !== false;   // defaut: simule cote revolut-x-trade
    const simulate: boolean = body.simulate === true;  // n'appelle pas revolut-x-trade du tout

    if (!simulate && !dry_run && !run_id) {
      return json({ ok: false, reason: "run_id obligatoire en mode reel" });
    }

    // Config + money-locks (inchanges)
    const cfgRows = await sb("ju_crypte_config?select=key,value");
    const cfg: Record<string, string> = Object.fromEntries((cfgRows || []).map((r: any) => [r.key, r.value]));
    const killSwitch = (cfg.kill_switch || "").toLowerCase();
    const arme = killSwitch === "on";
    const rawAllowed = (cfg.allowed_pairs || "").trim();
    const whitelist = (rawAllowed === "" || rawAllowed === "*")
      ? null
      : new Set(rawAllowed.split(",").map((s: string) => s.trim()).filter(Boolean));
    const maxOrder = parseFloat(cfg.max_order_usd || "0");
    const maxDaily = parseFloat(cfg.max_daily_usd || "0");

    // Realite LIVE : univers tradable + soldes reels
    const [prices, read] = await Promise.all([fn("revolut-x-prices", {}), fn("revolut-x-read", {})]);
    const univers = new Map<string, { bid: number; ask: number }>();
    for (const t of (prices?.prix || [])) {
      const p = String(t.paire || "").toUpperCase();
      if (p.endsWith("-USD")) univers.set(p, { bid: num(t.bid), ask: num(t.ask) });
    }
    const soldes = new Map<string, { dispo: number; stake: number }>();
    for (const b of (read?.soldes || [])) {
      soldes.set(String(b.devise || "").toUpperCase(), { dispo: num(b.disponible), stake: num(b.stake) });
    }
    let cashUSD = soldes.get("USD")?.dispo ?? 0;

    const delaiRows = await sb("alc_staking_delais?select=devise,unbonding_jours");
    const delais: Record<string, string> = Object.fromEntries(
      (delaiRows || []).map((r: any) => [String(r.devise).toUpperCase(), String(r.unbonding_jours)]));

    // Propositions du cycle
    let q = "alchimiste_crypte_propositions?select=id,paire,side,montant,confidence,run_id,statut,oui_at,order_id&statut=eq.proposee&order=confidence.desc.nullslast,id.desc";
    if (run_id) q += `&run_id=eq.${encodeURIComponent(run_id)}`;
    else {
      const since = new Date(Date.now() - 20 * 60 * 1000).toISOString();
      q += `&proposed_at=gte.${since}`;
    }
    const props: any[] = (await sb(q)) || [];

    const today = new Date().toISOString().split("T")[0];
    const todayRows = await sb(`ju_crypte_orders?select=amount_usd&dry_run=eq.false&created_at=gte.${today}T00:00:00Z`);
    let plannedDaily = (todayRows || []).reduce((s: number, o: any) => s + num(o.amount_usd), 0);

    const results: any[] = [];
    for (const p of props) {
      const paire = String(p.paire || "").toUpperCase();
      const side = String(p.side || "").toLowerCase();
      let montant = num(p.montant);
      const base = baseOf(paire);
      const line: any = { id: p.id, paire, side, montant_demande: montant, confidence: p.confidence };

      if (!simulate && !arme) { line.statut = "bloque"; line.raison = `kill_switch=${cfg.kill_switch || "?"} (desarme)`; results.push(line); continue; }
      // Idempotence : deja executee (rejeu du meme run). Ne peut que retenir un ordre.
      if (!simulate && !dry_run && p.oui_at) {
        line.statut = "deja_executee";
        line.raison = `ordre deja passe le ${p.oui_at}${p.order_id ? ` (${p.order_id})` : ""}`;
        results.push(line); continue;
      }
      if (side !== "buy" && side !== "sell") { line.statut = "ignore"; line.raison = `side invalide (${p.side})`; results.push(line); continue; }
      if (whitelist && !whitelist.has(paire)) { line.statut = "ignore"; line.raison = "hors whitelist allowed_pairs"; results.push(line); continue; }
      const cote = univers.get(paire);
      if (!cote || (!(cote.bid > 0) && !(cote.ask > 0))) { line.statut = "ignore"; line.raison = "hors univers Revolut X (non cotee)"; results.push(line); continue; }
      if (!(montant > 0)) { line.statut = "ignore"; line.raison = "montant nul"; results.push(line); continue; }

      if (side === "buy") {
        if (!(cashUSD > 0)) { line.statut = "ignore"; line.raison = "cash USD insuffisant (rien a investir)"; results.push(line); continue; }
        const plafond = Math.min(maxOrder, cashUSD);
        if (montant > plafond) { montant = plafond; line.montant_plafonne = montant; }
      } else {
        const h = soldes.get(soldeKey(base)) || { dispo: 0, stake: 0 };
        if (!(h.dispo > 0)) {
          if (h.stake > 0) {
            const d = delais[base] ? ` (~${delais[base]}j deblocage, destake manuel in-app)` : "";
            line.statut = "ignore"; line.raison = `en stake, non vendable${d}`;
          } else {
            line.statut = "ignore"; line.raison = "non detenu (rien a vendre, pas de short sur spot)";
          }
          results.push(line); continue;
        }
        const valeurLiquide = h.dispo * cote.bid;
        const plafond = Math.min(maxOrder, valeurLiquide);
        if (montant > plafond) { montant = plafond; line.montant_plafonne = montant; }
        if (!(montant > 0)) { line.statut = "ignore"; line.raison = "valeur liquide detenue trop faible"; results.push(line); continue; }
      }

      if (plannedDaily + montant > maxDaily) { line.statut = "ignore"; line.raison = `plafond jour atteint (${plannedDaily}/${maxDaily})`; results.push(line); continue; }

      line.montant_execute = montant;
      if (simulate) {
        line.statut = arme ? "a_executer" : "a_executer_si_arme";
        plannedDaily += montant;
        if (side === "buy") cashUSD -= montant;
        results.push(line); continue;
      }

      const rr = await fn("revolut-x-trade", { pair: paire, side, amount: montant, dry_run, proposition_id: p.id });
      line.resultat = rr;
      if (rr?.ok) {
        line.statut = dry_run ? "simule" : "execute";
        if (!dry_run) plannedDaily += montant;
        if (side === "buy") cashUSD -= montant;
        // La boucle se referme : on relie la proposition a l'ordre reellement passe.
        // statut n'est PAS touche (le portefeuille virtuel continue de la lire).
        if (!dry_run) {
          // Number(null) vaut 0 et 0 est fini : sans le test > 0 on ecrirait un prix
          // d'execution de 0,00, qui est un mensonge. Pas de prix mesure -> NULL.
          const px = Number(rr.prix_exec);
          const maj = await sbPatch(`alchimiste_crypte_propositions?id=eq.${p.id}`, {
            oui_at: new Date().toISOString(),
            order_id: rr.order_id ?? null,
            prix_exec: Number.isFinite(px) && px > 0 ? px : null,
          });
          line.maj_proposition = maj.ok ? "ok" : `ECHEC ${maj.error}`;
        }
      } else {
        line.statut = "refuse"; line.raison = rr?.reason || rr?.error || "refuse";
      }
      results.push(line);
    }

    return json({
      ok: true,
      mode: simulate ? "simulate" : (dry_run ? "dry_run" : "reel"),
      kill_switch: cfg.kill_switch || null,
      arme,
      max_order_usd: maxOrder, max_daily_usd: maxDaily,
      whitelist: whitelist ? Array.from(whitelist) : "* (univers complet)",
      cash_usd: cashUSD,
      univers_count: univers.size,
      proposees: props.length,
      a_executer: results.filter((r) => ["a_executer", "a_executer_si_arme", "simule", "execute"].includes(r.statut)).length,
      resultats: results,
    });
  } catch (e: any) {
    return json({ ok: false, error: String(e?.message || e) }, 200);
  }
});
