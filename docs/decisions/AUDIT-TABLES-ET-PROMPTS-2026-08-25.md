# Audit complet — tables, vues, prompts, chaîne d'exécution — 25/08/2026

Périmètre : **70 tables, 57 vues, les 10 modules LLM, la chaîne d'ordres**.
Tout ce qui est marqué ✅ est **appliqué et vérifié en direct**. Le reste est listé avec sa preuve.

---

## ✅ 1. Le coupe-circuit bloque enfin les ouvertures — `execute-trades` v42

**Ce qui n'allait pas.** `check_circuit_breakers` déclenchait bien (toutes les 2 h, job pg_cron
`directional_kelly_breakers`), mais **rien ne lisait le résultat au moment de passer les ordres** :
116 ordres sur 7 jours, 116 exécutés, 0 refusé, alors que GIL était à 10,23 % de drawdown.

**Ce qui est fait.** Avant toute OUVERTURE, `execute-trades` lit `oracle_brain_state` et
`oracle_circuit_breakers` et refuse achats d'ouverture et nouveaux shorts au-delà de 8 %.
Test de bout en bout sur GIL, sur la fonction déployée :

```
coupe_circuit = { defensif: true, drawdown: 0.1023,
                  motif: "coupe_circuit_drawdown_8pct (10.23%, declenche le 2026-08-25T14:19)" }
```

| Archimage | drawdown retenu | défensif |
|---|---|---|
| GIL | 10,30 % | **oui — plus aucune ouverture** |
| SYL | 3,46 % | non |
| JU | 0,44 % | non |

**Ce qui passe toujours, même en défensif** : rachat de vente à découvert, vente d'une position
détenue, sorties automatiques TP/SL, désendettement. Un coupe-circuit protège le capital, il
n'enferme pas dans une position.

**`iron_sentinel_validate_order` n'est volontairement pas appelée.** Elle contient
`v_cap numeric := 2000` : brancher la fonction telle quelle plafonnerait **chaque ordre à 2 000 $**
sur des portefeuilles à 500 k$ où `MAX_NOTIONAL_PER_ORDER` vaut 190 000 $. Elle a été écrite pour
un autre régime de sizing. Seule sa **règle** de drawdown est reprise.

---

## ✅ 2. Les Marées sont visibles — et elles écrivaient déjà

Deux objets portaient le même nom dans ma tête, et c'est ça qui trompait l'écran :

| Table | Ce que c'est | État au 25/08 |
|---|---|---|
| `marees_propositions` | le **livre cible** : ce que l'Archimage déclare tenir | **3 positions ouvertes** |
| `marees_virtual_trades` | le **simulateur d'évaluation**, reconstruit toutes les 6 h par `marees_rebuild_virtual`, qui **ferme d'office à 96 h** pour pouvoir noter chaque proposition | 0 position ouverte |

