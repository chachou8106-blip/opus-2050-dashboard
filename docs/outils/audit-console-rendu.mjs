import { chromium } from 'playwright';
import fs from 'fs'; import http from 'http';
const M='/tmp/claude-0/-home-user-opus-2050-dashboard/f7b54a84-b499-5e7d-863b-465538b2fbb8/scratchpad/mock/';
const j=n=>JSON.parse(fs.readFileSync(M+n,'utf8'));
const suivi=j('suivi.json'), snap=j('snap.json'), expo=j('expo.json'), sages=j('sages.json'),
      runs=j('runs.json'), positions=j('positions.json'), bt=j('bt.json'), teq=j('teq.json'),
      journal=j('journal.json'), P=j('petits.json');
const html=fs.readFileSync('/home/user/opus-2050-dashboard/aether.html','utf8');

const srv=http.createServer((q,r)=>{r.writeHead(200,{'Content-Type':'text/html; charset=utf-8'});r.end(html);});
await new Promise(res=>srv.listen(8899,res));

const b=await chromium.launch({executablePath:'/opt/pw-browsers/chromium-1194/chrome-linux/chrome'});
const page=await b.newPage({viewport:{width:1400,height:1000},timezoneId:'Europe/Paris',locale:'fr-FR'});
const erreurs=[];
page.on('pageerror',e=>erreurs.push('PAGEERROR: '+e.message));
page.on('console',m=>{ if(m.type()==='error') erreurs.push('CONSOLE: '+m.text().slice(0,300)); });
await page.route('**/*', async route => {
  const u=route.request().url();
  if(u.startsWith('http://localhost:8899')) return route.continue();
  const post=()=>{ try{return JSON.parse(route.request().postData()||'{}');}catch(e){return {};} };
  const ok=d=>route.fulfill({status:200,contentType:'application/json',body:JSON.stringify(d)});
  if(u.includes('/rpc/dashboard_snapshot')) return ok(snap);
  if(u.includes('v_exposition_traders'))    return ok(expo);
  if(u.includes('/oracle-inbox')){ const a=post().action||'journal'; return ok(a==='suivi'?suivi:journal); }
  if(u.includes('/oracle-tests')){ const a=post().action;
    const map={hero:P.hero,sages,runs,positions,bt_alchimiste:bt,equity:teq,alchimiste:P.alch};
    return ok({ok:true,action:a,data:(a in map)?map[a]:null}); }
  if(u.includes('/scenario-switch')) return ok({ok:true,etat:P.scen});
  if(u.includes('/ju-killswitch'))   return ok(P.ks);
  if(u.includes('/ju-passkey'))      return ok({ok:false,error:'mock'});
  return ok({});
});
await page.goto('http://localhost:8899/',{waitUntil:'networkidle'});
await page.waitForTimeout(4000);
await page.evaluate(()=>{ ['jrnGate','opsGate'].forEach(i=>{const e=document.getElementById(i);if(e)e.style.display='none';});
  ['jrnContent','opsContent'].forEach(i=>{const e=document.getElementById(i);if(e)e.style.display='';});
  });
await page.evaluate(async()=>{ try{ await unlockedOK(); }catch(e){ console.error('unlockedOK: '+e.message); } });
await page.waitForTimeout(2500);

const DUMP=await page.evaluate(()=>{
  const o={};
  document.querySelectorAll('section.tab').forEach(s=>{
    const t=[];
    s.querySelectorAll('table').forEach(tb=>{
      const head=[...tb.querySelectorAll('thead th')].map(x=>x.textContent.trim());
      const rows=[...tb.querySelectorAll('tbody tr')].slice(0,4).map(tr=>[...tr.children].map(td=>td.textContent.trim().slice(0,24)));
      t.push({id:tb.id||'(sans id)',head,rows,n:tb.querySelectorAll('tbody tr').length});
    });
    const tiles=[...s.querySelectorAll('.tile,.card.kpi,.fig,.c')].map(e=>e.textContent.replace(/\s+/g,' ').trim()).filter(x=>x);
    o[s.id]={t,tiles};
  });
  return o;
});
const SUSP=await page.evaluate(()=>{
  const out=[]; const MOTS=/(undefined|NaN|Invalid Date|\[object|indisponible|null)/i;
  document.querySelectorAll('section.tab').forEach(sec=>{
    sec.querySelectorAll('[id]').forEach(el=>{
      if(['INPUT','TEXTAREA','BUTTON'].includes(el.tagName))return;
      const t=(el.textContent||'').trim();
      const media=el.querySelector('svg,canvas,img');
      if(!t && !media && el.children.length===0) out.push([sec.id,el.id,'VIDE','']);
      else if(t && !media && /^[\u2014\-\u2013\s]*$/.test(t)) out.push([sec.id,el.id,'TIRETS',t.slice(0,40)]);
      else if(MOTS.test(t) && t.length<300) out.push([sec.id,el.id,'SUSPECT',t.replace(/\s+/g,' ').slice(0,90)]);
    });
  });
  return out;
});
console.log('=== CONTENEURS VIDES / TIRETS / SUSPECTS ===');
SUSP.length?SUSP.forEach(r=>console.log(` [${r[0]}] ${r[1]} : ${r[2]} ${r[3]}`)):console.log(' aucun');
console.log('\n=== ERREURS JS ==='); erreurs.length?erreurs.slice(0,20).forEach(e=>console.log(' '+e)):console.log(' aucune');
console.log('\n=== TABLEAUX ET TUILES PAR ONGLET ===');
for(const [ong,d] of Object.entries(DUMP)){
  console.log(`\n--- ${ong.toUpperCase()}`);
  d.t.forEach(t=>{
    console.log(`  table#${t.id} (${t.n} lignes) : ${t.head.join(' | ')}`);
    t.rows.forEach(r=>console.log('      '+r.join(' | ')));
  });
  const avecTiret=d.tiles.filter(x=>/—/.test(x));
  if(avecTiret.length){ console.log(`  tuiles avec « — » (${avecTiret.length}) :`); avecTiret.slice(0,16).forEach(x=>console.log('      '+x.slice(0,70))); }
}
const T=await page.evaluate(()=>{const g=id=>{const e=document.getElementById(id);return e?e.textContent.replace(/\s+/g,' ').trim():'(absent)';};
 return {gainsSub:g('gainsSub'), verdictTop:g('verdictTop'), verdictReel:g('verdictReel'), risque:g('risque'), vigieHead:g('vigieHead')};});
const COL=await page.evaluate(()=>{const o={};
 ['gauges','sages','archi','meta','flux','sceau'].forEach(id=>{const e=document.getElementById(id);
  o[id]=e?e.textContent.replace(/\s+/g,' ').trim().slice(0,220):'(absent)';});
 return o;});
console.log('\n=== ONGLET COLLEGE ===');
for(const [k,v] of Object.entries(COL)) console.log(` ${k} : ${v}`);
console.log('\n=== LIBELLES CLES ===');
for(const [k,v] of Object.entries(T)) console.log(` ${k} : ${v.slice(0,230)}`);
await page.screenshot({path:'/tmp/claude-0/-home-user-opus-2050-dashboard/f7b54a84-b499-5e7d-863b-465538b2fbb8/scratchpad/apercu.png',fullPage:false});
await b.close(); srv.close();
