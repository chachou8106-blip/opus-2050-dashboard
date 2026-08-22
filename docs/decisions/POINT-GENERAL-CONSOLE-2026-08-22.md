# Point général — tests de bout en bout de la console AETHER

**Date :** 22/08/2026, 17h10 (Paris) · **Demandé par :** Chachou
**Périmètre :** les 8 onglets de `aether.html`, toutes leurs sources de données.

## Ce qui a été réellement testé

| Objet | Nombre | Méthode |
|---|---|---|
| Onglets de la console | 8 | source par source, bloc par bloc |
| Blocs de `dashboard_snapshot()` | 17 | RPC exécutée, chaque clé inspectée |
| Vues | 26 | comptées + datées + définitions relues |
| Fonctions / RPC | 12 | exécutées |
| Tâches pg_cron | 22 | dernier passage + échecs sur 24 h |
| Edge functions | 2 (`oracle-tests`, `oracle-inbox`) | code relu, **toutes** leurs requêtes rejouées en SQL |
| Historique Make | scénarios 6183820 et 7051944 | exécutions listées, dernière erreur ouverte |

> Les edge functions n'ont pas pu être appelées en HTTP depuis cet environnement
> (le proxy sortant refuse `supabase.co` en CONNECT 403). Elles ont donc été testées
> par relecture du code **et** rejeu intégral de leurs requêtes côté base — ce qui couvre
> tout sauf le transport HTTP lui-même.

## Verdict global

La couche données va bien. Ce qui est figé est figé côté **Make**, pas côté Supabase :

- 22 tâches cron sur 22 actives, **0 échec sur 24 h** ;
- prix, FX et crypto ingérés jusqu'à 17h05 ; backtests recalculés à 14h35 ;
- Alchimiste virtuel réparé (la contrainte de clé primaire qui bloquait le rebuild
  depuis le 21/08 est levée : 54 trades, 25 clôturés, WR 84 %) ;
- dernier run complet du Collège : **21/08 09h05**. Scénario Make à l'arrêt
  (`applied_state = inactive` depuis le 21/08 21h20), crédits épuisés jusqu'au 25.

Sept défauts réels ont été trouvés. Aucun ne concerne la collecte de données ;
tous concernent **ce que la console affiche**.

---

## Onglet par onglet

### 1 · Aperçu — OK
Source : `oracle-inbox/suivi` + `oracle-tests/hero`.
`oracle_dashboard` est une vue vivante (17h07, 5 agents). 28 lignes de gains,
55 points d'equity par série, 23 Sharpe. Chiffres du bandeau :
**+76 709 $ cumulés, 3 076 756 $ de valeur totale, WR 51,0 %, S&P +4,30 %, alpha −1,74 pt.**

### 2 · Stratégies — 2 défauts
- **MARÉES est vide.** `v_perf_resume` code en dur `NULL, NULL, NULL` pour MAREES
  (vue écrite avant que Marées ait des trades). Or Marées a aujourd'hui 40 trades
  virtuels et un WR de 30,8 %. La ligne existe mais n'affiche rien.
- **Deux rendements différents pour le même portefeuille Alchimiste.**
  `alc_stats.rendement_compose_pct` = **59,7 %** (composé trade par trade, comme si
  chaque trade mobilisait 100 % du capital) ; `v_alc_virtuel_jour.cumul_pct` = **17,4 %**
  (composé jour par jour, pondéré par les montants réellement engagés).
  La console affiche la courbe à 17,4 % et la carte KPI à 59,7 %, côte à côte.
  Le chiffre honnête est 17,4 %.

### 3 · Marchés — OK
23 séries, aucune manquante. Cryptos à jour au 22/08, ETF au 21/08 (week-end, normal).
`v_comparaison` 1 269 lignes — la pagination ajoutée le 19/08 tient, URTH / USO / XRP
remontent bien.

### 4 · Collège — OK sur l'affichage, 1 alerte sur le fond
Les 5 Sages sont mesurés et **cohérents** entre la jauge (`evaluate_sages`) et le
coaching (`sages_coaching`) : Mémoire 82,4 · Macro 62,7 · Technique 61,9 · Risque 54,7 · Flash 49,5.

