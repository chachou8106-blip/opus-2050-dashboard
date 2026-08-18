# Journal des changements & décisions — AETHER / OPUS 2050

> Historique des choix, corrections, améliorations et analyses. Sert de mémoire longue pour le suivi
> sur plusieurs mois. Ajouter une entrée **datée** à chaque changement significatif (décision, fix,
> amélioration, analyse). Le détail de certains sujets vit dans `docs/decisions/`.

Format : `AAAA-MM-JJ` — **Sujet** — quoi + pourquoi + où.

---

## 2026-08-18

- **FIX modèle de déclenchement : `/run` → `/start` + `/stop` différé (jeton Aether posé, testé bout-en-bout).**
  Le jeton API Make (clé **Aether**) a été mis en Vault par Chachou + zone `eu1` en base. Test : `POST
  /scenarios/{id}/run` renvoie **422 « Scenario is not activated » (IM325)** — l'endpoint « run once » exige
  un scénario ACTIF. Découverte (vérifiée via `executions_list`) : `POST /scenarios/{id}/start` **active ET
  déclenche 1 exécution immédiate** (~3 s après). Et `POST …/stop` **pendant** une exécution **ne la tue pas**
  (le run 07:50→07:53 a fini `status:1` malgré un /stop à 07:51). **Nouveau modèle** : à chaque slot (et pour
  « Lancer maintenant ») → `/start` (= 1 run), puis `/stop` **3 min après** (avant le +3600s interne) pour
  qu'il ne reste **qu'un seul run**. Implémenté dans `scenario_fire()` (colonne `scenario_control.pending_stop_at`,
  le cron 5 min applique le /stop en attente même maître OFF) + `scenario_stop_now()` (coupe immédiate de
  sécurité, appelée par le bouton **Couper**). `v_scenario_etat` détecte le jeton sous `make_api_token` **ou**
  `Aether` (`api_configuree=true`). Edge `scenario-switch` **v3**. Testé bout-en-bout : `scenario_fire(true)`
  → `/start` HTTP 200 `isActive:true`, run déclenché, `pending_stop_at` posé (+3 min). Cron `scenario_fire_5min`
  actif (`*/5`). **Maître toujours OFF par défaut** (aucun run tant que Chachou n'a pas cliqué « Activer »).

- **Planning multi-marchés + bouton ON/OFF console — 100% Supabase, AUCUNE modif Make.** Constat (vérifié) :
  le scénario a déjà un planning interne horaire (`interval:3600`) mais reste `isActive:false` → activé à la
  main = runs irréguliers, données polluées. Sur demande de Chachou (« rien sur Make, un bouton par sécurité,
  décide le planning ») : Supabase **active/désactive** le scénario aux heures de marché via l'**API Make**
  (start/stop = même effet que le toggle Make, sans toucher interval ni modules). DDL
  `supabase/schema/14_scenario_scheduler.sql` : `scenario_control` (interrupteur maître), `scenario_schedule`
  (fenêtres data-driven, seed **Lun-Ven 8h→22h Paris** = forex Londres + session US + crypto ; extensible
  Darwinex 24/5 + crypto week-end en 1 INSERT), `scenario_reconcile()` (appelle l'API Make au changement
  d'état), vue `v_scenario_etat`. Edge function **`scenario-switch`** (PIN `arm_pin`) + **bouton dans la zone
  Face ID de la console** (Activer / Couper, état live). Testé : `status` → HTTP 200. **Défaut OFF** (rien ne
  tourne). **Reste à fournir** : un **jeton API Make** (Vault `make_api_token`) + la **zone** (`make_zone`,
  ex eu2) pour que le pilotage agisse réellement — d'ici là le bouton mémorise l'état sans toucher Make
  (`api_configuree=false` affiché). Le cron 10 min de réconciliation est prêt (à activer une fois le jeton posé).

- **RÉVISION planning : 4 runs/jour à heures fixes (coût), au lieu d'horaire.** Chachou (à raison, coût) : pas
  toutes les heures — régulier, 3-4×/jour. **Nouveau modèle** : le scénario reste DÉSACTIVÉ ; Supabase
  déclenche **exactement N runs via l'API Make « run once »** (`POST /scenarios/{id}/run`) aux heures prévues.
  Remplace le modèle fenêtre+start/stop. Table `scenario_runs_planifies` (seed **Lun-Ven 09h00 · 15h45 ·
  18h30 · 21h15 Paris**), fonction `scenario_fire(force)`, cron **5 min** (grâce 30 min). Bouton console :
  **Activer le planning / Couper / ⚡ Lancer maintenant** (PIN). `scenario-switch` v2. OFF par défaut ; jeton
  API Make + zone toujours à fournir.

## 2026-08-17

- **NETTOYAGE des redondances + règle « vérifier avant d'ajouter » (demandée par Chachou).** Chachou signale
  à juste titre que j'avais ajouté une table (`alchimiste_crypte_verdicts`) + un module Make (20024) + 2 vues
  staking alors que TOUT existait déjà. Correctifs : (1) **règle inscrite** dans `CLAUDE.md` — toujours
  vérifier l'existant (Supabase + blueprint Make) avant d'affirmer une absence ou de créer un objet ; ne pas
  faire ajouter de module Make sans avoir confirmé qu'aucun existant ne fait le travail. (2) **Supprimé** :
  table `alchimiste_crypte_verdicts`, fonction `log_alc_verdict`, vue `v_alc_verdict_dernier`, fichiers
  `13_alc_verdict_log.sql` + prompt de log (le dé-stake est déjà journalisé dans `alc_destake_reco` par la
  RPC existante `alc_record_propositions`). Module Make **20024 « LE VERDICT SCELLÉ » à retirer** (prompt Maia).
  (3) **Staking reconnecté sur l'existant** : les 2 vues texte projettent désormais la vue EXISTANTE
  `v_staking_point` (déjà apy_pct + unbonding_jours + coût, coins détenus). Fix mapping VÉRIFIÉ (REST 200) :
  modules 20022/20023 avec en-tête `Accept: application/vnd.pgrst.object+json` → mapping Alchimiste
  `20022.data.delais_texte` / `20023.data.apy_texte` (sans `[1]`, qui ne se résolvait pas). Objet renvoyé :
  `{"delais_texte":"ATOM:21j | … | TON:2j | …"}`. `supabase/schema/12_alc_staking_text.sql` mis à jour.

- **Alchimiste — le dé-stake était DÉJÀ loggé (`alc_destake_reco`) ; diagnostic « aucune reco » = correct.**
  En cherchant pourquoi le journal `alchimiste_crypte_verdicts` restait vide (module Make 20024 n'a pas
  écrit — la RPC `log_alc_verdict` est pourtant OK, testée en REST 200), découverte que la RPC EXISTANTE
  `alc_record_propositions` (appelée chaque run par « Le Registre de Cristal ») écrit déjà le dé-stake dans
  **`alc_destake_reco`** (devise, apy, délai, verdict, raison). Preuve par les données : run 20:12 (pré-fix)
  = raisons « tables encodées vides / données absentes » (aveugle) ; run 22:00 (post-fix) = 7 coins évalués,
  **verdict GARDER pour tous**, plus aucune mention d'aveuglement → « aucune reco de dé-stake » = « tout
  garder staké » = CORRECT. **Réserve** : les valeurs APY/délai de son raisonnement au 22:00 restent estimées
  (TON 5% vs réel 17.67% ; TRX 3j vs réel 14j) → les CHIFFRES staking ne lui parviennent probablement pas
  encore (mapping `[1]`), même s'il n'est plus totalement aveugle (prix OK). Pas urgent (APY réels plus élevés
  → GARDER encore plus justifié), fix Make à préparer. **Vigie** : sonde « Alchimiste verdict » repointée sur
  `alc_destake_reco` (fiable), test d'aveuglement scopé au **dernier batch** uniquement (un run pré-fix dans
  la fenêtre donnait un faux positif PANNE, corrigé → OK). `alchimiste_crypte_verdicts`/`log_alc_verdict`
  conservés (le module 20024 est redondant avec `alc_destake_reco` ; il peut être retiré).

- **LA VIGIE — 2 sondes ajoutées pour « ce genre de problème » (aveuglement Alchimiste).** À la demande de
  Chachou, la Vigie surveille désormais 13 composants (au lieu de 11). (1) **Alchimiste verdict** : lit le
  dernier verdict loggué (`alchimiste_crypte_verdicts`) — PANNE si `parse_ok=false` (sortie illisible) ou si
  le commentaire contient des marqueurs d'aveuglement (« faute de données », « encodées vides », « données
  manquantes », « faute de prix/APY »…) ; VEILLE tant que le module Make de log n'est pas ajouté (pas de
  fausse alerte). (2) **Données staking** (catégorie Source) : vérifie en direct que `v_alc_staking_apy_txt`
  / `v_alc_staking_delais_txt` renvoient du contenu → PANNE immédiate si une table se vide. Ces PANNE
  déclenchent aussi l'alerte Discord existante. `supabase/schema/11_vigie.sql` mis à jour.

