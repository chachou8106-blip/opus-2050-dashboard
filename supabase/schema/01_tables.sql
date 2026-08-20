-- ============================================================
-- TABLES (public schema)
-- Exported from Supabase project smddzybxebwhfnitxuyp on 2026-08-14
-- Reference / rebuild only. Not an auto-applied migration.
-- ============================================================

-- TABLE: _ju_brain_backup
CREATE TABLE IF NOT EXISTS public._ju_brain_backup (
  backed_at timestamp with time zone DEFAULT now(),
  note text,
  archimage text,
  current_bias text,
  learnings jsonb
);

-- TABLE: alc_bt_coins
CREATE TABLE IF NOT EXISTS public.alc_bt_coins (
  coin text NOT NULL,
  held boolean DEFAULT true,
  reliable boolean DEFAULT false
);

-- TABLE: alc_destake_reco
CREATE TABLE IF NOT EXISTS public.alc_destake_reco (
  id bigint NOT NULL,
  run_id text,
  devise text,
  montant_usd numeric,
  gain_trade_attendu_pct numeric,
  apy_staking_pct numeric,
  delai_deblocage_jours numeric,
  verdict text,
  raison text,
  created_at timestamp with time zone DEFAULT now()
);

-- TABLE: alc_staking_apy
CREATE TABLE IF NOT EXISTS public.alc_staking_apy (
  devise text NOT NULL,
  apy_pct numeric NOT NULL,
  source text,
  updated_at timestamp with time zone NOT NULL DEFAULT now()
);

-- TABLE: alc_staking_delais
CREATE TABLE IF NOT EXISTS public.alc_staking_delais (
  devise text NOT NULL,
  unbonding_jours numeric,
  "precision" text,
  source text,
  note text,
  updated_at timestamp with time zone DEFAULT now()
);

-- TABLE: alc_staking_holdings
CREATE TABLE IF NOT EXISTS public.alc_staking_holdings (
  devise text NOT NULL,
  principal_qty numeric,
  cout_achat numeric,
  devise_cout text DEFAULT 'GBP'::text,
  date_achat date,
  qty_actuelle numeric,
  gain_vie_qty numeric,
  note text,
  updated_at timestamp with time zone NOT NULL DEFAULT now()
);

-- TABLE: alc_staking_lots
CREATE TABLE IF NOT EXISTS public.alc_staking_lots (
  id bigint NOT NULL,
  devise text NOT NULL,
  qty numeric NOT NULL,
  cout_gbp numeric NOT NULL,
  date_achat date NOT NULL,
  note text,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  devise_cout text NOT NULL DEFAULT 'GBP'::text
);

-- TABLE: alchimiste_crypte_propositions
CREATE TABLE IF NOT EXISTS public.alchimiste_crypte_propositions (
  id bigint NOT NULL,
  run_id text,
  proposed_at timestamp with time zone NOT NULL DEFAULT now(),
  paire text,
  side text,
  prix_ref numeric,
  montant numeric,
  confidence numeric,
  raison text,
  tolerance_pct numeric NOT NULL DEFAULT 1.0,
  expire_at timestamp with time zone,
  statut text NOT NULL DEFAULT 'proposee'::text,
  oui_at timestamp with time zone,
  prix_exec numeric,
  resultat jsonb,
  created_at timestamp with time zone NOT NULL DEFAULT now()
);

-- TABLE: alchimiste_virtual_trades
CREATE TABLE IF NOT EXISTS public.alchimiste_virtual_trades (
  proposition_id bigint NOT NULL,
  paire text NOT NULL,
  side text NOT NULL,
  prix_entree double precision NOT NULL,
  montant double precision,
  opened_at timestamp with time zone NOT NULL,
  tp_pct double precision NOT NULL DEFAULT 5,
  sl_pct double precision NOT NULL DEFAULT 4,
  exit_ts timestamp with time zone,
  prix_sortie double precision,
  exit_reason text,
  pnl_pct double precision,
  hold_hours double precision,
  is_open boolean NOT NULL DEFAULT false,
  rebuilt_at timestamp with time zone NOT NULL DEFAULT now()
);

-- TABLE: alpaca_orders
CREATE TABLE IF NOT EXISTS public.alpaca_orders (
  id uuid NOT NULL DEFAULT uuid_generate_v4(),
  created_at timestamp with time zone DEFAULT now(),
  updated_at timestamp with time zone DEFAULT now(),
  run_id text,
  portfolio_id uuid,
  alpaca_order_id text,
  alpaca_client_order_id text,
  symbol text NOT NULL,
  side text NOT NULL,
  type text,
  qty numeric,
  notional numeric,
  status text,
  filled_qty numeric,
  filled_avg_price numeric,
  limit_price numeric,
  stop_price numeric,
  submitted_at timestamp with time zone,
  filled_at timestamp with time zone,
  is_paper boolean DEFAULT true,
  oracle_rationale text,
  layer text,
  error_message text,
  account text DEFAULT 'Ju'::text,
  synth_used text DEFAULT 'Claude'::text,
  order_type text DEFAULT 'market'::text,
  forex_conviction numeric DEFAULT 0,
  run_id_ref text,
  archimage text,
  order_type_label text DEFAULT 'market'::text
);

-- TABLE: app_users
CREATE TABLE IF NOT EXISTS public.app_users (
  id uuid NOT NULL DEFAULT uuid_generate_v4(),
  created_at timestamp with time zone DEFAULT now(),
  updated_at timestamp with time zone DEFAULT now(),
  auth_id uuid,
  email text,
  username text,
  risk_profile text DEFAULT 'MODERATE'::text,
  capital_total numeric,
  capital_investable numeric,
  currency text DEFAULT 'EUR'::text,
  investment_horizon text DEFAULT 'MEDIUM'::text,
  experience_level text DEFAULT 'NOVICE'::text,
  alpaca_api_key text,
  alpaca_secret_key text,
  alpaca_paper_mode boolean DEFAULT true,
  notification_slack text,
  notification_email boolean DEFAULT true,
  notification_push boolean DEFAULT true,
  total_runs_followed integer DEFAULT 0,
  total_pnl numeric DEFAULT 0,
  best_trade_pnl numeric,
  worst_trade_pnl numeric,
  win_rate numeric
);

