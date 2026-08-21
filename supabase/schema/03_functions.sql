-- FUNCTION: alc_process_oui
CREATE OR REPLACE FUNCTION public.alc_process_oui(p_run_id text, p_user_id text, p_messages_b64 text, p_prices_b64 text, p_dry_run boolean DEFAULT true)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_msgs jsonb; v_prices jsonb; v_msg jsonb; v_content text; v_sym text;
  v_prop record; v_cur numeric; v_drift numeric; v_processed int := 0;
  v_actions jsonb := '[]'::jsonb; v_text text := ''; v_pair_norm text;
begin
  if p_messages_b64 is null or length(p_messages_b64)=0 then
    return jsonb_build_object('processed',0,'actions','[]'::jsonb,'discord_text',''); end if;
  begin v_msgs := convert_from(decode(p_messages_b64,'base64'),'UTF8')::jsonb;
  exception when others then return jsonb_build_object('error','messages_parse_fail','processed',0,'discord_text',''); end;
  if jsonb_typeof(v_msgs) <> 'array' then v_msgs := jsonb_build_array(v_msgs); end if;
  begin v_prices := convert_from(decode(coalesce(nullif(p_prices_b64,''),'W10='),'base64'),'UTF8')::jsonb;
  exception when others then v_prices := '[]'::jsonb; end;
  if jsonb_typeof(v_prices) <> 'array' then v_prices := '[]'::jsonb; end if;

  for v_msg in select * from jsonb_array_elements(v_msgs) loop
    if p_user_id is not null and length(p_user_id) > 0 and (v_msg->'author'->>'id') is distinct from p_user_id then continue; end if;
    v_content := upper(coalesce(v_msg->>'content',''));
    if position('OUI' in v_content) = 0 then continue; end if;
    v_sym := (regexp_match(v_content, 'OUI\s+([A-Z0-9]{2,10})'))[1];
    if v_sym is null then continue; end if;
    select * into v_prop from public.alchimiste_crypte_propositions
      where statut='proposee' and upper(paire) like v_sym || '%' order by proposed_at desc limit 1;
    if not found then continue; end if;
    v_pair_norm := replace(upper(v_prop.paire),'-','/');
    select coalesce((elem->>'mid')::numeric,(elem->>'last')::numeric,(elem->>'ask')::numeric) into v_cur
      from jsonb_array_elements(v_prices) elem
      where upper(elem->>'paire') = v_pair_norm or replace(upper(elem->>'paire'),'/','-') = upper(v_prop.paire) limit 1;
    if v_prop.expire_at is not null and now() > v_prop.expire_at then
      update public.alchimiste_crypte_propositions set statut='expiree', oui_at=now() where id=v_prop.id;
      v_text := v_text || 'OUI ' || v_sym || ' -> EXPIRE, a reproposer. '; v_processed := v_processed+1; continue; end if;
    if v_cur is null or v_prop.prix_ref is null or v_prop.prix_ref = 0 then
      update public.alchimiste_crypte_propositions set statut='prix_indispo', oui_at=now() where id=v_prop.id;
      v_text := v_text || 'OUI ' || v_sym || ' -> prix indispo, refuse par securite. '; v_processed := v_processed+1; continue; end if;
    v_drift := abs(v_cur - v_prop.prix_ref) / v_prop.prix_ref * 100.0;
    if v_drift > coalesce(v_prop.tolerance_pct,1.0) then
      update public.alchimiste_crypte_propositions set statut='prix_derive', oui_at=now(), prix_exec=v_cur where id=v_prop.id;
      v_text := v_text || 'OUI ' || v_sym || ' -> prix derive ' || round(v_drift,2) || 'pct, NON execute, a reproposer. '; v_processed := v_processed+1; continue; end if;
    update public.alchimiste_crypte_propositions set statut = case when p_dry_run then 'valide_simule' else 'validee_oui' end, oui_at=now(), prix_exec=v_cur where id=v_prop.id;
    v_actions := v_actions || jsonb_build_object('id',v_prop.id,'paire',v_prop.paire,'side',v_prop.side,'montant',v_prop.montant,'prix_ref',v_prop.prix_ref,'prix_exec',v_cur,'drift_pct',round(v_drift,3));
    v_text := v_text || case when p_dry_run then 'SIMULE: ' else 'VALIDE: ' end || v_prop.side || ' ' || v_prop.paire || ' ~' || coalesce(v_prop.montant::text,'?') || 'USD @' || v_cur || ' (derive ' || round(v_drift,2) || 'pct OK). '; v_processed := v_processed+1;
  end loop;
  return jsonb_build_object('processed',v_processed,'actions',v_actions,'discord_text',v_text,'dry_run',p_dry_run);
end; $function$



-- FUNCTION: alc_rebuild_virtual
CREATE OR REPLACE FUNCTION public.alc_rebuild_virtual(p_fee_pct double precision DEFAULT 0.18, p_max_hold_h integer DEFAULT 240)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_res jsonb;
begin
  truncate public.alchimiste_virtual_trades;
  insert into public.alchimiste_virtual_trades
    (proposition_id, paire, side, prix_entree, montant, opened_at, tp_pct, sl_pct,
     exit_ts, prix_sortie, exit_reason, pnl_pct, hold_hours, is_open)
  with props as (
    select id, paire, lower(side) as side, prix_ref::float8 as e, montant::float8 as m, proposed_at as t0
    from alchimiste_crypte_propositions
    where statut in ('expiree','proposee') and prix_ref > 0
      and paire not in ('USDT-USD','USDC-USD','EUR-USD')
  ),
  sim as (
    select p.*,
      case when p.side='buy' then p.e*1.05 else p.e*0.95 end as tp_price,
      case when p.side='buy' then p.e*0.96 else p.e*1.04 end as sl_price
    from props p
  ),
  hit as (
    select s.*, lat.ts as hit_ts, lat.motif as hit_motif
    from sim s
    left join lateral (
      select ph.ts,
        case when s.side='buy' then (case when ph.low<=s.sl_price then 'SL' else 'TP' end)
             else (case when ph.high>=s.sl_price then 'SL' else 'TP' end) end as motif
      from price_history ph
      where ph.symbol=s.paire and ph.interval='1h'
        and ph.ts > s.t0 and ph.ts <= s.t0 + (p_max_hold_h||' hours')::interval
        and ( (s.side='buy'  and (ph.high>=s.tp_price or ph.low<=s.sl_price))
           or (s.side='sell' and (ph.low<=s.tp_price or ph.high>=s.sl_price)) )
      order by ph.ts asc limit 1
    ) lat on true
  ),
  fin as (
    select h.*,
      (select ph.close from price_history ph where ph.symbol=h.paire and ph.interval='1h'
        and ph.ts <= h.t0 + (p_max_hold_h||' hours')::interval order by ph.ts desc limit 1) as close_maxhold,
      (select ph.close from price_history ph where ph.symbol=h.paire and ph.interval='1h'
        order by ph.ts desc limit 1) as close_now,
      (select count(*) from price_history ph where ph.symbol=h.paire and ph.interval='1h'
        and ph.ts > h.t0 and ph.ts <= h.t0 + (p_max_hold_h||' hours')::interval) as n_bougies,
      (h.t0 + (p_max_hold_h||' hours')::interval < now()) as fenetre_finie
    from hit h
  ),
  finale as (
    select f.*,
      coalesce(case when fenetre_finie then close_maxhold else close_now end, e) as cm,
      ( case when side='buy' then (coalesce(case when fenetre_finie then close_maxhold else close_now end,e)/e - 1)*100
             else (1 - coalesce(case when fenetre_finie then close_maxhold else close_now end,e)/e)*100 end ) as marche_move
    from fin f
  )
  select
    id, paire, side, e, m, t0, 5, 4,
    case when hit_motif is not null then hit_ts else null end,
    case when hit_motif='TP' then tp_price when hit_motif='SL' then sl_price
         when n_bougies=0 then null
         when fenetre_finie then close_maxhold else close_now end,
    -- GARDE-FOU : MARCHE avec mouvement aberrant (>15%) = trou de donnees -> non evaluable (le stop a 4% aurait du sortir).
    case when hit_motif is not null then hit_motif
         when n_bougies=0 then 'SANS_DONNEES'
         when fenetre_finie and abs(marche_move) > 15 then 'SANS_DONNEES'
         when fenetre_finie then 'MARCHE' else 'OUVERT' end,
    case when hit_motif='TP' then 5 - 2*p_fee_pct
         when hit_motif='SL' then -4 - 2*p_fee_pct
         when n_bougies=0 then null
         when fenetre_finie and abs(marche_move) > 15 then null
         when fenetre_finie then marche_move - 2*p_fee_pct
         else null end,
    case when hit_ts is not null then extract(epoch from (hit_ts - t0))/3600 else null end,
    (hit_motif is null and n_bougies>0 and not fenetre_finie)
  from finale;

  select jsonb_build_object(
    'trades_total', (select count(*) from alchimiste_virtual_trades),
    'clotures', (select count(*) from alchimiste_virtual_trades where exit_reason in ('TP','SL','MARCHE')),
    'tp', (select count(*) from alchimiste_virtual_trades where exit_reason='TP'),
    'sl', (select count(*) from alchimiste_virtual_trades where exit_reason='SL'),
    'marche', (select count(*) from alchimiste_virtual_trades where exit_reason='MARCHE'),
    'ouvertes', (select count(*) from alchimiste_virtual_trades where is_open),
    'sans_donnees', (select count(*) from alchimiste_virtual_trades where exit_reason='SANS_DONNEES'),
    'win_rate', (select round((count(*) filter (where exit_reason='TP'))::numeric/nullif(count(*) filter (where exit_reason in ('TP','SL')),0)*100,1) from alchimiste_virtual_trades),
    'gain_moy_pct', (select round((avg(pnl_pct) filter (where pnl_pct>0))::numeric,3) from alchimiste_virtual_trades),
    'perte_moy_pct', (select round((avg(pnl_pct) filter (where pnl_pct<0))::numeric,3) from alchimiste_virtual_trades),
    'esperance_pct', (select round((avg(pnl_pct) filter (where exit_reason in ('TP','SL','MARCHE')))::numeric,3) from alchimiste_virtual_trades),
    'somme_rendements_pct', (select round((sum(pnl_pct) filter (where exit_reason in ('TP','SL','MARCHE')))::numeric,1) from alchimiste_virtual_trades)
  ) into v_res;
  return v_res;
end $function$



-- FUNCTION: alc_record_propositions
CREATE OR REPLACE FUNCTION public.alc_record_propositions(p_run_id text, p_raw_b64 text, p_tolerance numeric DEFAULT 1.0, p_validity_hours numeric DEFAULT 6)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_raw text;
  v_obj jsonb;
  v_props jsonb;
  v_elem jsonb;
  v_dest jsonb;
  v_delem jsonb;
  v_count int := 0;
  v_paire text;
  v_side text;
  v_prix numeric;
begin
  if p_raw_b64 is null or length(p_raw_b64) = 0 then
    return 0;
  end if;
  v_raw := convert_from(decode(p_raw_b64, 'base64'), 'UTF8');
  v_raw := regexp_replace(v_raw, '```json|```', '', 'g');
  v_raw := btrim(v_raw);
  begin
    v_obj := v_raw::jsonb;
  exception when others then
    return -1;
  end;
  v_props := v_obj->'propositions';
  if v_props is null or jsonb_typeof(v_props) <> 'array' then
    return 0;
  end if;
  for v_elem in select * from jsonb_array_elements(v_props)
  loop
    v_paire := upper(coalesce(v_elem->>'paire', v_elem->>'crypto'));
    v_side  := lower(coalesce(v_elem->>'side',  v_elem->>'sens'));
    v_prix  := nullif(coalesce(v_elem->>'prix_actuel', v_elem->>'prix_ref', v_elem->>'prix'), '')::numeric;
    if v_prix is null and v_paire is not null then
      select ph.close into v_prix
      from price_history ph
      where ph.symbol = v_paire and ph.interval = '1h'
      order by ph.ts desc limit 1;
    end if;
    insert into public.alchimiste_crypte_propositions
      (run_id, paire, side, prix_ref, montant, confidence, raison, tolerance_pct, expire_at, statut, resultat)
    values (
      p_run_id,
      v_paire,
      v_side,
      v_prix,
      nullif(coalesce(v_elem->>'montant', v_elem->>'montant_usd'), '')::numeric,
      nullif(coalesce(v_elem->>'confidence', v_elem->>'gain_net_estime_pct'), '')::numeric,
      coalesce(v_elem->>'raison', v_elem->>'raison_courte'),
      p_tolerance,
      now() + make_interval(mins => (p_validity_hours*60)::int),
      'proposee',
      v_elem
    );
    v_count := v_count + 1;
  end loop;
  -- Dé-staking recommandé (nouveau schéma)
  v_dest := v_obj->'destake_recommande';
  if v_dest is not null and jsonb_typeof(v_dest) = 'array' then
    for v_delem in select * from jsonb_array_elements(v_dest)
    loop
      insert into public.alc_destake_reco
        (run_id, devise, montant_usd, gain_trade_attendu_pct, apy_staking_pct, delai_deblocage_jours, verdict, raison)
      values (
        p_run_id,
        upper(v_delem->>'devise'),
        nullif(v_delem->>'montant_usd', '')::numeric,
        nullif(v_delem->>'gain_trade_attendu_pct', '')::numeric,
        nullif(v_delem->>'apy_staking_pct', '')::numeric,
        nullif(v_delem->>'delai_deblocage_jours', '')::numeric,
        v_delem->>'verdict',
        v_delem->>'raison'
      );
    end loop;
  end if;
  return v_count;
end;
$function$



-- FUNCTION: alc_stats
CREATE OR REPLACE FUNCTION public.alc_stats()
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select jsonb_build_object(
    'trades_total', count(*),
    'clotures', count(*) filter (where exit_reason in ('TP','SL','MARCHE')),
    'tp', count(*) filter (where exit_reason='TP'),
    'sl', count(*) filter (where exit_reason='SL'),
    'positions_ouvertes', count(*) filter (where is_open),
    'non_simulables', count(*) filter (where exit_reason='SANS_DONNEES'),
    'win_rate', round((count(*) filter (where pnl_pct>0 and exit_reason in ('TP','SL','MARCHE')))::numeric
                      / nullif(count(*) filter (where exit_reason in ('TP','SL','MARCHE')),0)*100,1),
    'gain_moy_pct', round((avg(pnl_pct) filter (where pnl_pct>0 and exit_reason in ('TP','SL','MARCHE')))::numeric,2),
    'perte_moy_pct', round((avg(pnl_pct) filter (where pnl_pct<0 and exit_reason in ('TP','SL','MARCHE')))::numeric,2),
    'esperance_pct', round((avg(pnl_pct) filter (where exit_reason in ('TP','SL','MARCHE')))::numeric,3),
    'rendement_compose_pct', round(((exp(sum(ln(1 + pnl_pct/100.0)) filter (where exit_reason in ('TP','SL','MARCHE')))-1)*100)::numeric,1),
    'pnl_reel_usd', round((sum(montant * pnl_pct/100.0) filter (where exit_reason in ('TP','SL','MARCHE')))::numeric,2),
    'top_ouvertes', (select coalesce(jsonb_agg(t), '[]'::jsonb) from (
        select paire, side, round(pnl_pct::numeric,1) as rendement
        from alchimiste_virtual_trades where is_open and pnl_pct is not null
        order by pnl_pct desc limit 5) t),
    'derniere_maj', max(rebuilt_at)
  )
  from alchimiste_virtual_trades;
$function$