Mais : **depuis le 19/08 22h18, aucun run n'a produit les 5 Sages.** Au mieux 4 sur 5.
Au dernier run (22/08 10h51) : Flash, Macro, Risque, Technique ont écrit — **Mémoire non**.
Le module 207 avait alors encore une clé Gemini incorrecte ; elle a été corrigée à 11h04–11h13,
soit **après** ce run. La correction n'a donc jamais été exercée.

Sur le fond, deux chiffres à connaître :
- Kelly réel : **JU et GIL n'ont aucun edge** (Kelly brut −0,77 % et −3,23 %, plancher à 0,5 %).
  SYL est le seul actif (+3,68 % brut).
- Précision directionnelle : GIL **44,6 %**, sous le hasard, sur 112 évaluations.

### 5 · Portefeuille — 2 défauts, dont un grave à l'affichage
- **3 positions fantômes gonflent le P/L latent de +324 985 $.**
  Alpaca laisse des résidus crypto à `qty = 0,000000001` avec un prix d'entrée moyen
  aberrant (SOLUSD de GIL : `avg_entry_price = −188 325 097 639 587`). Résultat :

  | Agent | P/L latent affiché | P/L latent réel |
  |---|---|---|
  | GIL | +203 849 $ | **+15 524 $** |
  | JU | +136 308 $ | **−355 $** |
  | SYL | +15 003 $ | +15 003 $ |

  La vue `ju_archimage_metrics` est protégée par hasard (elle filtre `|market_value| ≥ 50`) ;
  le bloc `positions_vivantes` de `dashboard_snapshot()`, lui, ne filtre rien. D'où deux
  chiffres contradictoires dans la même console. Ces mêmes lignes reviennent à chaque run
  sous le motif `dust_unsellable`.
- **SYL est au levier 2,00**, plafond réglementaire : 2 135 529 $ d'exposition brute pour
  1 067 424 $ de capital, dont un short TLT de **−1 681 547 $ détenu depuis 220 runs**.
  Ce n'est pas un bug d'affichage, c'est une position à regarder.

### 6 · Réel — 2 défauts
- Le bloc titré « **L'Alchimiste — capital réel (Revolut X)** » affiche les chiffres du
  portefeuille **virtuel** (`alc_stats`), étiquetés « Win rate réel ». Les vrais chiffres
  existent et sont utilisés partout ailleurs dans la page (`v_alc_reel_live` :
  **1 005 $ valorisés en direct, 49 lignes, snapshot 10h00**). Seul ce bloc-là se trompe de source.
- **La porte 1 est fausse.** Le gate « aucun drawdown au-dessus de 5 % » lit
  `oracle_brain_state.current_drawdown`, colonne figée : GIL y est à **6,26 %** — soit
  exactement son drawdown *maximum* historique. La colonne alimentée par le broker,
  `alpaca_drawdown_from_peak`, dit **0,59 %**. L'onglet Collège lit la bonne colonne,
  l'onglet Réel la mauvaise : le même drawdown s'affiche 6,26 % ici et 0,59 % là.

  État réel des 4 portes aujourd'hui : **2 sur 4**.

  | Porte | Valeur | État |
  |---|---|---|
  | Drawdown < 5 % | 6,26 % (faux) — 0,59 % en vrai | KO à l'écran, **OK en réalité** |
  | WR collectif ≥ 52 % | 51,0 % | KO |
  | Aucun agent < 45 % | min 49,0 % | OK |
  | Alpha positif | −1,74 pt | KO |

### 7 · Journal — OK
Le registre d'incidents de LA VIGIE fonctionne comme prévu : **3 incidents ouverts,
2 clos avec leur durée**. L'incident « Tâches planifiées — `alc_rebuild_virtual_6h` »
ouvert le 21/08 15h00 et clos le 22/08 15h00 est la trace durable de la réparation
demandée. 3 rappels en attente, dont un **échu demain 23/08** (calibrage des sorties Marées).

Détail mineur : chaque créneau est écrit **deux fois** (par le cron `aether-point-*`
et par un second rédacteur), donc les entrées apparaissent par paires.

### 8 · Ops — OK
Scénario à l'arrêt, `kill_switch` = OFF, 22 crons verts, plafond Alchimiste 200 $/jour.
Un chiffre à ne pas croire : **le slippage moyen affiché** (−22,5 % SYL, −19,3 % GIL,
−9,8 % JU). La médiane est à **0,000 %** ; la moyenne est détruite par 233 valeurs
aberrantes sur 741 (minimum −93,1 %). C'est un problème de calcul de moyenne,
pas un coût de transaction réel.

