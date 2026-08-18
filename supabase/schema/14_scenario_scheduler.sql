-- ============================================================================
-- 14_scenario_scheduler.sql — Déclenchement du scénario Make DEPUIS Supabase (0 modif Make)
-- ----------------------------------------------------------------------------
-- Le scénario Make a un planning interne horaire (interval 3600) qu'on N'UTILISE PAS
-- (coût). On le laisse DÉSACTIVÉ et Supabase déclenche EXACTEMENT N runs/jour à heures
-- fixes.
--
-- MODÈLE (important) : l'API Make "run once" (POST /scenarios/{id}/run) renvoie 422
-- « Scenario is not activated » (IM325) quand le scénario est inactif. On utilise donc :
--   1. POST /scenarios/{id}/start  → ACTIVE le scénario ET déclenche 1 exécution immédiate.
--   2. POST /scenarios/{id}/stop   → 3 min plus tard (avant le +3600s interne) → coupe la
--      répétition automatique. Il ne reste donc QU'UN seul run par slot.
-- Confirmé empiriquement : /stop pendant une exécution ne la tue pas (elle finit status 1).
--
-- Bonnes pratiques retenues : peu de runs, réguliers, calés sur les moments de marché US.
-- Par défaut 4 runs/jour en semaine (Paris) : 09h00 (matin Europe/forex/crypto), 15h45
-- (ouverture US), 18h30 (mi-séance), 21h15 (avant clôture). Data-driven → extensible.
--
-- Interrupteur maître = bouton console (scenario_control.actif). Cron 5 min vérifie l'heure
-- ET applique les /stop en attente (même maître off).
-- PRÉ-REQUIS pour agir sur Make : Vault `Aether` (ou `make_api_token`) + scenario_control.make_zone.
-- ============================================================================
create table if not exists public.scenario_control (
  id int primary key default 1,
  actif boolean not null default false,
  applied_state text,
  scenario_id text not null default '6183820',
  make_zone text,
  pending_stop_at timestamptz,           -- /stop programmé après un run déclenché
  last_action text, last_action_at timestamptz,
  updated_at timestamptz not null default now(), updated_by text,
  constraint scenario_control_one_row check (id = 1)
);
insert into public.scenario_control (id, actif) values (1, false) on conflict (id) do nothing;
-- (make_zone renseigné à 'eu1' en base ; le token est en Vault sous le nom 'Aether'.)

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

-- Déclencheur : /start (déclenche 1 run) aux heures prévues, /stop programmé 3 min après.
-- p_force = run manuel immédiat (bouton console « Lancer maintenant »).
create or replace function public.scenario_fire(p_force boolean default false)
returns jsonb language plpgsql security definer set search_path to 'public' as $$
declare c record; r record;
  v_token text; v_start_url text; v_stop_url text;
  v_rid bigint; v_target timestamptz; v_now timestamptz;
  n int := 0; v_fired jsonb := '[]'::jsonb; v_stopped boolean := false;