-- FUNCTION: batch_write_college_run
CREATE OR REPLACE FUNCTION public.batch_write_college_run(p_payload jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_run_id text;
  v_order jsonb;
  v_brain jsonb;
  v_arch text;
  v_result jsonb;
BEGIN
  v_run_id := COALESCE(p_payload->>'run_id', 'RUN-' || to_char(now(),'YYYYMMDD-HH24MI'));

  -- 1. UPSERT oracle_college_runs
  INSERT INTO oracle_college_runs (
    run_id, run_at, status, market_phase, data_completeness,
    consensus_level, risk_override, risk_override_reason,
    claude_confidence, perplexity_confidence, mistral_confidence,
    final_cash_pct, final_equities_pct, final_crypto_pct,
    final_bonds_pct, final_forex_pct, final_commodities_pct,
    orders_count, orders_executed, slack_title, slack_sent, raw_payload
  ) VALUES (
    v_run_id,
    COALESCE((p_payload->>'run_at')::timestamptz, now()),
    COALESCE(p_payload->>'status', 'success'),
    p_payload->>'market_phase',
    COALESCE((p_payload->>'data_completeness')::int, 0),
    p_payload->>'consensus_level',
    COALESCE((p_payload->>'risk_override')::boolean, false),
    p_payload->>'risk_override_reason',
    COALESCE((p_payload->'claude_decision'->>'confidence_score')::int, 0),
    COALESCE((p_payload->'perplexity_decision'->>'confidence_score')::int, 0),
    COALESCE((p_payload->'mistral_decision'->>'confidence_score')::int, 0),
    COALESCE((p_payload->'brain_synthesis'->'final_portfolio_allocation'->>'cash_pct')::numeric, 15),
    COALESCE((p_payload->'brain_synthesis'->'final_portfolio_allocation'->>'equities_pct')::numeric, 0),
    COALESCE((p_payload->'brain_synthesis'->'final_portfolio_allocation'->>'crypto_pct')::numeric, 0),
    COALESCE((p_payload->'brain_synthesis'->'final_portfolio_allocation'->>'bonds_pct')::numeric, 0),
    COALESCE((p_payload->'brain_synthesis'->'final_portfolio_allocation'->>'forex_pct')::numeric, 0),
    COALESCE((p_payload->'brain_synthesis'->'final_portfolio_allocation'->>'commodities_pct')::numeric, 0),
    COALESCE(jsonb_array_length(p_payload->'brain_synthesis'->'validated_orders'), 0),
    COALESCE(jsonb_array_length(p_payload->'alpaca_results'), 0),
    p_payload->'brain_synthesis'->'slack_message'->>'title',
    true,
    p_payload
  )
  ON CONFLICT (run_id) DO UPDATE SET
    status = EXCLUDED.status,
    data_completeness = EXCLUDED.data_completeness,
    consensus_level = EXCLUDED.consensus_level,
    orders_executed = EXCLUDED.orders_executed,
    slack_sent = true,
    raw_payload = EXCLUDED.raw_payload;

  -- 2. Insérer les ordres validés
  IF p_payload->'brain_synthesis'->'validated_orders' IS NOT NULL THEN
    FOR v_order IN SELECT * FROM jsonb_array_elements(p_payload->'brain_synthesis'->'validated_orders')
    LOOP
      INSERT INTO oracle_college_orders (
        run_id, archimage, symbol, side, asset_class,
        size_pct_portfolio, notional, broker, broker_order_id, broker_status,
        rationale, urgency, stop_loss_pct, take_profit_pct, validated
      ) VALUES (
        v_run_id,
        COALESCE(v_order->>'archimage', 'cerveau'),
        COALESCE(v_order->>'symbol', 'SPY'),
        COALESCE(v_order->>'side', 'buy'),
        COALESCE(v_order->>'asset_class', 'equity'),
        COALESCE((v_order->>'size_pct_portfolio')::numeric, 0),
        COALESCE((v_order->>'notional')::numeric, 0),
        COALESCE(v_order->>'broker', 'alpaca'),
        v_order->>'broker_order_id',
        COALESCE(v_order->>'broker_status', 'submitted'),
        v_order->>'rationale',
        COALESCE(v_order->>'urgency', 'immediate'),
        COALESCE((v_order->>'stop_loss_pct')::numeric, 5),
        COALESCE((v_order->>'take_profit_pct')::numeric, 10),
        true
      );
    END LOOP;
  END IF;

  -- 3. Mettre à jour brain_state pour chaque archimage
  IF p_payload->'brain_state_updates' IS NOT NULL THEN
    FOR v_arch IN SELECT jsonb_object_keys(p_payload->'brain_state_updates')
    LOOP
      v_brain := p_payload->'brain_state_updates'->v_arch;
      UPDATE oracle_brain_state SET
        last_run_at = now(),
        last_run_id = v_run_id,
        total_runs = total_runs + 1,
        current_bias = COALESCE(v_brain->>'current_bias', current_bias),
        risk_appetite = COALESCE(v_brain->>'risk_appetite', risk_appetite),
        synthesis_weight = COALESCE((v_brain->>'synthesis_weight')::numeric, synthesis_weight),
        last_decision = COALESCE(v_brain->'last_decision', last_decision),
        learnings = CASE 
          WHEN v_brain->'new_learning' IS NOT NULL 
          THEN (learnings || v_brain->'new_learning')
          ELSE learnings 
        END,
        updated_at = now()
      WHERE archimage = v_arch;
    END LOOP;
  END IF;

  -- 4. Insérer rapport sages
  IF p_payload->'sages_report' IS NOT NULL THEN
    INSERT INTO oracle_sages_report (run_id, sage_name, sage_output)
    SELECT v_run_id, key, value
    FROM jsonb_each(p_payload->'sages_report');
  END IF;

  RETURN jsonb_build_object(
    'success', true, 'run_id', v_run_id,
    'orders_written', COALESCE(jsonb_array_length(p_payload->'brain_synthesis'->'validated_orders'), 0),
    'timestamp', now()
  );
EXCEPTION WHEN OTHERS THEN
  RETURN jsonb_build_object('success', false, 'error', SQLERRM, 'run_id', v_run_id);
END;
$function$



-- FUNCTION: batch_write_college_run_v2
CREATE OR REPLACE FUNCTION public.batch_write_college_run_v2(p_payload jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_run_id text;
  v_order jsonb;
  v_arch text;
  v_brain jsonb;
  v_orders_buy integer := 0;
  v_orders_sell integer := 0;
  v_total_notional numeric := 0;
  v_total_capped numeric := 0;
  v_capped_count integer := 0;
  v_overlap_score numeric := 0;
  v_ju_tickers text[];
  v_syl_tickers text[];
  v_gil_tickers text[];
BEGIN
  -- !! CORRECTION BUG : run_id forcé non-vide non-ND
  v_run_id := NULLIF(TRIM(COALESCE(p_payload->>'run_id', '')), '');
  IF v_run_id IS NULL OR v_run_id = 'ND' THEN
    v_run_id := 'COLLEGE-' || to_char(now(), 'YYYYMMDD-HH24MI-US');
  END IF;

  -- Compter ordres buy/sell et calculer overlap
  IF p_payload->'orders' IS NOT NULL THEN
    FOR v_order IN SELECT * FROM jsonb_array_elements(p_payload->'orders')
    LOOP
      IF LOWER(v_order->>'side') = 'buy' THEN
        v_orders_buy := v_orders_buy + 1;
      ELSE
        v_orders_sell := v_orders_sell + 1;
      END IF;
      v_total_notional := v_total_notional + COALESCE((v_order->>'notional')::numeric, 0);
      IF (v_order->>'notional')::numeric > 2000 THEN
        v_capped_count := v_capped_count + 1;
        v_total_capped := v_total_capped + (COALESCE((v_order->>'notional')::numeric, 0) - 2000);
      END IF;
    END LOOP;
  END IF;

  -- Calculer overlap score inter-archimages (alias 'elem' pour ne pas masquer la variable v_order)
  SELECT ARRAY(SELECT DISTINCT UPPER(elem->>'ticker') FROM jsonb_array_elements(p_payload->'orders') elem WHERE elem->>'archimage' = 'JU') INTO v_ju_tickers;
  SELECT ARRAY(SELECT DISTINCT UPPER(elem->>'ticker') FROM jsonb_array_elements(p_payload->'orders') elem WHERE elem->>'archimage' = 'SYL') INTO v_syl_tickers;
  SELECT ARRAY(SELECT DISTINCT UPPER(elem->>'ticker') FROM jsonb_array_elements(p_payload->'orders') elem WHERE elem->>'archimage' = 'GIL') INTO v_gil_tickers;

  -- Score d'overlap : combien de tickers en commun entre les 3 (idéal = 0)
  IF array_length(v_ju_tickers, 1) > 0 AND array_length(v_syl_tickers, 1) > 0 THEN
    SELECT ROUND(
      (SELECT COUNT(*) FROM unnest(v_ju_tickers) t WHERE t = ANY(v_syl_tickers))::numeric /
      GREATEST(array_length(v_ju_tickers, 1), 1) * 50 +
      (SELECT COUNT(*) FROM unnest(v_ju_tickers) t WHERE t = ANY(v_gil_tickers))::numeric /
      GREATEST(array_length(v_ju_tickers, 1), 1) * 25 +
      (SELECT COUNT(*) FROM unnest(v_syl_tickers) t WHERE t = ANY(v_gil_tickers))::numeric /
      GREATEST(array_length(v_syl_tickers, 1), 1) * 25
    , 2) INTO v_overlap_score;
  END IF;

  -- UPSERT oracle_college_runs avec toutes les nouvelles colonnes
  INSERT INTO oracle_college_runs (
    run_id, run_at, status, market_phase, data_completeness,
    consensus_level, risk_override, claude_confidence, perplexity_confidence, mistral_confidence,
    orders_count, orders_executed, orders_buy, orders_sell,
    orders_capped_notional, total_notional_submitted, total_notional_capped,
    overlap_score, circuit_breaker_fired,
    ju_universe_zone, syl_universe_zone, gil_universe_zone,
    syl_web_catalysts, syl_top_catalyst_ticker,
    slack_title, slack_sent, raw_payload
  ) VALUES (
    v_run_id,
    COALESCE((p_payload->>'run_at')::timestamptz, now()),
    COALESCE(p_payload->>'status', 'success'),
    COALESCE(p_payload->>'market_phase', 'NEUTRAL'),
    COALESCE((p_payload->>'data_completeness')::int, 0),
    COALESCE(p_payload->>'consensus_level', 'SPLIT'),
    COALESCE((p_payload->>'risk_override')::boolean, false),
    COALESCE((p_payload->>'claude_confidence')::int, 0),
    COALESCE((p_payload->>'perplexity_confidence')::int, 0),
    COALESCE((p_payload->>'mistral_confidence')::int, 0),
    v_orders_buy + v_orders_sell,
    0, -- orders_executed mis à jour par execute-trades
    v_orders_buy,
    v_orders_sell,
    v_capped_count,
    v_total_notional,
    v_total_capped,
    v_overlap_score,
    false,
    'US_EQUITIES_LARGECAP', 'INTERNATIONAL_MACRO_NEWS', 'CRYPTO_TACTICAL_DERIVATIVES',
    p_payload->>'syl_web_catalysts',
    p_payload->>'syl_top_catalyst',
    COALESCE(p_payload->>'slack_title', 'Oracle v5 ' || v_run_id),
    true,
    p_payload
  )
  ON CONFLICT (run_id) DO UPDATE SET
    status = EXCLUDED.status,
    orders_executed = oracle_college_runs.orders_executed,
    overlap_score = EXCLUDED.overlap_score,
    orders_buy = EXCLUDED.orders_buy,
    orders_sell = EXCLUDED.orders_sell,
    raw_payload = EXCLUDED.raw_payload;

  -- Insérer les ordres avec iron_sentinel validation inline
  IF p_payload->'orders' IS NOT NULL THEN
    FOR v_order IN SELECT * FROM jsonb_array_elements(p_payload->'orders')
    LOOP
      INSERT INTO oracle_college_orders (
        run_id, archimage, symbol, side, asset_class,
        size_pct_portfolio, notional, broker, broker_status,
        rationale, urgency, stop_loss_pct, take_profit_pct,
        validated, universe_zone, web_catalyst,
        is_liquidation
      ) VALUES (
        v_run_id,
        COALESCE(v_order->>'archimage', 'JU'),
        UPPER(COALESCE(v_order->>'ticker', v_order->>'symbol', 'SPY')),
        LOWER(COALESCE(v_order->>'side', 'buy')),
        COALESCE(v_order->>'asset_class', 'equity'),
        COALESCE((v_order->>'size_pct_portfolio')::numeric, 0),
        COALESCE((v_order->>'notional')::numeric, 300),
        COALESCE(v_order->>'broker', 'alpaca'),
        COALESCE(v_order->>'broker_status', 'pending_new'),
        v_order->>'rationale',
        COALESCE(v_order->>'urgency', 'immediate'),
        COALESCE((v_order->>'stop_loss_pct')::numeric, 5),
        COALESCE((v_order->>'take_profit_pct')::numeric, 10),
        true,
        CASE 
          WHEN v_order->>'archimage' = 'JU' THEN 'US_EQUITIES_LARGECAP'
          WHEN v_order->>'archimage' = 'SYL' THEN 'INTERNATIONAL_MACRO_NEWS'
          WHEN v_order->>'archimage' = 'GIL' THEN 'CRYPTO_TACTICAL_DERIVATIVES'
          ELSE 'global' END,
        v_order->>'web_catalyst',
        COALESCE((v_order->>'is_liquidation')::boolean, LOWER(v_order->>'side') = 'sell')
      );
    END LOOP;
  END IF;

  -- Mettre à jour brain_state pour chaque archimage
  IF p_payload->'brain_state_updates' IS NOT NULL THEN
    FOR v_arch IN SELECT jsonb_object_keys(p_payload->'brain_state_updates')
    LOOP
      v_brain := p_payload->'brain_state_updates'->v_arch;
      UPDATE oracle_brain_state SET
        last_run_at = now(),
        last_run_id = v_run_id,
        current_bias = COALESCE(v_brain->>'current_bias', current_bias),
        risk_appetite = COALESCE(v_brain->>'risk_appetite', risk_appetite),
        synthesis_weight = COALESCE((v_brain->>'synthesis_weight')::numeric, synthesis_weight),
        last_decision = COALESCE(v_brain->'last_decision', last_decision),
        learnings = CASE 
          WHEN v_brain->'new_learning' IS NOT NULL 
          THEN learnings || v_brain->'new_learning'
          ELSE learnings END,
        updated_at = now()
      WHERE archimage = v_arch;
    END LOOP;
  END IF;

  RETURN jsonb_build_object(
    'success', true,
    'run_id', v_run_id,
    'orders_written', v_orders_buy + v_orders_sell,
    'orders_buy', v_orders_buy,
    'orders_sell', v_orders_sell,
    'overlap_score', v_overlap_score,
    'notional_capped_count', v_capped_count,
    'total_capped_amount', v_total_capped,
    'timestamp', now()
  );

EXCEPTION WHEN OTHERS THEN
  RETURN jsonb_build_object('success', false, 'error', SQLERRM, 'run_id', v_run_id);
END;
$function$



-- FUNCTION: batch_write_oracle_run
CREATE OR REPLACE FUNCTION public.batch_write_oracle_run(p_run jsonb, p_orders jsonb DEFAULT '[]'::jsonb, p_market jsonb DEFAULT '{}'::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_run_id text;
  v_order jsonb;
  v_result jsonb;
BEGIN
  -- Extraire run_id
  v_run_id := p_run->>'run_id';
  
  IF v_run_id IS NULL OR v_run_id = '' THEN
    v_run_id := 'SAGE-' || to_char(now(), 'YYYYMMDD-HH24MI');
  END IF;

  -- UPSERT oracle_runs
  INSERT INTO oracle_runs (
    run_id, market_phase, risk_score, confidence, data_completeness,
    master_word, action_type, status, allocation_cash, allocation_defensive, allocation_risk,
    spy_price, vix_value, oil_price, btc_price, fear_greed, t10y_rate, t2y_rate, fed_rate, cpi_value,
    claude_synthesis, signals_positive, signals_negative, guardrails,
    revolut_manual_action, learning_update,
    synth_a_phase, synth_b_phase, synth_c_phase, synth_agreement, verdict_final,
    sage_macro_score, sage_geopo_score, sage_quant_score, sage_tech_score,
    sage_vision_niche1, sage_vision_niche2, sage_rotation_etf,
    crypto_allocation, crypto_recommended_ticker,
    position1_ticker, position1_action, position1_alloc, position1_conviction,
    slack_sent, trades_count, memory_summary, error_log,
    visionary_view_short, visionary_view_long, run_at
  ) VALUES (
    v_run_id,
    COALESCE(p_run->>'market_phase', 'DEGRADED'),
    COALESCE((p_run->>'risk_score')::integer, 0),
    COALESCE((p_run->>'confidence')::integer, 0),
    COALESCE((p_run->>'data_completeness')::integer, 0),
    COALESCE(p_run->>'master_word', 'ND'),
    COALESCE(p_run->>'action_type', 'INVEST'),
    COALESCE(p_run->>'status', 'DEGRADED'),
    COALESCE((p_run->>'allocation_cash')::integer, 40),
    COALESCE((p_run->>'allocation_defensive')::integer, 20),
    COALESCE((p_run->>'allocation_risk')::integer, 40),
    COALESCE((p_run->>'spy_price')::numeric, 0),
    COALESCE((p_run->>'vix_value')::numeric, 0),
    COALESCE((p_run->>'oil_price')::numeric, 0),
    COALESCE((p_run->>'btc_price')::numeric, 0),
    COALESCE((p_run->>'fear_greed')::integer, 50),
    COALESCE((p_run->>'t10y_rate')::numeric, 0),
    COALESCE((p_run->>'t2y_rate')::numeric, 0),
    COALESCE((p_run->>'fed_rate')::numeric, 0),
    COALESCE((p_run->>'cpi_value')::numeric, 0),
    COALESCE(p_run->>'claude_synthesis', 'ND'),
    COALESCE(p_run->>'signals_positive', 'ND'),
    COALESCE(p_run->>'signals_negative', 'ND'),
    COALESCE(p_run->>'guardrails', 'ND'),
    COALESCE(p_run->>'revolut_manual_action', 'ND'),
    COALESCE(p_run->>'learning_update', 'ND'),
    COALESCE(p_run->>'synth_a_phase', 'DEGRADED'),
    COALESCE(p_run->>'synth_b_phase', 'DEGRADED'),
    COALESCE(p_run->>'synth_c_phase', 'DEGRADED'),
    COALESCE((p_run->>'synth_agreement')::boolean, false),
    COALESCE(p_run->>'verdict_final', 'ND'),
    COALESCE((p_run->>'sage_macro_score')::integer, 0),
    COALESCE((p_run->>'sage_geopo_score')::integer, 0),
    COALESCE((p_run->>'sage_quant_score')::integer, 0),
    COALESCE((p_run->>'sage_tech_score')::integer, 0),
    COALESCE(p_run->>'sage_vision_niche1', 'ND'),
    COALESCE(p_run->>'sage_vision_niche2', 'ND'),
    COALESCE(p_run->>'sage_rotation_etf', 'ND'),
    COALESCE((p_run->>'crypto_allocation')::integer, 0),
    COALESCE(p_run->>'crypto_recommended_ticker', 'ND'),
    COALESCE(p_run->>'position1_ticker', 'SPY'),
    COALESCE(p_run->>'position1_action', 'BUY'),
    COALESCE((p_run->>'position1_alloc')::integer, 100),
    COALESCE((p_run->>'position1_conviction')::integer, 5),
    true,
    jsonb_array_length(p_orders),
    COALESCE(p_run->>'memory_summary', 'ND'),
    COALESCE(p_run->>'error_log', 'OK'),
    COALESCE(p_run->>'visionary_view_short', 'ND'),
    COALESCE(p_run->>'visionary_view_long', 'ND'),
    now()
  )
  ON CONFLICT (run_id) DO UPDATE SET
    market_phase = EXCLUDED.market_phase,
    risk_score = EXCLUDED.risk_score,
    confidence = EXCLUDED.confidence,
    data_completeness = EXCLUDED.data_completeness,
    master_word = EXCLUDED.master_word,
    action_type = EXCLUDED.action_type,
    status = EXCLUDED.status,
    claude_synthesis = EXCLUDED.claude_synthesis,
    signals_positive = EXCLUDED.signals_positive,
    signals_negative = EXCLUDED.signals_negative,
    position1_ticker = EXCLUDED.position1_ticker,
    position1_action = EXCLUDED.position1_action,
    slack_sent = true,
    trades_count = EXCLUDED.trades_count,
    run_at = now();

  -- Insérer les ordres Alpaca en batch (si présents)
  IF jsonb_array_length(p_orders) > 0 THEN
    FOR v_order IN SELECT * FROM jsonb_array_elements(p_orders)
    LOOP
      INSERT INTO alpaca_orders (
        run_id, symbol, side, type, notional, status,
        oracle_rationale, account, archimage, order_type_label, is_paper
      ) VALUES (
        v_run_id,
        COALESCE(v_order->>'symbol', 'SPY'),
        COALESCE(v_order->>'side', 'buy'),
        COALESCE(v_order->>'order_type', 'market'),
        COALESCE((v_order->>'notional')::numeric, 500),
        COALESCE(v_order->>'status', 'submitted'),
        COALESCE(v_order->>'rationale', 'ND'),
        COALESCE(v_order->>'account', 'Ju'),
        COALESCE(v_order->>'archimage', 'JU'),
        'market',
        true
      ) ON CONFLICT (alpaca_order_id) DO NOTHING;
    END LOOP;
  END IF;

  -- Retourner confirmation
  v_result := jsonb_build_object(
    'success', true,
    'run_id', v_run_id,
    'orders_logged', jsonb_array_length(p_orders),
    'timestamp', now()
  );
  
  RETURN v_result;
  
EXCEPTION WHEN OTHERS THEN
  RETURN jsonb_build_object(
    'success', false,
    'error', SQLERRM,
    'run_id', v_run_id
  );
END;
$function$



-- FUNCTION: bt_optimize_alchimiste
CREATE OR REPLACE FUNCTION public.bt_optimize_alchimiste(p_fee_pct numeric DEFAULT 0.18, p_max_hold integer DEFAULT 240, p_tps numeric[] DEFAULT ARRAY[(2)::numeric, 2.5, (3)::numeric, 3.2, 3.5, (4)::numeric, (5)::numeric, (7)::numeric], p_sls numeric[] DEFAULT ARRAY[1.5, (2)::numeric, 2.5, 2.6, (3)::numeric, (4)::numeric], p_from timestamp with time zone DEFAULT NULL::timestamp with time zone, p_to timestamp with time zone DEFAULT NULL::timestamp with time zone)
 RETURNS TABLE(tp_pct numeric, sl_pct numeric, trades integer, win_rate numeric, avg_ret_pct numeric, total_ret_pct numeric)
 LANGUAGE plpgsql
 SET search_path TO 'public'
AS $function$
declare
  p record; highs numeric[]; lows numeric[]; closes numeric[];
  n int; k int; ret numeric; tpv numeric; slv numeric; v_side text;
begin
  create temp table if not exists bt_tmp2 (tp numeric, sl numeric, ret numeric);
  delete from bt_tmp2;
  for p in
    select acp.paire, acp.prix_ref, acp.proposed_at, acp.side
    from public.alchimiste_crypte_propositions acp
    where acp.prix_ref is not null and acp.prix_ref>0 and lower(acp.side) in ('buy','sell')
      and acp.proposed_at >= coalesce(p_from, (select min(ts) from public.price_history))
      and acp.proposed_at < coalesce(p_to, now())
      and acp.proposed_at >= (select min(ts) from public.price_history)
  loop
    select array_agg(ph.high order by ph.ts), array_agg(ph.low order by ph.ts), array_agg(ph.close order by ph.ts)
      into highs, lows, closes from public.price_history ph
      where ph.symbol=p.paire and ph.interval='1h' and ph.ts > p.proposed_at;
    n := coalesce(array_length(highs,1),0);
    if n=0 then continue; end if;
    v_side := lower(p.side);
    foreach tpv in array p_tps loop
      foreach slv in array p_sls loop
        ret := null; k := 1;
        if v_side='buy' then
          -- CONSERVATEUR : on teste le SL AVANT le TP (si une bougie touche les deux, on compte la perte)
          while k <= least(n,p_max_hold) loop
            if lows[k]  <= p.prix_ref*(1-slv/100) then ret := -slv; exit; end if;
            if highs[k] >= p.prix_ref*(1+tpv/100) then ret :=  tpv; exit; end if;
            k := k+1;
          end loop;
          if ret is null then ret := (closes[least(n,p_max_hold)]/p.prix_ref-1)*100; end if;
        else
          -- SHORT : TP = prix qui BAISSE de tpv%, SL = prix qui MONTE de slv%. SL teste en premier.
          while k <= least(n,p_max_hold) loop
            if highs[k] >= p.prix_ref*(1+slv/100) then ret := -slv; exit; end if;
            if lows[k]  <= p.prix_ref*(1-tpv/100) then ret :=  tpv; exit; end if;
            k := k+1;
          end loop;
          if ret is null then ret := -(closes[least(n,p_max_hold)]/p.prix_ref-1)*100; end if;
        end if;
        -- frais aller-retour (entree + sortie)
        insert into bt_tmp2 values (tpv, slv, ret - 2*p_fee_pct);
      end loop;
    end loop;
  end loop;
  return query
  select t.tp, t.sl, count(*)::int,
    round(count(*) filter (where t.ret>0)*100.0/count(*),1),
    round(avg(t.ret),3),
    round(((exp(sum(ln(greatest(1+t.ret/100, 0.01))))-1)*100)::numeric,2)
  from bt_tmp2 t group by t.tp, t.sl order by 6 desc;
end;
$function$



-- FUNCTION: bt_optimize_exits
CREATE OR REPLACE FUNCTION public.bt_optimize_exits(p_fee_pct numeric DEFAULT 0.18, p_max_hold integer DEFAULT 240, p_tps numeric[] DEFAULT ARRAY[(2)::numeric, 2.5, (3)::numeric, 3.2, 3.5, (4)::numeric, (5)::numeric, (7)::numeric], p_sls numeric[] DEFAULT ARRAY[1.5, (2)::numeric, 2.5, 2.6, (3)::numeric, (4)::numeric])
 RETURNS TABLE(tp_pct numeric, sl_pct numeric, trades integer, win_rate numeric, avg_ret_pct numeric, total_ret_pct numeric)
 LANGUAGE plpgsql
 SET search_path TO 'public'
AS $function$
declare
  o record; sym_ph text; highs numeric[]; lows numeric[]; closes numeric[];
  n int; k int; ret numeric; tpv numeric; slv numeric;
begin
  create temp table if not exists bt_tmp (tp numeric, sl numeric, ret numeric);
  delete from bt_tmp;
  for o in
    select oco.symbol as sym, oco.fill_price::numeric as fp, oco.created_at as ca
    from public.oracle_college_orders oco
    where oco.symbol in ('BTCUSD','ETHUSD','SOLUSD') and oco.fill_price is not null
      and lower(oco.side)='buy' and oco.created_at >= (select min(ts) from public.price_history)
  loop
    sym_ph := case o.sym when 'BTCUSD' then 'BTC-USD' when 'ETHUSD' then 'ETH-USD' when 'SOLUSD' then 'SOL-USD' end;
    select array_agg(ph.high order by ph.ts), array_agg(ph.low order by ph.ts), array_agg(ph.close order by ph.ts)
      into highs, lows, closes from public.price_history ph
      where ph.symbol=sym_ph and ph.interval='1h' and ph.ts > o.ca;
    n := coalesce(array_length(highs,1),0);
    if n=0 or o.fp is null or o.fp=0 then continue; end if;
    foreach tpv in array p_tps loop
      foreach slv in array p_sls loop
        ret := null; k := 1;
        while k <= least(n,p_max_hold) loop
          if highs[k] >= o.fp*(1+tpv/100) then ret := tpv; exit; end if;
          if lows[k]  <= o.fp*(1-slv/100) then ret := -slv; exit; end if;
          k := k+1;
        end loop;
        if ret is null then ret := (closes[least(n,p_max_hold)]/o.fp-1)*100; end if;
        insert into bt_tmp values (tpv, slv, ret - p_fee_pct);
      end loop;
    end loop;
  end loop;
  return query
  select t.tp, t.sl, count(*)::int,
    round(count(*) filter (where t.ret>0)*100.0/count(*),1),
    round(avg(t.ret),3),
    round(((exp(sum(ln(greatest(1+t.ret/100, 0.01))))-1)*100)::numeric,2)
  from bt_tmp t group by t.tp, t.sl order by 6 desc;
end;
$function$



-- FUNCTION: bt_replay_archmages
CREATE OR REPLACE FUNCTION public.bt_replay_archmages(p_fee_pct numeric DEFAULT 0.18, p_max_hold integer DEFAULT 240)
 RETURNS TABLE(archimage text, trades integer, win_rate numeric, avg_ret_pct numeric, total_ret_pct numeric, profit_factor numeric)
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'public'
AS $function$
declare
  o record; sym_ph text; highs numeric[]; lows numeric[]; closes numeric[];
  n int; k int; ret numeric;
  arch_arr text[] := '{}'; ret_arr numeric[] := '{}';
begin
  for o in
    select oco.archimage as arch, oco.symbol as sym, oco.fill_price::numeric as fp, oco.created_at as ca,
           coalesce(oco.take_profit_pct,7)::numeric as tp, coalesce(oco.stop_loss_pct,4)::numeric as sl
    from public.oracle_college_orders oco
    where oco.symbol in ('BTCUSD','ETHUSD','SOLUSD')
      and oco.fill_price is not null and lower(oco.side)='buy'
      and oco.created_at >= (select min(ts) from public.price_history)
  loop
    sym_ph := case o.sym when 'BTCUSD' then 'BTC-USD' when 'ETHUSD' then 'ETH-USD' when 'SOLUSD' then 'SOL-USD' end;
    select array_agg(ph.high order by ph.ts), array_agg(ph.low order by ph.ts), array_agg(ph.close order by ph.ts)
      into highs, lows, closes
      from public.price_history ph
      where ph.symbol=sym_ph and ph.interval='1h' and ph.ts > o.ca;
    n := coalesce(array_length(highs,1),0);
    if n=0 or o.fp is null or o.fp=0 then continue; end if;
    ret := null; k := 1;
    while k <= least(n, p_max_hold) loop
      if highs[k] >= o.fp*(1+o.tp/100) then ret := o.tp; exit; end if;
      if lows[k]  <= o.fp*(1-o.sl/100) then ret := -o.sl; exit; end if;
      k := k+1;
    end loop;
    if ret is null then ret := (closes[least(n,p_max_hold)]/o.fp - 1)*100; end if;
    ret := ret - p_fee_pct;
    arch_arr := arch_arr || o.arch; ret_arr := ret_arr || ret;
  end loop;

  return query
  select a.arch, count(*)::int,
    round(count(*) filter (where a.r>0)*100.0/nullif(count(*),0),1),
    round(avg(a.r),3),
    round(((exp(sum(ln(1+a.r/100)))-1)*100)::numeric,2),
    round((sum(a.r) filter (where a.r>0))/nullif(abs(sum(a.r) filter (where a.r<0)),0),2)
  from unnest(arch_arr, ret_arr) as a(arch, r)
  group by a.arch order by 5 desc;
end;
$function$



-- FUNCTION: bt_replay_tpsl
CREATE OR REPLACE FUNCTION public.bt_replay_tpsl(p_tp_pct numeric DEFAULT 7, p_sl_pct numeric DEFAULT 4, p_every_bars integer DEFAULT 24, p_fee_pct numeric DEFAULT 0.18, p_slip_pct numeric DEFAULT 0.10, p_max_hold integer DEFAULT 240)
 RETURNS TABLE(symbol text, trades integer, win_rate numeric, avg_ret_pct numeric, total_ret_pct numeric, profit_factor numeric, max_dd_pct numeric, sharpe_like numeric)
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'public'
AS $function$
declare
  sym text; highs numeric[]; lows numeric[]; closes numeric[];
  n int; i int; j int; entry numeric; ret numeric;
  wins int; losses int; gross_win numeric; gross_loss numeric;
  rets numeric[]; equity numeric; peak numeric; dd numeric; maxdd numeric;
  tcount int; sumret numeric;
begin
  for sym in select distinct ph.symbol from public.price_history ph where ph.interval='1h' loop
    select array_agg(ph.close order by ph.ts), array_agg(ph.high order by ph.ts), array_agg(ph.low order by ph.ts)
      into closes, highs, lows
      from public.price_history ph where ph.symbol=sym and ph.interval='1h';
    n := coalesce(array_length(closes,1),0);
    wins:=0; losses:=0; gross_win:=0; gross_loss:=0; rets:=array[]::numeric[]; tcount:=0; sumret:=0;
    equity:=100; peak:=100; maxdd:=0; i:=1;
    while i <= n loop
      entry := closes[i] * (1 + p_slip_pct/100);
      ret := null; j := i+1;
      while j <= least(i+p_max_hold, n) loop
        if highs[j] >= entry*(1+p_tp_pct/100) then ret := p_tp_pct; exit; end if;
        if lows[j]  <= entry*(1-p_sl_pct/100) then ret := -p_sl_pct; exit; end if;
        j := j+1;
      end loop;
      if ret is null and i < n then ret := (closes[least(i+p_max_hold,n)]/entry - 1)*100; end if;
      if ret is not null then
        ret := ret - p_fee_pct;
        tcount:=tcount+1; sumret:=sumret+ret; rets:=rets||ret;
        if ret>0 then wins:=wins+1; gross_win:=gross_win+ret; else losses:=losses+1; gross_loss:=gross_loss+abs(ret); end if;
        equity:=equity*(1+ret/100);
        if equity>peak then peak:=equity; end if;
        dd:=(peak-equity)/peak*100; if dd>maxdd then maxdd:=dd; end if;
      end if;
      i := i + p_every_bars;
    end loop;
    if tcount>0 then
      symbol:=sym; trades:=tcount; win_rate:=round(wins*100.0/tcount,1);
      avg_ret_pct:=round(sumret/tcount,3); total_ret_pct:=round((equity-100),2);
      profit_factor:=round(gross_win/nullif(gross_loss,0),2); max_dd_pct:=round(maxdd,2);
      select round((avg(r)/nullif(stddev_pop(r),0))::numeric,3) into sharpe_like from unnest(rets) r;
      return next;
    end if;
  end loop;
end;
$function$



-- FUNCTION: check_circuit_breakers
-- 21/08 : FORCE_CONTRARIAN restaure et etendu a tous les agents.
-- La regle d'origine vivait dans le prompt du Sage Memoire (module 207) avant le 13/08 :
--   « si les 3 dernieres decisions JU sont identiques meme ticker et meme side ET que le PnL est
--     negatif alors FORCE_CONTRARIAN egal true »
-- Elle a disparu le 19/08 (commit f65384c) en elargissant le Sage Memoire a 5 agents.
-- On ne cree AUCUN objet : check_circuit_breakers() et oracle_circuit_breakers existent deja et
-- sont deja injectees dans les prompts via CTX (110), SAGES (215) et les 3 Archimages. On etend.
CREATE OR REPLACE FUNCTION public.check_circuit_breakers()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_fired int := 0;
  b record;
  v_sym text; v_side text; v_n int; v_eval int;
begin
  for b in
    select archimage, current_drawdown, consecutive_losses, current_streak_type,
           win_rate, wins, losses, alpaca_portfolio_value, last_run_id
    from public.oracle_brain_state
    where archimage <> 'cerveau'          -- 21/08 : tous les agents, plus seulement JU/SYL/GIL
  loop
    ---------------------------------------------------------------- drawdown
    if b.current_drawdown >= 0.08 then
      if not exists (select 1 from public.oracle_circuit_breakers
                      where archimage=b.archimage and breaker_type='drawdown_8pct' and auto_resolved=false) then
        insert into public.oracle_circuit_breakers (archimage, run_id, breaker_type, trigger_value, threshold_value, action_taken, capital_protected, notes)
        values (b.archimage, b.last_run_id, 'drawdown_8pct', round(b.current_drawdown,4), 0.08, 'poids_plancher_0.05', b.alpaca_portfolio_value,
                'Drawdown critique : poids reduit au plancher par update-brain');
        v_fired := v_fired + 1;
      end if;
    elsif b.current_drawdown >= 0.05 then
      if not exists (select 1 from public.oracle_circuit_breakers
                      where archimage=b.archimage and breaker_type='drawdown_5pct' and auto_resolved=false) then
        insert into public.oracle_circuit_breakers (archimage, run_id, breaker_type, trigger_value, threshold_value, action_taken, capital_protected, notes)
        values (b.archimage, b.last_run_id, 'drawdown_5pct', round(b.current_drawdown,4), 0.05, 'poids_coupe_moitie', b.alpaca_portfolio_value,
                'Drawdown >= 5% : poids coupe de moitie par update-brain');
        v_fired := v_fired + 1;
      end if;
    end if;

    ---------------------------------------------------- pertes consecutives
    if coalesce(b.consecutive_losses,0) >= 5 then
      if not exists (select 1 from public.oracle_circuit_breakers
                      where archimage=b.archimage and breaker_type='pertes_consecutives_5' and auto_resolved=false) then
        insert into public.oracle_circuit_breakers (archimage, run_id, breaker_type, trigger_value, threshold_value, action_taken, capital_protected, notes)
        values (b.archimage, b.last_run_id, 'pertes_consecutives_5', b.consecutive_losses, 5, 'prudence_maximale_demandee', b.alpaca_portfolio_value,
                '5+ runs perdants consecutifs : reduire les tailles et couper les positions perdantes');
        v_fired := v_fired + 1;
      end if;
    end if;

    ------------------------------------- FORCE_CONTRARIAN (restaure du 13/08)
    -- 3 dernieres decisions identiques (meme symbole ET meme sens) pendant une serie perdante.
    if b.archimage in ('JU','SYL','GIL') and coalesce(b.current_streak_type,'') = 'loss' then
      select count(*), max(symbol), max(lower(side))
        into v_n, v_sym, v_side
      from (select symbol, side from public.oracle_college_orders
             where archimage = b.archimage order by created_at desc limit 3) d;
      if v_n = 3
         and (select count(distinct symbol) from (select symbol from public.oracle_college_orders
               where archimage=b.archimage order by created_at desc limit 3) x) = 1
         and (select count(distinct lower(side)) from (select side from public.oracle_college_orders
               where archimage=b.archimage order by created_at desc limit 3) y) = 1
      then
        if not exists (select 1 from public.oracle_circuit_breakers
                        where archimage=b.archimage and breaker_type='repetition_identique_perdante' and auto_resolved=false) then
          insert into public.oracle_circuit_breakers (archimage, run_id, breaker_type, trigger_value, threshold_value, action_taken, capital_protected, notes)
          values (b.archimage, b.last_run_id, 'repetition_identique_perdante', 3, 3, 'force_contrarian', b.alpaca_portfolio_value,
                  'FORCE_CONTRARIAN : 3 decisions identiques ('||coalesce(v_side,'?')||' '||coalesce(v_sym,'?')||') pendant une serie perdante. Changer de these ou ne rien faire, ne pas repeter.');
          v_fired := v_fired + 1;
        end if;
      end if;
    end if;

    ------------------------------------------------- sous-performance durable
    v_eval := coalesce(b.wins,0) + coalesce(b.losses,0);
    if v_eval >= 20 and coalesce(b.win_rate,1) < 0.40 then
      if not exists (select 1 from public.oracle_circuit_breakers
                      where archimage=b.archimage and breaker_type='win_rate_faible' and auto_resolved=false) then
        insert into public.oracle_circuit_breakers (archimage, run_id, breaker_type, trigger_value, threshold_value, action_taken, capital_protected, notes)
        values (b.archimage, b.last_run_id, 'win_rate_faible', round(b.win_rate::numeric,3), 0.40, 'selection_a_revoir', b.alpaca_portfolio_value,
                'Win rate '||round(b.win_rate::numeric*100,1)||'% sur '||v_eval||' decisions evaluees : le probleme est la SELECTION, pas la frequence. Moins de decisions, plus de conviction.');
        v_fired := v_fired + 1;
      end if;
    end if;

    ------------------------------------------------- resolutions automatiques
    update public.oracle_circuit_breakers set auto_resolved = true, resolved_at = now()
      where archimage = b.archimage and auto_resolved = false
        and ((breaker_type='drawdown_8pct' and b.current_drawdown < 0.08)
          or (breaker_type='drawdown_5pct' and b.current_drawdown < 0.05)
          or (breaker_type='pertes_consecutives_5' and coalesce(b.consecutive_losses,0) < 5)
          or (breaker_type='repetition_identique_perdante' and coalesce(b.current_streak_type,'') <> 'loss')
          or (breaker_type='win_rate_faible' and coalesce(b.win_rate,1) >= 0.40));
  end loop;

  return jsonb_build_object('fired', v_fired,
    'actifs', (select count(*) from public.oracle_circuit_breakers where auto_resolved=false));
end $function$



-- FUNCTION: compute_kelly_real
CREATE OR REPLACE FUNCTION public.compute_kelly_real()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_result jsonb := '{}'::jsonb;
  b record;
  v_r numeric; v_kraw numeric; v_kelly numeric;
begin
  for b in
    select archimage, win_rate, avg_win_pct, avg_loss_pct, alpaca_portfolio_value
    from public.oracle_brain_state
    where archimage in ('JU','SYL','GIL','CRYPTE_JU') and win_rate is not null
  loop
    v_r := case when coalesce(b.avg_loss_pct,0) > 0 then b.avg_win_pct / b.avg_loss_pct else null end;
    v_kraw := case when v_r is not null and v_r > 0 then b.win_rate - (1 - b.win_rate) / v_r else null end;
    v_kelly := case when v_kraw is null or v_kraw <= 0 then 0.005            -- pas d'edge mesurable : taille plancher
                    else least(round(0.25 * v_kraw, 4), 0.10) end;          -- quart de Kelly, plafond 10%
    update public.oracle_brain_state
      set kelly_fraction = v_kelly, kelly_last_computed = now()
      where archimage = b.archimage;
    insert into public.oracle_kelly_sizing
      (archimage, ticker, win_rate_used, avg_win_used, avg_loss_used, kelly_raw, kelly_fractional,
       recommended_notional, capped_notional, buying_power_at_time, applied)
    values
      (b.archimage, 'PORTFOLIO', b.win_rate, b.avg_win_pct, b.avg_loss_pct,
       round(coalesce(v_kraw,0),4), v_kelly,
       round(coalesce(b.alpaca_portfolio_value,0) * v_kelly, 0),
       least(round(coalesce(b.alpaca_portfolio_value,0) * v_kelly, 0), 190000),
       b.alpaca_portfolio_value, true);
    v_result := v_result || jsonb_build_object(b.archimage,
      jsonb_build_object('kelly_raw', round(coalesce(v_kraw,0),4), 'kelly_fraction', v_kelly,
        'statut', case when v_kraw is null or v_kraw <= 0 then 'PAS D EDGE - plancher 0.5%' else 'ACTIF' end));
  end loop;
  return v_result;
end $function$



-- FUNCTION: courbes_virtuelles
CREATE OR REPLACE FUNCTION public.courbes_virtuelles()
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
with c as (
  select date_trunc('day', exit_ts)::date as jour,
         sum(pnl_pct) as pnl_jour,
         count(*) as n,
         count(*) filter (where pnl_pct > 0) as gagnants
  from alchimiste_virtual_trades
  where is_open = false and exit_ts is not null
  group by 1
),
c2 as (
  select jour, round(pnl_jour::numeric,3) as pnl_jour,
         round(sum(pnl_jour) over (order by jour)::numeric,3) as cumul_pct,
         n, gagnants
  from c
),
m as (
  select date_trunc('day', exit_ts)::date as jour,
         sum(pnl_pct) as pnl_jour,
         count(*) as n,
         count(*) filter (where pnl_pct > 0) as gagnants
  from marees_virtual_trades
  where is_open = false and exit_ts is not null
  group by 1
),
m2 as (
  select jour, round(pnl_jour::numeric,3) as pnl_jour,
         round(sum(pnl_jour) over (order by jour)::numeric,3) as cumul_pct,
         n, gagnants
  from m
)
select jsonb_build_object(
  'genere_a', to_char(now(),'YYYY-MM-DD HH24:MI'),
  'crypte', jsonb_build_object(
     'nom', 'L''Alchimiste de la Crypte (virtuel)',
     'points', coalesce((select jsonb_agg(jsonb_build_object(
            'jour', to_char(jour,'YYYY-MM-DD'),
            'pnl_jour_pct', pnl_jour,
            'cumul_pct', cumul_pct,
            'trades', n,
            'gagnants', gagnants) order by jour) from c2), '[]'::jsonb),
     'total_clotures', (select count(*) from alchimiste_virtual_trades where is_open=false and exit_ts is not null),
     'ouverts', (select count(*) from alchimiste_virtual_trades where is_open),
     'cumul_final_pct', coalesce((select cumul_pct from c2 order by jour desc limit 1),0)
  ),
  'marees', jsonb_build_object(
     'nom', 'L''Archimage des Marées (virtuel)',
     'points', coalesce((select jsonb_agg(jsonb_build_object(
            'jour', to_char(jour,'YYYY-MM-DD'),
            'pnl_jour_pct', pnl_jour,
            'cumul_pct', cumul_pct,
            'trades', n,
            'gagnants', gagnants) order by jour) from m2), '[]'::jsonb),
     'total_clotures', (select count(*) from marees_virtual_trades where is_open=false and exit_ts is not null),
     'ouverts', (select count(*) from marees_virtual_trades where is_open),
     'cumul_final_pct', coalesce((select cumul_pct from m2 order by jour desc limit 1),0)
  )
);
$function$



-- FUNCTION: crypte_ju_evaluate_and_learn
CREATE OR REPLACE FUNCTION public.crypte_ju_evaluate_and_learn(p_fee_pct numeric DEFAULT 0.18, p_max_hold integer DEFAULT 240)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  p record; highs numeric[]; lows numeric[]; closes numeric[]; n int; k int; ret numeric;
  v_tp numeric; v_sl numeric; v_side text;
  v_wins int:=0; v_losses int:=0; v_evald int:=0; v_gw numeric:=0; v_gl numeric:=0;
  v_wr numeric; v_aw numeric; v_al numeric; v_bias text;
  v_expired int := 0;
  v_learn jsonb;
  v_reco text;
  v_tp_opt text; v_sl_opt text;
begin
  for p in
    select acp.id, acp.paire, acp.prix_ref, acp.proposed_at, acp.side, acp.resultat
    from public.alchimiste_crypte_propositions acp
    where acp.prix_ref is not null and acp.prix_ref>0 and lower(acp.side) in ('buy','sell')
      and acp.proposed_at >= (select min(ts) from public.price_history)
  loop
    select array_agg(ph.high order by ph.ts), array_agg(ph.low order by ph.ts), array_agg(ph.close order by ph.ts)
      into highs, lows, closes from public.price_history ph
      where ph.symbol=p.paire and ph.interval='1h' and ph.ts > p.proposed_at;
    n := coalesce(array_length(highs,1),0);
    if n=0 then continue; end if;
    v_side := lower(p.side);
    v_tp := coalesce((p.resultat->>'take_profit_pct')::numeric,7);
    v_sl := coalesce((p.resultat->>'stop_loss_pct')::numeric,4);
    ret := null; k:=1;
    if v_side='buy' then
      while k <= least(n,p_max_hold) loop
        if highs[k] >= p.prix_ref*(1+v_tp/100) then ret:=v_tp; exit; end if;
        if lows[k]  <= p.prix_ref*(1-v_sl/100) then ret:=-v_sl; exit; end if;
        k:=k+1;
      end loop;
      if ret is null then ret := (closes[least(n,p_max_hold)]/p.prix_ref-1)*100; end if;
    else
      while k <= least(n,p_max_hold) loop
        if lows[k]  <= p.prix_ref*(1-v_sl/100) then ret:=v_sl; exit; end if;
        if highs[k] >= p.prix_ref*(1+v_tp/100) then ret:=-v_tp; exit; end if;
        k:=k+1;
      end loop;
      if ret is null then ret := -(closes[least(n,p_max_hold)]/p.prix_ref-1)*100; end if;
    end if;
    ret := ret - p_fee_pct;
    v_evald:=v_evald+1;
    if ret>0 then v_wins:=v_wins+1; v_gw:=v_gw+ret; else v_losses:=v_losses+1; v_gl:=v_gl+abs(ret); end if;

    update public.alchimiste_crypte_propositions
      set resultat = coalesce(resultat,'{}'::jsonb) || jsonb_build_object(
        'paper_eval', jsonb_build_object(
          'ret_pct', round(ret,2), 'win', ret>0, 'hold_hours', least(n,p_max_hold),
          'tp_pct', v_tp, 'sl_pct', v_sl, 'evaluated_at', now()))
      where id = p.id;
  end loop;

  update public.alchimiste_crypte_propositions
    set statut = 'expiree'
    where statut = 'proposee' and expire_at is not null and expire_at < now();
  get diagnostics v_expired = row_count;

  if v_evald=0 then
    return jsonb_build_object('evaluated',0,'note','aucune proposition evaluable pour le moment');
  end if;
  v_wr := round(v_wins::numeric/v_evald,3);
  v_aw := round(case when v_wins>0 then v_gw/v_wins else 0 end,2);
  v_al := round(case when v_losses>0 then v_gl/v_losses else 0 end,2);

  select value into v_tp_opt from public.ju_crypte_config where key='tp_optimal_backtest';
  select value into v_sl_opt from public.ju_crypte_config where key='sl_optimal_backtest';
  v_reco := 'Calibrage optimal (backtest en grille sur tout l historique, valide par decoupage temporel): TP '
         || coalesce(v_tp_opt,'5') || '% / SL ' || coalesce(v_sl_opt,'4')
         || '%. Laisser courir les gains: en crypto volatile un SL serre se fait toucher trop souvent.';
  v_bias := 'Auto (paper, achats+ventes): '||v_wins||'W/'||v_losses||'L, WR '||round(v_wr*100,1)||'%, gain moy '||v_aw||'% vs perte moy '||v_al||'%. '||v_reco;

  select coalesce(learnings,'[]'::jsonb) into v_learn from public.oracle_brain_state where archimage='CRYPTE_JU';
  v_learn := v_learn || jsonb_build_array(jsonb_build_object(
    'at', now(), 'evaluated', v_evald, 'wr', v_wr, 'avg_win_pct', v_aw, 'avg_loss_pct', v_al, 'reco', v_reco));
  if jsonb_array_length(v_learn) > 30 then
    select jsonb_agg(e) into v_learn from (
      select e from jsonb_array_elements(v_learn) e offset jsonb_array_length(v_learn) - 30) sub;
  end if;

  update public.oracle_brain_state
    set total_runs=v_evald, wins=v_wins, losses=v_losses, win_rate=v_wr, avg_win_pct=v_aw, avg_loss_pct=v_al,
        current_bias=v_bias, learnings=v_learn, last_run_at=now(), updated_at=now()
    where archimage='CRYPTE_JU';
  return jsonb_build_object('evaluated',v_evald,'wins',v_wins,'losses',v_losses,'win_rate',v_wr,
    'avg_win_pct',v_aw,'avg_loss_pct',v_al,'expired',v_expired,'bias',v_bias);
end;
$function$



-- FUNCTION: crypte_virtual_resume
CREATE OR REPLACE FUNCTION public.crypte_virtual_resume()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_runs int; v_wr numeric; v_kelly numeric;
  v_clos int; v_vwins int; v_open int; v_sum numeric;
  v_props text; v_resume text;
BEGIN
  SELECT total_runs, win_rate, kelly_fraction
    INTO v_runs, v_wr, v_kelly
  FROM oracle_brain_state WHERE archimage='CRYPTE_JU';

  SELECT count(*) FILTER (WHERE exit_reason IN ('TP','SL','MARCHE')),
         count(*) FILTER (WHERE exit_reason IN ('TP','SL','MARCHE') AND pnl_pct>0),
         count(*) FILTER (WHERE is_open OR exit_reason='OUVERT'),
         round(coalesce(sum(pnl_pct) FILTER (WHERE exit_reason IN ('TP','SL','MARCHE')),0)::numeric,2)
    INTO v_clos, v_vwins, v_open, v_sum
  FROM alchimiste_virtual_trades;

  SELECT string_agg('• '||paire||'  '||CASE WHEN lower(side)='buy' THEN 'ACHAT ▲' ELSE 'VENTE ▼' END
                    ||'  conf '||trim(to_char(coalesce(confidence,0),'FM990.9')), E'\n')
    INTO v_props
  FROM (SELECT paire, side, confidence FROM alchimiste_crypte_propositions
        ORDER BY proposed_at DESC LIMIT 5) s;

  v_resume := '🔮 **L''Alchimiste de la Crypte — VIRTUEL (apprentissage)**'
    || E'\n' || '📊 ' || coalesce(v_runs,0) || ' runs · ' || round(coalesce(v_wr,0)*100)::int || '% de réussite · Kelly ' || trim(to_char(coalesce(v_kelly,0),'FM990.999'))
    || E'\n' || '🧪 Trades virtuels : ' || coalesce(v_clos,0) || ' clôturés (' || coalesce(v_vwins,0) || ' ✅) · PnL cumulé ' || coalesce(v_sum,0) || '% · ' || coalesce(v_open,0) || ' ouverts'
    || coalesce(E'\n' || '🔭 Dernières propositions :' || E'\n' || v_props, E'\n_Aucune proposition récente._');

  RETURN jsonb_build_object('resume', v_resume, 'runs', coalesce(v_runs,0), 'win_rate', coalesce(v_wr,0));
END;
$function$



-- FUNCTION: dashboard_snapshot
CREATE OR REPLACE FUNCTION public.dashboard_snapshot()
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
select jsonb_build_object(
  'archimages', (select jsonb_agg(row_to_json(m)) from public.ju_archimage_metrics m),
  'cerveau', (select jsonb_agg(jsonb_build_object(
      'archimage',archimage,'win_rate',win_rate,'total_runs',total_runs,'wins',wins,'losses',losses,
      'poids',synthesis_weight,'kelly',kelly_fraction,'maj',to_char(updated_at,'MM-DD HH24:MI'),
      'doctrine',left(current_bias,220),
      'avg_win_pct',avg_win_pct,'avg_loss_pct',avg_loss_pct,
      'cumulative_pnl',cumulative_pnl,
      'current_drawdown', coalesce(alpaca_drawdown_from_peak, current_drawdown),
      'max_drawdown',max_drawdown,
      'consecutive_wins',consecutive_wins,'consecutive_losses',consecutive_losses,'current_streak_type',current_streak_type,
      'risk_appetite',risk_appetite,
      'alpaca_portfolio_value',alpaca_portfolio_value,'alpaca_buying_power',alpaca_buying_power,'baseline_equity',baseline_equity
    ) order by synthesis_weight desc) from public.oracle_brain_state where archimage!='cerveau'),
  'meta_cerveau', (select jsonb_build_object('doctrine',left(current_bias,220),'maj',to_char(updated_at,'MM-DD HH24:MI')) from public.oracle_brain_state where archimage='cerveau'),

  'sages', (select jsonb_agg(row_to_json(s)) from public.evaluate_sages(24,0.5) s),
  'runs', (select jsonb_agg(x) from (select to_char(run_at,'MM-DD HH24:MI') as quand, market_phase, status, orders_count from public.oracle_college_runs order by run_at desc limit 8) x),
  'portefeuille', (select to_jsonb(p) from public.revolut_portfolio_daily p order by id desc limit 1),
  'propositions', (select jsonb_agg(x) from (select paire, side, prix_ref, montant, statut, to_char(proposed_at,'MM-DD HH24:MI') as quand from public.alchimiste_crypte_propositions order by id desc limit 12) x),

  'positions_vivantes', (
    select jsonb_agg(x) from (
      select archimage, count(*) as nb,
        round(sum(unrealized_pl)::numeric,2) as pl_latent_total,
        round(sum(market_value)::numeric,2) as valeur_marche_totale,
        count(*) filter (where is_stale) as nb_perimees,
        max(consecutive_runs_held) as max_runs_detenu,
        count(*) filter (where abs(market_value) < 50) as nb_poussiere
      from public.oracle_positions_live group by archimage
    ) x
  ),
  'positions_detail', (
    select jsonb_agg(x) from (
      select archimage, ticker, side, qty, avg_entry_price, current_price,
        unrealized_pl, unrealized_pl_pct, consecutive_runs_held as runs_detenu, is_stale,
        (abs(market_value) < 50) as poussiere
      from public.oracle_positions_live order by archimage, abs(market_value) desc
    ) x
  ),
  'ordres_recents', (
    select jsonb_agg(x) from (
      select archimage, symbol, side, coalesce(executed_notional, notional_validated, notional) as montant,
        broker_status, rejected_reason, asset_class, to_char(created_at,'MM-DD HH24:MI') as quand
      from (select *, row_number() over (partition by archimage order by created_at desc) rn
        from public.oracle_college_orders where archimage in ('GIL','JU','SYL')) t where rn<=10
      order by archimage, created_at desc
    ) x
  ),
  'debug_execution', (
    select jsonb_agg(x) from (
      select distinct on (archimage) archimage, accepted, rejected, skipped,
        to_char(created_at,'MM-DD HH24:MI') as quand,
        (select jsonb_agg(d->>'reason') from jsonb_array_elements(payload->'skipped_detail') d) as raisons_skip
      from public.oracle_exec_debug order by archimage, created_at desc
    ) x
  ),

  'sante_flux', (
    select jsonb_build_object(
      'quand', to_char(run_at,'MM-DD HH24:MI'),
      'data_completeness', data_completeness,
      'circuit_breaker_fired', circuit_breaker_fired, 'circuit_breaker_reason', circuit_breaker_reason,
      'risk_override', risk_override, 'risk_override_reason', risk_override_reason
    ) from public.oracle_college_runs order by run_at desc limit 1
  ),

  'performance_historique', (
    select jsonb_agg(x) from (
      select archimage, to_char(date_trunc('day',evaluated_at),'YYYY-MM-DD') as jour,
        count(*) as evals,
        round((avg(case when win then 1.0 else 0 end)*100)::numeric,1) as wr_jour
      from public.oracle_performance group by archimage, date_trunc('day',evaluated_at)
      order by archimage, jour
    ) x
  ),
  'performance_synthese', (
    select jsonb_agg(x) from (
      select p.archimage, count(*) as evals_total,
        round((avg(case when p.win then 1.0 else 0 end)*100)::numeric,1) as wr_global,
        b.cumulative_pnl as pnl_cumule_fiable,
        min(p.evaluated_at) as depuis, max(p.evaluated_at) as jusqua
      from public.oracle_performance p
      join public.oracle_brain_state b using (archimage)
      group by p.archimage, b.cumulative_pnl
    ) x
  ),

  'audit', jsonb_build_object(
    'runs_total', (select count(*) from public.oracle_college_runs),
    'runs_avec_flux_ok', (select count(*) from public.oracle_college_runs where data_completeness>=60),
    'propositions_total', (select count(*) from public.alchimiste_crypte_propositions),
    'propositions_validees', (select count(*) from public.alchimiste_crypte_propositions where statut not in ('proposee','prix_indispo','expiree')),
    'cryptos_qty_perdue', (select count(*) from jsonb_array_elements(coalesce((select detail from public.revolut_portfolio_daily order by id desc limit 1),'[]'::jsonb)) d where (d->>'qty')::numeric=0 and (d->>'valeur_usd')::numeric>0),
    'ju_doctrine_actuelle', (select left(current_bias,220) from public.oracle_brain_state where archimage='JU')
  ),

  'stats', jsonb_build_object(
     'ordres_total',(select count(*) from public.oracle_college_orders),
     'runs_total',(select count(*) from public.oracle_college_runs),
     'propositions_total',(select count(*) from public.alchimiste_crypte_propositions),
     'sages_total',(select count(*) from public.oracle_sages_report),
     'bougies',(select count(*) from public.price_history),
     'kill_switch',(select value from public.ju_crypte_config where key='kill_switch'),
     'crons',(select jsonb_agg(jsonb_build_object('nom',jobname,'actif',active)) from cron.job),
     'minutes_depuis_dernier_run', (select round(extract(epoch from (now()-max(run_at)))/60) from public.oracle_college_runs),
     'minutes_depuis_derniere_proposition', (select round(extract(epoch from (now()-max(proposed_at)))/60) from public.alchimiste_crypte_propositions),
     'minutes_depuis_maj_cerveau', (select round(extract(epoch from (now()-max(updated_at)))/60) from public.oracle_brain_state where archimage!='CRYPTE_JU'),
     'minutes_avant_1er_score_sages', (select greatest(0, round(24*60 - extract(epoch from (now()-min(created_at)))/60)) from public.oracle_sages_report),
     'premier_run_historique', (select to_char(min(run_at),'YYYY-MM-DD') from public.oracle_college_runs)
  ),
  'genere_a', to_char(now(),'YYYY-MM-DD HH24:MI')
);
$function$



-- FUNCTION: equity_series
CREATE OR REPLACE FUNCTION public.equity_series()
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
select jsonb_build_object(
  'archimages', (
    select jsonb_object_agg(archimage, serie) from (
      select archimage, jsonb_agg(jsonb_build_object('d', jour, 'pct', pct) order by jour) serie
      from (
        select archimage, evaluated_at::date as jour, round((max(actual_pnl) / 10000)::numeric, 2) as pct
        from public.oracle_performance
        where archimage in ('JU','SYL','GIL') and actual_pnl is not null
        group by archimage, evaluated_at::date
      ) x group by archimage
    ) y
  ),
  'spy', (
    with d as (
      select ts::date as jour, (array_agg(close order by ts desc))[1] as c
      from public.price_history
      where symbol = 'SPY' and interval = '1h' and ts >= '2026-06-05'
      group by ts::date
    ), base as (select c from d order by jour limit 1)
    select jsonb_agg(jsonb_build_object('d', d.jour, 'pct', round((d.c / base.c - 1) * 100, 2)) order by d.jour)
    from d, base
  )
);
$function$



-- FUNCTION: evaluate_archimages_win_loss_pct
CREATE OR REPLACE FUNCTION public.evaluate_archimages_win_loss_pct()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_result jsonb := '{}'::jsonb;
  r record;
begin
  -- Pour GIL/JU/SYL : le delta de pnl RUN A RUN (pas le cumulé), exprimé en % du capital de départ (~1M),
  -- pour être dans la même unité que l'Alchimiste (avg_win_pct/avg_loss_pct en %).
  -- On réutilise le flag "win" déjà posé par update-brain (pnl > pnl du run précédent) pour rester cohérent.
  for r in
    with deltas as (
      select p.archimage, p.win,
        (p.actual_pnl - lag(p.actual_pnl) over (partition by p.archimage order by p.evaluated_at)) as delta_usd,
        b.baseline_equity
      from public.oracle_performance p
      join public.oracle_brain_state b using (archimage)
      where p.archimage in ('GIL','JU','SYL')
    ),
    pct as (
      select archimage, win,
        case when baseline_equity>0 then (delta_usd/baseline_equity)*100 else null end as delta_pct
      from deltas where delta_usd is not null
    ),
    agg as (
      select archimage,
        count(*) filter (where win) as wins,
        count(*) filter (where not win) as losses,
        round(avg(delta_pct) filter (where win and delta_pct>0)::numeric,3) as avg_win_pct,
        round(avg(abs(delta_pct)) filter (where not win and delta_pct<0)::numeric,3) as avg_loss_pct
      from pct group by archimage
    )
    select * from agg
  loop
    update public.oracle_brain_state
      set avg_win_pct = coalesce(r.avg_win_pct,0), avg_loss_pct = coalesce(r.avg_loss_pct,0)
      where archimage = r.archimage;
    v_result := v_result || jsonb_build_object(r.archimage, jsonb_build_object(
      'wins', r.wins, 'losses', r.losses, 'avg_win_pct', r.avg_win_pct, 'avg_loss_pct', r.avg_loss_pct));
  end loop;
  return v_result;
end;
$function$



-- FUNCTION: evaluate_directional_accuracy
CREATE OR REPLACE FUNCTION public.evaluate_directional_accuracy(p_hold_hours integer DEFAULT 24, p_seuil numeric DEFAULT 0.3)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_result jsonb := '{}'::jsonb;
  r record;
begin
  for r in
    with runs_net as (
      select o.archimage, o.run_id, min(rr.run_at) run_at,
        sum(case when lower(o.side)='buy' then coalesce(o.executed_notional, o.notional, 0)
                 else -coalesce(o.executed_notional, o.notional, 0) end) as net
      from public.oracle_college_orders o
      join public.oracle_college_runs rr on rr.run_id = o.run_id
      where o.broker_status in ('filled','partially_filled') and o.archimage in ('JU','SYL','GIL')
      group by o.archimage, o.run_id
      having abs(sum(case when lower(o.side)='buy' then coalesce(o.executed_notional, o.notional, 0)
                          else -coalesce(o.executed_notional, o.notional, 0) end)) > 100
    ),
    scored as (
      select rn.archimage, rn.net,
        ((select ph.close from public.price_history ph
           where ph.symbol = case when rn.archimage='GIL' then 'BTC-USD' else 'SPY' end
             and ph.interval='1h' and ph.ts >= rn.run_at + (p_hold_hours||' hours')::interval
           order by ph.ts asc limit 1)
        / nullif((select ph.close from public.price_history ph
           where ph.symbol = case when rn.archimage='GIL' then 'BTC-USD' else 'SPY' end
             and ph.interval='1h' and ph.ts >= rn.run_at
           order by ph.ts asc limit 1), 0) - 1) * 100 as ret_pct
      from runs_net rn
    ),
    agg as (
      select archimage,
        count(*) filter (where ret_pct is not null and abs(ret_pct) > p_seuil) as evalue,
        count(*) filter (where ret_pct is not null and abs(ret_pct) > p_seuil
          and ((net > 0 and ret_pct > 0) or (net < 0 and ret_pct < 0))) as corrects
      from scored group by archimage
    )
    select * from agg
  loop
    update public.oracle_brain_state
      set directional_accuracy = case when r.evalue > 0 then round(r.corrects::numeric / r.evalue, 3) else 0 end
      where archimage = r.archimage;
    v_result := v_result || jsonb_build_object(r.archimage,
      jsonb_build_object('evalue', r.evalue, 'corrects', r.corrects,
        'accuracy', case when r.evalue > 0 then round(r.corrects::numeric / r.evalue, 3) end));
  end loop;
  return v_result;
end $function$



-- FUNCTION: evaluate_sages
CREATE OR REPLACE FUNCTION public.evaluate_sages(p_hold_hours integer DEFAULT 24, p_seuil numeric DEFAULT 0.5)
 RETURNS TABLE(sage text, evalue integer, corrects integer, taux_reussite numeric, dernier_signal text, directionnel boolean)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
with base as (
  select sage_name, created_at,
    case sage_name
      when 'Macro'    then upper(coalesce(nullif(sage_output->>'recommended_bias',''), sage_output->>'spy_trend'))
      when 'Technique'then upper(coalesce(nullif(sage_output->>'spy_momentum',''), sage_output->>'wyckoff_phase'))
      when 'Flash'    then upper(sage_output->>'flash_sentiment')
      when 'Risque'   then upper(sage_output->>'risk_level')
      when 'Memoire'  then upper(left(coalesce(sage_output->>'correction_directive',''),40))
    end as signal
  from public.oracle_sages_report
),
dir as (
  select *,
    case when signal in ('BULLISH','UP','ACCUMULATION') then 1
         when signal in ('BEARISH','DOWN','DISTRIBUTION') then -1
         when signal in ('NEUTRAL','FLAT') then 0 else null end as d,
    sage_name in ('Macro','Technique','Flash') as directionnel,
    'SPY'::text as symbole_ref
  from base
),
scored as (
  select sage_name, created_at, d, directionnel, signal,
    case when sage_name in ('Macro','Technique','Flash','Risque') then
      (select close from public.price_history where symbol=dir.symbole_ref and interval='1h' and ts >= dir.created_at + (p_hold_hours||' hours')::interval order by ts asc limit 1)
      / nullif((select close from public.price_history where symbol=dir.symbole_ref and interval='1h' and ts >= dir.created_at order by ts asc limit 1),0)
    end as ratio
  from dir
),
risque as (
  select signal, abs((ratio-1)*100) as amove
  from scored where sage_name='Risque' and ratio is not null
),
risque_scored as (
  select count(*)::int as evalue,
    count(*) filter (where
      (signal='LOW' and amove < 1.0) or
      (signal='MEDIUM' and amove >= 0.3 and amove < 2.0) or
      (signal='HIGH' and amove >= 0.8) or
      (signal='EXTREME' and amove >= 1.5))::int as corrects
  from risque
),
memoire as (
  select b.created_at,
    (select count(*) filter (where p.win) from public.oracle_performance p
      where p.archimage in ('JU','SYL','GIL')
        and p.evaluated_at > b.created_at and p.evaluated_at <= b.created_at + interval '4 hours') as wins3,
    (select count(*) from public.oracle_performance p
      where p.archimage in ('JU','SYL','GIL')
        and p.evaluated_at > b.created_at and p.evaluated_at <= b.created_at + interval '4 hours') as n3
  from base b where b.sage_name='Memoire'
),
memoire_scored as (
  select count(*) filter (where n3 >= 3)::int as evalue,
         count(*) filter (where n3 >= 3 and wins3 >= 2)::int as corrects
  from memoire
),
agg as (
  select s.sage_name,
    count(*) filter (where s.directionnel and s.ratio is not null)::int as evalue,
    count(*) filter (where s.directionnel and s.ratio is not null and (
       (s.d=1 and (s.ratio-1)*100 > p_seuil) or (s.d=-1 and (s.ratio-1)*100 < -p_seuil) or (s.d=0 and abs((s.ratio-1)*100) <= p_seuil)))::int as corrects,
    true as directionnel
  from scored s where s.sage_name in ('Macro','Technique','Flash') group by s.sage_name
  union all select 'Risque', evalue, corrects, false from risque_scored
  union all select 'Memoire', evalue, corrects, false from memoire_scored
)
select a.sage_name::text, a.evalue, a.corrects,
  case when a.evalue>0 then round(a.corrects*100.0/a.evalue,1) end,
  (select b.signal from base b where b.sage_name=a.sage_name order by b.created_at desc limit 1),
  a.directionnel
from agg a;
$function$



-- FUNCTION: flash_route
CREATE OR REPLACE FUNCTION public.flash_route(p_ticker text, p_type text)
 RETURNS text[]
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  t text := upper(btrim(coalesce(p_ticker,'')));
  ty text := lower(coalesce(p_type,''));
  base text;
  assigned text;
BEGIN
  -- Macro / regime -> tous les archimages (contexte universel)
  IF ty LIKE '%macro%' OR ty LIKE '%rate%' OR ty LIKE '%fed%' OR ty LIKE '%geopol%'
     OR t IN ('','MARKET','MACRO','GLOBAL','SPY','QQQ','VIX','DXY','US10Y','FED','ECB') THEN
    RETURN ARRAY['SYL','JU','GIL','CRYPTE_JU','MAREES'];
  END IF;

  -- Override explicite defini par l'utilisateur dans asset_universe
  SELECT assigned_archimage INTO assigned FROM public.asset_universe
   WHERE upper(ticker)=t AND assigned_archimage IS NOT NULL LIMIT 1;
  IF assigned IS NOT NULL THEN RETURN ARRAY[assigned]; END IF;

  t := replace(t,'/','-');
  base := split_part(t,'-',1);

  -- Forex majors -> MAREES
  IF t ~ '^(EUR|USD|GBP|JPY|CHF|AUD|NZD|CAD)-?(EUR|USD|GBP|JPY|CHF|AUD|NZD|CAD)$' THEN
    RETURN ARRAY['MAREES'];
  END IF;

  -- Crypto (present dans l'univers Revolut, ou major connu) -> GIL + CRYPTE_JU
  IF EXISTS (SELECT 1 FROM public.revolut_univers_complet
             WHERE upper(paire)=t OR upper(split_part(paire,'-',1))=base)
     OR base IN ('BTC','ETH','SOL','XRP','ADA','DOGE','DOT','AVAX','LINK','MATIC',
                 'LTC','BCH','BNB','TRX','SHIB','TON','NEAR','ATOM','UNI','XLM','ARB','OP') THEN
    RETURN ARRAY['GIL','CRYPTE_JU'];
  END IF;

  -- Defaut : action US -> JU
  RETURN ARRAY['JU'];
END;
$function$



-- FUNCTION: generate_daily_journal
CREATE OR REPLACE FUNCTION public.generate_daily_journal(creneau text DEFAULT 'auto'::text)
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  cren text; h int;
  r_now numeric; r_prev numeric; r_cash numeric; r_stake numeric; r_liq numeric; r_lignes int;
  var_abs numeric; var_pct numeric; r_peak numeric; r_dd numeric;
  syl_r numeric; syl_dd numeric; syl_wr numeric; syl_ddc numeric;
  gil_r numeric; gil_dd numeric; gil_wr numeric; gil_ddc numeric;
  ju_r numeric; ju_dd numeric; ju_wr numeric; ju_ddc numeric;
  regime text; meilleur text; pire text; align_txt text;
  alc_brut numeric; alc_net numeric; alc_trades int; alc_wr numeric; alc_pos int; alc_jour numeric; alc_txt text;
  mar_trades int; mar_txt text;
  destake_txt text; sante_txt text;
  txt text;
begin
  h := extract(hour from now())::int;
  cren := case when creneau<>'auto' then creneau when h<10 then 'matin' when h<16 then 'midi' else 'soir' end;
  if exists (select 1 from oracle_journal where jour=current_date and resume like '%('||cren||')%' and created_at>now()-interval '6 hours') then
    return 'skip: '||cren||' deja present';
  end if;

  select total_usd,cash_usd,stake_usd, jsonb_array_length(detail)
    into r_now,r_cash,r_stake,r_lignes from revolut_portfolio_daily order by snapshot_at desc limit 1;
  select total_usd into r_prev from revolut_portfolio_daily order by snapshot_at desc offset 1 limit 1;
  select max(total_usd) into r_peak from revolut_portfolio_daily;
  r_liq := round(coalesce(r_now,0)-coalesce(r_cash,0)-coalesce(r_stake,0),2);
  var_abs := round(coalesce(r_now,0)-coalesce(r_prev,0),2);
  var_pct := case when coalesce(r_prev,0)<>0 then round(var_abs/r_prev*100,2) end;
  r_dd := case when coalesce(r_peak,0)>0 then round((r_peak-r_now)/r_peak*100,2) end;

  select rendement_pct,drawdown_max_pct,reussite_pct into syl_r,syl_dd,syl_wr from v_perf_resume where trader='SYL';
  select rendement_pct,drawdown_max_pct,reussite_pct into gil_r,gil_dd,gil_wr from v_perf_resume where trader='GIL';
  select rendement_pct,drawdown_max_pct,reussite_pct into ju_r,ju_dd,ju_wr from v_perf_resume where trader='JU';
  select round(current_drawdown*100,2) into syl_ddc from oracle_brain_state where archimage='SYL';
  select round(current_drawdown*100,2) into gil_ddc from oracle_brain_state where archimage='GIL';
  select round(current_drawdown*100,2) into ju_ddc from oracle_brain_state where archimage='JU';

  select contexte_mondial->>'regime',contexte_mondial->>'meilleur',contexte_mondial->>'pire'
    into regime,meilleur,pire from v_world_context limit 1;
  align_txt := case lower(coalesce(regime,''))
    when 'risk_on' then 'sages actions coherents avec le risk-on ; le segment crypto est souvent a contre-courant.'
    when 'risk_off' then 'prudence : reduire l''exposition, privilegier cash/defensif.'
    else 'regime neutre : pas de biais directionnel fort.' end;

  select cumul_pct,wr_pct,trades_clos,positions_ouvertes into alc_brut,alc_wr,alc_trades,alc_pos from v_alc_virtuel_resume limit 1;
  select case when count(*)=0 then null else round((exp(sum(ln(greatest(1+(ret_pct-0.18)/100.0,0.0001))))-1)*100,2) end
    into alc_net from v_alc_virtuel_jour;
  select ret_pct into alc_jour from v_alc_virtuel_jour order by jour desc limit 1;
  if coalesce(alc_trades,0)=0 then
    alc_txt := 'compteur a zero (apprentissage reinitialise) — brut/net incalculables, reprise des les premiers trades clos.';
  else
    alc_txt := 'brut '||coalesce(alc_brut::text,'—')||' %, net de frais (0,18%/trade) '||coalesce(alc_net::text,'—')||' %, PnL du jour '||coalesce(alc_jour::text,'—')||' %, WR '||coalesce(alc_wr::text,'—')||' %, '||alc_trades||' trades clos, '||coalesce(alc_pos::text,'0')||' positions ouvertes.';
  end if;

  select count(*) into mar_trades from marees_virtual_trades;
  if coalesce(mar_trades,0)=0 then mar_txt:='forex virtuel remis a zero — aucun trade clos pour l''instant.';
  else mar_txt:=mar_trades||' trades virtuels enregistres.'; end if;

  select string_agg(
    devise||' : investi '||coalesce(invest_usd::text,'n/d')||'$, vaut '||valeur_live::text||'$'||
    case when pnl_pct is not null then ' (P&L '||pnl_pct::text||'%)' else '' end||
    ' | staking +'||trim(to_char(gain_staking_qty,'FM990.00000000'))||' '||devise||' (APY '||coalesce(apy_pct::text,'?')||'%), deblocage '||coalesce(unbonding_jours,'?')||'j, cout de-staking ~'||coalesce(cout_destaking_usd::text,'?')||'$',
    E'\n   • ' order by pnl_pct nulls last)
  into destake_txt from v_staking_point;

  select string_agg(source||' (fige depuis '||round(age_h/24.0,1)||'j)', ' ; ' order by age_h desc)
    into sante_txt from v_data_health where statut='FIGE';

  txt := 'AETHER — Point du '||to_char(current_date,'DD/MM/YYYY')||' ('||cren||').'||E'\n\n'||
    '1) REVOLUT X (priorite) : '||coalesce(r_now::text,'?')||' $ (cash '||coalesce(r_cash::text,'?')||' $, liquide '||coalesce(r_liq::text,'?')||' $, stake '||coalesce(r_stake::text,'?')||' $, '||coalesce(r_lignes::text,'?')||' lignes). Variation vs snapshot precedent : '||coalesce(var_abs::text,'?')||' $ ('||coalesce(var_pct::text,'?')||' %). Drawdown courant : '||coalesce(r_dd::text,'—')||' % (depuis le pic).'||E'\n\n'||
    '2) SAGES ACTIONS (simulation) : SYL '||coalesce(syl_r::text,'—')||' % (DD courant '||coalesce(syl_ddc::text,'—')||' %, DD max '||coalesce(syl_dd::text,'—')||' %, WR '||coalesce(syl_wr::text,'—')||' %), GIL '||coalesce(gil_r::text,'—')||' % (DD courant '||coalesce(gil_ddc::text,'—')||' %, DD max '||coalesce(gil_dd::text,'—')||' %, WR '||coalesce(gil_wr::text,'—')||' %), JU '||coalesce(ju_r::text,'—')||' % (DD courant '||coalesce(ju_ddc::text,'—')||' %, DD max '||coalesce(ju_dd::text,'—')||' %, WR '||coalesce(ju_wr::text,'—')||' %).'||E'\n\n'||
    '3) REGIME MONDIAL : '||coalesce(upper(regime),'?')||'. Meilleur 7j : '||coalesce(meilleur,'?')||' ; pire : '||coalesce(pire,'?')||'. Alignement : '||align_txt||E'\n\n'||
    '4) ALCHIMISTE VIRTUEL (crypto Revolut X) : '||alc_txt||E'\n\n'||
    '5) MAREES (forex) : '||mar_txt||E'\n\n'||
    '6) DE-STAKING (action manuelle, reco) :'||E'\n   • '||coalesce(destake_txt,'aucune ligne en stake')||E'\n   Regle : le de-staking coute surtout le delai (Nj sans pouvoir vendre) ; le rendement perdu est minime. Garder de preference les APY eleves (ATOM 21%, TON 17.67%) ; liberer les autres si un trade le justifie.'||E'\n\n'||
    '7) SANTE DES DONNEES : '||coalesce('⚠ FIGE -> '||sante_txt, 'toutes les sources a jour.')||E'\n\n'||
    'Synthese : Revolut X '||coalesce(r_now::text,'?')||' $ ('||coalesce(var_pct::text,'?')||' %, DD '||coalesce(r_dd::text,'—')||' %) ; sages SYL/GIL/JU '||coalesce(syl_r::text,'—')||'/'||coalesce(gil_r::text,'—')||'/'||coalesce(ju_r::text,'—')||' % ; Alchimiste '||case when coalesce(alc_trades,0)=0 then 'a zero' else 'net '||coalesce(alc_net::text,'—')||' %' end||'.';

  insert into oracle_journal (jour,resume,created_at,problemes_traites) values (current_date,txt,now(),0);
  return 'ok: '||cren;
end;
$function$



-- FUNCTION: get_oracle_context
CREATE OR REPLACE FUNCTION public.get_oracle_context()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
  RETURN jsonb_build_object(

    'brain_states', (
      SELECT jsonb_object_agg(archimage, jsonb_build_object(
        'win_rate',              win_rate,
        'synthesis_weight',      synthesis_weight,
        'current_bias',          current_bias,
        'risk_appetite',         risk_appetite,
        'total_runs',            total_runs,
        'wins',                  wins,
        'losses',                losses,
        'cumulative_pnl',        ROUND(cumulative_pnl::numeric, 2),
        'current_drawdown',      ROUND(current_drawdown::numeric, 4),
        'kelly_fraction',        ROUND(kelly_fraction::numeric, 3),
        'kelly_last_computed',   kelly_last_computed,
        'avg_win_pct',           avg_win_pct,
        'avg_loss_pct',          avg_loss_pct,
        'consecutive_wins',      consecutive_wins,
        'consecutive_losses',    consecutive_losses,
        'assigned_universe',     assigned_universe,
        'preferred_tickers',     preferred_tickers,
        'forbidden_tickers',     forbidden_tickers,
        'sector_expertise',      sector_expertise,
        -- 20/08 : memoire COMPLETE depuis brain_lessons (append-only) au lieu des 30 entrees
        -- glissantes de oracle_brain_state, que update-brain rogne a chaque run. Format allege
        -- {run, bias} : seul 'bias' est lu par les prompts, et CTX alimente les 7 modules --
        -- livrer run/at/pnl/dd/eval faisait passer CTX a 167 511 caracteres (~42 000 tokens
        -- injectes SEPT fois). Avec l'allegement : 63 lecons par agent pour un CTX de 93 183.
        -- COALESCE : MAREES, CRYPTE_JU et cerveau, absents de brain_lessons, sont inchanges.
        'learnings',             COALESCE((SELECT jsonb_agg(jsonb_build_object('run', bl.run_id, 'bias', translate(bl.bias, E'\\"|' || chr(10) || chr(13), '     ')) ORDER BY bl.at) FROM public.brain_lessons bl WHERE bl.archimage = oracle_brain_state.archimage AND bl.bias IS NOT NULL AND bl.bias <> ''), learnings),
        -- Historique COMPLET des runs perdants (kind='mistake', analyse ecrite par l'agent
        -- lui-meme dans 'eval'). Livre a Make depuis toujours, lu par AUCUN prompt : le
        -- branchement cote Make (champ MES_ERREURS sur 301/303/305) reste a faire via Maia.
        'mistakes_history',      COALESCE((SELECT jsonb_agg(jsonb_build_object('run', bl.run_id, 'erreur', translate(bl.eval, E'\\"|' || chr(10) || chr(13), '     ')) ORDER BY bl.at) FROM public.brain_lessons bl WHERE bl.archimage = oracle_brain_state.archimage AND bl.kind = 'mistake' AND COALESCE(bl.eval,'') <> ''), mistakes_history),
        'last_decision',         last_decision,
        'alpaca_buying_power',   ROUND(alpaca_buying_power::numeric, 2),
        'alpaca_portfolio_value',ROUND(alpaca_portfolio_value::numeric, 2),
        'alpaca_drawdown',       ROUND(alpaca_drawdown_from_peak::numeric, 4),
        'latest_web_catalysts',  COALESCE(latest_web_catalysts, '[]'::jsonb),
        'catalyst_updated_at',   catalyst_updated_at
      ))
      FROM oracle_brain_state
    ),

    'last_10_runs', (
      SELECT COALESCE(jsonb_agg(jsonb_build_object(
        'run_id',              run_id,
        'run_at',              run_at,
        'market_phase',        market_phase,
        'consensus_level',     consensus_level,
        'orders_count',        orders_count,
        'orders_executed',     orders_executed,
        'orders_buy',          orders_buy,
        'orders_sell',         orders_sell,
        'overlap_score',       overlap_score,
        'circuit_breaker',     circuit_breaker_fired,
        'visionary_score',     visionary_score,
        'syl_web_catalysts',   syl_web_catalysts
      ) ORDER BY run_at DESC), '[]'::jsonb)
      FROM (SELECT * FROM oracle_college_runs ORDER BY run_at DESC LIMIT 10) sub
    ),

    'flash_intel_latest', (
      SELECT COALESCE(jsonb_agg(jsonb_build_object(
        'ticker',      ticker,
        'direction',   direction,
        'strength',    strength,
        'catalyst_type', catalyst_type,
        'headline',    headline,
        'horizon',     horizon,
        'confidence',  confidence,
        'routed_to',   routed_to
      ) ORDER BY captured_at DESC), '[]'::jsonb)
      FROM oracle_flash_intel
      WHERE captured_at > now() - interval '6 hours'
      LIMIT 20
    ),

    'positions_live', (
      SELECT COALESCE(jsonb_object_agg(
        archimage,
        positions
      ), '{}'::jsonb)
      FROM (
        SELECT archimage,
          jsonb_agg(jsonb_build_object(
            'ticker',         ticker,
            'qty',            qty,
            'market_value',   ROUND(market_value::numeric, 2),
            'unrealized_pl',  ROUND(unrealized_pl::numeric, 2),
            'unrealized_pl_pct', ROUND(unrealized_pl_pct::numeric, 2),
            'days_held',      days_held,
            'runs_held',      consecutive_runs_held,
            'is_stale',       is_stale
          )) as positions
        FROM oracle_positions_live
        WHERE qty > 0
        GROUP BY archimage
      ) grouped
    ),

    'active_circuit_breakers', (
      SELECT COALESCE(jsonb_agg(jsonb_build_object(
        'archimage',   archimage,
        'type',        breaker_type,
        'action',      action_taken,
        'fired_at',    fired_at,
        'notes',       notes
      )), '[]'::jsonb)
      FROM oracle_circuit_breakers
      WHERE auto_resolved = false
        AND fired_at > now() - interval '24 hours'
    ),

    'visionary_signals', (
      SELECT COALESCE(jsonb_agg(jsonb_build_object(
        'type',        signal_type,
        'ticker',      ticker,
        'label',       signal_label,
        'conviction',  conviction,
        'horizon',     time_horizon,
        'corroborated', corroborated_by
      ) ORDER BY conviction DESC), '[]'::jsonb)
      FROM oracle_visionary_signals
      WHERE generated_at > now() - interval '4 hours'
        AND conviction >= 6
    ),

    'datasource_health', (
      SELECT COALESCE(jsonb_object_agg(
        source_name,
        jsonb_build_object(
          'status', status,
          'completeness_pct', completeness_pct,
          'latency_ms', latency_ms
        )
      ), '{}'::jsonb)
      FROM (
        SELECT DISTINCT ON (source_name)
          source_name, status, completeness_pct, latency_ms
        FROM oracle_datasource_health
        ORDER BY source_name, checked_at DESC
      ) latest_health
    ),

    'performance_summary', (
      SELECT jsonb_build_object(
        'total_runs',         COUNT(*),
        'avg_completeness',   ROUND(AVG(data_completeness)::numeric, 1),
        'avg_overlap_score',  ROUND(AVG(overlap_score)::numeric, 2),
        'circuit_breakers',   SUM(CASE WHEN circuit_breaker_fired THEN 1 ELSE 0 END),
        'avg_visionary_score',ROUND(AVG(visionary_score)::numeric, 1),
        'avg_sell_ratio',     ROUND(AVG(CASE WHEN (orders_buy + orders_sell) > 0
                                        THEN orders_sell::numeric/(orders_buy + orders_sell)
                                        ELSE 0 END)::numeric, 3)
      ) FROM oracle_college_runs WHERE status = 'success'
    ),

    -- NOUVEAU : rejets d'execution recents, pour que chaque archimage corrige ses ordres
    'recent_exec_errors', (
      SELECT COALESCE(jsonb_agg(e.entry ORDER BY e.created_at DESC), '[]'::jsonb)
      FROM (
        SELECT d.created_at, jsonb_build_object(
          'archimage', d.archimage,
          'at', d.created_at,
          'errors', (SELECT jsonb_agg(jsonb_build_object('ticker', r->>'t', 'side', r->>'side', 'err', r->>'err'))
                     FROM jsonb_array_elements(d.payload->'results') r WHERE r->>'err' IS NOT NULL)
        ) as entry
        FROM oracle_exec_debug d
        WHERE d.created_at > now() - interval '48 hours' AND d.rejected > 0
        ORDER BY d.created_at DESC LIMIT 6
      ) e
    ),

    -- NOUVEAU : bilan chiffre des 5 Sages (fiabilite mesuree sur donnees reelles)
    'sages_coaching', public.sages_coaching(),

    -- 19/08/2026 : dxy_trend, ratio or/argent et spread de credit HYG-LQD. Le prompt du
    -- Sage Macro les reclamait alors qu'aucun n'existait dans CTX (il repondait « DXY missing »).
    'macro_extra', (SELECT to_jsonb(m) FROM public.v_macro_extra m),

    'fetched_at', now()
  );
END;
$function$



-- FUNCTION: iron_sentinel_validate_order
CREATE OR REPLACE FUNCTION public.iron_sentinel_validate_order(p_archimage text, p_ticker text, p_side text, p_notional numeric, p_run_id text, p_buying_power numeric DEFAULT 100000, p_is_liquidation boolean DEFAULT false)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_brain oracle_brain_state%ROWTYPE;
  v_cap numeric := 2000;
  v_effective_notional numeric;
  v_result jsonb;
  v_blocked boolean := false;
  v_block_reason text;
  v_consecutive_buys integer;
  v_drawdown numeric;
BEGIN
  -- Charger le brain state
  SELECT * INTO v_brain FROM oracle_brain_state WHERE archimage = p_archimage;

  -- 1. DRAWDOWN CIRCUIT BREAKER
  v_drawdown := COALESCE(v_brain.alpaca_drawdown_from_peak, 0);
  IF v_drawdown >= 0.08 AND NOT p_is_liquidation THEN
    v_blocked := true;
    v_block_reason := 'DRAWDOWN_8PCT: ' || ROUND(v_drawdown * 100, 2) || '% > 8% — mode DEFENSIVE activé';
    INSERT INTO oracle_circuit_breakers (run_id, archimage, breaker_type, trigger_value, threshold_value, action_taken, notes)
    VALUES (p_run_id, p_archimage, 'drawdown_8pct', v_drawdown, 0.08, 'BLOCK_ALL_BUY', v_block_reason);
  ELSIF v_drawdown >= 0.05 AND p_side = 'buy' AND NOT p_is_liquidation THEN
    v_cap := 500; -- Réduire le cap à 500$ si drawdown 5-8%
    v_block_reason := 'DRAWDOWN_5PCT: notional cappé à 500$ (drawdown=' || ROUND(v_drawdown*100,2) || '%)';
    INSERT INTO oracle_circuit_breakers (run_id, archimage, breaker_type, trigger_value, threshold_value, action_taken, capital_protected, notes)
    VALUES (p_run_id, p_archimage, 'drawdown_5pct', v_drawdown, 0.05, 'CAP_NOTIONAL_500', p_notional - 500, v_block_reason)
    ON CONFLICT DO NOTHING;
  END IF;

  -- 2. BUYING POWER CHECK
  IF p_buying_power < 5000 AND p_side = 'buy' AND NOT p_is_liquidation THEN
    v_blocked := true;
    v_block_reason := 'BUYING_POWER_LOW: ' || p_buying_power || '$ < 5000$ minimum';
    INSERT INTO oracle_circuit_breakers (run_id, archimage, breaker_type, trigger_value, threshold_value, action_taken, notes)
    VALUES (p_run_id, p_archimage, 'low_buying_power', p_buying_power, 5000, 'BLOCK_ALL_BUY', v_block_reason);
  END IF;

  -- 3. CONSECUTIVE BUY DETECTOR — même ticker BUY 3x sans SELL
  SELECT COUNT(*) INTO v_consecutive_buys
  FROM oracle_college_orders
  WHERE archimage = p_archimage
    AND symbol = p_ticker
    AND side = 'buy'
    AND created_at > now() - interval '7 days'
    AND NOT EXISTS (
      SELECT 1 FROM oracle_college_orders o2
      WHERE o2.archimage = p_archimage
        AND o2.symbol = p_ticker
        AND o2.side = 'sell'
        AND o2.created_at > now() - interval '7 days'
        AND o2.created_at > (
          SELECT MAX(o3.created_at) FROM oracle_college_orders o3
          WHERE o3.archimage = p_archimage AND o3.symbol = p_ticker AND o3.side = 'buy'
        )
    );

  IF v_consecutive_buys >= 3 AND p_side = 'buy' AND NOT p_is_liquidation THEN
    v_cap := LEAST(v_cap, 300); -- Forcer cap minimal si accumulation excessive
    INSERT INTO oracle_circuit_breakers (run_id, archimage, breaker_type, trigger_value, threshold_value, action_taken, notes)
    VALUES (p_run_id, p_archimage, 'consecutive_buy_3x', v_consecutive_buys, 3, 'CAP_NOTIONAL_300',
            'Ticker ' || p_ticker || ' BUY x' || v_consecutive_buys || ' sans SELL')
    ON CONFLICT DO NOTHING;
  END IF;

  -- 4. NOTIONAL CAP FINAL
  IF p_is_liquidation THEN
    v_effective_notional := p_notional; -- Pas de cap sur les liquidations/ventes
  ELSE
    v_effective_notional := LEAST(p_notional, v_cap);
  END IF;

  -- 5. LOG Kelly sizing
  IF NOT v_blocked THEN
    INSERT INTO oracle_kelly_sizing (
      run_id, archimage, ticker,
      win_rate_used, avg_win_used, avg_loss_used,
      kelly_raw, kelly_fractional,
      recommended_notional, capped_notional,
      buying_power_at_time, applied
    ) VALUES (
      p_run_id, p_archimage, p_ticker,
      COALESCE(v_brain.win_rate, 0),
      COALESCE(v_brain.avg_win_pct, 5),
      COALESCE(v_brain.avg_loss_pct, 3),
      CASE WHEN COALESCE(v_brain.avg_loss_pct, 0) > 0
        THEN COALESCE(v_brain.win_rate, 0) - (1 - COALESCE(v_brain.win_rate, 0)) / GREATEST(COALESCE(v_brain.avg_win_pct, 5) / GREATEST(COALESCE(v_brain.avg_loss_pct, 3), 0.01), 0.01)
        ELSE 0.1 END,
      COALESCE(v_brain.kelly_fraction, 0.1),
      LEAST(p_buying_power * COALESCE(v_brain.kelly_fraction, 0.1), 2000),
      v_effective_notional,
      p_buying_power,
      true
    );
  END IF;

  RETURN jsonb_build_object(
    'allowed',            NOT v_blocked,
    'effective_notional', v_effective_notional,
    'original_notional',  p_notional,
    'was_capped',         v_effective_notional < p_notional,
    'block_reason',       CASE WHEN v_blocked THEN v_block_reason ELSE null END,
    'drawdown',           v_drawdown,
    'kelly_fraction',     COALESCE(v_brain.kelly_fraction, 0.1)
  );

EXCEPTION WHEN OTHERS THEN
  RETURN jsonb_build_object('allowed', true, 'effective_notional', LEAST(p_notional, 2000), 'error', SQLERRM);
END;
$function$



-- FUNCTION: ju_kelly_sizing
CREATE OR REPLACE FUNCTION public.ju_kelly_sizing(p_capital numeric DEFAULT 1000, p_max_pct numeric DEFAULT 2.0, p_fraction numeric DEFAULT 0.5)
 RETURNS TABLE(archimage text, win_rate numeric, ratio_gp numeric, kelly_raw numeric, kelly_frac numeric, statut text, taille_pct numeric, taille_usd numeric)
 LANGUAGE sql
 STABLE
 SET search_path TO 'public'
AS $function$
  with m as (
    select archimage,
      count(*) filter (where unrealized_pl_pct>0)::numeric / nullif(count(*),0) as w,
      avg(unrealized_pl_pct) filter (where unrealized_pl_pct>0)        as avg_win,
      abs(avg(unrealized_pl_pct) filter (where unrealized_pl_pct<0))   as avg_loss
    from public.oracle_positions_live
    group by archimage
  ), k as (
    select archimage, w,
      (avg_win / nullif(avg_loss,0)) as r,
      (w - (1-w) / nullif(avg_win / nullif(avg_loss,0),0)) as kraw
    from m
  )
  select
    archimage,
    round((w*100)::numeric,1),
    round(r::numeric,2),
    round(kraw::numeric,3),
    round((kraw*p_fraction)::numeric,3),
    case when kraw is null or kraw<=0 then 'PAUSE — pas d edge' else 'ACTIF' end,
    round((case when kraw is null or kraw<=0 then 0 else least(kraw*p_fraction*100, p_max_pct) end)::numeric,2),
    round((p_capital * (case when kraw is null or kraw<=0 then 0 else least(kraw*p_fraction*100, p_max_pct) end)/100)::numeric,2)
  from k
  order by kraw desc nulls last;
$function$



-- FUNCTION: log_flash_intel
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
BEGIN
  v_run_id := p_payload->>'run_id';

  DELETE FROM oracle_flash_intel WHERE run_id = v_run_id;

  -- Accepte catalysts en TABLEAU json OU en CHAINE json (le module Flash envoie toString())
  v_catalysts := p_payload->'catalysts';
  IF v_catalysts IS NOT NULL AND jsonb_typeof(v_catalysts) = 'string' THEN
    BEGIN
      v_catalysts := (p_payload->>'catalysts')::jsonb;
    EXCEPTION WHEN OTHERS THEN
      v_catalysts := '[]'::jsonb;
    END;
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
        COALESCE((v_item->>'strength')::integer, 5),
        v_item->>'headline',
        COALESCE(v_item->>'horizon', '1w'),
        COALESCE((v_item->>'confidence')::integer, 70),
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
$function$



-- FUNCTION: log_visionary_signals
CREATE OR REPLACE FUNCTION public.log_visionary_signals(p_payload jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_run_id text;
  v_signal jsonb;
  v_count integer := 0;
BEGIN
  v_run_id := p_payload->>'run_id';

  IF p_payload->'signals' IS NOT NULL THEN
    FOR v_signal IN SELECT * FROM jsonb_array_elements(p_payload->'signals')
    LOOP
      INSERT INTO oracle_visionary_signals (
        run_id, signal_type, ticker, signal_value, signal_label,
        conviction, time_horizon, source, raw_data, corroborated_by
      ) VALUES (
        v_run_id,
        COALESCE(v_signal->>'signal_type', 'macro'),
        UPPER(COALESCE(v_signal->>'ticker', 'MARKET')),
        (v_signal->>'signal_value')::numeric,
        v_signal->>'signal_label',
        COALESCE((v_signal->>'conviction')::integer, 5),
        COALESCE(v_signal->>'time_horizon', '1w'),
        v_signal->>'source',
        COALESCE(v_signal->'raw_data', '{}'::jsonb),
        ARRAY(SELECT jsonb_array_elements_text(COALESCE(v_signal->'corroborated_by', '[]'::jsonb)))
      );
      v_count := v_count + 1;
    END LOOP;
  END IF;

  RETURN jsonb_build_object('success', true, 'signals_logged', v_count, 'run_id', v_run_id);

EXCEPTION WHEN OTHERS THEN
  RETURN jsonb_build_object('success', false, SQLERRM);
END;
$function$



-- FUNCTION: marees_evaluate_and_learn
CREATE OR REPLACE FUNCTION public.marees_evaluate_and_learn()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_wins int; v_losses int; v_evald int; v_open int; v_nodata int;
  v_wr numeric; v_aw numeric; v_al numeric; v_sum numeric;
  v_bias text; v_learn jsonb; v_prev jsonb;
BEGIN
  -- Only trades with a REAL outcome count as evaluated. SANS_DONNEES = pas encore de prix forward.
  SELECT
    count(*) FILTER (WHERE exit_reason IN ('TP','SL','MARCHE','FERME') AND pnl_pct > 0),
    count(*) FILTER (WHERE exit_reason IN ('TP','SL','MARCHE','FERME') AND pnl_pct <= 0),
    count(*) FILTER (WHERE exit_reason IN ('TP','SL','MARCHE','FERME')),
    count(*) FILTER (WHERE is_open OR exit_reason = 'OUVERT'),
    count(*) FILTER (WHERE exit_reason = 'SANS_DONNEES'),
    avg(pnl_pct) FILTER (WHERE exit_reason IN ('TP','SL','MARCHE','FERME') AND pnl_pct > 0),
    avg(pnl_pct) FILTER (WHERE exit_reason IN ('TP','SL','MARCHE','FERME') AND pnl_pct <= 0),
    sum(pnl_pct) FILTER (WHERE exit_reason IN ('TP','SL','MARCHE','FERME'))
  INTO v_wins, v_losses, v_evald, v_open, v_nodata, v_aw, v_al, v_sum
  FROM public.marees_virtual_trades;

  v_wins := coalesce(v_wins,0); v_losses := coalesce(v_losses,0);
  v_evald := coalesce(v_evald,0); v_open := coalesce(v_open,0); v_nodata := coalesce(v_nodata,0);
  v_wr := CASE WHEN v_evald > 0 THEN round(v_wins::numeric / v_evald, 3) ELSE 0 END;

  v_bias := CASE
    WHEN v_evald = 0 THEN 'apprentissage: '||v_nodata||' propositions en attente de prix forward, aucun trade evalue encore'
    WHEN v_wr >= 0.55 THEN 'forex: momentum favorable, maintenir la selection de paires'
    WHEN v_wr >= 0.45 THEN 'forex: neutre, affiner les entrees et le sizing'
    ELSE 'forex: sous-performance, resserrer TP/SL et reduire le sizing' END;

  SELECT learnings INTO v_prev FROM public.oracle_brain_state WHERE archimage = 'MAREES';
  v_learn := coalesce(v_prev, '[]'::jsonb) || jsonb_build_object(
    'at', now(), 'evald', v_evald, 'open', v_open, 'en_attente_prix', v_nodata, 'win_rate', v_wr,
    'avg_win_pct', round(coalesce(v_aw,0),3), 'avg_loss_pct', round(coalesce(v_al,0),3),
    'somme_rendements_pct', round(coalesce(v_sum,0),3));
  IF jsonb_array_length(v_learn) > 30 THEN
    v_learn := (SELECT jsonb_agg(e ORDER BY ord)
                FROM jsonb_array_elements(v_learn) WITH ORDINALITY AS t(e, ord)
                WHERE ord > jsonb_array_length(v_learn) - 30);
  END IF;

  UPDATE public.oracle_brain_state SET
    total_runs = v_evald, wins = v_wins, losses = v_losses, win_rate = v_wr,
    avg_win_pct = round(coalesce(v_aw,0),3), avg_loss_pct = round(coalesce(v_al,0),3),
    current_bias = v_bias, learnings = v_learn, last_run_at = now(), updated_at = now()
  WHERE archimage = 'MAREES';

  RETURN jsonb_build_object('mage','MAREES','evalues',v_evald,'ouverts',v_open,'en_attente_prix',v_nodata,
    'wins',v_wins,'losses',v_losses,'win_rate',v_wr,'somme_rendements_pct', round(coalesce(v_sum,0),3));
END;
$function$



-- FUNCTION: marees_rebuild_virtual
CREATE OR REPLACE FUNCTION public.marees_rebuild_virtual(p_fee_pct double precision DEFAULT 0.03, p_max_hold_h integer DEFAULT 96)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_res jsonb;
begin
  truncate public.marees_virtual_trades;
  insert into public.marees_virtual_trades
    (proposition_id, paire, side, prix_entree, montant, opened_at, tp_pct, sl_pct,
     exit_ts, prix_sortie, exit_reason, pnl_pct, hold_hours, is_open)
  with props as (
    select id, paire, lower(side) as side, prix_ref::float8 as e,
           coalesce(poids_pct,1)::float8 as m, proposed_at as t0,
           greatest(coalesce(tp_pct, 1.2), 1.2)::float8 as tpp,
           greatest(coalesce(sl_pct, 0.8), 0.8)::float8 as slp,
           cloturee_at,
           -- 20/08 : une position qui quitte le livre cible est FERMEE a cet instant.
           least(proposed_at + (p_max_hold_h||' hours')::interval,
                 coalesce(cloturee_at, 'infinity'::timestamptz)) as t_fin
    from marees_propositions
    -- 'remplacee' = doublon de tenue de l'ancien modele append-only, exclu des stats.
    where statut in ('expiree','proposee') and prix_ref > 0
  ),
  sim as (
    select p.*,
      case when p.side='buy' then p.e*(1+p.tpp/100) else p.e*(1-p.tpp/100) end as tp_price,
      case when p.side='buy' then p.e*(1-p.slp/100) else p.e*(1+p.slp/100) end as sl_price
    from props p
  ),
  hit as (
    select s.*, lat.ts as hit_ts, lat.motif as hit_motif
    from sim s
    left join lateral (
      select ph.ts,
        case when s.side='buy' then (case when ph.low<=s.sl_price then 'SL' else 'TP' end)
             else (case when ph.high>=s.sl_price then 'SL' else 'TP' end) end as motif
      from price_history ph
      where ph.symbol=s.paire and ph.interval='1h'
        and ph.ts > s.t0 and ph.ts <= s.t_fin
        and ( (s.side='buy'  and (ph.high>=s.tp_price or ph.low<=s.sl_price))
           or (s.side='sell' and (ph.low<=s.tp_price or ph.high>=s.sl_price)) )
      order by ph.ts asc limit 1
    ) lat on true
  ),
  fin as (
    select h.*,
      (select ph.close from price_history ph where ph.symbol=h.paire and ph.interval='1h'
        and ph.ts <= h.t_fin order by ph.ts desc limit 1) as close_fin,
      (select ph.close from price_history ph where ph.symbol=h.paire and ph.interval='1h'
        order by ph.ts desc limit 1) as close_now,
      (select count(*) from price_history ph where ph.symbol=h.paire and ph.interval='1h' and ph.ts > h.t0) as n_bougies,
      (h.t_fin < now()) as fenetre_finie
    from hit h
  )
  select
    id, paire, side, e, m, t0, tpp, slp,
    case when hit_motif is not null then hit_ts when fenetre_finie then t_fin else null end,
    case when hit_motif='TP' then tp_price when hit_motif='SL' then sl_price
         when n_bougies=0 then null
         when fenetre_finie then close_fin else close_now end,
    case when hit_motif is not null then hit_motif
         when n_bougies=0 then 'SANS_DONNEES'
         when fenetre_finie and cloturee_at is not null and cloturee_at <= t0 + (p_max_hold_h||' hours')::interval
           then 'FERME'
         when fenetre_finie then 'MARCHE'
         else 'OUVERT' end,
    case when hit_motif='TP' then tpp - 2*p_fee_pct
         when hit_motif='SL' then -slp - 2*p_fee_pct
         when n_bougies=0 then null
         else ( case when side='buy'
                  then (coalesce(case when fenetre_finie then close_fin else close_now end,e)/e - 1)*100
                  else (1 - coalesce(case when fenetre_finie then close_fin else close_now end,e)/e)*100 end ) - 2*p_fee_pct end,
    case when hit_ts is not null then extract(epoch from (hit_ts - t0))/3600
         when fenetre_finie then extract(epoch from (t_fin - t0))/3600 else null end,
    (hit_motif is null and n_bougies>0 and not fenetre_finie)
  from fin;

  -- 20/08 : le win_rate ne comptait que TP/(TP+SL) et ignorait les sorties au marche,
  -- dont 16 etaient gagnantes -> il affichait 0 %. Toute cloture compte, au signe du P&L.
  select jsonb_build_object(
    'trades_total', (select count(*) from marees_virtual_trades),
    'clotures',  (select count(*) from marees_virtual_trades where exit_reason in ('TP','SL','MARCHE','FERME')),
    'tp',        (select count(*) from marees_virtual_trades where exit_reason='TP'),
    'sl',        (select count(*) from marees_virtual_trades where exit_reason='SL'),
    'marche',    (select count(*) from marees_virtual_trades where exit_reason='MARCHE'),
    'ferme',     (select count(*) from marees_virtual_trades where exit_reason='FERME'),
    'ouvertes',  (select count(*) from marees_virtual_trades where is_open),
    'gagnants',  (select count(*) from marees_virtual_trades where exit_reason in ('TP','SL','MARCHE','FERME') and pnl_pct > 0),
    'perdants',  (select count(*) from marees_virtual_trades where exit_reason in ('TP','SL','MARCHE','FERME') and pnl_pct <= 0),
    'win_rate',  (select round((count(*) filter (where pnl_pct > 0))::numeric
                    / nullif(count(*) filter (where exit_reason in ('TP','SL','MARCHE','FERME')),0)*100,1)
                  from marees_virtual_trades where exit_reason in ('TP','SL','MARCHE','FERME')),
    'esperance_pct', (select round((avg(pnl_pct) filter (where exit_reason in ('TP','SL','MARCHE','FERME')))::numeric,3) from marees_virtual_trades),
    'somme_rendements_pct', (select round((sum(pnl_pct) filter (where exit_reason in ('TP','SL','MARCHE','FERME')))::numeric,1) from marees_virtual_trades)
  ) into v_res;
  return v_res;
end $function$



-- FUNCTION: marees_record_propositions
-- 20/08 : l'Archimage produit un LIVRE CIBLE COMPLET -- son prompt systeme dit « le miroir aligne
-- le book reel sur ta cible ; une paire absente de ta cible = position fermee ». Cette semantique
-- n'etait implementee nulle part : la fonction INSERAIT le livre entier a chaque run. Une position
-- tenue 34 runs comptait pour 34 trades independants (113 lignes pour 37 positions reelles).
-- Desormais : tenue = on garde la ligne d'origine, disparition = cloture, nouveaute = insertion.
CREATE OR REPLACE FUNCTION public.marees_record_propositions(p_run_id text, p_props jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_ouvertes int; v_tenues int; v_fermees int; v_nouvelles int;
  v_lines text; v_resume text;
begin
  create temp table _book on commit drop as
  select upper(replace(x->>'paire','/','-')) as paire,
         lower(x->>'side')                   as side,
         nullif(x->>'poids_pct','')::numeric        as poids_pct,
         nullif(x->>'confidence','')::numeric       as confidence,
         x->>'raison'                                as raison,
         nullif(x->>'prix_ref','')::double precision as prix_ref,
         nullif(x->>'tp_pct','')::double precision   as tp_pct,
         nullif(x->>'sl_pct','')::double precision   as sl_pct
  from jsonb_array_elements(coalesce(p_props,'[]'::jsonb)) x;

  delete from _book where paire is null or side not in ('buy','sell');

  -- 1. Les positions ouvertes absentes du nouveau livre cible sont FERMEES.
  update public.marees_propositions mp
     set cloturee_at = now()
   where mp.statut = 'proposee'
     and mp.cloturee_at is null
     and not exists (select 1 from _book b where b.paire = mp.paire and b.side = mp.side);
  get diagnostics v_fermees = row_count;

  -- 2. Les lignes deja ouvertes sont TENUES : on ne les reinsere pas, le prix d'entree
  --    et la date d'ouverture d'origine sont conserves.
  select count(*) into v_tenues
  from _book b
  where exists (select 1 from public.marees_propositions mp
                 where mp.statut='proposee' and mp.cloturee_at is null
                   and mp.paire=b.paire and mp.side=b.side);

  -- 3. Les lignes reellement nouvelles sont OUVERTES.
  insert into public.marees_propositions
    (run_id, paire, side, poids_pct, confidence, raison, prix_ref, tp_pct, sl_pct, statut, proposed_at)
  select p_run_id, b.paire, b.side, b.poids_pct, b.confidence, b.raison,
         coalesce(b.prix_ref, (select ph.close from price_history ph
                                where ph.symbol=b.paire and ph.interval='1h'
                                order by ph.ts desc limit 1)),
         b.tp_pct, b.sl_pct, 'proposee', now()
  from _book b
  where not exists (select 1 from public.marees_propositions mp
                     where mp.statut='proposee' and mp.cloturee_at is null
                       and mp.paire=b.paire and mp.side=b.side);
  get diagnostics v_nouvelles = row_count;

  -- Le resume Discord decrit le LIVRE CIBLE COURANT, pas les seules nouveautes.
  select count(*), string_agg(
      '• '||paire||'  '||case when side='buy' then 'ACHAT ▲' else 'VENTE ▼' end
      ||'  poids '||rtrim(rtrim(to_char(coalesce(poids_pct,0),'FM990.9'),'0'),'.')||'%'
      ||'  conf '||round(coalesce(confidence,0)*100)::int||'%'
      ||'  TP '||rtrim(rtrim(to_char(coalesce(tp_pct,0),'FM990.99'),'0'),'.')||'% / SL '
      ||rtrim(rtrim(to_char(coalesce(sl_pct,0),'FM990.99'),'0'),'.')||'%'
      ||case when proposed_at < now() - interval '5 minutes'
             then '  (tenue depuis '||to_char(proposed_at,'DD/MM HH24:MI')||')' else '  (nouvelle)' end,
      E'\n' order by confidence desc nulls last)
    into v_ouvertes, v_lines
  from public.marees_propositions
  where statut='proposee' and cloturee_at is null;

  v_resume := '🌊 **L''Archimage des Marées** — livre cible : '||v_ouvertes||' position'
    ||case when v_ouvertes>1 then 's' else '' end
    ||'  ('||v_nouvelles||' ouverte'||case when v_nouvelles>1 then 's' else '' end
    ||', '||v_tenues||' tenue'||case when v_tenues>1 then 's' else '' end
    ||', '||v_fermees||' fermée'||case when v_fermees>1 then 's' else '' end||')'
    || coalesce(E'\n'||v_lines, E'\n_Aucune position ce cycle._');

  return jsonb_build_object(
    'run_id', p_run_id,
    'inserted', v_nouvelles,      -- conserve : le module Make lit cette cle
    'nouvelles', v_nouvelles, 'tenues', v_tenues, 'fermees', v_fermees,
    'livre_cible', v_ouvertes,
    'resume', v_resume,
    'resume_json', replace(v_resume, E'\n', E'\\n'));
end $function$



-- FUNCTION: marees_resume
CREATE OR REPLACE FUNCTION public.marees_resume()
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  with bs as (
    select * from oracle_brain_state where archimage='MAREES' limit 1
  ),
  ev as (
    select
      count(*) filter (where exit_reason in ('TP','SL','MARCHE','FERME')) as n_eval,
      count(*) filter (where exit_reason in ('TP','SL','MARCHE','FERME') and pnl_pct>0) as wins,
      count(*) filter (where exit_reason in ('TP','SL','MARCHE','FERME') and pnl_pct<=0) as losses,
      count(*) filter (where is_open) as n_open,
      round(avg(pnl_pct) filter (where exit_reason in ('TP','SL','MARCHE','FERME'))::numeric,2) as pnl_moyen
    from marees_virtual_trades
  ),
  props as (
    select jsonb_agg(x order by x_proposed_at desc) as arr from (
      select paire, side, poids_pct, confidence, raison, tp_pct, sl_pct, statut, proposed_at as x_proposed_at
      from marees_propositions where statut <> 'remplacee' order by proposed_at desc limit 15
    ) x
  ),
  trades as (
    select jsonb_agg(y order by y_opened_at desc) as arr from (
      select paire, side, round(pnl_pct::numeric,2) as pnl_pct, exit_reason, is_open, opened_at as y_opened_at
      from marees_virtual_trades order by opened_at desc limit 10
    ) y
  )
  select jsonb_build_object(
    'cerveau', jsonb_build_object(
      'archimage','MAREES',
      'univers', (select assigned_universe from bs),
      'win_rate', (select win_rate from bs),
      'kelly', (select kelly_fraction from bs),
      'poids', (select synthesis_weight from bs),
      'total_runs', (select total_runs from bs),
      'wins', (select wins from bs),
      'losses', (select losses from bs),
      'pnl', (select cumulative_pnl from bs),
      'doctrine', (select current_bias from bs),
      'maj', (select updated_at from bs)
    ),
    'stats', jsonb_build_object(
      'n_propositions', (select count(*) from marees_propositions where statut <> 'remplacee'),
      'n_open', (select n_open from ev),
      'n_evaluated', (select n_eval from ev),
      'wins', (select wins from ev),
      'losses', (select losses from ev),
      'win_rate_reel', case when (select n_eval from ev)>0 then round((select wins from ev)::numeric/(select n_eval from ev),3) else null end,
      'pnl_moyen', (select pnl_moyen from ev)
    ),
    'propositions', coalesce((select arr from props), '[]'::jsonb),
    'trades_recents', coalesce((select arr from trades), '[]'::jsonb),
    'dernier_run', (select max(proposed_at) from marees_propositions),
    'derniere_maj', now()
  )
$function$



-- FUNCTION: mt5_book
CREATE OR REPLACE FUNCTION public.mt5_book(p_mode text DEFAULT 'JU'::text)
 RETURNS TABLE(ticker text, poids_pct numeric)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
with base as (
  select p.archimage, p.ticker,
         case when p.side = 'short' then -abs(p.market_value) else p.market_value end as val_signee
  from oracle_positions_live p
  where not coalesce(p.is_stale, false)
    and ( upper(p_mode) = 'COLLEGE' or p.archimage = upper(p_mode) )
),
equity as (
  select coalesce(sum(alpaca_portfolio_value), 0) as eq
  from oracle_brain_state
  where ( upper(p_mode) = 'COLLEGE' and archimage in ('JU','SYL','GIL') )
     or ( upper(p_mode) <> 'COLLEGE' and archimage = upper(p_mode) )
),
agg as (
  select ticker, sum(val_signee) as val_nette
  from base group by ticker
)
select a.ticker,
       round( (a.val_nette / nullif((select eq from equity),0) * 100)::numeric, 3) as poids_pct
from agg a
where abs(a.val_nette / nullif((select eq from equity),0) * 100) >= 0.10   -- ignore la poussière (<0,10%)
order by abs(a.val_nette) desc;
$function$



-- FUNCTION: populate_learning_feedback
CREATE OR REPLACE FUNCTION public.populate_learning_feedback()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_ins int := 0;
  r record;
begin
  for r in
    select run_id, run_at, market_phase,
      lead(market_phase) over (order by run_at) as next_phase,
      lead(run_at) over (order by run_at) as next_run_at
    from public.oracle_college_runs
    order by run_at
  loop
    if r.next_run_at is null then continue; end if;
    if exists (select 1 from public.learning_feedback lf where lf.run_id = r.run_id) then continue; end if;
    insert into public.learning_feedback
      (id, run_id, evaluated_at, evaluated_by, predicted_phase, actual_phase_next_run,
       spy_performance_7d, recommended_positions_pnl, phase_correct, direction_correct, accuracy_score, notes)
    values (
      gen_random_uuid(), r.run_id, now(), 'auto_cron', r.market_phase, r.next_phase,
      (select round(((a.c / nullif(b.c,0)) - 1) * 100, 2) from
        (select close c from public.price_history where symbol='SPY' and interval='1h' and ts <= r.run_at order by ts desc limit 1) a,
        (select close c from public.price_history where symbol='SPY' and interval='1h' and ts <= r.run_at - interval '7 days' order by ts desc limit 1) b),
      (select jsonb_object_agg(p.archimage, p.actual_pnl) from public.oracle_performance p
        where p.evaluated_at between r.run_at - interval '10 minutes' and r.run_at + interval '10 minutes'),
      (r.market_phase = r.next_phase),
      (select count(*) filter (where p.win) >= 2 from public.oracle_performance p
        where p.archimage in ('JU','SYL','GIL')
          and p.evaluated_at between r.run_at - interval '10 minutes' and r.run_at + interval '10 minutes'),
      (select coalesce((count(*) filter (where p.win)) * 100 / greatest(count(*),1), 0)::int
        from public.oracle_performance p
        where p.archimage in ('JU','SYL','GIL')
          and p.evaluated_at between r.run_at - interval '10 minutes' and r.run_at + interval '10 minutes'),
      'auto: phase ' || coalesce(r.market_phase,'?') || ' -> ' || coalesce(r.next_phase,'?')
    );
    v_ins := v_ins + 1;
  end loop;
  return jsonb_build_object('inserted', v_ins);
end $function$



-- FUNCTION: record_sages
CREATE OR REPLACE FUNCTION public.record_sages(p_run_id text, p_macro_b64 text DEFAULT NULL::text, p_technique_b64 text DEFAULT NULL::text, p_risque_b64 text DEFAULT NULL::text, p_memoire_b64 text DEFAULT NULL::text, p_flash_b64 text DEFAULT NULL::text)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare cnt int;
begin
  insert into public.oracle_sages_report(run_id, sage_name, sage_output, status)
  select p_run_id, s.name,
         public.try_jsonb(convert_from(decode(s.b64,'base64'),'UTF8')),
         'ok'
  from (values
    ('Macro', p_macro_b64), ('Technique', p_technique_b64), ('Risque', p_risque_b64),
    ('Memoire', p_memoire_b64), ('Flash', p_flash_b64)
  ) s(name, b64)
  where s.b64 is not null and length(s.b64) > 0;
  get diagnostics cnt = row_count;
  return cnt;
end; $function$



-- FUNCTION: refresh_backtest_cache
CREATE OR REPLACE FUNCTION public.refresh_backtest_cache()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_n int;
begin
  delete from public.oracle_backtest_cache;
  insert into public.oracle_backtest_cache (kind, tp_pct, sl_pct, trades, win_rate, avg_ret_pct, total_ret_pct)
    select 'alchimiste', tp_pct, sl_pct, trades, win_rate, avg_ret_pct, total_ret_pct from public.bt_optimize_alchimiste();
  insert into public.oracle_backtest_cache (kind, tp_pct, sl_pct, trades, win_rate, avg_ret_pct, total_ret_pct)
    select 'exits_crypto', tp_pct, sl_pct, trades, win_rate, avg_ret_pct, total_ret_pct from public.bt_optimize_exits();
  insert into public.oracle_backtest_cache (kind, archimage, trades, win_rate, avg_ret_pct, total_ret_pct, profit_factor)
    select 'archimages', archimage, trades, win_rate, avg_ret_pct, total_ret_pct, profit_factor from public.bt_replay_archmages();
  select count(*) into v_n from public.oracle_backtest_cache;
  return jsonb_build_object('lignes', v_n, 'computed_at', now());
end $function$



-- FUNCTION: sage_detail
CREATE OR REPLACE FUNCTION public.sage_detail(p_sage text, p_hold_hours integer DEFAULT 24, p_seuil numeric DEFAULT 0.5)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
with base as (
  select created_at, sage_output,
    case p_sage
      when 'Macro'     then upper(coalesce(nullif(sage_output->>'recommended_bias',''), sage_output->>'spy_trend'))
      when 'Technique' then upper(coalesce(nullif(sage_output->>'spy_momentum',''), sage_output->>'wyckoff_phase'))
      when 'Flash'     then upper(sage_output->>'flash_sentiment')
      when 'Risque'    then upper(sage_output->>'risk_level')
      when 'Memoire'   then upper(left(coalesce(sage_output->>'correction_directive',''),40))
    end as signal,
    case p_sage
      when 'Macro'     then coalesce(sage_output->>'rationale', sage_output->>'macro_regime')
      when 'Technique' then coalesce(sage_output->>'rationale', sage_output->>'wyckoff_phase')
      when 'Flash'     then sage_output->>'top_headline_1'
      when 'Risque'    then sage_output->>'hedge_recommendation'
      when 'Memoire'   then sage_output->>'correction_directive'
    end as extrait
  from oracle_sages_report
  where sage_name = p_sage
),
scored as (
  select b.*,
    case when b.signal in ('BULLISH','UP','ACCUMULATION') then 1
         when b.signal in ('BEARISH','DOWN','DISTRIBUTION') then -1
         when b.signal in ('NEUTRAL','FLAT') then 0 else null end as d,
    (select close from price_history where symbol='SPY' and interval='1h' and ts >= b.created_at + (p_hold_hours||' hours')::interval order by ts asc limit 1)
      / nullif((select close from price_history where symbol='SPY' and interval='1h' and ts >= b.created_at order by ts asc limit 1),0) as ratio
  from base b
),
lignes as (
  select created_at, signal, extrait,
    round(((ratio-1)*100)::numeric, 2) as spy_move_pct,
    case
      when p_sage in ('Macro','Technique','Flash') then
        case when ratio is null or d is null then null
             when (d=1 and (ratio-1)*100 > p_seuil) or (d=-1 and (ratio-1)*100 < -p_seuil) or (d=0 and abs((ratio-1)*100) <= p_seuil) then true
             else false end
      when p_sage = 'Risque' then
        case when ratio is null then null else
          (signal='LOW' and abs((ratio-1)*100) < 1.0) or
          (signal='MEDIUM' and abs((ratio-1)*100) >= 0.3 and abs((ratio-1)*100) < 2.0) or
          (signal='HIGH' and abs((ratio-1)*100) >= 0.8) or
          (signal='EXTREME' and abs((ratio-1)*100) >= 1.5) end
      when p_sage = 'Memoire' then
        (select case when count(*) >= 3 then (count(*) filter (where p.win)) >= 2 else null end
         from oracle_performance p
         where p.archimage in ('JU','SYL','GIL')
           and p.evaluated_at > scored.created_at and p.evaluated_at <= scored.created_at + interval '4 hours')
    end as correct
  from scored
)
select jsonb_build_object(
  'sage', p_sage,
  'evalue', (select count(*) from lignes where correct is not null),
  'corrects', (select count(*) from lignes where correct),
  'taux_reussite', (select round(count(*) filter (where correct) * 100.0 / nullif(count(*) filter (where correct is not null),0), 1) from lignes),
  'historique', (select coalesce(jsonb_agg(to_jsonb(l) order by l.created_at desc), '[]'::jsonb)
                 from (select * from lignes order by created_at desc limit 20) l)
);
$function$



-- FUNCTION: sages_coaching
CREATE OR REPLACE FUNCTION public.sages_coaching()
 RETURNS text
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select coalesce(string_agg(
    s.sage || '=' ||
    case when s.taux_reussite is null then 'sans bilan'
         when s.taux_reussite >= 65 then s.taux_reussite||'pct FIABLE garde ta ligne'
         when s.taux_reussite >= 50 then s.taux_reussite||'pct MOYEN affine'
         else s.taux_reussite||'pct FAIBLE baisse ta conviction et sois prudent'
    end, ' | ' order by s.sage), 'aucun bilan disponible pour le moment')
  from public.evaluate_sages(24,0.5) s;
$function$



-- FUNCTION: sync_alpaca_positions
CREATE OR REPLACE FUNCTION public.sync_alpaca_positions(p_payload jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_archimage text;
  v_position jsonb;
  v_buying_power numeric;
  v_portfolio_value numeric;
  v_current_drawdown numeric;
  v_peak_value numeric;
BEGIN
  v_archimage := p_payload->>'archimage';
  v_buying_power := COALESCE((p_payload->>'buying_power')::numeric, 0);
  v_portfolio_value := COALESCE((p_payload->>'portfolio_value')::numeric, 0);

  -- Calculer drawdown depuis le pic
  SELECT COALESCE(MAX(alpaca_portfolio_value), v_portfolio_value)
  INTO v_peak_value
  FROM oracle_brain_state
  WHERE archimage = v_archimage;

  v_current_drawdown := CASE WHEN v_peak_value > 0 
    THEN GREATEST(0, (v_peak_value - v_portfolio_value) / v_peak_value)
    ELSE 0 END;

  -- Upsert positions live
  IF p_payload->'positions' IS NOT NULL THEN
    -- Marquer les positions existantes comme potentiellement stale
    UPDATE oracle_positions_live
    SET is_stale = true
    WHERE archimage = v_archimage;

    -- Upsert chaque position
    FOR v_position IN SELECT * FROM jsonb_array_elements(p_payload->'positions')
    LOOP
      INSERT INTO oracle_positions_live (
        archimage, ticker, side, qty,
        avg_entry_price, current_price, market_value,
        unrealized_pl, unrealized_pl_pct, cost_basis,
        last_synced, is_stale, consecutive_runs_held
      ) VALUES (
        v_archimage,
        UPPER(v_position->>'symbol'),
        COALESCE(v_position->>'side', 'long'),
        COALESCE((v_position->>'qty')::numeric, 0),
        COALESCE((v_position->>'avg_entry_price')::numeric, 0),
        COALESCE((v_position->>'current_price')::numeric, 0),
        COALESCE((v_position->>'market_value')::numeric, 0),
        COALESCE((v_position->>'unrealized_pl')::numeric, 0),
        COALESCE((v_position->>'unrealized_plpc')::numeric, 0) * 100,
        COALESCE((v_position->>'cost_basis')::numeric, 0),
        now(),
        false,
        1
      )
      ON CONFLICT (archimage, ticker) DO UPDATE SET
        qty = EXCLUDED.qty,
        -- 19/08/2026 : ces 3 colonnes n'etaient jamais mises a jour et restaient figees
        -- a la valeur du premier INSERT (SYL XLF : position de 0,42 $ pour un cost_basis
        -- de 149 497 $ ; JU META marque 'long' avec une quantite de -59).
        side = EXCLUDED.side,
        avg_entry_price = EXCLUDED.avg_entry_price,
        cost_basis = EXCLUDED.cost_basis,
        current_price = EXCLUDED.current_price,
        market_value = EXCLUDED.market_value,
        unrealized_pl = EXCLUDED.unrealized_pl,
        unrealized_pl_pct = EXCLUDED.unrealized_pl_pct,
        last_synced = now(),
        is_stale = false,
        consecutive_runs_held = oracle_positions_live.consecutive_runs_held + 1,
        days_held = EXTRACT(DAY FROM (now() - oracle_positions_live.opened_at))::integer;
    END LOOP;

    -- SUPPRIMER les positions fermées (marquées stale = absentes du broker ce run) au lieu de les
    -- laisser en "zombie" (qty=0). Garde anti-wipe : on ne purge QUE si le broker a renvoyé >= 1
    -- position (sinon une réponse vide/erreur effacerait tout le portefeuille à tort). [17/08]
    IF COALESCE(jsonb_array_length(p_payload->'positions'), 0) > 0 THEN
      DELETE FROM oracle_positions_live
      WHERE archimage = v_archimage AND is_stale = true;
    END IF;
  END IF;

  -- Mettre à jour brain_state avec données Alpaca live
  UPDATE oracle_brain_state SET
    alpaca_buying_power = v_buying_power,
    alpaca_portfolio_value = v_portfolio_value,
    alpaca_last_synced = now(),
    alpaca_drawdown_from_peak = v_current_drawdown,
    -- Recalculer kelly si nécessaire (winrate * avgWin - (1-winrate) * avgLoss) / avgWin * 0.25
    kelly_fraction = CASE 
      WHEN total_runs >= 5 AND COALESCE(avg_win_pct, 0) > 0 AND COALESCE(avg_loss_pct, 0) > 0
      THEN GREATEST(0.02, LEAST(0.5,
        (win_rate * avg_win_pct - (1 - win_rate) * avg_loss_pct) / GREATEST(avg_win_pct, 0.01) * 0.25
      ))
      ELSE 0.05 -- Kelly conservateur par défaut
    END,
    kelly_last_computed = now()
  WHERE archimage = v_archimage;

  RETURN jsonb_build_object(
    'success', true,
    'archimage', v_archimage,
    'buying_power', v_buying_power,
    'portfolio_value', v_portfolio_value,
    'drawdown', ROUND(v_current_drawdown * 100, 2),
    'positions_synced', COALESCE(jsonb_array_length(p_payload->'positions'), 0)
  );

EXCEPTION WHEN OTHERS THEN
  RETURN jsonb_build_object('success', false, 'error', SQLERRM);
END;
$function$



-- FUNCTION: trg_set_run_order_counts
CREATE OR REPLACE FUNCTION public.trg_set_run_order_counts()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  h record;
begin
  if coalesce(new.orders_count,0) = 0 then
    select count(*),
           count(*) filter (where broker_status in ('filled','partially_filled','accepted','pending_new','new')),
           count(*) filter (where lower(side)='buy'),
           count(*) filter (where lower(side)='sell')
      into new.orders_count, new.orders_executed, new.orders_buy, new.orders_sell
      from public.oracle_college_orders
      where created_at > now() - interval '3 hours';
  end if;

  -- Flags de sources depuis les derniers rapports de santé (20 min)
  select
    bool_or(source_name = 'fred' and status = 'ok') as fred_ok,
    bool_or(source_name = 'finnhub_spy' and status = 'ok') as spy_ok,
    bool_or(source_name = 'perplexity_news' and status = 'ok') as news_ok,
    bool_or(source_name = 'alpaca_screener' and status = 'ok') as screener_ok
    into h
  from public.oracle_datasource_health
  where checked_at > now() - interval '20 minutes';

  if h is not null then
    new.fred_series_ok  := coalesce(h.fred_ok, new.fred_series_ok);
    new.polygon_ok      := coalesce(h.spy_ok, new.polygon_ok);
    new.newsapi_ok      := coalesce(h.news_ok, new.newsapi_ok);
    new.options_flow_ok := coalesce(h.screener_ok, new.options_flow_ok);
  end if;

  return new;
end $function$



-- FUNCTION: try_jsonb
CREATE OR REPLACE FUNCTION public.try_jsonb(t text)
 RETURNS jsonb
 LANGUAGE plpgsql
 IMMUTABLE
 SET search_path TO 'public'
AS $function$
begin return t::jsonb; exception when others then return jsonb_build_object('contenu', t); end; $function$



-- FUNCTION: update_archimage_performance
CREATE OR REPLACE FUNCTION public.update_archimage_performance(p_archimage text, p_run_id text, p_pnl numeric, p_orders_count integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_brain oracle_brain_state%ROWTYPE;
  v_new_wins integer;
  v_new_losses integer;
  v_new_consec_wins integer;
  v_new_consec_losses integer;
BEGIN
  SELECT * INTO v_brain FROM oracle_brain_state WHERE archimage = p_archimage;

  -- Calculer win/loss
  IF p_pnl > 0 THEN
    v_new_wins := v_brain.wins + 1;
    v_new_losses := v_brain.losses;
    v_new_consec_wins := v_brain.consecutive_wins + 1;
    v_new_consec_losses := 0;
  ELSE
    v_new_wins := v_brain.wins;
    v_new_losses := v_brain.losses + 1;
    v_new_consec_wins := 0;
    v_new_consec_losses := v_brain.consecutive_losses + 1;
  END IF;

  UPDATE oracle_brain_state SET
    total_runs = total_runs + 1,
    wins = v_new_wins,
    losses = v_new_losses,
    win_rate = ROUND(v_new_wins::numeric / GREATEST(v_new_wins + v_new_losses, 1), 3),
    cumulative_pnl = cumulative_pnl + p_pnl,
    consecutive_wins = v_new_consec_wins,
    consecutive_losses = v_new_consec_losses,
    max_consecutive_wins = GREATEST(v_brain.max_consecutive_wins, v_new_consec_wins),
    current_streak_type = CASE WHEN p_pnl > 0 THEN 'win' ELSE 'loss' END,
    last_run_at = now(),
    last_run_id = p_run_id,
    updated_at = now()
  WHERE archimage = p_archimage;

  RETURN jsonb_build_object('success', true, 'archimage', p_archimage, 'win_rate', 
    ROUND(v_new_wins::numeric / GREATEST(v_new_wins + v_new_losses, 1), 3));

EXCEPTION WHEN OTHERS THEN
  RETURN jsonb_build_object('success', false, 'error', SQLERRM);
END;
$function$



-- FUNCTION: update_updated_at
CREATE OR REPLACE FUNCTION public.update_updated_at()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public'
AS $function$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$function$



-- FUNCTION: upsert_college_run
CREATE OR REPLACE FUNCTION public.upsert_college_run(p_payload jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_run_id text;
BEGIN
  v_run_id := NULLIF(TRIM(COALESCE(p_payload->>'run_id', '')), '');
  IF v_run_id IS NULL THEN
    v_run_id := 'COLLEGE-' || to_char(now(), 'YYYYMMDD-HH24MI-US');
  END IF;

  INSERT INTO oracle_college_runs (
    run_id, run_at, status, market_phase, data_completeness,
    claude_confidence, perplexity_confidence, mistral_confidence,
    orders_count, orders_executed, slack_title, slack_sent
  ) VALUES (
    v_run_id,
    now(),
    COALESCE(p_payload->>'status', 'success'),
    COALESCE(p_payload->>'market_phase', 'NEUTRAL'),
    COALESCE((p_payload->>'data_completeness')::int, 0),
    COALESCE((p_payload->>'claude_confidence')::int, 0),
    COALESCE((p_payload->>'perplexity_confidence')::int, 0),
    COALESCE((p_payload->>'mistral_confidence')::int, 0),
    COALESCE((p_payload->>'orders_count')::int, 0),
    COALESCE((p_payload->>'orders_executed')::int, 0),
    p_payload->>'slack_title',
    true
  )
  ON CONFLICT (run_id) WHERE run_id IS NOT NULL AND run_id <> ''
  DO UPDATE SET
    status            = EXCLUDED.status,
    data_completeness = EXCLUDED.data_completeness,
    orders_executed   = EXCLUDED.orders_executed,
    slack_sent        = true;

  RETURN jsonb_build_object('success', true, 'run_id', v_run_id);
EXCEPTION WHEN OTHERS THEN
  RETURN jsonb_build_object('success', false, 'error', SQLERRM, 'run_id', v_run_id);
END;
$function$

