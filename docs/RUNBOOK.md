# RUNBOOK — Exploitation, maintenance & secours

> Procédures opérationnelles pour AETHER / OPUS 2050. Projet Supabase : `smddzybxebwhfnitxuyp`.
> À lire avant toute intervention. Voir aussi `ARCHITECTURE.md`.

---

## 0. Règles d'or (ne jamais enfreindre)
1. **Kill-switch & argent réel** : ne JAMAIS armer/désarmer `kill_switch` ni passer `dry_run=false`
   sans l'accord explicite de Chachou.
2. **Make** : ne JAMAIS éditer le blueprint en direct — tout passe par **Maia**.
3. **Données** : ne jamais inventer un chiffre. Toujours vérifier en base. Signaler les trous.
4. **Déploiement console** : la console n'est en ligne qu'une fois sur `main` (Netlify auto-deploy).

---

## 1. Kill-switch (trading réel Alchimiste)

```sql
-- État + PIN
select key, value from ju_crypte_config where key in ('kill_switch','arm_pin');
-- Forcer OFF (sûr, en cas de doute)
update ju_crypte_config set value='OFF' where key='kill_switch';
-- Forcer ON (⚠️ argent réel)         -- uniquement sur accord de Chachou
update ju_crypte_config set value='ON' where key='kill_switch';
-- Changer le PIN
update ju_crypte_config set value='<NOUVEAU_PIN>' where key='arm_pin';
-- Passkeys Face ID (si appareil perdu)
select credential_id, label, created_at from killswitch_passkeys;
delete from killswitch_passkeys;   -- réinitialise ; on ré-enregistre via le bouton console
```
Anti-lockout : OFF ne demande jamais de code ; le PIN vit en base. Détails :
`supabase/functions/README-KILLSWITCH.md`.

---

## 2. Santé des données (à checker en premier)

```sql
select * from v_data_health order by statut desc, age_h desc;
```
`FIGE` = source en retard au-delà du seuil. Sources surveillées : portefeuille Revolut, prix
(`price_history`), univers live, journal quotidien, cerveaux, propositions Alchimiste.
- `Propositions Alchimiste` FIGE → le scénario Make 6183820 ne tourne pas (voir §5).
- `Prix` / `Univers` FIGE → un ingest est cassé (voir §3).

---

## 3. Ingestion de prix cassée

```sql
-- Dernier point par source
select symbol, max(ts) from price_history where interval='1h' group by symbol order by 2 limit 5;
-- Jobs cron d'ingestion
select jobname, schedule, active from cron.job where jobname like 'ingest%' order by jobname;
-- Relancer un ingest à la main (exemple Revolut X)
select net.http_post(
  url:='https://smddzybxebwhfnitxuyp.supabase.co/functions/v1/ingest-revx-prices',
  headers:=jsonb_build_object('Content-Type','application/json'),
  body:='{}'::jsonb, timeout_milliseconds:=30000);
```
Consulter les logs d'une edge function via le dashboard Supabase (Functions → logs) ou
`mcp__Supabase__query_logs`.

---

## 4. Journal quotidien (matin / midi / soir)

Écrit **côté serveur** par `generate_daily_journal(creneau)` via pg_cron, indépendamment de toute
session Claude. Détails : `supabase/README-DAILY-JOURNAL.md`.
```sql
select public.generate_daily_journal('midi');            -- forcer un point
select jobname, schedule, active from cron.job where jobname like 'aether-point-%';
select id, jour, created_at, left(resume,80) from oracle_journal order by created_at desc limit 5;
```
Crons : `aether-point-matin` (10 6 * * *), `-midi` (10 11 * * *), `-soir` (10 18 * * *) — heures UTC.

---

## 5. L'Alchimiste ne propose plus / plante (scénario Make 6183820)

1. Vérifier les exécutions récentes (via Maia / Make : executions_list du scénario 6183820).
2. Erreur « The provided JSON body content is not valid JSON » → un corps JSON d'un module HTTP
   contient une valeur structurée brute. Rédiger un prompt Maia (modèle :
   `docs/decisions/PROMPT-MAIA-ALCHIMISTE-JSON-2026-08-14.md`).
