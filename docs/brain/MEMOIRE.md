# Mémoire des bots traders — permanente (« à vie »)

> Objectif : aucun apprentissage n'est perdu. Chaque bot (JU, SYL, GIL) garde son historique complet
> sur des mois puis des années. Ce document explique où vit la mémoire et comment elle est préservée.

## Le principe (important)
On garde **tout, pour toujours, dans la base**. Mais on ne peut PAS réinjecter des milliers de leçons
dans chaque prompt (limite de taille des modèles). Donc :
- **Archive complète** = mémoire longue, permanente, consultable (base Supabase + sauvegarde GitHub).
- **État distillé** = ce que le bot lit à chaque décision : win rate, doctrine courante, leçons
  récentes (fenêtre) **+ leçons épinglées permanentes**. Il est **calculé à partir de l'archive**.
Le bot progresse via cet état distillé ; l'archive sert de mémoire de fond et de sauvegarde.

## Où vit la mémoire

| Donnée | Table | Rétention |
|---|---|---|
| Performance run par run (PnL, win/loss, drawdown, précision, régime, notes) | `oracle_performance` | **permanente** (append-only) |
| Leçons & erreurs qualitatives (bias/eval par run) | **`brain_lessons`** | **permanente** (append-only, jamais rognée) |
| État courant injecté au prompt (win_rate, doctrine, 30 dernières leçons, leçons épinglées) | `oracle_brain_state` | fenêtre glissante 30 + **épinglées permanentes** |

### `brain_lessons` (archive permanente)
`(archimage, run_id, kind['learning'|'mistake'], bias, eval, pnl, dd, at)`, clé unique
`(archimage, run_id, kind)`. Alimentée automatiquement par le **trigger** `trg_archive_brain_lessons`
sur `oracle_brain_state` : à chaque écriture du cerveau, la dernière leçon + la dernière erreur sont
archivées (dédup). Rien n'est jamais supprimé.

Consulter la mémoire d'un bot :
```sql
select at, kind, pnl, dd, coalesce(bias,eval) as lecon
from brain_lessons where archimage='SYL' order by at desc;   -- historique complet
select count(*) , min(at) from brain_lessons where archimage='SYL';
```

### Leçons épinglées (permanentes, toujours lues)
Le prompt lit `learnings[1].bias` comme MEMORY_CORRECTION. `update-brain` v16+ **préserve** les
entrées `pinned:true` en tête de `learnings` (jamais rognées) → une leçon manuelle reste lue en
permanence. Procédure : `docs/RUNBOOK.md` §11.

## Sauvegarde GitHub (versionnée, hors base)
La base est la mémoire **runtime** (rapide, ce que lisent les IA). GitHub sert de **sauvegarde
versionnée** sur la durée. Snapshot périodique de `brain_lessons` + doctrines dans `docs/brain/` (voir
`snapshots/`). L'export peut être relancé à la demande ou planifié (hebdo). Note : un push GitHub
100 % automatisé depuis Supabase nécessiterait un token GitHub (secret) — en attendant, l'export est
fait via l'outillage (à la demande / planifié).

## Ce qui reste à faire (honnête)
- Les leçons qualitatives **antérieures aux 30 dernières** (juin/juillet) étaient déjà perdues avant
  cette archive — irrécupérables côté texte, mais le **quantitatif** de ces runs est dans
  `oracle_performance`. À partir du 15/08/2026, **plus aucune perte**.
