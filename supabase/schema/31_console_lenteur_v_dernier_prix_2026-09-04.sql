-- La console mettait plus de 25 secondes a charger. 04/09/2026, apres le run de 15h45.
-- Controle demande par Chachou : « va tout controler et regarde si tout fonctionne bien
-- dans ma console ». Les douze appels du demarrage ont ete rejoues un par un depuis la base.
-- Onze repondent 200. Le douzieme, oracle-inbox action=suivi, a EXPIRE a 25 000 ms.
-- C'est le bloc qui alimente huit affichages (kpis, gains, strats, comparaison, overview,
-- stats, tables, alchimiste) et il est rafraichi toutes les 2 minutes.

-- ---------------------------------------------------------------------------
-- 1. LA MESURE, ET LA PREMIERE QUI ETAIT FAUSSE
-- ---------------------------------------------------------------------------
-- Premier chronometrage des 22 vues du bloc : 4,45 s au total. Conclusion tentante et
-- FAUSSE : « ce n'est pas le SQL ». J'avais chronometre `select count(*) from v`, et sur un
-- count le planificateur saute une partie du travail. Rechronometre en materialisant chaque
-- ligne (`select count(md5(t::text)) from v t`), le total passe a 12,5 s et un coupable
-- ressort : v_alc_virtuel_positions, 6,4 s pour DEUX lignes.

-- ---------------------------------------------------------------------------
-- 2. LA CAUSE : v_dernier_prix
-- ---------------------------------------------------------------------------
-- v_alc_virtuel_positions joint v_dernier_prix, tout comme v_alc_reel_live_*, v_live_crypto_*
-- et les vues Marees. Or v_dernier_prix etait :
--     select distinct on (symbol) symbol, ..., close, ts from price_history order by symbol, ts desc
-- EXPLAIN ANALYZE : Index Scan sur idx_price_history_sym_ts_desc, 631 216 lignes lues pour
-- 376 lignes produites, 1,07 s. L'index EXISTE (verifie avant toute idee d'en creer un) et il
-- est bien utilise — mais Postgres n'a pas de « saut d'index » sur DISTINCT ON : il parcourt
-- toutes les bougies de tous les symboles pour ne garder que la derniere de chacun.
--
-- Remplacee par un parcours par sauts (loose index scan) : on avance de symbole en symbole
-- avec min(), puis on prend la derniere bougie de chacun par lateral. Meme index, 376 sondages
-- au lieu de 631 216 lignes.
--
-- EQUIVALENCE PROUVEE AVANT/APRES, pas supposee :
--     376 lignes des deux cotes
--     md5 identique : b20a37bda0523797caa0a7f7b0ab7a9e
--     0 ligne en trop (nouveau EXCEPT ancien), 0 manquante (ancien EXCEPT nouveau)
--
-- Effet mesure sur les 22 vues du bloc : 12,5 s -> 4,0 s.
--   v_alc_virtuel_positions  6456 ms -> hors des 6 plus lentes
--   v_alc_reel_live_resume    979 ms -> idem
--   v_alc_reel_live_positions 948 ms -> idem

-- ---------------------------------------------------------------------------
-- 3. CE QUE J'AI ESSAYE ENSUITE, ET ANNULE DANS LA DEMI-HEURE
-- ---------------------------------------------------------------------------
-- Il restait ~12 s : oracle-inbox enchaine 25 lectures PostgREST une par une. J'ai deploye une
-- v28 qui les regroupe en vagues de Promise.all (3, 5, 6 et 10 lectures). Resultat mesure :
--     duree : 41 s — PIRE qu'avant
--     stats  23 cles -> 0     avance  24 cles -> 0
--     sharpe 24 cles -> 0     mensuel 24 cles -> 0
-- Quatre affichages de la console revenaient VIDES. Les lectures concurrentes echouent cote
-- PostgREST, et sb() renvoie body:null sans bruit : arr(null) donne [], donc un ecran vide a
-- l'air d'un ecran sans donnees. C'est mot pour mot la panne du 02/09.
--
-- ANNULE : la v29 deployee est le fichier de la v27, inchange, avec un en-tete qui interdit de
-- recommencer. Verification apres retour arriere, sur la reponse en direct :
--     stats 23 · avance 24 · sharpe 24 · mensuel 24 · perf 6 · rendements 441 — identique au
--     releve d'avant l'essai.
--
-- CE QUI RESTE, ET COMMENT LE FAIRE : la console charge en ~12-20 s. Pour descendre il faut
-- reduire le NOMBRE d'allers-retours, pas les lancer en parallele : une RPC SQL unique qui
-- renvoie tout le bloc en un seul appel. C'est un chantier a part, a faire et a mesurer au
-- calme, pas en fin de session.

-- ---------------------------------------------------------------------------
-- 4. LE RESTE DE LA CONSOLE, VERIFIE CE JOUR
-- ---------------------------------------------------------------------------
-- inbox journal 200 (214 ko) · scenario-switch 200 · killswitch 200 (ON) · oracle-tests
-- hero/sages/runs/positions/bt_alchimiste/equity/alchimiste : 200 avec donnees.
-- dashboard_snapshot et v_exposition_traders : verifies en `set role anon`, 53 ko et 3 lignes
-- (mon premier essai les donnait en 401, mais c'est mon rejeu qui n'envoyait pas de cle,
-- pas la console).

-- ---------------------------------------------------------------------------
-- 5. LA VUE, TELLE QU'ELLE EST DESORMAIS EN BASE
-- ---------------------------------------------------------------------------
create or replace view public.v_dernier_prix as
with recursive syms as (
  (select min(symbol) as symbol from price_history)
  union all
  select (select min(p.symbol) from price_history p where p.symbol > s.symbol)
  from syms s where s.symbol is not null
)
select d.symbol,
       replace(replace(upper(d.symbol), '-USD', ''), '/USD', '') as base,
       d.prix,
       d.ts
from syms s
cross join lateral (
  select p.symbol, p.close as prix, p.ts
  from price_history p
  where p.symbol = s.symbol
  order by p.ts desc
  limit 1) d
where s.symbol is not null;