3. Propositions écrites mais colonnes vides → mapping ; **c'est côté Supabase**
   (`alc_record_propositions`), pas Make. Voir `docs/decisions/CORRECTIF-ALCHIMISTE-MAPPING-2026-08-14.md`.
```sql
-- Dernières propositions (colonnes remplies ?)
select id, proposed_at, paire, side, montant, prix_ref, confidence, statut
from alchimiste_crypte_propositions order by id desc limit 8;
-- Reconstruire le portefeuille papier (learning)
select public.alc_rebuild_virtual();
```

---

## 6. Gains par trader (tableau console en €)

Source unique : vue `v_gains_traders` (servie par `oracle-inbox` action `suivi`, champ `gains`).
```sql
select serie, horizon, gain_pct, gain_usd, gain_eur from v_gains_traders order by ordre, horizon;
```
- JU/SYL/GIL : `baseline_equity × rendement_période / 100` (base ~1 M, `oracle_brain_state`).
- Alchimiste réel : variation `revolut_portfolio_daily.total_usd`. AETHER : somme des sages.
- Alchimiste virtuel : PnL des trades papier. Marées : idem forex (vide tant qu'aucun trade clos).
- Conversion €/$ via `price_history` EUR-USD (dernier cours). Marées absent des vues de rendement
  tant qu'aucun trade virtuel n'est clôturé.

---

## 7. Calendrier & rappels

`oracle_rappels(date_rappel, creneau, titre, message, done)` — affiché dans la console (section
Calendrier, bannière des rappels dus). Servi par `oracle-inbox` action `journal`.
```sql
-- Ajouter un rappel
insert into oracle_rappels(date_rappel, creneau, titre, message)
values ('2026-09-01','matin','Titre','Message…');
-- Marquer fait
update oracle_rappels set done=true where id=<id>;
```

---

## 8. Déploiement

- **Console (Netlify)** : commiter `console_aether 2.html` puis **merger sur `main`** → déploiement auto.
  Anti-cache : `?v=N`.
- **Edge functions** : déployer via `mcp__Supabase__deploy_edge_function` (⚠️ garder
  `verify_jwt=false` pour les fonctions publiques appelées par la console, sinon régression).
  Puis mettre à jour la source dans `supabase/functions/<slug>/index.ts`.
- **Schéma (vues/fonctions)** : appliquer via `mcp__Supabase__apply_migration`, puis regénérer le
  dump `supabase/schema/` (voir §10).

---

## 9. Incidents connus & résolutions (14/08/2026)
| Symptôme | Cause | Fix |
|---|---|---|
| Alchimiste « trade non tradable » | sell-only + spot | `alc-auto` v6 buy+sell, tradabilité live |
| Scénario 6183820 « JSON invalide » | tableaux bruts dans le corps Perplexity | via Maia (prompt JSON) |
| Propositions colonnes NULL | `alc_record_propositions` lisait les anciennes clés | fonction réécrite + lookup prix |
| Alerte univers « figé 37j » | table morte `revolut_univers_complet` | `v_data_health` repointée sur `price_history` |
| Gains € faux | base d'équité mauvaise (~54k au lieu de ~1M) | `v_gains_traders` (baseline_equity) |
| Journal absent de l'app | cron ne pouvait pas écrire | `generate_daily_journal` + pg_cron serveur |

---

## 10. Regénérer les exports du repo

Le dump `supabase/schema/*.sql` et `supabase/functions/*/index.ts` sont des **exports de l'état
vivant**. Pour les rafraîchir après des changements :
- **Edge functions** : pour chaque slug, `mcp__Supabase__get_edge_function` → écrire
  `supabase/functions/<slug>/index.ts`. Liste des slugs : `supabase/functions/_MANIFEST.md`.
- **Schéma** : requêtes `pg_get_viewdef` (vues), `pg_get_functiondef` (fonctions),
  `information_schema.columns` (tables), `cron.job` (cron), `pg_policies` (RLS). Détails et requêtes
  exactes : `supabase/schema/README.md`.

> Ces fichiers ne sont pas appliqués automatiquement : ils servent de **référence et de reconstruction**.
> La source de vérité opérationnelle reste la base Supabase live.
