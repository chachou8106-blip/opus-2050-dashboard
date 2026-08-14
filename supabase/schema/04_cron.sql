-- Scheduled jobs (pg_cron) exported from project smddzybxebwhfnitxuyp on 2026-08-14
-- Reference / rebuild only.

-- jobid: 24 | active: True | schedule: 10 6 * * *
select cron.schedule('aether-point-matin', '10 6 * * *', $CRON$select public.generate_daily_journal('matin')$CRON$);

-- jobid: 25 | active: True | schedule: 10 11 * * *
select cron.schedule('aether-point-midi', '10 11 * * *', $CRON$select public.generate_daily_journal('midi')$CRON$);

-- jobid: 26 | active: True | schedule: 10 18 * * *
select cron.schedule('aether-point-soir', '10 18 * * *', $CRON$select public.generate_daily_journal('soir')$CRON$);

-- jobid: 15 | active: True | schedule: 45 */6 * * *
select cron.schedule('alc_rebuild_virtual_6h', '45 */6 * * *', $CRON$select public.alc_rebuild_virtual();$CRON$);

-- jobid: 14 | active: True | schedule: 35 */6 * * *
select cron.schedule('backtests_cache_6h', '35 */6 * * *', $CRON$select public.refresh_backtest_cache()$CRON$);

-- jobid: 3 | active: True | schedule: 5 */2 * * *
select cron.schedule('crypte_ju_apprentissage', '5 */2 * * *', $CRON$ select public.crypte_ju_evaluate_and_learn(); $CRON$);

-- jobid: 13 | active: True | schedule: 19 */2 * * *
select cron.schedule('directional_kelly_breakers', '19 */2 * * *', $CRON$select public.evaluate_directional_accuracy(); select public.compute_kelly_real(); select public.check_circuit_breakers();$CRON$);

-- jobid: 8 | active: True | schedule: 7 */2 * * *
select cron.schedule('evaluer_win_loss_archimages', '7 */2 * * *', $CRON$select public.evaluate_archimages_win_loss_pct();$CRON$);

-- jobid: 19 | active: True | schedule: 2 * * * *
select cron.schedule('ingest_binance_hourly', '2 * * * *', $CRON$
  select net.http_post(
    url := 'https://smddzybxebwhfnitxuyp.supabase.co/functions/v1/ingest-klines',
    headers := jsonb_build_object('Content-Type','application/json',
      'apikey','eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InNtZGR6eWJ4ZWJ3aGZuaXR4dXlwIiwicm9sZSI6ImFub24iLCJpYXQiOjE3Nzk4ODk4NzksImV4cCI6MjA5NTQ2NTg3OX0.ppjgF79OokQ-2jE8UCp26U-E-YZPcmf6TNnYEKHGKSM',
      'Authorization','Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InNtZGR6eWJ4ZWJ3aGZuaXR4dXlwIiwicm9sZSI6ImFub24iLCJpYXQiOjE3Nzk4ODk4NzksImV4cCI6MjA5NTQ2NTg3OX0.ppjgF79OokQ-2jE8UCp26U-E-YZPcmf6TNnYEKHGKSM'),
    body := '{}'::jsonb, timeout_milliseconds := 150000);
$CRON$);

-- jobid: 16 | active: True | schedule: 22 */6 * * *
select cron.schedule('ingest_fx_6h', '22 */6 * * *', $CRON$ select net.http_get(url := 'https://smddzybxebwhfnitxuyp.supabase.co/functions/v1/ingest-fx?range=1mo'); $CRON$);

-- jobid: 22 | active: True | schedule: 4 * * * *
select cron.schedule('ingest_gate_hourly', '4 * * * *', $CRON$
  select net.http_post(
    url := 'https://smddzybxebwhfnitxuyp.supabase.co/functions/v1/ingest-gate-prices',
    headers := jsonb_build_object('Content-Type','application/json',
      'apikey','eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InNtZGR6eWJ4ZWJ3aGZuaXR4dXlwIiwicm9sZSI6ImFub24iLCJpYXQiOjE3Nzk4ODk4NzksImV4cCI6MjA5NTQ2NTg3OX0.ppjgF79OokQ-2jE8UCp26U-E-YZPcmf6TNnYEKHGKSM',
      'Authorization','Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InNtZGR6eWJ4ZWJ3aGZuaXR4dXlwIiwicm9sZSI6ImFub24iLCJpYXQiOjE3Nzk4ODk4NzksImV4cCI6MjA5NTQ2NTg3OX0.ppjgF79OokQ-2jE8UCp26U-E-YZPcmf6TNnYEKHGKSM'),
    body := '{}'::jsonb, timeout_milliseconds := 60000);
$CRON$);

