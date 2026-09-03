# Est-ce que chaque trader gère et écrit ses TP/SL ? — audit du 03/09/2026

Les deux bouts de la chaîne pour chacun des cinq : ce que le prompt demande,
ce qui est écrit en base, si les valeurs varient, et si le stop **agit**.

---

## Le tableau

| Trader | Demandé au prompt | Écrit en base | Varie ? | Le stop agit ? |
|---|---|---|---|---|
| **JU** (301) | oui, clés requises | **10/10 des achats** (20/28 ordres) | oui — SL 3 à 5, TP 3,5 à 12, **7 valeurs de TP** | oui, mesuré |
| **SYL** (303) | oui, dans le schéma | **6/6 des achats** (14/28) | oui — SL 1 à 5, TP 2 à 10 | oui, même mécanisme |
| **GIL** (305) | oui, dans le schéma | 6/19 ordres, **aucun achat** | **non — 5/10, une seule valeur** | oui, déclenché ×2 |
| **Marées** (20015) | oui | **10/10** | oui — TP 1 à 1,4, SL 0,65 à 0,9 (échelle forex) | virtuel uniquement |
| **Alchimiste** (10012) | oui, **depuis aujourd'hui** | **2/2** depuis la fiche | oui — 5/3 puis 7/3 | **non, aucun stop réel** |

## Les NULL ne sont pas un défaut

Sur 7 jours, la répartition par sens est sans ambiguïté :

```
JU   buy  10 → 10 avec SL, 0 sans        JU   sell 18 →  8 sans SL
SYL  buy   6 →  6 avec SL, 0 sans        SYL  sell 22 → 14 sans SL
GIL  buy   0                              GIL  sell 19 → 13 sans SL
```

**Tout achat porte ses deux seuils. 100 %.** Les NULL sont exclusivement sur des
ventes — une vente qui solde une position n'a pas de sortie à définir. C'est
cohérent, pas un trou.

GIL n'a passé aucun achat depuis 7 jours : son coupe-circuit `drawdown_8pct` est
actif depuis le 25/08 et bloque les ouvertures. Ses 6 seuils écrits sont sur des
ventes, et il met **toujours 5/10** — c'est le seul des cinq qui ne calibre pas.

## Où vit le stop, exactement

**Pas chez Alpaca.** `execute-trades` envoie `order_class: 'simple'` — aucun ordre
bracket, aucun stop posé chez le courtier.

Le stop est appliqué **à chaque run** par `execute-trades`, avec le seuil que
l'agent lui-même a écrit :

```js
const _s = seuilsSortie[sym]                       // lu dans oracle_college_orders
const _tpSeuil = (_s && _s.tp !== null) ? _s.tp/100 : null
const _slSeuil = (_s && _s.sl !== null) ? _s.sl/100 : null
if (_tpSeuil !== null && plpc >= _tpSeuil) reason = 'take_profit'
else if (_slSeuil !== null && plpc <= -_slSeuil) reason = 'stop_loss'
```

Trois choses à retenir :

1. **Depuis la v44, il n'y a plus de valeur de repli.** Sans seuil venu de
   l'Archimage, aucune sortie automatique. C'est le trader qui décide, ou
   personne. C'est exactement ce que tu demandais.
2. **Les bornes de vraisemblance sont larges** : TP 1 à 200 %, SL 1 à 60 %. Elles
   ne servent qu'à rejeter le `0` que les prompts 303 et 305 montrent dans leur
   exemple `trades_extended` — un modèle qui recopie l'exemple renvoie 0, et 0 ne
   veut pas dire « sors tout de suite » mais « je ne me prononce pas ».
3. **Ça se déclenche pour de vrai**, c'est mesuré sur 14 jours :

```
GIL  « sortie auto stop_loss a 5 % (agent) »    ×2   le 01/09
JU   « sortie auto take_profit a 6 % (agent) »  ×1   le 03/09
```

La provenance `(agent)` est écrite dans `rationale`, donc relisible six semaines
plus tard.

**La limite honnête :** ce stop n'est vérifié qu'aux 4 runs de la journée. Entre
deux runs, rien ne surveille. Un décrochage à 10 h du matin n'est vu qu'à 15h45.

## L'Alchimiste est le seul sans filet

Il écrit maintenant ses TP/SL et il les fait varier (5/3 à 15h45, 7/3 à 18h30),
mais **rien ne les applique sur le compte réel Revolut X**. Il n'y a pas
d'équivalent de la boucle de `execute-trades`. La vue `v_alc_positions_reelles`
signale le franchissement ; la coupe est manuelle.

Les Marées, elles, n'ont pas ce problème : `marees_config.kill_switch = OFF`,
tout est virtuel, leurs seuils vivent dans `marees_virtual_trades`.

---

## Ce qui reste ouvert, par ordre d'importance

1. **Le stop réel de l'Alchimiste** — bloqué sur un point non mesuré : est-ce que
   Revolut X accepte une vente en quantité de base ? Ta position ne représente que
   **1,2 % du BTC que tu détiens** (0,00003173 sur 0,00271357), donc une vente
   calculée en dollars mordrait dans les 98,8 % restants.
2. **GIL ne calibre pas** — 5/10 sur tous ses ordres. Ce n'est pas un bug : son
   prompt porte encore une ligne « Stop loss crypto 5%, levier ETF 4% », de ma
   main, comme la fourchette que tu as retirée du 10012. Même remède si tu veux.
3. **Le stop entre deux runs** — quatre vérifications par jour, c'est tout.
