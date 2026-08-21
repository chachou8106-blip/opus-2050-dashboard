-- ============================================================================
-- 11_vigie.sql — 🔭 LA VIGIE : couche de surveillance santé du Collège
-- ----------------------------------------------------------------------------
-- Raison d'être (17/08) : les 4 Sages Groq sont restés MUETS 3 jours (15→17/08)
-- sans qu'aucun tableau de bord ne le signale (stopOnHttpError=false masquait la
-- panne). LA VIGIE détecte, à chaque run, un composant qui ne produit plus (PANNE)
-- ou qui sort la même valeur en boucle (FIGÉ), et l'expose à la console.
--
-- PRINCIPE : on ne surveille pas « l'API répond-elle ? » mais « le run a tourné —
-- chaque composant a-t-il produit sa sortie ? ». Un run exécuté + un composant
-- absent = anomalie certaine, quelle qu'en soit la cause (modèle mort, crédit API
-- vide, rate-limit, bug de prompt, réseau). Détection par ABSENCE = filet universel.
--
-- SÛR : lecture seule sur les tables métier ; crée uniquement de nouveaux objets ;
-- ne touche NI au trading, NI au kill_switch, NI au dry_run, NI à Make.
-- Anti-faux-positif week-end : si aucun run récent → état VEILLE (pas d'alarme).
-- ============================================================================

-- Snapshot courant (réécrit à chaque scan) --------------------------------------
create table if not exists public.vigie_status (
  composant       text primary key,
  categorie       text not null,               -- 'Sage' | 'Archimage' | 'Trader' | 'Signal'
  etat            text not null,               -- 'OK' | 'ALERTE' | 'PANNE' | 'FIGE' | 'MUET' | 'VEILLE'
  detail          text,
  derniere_sortie timestamptz,
  run_auditee     timestamptz,
  scanned_at      timestamptz not null default now()
);

-- Fonction de scan : peuple vigie_status pour le dernier run « stabilisé » ------
create or replace function public.vigie_scan()
returns jsonb language plpgsql security definer set search_path to 'public'
as $function$
declare
  v_run   record;
  v_ws    timestamptz;   -- fenêtre début
  v_we    timestamptz;   -- fenêtre fin
  v_veille boolean;
  v_sage  record;
  v_cnt   int; v_ndist int; v_nrows int; v_last timestamptz; v_mints timestamptz; v_etat text; v_detail text;
  k_stag  int := 6;      -- fenêtre courte => ALERTE (peut refléter un marché stable)
  k_long  int := 12;     -- fenêtre longue (72 h) => FIGÉ confirmé
  v_ndist_long int; v_nrows_long int;
  -- garde de récence : on ne juge la stagnation que si les k_stag runs sont récents
  -- (< 12h), sinon un composant qui vient de « ressusciter » après une panne serait
  -- faussement noté FIGÉ (ses vieilles lignes d'avant-panne fausseraient la variance).
  v_res   jsonb;
  v_pok boolean; v_vts timestamptz; v_apy text; v_del text;  -- sondes Alchimiste/staking
  -- clés de stagnation par Sage
  sages   text[][] := array[
      array['Macro','macro_regime'], array['Technique','cycle_phase'],
      array['Risque','risk_level'],  array['Memoire','best_archimage'],
      array['Flash','urgency_level']];
  i int;
begin
  -- 1) run à auditer = dernier run du Collège vieux d'au moins 3 min (stabilisé)
  select run_at, run_id, claude_confidence, perplexity_confidence, mistral_confidence, market_phase
    into v_run
  from oracle_college_runs
  where run_at < now() - interval '3 minutes'
  order by run_at desc limit 1;

  if not found then
    return jsonb_build_object('scanned', false, 'raison', 'aucun run stabilisé');
  end if;

  v_ws := v_run.run_at - interval '15 minutes';
  v_we := v_run.run_at + interval '5 minutes';
  -- VEILLE : le dernier run date de > 2h30 (scénario coupé, ex. week-end) => pas d'alarme
  v_veille := (v_run.run_at < now() - interval '150 minutes');

  delete from public.vigie_status;

  -- 2) Les 5 Sages : présence dans oracle_sages_report + anti-stagnation
  for i in 1 .. array_length(sages,1) loop
    select count(*), max(created_at) into v_cnt, v_last
    from oracle_sages_report
    where sage_name = sages[i][1] and created_at >= v_ws and created_at <= v_we;

    -- dernière sortie tout court (hors fenêtre) pour l'affichage
    if v_last is null then
      select max(created_at) into v_last from oracle_sages_report where sage_name = sages[i][1];
    end if;

    if v_veille then
      v_etat := 'VEILLE'; v_detail := 'scénario en veille';
    elsif v_cnt = 0 then
      v_etat := 'PANNE'; v_detail := 'aucune sortie sur le dernier run';
    else
      -- stagnation : k_stag derniers runs, valeur clé identique ?
      select count(distinct (sage_output->>sages[i][2])), count(*), min(created_at)
        into v_ndist, v_nrows, v_mints
      from (select sage_output, created_at from oracle_sages_report
            where sage_name = sages[i][1] order by created_at desc limit k_stag) t;
      -- 19/08/2026 : DEUX NIVEAUX. Sur 6 runs et une séance calme, NEUTRAL/LOW/MEDIUM/SYL se
      -- répètent naturellement : ce seuil seul a signalé 4 Sages alors qu'un seul était bloqué.
      -- Fenêtre longue de 12 runs sur 72 h : une valeur unique sur cette durée ne s'explique
      -- plus par un marché stable. Mesure du 19/08 sur 72 h — Macro 16 runs / 1 valeur (figé),
      -- Mémoire 16/2, Risque 17/2, Flash 25/3 (sains).
      select count(distinct (sage_output->>sages[i][2])), count(*)
        into v_ndist_long, v_nrows_long
      from (select sage_output from oracle_sages_report
            where sage_name = sages[i][1] and created_at >= now() - interval '72 hours'
            order by created_at desc limit k_long) t;
      if v_nrows_long >= k_long and v_ndist_long = 1 then
        v_etat := 'FIGE';
        v_detail := format('%s=%s identique sur %s runs et 72 h', sages[i][2],
                    (select sage_output->>sages[i][2] from oracle_sages_report
                     where sage_name = sages[i][1] order by created_at desc limit 1), v_nrows_long);
      elsif v_nrows >= k_stag and v_ndist = 1 and v_mints >= now() - interval '12 hours' then
        v_etat := 'ALERTE';
        v_detail := format('%s=%s sur %s runs — a surveiller, peut refleter un marche stable', sages[i][2],
                    (select sage_output->>sages[i][2] from oracle_sages_report
                     where sage_name = sages[i][1] order by created_at desc limit 1), k_stag);
      else
        v_etat := 'OK'; v_detail := 'produit + varie';
      end if;
    end if;

    insert into public.vigie_status(composant, categorie, etat, detail, derniere_sortie, run_auditee)
    values ('Sage '||sages[i][1], 'Sage', v_etat, v_detail, v_last, v_run.run_at);
  end loop;

  -- 3) Archimages : liveness via les confidences du run (JU=Claude, SYL=Perplexity, GIL=Mistral)
  insert into public.vigie_status(composant, categorie, etat, detail, derniere_sortie, run_auditee) values
   ('Archimage JU', 'Archimage',
      case when v_veille then 'VEILLE' when v_run.claude_confidence is not null then 'OK' else 'PANNE' end,
      case when v_run.claude_confidence is null then 'confidence Claude absente' else 'Claude a répondu' end,
      v_run.run_at, v_run.run_at),
   ('Archimage SYL', 'Archimage',
      case when v_veille then 'VEILLE' when v_run.perplexity_confidence is not null then 'OK' else 'PANNE' end,
      case when v_run.perplexity_confidence is null then 'confidence Perplexity absente' else 'Perplexity a répondu' end,
      v_run.run_at, v_run.run_at),
   ('Archimage GIL', 'Archimage',
      case when v_veille then 'VEILLE' when v_run.mistral_confidence is not null then 'OK' else 'PANNE' end,
      case when v_run.mistral_confidence is null then 'confidence Mistral absente' else 'Mistral a répondu' end,
      v_run.run_at, v_run.run_at);

  -- 4) Traders spécialistes (Alchimiste, Marées) : fraîcheur souple
  --    (ils peuvent légitimement ne rien proposer un run => on n'alarme qu'au-delà de 6h)
  select max(proposed_at) into v_last from alchimiste_crypte_propositions;
  insert into public.vigie_status(composant, categorie, etat, detail, derniere_sortie, run_auditee)
  values ('Trader Alchimiste', 'Trader',
     case when v_veille then 'VEILLE'
          when v_last >= v_ws then 'OK'
          when v_last >= now() - interval '6 hours' then 'OK'
          else 'MUET' end,
     case when v_last >= v_ws then 'a proposé sur le dernier run'
          when v_last >= now() - interval '6 hours' then 'calme (rien à proposer récemment)'
          else 'aucune proposition depuis > 6h' end,
     v_last, v_run.run_at);

  select max(proposed_at) into v_last from marees_propositions;
  insert into public.vigie_status(composant, categorie, etat, detail, derniere_sortie, run_auditee)
  values ('Trader Marées', 'Trader',
     case when v_veille then 'VEILLE'
          when v_last >= v_ws then 'OK'
          when v_last >= now() - interval '6 hours' then 'OK'
          else 'MUET' end,
     case when v_last >= v_ws then 'a proposé sur le dernier run'
          when v_last >= now() - interval '6 hours' then 'calme (rien à proposer récemment)'
          else 'aucune proposition depuis > 6h' end,
     v_last, v_run.run_at);

  -- 5) Signal de synthèse figé : market_phase (produit par GIL) identique k_stag runs
  select count(distinct market_phase), count(*), min(run_at) into v_ndist, v_nrows, v_mints
  from (select market_phase, run_at from oracle_college_runs order by run_at desc limit k_stag) t;
  insert into public.vigie_status(composant, categorie, etat, detail, derniere_sortie, run_auditee)
  values ('Signal market_phase', 'Signal',
     case when v_veille then 'VEILLE'
          when v_nrows >= k_stag and v_ndist = 1 and v_mints >= now() - interval '12 hours' then 'FIGE' else 'OK' end,
     case when v_nrows >= k_stag and v_ndist = 1 and v_mints >= now() - interval '12 hours'
          then format('%s sur %s runs', v_run.market_phase, k_stag) else 'varie' end,
     v_run.run_at, v_run.run_at);

  -- Alchimiste — verdict de dé-stake, via alc_destake_reco (alimenté chaque run par alc_record_propositions).
  -- Aveuglement testé UNIQUEMENT sur le dernier batch de dé-stake (sinon un vieux run pré-fix fausse le test).
  select max(created_at) into v_vts from alc_destake_reco;
  select bool_or(coalesce(raison,'') ilike '%faute de don%' or coalesce(raison,'') ilike '%encod%vide%'
              or coalesce(raison,'') ilike '%donn%manquant%' or coalesce(raison,'') ilike '%sans donn%'
              or coalesce(raison,'') ilike '%aucune donn%' or coalesce(raison,'') ilike '%donnees%absent%'
              or coalesce(raison,'') ilike '%donnees%vides%')
    into v_pok from alc_destake_reco where v_vts is not null and created_at >= v_vts - interval '5 minutes';
  insert into public.vigie_status(composant, categorie, etat, detail, derniere_sortie, run_auditee)
  values ('Alchimiste verdict', 'Alchimiste',
     case when v_vts is null then 'VEILLE' when v_veille then 'VEILLE'
          when coalesce(v_pok,false) then 'PANNE'
          when v_vts < now() - interval '6 hours' then 'MUET' else 'OK' end,
     case when v_vts is null then 'aucun de-stake logue'
          when coalesce(v_pok,false) then 'se dit AVEUGLE aux donnees (dernier run)'
          when v_vts < now() - interval '6 hours' then 'pas de de-stake evalue depuis >6h'
          else 'de-stake evalue, raisons lisibles' end,
     v_vts, v_run.run_at);

  -- Sources staking : détection immédiate de « tables vides » (indépendant du run)
  select apy_texte into v_apy from v_alc_staking_apy_txt;
  select delais_texte into v_del from v_alc_staking_delais_txt;
  insert into public.vigie_status(composant, categorie, etat, detail, derniere_sortie, run_auditee)
  values ('Donnees staking', 'Source',
     case when coalesce(v_apy,'')='' or coalesce(v_del,'')='' then 'PANNE' else 'OK' end,
     case when coalesce(v_apy,'')='' and coalesce(v_del,'')='' then 'APY et delais VIDES'
          when coalesce(v_apy,'')='' then 'table APY vide'
          when coalesce(v_del,'')='' then 'table delais vide'
          else 'APY + delais alimentes' end,
     now(), v_run.run_at);

  select jsonb_build_object(
    'scanned', true, 'run_auditee', v_run.run_at, 'veille', v_veille,
    'panne', (select count(*) from vigie_status where etat='PANNE'),
    'fige',  (select count(*) from vigie_status where etat in ('FIGE','MUET','ALERTE'))
  ) into v_res;
  return v_res;
