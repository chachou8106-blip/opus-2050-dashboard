# L'Alchimiste — pourquoi il ne trade plus depuis le 13/08

> Tout ce qui suit est lu dans le blueprint et dans la base, pas déduit. Les numéros de ligne
> renvoient au blueprint du scénario 6183820 tel qu'exporté ce matin.

## Le compte est vite fait : 50 propositions, 50 expirées, zéro validée. Jamais.

```sql
select statut, count(*) from alchimiste_crypte_propositions group by statut;
-- expiree | 50     <- une seule ligne. Il n'y en a pas d'autre.
```

Ce n'est pas « 50 sur les 7 derniers jours ». C'est **la totalité de la table depuis sa création
le 13/08**. Aucune proposition n'a jamais atteint un autre statut. Et `oui_at` est `null` sur
les 50.

## Je me corrige sur un point

J'allais te proposer d'apprendre à l'Alchimiste à **vendre** pour se refaire du cash. En lisant
la table, c'est faux : **il vend déjà, et c'est même son geste dominant.**

| Sens | Nombre | Ticket moyen |
|---|---|---|
| **sell** | **29** | **17,29 $** |
| buy | 21 | 2,15 $ |

Le 19/08 à 13:48 il a proposé exactement le bon geste, de lui-même :

> « Portefeuille très éclaté avec beaucoup de micro-lignes, peu de cash USD (2.52). **Vendre une
> petite partie de la ligne BTC**, qui est liquide et avec spread raisonnable, permet de dégager
> du cash utilisable. » — 20 $, expirée elle aussi.

L'agent n'a pas de problème de jugement. Il a un problème de **débouché**.

## Les deux verrous, dans l'ordre

### Verrou 1 — le kill switch est désarmé. C'est ta décision, je n'y touche pas.

```sql
select * from ju_crypte_config where key='kill_switch';
-- kill_switch | OFF
```

Le module **20013** appelle `alc-auto` avec `{"run_id":"…","dry_run":false}` — donc **armé pour
passer des ordres réels**. C'est `alc-auto` lui-même qui refuse, en première ligne, tant que
`kill_switch` vaut `OFF` : il renvoie `statut: "bloque", raison: "kill_switch=OFF (desarme)"`.

Le dispositif fonctionne donc **exactement comme prévu** : la sécurité est mise, et elle tient.

CLAUDE.md dit : « Ne jamais armer/désarmer le kill_switch ni passer dry_run=false sans accord
explicite de Chachou. » **Je ne le touche pas et je ne te pousse pas à le toucher.** Je te signale
seulement que c'est lui, et lui seul, qui explique les 6 jours sans ordre réel.

### Verrou 2 — la validation à la main n'est branchée nulle part. Ça, c'est un vrai défaut.

Il existe une fonction faite pour ça, `alc_process_oui` : elle lit tes messages Discord, cherche
`OUI <SYMBOLE>`, vérifie que la proposition n'a pas expiré, que le prix n'a pas dérivé de plus de
1 %, puis la passe en `validee_oui`.

**Aucun module du scénario ne l'appelle.** J'ai cherché la chaîne `alc_process_oui` dans les
20 327 lignes du blueprint : zéro occurrence. C'est du code mort.

Et le message Discord de l'Alchimiste (module **10031**) n'affiche **jamais les propositions**.
Relis-le : il montre le kill switch, le compteur `a_executer/proposees`, les **résultats** de
`alc-auto`, puis les dé-stakings. Les propositions elles-mêmes n'y sont pas. Comme `alc-auto`
est bloqué, la partie « résultats » est vide, et tu reçois un message qui ne dit rien.

**Conséquence : l'Alchimiste réfléchit, écrit ses propositions en base, et personne ne les voit
passer.** Elles meurent 6 heures plus tard, expirées par le cron `crypte_ju_apprentissage`
(`5 */2 * * *`, ligne 1159 de `03_functions.sql`).

## Verrou 3 — les mêmes références cassées que les six autres modules

Je t'ai écrit hier que le module 10012 n'était pas concerné, « parce qu'il utilise `base64(CTX)`
et que le staking est exact ». **Ce raisonnement ne tient pas** : le staking vient du module
20022, pas de `CTX`. Il ne prouve rien sur `CTX`.

Message user du module 10012, relevé au caractère près :

```
…|CTX_B64={{base64(CTX)}}|SAGES_B64={{base64(SAGES)}}|AVIS_GIL_PHASE={{base64(ifempty(306.market_phase; emptystring))}}|…
```

`CTX` et `SAGES` y sont des **références nues**, exactement comme dans les modules 203, 205, 207,
301, 303 et 305. Les envelopper dans `base64()` ne change pas la façon dont Make résout le nom.

Indice concordant, sans être une preuve : sur les **50 propositions**, la requête

```sql
select … where raison ~* 'vix|spy|s&p|fed|taux|inflation|dxy|dollar';
```

ne renvoie **rien**. Pas un seul chiffre macro cité en une semaine. Toutes les raisons parlent de
liquidité, de spread, et de l'avis de GIL — le seul champ dont la référence (`306.xxx`) est de
type module, donc valide.

La correction `base64(110.value)` est **sans risque même si j'avais tort** : `110.value` contient
la valeur de `CTX`. Si `base64(CTX)` fonctionnait déjà, le résultat serait identique.

## Ce que je NE propose pas

- Toucher au `kill_switch` — ta décision.
- Toucher à `STAKING_DELAIS`, `STAKING_APY`, `SOLDES_REVOLUTX` ou `PRIX_REVOLUTX_B64` dans le
  module 10012. Le staking est juste depuis 5 runs ; c'est en modifiant ce module qu'on l'a cassé
  pendant trois jours.
