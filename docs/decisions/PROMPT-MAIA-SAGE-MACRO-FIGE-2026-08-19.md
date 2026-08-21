# Prompt Maia — le Sage Macro est réellement figé : il tourne sur le mauvais moteur

> **Statut : PRÊT.** Diagnostic établi sur 14 jours de sorties, pas sur l'alerte de la Vigie.

## L'alerte de la Vigie visait 4 Sages. Un seul est réellement en cause.

La Vigie compare **un** champ sur **6 runs**. Sur une séance calme, `NEUTRAL` / `LOW` / `MEDIUM` /
`SYL` se répètent naturellement. En remontant à 14 jours, le tableau change complètement :

| Sage | Runs sur 14 j | Valeurs distinctes du champ surveillé | Verdict réel |
|---|---|---|---|
| **Macro** | 52 | **1** (`NEUTRAL` sans exception) | **figé** |
| Risque | 53 | 2 | limite |
| Mémoire | 52 | 4 | sain |
| Flash | 61 | 3 | sain |

Le Sage Macro a même produit **`macro_score` = 55 sur tous les runs du 06 au 15/08**, puis
**50 sur tous les runs depuis le 17/08**. Deux valeurs en deux semaines, pendant que le BTC passait
de 63 000 à 68 700 $. Ce n'est pas un marché calme, c'est une réponse toute faite.

## La cause : il interroge un moteur de recherche, pas un analyste

| Sage | Endpoint | Modèle | Reçoit CTX | État |
|---|---|---|---|---|
| **Macro (201)** | **api.perplexity.ai** | **sonar-pro** | **oui** | **figé** |
| Flash (209) | api.perplexity.ai | sonar-pro | **non** | sain |
| Mémoire (207) | api.groq.com | openai/gpt-oss-120b | oui | sain |
| Technique (203) | api.groq.com | openai/gpt-oss-120b | oui | sain |
| Risque (205) | api.mistral.ai | mistral-large-latest | oui | limite |

Le croisement est net : **le seul Sage qui reçoit CTX *et* tourne sur un modèle de recherche web est
le seul qui est figé.** Flash utilise le même modèle mais ne reçoit pas CTX — il va bien. Mémoire
reçoit CTX sur un modèle classique — il va bien.

`sonar-pro` traite le message utilisateur comme une **requête de recherche**. On lui envoie
8 421 caractères de champs séparés par des barres verticales. Il ne les analyse pas, il les cherche
sur le web — et répond ce que répond un moteur de recherche devant une requête incompréhensible.

Sa propre sortie le dit, dans le champ `news_catalyst` :

| Période | Runs | `news_catalyst` |
|---|---|---|
| 06 → 15/08 | 48 | « inflation », « Inflation attendue » |
| **17 → 19/08** | **16** | **« CTX est ambigu ; aucune donnée macro exploitable »** — 16 fois sur 16 |

## Les données, elles, sont parfaites

Le module 102 fournit tout, avec `data_quality = 100` :

```
VIX 15.84 · SPY 770.57 (+0.41 %) · BTC 68 686 (+5.8 %) · ETH 2 096 · Fear&Greed 46 « Fear »
CPI 332.81 · Fed 3.63 % · T10Y 4.72 · T2Y 4.19 · USD/EUR 0.8617
CATALYST : « IPO revival, record equity highs, and cooling inflation are supporting risk appetite »
```

Et CTX est bien construit : **92 champs, 8 421 caractères**, VIX et CATALYST inclus. Le problème
n'est ni dans la donnée ni dans CTX — il est dans le moteur qui les lit.

## Prompt à envoyer à Maia

