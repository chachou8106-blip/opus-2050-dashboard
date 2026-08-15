-- Panneau Marées : positions virtuelles forex ouvertes, valorisées au dernier cours (mark-to-market).
-- Appliqué le 2026-08-15. Servi par oracle-inbox (suivi.marees_virtuel) et affiché dans la console.

CREATE OR REPLACE VIEW public.v_marees_virtuel_positions AS
WITH px AS (
  SELECT symbol, (array_agg(close ORDER BY ts DESC))[1]::float8 AS last
  FROM price_history WHERE interval='1h' GROUP BY symbol
)
SELECT t.paire, t.side,
  t.prix_entree::float8 AS prix_entree,
  px.last AS prix_actuel,
  round((CASE WHEN t.side='buy' THEN (px.last/nullif(t.prix_entree,0)-1)
              ELSE (1-px.last/nullif(t.prix_entree,0)) END * 100)::numeric, 2) AS unreal_pct,
  t.montant, t.tp_pct, t.sl_pct, t.opened_at,
  round(extract(epoch FROM now()-t.opened_at)/3600.0, 0) AS age_h
FROM marees_virtual_trades t
JOIN px ON px.symbol = t.paire
WHERE coalesce(t.is_open,false) = true;

CREATE OR REPLACE VIEW public.v_marees_virtuel_resume AS
SELECT
  (SELECT count(*) FROM v_marees_virtuel_positions) AS positions_ouvertes,
  (SELECT round((sum(unreal_pct*greatest(montant,0.0001))/nullif(sum(greatest(montant,0.0001)),0))::numeric,2)
     FROM v_marees_virtuel_positions) AS pnl_latent_pct,
  (SELECT round(sum(montant)::numeric,1) FROM v_marees_virtuel_positions) AS expo_poids,
  (SELECT max(proposed_at) FROM marees_propositions) AS derniere_proposition,
  (SELECT count(*) FROM marees_virtual_trades WHERE coalesce(is_open,false)=false AND exit_ts IS NOT NULL) AS trades_clos;
