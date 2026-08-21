# Audit intégral Supabase ↔ Blueprint Make — 21/08/2026

Base `smddzybxebwhfnitxuyp` · scénario Make 6183820 · blueprint lu en direct le 21/08 à 11h39.
Méthode : inventaire exhaustif des 67 tables, 51 vues, 51 fonctions, 22 tâches cron ;
extraction des 38 modules racine + 7 routes du blueprint ; croisement champ par champ.

---

## 0. État à l'instant de l'audit

| Élément | Valeur |
|---|---|
| Dernier run complet | **21/08 09:05** (5 ordres) |
| Runs planifiés/jour | 9h00, 15h45, 18h30, 21h15 (lun-ven), table `scenario_runs_planifies` |
| Prochain tir automatique | **15h45 Paris** |
| `scenario_control` | `actif=true`, `applied_state=inactive`, dernier `stop` à 09h05 |
| Scénario Make | `isActive: false` |
| Circuit breakers actifs | 3 |

---

## A. BLOQUANT — trois Sages ont un corps de requête JSON malformé

Cause directe de l'arrêt du scénario depuis 11h15. En modifiant `max_tokens`,
l'assistant Maia a supprimé le séparateur `"},{"role":"user",` entre le message système et
le message utilisateur. Les deux messages ont fusionné en un seul objet à clés dupliquées ;
en JSON la dernière clé écrase la première.

| Module | Sage | Messages réellement envoyés | Prompt système reçu par le modèle |
|---|---|---|---|
| 201 | Macro — AURORA BOREALIS | 1 (clé `content` en double) | **114 car. au lieu de 4 371** |
| 203 | Technique — STELLAR NAVIGATOR | 1 (clé `content` en double) | **197 car. au lieu de 2 947** |
| 205 | Risque — IRON SENTINEL | 1 (clés `role` ET `content` en double) | **0 — le message devient `role:user`** |
| 207 | Mémoire — DEEP MEMORY | 2 | intact (3 061 car.) |
| 209 | Flash — QUANTUM PULSE | 2 | intact (3 553 car.) |

Le module 205 n'envoie plus à Mistral qu'un message `user` de 280 caractères (le CTX brut),
sans consigne ni format de sortie, avec 4 000 tokens disponibles : le modèle part en boucle.
C'est le blocage observé sur « IRON SENTINEL ». Le run de 11h19 s'était arrêté juste après,
sur le module 206 (ParseJSON du Sage Risque), à 19 opérations.

**Le texte des prompts n'est pas perdu** — il est intégralement présent dans le champ.
Seule la ponctuation JSON manque. Réparation = un remplacement de chaîne par module.

---

## B. Le pipeline de catalyseurs du Sage Flash n'a jamais fonctionné

| Constat | Preuve |
|---|---|
| `oracle_flash_intel` | **0 ligne** |
| `oracle_brain_state.catalyst_updated_at` | **NULL pour les 6 agents** |
| Module 211 (`log_flash_intel`) | appelé à **chaque** run, sans filtre, dans le flux principal |
| `get_oracle_context().flash_intel_latest` | tableau **vide** |
| CTX (module 110), champ `FLASH_INTEL` | alimenté par ce tableau vide → toujours `[]` |
| Module 305 (GIL) | lit `flash_intel_latest` → reçoit toujours du vide |

La fonction `log_flash_intel` se termine par `EXCEPTION WHEN OTHERS THEN RETURN
jsonb_build_object('success', false, ...)`. Elle renvoie donc **HTTP 200 même en échec** :
Make ne voit jamais l'erreur et continue. La panne est invisible depuis le scénario.

`catalyst_updated_at` étant NULL partout, le bloc de routage de la fonction n'a jamais été
atteint — l'échec se produit donc avant, ou le module 211 n'atteint jamais Postgres.
Diagnostic à terminer en lisant le retour réel du module 211 lors d'un run.

**Conséquence** : le travail du Sage Flash (Perplexity, module 209) est facturé à chaque run
et n'atteint aucun agent.

---

## C. Objets Supabase morts — jamais écrits, jamais lus

### C1. Tables à 0 ligne, référencées par rien

`market_data_cache`, `oracle_market_cache`, `market_signals`, `oracle_logs`,
`fonds_versements`, `app_users`, `portfolio_virtual`, `positions_recommended`,
`marees_positions`.

Remarque : `market_data_cache` **et** `oracle_market_cache` couvrent le même besoin ;
les deux sont vides. `marees_positions` (0 ligne) double `marees_propositions` (116 lignes).

