// revx-staking-probe : teste des endpoints staking candidats de Revolut X (lecture seule signee).

const REVX_BASE = 'https://revx.revolut.com'
const API_KEY = (Deno.env.get('REVX_API_KEY') || '').trim()
const PRIVATE_PEM = Deno.env.get('REVX_PRIVATE_KEY') || ''
const cors = { 'Access-Control-Allow-Origin': '*', 'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type' }
function pem(p: string) { const b = p.replace(/-----BEGIN [A-Z ]+-----/g, '').replace(/-----END [A-Z ]+-----/g, '').replace(/\s+/g, ''); return Uint8Array.from(atob(b), c => c.charCodeAt(0)) }
async function key() { return await crypto.subtle.importKey('pkcs8', pem(PRIVATE_PEM), { name: 'Ed25519' }, false, ['sign']) }
function b64(x: Uint8Array) { let s = ''; for (const c of x) s += String.fromCharCode(c); return btoa(s) }
async function sget(path: string, k: CryptoKey) {
  const ts = Date.now().toString(); const msg = `${ts}GET${path}`
  const sig = new Uint8Array(await crypto.subtle.sign({ name: 'Ed25519' }, k, new TextEncoder().encode(msg)))
  const r = await fetch(REVX_BASE + path, { method: 'GET', headers: { 'X-Revx-API-Key': API_KEY, 'X-Revx-Timestamp': ts, 'X-Revx-Signature': b64(sig), 'Content-Type': 'application/json' }, signal: AbortSignal.timeout(9000) })
  let body: any; try { body = await r.text() } catch { body = '' }
  return { path, status: r.status, snippet: String(body).slice(0, 220) }
}
Deno.serve(async () => {
  try {
    const k = await key()
    const paths = ['/api/1.0/staking', '/api/1.0/staking/positions', '/api/1.0/staking/products', '/api/1.0/earn', '/api/1.0/earn/positions', '/api/1.0/rewards', '/api/1.0/crypto/staking', '/api/1.0/stakes']
    const results = []
    for (const p of paths) { try { results.push(await sget(p, k)) } catch (e) { results.push({ path: p, status: -1, snippet: String(e).slice(0, 120) }) } }
    return new Response(JSON.stringify({ ok: true, results }), { headers: { ...cors, 'Content-Type': 'application/json' } })
  } catch (e) { return new Response(JSON.stringify({ ok: false, error: String(e) }), { headers: { ...cors, 'Content-Type': 'application/json' } }) }
})