-- TABLE: asset_universe
CREATE TABLE IF NOT EXISTS public.asset_universe (
  ticker text NOT NULL,
  name text NOT NULL,
  asset_type text,
  layer text,
  market_phase_fit ARRAY,
  description_fr text,
  risk_level integer,
  available_alpaca boolean DEFAULT true,
  available_revolut boolean DEFAULT true,
  assigned_archimage text,
  polygon_id text,
  options_available boolean DEFAULT false,
  typical_spread_bps numeric,
  avg_daily_volume_1m numeric
);

-- TABLE: bak_20260813_alchimiste_crypte_propositions
CREATE TABLE IF NOT EXISTS public.bak_20260813_alchimiste_crypte_propositions (
  id bigint,
  run_id text,
  proposed_at timestamp with time zone,
  paire text,
  side text,
  prix_ref numeric,
  montant numeric,
  confidence numeric,
  raison text,
  tolerance_pct numeric,
  expire_at timestamp with time zone,
  statut text,
  oui_at timestamp with time zone,
  prix_exec numeric,
  resultat jsonb,
  created_at timestamp with time zone
);

-- TABLE: bak_20260813_alchimiste_virtual_trades
CREATE TABLE IF NOT EXISTS public.bak_20260813_alchimiste_virtual_trades (
  proposition_id bigint,
  paire text,
  side text,
  prix_entree double precision,
  montant double precision,
  opened_at timestamp with time zone,
  tp_pct double precision,
  sl_pct double precision,
  exit_ts timestamp with time zone,
  prix_sortie double precision,
  exit_reason text,
  pnl_pct double precision,
  hold_hours double precision,
  is_open boolean,
  rebuilt_at timestamp with time zone
);

-- TABLE: bak_20260813_brain_alc_marees
CREATE TABLE IF NOT EXISTS public.bak_20260813_brain_alc_marees (
  id uuid,
  archimage text,
  last_run_at timestamp with time zone,
  last_run_id text,
  total_runs integer,
  wins integer,
  losses integer,
  win_rate numeric,
  cumulative_pnl numeric,
  current_drawdown numeric,
  max_drawdown numeric,
  synthesis_weight numeric,
  current_bias text,
  risk_appetite text,
  learnings jsonb,
  mistakes_history jsonb,
  style_evolution jsonb,
  best_asset_classes jsonb,
  last_decision jsonb,
  updated_at timestamp with time zone,
  baseline_equity numeric,
  assigned_universe text,
  universe_last_updated timestamp with time zone,
  directional_accuracy numeric,
  avg_conviction_score numeric,
  best_asset_class text,
  worst_asset_class text,
  consecutive_wins integer,
  consecutive_losses integer,
  max_consecutive_wins integer,
  current_streak_type text,
  kelly_fraction numeric,
  kelly_last_computed timestamp with time zone,
  avg_win_pct numeric,
  avg_loss_pct numeric,
  sector_expertise jsonb,
  forbidden_tickers ARRAY,
  preferred_tickers ARRAY,
  latest_web_catalysts jsonb,
  catalyst_updated_at timestamp with time zone,
  alpaca_buying_power numeric,
  alpaca_portfolio_value numeric,
  alpaca_last_synced timestamp with time zone,
  alpaca_drawdown_from_peak numeric
);

-- TABLE: bak_20260813_marees_propositions
CREATE TABLE IF NOT EXISTS public.bak_20260813_marees_propositions (
  id bigint,
  run_id text,
  paire text,
  side text,
  poids_pct numeric,
  confidence numeric,
  raison text,
  prix_ref double precision,
  statut text,
  proposed_at timestamp with time zone,
  tp_pct double precision,
  sl_pct double precision
);

-- TABLE: bak_20260813_marees_virtual_trades
CREATE TABLE IF NOT EXISTS public.bak_20260813_marees_virtual_trades (
  proposition_id bigint,
  paire text,
  side text,
  prix_entree double precision,
  montant double precision,
  opened_at timestamp with time zone,
  tp_pct double precision,
  sl_pct double precision,
  exit_ts timestamp with time zone,
  prix_sortie double precision,
  exit_reason text,
  pnl_pct double precision,
  hold_hours double precision,
  is_open boolean,
  rebuilt_at timestamp with time zone
);

-- TABLE: fonds_config
CREATE TABLE IF NOT EXISTS public.fonds_config (
  cle text NOT NULL,
  valeur text,
  maj timestamp with time zone DEFAULT now()
);

-- TABLE: fonds_versements
CREATE TABLE IF NOT EXISTS public.fonds_versements (
  id integer NOT NULL DEFAULT nextval('fonds_versements_id_seq'::regclass),
  jour date,
  montant_usd numeric,
  source text,
  note text,
  created_at timestamp with time zone DEFAULT now()
);

-- TABLE: ju_crypte_config
CREATE TABLE IF NOT EXISTS public.ju_crypte_config (
  key text NOT NULL,
  value text NOT NULL
);

-- TABLE: ju_crypte_orders
CREATE TABLE IF NOT EXISTS public.ju_crypte_orders (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  pair text NOT NULL,
  side text NOT NULL,
  amount_usd numeric NOT NULL,
  order_id text,
  status text,
  dry_run boolean NOT NULL DEFAULT true
);

-- TABLE: killswitch_passkeys
CREATE TABLE IF NOT EXISTS public.killswitch_passkeys (
  credential_id text NOT NULL,
  public_key text NOT NULL,
  counter bigint NOT NULL DEFAULT 0,
  transports text,
  label text,
  created_at timestamp with time zone NOT NULL DEFAULT now()
);

