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
--
-- ATTENTION : cette première version composait MARÉES trade par trade — le défaut
-- exact que la ligne au-dessus reproche à alc_stats, et qui donnait -3,01 % au lieu
-- de -0,27 %. Elle a été remplacée le soir même. La définition qui fait foi est
-- celle de la SECONDE PASSE, en fin de fichier. Ne pas rejouer ce bloc.
-- ---------------------------------------------------------------------------
-- (version périmée retirée — voir « v_perf_resume » dans la seconde passe)


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


-- ############################################################################
-- SECONDE PASSE — 22/08/2026 au soir, demande de Chachou :
-- « rien ne doit être écrit en dur, vérifie tous les calculs, tout doit être
--   transparent et vrai — c'est ma future vitrine d'abonnés »
--
-- Objets ajoutés / corrigés (migrations vitrine_1 à vitrine_7) :
--   v_equity_journalier   (nouveau) valeur des comptes = historique + jour courant
--   v_marees_virtuel_jour (nouveau) pendant de v_alc_virtuel_jour pour Marées
--   v_alc_reel_jour       (nouveau) performance Revolut X, apports déduits (TWR)
--   v_comparaison         courbes jusqu'au dernier état réel, date dérivée
--   v_equity_points       une seule unité, + colonnes unite / rendement_pct
--   v_perf_resume         MARÉES et ALCHIMISTE alimentés, rendement aligné
--   v_gains_traders       libellés conformes à la composition constatée
--   equity_series()       plus de /10000 ni de date en dur
--
-- CE QUE LA VITRINE AFFICHAIT DE FAUX, ET POURQUOI :
--
-- 1. GIL en positif alors qu'il est en perte.
--    alpaca_equity_daily vient de l'historique Alpaca, qui a un jour de retard ;
--    la valeur constatée est dans oracle_brain_state. Les courbes s'arrêtaient
--    donc au 20/08 : GIL affiché +1,56 % (1 015 563 $) contre -3,61 % réel
--    (963 914 $) sur l'onglet Stratégies. Cinq points d'écart entre deux onglets
--    pour le même agent, le même jour.
--
-- 2. Trois unités dans une colonne nommée « Valeur $ ».
--    v_equity_points renvoyait un GAIN pour les archimages, une VALEUR pour
--    l'Alchimiste, un nombre sans unité pour Marées. La tuile « Valeur actuelle »
--    montrait donc un gain, et le drawdown — calculé en (pic-valeur)/pic sur un
--    GAIN — donnait des pourcentages absurdes.
--
-- 3. Marées invisible.
--    « n'a pas encore de courbe de valeur » alors qu'il a 39 points depuis le
--    14/08. Il n'a pas de capital en dollars : il est dimensionné en poids. La
--    vue déclare maintenant son unité et la console trace sa courbe en %.
--
-- 4. Quatre méthodes de rendement pour deux portefeuilles virtuels.
--    Alchimiste : +0,163 % en courbe, +17,42 % en fiche. Marées : -0,072 % en
--    courbe, -3,01 % en fiche (ce dernier écrit par moi le matin même, et
--    reproduisant exactement le défaut que je venais de corriger sur alc_stats).
--    Convention unique : rendement du jour pondéré par les montants engagés,
--    puis composition des jours.
--
-- 5. Des apports de capital comptés comme performance.
--    Le portefeuille réel Revolut X affichait +84,1 % (553,27 $ -> 1 020,06 $).
--    Or le compte a reçu 100 $ le 07/07 (cash_usd 22,96 -> 122,96 le jour où le
--    total bondit de 558,61 à 664,27) et 2,52 $ le 14/08. Performance réelle,
--    en rendement chaîné : +55,87 %. Annoncer +84 % à de futurs abonnés aurait
--    été faux.
--
-- 6. Un capital de 3 000 000 $ écrit dans le code.
--    oracle-tests calculait l'alpha par gain/30000. Il le calcule désormais sur
--    la somme des baseline_equity lues (2 999 734 $). equity_series divisait par
--    10000 — un capital de 1 M$ supposé — et filtrait sur '2026-06-05', date
--    répétée à trois endroits. Elle est maintenant dérivée du premier jour où
--    les trois comptes sont suivis (ce qui redonne 2026-06-05, mais se corrigera
--    tout seul).
--
-- 7. GIL présenté comme « Crypto tactique ».
--    Mesure au 21/08 : 1 397 372 $ en actions et ETF, 56 $ en crypto — 0,004 %.
--
-- CONTRÔLE FINAL — le même agent, lu par trois chemins différents :
--   agent       onglet Marchés   onglet Stratégies   onglet Portefeuille   recalcul
--   GIL             -3,608            -3,61                -3,608           -3,61
--   JU               4,564             4,56                 4,564            4,56
--   SYL              6,747             6,75                 6,747            6,75
--   MARÉES          -0,273            -0,27                -0,27 (pct)         —
--   ALCHIMISTE      17,421            17,42  (virtuel)     55,87 (réel)         —
--   OPUS             2,568  = moyenne des trois = hero.rendement_moyen_pct 2,57
--
-- Les deux chiffres de l'Alchimiste sont deux portefeuilles distincts : le
-- virtuel de validation et le compte Revolut X. La console les nomme désormais
-- séparément (« Rendement virtuel » / « Rendement réel ») au lieu de les
-- présenter sous une seule étiquette.
-- ############################################################################

