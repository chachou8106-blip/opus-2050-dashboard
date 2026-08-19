-- ============================================================
-- VIEW: ju_archimage_metrics
-- ============================================================
CREATE OR REPLACE VIEW public.ju_archimage_metrics AS
 SELECT archimage,
    count(*) AS positions,
    round(avg(unrealized_pl_pct), 2) AS rendement_moyen_pct,
    round(count(*) FILTER (WHERE unrealized_pl_pct > 0::numeric)::numeric * 100.0 / NULLIF(count(*), 0)::numeric, 1) AS pct_gagnantes,
    round(avg(unrealized_pl_pct) FILTER (WHERE unrealized_pl_pct > 0::numeric), 2) AS gain_moyen_pct,
    round(avg(unrealized_pl_pct) FILTER (WHERE unrealized_pl_pct < 0::numeric), 2) AS perte_moyenne_pct,
    round(max(unrealized_pl_pct), 2) AS meilleur_pct,
    round(min(unrealized_pl_pct), 2) AS pire_pct,
    round(stddev_pop(unrealized_pl_pct), 2) AS volatilite_pct,
    round(avg(unrealized_pl_pct) / NULLIF(stddev_pop(unrealized_pl_pct), 0::numeric), 3) AS sharpe_like,
    round(avg(unrealized_pl_pct) FILTER (WHERE unrealized_pl_pct > 0::numeric) / NULLIF(abs(avg(unrealized_pl_pct) FILTER (WHERE unrealized_pl_pct < 0::numeric)), 0::numeric), 2) AS ratio_gain_perte,
    round(sum(unrealized_pl), 2) AS pnl_usd
   FROM oracle_positions_live
  WHERE abs(market_value) >= 50::numeric
  GROUP BY archimage
;

-- ============================================================
-- VIEW: oracle_dashboard
-- ============================================================
CREATE OR REPLACE VIEW public.oracle_dashboard AS
 SELECT now() AS snapshot_at,
    ( SELECT oracle_college_runs.run_id
           FROM oracle_college_runs
          ORDER BY oracle_college_runs.run_at DESC
         LIMIT 1) AS last_run_id,
    ( SELECT oracle_college_runs.run_at
           FROM oracle_college_runs
          ORDER BY oracle_college_runs.run_at DESC
         LIMIT 1) AS last_run_at,
    ( SELECT oracle_college_runs.market_phase
           FROM oracle_college_runs
          ORDER BY oracle_college_runs.run_at DESC
         LIMIT 1) AS last_market_phase,
    ( SELECT oracle_college_runs.orders_count
           FROM oracle_college_runs
          ORDER BY oracle_college_runs.run_at DESC
         LIMIT 1) AS last_run_orders,
    ( SELECT oracle_college_runs.overlap_score
           FROM oracle_college_runs
          ORDER BY oracle_college_runs.run_at DESC
         LIMIT 1) AS last_overlap_score,
    ( SELECT jsonb_object_agg(oracle_brain_state.archimage, jsonb_build_object('win_rate', round(oracle_brain_state.win_rate * 100::numeric, 1), 'pnl', round(oracle_brain_state.cumulative_pnl, 2), 'weight', oracle_brain_state.synthesis_weight, 'universe', oracle_brain_state.assigned_universe, 'drawdown', round(oracle_brain_state.alpaca_drawdown_from_peak * 100::numeric, 2), 'kelly', round(oracle_brain_state.kelly_fraction, 3))) AS jsonb_object_agg
           FROM oracle_brain_state
          WHERE oracle_brain_state.archimage <> 'cerveau'::text) AS archimages,
    ( SELECT count(*) AS count
           FROM oracle_college_orders) AS total_orders,
    ( SELECT count(*) AS count
           FROM oracle_college_orders
          WHERE oracle_college_orders.side = 'buy'::text) AS total_buys,
    ( SELECT count(*) AS count
           FROM oracle_college_orders
          WHERE oracle_college_orders.side = 'sell'::text) AS total_sells,
    ( SELECT count(*) AS count
           FROM oracle_college_orders
          WHERE oracle_college_orders.notional > 2000::numeric) AS orders_above_cap,
    ( SELECT count(*) AS count
           FROM oracle_college_orders
          WHERE oracle_college_orders.broker_status = 'accepted'::text) AS orders_accepted,
    ( SELECT count(*) AS count
           FROM oracle_flash_intel
          WHERE oracle_flash_intel.captured_at > (now() - '06:00:00'::interval)) AS fresh_catalysts,
    ( SELECT count(*) AS count
           FROM oracle_circuit_breakers
          WHERE oracle_circuit_breakers.auto_resolved = false AND oracle_circuit_breakers.fired_at > (now() - '24:00:00'::interval)) AS active_breakers,
    ( SELECT count(*) AS count
           FROM oracle_visionary_signals
          WHERE oracle_visionary_signals.generated_at > (now() - '04:00:00'::interval) AND oracle_visionary_signals.conviction >= 7) AS strong_visionary_signals,
    ( SELECT round(avg(oracle_college_runs.overlap_score), 2) AS round
           FROM oracle_college_runs
          WHERE oracle_college_runs.run_at > (now() - '7 days'::interval)) AS avg_overlap_7d,
    ( SELECT round(sum(
                CASE
                    WHEN oracle_college_orders.side = 'sell'::text THEN 1
                    ELSE 0
                END)::numeric / GREATEST(count(*), 1::bigint)::numeric * 100::numeric, 1) AS round
           FROM oracle_college_orders
          WHERE oracle_college_orders.created_at > (now() - '7 days'::interval)) AS sell_ratio_7d_pct
;

-- ============================================================
-- VIEW: oracle_recent_runs_v2
-- ============================================================
CREATE OR REPLACE VIEW public.oracle_recent_runs_v2 AS
 SELECT run_id,
    run_at,
    market_phase,
    data_completeness,
    consensus_level,
    orders_count,
    orders_buy,
    orders_sell,
    orders_executed,
    overlap_score,
    circuit_breaker_fired,
    syl_web_catalysts,
    syl_top_catalyst_ticker,
    visionary_score,
    claude_confidence,
    perplexity_confidence,
    mistral_confidence
   FROM oracle_college_runs
  ORDER BY run_at DESC
;

-- ============================================================
-- VIEW: v_alc_bh_daily
-- ============================================================
CREATE OR REPLACE VIEW public.v_alc_bh_daily AS
 SELECT r.jour,
    sum(w.val * r.ret) / NULLIF(sum(w.val), 0::numeric) AS bh_ret
   FROM v_alc_coin_ret r
     JOIN v_alc_holdings_w w ON w.coin = r.coin
  WHERE r.ret IS NOT NULL
  GROUP BY r.jour
;

-- ============================================================
-- VIEW: v_alc_bt_daily
-- ============================================================
CREATE OR REPLACE VIEW public.v_alc_bt_daily AS
 SELECT strategie,
    jour,
    count(*) AS n,
    round((sum(montant * pn) / NULLIF(sum(montant), 0::double precision))::numeric, 4) AS ret_net_pct
   FROM v_alc_bt_flat
  GROUP BY strategie, jour
;

-- ============================================================
-- VIEW: v_alc_bt_flat
-- ============================================================
CREATE OR REPLACE VIEW public.v_alc_bt_flat AS
 WITH t AS (
         SELECT tr.montant,
            tr.side,
            tr.pnl_pct,
            (tr.exit_ts AT TIME ZONE 'UTC'::text)::date AS jour,
            upper(replace(replace(tr.paire, '-USD'::text, ''::text), '/USD'::text, ''::text)) AS coin,
            c.held,
            COALESCE(c.reliable, false) AS reliable
           FROM alchimiste_virtual_trades tr
             LEFT JOIN alc_bt_coins c ON c.coin = upper(replace(replace(tr.paire, '-USD'::text, ''::text), '/USD'::text, ''::text))
          WHERE NOT tr.is_open AND tr.exit_ts IS NOT NULL
        )
 SELECT 'A. Tel quel (baseline)'::text AS strategie,
    t.jour,
    t.montant,
    t.pnl_pct - 0.18::double precision AS pn
   FROM t
UNION ALL
 SELECT 'B. Shorts seuls'::text AS strategie,
    t.jour,
    t.montant,
    t.pnl_pct - 0.18::double precision AS pn
   FROM t
  WHERE t.side = 'sell'::text
UNION ALL
 SELECT 'C. Longs inverses'::text AS strategie,
    t.jour,
    t.montant,
        CASE
            WHEN t.side = 'sell'::text THEN t.pnl_pct
            ELSE - t.pnl_pct
        END - 0.18::double precision AS pn
   FROM t
UNION ALL
 SELECT 'D. Rotation-cash (detenus)'::text AS strategie,
    t.jour,
    t.montant,
    t.pnl_pct - 0.18::double precision AS pn
   FROM t
  WHERE t.side = 'sell'::text AND COALESCE(t.held, false)
