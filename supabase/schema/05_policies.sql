-- ============================================================
-- RLS POLICIES (public schema) -- INFORMATIONAL EXPORT
-- Project smddzybxebwhfnitxuyp, as of 2026-08-14
-- ============================================================

-- Tables with RLS ENABLED:
--   _ju_brain_backup
--   alc_bt_coins
--   alc_staking_delais
--   alchimiste_crypte_propositions
--   alchimiste_virtual_trades
--   alpaca_orders
--   app_users
--   asset_universe
--   fonds_config
--   fonds_versements
--   ju_crypte_config
--   ju_crypte_orders
--   learning_feedback
--   marees_config
--   marees_positions
--   marees_propositions
--   marees_virtual_trades
--   market_data_cache
--   market_signals
--   oracle_backtest_cache
--   oracle_brain_state
--   oracle_circuit_breakers
--   oracle_college_orders
--   oracle_college_runs
--   oracle_contexte
--   oracle_datasource_health
--   oracle_exec_debug
--   oracle_flash_intel
--   oracle_journal
--   oracle_kelly_sizing
--   oracle_leads
--   oracle_logs
--   oracle_market_cache
--   oracle_performance
--   oracle_positions_live
--   oracle_problemes
--   oracle_runs
--   oracle_sages_report
--   oracle_visionary_signals
--   portfolio_virtual
--   positions_recommended
--   price_history
--   revolut_portfolio_daily
--   revolut_univers_complet
--   world_regime_journal

-- ------------------------------------------------------------
-- POLICY: anon_select_alpaca_orders
--   table:      public.alpaca_orders
--   command:    SELECT
--   roles:      {anon}
--   USING:      true
--   WITH CHECK: None

-- ------------------------------------------------------------
-- POLICY: anon_select_app_users
--   table:      public.app_users
--   command:    SELECT
--   roles:      {anon}
--   USING:      true
--   WITH CHECK: None

-- ------------------------------------------------------------
-- POLICY: anon_select_asset_universe
--   table:      public.asset_universe
--   command:    SELECT
--   roles:      {anon}
--   USING:      true
--   WITH CHECK: None

-- ------------------------------------------------------------
-- POLICY: anon_select_learning_feedback
--   table:      public.learning_feedback
--   command:    SELECT
--   roles:      {anon}
--   USING:      true
--   WITH CHECK: None

-- ------------------------------------------------------------
-- POLICY: anon_select_market_data_cache
--   table:      public.market_data_cache
--   command:    SELECT
--   roles:      {public}
--   USING:      true
--   WITH CHECK: None

-- ------------------------------------------------------------
-- POLICY: anon_select_market_signals
--   table:      public.market_signals
--   command:    SELECT
--   roles:      {anon}
--   USING:      true
--   WITH CHECK: None

-- ------------------------------------------------------------
-- POLICY: anon_select_oracle_brain_state
--   table:      public.oracle_brain_state
--   command:    SELECT
--   roles:      {anon}
--   USING:      true
--   WITH CHECK: None

-- ------------------------------------------------------------
-- POLICY: service_select_oracle_brain_state
--   table:      public.oracle_brain_state
--   command:    ALL
--   roles:      {service_role}
--   USING:      true
--   WITH CHECK: true

-- ------------------------------------------------------------
-- POLICY: Anon read circuit_breakers
--   table:      public.oracle_circuit_breakers
--   command:    SELECT
--   roles:      {anon}
--   USING:      true
--   WITH CHECK: None

-- ------------------------------------------------------------
-- POLICY: Service role full access circuit_breakers
--   table:      public.oracle_circuit_breakers
--   command:    ALL
--   roles:      {service_role}
--   USING:      true
--   WITH CHECK: true

-- ------------------------------------------------------------
-- POLICY: anon_select_oracle_college_orders
--   table:      public.oracle_college_orders
--   command:    SELECT
--   roles:      {anon}
--   USING:      true
--   WITH CHECK: None

-- ------------------------------------------------------------
-- POLICY: service_all_oracle_college_orders
--   table:      public.oracle_college_orders
--   command:    ALL
--   roles:      {service_role}
--   USING:      true
--   WITH CHECK: true

-- ------------------------------------------------------------
-- POLICY: anon_select_oracle_college_runs
--   table:      public.oracle_college_runs
--   command:    SELECT
--   roles:      {anon}
--   USING:      true
--   WITH CHECK: None

-- ------------------------------------------------------------
-- POLICY: oracle_college_runs_anon_insert
--   table:      public.oracle_college_runs
--   command:    INSERT
--   roles:      {anon}
--   USING:      None
--   WITH CHECK: (run_id IS NOT NULL)

-- ------------------------------------------------------------
-- POLICY: service_all_oracle_college_runs
--   table:      public.oracle_college_runs
--   command:    ALL
--   roles:      {service_role}
--   USING:      true
--   WITH CHECK: true

-- ------------------------------------------------------------
-- POLICY: Anon read datasource_health
--   table:      public.oracle_datasource_health
--   command:    SELECT
--   roles:      {anon}
--   USING:      true
--   WITH CHECK: None

