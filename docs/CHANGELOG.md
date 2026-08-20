# Journal des changements & décisions — AETHER / OPUS 2050

> Historique des choix, corrections, améliorations et analyses. Sert de mémoire longue pour le suivi
> sur plusieurs mois. Ajouter une entrée **datée** à chaque changement significatif (décision, fix,
> amélioration, analyse). Le détail de certains sujets vit dans `docs/decisions/`.

Format : `AAAA-MM-JJ` — **Sujet** — quoi + pourquoi + où.

---

## 2026-08-20 — Audit complet des agents : 7 anomalies, dont 3 serieuses

Correspondance Fear & Greed verifiee dans le module 201, au bon endroit. **Pas encore eprouvee** :
aucun run depuis 23:22, le prochain est a 09:00.

Detail complet : `docs/decisions/AUDIT-AGENTS-2026-08-20.md`.

| # | Agent | Anomalie | Gravite |
|---|---|---|---|
| 1 | Sage Risque | **Invente le VIX** : cite 14.2, 17, 18 alors que le reel est 15,84. Meme reference `{{CTX}}` que le module 201 qui etait aveugle. | serieux |
| 2 | SYL | **Pouvoir d'achat a 0 $**, levier 3,35x. Trois ordres rejetes le 19/08 pour « insufficient buying power ». | serieux |
| 3 | SYL | **Le short GLD ne peut pas etre solde** : rachat envoye en notionnel (121 titres) pour une position short de 22,85. Rejete 3 fois en 2 jours. | serieux |
| 4 | Meta-Cerveau | Pondere sur PnL, drawdown et win rate — **ni le levier ni la marge disponible**. SYL recoit 56 % du poids alors qu'il ne peut plus executer. | moyen |
| 5 | Marees | **17 trades clos, 0 gagnant.** EUR-USD vente, USD-JPY achat, USD-CHF achat : le meme pari dollar-en-hausse, alors que le dollar recule de 1,03 %. Win rate 57 % -> 35,6 %. 68 positions ouvertes, ~40 sur ce meme pari. | serieux |
| 6 | Alchimiste | 50 propositions sur 7 jours, **toutes expirees**. Dernier ordre reel le 13/08. Pas une panne — le flux attend la validation de Chachou. | a decider |
| 7 | Sage Memoire | Absent du run de 23:22 (4 Sages sur 5). Une seule occurrence. | a surveiller |

### Verifie et sain

- **Verrous d'univers : 0 violation en 7 jours** (JU/ETF, SYL/actions, GIL/SPY-QQQ, crypto=GIL).
- **Sage Memoire : chiffres exacts** — win rates au point pres contre `oracle_brain_state`.
- **Sage Flash** : titres reels et dates.
- Staking exact 5 runs de suite, garde-fou short actif, clés saines, 80 modules.

### Note de methode

Le « MAREES 57 % » du Sage Memoire semblait faux face aux 35,6 % actuels. Verification faite :
la mise a jour a eu lieu a 00:55, **apres** le run de 23:22. Le Sage avait raison au moment ou il
a parle. C'est la chute de Marees qui est reelle, pas une erreur de lecture.

---

## 2026-08-19 (suite 17) — Les 3 indicateurs sont branches. Le Sage Macro analyse. Un champ reste faux.

Run de 23:22. Maia a tout applique — verifie dans le blueprint : les 4 champs `DXY_TREND`,
`DXY_VAR20J`, `OR_ARGENT`, `CREDIT_HYG_LQD` sont en fin de CTX, la phrase INDICATEURS est remplacee,
le message user reste `CTX={{110.value}}`, 80 modules, et aucun correctif de la journee n'a recule.

### Le Sage Macro analyse pour de vrai

| Champ | 14 jours de gel | 22:18 | **23:22** |
|---|---|---|---|
| `macro_score` | 55 puis 50 | 60 | **55** |
| `macro_regime` | NEUTRAL toujours | BULL | **NEUTRAL** |
| `rate_pressure` | NEUTRAL toujours | NEUTRAL | **HAWKISH** |
| `news_catalyst` | « CTX est ambigu » | catalyseur reel | **« Oil, inflation, Fed minutes, and AI-driven earnings/capital spending »** |
| `dxy_trend` | NEUTRAL par defaut | « DXY missing » | **NEUTRAL, calcule** |

Plus aucune mention de « missing ». `yield_curve = NORMAL` reste juste : T10Y 4,71 − T2Y 4,19 = +0,52.

### Une erreur reelle, a corriger

`fear_greed_level = GREED` alors que la donnee dit **46, label « Fear »**. Verifie en appelant
`collect-market-data` : `fear_greed: 46`, `fear_greed_label: Fear`, `data_quality: 100`.

Cause identifiee : le prompt systeme donne les seuils du VIX (15 / 20 / 25 / 30) mais **aucune table
de correspondance** pour les 5 valeurs de `fear_greed_level`. Il ne donne que les deux regles
contrariantes (< 20 achat, > 80 vente). Le modele doit donc deviner le mapping — et se trompe.

`recommended_bias = RISK_ON` decoule de cette erreur : avec un Fear&Greed a 46, rien ne justifie
un biais risque.

### Sage Memoire absent de ce run

4 Sages sur 5 : Flash, Macro, Risque, Technique. Le Memoire n'a rien ecrit. **Premiere fois sur les
5 derniers runs** — les 4 precedents avaient bien 5 Sages. Le run n'est pas mort pour autant
(succes, completude 100 %). A surveiller ; si cela se reproduit, regarder le module 207 cote Groq.

### Etat du run

`success`, completude 100 %, 7 ordres (2 achats, 5 ventes), Discord envoye.
**Staking : 7 lignes, 150,99 $** — cinquieme run consecutif exact.

---

## 2026-08-19 (suite 16) — Les 3 indicateurs manquants du Sage Macro + verification des runs

### Les runs vont bien : les 3 derniers sont alles au bout

Chachou avait l'impression qu'ils ne terminaient pas. Journal Make :

| Depart | Duree | Operations | Statut |
|---|---|---|---|
| 21:15 | 2 min 00 | 76 / 76 | succes |
| 22:01 | 2 min 09 | 76 / 76 | succes |
| 22:17 | 2 min 13 | 76 / 76 | succes |

Aucun echec depuis 18:31. Un run complet dure **environ 2 min 15** et la notification n'arrive qu'a
la toute fin de la chaine — d'ou l'impression d'attente.

### Les 3 indicateurs, cote Supabase (fait et verifie)

Le Sage Macro repondait « DXY missing » : son prompt reclame `dxy_trend`, le ratio or/argent et le
spread HYG-LQD, **absents des 92 champs de CTX**.

1. **Ingestion** : `HYG`, `LQD`, `UUP` ajoutes au cron `ingest-indices-daily`, et charges sur 30
   jours immediatement (HYG 252 bougies, LQD 225, UUP 254 ; GLD et SLV rafraichis a 365).
   `UUP` sert de mandataire cote du dollar index : le DXY n'est pas negociable, donc absent d'Alpaca.
2. **Vue `v_macro_extra`** :

| Indicateur | Valeur mesuree |
|---|---|
| `dxy_trend` | **NEUTRAL** (dollar a -1,03 % sur 20 seances, seuils ±1,5 %) |
| `ratio_or_argent` | **6,893** |
| `credit_hyg_lqd_20j_pct` | **+0,10** (leger appetit pour le risque) |

3. **`get_oracle_context()`** expose le bloc `macro_extra` — meme module 105 que CTX utilise deja
   pour FLASH_INTEL et CIRCUIT_BREAKERS, donc chemin eprouve et aucun nouveau module Make.

### A faire cote Make

`docs/decisions/PROMPT-MAIA-CTX-DXY-OR-ARGENT-CREDIT-2026-08-19.md` : 4 champs a ajouter en fin de
la variable CTX (module 110) et une phrase a remplacer dans le prompt systeme du 201.

### Reserve honnete

Le niveau absolu de UUP (27,90) **n'est pas** la valeur du DXY. Seuls la tendance et la variation
sont transmis au Sage ; le niveau brut ne l'est jamais, pour qu'il ne puisse pas le confondre.

---

## 2026-08-19 (suite 15) — RESOLU : le Sage Macro est vivant. C'etait la reference {{CTX}}.

Run de 22:18. Une seule modification depuis le run precedent : dans le message user du module 201,
`CTX={{CTX}}` remplace par `CTX={{110.value}}` — la reference directe a la sortie du module qui
construit CTX.

