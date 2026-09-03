# Le premier trade réel de l'Alchimiste — 03/09/2026, 15:49

Run `COLLEGE-20260903-1545`, exécution Make `719b870d…`, **statut succès, 76 opérations**.

---

## 1. Oui, il a tradé pour de vrai

```
ju_crypte_orders
  created_at  2026-09-03 13:49:03 UTC   = 15:49:03 Paris
  pair        BTC-USD      side  buy      amount_usd  2.50
  order_id    5b757821-81d7-4426-843a-8c111be30e77
  status      filled       dry_run       FALSE
```

C'est le premier ordre réel depuis le 13/08, et le premier jamais décidé par
l'Alchimiste (les 5 lignes du 13/08 étaient un nettoyage de portefeuille).

## 2. Et il a choisi ses sorties

La proposition du même run :

```
paire BTC-USD   side buy   prix_ref 78 806,06   montant 2,50   confidence 0,60
tp_pct 5,0      sl_pct 3,0
```

**Première proposition de l'histoire qui porte ses propres TP/SL.** La chaîne
livrée ce matin fonctionne de bout en bout : prompt → `alc_record_propositions`
→ colonnes. Et il n'a pas repris le 5/4 qu'on lui imposait : il a mis SL 3.

Les 5 lignes de dé-staking sont écrites elles aussi, sept clés remplies,
verdict GARDER partout (ATOM 21,06 % / 21 j, TON 17,67 % / 2 j, SOL 6,16 % / 3 j,
ETH 2,45 % / 5 j, TRX 3,26 % / 14 j).

## 3. Qui a déclenché l'ordre — ce n'est pas ce que je croyais

**Aucun module Make n'appelle `revolut-x-trade`.** J'ai cherché dans les 80
modules : zéro occurrence. L'exécuteur est le module **20013 `alc-auto`**
(« L'ALCHIMISTE AUTOMATE »), position 71, juste après le Registre de Cristal
qui enregistre les propositions et juste avant le Héraut Discord.

Son corps est figé :

```json
{"run_id":"{{...}}","dry_run":false}
```

`dry_run: false` **en dur, à chaque run**. Le seul verrou était le
`kill_switch`. Il est passé à `ON` aujourd'hui : le premier run suivant a donc
exécuté, automatiquement, sans validation.

Le plafond qui a joué n'est ni les 50 $ ni les 200 $ : c'est le **cash
disponible**, 2,52 $. `alc-auto` plafonne l'achat à `min(max_order_usd, cash)`.

**Quand le dé-stakage de SOL et ETH arrivera, ce plafond disparaît** et les
ordres monteront jusqu'à 50 $ pièce, 200 $ par jour, automatiquement.

## 4. Discord : le module a bien tourné

80 modules dans le scénario, dont 4 qui ne consomment pas d'opération
(101, 110, 215 SetVariable et 999 Router) : **80 − 4 = 76**, exactement le
compte du run. Tous les modules ont donc tourné, **le 10031 compris**.

Il n'a aucun filtre, ni sur le module ni sur sa route — il ne peut pas être
sauté. Et il lit bien le résultat de l'exécuteur :

```
Kill switch: {{20013.data.kill_switch}} | Executes: {{20013.data.a_executer}}/{{20013.data.proposees}}
✅ {{...side}} — {{...paire}} — {{...montant_execute}}$
```

Avec les données du run, le message envoyé commençait donc par :

```
**L'ALCHIMISTE — CRYPTE REVOLUT X (REEL)**
Kill switch: ON | Executes: 1/1

✅ BUY — BTC-USD — 2.5$
```

Il part par la **connexion Discord** (`discord:createMessage`), dans le salon
**`1522017680838627458`** — pas par le webhook du Héraut du collège (module 981),
qui est un autre canal. C'est ce salon-là qu'il faut regarder.

---

## 5. Trois trous réels, trouvés en vérifiant

### a) Le retour n'est jamais écrit

`alchimiste_crypte_propositions.oui_at` et `.prix_exec` sont restés **NULL**
alors que l'ordre est passé. Ce n'est pas un bug : `alc-auto` le dit en tête de
fichier, « NE MODIFIE JAMAIS le statut des propositions ». La proposition va
donc expirer dans 6 heures comme si rien ne s'était produit, et rien ne relie
la ligne de `ju_crypte_orders` à la proposition qui l'a causée.

### b) Le prix payé n'existe nulle part

`ju_crypte_orders` a huit colonnes : `id, created_at, pair, side, amount_usd,
order_id, status, dry_run`. **Aucune colonne de prix.** Et `revolut-x-trade`
n'écrit que cette ligne.

C'est exactement la mesure que j'avais dit de surveiller — l'écart entre
`prix_ref` (78 806,06) et le prix réellement payé, qui donne le spread subi en
direct. **Elle est impossible à faire.** Le prix n'existe que chez Revolut,
sous l'`order_id` 5b757821.

### c) Toujours aucun stop sur le compte réel

Il y a maintenant 2,50 $ de BTC en portefeuille avec un TP 5 % et un SL 3 %
qui n'existent **que dans le simulateur**. `revolut-x-trade` envoie un ordre au
marché nu. Rien ne fermera cette position automatiquement.

---

## 6. Ce que je propose, sans le faire

Les trois corrections touchent la fonction qui envoie les ordres réels. Règle
du 20/08 : elles ne partent pas sans test en conditions réelles ou accord
explicite. Par ordre d'utilité :

1. **Ajouter le prix payé.** `revolut-x-trade` lit déjà la réponse de Revolut ;
   il faut une colonne `prix_exec` sur `ju_crypte_orders` et l'écrire. Sans ça
   on ne saura jamais ce que le spread coûte vraiment.
2. **Refermer la boucle.** Écrire `oui_at` et `prix_exec` sur la proposition
   exécutée, et y poser l'`order_id`. Une colonne de plus, pas de logique
   nouvelle.
3. **Le stop réel.** C'est le seul vrai chantier : il faut regarder si Revolut X
   accepte un ordre stop, et sinon le simuler en surveillant les prix. À décider
   séparément.