La console lisait `v_marees_virtuel_positions`, donc le simulateur, donc « Aucune position ouverte »
pendant que le livre en portait trois. **Nouvelle vue `v_marees_livre_cible`** (vérifié avant
création : rien n'exposait cette table), transmise par `oracle-inbox` v25 et affichée dans `aether`.

```
EUR-GBP  vente  2,5 %  entrée 0,8569  actuel 0,8555  +0,17 %  108 h
EUR-USD  vente  3,0 %  entrée 1,1582  actuel 1,1678  −0,83 %  173 h
USD-JPY  achat  5,0 %  entrée 158,88  actuel 159,21  +0,21 %  267 h
```

Et l'écriture marchait : log Supabase du run de 12:35 →
`12:38:02 POST | 200 | /rpc/marees_record_propositions | Make/production`. 3 tenues, 0 nouvelle,
0 fermée — donc rien de neuf en base, ce qui n'est pas une panne.

**Incohérence qui reste** : le simulateur ferme à 96 h, le livre cible ne ferme jamais. USD-JPY est
tenu depuis 267 h (11 jours) dans le livre, et compté comme clos depuis le 18/08 dans l'évaluation.
Le win rate de 13W/27L est calculé sur des sorties que l'Archimage n'a jamais décidées.
**Décision à prendre** (je ne tranche pas seul) : soit le simulateur ferme AUSSI la proposition,
soit l'horizon passe à la durée réelle de détention.

---

## ✅ 3. `oracle_flash_intel` était vide depuis toujours — la moitié est réparée

Le module Make **211 ⚡ FLASH INTEL LOGGER** appelle `/rpc/log_flash_intel` avec des clés nommées
(`run_id`, `summary`, `top_ticker`, `top_direction`, `catalysts`), alors que la fonction ne prenait
qu'un `p_payload jsonb`. Testé, réponse réelle :

```
404  {"code":"PGRST202","message":"Could not find the function
      public.log_flash_intel(catalysts, run_id, summary, top_direction, top_ticker)"}
```

`stopOnHttpError = false` → l'échec passait en silence. **La table n'a jamais reçu une ligne.**

**Corrigé côté Supabase** : surcharge `log_flash_intel(run_id, summary, top_ticker, top_direction,
catalysts)` qui délègue à la fonction existante. Retesté : `200 {"success": true,
"catalysts_logged": 1, "routage": {"JU":1,"SYL":1,"GIL":1,"CRYPTE_JU":1,"MAREES":1}}`.
Lignes de test supprimées.

**⚠️ Il reste la moitié du problème, et elle est côté Make** — voir §4.

---

## ⚠️ 4. Le Sage Flash ne produit pas ce que le module 211 lui demande

Son `response_format` est un `json_schema` **strict** avec `additionalProperties: false` et
8 champs : `top_headline_1`, `top_headline_2`, `market_shock`, `shock_type`, `btc_breaking_news`,
`urgency_level`, `flash_sentiment`, `immediate_action`.

Le module 211 lit **trois champs qui n'y sont pas** :

| Ce que 211 lit | Ce qu'il obtient | Conséquence |
|---|---|---|
| `210.web_intelligence` | `ND` | `summary` toujours vide |
| `210.trade_1.ticker` / `.side` | `MARKET` / `neutral` | jamais de ticker réel |
| `210.catalysts` | `[]` | **`catalysts_logged` toujours 0** |

Donc même avec la surcharge du §3, `oracle_flash_intel` restera vide. Et par ricochet,
`get_oracle_context().flash_intel_latest` est vide — or **le prompt de GIL le lit** : GIL reçoit un
bloc de renseignement vide à chaque run depuis toujours.

**Correctif Maia** : ajouter au `json_schema` du module 209 les propriétés `web_intelligence`
(string) et `catalysts` (array d'objets `{ticker, type, headline}`), et les ajouter à `required`.
Retirer la référence à `210.trade_1` dans le module 211, ou la remplacer par le premier catalyseur.

---

## ✅ 5. « Deux agents sur un moteur de recherche » — j'avais tort, la mesure le dit

J'ai écrit que SYL (303) et l'Alchimiste (10012) tournant sur `sonar-pro` risquaient le mal du
Sage Macro du 19/08 (« il cherche les champs sur le web au lieu de les analyser »). **C'était une
hypothèse tirée d'un cas ancien, et je ne l'avais pas vérifiée. Elle est fausse.**

Le symptôme d'un moteur figé, c'est une sortie qui ne bouge plus. Sur 55 runs des 14 derniers jours :

| Archimage | moteur | valeurs de `confidence` distinctes | étendue |
|---|---|---|---|
| **SYL** | Perplexity `sonar-pro` | **11** | 62 → 82 |
| GIL | Mistral `mistral-large-latest` | 3 | 65 → 78 |
| JU | Anthropic `claude-sonnet-4-5` | 2 | 6 → 7 |

**SYL est le plus variable des trois**, pas le moins. Et l'Alchimiste, sur 42 runs :
57 propositions, **17 paires différentes**, 22 valeurs de confiance (0,35 → 5,80),
**55 justifications distinctes sur 57**. Aucun signe de figement.

Ce qui avait rendu le Sage Macro malade n'était pas `sonar-pro` seul : c'était `sonar-pro` **plus**
un message de 8 421 caractères de champs collés par des barres verticales, que le modèle a traité
comme une requête de recherche — il l'écrivait lui-même dans `news_catalyst` : « CTX est ambigu ».
SYL et l'Alchimiste reçoivent un prompt rédigé, pas un CTX à plat. **Rien à changer.**

Ce qui reste vrai et vérifiable : ni 303 ni 10012 n'ont de `response_format`. Ils s'en sortent
grâce aux nettoyages des modules 304 et 10014. Le seul contrôle utile est celui du 19/08 : si les
valeurs de SYL se figent d'un run à l'autre, alors le mal est là. Aujourd'hui, non.

---

## ⚠️ 5 bis. Deux blocs du contexte injecté sont vides en permanence

`get_oracle_context()` renvoie 12 blocs. Deux sont des tableaux vides **à chaque run** :

| Bloc | Taille | Cause |
|---|---|---|
| `flash_intel_latest` | `[]` | le Sage Flash ne produit pas `catalysts` (§4) |
| `visionary_signals` | `[]` | la table `oracle_visionary_signals` n'a **jamais** reçu une ligne |

Pour `visionary_signals`, la fonction d'écriture **existe** — `log_visionary_signals(p_payload jsonb)`,
qui attend `{run_id, signals:[{signal_type, ticker, signal_value, signal_label, conviction,
time_horizon, source}]}` — mais **aucun module Make ne l'appelle**. Vérifié sur les 80 modules :
zéro occurrence. Le module 901 cite bien « visionary », mais c'est la colonne `visionary_score` de
`oracle_college_runs` qu'il lit, pas cette fonction.

C'est la même maladie que le Flash Intel, au stade au-dessus : là il y avait un appel avec la
mauvaise signature, ici il n'y a pas d'appel du tout. Deux blocs sur douze du contexte des agents
ne transportent rien.

**Deux issues, au choix :** brancher un module Make sur `log_visionary_signals`, ou retirer le bloc
de `get_oracle_context()`. Je n'en applique aucune sans décision : la première ajoute une donnée
aux prompts, la seconde en retire une.

---

## ⚠️ 6. Aucun module Sage n'a de gestion d'erreur

Les cinq Sages (201, 203, 205, 207, 209) ont `stopOnHttpError = false` et **aucun `onerror`**.
C'est ce qui a laissé le Sage Mémoire mourir du 21/08 au 25/08 sans le moindre signal.
Seul le module 10012 (Alchimiste) a `stopOnHttpError = true`.

**Correctif Maia** : « Evaluate all states as errors » sur les 5 Sages + une route d'erreur
`Resume` renvoyant `{}`, pour que le scénario continue mais que l'échec soit visible.

---

## État des moteurs, au 25/08 21 h

| Module | Moteur | Modèle | max_tokens | mode JSON | stopOnHttpError |
|---|---|---|---|---|---|
| 201 Macro | Groq | `openai/gpt-oss-120b` | 1 500 | json_object | false |
| 203 Technique | Groq | `openai/gpt-oss-120b` | 2 000 | json_object | false |
| 205 Risque | Mistral | `mistral-large-latest` | 4 000 | json_object | false |
| 207 Mémoire | Gemini | `gemini-3.5-flash` | 2 000 | — | false |
| 209 Flash | Perplexity | `sonar-pro` | 1 500 | json_schema | false |
| 301 JU | Anthropic | `claude-sonnet-4-5` | 12 000 | **aucun** | false |
| 303 SYL | Perplexity | `sonar-pro` | 8 000 | **aucun** | false |
| 305 GIL | Mistral | `mistral-large-latest` | 8 000 | json_object | false |
| 10012 Alchimiste | Perplexity | `sonar-pro` | 8 000 | **aucun** | **true** |
| 20015 Marées | Gemini (app Make) | `gemini-3.5-flash` | défaut | responseMimeType | — |

---

## Contrôles passés sans écart

- **Les 10 prompts** : toutes les références `105.data.*` résolvent contre la sortie réelle de
  `get_oracle_context()` (52 chemins contrôlés un par un). Zéro référence morte.
- **Schémas de sortie contre consommation aval** : conformes pour les 5 Sages sauf le Flash (§4),
  et pour les 3 Archimages, l'Alchimiste et les Marées. La clé `livre_cible` des Marées correspond
  exactement aux champs lus par `marees_record_propositions` (`paire`, `side`, `poids_pct`,
  `confidence`, `raison`, `prix_ref`, `tp_pct`, `sl_pct`).
- **`FIABILITE_SAGES`** (module 215) : lit bien `105.data.sages_coaching`, plus le texte figé
  signalé le 21/08.
- **57 vues** : aucune en erreur. Quatre vides, toutes expliquées
  (`v_alc_virtuel_positions` et `v_marees_virtuel_positions` = simulateurs à horizon,
  `v_portfolio_open` et `v_recent_performance` = inutilisées).
- **`oracle_positions_live`** : 77 lignes, synchro du 25/08 14:37, 0 périmée, 16 shorts.
  C'est la source de la concentration croisée dans `execute-trades`.
- **`marees_config`** : 10 paires autorisées, `max_poids_pct` 5, `max_gross_pct` 50, kill_switch OFF.
  Les 3 positions tenues respectent les trois bornes (somme des poids 10,5 % sur 50 autorisés).

---

## Ménage — ce qui peut encore servir, objet par objet

Question posée : « avant de faire le ménage ça serait utile de savoir si quelque chose peut
réellement servir ». J'ai ouvert chaque objet. Trois catégories, pas une.

### À GARDER — ça sert, ou ça contient déjà quelque chose d'utile

| Objet | Contenu réel | Pourquoi le garder |
|---|---|---|
| **`v_perf_anomalies`** | **6 lignes** | Compare l'equity **mesurée** à l'equity **Alpaca** et chiffre l'écart. C'est le contrôle qui aurait attrapé le faux +55 % : il montre encore JU à +174 432 $ d'écart le 18/08 (17,45 % du capital), marqué `fiable = false`. **À brancher dans la Vigie et dans la console.** |
| **`v_vigie_incidents`** | **9 incidents** | Historique ouvert/clos des pannes détectées, avec durée. La console affiche l'état courant mais pas l'historique. |
| **`oracle_visionary_signals`** | 0 ligne | **Ce n'est pas une table morte : c'est un canal branché sur les prompts** (`get_oracle_context().visionary_signals`) que personne n'alimente. Voir §5 bis. Supprimer la table casserait le bloc. |
| **`v_oracle_performance`** | 5 lignes | PnL, win rate, drawdown et poids par archimage, croisés avec le nombre d'ordres. Plus complet que `v_perf_resume` sur la partie ordres. |
| **`oracle_recent_runs_v2`** | **276 runs** | Les 276 runs du Collège avec consensus, ordres, overlap, coupe-circuit. Données vivantes. Le module 901 refait la même requête à la main sur `oracle_college_runs`. |
| **`v_alc_bt_resume`** / `v_alc_bt_daily` | **10 stratégies** | Les backtests de l'Alchimiste, par stratégie, win rate net et rendement. `refresh_backtest_cache` ne les lit pas (vérifié) : `oracle_backtest_cache` est rempli autrement. Utile pour comparer stratégie contre stratégie. |
| **`v_alc_riskoff_resume`** | 2 lignes | Stratégie risk-off : jours en cash contre jours investis, cumul. |
| **`v_rapport_periodes`** / `v_rapport_mensuel_virtuels` | 24 / 2 lignes | Rendements par période des **virtuels** (ALC_VIRT, MAREES). Doublonnent partiellement `v_rendements_periodes`, mais sur un périmètre que celle-ci ne couvre pas de la même façon. |
| **`market_data_cache`** | 0 ligne | 20 colonnes de données de marché (VIX, taux, CPI, BTC, Fear&Greed, qualité). **Rien ne persiste aujourd'hui le CTX d'un run** : il ne vit que dans le journal d'exécution Make. Cette table permettrait de rejouer et d'auditer un run passé. |
| **`app_users`** | 0 ligne | Comptes abonnés, profil de risque, capital, clés Alpaca par utilisateur. C'est le socle de la vitrine d'abonnés. À garder. |
| **`fonds_versements`** | 0 ligne | Versements du fonds. `fonds_config` dit « inactif, calcul seulement, 50 % des gains » — la table est le pendant, prête pour l'activation. |

### À SUPPRIMER — architecture v1, remplacée, et plus rien ne les lit

Toute cette grappe tourne autour de **`oracle_runs`** (un run = une ligne, 90 colonnes,
`master_word`, `synth_a_phase`…), remplacée par `oracle_college_runs` (276 lignes vivantes).

| Objet | Remplacé par |
|---|---|
| `oracle_runs` (0 ligne, 90 colonnes) | `oracle_college_runs` |
| `portfolio_virtual` (0) | `oracle_positions_live` (77 lignes) |
| `positions_recommended` (0) | `oracle_college_orders` (1 577 lignes) |
| `alpaca_orders` (0, 30 colonnes) | `oracle_college_orders` |
| `oracle_logs` (0) | `oracle_exec_debug` (726 lignes) |
| `oracle_market_cache` (0) | jamais alimentée, doublon de `market_data_cache` |
| `marees_positions` (0) | `marees_propositions` (116 lignes) |
| `market_signals` (0) | jamais alimentée (géopolitique, séismes, alertes météo) |
| `v_portfolio_open` (0) | lit `portfolio_virtual` + `oracle_runs`, deux tables vides |
| `v_recent_performance` (0) | lit `oracle_runs`, vide |
| `v_oracle_stats` (1 ligne bidon) | compte des `market_phase` dans `oracle_runs`, vide |

### SAUVEGARDES — à trancher

8 tables, ~1 700 lignes : `bak_20260813_*` (5 tables, la casse de l'Alchimiste),
`bak_20260820_*` (2), `bak_20260821_alc_virtual_trades`, `bak_20260823_lecon_manuelle`,
`_ju_brain_backup`. Les plus anciennes ont 13 jours. Elles ne coûtent presque rien et elles sont
la seule trace d'avant mes corrections. **Mon avis : garder celles du 13/08 tant que le scénario
n'a pas retrouvé un régime stable, supprimer le reste quand tu me le diras.**

---

## Point de sécurité

Le blueprint Make contient **en clair** les clés Alpaca des trois comptes (`PKCLIVE...` + secret) et
la clé `anon` Supabase. Les comptes Alpaca sont en **paper**, donc l'exposition est limitée à des
portefeuilles simulés, mais quiconque lit le blueprint peut passer des ordres dessus. À déplacer
vers des connexions Make ou le Vault quand le reste sera stabilisé.

Rappel de l'existant : `ju_crypte_config` contient `arm_pin = 2050` **en clair**, hors Vault
(déjà signalé le 23/08).