-- ---------------------------------------------------------------------------
-- DÉFINITIONS QUI FONT FOI (seconde passe). Elles remplacent, pour v_perf_resume,
-- le bloc marqué « version périmée » plus haut dans ce fichier.
-- ---------------------------------------------------------------------------

create or replace view public.v_equity_journalier as
with hist as (
  select e.archimage as trader, e.jour, e.equity::numeric as equity_usd, 'historique'::text as source
  from public.alpaca_equity_daily e
),
live as (
  -- le point du jour, absent de l'historique Alpaca ; jamais dupliqué
  select b.archimage, (b.updated_at at time zone 'Europe/Paris')::date,
         b.alpaca_portfolio_value::numeric, 'constate'::text
  from public.oracle_brain_state b
  where b.archimage in ('JU','SYL','GIL')
    and coalesce(b.alpaca_portfolio_value, 0) > 0
    and (b.updated_at at time zone 'Europe/Paris')::date
        > coalesce((select max(e.jour) from public.alpaca_equity_daily e
                     where e.archimage = b.archimage), 'epoch'::date)
)
select * from hist union all select * from live;

create or replace view public.v_marees_virtuel_jour as
with j as (
  select (exit_ts at time zone 'UTC')::date as jour, count(*) as n_trades,
         count(*) filter (where pnl_pct > 0) as gagnants,
         sum(montant * pnl_pct) / nullif(sum(montant), 0) as ret_pct
  from public.marees_virtual_trades
  where not is_open and exit_ts is not null and pnl_pct is not null
  group by 1
)
select jour, n_trades, gagnants,
       round(gagnants::numeric / nullif(n_trades, 0)::numeric * 100, 1) as wr_pct,
       round(ret_pct::numeric, 3) as ret_pct,
       round(((exp(sum(ln(1 + ret_pct / 100.0)) over (order by jour)) - 1) * 100)::numeric, 2) as cumul_pct
from j;

create or replace view public.v_alc_reel_jour as
with s as (
  select snapshot_at, snapshot_at::date as jour, total_usd, cash_usd,
         lag(total_usd) over (order by snapshot_at) as prev_total,
         lag(cash_usd)  over (order by snapshot_at) as prev_cash
  from public.revolut_portfolio_daily
  where total_usd >= 300
),
r as (
  select jour, total_usd, cash_usd,
         greatest(coalesce(cash_usd - prev_cash, 0), 0) as apport,
         case when prev_total is null or prev_total = 0 then null
              else (total_usd - greatest(coalesce(cash_usd - prev_cash, 0), 0)) / prev_total - 1 end as ret
  from s
)
select jour, round(total_usd, 2) as valeur_usd, round(apport, 2) as apport_usd,
       round((coalesce(ret, 0) * 100)::numeric, 3) as ret_pct,
       round(((exp(sum(ln(1 + greatest(coalesce(ret, 0), -0.999))) over (order by jour, total_usd)) - 1) * 100)::numeric, 2) as cumul_pct
from r;

create or replace view public.v_perf_resume as
select b.archimage as trader,
       round((b.alpaca_portfolio_value - b.baseline_equity) / nullif(b.baseline_equity, 0) * 100, 2) as rendement_pct,
       round(b.max_drawdown * 100, 2) as drawdown_max_pct,
       round(b.win_rate * 100, 1)     as reussite_pct,
       'simulation'::text             as statut,
       'juin–août 2026'::text         as periode
  from public.oracle_brain_state b
 where b.archimage = any (array['JU','SYL','GIL'])
union all
select 'ALCHIMISTE',
       (select round(cumul_pct, 2) from public.v_alc_virtuel_jour order by jour desc limit 1),
       null::numeric,
       (select wr_pct from public.v_alc_virtuel_resume),
       'reel_imminent', 'validation'
union all
select 'MAREES',
       (select round(cumul_pct, 2) from public.v_marees_virtuel_jour order by jour desc limit 1),
       null::numeric,
       (select round(count(*) filter (where pnl_pct > 0)::numeric * 100.0
                     / nullif(count(*), 0)::numeric, 1)
          from public.marees_virtual_trades where not is_open and pnl_pct is not null),
       'validation_precoce', 'depuis juil.';

create or replace view public.v_equity_points as
select e.trader, (e.jour + '20:00:00'::time)::timestamptz as ts, e.equity_usd as equity, 'usd'::text as unite,
       round((e.equity_usd - bs.baseline_equity) / nullif(bs.baseline_equity, 0) * 100, 3) as rendement_pct
from public.v_equity_journalier e
join public.oracle_brain_state bs on bs.archimage = e.trader
where bs.baseline_equity is not null
union all
select 'ALCHIMISTE', (j.jour + '20:00:00'::time)::timestamptz, j.valeur_usd, 'usd', j.cumul_pct
from public.v_alc_reel_jour j
union all
select 'MAREES', (j.jour + '20:00:00'::time)::timestamptz, null::numeric, 'pct', j.cumul_pct
from public.v_marees_virtuel_jour j;

-- v_comparaison et equity_series() : corps complets dans les migrations
--   vitrine_3_une_seule_convention_pour_les_virtuels
--   vitrine_6_equity_series_sans_constante_en_dur
