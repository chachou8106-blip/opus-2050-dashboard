# Audit complet des agents — 20/08/2026 au matin

> Demandé par Chachou après la correction du Sage Macro. Passage en revue des 5 Sages, des
> 3 Archimages, de Marées et de l'Alchimiste. **7 anomalies trouvées**, dont 3 sérieuses.

## Vérification préalable : la correspondance Fear & Greed est appliquée

Module 201, prompt système, au bon endroit :
`0 a 24 EXTREME_FEAR, 25 a 44 FEAR, 45 a 55 NEUTRAL, 56 a 75 GREED, 76 a 100 EXTREME_GREED`

**Pas encore éprouvée** : aucun run depuis 23:22, le prochain est à 09:00. Contrôle d'intégrité par
ailleurs bon — 80 modules, clé 20022 saine, 10012 en texte brut, 205 au bon plafond.

---

## 1. Sage Risque — il invente le VIX ⚠️ sérieux

Sa dernière sortie : « **VIX a 14.2** confirme un marche calme ». Le VIX réel, vérifié en appelant
`collect-market-data` : **15,84**.

Ce n'est pas un écart isolé. Valeurs citées sur 5 jours : **14.2, 18, 15, 17, 15, 15…** alors que
le VIX de `102.data.macro.vix` est resté à **15,84**.

Le module 205 utilise `CTX={{CTX}}` — **exactement la référence qui ne se résolvait pas sur le
module 201**. Le Sage Risque produit donc probablement ses chiffres de mémoire, comme le Macro le
faisait. Cela expliquerait aussi qu'il n'ait produit que **2 valeurs de `risk_level` et 3 de
`risk_score` en 53 runs**.

**Action** : appliquer aux modules **203, 205 et 207** le correctif déjà validé sur le 201 —
remplacer `{{CTX}}` par `{{110.value}}`. Coût nul, doute levé.

## 2. SYL n'a plus de pouvoir d'achat ⚠️ sérieux

| Compte | Pouvoir d'achat | Levier | Poids Méta-Cerveau |
|---|---|---|---|
| JU | 2 739 797 $ | 1,14× | 0,350 |
| GIL | 88 042 $ | 2,00× | 0,090 |
| **SYL** | **0 $** | **3,35× — ÉLEVÉ** | **0,560** |

Conséquence directe, le 19/08 à 21:16 : trois ordres **rejetés** pour « insufficient buying power »
— GLD 413 $, TLT 580 $, IEF 560 $. SYL ne peut plus ouvrir de position.

## 3. SYL — le short GLD ne peut pas être soldé ⚠️ sérieux

Trois tentatives de rachat en deux jours, toutes rejetées :

| Date | Demandé | Disponible | Écart |
|---|---|---|---|
| 18/08 14:30 | 404,14 | 24,07 | ×17 |
| 18/08 19:17 | 406,38 | 24,07 | ×17 |
| 19/08 16:41 | 121,25 | 22,85 | ×5 |

L'ordre part en **notionnel** (50 000 $), qu'Alpaca convertit en 121 titres, alors que la position
short n'est que de 22,85. Alpaca refuse — un achat en notionnel ne peut pas retourner une position
short en long d'un seul ordre. **Résultat : le short GLD reste ouvert depuis au moins deux jours,
sans possibilité de le fermer.**

Correctif possible dans `execute-trades` : quand `heldQty < 0`, envoyer une **quantité** égale à la
taille du short plutôt qu'un notionnel. Je ne l'ai pas appliqué — ça change le comportement
d'exécution, c'est ton feu vert.

## 4. Le Méta-Cerveau ne regarde ni le levier ni la marge

SYL reçoit **56 % du poids** parce que son win rate est le meilleur (54 %) — alors qu'il est à
0 $ de pouvoir d'achat et 3,35× de levier, donc incapable d'exécuter. La formule de pondération
(`update-brain`) combine PnL, drawdown et win rate ; **ni `alpaca_buying_power` ni le levier n'y
entrent**.

## 5. Marées — une seule idée, répétée, et du mauvais côté ⚠️ sérieux

Les **17 trades clos** des 7 derniers jours :

| Paire | Sens | Trades | Gagnants | P&L moyen | Sortie |
|---|---|---|---|---|---|
| EUR-USD | vente | 8 | **0** | −0,86 % | stop-loss |
| USD-JPY | achat | 6 | **0** | −0,86 % | stop-loss |
| USD-CHF | achat | 3 | **0** | −0,86 % | stop-loss |

**Zéro gagnant sur 17.** Et les trois lignes expriment **le même pari : dollar en hausse**. Or le
dollar **recule de 1,03 % sur 20 séances** (mesure UUP ajoutée hier soir).

Win rate Marées : **57 % → 35,6 %** (16 gains / 29 pertes). Les 17 trades ajoutés sont 17 pertes.

Les **68 positions ouvertes** répètent le même pari : USD-JPY achat ×21, EUR-USD vente ×16,
EUR-GBP vente ×15, GBP-JPY achat ×10. Une seule ligne va à contre-courant (USD-CAD vente ×1).
Montants minuscules (281 $ au total), mais la concentration est totale.

## 6. Alchimiste — 50 propositions, 50 expirées

Sur 7 jours : **50 propositions, toutes au statut `expiree`**. Aucune validée. Dernier ordre réel
passé le **13/08**, il y a 6 jours.

Ce n'est pas une panne : le flux demande ta validation explicite. Mais l'agent crypto **réel** ne
trade plus depuis une semaine. Le staking, lui, fonctionne parfaitement (7 lignes à 150,99 $,
cinq runs consécutifs justes).

## 7. Sage Mémoire absent du run de 23:22

4 Sages sur 5 (Flash, Macro, Risque, Technique). Les 4 runs précédents en avaient 5. Le run n'est
pas mort — succès, complétude 100 %. **Une seule occurrence**, à surveiller.

---

## Ce qui va bien, vérifié

- **Verrous d'univers : 0 violation en 7 jours.** JU n'achète pas d'ETF, SYL pas d'action
  individuelle, GIL ne touche pas SPY/QQQ, la crypto reste chez GIL.
- **Sage Mémoire : chiffres exacts.** Ses win rates recoupent `oracle_brain_state` au point près
  (JU 49/49, GIL 51/51, SYL 53/54). Le « MAREES 57 » de 23:22 était juste au moment du run — la
  chute à 35,6 % date de 00:55.
- **Sage Flash : titres réels et datés**, pas de contenu générique.
- **Staking exact 5 runs de suite**, garde-fou short actif, clés saines, 80 modules.

## Priorités proposées

1. `{{CTX}}` → `{{110.value}}` sur les modules **203, 205, 207** — même correctif que le 201.
2. Rachat de short en quantité et non en notionnel (`execute-trades`) — débloque le short GLD.
3. Décider quoi faire du levier de SYL : il est à 3,35× sur un maximum de 4×, sans marge.
4. Regarder Marées : 17 pertes d'affilée sur un pari unique, ce n'est plus de la malchance.
