-- ============================================================================
-- CONSOLE AETHER — remise en accord avec la réalité du terrain
-- 22/08/2026 · demandé par Chachou après le point général du même jour
--
-- Aucun de ces objets n'est relu par un prompt d'agent (cf. la liste des textes
-- Supabase qui atteignent un prompt, dans CLAUDE.md) et aucun ne touche à
-- l'exécution d'ordres. Ce sont uniquement des objets d'affichage.
--
-- Migrations appliquées, dans l'ordre :
--   console_verite_terrain_1_dashboard_snapshot
--   console_verite_terrain_2_metrics_perf_friction
--   console_verite_terrain_3_perf_resume_friction
--   vigie_sage_ayant_reparle_depuis_le_run_audite
--   vigie_alert_gras_discord_espace_parasite
-- ============================================================================


-- ---------------------------------------------------------------------------
-- 1) dashboard_snapshot() — fuseau horaire et positions fantômes
--
-- FUSEAU. Toutes les heures étaient produites par to_char() sans conversion,
-- donc en UTC (la session Postgres est en UTC) et sans mention du fuseau, alors
-- que les blocs servis par oracle-inbox arrivent en ISO et sont convertis en
-- heure de Paris par le navigateur. Le même run s'affichait 07:05 sur un onglet
-- et 09:05 sur un autre. Huit to_char() passent en Europe/Paris : genere_a,
-- runs, cerveau.maj, meta_cerveau.maj, sante_flux.quand, propositions.quand,
-- ordres_recents.quand, debug_execution.quand, performance_historique.jour et
-- stats.premier_run_historique.
--
-- POSITIONS FANTÔMES. Alpaca laisse des résidus crypto à qty = 1e-9 avec un
-- prix d'entrée moyen négatif (SOLUSD de GIL : avg_entry_price =
-- -188 325 097 639 587). Leur unrealized_pl aberrant gonflait positions_vivantes
-- de +324 985 $ : GIL affichait +203 849 $ au lieu de +15 524 $, JU +136 308 $
-- au lieu de -355 $. Un prix ne peut pas être négatif : ces lignes sont écartées
-- des sommes et du détail, et comptées à part dans nb_aberrantes.
-- ---------------------------------------------------------------------------
-- Corps complet : voir la migration console_verite_terrain_1_dashboard_snapshot.
-- Les deux corrections, en résumé :
--   'maj', to_char(updated_at at time zone 'Europe/Paris','MM-DD HH24:MI')
--   count(*)            filter (where coalesce(avg_entry_price,0) > 0)  as nb
--   sum(unrealized_pl)  filter (where coalesce(avg_entry_price,0) > 0)  as pl_latent_total
--   sum(market_value)   filter (where coalesce(avg_entry_price,0) > 0)  as valeur_marche_totale
--   count(*)            filter (where coalesce(avg_entry_price,0) <= 0) as nb_aberrantes
-- et, dans positions_detail :  where coalesce(avg_entry_price,0) > 0


