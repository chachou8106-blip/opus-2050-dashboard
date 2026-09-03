# Règles de travail — AETHER / OPUS 2050

## RÈGLE ABSOLUE — Vérifier avant d'affirmer ou de créer (demandée par Chachou, 17/08/2026)

**Avant de dire « ça n'existe pas / il n'y a pas / il faut ajouter », JE VÉRIFIE d'abord.**
Ne jamais inventer, ne jamais supposer l'absence d'un objet.

Concrètement, avant de proposer une nouvelle table / vue / fonction / module Make :
1. **Chercher l'existant** : `information_schema.tables` / `.views` / `.columns`, `pg_proc`,
   et le blueprint Make (`scenarios_get` + grep) — par mot-clé (staking, apy, delai, verdict, destake…).
2. **Réutiliser** ce qui existe (ex. `v_staking_point` a déjà apy_pct + unbonding_jours + coût ;
   `alc_destake_reco` journalise déjà le dé-stake via `alc_record_propositions`).
3. **N'ajouter un objet QUE si** rien d'existant ne convient, et le dire explicitement
   (« j'ai vérifié X, Y, Z, rien ne couvre ce besoin, donc j'ajoute … »).
4. Ne pas faire faire de manipulations Make à Chachou (ajout de module, etc.) sans avoir
   confirmé qu'aucun module/objet existant ne fait déjà le travail.

Cette règle prime sur toute envie d'aller vite.

## RÈGLE ABSOLUE — Ne JAMAIS écrire d'instruction à un agent depuis Supabase (20/08/2026)

**Les leçons et les consignes d'un agent viennent de l'agent, jamais de moi.**

Ce que j'ai fait et qui ne doit plus jamais se reproduire : le 15/08 (commit `b88f8d5`) j'ai créé
un mécanisme de « leçon épinglée » dans `update-brain` v16, puis j'ai inséré à la main dans
`oracle_brain_state.learnings` un texte de ma composition pour SYL
(`run_id = 'lecon-manuelle-20260815'`). Le module Make 303 lit `learnings[1].bias` : mon texte a
donc occupé **l'unique canal de mémoire de SYL pendant cinq jours**, et SYL n'a plus relu une
seule de ses propres leçons.

**Le retrait du 20/08 a nettoyé la mauvaise table.** J'avais supprimé la ligne de
`oracle_brain_state.learnings` (sauvegarde `bak_20260820_lecon_epinglee`) en croyant l'affaire
close, et je l'ai écrit ici. Or `get_oracle_context()` ne construit PAS le bloc `learnings` à
partir de cette colonne : il le construit à partir de **`brain_lessons`**, où la ligne est restée.
Mon texte a donc continué de partir dans le prompt de SYL **huit jours de plus**, jusqu'au
23/08 (sauvegarde `bak_20260823_lecon_manuelle`). Leçon : vérifier le CHEMIN de lecture, pas
seulement la table qui porte le nom attendu.

Interdictions, sans exception :
1. **Ne jamais écrire, modifier ou épingler** une ligne de `oracle_brain_state.learnings`,
   `current_bias`, `mistakes_history` ou toute autre colonne relue par un prompt.
2. **Ne jamais créer de canal** permettant d'injecter un texte de ma main dans un prompt.
3. Une consigne de comportement se met **dans le prompt système, via Maia**. Point.
4. Si je pense qu'un agent a besoin d'une règle, je le **propose à Chachou** avec le prompt Maia
   correspondant. C'est lui qui décide. Je n'ai pas le droit de court-circuiter.

**Liste des textes qui atteignent un prompt** — à vérifier avant toute modification. Elle était
incomplète, c'est ce qui m'a fait nettoyer la mauvaise table le 20/08 :

Dans Supabase, via `get_oracle_context()` → module 105 :
- **`brain_lessons.bias` et `.eval`** — la VRAIE source des blocs `learnings` et
  `mistakes_history`. C'est ici qu'on lit, pas dans `oracle_brain_state`.
- `oracle_brain_state.current_bias` (les 3 Archimages via `MEMORY_CORRECTION`) ; `.learnings` et
  `.mistakes_history` ne servent que de repli quand `brain_lessons` est vide.
- `oracle_circuit_breakers` → bloc `active_circuit_breakers` (via `CIRCUIT_BREAKERS`).
- `crypte_ju_evaluate_and_learn` (Alchimiste), `marees_evaluate_and_learn` (Marées) : ces
  fonctions ÉCRIVENT le `current_bias` de CRYPTE_JU et de MAREES.

