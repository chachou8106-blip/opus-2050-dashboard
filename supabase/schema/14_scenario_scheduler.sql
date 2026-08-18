-- ============================================================================
-- 14_scenario_scheduler.sql — Déclenchement du scénario Make DEPUIS Supabase (0 modif Make)
-- ----------------------------------------------------------------------------
-- Le scénario Make a un planning interne horaire (interval 3600) mais on ne l'utilise PAS
-- (coût). On le laisse DÉSACTIVÉ et Supabase déclenche EXACTEMENT N runs/jour à heures
-- fixes via l'API Make "run once" (POST /scenarios/{id}/run). Coût maîtrisé, régularité.
--
-- Bonnes pratiques retenues : peu de runs, réguliers, calés sur les moments de marché US.
-- Par défaut 4 runs/jour en semaine (Paris) : 09h00 (matin Europe/forex/crypto), 15h45
-- (ouverture US), 18h30 (mi-séance), 21h15 (avant clôture). Data-driven → extensible.
--
-- Interrupteur maître = bouton console (scenario_control.actif). Cron 5 min vérifie l'heure.
-- PRÉ-REQUIS pour agir sur Make : Vault `make_api_token` + scenario_control.make_zone (ex 'eu2').
-- ============================================================================
create table if not exists public.scenario_control (
  id int primary key default 1,
  actif boolean not null default false,
  applied_state text,
  scenario_id text not null default '6183820',
  make_zone text,
  last_action text, last_action_at timestamptz,
  updated_at timestamptz not null default now(), updated_by text,
  constraint scenario_control_one_row check (id = 1)
);
insert into public.scenario_control (id, actif) values (1, false) on conflict (id) do nothing;

-- Heures de run (Paris), data-driven
create table if not exists public.scenario_runs_planifies (
  id bigserial primary key, libelle text not null,
  heure int not null, minute int not null default 0,
  jours int[] not null,            -- 0=dim … 6=sam
  actif boolean not null default true, last_fired timestamptz
);
insert into public.scenario_runs_planifies (libelle, heure, minute, jours)
select * from (values
  ('Matin Europe (forex + crypto + overnight)', 9, 0, array[1,2,3,4,5]),
  ('Ouverture US', 15, 45, array[1,2,3,4,5]),
  ('Mi-seance US', 18, 30, array[1,2,3,4,5]),
  ('Avant cloture US', 21, 15, array[1,2,3,4,5])
) v(libelle,heure,minute,jours)
where not exists (select 1 from public.scenario_runs_planifies);
-- Extensions futures (sans toucher Make) : ajouter des lignes (Darwinex forex nocturne,
-- crypto week-end jours {6,0}, etc.).

create table if not exists public.scenario_toggle_log (
  id bigserial primary key, ts timestamptz not null default now(),
  action text, source text, http_status int, detail text
);

-- Déclencheur : lance un "run once" à l'heure prévue (grâce 30 min), ou tout de suite si p_force.
create or replace function public.scenario_fire(p_force boolean default false)
returns jsonb language plpgsql security definer set search_path to 'public' as $$
declare c record; r record; v_token text; v_url text; v_rid bigint; v_target timestamptz; v_now timestamptz;
  n int := 0; v_fired jsonb := '[]'::jsonb;
begin
  select * into c from scenario_control where id=1;
  v_now := now();
  if not p_force and not c.actif then return jsonb_build_object('fired', false, 'raison', 'maitre off'); end if;
  select decrypted_secret into v_token from vault.decrypted_secrets where name='make_api_token' limit 1;
  v_url := case when c.make_zone is not null
                then format('https://%s.make.com/api/v2/scenarios/%s/run', c.make_zone, c.scenario_id) end;
  if v_token is null or v_url is null then return jsonb_build_object('fired', false, 'raison', 'api non configuree'); end if;

  if p_force then
    select net.http_post(url:=v_url, headers:=jsonb_build_object('Authorization','Token '||v_token,'Content-Type','application/json'), body:='{}'::jsonb) into v_rid;
    insert into scenario_toggle_log(action, source, detail) values ('run','manuel','req '||v_rid::text);
    return jsonb_build_object('fired', true, 'request', v_rid);
  end if;

  for r in select * from scenario_runs_planifies where actif loop
    v_target := (((v_now at time zone 'Europe/Paris')::date + make_time(r.heure, r.minute, 0)) at time zone 'Europe/Paris');
    if (extract(dow from (v_now at time zone 'Europe/Paris'))::int) = any(r.jours)
       and v_now >= v_target and v_now < v_target + interval '30 minutes'
       and (r.last_fired is null or r.last_fired < v_target) then
      select net.http_post(url:=v_url, headers:=jsonb_build_object('Authorization','Token '||v_token,'Content-Type','application/json'), body:='{}'::jsonb) into v_rid;
      insert into scenario_toggle_log(action, source, detail) values ('run','planning', r.libelle||' req '||v_rid::text);
      update scenario_runs_planifies set last_fired = v_now where id = r.id;
      n := n+1; v_fired := v_fired || to_jsonb(r.libelle);
    end if;
  end loop;
  return jsonb_build_object('fired', n>0, 'n', n, 'slots', v_fired);
end $$;

-- Cron toutes les 5 min (ne déclenche qu'aux heures prévues + fenêtre de grâce)
-- select cron.schedule('scenario_fire_5min', '*/5 * * * *', 'select public.scenario_fire(false);');

create or replace view public.v_scenario_etat as
select c.actif as maitre_on, c.last_action, c.last_action_at,
       (select string_agg(lpad(heure::text,2,'0')||'h'||lpad(minute::text,2,'0'), ' · ' order by heure, minute)
          from scenario_runs_planifies where actif) as heures,
       (select count(*) from scenario_runs_planifies where actif) as nb_runs_jour,
       (select max(ts) from scenario_toggle_log where action='run') as dernier_run,
       (c.make_zone is not null and exists(select 1 from vault.decrypted_secrets where name='make_api_token')) as api_configuree
from scenario_control c where c.id=1;
grant select on public.v_scenario_etat to anon, authenticated, service_role;