-- TABLE: killswitch_webauthn
CREATE TABLE IF NOT EXISTS public.killswitch_webauthn (
  purpose text NOT NULL,
  challenge text NOT NULL,
  created_at timestamp with time zone NOT NULL DEFAULT now()
);

-- TABLE: learning_feedback
CREATE TABLE IF NOT EXISTS public.learning_feedback (
  id uuid NOT NULL DEFAULT uuid_generate_v4(),
  run_id text,
  evaluated_at timestamp with time zone DEFAULT now(),
  evaluated_by text DEFAULT 'AUTO'::text,
  predicted_phase text,
  predicted_risk_score integer,
  predicted_action text,
  actual_phase_next_run text,
  spy_performance_7d numeric,
  spy_performance_30d numeric,
  recommended_positions_pnl jsonb,
  phase_correct boolean,
  direction_correct boolean,
  accuracy_score integer,
  notes text
);

-- TABLE: marees_config
CREATE TABLE IF NOT EXISTS public.marees_config (
  key text NOT NULL,
  value text
);

-- TABLE: marees_positions
CREATE TABLE IF NOT EXISTS public.marees_positions (
  id bigint NOT NULL DEFAULT nextval('marees_positions_id_seq'::regclass),
  run_id text,
  ticker text NOT NULL,
  poids_pct numeric NOT NULL,
  rationale text,
  created_at timestamp with time zone NOT NULL DEFAULT now()
);

-- TABLE: marees_propositions
CREATE TABLE IF NOT EXISTS public.marees_propositions (
  id bigint NOT NULL DEFAULT nextval('marees_propositions_id_seq'::regclass),
  run_id text,
  paire text NOT NULL,
  side text NOT NULL,
  poids_pct numeric,
  confidence numeric,
  raison text,
  prix_ref double precision,
  statut text DEFAULT 'proposee'::text,
  proposed_at timestamp with time zone NOT NULL DEFAULT now(),
  tp_pct double precision,
  sl_pct double precision,
  -- 20/08 : instant ou la ligne a quitte le livre cible = fermeture de la position.
  -- statut 'remplacee' = doublon de tenue de l'ancien modele append-only (exclu des stats).
  cloturee_at timestamp with time zone
);

-- TABLE: marees_virtual_trades
CREATE TABLE IF NOT EXISTS public.marees_virtual_trades (
  proposition_id bigint,
  paire text,
  side text,
  prix_entree double precision,
  montant double precision,
  opened_at timestamp with time zone,
  tp_pct double precision,
  sl_pct double precision,
  exit_ts timestamp with time zone,
  prix_sortie double precision,
  exit_reason text,
  pnl_pct double precision,
  hold_hours double precision,
  is_open boolean,
  rebuilt_at timestamp with time zone DEFAULT now()
);

-- TABLE: market_data_cache
CREATE TABLE IF NOT EXISTS public.market_data_cache (
  id uuid NOT NULL DEFAULT uuid_generate_v4(),
  fetched_at timestamp with time zone DEFAULT now(),
  vix numeric,
  t10y numeric,
  t2y numeric,
  fed_rate numeric,
  cpi numeric,
  unemployment numeric,
  spy_price numeric,
  spy_change_pct numeric,
  wti numeric,
  btc_price numeric,
  btc_24h_pct numeric,
  eth_price numeric,
  fear_greed integer,
  usd_eur numeric,
  usd_jpy numeric,
  spy_news text,
  data_quality integer DEFAULT 0,
  raw jsonb
);

-- TABLE: market_signals
CREATE TABLE IF NOT EXISTS public.market_signals (
  id uuid NOT NULL DEFAULT uuid_generate_v4(),
  run_id text,
  captured_at timestamp with time zone DEFAULT now(),
  source text,
  raw_data jsonb,
  geopolitical_tension_score integer,
  geopolitical_events jsonb,
  oil_price numeric,
  gold_price numeric,
  fear_index integer,
  greed_index integer,
  earthquake_events jsonb,
  weather_alerts jsonb
);

-- TABLE: oracle_backtest_cache
CREATE TABLE IF NOT EXISTS public.oracle_backtest_cache (
  id bigint NOT NULL,
  kind text NOT NULL,
  archimage text,
  tp_pct numeric,
  sl_pct numeric,
  trades integer,
  win_rate numeric,
  avg_ret_pct numeric,
  total_ret_pct numeric,
  profit_factor numeric,
  computed_at timestamp with time zone DEFAULT now()
);

-- TABLE: oracle_brain_state
CREATE TABLE IF NOT EXISTS public.oracle_brain_state (
  id uuid NOT NULL DEFAULT uuid_generate_v4(),
  archimage text NOT NULL,
  last_run_at timestamp with time zone,
  last_run_id text,
  total_runs integer DEFAULT 0,
  wins integer DEFAULT 0,
  losses integer DEFAULT 0,
  win_rate numeric DEFAULT 0,
  cumulative_pnl numeric DEFAULT 0,
  current_drawdown numeric DEFAULT 0,
  max_drawdown numeric DEFAULT 0,
  synthesis_weight numeric DEFAULT 0.33,
  current_bias text DEFAULT 'neutral'::text,
  risk_appetite text DEFAULT 'medium'::text,
  learnings jsonb DEFAULT '[]'::jsonb,
  mistakes_history jsonb DEFAULT '[]'::jsonb,
  style_evolution jsonb DEFAULT '{}'::jsonb,
  best_asset_classes jsonb DEFAULT '[]'::jsonb,
  last_decision jsonb DEFAULT '{}'::jsonb,
  updated_at timestamp with time zone DEFAULT now(),
  baseline_equity numeric,
  assigned_universe text DEFAULT 'global'::text,
  universe_last_updated timestamp with time zone DEFAULT now(),
  directional_accuracy numeric DEFAULT 0,
  avg_conviction_score numeric DEFAULT 5,
  best_asset_class text,
  worst_asset_class text,
  consecutive_wins integer DEFAULT 0,
  consecutive_losses integer DEFAULT 0,
  max_consecutive_wins integer DEFAULT 0,
  current_streak_type text DEFAULT 'none'::text,
  kelly_fraction numeric DEFAULT 0.1,
  kelly_last_computed timestamp with time zone,
  avg_win_pct numeric DEFAULT 0,
  avg_loss_pct numeric DEFAULT 0,
  sector_expertise jsonb DEFAULT '{}'::jsonb,
  forbidden_tickers ARRAY DEFAULT '{}'::text[],
  preferred_tickers ARRAY DEFAULT '{}'::text[],
  latest_web_catalysts jsonb DEFAULT '[]'::jsonb,
  catalyst_updated_at timestamp with time zone,
  alpaca_buying_power numeric DEFAULT 0,
  alpaca_portfolio_value numeric DEFAULT 0,
  alpaca_last_synced timestamp with time zone,
  alpaca_drawdown_from_peak numeric DEFAULT 0
);

