# Chantiers 3 et 4 — le Sage Flash et la visibilité des pannes — 26/08/2026

Scénario **7051944** uniquement. Le 6183820 ne reçoit rien tant que la copie n'a pas fait un
run complet à 76 opérations.

---

## Chantier 3 — le Sage Flash

### Ce que j'ai trouvé en vérifiant les deux bouts de la chaîne

`oracle_flash_intel` est vide depuis toujours, et ce n'est pas un problème de fonction : c'est
ma livraison qui n'a jamais été raccordée.

| Ce que le module 211 envoie | Ce que le module 209 produit |
|---|---|
| `210.web_intelligence` | n'existe pas → `summary` vaut toujours `ND` |
| `210.trade_1.ticker` | n'existe pas → `top_ticker` vaut toujours `MARKET` |
| `210.trade_1.side` | n'existe pas → `top_direction` vaut toujours `neutral` |
| `210.catalysts` | n'existe pas → `catalysts` part toujours à `[]` |

Le schéma JSON du 209 déclare huit propriétés, aucune des quatre attendues. Le module 211 a
donc toujours envoyé un enregistrement vide, et `log_flash_intel` a toujours répondu
`catalysts_logged: 0` sans que personne le regarde.

Deuxième désaccord, plus discret : `log_flash_intel(jsonb)` lit dans chaque catalyseur les clés
`catalyst_type`, `direction`, `strength`, `headline`, `horizon`, `confidence`. La version du
prompt que j'avais préparée le matin même n'en nommait que trois (`ticker`, `type`, `headline`)
— `type` au lieu de `catalyst_type`. Elle aurait rempli la table avec `macro / neutral / 5 /
1w / 70` sur toutes les lignes. Corrigé avant envoi.

### Pourquoi un format délimité et pas du JSON

Le corps du module 211 est du JSON brut dans lequel Make substitue les `{{...}}` **avant** que
le JSON ne soit analysé. Un tableau de catalyseurs sérialisé en JSON y injecterait des
guillemets et casserait le corps du module — donc le module, donc le scénario.

Format retenu, sans guillemet possible :

```
ticker~catalyst_type~direction~strength~headline~horizon~confidence
blocs séparés par ;;
```

`log_flash_intel` accepte désormais **trois** formes — tableau JSON, chaîne JSON, chaîne
délimitée. Les deux anciennes continuent de fonctionner à l'identique ; rien ne régresse.

### Vérifié en base le 26/08

| Cas testé | Résultat |
|---|---|
| chaîne délimitée, 4 catalyseurs | `catalysts_logged: 4`, routage `SYL 2 / JU 3 / GIL 3 / CRYPTE_JU 3 / MAREES 2` |
| chaîne vide | `catalysts_logged: 0`, pas d'erreur |
| tableau JSON (ancien format) | `catalysts_logged: 1` |
| chaîne JSON (ancien format) | `catalysts_logged: 1` |

Les lignes de test ont été supprimées et `oracle_brain_state.latest_web_catalysts` restauré à
l'identique (sauvegarde `bak_20260826_flash_test`, créée puis supprimée).

### Ce qui reste à faire dans Make

`docs/maia/F-209-flash-schema.txt` puis `docs/maia/G-211-flash-logger.txt`.
Contrôles : module 209 à **6203** caractères (4873 avant), module 211 à **412** (369 avant).

---

## Chantier 4 — la visibilité des pannes

### La panne était déjà lisible en base

Nombre de runs où chaque sage a écrit, par jour :

| Jour | runs | Macro | Technique | Risque | Flash | Mémoire |
|---|---|---|---|---|---|---|
| 19/08 | 10 | 10 | 10 | 10 | 10 | 9 |
| 20/08 | 4 | **0** | 4 | 4 | 4 | 4 |
| 21/08 | 8 | 6 | **1** | 8 | 8 | **2** |
| 22/08 | 1 | 1 | 1 | 1 | 1 | **0** |
| 25/08 | 2 | 2 | 2 | 2 | 2 | **0** |

Le Sage Mémoire muet du 21 au 26, Aurora muet toute la journée du 20 : c'était écrit dans
`oracle_sages_report` depuis le premier jour. Le défaut n'est pas que Make avale l'erreur —
c'est que **personne ne pose la question**.

### `v_sages_pannes`

Vérifié avant de créer, comme le veut la règle : `v_data_health` couvre la fraîcheur des
données de marché, `oracle_datasource_health` les sources externes, `evaluate_sages` et
`sages_coaching` mesurent la **justesse** des verdicts. Aucun objet ne dit « ce sage n'a pas
répondu ». D'où cette vue, et elle seule.

Piège rencontré : `oracle_sages_report.run_id` et `oracle_college_runs.run_id` ne coïncident
**jamais**. Le scénario met environ deux minutes ; les sages sont horodatés au début
(`20260826-1615`) et la ligne du collège à la fin (`20260826-1617`). Ma première version
jointait sur `run_id` et déclarait les cinq sages en panne. Le rattachement se fait par fenêtre
de ± 5 minutes.

État au 26/08 après le run de 16:17 :

| Sage | runs 14j | runs muets | muets consécutifs | statut |
|---|---|---|---|---|
| Flash | 52 | 0 | 0 | OK |
| Risque | 52 | 8 | 0 | OK |
| Technique | 52 | 9 | 0 | OK |
| Mémoire | 52 | 11 | 0 | OK |
| Macro | 52 | 14 | 0 | OK |

Seuil `PANNE` : 3 runs consécutifs sans réponse.

### Ce que la vue ne fait pas encore

Elle n'est branchée sur rien que tu lises. Deux options, à ton choix :
- une ligne dans le §7 du message trois fois par jour (`generate_daily_journal`) ;
- un encart dans la console AETHER, à côté de la santé des données.

### Et la route d'erreur dans Make

`docs/maia/H-201-209-visibilite-des-pannes.txt` est prêt, mais c'est la modification la plus
risquée de la série : **aucun module du scénario n'a de route d'erreur aujourd'hui**. Activer
« Evaluate all states as errors » sans ajouter la route `Resume` ferait s'arrêter le scénario
entier au premier 429 de Groq — aujourd'hui il continue en boitant, demain il mourrait.

Mon conseil : faire F et G d'abord, lancer un run, vérifier que `oracle_flash_intel` se
remplit. H seulement après, et seulement si tu veux la trace côté Make — la vue Supabase donne
déjà l'alerte sans toucher au scénario.
