# AETHER / OPUS 2050

Système de trading multi-agents autonome : **cinq stratégies spécialisées** (JU, SYL, GIL, l'Alchimiste,
Marées) pilotées par IA, un moteur central qui mesure et réalloue, et une console de suivi.
**Seul l'Alchimiste engage de l'argent réel** (Revolut X, au comptant) ; le reste est en
simulation / apprentissage.

- **Console en production** : `console_aether 2.html` → https://oracle-financier.netlify.app/console_aether%202.html
- **Projet Supabase** : `smddzybxebwhfnitxuyp`
- **Orchestration IA** : Make.com (scénario Alchimiste **6183820**), édité via l'assistant **Maia**

## 📚 Documentation (lire dans cet ordre)
1. **[docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)** — le système de bout en bout (traders, pipeline,
   base de données, services externes, console, carte du repo).
2. **[docs/RUNBOOK.md](docs/RUNBOOK.md)** — exploitation, maintenance, secours, incidents connus.
3. **[docs/PASSAGE-AU-REEL.md](docs/PASSAGE-AU-REEL.md)** — checklist argent réel (kill-switch, garde-fous).
4. **[docs/CHANGELOG.md](docs/CHANGELOG.md)** — journal des décisions & changements (mémoire longue).
5. **[docs/decisions/](docs/decisions/)** — correctifs datés & prompts Maia (détail par sujet).

## 🗂️ Structure du repo
```
console_aether 2.html          ← LA console en production (Netlify, déploiement depuis main)
_headers                       ← cache Netlify (no-cache HTML)
docs/                          ← toute la documentation (ci-dessus)
supabase/
  functions/<slug>/index.ts    ← source de TOUTES les edge functions déployées
  functions/_MANIFEST.md       ← table des edge functions (version, verify_jwt, rôle)
  functions/README-KILLSWITCH.md
  README-DAILY-JOURNAL.md
  schema/                      ← dump SQL complet (tables, vues, fonctions, cron, policies)
  schema/README.md             ← index du dump + requêtes de regénération
autres *.html                  ← versions antérieures / dashboards annexes (historique)
```

## ⚠️ Règles d'or (voir RUNBOOK §0)
1. Ne JAMAIS armer/désarmer le **kill-switch** ni passer `dry_run=false` sans l'accord de Chachou.
2. Ne JAMAIS éditer le **blueprint Make** en direct — tout passe par **Maia**.
3. Ne jamais inventer un chiffre : vérifier en base, signaler les trous.
4. La console n'est en ligne qu'une fois sur **`main`** (Netlify auto-deploy).

## 🔄 Tenir le repo à jour
Après tout changement en base ou sur une edge function, **regénérer les exports** (voir
`docs/RUNBOOK.md` §10) et **ajouter une entrée datée** dans `docs/CHANGELOG.md`. Objectif : un repo
complet et fiable pour le suivi, la maintenance, l'évolution et le passage au réel sur la durée.

## 🔐 Secrets
Aucun secret n'est commité. Les edge functions lisent leurs clés depuis les variables d'environnement
Supabase (`SUPABASE_SERVICE_ROLE_KEY`, `REVX_API_KEY`, `REVX_PRIVATE_KEY`, clés Alpaca…). La clé
**anon** Supabase présente dans la console est publique (ce n'est pas un secret).