### C2. Branche d'écriture morte : `batch_write_oracle_run`

Seule fonction à utiliser `oracle_runs` (**0 ligne**) et `alpaca_orders` (**0 ligne**).
Aucun module du blueprint ne l'appelle. Le scénario écrit en réalité via
`batch_write_college_run_v2` (module 982) → `oracle_college_runs` (275 lignes) et
`oracle_college_orders` (1 572 lignes).

### C3. Quatre fonctions pour écrire un run, une seule utilisée

| Fonction | Appelée par |
|---|---|
| `batch_write_college_run_v2` | **module 982 — la seule vivante** |
| `batch_write_college_run` | personne |
| `batch_write_oracle_run` | personne |
| `upsert_college_run` | personne |

### C4. `log_visionary_signals` / `oracle_visionary_signals`

Table à 0 ligne. Fonction appelée par aucun module. La clé `visionary_signals` est
malgré tout servie dans `get_oracle_context()` et lue par personne.

### C5. `alc_process_oui`

Fonction de traitement de la validation Alchimiste : appelée par **aucun module** du blueprint.
(Constat déjà relevé le 20/08, toujours vrai.)

---

## D. Doublons et étiquettes trompeuses

### D1. Module 20022 — l'Alchimiste reçoit le staking sous le nom « délais »

URL du module 20022 : `v_alc_staking_txt?select=delais_texte:staking_texte`

C'est un alias PostgREST : la colonne `staking_texte` est renvoyée sous le nom `delais_texte`.
Le module 10012 (Alchimiste réel) lit `20022.delais_texte` et reçoit donc :

```
SOL montant=106.13USD apy=6.16% deblocage=3jours ; ETH montant=33.48USD apy=2.45% deblocage=5jours ; …
```

alors que la vraie vue des délais, `v_alc_staking_delais_txt`, contient :

```
ATOM:21j ; ETH:5j ; KSM:7j ; OSMO:14j ; SOL:3j ; TON:2j ; TRX:14j
```

**Pas de perte de données** : `staking_texte` contient déjà les délais (`deblocage=Xjours`).
Mais le champ porte un nom qui ne décrit pas son contenu, et :
- `v_alc_staking_delais_txt` n'est jamais appelée par le scénario (seulement par `vigie_scan`) ;
- le module **20023** envoie l'APY une **deuxième fois** — l'APY est déjà dans `staking_texte`.

Trois vues, une seule nécessaire pour le module 10012.

### D2. Les 10 derniers runs sont chargés deux fois par run

- `get_oracle_context()` sert `last_10_runs` (**4 364 caractères**) — **lu par aucun module**.
- Le module **901** refait un appel REST sur `oracle_college_runs?limit=10` pour la même chose.

Idem pour `positions_live` (**10 432 caractères** servis, lus par aucun module) alors que les
positions réelles sont déjà lues par les modules 9971/9973/9975 directement chez Alpaca.

### D3. Clés servies par `get_oracle_context()` et lues par personne

`datasource_health`, `fetched_at`, `last_10_runs`, `positions_live`, `recent_exec_errors`,
`visionary_signals` — soit environ **15 Ko transmis à chaque run pour rien**.

Point positif : **aucune clé lue par Make n'est absente du payload**. Le contrat 105 → Make
est complet dans ce sens-là. Les 52 références `105.data.*` du blueprint résolvent toutes.

### D4. Sept tables de sauvegarde en base

`_ju_brain_backup`, `bak_20260813_alchimiste_crypte_propositions`,
`bak_20260813_alchimiste_virtual_trades`, `bak_20260813_brain_alc_marees`,
`bak_20260813_marees_propositions`, `bak_20260813_marees_virtual_trades`,
`bak_20260820_lecon_epinglee`, `bak_20260820_marees_propositions`.

Sans danger, mais elles encombrent la liste des tables et brouillent la lecture.

---

## E. Valeurs figées en dur dans les prompts

Les agents reçoivent des chiffres écrits à la main qui ne correspondent plus au mesuré.

| Module | Texte figé | Valeur réelle mesurée aujourd'hui |
|---|---|---|
| 215 | `FIABILITE_SAGES=Macro/Technique/Memoire fiables (68-84% de reussite mesuree), Flash/Risque peu fiables (~50%…)` | Macro **62.7 %**, Technique **62.4 %**, Mémoire **82.4 %**, Risque **54.0 %**, Flash **49.2 %** |
| 205 | `score actuel 47 pour cent - a redresser` | Sage Risque à **54.0 %** |

