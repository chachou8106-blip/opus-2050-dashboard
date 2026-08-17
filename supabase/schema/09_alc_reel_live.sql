-- ============================================================================
-- 09_alc_reel_live.sql — Alchimiste RÉEL (Revolut X) valorisé EN DIRECT
-- ============================================================================
-- Même principe que le virtuel (v_alc_virtuel_positions via v_dernier_prix) et que 08_live_crypto :
-- le portefeuille réel n'était valorisé qu'une fois par jour (revolut_portfolio_daily, écrit par
-- l'edge function revolut-portfolio-summary à 8h). Ici on reprend le DERNIER snapshot (quantités par
-- coin dans `detail`) et on revalorise CHAQUE ligne au dernier cours de price_history — alimenté 24/7
-- par ingest-revx-prices / ingest-klines / ingest-gate. Couverture : 47/49 coins ont un prix live +
-- 2 lignes de cash → ~100 % du portefeuille bouge en direct.
--
-- 100 % LECTURE : aucune écriture, aucun cron, aucun ordre, aucune décision. Ne touche NI au
-- kill-switch NI au dry_run. C'est le SEUL argent réel du système (Revolut X, au comptant, sans levier).
-- ============================================================================

-- Détail par coin (dernier snapshot, revalorisé live) ------------------------
create or replace view public.v_alc_reel_live_positions as
with latest as (
  select snapshot_at, detail from public.revolut_portfolio_daily
   order by snapshot_at desc limit 1
),
lignes as (
  select l.snapshot_at,
         (e->>'devise')            as devise,
         (e->>'qty')::float8        as qty,
         coalesce((e->>'stake')::float8,0) as stake,
         (e->>'valeur_usd')::float8 as valeur_snap
  from latest l, jsonb_array_elements(l.detail) e
)
select
  li.devise,
  li.qty,
  (li.stake > 0)                          as en_stake,
  round(li.valeur_snap::numeric,2)        as valeur_snapshot_usd,
  round(dp.prix::numeric,6)               as prix_live,
  dp.ts                                   as prix_ts,
  (dp.prix is not null or li.devise in ('USD','USDT','USDC','EUR','GBP')) as est_live,
  round((case
           when li.devise in ('USD','USDT','USDC','EUR','GBP') then li.qty
           when dp.prix is not null then li.qty*dp.prix
           else li.valeur_snap
         end)::numeric,2)                 as valeur_live_usd
from lignes li
left join public.v_dernier_prix dp on dp.base = upper(li.devise)
order by valeur_live_usd desc nulls last;

-- Résumé (total live vs snapshot 8h) ----------------------------------------
create or replace view public.v_alc_reel_live_resume as
with latest as (
  select snapshot_at, total_usd from public.revolut_portfolio_daily
   order by snapshot_at desc limit 1
),
fx as (
  select (close)::float8 as eurusd from public.price_history
   where symbol='EUR-USD' and interval='1h' order by ts desc limit 1
)
select
  (select snapshot_at from latest)                         as snapshot_at,
  (select round(total_usd::numeric,2) from latest)         as total_snapshot_usd,
  round(sum(valeur_live_usd)::numeric,2)                   as total_live_usd,
  round((sum(valeur_live_usd) - (select total_usd from latest))::numeric,2) as ecart_depuis_snapshot_usd,
  round((sum(valeur_live_usd)/nullif((select eurusd from fx),0))::numeric,2) as total_live_eur,
  count(*)                                                 as n_lignes,
  count(*) filter (where est_live)                        as n_live,
  max(prix_ts)                                            as dernier_cours
from public.v_alc_reel_live_positions;

grant select on public.v_alc_reel_live_positions, public.v_alc_reel_live_resume
  to anon, authenticated, service_role;