end $function$;

-- Vue de synthèse (bannière console) --------------------------------------------
create or replace view public.v_vigie_resume as
with s as (select * from vigie_status)
select
  case
    when (select count(*) from s) = 0 then 'INCONNU'
    when exists(select 1 from s where etat='PANNE') then 'ROUGE'
    when exists(select 1 from s where etat in ('FIGE','MUET','ALERTE')) then 'ORANGE'
    when (select count(*) from s) = (select count(*) from s where etat='VEILLE') then 'VEILLE'
    else 'VERT'
  end                                                             as niveau,
  (select count(*) from s where etat='OK')                        as nb_ok,
  (select count(*) from s where etat='PANNE')                     as nb_panne,
  (select count(*) from s where etat in ('FIGE','MUET','ALERTE'))          as nb_alerte,
  (select count(*) from s)                                        as nb_total,
  (select string_agg(composant||' ('||etat||')', ', ' order by composant)
     from s where etat not in ('OK','VEILLE'))                    as problemes,
  (select max(run_auditee) from s)                                as run_auditee,
  (select max(scanned_at) from s)                                 as scanned_at;

-- Vue détail triée (panneau console) --------------------------------------------
create or replace view public.v_vigie_detail as
select composant, categorie, etat, detail, derniere_sortie, run_auditee, scanned_at
from vigie_status
order by
  case etat when 'PANNE' then 0 when 'MUET' then 1 when 'FIGE' then 2 when 'OK' then 3 else 4 end,
  categorie, composant;

