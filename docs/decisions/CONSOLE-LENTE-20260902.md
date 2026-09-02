# « Ma console ne fonctionne plus » — 02/09/2026

Ce n'était pas une panne : c'était une attente trop longue pour un navigateur.

## Ce que la console demande au démarrage

`aether.html` → `boot()` lance dix appels en parallèle, dont
`INBOX({action:'suivi'})`. Tant que celui-là n'a pas répondu, la page reste sur
« Chargement des données réelles… », puis affiche
« ⚠️ oracle-inbox injoignable » si la requête échoue.

## Ce qui a été mesuré (et non supposé)

**Tous les points d'entrée répondent 200.** Testés un par un avec la clé `anon`
exacte du fichier, celle que le navigateur envoie :

| Appel | Résultat |
|---|---|
| `oracle-inbox` action `suivi` | 200, 126 287 caractères |
| `oracle-inbox` action `journal` | 200, 199 678 caractères |
| `rpc/dashboard_snapshot` | 200, 52 698 caractères |
| `v_exposition_traders` | 200, 842 caractères |
| les 14 actions de `oracle-tests` | 200, toutes avec des données réelles |

Donc ni la clé, ni les droits, ni le RLS, ni le fichier HTML (inchangé depuis le
commit `d78172b`, déjà sur `main`).

**Le temps d'exécution, lui, était hors de portée d'un navigateur.** Relevé dans
les logs edge (`function_edge_logs`, champ `execution_time_ms`) pour `oracle-inbox`
action `suivi`, le 02/09 :

```
16:41:26   47 216 ms
16:54:35   64 562 ms
16:57:12   20 936 ms
17:29:27   24 857 ms
17:30:40   18 913 ms
```

À côté, l'action `journal` du même fichier : 1 658 ms. Le problème était donc
circonscrit au bloc `suivi`.

## Les deux causes, séparées et mesurées

### 1. La base — `v_dernier_prix` relisait 575 000 lignes pour en rendre 331

```sql
SELECT DISTINCT ON (symbol) ... FROM price_history ORDER BY symbol, ts DESC
```

Le plan le confirmait : `Index Scan ... rows=575525`, **371 081 buffers touchés**
pour 331 lignes en sortie. La table grossit toutes les 5 minutes : la vue
ralentissait un peu plus chaque jour. Deux vues de la console en dépendent
(`v_alc_virtuel_positions`, `v_alc_reel_live_positions`, et donc
`v_alc_reel_live_resume`).

Réécrite en parcours d'index par sauts (*loose index scan*) : la liste des 331
symboles est construite par descentes successives dans l'index
`idx_price_history_sym_ts_desc` — **qui existait déjà**, rien n'a été ajouté —
puis un `ORDER BY ts DESC LIMIT 1` par symbole. C'est exactement le motif que
`v_live_crypto_positions` utilisait déjà et qui la maintenait à 1 ms.

Contrôle d'équivalence avant remplacement, dans les deux sens :

```
n_ancien 331 | n_nouveau 331 | dans_ancien_seulement 0 | dans_nouveau_seulement 0
```

| Vue | Avant | Après |
|---|---|---|
| `v_dernier_prix` | 5 827 ms | **19 ms** |
| `v_alc_virtuel_positions` | 8 284 ms | **18 ms** |
| `v_alc_reel_live_positions` | 933 ms | **24 ms** |
| `v_alc_reel_live_resume` | 920 ms | **15 ms** |
| `v_perf_avancee` | 6 110 ms | **166 ms** |
| **les 22 vues du bloc suivi** | **~17 600 ms** | **1 305 ms** |

### 2. La fonction — 25 lectures indépendantes, mises à la queue leu leu

`oracle-inbox` v27 enchaînait ses 25 `await` l'un après l'autre alors qu'aucune
lecture ne dépend d'une autre. v28 les lance ensemble (`Promise.all`). Aucune
requête n'a changé : même URL, mêmes colonnes, même JSON en sortie — seul
l'ordonnancement change. Vérifié après déploiement : 200, 21 clés de premier
niveau, toutes peuplées (5 traders, 6 lignes de perf, 427 rendements, 24 séries
de comparaison, 20 positions Alchimiste réel, 5 sages), et l'action `journal`
inchangée à 199 678 caractères.

## Résultat

```
avant : 18,9 / 20,9 / 24,9 / 47,2 / 64,6 s
après : 11,7 / 11,7 s
```

Le pire cas passe de 65 s à 12 s, et la dispersion disparaît.

## Ce qui reste, et que je n'ai pas fait

La base ne pèse plus que 1,3 s sur les 11,7. Le reste, ~10 s, ce sont les
**26 allers-retours HTTP** entre la fonction edge et PostgREST, qui passent par
l'adresse publique du projet. Les lancer ensemble ne les rend pas gratuits.

La suite logique serait une fonction SQL unique (sur le modèle de
`dashboard_snapshot`, qui rend 52 ko en 1,3 s en un seul appel) qui renverrait
tout le bloc `suivi` d'un coup : 26 appels deviendraient 1. Je ne l'ai pas fait —
c'est un chantier à part, et il ne se décide pas pendant qu'un run est cassé.
