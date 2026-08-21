# Prompt 1/6 — les références `{{CTX}}` et `{{SAGES}}` ne se résolvent pas

> **Le plus grave de la liste, et de loin.** Corrigé sur le module 201 hier soir ; les **six autres
> modules concernés** sont restés en l'état, dont **les trois Archimages**.

## Correction de mon audit d'hier

J'avais annoncé 3 modules à corriger (203, 205, 207). En relisant le blueprint mot à mot,
`CTX={{CTX}}` apparaît **6 fois**, pas 3 :

```
module 201  (deja corrige en {{110.value}})
module 203  Sage Technique
module 205  Sage Risque
module 207  Sage Memoire
module 301  ARCHIMAGE JU    (claude-sonnet-4-5)
module 303  ARCHIMAGE SYL   (sonar-pro)
module 305  ARCHIMAGE GIL   (mistral-large-latest)
```

Et les trois Archimages utilisent **en plus** `{{SAGES}}`, la variable posée par le module 215 —
même mécanisme, donc probablement le même problème.

**Les trois traders qui passent les ordres réels décident peut-être sans aucune donnée de marché.**

## La preuve, en une expérience à une seule variable

Sur le run du 19/08 à 22:02, le module 201 utilisait `{{CTX}}` et répondait :

```
"news_catalyst": "Missing keys:VIX,SPY,SPY_CHG,FG,T10Y,T2Y,FED,CPI,DXY,GOLD_SILVER_RATIO,HYG_LQD_SPREAD,MACRO_SHOCK"
```

Seule modification avant le run de 22:18 : `CTX={{CTX}}` → `CTX={{110.value}}`. Résultat :

```
"news_catalyst": "AI investment, IPO revival, and geopolitics driving mixed risk appetite"
"yield_curve": "NORMAL"   (T10Y 4,72 - T2Y 4,19 = +0,53, sa propre regle dit « > 0 = normale »)
```

Rien d'autre n'a changé. Le modèle, l'URL et le prompt système étaient déjà ceux de 22:02.

Et dans le **même run** de 23:22, le module 205, resté en `{{CTX}}`, écrivait :
« **VIX a 14.2** confirme un marche calme » — alors que le VIX réel est **15,84**. Sur 5 jours il a
cité 14.2, 18, 15, 17, 15 : des chiffres plausibles, jamais le bon.

## Ce que dit le blueprint, vérifié ligne à ligne

| Module | Type | Variable | Référence correcte |
|---|---|---|---|
| 110 | `util:SetVariable` | `CTX`, scope roundtrip | `{{110.value}}` |
| 215 | `util:SetVariable` | `SAGES`, scope roundtrip | `{{215.value}}` |

Ordre d'exécution : 110 → 201, 203, 205, 207 → 215 → 301, 303, 305. Chaque variable est donc bien
posée avant ses consommateurs ; c'est la **forme** de la référence qui échoue, pas l'ordre.

## Messages user actuels, relevés mot à mot

```
203 : CTX={{CTX}} MACRO={{replace(replace(ifempty(202.macro_regime; NEUTRAL); newline; ); quote; )}}
205 : CTX={{CTX}} MACRO={{...202.macro_regime...}} MOMENTUM={{...204.spy_momentum...}}
207 : CTX={{CTX}} JU_W={{...}} JU_L={{...}} ... MAR_RUNS={{...}}
301 : CTX={{CTX}}|SAGES={{SAGES}}|JU_WR={{...}} ...
303 : CTX={{CTX}}|SAGES={{SAGES}}|SYL_WR={{...}} ...
305 : CTX={{CTX}}|SAGES={{SAGES}}|GIL_WR={{...}} ...
```

## Prompt à envoyer à Maia

```
Bonjour Maia. Scenario 6183820. Six modules, un seul type de changement : la forme d'une reference.

Contexte verifie : la variable CTX est posee par le module 110 (util:SetVariable, scope roundtrip)
et la variable SAGES par le module 215 (meme type). La reference par NOM {{CTX}} ne se resout pas
dans ce scenario : le module 201 repondait "Missing keys:VIX,SPY,SPY_CHG,FG,T10Y,T2Y,FED,CPI".
Remplacer {{CTX}} par {{110.value}} sur ce seul module l'a repare immediatement, sans aucune autre
modification. Le module 205, reste en {{CTX}}, cite toujours un VIX a 14.2 alors que le reel est
15.84 : il invente. On applique donc la meme correction partout.

Dans le message "user" de chaque module ci-dessous, remplace UNIQUEMENT la sous-chaine indiquee.
Tout le reste de chaque message doit rester identique au caractere pres.

MODULE 203 : remplace   CTX={{CTX}}   par   CTX={{110.value}}
MODULE 205 : remplace   CTX={{CTX}}   par   CTX={{110.value}}
MODULE 207 : remplace   CTX={{CTX}}   par   CTX={{110.value}}

MODULE 301 : remplace   CTX={{CTX}}|SAGES={{SAGES}}|   par   CTX={{110.value}}|SAGES={{215.value}}|
MODULE 303 : remplace   CTX={{CTX}}|SAGES={{SAGES}}|   par   CTX={{110.value}}|SAGES={{215.value}}|
MODULE 305 : remplace   CTX={{CTX}}|SAGES={{SAGES}}|   par   CTX={{110.value}}|SAGES={{215.value}}|

Ne touche a AUCUN prompt systeme, AUCUN modele, AUCUNE URL, AUCUN en-tete, et a aucun autre module.
Ne touche pas au module 201, deja corrige, ni au module 10012 qui utilise base64(CTX) et fonctionne.

Puis SAUVEGARDE et confirme-moi que la chaine {{CTX}} n'apparait plus nulle part dans le scenario,
et que {{SAGES}} n'apparait plus non plus.
```

## Contrôle après le prochain run

```sql
select sage_name,
       (regexp_match(sage_output::text, 'VIX[^0-9]{0,12}([0-9]{1,2}[.,]?[0-9]?)'))[1] as vix_cite
from oracle_sages_report
where created_at = (select max(created_at) from oracle_sages_report)
  and sage_name in ('Risque','Macro');
```

Le VIX cité par le Sage Risque doit devenir **15,8x** et non plus 14,2 ou 18. C'est le test le plus
direct : un chiffre exact ne s'invente pas deux fois de suite.

## Pourquoi le module 10012 n'est pas dans la liste

L'Alchimiste reçoit `CTX_B64={{base64(CTX)}}` — un appel de fonction, pas une référence nue. Il
fonctionne (staking exact cinq runs de suite). Je n'y touche pas tant que rien ne prouve qu'il est
affecté : modifier ce qui marche est exactement ce qui a cassé le staking pendant trois jours.