UNION ALL
 SELECT 'E. Rotation-cash selective'::text AS strategie,
    t.jour,
    t.montant,
    t.pnl_pct - 0.18::double precision AS pn
   FROM t
  WHERE t.side = 'sell'::text AND t.reliable
;

-- ============================================================
-- VIEW: v_alc_bt_resume
-- ============================================================
CREATE OR REPLACE VIEW public.v_alc_bt_resume AS
 SELECT v_alc_bt_flat.strategie,
    'total'::text AS periode,
    count(*) AS trades,
    round(count(*) FILTER (WHERE v_alc_bt_flat.pn > 0::double precision)::numeric / NULLIF(count(*), 0)::numeric * 100::numeric, 1) AS wr_net,
    round((sum(v_alc_bt_flat.montant * v_alc_bt_flat.pn) / NULLIF(sum(v_alc_bt_flat.montant), 0::double precision))::numeric, 3) AS edge_net_moy,
    round(sum(v_alc_bt_flat.montant * v_alc_bt_flat.pn / 100::double precision)::numeric, 2) AS pnl_net_unit
   FROM v_alc_bt_flat
  GROUP BY v_alc_bt_flat.strategie
UNION ALL
 SELECT v_alc_bt_flat.strategie,
    'hors-echantillon'::text AS periode,
    count(*) AS trades,
    round(count(*) FILTER (WHERE v_alc_bt_flat.pn > 0::double precision)::numeric / NULLIF(count(*), 0)::numeric * 100::numeric, 1) AS wr_net,
    round((sum(v_alc_bt_flat.montant * v_alc_bt_flat.pn) / NULLIF(sum(v_alc_bt_flat.montant), 0::double precision))::numeric, 3) AS edge_net_moy,
    round(sum(v_alc_bt_flat.montant * v_alc_bt_flat.pn / 100::double precision)::numeric, 2) AS pnl_net_unit
   FROM v_alc_bt_flat
  WHERE v_alc_bt_flat.jour >= '2026-08-12'::date
  GROUP BY v_alc_bt_flat.strategie
;

-- ============================================================
-- VIEW: v_alc_coin_ret
-- ============================================================
CREATE OR REPLACE VIEW public.v_alc_coin_ret AS
 WITH dc AS (
         SELECT upper(replace(replace(price_history.symbol, '-USD'::text, ''::text), '/USD'::text, ''::text)) AS coin,
            price_history.ts::date AS jour,
            (array_agg(price_history.close ORDER BY price_history.ts DESC))[1] AS c
           FROM price_history
          WHERE (upper(replace(replace(price_history.symbol, '-USD'::text, ''::text), '/USD'::text, ''::text)) IN ( SELECT alc_bt_coins.coin
                   FROM alc_bt_coins
                  WHERE alc_bt_coins.held))
          GROUP BY (upper(replace(replace(price_history.symbol, '-USD'::text, ''::text), '/USD'::text, ''::text))), (price_history.ts::date)
        )
 SELECT coin,
    jour,
    c / NULLIF(lag(c) OVER (PARTITION BY coin ORDER BY jour), 0::numeric) - 1::numeric AS ret
   FROM dc
;

-- ============================================================
-- VIEW: v_alc_holdings_w
-- ============================================================
CREATE OR REPLACE VIEW public.v_alc_holdings_w AS
 SELECT upper(d.value ->> 'devise'::text) AS coin,
    (d.value ->> 'valeur_usd'::text)::numeric AS val
   FROM revolut_portfolio_daily,
    LATERAL jsonb_array_elements(revolut_portfolio_daily.detail) d(value)
  WHERE revolut_portfolio_daily.snapshot_at = (( SELECT max(revolut_portfolio_daily_1.snapshot_at) AS max
           FROM revolut_portfolio_daily revolut_portfolio_daily_1)) AND ((d.value ->> 'valeur_usd'::text)::numeric) >= 3::numeric AND (upper(d.value ->> 'devise'::text) IN ( SELECT alc_bt_coins.coin
           FROM alc_bt_coins
          WHERE alc_bt_coins.held))
;

-- ============================================================
-- VIEW: v_alc_regime_daily
-- ============================================================
CREATE OR REPLACE VIEW public.v_alc_regime_daily AS
 SELECT proposed_at::date AS jour,
    count(*) FILTER (WHERE side = 'sell'::text)::numeric / NULLIF(count(*), 0)::numeric AS share_short
   FROM alchimiste_crypte_propositions
  GROUP BY (proposed_at::date)
;

-- ============================================================
-- VIEW: v_alc_riskoff_daily
-- ============================================================
CREATE OR REPLACE VIEW public.v_alc_riskoff_daily AS
 WITH r AS (
         SELECT b.jour,
            b.bh_ret,
            COALESCE(g.share_short, 0::numeric) AS ss,
            COALESCE(g.share_short, 0::numeric) >= 0.9 AS cash
           FROM v_alc_bh_daily b
             LEFT JOIN v_alc_regime_daily g ON g.jour = b.jour
        ), r2 AS (
         SELECT r.jour,
            r.bh_ret,
            r.ss,
            r.cash,
            lag(r.cash) OVER (ORDER BY r.jour) AS prev_cash
           FROM r
        )
 SELECT jour,
    bh_ret,
    ss,
    cash,
        CASE
            WHEN cash THEN 0::numeric
            ELSE bh_ret
        END -
        CASE
            WHEN prev_cash IS NOT NULL AND cash IS DISTINCT FROM prev_cash THEN 0.0009
            ELSE 0::numeric
        END AS f_ret
   FROM r2
;

-- ============================================================
-- VIEW: v_alc_riskoff_resume
-- ============================================================
CREATE OR REPLACE VIEW public.v_alc_riskoff_resume AS
 SELECT 'F. Risk-off global'::text AS strategie,
    'total'::text AS periode,
    count(*) FILTER (WHERE v_alc_riskoff_daily.cash) AS jours_cash,
    count(*) AS jours,
    round((exp(sum(ln(1::numeric + v_alc_riskoff_daily.f_ret))) - 1::numeric) * 100::numeric, 2) AS f_cumul_pct,
    round((exp(sum(ln(1::numeric + v_alc_riskoff_daily.bh_ret))) - 1::numeric) * 100::numeric, 2) AS bh_cumul_pct
   FROM v_alc_riskoff_daily
  WHERE v_alc_riskoff_daily.jour >= '2026-07-03'::date
UNION ALL
 SELECT 'F. Risk-off global'::text AS strategie,
    'hors-echantillon'::text AS periode,
    count(*) FILTER (WHERE v_alc_riskoff_daily.cash) AS jours_cash,
    count(*) AS jours,
    round((exp(sum(ln(1::numeric + v_alc_riskoff_daily.f_ret))) - 1::numeric) * 100::numeric, 2) AS f_cumul_pct,
    round((exp(sum(ln(1::numeric + v_alc_riskoff_daily.bh_ret))) - 1::numeric) * 100::numeric, 2) AS bh_cumul_pct
   FROM v_alc_riskoff_daily
  WHERE v_alc_riskoff_daily.jour >= '2026-08-12'::date
;

-- ============================================================
-- VIEW: v_alc_virtuel_jour
-- ============================================================
CREATE OR REPLACE VIEW public.v_alc_virtuel_jour AS
 WITH j AS (
         SELECT (alchimiste_virtual_trades.exit_ts AT TIME ZONE 'UTC'::text)::date AS jour,
            count(*) AS n_trades,
            count(*) FILTER (WHERE alchimiste_virtual_trades.pnl_pct > 0::double precision) AS gagnants,
            sum(alchimiste_virtual_trades.montant * alchimiste_virtual_trades.pnl_pct) / NULLIF(sum(alchimiste_virtual_trades.montant), 0::double precision) AS ret_pct
           FROM alchimiste_virtual_trades
          WHERE NOT alchimiste_virtual_trades.is_open AND alchimiste_virtual_trades.exit_ts IS NOT NULL
          GROUP BY ((alchimiste_virtual_trades.exit_ts AT TIME ZONE 'UTC'::text)::date)
        )
 SELECT jour,
    n_trades,
    gagnants,
    round(gagnants::numeric / NULLIF(n_trades, 0)::numeric * 100::numeric, 1) AS wr_pct,
    round(ret_pct::numeric, 3) AS ret_pct,
    round(((exp(sum(ln(1::double precision + ret_pct / 100::double precision)) OVER (ORDER BY jour)) - 1::double precision) * 100::double precision)::numeric, 2) AS cumul_pct
   FROM j
;