Hors Supabase, dans le code des edge functions — même statut, même interdiction :
- `collect-market-data/index.ts` : le champ `directive` injecté aux Archimages, et 3 prompts
  système Perplexity.
- `marees-context/index.ts` : le champ `directive`, prompt système complet de l'Archimage des Marées.
- `fx-context/index.ts` : le champ `directive` forex.

**Deux chemins écrivent `current_bias`, avec des règles opposées** : `update-brain` tronque à
260 caractères et garde 30 leçons ; `batch_write_college_run_v2` (la RPC appelée par Make) ne
tronque pas et empile. C'est par là que `JU.current_bias` a atteint 1 132 caractères.

## RÈGLE ABSOLUE — Ne jamais déployer ce que je n'ai pas pu tester (20/08/2026)

Le 20/08 à 05:55 j'ai déployé `execute-trades` v39 (rachat de short en quantité) sans l'avoir
jamais exercé marché ouvert, en le sachant et en l'écrivant. À 15:32 il a liquidé **1 361 754 $**
sur une demande de 6 000 $ (IEF), puis 9 394 $ sur GLD.

Un correctif touchant l'exécution d'ordres réels ne part en production qu'après :
1. un test en conditions réelles, ou à défaut l'accord explicite de Chachou en connaissance du
   risque ;
2. une borne de sécurité : **jamais d'ordre plus gros que ce que le modèle a demandé.**

## RÈGLE — Un contrôle étroit ne prouve pas une affirmation large (20/08/2026)

Le 20/08 j'ai affirmé « je n'ai jamais touché aux prompts des Archimages » après avoir vérifié
uniquement que `{{CTX}}` y figurait encore. Le prompt système est une autre partie du module.
Avant d'affirmer qu'une chose n'a pas changé, **lire l'objet entier**, pas un champ.

## RÈGLE ABSOLUE — Chachou n'écrit pas de code. Si c'est cassé, c'est moi (25/08/2026)

Chachou ne sait pas écrire une ligne de code : **tout ce qui est dans Supabase, dans les edge
functions et dans les modules Make vient de moi**, directement ou via les consignes que je lui
fais passer à Maia. La date d'un commit ou d'un dump ne prouve rien : un objet présent le 14/08
au matin peut très bien avoir été écrit par moi le 13/08 au soir. **Cesser de discuter la
paternité.** Le seul débat utile est : qu'est-ce qui est cassé, et comment on le répare.

Quand il dit « ça marchait avant », la réponse n'est pas « non » — c'est **comparer**. Le
blueprint d'avant le 13/08 qu'il a fourni est dans `scratchpad/ancien_bp.txt` ; le comparer
module par module avant toute affirmation. Le 25/08 cette comparaison lui a donné raison sur
trois points d'un coup : le Sage Mémoire tournait bien sur Groq, les Marées n'ont jamais changé
de moteur, et aucun module n'a disparu — c'est un seul module cassé (303) qui bloquait tout
le reste du scénario.

## RÈGLE ABSOLUE — Un agent reçoit la MESURE, jamais la CONCLUSION (26/08/2026)

Le robot doit apprendre de ses erreurs et se corriger **lui-même**. C'est son ADN. À trois endroits
j'ai mis mes conclusions sur ce chemin, et Chachou l'a vu :

1. **`sages_coaching()`** : le taux de réussite est une mesure, mais « garde ta ligne », « affine »,
   « baisse ta conviction et sois prudent » sont des ordres de ma main. Cette chaîne part dans le
   prompt des cinq Sages (`COACHING`) et dans `FIABILITE_SAGES` du module 215.
2. **`oracle_circuit_breakers.notes`**, écrites par `check_circuit_breakers` : « le probleme est la
   SELECTION, pas la frequence. Moins de decisions, plus de conviction. » Ça atteint tous les agents
   via `active_circuit_breakers`.
3. **`generate_daily_journal` §6** : « Garder de preference les APY eleves (ATOM 21%, TON 17.67%) » —
   mon arbitrage, avec des valeurs en dur, dans les messages de Chachou trois fois par jour.
4. Les blocs **AUTOCRITIQUE** ajoutés aux 10 prompts le 21/08 ne demandent pas à l'agent de se
   corriger : ils lui dictent la correction, motif par motif.

**Règle : je transmets le chiffre, le motif, le seuil et l'observation. Jamais le verbe d'action.**
Un garde-fou d'EXÉCUTION (plafond de levier, plafond de notionnel, blocage d'ouverture sur
drawdown) est autre chose et reste légitime : il n'entre pas dans la tête de l'agent, il borne ce
qui part au courtier.