-- ---------------------------------------------------------------------------
-- 2) ju_archimage_metrics — un seul compte de positions, et plus d'extrêmes faux
--
-- Deux compteurs coexistaient dans la console : cette vue ne comptait que les
-- lignes >= 50 $ (26 / 21 / 19) tandis que positions_vivantes les comptait
-- toutes (28 / 26 / 22). Désormais : UN seul compte, celui des positions
-- réelles, et l'argent (pnl_usd) sur ces mêmes lignes. Les statistiques de
-- dispersion restent mesurées sur les lignes significatives (>= 50 $) : la
-- poussière a des pourcentages erratiques qui n'apprennent rien.
--
-- Effet de bord vérifié : le filtre avg_entry_price > 0 a fait tomber
-- meilleur_pct de GIL de 456,03 % à 18,12 % et sa volatilité de 87,41 à 7,57.
-- Une quatrième ligne aberrante passait le filtre |market_value| >= 50 et
-- faussait ces deux statistiques depuis des semaines.
-- ---------------------------------------------------------------------------
create or replace view public.ju_archimage_metrics as
select archimage,
  count(*)                                                                   as positions,
  round(avg(unrealized_pl_pct) filter (where abs(market_value) >= 50), 2)    as rendement_moyen_pct,
  round(count(*) filter (where abs(market_value) >= 50 and unrealized_pl_pct > 0)::numeric * 100.0
        / nullif(count(*) filter (where abs(market_value) >= 50), 0)::numeric, 1) as pct_gagnantes,
  round(avg(unrealized_pl_pct) filter (where abs(market_value) >= 50 and unrealized_pl_pct > 0), 2) as gain_moyen_pct,
  round(avg(unrealized_pl_pct) filter (where abs(market_value) >= 50 and unrealized_pl_pct < 0), 2) as perte_moyenne_pct,
  round(max(unrealized_pl_pct) filter (where abs(market_value) >= 50), 2)    as meilleur_pct,
  round(min(unrealized_pl_pct) filter (where abs(market_value) >= 50), 2)    as pire_pct,
  round(stddev_pop(unrealized_pl_pct) filter (where abs(market_value) >= 50), 2) as volatilite_pct,
  round(avg(unrealized_pl_pct) filter (where abs(market_value) >= 50)
        / nullif(stddev_pop(unrealized_pl_pct) filter (where abs(market_value) >= 50), 0), 3) as sharpe_like,
  round(avg(unrealized_pl_pct) filter (where abs(market_value) >= 50 and unrealized_pl_pct > 0)
        / nullif(abs(avg(unrealized_pl_pct) filter (where abs(market_value) >= 50 and unrealized_pl_pct < 0)), 0), 2) as ratio_gain_perte,
  round(sum(unrealized_pl), 2)                                               as pnl_usd,
  count(*) filter (where abs(market_value) >= 50)                            as positions_significatives
from public.oracle_positions_live
where coalesce(avg_entry_price, 0) > 0   -- écarte les résidus Alpaca (prix d'entrée négatif)
group by archimage;


-- ---------------------------------------------------------------------------
-- 3) v_perf_resume — MARÉES et ALCHIMISTE cessent d'être vides
--
-- La ligne MAREES était codée en dur à NULL, NULL, NULL : la vue a été écrite
-- avant que Marées ait le moindre trade. Il en a 40 aujourd'hui. Idem pour le
-- rendement de l'ALCHIMISTE, laissé à NULL alors que v_alc_virtuel_jour le
-- calcule. Les deux lisent maintenant leurs vraies tables.
--
-- Rendement retenu : le cumul JOURNALIER pondéré par les montants engagés
-- (v_alc_virtuel_jour.cumul_pct = 17,42 %), et non le composé trade par trade
-- (alc_stats.rendement_compose_pct = 59,7 %) qui suppose 100 % du capital sur
-- chaque trade — une hypothèse qu'aucun portefeuille ne peut tenir.
-- ---------------------------------------------------------------------------
create or replace view public.v_perf_resume as
select archimage as trader,
       round(cumulative_pnl / nullif(baseline_equity, 0) * 100, 2) as rendement_pct,
       round(max_drawdown * 100, 2)                                as drawdown_max_pct,
       round(win_rate * 100, 1)                                    as reussite_pct,
       'simulation'::text                                          as statut,
       'juin–août 2026'::text                                      as periode
  from public.oracle_brain_state
 where archimage = any (array['JU','SYL','GIL'])
union all
select 'ALCHIMISTE',
       (select round(cumul_pct, 2) from public.v_alc_virtuel_jour order by jour desc limit 1),
       null::numeric,
       (select wr_pct from public.v_alc_virtuel_resume),
       'reel_imminent',
       'validation'
union all
select 'MAREES',
       (select round((exp(sum(ln(1 + pnl_pct/100.0))) - 1)::numeric * 100, 2)
          from public.marees_virtual_trades
         where not is_open and pnl_pct is not null and pnl_pct > -100),
       null::numeric,
       (select round(count(*) filter (where pnl_pct > 0)::numeric * 100.0
                     / nullif(count(*), 0)::numeric, 1)
          from public.marees_virtual_trades
         where not is_open and pnl_pct is not null),
       'validation_precoce',
       'depuis juil.';


