-- v_dernier_prix — le dernier cours connu de chaque symbole.
--
-- 02/09/2026. L'ancienne version faisait :
--     SELECT DISTINCT ON (symbol) ... FROM price_history ORDER BY symbol, ts DESC
-- soit un parcours des 575 000 lignes de price_history (371 081 buffers) pour en
-- rendre 331. La table grossit toutes les 5 minutes : la vue ralentissait un peu
-- plus chaque jour, et elle portait a elle seule la moitie du temps de reponse du
-- bloc `suivi` de la console (5 827 ms mesures).
--
-- Ici : parcours d'index par sauts. On construit la liste des symboles par
-- descentes successives dans idx_price_history_sym_ts_desc (index qui EXISTAIT
-- deja, rien n'a ete ajoute), puis un ORDER BY ts DESC LIMIT 1 par symbole.
-- C'est le meme motif que v_live_crypto_positions, qui tenait deja 1 ms.
--
-- Mesure : 5 827 ms -> 19 ms. Sortie identique a l'ancienne, verifiee dans les
-- deux sens (EXCEPT dans un sens et dans l'autre : 0 ligne de difference, 331 de
-- part et d'autre).
--
-- Dependances : v_alc_virtuel_positions, v_alc_reel_live_positions (et donc
-- v_alc_reel_live_resume). Verifie via pg_depend avant remplacement.

create or replace view v_dernier_prix as
with recursive k as (
  (select symbol from price_history order by symbol limit 1)
  union all
  select (select p.symbol from price_history p where p.symbol > k.symbol order by p.symbol limit 1)
  from k where k.symbol is not null
)
select s.symbol,
       replace(replace(upper(s.symbol), '-USD', ''), '/USD', '') as base,
       d.prix,
       d.ts
from (select symbol from k where symbol is not null) s
cross join lateral (
  select ph.close as prix, ph.ts
  from price_history ph
  where ph.symbol = s.symbol
  order by ph.ts desc
  limit 1
) d;
