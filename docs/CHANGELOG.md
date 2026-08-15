# Journal des changements & décisions — AETHER / OPUS 2050

> Historique des choix, corrections, améliorations et analyses. Sert de mémoire longue pour le suivi
> sur plusieurs mois. Ajouter une entrée **datée** à chaque changement significatif (décision, fix,
> amélioration, analyse). Le détail de certains sujets vit dans `docs/decisions/`.

Format : `AAAA-MM-JJ` — **Sujet** — quoi + pourquoi + où.

---

## 2026-08-15

- **Panneau Marées (forex virtuel) dans la console.** Diagnostic : la console n'affichait rien pour
  Marées car elle ne montre que les trades **clôturés**, or 0 clôturé depuis le reset du 13/08
  (positions <49h ; sortie TP 3%/SL 2% ou 240h = trop lent pour du forex). Correctif d'affichage :
  vues `v_marees_virtuel_positions` / `_resume` (positions ouvertes valorisées au dernier cours,
  P&L latent), exposées par `oracle-inbox` v15 (`suivi.marees_virtuel`) + nouvelle section console
  « Marées — Devises ». Marées n'est plus jamais vide ; les résultats réalisés apparaîtront dès les
  premières clôtures (~23/08). DDL : `supabase/schema/07_marees_virtuel.sql`.
- **Sauvegarde GitHub quotidienne automatique.** Workflow GitHub Actions `brain-backup.yml` (cron
  23:15 Paris) : appelle la RPC `brain_snapshot()` (lecture seule, clé anon publique) et commite
  `docs/brain/snapshots/lessons-AAAA-MM-JJ.json`. Indépendant de toute session ; aucun secret requis.

- **Mémoire permanente des bots (« à vie »).** Constat : `learnings`/`mistakes_history` étaient rognés
  aux 30 dernières entrées (perte de la mémoire qualitative ancienne). Correctif : nouvelle table
  **`brain_lessons`** append-only (jamais rognée) + **trigger** `trg_archive_brain_lessons` qui archive
  chaque leçon/erreur à chaque cycle. Le quantitatif (`oracle_performance`, 245 runs/bot depuis juin)
  était déjà permanent. Sauvegarde GitHub versionnée : `docs/brain/snapshots/`. Architecture &
  procédures : `docs/brain/MEMOIRE.md`. DDL : `supabase/schema/06_brain_memory.sql`.

- **Analyse SYL — short or/argent à contre-tendance.** SYL est short GLD (~150 k$ notionnel, entrée
  moy. 372, cours ~401 → −12,7 k$ / −6,1 %) et SLV (−1,8 k$), tenus **181 runs** sans être coupés.
  Causes : (a) doctrine apprise « GLD vs TLT rotation, prior wins on GLD » qui rejoue le short ;
  (b) **stop-loss non appliqué** — les ordres portent `stop_loss_pct=5` mais `stop_loss_target` reste
  null et la position dépasse −5 % sans coupe ; (c) la perte reste **latente** (jamais clôturée) donc
  la boucle d'apprentissage ne la **book pas** comme erreur → SYL ne se corrige pas seule. NB : paper.

- **Mécanisme « leçon épinglée » (pinned) + leçon anti-short-métaux pour SYL.** Découverte : le prompt
  du Conseil lit `brain_states.<archimage>.learnings[1].bias` comme MEMORY_CORRECTION, mais
  `update-brain` **rognait `learnings` aux 30 dernières** → une leçon manuelle disparaissait au cycle
  suivant. **`update-brain` v16** : les entrées `learnings` marquées `pinned:true` sont **préservées en
  tête** (jamais rognées) → une leçon manuelle reste lue en permanence. Leçon posée pour SYL
  (`learnings[0]`, pinned) : « ne pas shorter or/argent en tendance haussière ; couper tout short
  perdant au-delà de −5 % ; ne pas moyenner à la baisse ; un gain passé sur une rotation ne justifie
  pas un short à contre-tendance ». Procédure de réutilisation : `docs/RUNBOOK.md` §11.
  ⚠️ Reste ouvert : le **bug du stop non appliqué** (code `execute-trades`) — une leçon change les
  décisions mais ne fait pas se déclencher le stop ; à traiter avant le réel.

## 2026-08-14

- **Export & documentation complète du repo.** Dump de tout le schéma Supabase (tables, vues,
  fonctions, cron, policies) dans `supabase/schema/`, de toutes les edge functions dans
  `supabase/functions/`, et rédaction des docs (`ARCHITECTURE`, `RUNBOOK`, `PASSAGE-AU-REEL`, ce
  journal). But : ne rien perdre du travail, permettre suivi/maintenance/évolution/passage au réel.

- **Calendrier & rappels dans la console.** Nouvelle table `oracle_rappels` ; section « 📅 Calendrier »
  (espace opérationnel) avec badges par créneau (🌅/☀️/🌙), demandes (💬), rappels (🔔), détail au clic,
  bannière des rappels dus. `oracle-inbox` v14 sert l'historique étendu + rappels. **Rappel posé le
  28/08 (matin) : faire le point GIL → Alchimiste.**