-- TABLE: oracle_circuit_breakers
CREATE TABLE IF NOT EXISTS public.oracle_circuit_breakers (
  id bigint NOT NULL,
  fired_at timestamp with time zone DEFAULT now(),
  run_id text,
  archimage text NOT NULL,
  breaker_type text NOT NULL,
  trigger_value numeric,
  threshold_value numeric,
  action_taken text NOT NULL,
  orders_blocked integer DEFAULT 0,
  capital_protected numeric DEFAULT 0,
  auto_resolved boolean DEFAULT false,
  resolved_at timestamp with time zone,
  notes text
);

-- TABLE: oracle_college_orders
CREATE TABLE IF NOT EXISTS public.oracle_college_orders (
  id uuid NOT NULL DEFAULT uuid_generate_v4(),
  run_id text NOT NULL,
  archimage text NOT NULL,
  symbol text NOT NULL,
  side text NOT NULL,
  asset_class text,
  size_pct_portfolio numeric DEFAULT 0,
  notional numeric DEFAULT 0,
  broker text DEFAULT 'alpaca'::text,
  broker_order_id text,
  broker_status text DEFAULT 'pending'::text,
  broker_response jsonb,
  rationale text,
  urgency text DEFAULT 'immediate'::text,
  stop_loss_pct numeric DEFAULT 5,
  take_profit_pct numeric DEFAULT 10,
  validated boolean DEFAULT false,
  rejected_reason text,
  created_at timestamp with time zone DEFAULT now(),
  notional_validated numeric,
  notional_capped boolean,
  consecutive_buy_count integer DEFAULT 0,
  universe_zone text DEFAULT 'global'::text,
  signal_sources ARRAY DEFAULT '{}'::text[],
  web_catalyst text,
  executed_notional numeric DEFAULT 0,
  fill_price numeric,
  slippage_pct numeric,
  is_liquidation boolean DEFAULT false
);

-- TABLE: oracle_college_runs
CREATE TABLE IF NOT EXISTS public.oracle_college_runs (
  id uuid NOT NULL DEFAULT uuid_generate_v4(),
  run_id text NOT NULL,
  run_at timestamp with time zone DEFAULT now(),
  status text DEFAULT 'running'::text,
  market_phase text,
  data_completeness integer DEFAULT 0,
  consensus_level text,
  risk_override boolean DEFAULT false,
  risk_override_reason text,
  claude_confidence integer DEFAULT 0,
  perplexity_confidence integer DEFAULT 0,
  mistral_confidence integer DEFAULT 0,
  final_cash_pct numeric DEFAULT 15,
  final_equities_pct numeric DEFAULT 0,
  final_crypto_pct numeric DEFAULT 0,
  final_bonds_pct numeric DEFAULT 0,
  final_forex_pct numeric DEFAULT 0,
  final_commodities_pct numeric DEFAULT 0,
  orders_count integer DEFAULT 0,
  orders_executed integer DEFAULT 0,
  pnl_estimated numeric DEFAULT 0,
  slack_title text,
  slack_sent boolean DEFAULT false,
  raw_payload jsonb,
  created_at timestamp with time zone DEFAULT now(),
  run_id_canonical text,
  polygon_ok boolean DEFAULT false,
  newsapi_ok boolean DEFAULT false,
  fred_series_ok boolean DEFAULT false,
  options_flow_ok boolean DEFAULT false,
  darkpool_ok boolean DEFAULT false,
  put_call_ratio numeric,
  smart_money_flow text,
  sector_rotation_signal text,
  dark_pool_signal text,
  yield_curve_shape text,
  credit_spread_bps numeric,
  m2_growth_pct numeric,
  pmi_composite numeric,
  syl_web_catalysts text,
  syl_top_catalyst_ticker text,
  syl_catalyst_direction text,
  ju_universe_zone text DEFAULT 'US_EQUITIES'::text,
  syl_universe_zone text DEFAULT 'INTERNATIONAL_MACRO'::text,
  gil_universe_zone text DEFAULT 'CRYPTO_TACTICAL'::text,
  overlap_score numeric DEFAULT 0,
  orders_buy integer DEFAULT 0,
  orders_sell integer DEFAULT 0,
  orders_capped_notional integer DEFAULT 0,
  total_notional_submitted numeric DEFAULT 0,
  total_notional_capped numeric DEFAULT 0,
  circuit_breaker_fired boolean DEFAULT false,
  circuit_breaker_reason text,
  drawdown_at_run numeric DEFAULT 0,
  max_drawdown_pct_allowed numeric DEFAULT 5,
  visionary_score integer DEFAULT 0,
  forward_signal_accuracy numeric,
  signal_vs_market_delta numeric
);

-- TABLE: oracle_contexte
CREATE TABLE IF NOT EXISTS public.oracle_contexte (
  id integer NOT NULL DEFAULT nextval('oracle_contexte_id_seq'::regclass),
  section text,
  cle text,
  valeur text,
  maj timestamp with time zone DEFAULT now()
);