-- ============================================================================
-- ALERTE DISCORD (indépendante de Make — pg_net côté Supabase)
-- ----------------------------------------------------------------------------
-- Le webhook Discord est stocké dans Supabase Vault (secret 'vigie_discord_webhook'),
-- JAMAIS en git. On n'alerte que sur les TRANSITIONS (pas en boucle) :
--   PANNE  = urgent  -> alerte à la bascule + rappel toutes les 6h tant que non résolu.
--   FIGE/MUET = advisory -> une alerte à la bascule.
--   bad -> OK -> message de rétablissement (vert). VEILLE et OK n'alertent pas.
-- Cron (job vigie_scan_15min) : 'select public.vigie_scan(); select public.vigie_alert();'
-- Après création : amorcer vigie_alert_state depuis vigie_status pour ne notifier que
-- les changements FUTURS (voir migration vigie_discord_alert).
-- ============================================================================
create table if not exists public.vigie_alert_state (
  composant  text primary key,
  last_etat  text,
  alerted_at timestamptz
);

create or replace function public.vigie_alert()
returns jsonb language plpgsql security definer set search_path to 'public'
as $function$
declare
  v_url text; v_lines text := ''; v_recover text := ''; v_msg text := '';
  r record; v_bad text[] := array['PANNE','MUET','FIGE']; v_should boolean;
