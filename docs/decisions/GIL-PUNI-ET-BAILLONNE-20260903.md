# « Il ne remontera jamais son drawdown » — Chachou a raison, et les chiffres vont plus loin

Question du 03/09 au soir : *« comment les coupe-circuits de GIL vont être enlevés s'il n'a
plus le droit d'acheter ? Il ne remontera jamais son drawdown. Ça ne serait pas mieux de le
virtualiser sur ses choix, et s'il a raison ça débloque les garde-fous — comme le font
l'Alchimiste et Marées ? »*

---

## 1. L'impasse est réelle, et mesurée

La levée du coupe-circuit est écrite dans `check_circuit_breakers` :

```sql
update oracle_circuit_breakers set auto_resolved = true, resolved_at = now()
  where breaker_type = 'drawdown_8pct' and b.current_drawdown < 0.08
```

Il faut donc que le drawdown **redescende sous 8 %**. Or :

```
25/08  déclenchement       drawdown 10,23 %
03/09  aujourd'hui         drawdown 11,15 %      (dd Alpaca 12,40 %)
```

**Neuf jours de vente forcée, et le drawdown a EMPIRÉ de près d'un point.** C'est
arithmétique : vendre fige la perte, et sans achat il ne reste que les lignes existantes
pour remonter. GIL a deux coupe-circuits ouverts, `drawdown_5pct` depuis le 20/08 et
`drawdown_8pct` depuis le 25/08, aucun résolu.

Pour comparaison, les autres se sont résolus tout seuls : JU en 4 jours, SYL en 12.
Eux n'ont jamais été bloqués aussi longtemps.

Et son poids dans la synthèse du Collège est tombé à **0,010** — 1 %, contre 0,46 pour JU
et 0,53 pour SYL. Il n'est plus écouté.

## 2. Ce n'est pas qu'on l'empêche d'acheter. C'est qu'on le fait taire.

Le coupe-circuit ne bloque pas seulement l'exécution. Il change son PROMPT :

```
CIRCUIT_BREAKERS: Si CTX contient circuit_breakers actifs pour GIL:
                  seulement SELL ou HOLD.
```

Conséquence : **on ne sait même pas ce qu'il aurait acheté.** Il n'émet plus de décision
d'achat, donc il n'y a rien à mesurer, donc rien ne peut jamais prouver qu'il avait raison.
La boucle est fermée sur elle-même.

C'est encore la règle du 26/08 : on lui donne un verbe d'action (« seulement SELL ou HOLD »)
au lieu de lui donner la mesure et de le laisser conclure.

## 3. Ce que ses décisions valent réellement

`bt_replay_archmages(0.05, 240)` rejoue les ordres de chaque Archimage avec **ses propres
TP/SL** et une durée de détention maximale, frais 0,05 % :

| | trades | réussite | rendement moyen | rendement total | profit factor |
|---|---|---|---|---|---|
| **GIL** | 59 | **78,0 %** | **+3,98 %** | **+816,3 %** | **5,19** |
| JU | 76 | 60,5 % | +2,12 % | +333,0 % | 2,26 |
| SYL | 33 | 66,7 % | +3,91 % | +230,5 % | 3,54 |

**Le puni est le meilleur des trois sur ses propres choix.** Et son taux de réussite brut
sur les 293 runs est aussi le plus équilibré : 146 gagnés / 146 perdus, soit 50,0 %, contre
49,0 % pour JU et 53,0 % pour SYL.

### La réserve, dite franchement

Ce rejeu mesure la **qualité des entrées**, pas la performance réelle. Il applique une sortie
propre (TP/SL de l'agent, hold max 240 h) à des ordres qui, dans la vraie vie, ont subi le
dimensionnement, les ventes de désendettement, le mandat « minimum 2 SELL par run » et les
shorts. Il ne prouve pas que GIL est rentable ; il prouve que **ses choix d'entrée sont bons
et que l'écart vient d'ailleurs**. C'est exactement ce qu'il faut savoir avant de décider si
on le bâillonne.

## 4. La proposition de Chachou est la bonne, et la moitié existe déjà

L'Alchimiste et les Marées ont chacun un carnet virtuel, reconstruit toutes les 6 h par cron :

```
alc_rebuild_virtual()      job 15, toutes les 6 h
marees_rebuild_virtual()   job 17, toutes les 6 h
```

Leurs propositions sont notées **même quand rien ne part en réel** — c'est précisément ce qui
a permis de mesurer que l'Alchimiste virtuel gagnait pendant que le réel dormait.

Les trois Archimages n'ont pas cet équivalent permanent. Ils ont `bt_replay_archmages`, qui
rejoue les ordres **exécutés** — donc rien quand ils sont bloqués.

### Ce qu'il faudrait, concrètement

1. **Retirer « seulement SELL ou HOLD » du prompt** et le remplacer par la mesure : le motif
   du coupe-circuit, la valeur mesurée, le seuil franchi, et le fait que ses achats ne
   partiront pas au courtier tant que le drawdown n'est pas repassé sous le seuil. Il
   continue de dire ce qu'il ferait ; on cesse de lui dicter ce qu'il doit vouloir.
2. **Un carnet virtuel des Archimages**, sur le modèle exact de `alc_rebuild_virtual` : ses
   achats bloqués sont enregistrés avec son `prix_ref`, son `tp_pct` et son `sl_pct`, puis
   notés sur `price_history`. Les trois colonnes existent déjà dans `oracle_college_orders`.
3. **La levée par la preuve** : si le carnet virtuel de GIL affiche une performance positive
   sur N décisions bloquées, le coupe-circuit se lève — au lieu d'attendre un drawdown qui,
   mécaniquement, ne peut plus baisser.

Le garde-fou d'EXÉCUTION reste entier dans les trois cas : rien ne part chez Alpaca tant que
la preuve n'est pas faite. On ne desserre pas la sécurité, on lui donne une porte de sortie
mesurable au lieu d'une impasse.

## 5. Ce que je n'ai pas fait

Rien de tout ça, ce soir. C'est une modification de la boucle d'apprentissage de trois
agents, elle touche leur prompt et le mécanisme des coupe-circuits, et il est 22 h. Je pose
la mesure et la proposition ; c'est Chachou qui décide, comme pour tout ce qui entre dans la
tête d'un agent.

Une remarque au passage : `MAREES` porte aussi un coupe-circuit `win_rate_faible` ouvert
depuis le 21/08, avec `action_taken = aucune_action_automatique`. Celui-là ne bloque rien,
il informe. C'est la bonne forme.
