// scenario-switch v1 — bouton console ON/OFF du scénario Make (interrupteur maître).
// Ne touche PAS au blueprint Make : bascule scenario_control.actif puis appelle scenario_reconcile()
// qui active/désactive le scénario via l'API Make (start/stop). PIN-gardé (ju_crypte_config.arm_pin).
// Lecture d'état sans PIN ; bascule ON/OFF avec PIN.
const SUPABASE_URL = Deno.env.get('SUPABASE_URL')!
const SRK = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
const cors = { 'Access-Control-Allow-Origin': '*', 'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type', 'Access-Control-Allow-Methods': 'POST, OPTIONS' }
const json = (d: unknown, s = 200) => new Response(JSON.stringify(d), { status: s, headers: { ...cors, 'Content-Type': 'application/json' } })

async function sb(path: string, init?: RequestInit) {
  const r = await fetch(`${SUPABASE_URL}/rest/v1/${path}`, { ...init, headers: { apikey: SRK, Authorization: `Bearer ${SRK}`, 'Content-Type': 'application/json', ...(init?.headers || {}) } })
  try { return { ok: r.ok, status: r.status, body: await r.json() } } catch { return { ok: r.ok, status: r.status, body: null } }
}
const etat = async () => { const r = await sb('v_scenario_etat?select=*'); return Array.isArray(r.body) ? (r.body[0] || null) : null }

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: cors })
  try {
    const b = await req.json().catch(() => ({}))
    const action = (b.action || 'status').toString()

    if (action === 'status') return json({ ok: true, etat: await etat() })

    if (action === 'on' || action === 'off') {
      // Vérif PIN (le même que l'armement)
      const pr = await sb('ju_crypte_config?key=eq.arm_pin&select=value')
      const pin = Array.isArray(pr.body) && pr.body[0] ? String(pr.body[0].value) : null
      if (!pin || String(b.pin || '') !== pin) return json({ ok: false, error: 'PIN incorrect' })

      const actif = action === 'on'
      await sb('scenario_control?id=eq.1', { method: 'PATCH', headers: { Prefer: 'return=minimal' }, body: JSON.stringify({ actif, updated_at: new Date().toISOString(), updated_by: 'console' }) })
      // Applique tout de suite (n'attend pas le cron 10 min)
      const rc = await sb('rpc/scenario_reconcile', { method: 'POST', body: JSON.stringify({ p_source: 'bouton' }) })
      return json({ ok: true, etat: await etat(), reconcile: rc.body })
    }

    return json({ ok: false, error: 'action inconnue' })
  } catch (e) {
    return json({ ok: false, error: String(e) })
  }
})