- **Journal du verdict de l'Alchimiste (comble l'angle mort du raisonnement).** Constat : le `commentaire`
  et la liste `destake_recommande` de l'Alchimiste n'étaient stockés nulle part → impossible de savoir
  après coup POURQUOI il dé-stake ou non (ex. « aucune reco de dé-stake » ce soir = verdict légitime
  « garder staké », mais invérifiable). Côté Supabase (fait, testé) : table `alchimiste_crypte_verdicts`,
  RPC `log_alc_verdict(p_run_id, p_raw_b64)` qui reçoit la sortie BRUTE de l'Alchimiste en base64, la
  décode + parse côté serveur (pas de `toString` cassant) et extrait commentaire / destake / nb propositions,
  vue `v_alc_verdict_dernier`. Côté Make (prompt Maia, `docs/decisions/PROMPT-MAIA-LOG-VERDICT-ALCHIMISTE-2026-08-17.md`) :
  ajouter 1 module HTTP POST après l'Alchimiste appelant la RPC avec
  `base64(10012.data.choices[1].message.content)`. DDL : `supabase/schema/13_alc_verdict_log.sql`.
  À suivre (optionnel) : affichage dans la zone privée console + intégration Vigie. NB diagnostic du soir :
  le « plus aucune reco de dé-stake » est cohérent (APY TON/GRAM 17.67% déblocable en 2j + marché neutre +
  2.52 USD de cash → garder staké est rationnel) ; ce log permettra de le CONFIRMER au prochain run.