| Champ | Avant (52 runs, 14 jours) | Run de 22:18 |
|---|---|---|
| `macro_regime` | `NEUTRAL` **sans exception** | **`BULL`** |
| `macro_score` | 55 puis 50 — 2 valeurs en 14 j | **60** |
| `spy_trend` | `FLAT` | **`UP`** |
| `yield_curve` | `FLAT` | **`NORMAL`** |
| `urgency` | `LOW` | **`MEDIUM`** |
| `recommended_bias` | `NEUTRAL` | **`RISK_ON`** |
| `news_catalyst` | « CTX est ambigu » | **« AI investment, IPO revival, and geopolitics driving mixed risk appetite »** |

`yield_curve = NORMAL` est la preuve la plus nette qu'il calcule desormais : T10Y 4,72 − T2Y 4,19 =
**+0,53**, et la regle de son propre prompt dit « superieur a 0 = courbe normale ». Il repondait
`FLAT` par defaut depuis deux semaines.

### Ce que j'ai eu faux, et ce que le detour a apporte

Le gel n'etait **pas** du au modele `sonar-pro` : c'etait la resolution de la variable par nom dans
ce module precis. Le passage sur Groq n'a pas repare le Sage — mais il a transforme un « CTX est
ambigu » inexploitable en « Missing keys:VIX,SPY,SPY_CHG,… », et c'est cette liste qui a permis de
localiser la panne. Le detour n'etait pas inutile ; ma conclusion, si.

### Reste un manque reel, mineur

`news_catalyst` se termine par « ;DXY missing ». C'est exact : **DXY n'est dans aucun des 92 champs
de CTX**, alors que le prompt systeme reclame `dxy_trend`. Le Sage le signale honnetement au lieu
d'inventer. Meme situation pour le ratio or/argent et le spread HYG-LQD. A ajouter au module 110 si
on veut ces trois indicateurs, sinon a retirer du prompt.

### Etat du run

`success`, **completude 100 %**, 6 ordres (2 achats, 4 ventes), 5 Sages OK, Discord envoye.
**Staking : 7 lignes, 150,99 $** — quatrieme run consecutif exact.

---

## 2026-08-19 (suite 14) — Le Sage Macro ne recoit PAS CTX. Mon diagnostic precedent etait faux.

Run de 22:02. Le module 201 tourne bien sur Groq (verifie dans le blueprint), et sa reponse est
desormais exploitable :

```
"news_catalyst": "Missing keys:VIX,SPY,SPY_CHG,FG,T10Y,T2Y,FED,CPI,DXY,GOLD_SILVER_RATIO,HYG_LQD_SPREAD,MACRO_SHOCK"
```

### Correction : ce n'etait pas le modele

J'ai attribue le gel a `sonar-pro`, modele de recherche web. **C'etait faux.** Le changement de
modele n'a pas repare le Sage — il a seulement transforme un « CTX est ambigu » inutilisable en une
liste precise de cles manquantes. C'est ce qui a permis le vrai diagnostic, mais la cause est
ailleurs.

### Ce qui est etabli

1. **CTX est correctement construit.** Sortie memorisee du module 110 :
   `DATE=2026-08-19 18:40|VIX=15.84|FED=3.63|CPI=332.813|T10Y=4.72|T2Y=4.19|SPY=…`
2. **Le module 201 ne le recoit pas.** Il declare manquantes des cles qui sont demonstrablement
   presentes dans CTX — VIX en tete.
3. **Le module 203 (Technique), lui, le recoit.** Meme reference `{{CTX}}`, meme fournisseur Groq :
   **8 valeurs distinctes de `tech_score` (40 a 68) sur 53 runs**, 4 phases de cycle, 3 ETF. Son
   seul autre champ d'entree est `MACRO`, constant depuis 14 jours — la variation ne peut donc venir
   que de CTX.

Conclusion : `{{CTX}}` se resout pour le 203 et pas pour le 201. La raison n'est pas etablie, et je
ne la devinerai pas — l'etape suivante est une experience, pas une theorie.

### Experience proposee (1 caractere de diff)

Module 201, message user : `CTX={{CTX}}` -> `CTX={{110.value}}`, la reference directe a la sortie du
module qui construit CTX. Si les cles arrivent, le probleme etait la resolution par nom.

### Le reste du run

Statut `success`, completude 90 %. **Staking : 7 lignes, total 150,99 $** — troisieme run consecutif
juste, le correctif du 10012 tient. Garde-fou short actif, aucun renfort de position perdante.

---

## 2026-08-19 (suite 13) — Sage Macro reellement fige : il tourne sur un moteur de recherche

Alerte Vigie : « 4 Sages FIGES ». Verification sur **14 jours** au lieu des 6 runs de la regle :
**un seul** Sage est reellement bloque.

| Sage | Runs 14 j | Valeurs distinctes | Verdict |
|---|---|---|---|
| **Macro** | 52 | **1** (`NEUTRAL` sans exception) | **fige** |
| Risque | 53 | 2 | limite |
| Memoire | 52 | 4 | sain |
| Flash | 61 | 3 | sain |

`macro_score` = **55 sur tous les runs du 06 au 15/08**, puis **50 depuis le 17/08**. Deux valeurs
en deux semaines, pendant que le BTC passait de 63 000 a 68 700 $.

### Cause : le mauvais moteur

Croisement sans ambiguite — le seul Sage qui recoit CTX **et** tourne sur un modele de recherche web
est le seul fige :

| Sage | Endpoint | Modele | CTX | Etat |
|---|---|---|---|---|
| **Macro (201)** | **api.perplexity.ai** | **sonar-pro** | oui | **fige** |
| Flash (209) | api.perplexity.ai | sonar-pro | **non** | sain |
| Memoire (207) | api.groq.com | gpt-oss-120b | oui | sain |
| Technique (203) | api.groq.com | gpt-oss-120b | oui | sain |
| Risque (205) | api.mistral.ai | mistral-large | oui | limite |

`sonar-pro` traite le message comme une **requete de recherche**. On lui envoie 8 421 caracteres de
champs separes par des barres verticales ; il les cherche sur le web au lieu de les analyser.

Sa sortie l'ecrit noir sur blanc dans `news_catalyst` : « inflation » sur les 48 runs du 06 au 15/08,
puis **« CTX est ambigu ; aucune donnee macro exploitable » sur 16 runs sur 16 depuis le 17/08**.

### Les donnees etaient parfaites

Module 102, `data_quality = 100` : VIX 15,84 · SPY 770,57 · BTC 68 686 · Fear&Greed 46 · CPI · taux ·
FX, et un CATALYST reel. CTX bien forme : **92 champs, 8 421 caracteres**. Ni la donnee ni CTX ne
sont en cause — seulement le moteur qui les lit.

### Correctif Supabase applique : la regle de la Vigie

Elle comparait **un** champ sur **6 runs**. Sur une seance calme, NEUTRAL/LOW/MEDIUM/SYL se repetent
naturellement : 4 Sages signales pour un seul malade. Desormais deux niveaux —
**ALERTE** (6 runs, a surveiller) et **FIGE** (12 runs sur 72 h, confirme). `v_vigie_resume` compte
ALERTE parmi les alertes (niveau ORANGE).

Apres correction, la Vigie dit exactement ce que montrent les mesures : **Macro FIGE**, Flash /
Memoire / Risque ALERTE, Technique OK.

Le seuil long est a 12 runs et non 20 : a ~5 runs/jour, 72 h n'en contiennent que 16, et 20 n'etait
jamais atteignable.

### A faire cote Make

`docs/decisions/PROMPT-MAIA-SAGE-MACRO-FIGE-2026-08-19.md` : basculer le module 201 sur Groq
(URL, en-tete Authorization copie du 207, modele `openai/gpt-oss-120b`, `response_format` en
`json_object`) et ajouter au prompt systeme une consigne de lecture explicite des cles de CTX.

**Controle de guerison** : `macro_score` doit varier d'un run a l'autre. Deux valeurs en 14 jours,
c'est le symptome ; un score qui bouge, c'est repare.

### Point ouvert

Le Sage Risque n'a produit que 2 valeurs de `risk_level` en 53 runs. A reexaminer apres la
reparation du Macro : il recoit `MACRO={{202.macro_regime}}`, donc une partie de son immobilite
vient peut-etre de ce qu'on lui repete NEUTRAL depuis 14 jours.

---

## 2026-08-19 (suite 12) — Garde-fou : interdiction de renforcer une vente a decouvert perdante

