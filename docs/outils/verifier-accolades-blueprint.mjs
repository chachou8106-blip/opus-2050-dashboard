// Contrôle d'équilibre des accolades dans les corps JSON des modules Make.
//
// Pourquoi : le 26/08, le scénario 7051944 s'est arrêté à 20 opérations sur
// « InvalidConfigurationError — The provided JSON body content is not valid JSON ».
// Cause : l'ajout de "thinkingConfig":{"thinkingBudget":0} dans le module 207 avait
// mangé l'accolade fermante du corps — 7 ouvertes, 6 fermées. Un seul caractère.
//
// Le critère qui compte est OUVERTES === FERMEES. Les modules dont tout le corps est
// une expression Make ({{10000.json}}) ou qui injectent un nombre brut échouent
// JSON.parse sans être cassés : c'est le déséquilibre d'accolades qui trahit une
// vraie erreur d'édition.
//
// Usage : node verifier-accolades-blueprint.mjs <cle1> <cle2>
// où les clés sont celles de bp.mjs (snapshots de scenarios_get).

import {bp, mods, nom} from './bp.mjs';

// Neutralise les expressions Make {{ ... }} (y compris imbriquees d'un niveau) puis
// verifie que le corps est du JSON valide et que les accolades sont equilibrees.
function neutralise(s) {
  let t = s;
  for (let i = 0; i < 6; i++) t = t.replace(/\{\{[^{}]*\}\}/g, 'X');
  return t;
}
function bilan(s) {
  const t = neutralise(s);
  let o = 0, c = 0, str = false;
  for (let i = 0; i < t.length; i++) {
    const ch = t[i];
    if (ch === '\\') { i++; continue }
    if (ch === '"') { str = !str; continue }
    if (str) continue;
    if (ch === '{') o++; if (ch === '}') c++;
  }
  let err = null;
  try { JSON.parse(t) } catch (e) { err = e.message }
  return { o, c, err, reste: (t.match(/\{\{|\}\}/g) || []).length };
}

for (const cle of process.argv.slice(2)) {
  console.log('\n########## ' + cle);
  const M = mods(bp(cle));
  let ko = 0;
  for (const [id, m] of [...M].sort((a, b) => a[0] - b[0])) {
    const body = m.mapper && m.mapper.jsonStringBodyContent;
    if (!body) continue;
    const b = bilan(body);
    if (b.o === b.c && !b.err) continue;
    ko++;
    console.log('  ✘ module ' + id + '  ' + nom(m));
    console.log('      accolades ouvertes=' + b.o + ' fermees=' + b.c +
      (b.err ? '\n      JSON : ' + b.err : ''));
    console.log('      fin : ' + JSON.stringify(body.slice(-70)));
  }
  if (!ko) console.log('  tous les corps JSON sont equilibres et valides');
}