- **Alchimiste « ne voit ni prix ni staking » — bug de mapping Make (pas les données).** Chachou constate
  que l'Alchimiste écrit « faute de données de prix, d'APY et de délais (tables encodées vides) ». Vérifié
  (pas supposé) : les données EXISTENT — `revolut-x-prices` répond **HTTP 200** avec `prix_texte`
  (BTC/DOGE/XLM/TON/TRU…), et `alc_staking_apy` / `alc_staking_delais` ont **8 lignes** chacune. Cause :
  les 3 feeds sont mappés `base64(toString(<module>.data))` où `.data` est un OBJET/ARRAY → `toString`
  rend une chaîne vide → l'Alchimiste décode du vide. Correctif : lui donner les champs TEXTE prêts.
  Côté Supabase (fait, additif, lecture seule) : 2 vues `v_alc_staking_apy_txt(apy_texte)` /
  `v_alc_staking_delais_txt(delais_texte)` (chaînes « DEV:val | … »), testées via REST (200). Côté Make
  (prompt Maia, `docs/decisions/PROMPT-MAIA-ALCHIMISTE-PRIX-2026-08-17.md`) : 3 fixes — prix
  `base64(10011.data.prix_texte)`, staking APY/délais repointés sur les vues + mapping `.data[1].<txt>`.
  `revx-staking-probe`/tables déjà OK ; le CTX/SAGES/AVIS_GIL (autre base64, corrigé le 16-17/08) n'était
  PAS en cause ici. DDL : `supabase/schema/12_alc_staking_text.sql`.

- **🔭 LA VIGIE — couche de surveillance santé du Collège (pour que la panne muette ne se reproduise plus).**
  Constat de Chachou : aucun tableau de bord n'a signalé que 4 Sages étaient morts pendant 3 jours ni que
  Risque tournait en boucle. Nouvelle couche **100 % Supabase** (`supabase/schema/11_vigie.sql`), sûre
  (lecture seule sur les tables métier, aucun objet existant modifié, ne touche NI trading NI kill_switch
  NI dry_run NI Make). Principe : on ne teste pas « l'API répond ? » mais **« le run a tourné — chaque
  composant a-t-il produit sa sortie ? »** → un composant absent = anomalie certaine quelle qu'en soit la
  cause (modèle décommissionné, **crédit API vide**, rate-limit, bug, réseau) : détection par ABSENCE =
  filet universel. Objets : table `vigie_status`, fonction `vigie_scan()` (pg_cron toutes les 15 min,
  job #27), vues `v_vigie_resume` (bannière) + `v_vigie_detail`. Surveille 11 composants : 5 Sages
  (présence + **anti-stagnation** sur macro_regime/cycle_phase/risk_level/best_archimage/urgency_level),
  3 Archimages (via claude/perplexity/mistral_confidence du run), 2 Traders (Alchimiste/Marées, fraîcheur
  souple), + signal `market_phase`. États : OK / PANNE / FIGE / MUET / VEILLE. Garde-fous anti-faux-positif :
  **VEILLE** si dernier run > 2h30 (week-end/scénario coupé → pas d'alarme) ; garde de **récence** (stagnation
  jugée seulement si les 6 runs sont < 12h, pour ne pas cataloguer FIGÉ un Sage qui vient de ressusciter).
  Exposé par `oracle-inbox` **v18** (bloc `vigie`) + **bannière console** en tête de page (verte/orange/rouge,
  dépliable, liste les composants). Dès le 1er scan, LA VIGIE a correctement remonté la vraie stagnation
  `market_phase=DEFENSIVE` (à investiguer côté GIL/synthèse). NB sur le « suivi des sous API » : la plupart
  des API LLM n'exposent pas le solde ; la détection par absence couvre de toute façon l'épuisement de crédit.
  Extensions possibles (non faites, sur décision) : capture des en-têtes rate-limit Groq, rappel hebdo de recharge.

- **🔔 LA VIGIE — alerte Discord (activée).** À la demande de Chachou. Notification **côté Supabase**
  (`pg_net`), donc **indépendante de Make** : une alerte part même si tout le scénario est mort. Webhook
  Discord (canal Héraut, récupéré du module existant) stocké dans **Supabase Vault** (`vigie_discord_webhook`),
  jamais en git. Fonction `vigie_alert()` (table `vigie_alert_state`), lancée par le cron après `vigie_scan`
  (`select public.vigie_scan(); select public.vigie_alert();`). N'alerte que sur les **transitions** (pas en
  boucle) : PANNE = urgent (alerte à la bascule + rappel toutes les 6h tant que non résolu), FIGE/MUET =
  advisory (une alerte), rétablissement bad→OK = message vert ; VEILLE/OK silencieux. Amorçage sur l'état
  courant pour ne notifier que les changements futurs (pas de blast sur le market_phase déjà connu). Plomberie
  validée de bout en bout : `net.http_post` → Discord **HTTP 204** (message de test reçu).

- **RÉSOLU & VÉRIFIÉ EN PROD (run 19:59) — les 5 Sages écrivent enfin tous ensemble.** Après le correctif #2
  appliqué par Maia (Macro→json_schema+max_tokens 1500 ; Technique & Mémoire→reasoning_effort low+max_tokens
  2000), le run de 19:59 a inscrit dans `oracle_sages_report` les **5 Sages** simultanément pour la 1re fois
  depuis le 15/08 : Macro (Perplexity), Technique (Groq gpt-oss-120b), Mémoire (Groq gpt-oss-120b), Flash
  (Perplexity), Risque (Mistral). Signaux **non figés** : Risque est passé de « VIX 18→MEDIUM » (19:33) à
  « VIX sous 15→complaisant » (19:59) — il suit réellement le marché ; Mémoire ressort des win rates par
  archimage (JU 49 / GIL 51 / SYL 54) ; Technique lit le cycle (TROUGH, tech_score 65). Diversification
  fournisseurs actée : Perplexity ×2, Groq ×2, Mistral ×1 → plus de point de panne unique (cause racine du 15/08).