Demande par Chachou apres l'analyse du short MSTR de GIL. **execute-trades v38**, cote Supabase
uniquement — aucune modification Make.

### Le trou dans la protection existante

```js
if (pending.has(sym) || (heldMV[sym] || 0) > 0) { ... 'short_blocked_position' }
```

Ce test bloque l'ouverture d'un short quand une position ACHETEUSE existe. Mais sur un short,
`market_value` est **negatif** : la condition etait fausse, l'ordre passait, et il **agrandissait**
la position. Le 19/08, GIL a ainsi renforce deux fois un short MSTR deja a -10 % (14 952 $ a 15:48,
puis 2 963 $ a 18:41).

### La regle ajoutee

`RENFORT_SHORT_PERTE_MAX = -0.05` : si un short existe deja sur le ticker **et** perd plus de 5 %,
l'ordre est refuse et journalise sous `renfort_short_perdant_bloque`, avec la perte constatee, le
seuil et l'exposition.

Ce que le garde-fou **ne bloque pas**, volontairement :
- l'ouverture d'un **nouveau** short (aucune position en cours) ;
- le **rachat** (`buy`) qui deboucle une position — c'est un ordre d'achat, il ne passe pas par la ;
- la vente d'une position **reellement detenue** ;
- le renfort d'un short **gagnant**.

### Test realise avant mise en service

Appel reel de la fonction avec un notionnel de **1 $** — trop petit pour produire un ordre meme si
le garde-fou avait echoue. Resultat : **0 ordre execute, 0 rejete**.

| Ticker | Perte latente | Verdict |
|---|---|---|
| **MSTR** | **-8,08 %** | **`renfort_short_perdant_bloque`** (exposition -549 942 $) |
| XLE | — | `short_not_downtrend` (garde momentum anterieure, atteinte avant) |
| TQQQ | short **gagnant** | garde-fou **franchi**, puis `short_too_small` |

TQQQ prouve le point important : un short en profit reste renforcable. Le garde-fou ne se declenche
que sur les positions perdantes.

### Effet immediat sur les positions du soir

Bloques au renfort : **GIL XLE** (-10,43 %), **GIL MSTR** (-7,77 %), **SYL SLV** (-7,57 %).
Les 14 autres ventes a decouvert du systeme restent renforcables.

### Ce qui n'est pas fait

Le levier de SYL (3,3x, 3,04 M$ de shorts obligataires pour 1,05 M$ de capital) n'est pas plafonne.
C'est une decision de gestion distincte, a arbitrer separement.

---

## 2026-08-19 (suite 11) — Les 4 correctifs demandes par Chachou, appliques et verifies

Suite a « tous les comptes se sont pete la figure aujourd'hui ». Verite etablie en interrogeant
**Alpaca directement** (`/v2/account` et `/v2/account/portfolio/history`), pas la console.

### Correction d'une erreur de diagnostic de ma part

J'avais annonce deux bugs d'arithmetique dans `v_gains_traders` (« pourcentage calcule sur le gain »,
« multiplie par le capital entier »). **C'etait faux** : `v_comparaison` rapporte deja le gain cumule
au capital de depart, et `gain_usd` redonnait exactement la variation en dollars. Le calcul etait bon.
Le probleme etait **la donnee** : des instantanes pris a l'heure des runs, donc en pleine seance.

### Point 1 — les courbes s'appuient sur la cloture officielle Alpaca

Ecart mesure entre la base et Alpaca sur 7 jours : **-12 925 $ a +32 382 $** les jours normaux
(simple decalage intra-seance), et **+182 624 $ sur JU le 18/08**.

- Nouvelle table `alpaca_equity_daily` (52-53 jours par compte, du 04/06 au 19/08), alimentee a
  chaque run par **update-brain v19**, qui lisait deja cet historique sans l'archiver.
- `v_comparaison` et `v_equity_points` reecrites dessus.

| Affichage « jour » | Avant | Apres | Cloture Alpaca |
|---|---|---|---|
| JU | -17,95 % (-179 462 $) | **+0,70 % (+6 999 $)** | 1 047 365 -> 1 054 319 |
| GIL | -6,93 % (-69 299 $) | **+3,27 % (+32 700 $)** | 1 040 367 -> 1 073 037 |
| SYL | -2,43 % (-24 299 $) | **-0,65 % (-6 500 $)** | 1 091 405 -> 1 084 884 |
| AETHER | **-9,10 % (-273 060 $)** | **+1,10 % (+33 199 $)** | — |

### Point 2 — mesures aberrantes neutralisees

Colonne `oracle_performance.fiable` (les lignes sont conservees, jamais supprimees). Marquees false :
- **4 lignes JU du 18/08** (gain 222 007 a 230 200 $ ; cloture Alpaca : 47 576 $) ;
- **2 lignes du 07/07** (JU -665 308 $, GIL -871 345 $ : calibration ratee).

Garde-fou ajoute : `v_perf_anomalies` liste toute mesure s'ecartant de plus de 5 % du capital face a
la cloture Alpaca. **Aucune exclusion automatique** — une vraie chute ne doit jamais etre masquee.

### Point 3 — exposition brute et levier affiches

Nouvelle vue `v_exposition_traders` + section « Exposition reelle & levier » dans la console (b7).
La somme nette masquait les ventes a decouvert, qui annulent les achats :

| Compte | Achats | Ventes a decouvert | Engage (brut) | Levier |
|---|---|---|---|---|
| **SYL** | 401 149 $ | **-3 041 036 $** (TLT, IEF) | 3 442 184 $ | **3,3x — ELEVE** |
| GIL | 1 003 062 $ | -920 234 $ | 1 923 296 $ | 1,9x |
| JU | 846 153 $ | -306 600 $ | 1 152 752 $ | 1,1x |

Confirme par Alpaca : SYL `short_market_value` = -3 119 834 $, `multiplier` = 4.

### Point 4 — cost_basis, avg_entry_price et side suivent enfin le courtier

Cause trouvee dans `sync_alpaca_positions` : le `ON CONFLICT ... DO UPDATE SET` **omettait ces trois
colonnes**. Elles restaient figees a la valeur du tout premier INSERT — d'ou SYL XLF a 0,42 $ avec un
`cost_basis` de 149 497 $ (facteur 388 611), et JU META marque `long` avec une quantite de -59.

Apres correction et resynchronisation des 76 positions : **0 ligne incoherente** sur cost_basis,
**0 ligne** ou `side` contredit le signe de la quantite.

### Ce qui reste, et qui n'est pas un bug

GIL porte un short MSTR de **-558 353 $** en perte latente de **-52 485 $ (-10,4 %)**, renforce deux
fois le 19/08 (sell 14 952 $ puis 2 963 $) — un `sell` sur un titre non detenu augmente la vente a
decouvert. Encadrer ce comportement est une **decision de gestion qui appartient a Chachou**, pas une
correction technique.

---

## 2026-08-19 (suite 10) — RÉSOLU : le dé-staking est enfin exact, et les runs ne meurent plus

Run manuel de **18:40 (16:40 UTC)** — **76 opérations sur 76**, succès. Les deux correctifs appliqués
par Maia sont dans le blueprint (relu à 16:43) et produisent le résultat attendu.

### Module 205 (Sage Risque) — le run ne meurt plus

`max_tokens` 800 → **2000**, et la clause LANGUE bornée à 200 caractères par champ texte.
Effet mesuré : la sortie du Sage Risque passe de **2 951 à 985 caractères**, soit environ 275 tokens
pour un plafond de 2 000 — une marge de 7×, contre une marge négative auparavant.

Historique de la panne : 4 échecs `ParseJSON` à 19 opérations sur 76 (18/08 16:31, 19/08 07:04,
19/08 10:13, 19/08 16:31). Les runs qui passaient ne le devaient à aucun correctif : la sortie
retombait simplement sous le plafond (965 à 3 009 caractères pour une limite à ~2 900).

**À noter comme erreur de méthode de ma part** : j'ai affirmé le matin du 19/08 que « le correctif
max_tokens 2000 tient », en me fondant sur la réussite des runs au lieu de lire la valeur dans le
blueprint. Elle valait 800. Un correctif n'est acquis que lorsqu'il est **lu** dans le blueprint.

### Module 10012 (Alchimiste) — les 21 valeurs sont exactes

Retour au texte brut (`STAKING_DELAIS=` sans Base64), les 3 phrases du prompt système, plus une
consigne ajoutée : une ligne par devise présente, sans omission.