- **Analyse : les leçons de GIL doivent-elles alimenter l'Alchimiste ?** GIL (crypto tactique, WR
  52 %, doctrine contrarian validée) vs Alchimiste (WR 38,5 %, asymétrie gain +0,56 % / perte −2,84 %,
  historique plombé par l'ancienne ère short-only sur micro-cryptos illiquides). Avis : oui, ajouter
  la **doctrine apprise** de GIL au prompt de l'Alchimiste en **contexte advisory** (il reçoit déjà son
  avis du jour, pas sa doctrine), MAIS le vrai levier reste la **discipline de sortie** et la
  **liquidité** de l'Alchimiste ; surveiller la **corrélation** (décorrélation = protection).
  **Décision : on laisse tourner jusqu'au 28/08 puis on tranche.** (rappel posé)

- **Fix `alc_record_propositions` (côté Supabase).** Le module Make « Le Registre de Cristal » (10023)
  envoie le JSON IA brut ; c'est la fonction Postgres qui extrait les colonnes. Elle lisait les
  **anciennes clés** (`crypto/sens/montant_usd/prix_actuel/gain_net_estime_pct/raison_courte`) alors
  que le nouveau prompt produit `paire/side/montant/confidence/raison` (sans prix) → colonnes NULL.
  Fonction réécrite : nouvelles clés (repli ancien), **`prix_ref` récupéré depuis `price_history`**,
  `destake_recommande` persisté dans nouvelle table `alc_destake_reco`. Backfill des propositions du
  jour + rebuild du portefeuille papier (9 trades). **Aucune modif Make nécessaire.**
  → `docs/decisions/CORRECTIF-ALCHIMISTE-MAPPING-2026-08-14.md`.

- **Tableau des gains par trader (console), en euros.** Nouvelle vue `v_gains_traders` (source unique) :
  7 lignes (AETHER, Alchimiste réel, Alchimiste virtuel, JU, SYL, GIL, Marées) × 4 horizons
  (jour/semaine/mois/année), en **€** (« si je soldais ») + équivalent **$** + **%**. `oracle-inbox`
  expose `gains` + `fx` (EUR-USD live). **Correction majeure** : le montant était calculé sur une
  mauvaise base d'équité (~54 k) ; la vraie base des sages est `baseline_equity` ≈ **1 M**.

- **Alerte univers repointée.** `v_data_health` surveillait la table morte `revolut_univers_complet`
  (figée 07/07). Repointée sur la vraie source live `price_history` (univers ≥ 200 symboles/heure).
  → `docs/decisions/CORRECTIF-UNIVERS-SANTE-2026-08-14.md`.

- **Diagnostic crash Alchimiste (Make 6183820).** Erreur « JSON invalide » sur le module Perplexity
  (10012) : des tableaux bruts (`10011.data`, `20022.data`, `20023.data`) étaient injectés dans le
  corps JSON. Prompt de diagnostic rédigé pour Maia (elle décide du fix).
  → `docs/decisions/PROMPT-MAIA-ALCHIMISTE-JSON-2026-08-14.md`. **Corrigé via Maia le 14/08.**

- **Audit de la journée.** JU/SYL/GIL : 11 ordres remplis, complets. Alchimiste : réparé, achète ET
  vend. Marées : 7 propositions complètes. `alpaca_orders` confirmée **table morte** (canonique =
  `oracle_college_orders`).

## 2026-08-13

- **Résumé quotidien serveur (matin/midi/soir).** `generate_daily_journal(creneau)` + pg_cron, pour
  écrire le point complet (tous traders + destaking) dans `oracle_journal` **sans dépendre d'une
  session Claude**. → `supabase/README-DAILY-JOURNAL.md`.

- **Kill-switch + Face ID.** Bouton dans la console ; edge functions `ju-killswitch` (PIN, option A,
  anti-lockout) et `ju-passkey` (Face ID/WebAuthn, option B). Espace opérationnel verrouillé (PIN puis
  Face ID). → `supabase/functions/README-KILLSWITCH.md`.

- **Fix Alchimiste spot.** `alc-auto` v6 + `revolut-x-trade` v7 : achète ET vend (fin du sell-only),
  tradabilité **live**, achat plafonné au cash USD, vente sur actif détenu liquide (hors staking).
  → `docs/decisions/CORRECTIF-ALCHIMISTE-2026-08-13.md`.

- **Staking.** Tables `alc_staking_apy`, `alc_staking_delais`, `alc_staking_lots` ; vue
  `v_staking_point` (coût/valeur/PnL/coût de dé-staking par coin, FX historique aux dates d'achat).

- **Netlify no-cache.** `_headers` (`Cache-Control: max-age=0`) pour voir les MAJ HTML tout de suite.

## Avant le 2026-08-13 (résumé)
- Construction du dashboard/vitrine, ajout de l'archimage **Marées** (forex, 24/07), suivi
  multi-périodes + santé système, PWA suivi mobile, ratios réels de l'Alchimiste virtuel, ingestion
  multi-sources (Binance/Gate/Revolut X/FX/indices), apprentissage par brain states, réconciliation
  des ordres. (Historique détaillé : `git log`.)

---

### Modèle d'entrée (à copier pour les prochaines)
```
## AAAA-MM-JJ
- **Sujet.** Quoi. Pourquoi. Où (fichier / table / fonction). Décision & suite.
```
