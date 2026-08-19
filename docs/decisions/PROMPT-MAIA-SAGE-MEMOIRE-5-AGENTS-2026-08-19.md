# Prompt pour Maia — étendre le Sage Mémoire aux 5 agents (module 207)

> **Statut : PRÊT, non envoyé.** À arbitrer par Chachou.
> Rappel CLAUDE.md : toute modification Make passe par Maia, jamais par le blueprint en direct.

## Ce qui a été vérifié avant de proposer quoi que ce soit

Scénario **6183820 — ZCT Oracle L'Alchimiste Financier v5 VISIONNAIRE**, lecture seule du blueprint.

- Module **207 · 📚 DEEP MEMORY — Sage Mémoire** (`http:MakeRequest` → Groq `openai/gpt-oss-120b`,
  `temperature 0.01`, `response_format: json_object`). Sortie parsée par le module **208 · 💧 DISTILLATION
  MÉMOIRE**, consommée par le **215 · 🔮 LA MATRICE DES SIGNAUX** sous les clés `JU_WR`, `SYL_WR`,
  `GIL_WR`, `BEST_ARCH`, `WIN_PATT`, `FAIL_PATT`, `CORRECTION`.
- Le schéma de sortie impose **7 champs** : `ju_win_rate`, `syl_win_rate`, `gil_win_rate`,
  `best_archimage` (`JU|SYL|GIL|EQUAL`), `failed_pattern` (100 car.), `winning_pattern` (100 car.),
  `correction_directive` (120 car.).

### Constat 1 — il couvre bien les 3 Archimages, mais analyse surtout JU

Les trois sont notés à chaque run. En revanche les **règles** du prompt ne parlent que de JU :
« ANALYSE DE SEQUENCE » ne regarde que les 3 dernières décisions JU, « DETECTION OVER-TRADING » ne teste
que `JU_RUNS`. Aucune règle propre à SYL ou GIL.

Côté entrées, l'asymétrie est la même :

| Agent | Variables réellement injectées |
|---|---|
| JU | `wins`, `losses`, `total_runs`, `cumulative_pnl` |
| SYL | `wins`, `losses`, `current_bias` |
| GIL | `wins`, `losses`, `current_bias` |

Manquent : `SYL_RUNS`, `GIL_RUNS`, `SYL_PNL`, `GIL_PNL`, `JU_BIAS`.

### Constat 2 — l'Alchimiste et les Marées sont totalement absents

Zéro occurrence de `CRYPTE_JU` / `MAREES` dans le module 207, ni dans la variable `CTX` (module 110).
Leurs pipelines (10012 Alchimiste, 20015 Marées) sont **en aval** du routeur 999 : ils ne peuvent pas
alimenter le Sage Mémoire.

**Mais les données existent déjà** : la RPC `get_oracle_context` (module **105**) renvoie `brain_states`
pour **toutes** les lignes d'`oracle_brain_state`, qui contient aujourd'hui `CRYPTE_JU` (38 runs, WR 52,6 %)
et `MAREES` (25 runs, WR 64,0 %). Les mappings `105.data.brain_states.CRYPTE_JU.*` et `.MAREES.*` sont
**disponibles et simplement inutilisés**. Aucune nouvelle source de données n'est nécessaire.

### Constat 3 — deux scories dans le prompt actuel

- Il exige un champ `FORCE_CONTRARIAN` qui n'existe pas dans le schéma.
- Un bloc « LANGUE » copié d'un autre Sage cite `prophet_vision`, `portfolio_rationale`, `rationale`,
  `memory_summary`, `evaluations` — aucun de ces champs n'est au schéma du Mémoire.
- Le prompt demande d'analyser « les 3 dernières décisions JU, même ticker et même side », information
  que le module ne reçoit **jamais** (l'historique détaillé des ordres, module 902, s'exécute après le 207).
  Le Sage travaille en réalité sur des compteurs cumulés.

---

## Prompt à envoyer à Maia (copier-coller tel quel)

