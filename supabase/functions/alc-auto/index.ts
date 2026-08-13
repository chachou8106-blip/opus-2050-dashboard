// alc-auto v6 — EXECUTION SPOT ALIGNEE SUR LA REALITE REVOLUT X (buy + sell)
// -----------------------------------------------------------------------------
// Corrige le bug repete "l'Alchimiste trade ce qui n'est pas tradable".
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

    // ── Config + money-locks (inchanges) ─────────────────────────────────────
    const cfgRows = await sb("ju_crypte_config?select=key,value");
    const cfg: Record<string, string> = Object.fromEntries((cfgRows || []).map((r: any) => [r.key, r.value]));
    const killSwitch = (cfg.kill_switch || "").toLowerCase();
    const arme = killSwitch === "on";
    const rawAllowed = (cfg.allowed_pairs || "").trim();
    // whitelist optionnelle : "*" ou vide => aucun filtre statique (on suit la realite live)
    const whitelist = (rawAllowed === "" || rawAllowed === "*")
      ? null
      : new Set(rawAllowed.split(",").map((s: string) => s.trim()).filter(Boolean));
    const maxOrder = parseFloat(cfg.max_order_usd || "0");
    const maxDaily = parseFloat(cfg.max_daily_usd || "0");

    // ── Realite LIVE : univers tradable + soldes reels ───────────────────────
    const [prices, read] = await Promise.all([fn("revolut-x-prices", {}), fn("revolut-x-read", {})]);
    // Univers : map paire -> {bid, ask}. Seules les paires -USD cotees sont tradables.
    const univers = new Map<string, { bid: number; ask: number }>();
    for (const t of (prices?.prix || [])) {
      const p = String(t.paire || "").toUpperCase();
      if (p.endsWith("-USD")) univers.set(p, { bid: num(t.bid), ask: num(t.ask) });
    }
    // Soldes : map devise -> {dispo, stake}. cashUSD = USD disponible.
    const soldes = new Map<string, { dispo: number; stake: number }>();
    for (const b of (read?.soldes || [])) {
      soldes.set(String(b.devise || "").toUpperCase(), { dispo: num(b.disponible), stake: num(b.stake) });
    }
    let cashUSD = soldes.get("USD")?.dispo ?? 0;

    // Delais de deblocage staking (pour tracer, pas pour executer)
    const delaiRows = await sb("alc_staking_delais?select=devise,unbonding_jours");
    const delais: Record<string, string> = Object.fromEntries(
      (delaiRows || []).map((r: any) => [String(r.devise).toUpperCase(), String(r.unbonding_jours)]));

    // ── Propositions du cycle ────────────────────────────────────────────────
    let q = "alchimiste_crypte_propositions?select=id,paire,side,montant,confidence,run_id,statut&statut=eq.proposee&order=confidence.desc.nullslast,id.desc";
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

      // 1) kill_switch (money-lock inchange)
      if (!simulate && !arme) { line.statut = "bloque"; line.raison = `kill_switch=${cfg.kill_switch || "?"} (desarme)`; results.push(line); continue; }
      // 2) sens valide (spot buy|sell uniquement)
      if (side !== "buy" && side !== "sell") { line.statut = "ignore"; line.raison = `side invalide (${p.side})`; results.push(line); continue; }
      // 3) whitelist optionnelle
      if (whitelist && !whitelist.has(paire)) { line.statut = "ignore"; line.raison = "hors whitelist allowed_pairs"; results.push(line); continue; }
      // 4) TRADABILITE : paire cotee dans l'univers Revolut X (-USD)
      const cote = univers.get(paire);
      if (!cote || (!(cote.bid > 0) && !(cote.ask > 0))) { line.statut = "ignore"; line.raison = "hors univers Revolut X (non cotee)"; results.push(line); continue; }
      // 5) montant valide
      if (!(montant > 0)) { line.statut = "ignore"; line.raison = "montant nul"; results.push(line); continue; }

      // 6) tradabilite reelle selon le sens (le coeur du correctif)
      if (side === "buy") {
        // il faut du cash USD (quote). On plafonne au cash restant.
        if (!(cashUSD > 0)) { line.statut = "ignore"; line.raison = "cash USD insuffisant (rien a investir)"; results.push(line); continue; }
        const plafond = Math.min(maxOrder, cashUSD);
        if (montant > plafond) { montant = plafond; line.montant_plafonne = montant; }
      } else {
        // SELL : il faut DETENIR l'actif et qu'il soit LIQUIDE (dispo>0, hors stake).
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
        const valeurLiquide = h.dispo * cote.bid; // valeur vendable au bid
        const plafond = Math.min(maxOrder, valeurLiquide);
        if (montant > plafond) { montant = plafond; line.montant_plafonne = montant; }
        if (!(montant > 0)) { line.statut = "ignore"; line.raison = "valeur liquide detenue trop faible"; results.push(line); continue; }
      }

      // 7) plafond journalier (money-lock inchange)
      if (plannedDaily + montant > maxDaily) { line.statut = "ignore"; line.raison = `plafond jour atteint (${plannedDaily}/${maxDaily})`; results.push(line); continue; }

      line.montant_execute = montant;
      if (simulate) {
        line.statut = arme ? "a_executer" : "a_executer_si_arme";
        plannedDaily += montant;
        if (side === "buy") cashUSD -= montant; // reserve le cash pour les buys suivants du meme cycle
        results.push(line); continue;
      }

      // 8) execution via revolut-x-trade (re-applique TOUS les verrous + check spot).
      const rr = await fn("revolut-x-trade", { pair: paire, side, amount: montant, dry_run });
      line.resultat = rr;
      if (rr?.ok) {
        line.statut = dry_run ? "simule" : "execute";
        if (!dry_run) plannedDaily += montant;
        if (side === "buy") cashUSD -= montant;
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
