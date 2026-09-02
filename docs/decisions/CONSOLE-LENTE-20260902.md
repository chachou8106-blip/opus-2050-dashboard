# La console — 02/09/2026

Deux parties : ce que j'ai cassé et remis, puis la vraie cause, trouvée après.

---

## 1. Ce que j'ai fait, et pourquoi je l'ai annulé

J'ai déployé deux changements ce soir :

- une réécriture de la vue `v_dernier_prix` (parcours d'index par sauts) ;
- `oracle-inbox` v28, qui lançait les 25 lectures du bloc `suivi` ensemble.

Chachou a chargé la console pendant que ces changements étaient en place et
pendant que mon propre trafic de test tournait. Résultat mesuré à ce
moment-là :

- `rpc/dashboard_snapshot` → **500**, `57014 canceling statement due to statement timeout` ;
- le bloc `suivi` → **36 844 caractères au lieu de 126 312**, donc à moitié vide,
  **et pourtant `ok:true`**. Une panne muette : exactement le défaut qu'on s'était
  juré d'éliminer le 31/08 avec le `.catch` vide d'`execute-trades`.

La panne muette vient de la parallélisation : dans le bloc `suivi`, chaque lecture
ratée retombe sur `arr(body)` qui rend `[]`. En séquentiel ça n'arrivait jamais ;
en lançant 25 requêtes d'un coup, plusieurs peuvent échouer et les blocs
correspondants repartent vides, sans rien signaler.

**Tout est remis dans l'état d'avant.** `v_dernier_prix` a retrouvé sa définition
`DISTINCT ON` d'origine ; `oracle-inbox` a été redéployé avec le code v27 à
l'identique (version 29 côté Supabase, même contenu que la 27).

**Et une explication que j'ai donnée était fausse :** j'ai écrit que ma vue avait
ralenti `dashboard_snapshot`. Vérification faite ensuite, `dashboard_snapshot` ne
référence **pas** `v_dernier_prix` — il lit `price_history` en direct. Ma vue ne
pouvait pas le ralentir par cette voie. Je l'ai retirée.

---

## 2. La vraie cause, et elle est antérieure à ce soir

Une fois tout remis à l'état initial, `rpc/dashboard_snapshot` appelé **seul**,
sans aucun autre trafic, avec la clé `anon` du fichier :

```
500 — {"code":"57014","message":"canceling statement due to statement timeout"}
```

### Le plafond

```sql
select rolname, rolconfig from pg_roles;
  anon           statement_timeout=3s
  authenticated  statement_timeout=8s
  service_role   (aucun)
```

La console appelle `dashboard_snapshot` **directement depuis le navigateur**, donc
en rôle `anon` : elle a **3 secondes**, pas une de plus.

### Le temps réel de la fonction

```
passage 1 (cache froid) : 3 127,6 ms
passage 2               :   101,6 ms
passage 3               :   100,3 ms
passage 4               :   100,1 ms
```

**3 127 ms à froid contre un plafond de 3 000 ms.** À chaud, 100 ms. C'est
exactement pour ça que la console marche une fois sur deux : dès que les pages
concernées sortent du cache — et elles en sortent en permanence, `price_history`
grossit toutes les 5 minutes — l'appel dépasse et le serveur coupe.

Côté page, `SNAPF()` fait `.then(r => r.ok ? r.json() : null)` : un 500 devient
`null`, `D.snap` est vide, et les panneaux qui en dépendent restent blancs. Sans
message d'erreur.

C'est aussi ce qui explique mes mesures de l'après-midi : j'avais lu 1 285 ms puis
353 ms puis 106 ms, toutes à chaud, et j'en avais conclu que la fonction allait
bien. **Une mesure à chaud ne dit rien du cas qui casse.**

### Ce qui coûte les 3 secondes

Les treize relations lues par la fonction, chronométrées une par une :

| Relation | Lignes | Temps |
|---|---|---|
| **`price_history`** | **575 898** | **423,6 ms** |
| `evaluate_sages()` | — | 45,8 ms |
| `oracle_exec_debug` | 752 | 9,6 ms |
| `revolut_portfolio_daily` | 62 | 8,4 ms |
| `oracle_performance` | 864 | 4,8 ms |
| `oracle_positions_live` | 72 | 4,2 ms |
| `oracle_college_orders` | 1 636 | 2,6 ms |
| `oracle_college_runs` | 285 | 1,8 ms |
| `alchimiste_crypte_propositions` | 68 | 0,7 ms |
| `oracle_sages_report` | 1 045 | 0,7 ms |

Une seule pèse. Et voici à quoi elle sert, dans le bloc `stats` de la fonction :

```sql
'bougies', (select count(*) from public.price_history),
```

**Un compteur d'affichage.** Un `count(*)` complet sur 575 898 lignes — 424 ms à
chaud, bien davantage à froid — pour écrire un nombre de bougies à l'écran. C'est
lui qui fait passer la fonction au-dessus des 3 secondes du rôle `anon`.

Les deux autres fonctions du même bloc sont `STABLE` et n'écrivent rien
(vérifié : `provolatile = 's'`, zéro `insert`, zéro `update`) — le chemin de
lecture de la console n'écrit pas en base, c'est propre de ce côté-là.

---

## 3. Ce que je propose — et que je n'ai pas fait

Remplacer ce `count(*)` exact par l'estimation que Postgres tient déjà à jour :

```sql
'bougies', (select reltuples::bigint from pg_class where relname = 'price_history'),
```

Coût : quelques microsecondes au lieu de 424 ms à chaud. Sur un compteur
d'affichage, l'estimation vaut le compte exact.

Je ne l'applique pas. J'ai déjà déployé deux choses ce soir sans les avoir
éprouvées à froid, et c'est ce qui a cassé sa console. Cette fois je montre
d'abord.

---

## 4. La leçon, pour moi

Tout mon diagnostic de l'après-midi reposait sur des mesures **à chaud**, prises
juste après un appel identique. Le cas qui casse est le cas **à froid**, et il ne
se voit qu'à froid. Un chiffre pris dans de bonnes conditions ne prouve rien sur
les mauvaises — c'est la règle du 20/08 (« un contrôle étroit ne prouve pas une
affirmation large ») sous une autre forme, et je l'ai reviolée.

Et j'ai mesuré pendant que je générais moi-même du trafic. Tous mes écarts de la
soirée sont pollués par mes propres rafales de test. On ne mesure pas une machine
en tapant dessus.