```
Bonjour Maia. Dans le scénario 6183820 (ZCT Oracle v5), je veux étendre le Sage Mémoire aux 5 agents.
Ne touche QUE le module 207 (📚 DEEP MEMORY). Ne modifie aucun autre module, ni le 208, ni le 215.

1) Dans le corps du module 207, remplace le contenu du message "user" par celui-ci
   (j'ajoute Alchimiste et Marées, et je complète SYL/GIL qui étaient incomplets) :

CTX={{CTX}} JU_W={{ifempty(105.data.brain_states.JU.wins; 0)}} JU_L={{ifempty(105.data.brain_states.JU.losses; 0)}} JU_RUNS={{ifempty(105.data.brain_states.JU.total_runs; 0)}} JU_PNL={{ifempty(105.data.brain_states.JU.cumulative_pnl; 0)}} JU_BIAS={{replace(replace(ifempty(105.data.brain_states.JU.current_bias; neutral); newline; ); quote; )}} SYL_W={{ifempty(105.data.brain_states.SYL.wins; 0)}} SYL_L={{ifempty(105.data.brain_states.SYL.losses; 0)}} SYL_RUNS={{ifempty(105.data.brain_states.SYL.total_runs; 0)}} SYL_PNL={{ifempty(105.data.brain_states.SYL.cumulative_pnl; 0)}} SYL_BIAS={{replace(replace(ifempty(105.data.brain_states.SYL.current_bias; neutral); newline; ); quote; )}} GIL_W={{ifempty(105.data.brain_states.GIL.wins; 0)}} GIL_L={{ifempty(105.data.brain_states.GIL.losses; 0)}} GIL_RUNS={{ifempty(105.data.brain_states.GIL.total_runs; 0)}} GIL_PNL={{ifempty(105.data.brain_states.GIL.cumulative_pnl; 0)}} GIL_BIAS={{replace(replace(ifempty(105.data.brain_states.GIL.current_bias; neutral); newline; ); quote; )}} ALC_W={{ifempty(105.data.brain_states.CRYPTE_JU.wins; 0)}} ALC_L={{ifempty(105.data.brain_states.CRYPTE_JU.losses; 0)}} ALC_RUNS={{ifempty(105.data.brain_states.CRYPTE_JU.total_runs; 0)}} MAR_W={{ifempty(105.data.brain_states.MAREES.wins; 0)}} MAR_L={{ifempty(105.data.brain_states.MAREES.losses; 0)}} MAR_RUNS={{ifempty(105.data.brain_states.MAREES.total_runs; 0)}}

2) Dans le message "system" du même module 207, remplace UNIQUEMENT la partie "Schema :" et les règles
   d'analyse par ceci, en gardant le reste du texte tel quel :

Schema : {"ju_win_rate":0,"syl_win_rate":0,"gil_win_rate":0,"alc_win_rate":0,"marees_win_rate":0,"best_archimage":"JU|SYL|GIL|EQUAL","best_agent":"JU|SYL|GIL|ALCHIMISTE|MAREES|EQUAL","failed_pattern":"max 100 chars no quotes","winning_pattern":"max 100 chars no quotes","correction_directive":"max 120 chars no quotes","correction_cible":"JU|SYL|GIL|ALCHIMISTE|MAREES|COLLEGE"}
Regles d analyse, appliquees a CHAQUE agent et pas seulement a JU : au-dessus de 55 pour cent de win rate egal excellent ; en dessous de 45 pour cent egal correction obligatoire ; win rate egal wins divise par wins plus losses multiplie par 100. DETECTION OVER-TRADING : pour chaque agent, si RUNS superieur a 10 et win rate inferieur a 40 pour cent alors le probleme est la SELECTION et pas la frequence, recommande de reduire a 5 a 10 decisions de haute conviction. CIBLAGE : correction_cible doit designer l agent dont le win rate est le plus faible parmi ceux qui ont au moins 10 runs ; si tous sont au-dessus de 50 pour cent mets COLLEGE. VOLUME INSUFFISANT : si un agent a moins de 10 runs, mets son win rate mais ne fonde aucune correction sur lui. alc_win_rate et marees_win_rate entiers 0 a 100.

3) Supprime du message "system" les deux scories suivantes, qui ne correspondent à aucun champ du schéma :
   - la phrase qui impose "FORCE_CONTRARIAN egal true"
   - la phrase LANGUE qui cite prophet_vision, portfolio_rationale, rationale, memory_summary, evaluations
     (remplace-la par : les valeurs des champs texte doivent etre redigees en francais clair)
   Retire aussi la règle "ANALYSE DE SEQUENCE ... 3 dernieres decisions JU meme ticker et meme side" :
   le module ne reçoit pas ces données, elle est donc ininterprétable.

4) Ne change rien d'autre : ni le modèle, ni la température, ni le response_format, ni le module 208,
   ni le mapping du module 215.

Merci de me confirmer les modifications avant de sauvegarder.
```

## Après application

- Vérifier qu'un run produit bien `alc_win_rate`, `marees_win_rate`, `best_agent` et `correction_cible`
  dans `oracle_sages_report` (`sage_name = 'Memoire'`).
- Le module **215** ne mappe que les 7 clés d'origine : les 4 nouvelles ne remonteront pas aux Archimages
  tant qu'il n'est pas étendu. **C'est volontaire dans un premier temps** — on observe la sortie avant de
  la faire agir sur les décisions.
- Côté console AETHER : rien à faire, la modale du Sage affiche automatiquement tous les champs produits
  (`sage_detail.derniere_sortie`).

## ⚠️ Point sécurité relevé au passage (non corrigé)

Le blueprint du scénario contient **en clair** une clé API Groq (`Bearer gsk_…`, module 207) et la clé anon
Supabase (module 105). CLAUDE.md impose les secrets en Vault. Recommandation : **roter la clé Groq** puis la
déplacer. Aucune modification effectuée — décision de Chachou.