-- TABLE: oracle_datasource_health
CREATE TABLE IF NOT EXISTS public.oracle_datasource_health (
  id bigint NOT NULL,
  checked_at timestamp with time zone DEFAULT now(),
  run_id text,
  source_name text NOT NULL,
  status text NOT NULL,
  latency_ms integer,
  data_freshness_minutes integer,
  error_message text,
  fields_populated integer DEFAULT 0,
  fields_expected integer DEFAULT 0,
  completeness_pct numeric
);

-- TABLE: oracle_exec_debug
CREATE TABLE IF NOT EXISTS public.oracle_exec_debug (
  id bigint NOT NULL,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  archimage text,
  run_id text,
  market_open boolean,
  total integer,
  accepted integer,
  rejected integer,
  skipped integer,
  payload jsonb
);

-- TABLE: oracle_flash_intel
CREATE TABLE IF NOT EXISTS public.oracle_flash_intel (
  id uuid NOT NULL DEFAULT uuid_generate_v4(),
  run_id text NOT NULL,
  captured_at timestamp with time zone DEFAULT now(),
  ticker text NOT NULL,
  catalyst_type text NOT NULL,
  direction text NOT NULL,
  strength integer DEFAULT 5,
  headline text,
  source_url text,
  horizon text DEFAULT 'intraday'::text,
  confidence integer DEFAULT 70,
  shared_with_ju boolean DEFAULT true,
  shared_with_gil boolean DEFAULT true,
  verified boolean DEFAULT false,
  routed_to ARRAY DEFAULT '{}'::text[]
);

-- TABLE: oracle_journal
CREATE TABLE IF NOT EXISTS public.oracle_journal (
  id bigint NOT NULL,
  jour date NOT NULL DEFAULT ((now() AT TIME ZONE 'Europe/Paris'::text))::date,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  resume text,
  snapshot jsonb,
  problemes_traites integer DEFAULT 0
);

-- TABLE: oracle_kelly_sizing
CREATE TABLE IF NOT EXISTS public.oracle_kelly_sizing (
  id bigint NOT NULL,
  computed_at timestamp with time zone DEFAULT now(),
  run_id text,
  archimage text NOT NULL,
  ticker text NOT NULL,
  win_rate_used numeric,
  avg_win_used numeric,
  avg_loss_used numeric,
  kelly_raw numeric,
  kelly_fractional numeric,
  recommended_notional numeric,
  capped_notional numeric,
  buying_power_at_time numeric,
  applied boolean DEFAULT false
);

-- TABLE: oracle_leads
CREATE TABLE IF NOT EXISTS public.oracle_leads (
  id bigint NOT NULL,
  email text NOT NULL,
  source text,
  created_at timestamp with time zone DEFAULT now()
);

-- TABLE: oracle_logs
CREATE TABLE IF NOT EXISTS public.oracle_logs (
  id uuid NOT NULL DEFAULT uuid_generate_v4(),
  created_at timestamp with time zone DEFAULT now(),
  run_id text,
  log_type text,
  module_name text,
  status text,
  payload jsonb,
  error_msg text
);

-- TABLE: oracle_market_cache
CREATE TABLE IF NOT EXISTS public.oracle_market_cache (
  id uuid NOT NULL DEFAULT uuid_generate_v4(),
  snapshot_at timestamp with time zone DEFAULT now(),
  source text,
  dataset text,
  payload jsonb,
  ttl_minutes integer DEFAULT 60
);

-- TABLE: oracle_performance
CREATE TABLE IF NOT EXISTS public.oracle_performance (
  id uuid NOT NULL DEFAULT uuid_generate_v4(),
  run_id text NOT NULL,
  archimage text NOT NULL,
  predicted_direction text,
  actual_direction text,
  predicted_pnl numeric DEFAULT 0,
  actual_pnl numeric DEFAULT 0,
  accuracy_score numeric DEFAULT 0,
  market_phase text,
  orders_count integer DEFAULT 0,
  win boolean,
  notes text,
  evaluated_at timestamp with time zone DEFAULT now()
);

-- TABLE: oracle_positions_live
CREATE TABLE IF NOT EXISTS public.oracle_positions_live (
  id uuid NOT NULL DEFAULT uuid_generate_v4(),
  archimage text NOT NULL,
  ticker text NOT NULL,
  side text NOT NULL,
  qty numeric NOT NULL DEFAULT 0,
  avg_entry_price numeric,
  current_price numeric,
  market_value numeric,
  unrealized_pl numeric DEFAULT 0,
  unrealized_pl_pct numeric DEFAULT 0,
  cost_basis numeric,
  opened_at timestamp with time zone,
  last_synced timestamp with time zone DEFAULT now(),
  days_held integer DEFAULT 0,
  consecutive_runs_held integer DEFAULT 0,
  take_profit_target numeric,
  stop_loss_target numeric,
  is_stale boolean DEFAULT false
);

-- TABLE: oracle_problemes
CREATE TABLE IF NOT EXISTS public.oracle_problemes (
  id bigint NOT NULL,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  message text NOT NULL,
  source text DEFAULT 'telephone'::text,
  statut text NOT NULL DEFAULT 'nouveau'::text,
  diagnostic text,
  recommandation text,
  traite_at timestamp with time zone
);

-- TABLE: oracle_rappels
CREATE TABLE IF NOT EXISTS public.oracle_rappels (
  id bigint NOT NULL,
  date_rappel date NOT NULL,
  creneau text DEFAULT 'matin'::text,
  titre text,
  message text,
  cree_le timestamp with time zone DEFAULT now(),
  done boolean DEFAULT false
);

