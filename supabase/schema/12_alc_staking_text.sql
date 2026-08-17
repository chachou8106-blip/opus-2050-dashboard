-- ============================================================================
-- 12_alc_staking_text.sql — vues « texte prêt pour l'IA » du staking Alchimiste
-- ----------------------------------------------------------------------------
-- Raison (17/08) : l'Alchimiste recevait STAKING_APY_B64 / STAKING_DELAIS_B64 en
-- base64(toString(<array PostgREST>)) → toString d'un tableau d'objets rend une
-- chaîne vide → l'Alchimiste croyait ses « tables encodées vides » (idem prix, mais
-- côté prix la fonction revolut-x-prices exposait déjà prix_texte, inutilisé par le
-- mapping). Ces vues renvoient UNE chaîne « DEV:val | DEV:val » directement lisible,
-- que Make encode en base64 puis que l'Alchimiste décode. Lecture seule, additif.
-- Le mapping Make est corrigé côté Maia (voir docs/decisions/PROMPT-MAIA-ALCHIMISTE-PRIX-2026-08-17.md).
-- ============================================================================
create or replace view public.v_alc_staking_apy_txt as
select coalesce(string_agg(devise || ':' || apy_pct || '%', ' | ' order by devise), '') as apy_texte
from public.alc_staking_apy;

create or replace view public.v_alc_staking_delais_txt as
select coalesce(string_agg(devise || ':' || unbonding_jours || 'j', ' | ' order by devise), '') as delais_texte
from public.alc_staking_delais;

grant select on public.v_alc_staking_apy_txt to anon, authenticated, service_role;
grant select on public.v_alc_staking_delais_txt to anon, authenticated, service_role;
