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

## ⚠️ 5. Deux agents décident sur un moteur de recherche web

| Module | Moteur | Enjeu |
|---|---|---|
| **303 SYL** | Perplexity `sonar-pro` | portefeuille papier ~500 k$ |
| **10012 Alchimiste** | Perplexity `sonar-pro` | **ARGENT RÉEL** (Revolut X) |

C'est exactement le diagnostic posé le 19/08 pour le Sage Macro : *« sonar-pro traite le message
comme une requête de recherche. On lui envoie 8 421 caractères de champs séparés par des barres
verticales ; il les cherche sur le web au lieu de les analyser. »* Le Macro a été basculé sur Groq
pour cette raison. SYL reçoit 6,6 ko de contexte, l'Alchimiste davantage — et aucun des deux n'a
`response_format`.

Je ne propose pas de bascule à chaud sur l'Alchimiste : c'est de l'argent réel et il fonctionne.
Mais **le contrôle de guérison du 19/08 s'applique** : si `market_phase` ou `confidence` de SYL ne
bougent plus d'un run à l'autre, c'est le même mal.

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

## Ménage possible — rien n'est supprimé sans accord

**13 tables vides depuis leur création** : `market_data_cache`, `oracle_flash_intel` (§3-4),
`alpaca_orders`, `app_users`, `marees_positions`, `market_signals`, `oracle_market_cache`,
`oracle_runs`, `portfolio_virtual`, `positions_recommended`, `oracle_logs`,
`oracle_visionary_signals`, `fonds_versements`.

**12 vues qu'aucune fonction, aucune vue, aucune edge function et aucun module Make ne lit** :
`oracle_recent_runs_v2`, `v_alc_bt_daily`, `v_alc_bt_resume`, `v_alc_riskoff_resume`,
`v_oracle_performance`, `v_oracle_stats`, `v_perf_anomalies`, `v_portfolio_open`,
`v_rapport_mensuel_virtuels`, `v_rapport_periodes`, `v_recent_performance`, `v_vigie_incidents`.

**8 tables de sauvegarde**, ~1 700 lignes : `bak_20260813_*` (5), `bak_20260820_*` (2),
`bak_20260821_*`, `bak_20260823_*`, `_ju_brain_backup`.

---

## Point de sécurité

Le blueprint Make contient **en clair** les clés Alpaca des trois comptes (`PKCLIVE...` + secret) et
la clé `anon` Supabase. Les comptes Alpaca sont en **paper**, donc l'exposition est limitée à des
portefeuilles simulés, mais quiconque lit le blueprint peut passer des ordres dessus. À déplacer
vers des connexions Make ou le Vault quand le reste sera stabilisé.

Rappel de l'existant : `ju_crypte_config` contient `arm_pin = 2050` **en clair**, hors Vault
(déjà signalé le 23/08).