-- TABLE: oracle_runs
CREATE TABLE IF NOT EXISTS public.oracle_runs (
  id uuid NOT NULL DEFAULT uuid_generate_v4(),
  run_id text NOT NULL,
  created_at timestamp with time zone DEFAULT now(),
  run_at timestamp with time zone,
  market_phase text NOT NULL,
  risk_score integer,
  confidence integer,
  data_completeness integer,
  macro_summary text,
  market_summary text,
  news_summary text,
  perplexity_summary text,
  mistral_summary text,
  claude_synthesis text,
  master_word text,
  action_type text,
  allocation_cash integer,
  allocation_defensive integer,
  allocation_risk integer,
  max_position_risk_pct integer,
  revolut_manual_action text,
  signals_positive text,
  signals_negative text,
  contradictions text,
  guardrails text,
  stop_conditions text,
  slack_title text,
  slack_message text,
  slack_sent boolean DEFAULT false,
  prompt_version text,
  status text,
  learning_update text,
  spy_price numeric,
  spy_variation numeric,
  vix_value numeric,
  t10y_rate numeric,
  t2y_rate numeric,
  fed_rate numeric,
  cpi_value numeric,
  chomage_rate numeric,
  news_count integer,
  fred_ok boolean,
  finnhub_ok boolean,
  alpha_ok boolean,
  geopolitical_summary text,
  leading_indicators text,
  oil_price numeric,
  gdelt_ok boolean,
  eia_ok boolean,
  synth_a_phase text,
  synth_b_phase text,
  synth_c_phase text,
  synth_agreement boolean DEFAULT false,
  verdict_final text,
  sage_macro_score integer,
  sage_geopo_score integer,
  sage_vision_niche1 text,
  sage_vision_niche2 text,
  sage_rotation_etf text,
  crypto_allocation integer DEFAULT 0,
  crypto_recommended_ticker text,
  synth_b_analysis text,
  synth_c_analysis text,
  sage_quant_score integer DEFAULT 0,
  sage_quant_regime text,
  short_term_catalyst text,
  trades_executed integer DEFAULT 0,
  historical_adjustment text,
  crypto_weight integer DEFAULT 0,
  sage_forex_score integer DEFAULT 0,
  forex_signal text,
  forex_usd_eur numeric,
  forex_usd_gbp numeric,
  forex_usd_jpy numeric,
  sage_energie_score integer DEFAULT 0,
  sage_tech_score integer DEFAULT 0,
  btc_price numeric,
  eth_price numeric,
  fear_greed integer,
  memory_summary text,
  visionary_view_short text,
  visionary_view_long text,
  run_id_v2 text,
  perf_48h_pct numeric,
  was_correct boolean,
  error_log text,
  position1_ticker text,
  position1_action text,
  position1_alloc integer,
  position1_conviction integer,
  trades_count integer DEFAULT 0
);

-- TABLE: oracle_sages_report
CREATE TABLE IF NOT EXISTS public.oracle_sages_report (
  id uuid NOT NULL DEFAULT uuid_generate_v4(),
  run_id text NOT NULL,
  sage_name text NOT NULL,
  sage_output jsonb,
  execution_ms integer DEFAULT 0,
  status text DEFAULT 'ok'::text,
  created_at timestamp with time zone DEFAULT now()
);

-- TABLE: oracle_visionary_signals
CREATE TABLE IF NOT EXISTS public.oracle_visionary_signals (
  id uuid NOT NULL DEFAULT uuid_generate_v4(),
  generated_at timestamp with time zone DEFAULT now(),
  run_id text,
  signal_type text NOT NULL,
  ticker text,
  signal_value numeric,
  signal_label text,
  conviction integer DEFAULT 5,
  time_horizon text DEFAULT '1w'::text,
  source text,
  raw_data jsonb DEFAULT '{}'::jsonb,
  corroborated_by ARRAY DEFAULT '{}'::text[],
  outcome_tracked boolean DEFAULT false,
  outcome_correct boolean,
  outcome_evaluated_at timestamp with time zone
);

-- TABLE: portfolio_virtual
CREATE TABLE IF NOT EXISTS public.portfolio_virtual (
  id uuid NOT NULL DEFAULT uuid_generate_v4(),
  created_at timestamp with time zone DEFAULT now(),
  updated_at timestamp with time zone DEFAULT now(),
  ticker text NOT NULL,
  asset_name text,
  asset_type text,
  layer text,
  entry_run_id text,
  entry_date timestamp with time zone,
  entry_price numeric,
  quantity numeric,
  invested_amount numeric,
  current_price numeric,
  current_value numeric,
  unrealized_pnl numeric,
  unrealized_pnl_pct numeric,
  status text DEFAULT 'OPEN'::text,
  exit_run_id text,
  exit_date timestamp with time zone,
  exit_price numeric,
  realized_pnl numeric,
  realized_pnl_pct numeric,
  alpaca_order_id text,
  alpaca_symbol text,
  is_paper_trade boolean DEFAULT true
);

-- TABLE: positions_recommended
CREATE TABLE IF NOT EXISTS public.positions_recommended (
  id uuid NOT NULL DEFAULT uuid_generate_v4(),
  run_id text,
  created_at timestamp with time zone DEFAULT now(),
  ticker text NOT NULL,
  asset_name text,
  asset_type text,
  layer text,
  action text NOT NULL,
  allocation_pct numeric,
  entry_price numeric,
  target_price numeric,
  stop_loss_pct numeric,
  time_horizon text,
  rationale text,
  conviction_score integer,
  is_niche boolean DEFAULT false,
  is_coup_de_fusil boolean DEFAULT false
);

-- TABLE: price_history
CREATE TABLE IF NOT EXISTS public.price_history (
  id bigint NOT NULL,
  symbol text NOT NULL,
  "interval" text NOT NULL DEFAULT '1h'::text,
  ts timestamp with time zone NOT NULL,
  open numeric,
  high numeric,
  low numeric,
  close numeric,
  volume numeric
);

