# Analyse — « tous les comptes se sont pété la figure » (19/08/2026 au soir)

> **Conclusion : aucun compte n'a sauté.** Les trois comptes sont au-dessus de leur capital de départ.
> Le chiffre affiché dans la console est faux, et il masque un vrai problème qui, lui, n'a rien à voir
> avec une chute des marchés.

## 1. Ce que dit Alpaca lui-même (source de vérité, sync 16:41 UTC)

| Compte | Capital de départ | Valeur Alpaca | Écart | Drawdown depuis le pic |
|---|---|---|---|---|
| SYL | 999 953 $ | **1 058 854 $** | **+5,89 %** | **0 %** (au plus haut) |
| JU | 999 789 $ | **1 050 841 $** | **+5,11 %** | **0,50 %** |
| GIL | 999 992 $ | **1 002 120 $** | **+0,21 %** | **5,17 %** |

Ce sont des comptes **papier** (simulation, 1 M$ virtuel chacun). Le seul argent réel est celui de
l'Alchimiste sur Revolut : **847,73 $ aujourd'hui contre 847,69 $ hier**, soit **+0,04 $**. Intact.

## 2. Les marchés n'ont pas chuté aujourd'hui

| Actif | 18/08 | 19/08 | Variation |
|---|---|---|---|
| SPY | 768,17 | 769,37 | **+0,16 %** |
| BTC-USD | 64 431 | 65 355 | **+1,43 %** |

Journée calme, légèrement haussière.

## 3. Pourquoi la console affiche −9,10 % et −273 060 $ : deux bugs cumulés

La vue `v_gains_traders` produit les cartes de la console. Elle contient deux erreurs de calcul.

### Bug A — le pourcentage est calculé sur le gain, pas sur le portefeuille

`v_equity_points` définit l'« equity » de JU/SYL/GIL comme `oracle_performance.actual_pnl`, qui est le
**gain cumulé**, pas la valeur du compte. Un gain qui passe de 61 000 $ à 51 000 $ affiche donc
**−17,9 %**, alors que sur un portefeuille de 1 050 000 $ le mouvement réel est de **−0,44 %**.

### Bug B — ce mauvais pourcentage est ensuite multiplié par le capital entier

```sql
bs.baseline_equity * r.pct / 100.0 AS gain_usd
```
→ 999 789 × (−17,95 %) = **−179 462 $** affichés, pour une variation réelle d'environ **−4 600 $**.
L'erreur est d'un facteur ~39.

Le « AETHER (ensemble) −273 060 $ » est simplement la somme des trois montants faux.

### Aggravant — quatre lignes réinsérées à la main le 18/08 sur JU

```
18/08 07:52  gain 222 007  « reinsertion audit 18/08 - saut reel (cloture ETF), valeur Alpaca corroboree »
18/08 07:59  gain 221 986  « reinsertion audit 18/08 - saut reel (cloture ETF) »
18/08 14:30  gain 225 985  « reinsertion audit 18/08 - saut reel (cloture ETF) »
18/08 19:17  gain 230 200
```
Encadrement : **47 000–50 000 $ le 17/08**, **50 000–57 000 $ le 19/08**. Ces quatre lignes valent
**4,4×** le niveau des jours voisins.

**Elles sont fausses, et Alpaca le prouve** : le drawdown depuis le pic de JU vaut **0,50 %**. Si le
compte avait réellement valu 1 230 000 $ hier pour 1 050 000 $ aujourd'hui, ce drawdown serait de
~14,6 %. Alpaca n'a jamais vu ce pic. La mention « valeur Alpaca corroboree » de la note est
contredite par Alpaca lui-même.

## 4. Le vrai problème : GIL est massivement vendeur à découvert sur MSTR

GIL a réellement reculé aujourd'hui, mais pas à cause des marchés — **à cause d'une position short**.

| Ticker | Sens | Quantité | Exposition | Perte latente |
|---|---|---|---|---|
| **MSTR** | **short** | **−5 265** | **−558 353 $** | **−52 485 $ (−10,4 %)** |
| XLE | short | −1 777 | −113 275 $ | −10 842 $ (−10,6 %) |