---

## Transversal

**Toutes les heures de `dashboard_snapshot()` sont en UTC**, sans mention, donc
2 h en retard : `to_char(run_at, 'MM-DD HH24:MI')` sans conversion de fuseau, alors
que la session Postgres est en UTC. Les blocs servis par `oracle-inbox` renvoient
des horodatages ISO que le navigateur convertit en heure de Paris. Conséquence :
le même run s'affiche **07:05** sur un onglet et **09:05** sur un autre.
Concerne : `genere_a`, `runs`, `cerveau.maj`, `meta_cerveau.maj`, `sante_flux.quand`,
`propositions.quand`, `ordres_recents.quand`, `debug_execution.quand`.

Trois constats déjà listés dans l'audit du 21/08 et toujours vrais :
- `oracle_flash_intel` : **0 ligne** depuis toujours, `catalyst_updated_at` NULL pour les 6 agents ;
- `alchimiste_crypte_propositions` : **0 validée sur 56** — aucune proposition ne franchit `proposee` ;
- le créneau **9h00 Paris** tombe marché US fermé : au run du 21/08, 15 ordres écartés
  pour `us_market_closed_equity_buy` / `short_market_closed`, 5 acceptés.

## Côté Make

- Dernière exécution du **6183820** : 22/08 10h50, en erreur —
  `InvalidConfigurationError · The provided JSON body content is not valid JSON`,
  module fautif `http:MakeRequest`. C'est la signature du module **303 (SYL)** :
  dans la sauvegarde du blueprint prise à 11h20, 303 est le seul Sage/Archimage dont
  le corps porte encore un `\` d'échappement invalide (`Invalid \escape`, position 6316).
  Les 5 Sages, eux, sont tous syntaxiquement corrects.
- Le scénario **7051944 n'a jamais été exécuté** : son historique ne contient qu'un
  événement `modify`. La correction qu'il porte n'a donc encore **jamais été vérifiée
  en conditions réelles**.

## Corrections — TOUTES APPLIQUÉES le 22/08 au soir

Chachou : « je veux que tu corriges intégralement ma console pour que chaque onglet
soit bien la réalité du terrain ». Les sept défauts ci-dessus sont corrigés, plus
quatre autres trouvés en corrigeant. Détail SQL : `supabase/schema/16_console_verite_terrain.sql`.

| # | Correction | Où | Vérifié |
|---|---|---|---|
| 1 | 10 `to_char()` passent en `Europe/Paris` | `dashboard_snapshot()` | `genere_a` = 21:19 Paris, dernier run « 08-21 **09:05** » |
| 2 | Positions fantômes écartées (`avg_entry_price > 0`) | `dashboard_snapshot()`, `ju_archimage_metrics`, `oracle-tests/archimage_detail` | GIL +15 196 $ · JU −353 $ · 4 lignes aberrantes comptées à part |
| 3 | Drawdown résolu sur la colonne du broker | `oracle-tests` v12 (`ddResolu`) | GIL 0,59 % · `dd_source=alpaca_drawdown_from_peak` · **porte 1 OK** |
| 4 | Le bloc « capital réel (Revolut X) » affiche le capital réel | `aether.html` `rReel()` | 1 004 $ / 861 € / 49 lignes ; le virtuel reste, nommé « (virtuel) » |
| 5 | MARÉES et ALCHIMISTE alimentés | `v_perf_resume` | MARÉES −3,01 % / 30,8 % · ALCHIMISTE 17,42 % / 84 % |
| 6 | Un seul rendement Alchimiste partout | `oracle-tests`, `aether.html` ×2 | `rendement_pct` = 17,42 ; l'autre renommé `rendement_compose_theorique_pct` |
| 7 | Médiane au lieu de la moyenne | `v_couts_friction` | GIL −1,945 · JU 0,000 · SYL −1,960, aberrations exposées |

Trouvés et corrigés en chemin :

| # | Correction | Où |
|---|---|---|
| 8 | `meilleur_pct` de GIL à **456,03 %** et volatilité à **87,41** : une 4ᵉ ligne aberrante passait le filtre `≥ 50 $`. Ramenés à 18,12 % et 7,57 | `ju_archimage_metrics` |
| 9 | La Vigie déclarait « Sage Macro PANNE » alors qu'il avait reparlé le 22/08 à 10h51 — et affichait elle-même une sortie postérieure au run audité | `vigie_scan()` |
| 10 | Le titre Discord de la Vigie ne s'affichait plus en gras : un espace après `**` annule le gras Markdown (résidu de la correction emoji du 21/08) | `vigie_alert()` |
| 11 | Valeurs figées visibles au chargement : KPI d'accueil (`+9.4 %`, `+6.4 %`, `1.32`, `$847.69`), les deux bandeaux « 3/4 », et surtout la **légende du graphe d'accueil** (`AETHER +11.8 % / S&P 500 +3.1 % / Bitcoin −4.6 %`) qui n'était recalculée **jamais** | `aether.html` |

L'incident « Sage Macro » a été clos dans le registre `oracle_problemes`
(1 fermeture, notification Discord envoyée). La Vigie est passée de 14 OK / 2 PANNE / 1 alerte
à **15 OK / 1 PANNE / 1 alerte** ; les deux restants sont vrais : le scénario Make est arrêté,
donc le tir de 21h15 n'a pas eu lieu et le verdict de dé-stake n'est plus évalué.

### Ce qui n'était pas un défaut, après vérification
- **Journal écrit deux fois par créneau** : c'est voulu et documenté dans
  `supabase/README-DAILY-JOURNAL.md`. `generate_daily_journal()` garantit l'écriture côté
  serveur, la tâche Claude « AETHER — Résumé » écrit sa propre version pour la notification
  push. Deux textes différents, pas un doublon technique. Rien touché.
- **Taux du Sage Macro à 63,4 % dans sa fiche contre 62,7 % dans la jauge** : ce sont deux
  fenêtres de mesure différentes (`sage_detail` vs `evaluate_sages(24, 0.5)`), pas une incohérence.

### Vérification finale, en HTTP réel
Les edge functions ont été appelées depuis Postgres via `net.http_post` — vrai transport HTTP,
pas une simulation SQL :

| Appel | Résultat |
|---|---|
| `oracle-tests/hero` | 200 · alpha −1,74 pt · drawdowns résolus sur la source broker |
| `oracle-tests/alchimiste` | 200 · `rendement_pct` 17,42 · plus de `rendement_compose_pct` dans le flux |
| `oracle-tests/archimage_detail` (GIL) | 200 · **26** positions (2 fantômes écartées) · dd 0,59 % |
| `oracle-tests/positions` | 200 · 76 lignes |
| `oracle-tests/friction` | 200 · médianes en place |
| `oracle-inbox/suivi` | 200 · 100 Ko · VIGIE, MARÉES, ALCHIMISTE, capital réel corrects |
| `oracle-inbox/journal` | 200 · 121 Ko |

Syntaxe JavaScript de `aether.html` validée par `node --check`.

### Restent ouverts — hors console, non corrigés

Ces points relèvent du scénario Make ou de la stratégie, pas de l'affichage :

- **Module 303 (SYL)** : la dernière exécution du 6183820 (22/08 10h50) est morte sur son
  échappement. Le correctif est dans le scénario 7051944 et dans
  `blueprint-6183820-CORRIGE-v2.json` — **7051944 n'a encore jamais été exécuté**.
- **Aucun run n'a produit les 5 Sages depuis le 19/08 22h18.** La clé Gemini du module 207
  a été corrigée après le dernier run : à re-vérifier au premier tir.
- `oracle_flash_intel` : 0 ligne. `propositions_validees` : 0 sur 56.
- **SYL au levier 2,00**, short TLT de −1 681 547 $ détenu depuis 220 runs.
- **JU et GIL n'ont aucun edge** (Kelly brut négatif) ; GIL est à 44,6 % de précision directionnelle.
- Le créneau 9h00 Paris tombe marché US fermé : 15 ordres écartés au dernier run.
- `oracle-inbox/suivi` répond en plus de 5 secondes (il pagine 1 269 + 1 613 lignes). Sans effet
  dans le navigateur, mais c'est le point lent de la console.
- `dashboard.html:518` code en dur l'identifiant de scénario `6183820` (autre fichier, non utilisé
  par les 8 onglets).