begin
  select * into c from scenario_control where id=1;
  v_now := now();

  select coalesce(
    (select decrypted_secret from vault.decrypted_secrets
       where name in ('make_api_token','Aether') order by (name='make_api_token') desc limit 1),
    (select value from ju_crypte_config where key='make_api_token' limit 1)
  ) into v_token;

  if c.make_zone is not null and c.scenario_id is not null then
    v_start_url := format('https://%s.make.com/api/v2/scenarios/%s/start', c.make_zone, c.scenario_id);
    v_stop_url  := format('https://%s.make.com/api/v2/scenarios/%s/stop',  c.make_zone, c.scenario_id);
  end if;
  if v_token is null or v_start_url is null then
    return jsonb_build_object('fired', false, 'raison', 'api non configuree');
  end if;

  -- 1) Coupe en attente : après un run déclenché, on désactive le scénario (toujours, même maitre off)
  if c.pending_stop_at is not null and v_now >= c.pending_stop_at then
    select net.http_post(url:=v_stop_url,
      headers:=jsonb_build_object('Authorization','Token '||v_token,'Content-Type','application/json'),
      body:='{}'::jsonb) into v_rid;
    update scenario_control set pending_stop_at=null, last_action='stop', last_action_at=v_now, updated_at=v_now where id=1;
    insert into scenario_toggle_log(action, source, detail) values ('stop','auto-apres-run','req '||v_rid::text);
    v_stopped := true;
  end if;

  -- 2) Run manuel (bouton) : /start = déclenche 1 exécution immédiate, /stop programmé dans 3 min
  if p_force then
    select net.http_post(url:=v_start_url,
      headers:=jsonb_build_object('Authorization','Token '||v_token,'Content-Type','application/json'),
      body:='{}'::jsonb) into v_rid;
    update scenario_control set pending_stop_at = v_now + interval '3 minutes',
           last_action='start', last_action_at=v_now, updated_at=v_now where id=1;
    insert into scenario_toggle_log(action, source, detail) values ('run','manuel','start req '||v_rid::text);
    return jsonb_build_object('fired', true, 'request', v_rid, 'stopped', v_stopped,
                             'stop_prevu', to_char(v_now + interval '3 minutes','HH24:MI'));
  end if;

  -- 3) Runs planifiés : seulement si maitre ON
  if not c.actif then
    return jsonb_build_object('fired', false, 'stopped', v_stopped, 'raison', 'maitre off');
  end if;

  for r in select * from scenario_runs_planifies where actif loop
    v_target := (((v_now at time zone 'Europe/Paris')::date + make_time(r.heure, r.minute, 0)) at time zone 'Europe/Paris');
    if (extract(dow from (v_now at time zone 'Europe/Paris'))::int) = any(r.jours)
       and v_now >= v_target and v_now < v_target + interval '30 minutes'
       and (r.last_fired is null or r.last_fired < v_target) then
      select net.http_post(url:=v_start_url,
        headers:=jsonb_build_object('Authorization','Token '||v_token,'Content-Type','application/json'),
        body:='{}'::jsonb) into v_rid;
      update scenario_runs_planifies set last_fired = v_now where id = r.id;
      insert into scenario_toggle_log(action, source, detail) values ('run','planning', r.libelle||' start req '||v_rid::text);
      n := n+1; v_fired := v_fired || to_jsonb(r.libelle);
    end if;
  end loop;
  if n>0 then
    update scenario_control set pending_stop_at = v_now + interval '3 minutes',
           last_action='start', last_action_at=v_now, updated_at=v_now where id=1;
  end if;
  return jsonb_build_object('fired', n>0, 'n', n, 'slots', v_fired, 'stopped', v_stopped);
end $$;

-- Coupure immédiate de sécurité (bouton « Couper ») : /stop maintenant + purge la coupe en attente.
create or replace function public.scenario_stop_now()
returns jsonb language plpgsql security definer set search_path to 'public' as $$
declare v_token text; v_stop_url text; v_rid bigint; z text; s text;
begin
  select make_zone, scenario_id into z, s from scenario_control where id=1;
  select coalesce(
    (select decrypted_secret from vault.decrypted_secrets
       where name in ('make_api_token','Aether') order by (name='make_api_token') desc limit 1),
    (select value from ju_crypte_config where key='make_api_token' limit 1)
  ) into v_token;
  if v_token is null or z is null or s is null then
    return jsonb_build_object('ok', false, 'raison', 'api non configuree');
  end if;
  v_stop_url := format('https://%s.make.com/api/v2/scenarios/%s/stop', z, s);
  select net.http_post(url:=v_stop_url,
    headers:=jsonb_build_object('Authorization','Token '||v_token,'Content-Type','application/json'),
    body:='{}'::jsonb) into v_rid;
  update scenario_control set pending_stop_at=null, last_action='stop', last_action_at=now(), updated_at=now() where id=1;
  insert into scenario_toggle_log(action, source, detail) values ('stop','securite-console','req '||v_rid::text);
  return jsonb_build_object('ok', true, 'request', v_rid);
end $$;

grant execute on function public.scenario_fire(boolean) to service_role;
grant execute on function public.scenario_stop_now() to service_role;

-- Cron toutes les 5 min : déclenche aux heures prévues (fenêtre de grâce 30 min) ET
-- applique les /stop en attente. No-op tant que le maître est OFF (sauf coupe en attente).
--   select cron.schedule('scenario_fire_5min', '*/5 * * * *', 'select public.scenario_fire(false);');

create or replace view public.v_scenario_etat as
select c.actif as maitre_on, c.last_action, c.last_action_at, c.pending_stop_at,
       (select string_agg(lpad(heure::text,2,'0')||'h'||lpad(minute::text,2,'0'), ' · ' order by heure, minute)
          from scenario_runs_planifies where actif) as heures,
       (select count(*) from scenario_runs_planifies where actif) as nb_runs_jour,
       (select max(ts) from scenario_toggle_log where action='run') as dernier_run,
       (c.make_zone is not null and exists(
          select 1 from vault.decrypted_secrets where name in ('make_api_token','Aether'))) as api_configuree
from scenario_control c where c.id=1;
grant select on public.v_scenario_etat to anon, authenticated, service_role;