À eux deux : **−63 327 $**, ce qui explique la quasi-totalité du recul de GIL sur la journée.

MSTR est un proxy Bitcoin. BTC a monté de +1,43 % aujourd'hui → MSTR monte → un short perd.

**Et le robot a renforcé ce short perdant deux fois aujourd'hui :**

| Heure (FR) | Ordre | Montant |
|---|---|---|
| 15:48 | GIL **sell** MSTR | 14 952 $ |
| 18:41 | GIL **sell** MSTR | 2 963 $ |

Un `sell` sur un titre non détenu **augmente** la vente à découvert. Le système moyenne donc à la
baisse sur une position qui perd 10 %.

## 5. Effet de levier réel, invisible dans la console

La console additionne les `market_value`, or les shorts sont négatifs et **compensent** les longs.
L'exposition brute est bien plus élevée que ce qui s'affiche :

| Compte | Longs | Shorts | Exposition brute | Levier ≈ |
|---|---|---|---|---|
| GIL | ≈ +1 000 000 $ | ≈ −920 000 $ | ≈ 1,9 M$ | **~1,9×** |
| SYL | ≈ +400 000 $ | **TLT −1 644 550 $ · IEF −1 334 839 $** et autres ≈ −3,0 M$ | ≈ 3,4 M$ | **~3,2×** |

SYL est donc vendeur à découvert de **~3 M$ d'obligations** sur un compte de 1,06 M$. Aujourd'hui ça
lui rapporte (TLT et IEF baissent, +10 629 $ et +4 154 $ de latent), mais le risque est réel et il
n'apparaît nulle part.

## 6. Qualité des données de position — à corriger aussi

`oracle_positions_live` est incohérent sur deux points :

- `cost_basis` ne correspond pas à `qty × avg_entry_price`. Exemples : SYL XLF → position de **0,42 $**
  avec un `cost_basis` de **149 497 $** (facteur 388 611) ; JU AMZN → 0,48 $ contre 16 307 $ ;
  GIL ETHUSD → 29 $ contre 48 924 $. `cost_basis` semble contenir le **notionnel de l'ordre d'origine**,
  jamais mis à jour quand la position est réduite.
- `side` contredit parfois le signe de `qty` : JU META est marqué `long` avec `qty = −59,1` ;
  JU COST est `long` avec `qty = −16`.

Tout P&L calculé à partir de `cost_basis` est donc faux.

## 7. Ce qu'il faudrait faire

1. **Corriger `v_gains_traders`** : calculer le rendement sur `baseline_equity + cumulative_pnl`
   (ou directement sur `alpaca_portfolio_value`), et ne plus multiplier un pourcentage de gain par le
   capital entier.
2. **Purger les 4 lignes réinsérées du 18/08 sur JU** dans `oracle_performance`, ou les marquer comme
   non fiables pour qu'elles sortent des séries.
3. **Afficher l'exposition brute et le levier** dans la console (somme des valeurs absolues), pas
   seulement le net.
4. **Recharger `cost_basis` depuis Alpaca** à chaque sync au lieu de conserver le notionnel d'ordre.
5. **Décision de gestion, qui appartient à Chachou** : encadrer le renforcement automatique d'un short
   déjà perdant (MSTR −10,4 %). Techniquement, c'est un garde-fou à ajouter au Sage Risque ou au
   routeur d'ordres ; ce n'est pas à moi de décider s'il faut couper la position.

## Note de méthode

Ma première mesure comparait la dernière valeur de `v_equity_points` d'aujourd'hui à celle d'hier et
donnait « GIL −95 %, JU −78 % ». **C'était faux** : cette vue ne contient pas une courbe d'equity mais
le P&L d'évaluations ponctuelles. J'ai vérifié la définition de la vue avant de conclure. C'est la
raison pour laquelle le chiffre de la console est faux, lui aussi : il repose sur la même confusion.
