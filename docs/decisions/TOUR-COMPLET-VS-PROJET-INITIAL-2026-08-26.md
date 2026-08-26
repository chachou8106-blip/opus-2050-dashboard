# Le tour complet — Supabase, GitHub, Make — comparé au projet initial

**26/08/2026.** Référence « projet initial » = le blueprint Make fourni par Chachou, **d'avant le
13/08**, et l'état du dépôt à la même date. Tout ce qui suit est mesuré, pas supposé.

---

## D'abord : deux choses que j'ai dites hier et qui étaient fausses

### 1. « Le dé-staking, ce n'était pas une fonctionnalité, c'était un coup de chance »

**Faux, et injuste.** Mesuré sur les trois versions du blueprint :

| | module 10031 (message Discord) | prompt 10012 (Alchimiste) |
|---|---|---|
| avant le 13/08 | `destake_recommande` : **0** | `destake_recommande` : **0** |
| 22/08 | **22** références, `verdict` **3 fois** | 3 références, `DE-STAKING` 4 fois |
| 26/08 | idem | idem |

Le dé-staking **n'existait pas avant le 13/08**. Il a été construit entre le 13 et le 21 — c'est
bien la semaine de travail dont Chachou parle. Le message Discord affiche, pour trois lignes :
devise, montant, gain attendu, APY staking, **VERDICT** et raison. Côté Supabase, la migration
`20260817194116 alchimiste_verdict_log` et `20260817201907 vigie_verdict_via_destake_reco` datent
cette construction au 17/08.

**Le vrai défaut est le mien : j'ai livré la chaîne à moitié.** L'affichage (module 10031) et le
stockage (`alc_record_propositions`) attendent tous les deux `verdict`, `raison` et
`gain_trade_attendu_pct` — et **le prompt ne nomme aucune de ces trois clés** : `verdict`
0 occurrence, `GARDER` 0, `DESTAKER` 0, `gain_trade_attendu_pct` 0, sur les trois versions.
Le modèle les déduisait de la consigne en prose (« tu le SUGGÈRES clairement »). Ça a tenu
jusqu'au 21/08, puis non.

Le coup de chance, ce n'est pas la fonctionnalité. C'est que **mon travail incomplet ait tenu
quatre jours**. Correctif dans le document Maia, §2 ter.

### 2. Sur les garde-fous : Chachou a raison, j'ai écrit des consignes en dur

Ce système doit apprendre de ses erreurs et se corriger **lui-même**. J'ai mis des ordres à moi
sur ce chemin. Recensement exhaustif, trois canaux :

#### a) `sages_coaching()` — les chiffres sont mesurés, les verbes sont de moi

```sql
when s.taux_reussite >= 65 then s.taux_reussite||'pct FIABLE garde ta ligne'
when s.taux_reussite >= 50 then s.taux_reussite||'pct MOYEN affine'
else                            s.taux_reussite||'pct FAIBLE baisse ta conviction et sois prudent'
```

Cette chaîne part dans le prompt des **cinq Sages** (champ `COACHING`) et dans la matrice
`FIABILITE_SAGES` du module 215. Mesurer un taux de réussite est légitime. **« garde ta ligne »,
« affine », « baisse ta conviction » sont des ordres que j'ai écrits.**

#### b) `oracle_circuit_breakers.notes` — écrites par `check_circuit_breakers`

Ce que reçoivent tous les agents aujourd'hui via `active_circuit_breakers` :

> « Win rate 30.8% sur 39 decisions evaluees : **le probleme est la SELECTION, pas la frequence.
> Moins de decisions, plus de conviction.** »

Le premier membre est une mesure. Le second est ma conclusion, présentée à l'agent comme un fait.

#### c) `generate_daily_journal` §6 — dans SES messages, trois fois par jour

> « Regle : le de-staking coute surtout le delai (Nj sans pouvoir vendre) ; le rendement perdu est
> minime. **Garder de preference les APY eleves (ATOM 21%, TON 17.67%)** ; liberer les autres si un
> trade le justifie. »

Deux problèmes en une phrase : c'est **mon** arbitrage, et il est écrit avec des **valeurs en dur**
(ATOM 21 %, TON 17,67 %) alors que `v_staking_point` donne ces chiffres en direct. Cette section est
présente dans tous les points jusqu'à celui du 26/08 13:10.

#### d) Les blocs AUTOCRITIQUE ajoutés aux dix prompts

Ajoutés le 21/08 dans les 10 modules. Ils ne demandent pas à l'agent de se corriger : **ils lui
dictent la correction.**

> « repetition_identique_perdante : tu repetes le meme geste en perdant, change de these ou ne fais
> rien, ne repete pas. pertes_consecutives_5 : reduis les tailles et coupe les positions perdantes.
> win_rate_faible : ton probleme est la SELECTION et pas la frequence, moins de decisions et plus
> de conviction. »

Et pour les Sages : « Si ton score est FAIBLE, baisse ta conviction et resserre tes fourchettes. »

