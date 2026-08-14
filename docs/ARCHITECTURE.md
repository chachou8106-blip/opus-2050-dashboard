# AETHER / OPUS 2050 — Architecture du système

> Système de trading multi-agents autonome. Ce document décrit **tout** le système pour le suivi,
> la maintenance et le passage au réel. Dernière mise à jour : **14/08/2026**.
> Projet Supabase : `smddzybxebwhfnitxuyp`. Console en ligne : `https://oracle-financier.netlify.app/console_aether%202.html`.

---

## 1. Vue d'ensemble

AETHER fait travailler ensemble **cinq stratégies spécialisées** (« archimages »), pilotées chacune
par une IA, plus un **moteur central** qui mesure leurs résultats et réalloue le capital. Chaque
stratégie apprend de ses résultats (brain states) et est encadrée par des règles de risque.

| Stratégie | Clé(s) interne(s) | Marché | Exécution | Capital / devise |
|---|---|---|---|---|
| **JU** | `JU` | Actions US (grandes caps) | Alpaca **paper** | ~1 000 000 $ (simulation) |
| **SYL** | `SYL` | Macro internationale | Alpaca **paper** | ~1 000 000 $ (simulation) |
| **GIL** | `GIL` | Crypto tactique (contrarian) | Alpaca **paper** | ~1 000 000 $ (simulation) |
| **Alchimiste réel** | `CRYPTE_JU` / `ALC` | Crypto **au comptant** | **Revolut X — ARGENT RÉEL** | portefeuille réel (USD) |
| **Alchimiste virtuel** | `ALCHIMISTE` (séries perf) | Crypto (apprentissage papier) | simulation sur prix réels | notionnel |
| **Marées** | `MAREES` | Forex (devises) | virtuel (MT5 bridge) | notionnel |
| **AETHER / OPUS** | `OPUS` | Indice d'ensemble | — | moyenne/somme des sages validés |

⚠️ **Seul l'Alchimiste réel engage de l'argent réel** (Revolut X, au comptant, pas de levier, pas de
short). Tout le reste est en simulation / apprentissage.

---

## 2. Flux de données (pipeline)

```
Marchés → Ingestion (edge functions, pg_cron) → price_history → Contexte → IA (Make) →
   → Propositions → Exécution → Réconciliation → Apprentissage (brain states) → Console
```

### 2.1 Ingestion de prix (source de vérité : `price_history`)
`price_history(symbol, interval, ts, open, high, low, close, ...)` est alimentée **chaque heure** :

| Edge function | Source | Cron |
|---|---|---|
| `ingest-klines` | Binance (klines) | `ingest_binance_hourly` (2 * * * *), `ingest_prix_6h` |
| `ingest-gate-prices` | Gate.io | `ingest_gate_hourly` (4 * * * *) |
| `ingest-revx-prices` | Revolut X | `ingest_revx_hourly` (7 * * * *) |
| `ingest-fx` | Forex (EUR-USD, GBP-USD…) | `ingest_fx_6h` |
| `ingest-spy` | SPY intraday | `ingest_spy_horaire` (15 * * * *) |
| `ingest-indices` | Indices (QQQ, GLD, EEM…) | `ingest-indices-daily` (0 21 * * *) |

> ⚠️ **Table morte** : `revolut_univers_complet` (univers tickers) est figée depuis le 07/07/2026 et
> n'est plus alimentée. L'univers réellement coté vit dans `price_history` (~311 symboles/3h). Voir
> `docs/decisions/CORRECTIF-UNIVERS-SANTE-2026-08-14.md`.

### 2.2 Contexte marché
`oracle_contexte`, `v_world_context`, régime mondial (`world_regime_journal`), fournis aux IA.

