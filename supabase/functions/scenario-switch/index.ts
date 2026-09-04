// scenario-switch v4 — les trois boutons de la console, avec MAKE comme planificateur.
// 04/09/2026 : « répare ma console pour que ça fonctionne comme avant mais avec Make programmé ».
//
// Modèle : les 4 créneaux (09h00 · 15h45 · 18h30 · 21h15) sont dans Make. Supabase ne
// planifie plus rien et ne programme plus de coupure — c'est elle qui éteignait le scénario
// que Make venait d'allumer.
//   on      → scenario_control.actif = true  PUIS /start : le scénario Make est ALLUMÉ.
//             (avant : le booléen basculait, et rien ne partait chez Make.)
//   off     → actif = false PUIS /stop. La sentinelle respecte ce false et ne rallume pas.
//   run-now → scenario_fire(force) qui, sous planificateur=make, appelle /run : UNE exécution
//             tout de suite, sans toucher à l'activation et sans coupure 3 min après.
// PIN-gardé (arm_pin) ; status reste en lecture libre.
const SUPABASE_URL = Deno.env.get('SUPABASE_URL')!
const SRK = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
const cors = { 'Access-Control-Allow-Origin': '*', 'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type', 'Access-Control-Allow-Methods': 'POST, OPTIONS' }
const json = (d: unknown, s = 200) => new Response(JSON.stringify(d), { status: s, headers: { ...cors, 'Content-Type': 'application/json' } })

async function sb(path: string, init?: RequestInit) {
  const r = await fetch(`${SUPABASE_URL}/rest/v1/${path}`, { ...init, headers: { apikey: SRK, Authorization: `Bearer ${SRK}`, 'Content-Type': 'application/json', ...(init?.headers || {}) } })
  try { return { ok: r.ok, status: r.status, body: await r.json() } } catch { return { ok: r.ok, status: r.status, body: null } }
}
const etat = async () => { const r = await sb('v_scenario_etat?select=*'); return Array.isArray(r.body) ? (r.body[0] || null) : null }
async function checkPin(pin: unknown) {
  const pr = await sb('ju_crypte_config?key=eq.arm_pin&select=value')
  const p = Array.isArray(pr.body) && pr.body[0] ? String(pr.body[0].value) : null
  return !!p && String(pin || '') === p
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: cors })
  try {
    const b = await req.json().catch(() => ({}))
    const action = (b.action || 'status').toString()

    if (action === 'status') return json({ ok: true, etat: await etat() })

    if (action === 'on' || action === 'off') {
      if (!(await checkPin(b.pin))) return json({ ok: false, error: 'PIN incorrect' })
      await sb('scenario_control?id=eq.1', { method: 'PATCH', headers: { Prefer: 'return=minimal' }, body: JSON.stringify({ actif: action === 'on', updated_at: new Date().toISOString(), updated_by: 'console' }) })
      // « Couper » = sécurité : on désactive AUSSI le scénario Make tout de suite (au cas où un run est en cours).
      // « Activer » = symétrique : on ALLUME le scénario Make. Sans ça le bouton ne faisait
      //   que basculer un booléen — c'est ce que Chachou a constaté le 04/09.
      const rpc = action === 'on' ? 'rpc/scenario_start_now' : 'rpc/scenario_stop_now'
      const rr = await sb(rpc, { method: 'POST', body: '{}' })
      // L'état réel de Make n'est mesuré que toutes les 5 min : sans ça la console
      // renverrait l'ancienne mesure et le bouton aurait l'air de n'avoir rien fait.
      // scenario_make_sync est en deux temps (récolte la réponse précédente, lance la
      // suivante) : deux appels espacés donnent une mesure FRAÎCHE, pas une supposition.
      await sb('rpc/scenario_make_sync', { method: 'POST', body: '{}' })
      await new Promise((r) => setTimeout(r, 2000))
      await sb('rpc/scenario_make_sync', { method: 'POST', body: '{}' })
      return json({ ok: true, make: rr.body ?? null, etat: await etat() })
    }

    if (action === 'run-now') {
      if (!(await checkPin(b.pin))) return json({ ok: false, error: 'PIN incorrect' })
      const rc = await sb('rpc/scenario_fire', { method: 'POST', body: JSON.stringify({ p_force: true }) })
      return json({ ok: true, run: rc.body, etat: await etat() })
    }

    return json({ ok: false, error: 'action inconnue' })
  } catch (e) {
    return json({ ok: false, error: String(e) })
  }
})
