-- ============================================================================
-- 14_scenario_scheduler.sql — Pilotage du scénario Make DEPUIS Supabase (0 modif Make)
-- ----------------------------------------------------------------------------
-- Le scénario Make a déjà un planning interne horaire (interval 3600) mais il est
-- activé/désactivé à la main → runs irréguliers. On ne touche NI l'interval NI aucun
-- module : Supabase ACTIVE/DÉSACTIVE le scénario aux heures de marché via l'API Make
-- (start/stop) — exactement comme le bouton on/off de Make, mais automatisé + market-aware.
--
-- Composants : scenario_control (interrupteur maître = bouton console), scenario_schedule
-- (fenêtres de marché, data-driven → extensible Darwinex/crypto), scenario_reconcile()
-- (appelle l'API Make quand l'état désiré change), cron 10 min, vue v_scenario_etat.
-- Bouton console + edge function scenario-switch (PIN ju_crypte_config.arm_pin).
--
-- PRÉ-REQUIS pour agir réellement sur Make : secret Vault `make_api_token` + colonne
-- scenario_control.make_zone (ex 'eu2'). Tant qu'absents, tout est mémorisé mais inerte.
-- ============================================================================
create table if not exists public.scenario_control (
  id            int primary key default 1,
  actif         boolean not null default false,
  applied_state text,
  scenario_id   text not null default '6183820',
  make_zone     text,
  last_action   text,
  last_action_at timestamptz,
  updated_at    timestamptz not null default now(),
  updated_by    text,
  constraint scenario_control_one_row check (id = 1)
);
insert into public.scenario_control (id, actif, applied_state)
values (1, false, 'inactive') on conflict (id) do nothing;

create table if not exists public.scenario_schedule (
  id bigserial primary key, libelle text not null,
  jours int[] not null, heure_debut int not null, heure_fin int not null,
  actif boolean not null default true
);
insert into public.scenario_schedule (libelle, jours, heure_debut, heure_fin, actif)
select 'Session principale (forex Londres + actions US + crypto)', array[1,2,3,4,5], 8, 22, true
where not exists (select 1 from public.scenario_schedule);
-- Extensions futures (à activer le moment venu, sans toucher Make) :
--   Darwinex forex 24/5 : jours {0,1,2,3,4,5}, plages nocturnes ; crypto week-end : jours {6,0}, 0-24.

create table if not exists public.scenario_toggle_log (
  id bigserial primary key, ts timestamptz not null default now(),
  action text, source text, http_status int, detail text
);

create or replace function public.scenario_doit_etre_actif()
returns boolean language sql stable security definer set search_path to 'public' as $$
  select (select actif from scenario_control where id=1)
     and exists (
       select 1 from scenario_schedule s
       where s.actif
         and (extract(dow  from now() at time zone 'Europe/Paris')::int) = any(s.jours)
         and (extract(hour from now() at time zone 'Europe/Paris')::int) >= s.heure_debut
         and (extract(hour from now() at time zone 'Europe/Paris')::int) <  s.heure_fin
     );
$$;

create or replace function public.scenario_reconcile(p_source text default 'planning')
returns jsonb language plpgsql security definer set search_path to 'public' as $$
declare c record; v_desire boolean; v_cible text; v_token text; v_url text; v_rid bigint;
begin
  select * into c from scenario_control where id=1;
  v_desire := scenario_doit_etre_actif();
  v_cible  := case when v_desire then 'active' else 'inactive' end;
  if c.applied_state is not distinct from v_cible then
    return jsonb_build_object('change', false, 'etat', v_cible);
  end if;
  select decrypted_secret into v_token from vault.decrypted_secrets where name='make_api_token' limit 1;
  if v_token is null or c.make_zone is null then
    update scenario_control set applied_state=v_cible, last_action='(config manquante)', last_action_at=now() where id=1;
    insert into scenario_toggle_log(action, source, http_status, detail)
      values (case when v_desire then 'start' else 'stop' end, p_source, null, 'jeton ou zone Make absent');
    return jsonb_build_object('change', false, 'raison', 'jeton/zone Make manquant');
  end if;
  v_url := format('https://%s.make.com/api/v2/scenarios/%s/%s',
                  c.make_zone, c.scenario_id, case when v_desire then 'start' else 'stop' end);
  select net.http_post(url := v_url,
           headers := jsonb_build_object('Authorization','Token '||v_token, 'Content-Type','application/json'),
           body := '{}'::jsonb) into v_rid;
  update scenario_control set applied_state=v_cible,
    last_action=case when v_desire then 'start' else 'stop' end, last_action_at=now() where id=1;
  insert into scenario_toggle_log(action, source, detail)
    values (case when v_desire then 'start' else 'stop' end, p_source, 'req '||v_rid::text);
  return jsonb_build_object('change', true, 'etat', v_cible, 'request', v_rid);
end $$;

-- select cron.schedule('scenario_reconcile_10min', '*/10 * * * *', 'select public.scenario_reconcile(''planning'');');

create or replace view public.v_scenario_etat as
select c.actif as maitre_on, scenario_doit_etre_actif() as devrait_tourner,
       c.applied_state as etat_make, c.last_action, c.last_action_at,
       (select string_agg(libelle||' ('||array_to_string(jours,',')||' '||heure_debut||'h-'||heure_fin||'h)', ' ; ')
          from scenario_schedule where actif) as fenetres,
       (c.make_zone is not null and exists(select 1 from vault.decrypted_secrets where name='make_api_token')) as api_configuree
from scenario_control c where c.id=1;
grant select on public.v_scenario_etat to anon, authenticated, service_role;