| Devise | montant_usd | attendu | apy_staking_pct | delai_deblocage_jours |
|---|---|---|---|---|
| SOL | 90,27 | 90,27 ✅ | 6,16 ✅ | 3 ✅ |
| ETH | 27,02 | 27,02 ✅ | 2,45 ✅ | 5 ✅ |
| KSM | 14,67 | 14,67 ✅ | 10,47 ✅ | 7 ✅ |
| TON | 7,91 | 7,91 ✅ | 17,67 ✅ | 2 ✅ |
| ATOM | 5,87 | 5,87 ✅ | 21,06 ✅ | 21 ✅ |
| OSMO | 4,91 | 4,91 ✅ | 5,39 ✅ | 14 ✅ |
| TRX | 0,34 | 0,34 ✅ | 3,26 ✅ | 14 ✅ |

Total **150,99 $** contre **150,98 $** déclarés par Revolut. 7 devises sur 7, 21 valeurs sur 21.

### Chronologie complète du feuilleton dé-staking

| Run | Configuration 10012 | Montants | Délais |
|---|---|---|---|
| 17/08 → 18/08 | Base64 + clé 20022 corrompue | inventés (TON 787 $ pour 7,91 $) | 0 |
| 19/08 10:28 | Base64, clé réparée | faux | 0 |
| 19/08 11:11 | texte brut, séparateur `\|` | 0 | 0 |
| 19/08 11:56 | texte brut, séparateur `;` | **7/7 exacts** | **7/7 exacts** |
| 19/08 12:00 | Base64 (revert) | 0 | exacts |
| 19/08 15:48 | Base64 | 5 devises, 1 fausse, ETH+TON perdus | exacts |
| 19/08 18:40 | texte brut + consigne « sans omission » | **7/7 exacts** | **7/7 exacts** |

### Reste du run

5 Sages `ok`, 3 Archimages ont répondu, `data_completeness` 100 %, phase DEFENSIVE,
10 ordres passés (1 achat, 9 ventes), Discord envoyé, aucun circuit breaker.
80 modules avant / 80 après ; module 20022 intact (clé valide, URL en alias).

### Point ouvert

Trois correctifs validés se sont retrouvés absents du scénario au cours de la journée : la clé JWT du
20022 (deux fois, sur deux caractères différents du jeton), le `max_tokens` du 205, et le mapping du
10012. La cause n'est pas identifiée. **Règle retenue : revérifier le blueprint après chaque
sauvegarde et avant chaque run** ; ne jamais considérer un correctif comme acquis parce qu'un run a
réussi. Si le phénomène se reproduit, exporter le blueprint qui fonctionne et le conserver comme
référence restaurable d'un bloc.

Détail : `docs/decisions/PROMPT-MAIA-205-ET-10012-2026-08-19-SOIR.md`.

---

## 2026-08-19 (suite 9) — MON ERREUR : le passage en texte brut a cassé les montants du dé-staking

Chachou : « je ne vois plus le staking et il n'y a plus les montants, je pense qu'elle a cassé quelque chose ».
**Ce n'est pas Maia — c'est mon correctif Base64 qui a provoqué la régression.**

### Ce que j'ai raté

Avant de proposer de retirer le Base64, j'ai vérifié que les textes staking ne contenaient ni guillemets,
ni sauts de ligne, ni antislash. **Je n'ai pas vérifié la barre verticale `|`** — qui est précisément le
séparateur de champs du message envoyé à l'Alchimiste :

```
SOLDES_REVOLUTX=…|PRIX_REVOLUTX_B64=…|STAKING_DELAIS=…|STAKING_APY=…|CTX_B64=…
```

Or les deux vues produisaient `ATOM:21j | ETH:5j | KSM:7j | …`. En Base64 c'était inoffensif ; en texte
brut, les barres internes se confondent avec les séparateurs de champs et le modèle ne sait plus où
commence ni finit chaque champ.

**Preuve écrite par le modèle lui-même**, dans sa raison pour ATOM au run de 11:11 :
« *Sans information sur le délai de déblocage…* »

| Run | Encodage | APY | Délais | Montants |
|---|---|---|---|---|
| 10:28 | Base64 | ✅ exacts | ❌ 0 | ⚠️ inventés |
| 11:11 | texte brut | ✅ exacts | ❌ 0 | ❌ **0** |

### Découverte au passage : les montants n'ont JAMAIS été justes

Comparaison avec `v_staking_point` (la vérité) :

| Devise | Montant réel staké | Écrit par l'Alchimiste à 10:28 |
|---|---|---|
| TON | **7,91 $** | 787,07 $ |
| SOL | **90,92 $** | 249,91 $ |
| ATOM | **5,87 $** | 21,09 $ |

Le modèle devait extraire le montant d'un gros bloc de texte (`soldes_texte`, section « EN STAKE »),
croisé avec deux autres vues. Il l'a toujours inventé. Le total de son estimation dépassait la valeur
du portefeuille entier (848 $ pour 169 $ réellement stakés).

### Correctifs appliqués côté Supabase (aucune intervention Make requise)

1. **`v_alc_staking_delais_txt` et `v_alc_staking_apy_txt`** : séparateur interne `|` → **`;`**.
   Plus aucune collision. Vérifié : aucune barre verticale ne subsiste.
2. **Nouvelle vue `v_alc_staking_txt`** — source **unique et complète**, 498 caractères, sans barre :
   `SOL montant=90.92USD apy=6.16% deblocage=3jours cout_destake=0.05USD ; ETH montant=27.13USD …`
   Elle donne d'un coup le montant **réel**, l'APY, le délai et le coût de dé-stake, coin par coin.
   Dépendances vérifiées avant modification : aucune autre vue ne consomme ces trois vues.
3. Schéma versionné dans `supabase/schema/02_views.sql`.

→ Un dernier prompt Maia (module 20022 + 2 phrases du prompt 10012) branche l'Alchimiste sur cette
source unique. Le séparateur `;` étant déjà corrigé, **les délais reviendront même sans ce prompt** ;
les montants exacts, eux, l'exigent.

## 2026-08-19 (suite 8) — RUN COMPLET RÉUSSI : les trois correctifs validés en réel

Run manuel du **19/08 à 10:27** : **76 opérations sur 76**, 118 s, `status: success`, aucune erreur.
Premier run complet depuis le 18/08 14:28.

### ✅ Correctif n°1 — Sage Risque (max_tokens 800 → 2000 + bornage des textes)

| | Avant | Après |
|---|---|---|
| Sortie du Sage Risque | 2 948 car. ≈ **819 tokens** (plafond 800 → tronqué) | 970 car. ≈ **269 tokens** |

Le bornage à 200 caractères a divisé la sortie par 3. Le module 206 parse sans problème. Les 5 Sages ont
tous produit leur analyse à 10:27.

### ✅ Correctif n°2 — Staking : le dé-stake est ressuscité

**7 lignes écrites dans `alc_destake_reco` à 10:28** — les premières depuis le **17/08 20:00**, soit 40 h
de silence. Les **vrais APY Revolut** sont enfin transmis : TON 17,67 % · ATOM 21,06 % · KSM 10,47 % ·
SOL 6,16 % · OSMO 5,39 % · TRX 3,26 % · ETH 2,45 %. Verdicts : **GARDER** sur les 7 (l'APY dépasse
partout le gain de trade attendu de 5-6,5 %). La Vigie ne signale plus « MUET » mais
« dé-stake évalué, raisons lisibles ».

### ✅ Correctif n°3 — Sage Mémoire étendu aux 5 agents

Sa sortie passe de 7 à **11 champs** et couvre enfin tout le Collège :
`ju 49 · syl 54 · gil 51 · **alc 58** · **marees 64**`, `best_agent: MAREES`, `correction_cible: JU`.

⚠️ **Un défaut mineur** : le modèle a mis `best_archimage: "MAR"`, valeur hors de l'énumération attendue
(`JU|SYL|GIL|EQUAL`) — il a confondu avec le nouveau `best_agent`. Le module 215 lit `BEST_ARCH` :
à surveiller au prochain run, à corriger dans le prompt si ça se reproduit.

### ⚠️ Reste à corriger — les délais de déblocage arrivent à 0

