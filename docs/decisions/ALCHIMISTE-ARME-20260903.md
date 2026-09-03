# L'Alchimiste réel est armé — 03/09/2026

`ju_crypte_config.kill_switch` : `OFF` → **`ON`**, sur demande explicite de Chachou
(« je veux mettre l'alchimiste en route », « je peux mettre 50 euros dessus »).

Les plafonds ne sont **pas** touchés, à sa demande — le dé-stakage de SOL et ETH
arrive dans quelques jours :

```
max_order_usd  =  50 $
max_daily_usd  = 200 $
allowed_pairs  = *
tp / sl        = 5 % / 4 %
```

---

## Le taux de frais, trouvé dans ses propres données

Chachou : « va le trouver !!! ». La table `revolut_univers_complet` porte
`bid`, `ask` et `mid` pour **303 paires** — le spread bid/ask EST le coût
aller-retour sur Revolut X.

```sql
(ask - bid) / mid * 100   -- coût aller-retour, en %
```

| Périmètre | Médiane | Moyenne | Min | Max |
|---|---|---|---|---|
| les 303 paires | 0,871 % | 0,963 % | 0,010 % | 5,860 % |
| **les paires que l'Alchimiste propose** | **0,159 %** | 0,609 % | 0,021 % | 3,300 % |

Détail des paires réellement proposées :

| Paire | Spread A/R | Fois proposée |
|---|---|---|
| **BTC-USD** | **0,021 %** | 20 |
| SOL-USD | 0,027 % | 2 |
| TRX-USD | 0,033 % | 4 |
| ETH-USD | 0,039 % | 4 |
| LINK-USD | 0,051 % | 1 |
| XRP-USD | 0,054 % | 2 |
| DOGE-USD | 0,067 % | 3 |
| AVAX-USD | 0,074 % | 3 |
| XLM-USD | 0,159 % | 3 |
| MEW-USD | 0,532 % | 2 |
| HFT-USD | 0,530 % | 3 |
| LRC-USD | 0,632 % | 2 |
| OSMO-USD | 0,855 % | 1 |
| ANKR-USD | 1,066 % | 1 |
| RLC-USD | 1,087 % | 1 |
| IDEX-USD | 1,827 % | 1 |
| **TRU-USD** | **3,299 %** | **9** |

---

## Le verdict : la stratégie passe largement

Rejeu des **27 trades réellement notés** du virtuel, chacun avec le spread réel
de SA paire (0 trade sans spread connu) :

```
spread moyen réellement subi   :  0,404 %
P&L brut moyen                 : +1,585 %
P&L NET moyen                  : +1,181 %
gagnants nets                  :  20 / 27
rendement composé NET          : +33,63 %
```

**Le seuil de bascule était 1,585 %. Le coût réel est 0,404 %.** Marge de 4×.

### Trois réserves, dites franchement

1. **La photo des spreads date du 07/07/2026** — deux mois. Les spreads bougent,
   surtout sur les petites paires. La table n'a pas été rafraîchie depuis.
2. **C'est le spread SEUL.** Si Revolut X applique une commission par-dessus,
   il faut l'ajouter. Les données de Chachou ne la contiennent pas — je ne peux
   pas la mesurer, et je ne l'invente pas.
3. Le calcul suppose qu'on subit le spread **complet** à l'aller-retour (achat à
   l'ask, vente au bid). C'est l'hypothèse prudente.

---

## Le point noir : TRU-USD

**3,299 % de spread aller-retour, et l'Alchimiste l'a proposée 9 fois** — c'est
sa deuxième paire la plus proposée après BTC.

À elle seule, elle mange **deux fois** le gain brut moyen de la stratégie
(+1,585 %). Un aller-retour sur TRU est perdant d'avance, quelle que soit la
qualité de la décision.

Même famille : IDEX 1,827 %, RLC 1,087 %, ANKR 1,066 %.

Je ne change rien aujourd'hui — Chachou a demandé qu'on ne touche pas aux
réglages. Mais c'est le premier levier à regarder : donner le spread à
l'Alchimiste dans son contexte, ou refuser les paires au-dessus d'un seuil.

---

## Ce qui va se passer concrètement

Le cash disponible est de **2,52 $**. Les plafonds (50 $ / 200 $) ne seront donc
pas atteints : le premier ordre réel fera au plus 2,52 $.

C'est le meilleur moment possible pour armer — **le risque est plafonné par le
cash lui-même**, et ça permet de vérifier la chaîne complète en conditions
réelles avant que les 50 € et le dé-stakage n'arrivent.

À surveiller au prochain run :

- `ju_crypte_orders` : une ligne avec `dry_run = false` et un `order_id` Revolut
- `alchimiste_crypte_propositions` : `oui_at` et `prix_exec` renseignés au lieu
  de rester NULL comme les 63 précédentes
- l'écart entre `prix_ref` (ce que l'Alchimiste visait) et `prix_exec` (ce qu'il
  a payé) — c'est la mesure du spread réellement subi, en direct

Le désarmement est immédiat : `kill_switch` sur `OFF`.
