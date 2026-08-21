-- ============================================================================
-- LA VIGIE v2 — 21/08/2026
-- 1) La VEILLE suit le PLANNING reel (scenario_runs_planifies) et non plus un
--    delai fixe de 150 minutes qui la rendait aveugle ~14 h sur 24.
-- 2) Nouveau composant « Planificateur » : un creneau passe sans run = tir manque.
-- 3) Les incidents sont CONSIGNES dans oracle_problemes (table existante, deja
--    affichee dans aether.html) : une ligne par incident, ouverte a la bascule,
--    fermee au retablissement. Trace durable du passe, du present et du futur.
-- Aucun objet nouveau : on reutilise vigie_status, vigie_alert_state,
-- oracle_problemes et scenario_runs_planifies.
-- ============================================================================

-- ---------------------------------------------------------------- 1) vigie_scan
do $do$
declare
  d text := pg_get_functiondef('public.vigie_scan()'::regprocedure);
  d0 text := d;
  -- ATTENTION : la version DEPLOYEE de vigie_scan est une variante compactee, differente
  -- de la mise en forme de 11_vigie.sql. Les ancres ci-dessous visent le texte REEL en base,
  -- lu par pg_get_functiondef(). Chaque remplacement est verifie avant execution.
  a_old text := 'v_we timestamptz; v_veille boolean;';
  a_new text := 'v_we timestamptz; v_veille boolean; v_creneau timestamptz;';
  b_old text := '  v_veille := (v_run.run_at < now() - interval ''150 minutes'');';
  b_new text :=
'  -- 21/08/2026 : la VEILLE ne depend plus d''un delai fixe de 150 minutes mais du'||chr(10)||
'  -- PLANNING reel. Avec 4 tirs par jour, la fenetre fixe laissait ~14 h sur 24 sans'||chr(10)||
'  -- surveillance : le Sage Macro est reste muet du 19/08 au 21/08 sans aucune alerte.'||chr(10)||
'  select max(s.slot) into v_creneau from ('||chr(10)||
'    select ((date_trunc(''day'', (now() at time zone ''Europe/Paris''))'||chr(10)||
'             - make_interval(days => g.n)'||chr(10)||
'             + make_interval(hours => p.heure, mins => p.minute)) at time zone ''Europe/Paris'') as slot,'||chr(10)||
'           p.jours'||chr(10)||
'    from public.scenario_runs_planifies p, generate_series(0, 7) g(n)'||chr(10)||
'    where p.actif'||chr(10)||
'  ) s'||chr(10)||
'  where extract(isodow from (s.slot at time zone ''Europe/Paris''))::int = any(s.jours)'||chr(10)||
'    and s.slot < now() - interval ''10 minutes'';'||chr(10)||
'  -- veille seulement si AUCUN creneau planifie n''est encore passe (planning vide/coupe)'||chr(10)||
'  v_veille := (v_creneau is null);';
  c_old text := '  select jsonb_build_object(''scanned'', true, ''run_auditee'', v_run.run_at, ''veille'', v_veille,';
  c_new text :=
'  -- 21/08/2026 : le planificateur lui-meme. Un creneau passe sans run = tir manque.'||chr(10)||
'  insert into public.vigie_status(composant, categorie, etat, detail, derniere_sortie, run_auditee)'||chr(10)||
'  values (''Planificateur'', ''Signal'','||chr(10)||
'     case when v_creneau is null then ''VEILLE'''||chr(10)||
'          when v_run.run_at < v_creneau then ''PANNE'' else ''OK'' end,'||chr(10)||
'     case when v_creneau is null then ''aucun creneau planifie'''||chr(10)||
'          when v_run.run_at < v_creneau'||chr(10)||
'            then format(''tir de %s non execute (dernier run %s)'','||chr(10)||
'                        to_char(v_creneau at time zone ''Europe/Paris'',''DD/MM HH24:MI''),'||chr(10)||
'                        to_char(v_run.run_at at time zone ''Europe/Paris'',''DD/MM HH24:MI''))'||chr(10)||
'          else format(''dernier tir %s conforme au planning'','||chr(10)||
'                      to_char(v_creneau at time zone ''Europe/Paris'',''DD/MM HH24:MI'')) end,'||chr(10)||
'     v_run.run_at, v_run.run_at);'||chr(10)||chr(10)||
'  select jsonb_build_object(''scanned'', true, ''run_auditee'', v_run.run_at, ''veille'', v_veille, ''creneau'', v_creneau,';
begin
  if position(a_old in d) = 0 then raise exception 'vigie_scan : bloc declare introuvable'; end if;
  d := replace(d, a_old, a_new);
  if position(b_old in d) = 0 then raise exception 'vigie_scan : calcul v_veille introuvable'; end if;
  d := replace(d, b_old, b_new);
  if position(c_old in d) = 0 then raise exception 'vigie_scan : bloc de synthese introuvable'; end if;
  d := replace(d, c_old, c_new);
  if d = d0 then raise exception 'vigie_scan : aucune modification appliquee'; end if;
  execute d;
