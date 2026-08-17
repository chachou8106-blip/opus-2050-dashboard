PROMPT POUR MAIA — scénario 6183820 « ZCT — Oracle L'Alchimiste Financier v5 VISIONNAIRE »

Maia, TROIS corrections chirurgicales. Le scénario tourne (semaine de test avant le passage au réel :
il doit performer). Change UNIQUEMENT ce qui est décrit ci-dessous. Ne touche NI aux IDs de modules,
NI aux connexions/mappings, NI aux autres prompts. Après coup, une exécution doit tourner sans erreur.

════════════════════════════════════════════════════════════════════════
1) ALCHIMISTE — il ne « voit » pas le Conseil (CTX / SAGES / avis de GIL envoyés en BASE64 illisible)
════════════════════════════════════════════════════════════════════════
Module de l'Alchimiste (celui dont le texte système commence par « Tu es L'ALCHIMISTE DE LA CRYPTE… »
et qui produit le JSON {"propositions":[…],"destake_recommande":[…],"commentaire":…}).

CONSTAT (vérifié) : dans son CORPS UTILISATEUR (message role=user), le contexte marché (CTX), les Sages
(SAGES) et l'avis de GIL sont encodés en base64. Le modèle ne les décode pas → il est aveugle au
Conseil. Preuve : les 3 archimages (JU/SYL/GIL) reçoivent déjà `CTX={{CTX}}|SAGES={{SAGES}}` EN CLAIR,
sans souci ; seul l'Alchimiste utilise base64(CTX)/base64(SAGES). On l'aligne sur eux.

Dans le CORPS UTILISATEUR de l'Alchimiste UNIQUEMENT, remplace :
- `CTX_B64={{base64(CTX)}}`                         →  `CTX={{CTX}}`
- `SAGES_B64={{base64(SAGES)}}`                     →  `SAGES={{SAGES}}`
- `AVIS_GIL_PHASE={{base64(ifempty(306.market_phase; emptystring))}}`
                                                    →  `AVIS_GIL_PHASE={{ifempty(306.market_phase; emptystring)}}`
- `AVIS_GIL_ACTION={{base64(ifempty(306.action; emptystring))}}`
                                                    →  `AVIS_GIL_ACTION={{ifempty(306.action; emptystring)}}`
- `AVIS_GIL_THESE_B64={{base64(ifempty(306.contrarian_thesis; emptystring))}}`
                                                    →  `AVIS_GIL_THESE={{replace(replace(ifempty(306.contrarian_thesis; emptystring); newline; ); quote; )}}`
- `AVIS_GIL_VISION_B64={{base64(ifempty(306.prophet_vision; emptystring))}}`
                                                    →  `AVIS_GIL_VISION={{replace(replace(ifempty(306.prophet_vision; emptystring); newline; ); quote; )}}`
- `AVIS_GIL_TRADE1={{base64(ifempty(306.trade_1.ticker; emptystring))}}/{{base64(ifempty(306.trade_1.side; emptystring))}}`
                                                    →  `AVIS_GIL_TRADE1={{ifempty(306.trade_1.ticker; emptystring)}}/{{ifempty(306.trade_1.side; emptystring)}}`
- `AVIS_GIL_RATIONALE_B64={{base64(ifempty(306.trade_1.rationale; emptystring))}}`
                                                    →  `AVIS_GIL_RATIONALE={{replace(replace(ifempty(306.trade_1.rationale; emptystring); newline; ); quote; )}}`

NE TOUCHE PAS à `PRIX_REVOLUTX_B64`, `STAKING_DELAIS_B64`, `STAKING_APY_B64` : ce sont des TABLEAUX,
ils restent en base64 (le prompt demande déjà de les décoder). Ne touche pas non plus à
`SOLDES_REVOLUTX` ni `CRYPTE_CATALYSTS` (déjà en clair).

Dans le TEXTE SYSTÈME de l'Alchimiste : la section « TON MATÉRIEL DE DÉCISION » décrit déjà CTX/SAGES/
AVIS_GIL comme lisibles → laisse-la. Vérifie juste qu'aucune phrase n'affirme que CTX, SAGES ou AVIS_GIL
sont en base64 (seuls PRIX_REVOLUTX / STAKING_* le sont). Si une telle phrase existe, retire CTX/SAGES/
AVIS_GIL de la liste des champs base64 à décoder.

════════════════════════════════════════════════════════════════════════
2) SAGE RISQUE (⚔️ IRON SENTINEL) — verdict bloqué sur MEDIUM à chaque run
════════════════════════════════════════════════════════════════════════
CONSTAT (vérifié dans son texte système) : (a) les seuils de risk_level SE CHEVAUCHENT et sont
incohérents — « LOW < 1% ; MEDIUM 0,3–2% ; HIGH ≥ 0,8% ; EXTREME ≥ 1,5% » (un même mouvement tombe dans
plusieurs cases) → le modèle retombe sur le repère VIX, or le VIX est stable ~17 → MEDIUM en boucle ;
(b) `temperature = 0.01` → sortie quasi déterministe (aucune variation).

Corrige SANS toucher au schéma de sortie (risk_level / max_single_position_pct / cash_floor_pct /
drawdown_alert / hedge_recommendation / risk_score / sizing_multiplier / crypto_max_pct) :
- Remplace les seuils de mouvement 24h par des bornes MUTUELLEMENT EXCLUSIVES :
    LOW = mouvement 24h attendu < 0,5 % ; MEDIUM = 0,5 à 1,0 % ; HIGH = 1,0 à 1,8 % ; EXTREME = > 1,8 %.
    (Le repère VIX reste : < 15 → LOW ; 15–20 → MEDIUM ; 20–30 → HIGH ; > 30 → EXTREME.)
- Ajoute une consigne : « Estime d'abord le mouvement 24h le plus PROBABLE du SPY à partir de MOMENTUM
    (204.spy_momentum), des catalyseurs Flash et du régime macro — PAS uniquement du VIX — puis mappe-le
    aux bornes ci-dessus. Le VIX est un repère, pas le seul déterminant. Ne réponds jamais MEDIUM par
    défaut. »
- Passe `temperature` de 0.01 à 0.3.

════════════════════════════════════════════════════════════════════════
3) SAGE FLASH (⚡ QUANTUM PULSE) — classification figée (market_shock=NO / urgency=MEDIUM)
════════════════════════════════════════════════════════════════════════
CONSTAT : `temperature = 0.01` fige sa classification même quand les manchettes varient.
Corrige : passe `temperature` de 0.01 à 0.3. Ne touche à RIEN d'autre (logique anti-biais, priorités,
schéma shock_type / market_shock / urgency_level / top_headline_* : inchangés).

════════════════════════════════════════════════════════════════════════
RÈGLES
════════════════════════════════════════════════════════════════════════
- Ne modifie QUE les points ci-dessus. Pas de changement d'IDs, de connexions/mappings, ni des autres
  prompts (JU, SYL, GIL, Marées, Macro, Technique, Mémoire, modules d'exécution/parse).
- Après coup, une exécution complète doit tourner sans erreur (semaine de test avant le réel).