-- jobid: 5 | active: True | schedule: 20 */6 * * *
select cron.schedule('ingest_prix_6h', '20 */6 * * *', $CRON$select net.http_post(url:='https://smddzybxebwhfnitxuyp.supabase.co/functions/v1/ingest-klines', headers:='{"Content-Type":"application/json"}'::jsonb, body:=jsonb_build_object('interval','1h','limit',1000,'symbols','["DOT-USD", "KAVA-USD", "BIGTIME-USD", "KNC-USD", "CVX-USD", "SHIB-USD", "WLFI-USD", "XTZ-USD", "AST-USD", "ZRO-USD", "SPK-USD", "C98-USD", "ETC-USD", "EUL-USD", "AERGO-USD", "IO-USD", "DASH-USD", "ETH-USD", "FIDA-USD", "PYTH-USD", "STX-USD", "PROVE-USD", "STG-USD", "IMX-USD", "ARPA-USD", "LQTY-USD", "CVC-USD", "SKL-USD", "RENDER-USD", "ROSE-USD", "BLZ-USD", "KSM-USD", "STRK-USD", "JASMY-USD", "SOL-USD", "UMA-USD", "GMT-USD", "TIA-USD", "APT-USD", "AMP-USD", "ALGO-USD", "ZKC-USD", "QNT-USD", "AVAX-USD", "TRU-USD", "GHST-USD", "OGN-USD", "ADA-USD", "ENA-USD", "IDEX-USD", "BLUR-USD", "BNB-USD", "QI-USD", "MLN-USD", "LINK-USD", "INJ-USD", "AAVE-USD", "CRV-USD", "PENDLE-USD", "ORCA-USD", "SKY-USD", "ILV-USD", "GTC-USD", "BAND-USD", "POWR-USD", "METIS-USD", "ICP-USD", "EIGEN-USD", "BICO-USD", "PARTI-USD", "TURBO-USD", "POL-USD", "TNSR-USD", "USDC-USD", "NOT-USD", "FET-USD", "OCEAN-USD", "LAYER-USD", "MANA-USD", "ARKM-USD", "LTC-USD", "TON-USD", "RLC-USD", "LA-USD", "EGLD-USD", "TRUMP-USD", "DOGS-USD", "MDT-USD", "BADGER-USD", "FLOW-USD", "FIS-USD", "AXS-USD", "RAY-USD", "RPL-USD", "HFT-USD", "ANKR-USD", "LDO-USD", "REQ-USD", "CELO-USD", "OP-USD", "PLUME-USD", "BERA-USD", "SNX-USD", "DYDX-USD", "ME-USD", "SAND-USD", "ACH-USD", "NEAR-USD", "AUCTION-USD", "BNT-USD", "BCH-USD", "NKN-USD", "ACX-USD", "AUDIO-USD", "SYRUP-USD", "SUPER-USD", "BONK-USD", "BAT-USD", "APE-USD", "TREE-USD", "XRP-USD", "LPT-USD", "ZK-USD", "CTSI-USD", "BAL-USD", "MAGIC-USD", "LRC-USD", "W-USD", "ZRX-USD", "JTO-USD", "NMR-USD", "RED-USD", "HBAR-USD", "GALA-USD", "FIL-USD", "GRT-USD", "SENT-USD", "DOLO-USD", "UNI-USD", "AI-USD", "DOGE-USD", "VET-USD", "RARE-USD", "PERP-USD", "SPELL-USD", "ONDO-USD", "HIGH-USD", "RAD-USD", "TRX-USD", "SXT-USD", "FARM-USD", "AVNT-USD", "VTHO-USD", "STORJ-USD", "BTC-USD", "JUP-USD", "WLD-USD", "CHZ-USD", "BEAM-USD", "PENGU-USD", "AWE-USD", "MORPHO-USD", "ATOM-USD", "COMP-USD", "FORTH-USD", "SUSHI-USD", "SOMI-USD", "MINA-USD", "KAITO-USD", "T-USD", "REZ-USD", "OXT-USD", "MASK-USD", "PYR-USD", "1INCH-USD", "PEPE-USD", "XLM-USD", "TRB-USD", "POLS-USD", "DIA-USD", "WIF-USD", "ALICE-USD", "KERNEL-USD", "ENS-USD", "API3-USD", "YFI-USD", "FLOKI-USD", "GLM-USD", "HNT-USD", "NEIRO-USD", "VOXEL-USD", "ARB-USD", "AGLD-USD", "2Z-USD", "SUI-USD", "PUNDIX-USD", "SEI-USD", "PNUT-USD", "POND-USD", "OSMO-USD", "PUMP-USD", "WOO-USD", "RSR-USD", "COOKIE-USD", "CELR-USD", "ALCX-USD", "IOTX-USD", "COW-USD", "COTI-USD"]'::jsonb));$CRON$);

