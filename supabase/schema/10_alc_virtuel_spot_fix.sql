-- ============================================================================
-- 10_alc_virtuel_spot_fix.sql — Alchimiste virtuel : simulation SPOT correcte (FIFO)
-- Remplace les définitions de 03_functions.sql (alc_rebuild_virtual) et
-- 02_views.sql (v_alc_virtuel_jour / v_alc_virtuel_resume).
-- ============================================================================
-- BUG corrigé (17/08) : l'ancienne simulation traitait chaque `sell` comme
-- l'ouverture d'un SHORT (tp = prix*0.95, sl = prix*1.04, pnl = 1 - close/entrée).
-- Or l'Alchimiste est SPOT (Revolut X, pas de short) : un `sell` = vente d'un actif
-- DÉTENU pour prendre son profit / passer en cash. Résultat du bug : toute vente-profit
-- correcte était comptée en perte dès que le prix remontait après → le virtuel affichait
-- ~-10 % alors que ~90 % venait de 10 ventes de coins hérités shortées à tort.
--
-- MODÈLE CORRECT (FIFO spot) :
--   BUY  -> ouvre un lot long (fallback TP +5% / SL -4%, sinon mark-to-market = OUVERT).
--   SELL -> clôture le(s) lot(s) d'achat le(s) plus ancien(s) (FIFO) et réalise le vrai
--           gain spot (prix_vente/prix_achat - 1).
--   SELL sans achat virtuel correspondant (coin HÉRITÉ) -> 'VENTE_LEGACY', hors P&L
--           (en spot on ne score pas la vente d'un actif jamais acheté par le bot).
-- Les vues ne comptent QUE les trades scorables (pnl_pct IS NOT NULL).
-- ============================================================================

CREATE OR REPLACE FUNCTION public.alc_rebuild_virtual(p_fee_pct double precision DEFAULT 0.18, p_max_hold_h integer DEFAULT 240)
 RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
declare
  r record; v_lot record; v_hit record;
  v_rem float8; v_match float8; v_pnl float8; v_close float8; v_res jsonb;
begin
  truncate public.alchimiste_virtual_trades;
  drop table if exists _alc_lots;
  create temp table _alc_lots(lot_id serial, prop_id bigint, paire text, entry float8, montant float8, t0 timestamptz);
  for r in
    select id, paire, lower(side) as side, prix_ref::float8 as px, montant::float8 as m, proposed_at as t0
    from alchimiste_crypte_propositions
    where statut in ('expiree','proposee') and prix_ref > 0 and paire not in ('USDT-USD','USDC-USD','EUR-USD')
    order by proposed_at asc, id asc
  loop
    if r.side = 'buy' then
      insert into _alc_lots(prop_id, paire, entry, montant, t0) values (r.id, r.paire, r.px, r.m, r.t0);
    elsif r.side = 'sell' then
      v_rem := r.m;
      loop
        select * into v_lot from _alc_lots where paire = r.paire order by lot_id asc limit 1;
        exit when not found or v_rem <= 0;
        v_match := least(v_lot.montant, v_rem);
        v_pnl := (r.px / v_lot.entry - 1) * 100 - 2*p_fee_pct;
        insert into public.alchimiste_virtual_trades
          (proposition_id, paire, side, prix_entree, montant, opened_at, tp_pct, sl_pct, exit_ts, prix_sortie, exit_reason, pnl_pct, hold_hours, is_open)
        values (v_lot.prop_id, r.paire, 'buy', v_lot.entry, v_match, v_lot.t0, 5, 4, r.t0, r.px, 'VENTE', round(v_pnl::numeric,4), extract(epoch from (r.t0 - v_lot.t0))/3600, false);
        if v_lot.montant <= v_rem + 1e-9 then v_rem := v_rem - v_lot.montant; delete from _alc_lots where lot_id = v_lot.lot_id;
        else update _alc_lots set montant = montant - v_rem where lot_id = v_lot.lot_id; v_rem := 0; end if;
      end loop;
      if v_rem > 0 then
        insert into public.alchimiste_virtual_trades
          (proposition_id, paire, side, prix_entree, montant, opened_at, tp_pct, sl_pct, exit_ts, prix_sortie, exit_reason, pnl_pct, hold_hours, is_open)
        values (r.id, r.paire, 'sell', r.px, v_rem, r.t0, 5, 4, r.t0, r.px, 'VENTE_LEGACY', null, 0, false);
      end if;
    end if;
  end loop;
  for v_lot in select * from _alc_lots loop
    v_hit := null;
    select ph.ts as ts, case when ph.high >= v_lot.entry*1.05 then 'TP' else 'SL' end as motif into v_hit
    from price_history ph
    where ph.symbol = v_lot.paire and ph.interval='1h' and ph.ts > v_lot.t0 and ph.ts <= v_lot.t0 + (p_max_hold_h||' hours')::interval
      and (ph.high >= v_lot.entry*1.05 or ph.low <= v_lot.entry*0.96)
    order by ph.ts asc limit 1;
    if v_hit.ts is not null then
      insert into public.alchimiste_virtual_trades
        (proposition_id, paire, side, prix_entree, montant, opened_at, tp_pct, sl_pct, exit_ts, prix_sortie, exit_reason, pnl_pct, hold_hours, is_open)
      values (v_lot.prop_id, v_lot.paire, 'buy', v_lot.entry, v_lot.montant, v_lot.t0, 5, 4, v_hit.ts,
        case when v_hit.motif='TP' then v_lot.entry*1.05 else v_lot.entry*0.96 end, v_hit.motif,
        case when v_hit.motif='TP' then 5 - 2*p_fee_pct else -4 - 2*p_fee_pct end, extract(epoch from (v_hit.ts - v_lot.t0))/3600, false);
    else
      select ph.close into v_close from price_history ph where ph.symbol=v_lot.paire and ph.interval='1h' order by ph.ts desc limit 1;
      insert into public.alchimiste_virtual_trades
        (proposition_id, paire, side, prix_entree, montant, opened_at, tp_pct, sl_pct, exit_ts, prix_sortie, exit_reason, pnl_pct, hold_hours, is_open)
      values (v_lot.prop_id, v_lot.paire, 'buy', v_lot.entry, v_lot.montant, v_lot.t0, 5, 4, null, v_close, 'OUVERT',
        case when v_close is not null then round(((v_close/v_lot.entry - 1)*100)::numeric,4) else null end, null, true);
    end if;
  end loop;
  drop table if exists _alc_lots;
  select jsonb_build_object(
    'trades_total', (select count(*) from alchimiste_virtual_trades),
    'round_trips_clos', (select count(*) from alchimiste_virtual_trades where exit_reason='VENTE'),
    'tp', (select count(*) from alchimiste_virtual_trades where exit_reason='TP'),
    'sl', (select count(*) from alchimiste_virtual_trades where exit_reason='SL'),
    'ouvertes', (select count(*) from alchimiste_virtual_trades where is_open),
    'ventes_legacy_hors_pnl', (select count(*) from alchimiste_virtual_trades where exit_reason='VENTE_LEGACY'),
    'win_rate', (select round((count(*) filter (where pnl_pct>0 and exit_reason in ('VENTE','TP','SL')))::numeric
                   / nullif(count(*) filter (where exit_reason in ('VENTE','TP','SL') and pnl_pct is not null),0)*100,1)
                 from alchimiste_virtual_trades),
    'esperance_pct', (select round((avg(pnl_pct) filter (where exit_reason in ('VENTE','TP','SL')))::numeric,3) from alchimiste_virtual_trades),
    'somme_rendements_pct', (select round((sum(pnl_pct) filter (where exit_reason in ('VENTE','TP','SL')))::numeric,1) from alchimiste_virtual_trades)
  ) into v_res;
  return v_res;
end $function$;

-- Vues : ne compter QUE les trades scorables (pnl_pct IS NOT NULL) -> exclut VENTE_LEGACY.
create or replace view public.v_alc_virtuel_jour as
with j as (
  select ((exit_ts at time zone 'UTC'))::date as jour,
    count(*) as n_trades,
    count(*) filter (where pnl_pct > 0) as gagnants,
    (sum(montant*pnl_pct)/nullif(sum(montant),0)) as ret_pct
  from alchimiste_virtual_trades
  where not is_open and exit_ts is not null and pnl_pct is not null
  group by (((exit_ts at time zone 'UTC'))::date)
)
select jour, n_trades, gagnants,
  round(((gagnants)::numeric/(nullif(n_trades,0))::numeric)*100,1) as wr_pct,
  round((ret_pct)::numeric,3) as ret_pct,
  round((((exp(sum(ln((1)::double precision + (ret_pct/(100)::double precision))) over (order by jour)) - (1)::double precision)*(100)::double precision))::numeric,2) as cumul_pct
from j;

create or replace view public.v_alc_virtuel_resume as
with c as (
  select proposition_id, paire, side, prix_entree, montant, opened_at, tp_pct, sl_pct,
         exit_ts, prix_sortie, exit_reason, pnl_pct, hold_hours, is_open, rebuilt_at
  from alchimiste_virtual_trades
  where not is_open and exit_ts is not null and pnl_pct is not null
)
select
  (select count(*) from c) as trades_clos,
  (select round(((count(*) filter (where c.pnl_pct>0))::numeric/(nullif(count(*),0))::numeric)*100,1) from c) as wr_pct,
  (select round((avg(c.pnl_pct))::numeric,3) from c) as pnl_moy_pct,
  (select v_alc_virtuel_jour.cumul_pct from v_alc_virtuel_jour order by v_alc_virtuel_jour.jour desc limit 1) as cumul_pct,
  (select count(*) from alchimiste_virtual_trades where is_open) as positions_ouvertes,
  (select round((sum(montant))::numeric,2) from alchimiste_virtual_trades where is_open) as expo_ouverte,
  (select min(opened_at) from alchimiste_virtual_trades) as depuis,
  (select max(c.exit_ts) from c) as dernier;
