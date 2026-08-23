# Contrôle des tables de contexte — 23/08/2026

Demande : « Contrôle toutes les tables de contexte ».

Périmètre : toute table portant du texte de contexte, de configuration ou de mémoire, plus
le chemin par lequel ce texte atteint les prompts des agents (`get_oracle_context()` → module 105).

---

## 1. LE POINT LE PLUS GRAVE — un texte de ma main est toujours injecté à SYL

`CLAUDE.md` dit que la « leçon épinglée » du 15/08 a été **retirée le 20/08**
(sauvegarde `bak_20260820_lecon_epinglee`). C'est vrai pour `oracle_brain_state.learnings`.

**Ce n'est pas vrai pour `brain_lessons`. La ligne y est toujours :**

```
archimage : SYL
run_id    : lecon-manuelle-20260815
kind      : learning
at        : 2026-08-15 12:20:14+00
eval      : "lecon manuelle Chachou"
bias      : "LECON: ne pas shorter or (GLD) ni argent (SLV) en tendance haussiere;
             couper tout short perdant au-dela de -5%; ne pas moyenner a la baisse un
             short; un gain passe sur une rotation ne justifie pas un short a
             contre-tendance."
```

Et `get_oracle_context()` construit le bloc `learnings` **depuis `brain_lessons`**, pas depuis
`oracle_brain_state.learnings` :

```sql
'learnings', COALESCE((SELECT jsonb_agg(jsonb_build_object('run', bl.run_id, 'bias', ...))
                       FROM public.brain_lessons bl
                       WHERE bl.archimage = oracle_brain_state.archimage
                         AND bl.bias IS NOT NULL AND bl.bias <> ''), learnings)
```

**Donc ce texte que j'ai composé part encore dans le prompt de SYL à chaque run.** Le retrait du
20/08 a nettoyé la mauvaise table. La règle absolue n°2 de CLAUDE.md est toujours enfreinte,
huit jours après.

Le champ `eval` dit « lecon manuelle Chachou » : il attribue à Chachou un texte de ma
composition. C'est la seule des 338 lignes de `brain_lessons` dont le `run_id` ne suit pas le
format `AAAAMMJJ-HHMM` d'un vrai run.

**Non supprimée** — écrire dans un canal qui atteint un prompt demande l'accord de Chachou,
dans les deux sens. La requête, quand il le dira :

```sql
-- sauvegarde d'abord
create table if not exists bak_20260823_lecon_manuelle as
  select * from public.brain_lessons where run_id = 'lecon-manuelle-20260815';
delete from public.brain_lessons where run_id = 'lecon-manuelle-20260815';
```

---

## 2. Ce qui part réellement dans les prompts — 92 ko par run

`get_oracle_context()`, 12 blocs :

| Bloc | Poids | Part |
|---|---|---|
| `brain_states` | 74 ko | **82,3 %** |
| `positions_live` | 10 ko | 11,3 % |
| `last_10_runs` | 4,4 ko | 4,7 % |
| `datasource_health` | 723 o | 0,8 % |
| `sages_coaching` | 191 o | 0,2 % |
| `macro_extra` | 153 o | 0,2 % |
| `performance_summary` | 148 o | 0,2 % |
| `active_circuit_breakers` | **2 o** | 0 % |
| `recent_exec_errors` | **2 o** | 0 % |
| `flash_intel_latest` | **2 o** | 0 % |
| `visionary_signals` | **2 o** | 0 % |

Trois constats :

**a) Les quatre blocs de sécurité sont vides.** `active_circuit_breakers` renvoie `[]` alors que
trois coupe-circuits sont armés (fenêtre de 24 h, cf. audit du matin). `oracle_flash_intel` :
0 ligne depuis toujours. La mémoire pèse 74 ko, l'alerte pèse 2 octets.

