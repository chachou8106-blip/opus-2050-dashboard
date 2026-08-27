-- =============================================================================
-- 19 — Chaine Flash rendue coherente + detection d'un sage muet — 26/08/2026
-- =============================================================================
-- Deux migrations appliquees et verifiees en base le 26/08/2026 :
--   flash_intel_accepte_chaine_delimitee
--   v_sages_pannes_rattachement_par_horodatage
--
-- CONTEXTE 1 — pourquoi oracle_flash_intel est vide depuis toujours.
-- Le module Make 211 envoie a log_flash_intel trois champs que le module 209 ne produit
-- pas : 210.web_intelligence, 210.trade_1.ticker et 210.trade_1.side. Les trois tombent
-- donc sur leur valeur de repli (ND, MARKET, neutral) et catalysts part toujours a "[]".
-- Cote lecture, log_flash_intel(jsonb) attend en plus, dans chaque catalyseur, les cles
-- catalyst_type, direction, strength, horizon et confidence. Les deux bouts de la chaine
-- ne se parlaient pas.
--
-- CONTRAINTE — le corps du module 211 est du JSON brut dans lequel Make substitue les
-- {{...}} AVANT que le JSON ne soit analyse. Un catalyseur serialise en JSON y injecterait
-- des guillemets et casserait le corps du module. D'ou un format delimite, sans guillemet
-- possible :
--     ticker~catalyst_type~direction~strength~headline~horizon~confidence
--     blocs separes par ';;'
-- log_flash_intel accepte desormais TROIS formes : tableau json, chaine json, chaine
-- delimitee. Les deux anciennes formes continuent de fonctionner a l'identique.
--
-- CONTEXTE 2 — pourquoi personne n'a vu le Sage Memoire mourir.
-- La panne etait deja lisible en base : Macro 0/4 runs le 20/08, Technique 1/8 et Memoire
-- 2/8 le 21/08, Memoire 0 le 22/08 et le 25/08.
--
-- CORRECTION [27/08] — j'avais ecrit "aucun objet ne dit ce sage n'a pas repondu". C'est FAUX.
-- La VIGIE le dit, et mieux que cette vue : vigie_scan() teste les 5 sages sur la fenetre du
-- run (-15 min / +5 min), connait le planning reel de scenario_runs_planifies, distingue MUET
-- de VEILLE, et porte deja en commentaire le correctif du 21/08 sur le Sage Macro. Mon
-- controle initial cherchait des noms contenant sage / panne / health : vigie_status et
-- vigie_scan n'y repondaient pas. Le controle etait trop etroit, pas la base incomplete.
--
-- Ce que la Vigie ne fait pas : vigie_status est SUPPRIMEE puis reecrite a chaque scan
-- (delete from public.vigie_status au debut de vigie_scan). Elle dit ce qui va mal maintenant,
-- jamais ce qui est alle mal. v_sages_pannes n'ajoute que cette memoire — 14 jours d'historique
-- de presence — et rien d'autre. L'etat courant reste du ressort de la Vigie.
--
-- PIEGE — oracle_sages_report.run_id et oracle_college_runs.run_id ne coincident jamais :
-- le scenario met environ deux minutes, les sages sont horodates au debut (20260826-1615)
-- et la ligne du college a la fin (20260826-1617). Le rattachement se fait par fenetre de
-- temps de +/- 5 minutes.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- log_flash_intel(jsonb) — accepte aussi la chaine delimitee
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.log_flash_intel(p_payload jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_run_id text;
  v_item jsonb;
  v_count integer := 0;
  v_ticker text;
  v_type text;
  v_routed text[];
  v_arch text;
  v_archimages text[] := ARRAY['JU','SYL','GIL','CRYPTE_JU','MAREES'];
  v_catalysts jsonb;
  v_txt text;
BEGIN
  v_run_id := p_payload->>'run_id';

  DELETE FROM oracle_flash_intel WHERE run_id = v_run_id;

  -- catalysts accepte TROIS formes : tableau json, chaine json, chaine delimitee
  v_catalysts := p_payload->'catalysts';
  IF v_catalysts IS NOT NULL AND jsonb_typeof(v_catalysts) = 'string' THEN
    v_txt := btrim(p_payload->>'catalysts');
    IF v_txt = '' THEN
      v_catalysts := '[]'::jsonb;
    ELSIF left(v_txt, 1) IN ('[', '{') THEN
      BEGIN
        v_catalysts := v_txt::jsonb;
      EXCEPTION WHEN OTHERS THEN
        v_catalysts := '[]'::jsonb;
      END;
    ELSE
      BEGIN
        SELECT coalesce(jsonb_agg(jsonb_build_object(
                 'ticker',        btrim(f[1]),
                 'catalyst_type', nullif(btrim(coalesce(f[2], '')), ''),
                 'direction',     nullif(lower(btrim(coalesce(f[3], ''))), ''),
                 'strength',      nullif(regexp_replace(coalesce(f[4], ''), '\D', '', 'g'), ''),
                 'headline',      nullif(btrim(coalesce(f[5], '')), ''),
                 'horizon',       nullif(btrim(coalesce(f[6], '')), ''),
                 'confidence',    nullif(regexp_replace(coalesce(f[7], ''), '\D', '', 'g'), '')
               ) ORDER BY ord), '[]'::jsonb)
          INTO v_catalysts
          FROM (
            SELECT ord, string_to_array(bloc, '~') AS f
              FROM unnest(string_to_array(v_txt, ';;')) WITH ORDINALITY AS u(bloc, ord)
             WHERE btrim(bloc) <> ''
          ) s
         WHERE btrim(coalesce(f[1], '')) <> '';
      EXCEPTION WHEN OTHERS THEN
        v_catalysts := '[]'::jsonb;
      END;
    END IF;
  END IF;

  IF v_catalysts IS NOT NULL AND jsonb_typeof(v_catalysts) = 'array' THEN
    FOR v_item IN SELECT * FROM jsonb_array_elements(v_catalysts)
    LOOP
      v_ticker := UPPER(COALESCE(v_item->>'ticker', 'MARKET'));
      v_type   := COALESCE(v_item->>'catalyst_type', 'macro');
      v_routed := public.flash_route(v_ticker, v_type);

      INSERT INTO oracle_flash_intel (
        run_id, ticker, catalyst_type, direction, strength,
        headline, horizon, confidence, shared_with_ju, shared_with_gil, routed_to
      ) VALUES (
        v_run_id, v_ticker, v_type,
        COALESCE(v_item->>'direction', 'neutral'),
        least(10, greatest(1, COALESCE(nullif(v_item->>'strength', '')::integer, 5))),
        v_item->>'headline',
        COALESCE(v_item->>'horizon', '1w'),
        least(100, greatest(0, COALESCE(nullif(v_item->>'confidence', '')::integer, 70))),
        ('JU'  = ANY(v_routed)),
        ('GIL' = ANY(v_routed)),
        v_routed
      );
      v_count := v_count + 1;
    END LOOP;
  END IF;

  -- Routage par univers : chaque archimage recoit UNIQUEMENT ses catalyseurs
  FOREACH v_arch IN ARRAY v_archimages LOOP
    UPDATE oracle_brain_state SET
      latest_web_catalysts = COALESCE((
        SELECT jsonb_agg(jsonb_build_object(
          'ticker', ticker, 'direction', direction, 'strength', strength,
          'catalyst_type', catalyst_type, 'headline', headline,
          'horizon', horizon, 'confidence', confidence
        ) ORDER BY strength DESC, confidence DESC)
        FROM oracle_flash_intel
        WHERE run_id = v_run_id AND v_arch = ANY(routed_to)
      ), '[]'::jsonb),
      catalyst_updated_at = now()
    WHERE archimage = v_arch;
  END LOOP;

  UPDATE oracle_college_runs SET
    syl_web_catalysts       = p_payload->>'summary',
    syl_top_catalyst_ticker = p_payload->>'top_ticker',
    syl_catalyst_direction  = p_payload->>'top_direction'
  WHERE run_id = v_run_id;

  RETURN jsonb_build_object(
    'success', true,
    'catalysts_logged', v_count,
    'run_id', v_run_id,
    'routage', (
      SELECT COALESCE(jsonb_object_agg(a, cnt), '{}'::jsonb) FROM (
        SELECT a, count(*) cnt
        FROM oracle_flash_intel, unnest(routed_to) a
        WHERE run_id = v_run_id GROUP BY a
      ) s)
  );

EXCEPTION WHEN OTHERS THEN
  RETURN jsonb_build_object('success', false, 'error', SQLERRM);
END;
$function$;

-- -----------------------------------------------------------------------------
-- v_sages_pannes — l'HISTORIQUE de presence des sages (l'etat courant est a la Vigie)
-- -----------------------------------------------------------------------------
CREATE OR REPLACE VIEW public.v_sages_pannes AS
WITH runs AS (
  SELECT run_id, coalesce(run_at, created_at) AS run_at
    FROM oracle_college_runs
   WHERE coalesce(run_at, created_at) > now() - interval '14 days'
),
attendus (sage_name) AS (VALUES ('Macro'), ('Technique'), ('Risque'), ('Flash'), ('Memoire')),
croise AS (
  SELECT r.run_id, r.run_at, a.sage_name,
         EXISTS (SELECT 1 FROM oracle_sages_report s
                  WHERE s.sage_name = a.sage_name
                    AND s.created_at BETWEEN r.run_at - interval '5 minutes'
                                        AND r.run_at + interval '5 minutes') AS a_repondu,
         row_number() OVER (PARTITION BY a.sage_name ORDER BY r.run_at DESC) AS rang
    FROM runs r CROSS JOIN attendus a
),
tete AS (
  SELECT sage_name,
         coalesce(min(rang) FILTER (WHERE a_repondu), count(*) + 1) - 1 AS runs_muets_consecutifs
    FROM croise GROUP BY sage_name
)
SELECT c.sage_name,
       count(*)                                 AS runs_14j,
       count(*) FILTER (WHERE NOT c.a_repondu)  AS runs_muets_14j,
       t.runs_muets_consecutifs,
       max(c.run_at) FILTER (WHERE c.a_repondu) AS derniere_reponse,
       round(extract(epoch FROM now() - max(c.run_at) FILTER (WHERE c.a_repondu)) / 3600.0, 1)
                                                AS age_derniere_reponse_h,
       3                                        AS seuil_panne_runs,
       CASE WHEN t.runs_muets_consecutifs >= 3 THEN 'PANNE'
            WHEN t.runs_muets_consecutifs >= 1 THEN 'A SURVEILLER'
            ELSE 'OK' END                       AS statut
  FROM croise c
  JOIN tete t ON t.sage_name = c.sage_name
 GROUP BY c.sage_name, t.runs_muets_consecutifs
 ORDER BY t.runs_muets_consecutifs DESC, c.sage_name;