## RÈGLE — Une chaîne livrée à moitié finit par lâcher (26/08/2026)

Le dé-staking : le module Discord 10031 et `alc_record_propositions` attendent tous deux `verdict`,
`raison` et `gain_trade_attendu_pct`. Le prompt du 10012 ne nomme **aucune** de ces clés. Le modèle
les déduisait de la prose ; ça a tenu du 17/08 au 21/08, puis les colonnes sont passées à NULL.
**Avant de dire qu'une fonctionnalité « tenait par chance », vérifier les DEUX bouts de la chaîne :
qui écrit, qui lit, et si quelqu'un l'a jamais demandé.** Ici c'est ma livraison qui était
incomplète, pas la fonctionnalité qui était fragile.

## RÈGLE — Un corps de module Make n'est pas du JSON ordinaire (27/08/2026)

Le 26/08, en appliquant mon prompt A sur le module 305, Maia a réécrit le champ et **échappé les
guillemets à l'intérieur des `{{...}}`** : `\"bias\"` au lieu de `"bias"`. Make garde l'antislash
dans la valeur produite. Le corps envoyé à Mistral contenait
`MEMORY_CORRECTION= ## \ ## \ ## \ …` — un antislash seul dans une chaîne JSON. Le run du 27/08
s'est arrêté à 31 opérations sur `Bad escaped character in JSON`.

Mes trois contrôles — taille exacte, équilibre des accolades, `JSON.parse` — n'ont rien vu.
Pire : l'échappement rend le corps **plus** valide au sens JSON strict. Les modules 301 et 303,
qui écrivent `"bias"` nu, échouent `JSON.parse` brut — et ce sont eux qui tournent.

**À l'intérieur d'un `{{...}}`, les guillemets restent nus.** Ajouter au contrôle après chaque
passage de Maia : aucune expression `{{...}}` ne doit contenir d'antislash.

**Et `toString()` sur un tableau de collections Make ne produit PAS du JSON** : il rend
`[{object},{object}]`. Ne jamais supposer qu'une valeur Make se sérialise comme en JavaScript —
le panneau INPUT de l'historique d'exécution est la seule source de vérité sur ce qui part
vraiment.

## Rappels système (contexte)
- Modifs Make **uniquement via l'assistant Maia** (jamais le blueprint en direct).
- Un blueprint complet fait ~620 ko : `scenarios_update` avec blueprint est hors de portée d'un
  appel d'outil. Les correctifs Make se livrent donc **en chaînes exactes à chercher/remplacer**,
  extraites du blueprint en direct et vérifiées contre une version qui tourne.
- Ne jamais armer/désarmer le kill_switch ni passer dry_run=false sans accord explicite de Chachou.
- 100 % Supabase pour la logique data ; ne pas committer de secrets (webhooks → Vault).

## RÈGLE ABSOLUE — Maia casse la clé du module qu'elle réécrit (28/08/2026)

Le module 211 a renvoyé `401 PGRST301 — None of the keys was able to decode the JWT` pendant
trois runs. J'ai cherché la cause dans le corps : troisième argument omis, caractères de
contrôle, antislashs. **Trois hypothèses, trois fausses.** Le corps était bon depuis le début.
C'était l'en-tête `Authorization`, altéré sur 6 caractères au milieu du jeton.

Preuve établie sur le module 10032, dont j'ai l'historique complet :

| Moment | Corps | `Authorization` |
|---|---|---|
| avant intervention | 409 | intact |
| trois retouches **manuelles** de Chachou | 412 → 413 | **intact** |
| **un passage de Maia** | 409 | **60 caractères modifiés** |

**À chaque fois que Maia réécrit un module qui appelle Supabase, elle en réécrit la clé et la
casse** — malgré la consigne « ne touche à aucun en-tête » écrite en tête du prompt. Les
retouches manuelles de Chachou, elles, n'abîment jamais les clés (elles abîment parfois
l'expression, ce qui se voit tout de suite au compteur de caractères).

Conséquences :
1. **Après chaque passage de Maia sur un module Supabase, vérifier l'`Authorization` AVANT tout
   le reste.** `docs/outils/controle-blueprint-complet.mjs` le fait : il compare les en-têtes
   des 26 modules Supabase entre eux et signale celui qui diverge.
