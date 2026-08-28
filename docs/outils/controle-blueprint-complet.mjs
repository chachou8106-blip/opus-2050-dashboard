import fs from 'fs'; import crypto from 'crypto';
const TR='/root/.claude/projects/-home-user-opus-2050-dashboard/f7b54a84-b499-5e7d-863b-465538b2fbb8/tool-results/';
function mods(f){ const raw=fs.readFileSync(TR+f,'utf8'); const j=JSON.parse(raw.slice(raw.indexOf('{')));
  let b=j.blueprint; if(typeof b==='string') b=JSON.parse(b); const M=new Map();
  (function w(n){ if(!n||typeof n!=='object')return; if(Array.isArray(n))return n.forEach(w);
    if(n.id!=null&&n.module) M.set(n.id,n); Object.values(n).forEach(w); })(b); return M; }
const nom=m=>((m.metadata&&m.metadata.designer&&m.metadata.designer.name)||'').split('\n')[0];
const emp=v=>crypto.createHash('sha256').update(String(v==null?'':v)).digest('hex').slice(0,10);
const B=mods(process.argv[3]), A=process.argv[2]!=='-'?mods(process.argv[2]):null;
console.log('modules : '+B.size);
if(A){ console.log('\n--- modules modifies ---'); let n=0;
  for(const [id,m] of B){ const a=A.get(id); if(!a||JSON.stringify(a)!==JSON.stringify(m)){ console.log('  ~ '+String(id).padStart(6)+'  '+nom(m)); n++; } }
  if(!n) console.log('  aucune'); }

// 1. tailles des corps
const CIBLE={201:5267,203:3450,205:4566,207:4442,209:6203,211:811,10032:409,301:7013,303:6816,305:6647,
             401:4795,960:1422,981:3596,982:1815,10012:7697,20015:4168};
console.log('\n--- 1. tailles des corps ---');
let ok=0;
for(const id of Object.keys(CIBLE).map(Number)){
  const m=B.get(id);
  const t=m.mapper.jsonStringBodyContent || JSON.parse(JSON.stringify(m.mapper.system_instruction||'{}')).parts?.[0]?.text || '';
  const bon=t.length===CIBLE[id]; if(bon)ok++;
  if(!bon) console.log('  ✘ '+String(id).padStart(6)+' : '+t.length+' au lieu de '+CIBLE[id]);
}
console.log('  '+ok+'/'+Object.keys(CIBLE).length+' conformes');

// 2. EN-TETES : toutes les cles Supabase doivent etre identiques
console.log('\n--- 2. en-tetes des modules Supabase (nouveau controle) ---');
const ref={}; const sup=[];
for(const [id,m] of B){ const u=m.mapper&&m.mapper.url; if(typeof u!=='string'||!u.includes('supabase.co')) continue;
  const h=m.mapper.headers||[]; const o={}; for(const x of h) o[x.name]=emp(x.value); sup.push([id,m,o]);
  for(const k of Object.keys(o)) (ref[k]=ref[k]||{})[o[k]]=(ref[k][o[k]]||0)+1; }
let anomalies=0;
for(const k of Object.keys(ref)){
  const majoritaire=Object.entries(ref[k]).sort((a,b)=>b[1]-a[1])[0][0];
  for(const [id,m,o] of sup) if(o[k] && o[k]!==majoritaire){ anomalies++;
    console.log('  ✘ module '+id+' '+nom(m)+' : '+k+'差 empreinte '+o[k]+' au lieu de '+majoritaire); }
}
console.log('  '+sup.length+' modules Supabase, '+(anomalies||'aucune')+' anomalie'+(anomalies>1?'s':'')+' d en-tete');

// 3. cles d API des autres services : coherence par domaine
console.log('\n--- 3. autres services ---');
const parDomaine={};
for(const [id,m] of B){ const u=m.mapper&&m.mapper.url; if(typeof u!=='string') continue;
  let d; try{ d=new URL(u.replace(/\{\{[^}]*\}\}/g,'x')).hostname }catch(e){ continue }
  if(d.includes('supabase.co')) continue;
  const h=m.mapper.headers||[]; const a=h.find(x=>/authorization|api-key|x-api-key/i.test(x.name));
  if(a){ (parDomaine[d]=parDomaine[d]||[]).push([id,emp(a.value)]); } }
for(const [d,l] of Object.entries(parDomaine)){
  const u=[...new Set(l.map(x=>x[1]))];
  console.log('  '+d.padEnd(34)+l.length+' module(s), '+u.length+' cle(s) distincte(s)'+(u.length>1?'  <-- a verifier : '+l.map(x=>x[0]).join(','):''));
}

// 4. securite habituelle
function extraire(x){ const out=[]; let i=0;
  while(i<x.length){ const a=x.indexOf('{{',i); if(a<0)break; let d=0,k=a;
    for(;k<x.length;k++){ if(x.startsWith('{{',k)){d++;k++;} else if(x.startsWith('}}',k)){d--;k++; if(d===0){k++;break;}} }
    out.push(x.slice(a,k)); i=k; } return out; }
const susp=/(Yikes|Let's |maybe too much|perhaps tool|I should|We need|D'accord)/;
let sale=0,desq=0,ctrl=0,bs=0;
for(const [id,m] of B){
  if(susp.test(JSON.stringify(m.mapper||{}))){sale++;console.log('  ✘ monologue dans '+id);}
  const t=m.mapper&&m.mapper.jsonStringBodyContent; if(!t) continue;
  if([201,203,205,207,209,211,301,303,305,10012].includes(id)){
    const e=extraire(t).filter(x=>x.includes('\\')); if(e.length){bs++;console.log('  ✘ antislash dans une expression du '+id);} }
  let st=false; for(let i=0;i<t.length;i++){ const c=t[i];
    if(c==='\\'){i++;continue} if(c==='"'){st=!st;continue}
    if(st&&t.charCodeAt(i)<0x20){ctrl++;console.log('  ✘ caractere de controle dans une chaine du '+id);break;} }
  let z=t; for(let i=0;i<6;i++) z=z.replace(/\{\{[^{}]*\}\}/g,'X');
  let o=0,c2=0,s2=false;
  for(let i=0;i<z.length;i++){const ch=z[i]; if(ch==='\\'){i++;continue} if(ch==='"'){s2=!s2;continue} if(s2)continue; if(ch==='{')o++; if(ch==='}')c2++;}
  if(o!==c2){desq++;console.log('  ✘ accolades '+id+' : '+o+'/'+c2);}
}
console.log('\n--- 4. securite : monologue='+(sale||'aucun')+'  antislash='+(bs||'aucun')+'  controle='+(ctrl||'aucun')+'  accolades='+(desq?desq+' DESEQ':'equilibrees'));