L'Alchimiste a écrit `delai_deblocage_jours = 0` pour les 7 devises, alors que la vue envoie bien
`ATOM:21j | ETH:5j | KSM:7j | OSMO:14j | SOL:3j | TON:2j | TRX:14j`. **Le Base64 est confirmé coupable** :
le modèle décode partiellement (APY justes, délais à zéro ; le 18/08 c'était l'inverse).
→ `PROMPT-MAIA-ALCHIMISTE-BASE64-2026-08-18.md`, mis à jour avec cette preuve, est **prêt à envoyer**.

### Le « 0 ordre » du run est NORMAL, pas une panne

17 décisions ont été prises et **toutes bloquées par les garde-fous**, à juste titre :
- `short_market_closed` (TQQQ, MSTR, GOOGL, TLT, IEF) et `us_market_closed_equity_buy` (GLD) —
  il était **06:28 à New York**, marché fermé. Le système a refusé d'envoyer des ordres actions.
- `dust_unsellable` (7 lignes) — les poussières crypto invendables.
- `momentum_downtrend` (BTCUSD), `short_not_downtrend` (V) — filtres de stratégie.

Le Méta-Cerveau a rééquilibré derrière : **GIL 32 → 40 %**, **SYL 42 → 36 %**, **JU 26 → 24 %** (264 runs).

## 2026-08-19 (suite 7) — Le run échoue depuis le 18/08 : le Sage Risque déborde son plafond de tokens

Run manuel lancé depuis la console à 10:12:54 → **échec à 10:13:03**, `DataError: Source is not valid JSON`
au module ParseJSON, **19 opérations sur 76**.

- **Cause : module 205 (⚔️ IRON SENTINEL, Sage Risque) plafonné à `max_tokens: 800`** — le plus bas des
  5 Sages — alors qu'il produit la sortie la plus longue : **2 948 caractères ≈ 819 tokens** au maximum
  observé. La réponse est coupée en plein milieu → JSON invalide → le module **206 · 💧 DISTILLATION DU
  RISQUE** plante → tout le run s'arrête.
  Marges des autres Sages : Technique 5,8× · Macro 3,7× · Flash 10× · Mémoire 16×. Le Risque : **dépassé**.
- **Intermittence expliquée** : les sorties du Sage Risque ont grossi (288 tokens le 14/08 → 819 le 17/08).
  Échecs les **18/08 16:31**, **19/08 07:04**, **19/08 10:13** ; succès quand le modèle reste sous 800.
- **Aggravant : 8 champs sur 16 ne servent à personne.** Le schéma déclare 8 champs courts ; le prompt en
  réclame 8 de plus, dont 5 textes libres en français (`prophet_vision`, `portfolio_rationale`, `rationale`,
  `memory_summary`, `evaluations`). Vérification faite : le module **215 · 🔮 LA MATRICE DES SIGNAUX**, seul
  consommateur, ne lit **que les 8 champs du schéma**. Le modèle brûle la moitié de son budget en texte ignoré.
- → **`docs/decisions/PROMPT-MAIA-SAGE-RISQUE-MAXTOKENS-2026-08-19.md`** : prompt prêt, non envoyé.
  Décision retenue : `max_tokens` 800 → 2000 **et** bornage des 5 textes à 200 caractères. On garde les
  champs de raisonnement (affichés dans le dossier du Sage côté console) mais on les encadre.

### Conséquence : le correctif staking n'a pas encore pu être testé

Les modules 20022/20023 (clé réparée à 10:06) se situent **après** le routeur 999. Le run étant mort à la
19ᵉ opération, ils n'ont jamais été atteints. `alc_destake_reco` reste donc figé au 17/08 20:00.

### Deux points signalés par Chachou, aucun n'est une panne

- **« dust_unsellable »** : message normal face aux poussières crypto (qty ~1e-9 de SOL/XRP/BTC) qu'Alpaca
  refuse de vendre car sous le minimum négociable. Le système les saute proprement à chaque run.
  Seul défaut : elles gonflent le compteur « ignorés ». Un nettoyage côté Alpaca les supprimerait.
- **Aucun message Discord** : le module 10031 est en fin de chaîne, jamais atteint. Il reviendra avec un
  run complet.
- **La console a bien fonctionné** : `v_scenario_etat` confirme run déclenché à 10:12:54 et coupure
  automatique à 10:20:00. Le run n'apparaît pas dans la liste parce que `oracle_college_runs` n'est écrit
  qu'en fin de chaîne.

## 2026-08-19 (suite 6) — Vérification après passage de Maia + sort de la règle « 3 pertes consécutives »

### Ce que Maia a fait (blueprint enregistré à 09:52:54)

- **Module 207 · 📚 DEEP MEMORY : conforme sur toute la ligne.** 21 variables présentes (dont `ALC_*`,
  `MAR_*`, `JU_BIAS`, `SYL_RUNS/PNL`, `GIL_RUNS/PNL`), mappings `brain_states.CRYPTE_JU` et `.MAREES`
  branchés, schéma passé à 11 champs (`alc_win_rate`, `marees_win_rate`, `best_agent`,
  `correction_cible` ajoutés), 3 scories supprimées (`FORCE_CONTRARIAN`, bloc `prophet_vision`,
  « ANALYSE DE SEQUENCE »), règles multi-agents en place (CIBLAGE, VOLUME INSUFFISANT).
  Paramètres techniques intacts : modèle, température, max_tokens, response_format, URL, timeout, en-têtes.
- **Portée du changement : 80 modules avant, 80 après ; seul le 207 modifié.** Ni le 208, ni le 215.
- **Modules 20022 / 20023 : NON corrigés.** La clé corrompue (`ref: smddzbxebwfnitxuyuyp`) est toujours
  sur les 4 en-têtes. Le prompt staking n'a pas été appliqué → renvoyé seul à Maia.

### La règle « 3 pertes consécutives = changement de régime probable » : ne pas la restaurer

Question de Chachou : « si on avait mis ces règles, elles avaient une raison valable ? » Vérification faite —
**l'intention était bonne, l'implémentation ne pouvait pas fonctionner, et le besoin est déjà couvert ailleurs.**

1. **Pas d'entrée.** `consecutive_losses` existe bien dans `get_oracle_context()->brain_states`
   (JU 0, SYL 2 aujourd'hui) mais n'a **jamais** été mappé dans le message user du module 207. Le Sage
   ne recevait pas l'information dont la règle avait besoin.
2. **Pas de sortie.** Aucun champ du schéma (7 champs à l'époque, 11 aujourd'hui) ne peut porter un
   « changement de régime ». Le modèle n'avait aucun moyen de l'exprimer.
3. **Déjà couvert, et mieux.** `check_circuit_breakers()` déclenche un breaker `pertes_consecutives_5`
   dès `consecutive_losses >= 5`, avec action `prudence_maximale_demandee` — déterministe, en base,
   et qui **agit** au lieu de décrire. Déjà déclenché **2 fois**, la dernière le **17/08 à 12:19**,
   auto-résolu depuis.

→ **Rien à restaurer.** Conformément à CLAUDE.md (réutiliser l'existant plutôt qu'ajouter), le garde-fou
déterministe prime sur une phrase de prompt inapplicable. Si Chachou veut malgré tout que le Sage
*commente* les séries de pertes, il faudrait un vrai chantier : mapper `JU_STREAK`/`SYL_STREAK`/`GIL_STREAK`
**et** ajouter un champ `regime_alerte` au schéma — sinon la règle resterait décorative.

## 2026-08-19 (suite 5) — Comparaison des deux blueprints Make : Make n'a rien cassé

Chachou craignait qu'un enregistrement Make ait abîmé le scénario. Vérification faite en comparant
**octet par octet** le blueprint lu à 09:12 et celui enregistré à **09:43:26** (même taille : 620 853
caractères, empreintes différentes).

**7 zones de différence, toutes anodines — 2 changements réels :**

| Ce qui a changé | Détail | Impact |
|---|---|---|
| `lastEdit` | `2026-08-17T20:50:38Z` → `2026-08-19T09:43:26Z` | horodatage de l'enregistrement |
| Position du module « L'Alchimiste de la Crypte » | `x: 12900 → 12940`, `y: 1500 → 1453` | **cosmétique** : la boîte a été déplacée sur le canevas |

**Preuve formelle** : en neutralisant `designer` (positions visuelles) et `lastEdit`, les deux blueprints
donnent la **même empreinte SHA-256** (`c4c4d6179b81ecf2583b`). Aucune modification fonctionnelle :
ni prompt, ni clé, ni URL, ni mapping, ni routage, ni planification.

**Re-validation des deux diagnostics sur la version enregistrée à 09:43 :**
- Clé Supabase corrompue (`ref: smddzbxebwfnitxuyuyp`) : **toujours présente sur 4 en-têtes** —
  modules **20022** (`apikey` + `Authorization`) et **20023** (`apikey` + `Authorization`).
- Module **207 · 📚 DEEP MEMORY** : inchangé — schéma à 7 champs (JU/SYL/GIL), **aucune mention de
  `CRYPTE_JU` ni de `MAREES`**, scories `FORCE_CONTRARIAN` et `prophet_vision` toujours là.
  Prompt system + user relus **verbatim** : identiques à l'analyse précédente.

→ Les deux prompts Maia (`PROMPT-MAIA-FIX-CLE-STAKING-2026-08-18.md` et
`PROMPT-MAIA-SAGE-MEMOIRE-5-AGENTS-2026-08-19.md`) restent **valables mot pour mot**.

## 2026-08-19 (suite 4) — Sages : la console cachait 6 champs sur 7 (je m'étais trompé)

Chachou : « je comprends pas, avant il corrigeait tout le monde, va voir dans Make ». Il avait raison.

- **CORRECTION DE MON DIAGNOSTIC PRÉCÉDENT.** J'avais conclu que le Sage Mémoire « ne regarde que JU »
  en comptant les mentions dans le champ `signal` de `sage_detail`. Or ce champ est une **réduction** :
  pour le Mémoire, c'est `left(correction_directive, 40)`. En interrogeant `oracle_sages_report` (la sortie
  brute), le Sage note **les trois Archimages à 100 % des runs, chaque semaine depuis juin**. Ma conclusion
  était fausse ; la vraie cause était un défaut d'affichage, pas un défaut du système.
