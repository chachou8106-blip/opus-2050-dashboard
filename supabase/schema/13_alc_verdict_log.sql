-- ============================================================================
-- 13_alc_verdict_log.sql — Journal du VERDICT de l'Alchimiste (commentaire + dé-stake)
-- ----------------------------------------------------------------------------
-- Angle mort comblé (17/08) : le raisonnement de l'Alchimiste (pourquoi il dé-stake
-- ou non) n'était stocké nulle part → invérifiable après coup. Make envoie désormais
-- sa sortie BRUTE (JSON) en base64 à la RPC log_alc_verdict, qui décode + parse côté
-- serveur (pas de toString cassant) et archive commentaire / destake / nb propositions.
-- Voir docs/decisions/PROMPT-MAIA-LOG-VERDICT-ALCHIMISTE-2026-08-17.md pour le module Make.
-- ============================================================================
create table if not exists public.alchimiste_crypte_verdicts (
  id             bigserial primary key,
  run_id         text,
  created_at     timestamptz not null default now(),
  commentaire    text,
  destake_recommande jsonb,
  n_destake      int,
  n_propositions int,
  parse_ok       boolean,
  raw            text
);
create index if not exists idx_alc_verdicts_created on public.alchimiste_crypte_verdicts (created_at desc);

create or replace function public.log_alc_verdict(p_run_id text, p_raw_b64 text)
returns jsonb language plpgsql security definer set search_path to 'public'
as $function$
declare v_raw text; v_j jsonb;
begin
  begin
    v_raw := convert_from(decode(p_raw_b64, 'base64'), 'UTF8');
  exception when others then
    v_raw := p_raw_b64;
  end;
  v_j := public.try_jsonb(v_raw);
  insert into public.alchimiste_crypte_verdicts
    (run_id, commentaire, destake_recommande, n_destake, n_propositions, parse_ok, raw)
  values (
    nullif(p_run_id, ''),
    v_j->>'commentaire',
    v_j->'destake_recommande',
    coalesce(jsonb_array_length(v_j->'destake_recommande'), 0),
    coalesce(jsonb_array_length(v_j->'propositions'), 0),
    v_j is not null,
    left(v_raw, 20000)
  );
  return jsonb_build_object('ok', true, 'parse_ok', v_j is not null,
     'n_destake', coalesce(jsonb_array_length(v_j->'destake_recommande'), 0),
     'n_propositions', coalesce(jsonb_array_length(v_j->'propositions'), 0));
end $function$;

grant execute on function public.log_alc_verdict(text, text) to anon, authenticated, service_role;

create or replace view public.v_alc_verdict_dernier as
select run_id, created_at, commentaire, destake_recommande, n_destake, n_propositions, parse_ok
from public.alchimiste_crypte_verdicts
order by created_at desc limit 1;
grant select on public.v_alc_verdict_dernier to anon, authenticated, service_role;