-- ============================================================
-- VIEW: v_alc_virtuel_positions
-- ============================================================
CREATE OR REPLACE VIEW public.v_alc_virtuel_positions AS
 SELECT t.paire,
    t.side,
    round(t.prix_entree::numeric, 6) AS prix_entree,
    round(t.montant::numeric, 2) AS montant,
    (t.opened_at AT TIME ZONE 'UTC'::text) AS opened_at,
    round(p.prix, 6) AS prix_actuel,
        CASE
            WHEN p.prix IS NOT NULL AND t.prix_entree > 0::double precision THEN round((
            CASE
                WHEN t.side = 'sell'::text THEN t.prix_entree - p.prix::double precision
                ELSE p.prix::double precision - t.prix_entree
            END / t.prix_entree * 100::double precision)::numeric, 2)
            ELSE NULL::numeric
        END AS unreal_pct
   FROM alchimiste_virtual_trades t
     LEFT JOIN v_dernier_prix p ON p.base = upper(replace(replace(t.paire, '-USD'::text, ''::text), '/USD'::text, ''::text))
  WHERE t.is_open
;

-- ============================================================
-- VIEW: v_alc_virtuel_resume
-- ============================================================
CREATE OR REPLACE VIEW public.v_alc_virtuel_resume AS
 WITH c AS (
         SELECT alchimiste_virtual_trades.proposition_id,
            alchimiste_virtual_trades.paire,
            alchimiste_virtual_trades.side,
            alchimiste_virtual_trades.prix_entree,
            alchimiste_virtual_trades.montant,
            alchimiste_virtual_trades.opened_at,
            alchimiste_virtual_trades.tp_pct,
            alchimiste_virtual_trades.sl_pct,
            alchimiste_virtual_trades.exit_ts,
            alchimiste_virtual_trades.prix_sortie,
            alchimiste_virtual_trades.exit_reason,
            alchimiste_virtual_trades.pnl_pct,
            alchimiste_virtual_trades.hold_hours,
            alchimiste_virtual_trades.is_open,
            alchimiste_virtual_trades.rebuilt_at
           FROM alchimiste_virtual_trades
          WHERE NOT alchimiste_virtual_trades.is_open AND alchimiste_virtual_trades.exit_ts IS NOT NULL
        )
 SELECT ( SELECT count(*) AS count
           FROM c) AS trades_clos,
    ( SELECT round(count(*) FILTER (WHERE c.pnl_pct > 0::double precision)::numeric / NULLIF(count(*), 0)::numeric * 100::numeric, 1) AS round
           FROM c) AS wr_pct,
    ( SELECT round(avg(c.pnl_pct)::numeric, 3) AS round
           FROM c) AS pnl_moy_pct,
    ( SELECT v_alc_virtuel_jour.cumul_pct
           FROM v_alc_virtuel_jour
          ORDER BY v_alc_virtuel_jour.jour DESC
         LIMIT 1) AS cumul_pct,
    ( SELECT count(*) AS count
           FROM alchimiste_virtual_trades
          WHERE alchimiste_virtual_trades.is_open) AS positions_ouvertes,
    ( SELECT round(sum(alchimiste_virtual_trades.montant)::numeric, 2) AS round
           FROM alchimiste_virtual_trades
          WHERE alchimiste_virtual_trades.is_open) AS expo_ouverte,
    ( SELECT min(alchimiste_virtual_trades.opened_at) AS min
           FROM alchimiste_virtual_trades) AS depuis,
    ( SELECT max(c.exit_ts) AS max
           FROM c) AS dernier
;

-- ============================================================
-- VIEW: v_comparaison
-- ============================================================
-- Reecrite le 19/08/2026 : JU/SYL/GIL proviennent des clotures officielles Alpaca
-- (alpaca_equity_daily) et non plus des instantanes intra-seance de oracle_performance,
-- qui derivaient de -12 925 $ a +32 382 $ par jour (et +182 624 $ sur JU le 18/08).
CREATE OR REPLACE VIEW public.v_comparaison AS
 WITH d0 AS (SELECT '2026-06-05'::date AS start),
 strat AS (
   SELECT e.archimage AS serie, e.jour,
          round((e.equity - bs.baseline_equity) / NULLIF(bs.baseline_equity, 0) * 100::numeric, 3) AS ret
     FROM alpaca_equity_daily e
     JOIN oracle_brain_state bs ON bs.archimage = e.archimage
     CROSS JOIN d0
    WHERE e.jour >= d0.start AND bs.baseline_equity IS NOT NULL
 ), opus AS (
   SELECT 'OPUS'::text AS serie, strat.jour, round(avg(strat.ret), 3) AS ret
     FROM strat GROUP BY strat.jour
 ), alc_d AS (
   SELECT date_trunc('day'::text, alchimiste_virtual_trades.exit_ts)::date AS jour,
          sum(alchimiste_virtual_trades.pnl_pct / 100.0::double precision * alchimiste_virtual_trades.montant) AS dpnl,
          sum(alchimiste_virtual_trades.montant) AS ddep
     FROM alchimiste_virtual_trades, d0
    WHERE NOT alchimiste_virtual_trades.is_open AND alchimiste_virtual_trades.exit_ts IS NOT NULL AND alchimiste_virtual_trades.exit_ts >= d0.start
    GROUP BY (date_trunc('day'::text, alchimiste_virtual_trades.exit_ts)::date)
 ), alc AS (
   SELECT 'ALCHIMISTE'::text AS serie, alc_d.jour,
          round((sum(alc_d.dpnl) OVER (ORDER BY alc_d.jour) / NULLIF(sum(alc_d.ddep) OVER (ORDER BY alc_d.jour), 0::double precision) * 100::double precision)::numeric, 3) AS ret
     FROM alc_d
 ), mar_d AS (
   SELECT date_trunc('day'::text, marees_virtual_trades.exit_ts)::date AS jour,
          sum(marees_virtual_trades.pnl_pct / 100.0::double precision * marees_virtual_trades.montant) AS dpnl,
          sum(marees_virtual_trades.montant) AS ddep
     FROM marees_virtual_trades, d0
    WHERE NOT marees_virtual_trades.is_open AND marees_virtual_trades.exit_ts IS NOT NULL AND marees_virtual_trades.exit_ts >= d0.start
    GROUP BY (date_trunc('day'::text, marees_virtual_trades.exit_ts)::date)
 ), mar AS (
   SELECT 'MAREES'::text AS serie, mar_d.jour,
          round((sum(mar_d.dpnl) OVER (ORDER BY mar_d.jour) / NULLIF(sum(mar_d.ddep) OVER (ORDER BY mar_d.jour), 0::double precision) * 100::double precision)::numeric, 3) AS ret
     FROM mar_d
 ), bench_d AS (
   SELECT ph.symbol AS serie, date_trunc('day'::text, ph.ts)::date AS jour,
          (array_agg(ph.close ORDER BY ph.ts DESC))[1] AS close
     FROM price_history ph, d0
    WHERE ph."interval" = '1h'::text AND ph.ts >= d0.start
      AND (ph.symbol = ANY (ARRAY['SPY','QQQ','DIA','IWM','GLD','SLV','URTH','EEM','EFA','EWQ','FEZ','USO','BTC-USD','ETH-USD','SOL-USD','BNB-USD','XRP-USD']))
    GROUP BY ph.symbol, (date_trunc('day'::text, ph.ts)::date)
 ), bench0 AS (
   SELECT bench_d.serie, (array_agg(bench_d.close ORDER BY bench_d.jour))[1] AS c0
     FROM bench_d GROUP BY bench_d.serie
 ), bench AS (
   SELECT b.serie, b.jour, round((b.close / NULLIF(b0.c0, 0::numeric) - 1::numeric) * 100::numeric, 3) AS ret
     FROM bench_d b JOIN bench0 b0 USING (serie)
 )
 SELECT serie, jour, ret FROM strat
 UNION ALL SELECT serie, jour, ret FROM opus
 UNION ALL SELECT serie, jour, ret FROM alc
 UNION ALL SELECT serie, jour, ret FROM mar
 UNION ALL SELECT serie, jour, ret FROM bench
;

-- ============================================================
-- VIEW: v_couts_friction
-- ============================================================
CREATE OR REPLACE VIEW public.v_couts_friction AS
 SELECT archimage,
    count(*) AS ordres_executes,
    round(sum(COALESCE(executed_notional, notional, 0::numeric)), 0) AS notional_total,
    round(sum(COALESCE(executed_notional, notional, 0::numeric) *
        CASE
            WHEN asset_class = 'crypto'::text THEN 0.0025
            ELSE 0.0002
        END), 2) AS cout_estime_usd,
    round(avg(slippage_pct) FILTER (WHERE slippage_pct IS NOT NULL), 3) AS slippage_achats_moyen_pct,
    round(sum(COALESCE(executed_notional, notional, 0::numeric) *
        CASE
            WHEN asset_class = 'crypto'::text THEN 0.0025
            ELSE 0.0002
        END) / NULLIF(sum(COALESCE(executed_notional, notional, 0::numeric)), 0::numeric) * 100::numeric, 3) AS friction_moyenne_pct
   FROM oracle_college_orders
  WHERE broker_status = ANY (ARRAY['filled'::text, 'partially_filled'::text])
  GROUP BY archimage