- **Correctif #2 des Sages (run 19:33 en 400 silencieux).** Après le basculement de fournisseur (via Maia),
  le transport était bon mais 2 Sages renvoyaient un **400 masqué par `stopOnHttpError=false`** (Maia a
  faussement rapporté « success » en lisant le statut vert des modules, pas le body — même piège que le
  bug d'origine). Diagnostic sur les bodies du run : (1) **Macro/Perplexity** → 400 `response_format.type
  must be one of json_schema, text, got json_object` : Perplexity refuse `json_object` (Flash marche car
  il utilise `json_schema`). (2) **Technique/Groq gpt-oss-120b** → 400 `max completion tokens reached` :
  gpt-oss est un modèle de raisonnement, `max_tokens=800` (hérité de Llama) trop court. (3) **Mémoire/Groq**
  → même config, même risque. Risque/Mistral et Flash/Perplexity : OK, on n'y touche pas. **Prompt de
  correction préparé** (`docs/decisions/PROMPT-MAIA-SAGES-FIX2-2026-08-17.md`) : Macro → `response_format`
  json_schema complet + max_tokens 1500 ; Technique & Mémoire → `reasoning_effort:"low"` + max_tokens 2000.
  Rappel : valider par le BODY (status 200, `choices[0].message.content`) et `oracle_sages_report`, jamais
  par le statut vert des modules Make.

- **DIAGNOSTIC CRITIQUE — 4 Sages muets depuis le 15/08 (modèle Groq décommissionné).** Question de
  Chachou : « Risque écrit-il ailleurs ? sinon prépare un prompt Maia et vérifie les autres sages. »
  Traçage complet dans Make + Supabase : Risque n'écrit **nulle part ailleurs**. Il est censé écrire
  dans `oracle_sages_report` via le module « 📜 LE SCEAU DES SAGES » (RPC `record_sages`, qui envoie
  les 5 Sages en base64). Constat base : **depuis le 15/08 12h36, seul Flash y écrit** ; Macro,
  Technique, Risque, Mémoire ont cessé. Cause racine : ces **4 Sages tournent sur Groq**
  (`llama-3.3-70b-versatile`), modèle **décommissionné par Groq** (annonce 17/06/2026). Comme
  `stopOnHttpError=False`, l'erreur passe en silence → réponse sans `choices[]` → contenu vide → le
  SCEAU n'insère rien pour ces 4 Sages. **Aucun Archimage n'utilise Groq** (JU=Anthropic,
  SYL=Perplexity, GIL=Mistral) ni Flash (Perplexity `sonar-pro`) — d'où le motif exact observé : ces
  seuls 4 Sages éteints, tout le reste marche. Conséquence de fond : « Risque dit toujours la même
  chose » = Risque ne dit **rien** (le Conseil retombe sur des défauts : `market_phase` figé DEFENSIVE,
  `consensus_level` vide). Le correctif temp 0.3 posé plus tôt est réel mais **inopérant tant que le
  modèle est mort**. **Fix préparé pour Maia** (`docs/decisions/PROMPT-MAIA-SAGES-GROQ-2026-08-17.md`) :
  remplacer `"model": "llama-3.3-70b-versatile"` → `"model": "openai/gpt-oss-120b"` (remplacement
  officiel Groq, compatible OpenAI → mapping `choices[].message.content` inchangé) dans les 4 modules
  Groq (AURORA BOREALIS / STELLAR NAVIGATOR / IRON SENTINEL / DEEP MEMORY), sans rien toucher d'autre.
  Leçon d'observabilité : `stopOnHttpError=False` masque les pannes LLM → surveiller les trous dans
  `oracle_sages_report` comme signal d'alerte.

- **Alchimiste RÉEL (Revolut X) valorisé en direct — même principe que le virtuel.** Le portefeuille
  réel n'était valorisé qu'une fois par jour (`revolut_portfolio_daily`, écrit à 8h par
  `revolut-portfolio-summary`). Deux vues **100 % lecture** `v_alc_reel_live_positions` /
  `v_alc_reel_live_resume` reprennent le dernier snapshot (quantités par coin dans `detail`) et
  revalorisent chaque ligne au dernier cours de `price_history` (alimenté 24/7). Couverture **47/49
  coins + 2 cash ≈ 100 %**. Exposé par `oracle-inbox` **v17** (`suivi.alc_reel_live`) + sous-bloc
  console « 🜍 Alchimiste réel — Revolut X » dans la section « Crypto en direct » (valeur live, en €,
  écart depuis 8h, lignes live). Aucun ordre, aucune écriture, ne touche NI au kill-switch NI au
  dry_run. NB : le virtuel était **déjà** live (`v_alc_virtuel_positions` via `v_dernier_prix`).
  DDL : `supabase/schema/09_alc_reel_live.sql`.
- **SYL — soldage de la crypto hors univers (FAIT) + verrou anti-récidive.** Constat de Chachou : SYL
  (« Macro internationale / paniers ETF ») portait ~226 k$ de crypto spot (ETH/SOL/LINK/BTC/AVAX/DOGE),
  qui relève de GIL. Diagnostic (lecture prompt + code) : **positions LEGACY** — tenues **190 runs**
  sans être touchées, antérieures aux règles de spécialisation. Le prompt SYL **interdisait déjà** la
  crypto et `execute-trades` bloquait tout **ACHAT** crypto hors GIL (`CRYPTO_EXCLUSIF_GIL`, garde
  `if(isBuy)`), mais **pas les ventes** → rien ne les soldait et le prompt (« ne trade pas hors
  univers ») dissuadait SYL d'en proposer la vente. **Action (17/08, sur décision de Chachou) :**
  **liquidation immédiate** des 6 lignes via l'API Alpaca (`DELETE /v2/positions/{symbol}` par pg_net,
  chirurgical — n'a touché qu'elles, pas d'effet de bord de `execute-trades`). Résultat : **0 crypto
  restante** chez SYL (31 positions ETF/actions), produit repassé en cash USD ; lignes mortes purgées
  de `oracle_positions_live`. **Verrou durable** : `execute-trades` **v35** — la crypto est le domaine
  **EXCLUSIF de GIL dans les deux sens** (non-GIL ne peut plus ACHETER de crypto ; GIL ne peut
  ACHETER/shorter QUE de la crypto, remplace l'ancienne restriction SPY/QQQ). Les **ventes restent
  libres** (débouclage). **Rappel : SYL est en paper.** ⚠️ Reste ouvert (hors sujet ici) : le bug du
  stop DB −5 % non appliqué (seul le seuil live TP 35 % / SL 15 % agit).

- **Audit spécialité du collège + correctif GIL (revert verrou).** Contrôle des 3 comptes Alpaca :
  drift hors-univers **systémique**. **GIL** : ne détient quasi **aucune crypto** ($0,03) mais un gros
  livre actions/ETF (~169 k$ net, brut >1 M$ : MSTR short 441 k$, XLU, TLT, TQQQ short…). Analyse
  legacy-vs-prompt : **ce n'est PAS du legacy** — le **prompt actuel** de GIL est
  `CRYPTO_TACTICAL_DERIVATIVES` et l'autorise explicitement (proxies MSTR/COIN/BITO, ETF tactiques
  SQQQ/TQQQ/UPRO, vol VXX/UVXY, défensifs XLU/XLP, shorts contrarian vs JU/SYL) ; ses ordres récents
  (10-14/08) sont MSTR/TQQQ/XLU, 0 crypto. **Décision de Chachou : garder ce rôle large.** →
  **`execute-trades` v36 : REVERT du volet « GIL crypto-only » de v35** (qui bloquait à tort ses
  instruments). On CONSERVE l'interdiction de crypto pour les non-GIL (déjà en v34). **JU/SYL** : leurs
  prompts, eux, **interdisent** le hors-univers (SYL : pas de single stocks ; JU : pas d'ETF) → leurs
  débordements (NVDA/AMD chez SYL, XLU short chez JU) sont à analyser séparément (legacy vs
  désobéissance) avant tout soldage. Analyse en cours.
- **Soldage du legacy hors-univers de JU et SYL + verrou actions/ETF (v37).** Suite à l'audit :
  analyse legacy-vs-prompt confirmée — sur 10 jours, **JU ne propose que des actions**, **SYL que des
  ETF** (leurs prompts interdisent le hors-univers). Leurs positions hors-voie sont donc du **legacy
  inerte**. **Action (sur décision de Chachou, 17/08)** : liquidation chirurgicale via l'API Alpaca —
  **JU : 18 ETF** (dont **XLU short 318 k$** racheté, TLT, IEF, HYG, GLD, XLV, XLP, SCHD, USO…),
  **SYL : 9 actions** (NVDA 277 k$, AMD 123 k$, MSFT, LLY, COST, GS, META, V, UNH). Marché fermé au
  moment de l'ordre → 27 `DELETE /v2/positions` **acceptés et mis en file**, exécution à l'ouverture
  (13:30 UTC). **Verrou durable** : `execute-trades` **v37** — liste `ETF_REF` + règles : **JU** ne
  peut plus ACHETER d'ETF, **SYL** plus d'action individuelle ; **GIL EXEMPTÉ** (univers large). Ventes
  libres. NB : paper. `oracle_positions_live` sera nettoyé après exécution (réconciliation Make ou
  manuelle).
- **Prompt Maia rédigé — 3 correctifs (Alchimiste aveugle au Conseil + Sages Flash/Risque figés).**
  Vérifié mot à mot dans le Blueprint : (1) l'Alchimiste reçoit **CTX / SAGES / avis de GIL en base64**
  (le modèle ne les décode pas → aveugle au Conseil), alors que les 3 archimages les reçoivent en clair
  (`CTX={{CTX}}|SAGES={{SAGES}}`) → correctif = passer l'Alchimiste en clair comme eux (zéro risque). (2)
  **Sage Risque (IRON SENTINEL)** bloqué sur MEDIUM : seuils `risk_level` qui se chevauchent (LOW<1% /
  MEDIUM 0,3-2% / HIGH≥0,8% / EXTREME≥1,5%) + `temperature=0.01` déterministe + VIX stable ~17. (3)
  **Sage Flash (QUANTUM PULSE)** figé par `temperature=0.01`. Prompt Maia (bornes exclusives, prédiction
  du move via momentum/catalyseurs, temp 0.01→0.3) : `docs/decisions/PROMPT-MAIA-CORRECTIFS-2026-08-17.md`.
  À coller à Maia (aucune modif Make directe de notre côté).
- **Alchimiste virtuel : bug de simulation corrigé (le `sell` était shorté).** Constat de Chachou : le
  virtuel affichait des résultats « pourris » (WR 33 %, cumul **−10,5 %**). Cause trouvée dans
  `alc_rebuild_virtual` : il modélisait chaque **vente comme l'ouverture d'un SHORT** (tp=prix×0.95,
  sl=prix×1.04, pnl=1−close/entrée). Or l'Alchimiste est **SPOT** (Revolut X, pas de short) : un `sell`
  = vente d'un actif détenu pour prendre son profit. Conséquence : toute vente-profit correcte était
  comptée en perte dès que le prix remontait. **~90 % du −10,5 % venait de 10 ventes de coins hérités
  shortées à tort.** Correctif (A+B) : **modèle SPOT FIFO** — un BUY ouvre un lot long ; un SELL clôture
  le lot d'achat le plus ancien (FIFO) et réalise le vrai gain spot ; une vente sans achat virtuel
  correspondant (coin hérité) = `VENTE_LEGACY`, **hors P&L**. Vues `v_alc_virtuel_jour/_resume` mises à
  jour (ne comptent que `pnl_pct IS NOT NULL`). Après rejeu : **3 trades scorables**, WR 33 %, cumul
  −9,7 % — dominé par **UN** mauvais achat (TRU micro-cap **−13 %**, ce que son prompt déconseille
  justement), AVAX +4,6 % gagnant, reste ~neutre. Le virtuel n'était donc pas « idiot » : c'était le
  simulateur qui mesurait faux. DDL : `supabase/schema/10_alc_virtuel_spot_fix.sql`.
- **Diagnostic Alchimiste réel : désarmé (kill_switch OFF), pas « catastrophe ».** Vérifié : le prompt
  actuel (maj 16/08) est sain (déconseille micro-caps, exige poudre sèche, TP/SL corrects, spot only,
  reçoit CTX+SAGES+AVIS_GIL). L'exécuteur `alc-auto` n'arme QUE si `kill_switch='on'` — il est à `OFF`
  → **0 trade réel exécuté** (4 mini-ordres le 13/08, dont le TRU 25$ annulé pour illiquidité). Le
  portefeuille de 49 coins est **hérité/manuel**, son érosion = marché, pas le bot. Armement = décision
  de Chachou (jamais touché ici).
- **`sync_alpaca_positions` : purge des positions fermées (fini les zombies).** Cause identifiée du
  nettoyage manuel : la synchro des positions Alpaca (JU/SYL/GIL) ne **supprimait jamais** une position
  fermée — elle la passait juste à `qty=0`+`is_stale` (et encore, après 1 h), laissant des lignes
  « zombie » (d'où le compteur « 190 runs » de la crypto SYL). Correctif : elle **DELETE** désormais les
  positions absentes du broker à chaque run, avec **garde anti-wipe** (ne purge que si le broker renvoie
  ≥1 position, pour ne pas tout effacer sur une réponse vide/erreur). Vérifié : **Alchimiste** (snapshots
  complets `revolut_portfolio_daily`) et **Marées/Alchimiste virtuel** (`TRUNCATE`+rebuild) étaient déjà
  propres — le souci ne concernait que les 3 comptes Alpaca.
- **Contrôle final du soldage + base nettoyée + fiches console corrigées.** À l'ouverture US, les 27
  ordres se sont exécutés : **JU = 100 % actions** (0 ETF), **SYL = 100 % ETF** (0 action, 0 crypto),
  **GIL** inchangé (rôle large). Bonus : annulé un **ordre XRP/USD (crypto) périmé** qui traînait sur
  SYL depuis le 07/06 (aurait pu réintroduire de la crypto). `oracle_positions_live` nettoyé (18 lignes
  JU + 9 SYL + résidus périmés) → base alignée sur la réalité. **Console corrigée** (les descriptions
  ne collaient plus) : SYL « Macro Internationale » → **« Paniers ETF »** ; GIL « Crypto Tactique » →
  **« Tactique Contrarian »** (univers large : crypto + proxies + couvertures actions/ETF à contre-pied) ;
  JU précisé « actions individuelles » ; Alchimiste précisé « au comptant, argent réel » ; « Le concept »
  réécrit (4 spécialistes + 1 contrarian). Modèle final : **JU actions · SYL ETF · Alchimiste crypto
  réelle · Marées forex · GIL polyvalent contrarian**.
- **Console « Crypto en direct » (valorisation 24/7, week-end compris).** Constat de Chachou :
  le week-end, sans faire tourner le scénario Make, la console reste figée. Diagnostic : ce ne sont
  **pas les cours** qui gèlent — `price_history` est alimenté H24 par des crons serveur indépendants
  de Make (BTC/ETH : 24 bougies/jour samedi ET dimanche). Ce qui gèle, c'est la couche de
  **valorisation** produite par Make (dashboard, `oracle_performance`), et surtout : les courbes des
  Sages lisent `oracle_performance` (une écriture **par run**), pas un mark-to-market live. Forex et
  actions sont, eux, **réellement fermés** le week-end (gel normal). Solution **100 % lecture, sans
  cron ni écriture** : deux vues `v_live_crypto_positions` / `v_live_crypto_resume` recalculées **à la
  lecture** depuis le dernier cours (comme le panneau Marées), exposées par `oracle-inbox` v16
  (`suivi.live_crypto`) + nouvelle section console **« Crypto en direct »**. Aucun ordre, aucune
  décision, ne touche NI au kill-switch NI au dry_run. Périmètre assumé : **seule la crypto** (la seule
  classe 24/7) est affichée ; le total de `oracle_positions_live` n'étant pas fiable, il n'est pas
  exposé. État actuel : SYL porte ~226 k$ de crypto (P&L latent live), GIL/JU = poussière.
  DDL : `supabase/schema/08_live_crypto.sql`.

## 2026-08-15

- **Marées — retrait du « contre-pied aveugle » côté base.** Il subsistait DEUX inversions distinctes :
  (1) le « contre-pied raisonné » dans le prompt de Marées (contrarian vs consensus excessif, seulement
  si espérance positive) = **légitime, conservé** ; (2) une inversion AVEUGLE du signal dans
  `marees_rebuild_virtual` (`buy↔sell` systématique), vestige de l'ancien prompt Gemini anti-prédictif.
  Comme le prompt de Marées a été **refait la session précédente**, cette 2ᵉ inversion faisait un
  double contre-pied et n'avait plus lieu d'être → **ligne retirée** (`lower(side) as side`, on trade le
  sens PROPOSÉ). Vérifié : les 25 positions ouvertes suivent désormais exactement le sens des
  propositions (`concorde=true` sur tout l'échantillon). Migration `marees_retire_contre_pied_aveugle`
  + `marees_rebuild_virtual` rejouée (28 trades, 0 clôturé — forex quasi plat, positions ≤49 h).
  → `supabase/schema/03_functions.sql`.
- **Marées — calibrage de la sortie + prompt Maia (mémoire, sorties, renommage).** (a) `marees_rebuild_virtual`
  calibré pour le forex : planchers TP 3→**1,2 %** / SL 2→**0,8 %** (ratio 1,5:1), détention 240→**96 h**
  → premières clôtures avancées (~17-19/08 au lieu du 23). (b) Vérif : le prompt de Marées ne lisait
  QUE `latest_web_catalysts` (pas de doctrine) → prompt Maia rédigé pour ajouter une **fente MÉMOIRE**
  lisant `brain_states.MAREES.current_bias`, aligner les consignes TP/SL, et **renommer** les modules
  génériques restants (« Staking délais », « Staking APY ») dans l'univers alchimique.
  → `docs/decisions/PROMPT-MAIA-MAREES-2026-08-15.md`.
- **Panneau Marées (forex virtuel) dans la console.** Diagnostic : la console n'affichait rien pour
  Marées car elle ne montre que les trades **clôturés**, or 0 clôturé depuis le reset du 13/08
  (positions <49h ; sortie TP 3%/SL 2% ou 240h = trop lent pour du forex). Correctif d'affichage :
  vues `v_marees_virtuel_positions` / `_resume` (positions ouvertes valorisées au dernier cours,
  P&L latent), exposées par `oracle-inbox` v15 (`suivi.marees_virtuel`) + nouvelle section console
  « Marées — Devises ». Marées n'est plus jamais vide ; les résultats réalisés apparaîtront dès les
  premières clôtures (~23/08). DDL : `supabase/schema/07_marees_virtuel.sql`.
- **Sauvegarde GitHub quotidienne automatique.** Workflow GitHub Actions `brain-backup.yml` (cron
  23:15 Paris) : appelle la RPC `brain_snapshot()` (lecture seule, clé anon publique) et commite
  `docs/brain/snapshots/lessons-AAAA-MM-JJ.json`. Indépendant de toute session ; aucun secret requis.

- **Mémoire permanente des bots (« à vie »).** Constat : `learnings`/`mistakes_history` étaient rognés
  aux 30 dernières entrées (perte de la mémoire qualitative ancienne). Correctif : nouvelle table
  **`brain_lessons`** append-only (jamais rognée) + **trigger** `trg_archive_brain_lessons` qui archive
  chaque leçon/erreur à chaque cycle. Le quantitatif (`oracle_performance`, 245 runs/bot depuis juin)
  était déjà permanent. Sauvegarde GitHub versionnée : `docs/brain/snapshots/`. Architecture &
  procédures : `docs/brain/MEMOIRE.md`. DDL : `supabase/schema/06_brain_memory.sql`.

- **Analyse SYL — short or/argent à contre-tendance.** SYL est short GLD (~150 k$ notionnel, entrée
  moy. 372, cours ~401 → −12,7 k$ / −6,1 %) et SLV (−1,8 k$), tenus **181 runs** sans être coupés.
  Causes : (a) doctrine apprise « GLD vs TLT rotation, prior wins on GLD » qui rejoue le short ;
  (b) **stop-loss non appliqué** — les ordres portent `stop_loss_pct=5` mais `stop_loss_target` reste
  null et la position dépasse −5 % sans coupe ; (c) la perte reste **latente** (jamais clôturée) donc
  la boucle d'apprentissage ne la **book pas** comme erreur → SYL ne se corrige pas seule. NB : paper.

- **Mécanisme « leçon épinglée » (pinned) + leçon anti-short-métaux pour SYL.** Découverte : le prompt
  du Conseil lit `brain_states.<archimage>.learnings[1].bias` comme MEMORY_CORRECTION, mais
  `update-brain` **rognait `learnings` aux 30 dernières** → une leçon manuelle disparaissait au cycle
  suivant. **`update-brain` v16** : les entrées `learnings` marquées `pinned:true` sont **préservées en
  tête** (jamais rognées) → une leçon manuelle reste lue en permanence. Leçon posée pour SYL
  (`learnings[0]`, pinned) : « ne pas shorter or/argent en tendance haussière ; couper tout short
  perdant au-delà de −5 % ; ne pas moyenner à la baisse ; un gain passé sur une rotation ne justifie
  pas un short à contre-tendance ». Procédure de réutilisation : `docs/RUNBOOK.md` §11.
  ⚠️ Reste ouvert : le **bug du stop non appliqué** (code `execute-trades`) — une leçon change les
  décisions mais ne fait pas se déclencher le stop ; à traiter avant le réel.

## 2026-08-14

- **Export & documentation complète du repo.** Dump de tout le schéma Supabase (tables, vues,
  fonctions, cron, policies) dans `supabase/schema/`, de toutes les edge functions dans
  `supabase/functions/`, et rédaction des docs (`ARCHITECTURE`, `RUNBOOK`, `PASSAGE-AU-REEL`, ce
  journal). But : ne rien perdre du travail, permettre suivi/maintenance/évolution/passage au réel.

- **Calendrier & rappels dans la console.** Nouvelle table `oracle_rappels` ; section « 📅 Calendrier »
  (espace opérationnel) avec badges par créneau (🌅/☀️/🌙), demandes (💬), rappels (🔔), détail au clic,
  bannière des rappels dus. `oracle-inbox` v14 sert l'historique étendu + rappels. **Rappel posé le
  28/08 (matin) : faire le point GIL → Alchimiste.**

- **Analyse : les leçons de GIL doivent-elles alimenter l'Alchimiste ?** GIL (crypto tactique, WR
  52 %, doctrine contrarian validée) vs Alchimiste (WR 38,5 %, asymétrie gain +0,56 % / perte −2,84 %,
  historique plombé par l'ancienne ère short-only sur micro-cryptos illiquides). Avis : oui, ajouter
  la **doctrine apprise** de GIL au prompt de l'Alchimiste en **contexte advisory** (il reçoit déjà son
  avis du jour, pas sa doctrine), MAIS le vrai levier reste la **discipline de sortie** et la
  **liquidité** de l'Alchimiste ; surveiller la **corrélation** (décorrélation = protection).
  **Décision : on laisse tourner jusqu'au 28/08 puis on tranche.** (rappel posé)

- **Fix `alc_record_propositions` (côté Supabase).** Le module Make « Le Registre de Cristal » (10023)
  envoie le JSON IA brut ; c'est la fonction Postgres qui extrait les colonnes. Elle lisait les
  **anciennes clés** (`crypto/sens/montant_usd/prix_actuel/gain_net_estime_pct/raison_courte`) alors
  que le nouveau prompt produit `paire/side/montant/confidence/raison` (sans prix) → colonnes NULL.
  Fonction réécrite : nouvelles clés (repli ancien), **`prix_ref` récupéré depuis `price_history`**,
  `destake_recommande` persisté dans nouvelle table `alc_destake_reco`. Backfill des propositions du
  jour + rebuild du portefeuille papier (9 trades). **Aucune modif Make nécessaire.**
  → `docs/decisions/CORRECTIF-ALCHIMISTE-MAPPING-2026-08-14.md`.

- **Tableau des gains par trader (console), en euros.** Nouvelle vue `v_gains_traders` (source unique) :
  7 lignes (AETHER, Alchimiste réel, Alchimiste virtuel, JU, SYL, GIL, Marées) × 4 horizons
  (jour/semaine/mois/année), en **€** (« si je soldais ») + équivalent **$** + **%**. `oracle-inbox`
  expose `gains` + `fx` (EUR-USD live). **Correction majeure** : le montant était calculé sur une
  mauvaise base d'équité (~54 k) ; la vraie base des sages est `baseline_equity` ≈ **1 M**.

- **Alerte univers repointée.** `v_data_health` surveillait la table morte `revolut_univers_complet`
  (figée 07/07). Repointée sur la vraie source live `price_history` (univers ≥ 200 symboles/heure).
  → `docs/decisions/CORRECTIF-UNIVERS-SANTE-2026-08-14.md`.

- **Diagnostic crash Alchimiste (Make 6183820).** Erreur « JSON invalide » sur le module Perplexity
  (10012) : des tableaux bruts (`10011.data`, `20022.data`, `20023.data`) étaient injectés dans le
  corps JSON. Prompt de diagnostic rédigé pour Maia (elle décide du fix).
  → `docs/decisions/PROMPT-MAIA-ALCHIMISTE-JSON-2026-08-14.md`. **Corrigé via Maia le 14/08.**

- **Audit de la journée.** JU/SYL/GIL : 11 ordres remplis, complets. Alchimiste : réparé, achète ET
  vend. Marées : 7 propositions complètes. `alpaca_orders` confirmée **table morte** (canonique =
  `oracle_college_orders`).

## 2026-08-13

- **Résumé quotidien serveur (matin/midi/soir).** `generate_daily_journal(creneau)` + pg_cron, pour
  écrire le point complet (tous traders + destaking) dans `oracle_journal` **sans dépendre d'une
  session Claude**. → `supabase/README-DAILY-JOURNAL.md`.

- **Kill-switch + Face ID.** Bouton dans la console ; edge functions `ju-killswitch` (PIN, option A,
  anti-lockout) et `ju-passkey` (Face ID/WebAuthn, option B). Espace opérationnel verrouillé (PIN puis
  Face ID). → `supabase/functions/README-KILLSWITCH.md`.

- **Fix Alchimiste spot.** `alc-auto` v6 + `revolut-x-trade` v7 : achète ET vend (fin du sell-only),
  tradabilité **live**, achat plafonné au cash USD, vente sur actif détenu liquide (hors staking).
  → `docs/decisions/CORRECTIF-ALCHIMISTE-2026-08-13.md`.

- **Staking.** Tables `alc_staking_apy`, `alc_staking_delais`, `alc_staking_lots` ; vue
  `v_staking_point` (coût/valeur/PnL/coût de dé-staking par coin, FX historique aux dates d'achat).

- **Netlify no-cache.** `_headers` (`Cache-Control: max-age=0`) pour voir les MAJ HTML tout de suite.

## Avant le 2026-08-13 (résumé)
- Construction du dashboard/vitrine, ajout de l'archimage **Marées** (forex, 24/07), suivi
  multi-périodes + santé système, PWA suivi mobile, ratios réels de l'Alchimiste virtuel, ingestion
  multi-sources (Binance/Gate/Revolut X/FX/indices), apprentissage par brain states, réconciliation
  des ordres. (Historique détaillé : `git log`.)

---

### Modèle d'entrée (à copier pour les prochaines)
```
## AAAA-MM-JJ
- **Sujet.** Quoi. Pourquoi. Où (fichier / table / fonction). Décision & suite.
```