-- ---------------------------------------------------------------------------
-- 4) v_couts_friction — médiane au lieu d'une moyenne détruite par les extrêmes
--
-- « slippage moyen » affichait -22,5 % pour SYL, -19,3 % pour GIL, -9,8 % pour
-- JU. Ce ne sont pas des coûts de transaction : la médiane globale est à
-- 0,000 % et la moyenne est détruite par 233 valeurs aberrantes sur 741
-- (minimum -93,1 %), issues d'un prix de référence périmé au moment du calcul.
-- On publie la médiane — insensible aux extrêmes — sous le même nom de colonne,
-- et on expose le nombre d'aberrations pour qu'elles restent visibles au lieu
-- d'être noyées. Nouvelles valeurs : GIL -1,945 · JU 0,000 · SYL -1,960,
-- avec 73 / 63 / 97 aberrations sur 200 / 334 / 207 mesures — proportion qui
-- reste à expliquer, mais qui est désormais affichée au lieu d'être diluée.
-- ---------------------------------------------------------------------------
create or replace view public.v_couts_friction as
select archimage,
  count(*)                                                                   as ordres_executes,
  round(sum(coalesce(executed_notional, notional, 0)), 0)                    as notional_total,
  round(sum(coalesce(executed_notional, notional, 0)
        * case when asset_class = 'crypto' then 0.0025 else 0.0002 end), 2)  as cout_estime_usd,
  round((percentile_cont(0.5) within group (order by slippage_pct)
         filter (where slippage_pct is not null))::numeric, 3)               as slippage_achats_moyen_pct,
  round(sum(coalesce(executed_notional, notional, 0)
        * case when asset_class = 'crypto' then 0.0025 else 0.0002 end)
        / nullif(sum(coalesce(executed_notional, notional, 0)), 0) * 100, 3) as friction_moyenne_pct,
  count(*) filter (where slippage_pct is not null)                           as slippage_mesures,
  count(*) filter (where slippage_pct is not null and abs(slippage_pct) > 5) as slippage_aberrants
from public.oracle_college_orders
where broker_status = any (array['filled','partially_filled'])
group by archimage;


-- ---------------------------------------------------------------------------
-- 5) vigie_scan() — un Sage qui a reparlé depuis le run audité n'est plus en PANNE
--
-- vigie_scan audite la fenêtre [dernier run - 15 min, dernier run + 5 min].
-- Le dernier run COMPLET du Collège date du 21/08 09h05 ; le Sage Macro y était
-- effectivement muet, d'où l'état PANNE. Mais Macro a reproduit le 22/08 à
-- 10h51, lors d'un run qui s'est interrompu avant d'écrire sa ligne dans
-- oracle_college_runs. La Vigie affichait donc PANNE pour un composant qui
-- fonctionne — et pointait elle-même une derniere_sortie POSTÉRIEURE au run
-- qu'elle auditait, ce qui se contredisait à l'écran.
--
-- Branche ajoutée, avant la branche PANNE :
--
--   elsif v_cnt = 0 and v_last is not null and v_last > v_we then
--     v_etat := 'OK';
--     v_detail := format('a produit le %s, posterieurement au run audite',
--                        to_char(v_last at time zone 'Europe/Paris','DD/MM HH24:MI'));
--
-- Le cas « muet depuis toujours » (v_last null ou antérieur) reste PANNE.
-- Appliquée par pg_get_functiondef + replace, avec exception si l'ancre
-- n'est pas trouvée. Corps complet : voir la définition en base.


-- ---------------------------------------------------------------------------
-- 6) vigie_alert() — le titre Discord ne s'affichait plus en gras
--
-- Résidu de la correction emoji du 21/08 : le titre était composé
--   '** ' || chr(128301) || ' La Vigie...'
-- Un espace placé juste après les deux astérisques annule le gras Markdown chez
-- Discord : Chachou voyait « ** 🔭 La Vigie — anomalie detectee** » en texte
-- brut, astérisques comprises. Les deux occurrences sont recollées :
--   '**' || chr(128301) || ' La Vigie...'
