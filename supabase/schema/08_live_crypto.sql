-- ============================================================================
-- 08_live_crypto.sql — Valorisation CRYPTO en direct (24/7, week-end compris)
-- ============================================================================
-- Problème : quand le scénario Make est éteint (nuit, week-end), la console
-- affichait des valeurs figées. Or la crypto se négocie en continu et son cours
-- est bien alimenté 24/7 dans price_history (crons ingest_binance/gate/klines,
-- indépendants de Make). Ce qui gelait, c'était la couche de valorisation
-- (produite par Make), pas les cours.
--
-- Solution 100 % LECTURE, sans cron ni écriture : deux vues qui recalculent la
-- valorisation crypto À LA LECTURE depuis le dernier cours de price_history
-- (comme le panneau Marées). Aucun ordre, aucune décision, aucune écriture ;
-- ne touche NI au kill-switch NI au dry_run.
--
-- Périmètre honnête : SEULE la crypto (24/7) est exposée. Les actions/ETF
-- (bourses fermées) et le forex (fermé le week-end) restent au dernier close =
-- normal. Le TOTAL de portefeuille de oracle_positions_live n'est PAS fiable
-- (magnitudes incohérentes avec la baseline) → volontairement non exposé ici.
--
-- Mapping ticker : crypte Alpaca 'BTCUSD' → price_history 'BTC-USD'
--   (règle : left(ticker, len-3) || '-USD', pour les tickers finissant par USD
--    et sans tiret ; couvre BTC/ETH/SOL/XRP/LINK/AVAX/DOGE…).
-- ============================================================================

-- Détail par ligne crypto (une ligne = une position crypto d'un Sage) --------
create or replace view public.v_live_crypto_positions as
with pos as (
  select p.archimage, p.ticker,
         lower(coalesce(p.side,'long')) as side,
         p.qty::float8 as qty,
         p.avg_entry_price::float8 as avg_entry,
         left(p.ticker, length(p.ticker)-3) || '-USD' as ph_symbol
  from public.oracle_positions_live p
  where p.ticker ~ 'USD$' and p.ticker !~ '-' and coalesce(p.qty,0) <> 0
),
val as (
  select pos.*,
    (select ph.close::float8 from public.price_history ph
       where ph.symbol = pos.ph_symbol and ph.interval='1h'
         and ph.ts > now() - interval '6 hours'
       order by ph.ts desc limit 1) as live_price,
    (select ph.ts from public.price_history ph
       where ph.symbol = pos.ph_symbol and ph.interval='1h'
       order by ph.ts desc limit 1) as live_ts
  from pos
)
select archimage, ticker, side, qty, round(avg_entry::numeric,6) as prix_entree,
       round(live_price::numeric,6) as prix_actuel,
       (live_price is not null) as prix_live, live_ts,
       round((qty*live_price)::numeric,2) as valo_usd,
       round(((live_price/nullif(avg_entry,0)-1)*100)::numeric,2) as unreal_pct,
       round(((live_price-avg_entry)*qty)::numeric,2) as unreal_usd
from val
where live_price is not null
order by archimage, valo_usd desc;

-- Résumé par Sage (crypto uniquement, valorisée live) ------------------------
create or replace view public.v_live_crypto_resume as
with fx as (
  select (close)::float8 as eurusd from public.price_history
   where symbol='EUR-USD' and interval='1h' order by ts desc limit 1
)
select archimage,
       count(*) as n_crypto,
       bool_and(prix_live) as tout_live,
       max(live_ts) as dernier_cours,
       round(sum(valo_usd)::numeric,2) as valo_crypto_usd,
       round((sum(valo_usd)/nullif((select eurusd from fx),0))::numeric,2) as valo_crypto_eur,
       round(sum(unreal_usd)::numeric,2) as pnl_latent_usd
from public.v_live_crypto_positions
group by archimage
order by valo_crypto_usd desc;

grant select on public.v_live_crypto_positions, public.v_live_crypto_resume
  to anon, authenticated, service_role;
