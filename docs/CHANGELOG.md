# Journal des changements & décisions — AETHER / OPUS 2050

> Historique des choix, corrections, améliorations et analyses. Sert de mémoire longue pour le suivi
> sur plusieurs mois. Ajouter une entrée **datée** à chaque changement significatif (décision, fix,
> amélioration, analyse). Le détail de certains sujets vit dans `docs/decisions/`.

Format : `AAAA-MM-JJ` — **Sujet** — quoi + pourquoi + où.

---

## 2026-08-17

- **Alchimiste RÉEL (Revolut X) valorisé en direct — même principe que le virtuel.** Le portefeuille
  réel n'était valorisé qu'une fois par jour (`revolut_portfolio_daily`, écrit à 8h par
  `revolut-portfolio-summary`). Deux vues **100 % lecture** `v_alc_reel_live_positions` /
  `v_alc_reel_live_resume` reprennent le dernier snapshot (quantités par coin dans `detail`) et
  revalorisent chaque ligne au dernier cours de `price_history` (alimenté 24/7). Couverture **47/49
  coins + 2 cash ≈ 100 %**. Exposé par `oracle-inbox` **v17** (`suivi.alc_reel_live`) + sous-bloc
  console « 🜍 Alchimiste réel — Revolut X » dans la section « Crypto en direct » (valeur live, en €,
  écart depuis 8h, lignes live). Aucun ordre, aucune écriture, ne touche NI au kill-switch NI au
  dry_run. NB : le virtuel était **déjà** live (`v_alc_virtuel_positions` via `v_dernier_prix`).
  DDL : `supabase/schema/09_alc_reel_live.sql`.