### 2.3 Décision (IA)
- Les **sages** (JU/SYL/GIL) et l'archimage crypto passent par des scénarios Make + modèles IA.
- **L'Alchimiste** : scénario Make **6183820** « ZCT — Oracle L'Alchimiste Financier v5 VISIONNAIRE »
  (édité via l'assistant **Maia** de Make — voir §5). Il appelle Perplexity `sonar-pro`, produit un
  JSON `{propositions[], destake_recommande[], commentaire}`, puis l'enregistre via
  `alc_record_propositions` (voir §4) et exécute via `alc-auto`.

### 2.4 Exécution
| Trader | Voie d'exécution |
|---|---|
| JU/SYL/GIL | `execute-trades` / `oracle-college-orders` → Alpaca paper |
| Alchimiste réel | `alc-auto` → `revolut-x-trade` (Ed25519 signé) → Revolut X — **sous kill-switch** |
| Marées | `mt5-bridge` (virtuel) |

Tables d'ordres : `oracle_college_orders` (canonique JU/SYL/GIL), `ju_crypte_orders` (Alchimiste
réel), `alchimiste_crypte_propositions` (propositions Alchimiste). ⚠️ `alpaca_orders` est une table
**morte** (0 ligne) ; la table réelle est `oracle_college_orders`.

### 2.5 Réconciliation
`reconcile-orders` / `confirm-fills` (cron `reconcile_orders_horaire`) mettent à jour les statuts de
remplissage (`filled`, `fill_price`, `executed_notional`).

### 2.6 Apprentissage
`oracle_brain_state` (par archimage : `win_rate`, `current_bias`/doctrine), `learning_feedback`
(précision régime, `auto_cron`). Crons : `crypte_ju_apprentissage`, `marees_apprentissage`,
`evaluer_win_loss_archimages`, `directional_kelly_breakers`, `learning_feedback_auto`.

---

## 3. Le kill-switch (sécurité argent réel)

`ju_crypte_config.kill_switch` = `ON` (ordres réels actifs) / `OFF` (désarmé).
- **DÉSARMER (OFF)** et **STATUS** : toujours libres (anti-lockout).
- **ARMER (ON)** : exige le PIN `ju_crypte_config.arm_pin` (initial `2050`) **ou** Face ID (WebAuthn).
- Edge functions : `ju-killswitch` (PIN), `ju-passkey` (Face ID, domaine `oracle-financier.netlify.app`).
- Bouton dans la console (`console_aether 2.html`, espace opérationnel, verrouillé par Face ID).
- Détails + procédures de secours : `supabase/functions/README-KILLSWITCH.md`.

> 🔒 **Règle absolue** : ne JAMAIS armer/désarmer le kill-switch ni passer `dry_run=false` sans l'accord
> explicite de Chachou. Ce geste lui appartient.

---

## 4. Base de données (tables clés)

**Traders / ordres** : `oracle_college_orders`, `ju_crypte_orders`, `alchimiste_crypte_propositions`,
`alchimiste_virtual_trades`, `marees_propositions`, `marees_virtual_trades`, `marees_positions`,
`oracle_positions_live`, `positions_recommended`, `alc_destake_reco`.
**Portefeuille réel** : `revolut_portfolio_daily` (`total_usd`, `cash_usd`, `stake_usd`…).
**Prix / marché** : `price_history`, `oracle_contexte`, `world_regime_journal`.
**Apprentissage** : `oracle_brain_state`, `learning_feedback`, `oracle_dashboard`.
**Staking** : `alc_staking_apy`, `alc_staking_delais`, `alc_staking_lots`, `alc_staking_holdings`.
**Journal / suivi** : `oracle_journal`, `oracle_problemes`, `oracle_rappels`.
**Config / sécurité** : `ju_crypte_config`, `marees_config`, `killswitch_passkeys`, `killswitch_webauthn`.

**Vues importantes** (dump complet dans `supabase/schema/02_views.sql`) :
- `v_equity_points` — séries d'équité par trader (JU/SYL/GIL depuis `oracle_performance`, ALCHIMISTE
  depuis `revolut_portfolio_daily`, MAREES depuis `marees_virtual_trades`).
- `v_comparaison` / `v_rendements_periodes` — rendements cumulés & par période (jour/semaine/mois/année).
- `v_gains_traders` — **tableau des gains en €/$/%** par trader et horizon (source unique de la console).
- `v_staking_point` — coût/valeur/PnL du staking coin par coin.
- `v_data_health` — fraîcheur des sources (alerte FIGE/OK).
- `v_alc_virtuel_resume` / `_jour` / `_positions` — portefeuille papier de l'Alchimiste.