end $do$;

-- --------------------------------------------------------------- 2) vigie_alert
-- Ajout : consignation des incidents dans oracle_problemes.
--   source   = 'vigie:<composant>'  -> une seule ligne ouverte par composant
--   statut   = 'nouveau' a l'ouverture, 'resolu' + traite_at au retablissement
-- Le reste (transitions, Discord, rappel 6 h sur PANNE) est inchange.
create or replace function public.vigie_alert()
returns jsonb language plpgsql security definer set search_path to 'public'
as $function$
declare
  v_url text; v_lines text := ''; v_recover text := ''; v_msg text := '';
  r record; v_bad text[] := array['PANNE','MUET','FIGE']; v_should boolean;
  v_ouverts int := 0; v_fermes int := 0;
begin
  for r in
    select s.composant, s.etat, s.detail, s.categorie, a.last_etat, a.alerted_at
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

      -- CONSIGNATION : ouvre un incident s'il n'y en a pas deja un ouvert pour ce composant.
      if not exists (select 1 from oracle_problemes
                      where source = 'vigie:'||r.composant and coalesce(statut,'') <> 'resolu') then
        insert into oracle_problemes(message, source, statut, diagnostic, recommandation)
        values (format('%s — %s', r.composant, r.etat),
                'vigie:'||r.composant, 'nouveau',
                coalesce(r.detail,''),
                case r.etat
                  when 'PANNE' then 'Aucune sortie sur le dernier run : verifier la reponse du module correspondant dans Make.'
                  when 'MUET'  then 'Composant sans production depuis plus de 6 h.'
                  when 'FIGE'  then 'Valeur identique sur 12 runs et 72 h : sortie probablement bloquee.'
                  else 'A examiner.' end);
        v_ouverts := v_ouverts + 1;
      end if;

    else
      if r.last_etat = any(v_bad) then
        v_recover := v_recover || format(E'🟢 %s : rétabli (%s)\n', r.composant, r.etat);
      end if;
      insert into vigie_alert_state(composant, last_etat, alerted_at) values (r.composant, r.etat, null)
        on conflict (composant) do update set last_etat = excluded.last_etat, alerted_at = null;

      -- CONSIGNATION : ferme l'incident ouvert, mais SEULEMENT sur un vrai retablissement.
      -- VEILLE n'est pas un retablissement : on laisse l'incident ouvert tant qu'on ne l'a
      -- pas reellement vu revenir a OK, sinon une panne disparaitrait du registre la nuit.
      if r.etat = 'OK' then
        update oracle_problemes
           set statut = 'resolu', traite_at = now(),
               diagnostic = coalesce(diagnostic,'') || format(' | retabli le %s',
                            to_char(now() at time zone 'Europe/Paris','DD/MM HH24:MI'))
         where source = 'vigie:'||r.composant and coalesce(statut,'') <> 'resolu';
        if found then v_fermes := v_fermes + 1; end if;
      end if;
    end if;
  end loop;

  if v_lines <> '' then v_msg := '**🔭 La Vigie — anomalie détectée**' || E'\n' || v_lines; end if;
  if v_recover <> '' then
    v_msg := v_msg || (case when v_msg <> '' then E'\n' else '**🔭 La Vigie**' || E'\n' end) || v_recover;
  end if;
  if v_msg = '' then
    return jsonb_build_object('sent', false, 'raison', 'aucune transition',
                              'incidents_ouverts', v_ouverts, 'incidents_fermes', v_fermes);
  end if;

  select decrypted_secret into v_url from vault.decrypted_secrets where name = 'vigie_discord_webhook' limit 1;
  if v_url is null then
    return jsonb_build_object('sent', false, 'raison', 'webhook absent',
                              'incidents_ouverts', v_ouverts, 'incidents_fermes', v_fermes);
  end if;

  perform net.http_post(
    url := v_url,
    body := jsonb_build_object('content', left(v_msg, 1900)),
    headers := jsonb_build_object('Content-Type', 'application/json')
  );
  return jsonb_build_object('sent', true, 'msg', v_msg,
                            'incidents_ouverts', v_ouverts, 'incidents_fermes', v_fermes);