- **Cause : `sage_detail()` réduisait 7 à 16 champs à une seule ligne.** Chaque Sage produit en réalité une
  analyse structurée — Mémoire 7 champs (`ju/syl/gil_win_rate`, `best_archimage`, `winning_pattern`,
  `failed_pattern`, `correction_directive`), Macro 11, Technique 9, Flash 8, Risque 16. La console n'en
  montrait qu'un. **Migration `sage_detail_sortie_complete`** : la RPC renvoie désormais `derniere_sortie`
  (la sortie brute complète) et `derniere_sortie_le`, sans rien retirer de l'existant.
- **Console** : la modale d'un Sage affiche « Sa dernière analyse complète » avec tous ses champs traduits
  en français (≈ 50 libellés ajoutés : « JU · réussite », « Meilleur Archimage », « Ce qui marche »,
  « Ce qui échoue », « Correction demandée », plus tous les champs Macro / Technique / Flash / Risque).
  Deux réglages d'affichage au passage : une phrase de plus de 30 caractères devient un bloc de texte au
  lieu d'être écrasée dans une case de chiffre, et les pourcentages entiers perdent leurs « .00 ».

### Ce que dit vraiment le blueprint Make (module 207 · 📚 DEEP MEMORY)

Inspection **en lecture seule** du scénario 6183820 :

- Sortie imposée : **7 champs**, dont les win rates des **3 Archimages** + `best_archimage`. Confirmé.
- Mais les **règles** d'analyse ne parlent que de JU (séquence et over-trading testent uniquement `JU_RUNS`),
  et les entrées sont asymétriques : JU reçoit 4 variables, SYL et GIL seulement 3 (pas de `RUNS` ni `PNL`).
- **L'Alchimiste (CRYPTE_JU) et les Marées sont totalement absents** du Sage Mémoire — leurs pipelines sont
  en aval du routeur 999. **Pourtant leurs données arrivent déjà** dans le module 105
  (`brain_states.CRYPTE_JU` 38 runs WR 52,6 % · `brain_states.MAREES` 25 runs WR 64,0 %) : elles sont
  simplement non mappées. Aucune nouvelle source ne serait nécessaire.
- Trois scories dans le prompt : un `FORCE_CONTRARIAN` absent du schéma, un bloc « LANGUE » copié d'un autre
  Sage citant 5 champs inexistants, et une règle qui demande d'analyser « les 3 dernières décisions JU »
  alors que le module ne reçoit jamais l'historique des ordres (module 902 exécuté après le 207).
- → **`docs/decisions/PROMPT-MAIA-SAGE-MEMOIRE-5-AGENTS-2026-08-19.md`** : prompt Maia prêt, non envoyé.
- ⚠️ **Sécurité** : le blueprint contient en clair une clé API Groq et la clé anon Supabase. CLAUDE.md
  impose Vault → rotation de la clé Groq recommandée. Rien modifié, décision de Chachou.

## 2026-08-19 (suite 3) — Le plafond de 1000 lignes de PostgREST mangeait 3 marchés + la moitié de SYL

Chachou : « MSCI World, XRP et Pétrole je ne peux plus les sélectionner, soi-disant ils n'ont plus de séries ! »
Le grisage des pastilles ajouté plus tôt n'était pas une fausse alerte : c'était un **diagnostic juste**.

- **CAUSE : PostgREST plafonne toute réponse à 1000 lignes, côté serveur.** `v_comparaison` en compte
  **1204**, triées par série alphabétique. Les dernières de l'alphabet étaient donc purement et simplement
  absentes de la réponse : **URTH (MSCI World) 0/51, USO (Pétrole) 0/51, XRP-USD 0/76**, et **SYL amputée
  de moitié (26 points sur 52)** — la courbe d'une de tes propres stratégies était fausse.
- Premier essai `&limit=20000` : **sans effet**, un `limit` client ne dépasse jamais le plafond serveur.
  Vérifié en réel avant de conclure. Solution : `sbAll()` **pagine** par tranches de 1000 (offset).
  Appliqué à `v_comparaison`, `v_equity_points` (835 lignes, sous le plafond mais qui grossit chaque jour)
  et `v_rendements_periodes`. → **oracle-inbox v20 déployée**, vérifiée en réel : les 22 séries remontent,
  SYL repasse à 52 points.
- **Repère de version visible** en bas de page (`build 2026-08-19 · b5`) + en-têtes anti-cache. La question
  « as-tu poussé la version corrigée ? » se répond maintenant d'un coup d'œil : si le build ne change pas
  après une mise à jour, c'est le cache du navigateur (recharge forcée).
- **Fixtures reconstruites sur la réponse RÉELLE de `dashboard_snapshot()`** (5 cerveaux dont CRYPTE_JU et
  MAREES, `poids`/`doctrine`, `data_completeness`, `raisons_skip` en tableau, `montant`/`quand`).
  C'est ce qui manquait : le banc validait des données que j'avais inventées.

### Constat sur le Sage Mémoire (aucun bug console — c'est le système)

Sur ses **20 derniers signaux évalués** : **7 citent JU**, **13 ne nomment aucun agent**, et **0 citent SYL,
GIL, l'Alchimiste ou les Marées**. La console affiche fidèlement ce qu'il produit. Le Sage Mémoire ne
« regarde » donc réellement que JU. Son prompt vit dans le scénario Make (aucune table de prompts en
Supabase) : la correction passe par **Maia**, pas par moi. À arbitrer par Chachou.

## 2026-08-19 (suite 2) — Méta-Cerveau à zéro : mauvais noms de champs + comparateur incomplet

- **CAUSE RACINE : `dashboard_snapshot()` renvoie `poids` / `doctrine`, la console lisait
  `synthesis_weight` / `current_bias`.** Résultat : poids Méta-Cerveau à 0 %, barres vides et biais
  absents sur les trois Archimages. Vérifié en base : les vraies valeurs existent (JU 0.26, SYL 0.42,
  GIL 0.32) avec des doctrines complètes. La console accepte désormais **les deux conventions**
  (`poidsOf()` / `doctrineOf()`), la RPC comme la lecture directe d'`oracle_brain_state`.
  Deux autres décalages du même type corrigés : `sante_flux.data_completeness` / `circuit_breaker_fired`
  (lus comme `completude` / `circuit_breaker` → « — » dans l'audit) et `debug_execution.raisons_skip`
  (tableau, lu comme `raisons` → colonne vide).
- **La phrase « Dernière correction » du Méta-Cerveau était codée en dur** dans le HTML. Elle affiche
  maintenant `meta_cerveau.doctrine` réel, avec sa date de mise à jour.
- **Les fixtures de test portaient les mauvais noms** — voilà pourquoi le banc ne voyait rien. Elles sont
  reconstruites sur la forme exacte de la RPC. Leçon : une fixture doit venir de la réponse réelle, jamais
  d'une supposition.
- **Sages : phrases coupées** (« REVOIR LA SELECTION DES TRADES JU » tronquée à 42 caractères). Les cartes
  sont refaites : pastille de taux de réussite, signal **complet** sur plusieurs lignes, jauge colorée,
  carte entière cliquable vers le dossier. Contrôle automatique ajouté : aucun `dernier_signal` ne doit
  manquer du rendu.
- **Comparateur des marchés — deux vrais défauts** :
  ① **Les courbes n'étaient pas alignées dans le temps.** `lineChart` étirait chaque série sur toute la
  largeur quel que soit son intervalle réel : une série de 4 points (Alchimiste) paraissait couvrir la
  même période qu'une série de 52. Le traceur construit désormais un **axe de dates commun** (union des
  dates), place chaque point à sa vraie date, ne trace une série que là où elle existe, et l'infobulle lit
  les valeurs réellement alignées.
  ② **La légende ne listait que les stratégies** — sélectionner 15 marchés n'en affichait que 5. Elle liste
  maintenant **toutes** les séries affichées, classées par rendement, avec le compte et la période.
  Les pastilles sans série en base (Marées) sont **grisées et barrées** avec une explication au clic,
  au lieu de rester silencieusement inertes.