;

-- ============================================================
-- VIEW: v_crypto_univers
-- ============================================================
CREATE OR REPLACE VIEW public.v_crypto_univers AS
 SELECT DISTINCT paire
   FROM alchimiste_crypte_propositions
  WHERE paire ~~ '%-USD'::text AND (paire <> ALL (ARRAY['USD-USD'::text, 'USDT-USD'::text, 'USDC-USD'::text, 'EUR-USD'::text, 'DAI-USD'::text, 'FDUSD-USD'::text, 'TUSD-USD'::text]))
;

-- ============================================================
-- VIEW: v_data_health
-- ============================================================
CREATE OR REPLACE VIEW public.v_data_health AS
 WITH sources AS (
         SELECT 'Portefeuille Revolut (snapshot)'::text AS source,
            max(revolut_portfolio_daily.snapshot_at) AS maj,
            30 AS seuil_h
           FROM revolut_portfolio_daily
        UNION ALL
         SELECT 'Prix crypto/forex (price_history)'::text AS text,
            max(price_history.ts) AS max,
            6
           FROM price_history
        UNION ALL
         SELECT 'Univers tradable (live)'::text AS text,
            ( SELECT max(q.bucket) AS max
                   FROM ( SELECT date_trunc('hour'::text, ph.ts) AS bucket
                           FROM price_history ph
                          WHERE ph.ts > (now() - '7 days'::interval)
                          GROUP BY (date_trunc('hour'::text, ph.ts))
                         HAVING count(DISTINCT ph.symbol) >= 200) q) AS max,
            6
        UNION ALL
         SELECT 'Journal quotidien'::text AS text,
            max(oracle_journal.created_at) AS max,
            15
           FROM oracle_journal
        UNION ALL
         SELECT 'Cerveaux archimages'::text AS text,
            max(oracle_brain_state.updated_at) AS max,
            12
           FROM oracle_brain_state
        UNION ALL
         SELECT 'Propositions Alchimiste'::text AS text,
            max(alchimiste_crypte_propositions.proposed_at) AS max,
            12
           FROM alchimiste_crypte_propositions
        )
 SELECT source,
    maj,
    round(EXTRACT(epoch FROM now() - maj) / 3600.0, 1) AS age_h,
    seuil_h,
        CASE
            WHEN (EXTRACT(epoch FROM now() - maj) / 3600.0) > seuil_h::numeric THEN 'FIGE'::text
            ELSE 'OK'::text
        END AS statut
   FROM sources
;

-- ============================================================
-- VIEW: v_dernier_prix
-- ============================================================
CREATE OR REPLACE VIEW public.v_dernier_prix AS
 SELECT DISTINCT ON (symbol) symbol,
    replace(replace(upper(symbol), '-USD'::text, ''::text), '/USD'::text, ''::text) AS base,
    close AS prix,
    ts
   FROM price_history
  ORDER BY symbol, ts DESC
;

