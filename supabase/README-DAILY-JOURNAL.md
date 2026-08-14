# Résumé quotidien AETHER — 100 % serveur (matin / midi / soir)

Le point du jour affiché dans la console (`console_aether 2.html`, section « Journal quotidien »,
lit `oracle_journal`) est **généré et écrit côté serveur**, sans dépendre d'une session Claude.

## Ce qui l'écrit
Fonction SQL `public.generate_daily_journal(creneau text)` (security definer) — compose le point
COMPLET depuis les vues et l'insère dans `oracle_journal` :
1. REVOLUT X (total/cash/liquide/stake/lignes + variation)
2. SAGES ACTIONS — SYL, GIL, JU (rendement, DD, WR)
3. RÉGIME MONDIAL + alignement (v_world_context)
4. ALCHIMISTE VIRTUEL — brut **vs net de frais** (0,18 %/trade) + verdict
5. MARÉES (forex virtuel)
6. DÉ-STAKING — coins stakés + APY (`alc_staking_apy`) + délai (`alc_staking_delais`) + verdict
+ Synthèse

Garde anti-doublon : ne réécrit pas si un point du même créneau existe déjà (< 6h).

## Planification (pg_cron, dans la base)
- `aether-point-matin` : `10 6 * * *`  (08h10 Paris)
- `aether-point-midi`  : `10 11 * * *` (13h10 Paris)
- `aether-point-soir`  : `10 18 * * *` (20h10 Paris)

La tâche Claude « AETHER — Résumé » reste pour la **notification push** ; le serveur garantit l'écriture sur l'app.

## Vérif / secours (Supabase MCP execute_sql ou SQL editor, projet smddzybxebwhfnitxuyp)
```sql
-- générer un point à la main
select public.generate_daily_journal('midi');
-- voir les jobs planifiés
select jobname, schedule, active from cron.job where jobname like 'aether-point-%';
-- dernières entrées affichées par l'app
select id, jour, created_at, left(resume,80) from oracle_journal order by created_at desc limit 5;
```