- **« Performance dans le temps » refait en matrice premium** : une ligne par stratégie, une colonne par
  période, cellules colorées par intensité du rendement, **mini-tendance** en courbe et **rendement cumulé
  composé** en bout de ligne, plus une légende explicative.
- Banc E2E étendu : 22 séries activées d'un coup (toutes tracées, toutes en légende), poids ≠ 0, doctrine
  présente, phrases de Sages intégrales, matrice rendue, complétude et raisons lues. Rejoué : **0 erreur**.

## 2026-08-19 (suite) — 10 correctifs d'ergonomie signalés par Chachou

- **Plus jamais de JSON brut.** Un moteur de rendu (`autoRender` + libellés français) transforme toute réponse
  en présentation lisible : cartes de chiffres, sections, tableaux, timelines. Appliqué aux **dossiers des Sages**
  (rendu dédié : taux de réussite + jauge + derniers signaux ✓/✗ avec ce qu'ils ont dit et le verdict du marché),
  aux **dossiers des Archimages** (valeur, gain, drawdowns, doctrine, apprentissages, erreurs, positions) et aux
  **12 actions de la console de tests** (chacune avec son titre et son explication en clair).
- **Périodes harmonisées** : les barres 7J / 1M / TOUT deviennent **Jour · Semaine · Mois · Année · Début**,
  identiques aux tableaux de performance. Garde-fou : une fenêtre trop courte retombe sur 2 points minimum
  au lieu d'afficher un cadre vide.
- **Classement des portefeuilles** (ex-tableau « comparatif ») entièrement redessiné : podium (★, #2, #3…),
  valeur, gain en % et en $, jauge de décisions gagnantes, jauge de perte depuis le plus haut, poids
  Méta-Cerveau, et l'**Alchimiste réel** intégré au classement. Responsive 2 colonnes sur téléphone.
- **Comparatif par portefeuille qui n'affichait rien** : vérifié en base — `v_equity_points` **ne contient
  aucune série MAREES** (et `v_comparaison` non plus). Le cadre restait donc vide. Désormais un message explicite
  + les vrais chiffres Marées disponibles (positions ouvertes, trades clos, P&L latent, exposition).
- **Calendrier** : icônes différenciées selon l'heure réelle du message (🌅 matin · ☀️ midi · 🌙 soir),
  **💬 pour les demandes** (oracle_problemes) et 🔔 pour les rappels ; **jours cliquables** qui ouvrent tous les
  événements du jour (message intégral, demande avec statut/diagnostic/reco, rappel) ; flèches ‹ › fonctionnelles
  avec le mois affiché en titre.
- **Contexte système** affiché **en entier** (fini la troncature à 44 caractères et à 10 lignes), groupé par
  section, avec le compte de réglages lus.
- **Rapport investisseurs** : vrai document **sur fond clair**, ouvert dans un onglet dédié — en-tête AETHER,
  synthèse, 4 chiffres clés, courbe AETHER vs S&P 500, tableau par agent, 8 mesures de risque, les 4 critères
  de passage au réel, le journal de bord et un avertissement AMF complet. Mise en page d'impression (@page,
  masquage des boutons). Le bouton **Aperçu**, qui ne faisait qu'un message, ouvre maintenant ce document.
- **Curseur d'autonomie** : les 4 crans sont **cliquables** et **reflètent l'état réel** (planning + kill-switch),
  la barre de progression suit le niveau, chaque cran explique son contrat et propose l'action réelle
  correspondante (Face ID). Le cran « Proposer » est honnêtement marqué non disponible — il n'existe pas
  côté serveur. Aucun nouvel objet en base : le niveau est déduit de `scenario-switch` + `ju-killswitch`.
- **« Invalid Date »** : `hm()`/`dj()` renvoyaient le texte brut du navigateur sur une date absente — elles
  renvoient désormais une chaîne vide, et l'affichage omet le fragment.
- Détail : `.mini` du classement entrait en collision avec la classe `.mini` des cartes du Collège
  (barres transformées en gros rectangles vides) → renommée `.jauge`.
- Banc E2E étendu à ces 10 points (JSON brut, périodes, classement, repli Marées, icônes du calendrier,
  clic sur un jour, navigation de mois, contexte complet, fond clair du rapport, crans d'autonomie,
  « Invalid Date »). Rejoué : **0 erreur**.

## 2026-08-19 — Positions vivantes : les ventes à découvert étaient invisibles

Question de Chachou : « je ne comprends pas ce que tu appelles position vivante, sur Alpaca j'ai 26 positions ».
Vérification faite sur `oracle_positions_live` (miroir exact d'Alpaca : `sync_alpaca_positions` supprime les
lignes que le broker ne renvoie plus, avec garde anti-wipe).

- **État réel au 18/08 19:17 UTC** : **77 lignes** = GIL 28 · JU 27 · SYL 22, dont **17 ventes à découvert**
  (valeur de marché négative) et 4 poussières crypto corrompues (qty ~1e-9 avec « P&L +188 325 $ »).
  Les 26 de Chachou = **GIL, une fois ses 2 poussières crypto écartées** (28 − 2).
- **BUG MAJEUR trouvé** : `oracle-tests` action `positions` faisait `order=market_value.desc&limit=60`.
  Les ventes à découvert ayant une valeur négative, elles se classaient **toutes en dernier** → les 17 tombaient
  pile hors de la fenêtre de 60. **Aucune position vendeuse n'était visible dans la console**, soit −3 604 778 $
  d'exposition masquée (dont SYL : TLT −1 461 986 $ et IEF −1 168 914 $). Corrigé : `limit=300`, tri par compte,
  colonne `side` exposée. Même correctif sur `archimage_detail` (limit 20 → 60). → **oracle-tests v11 déployée.**
- **Console** : tableau « Positions vivantes » repensé — colonne **Sens (ACHAT / VENTE)**, tri par compte puis
  par taille, plafond 30 → 90 lignes, et **compteur par compte** (« GIL · 26 lignes dont 7 ventes ») pour
  recoupement direct avec l'écran Alpaca, plus le nombre de poussières écartées. Format monétaire corrigé :
  `−$474 556` au lieu de `$-474 556`.
- Le sens est déduit de `side='short'` **ou** d'une quantité négative : 2 lignes (JU COST, JU META) arrivent
  d'Alpaca avec `side='long'` malgré une qty négative.
- Banc E2E étendu : fixtures rechargées avec les 77 vraies lignes, contrôles ajoutés (73 lignes affichées,
  ventes TLT/IEF/MSTR/META présentes, compteur GIL = 26). Rejoué : 0 erreur.

## 2026-08-18 (suite 2 — test E2E intégral de la console)

- **Banc de test automatisé complet d'`aether.html`** (Playwright + fixtures = vraies réponses des edge
  functions capturées le 18/08 à 21:20 via `net.http_post` depuis Postgres, le proxy bloquant supabase.co
  en direct). Couverture : les 8 onglets, tous les tableaux, les 5 jauges Sages + dossiers (modales
  `sage_detail`/`archimage_detail`), courbes + périodes 7J/1M/TOUT, comparateur (pastilles), rendements
  par période, sélecteurs portefeuille (valeur/PnL/drawdown), déverrouillage PIN (repli Face ID),
  copilote (4 questions), « Signaler un problème » (écriture), calendrier, Vigie (MUET affiché), actions
  scénario/kill-switch, console de tests, vue mobile 390 px (aucun débordement horizontal).