-- ============================================================
-- VIEW: v_equity_points
-- ============================================================
-- Reecrite le 19/08/2026 : meme correction que v_comparaison. L'echelle reste le GAIN
-- (et non l'equity) pour ne pas changer l'echelle des graphiques de la console.
CREATE OR REPLACE VIEW public.v_equity_points AS
 SELECT e.archimage AS trader,
        (e.jour + time '20:00')::timestamptz AS ts,
        (e.equity - bs.baseline_equity) AS equity
   FROM alpaca_equity_daily e
   JOIN oracle_brain_state bs ON bs.archimage = e.archimage
  WHERE bs.baseline_equity IS NOT NULL
UNION ALL
 SELECT 'ALCHIMISTE'::text, revolut_portfolio_daily.snapshot_at, revolut_portfolio_daily.total_usd
   FROM revolut_portfolio_daily
  WHERE revolut_portfolio_daily.total_usd >= 300::numeric
UNION ALL
 SELECT 'MAREES'::text, marees_virtual_trades.exit_ts,
        sum(marees_virtual_trades.pnl_pct / 100.0::double precision * marees_virtual_trades.montant) OVER (ORDER BY marees_virtual_trades.exit_ts)::numeric
   FROM marees_virtual_trades
  WHERE COALESCE(marees_virtual_trades.is_open, false) = false AND marees_virtual_trades.exit_ts IS NOT NULL
;

-- ============================================================
-- VIEW: v_gains_traders
-- ============================================================
CREATE OR REPLACE VIEW public.v_gains_traders AS
 WITH fx AS (
         SELECT price_history.close::double precision AS eurusd
           FROM price_history
          WHERE price_history.symbol = 'EUR-USD'::text AND price_history."interval" = '1h'::text
          ORDER BY price_history.ts DESC
         LIMIT 1
        ), h(horizon, cutoff) AS (
         VALUES ('jour'::text,date_trunc('day'::text, now())), ('semaine'::text,date_trunc('week'::text, now())), ('mois'::text,date_trunc('month'::text, now())), ('annee'::text,date_trunc('year'::text, now()))
        ), rp AS (
         SELECT v_rendements_periodes.serie,
            v_rendements_periodes.granularite AS horizon,
            (array_agg(v_rendements_periodes.rendement_pct ORDER BY v_rendements_periodes.periode DESC))[1]::double precision AS pct
           FROM v_rendements_periodes
          GROUP BY v_rendements_periodes.serie, v_rendements_periodes.granularite
        ), sages AS (
         SELECT bs.archimage AS serie,
            r.horizon,
            r.pct,
            bs.baseline_equity::double precision * r.pct / 100.0::double precision AS gain_usd
           FROM oracle_brain_state bs
             JOIN rp r ON r.serie = bs.archimage
          WHERE bs.archimage = ANY (ARRAY['JU'::text, 'SYL'::text, 'GIL'::text])
        ), opus AS (
         SELECT 'OPUS'::text AS serie,
            r.horizon,
            r.pct,
            ( SELECT sum(s.gain_usd) AS sum
                   FROM sages s
                  WHERE s.horizon = r.horizon) AS gain_usd
           FROM rp r
          WHERE r.serie = 'OPUS'::text
        ), av_money AS (
         SELECT h.horizon,
            sum(t.pnl_pct / 100.0::double precision * t.montant) AS gain_usd
           FROM h
             JOIN alchimiste_virtual_trades t ON COALESCE(t.is_open, false) = false AND t.exit_ts IS NOT NULL AND t.exit_ts >= h.cutoff
          GROUP BY h.horizon
        ), alcv AS (
         SELECT 'ALC_VIRT'::text AS serie,
            r.horizon,
            r.pct,
            m.gain_usd
           FROM rp r
             LEFT JOIN av_money m ON m.horizon = r.horizon
          WHERE r.serie = 'ALCHIMISTE'::text
        ), mar_money AS (
         SELECT h.horizon,
            sum(t.pnl_pct / 100.0::double precision * t.montant) AS gain_usd
           FROM h
             JOIN marees_virtual_trades t ON COALESCE(t.is_open, false) = false AND t.exit_ts IS NOT NULL AND t.exit_ts >= h.cutoff
          GROUP BY h.horizon
        ), mar AS (
         SELECT 'MAREES'::text AS serie,
            h.horizon,
            r.pct,
            m.gain_usd
           FROM h
             LEFT JOIN rp r ON r.serie = 'MAREES'::text AND r.horizon = h.horizon
             LEFT JOIN mar_money m ON m.horizon = h.horizon
        ), rp_cur AS (
         SELECT revolut_portfolio_daily.total_usd::double precision AS v
           FROM revolut_portfolio_daily
          ORDER BY revolut_portfolio_daily.snapshot_at DESC
         LIMIT 1
        ), rp_first AS (
         SELECT revolut_portfolio_daily.total_usd::double precision AS v
           FROM revolut_portfolio_daily
          ORDER BY revolut_portfolio_daily.snapshot_at
         LIMIT 1
        ), alcr AS (
         SELECT 'ALC_REEL'::text AS serie,
            h.horizon,
            COALESCE(( SELECT revolut_portfolio_daily.total_usd::double precision AS total_usd
                   FROM revolut_portfolio_daily
                  WHERE revolut_portfolio_daily.snapshot_at < h.cutoff
                  ORDER BY revolut_portfolio_daily.snapshot_at DESC
                 LIMIT 1), ( SELECT rp_first.v
                   FROM rp_first)) AS base,
            ( SELECT rp_cur.v
                   FROM rp_cur) AS cur
           FROM h
        ), alcr2 AS (
         SELECT alcr.serie,
            alcr.horizon,
                CASE
                    WHEN alcr.base <> 0::double precision THEN (alcr.cur - alcr.base) / alcr.base * 100::double precision
                    ELSE NULL::double precision
                END AS pct,
            alcr.cur - alcr.base AS gain_usd
           FROM alcr
        ), allrows AS (
         SELECT sages.serie,
            sages.horizon,
            sages.pct,
            sages.gain_usd
           FROM sages
        UNION ALL
         SELECT opus.serie,
            opus.horizon,
            opus.pct,
            opus.gain_usd
           FROM opus
        UNION ALL
         SELECT alcv.serie,
            alcv.horizon,
            alcv.pct,
            alcv.gain_usd
           FROM alcv
        UNION ALL
         SELECT mar.serie,
            mar.horizon,
            mar.pct,
            mar.gain_usd
           FROM mar
        UNION ALL
         SELECT alcr2.serie,
            alcr2.horizon,
            alcr2.pct,
            alcr2.gain_usd
           FROM alcr2
        )
 SELECT serie,
        CASE serie
            WHEN 'OPUS'::text THEN 'AETHER (ensemble)'::text
            WHEN 'ALC_REEL'::text THEN 'Alchimiste — réel'::text
            WHEN 'ALC_VIRT'::text THEN 'Alchimiste — virtuel'::text
            WHEN 'JU'::text THEN 'JU — Actions US'::text
            WHEN 'SYL'::text THEN 'SYL — Macro internationale'::text
            WHEN 'GIL'::text THEN 'GIL — Crypto tactique'::text
            WHEN 'MAREES'::text THEN 'Marées — Devises'::text
            ELSE NULL::text
        END AS label,
        CASE serie
            WHEN 'OPUS'::text THEN 1
            WHEN 'ALC_REEL'::text THEN 2
            WHEN 'ALC_VIRT'::text THEN 3
            WHEN 'JU'::text THEN 4
            WHEN 'SYL'::text THEN 5
            WHEN 'GIL'::text THEN 6
            WHEN 'MAREES'::text THEN 7
            ELSE NULL::integer
        END AS ordre,
    horizon,
    round(pct::numeric, 2) AS gain_pct,
    round(gain_usd::numeric, 2) AS gain_usd,
    round((gain_usd / NULLIF(( SELECT fx.eurusd
           FROM fx), 0::double precision))::numeric, 2) AS gain_eur
   FROM allrows a
;

-- ============================================================
-- VIEW: v_oracle_performance
-- ============================================================
CREATE OR REPLACE VIEW public.v_oracle_performance AS
 SELECT b.archimage,
    b.baseline_equity AS baseline,
    b.cumulative_pnl AS pnl,
    round(b.cumulative_pnl / NULLIF(b.baseline_equity, 0::numeric) * 100::numeric, 4) AS pnl_pct,
    b.total_runs,
    b.wins,
    b.losses,
    b.win_rate,
    b.max_drawdown,
    b.synthesis_weight AS weight,
    COALESCE(o.orders, 0::bigint) AS orders_total,
    COALESCE(o.notional, 0::numeric) AS notional_total,
    b.last_run_at
   FROM oracle_brain_state b
     LEFT JOIN ( SELECT oracle_college_orders.archimage,
            count(*) AS orders,
            sum(oracle_college_orders.notional) AS notional
           FROM oracle_college_orders
          GROUP BY oracle_college_orders.archimage) o ON o.archimage = b.archimage
  WHERE b.archimage <> 'cerveau'::text
  ORDER BY b.cumulative_pnl DESC
;

-- ============================================================
-- VIEW: v_oracle_stats
-- ============================================================
CREATE OR REPLACE VIEW public.v_oracle_stats AS
 SELECT count(*) AS total_runs,
    count(*) FILTER (WHERE market_phase = 'Normal'::text) AS runs_normal,
    count(*) FILTER (WHERE market_phase = 'Prudence'::text) AS runs_prudence,
    count(*) FILTER (WHERE market_phase = 'Stress'::text) AS runs_stress,
    count(*) FILTER (WHERE market_phase = 'Crise'::text) AS runs_crise,
    avg(risk_score) AS avg_risk_score,
    avg(confidence) AS avg_confidence,
    avg(data_completeness) AS avg_data_quality,
    max(created_at) AS last_run
   FROM oracle_runs
;

-- ============================================================
-- VIEW: v_perf_avancee
-- ============================================================
CREATE OR REPLACE VIEW public.v_perf_avancee AS
 WITH r AS (
         SELECT v_comparaison.serie,
            v_comparaison.jour,
            v_comparaison.ret,
            v_comparaison.ret - lag(v_comparaison.ret) OVER (PARTITION BY v_comparaison.serie ORDER BY v_comparaison.jour) AS dr
           FROM v_comparaison
        ), vol AS (
         SELECT r.serie,
            round((stddev_samp(r.dr)::double precision * sqrt(252::double precision))::numeric, 2) AS volatilite,
            round(((avg(r.dr) / NULLIF(sqrt(avg(
                CASE
                    WHEN r.dr < 0::numeric THEN r.dr * r.dr
                    ELSE 0::numeric
                END)), 0::numeric))::double precision * sqrt(252::double precision))::numeric, 2) AS sortino
           FROM r
          WHERE r.dr IS NOT NULL
          GROUP BY r.serie
        ), ddv AS (
         SELECT z.serie,
            max(z.peak - z.ret) AS maxdd
           FROM ( SELECT v_comparaison.serie,
                    v_comparaison.ret,
                    max(v_comparaison.ret) OVER (PARTITION BY v_comparaison.serie ORDER BY v_comparaison.jour) AS peak
                   FROM v_comparaison) z
          GROUP BY z.serie
        ), fin AS (
         SELECT v_comparaison.serie,
            (array_agg(v_comparaison.ret ORDER BY v_comparaison.jour DESC))[1] AS ret_final
           FROM v_comparaison
          GROUP BY v_comparaison.serie
        ), mm AS (
         SELECT v_rendements_mensuels.serie,
            round(max(v_rendements_mensuels.rendement_pct), 2) AS meilleur_mois,
            round(min(v_rendements_mensuels.rendement_pct), 2) AS pire_mois,
            round(count(*) FILTER (WHERE v_rendements_mensuels.rendement_pct > 0::numeric)::numeric / NULLIF(count(*), 0)::numeric * 100::numeric, 0) AS pct_mois_positifs
           FROM v_rendements_mensuels
          GROUP BY v_rendements_mensuels.serie
        )
 SELECT v.serie,
    v.volatilite,
    v.sortino,
    round(f.ret_final / NULLIF(d.maxdd, 0::numeric), 2) AS calmar,
    round(d.maxdd, 2) AS drawdown_max,
    m.meilleur_mois,
    m.pire_mois,
    m.pct_mois_positifs
   FROM vol v
     LEFT JOIN ddv d USING (serie)
     LEFT JOIN fin f USING (serie)
     LEFT JOIN mm m USING (serie)
;

-- ============================================================
-- VIEW: v_perf_resume
-- ============================================================
CREATE OR REPLACE VIEW public.v_perf_resume AS
 SELECT oracle_brain_state.archimage AS trader,
    round(oracle_brain_state.cumulative_pnl / NULLIF(oracle_brain_state.baseline_equity, 0::numeric) * 100::numeric, 2) AS rendement_pct,
    round(oracle_brain_state.max_drawdown * 100::numeric, 2) AS drawdown_max_pct,
    round(oracle_brain_state.win_rate * 100::numeric, 1) AS reussite_pct,
    'simulation'::text AS statut,
    'juin–août 2026'::text AS periode
   FROM oracle_brain_state
  WHERE oracle_brain_state.archimage = ANY (ARRAY['JU'::text, 'SYL'::text, 'GIL'::text])
UNION ALL
 SELECT 'ALCHIMISTE'::text AS trader,
    NULL::numeric AS rendement_pct,
    NULL::numeric AS drawdown_max_pct,
    48.5 AS reussite_pct,
    'reel_imminent'::text AS statut,
    'validation'::text AS periode
UNION ALL
 SELECT 'MAREES'::text AS trader,
    NULL::numeric AS rendement_pct,
    NULL::numeric AS drawdown_max_pct,
    NULL::numeric AS reussite_pct,
    'validation_precoce'::text AS statut,
    'depuis juil.'::text AS periode
;

-- ============================================================
-- VIEW: v_portfolio_open
-- ============================================================
CREATE OR REPLACE VIEW public.v_portfolio_open AS
 SELECT pv.ticker,
    pv.asset_name,
    pv.layer,
    pv.entry_date,
    pv.entry_price,
    pv.current_price,
    pv.invested_amount,
    pv.current_value,
    pv.unrealized_pnl,
    pv.unrealized_pnl_pct,
    pv.is_paper_trade,
    r.market_phase AS entry_phase,
    r.master_word AS entry_word
   FROM portfolio_virtual pv
     LEFT JOIN oracle_runs r ON pv.entry_run_id = r.run_id
  WHERE pv.status = 'OPEN'::text
  ORDER BY pv.unrealized_pnl_pct DESC
;

-- ============================================================
-- VIEW: v_rapport_mensuel_virtuels
-- ============================================================
CREATE OR REPLACE VIEW public.v_rapport_mensuel_virtuels AS
 WITH t AS (
         SELECT 'ALCHIMISTE'::text AS trader,
            'CRYPTO_REVOLUT_X'::text AS univers,
            alchimiste_virtual_trades.opened_at,
            alchimiste_virtual_trades.montant,
            alchimiste_virtual_trades.pnl_pct,
            alchimiste_virtual_trades.is_open
           FROM alchimiste_virtual_trades
        UNION ALL
         SELECT 'MAREES'::text,
            'FOREX_MAJORS'::text,
            marees_virtual_trades.opened_at,
            marees_virtual_trades.montant,
            marees_virtual_trades.pnl_pct,
            marees_virtual_trades.is_open
           FROM marees_virtual_trades
        )
 SELECT trader,
    univers,
    to_char(date_trunc('month'::text, opened_at), 'YYYY-MM'::text) AS mois,
    count(*) FILTER (WHERE NOT is_open) AS trades,
    count(*) FILTER (WHERE NOT is_open AND pnl_pct > 0::double precision) AS gagnants,
    round(count(*) FILTER (WHERE NOT is_open AND pnl_pct > 0::double precision)::numeric / NULLIF(count(*) FILTER (WHERE NOT is_open), 0)::numeric * 100::numeric, 1) AS wr_pct,
    round(avg(pnl_pct) FILTER (WHERE NOT is_open)::numeric, 3) AS esperance_pct,
    round(sum(pnl_pct / 100.0::double precision * montant) FILTER (WHERE NOT is_open)::numeric, 2) AS pnl_realise_usd,
    count(*) FILTER (WHERE is_open) AS encore_ouverts
   FROM t
  GROUP BY trader, univers, (date_trunc('month'::text, opened_at))
;

-- ============================================================
-- VIEW: v_rapport_periodes
-- ============================================================
CREATE OR REPLACE VIEW public.v_rapport_periodes AS
 WITH t AS (
         SELECT 'ALCHIMISTE'::text AS trader,
            alchimiste_virtual_trades.opened_at,
            alchimiste_virtual_trades.montant,
            alchimiste_virtual_trades.pnl_pct,
            alchimiste_virtual_trades.is_open
           FROM alchimiste_virtual_trades
        UNION ALL
         SELECT 'MAREES'::text,
            marees_virtual_trades.opened_at,
            marees_virtual_trades.montant,
            marees_virtual_trades.pnl_pct,
            marees_virtual_trades.is_open
           FROM marees_virtual_trades
        ), g AS (
         SELECT t.trader,
            gran.gran,
                CASE gran.gran
                    WHEN 'jour'::text THEN to_char(date_trunc('day'::text, t.opened_at), 'YYYY-MM-DD'::text)
                    WHEN 'semaine'::text THEN to_char(date_trunc('week'::text, t.opened_at), 'IYYY-"S"IW'::text)
                    WHEN 'mois'::text THEN to_char(date_trunc('month'::text, t.opened_at), 'YYYY-MM'::text)
                    ELSE to_char(date_trunc('year'::text, t.opened_at), 'YYYY'::text)
                END AS periode,
            t.montant,
            t.pnl_pct,
            t.is_open
           FROM t,
            unnest(ARRAY['jour'::text, 'semaine'::text, 'mois'::text, 'annee'::text]) gran(gran)
        )
 SELECT trader,
    gran AS granularite,
    periode,
    count(*) FILTER (WHERE NOT is_open) AS trades,
    round(count(*) FILTER (WHERE NOT is_open AND pnl_pct > 0::double precision)::numeric / NULLIF(count(*) FILTER (WHERE NOT is_open), 0)::numeric * 100::numeric, 1) AS wr_pct,
    round(avg(pnl_pct) FILTER (WHERE NOT is_open)::numeric, 3) AS esperance_pct,
    round(sum(pnl_pct / 100.0::double precision * montant) FILTER (WHERE NOT is_open)::numeric, 2) AS pnl_realise_usd,
    count(*) FILTER (WHERE is_open) AS encore_ouverts
   FROM g
  GROUP BY trader, gran, periode
;

-- ============================================================
-- VIEW: v_recent_performance
-- ============================================================
CREATE OR REPLACE VIEW public.v_recent_performance AS
 SELECT r.run_id,
    r.run_at,
    r.market_phase,
    r.risk_score,
    r.confidence,
    r.master_word,
    r.allocation_cash,
    r.allocation_defensive,
    r.allocation_risk,
    r.spy_price,
    r.vix_value,
    lf.spy_performance_7d,
    lf.spy_performance_30d,
    lf.phase_correct,
    lf.accuracy_score
   FROM oracle_runs r
     LEFT JOIN learning_feedback lf ON r.run_id = lf.run_id
  ORDER BY r.created_at DESC
 LIMIT 30
;

-- ============================================================
-- VIEW: v_rendements_mensuels
-- ============================================================
CREATE OR REPLACE VIEW public.v_rendements_mensuels AS
 WITH me AS (
         SELECT v_comparaison.serie,
            date_trunc('month'::text, v_comparaison.jour::timestamp with time zone)::date AS mois,
            (array_agg(v_comparaison.ret ORDER BY v_comparaison.jour DESC))[1] AS end_ret
           FROM v_comparaison
          GROUP BY v_comparaison.serie, (date_trunc('month'::text, v_comparaison.jour::timestamp with time zone))
        )
 SELECT serie,
    to_char(mois::timestamp with time zone, 'YYYY-MM'::text) AS mois,
    round(end_ret - COALESCE(lag(end_ret) OVER (PARTITION BY serie ORDER BY me.mois), 0::numeric), 2) AS rendement_pct
   FROM me
;

-- ============================================================
-- VIEW: v_rendements_periodes
-- ============================================================
CREATE OR REPLACE VIEW public.v_rendements_periodes AS
 WITH g AS (
         SELECT v_comparaison.serie,
            gran.gran,
                CASE gran.gran
                    WHEN 'jour'::text THEN to_char(v_comparaison.jour::timestamp with time zone, 'YYYY-MM-DD'::text)
                    WHEN 'semaine'::text THEN to_char(date_trunc('week'::text, v_comparaison.jour::timestamp with time zone), 'IYYY-"S"IW'::text)
                    WHEN 'mois'::text THEN to_char(date_trunc('month'::text, v_comparaison.jour::timestamp with time zone), 'YYYY-MM'::text)
                    ELSE to_char(date_trunc('year'::text, v_comparaison.jour::timestamp with time zone), 'YYYY'::text)
                END AS periode,
            date_trunc(
                CASE gran.gran
                    WHEN 'jour'::text THEN 'day'::text
                    WHEN 'semaine'::text THEN 'week'::text
                    WHEN 'mois'::text THEN 'month'::text
                    ELSE 'year'::text
                END, v_comparaison.jour::timestamp with time zone) AS bucket,
            v_comparaison.jour,
            v_comparaison.ret
           FROM v_comparaison,
            unnest(ARRAY['jour'::text, 'semaine'::text, 'mois'::text, 'annee'::text]) gran(gran)
        ), ends AS (
         SELECT g.serie,
            g.gran,
            g.periode,
            g.bucket,
            (array_agg(g.ret ORDER BY g.jour DESC))[1] AS end_ret
           FROM g
          GROUP BY g.serie, g.gran, g.periode, g.bucket
        )
 SELECT serie,
    gran AS granularite,
    periode,
    round(end_ret - COALESCE(lag(end_ret) OVER (PARTITION BY serie, gran ORDER BY bucket), 0::numeric), 2) AS rendement_pct
   FROM ends
;

-- ============================================================
-- VIEW: v_sharpe
-- ============================================================
CREATE OR REPLACE VIEW public.v_sharpe AS
 WITH r AS (
         SELECT v_comparaison.serie,
            v_comparaison.jour,
            v_comparaison.ret,
            v_comparaison.ret - lag(v_comparaison.ret) OVER (PARTITION BY v_comparaison.serie ORDER BY v_comparaison.jour) AS dr
           FROM v_comparaison
        )
 SELECT serie,
    round(((avg(dr) / NULLIF(stddev_samp(dr), 0::numeric))::double precision * sqrt(252::double precision))::numeric, 2) AS sharpe
   FROM r
  WHERE dr IS NOT NULL
  GROUP BY serie
;

-- ============================================================
-- VIEW: v_staking_point
-- ============================================================
CREATE OR REPLACE VIEW public.v_staking_point AS
 WITH lot_usd AS (
         SELECT l.devise,
            sum(l.qty) AS principal_qty,
            sum(
                CASE l.devise_cout
                    WHEN 'USDT'::text THEN l.cout_gbp
                    WHEN 'USD'::text THEN l.cout_gbp
                    WHEN 'GBP'::text THEN l.cout_gbp * (( SELECT p.close
                       FROM price_history p
                      WHERE p.symbol = 'GBP-USD'::text AND p.ts::date <= l.date_achat
                      ORDER BY p.ts DESC
                     LIMIT 1))
                    WHEN 'EUR'::text THEN l.cout_gbp * (( SELECT p.close
                       FROM price_history p
                      WHERE p.symbol = 'EUR-USD'::text AND p.ts::date <= l.date_achat
                      ORDER BY p.ts DESC
                     LIMIT 1))
                    ELSE l.cout_gbp
                END) AS invest_usd
           FROM alc_staking_lots l
          GROUP BY l.devise
        ), snap AS (
         SELECT upper(d_1.value ->> 'devise'::text) AS dev,
            (d_1.value ->> 'stake'::text)::numeric AS stake_qty,
            (d_1.value ->> 'valeur_usd'::text)::numeric AS val_snap
           FROM ( SELECT revolut_portfolio_daily.detail
                   FROM revolut_portfolio_daily
                  ORDER BY revolut_portfolio_daily.snapshot_at DESC
                 LIMIT 1) s,
            LATERAL jsonb_array_elements(s.detail) d_1(value)
          WHERE ((d_1.value ->> 'stake'::text)::numeric) > 0::numeric
        ), px AS (
         SELECT replace(price_history.symbol, '-USD'::text, ''::text) AS dev,
            (array_agg(price_history.close ORDER BY price_history.ts DESC))[1] AS p
           FROM price_history
          WHERE price_history.symbol ~~ '%-USD'::text
          GROUP BY price_history.symbol
        )
 SELECT sn.dev AS devise,
    sn.stake_qty,
    lu.principal_qty,
    round(lu.invest_usd, 2) AS invest_usd,
    round(sn.stake_qty * COALESCE(px.p, sn.val_snap / NULLIF(sn.stake_qty, 0::numeric)), 2) AS valeur_live,
    round(sn.stake_qty * COALESCE(px.p, sn.val_snap / NULLIF(sn.stake_qty, 0::numeric)) - lu.invest_usd, 2) AS pnl_usd,
    round((sn.stake_qty * COALESCE(px.p, sn.val_snap / NULLIF(sn.stake_qty, 0::numeric)) - lu.invest_usd) / NULLIF(lu.invest_usd, 0::numeric) * 100::numeric, 1) AS pnl_pct,
    round(sn.stake_qty - COALESCE(lu.principal_qty, sn.stake_qty), 8) AS gain_staking_qty,
    a.apy_pct,
    d.unbonding_jours::text AS unbonding_jours,
    round(sn.stake_qty * COALESCE(px.p, sn.val_snap / NULLIF(sn.stake_qty, 0::numeric)) * a.apy_pct / 100::numeric * d.unbonding_jours / 365::numeric, 3) AS cout_destaking_usd
   FROM snap sn
     LEFT JOIN lot_usd lu ON lu.devise = sn.dev
     LEFT JOIN px ON px.dev = sn.dev
     LEFT JOIN alc_staking_apy a ON upper(a.devise) = sn.dev
     LEFT JOIN alc_staking_delais d ON upper(d.devise) = sn.dev
;

-- ============================================================
-- VIEW: v_stats_indice
-- ============================================================
CREATE OR REPLACE VIEW public.v_stats_indice AS
 WITH r AS (
         SELECT v_comparaison.serie,
            v_comparaison.jour,
            v_comparaison.ret - lag(v_comparaison.ret) OVER (PARTITION BY v_comparaison.serie ORDER BY v_comparaison.jour) AS dr
           FROM v_comparaison
        ), spy AS (
         SELECT r.jour,
            r.dr AS spy_dr
           FROM r
          WHERE r.serie = 'SPY'::text
        ), j AS (
         SELECT r.serie,
            r.dr,
            s.spy_dr
           FROM r
             JOIN spy s ON s.jour = r.jour
          WHERE r.dr IS NOT NULL AND s.spy_dr IS NOT NULL AND r.serie <> 'SPY'::text
        )
 SELECT serie,
    round(corr(dr::double precision, spy_dr::double precision)::numeric, 2) AS correlation,
    round(regr_slope(dr::double precision, spy_dr::double precision)::numeric, 2) AS beta,
    round((regr_intercept(dr::double precision, spy_dr::double precision) * 252::double precision)::numeric, 2) AS alpha_annualise
   FROM j
  GROUP BY serie
;

-- ============================================================
-- VIEW: v_world_context
-- ============================================================
CREATE OR REPLACE VIEW public.v_world_context AS
 WITH syms(symbol, nom, classe) AS (
         VALUES ('SPY'::text,'S&P 500'::text,'actions'::text), ('QQQ'::text,'Nasdaq 100'::text,'actions'::text), ('DIA'::text,'Dow Jones'::text,'actions'::text), ('IWM'::text,'Russell 2000'::text,'actions'::text), ('URTH'::text,'MSCI World'::text,'actions'::text), ('EEM'::text,'Emergents'::text,'actions'::text), ('EFA'::text,'Developpes hors-US'::text,'actions'::text), ('FEZ'::text,'Euro Stoxx 50'::text,'actions'::text), ('EWQ'::text,'France CAC'::text,'actions'::text), ('GLD'::text,'Or'::text,'matieres'::text), ('SLV'::text,'Argent'::text,'matieres'::text), ('USO'::text,'Petrole'::text,'matieres'::text), ('BTC-USD'::text,'Bitcoin'::text,'crypto'::text), ('ETH-USD'::text,'Ethereum'::text,'crypto'::text), ('SOL-USD'::text,'Solana'::text,'crypto'::text)
        ), lt AS (
         SELECT s.symbol,
            s.nom,
            s.classe,
            ( SELECT max(p.ts) AS max
                   FROM price_history p
                  WHERE p.symbol = s.symbol AND p."interval" = '1h'::text) AS mx
           FROM syms s
        ), base AS (
         SELECT l.symbol,
            l.nom,
            l.classe,
            ( SELECT p.close
                   FROM price_history p
                  WHERE p.symbol = l.symbol AND p."interval" = '1h'::text
                  ORDER BY p.ts DESC
                 LIMIT 1) AS c0,
            ( SELECT p.close
                   FROM price_history p
                  WHERE p.symbol = l.symbol AND p."interval" = '1h'::text AND p.ts <= (l.mx - '24:00:00'::interval)
                  ORDER BY p.ts DESC
                 LIMIT 1) AS c24,
            ( SELECT p.close
                   FROM price_history p
                  WHERE p.symbol = l.symbol AND p."interval" = '1h'::text AND p.ts <= (l.mx - '7 days'::interval)
                  ORDER BY p.ts DESC
                 LIMIT 1) AS c7
           FROM lt l
        ), calc AS (
         SELECT base.symbol,
            base.nom,
            base.classe,
            round(base.c0, 2) AS prix,
            round((base.c0 / NULLIF(base.c24, 0::numeric) - 1::numeric) * 100::numeric, 2) AS var_24h,
            round((base.c0 / NULLIF(base.c7, 0::numeric) - 1::numeric) * 100::numeric, 2) AS var_7j
           FROM base
        ), reg AS (
         SELECT count(*) FILTER (WHERE calc.classe = 'actions'::text AND calc.var_7j > 0::numeric) AS up_eq,
            count(*) FILTER (WHERE calc.classe = 'actions'::text AND calc.var_7j IS NOT NULL) AS tot_eq
           FROM calc
        )
 SELECT jsonb_build_object('maj', now(), 'regime',
        CASE
            WHEN (( SELECT reg.up_eq::double precision / NULLIF(reg.tot_eq, 0)::double precision
               FROM reg)) >= 0.6::double precision THEN 'risk_on'::text
            WHEN (( SELECT reg.up_eq::double precision / NULLIF(reg.tot_eq, 0)::double precision
               FROM reg)) <= 0.4::double precision THEN 'risk_off'::text
            ELSE 'neutre'::text
        END, 'indices', ( SELECT jsonb_agg(jsonb_build_object('nom', calc.nom, 'classe', calc.classe, 'prix', calc.prix, 'var_24h', calc.var_24h, 'var_7j', calc.var_7j) ORDER BY calc.var_7j DESC NULLS LAST) AS jsonb_agg
           FROM calc), 'meilleur', ( SELECT ((calc.nom || ' ('::text) || COALESCE(calc.var_7j::text, '?'::text)) || '% / 7j)'::text
           FROM calc
          WHERE calc.var_7j IS NOT NULL
          ORDER BY calc.var_7j DESC
         LIMIT 1), 'pire', ( SELECT ((calc.nom || ' ('::text) || COALESCE(calc.var_7j::text, '?'::text)) || '% / 7j)'::text
           FROM calc
          WHERE calc.var_7j IS NOT NULL
          ORDER BY calc.var_7j
         LIMIT 1), 'resume', ('Contexte marches mondiaux (7 jours) - regime '::text ||
        CASE
            WHEN (( SELECT reg.up_eq::double precision / NULLIF(reg.tot_eq, 0)::double precision
               FROM reg)) >= 0.6::double precision THEN 'RISK-ON (bourses majoritairement en hausse)'::text
            WHEN (( SELECT reg.up_eq::double precision / NULLIF(reg.tot_eq, 0)::double precision
               FROM reg)) <= 0.4::double precision THEN 'RISK-OFF (bourses majoritairement en baisse)'::text
            ELSE 'NEUTRE'::text
        END) || '. Utilise-le pour ajuster ta prudence : en risk-off reduis l''exposition, en risk-on ose davantage. Croise avec ton propre marche, ne copie pas aveuglement.'::text) AS contexte_mondial
;

-- ============================================================================
-- [19/08/2026] STAKING DE L'ALCHIMISTE — séparateur « ; » et source unique
-- ----------------------------------------------------------------------------
-- Le message envoyé au module 10012 (L'Alchimiste) sépare ses champs par « | ».
-- Les vues ci-dessous utilisaient elles aussi « | » en interne : tant que la valeur
-- était encodée en Base64 c'était sans effet, mais dès le passage en texte brut
-- (19/08 10:50) les barres se sont confondues avec les séparateurs de champs.
-- Le modèle a perdu les délais (« sans information sur le délai de déblocage »)
-- puis les montants (0 partout au run de 11:11). D'où le séparateur « ; ».
--
-- v_alc_staking_txt : source UNIQUE et complète (montant réel, APY, délai, coût).
-- Motif : le modèle devait croiser 3 sources et extrayait le montant d'un gros bloc
-- de texte — il l'inventait (TON 787 $ au run de 10:28 alors que le vrai montant
-- staké est 7,91 $, et que TOUT le staking vaut 169 $).
-- ============================================================================

CREATE OR REPLACE VIEW public.v_alc_staking_delais_txt AS
 SELECT COALESCE(string_agg(devise || ':' || unbonding_jours || 'j', ' ; ' ORDER BY devise), '') AS delais_texte
   FROM v_staking_point
  WHERE unbonding_jours IS NOT NULL;

CREATE OR REPLACE VIEW public.v_alc_staking_apy_txt AS
 SELECT COALESCE(string_agg(devise || ':' || apy_pct || '%', ' ; ' ORDER BY devise), '') AS apy_texte
   FROM v_staking_point
  WHERE apy_pct IS NOT NULL;

-- v_alc_staking_txt — VERSION RAPIDE (la 1re version mettait 11 s et renvoyait HTTP 500
-- « statement timeout » via l'API : elle lisait v_staking_point, qui rescanne 467 000 lignes de
-- price_history pour recalculer le dernier prix de chaque symbole. Mesuré, pas supposé.)
-- Ici : lecture du seul dernier snapshot Revolut X + les 2 tables de référence staking.
-- Mesures : 13 ms d'exécution, HTTP 200 vérifié avec les en-têtes exacts du module 20022.
-- Total des 7 lignes = 150,99 $ contre 150,98 $ déclarés par Revolut (stake_usd) : écart 1 centime.
CREATE OR REPLACE VIEW public.v_alc_staking_txt AS
WITH snap AS (
  SELECT detail, snapshot_at
    FROM revolut_portfolio_daily
   ORDER BY snapshot_at DESC
   LIMIT 1
), lignes AS (
  SELECT upper(e.value->>'devise')                      AS devise,
         COALESCE((e.value->>'stake')::numeric, 0)      AS stake_qty,
         COALESCE((e.value->>'qty')::numeric, 0)        AS qty_totale,
         COALESCE((e.value->>'valeur_usd')::numeric, 0) AS valeur_totale_usd
    FROM snap, jsonb_array_elements(snap.detail) e
   WHERE COALESCE((e.value->>'stake')::numeric, 0) > 0
)
SELECT COALESCE(
  string_agg(
    l.devise
    || ' montant=' || round(CASE WHEN l.qty_totale > 0
                                 THEN l.valeur_totale_usd * (l.stake_qty / l.qty_totale)
                                 ELSE 0 END, 2) || 'USD'
    || ' apy=' || COALESCE(round(a.apy_pct, 2)::text, 'inconnu') || '%'
    || ' deblocage=' || COALESCE(d.unbonding_jours::text, 'inconnu') || 'jours',
    ' ; ' ORDER BY l.valeur_totale_usd * (CASE WHEN l.qty_totale > 0 THEN l.stake_qty / l.qty_totale ELSE 0 END) DESC),
  'aucune ligne stakee') AS staking_texte
  FROM lignes l
  LEFT JOIN alc_staking_apy    a ON upper(a.devise) = l.devise
  LEFT JOIN alc_staking_delais d ON upper(d.devise) = l.devise;


-- ============================================================
-- VIEW: v_exposition_traders   (ajoutee le 19/08/2026)
-- ============================================================
-- La console additionnait les market_value : les ventes a decouvert etant negatives,
-- elles annulaient les achats et le risque reel n'apparaissait pas. Au 19/08/2026,
-- SYL portait 3,1 M$ de ventes a decouvert obligataires pour 1,05 M$ de capital.
CREATE OR REPLACE VIEW public.v_exposition_traders AS
WITH p AS (
  SELECT archimage,
         sum(market_value) FILTER (WHERE market_value > 0) AS longs,
         sum(market_value) FILTER (WHERE market_value < 0) AS shorts,
         sum(abs(market_value))                            AS brute,
         sum(market_value)                                 AS nette,
         count(*) FILTER (WHERE market_value < 0 AND abs(qty) > 1e-6) AS nb_shorts,
         count(*) FILTER (WHERE market_value > 0 AND abs(qty) > 1e-6) AS nb_longs
    FROM oracle_positions_live
   GROUP BY archimage
)
SELECT b.archimage,
       round(b.alpaca_portfolio_value, 0)               AS capital,
       round(COALESCE(p.longs, 0), 0)                   AS achats,
       round(COALESCE(p.shorts, 0), 0)                  AS ventes_a_decouvert,
       round(COALESCE(p.brute, 0), 0)                   AS exposition_brute,
       round(COALESCE(p.nette, 0), 0)                   AS exposition_nette,
       round(COALESCE(p.brute, 0) / NULLIF(b.alpaca_portfolio_value, 0), 2) AS levier,
       COALESCE(p.nb_longs, 0)                          AS nb_positions_achat,
       COALESCE(p.nb_shorts, 0)                         AS nb_positions_decouvert,
       CASE
         WHEN COALESCE(p.brute,0) / NULLIF(b.alpaca_portfolio_value,0) >= 3 THEN 'ELEVE'
         WHEN COALESCE(p.brute,0) / NULLIF(b.alpaca_portfolio_value,0) >= 2 THEN 'MOYEN'
         ELSE 'MODERE'
       END                                              AS niveau_levier,
       b.alpaca_last_synced                             AS synchronise_le
  FROM oracle_brain_state b
  LEFT JOIN p ON p.archimage = b.archimage
 WHERE b.alpaca_portfolio_value > 0
;

-- ============================================================
-- VIEW: v_perf_anomalies   (ajoutee le 19/08/2026)
-- ============================================================
-- Garde-fou : liste les mesures de oracle_performance qui contredisent la cloture Alpaca
-- de plus de 5 % du capital. Aucune exclusion automatique -- a examiner puis marquer
-- fiable = false si confirme.
CREATE OR REPLACE VIEW public.v_perf_anomalies AS
 SELECT p.archimage,
        (p.evaluated_at AT TIME ZONE 'UTC') AS mesure_le,
        round(bs.baseline_equity + p.actual_pnl, 0) AS equity_mesuree,
        round(e.equity, 0) AS equity_alpaca,
        round(bs.baseline_equity + p.actual_pnl - e.equity, 0) AS ecart_usd,
        round(100 * abs(bs.baseline_equity + p.actual_pnl - e.equity) / NULLIF(bs.baseline_equity, 0), 2) AS ecart_pct_capital,
        p.fiable,
        p.notes
   FROM oracle_performance p
   JOIN oracle_brain_state bs ON bs.archimage = p.archimage AND bs.baseline_equity IS NOT NULL
   JOIN alpaca_equity_daily e ON e.archimage = p.archimage AND e.jour = (p.evaluated_at AT TIME ZONE 'UTC')::date
  WHERE abs(bs.baseline_equity + p.actual_pnl - e.equity) > 0.05 * bs.baseline_equity
;