La fonction `sages_coaching()` existe déjà, est déjà servie par `get_oracle_context()` sous la
clé `sages_coaching`, et est **déjà lue par les 5 Sages** (modules 201, 203, 205, 207, 209 la
reçoivent dans leur message utilisateur sous le champ `COACHING`). Seul le module 215, qui
alimente les trois Archimages, reste sur le texte figé.

Les autres « pour cent » du scénario (1.5 % module 203, 55 %/45 % module 207, 53 % module 209)
sont des **seuils de règle**, pas des mesures : ils doivent rester en dur.

---

## F. Mémoire des agents — état réel

| Agent | runs | wins | losses | win rate | drawdown | pertes consécutives | série |
|---|---|---|---|---|---|---|---|
| JU | 278 | 135 | 142 | 49.0 % | 0.36 % | 3 | loss |
| SYL | 278 | 149 | 128 | **54.0 %** | 3.80 % | 0 | win |
| GIL | 278 | 138 | 139 | 50.0 % | **6.26 %** | **8** | loss |
| CRYPTE_JU | 56 | 29 | 27 | 51.8 % | 0 | 0 | — |
| MAREES | 39 | 12 | 27 | **30.8 %** | 0 | 0 | — |
| cerveau | 0 | 0 | 0 | — | 0 | 0 | none |

- `brain_lessons` : **338 lignes**, append-only, dernière écriture 21/08 09:05. Historique intact.
- `oracle_brain_state.learnings` / `.mistakes_history` : fenêtre glissante de **30** par agent.
  Ce n'est pas une perte : c'est le tampon. L'historique complet vit dans `brain_lessons`, et
  `get_oracle_context()` sert désormais les leçons depuis `brain_lessons` — 75 941 caractères
  de `brain_states`, soit toute la mémoire, et non plus 30 lignes.
- L'agent `cerveau` porte 50 leçons pour 0 run évalué : il n'est jamais noté.

---

## G. Secret en clair dans le blueprint

Un webhook Discord complet est écrit en dur dans les modules **981** et **20021** :
`https://discord.com/api/webhooks/1512408749959286985/…`

CLAUDE.md impose « webhooks → Vault ». À déplacer.

---

## H. Filtres étiquetés `[OFF]` mais toujours vrais

Constat antérieur au 13/08, confirmé : les filtres des modules **10009** (Revolut X) et
**20014** (Marées) portent le libellé `[OFF] … mettre ON pour activer` mais leur condition est
toujours vraie — les deux routes s'exécutent à chaque run. Le libellé ment sur l'état réel.

---

## Ordre de réparation proposé

1. **A** — les trois Sages (bloquant, avant le tir de 15h45).
2. **E** — module 215 sur `sages_coaching` (chiffres figés faux lus par les 3 Archimages).
3. **B** — diagnostic du module 211 sur un run réel, puis correction.
4. **D1** — nommer correctement le champ staking du module 10012, supprimer le doublon 20023.
5. **D2/D3** — alléger `get_oracle_context()` des 6 clés jamais lues (~15 Ko/run).
6. **C** — suppression des objets morts, après confirmation explicite de Chachou.
7. **G** — webhook Discord vers Vault.
8. **H** — libellés des filtres.

Aucune modification n'a été appliquée pendant cet audit. Lecture seule.

---

# Complément du 21/08 après-midi — trois découvertes

## I. Le `run_id` n'est partagé par aucun module — PROUVÉ

Le module **101** produit la valeur `COLLEGE-{{formatDate(now; "YYYYMMDD-HHmm")}}`.

Sur **3 863 lignes** réparties dans cinq tables, **zéro** ne porte le préfixe `COLLEGE-` :

| Table | Lignes | Avec le préfixe `COLLEGE-` |
|---|---|---|
| `oracle_sages_report` | 956 | **0** |
| `oracle_college_runs` | 275 | **0** |
| `oracle_college_orders` | 1 572 | **0** |
| `brain_lessons` | 338 | **0** |
| `oracle_exec_debug` | 722 | 1 (test manuel) |

Donc `{{101.RUN_ID}}` n'a **jamais** résolu, dans aucun module, depuis le 1er juillet.
Chaque module retombe sur son propre `ifempty(...; formatDate(now; "YYYYMMDD-HHmm"))` et
horodate à la minute de SA propre exécution. D'où, pour un même run : les Sages enregistrent
`20260821-0904` et le Collège `20260821-0905`.