begin
  for r in
    select s.composant, s.etat, s.detail, a.last_etat, a.alerted_at
    from vigie_status s left join vigie_alert_state a using (composant)
  loop
    if r.etat = any(v_bad) then
      v_should := (r.last_etat is distinct from r.etat)
               or (r.etat = 'PANNE' and (r.alerted_at is null or r.alerted_at < now() - interval '6 hours'));
      if v_should then
        v_lines := v_lines || format(E'🔴 %s : %s — %s\n', r.composant, r.etat, coalesce(r.detail,''));
        insert into vigie_alert_state(composant, last_etat, alerted_at) values (r.composant, r.etat, now())
          on conflict (composant) do update set last_etat = excluded.last_etat, alerted_at = now();
      else
        insert into vigie_alert_state(composant, last_etat, alerted_at) values (r.composant, r.etat, r.alerted_at)
          on conflict (composant) do update set last_etat = excluded.last_etat;
      end if;
    else
      if r.last_etat = any(v_bad) then
        v_recover := v_recover || format(E'🟢 %s : rétabli (%s)\n', r.composant, r.etat);
      end if;
      insert into vigie_alert_state(composant, last_etat, alerted_at) values (r.composant, r.etat, null)
        on conflict (composant) do update set last_etat = excluded.last_etat, alerted_at = null;
    end if;
  end loop;

  if v_lines <> '' then v_msg := '**🔭 La Vigie — anomalie détectée**' || E'\n' || v_lines; end if;
  if v_recover <> '' then
    v_msg := v_msg || (case when v_msg <> '' then E'\n' else '**🔭 La Vigie**' || E'\n' end) || v_recover;
  end if;
  if v_msg = '' then return jsonb_build_object('sent', false, 'raison', 'aucune transition'); end if;

  select decrypted_secret into v_url from vault.decrypted_secrets where name = 'vigie_discord_webhook' limit 1;
  if v_url is null then return jsonb_build_object('sent', false, 'raison', 'webhook absent'); end if;

  perform net.http_post(
    url := v_url,
    body := jsonb_build_object('content', left(v_msg, 1900)),
    headers := jsonb_build_object('Content-Type', 'application/json')
  );
  return jsonb_build_object('sent', true, 'msg', v_msg);
end $function$;