end $function$;

-- ------------------------------------------------------- 3) vue de consultation
-- Historique lisible : incidents ouverts et clos, avec leur duree.
create or replace view public.v_vigie_incidents as
select p.id,
       replace(p.source, 'vigie:', '')                                        as composant,
       p.message,
       p.diagnostic                                                           as detail,
       p.recommandation,
       case when coalesce(p.statut,'') = 'resolu' then 'clos' else 'ouvert' end as etat,
       p.created_at                                                           as ouvert_le,
       p.traite_at                                                            as clos_le,
       coalesce(p.traite_at, now()) - p.created_at                            as duree
from public.oracle_problemes p
where p.source like 'vigie:%'

-- ============================================================================
-- LA VIGIE v3 — 21/08/2026 : les virtuels et les taches planifiees
-- ============================================================================
-- Trois angles morts, decouverts le meme jour :
--  1) Alchimiste VIRTUEL fige depuis le 17/08 16:12 — alc_rebuild_virtual()
--     echouait a chaque passage sur
--       ERROR: duplicate key value violates unique constraint
--              "alchimiste_virtual_trades_pkey"
--     Cause : PRIMARY KEY (proposition_id) alors que la reconstruction FIFO peut
--     produire PLUSIEURS trades pour une meme proposition (sorties partielles).
--     Mesure apres correction : 54 lignes pour 52 propositions distinctes — deux
--     propositions produisent bien deux trades chacune. marees_virtual_trades a
--     les memes colonnes, la meme fonction de rebuild, AUCUNE cle primaire, et
--     n'echouait jamais. Contrainte retiree, index non unique conserve, table de
--     sauvegarde bak_20260821_alc_virtual_trades. Rebuild verifie : 54 trades,
--     15 round-trips clos, win rate 84 %, esperance +1,964 %.
--  2) Marees VIRTUEL : meme famille, jamais surveille non plus.
--  3) TACHES PLANIFIEES : le cron echouait toutes les 6 h en silence total.
--     C'est ce garde-fou qui aurait attrape le bug seul. Au premier scan il a
--     signale « 4 echec(s) sur 24 h : alc_rebuild_virtual_6h ».
--
-- Ces trois composants ne dependent pas d'un run du College : ils ne passent
-- donc jamais en VEILLE, exactement comme « Donnees staking ».
-- Le correctif ci-dessous s'ancre sur le commentaire du Planificateur ajoute en
-- v2 et verifie sa presence avant d'executer quoi que ce soit.
--
-- Couverture apres v3 — 17 composants :
--   5 Sages (Macro, Technique, Risque, Memoire, Flash)
--   3 Archimages (JU, SYL, GIL)
--   4 Traders (Alchimiste reel, Alchimiste virtuel, Marees, Marees virtuel)
--   1 Alchimiste verdict de-stake
--   3 Signaux (market_phase, Planificateur, Taches planifiees)
--   1 Source (donnees staking)
-- (Le corps exact du DO block applique se trouve dans la migration Supabase
--  « vigie_v3_virtuels_et_taches_planifiees ».)

-- ============================================================================
-- Correctif 21/08/2026 (soir) — emojis Discord de vigie_alert()
-- ============================================================================
-- Defaut introduit le meme jour : les emojis etaient ecrits E'\U0001F52D'.
-- Postgres n'interprete pas ces echappements sur 8 chiffres hexadecimaux, et
-- Discord affichait le texte brut au lieu du telescope et des ronds de couleur.
-- Corrige via chr() qui prend le point de code decimal, sans echappement :
--   chr(128301) = telescope U+1F52D  |  chr(128308) = rond rouge U+1F534
--   chr(128994) = rond vert  U+1F7E2
-- (DO block avec garde, applique par la migration « fix_vigie_alert_emojis_discord ».)