**Cause** : un module `util:SetVariable` s'adresse par `{{101.value}}`, pas par
`{{101.<nom_de_variable>}}`. Le module **20013** est le seul du scénario à utiliser la bonne
forme (`{{ifempty(101.value; ...)}}`).

**Modules à corriger** : 211, 401, 960, 981, 982, 10032. Les modules 9995, 10000 et 10001
passent par `960.data.run_id`, chaîne différente à vérifier ensuite.

**Correction propre** : retirer d'abord le préfixe `COLLEGE-` du module 101 pour rester
compatible avec les 3 863 lignes existantes, puis pointer tous les consommateurs sur
`{{101.value}}`.

**Portée** : c'est la même famille de référence que `{{CTX}}` et `{{SAGES}}` (modules 207, 301,
303, 305). La preuve ci-dessus vaut pour `{{101.RUN_ID}}` uniquement ; pour les deux autres, la
question reste ouverte — `raw_payload` ne stocke pas le raisonnement des Archimages, donc rien
ne permet de trancher côté base. À vérifier dans l'Output du module 301 dans Make.

## J. Deux modules LLM sans format de sortie imposé

Relevé exhaustif des dix modules LLM :

| Module | Agent | Modèle | `response_format` |
|---|---|---|---|
| 201, 203, 207 | Sages Macro / Technique / Mémoire | gpt-oss-120b | `json_object` |
| 205 | Sage Risque | mistral-large | `json_object` |
| 209 | Sage Flash | sonar-pro | `json_schema` |
| 301 | Archimage JU | claude-sonnet-4-5 | API Anthropic |
| **303** | **Archimage SYL** | **sonar-pro** | **AUCUN** |
| 305 | Archimage GIL | mistral-large | `json_object` |
| 401 | Cerveau | mistral-large | `json_object` |
| **10012** | **Alchimiste réel** | **sonar-pro** | **AUCUN** |

SYL et l'Alchimiste sont les deux seuls modules où rien n'oblige le modèle à produire du JSON.
Le module 304 compense en retirant les balises de code, les retours à la ligne et les
tabulations — un pansement, pas une contrainte. Le 21/08 à 13h29, le run est mort exactement là.

Le module 209 tourne sur le **même modèle** `sonar-pro` avec un `json_schema` imposé et n'a
jamais échoué : la correction consiste à lui copier ce mécanisme.

Ni 303 ni 10012 n'ont été modifiés le 21/08 — ils sont identiques au caractère près à leur état
de 11h39. Ce défaut est antérieur.

## K. Les erreurs HTTP des Sages passent en silence

Sur les modules Groq, l'option « Return error if HTTP request fails » (`stopOnHttpError`) est
**décochée**. Groq peut renvoyer une erreur, la réponse n'a plus de `choices[]`, le contenu est
vide, `record_sages` n'insère rien — et le scénario continue comme si de rien n'était.

C'était déjà la cause du silence du 15/08 (modèle `llama-3.3-70b-versatile` décommissionné,
corrigé le 17/08 en basculant sur `openai/gpt-oss-120b`). Le mécanisme n'a jamais été traité :
seul le symptôme l'a été.

Combiné au fait que `oracle_datasource_health` ne surveille **aucun** des cinq fournisseurs de
LLM, un Sage peut rester muet des jours sans qu'aucune alerte ne se déclenche. C'est exactement
ce qui s'est produit pour le Sage Macro, absent de tous les runs du 20/08 09h04 au 21/08 09h04.

## Historique mesuré des Sages ayant répondu

| Période | Sages qui écrivent |
|---|---|
| 15/08 12h36 → 17/08 19h33 | Flash seul, puis Flash + Risque — modèle Groq décommissionné |
| 17/08 19h59 → 19/08 22h18 | **5 sur 5** — après bascule sur `openai/gpt-oss-120b` |
| 19/08 23h22 | 4 — Mémoire tombe |
| 20/08 09h04 → 21/08 09h04 | 4 — **Macro absent sur cinq runs consécutifs** |
| 21/08 13h29 | 2 — les trois modules Groq éteints ensemble |

Le fait que Technique et Mémoire aient répondu normalement pendant que Macro restait muet, sur
cinq runs, avec la **même** chaîne de modèle, la **même** clé et la **même** URL, exclut un
décommissionnement comme cause de la panne du Sage Macro. Pour la panne simultanée des trois du
21/08, l'hypothèse reste ouverte et se tranche en lisant l'Output du module 201 dans Make.