Enfin, hors Supabase, trois `directive` codées en dur dans les edge functions —
`collect-market-data`, `marees-context`, `fx-context` — déjà listées dans `CLAUDE.md`.

---

## Combien le projet a bougé depuis le 13/08

### Les prompts

| Agent | avant le 13/08 | aujourd'hui | écart |
|---|---|---|---|
| **Archimage Marées** | 1 344 | 4 943 | **+268 %** |
| **Sage Macro** | 2 708 | 5 300 | **+96 %** |
| Sage Mémoire | 3 116 | 4 474 | +44 % |
| **Alchimiste (RÉEL)** | 4 994 | 6 886 | +38 % |
| Sage Technique | 2 562 | 3 483 | +36 % |
| Sage Risque | 3 916 | 4 599 | +17 % |
| Archimage JU | 6 269 | 7 042 | +12 % |
| Archimage SYL | 5 941 | 6 603 | +11 % |
| Archimage GIL | 5 773 | 6 434 | +11 % |
| Sage Flash | 5 219 | 4 906 | −6 % |

Tout n'est pas de même nature, et il faut le dire :

**Ce qui répare une panne** — légitime, à garder : la correspondance Fear & Greed du Macro (il
inventait ses paliers), la liste des clés de CTX à lire (il déclarait le contexte « ambigu »), les
règles structurelles de Revolut X spot pour l'Alchimiste (il proposait de vendre des actifs stakés
donc invendables), le format JSON strict.

**Ce qui dicte la conclusion** — c'est ce que Chachou dénonce, et il a raison : les blocs
AUTOCRITIQUE, le COACHING impératif, les notes de coupe-circuit.

### Supabase

**214 migrations au total, dont 101 depuis le 13/08** — 47 % de la base de données a été écrite en
treize jours. 70 tables, 57 vues.

### GitHub

**198 commits au total, dont 176 depuis le 13/08.** Le dépôt comptait 22 commits avant.

| jour | commits | | jour | commits |
|---|---|---|---|---|
| 13/08 | 7 | | 19/08 | **48** |
| 14/08 | 11 | | 20/08 | 8 |
| 15/08 | 12 | | 21/08 | 13 |
| 16/08 | 1 | | 22/08 | 10 |
| 17/08 | 32 | | 23/08 | 5 |
| 18/08 | 23 | | 25–26/08 | 7 |

### Make

**78 modules avant le 13/08, 80 aujourd'hui. Aucun supprimé**, deux ajoutés (20022 ⛓️ LES CHAÎNES
DU SCELLÉ, 20023 🌾 LA RENTE DES SCELLÉS — les deux sources de staking de l'Alchimiste). Quatre
Sages ont changé de moteur, pour des raisons documentées (modèle Groq décommissionné, puis quota
Groq dépassé).

**L'architecture est intacte.** Ce qui a changé, c'est le contenu des prompts et le volume de la
base.

---

## Ce que je propose de défaire — décision de Chachou, je n'applique rien seul

| # | Où | Ce que je retire | Ce que je garde |
|---|---|---|---|
| 1 | `sages_coaching()` | « garde ta ligne », « affine », « baisse ta conviction et sois prudent » | le taux de réussite et le nombre d'observations, bruts |
| 2 | `check_circuit_breakers` | les notes qui concluent (« le probleme est la SELECTION… ») | le motif, la valeur, le seuil |
| 3 | `generate_daily_journal` §6 | toute la phrase « Regle : … Garder de preference les APY eleves (ATOM 21%, TON 17.67%) » | le tableau des lignes stakées, chiffres en direct |
| 4 | les 10 prompts, bloc AUTOCRITIQUE | les quatre phrases qui dictent la correction par motif | la consigne d'autocritique elle-même, et le fait que les coupe-circuits soient des mesures |

Le principe qui les réunit : **un agent doit recevoir la mesure, pas la conclusion.** C'est lui qui
conclut — sinon il n'apprend rien, il obéit.

Les points 1, 2 et 3 sont dans Supabase, je peux les faire. Le point 4 passe par Maia.

---

## Ce que je propose de NE PAS défaire, et pourquoi

- Le **coupe-circuit branché dans `execute-trades`** (v42). Ce n'est pas une consigne à un agent :
  c'est un garde-fou d'exécution, au même titre que le plafond de levier ou le plafond de notionnel
  qui existaient déjà. Il ne dit pas à GIL quoi penser, il l'empêche d'ouvrir au-delà de 8 % de
  drawdown. Le 26/08 à 16:17 il a refusé un achat SQQQ et laissé passer une vente LINKUSD.
- Les corrections de **plomberie** des prompts (clés de CTX, format JSON, réalité spot de
  Revolut X). Sans elles, les agents produisent des sorties inexploitables.
- Le **`thinkingBudget: 0`** du Sage Mémoire : c'est un réglage d'API, pas une opinion.
