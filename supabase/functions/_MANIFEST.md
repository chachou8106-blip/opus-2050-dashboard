# Supabase Edge Functions — Manifest

Project: `smddzybxebwhfnitxuyp` — exported deployed source. Generated 2026-08-14.

> ⚠️ **Secrets caviardés (`REDACTED`).** Plusieurs fonctions **anciennes** codent en dur des clés API
> (Perplexity, OpenAI, FRED, Finnhub, clés/secrets Alpaca JU/SYL/GIL, token MT5). Ces valeurs ont été
> remplacées par `REDACTED` / `PK_REDACTED` dans le repo — jamais commiter de secret. Les valeurs
> réelles vivent dans la fonction déployée (Supabase) / les variables d'environnement.
> **Amélioration de sécurité à faire** : migrer ces clés en dur vers `Deno.env.get(...)` comme le font
> déjà les fonctions récentes (Revolut X, oracle-inbox, ju-*). L'URL Supabase et la clé **anon** ne
> sont pas des secrets (publiques). Fonctions concernées par du secret en dur : `collect-market-data`,
> `update-brain`, `reconcile-orders`, `ingest-spy`, `ingest-indices`, `fx-context`, `mt5-bridge`.

| Function | Deployed version | verify_jwt | One-line purpose |
|---|---|---|---|
| collect-market-data | 12 | false | Aggregates macro/equities/crypto/forex/news + trading universe into one market snapshot for the archimages. |
| execute-trades | 34 | false | Places Alpaca paper orders from archimage trade lists with risk/momentum/exposure guards, auto take-profit/stop-loss and deleveraging. |
| update-brain | 15 | false | Recomputes each archimage's PnL, drawdown, win rate and synthesis weights, persisting brain state and performance rows. |
| confirm-fills | 9 | false | Reconciles recent Alpaca orders against their real broker status and records fills/slippage. |
| revolut-x-read | 9 | false | Read-only signed fetch of Revolut X balances, formatted as human-readable cash/liquid/stake text for the AI. |
| revolut-x-prices | 2 | false | Read-only signed fetch of Revolut X tickers (bid/ask/mid/last) with a readable price string. |
| revolut-x-trade | 7 | false | Guarded spot order sender for Revolut X (dry-run default, kill_switch + spot-only + daily/order caps). |
| ingest-klines | 3 | false | Ingests hourly OHLCV crypto candles from Binance klines into price_history (auto-discovers the crypto universe). |
| revolut-portfolio-summary | 5 | false | Daily Revolut X portfolio valuation (cash/liquid/stake) with price fallback, persisted and posted to Discord. |
| revx-staking-probe | 1 | false | Probes candidate Revolut X staking endpoints (read-only signed) to discover which respond. |
| ingest-spy | 1 | false | Ingests hourly SPY (equity) OHLCV bars from Alpaca into price_history for sage evaluation. |
| reconcile-orders | 2 | false | Hourly reconciliation of non-finalized Alpaca orders (any age) across JU/SYL/GIL to their real status. |
| oracle-tests | 10 | false | Dashboard/data API dispatching many read actions (hero, positions, sages, backtests, snapshot, etc.) via RPC/REST. |
| mt5-bridge | 3 | false | Token-protected text feed of signed position weights per mode (JU/SYL/GIL/COLLEGE) for a MetaTrader 5 EA mirror. |
| alc-auto | 6 | false | Executes the Alchimiste's spot proposals aligned to live Revolut X universe/balances (buy+sell), respecting money-locks. |
| ingest-fx | 2 | false | Ingests hourly forex OHLC candles from Yahoo Finance into price_history (anti-429 retries). |
| fx-context | 1 | false | Builds a dedicated forex context (FX rates, policy rates, 10y yields/differentials, DXY) for the Marees archimage. |
| marees-context | 1 | false | Assembles the full council view (config, sages, archimage actions, alchimiste, fx-context) for the Marees archimage in one call. |
| ingest-revx-prices | 2 | false | Ingests current-hour Revolut X prices into price_history, overwriting the current candle so fresh prices win. |
| ingest-gate-prices | 1 | false | Ingests hourly OHLC crypto candles from Gate.io for coins Binance delisted/lacks. |
| oracle-inbox | 14 | false | Chachou <-> robot channel: reads journal/problemes/rappels, a rich 'suivi' dashboard payload, and posts problem reports. |
| ingest-indices | 1 | false | Ingests hourly index/ETF OHLCV bars from Alpaca with pagination (next_page_token) into price_history. |
| ju-killswitch | 3 | false | Reads/toggles the Alchimiste kill_switch; arming ON requires the server-side PIN, OFF/status are free. |
| ju-passkey | 2 | false | WebAuthn (Face ID) passkey register/auth to arm the kill-switch or unlock the technical menu, with PIN fallback. |