- **3 bugs trouvés et corrigés** :
  ① **Crosshair mort après changement de période** : `lineChart` réécrit `innerHTML` du chartbox, les
  écouteurs de `hoverize` gardaient les anciens éléments `.xhair`/`.ctip` détachés → infobulles mortes
  après tout re-rendu. Fix : références vivantes portées par le box (`box._xh`/`box._tip`).
  ② **Lignes fantômes dans « Positions vivantes »** : oracle-tests `positions` lit la table brute
  (poussière crypto qty ~1e-9, valeur 0 $, P&L « +188 325 $ ») → filtre client à l'entrée (`realPos`)
  sur qty < 1e-6 ou valeur < 1 $ avec P&L aberrant ; le KPI « Positions ouvertes » (21 → 17) et le
  tableau restent cohérents. (À terme : purge côté serveur, documentée.)
  ③ **Tableau positions tronqué** : `slice(0,15)` cachait 2 vraies lignes (XLK, ETHUSD) → cap à 30.
- Résultat final : **0 erreur** (SAFE_ERRS vides, aucune pageerror, tous les panneaux alimentés).
  Banc rejouable : `/tmp/aetest/` (fixtures `fx/build.py`, scénario `test.mjs`, captures `shots/`).

## 2026-08-18 (suite — audit complet + app réelle)

- **`aether.html` v1 RÉEL** : le design validé (maquette v9) devient l'application, branchée sur les vraies
  sources (oracle-inbox, oracle-tests, dashboard_snapshot, scenario-switch, ju-killswitch, ju-passkey).
  Face ID réel sur Journal/Commandes, actions scénario/kill-switch réelles, « Signaler un problème » écrit
  dans oracle_problemes, refresh auto 2 min, aucun chiffre inventé (sans donnée → « — »). Chaque panneau est
  isolé (`safe()`) : une erreur de rendu ne bloque plus les autres.
- **Audit complet des tables/calculs (agent, lecture seule)** → 5 correctifs appliqués :
  ① **JU réconcilié** : les 3 points de perf du 18/08 (~222-226 k$, RÉELS — clôture des ETF) réinsérés dans
  `oracle_performance` → courbes/gains/comparaison réalignés sur +22,6 %.
  ② **P&L fantôme +136 660 $ purgé** : `v_live_crypto_positions` filtre désormais prix d'entrée ≤ 0 et
  valorisation < 0,01 $ (dust corrompue JU).
  ③ **Stats Alchimiste unifiées** : `alc_stats()` compte les clôtures VENTE (fini le « 100 % sur 1 trade » —
  vrai WR 33,3 % sur 3 clôtures partout) ; le « 48.5 » codé en dur de `v_perf_resume` remplacé par le calcul réel.
  ④ **Marées débloqué** : backfill `exit_ts` sur les clôtures (21 trades clos maintenant visibles → gains,
  courbes et résumés Marées alimentés).
  ⑤ **Libellés AMF adoucis** (suivi/index/console) : « Objectif +15-20 % » → hypothèse non garantie ;
  « on bat le S&P 500 » → surperformance simulée ; « SEUL CERVEAU AVEC UN EDGE MESURÉ » → « premier candidat
  au réel, en validation » ; « La preuve en une courbe » → courbe comparée (simulation) ; etc.
  Restent documentés (rapport d'audit, non appliqués) : méthodo Sharpe/DD des benchmarks, gains ALC_RÉEL non
  neutralisés des dépôts (`fonds_versements` vide), incohérences v_gains « jour » multi-dates.

## 2026-08-18

- **« Alchimiste verdict MUET » : cause racine = clé anon corrompue dans les modules staking 20022/20023.**
  Depuis la modif Maia du 17/08 ~20:50, les 2 modules HTTP staking portent un JWT mutilé
  (`smddzbxebwfnitxuyuyp` au lieu de `smddzybxebwhfnitxuyp`) → **401 Invalid API key** à chaque run
  (prouvé dans les données de run stockées du blueprint, 17/08 21:28) → staking VIDES → l'Alchimiste rend
  `"destake_recommande": []` (prouvé dans la sortie 10014 stockée) → 0 ligne `alc_destake_reco` depuis 20:00,
  section DE-STAKING absente du rapport Discord, Vigie MUET. Les propositions trading marchent (10023 a la
  bonne clé) : le pipeline (10012 → 10014 → RPC `alc_record_propositions`, champ `destake_recommande`) est sain.
  **Correctif** : `docs/decisions/PROMPT-MAIA-FIX-CLE-STAKING-2026-08-18.md` (remettre la bonne clé anon dans
  apikey + Authorization des modules 20022/20023, rien d'autre). Le fix base64 reste en option derrière.

- **JU +22,6 % : FAUSSE ALERTE — c'était une vraie performance, pas un bug.** Ce matin JU affichait +22,6 %
  (`v_perf_resume` = `cumulative_pnl ÷ baseline` = 225 985 ÷ 999 789). D'abord pris pour une lecture d'equity
  Alpaca aberrante (seul JU touché) → un garde-fou a été posé dans `update-brain` (v17) et les données
  « nettoyées ». **Mais Chachou a confirmé que le compte Alpaca de JU a RÉELLEMENT 1,226 M$** : c'est le produit
  de la clôture des positions bloquées des archimages pendant le reset volontaire (changement de prompts + purge
  Cerveau/Méta-Cerveau, pour observer le trading de la semaine et faire le point le 28). **Corrections annulées** :
  garde-fou retiré (`update-brain` revenu à la logique v16, redéployé v18), `oracle_brain_state.JU.cumulative_pnl`
  restauré à sa vraie valeur **225 985** (JU +22,6 %, SYL +8,6 %, GIL +5,0 % = perf cumulée réelle, baselines
  conservées à ~1 M). Les clés Alpaca hardcodées ont été retirées du fichier source committé (placeholders ;
  la fonction déployée garde les vraies clés — à migrer vers les secrets Supabase). Leçon : **vérifier auprès de
  Chachou si une valeur « aberrante » n'est pas simplement réelle avant de la corriger.**

- **Bouton scénario déverrouillé par Face ID (repli PIN), comme le kill-switch.** Chachou : « pour activer/
  désactiver le scénario, rajoute le Face ID ». `ju-passkey` v3 : nouvelle action `scen-options`/`scen-verify`
  — vérifie l'empreinte WebAuthn **côté serveur** (purpose `scen`) puis relaie l'action à `scenario-switch`
  avec le PIN lu en interne (le client ne voit jamais le PIN). Console `scenInit` : les boutons Activer/Couper/
  Lancer demandent d'abord Face ID ; si indisponible (appareil non enregistré), repli sur le prompt PIN. Même
  schéma de sécurité que l'armement du kill-switch (action sensible exécutée après vérif serveur).

- **Alchimiste : la panne APY vient du Base64, PAS des modules Make.** Vérifié (sous-agent sur le blueprint) :
  les 2 modules HTTP staking (20022 délais → `v_alc_staking_delais_txt`, 20023 apy → `v_alc_staking_apy_txt`)
  lisent les BONNES vues avec le bon en-tête `Accept: pgrst.object+json`. La panne est dans le module Alchimiste
  (10012) qui encode les valeurs en **Base64** (`STAKING_APY_B64={{base64(...)}}`) et demande au LLM de « décoder
  mentalement » — `sonar-pro` n'y arrive pas et **devine** l'APY (TON 5 % au lieu de 17,67 % ; les délais tombent
  justes seulement car ce sont des constantes réseau connues). Correctif = prompt Maia pour envoyer du **texte
  brut** (`docs/decisions/PROMPT-MAIA-ALCHIMISTE-BASE64-2026-08-18.md`).

- **ANOMALIE archimage JU : equity ×4,7 en une nuit (bug, pas un vrai gain).** JU passe de ~47 142 $ (17/08
  20:55) à **222 007 $** (18/08 07:52) alors que `orders_count=0`. `v_equity_points` pour JU = `oracle_performance
  .actual_pnl` = `equity Alpaca − baseline` (calculé dans `update-brain`). La base de capital a ~quadruplé sans
  ordre. Les positions crypto de JU montrent des prix d'entrée **corrompus** (SOL entrée = −136 000 milliards).
  → À corriger dans une passe dédiée (lecture equity Alpaca / cost-basis). NON résolu, seulement diagnostiqué.

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
