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

## Rappels système (contexte)
- Modifs Make **uniquement via l'assistant Maia** (jamais le blueprint en direct).
- Ne jamais armer/désarmer le kill_switch ni passer dry_run=false sans accord explicite de Chachou.
- 100 % Supabase pour la logique data ; ne pas committer de secrets (webhooks → Vault).