-- jobid: 21 | active: True | schedule: 7 * * * *
select cron.schedule('ingest_revx_hourly', '7 * * * *', $CRON$
  select net.http_post(
    url := 'https://smddzybxebwhfnitxuyp.supabase.co/functions/v1/ingest-revx-prices',
    headers := jsonb_build_object('Content-Type','application/json',
      'apikey','eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InNtZGR6eWJ4ZWJ3aGZuaXR4dXlwIiwicm9sZSI6ImFub24iLCJpYXQiOjE3Nzk4ODk4NzksImV4cCI6MjA5NTQ2NTg3OX0.ppjgF79OokQ-2jE8UCp26U-E-YZPcmf6TNnYEKHGKSM',
      'Authorization','Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InNtZGR6eWJ4ZWJ3aGZuaXR4dXlwIiwicm9sZSI6ImFub24iLCJpYXQiOjE3Nzk4ODk4NzksImV4cCI6MjA5NTQ2NTg3OX0.ppjgF79OokQ-2jE8UCp26U-E-YZPcmf6TNnYEKHGKSM'),
    body := '{}'::jsonb, timeout_milliseconds := 30000);
$CRON$);

-- jobid: 12 | active: True | schedule: 15 * * * *
select cron.schedule('ingest_spy_horaire', '15 * * * *', $CRON$select net.http_post(
      url:='https://smddzybxebwhfnitxuyp.supabase.co/functions/v1/ingest-spy',
      headers:='{"Content-Type": "application/json"}'::jsonb,
      body:=jsonb_build_object('start', to_char(now() - interval '3 days', 'YYYY-MM-DD"T"HH24:MI:SS"Z"')));$CRON$);

-- jobid: 23 | active: True | schedule: 0 21 * * *
select cron.schedule('ingest-indices-daily', '0 21 * * *', $CRON$
  select net.http_post(
    'https://smddzybxebwhfnitxuyp.supabase.co/functions/v1/ingest-indices',
    body := jsonb_build_object(
      'symbols', array['SPY','QQQ','DIA','IWM','GLD','SLV','URTH','EEM','EFA','EWQ','FEZ','USO'],
      'start', to_char(now() - interval '8 days','YYYY-MM-DD"T"00:00:00"Z"')),
    headers := jsonb_build_object('Content-Type','application/json'),
    timeout_milliseconds := 60000);
$CRON$);

-- jobid: 10 | active: True | schedule: 25 */2 * * *
select cron.schedule('learning_feedback_auto', '25 */2 * * *', $CRON$select public.populate_learning_feedback()$CRON$);

-- jobid: 18 | active: True | schedule: 55 */6 * * *
select cron.schedule('marees_apprentissage', '55 */6 * * *', $CRON$select public.marees_evaluate_and_learn();$CRON$);

-- jobid: 17 | active: True | schedule: 50 */6 * * *
select cron.schedule('marees_rebuild_virtual_6h', '50 */6 * * *', $CRON$ select public.marees_rebuild_virtual(); $CRON$);

-- jobid: 11 | active: True | schedule: 40 * * * *
select cron.schedule('reconcile_orders_horaire', '40 * * * *', $CRON$select net.http_post(
      url := 'https://smddzybxebwhfnitxuyp.supabase.co/functions/v1/reconcile-orders',
      headers := '{"Content-Type":"application/json"}'::jsonb,
      body := '{}'::jsonb);$CRON$);

-- jobid: 4 | active: True | schedule: 0 8 * * *
select cron.schedule('revolut_point_quotidien', '0 8 * * *', $CRON$ select net.http_post(url := 'https://smddzybxebwhfnitxuyp.supabase.co/functions/v1/revolut-portfolio-summary', headers := '{"Content-Type":"application/json"}'::jsonb, body := '{}'::jsonb, timeout_milliseconds := 20000); $CRON$);