2. **Ne pas faire passer Maia sur ces modules quand une retouche manuelle suffit.**
3. Repère de réparation, vérifié sur les 26 modules :
   **`Authorization` = le mot `Bearer`, une espace, puis exactement la valeur d'`apikey`.**
   208 caractères d'un côté, 215 de l'autre.

**Et la leçon de méthode, qui est la vraie faute :** pendant quatre jours mon contrôle après
chaque intervention n'a porté que sur `jsonStringBodyContent` — taille, JSON, accolades. Je
n'ai jamais regardé les en-têtes. C'est la règle du 20/08 re-violée : un contrôle étroit ne
prouve pas une affirmation large. Le contrôle porte désormais sur le module entier.

**Et dans Make il faut DEUX validations** : `OK` sur le module, puis la disquette sur le
scénario. Tant que la disquette n'est pas cliquée, le blueprint ne bouge pas — Maia peut
annoncer un travail fait et le blueprint rester identique. Toujours vérifier le blueprint, pas
la réponse de Maia.

## RÈGLE ABSOLUE — Maia valide plus strictement que Make, et refuse du code qui tourne (31/08/2026)

Deux tentatives de Maia dans la même soirée, deux refus, deux causes différentes — et **aucune
des deux n'était un défaut du blueprint**.

**Module 301.** Son outil réenregistre le module entier et **ré-échappe le corps** : elle a envoyé
`\"bias\"` là où le champ contient `"bias"` nu. Make a refusé avec « backslash-escaped quote inside
an IML expression ». Le validateur avait raison : c'est le crash du 27/08 qu'il a empêché. Mais la
faute vient de son sérialiseur, pas du champ.

**Module 10012.** Elle a refusé d'enregistrer en invoquant `20023.data.apy_texte`. Vérifié sur le
blueprint : le module 20023 **existe**, il est en position 67 juste **avant** le 10012 en position
68, et le module a tourné le soir même à 19:49 en produisant six verdicts de dé-staking avec les
vrais APY (ATOM 21,06 %, TON 17,67 %, SOL 6,16 %). **Son validateur refuse une expression que Make
exécute sans broncher** : il ne sait pas résoudre le schéma de sortie d'un module HTTP dynamique.
Faux positif.

**Et elle casse les clés, c'est maintenant prouvé en direct.** Sa PREMIÈRE tentative sur le 301 a
envoyé une `x-api-key` de **109 caractères au lieu de 108**, divergence au caractère 42, début et
fin corrects — invisible à l'œil. Elle s'est corrigée seule au deuxième essai, mais un
enregistrement réussi du premier coup partait avec une clé cassée. Le contrôle par **longueur**
est le seul qui attrape ça.

Conséquences :
1. **Un module dont le corps contient des guillemets nus dans un `{{...}}`, ou une référence
   `.data.x` à un module HTTP, se retouche À LA MAIN.** Maia ne peut pas l'enregistrer.
2. Chachou a fait le 301 à la main le 31/08 : 7013 → 7114 exactement, `x-api-key` **identique à
   avant**, aucun autre module touché. La retouche manuelle ne présente aucun des deux risques.
3. Quand Maia doit quand même intervenir, lui donner des **repères chiffrés qu'elle vérifie
   elle-même** : longueur du corps, longueur de chaque en-tête, nombre d'antislashs. Jamais
   « ne touche pas aux en-têtes » — son outil DOIT les réécrire, et la consigne rend le travail
   impossible (elle a refusé pour ça le 31/08).

## RÈGLE — Des clés ajoutées « seulement si » cassent un insert groupé (31/08/2026)

`execute-trades` v43 ajoutait `stop_loss_pct`, `take_profit_pct` et `rationale` à `ordersToSave`
**de façon conditionnelle**. Les objets d'un même envoi n'avaient donc pas le même jeu de clés, et
**PostgREST refuse un insert groupé hétérogène**. Au run du 31/08 19:46 : 12 ordres acceptés chez
Alpaca, **2 enregistrés** — le seul lot homogène, celui de GIL. Les 6 de JU et les 4 de SYL ont
disparu.

Et l'échec était **muet** : `.catch(() => {})` n'attrape que les erreurs réseau, jamais un code
HTTP. Un refus 400 passait pour un succès.

Deux règles qui en découlent :
- **Tous les objets d'un insert groupé portent les mêmes clés**, à `null` quand la valeur manque.
  Un `null` explicite empêche aussi le `DEFAULT` de la colonne de mentir (les 5/10 fantômes).
- **Aucun `.catch` vide sur une écriture.** Vérifier `response.ok` et journaliser le code.
