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
seule de ses propres leçons. Retiré le 20/08 (sauvegarde `bak_20260820_lecon_epinglee`).

Interdictions, sans exception :
1. **Ne jamais écrire, modifier ou épingler** une ligne de `oracle_brain_state.learnings`,
   `current_bias`, `mistakes_history` ou toute autre colonne relue par un prompt.
2. **Ne jamais créer de canal** permettant d'injecter un texte de ma main dans un prompt.
3. Une consigne de comportement se met **dans le prompt système, via Maia**. Point.
4. Si je pense qu'un agent a besoin d'une règle, je le **propose à Chachou** avec le prompt Maia
   correspondant. C'est lui qui décide. Je n'ai pas le droit de court-circuiter.

**Liste des textes Supabase qui atteignent un prompt** — à vérifier avant toute modification :
`oracle_brain_state.current_bias` et `.learnings[].bias` (les 3 Archimages via `MEMORY_CORRECTION`),
`active_circuit_breakers` (via `CIRCUIT_BREAKERS`), `crypte_ju_evaluate_and_learn` (Alchimiste),
`marees_evaluate_and_learn` (Marées). Tout passe par `get_oracle_context()` → module 105.

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

## Rappels système (contexte)
- Modifs Make **uniquement via l'assistant Maia** (jamais le blueprint en direct).
- Ne jamais armer/désarmer le kill_switch ni passer dry_run=false sans accord explicite de Chachou.
- 100 % Supabase pour la logique data ; ne pas committer de secrets (webhooks → Vault).