-- TABLE: revolut_portfolio_daily
CREATE TABLE IF NOT EXISTS public.revolut_portfolio_daily (
  id bigint NOT NULL,
  snapshot_at timestamp with time zone NOT NULL DEFAULT now(),
  total_usd numeric,
  cash_usd numeric,
  liquide_usd numeric,
  stake_usd numeric,
  nb_lignes integer,
  resume_texte text,
  detail jsonb
);

-- TABLE: revolut_univers_complet
CREATE TABLE IF NOT EXISTS public.revolut_univers_complet (
  paire text NOT NULL,
  bid numeric,
  ask numeric,
  mid numeric,
  last_price numeric,
  disponible_binance boolean DEFAULT false,
  updated_at timestamp with time zone DEFAULT now()
);

-- TABLE: world_regime_journal
CREATE TABLE IF NOT EXISTS public.world_regime_journal (
  id integer NOT NULL DEFAULT nextval('world_regime_journal_id_seq'::regclass),
  jour date DEFAULT CURRENT_DATE,
  regime text,
  resume text,
  archimages_activite jsonb,
  alignement text,
  created_at timestamp with time zone DEFAULT now()
);


-- ============================================================
-- CONSTRAINTS (primary keys, unique, foreign keys)
-- ============================================================

ALTER TABLE public.alc_bt_coins ADD CONSTRAINT alc_bt_coins_pkey PRIMARY KEY (coin);
ALTER TABLE public.alc_destake_reco ADD CONSTRAINT alc_destake_reco_pkey PRIMARY KEY (id);
ALTER TABLE public.alc_staking_apy ADD CONSTRAINT alc_staking_apy_pkey PRIMARY KEY (devise);
ALTER TABLE public.alc_staking_delais ADD CONSTRAINT alc_staking_delais_pkey PRIMARY KEY (devise);
ALTER TABLE public.alc_staking_holdings ADD CONSTRAINT alc_staking_holdings_pkey PRIMARY KEY (devise);
ALTER TABLE public.alc_staking_lots ADD CONSTRAINT alc_staking_lots_pkey PRIMARY KEY (id);
ALTER TABLE public.alchimiste_crypte_propositions ADD CONSTRAINT alchimiste_crypte_propositions_pkey PRIMARY KEY (id);
ALTER TABLE public.alchimiste_virtual_trades ADD CONSTRAINT alchimiste_virtual_trades_pkey PRIMARY KEY (proposition_id);
ALTER TABLE public.alpaca_orders ADD CONSTRAINT alpaca_orders_portfolio_id_fkey FOREIGN KEY (portfolio_id) REFERENCES portfolio_virtual(id);
ALTER TABLE public.alpaca_orders ADD CONSTRAINT alpaca_orders_run_id_fkey FOREIGN KEY (run_id) REFERENCES oracle_runs(run_id);
ALTER TABLE public.alpaca_orders ADD CONSTRAINT alpaca_orders_pkey PRIMARY KEY (id);
ALTER TABLE public.alpaca_orders ADD CONSTRAINT alpaca_orders_alpaca_order_id_key UNIQUE (alpaca_order_id);
ALTER TABLE public.app_users ADD CONSTRAINT app_users_pkey PRIMARY KEY (id);
ALTER TABLE public.app_users ADD CONSTRAINT app_users_username_key UNIQUE (username);
ALTER TABLE public.app_users ADD CONSTRAINT app_users_auth_id_key UNIQUE (auth_id);
ALTER TABLE public.app_users ADD CONSTRAINT app_users_email_key UNIQUE (email);
ALTER TABLE public.asset_universe ADD CONSTRAINT asset_universe_pkey PRIMARY KEY (ticker);
ALTER TABLE public.fonds_config ADD CONSTRAINT fonds_config_pkey PRIMARY KEY (cle);
ALTER TABLE public.fonds_versements ADD CONSTRAINT fonds_versements_pkey PRIMARY KEY (id);
ALTER TABLE public.ju_crypte_config ADD CONSTRAINT alc_trade_config_pkey PRIMARY KEY (key);
ALTER TABLE public.ju_crypte_orders ADD CONSTRAINT alc_trade_orders_pkey PRIMARY KEY (id);
ALTER TABLE public.killswitch_passkeys ADD CONSTRAINT killswitch_passkeys_pkey PRIMARY KEY (credential_id);
ALTER TABLE public.killswitch_webauthn ADD CONSTRAINT killswitch_webauthn_pkey PRIMARY KEY (purpose);
ALTER TABLE public.learning_feedback ADD CONSTRAINT learning_feedback_pkey PRIMARY KEY (id);
ALTER TABLE public.marees_config ADD CONSTRAINT marees_config_pkey PRIMARY KEY (key);
ALTER TABLE public.marees_positions ADD CONSTRAINT marees_positions_pkey PRIMARY KEY (id);
ALTER TABLE public.marees_propositions ADD CONSTRAINT marees_propositions_pkey PRIMARY KEY (id);
ALTER TABLE public.market_data_cache ADD CONSTRAINT market_data_cache_pkey PRIMARY KEY (id);
ALTER TABLE public.market_signals ADD CONSTRAINT market_signals_run_id_fkey FOREIGN KEY (run_id) REFERENCES oracle_runs(run_id) ON DELETE CASCADE;
ALTER TABLE public.market_signals ADD CONSTRAINT market_signals_pkey PRIMARY KEY (id);
ALTER TABLE public.oracle_backtest_cache ADD CONSTRAINT oracle_backtest_cache_pkey PRIMARY KEY (id);
ALTER TABLE public.oracle_brain_state ADD CONSTRAINT oracle_brain_state_pkey PRIMARY KEY (id);
ALTER TABLE public.oracle_brain_state ADD CONSTRAINT oracle_brain_state_archimage_key UNIQUE (archimage);
ALTER TABLE public.oracle_circuit_breakers ADD CONSTRAINT oracle_circuit_breakers_pkey PRIMARY KEY (id);
ALTER TABLE public.oracle_college_orders ADD CONSTRAINT oracle_college_orders_pkey PRIMARY KEY (id);
ALTER TABLE public.oracle_college_runs ADD CONSTRAINT oracle_college_runs_pkey PRIMARY KEY (id);
ALTER TABLE public.oracle_college_runs ADD CONSTRAINT oracle_college_runs_run_id_key UNIQUE (run_id);
ALTER TABLE public.oracle_contexte ADD CONSTRAINT oracle_contexte_pkey PRIMARY KEY (id);
ALTER TABLE public.oracle_datasource_health ADD CONSTRAINT oracle_datasource_health_pkey PRIMARY KEY (id);
ALTER TABLE public.oracle_exec_debug ADD CONSTRAINT oracle_exec_debug_pkey PRIMARY KEY (id);
ALTER TABLE public.oracle_flash_intel ADD CONSTRAINT oracle_flash_intel_pkey PRIMARY KEY (id);
ALTER TABLE public.oracle_journal ADD CONSTRAINT oracle_journal_pkey PRIMARY KEY (id);
ALTER TABLE public.oracle_kelly_sizing ADD CONSTRAINT oracle_kelly_sizing_pkey PRIMARY KEY (id);
ALTER TABLE public.oracle_leads ADD CONSTRAINT oracle_leads_pkey PRIMARY KEY (id);
ALTER TABLE public.oracle_logs ADD CONSTRAINT oracle_logs_pkey PRIMARY KEY (id);
ALTER TABLE public.oracle_market_cache ADD CONSTRAINT oracle_market_cache_pkey PRIMARY KEY (id);
ALTER TABLE public.oracle_performance ADD CONSTRAINT oracle_performance_pkey PRIMARY KEY (id);
ALTER TABLE public.oracle_positions_live ADD CONSTRAINT oracle_positions_live_pkey PRIMARY KEY (id);
ALTER TABLE public.oracle_positions_live ADD CONSTRAINT oracle_positions_live_archimage_ticker_key UNIQUE (archimage, ticker);
ALTER TABLE public.oracle_problemes ADD CONSTRAINT oracle_problemes_pkey PRIMARY KEY (id);
ALTER TABLE public.oracle_rappels ADD CONSTRAINT oracle_rappels_pkey PRIMARY KEY (id);
ALTER TABLE public.oracle_runs ADD CONSTRAINT oracle_runs_pkey PRIMARY KEY (id);
ALTER TABLE public.oracle_runs ADD CONSTRAINT oracle_runs_run_id_key UNIQUE (run_id);
ALTER TABLE public.oracle_sages_report ADD CONSTRAINT oracle_sages_report_pkey PRIMARY KEY (id);
ALTER TABLE public.oracle_visionary_signals ADD CONSTRAINT oracle_visionary_signals_pkey PRIMARY KEY (id);
ALTER TABLE public.portfolio_virtual ADD CONSTRAINT portfolio_virtual_exit_run_id_fkey FOREIGN KEY (exit_run_id) REFERENCES oracle_runs(run_id);
ALTER TABLE public.portfolio_virtual ADD CONSTRAINT portfolio_virtual_entry_run_id_fkey FOREIGN KEY (entry_run_id) REFERENCES oracle_runs(run_id);
ALTER TABLE public.portfolio_virtual ADD CONSTRAINT portfolio_virtual_pkey PRIMARY KEY (id);
ALTER TABLE public.positions_recommended ADD CONSTRAINT positions_recommended_run_id_fkey FOREIGN KEY (run_id) REFERENCES oracle_runs(run_id) ON DELETE CASCADE;
ALTER TABLE public.positions_recommended ADD CONSTRAINT positions_recommended_pkey PRIMARY KEY (id);
ALTER TABLE public.price_history ADD CONSTRAINT price_history_pkey PRIMARY KEY (id);
ALTER TABLE public.price_history ADD CONSTRAINT price_history_symbol_interval_ts_key UNIQUE (symbol, "interval", ts);
ALTER TABLE public.revolut_portfolio_daily ADD CONSTRAINT revolut_portfolio_daily_pkey PRIMARY KEY (id);
ALTER TABLE public.revolut_univers_complet ADD CONSTRAINT revolut_univers_complet_pkey PRIMARY KEY (paire);
ALTER TABLE public.world_regime_journal ADD CONSTRAINT world_regime_journal_pkey PRIMARY KEY (id);

