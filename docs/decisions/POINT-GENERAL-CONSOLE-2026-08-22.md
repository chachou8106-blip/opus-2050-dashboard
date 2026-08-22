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

## Corrections proposées (aucune appliquée)

Par ordre de rapport / risque :

1. Convertir en `Europe/Paris` les 8 `to_char()` de `dashboard_snapshot()`. Purement affichage.
2. Filtrer `abs(market_value) >= 50` dans le bloc `positions_vivantes` de
   `dashboard_snapshot()`, comme le fait déjà `ju_archimage_metrics`. Supprime les +324 985 $ fantômes.
3. Faire lire à `oracle-tests/hero` `coalesce(alpaca_drawdown_from_peak, current_drawdown)`
   au lieu de `current_drawdown`. Rétablit la porte 1 et fait passer le verdict à 3/4.
4. Brancher `rReel()` (ligne 1349 de `aether.html`) sur `D.suivi.alc_reel_live.resume`
   au lieu de `D.alch`, pour que le bloc « capital réel » affiche le capital réel.
5. Alimenter la ligne MAREES de `v_perf_resume` depuis `marees_virtual_trades`.
6. Choisir **un seul** rendement Alchimiste et l'afficher partout — je recommande
   `cumul_pct` (17,4 %), le seul défendable.
7. Remplacer la moyenne par la médiane dans `v_couts_friction.slippage_achats_moyen_pct`.

Les points 1 à 3 et 5 à 7 sont des objets Supabase en lecture seule : aucun n'entre
dans un prompt d'agent, aucun ne touche l'exécution d'ordres.
