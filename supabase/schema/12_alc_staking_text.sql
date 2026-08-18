-- ============================================================================
-- 12_alc_staking_text.sql — vues texte du staking (source = v_staking_point EXISTANTE)
-- ----------------------------------------------------------------------------
-- L'Alchimiste recevait STAKING_APY_B64 / STAKING_DELAIS_B64 en base64(toString(<array>))
-- → toString d'un tableau rend une chaîne vide → « tables encodées vides ».
-- Ces 2 vues projettent la vue EXISTANTE `v_staking_point` (qui contient déjà apy_pct +
-- unbonding_jours + valeur live + coût de dé-stake, limitée aux coins réellement détenus)
-- en UNE chaîne lisible « DEV:val | … ». Aucune donnée ajoutée : simple reformattage.
--
-- Côté Make : modules 20022/20023 lisent ces vues avec l'en-tête
-- `Accept: application/vnd.pgrst.object+json` (PostgREST renvoie alors un OBJET, pas un
-- tableau) → mapping Alchimiste `base64(ifempty(20022.data.delais_texte; emptystring))`
-- et `…20023.data.apy_texte…` (SANS index [1], qui ne se résolvait pas).
-- ============================================================================
create or replace view public.v_alc_staking_apy_txt as
select coalesce(string_agg(devise || ':' || apy_pct || '%', ' | ' order by devise), '') as apy_texte
from public.v_staking_point where apy_pct is not null;

create or replace view public.v_alc_staking_delais_txt as
select coalesce(string_agg(devise || ':' || unbonding_jours || 'j', ' | ' order by devise), '') as delais_texte
from public.v_staking_point where unbonding_jours is not null;

grant select on public.v_alc_staking_apy_txt to anon, authenticated, service_role;
grant select on public.v_alc_staking_delais_txt to anon, authenticated, service_role;