```
Bonjour Maia. Scenario 6183820, module 201 (Sage Macro, AURORA BOREALIS) UNIQUEMENT.

Diagnostic : ce module appelle api.perplexity.ai avec le modele sonar-pro, qui est un modele de
RECHERCHE WEB. On lui envoie CTX, soit 8 421 caracteres de champs separes par des barres
verticales. Il ne les analyse pas, il les cherche sur le web, et repond depuis 3 jours
"CTX est ambigu, aucune donnee macro exploitable" sur 16 runs sur 16. Resultat : macro_regime
vaut NEUTRAL sur les 52 derniers runs et macro_score n'a pris que 2 valeurs en 14 jours.

Les modules 203 (Technique) et 207 (Memoire) recoivent le meme CTX sur Groq et fonctionnent
parfaitement. On bascule donc le 201 sur Groq, exactement comme eux.

1) MODULE 201 — URL :
   actuelle  : https://api.perplexity.ai/chat/completions
   nouvelle  : https://api.groq.com/openai/v1/chat/completions

2) MODULE 201 — en-tete Authorization : remplace sa valeur par CELLE DU MODULE 207, copiee a
   l'identique. Ne la retape pas a la main, copie-la depuis le 207. L'en-tete Content-Type
   application/json ne change pas.

3) MODULE 201 — dans le corps de la requete :
   "model": "sonar-pro"          ->  "model": "openai/gpt-oss-120b"
   "max_tokens": 1500            ->  "max_tokens": 2000
   ajoute      "reasoning_effort": "low"     (comme le module 207)
   remplace le bloc "response_format" ENTIER par : "response_format": {"type": "json_object"}
   Le schema reste decrit dans le prompt systeme, comme sur les modules 203 et 207 : Groq
   n'accepte pas le format json_schema de Perplexity.

4) MODULE 201 — dans le message "system", ajoute cette phrase JUSTE AVANT "CONTRAINTES :" :

Le message utilisateur commence par CTX= suivi de champs separes par des barres verticales, au format CLE=valeur (exemple VIX=15.84|SPY=770.57|SPY_CHG=0.41|FG=46|CATALYST=...). Lis ces champs directement : ils sont ta SEULE source, tu n as aucune recherche a faire. Utilise VIX pour vix_signal, SPY et SPY_CHG pour spy_trend, FG pour fear_greed_level, T10Y et T2Y pour yield_curve, FED et CPI pour rate_pressure, et recopie CATALYST dans news_catalyst. Ne declare JAMAIS le contexte ambigu : si une cle precise manque, nomme-la dans news_catalyst.

5) Ne touche a rien d'autre : ni le message "user" (il doit rester CTX={{CTX}}), ni la
   temperature 0.01, ni le module 202 qui parse la sortie, ni aucun autre module.

Puis SAUVEGARDE et confirme-moi trois points :
  1. l'URL du 201 se termine par api.groq.com/openai/v1/chat/completions
  2. le modele est openai/gpt-oss-120b
  3. response_format vaut {"type": "json_object"}
```

## Contrôle après le prochain run

Dans `oracle_sages_report`, le Sage Macro doit :

- écrire un `news_catalyst` **réel** (repris de CATALYST), plus jamais « CTX est ambigu » ;
- donner `vix_signal = NORMAL` pour VIX 15,84 — mais **calculé**, pas par défaut ;
- faire **bouger `macro_score`** d'un run à l'autre. C'est le vrai test : deux valeurs en 14 jours,
  c'est le symptôme ; un score qui varie, c'est la guérison.

Requête de contrôle :

```sql
select created_at, sage_output->>'macro_score' as score,
       sage_output->>'macro_regime' as regime,
       left(sage_output->>'news_catalyst', 60) as catalyseur
from oracle_sages_report where sage_name = 'Macro'
order by created_at desc limit 5;
```

## Correctif déjà appliqué côté Supabase

La règle de la Vigie a été corrigée (aucune intervention Make) : elle distingue désormais
**ALERTE** (6 runs, à surveiller — un marché stable suffit à l'expliquer) et **FIGÉ** (12 runs sur
72 h, confirmé). Après correction, elle affiche exactement ce que montrent les mesures :

```
Sage Macro     FIGE     macro_regime=NEUTRAL identique sur 12 runs et 72 h
Sage Flash     ALERTE   a surveiller
Sage Memoire   ALERTE   a surveiller
Sage Risque    ALERTE   a surveiller
Sage Technique OK
```

## Point à surveiller ensuite

Le Sage Risque (mistral-large) n'a produit que **2 valeurs de `risk_level` et 3 de `risk_score` en
53 runs**. Ce n'est pas un gel caractérisé, mais c'est peu. À réexaminer une fois le Macro réparé :
le Risque reçoit `MACRO={{202.macro_regime}}`, donc une partie de son immobilité vient peut-être
simplement du fait qu'on lui répète `NEUTRAL` depuis 14 jours.