-- ------------------------------------------------------------
-- POLICY: Service role full access datasource_health
--   table:      public.oracle_datasource_health
--   command:    ALL
--   roles:      {service_role}
--   USING:      true
--   WITH CHECK: true

-- ------------------------------------------------------------
-- POLICY: Anon read flash_intel
--   table:      public.oracle_flash_intel
--   command:    SELECT
--   roles:      {anon}
--   USING:      true
--   WITH CHECK: None

-- ------------------------------------------------------------
-- POLICY: Service role full access flash_intel
--   table:      public.oracle_flash_intel
--   command:    ALL
--   roles:      {service_role}
--   USING:      true
--   WITH CHECK: true

-- ------------------------------------------------------------
-- POLICY: Anon read kelly_sizing
--   table:      public.oracle_kelly_sizing
--   command:    SELECT
--   roles:      {anon}
--   USING:      true
--   WITH CHECK: None

-- ------------------------------------------------------------
-- POLICY: Service role full access kelly_sizing
--   table:      public.oracle_kelly_sizing
--   command:    ALL
--   roles:      {service_role}
--   USING:      true
--   WITH CHECK: true

-- ------------------------------------------------------------
-- POLICY: anon_select_oracle_logs
--   table:      public.oracle_logs
--   command:    SELECT
--   roles:      {anon}
--   USING:      true
--   WITH CHECK: None

-- ------------------------------------------------------------
-- POLICY: service_all_oracle_logs
--   table:      public.oracle_logs
--   command:    ALL
--   roles:      {service_role}
--   USING:      true
--   WITH CHECK: true

-- ------------------------------------------------------------
-- POLICY: anon_select_oracle_market_cache
--   table:      public.oracle_market_cache
--   command:    SELECT
--   roles:      {anon}
--   USING:      true
--   WITH CHECK: None

-- ------------------------------------------------------------
-- POLICY: service_all_oracle_market_cache
--   table:      public.oracle_market_cache
--   command:    ALL
--   roles:      {service_role}
--   USING:      true
--   WITH CHECK: true

-- ------------------------------------------------------------
-- POLICY: anon_select_oracle_performance
--   table:      public.oracle_performance
--   command:    SELECT
--   roles:      {anon}
--   USING:      true
--   WITH CHECK: None

-- ------------------------------------------------------------
-- POLICY: service_all_oracle_performance
--   table:      public.oracle_performance
--   command:    ALL
--   roles:      {service_role}
--   USING:      true
--   WITH CHECK: true

-- ------------------------------------------------------------
-- POLICY: Anon read positions_live
--   table:      public.oracle_positions_live
--   command:    SELECT
--   roles:      {anon}
--   USING:      true
--   WITH CHECK: None

-- ------------------------------------------------------------
-- POLICY: Service role full access positions_live
--   table:      public.oracle_positions_live
--   command:    ALL
--   roles:      {service_role}
--   USING:      true
--   WITH CHECK: true

-- ------------------------------------------------------------
-- POLICY: anon_peut_signaler
--   table:      public.oracle_problemes
--   command:    INSERT
--   roles:      {anon,authenticated}
--   USING:      None
--   WITH CHECK: true

-- ------------------------------------------------------------
-- POLICY: anon_select_oracle_runs
--   table:      public.oracle_runs
--   command:    SELECT
--   roles:      {anon}
--   USING:      true
--   WITH CHECK: None

-- ------------------------------------------------------------
-- POLICY: anon_select_oracle_sages_report
--   table:      public.oracle_sages_report
--   command:    SELECT
--   roles:      {anon}
--   USING:      true
--   WITH CHECK: None

-- ------------------------------------------------------------
-- POLICY: service_all_oracle_sages_report
--   table:      public.oracle_sages_report
--   command:    ALL
--   roles:      {service_role}
--   USING:      true
--   WITH CHECK: true

-- ------------------------------------------------------------
-- POLICY: Anon read visionary_signals
--   table:      public.oracle_visionary_signals
--   command:    SELECT
--   roles:      {anon}
--   USING:      true
--   WITH CHECK: None

-- ------------------------------------------------------------
-- POLICY: Service role full access visionary_signals
--   table:      public.oracle_visionary_signals
--   command:    ALL
--   roles:      {service_role}
--   USING:      true
--   WITH CHECK: true

-- ------------------------------------------------------------
-- POLICY: Users can only see own portfolio
--   table:      public.portfolio_virtual
--   command:    ALL
--   roles:      {public}
--   USING:      ((( SELECT auth.uid() AS uid))::text = ( SELECT (app_users.auth_id)::text AS auth_id
   FROM app_users
  WHERE (app_users.id = portfolio_virtual.id)
 LIMIT 1))
--   WITH CHECK: None

-- ------------------------------------------------------------
-- POLICY: anon_select_positions_recommended
--   table:      public.positions_recommended
--   command:    SELECT
--   roles:      {anon}
--   USING:      true
--   WITH CHECK: None

-- ------------------------------------------------------------
-- POLICY: revx_univers_read
--   table:      public.revolut_univers_complet
--   command:    SELECT
--   roles:      {anon,authenticated}
--   USING:      true
--   WITH CHECK: None

