import { chromium } from 'playwright';
import fs from 'fs'; import http from 'http';
const M='./mock/';
const j=n=>JSON.parse(fs.readFileSync(M+n,'utf8'));
const suivi=j('suivi.json'), snap=j('snap.json'), expo=j('expo.json'), sages=j('sages.json'),
      runs=j('runs.json'), positions=j('positions.json'), bt=j('bt.json'), teq=j('teq.json'),
      journal=j('journal.json'), P=j('petits.json'), T=j('tests_extra.json');
const html=fs.readFileSync('/home/user/opus-2050-dashboard/aether.html','utf8');
const srv=http.createServer((q,r)=>{r.writeHead(200,{'Content-Type':'text/html; charset=utf-8'});r.end(html);});
await new Promise(res=>srv.listen(8902,res));
const b=await chromium.launch({executablePath:'/opt/pw-browsers/chromium-1194/chrome-linux/chrome'});
const page=await b.newPage({viewport:{width:1400,height:1100},timezoneId:'Europe/Paris',locale:'fr-FR'});
const erreurs=[];
page.on('pageerror',e=>erreurs.push('PAGEERROR: '+e.message));
page.on('console',m=>{ if(m.type()==='error') erreurs.push('CONSOLE: '+m.text().slice(0,200)); });
await page.route('**/*', async route => {
  const u=route.request().url();
  if(u.startsWith('http://localhost:8902')) return route.continue();
  const post=()=>{ try{return JSON.parse(route.request().postData()||'{}');}catch(e){return {};} };
  const ok=d=>route.fulfill({status:200,contentType:'application/json',body:JSON.stringify(d)});
  if(u.includes('/rpc/dashboard_snapshot')) return ok(snap);
  if(u.includes('v_exposition_traders'))    return ok(expo);
  if(u.includes('/oracle-inbox')){ const a=post().action||'journal'; return ok(a==='suivi'?suivi:journal); }
  if(u.includes('/oracle-tests')){ const body=post(); const a=body.action; const p=body.params||{};
    const map=T;   // toutes les actions viennent des réponses réelles d'oracle-tests
    if(a==='archimage_detail') return ok({ok:true,action:a,data:T.archimage_detail[p.archimage]||null});
    if(a==='sage_detail')      return ok({ok:true,action:a,data:T.sage_detail[p.sage]||null});
    return ok({ok:true,action:a,data:(a in map)?map[a]:null}); }
  if(u.includes('/scenario-switch')) return ok({ok:true,etat:P.scen});
  if(u.includes('/ju-killswitch'))   return ok(P.ks);
  if(u.includes('/ju-passkey'))      return ok({ok:false,error:'mock'});
  return ok({});
});
await page.goto('http://localhost:8902/',{waitUntil:'networkidle'});
await page.waitForTimeout(3500);
await page.evaluate(async()=>{ try{ await unlockedOK(); }catch(e){} });
await page.waitForTimeout(2000);
await page.evaluate(()=>go('ops'));
await page.waitForTimeout(800);

const liste=await page.evaluate(()=>[...document.querySelectorAll('#tests [data-test]')]
  .map(e=>({a:e.dataset.test,pv:e.dataset.pv||'',t:e.querySelector('b').textContent})));
console.log('=== CONSOLE DE TESTS : '+liste.length+' actions ===\n');
for(const t of liste){
  const sel='#tests [data-test="'+t.a+'"]'+(t.pv?'[data-pv="'+t.pv+'"]':'');
  await page.click(sel);
  await page.waitForTimeout(700);
  const r=await page.evaluate(()=>{
    const m=document.getElementById('mbox'); if(!m) return {err:'pas de modale'};
    const txt=(m.textContent||'').replace(/\s+/g,' ').trim();
    return {n:txt.length, dollars:(txt.match(/\$/g)||[]).length,
      vide:/Aucune donnée|Liste vide|indisponible|Aucune donnée exploitable/i.test(txt),
      // /NaN/i attrapait « décisions gag-nan-tes » : NaN se cherche en respectant la casse.
      brut:/\[object|undefined|\bNaN\b/.test(txt), ap:txt.slice(0,150)};
  });
  const flag=r.err?'ERREUR':r.vide?'VIDE':r.brut?'BRUT':'ok';
  console.log(`${flag.padEnd(6)} ${t.t.padEnd(30)} ${String(r.n).padStart(5)} car · ${String(r.dollars).padStart(3)} $`);
  if(flag!=='ok') console.log('        '+(r.ap||r.err));
  await page.evaluate(()=>document.querySelector('.modal').classList.remove('on'));
  await page.waitForTimeout(120);
}
console.log('\n=== ERREURS JS ==='); erreurs.length?erreurs.slice(0,12).forEach(e=>console.log(' '+e)):console.log(' aucune');
await b.close(); srv.close();
