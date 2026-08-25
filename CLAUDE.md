# Règles de travail — AETHER / OPUS 2050

## RÈGLE ABSOLUE — Vérifier avant d'affirmer ou de créer (demandée par Chachou, 17/08/2026)

**Avant de dire « ça n'existe pas / il n'y a pas / il faut ajouter », JE VÉRIFIE d'abord.**
Ne jamais inventer, ne jamais supposer l'absence d'un objet.

Concrètement, avant de proposer une nouvelle table / vue / fonction / module Make :
1. **Chercher l'existant** : `information_schema.tables` / `.views` / `.columns`, `pg_proc`,
   et le blueprint Make (`scenarios_get` + grep) — par mot-clé (staking, apy, delai, verdict, destake…).
2. **Réutiliser** ce qui existe (ex. `v_staking_point` a déjà apy_pct + unbonding_jours + coût ;
   `alc_destake_reco` journalise déjà le dé-stake via `alc_record_propositions`).
3. **N'ajouter un objet QUE si** rien d'existant ne convient, et le dire explicitement
   (« j'ai vérifié X, Y, Z, rien ne couvre ce besoin, donc j'ajoute … »).
4. Ne pas faire faire de manipulations Make à Chachou (ajout de module, etc.) sans avoir
   confirmé qu'aucun module/objet existant ne fait déjà le travail.

Cette règle prime sur toute envie d'aller vite.

## RÈGLE ABSOLUE — Ne JAMAIS écrire d'instruction à un agent depuis Supabase (20/08/2026)

**Les leçons et les consignes d'un agent viennent de l'agent, jamais de moi.**

Ce que j'ai fait et qui ne doit plus jamais se reproduire : le 15/08 (commit `b88f8d5`) j'ai créé
un mécanisme de « leçon épinglée » dans `update-brain` v16, puis j'ai inséré à la main dans
`oracle_brain_state.learnings` un texte de ma composition pour SYL
(`run_id = 'lecon-manuelle-20260815'`). Le module Make 303 lit `learnings[1].bias` : mon texte a
donc occupé **l'unique canal de mémoire de SYL pendant cinq jours**, et SYL n'a plus relu une
seule de ses propres leçons.

**Le retrait du 20/08 a nettoyé la mauvaise table.** J'avais supprimé la ligne de
`oracle_brain_state.learnings` (sauvegarde `bak_20260820_lecon_epinglee`) en croyant l'affaire
close, et je l'ai écrit ici. Or `get_oracle_context()` ne construit PAS le bloc `learnings` à
partir de cette colonne : il le construit à partir de **`brain_lessons`**, où la ligne est restée.
Mon texte a donc continué de partir dans le prompt de SYL **huit jours de plus**, jusqu'au
23/08 (sauvegarde `bak_20260823_lecon_manuelle`). Leçon : vérifier le CHEMIN de lecture, pas
seulement la table qui porte le nom attendu.

Interdictions, sans exception :
1. **Ne jamais écrire, modifier ou épingler** une ligne de `oracle_brain_state.learnings`,
   `current_bias`, `mistakes_history` ou toute autre colonne relue par un prompt.
2. **Ne jamais créer de canal** permettant d'injecter un texte de ma main dans un prompt.
3. Une consigne de comportement se met **dans le prompt système, via Maia**. Point.
4. Si je pense qu'un agent a besoin d'une règle, je le **propose à Chachou** avec le prompt Maia
   correspondant. C'est lui qui décide. Je n'ai pas le droit de court-circuiter.

**Liste des textes qui atteignent un prompt** — à vérifier avant toute modification. Elle était
incomplète, c'est ce qui m'a fait nettoyer la mauvaise table le 20/08 :

Dans Supabase, via `get_oracle_context()` → module 105 :
- **`brain_lessons.bias` et `.eval`** — la VRAIE source des blocs `learnings` et
  `mistakes_history`. C'est ici qu'on lit, pas dans `oracle_brain_state`.
