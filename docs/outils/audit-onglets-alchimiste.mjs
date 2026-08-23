import { chromium } from 'playwright';
import fs from 'fs'; import http from 'http';
const M='./mock/';
const j=n=>JSON.parse(fs.readFileSync(M+n,'utf8'));
const suivi=j('suivi.json'), snap=j('snap.json'), expo=j('expo.json'),
      journal=j('journal.json'), P=j('petits.json'), T=j('tests_extra.json');
const html=fs.readFileSync('/home/user/opus-2050-dashboard/aether.html','utf8');
const srv=http.createServer((q,r)=>{r.writeHead(200,{'Content-Type':'text/html; charset=utf-8'});r.end(html);});
await new Promise(res=>srv.listen(8907,res));
const b=await chromium.launch({executablePath:'/opt/pw-browsers/chromium-1194/chrome-linux/chrome'});
const page=await b.newPage({viewport:{width:1400,height:1100},timezoneId:'Europe/Paris',locale:'fr-FR'});
const erreurs=[];
page.on('pageerror',e=>erreurs.push('PAGEERROR: '+e.message));
page.on('console',m=>{ if(m.type()==='error') erreurs.push('CONSOLE: '+m.text().slice(0,200)); });
await page.route('**/*', async route => {
  const u=route.request().url();
  if(u.startsWith('http://localhost:8907')) return route.continue();
  const post=()=>{ try{return JSON.parse(route.request().postData()||'{}');}catch(e){return {};} };
  const ok=d=>route.fulfill({status:200,contentType:'application/json',body:JSON.stringify(d)});
  if(u.includes('/rpc/dashboard_snapshot')) return ok(snap);
  if(u.includes('v_exposition_traders'))    return ok(expo);
  if(u.includes('/oracle-inbox')){ const a=post().action||'journal'; return ok(a==='suivi'?suivi:journal); }
  if(u.includes('/oracle-tests')){ const body=post(); const a=body.action; const p=body.params||{};
    if(a==='archimage_detail') return ok({ok:true,action:a,data:T.archimage_detail[p.archimage]||null});
    if(a==='sage_detail')      return ok({ok:true,action:a,data:T.sage_detail[p.sage]||null});
    return ok({ok:true,action:a,data:(a in T)?T[a]:null}); }
  if(u.includes('/scenario-switch')) return ok({ok:true,etat:P.scen});
  if(u.includes('/ju-killswitch'))   return ok(P.ks);
  if(u.includes('/ju-passkey'))      return ok({ok:false,error:'mock'});
  return ok({});
});
await page.goto('http://localhost:8907/',{waitUntil:'networkidle'});
await page.waitForTimeout(3500);
await page.evaluate(async()=>{ try{ await unlockedOK(); }catch(e){} });
await page.waitForTimeout(2000);

const ONGLETS=['apercu','strat','marches','college','portef','reel','journal','ops'];
const NOMS={apercu:"Vue d'ensemble",strat:'Stratégies',marches:'Marchés',college:'Le Collège',
  portef:'Portefeuilles',reel:'Passage au réel',journal:'Journal',ops:'Commandes'};
for(const o of ONGLETS){
  await page.evaluate(t=>go(t),o);
  await page.waitForTimeout(500);
  const r=await page.evaluate(id=>{
    const sec=document.getElementById(id); if(!sec) return {abs:true};
    const txt=(sec.innerText||'').replace(/ /g,' ');
    // toutes les lignes qui parlent de l'Alchimiste, avec 1 ligne de contexte de part et d'autre
    const L=txt.split('\n').map(s=>s.trim());
    const hits=[];
    L.forEach((l,i)=>{ if(/alchimis|revolut|virtuel|labo/i.test(l)){
      hits.push([Math.max(0,i-1),Math.min(L.length-1,i+2)]); }});
    // fusionne les plages qui se chevauchent
    const plages=[]; hits.forEach(h=>{ const last=plages[plages.length-1];
      if(last&&h[0]<=last[1]+1) last[1]=Math.max(last[1],h[1]); else plages.push([...h]); });
    return {extraits:plages.map(p=>L.slice(p[0],p[1]+1).filter(Boolean).join(' | '))};
  },o);
  console.log('\n########## '+NOMS[o]+' ('+o+')');
  if(r.abs){ console.log('  (onglet absent)'); continue; }
  if(!r.extraits.length){ console.log('  aucune mention de l\'Alchimiste'); continue; }
  r.extraits.forEach(x=>console.log('  • '+x));
}
console.log('\n=== ERREURS JS ==='); erreurs.length?erreurs.slice(0,10).forEach(e=>console.log(' '+e)):console.log(' aucune');
await b.close(); srv.close();