Le schéma complet (tables, vues, fonctions, cron, policies) est exporté dans **`supabase/schema/`**.

### `alc_record_propositions` (enregistrement des propositions Alchimiste)
Reçoit le JSON IA (base64), itère `propositions[]`, mappe les colonnes
(`paire/side/montant/confidence/raison`), récupère `prix_ref` depuis `price_history` si absent, et
persiste `destake_recommande[]` dans `alc_destake_reco`. Voir
`docs/decisions/CORRECTIF-ALCHIMISTE-MAPPING-2026-08-14.md`.

---

## 5. Services externes

| Service | Rôle | Accès |
|---|---|---|
| **Revolut X** | Crypto **réelle** au comptant | API Ed25519 signée (`REVX_API_KEY`, `REVX_PRIVATE_KEY`) |
| **Alpaca** | Actions/crypto **paper** (JU/SYL/GIL) | clés Alpaca (env edge functions) |
| **Make.com** | Orchestration des scénarios IA | assistant **Maia** ; scénario Alchimiste = **6183820** |
| **Perplexity** (`sonar-pro`) | Cerveau de l'Alchimiste | clé dans Make |
| **Groq** (`llama-3.3`) | Contexte macro (autres archimages) | clé dans Make |
| **Netlify** | Hébergement de la console | déploiement auto depuis la branche `main` |
| **Discord** | Notifications | webhook |
| **MT5 bridge** | Forex Marées | `mt5-bridge` |

> 🔒 **Règle absolue** : ne JAMAIS modifier le blueprint Make en direct. Toute modification Make passe
> par **Maia** (voir les prompts type dans `docs/decisions/PROMPT-MAIA-*.md`).

Secrets (jamais commités ; noms seulement) : `SUPABASE_URL`, `SUPABASE_SERVICE_ROLE_KEY`,
`REVX_API_KEY`, `REVX_PRIVATE_KEY`, clés Alpaca, clés Perplexity/Groq (dans Make), webhook Discord.
La clé **anon** Supabase est publique (présente dans la console) — ce n'est pas un secret.

---

## 6. La console (`console_aether 2.html`)

Page unique servie par Netlify, lit tout via l'edge function **`oracle-inbox`** (`action: suivi` pour
les perfs/gains/courbes ; `action: journal` pour journal/demandes/rappels ; `action: report` pour
envoyer un message). Sections : concept, stratégies (courbes), métriques, **gains par trader (€)**,
comparatif marchés, statistiques, portefeuille virtuel Alchimiste, rendements mensuels, performance,
et un **espace opérationnel verrouillé par Face ID** (kill-switch, calendrier, journal, contexte).

> `_headers` force `Cache-Control: max-age=0` pour éviter le cache Netlify. Astuce anti-cache navigateur :
> suffixer l'URL de `?v=N`.

Les autres fichiers HTML à la racine (`console_aether.html`, `console_opus2050*.html`, `dashboard.html`,
`index.html`, `suivi.html`) sont des **versions antérieures / dashboards annexes** conservés pour
historique. **La console vivante est `console_aether 2.html`.**

---

## 7. Où trouver quoi (carte du repo)

```
console_aether 2.html          ← LA console en production (Netlify)
_headers                       ← règles de cache Netlify
docs/
  ARCHITECTURE.md              ← ce fichier
  RUNBOOK.md                   ← exploitation, secours, incidents
  PASSAGE-AU-REEL.md           ← checklist argent réel
  CHANGELOG.md                 ← journal des décisions/changements
  decisions/                   ← correctifs datés & prompts Maia
supabase/
  functions/<slug>/index.ts    ← source de TOUTES les edge functions déployées
  functions/_MANIFEST.md       ← table des edge functions (version, rôle)
  functions/README-KILLSWITCH.md
  README-DAILY-JOURNAL.md
  schema/                      ← dump SQL complet (tables, vues, fonctions, cron, policies)
```