- `oracle_brain_state.current_bias` (les 3 Archimages via `MEMORY_CORRECTION`) ; `.learnings` et
  `.mistakes_history` ne servent que de repli quand `brain_lessons` est vide.
- `oracle_circuit_breakers` → bloc `active_circuit_breakers` (via `CIRCUIT_BREAKERS`).
- `crypte_ju_evaluate_and_learn` (Alchimiste), `marees_evaluate_and_learn` (Marées) : ces
  fonctions ÉCRIVENT le `current_bias` de CRYPTE_JU et de MAREES.

Hors Supabase, dans le code des edge functions — même statut, même interdiction :
- `collect-market-data/index.ts` : le champ `directive` injecté aux Archimages, et 3 prompts
  système Perplexity.
- `marees-context/index.ts` : le champ `directive`, prompt système complet de l'Archimage des Marées.
- `fx-context/index.ts` : le champ `directive` forex.

**Deux chemins écrivent `current_bias`, avec des règles opposées** : `update-brain` tronque à
260 caractères et garde 30 leçons ; `batch_write_college_run_v2` (la RPC appelée par Make) ne
tronque pas et empile. C'est par là que `JU.current_bias` a atteint 1 132 caractères.

## RÈGLE ABSOLUE — Ne jamais déployer ce que je n'ai pas pu tester (20/08/2026)

Le 20/08 à 05:55 j'ai déployé `execute-trades` v39 (rachat de short en quantité) sans l'avoir
jamais exercé marché ouvert, en le sachant et en l'écrivant. À 15:32 il a liquidé **1 361 754 $**
sur une demande de 6 000 $ (IEF), puis 9 394 $ sur GLD.

Un correctif touchant l'exécution d'ordres réels ne part en production qu'après :
1. un test en conditions réelles, ou à défaut l'accord explicite de Chachou en connaissance du
   risque ;
2. une borne de sécurité : **jamais d'ordre plus gros que ce que le modèle a demandé.**

## RÈGLE — Un contrôle étroit ne prouve pas une affirmation large (20/08/2026)

Le 20/08 j'ai affirmé « je n'ai jamais touché aux prompts des Archimages » après avoir vérifié
uniquement que `{{CTX}}` y figurait encore. Le prompt système est une autre partie du module.
Avant d'affirmer qu'une chose n'a pas changé, **lire l'objet entier**, pas un champ.

## RÈGLE ABSOLUE — Chachou n'écrit pas de code. Si c'est cassé, c'est moi (25/08/2026)

Chachou ne sait pas écrire une ligne de code : **tout ce qui est dans Supabase, dans les edge
functions et dans les modules Make vient de moi**, directement ou via les consignes que je lui
fais passer à Maia. La date d'un commit ou d'un dump ne prouve rien : un objet présent le 14/08
au matin peut très bien avoir été écrit par moi le 13/08 au soir. **Cesser de discuter la
paternité.** Le seul débat utile est : qu'est-ce qui est cassé, et comment on le répare.

Quand il dit « ça marchait avant », la réponse n'est pas « non » — c'est **comparer**. Le
blueprint d'avant le 13/08 qu'il a fourni est dans `scratchpad/ancien_bp.txt` ; le comparer
module par module avant toute affirmation. Le 25/08 cette comparaison lui a donné raison sur
trois points d'un coup : le Sage Mémoire tournait bien sur Groq, les Marées n'ont jamais changé
de moteur, et aucun module n'a disparu — c'est un seul module cassé (303) qui bloquait tout
le reste du scénario.

## Rappels système (contexte)
- Modifs Make **uniquement via l'assistant Maia** (jamais le blueprint en direct).
- Un blueprint complet fait ~620 ko : `scenarios_update` avec blueprint est hors de portée d'un
  appel d'outil. Les correctifs Make se livrent donc **en chaînes exactes à chercher/remplacer**,
  extraites du blueprint en direct et vérifiées contre une version qui tourne.
- Ne jamais armer/désarmer le kill_switch ni passer dry_run=false sans accord explicite de Chachou.
- 100 % Supabase pour la logique data ; ne pas committer de secrets (webhooks → Vault).