**b) La mémoire injectée croît sans plafond.** La requête ci-dessus n'a ni `LIMIT` ni `ORDER BY
DESC` : elle prend **toutes** les lignes de `brain_lessons` avec un bias. Aujourd'hui 63 leçons
par Archimage (contre 30 stockées dans `oracle_brain_state.learnings`) ; `brain_lessons` grossit
d'environ 16 lignes par jour et par agent. Rien ne l'arrête.

**c) Chaque Archimage reçoit la mémoire des cinq autres**, y compris `CRYPTE_JU` (crypto Revolut)
et `MAREES` (forex) qui ne le concernent pas — 27 champs × 6 cerveaux.

---

## 3. Le drawdown transmis aux agents est le faux

Corrigé ce matin **côté affichage seulement**. Côté agents :

```
get_oracle_context().brain_states.GIL.alpaca_drawdown = 0.0059   (0,59 %)
oracle_brain_state.GIL.current_drawdown               = 0.0626   (6,26 %)  <- le vrai
```

`get_oracle_context()` transmet `alpaca_drawdown_from_peak`, la colonne que
`sync_alpaca_positions` calcule avec un `MAX()` sur une table qui n'a qu'une ligne par agent
(cf. audit du matin, bloc A).

**GIL décide donc en croyant être à 0,6 % de son plus haut alors qu'il est à −6,3 %**, et le
coupe-circuit « drawdown_5pct » armé sur lui ne lui parvient pas non plus (bloc vide, point 2a).

Non corrigé : cela change ce que reçoivent les prompts.

---

## 4. `oracle_contexte` — 28 fiches, 6 fausses ou périmées

Cette table n'atteint aucun prompt : elle n'est lue que par `oracle-inbox` pour l'onglet Journal
(vérifié — `alc-auto` ne la cite qu'en commentaire, Make ne la lit pas). C'est de la
documentation. Six fiches ne décrivent plus le terrain :

| Section / clé | Ce qu'elle dit | Le terrain |
|---|---|---|
| `EXECUTION / config` | `allowed_pairs` = « SOL,TON,ATOM,TRX = coins stakés » | **`*`** — aucune whitelist |
| `EXECUTION / verrous` | « État actuel : kill_switch=**ON** » | `ju_crypte_config.kill_switch` = **OFF** |
| `CONSOLE / fichier` | « Console mobile = console_opus.html » | ce fichier est dans `legacy/` ; la console est `aether.html` |
| `CONSOLE / oracle-inbox` | « suivi renvoie … périodes (**v_rapport_periodes**) » | il lit `v_rendements_periodes` ; `v_rapport_periodes` n'est jamais appelée |
| `VUES / v_equity_points` | « JU/SYL/GIL=**oracle_performance**, **ALCHIMISTE**=revolut_portfolio_daily » | JU/SYL/GIL viennent de `v_equity_journalier` ; `ALCHIMISTE` n'existe plus (ALC_REEL / ALC_VIRT) |
| `TRADERS / SYL` | « Meilleure perf cumulée actuellement » | classement figé dans du texte — vrai aujourd'hui, faux demain, personne ne le verra |

Deux remarques sur `allowed_pairs = '*'` : ce n'est **pas** un trou de sécurité oublié. Le
commentaire de `alc-auto` v6 l'explique — la whitelist statique pointait des coins **stakés donc
invendables**, elle a été remplacée volontairement par une tradabilité calculée en direct
(paires réellement cotées + soldes liquides hors stake). C'est la **fiche** qui est périmée, pas
la configuration. En revanche l'écart sur le kill-switch décrit un système **plus permissif**
qu'il ne l'est.

Deux fiches sont également exactes et méritent d'être notées : `FAITS / staking_delais`
(SOL 3 j, TON/GRAM 2 j, ETH 5 j, KSM 7 j, OSMO 14 j, TRX 14 j, ATOM 21 j) correspond ligne pour
ligne à `alc_staking_delais` ; `EXECUTION / cron_indices` correspond au job pg_cron 23.

Trois fiches enfin ne sont pas fausses mais datées : `TRADERS / ALCHIMISTE` (« Passe RÉEL fin du
mois »), `TRADERS / GIL` (« Univers CRYPTO_TACTICAL_DERIVATIVES » — c'est bien
`assigned_universe` en base, mais GIL détient 1,4 M$ d'actions et d'ETF pour ~56 $ de crypto).

**Aucune fiche ne documente `marees_config` ni `fonds_config`**, alors que `ju_crypte_config` l'est.

---

## 5. Les autres tables de configuration

| Table | Lignes | État |
|---|---|---|
| `ju_crypte_config` | 7 | cohérente ; contient `arm_pin = 2050` **en clair** (pas dans le Vault) |
| `marees_config` | 4 | cohérente — kill_switch OFF, 10 paires, max 5 %/position, 50 % brut |
| `fonds_config` | 6 | cohérente — inactif, mode calcul seulement, 50 % des gains |
| `alc_staking_delais` | 8 | exacte |
| `oracle_runs` | 1 | sorties de run, pas du contexte injecté |
| `_ju_brain_backup`, `bak_20260813_brain_alc_marees` | — | sauvegardes, non lues |

---

## 6. Deux chemins d'écriture divergents vers `current_bias`

- `update-brain/index.ts` : `current_bias = (s.bias||'neutral').substring(0, 260)` — tronque
- `batch_write_college_run_v2` (la RPC appelée par Make) :
  `current_bias = COALESCE(v_brain->>'current_bias', current_bias)` — **ne tronque pas**,
  et `learnings = learnings || new_learning` — **empile**

Effet visible : `JU.current_bias` fait **1 132 caractères** alors que la limite d'`update-brain`
est 260. Ce texte est écrit par l'Archimage JU lui-même (auto-analyse chiffrée), pas de ma main —
mais il entre par le chemin qui n'applique aucune limite.

---

## 7. Quatre consignes de comportement vivent dans le code, hors du canal Maia

`CLAUDE.md` : « Une consigne de comportement se met dans le prompt système, via Maia. Point. »
Il en existe quatre dans les edge functions, absentes de la liste des textes qui atteignent un
prompt :

| Fichier | Contenu |
|---|---|
| `collect-market-data/index.ts:201` | `directive` : « Pioche DANS cet univers. Chaque archimage doit varier ses choix… » — injectée aux Archimages |
| `marees-context/index.ts:37` | `directive` : prompt système complet de l'Archimage des Marées |
| `fx-context/index.ts:34` | `directive` forex (carry, biais dollar) |
| `collect-market-data/index.ts:81,86,91` | 3 prompts système Perplexity (recherche web) |

Ce ne sont pas des textes de ma composition récente, mais la liste de `CLAUDE.md` est incomplète :
elle cite `oracle_brain_state`, `active_circuit_breakers`, `crypte_ju_evaluate_and_learn` et
`marees_evaluate_and_learn`. Il faut y ajouter **`brain_lessons`** (le vrai canal des leçons) et
ces quatre directives.

---

## Ce qui demande une décision

1. **Supprimer `lecon-manuelle-20260815` de `brain_lessons`** — requête au point 1.
2. **Plafonner la mémoire injectée** (`ORDER BY bl.at DESC LIMIT 30`) — sinon le contexte
   grossit à chaque run sans fin.
3. **Transmettre le bon drawdown aux agents** — dépend du correctif de `sync_alpaca_positions`
   déjà proposé ce matin.
4. **Élargir la fenêtre des coupe-circuits** au-delà de 24 h.
5. Corriger les 6 fiches périmées d'`oracle_contexte` — sans risque, mais j'attends l'accord
   par principe : c'est une table de contexte.
6. Compléter la liste de `CLAUDE.md` avec `brain_lessons` et les quatre directives.