-- ============================================================
-- TABLE: alpaca_equity_daily   (ajoutee le 19/08/2026)
-- ============================================================
-- Cloture quotidienne officielle de chaque compte Alpaca, lue sur
-- /v2/account/portfolio/history et archivee a chaque run par update-brain (v19).
-- Devient la source de verite des courbes de performance : les instantanes de
-- oracle_performance sont pris a l'heure des runs, donc en pleine seance, et
-- derivaient de -12 925 $ a +32 382 $ par jour (et de +182 624 $ sur JU le 18/08/2026).
CREATE TABLE IF NOT EXISTS public.alpaca_equity_daily (
  archimage   text        NOT NULL,
  jour        date        NOT NULL,
  equity      numeric     NOT NULL,
  source      text        NOT NULL DEFAULT 'alpaca_portfolio_history',
  updated_at  timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (archimage, jour)
);
ALTER TABLE public.alpaca_equity_daily ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS alpaca_equity_daily_lecture ON public.alpaca_equity_daily;
CREATE POLICY alpaca_equity_daily_lecture ON public.alpaca_equity_daily FOR SELECT USING (true);

-- oracle_performance : marquage des mesures aberrantes (19/08/2026).
-- false = mesure contredite par la cloture officielle Alpaca ; la ligne est conservee
-- pour l'historique mais exclue des courbes et des rendements.
ALTER TABLE public.oracle_performance
  ADD COLUMN IF NOT EXISTS fiable boolean NOT NULL DEFAULT true;
CREATE INDEX IF NOT EXISTS oracle_performance_fiable_idx
  ON public.oracle_performance (archimage, evaluated_at) WHERE fiable;
