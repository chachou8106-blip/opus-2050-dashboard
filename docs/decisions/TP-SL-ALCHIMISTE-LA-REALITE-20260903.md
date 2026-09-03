# TP 5 % / SL 4 % — qui le décide ? Personne. La réalité des faits.

Question de Chachou, 03/09/2026 : « qui le définit, car normalement chaque
trader choisit ses entrées et sorties, rien n'est fixe ». Il a raison, et voici
ce que les faits disent.

---

## 1. C'est écrit en dur dans une fonction SQL

`alc_rebuild_virtual`, ligne d'insertion :

```sql
insert into public.alchimiste_virtual_trades
  (proposition_id, paire, side, prix_entree, montant, opened_at, tp_pct, sl_pct, ...)
values (v_lot.prop_id, r.paire, 'buy', v_lot.entry, v_match, v_lot.t0, 5, 4, ...);
                                                                        ^^^^
```

**`5, 4` en clair, et la chaîne apparaît quatre fois dans la fonction.**

Ce n'est même pas lu depuis `ju_crypte_config` : les clés `tp_optimal_backtest`
et `sl_optimal_backtest` existent bien dans la table, mais **la fonction ne les
consulte pas**. Vérifié : `prosrc ilike '%tp_optimal_backtest%'` = false.

## 2. L'Alchimiste n'est jamais consulté

Son schéma de sortie, dans le prompt du module 10012 :

```
{"propositions":[{"paire","side","montant","confidence","raison","prix_ref"}], ...}
```

**Six clés. Ni `tp_pct`, ni `sl_pct`.** On ne lui demande pas où il veut sortir.

Comparaison — les trois Archimages, eux, décident leurs sorties depuis le 31/08 :
`oracle_college_orders` porte `stop_loss_pct` et `take_profit_pct` renseignés par
JU, SYL et GIL (3/5 sur NVDA, 4/6 sur XOM/KO/V/MA, etc.). L'Alchimiste est le
seul à qui on impose les siennes.

## 3. Et le nom ment : ce réglage est perdant

Le backtest, recalculé automatiquement le 03/09 à 12:35 sur 62 trades :

| Rang | TP | SL | Win rate | Rendement composé |
|---|---|---|---|---|
| **1** | **7 %** | **1,5 %** | 35,5 % | **+76,17 %** |
| 2 | 7 % | 2 % | 38,7 % | +72,18 % |
| 3 | 7 % | 2,5 % | 41,9 % | +62,36 % |
| **21** | **5 %** | **4 %** | 48,4 % | **−10,49 %** ← le réglage en production |
| 48 | 2,5 % | 4 % | 51,6 % | −46,86 % |

**Le réglage appelé « optimal_backtest » est 21ᵉ sur 48, et il perd de l'argent.**
Le meilleur couple est TP 7 / SL 1,5 — 86,66 points au-dessus.

Et la console enfonce le clou : `aether.html` dessine un cadre doré sur la case
5/4 de la heatmap avec `const opt=(t===5&&s===4);` — **codé en dur**. L'écran
désigne comme « optimal » une case que le backtest classe 21ᵉ.

## 4. Sur le compte RÉEL, il n'y a aucun stop du tout

`revolut-x-trade`, le corps de l'ordre envoyé :

```js
const orderBody = {
  client_order_id: clientOrderId,
  symbol,
  side: sideNorm,
  order_configuration: { market: { quote_size: String(amount) } },
};
```

**Un ordre au marché, rien d'autre.** Pas de TP, pas de SL, pas de stop.

Le TP 5 / SL 4 n'existe donc **que dans le simulateur**. Sur le compte réel, une
position achetée reste ouverte jusqu'à ce que l'Alchimiste propose une vente et
qu'elle passe. Aucun filet automatique.

C'est à savoir maintenant que le `kill_switch` est armé. Le risque reste borné
par le cash (2,52 $) et les plafonds (50 $ / 200 $), mais il n'y a pas de stop.

---

## 5. Correction d'un chiffre que j'ai donné il y a une heure

J'ai annoncé un rendement net de **+1,181 % par trade**. C'était pessimiste :
j'ai compté les frais deux fois.

`alc_rebuild_virtual` a pour signature :

```
p_fee_pct double precision DEFAULT 0.18, p_max_hold_h integer DEFAULT 240
```

et calcule `v_pnl := (r.px / v_lot.entry - 1) * 100 - 2*p_fee_pct`.

**Le `pnl_pct` enregistré est donc déjà net de 2 × 0,18 = 0,36 %.** J'ai ensuite
retranché 0,404 % de spread par-dessus.

Le calcul juste :

```
rendement avant frais   = 1,585 + 0,360 = 1,945 %
spread réel mesuré      =               − 0,404 %
rendement NET par trade =                 +1,541 %
```

Ma conclusion ne change pas — la stratégie passe largement le seuil de bascule
de 1,585 % — mais le bon chiffre est **+1,54 %**, pas +1,18 %.

À noter : le 0,18 % par côté posé en dur dans la signature est proche de la
mesure réelle (0,404 / 2 = 0,202 % par côté). Celui qui l'a écrit avait vu juste.

---

## 6. Ce que ça donne comme choix

Rien n'est changé aujourd'hui — Chachou a demandé qu'on ne touche pas aux
réglages avant que le dé-stakage arrive. Trois pistes, par ordre de fidélité à
sa règle :

1. **Demander à l'Alchimiste son TP et son SL**, comme on l'a fait pour les trois
   Archimages le 31/08 : deux clés de plus dans son schéma de sortie, et
   `alc_rebuild_virtual` les lit au lieu d'écrire 5 et 4. C'est le seul qui
   respecte « chaque trader choisit ses sorties ».
2. **À défaut, lire `ju_crypte_config`** au lieu du dur — et y mettre le couple
   que le backtest désigne réellement, pas 5/4.
3. **Retirer le cadre doré codé en dur** de la heatmap, qui affirme un optimum
   que les chiffres démentent.

Et indépendamment : sur le compte réel, poser un stop reste à construire —
`revolut-x-trade` ne sait envoyer qu'un ordre au marché.