- **SYL — soldage de la crypto hors univers (FAIT) + verrou anti-récidive.** Constat de Chachou : SYL
  (« Macro internationale / paniers ETF ») portait ~226 k$ de crypto spot (ETH/SOL/LINK/BTC/AVAX/DOGE),
  qui relève de GIL. Diagnostic (lecture prompt + code) : **positions LEGACY** — tenues **190 runs**
  sans être touchées, antérieures aux règles de spécialisation. Le prompt SYL **interdisait déjà** la
  crypto et `execute-trades` bloquait tout **ACHAT** crypto hors GIL (`CRYPTO_EXCLUSIF_GIL`, garde
  `if(isBuy)`), mais **pas les ventes** → rien ne les soldait et le prompt (« ne trade pas hors
  univers ») dissuadait SYL d'en proposer la vente. **Action (17/08, sur décision de Chachou) :**
  **liquidation immédiate** des 6 lignes via l'API Alpaca (`DELETE /v2/positions/{symbol}` par pg_net,
  chirurgical — n'a touché qu'elles, pas d'effet de bord de `execute-trades`). Résultat : **0 crypto
  restante** chez SYL (31 positions ETF/actions), produit repassé en cash USD ; lignes mortes purgées
  de `oracle_positions_live`. **Verrou durable** : `execute-trades` **v35** — la crypto est le domaine
  **EXCLUSIF de GIL dans les deux sens** (non-GIL ne peut plus ACHETER de crypto ; GIL ne peut
  ACHETER/shorter QUE de la crypto, remplace l'ancienne restriction SPY/QQQ). Les **ventes restent
  libres** (débouclage). **Rappel : SYL est en paper.** ⚠️ Reste ouvert (hors sujet ici) : le bug du
  stop DB −5 % non appliqué (seul le seuil live TP 35 % / SL 15 % agit).

- **Audit spécialité du collège + correctif GIL (revert verrou).** Contrôle des 3 comptes Alpaca :
  drift hors-univers **systémique**. **GIL** : ne détient quasi **aucune crypto** ($0,03) mais un gros
  livre actions/ETF (~169 k$ net, brut >1 M$ : MSTR short 441 k$, XLU, TLT, TQQQ short…). Analyse
  legacy-vs-prompt : **ce n'est PAS du legacy** — le **prompt actuel** de GIL est
  `CRYPTO_TACTICAL_DERIVATIVES` et l'autorise explicitement (proxies MSTR/COIN/BITO, ETF tactiques
  SQQQ/TQQQ/UPRO, vol VXX/UVXY, défensifs XLU/XLP, shorts contrarian vs JU/SYL) ; ses ordres récents
  (10-14/08) sont MSTR/TQQQ/XLU, 0 crypto. **Décision de Chachou : garder ce rôle large.** →
  **`execute-trades` v36 : REVERT du volet « GIL crypto-only » de v35** (qui bloquait à tort ses
  instruments). On CONSERVE l'interdiction de crypto pour les non-GIL (déjà en v34). **JU/SYL** : leurs
  prompts, eux, **interdisent** le hors-univers (SYL : pas de single stocks ; JU : pas d'ETF) → leurs
  débordements (NVDA/AMD chez SYL, XLU short chez JU) sont à analyser séparément (legacy vs
  désobéissance) avant tout soldage. Analyse en cours.
- **Soldage du legacy hors-univers de JU et SYL + verrou actions/ETF (v37).** Suite à l'audit :
  analyse legacy-vs-prompt confirmée — sur 10 jours, **JU ne propose que des actions**, **SYL que des
  ETF** (leurs prompts interdisent le hors-univers). Leurs positions hors-voie sont donc du **legacy
  inerte**. **Action (sur décision de Chachou, 17/08)** : liquidation chirurgicale via l'API Alpaca —
  **JU : 18 ETF** (dont **XLU short 318 k$** racheté, TLT, IEF, HYG, GLD, XLV, XLP, SCHD, USO…),
  **SYL : 9 actions** (NVDA 277 k$, AMD 123 k$, MSFT, LLY, COST, GS, META, V, UNH). Marché fermé au
  moment de l'ordre → 27 `DELETE /v2/positions` **acceptés et mis en file**, exécution à l'ouverture
  (13:30 UTC). **Verrou durable** : `execute-trades` **v37** — liste `ETF_REF` + règles : **JU** ne
  peut plus ACHETER d'ETF, **SYL** plus d'action individuelle ; **GIL EXEMPTÉ** (univers large). Ventes
  libres. NB : paper. `oracle_positions_live` sera nettoyé après exécution (réconciliation Make ou
  manuelle).
- **Contrôle final du soldage + base nettoyée + fiches console corrigées.** À l'ouverture US, les 27
  ordres se sont exécutés : **JU = 100 % actions** (0 ETF), **SYL = 100 % ETF** (0 action, 0 crypto),
  **GIL** inchangé (rôle large). Bonus : annulé un **ordre XRP/USD (crypto) périmé** qui traînait sur
  SYL depuis le 07/06 (aurait pu réintroduire de la crypto). `oracle_positions_live` nettoyé (18 lignes
  JU + 9 SYL + résidus périmés) → base alignée sur la réalité. **Console corrigée** (les descriptions
  ne collaient plus) : SYL « Macro Internationale » → **« Paniers ETF »** ; GIL « Crypto Tactique » →
  **« Tactique Contrarian »** (univers large : crypto + proxies + couvertures actions/ETF à contre-pied) ;
  JU précisé « actions individuelles » ; Alchimiste précisé « au comptant, argent réel » ; « Le concept »
  réécrit (4 spécialistes + 1 contrarian). Modèle final : **JU actions · SYL ETF · Alchimiste crypto
  réelle · Marées forex · GIL polyvalent contrarian**.
- **Console « Crypto en direct » (valorisation 24/7, week-end compris).** Constat de Chachou :
  le week-end, sans faire tourner le scénario Make, la console reste figée. Diagnostic : ce ne sont
  **pas les cours** qui gèlent — `price_history` est alimenté H24 par des crons serveur indépendants
  de Make (BTC/ETH : 24 bougies/jour samedi ET dimanche). Ce qui gèle, c'est la couche de
  **valorisation** produite par Make (dashboard, `oracle_performance`), et surtout : les courbes des
  Sages lisent `oracle_performance` (une écriture **par run**), pas un mark-to-market live. Forex et
  actions sont, eux, **réellement fermés** le week-end (gel normal). Solution **100 % lecture, sans
  cron ni écriture** : deux vues `v_live_crypto_positions` / `v_live_crypto_resume` recalculées **à la
  lecture** depuis le dernier cours (comme le panneau Marées), exposées par `oracle-inbox` v16
  (`suivi.live_crypto`) + nouvelle section console **« Crypto en direct »**. Aucun ordre, aucune
  décision, ne touche NI au kill-switch NI au dry_run. Périmètre assumé : **seule la crypto** (la seule
  classe 24/7) est affichée ; le total de `oracle_positions_live` n'étant pas fiable, il n'est pas
  exposé. État actuel : SYL porte ~226 k$ de crypto (P&L latent live), GIL/JU = poussière.
  DDL : `supabase/schema/08_live_crypto.sql`.

## 2026-08-15

- **Marées — retrait du « contre-pied aveugle » côté base.** Il subsistait DEUX inversions distinctes :
  (1) le « contre-pied raisonné » dans le prompt de Marées (contrarian vs consensus excessif, seulement
  si espérance positive) = **légitime, conservé** ; (2) une inversion AVEUGLE du signal dans
  `marees_rebuild_virtual` (`buy↔sell` systématique), vestige de l'ancien prompt Gemini anti-prédictif.
  Comme le prompt de Marées a été **refait la session précédente**, cette 2ᵉ inversion faisait un
  double contre-pied et n'avait plus lieu d'être → **ligne retirée** (`lower(side) as side`, on trade le
  sens PROPOSÉ). Vérifié : les 25 positions ouvertes suivent désormais exactement le sens des
  propositions (`concorde=true` sur tout l'échantillon). Migration `marees_retire_contre_pied_aveugle`
  + `marees_rebuild_virtual` rejouée (28 trades, 0 clôturé — forex quasi plat, positions ≤49 h).
  → `supabase/schema/03_functions.sql`.
- **Marées — calibrage de la sortie + prompt Maia (mémoire, sorties, renommage).** (a) `marees_rebuild_virtual`
  calibré pour le forex : planchers TP 3→**1,2 %** / SL 2→**0,8 %** (ratio 1,5:1), détention 240→**96 h**
  → premières clôtures avancées (~17-19/08 au lieu du 23). (b) Vérif : le prompt de Marées ne lisait
  QUE `latest_web_catalysts` (pas de doctrine) → prompt Maia rédigé pour ajouter une **fente MÉMOIRE**
  lisant `brain_states.MAREES.current_bias`, aligner les consignes TP/SL, et **renommer** les modules
  génériques restants (« Staking délais », « Staking APY ») dans l'univers alchimique.
  → `docs/decisions/PROMPT-MAIA-MAREES-2026-08-15.md`.
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
