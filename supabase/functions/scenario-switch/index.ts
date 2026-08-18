// scenario-switch v3 — bouton console du scénario Make (interrupteur maître + run manuel).
// Modèle : Supabase déclenche N runs/jour à heures fixes. Comme /run exige un scénario actif,
// on utilise /start (active + déclenche 1 exécution) puis /stop 3 min après (scenario_fire).
// Le maître (scenario_control.actif) autorise/bloque les runs planifiés. PIN-gardé (arm_pin).
// Actions : status (lecture, sans PIN) ; on / off (bascule maître ; off = coupe Make aussi) ;
//           run-now (lance un run tout de suite via /start + /stop programmé).
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
      if (action === 'off') await sb('rpc/scenario_stop_now', { method: 'POST', body: '{}' })
      return json({ ok: true, etat: await etat() })
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