GRANT SELECT ON public.v_sages_pannes TO anon, authenticated, service_role;

-- =============================================================================
-- 27/08/2026 — batch_write_college_run_v2 enregistre syl_catalyst_direction
-- =============================================================================
-- La colonne etait NULL sur les 278 runs : personne ne l'ecrivait. log_flash_intel sait le
-- faire, mais son UPDATE ne peut jamais aboutir — le module 211 tourne a l'operation 24 et la
-- ligne du college n'est creee qu'a l'operation 59 par le module 982.
-- La fonction fait 7542 caracteres : on la modifie par remplacement de chaine sur sa propre
-- definition plutot que de la retaper, avec un garde-fou qui refuse d'agir si l'ancrage n'est
-- pas trouve une fois et une seule.
do $$
declare d text; n1 int; n2 int;
begin
  select pg_get_functiondef(p.oid) into d
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'batch_write_college_run_v2';

  select count(*) into n1 from regexp_matches(d, 'syl_web_catalysts, syl_top_catalyst_ticker,', 'g');
  select count(*) into n2 from regexp_matches(d, 'p_payload->>''syl_top_catalyst'',', 'g');
  if n1 <> 1 or n2 <> 1 then
    raise exception 'ancrage introuvable ou multiple : colonnes=% valeurs=%', n1, n2;
  end if;

  d := replace(d,
    'syl_web_catalysts, syl_top_catalyst_ticker,',
    'syl_web_catalysts, syl_top_catalyst_ticker, syl_catalyst_direction,');
  d := replace(d,
    'p_payload->>''syl_top_catalyst'',',
    'p_payload->>''syl_top_catalyst'',' || E'\n    ' || 'p_payload->>''syl_catalyst_direction'',');

  execute d;
end $$;