- Brancher `alc_process_oui` sur Discord dans la foulée. C'est un chantier à part, qui ouvre une
  voie d'exécution réelle. On en parle avant, pas en passant.

## Un point à vérifier de ton côté, dans l'app Revolut

Le portefeuille contient deux lignes « cash » :

| Ligne | Valeur |
|---|---|
| USD | **2,52 $** |
| USDT | **22,65 $** |

L'Alchimiste ne considère que la première comme achetable — c'est écrit dans son prompt système :
« ACHETER : uniquement avec du cash USD disponible ». D'où les tickets à 2 $.

**Je ne sais pas si la paire USDT-USD est cotée sur Revolut X** : elle n'apparaît ni dans
`revolut_univers_complet` (qui ne connaît que `USDC-USD`, figée au 07/07) ni dans `price_history`.
Si elle l'est chez toi, ces 22,65 $ multiplieraient son cash par 10 d'un seul ordre. Regarde dans
l'app et dis-le-moi — je n'invente pas une paire que je n'ai pas vue.

---

## Prompt à envoyer à Maia

```
Bonjour Maia. Scenario 6183820. Deux modules, deux changements independants.

------------------------------------------------------------------
MODULE 10012 (HTTP vers api.perplexity.ai, le cerveau de l'Alchimiste)
------------------------------------------------------------------
Dans le message "user" UNIQUEMENT, remplace ces deux sous-chaines :

  remplace   CTX_B64={{base64(CTX)}}       par   CTX_B64={{base64(110.value)}}
  remplace   SAGES_B64={{base64(SAGES)}}   par   SAGES_B64={{base64(215.value)}}

Raison : la variable CTX est posee par le module 110 et SAGES par le module 215, tous deux
util:SetVariable en scope roundtrip. La reference par NOM ne se resout pas dans ce scenario --
le module 201 repondait "Missing keys:VIX,SPY,SPY_CHG,FG,T10Y,T2Y,FED,CPI" et a ete repare en
remplacant {{CTX}} par {{110.value}}, sans aucune autre modification.

NE TOUCHE A RIEN D'AUTRE dans ce module. En particulier, laisse STRICTEMENT INCHANGES :
  SOLDES_REVOLUTX, PRIX_REVOLUTX_B64, STAKING_DELAIS, STAKING_APY,
  tous les champs AVIS_GIL_*, CRYPTE_CATALYSTS,
  le prompt systeme, le modele sonar-pro, la temperature, max_tokens, l'URL, les en-tetes.

------------------------------------------------------------------
MODULE 10031 (Discord, le message de l'Alchimiste)
------------------------------------------------------------------
Il n'affiche jamais les propositions du cycle. Ajoute un bloc qui les liste.

Insere le bloc ci-dessous JUSTE AVANT la ligne qui commence par  **A DE-STAKER**
et laisse tout le reste du message identique au caractere pres.

**PROPOSITIONS DU CYCLE**
{{if(length(ifempty(10014.propositions; emptyarray)) = 0; "Aucune proposition ce cycle"; emptystring)}}
{{if(length(ifempty(10014.propositions; emptyarray)) >= 1; "• " & upper(ifempty(get(10014.propositions; "1.side"); emptystring)) & " " & upper(ifempty(get(10014.propositions; "1.paire"); emptystring)) & " — " & toString(ifempty(get(10014.propositions; "1.montant"); 0)) & "$ — conf " & toString(ifempty(get(10014.propositions; "1.confidence"); 0)) & " — " & ifempty(get(10014.propositions; "1.raison"); emptystring); emptystring)}}
{{if(length(ifempty(10014.propositions; emptyarray)) >= 2; "• " & upper(ifempty(get(10014.propositions; "2.side"); emptystring)) & " " & upper(ifempty(get(10014.propositions; "2.paire"); emptystring)) & " — " & toString(ifempty(get(10014.propositions; "2.montant"); 0)) & "$ — conf " & toString(ifempty(get(10014.propositions; "2.confidence"); 0)) & " — " & ifempty(get(10014.propositions; "2.raison"); emptystring); emptystring)}}
{{if(length(ifempty(10014.propositions; emptyarray)) >= 3; "• " & upper(ifempty(get(10014.propositions; "3.side"); emptystring)) & " " & upper(ifempty(get(10014.propositions; "3.paire"); emptystring)) & " — " & toString(ifempty(get(10014.propositions; "3.montant"); 0)) & "$ — conf " & toString(ifempty(get(10014.propositions; "3.confidence"); 0)) & " — " & ifempty(get(10014.propositions; "3.raison"); emptystring); emptystring)}}

Le module 10014 est bien le json:ParseJSON qui lit la reponse du module 10012 ; le bloc
"A DE-STAKER" existant utilise deja 10014.destake_recommande, donc 10014.propositions est
accessible de la meme facon.

Ne touche a AUCUN autre module, ni au module 20013 (alc-auto), ni a aucun parametre du
kill switch. Puis SAUVEGARDE et confirme.
```

## Contrôle après le prochain run

```sql
-- 1. Les propositions citent-elles enfin le contexte marche ?
select proposed_at, paire, side, montant, raison
from alchimiste_crypte_propositions
order by proposed_at desc limit 3;
```

Et sur Discord : le message de l'Alchimiste doit désormais contenir un bloc
**PROPOSITIONS DU CYCLE** non vide. Tant que le kill switch est sur `OFF`, il restera un bloc
d'information — mais tu sauras enfin ce que ton agent crypto voulait faire.
