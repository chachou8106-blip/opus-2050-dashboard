-- =====================================================================================
-- 26/08/2026 — L'AGENT REÇOIT LA MESURE, JAMAIS LA CONCLUSION
--
-- Trois endroits où j'avais écrit MES conclusions sur le chemin des agents ou des messages
-- de Chachou. Le robot doit apprendre de ses erreurs et se corriger lui-même : lui dicter la
-- correction supprime l'apprentissage, il ne fait plus qu'obéir.
--
-- Appliqué et vérifié en direct. Sauvegarde : bak_20260826_breakers_notes.
-- =====================================================================================


-- -------------------------------------------------------------------------------------
-- 1/3 — sages_coaching() : le taux est mesuré, les verbes étaient de moi.
--
-- Avant : 'Macro=61.3pct MOYEN affine | Memoire=82.4pct FIABLE garde ta ligne |
--          X=38.0pct FAIBLE baisse ta conviction et sois prudent'
-- Après : 'Macro=61.3pct sur 194 verdicts evalues | Memoire=82.4pct sur 188 verdicts evalues'
--
-- Cette chaîne part dans le prompt des 5 Sages (champ COACHING) et dans FIABILITE_SAGES
-- du module Make 215.
-- -------------------------------------------------------------------------------------
create or replace function public.sages_coaching()
returns text
language sql
stable security definer
set search_path to 'public'
as $function$
  select coalesce(string_agg(
    s.sage || '=' ||
    case when s.taux_reussite is null or coalesce(s.evalue,0) = 0
         then 'sans bilan'
         else s.taux_reussite || 'pct sur ' || s.evalue || ' verdicts evalues'
    end, ' | ' order by s.sage), 'aucun bilan disponible pour le moment')
  from public.evaluate_sages(24, 0.5) s;
$function$;


-- -------------------------------------------------------------------------------------
-- 2/3 — check_circuit_breakers : les notes ne concluent plus.
--
-- Elles atteignent TOUS les agents via get_oracle_context().active_circuit_breakers.
-- Appliqué par remplacement ciblé sur la définition existante, avec garde d'occurrence
-- (échec si un motif n'est pas trouvé exactement une fois).
--
--   'Drawdown critique : poids reduit au plancher par update-brain'
--     -> 'Drawdown mesure X% ; seuil 8%'
--   'Drawdown >= 5% : poids coupe de moitie par update-brain'
--     -> 'Drawdown mesure X% ; seuil 5%'
--   '5+ runs perdants consecutifs : reduire les tailles et couper les positions perdantes'
--     -> 'Pertes consecutives mesurees : N ; seuil 5'
--   '... pendant une serie perdante. Changer de these ou ne rien faire, ne pas repeter.'
--     -> '... pendant une serie perdante (streak_type = loss).'
--   'Win rate X% sur N decisions evaluees : le probleme est la SELECTION, pas la frequence.
--    Moins de decisions, plus de conviction.'
--     -> 'Win rate X% sur N decisions evaluees ; seuil 40%'
--
-- Et action_taken : 'poids_plancher_0.05', 'poids_coupe_moitie' et 'force_contrarian'
-- décrivent une action que le système APPLIQUE réellement — ce sont des faits, gardés.
-- 'selection_a_revoir' ne correspondait à AUCUNE action automatique (vérifié : aucune autre
-- fonction ne lit cette valeur) : c'était une consigne déguisée en libellé.
--     -> 'aucune_action_automatique'
--
-- Les lignes DÉJÀ en base ont été corrigées de la même façon : corriger la fonction ne suffit
-- pas, ce sont les lignes non résolues qui partent dans les prompts à chaque run.
-- Résultat vérifié dans get_oracle_context() :
--   GIL    drawdown_8pct    "Drawdown mesure 10.23% ; seuil 8%"
--   GIL    drawdown_5pct    "Drawdown mesure 6.26% ; seuil 5%"
--   MAREES win_rate_faible  "Win rate 30.8% ; seuil 40%"
-- -------------------------------------------------------------------------------------


-- -------------------------------------------------------------------------------------
-- 3/3 — generate_daily_journal §6 : plus d'arbitrage, plus de valeurs en dur.
--
-- Retiré du point quotidien (3 messages par jour) :
--   « Regle : le de-staking coute surtout le delai (Nj sans pouvoir vendre) ; le rendement
--     perdu est minime. Garder de preference les APY eleves (ATOM 21%, TON 17.67%) ;
--     liberer les autres si un trade le justifie. »
--
-- Deux défauts en une phrase : c'est mon arbitrage, et il porte des valeurs EN DUR alors que
-- v_staking_point donne ces chiffres en direct dans le tableau juste au-dessus.
--
-- Le tableau reste — c'est la mesure. La conclusion revient à l'Alchimiste, dont le verdict
-- est journalisé dans alc_destake_reco. Section 6 après nettoyage, sortie réelle :
--   6) DE-STAKING (action manuelle, reco) :
--      • TON : investi 11.54$, vaut 8.40$ (P&L -27.2%) | staking +0.20221355 TON
--        (APY 17.67%), deblocage 2j, cout de-staking ~0.008$
--      • ATOM : ... (7 lignes, toutes mesurées)
-- -------------------------------------------------------------------------------------
