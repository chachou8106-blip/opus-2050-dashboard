// mt5-bridge v3 — Miroir EXACT (achats + ventes) via RPC mt5_book. Modes : JU / SYL / GIL / COLLEGE.
// Format renvoye a l'EA :
//   ligne 1 : OK;<mode>;<timestamp ISO>
//   lignes  : <SYMBOLE>;<poids signe en % de l'equity>   (negatif = vendeur/short)
// Protege par token (?token=... ou header X-Bridge-Token). Lecture seule.

const cors = { 'Access-Control-Allow-Origin': '*', 'Access-Control-Allow-Headers': 'x-bridge-token, content-type' }
const SUPABASE_URL = Deno.env.get('SUPABASE_URL') || 'https://smddzybxebwhfnitxuyp.supabase.co'
const SRK = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') || ''
const TOKEN = Deno.env.get('MT5_BRIDGE_TOKEN') || 'REDACTED'
const MODES = ['JU', 'SYL', 'GIL', 'COLLEGE']

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: cors })
  try {
    const url = new URL(req.url)
    const token = url.searchParams.get('token') || req.headers.get('x-bridge-token') || ''
    if (token !== TOKEN) return new Response('ERR;token invalide', { status: 401, headers: { ...cors, 'Content-Type': 'text/plain' } })
    // ?archimage= accepte JU/SYL/GIL/COLLEGE (retro-compatible)
    const mode = (url.searchParams.get('mode') || url.searchParams.get('archimage') || 'JU').toUpperCase()
    if (!MODES.includes(mode)) return new Response('ERR;mode inconnu (JU/SYL/GIL/COLLEGE)', { status: 400, headers: { ...cors, 'Content-Type': 'text/plain' } })

    const r = await fetch(`${SUPABASE_URL}/rest/v1/rpc/mt5_book`, {
      method: 'POST',
      headers: { apikey: SRK, Authorization: `Bearer ${SRK}`, 'Content-Type': 'application/json' },
      body: JSON.stringify({ p_mode: mode }),
      signal: AbortSignal.timeout(15000)
    })
    if (!r.ok) return new Response('ERR;rpc ' + r.status, { status: 500, headers: { ...cors, 'Content-Type': 'text/plain' } })
    const rows = await r.json()
    let out = `OK;${mode};${new Date().toISOString()}\n`
    if (Array.isArray(rows)) for (const p of rows) {
      const sym = String(p.ticker || '').replace(/[^A-Za-z0-9._-]/g, '')
      const w = Number(p.poids_pct)
      if (sym && isFinite(w) && w !== 0) out += `${sym};${w.toFixed(2)}\n`
    }
    return new Response(out, { headers: { ...cors, 'Content-Type': 'text/plain', 'Cache-Control': 'no-store' } })
  } catch (e) {
    return new Response('ERR;' + String(e).slice(0, 120), { status: 500, headers: { ...cors, 'Content-Type': 'text/plain' } })
  }
})
