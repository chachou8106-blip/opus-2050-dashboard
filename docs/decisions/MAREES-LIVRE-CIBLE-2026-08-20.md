# Marées — le livre cible n'était pas un livre cible

> Corrigé côté Supabase, aucune intervention Make. Sauvegarde préalable :
> `bak_20260820_marees_propositions` (113 lignes, table intacte).

## Je dois corriger mon propre audit d'hier

J'avais écrit : « **17 trades clos, 0 gagnants**, 68 positions ouvertes, une seule idée répétée. »
En lisant le code et les données, deux de ces trois affirmations sont fausses.

### Ce que j'ai présenté comme 68 positions, ce sont 4 positions

```sql
select paire, side, count(*) n, count(distinct run_id) runs
from marees_propositions where statut='proposee' group by paire, side;
-- USD-JPY buy  |  34  |  34
-- EUR-USD sell |  30  |  30
-- GBP-JPY buy  |  17  |  17
-- EUR-GBP sell |  17  |  17
```

**`n` est exactement égal à `runs` sur chaque ligne.** Ce n'est pas un agent qui empile des paris :
c'est **la même position réécrite à chaque run**.

Le prompt système de l'Archimage dit pourtant, mot pour mot :

> « Ton résultat est un **LIVRE CIBLE COMPLET** : à chaque run tu décris TOUTES les positions à
> détenir MAINTENANT […] le miroir aligne le book réel sur ta cible ; **une paire absente de ta
> cible = position fermée**. »

Cette sémantique **n'était implémentée nulle part.** `marees_record_propositions` faisait un
`insert` du livre entier, sans jamais rien clôturer ni dédupliquer. 35 runs × ~3,2 lignes =
113 lignes en base pour **37 positions réelles**, dont **4 encore ouvertes** aujourd'hui.

### Le win rate ignorait 28 clôtures sur 45, dont 16 gagnantes

`marees_rebuild_virtual` renvoyait `win_rate = TP / (TP + SL)`. Les sorties `MARCHE` — une position
qui atteint sa durée maximale et se solde au cours du moment — n'y entraient pas :

```sql
select exit_reason, count(*) filter (where pnl_pct>0) gagnants,
                    count(*) filter (where pnl_pct<=0) perdants
from marees_virtual_trades group by exit_reason;
-- SL     |  0 | 17
-- MARCHE | 16 | 12   <-- 16 gains invisibles
```

D'où le « 0 gagnant » que je t'ai annoncé. Il était vrai **des seuls stop-loss** — ce qui est une
tautologie, un stop-loss est une perte par définition — et je l'ai présenté comme le bilan complet.

## Ce qui reste vrai

Le biais directionnel existe, mais il est bien plus modeste que je l'ai dit. Le livre actuel :

| Paire | Sens | Tenue depuis |
|---|---|---|
| USD-JPY | achat | 14/08 16:18 |
| GBP-JPY | achat | 19/08 21:24 |
| EUR-GBP | vente | 19/08 20:04 |
| EUR-USD | vente | 18/08 14:30 |

USD-JPY achat + GBP-JPY achat = **deux positions sur le même pari « yen faible »**. Sa propre règle
dit « Max ~2 positions même sens sur un groupe corrélé » : il est **à la limite, pas en infraction**.

## Le bilan réel, après correction

| | Avant (doublons comptés) | Après |
|---|---|---|
| Trades | 113 lignes | **37 positions** |
| Clôturés | 45 | **35** |
| Gagnants / perdants | 16 / 29 | **10 / 25** |
| Win rate | 35,6 % | **28,6 %** |
| Somme des rendements | −12,3 % | **−3,3 %** |

Le win rate est **plus mauvais** que je ne le croyais ; la perte est **quatre fois plus petite**.
Les deux allaient dans le même sens : les doublons multipliaient une mauvaise passe tenue longtemps.

À 28,6 % sur 35 trades, la sous-performance est réelle et le volume commence à être signifiant.
Mais ce sont désormais de vrais chiffres.

## Ce que j'ai changé

**1. `marees_record_propositions` — vraie sémantique de livre cible.**
- ligne présente au run précédent **et** au nouveau → **tenue** : la ligne d'origine est conservée,
  prix d'entrée et date d'ouverture inchangés, aucune insertion ;
- ligne absente du nouveau livre → **fermée** (`cloturee_at = now()`) ;
- ligne nouvelle → **ouverte**.

Le résumé Discord décrit maintenant **le livre courant** et non les seules nouveautés :
`livre cible : 4 positions (0 ouverte, 4 tenues, 0 fermée)`, chaque ligne annotée
« (tenue depuis 14/08 16:18) » ou « (nouvelle) ».

La clé `inserted` du retour est **conservée**, le module Make qui la lit n'a pas besoin de changer.

**2. `marees_rebuild_virtual`** — une position fermée cesse de courir à `cloturee_at` (nouveau
motif de sortie `FERME`) au lieu d'aller au bout des 96 h ; le `win_rate` compte toute clôture au
signe du P&L.

**3. `marees_evaluate_and_learn` et `marees_resume`** — prennent le motif `FERME` en compte, sinon
le brain state serait tombé de 35 trades à 2. `marees_resume` ne compte plus les doublons.
Au passage, un `jsonb_agg(e ORDER BY ord DESC)` inversait la chronologie du tableau `learnings`
à chaque fois qu'il dépassait 30 entrées — corrigé.

**4. Historique replié.** Les 76 lignes qui n'étaient que des reconductions passent en
`remplacee` (conservées, exclues des statistiques) ; les 37 premières lignes de chaque série
gardent leur statut et reçoivent leur `cloturee_at`.

### Tests passés

- **Idempotence** : `marees_record_propositions` rappelée avec le livre ouvert actuel →
  `0 nouvelle, 4 tenues, 0 fermée`, table inchangée à 113 lignes.
- **Fermeture + ouverture** : appel avec `[USD-JPY buy, AUD-USD buy]` dans une transaction annulée
  par exception → `1 tenue, 1 nouvelle, 3 fermées`. Vérifié après coup : **0 ligne de test écrite**.

## Deux points que je n'ai pas touchés, et pourquoi

### Le filtre du module 20014 s'appelle « [OFF] » mais il est ON

```json
"filter": {
  "name": "[OFF] Marées — mettre ON pour activer",
  "conditions": [[ { "a": "ON", "b": "ON", "o": "text:equal" } ]]
}
```

La condition compare `"ON"` à `"ON"` : **toujours vraie**. Marées tourne, malgré son étiquette.
C'est cohérent avec les 35 runs en base — mais si tu lis le nom du module en croyant l'agent
désactivé, tu te trompes. Correction possible via Maia si tu veux que l'étiquette dise la vérité,
ou un vrai interrupteur si tu veux pouvoir le couper. **Dis-moi lequel des deux.**

### USD-JPY est tenu depuis 6 jours alors que la doctrine dit 2 à 4 jours

Le prompt vise une détention de « 2 à 4 jours » et la simulation coupe à 96 h. USD-JPY est au livre
depuis le 14/08 à 16:18. Résultat : **le livre le tient encore, la simulation l'a déjà soldé.**
Les deux ne parlent plus de la même position.

Deux réponses possibles — allonger `p_max_hold_h`, ou apprendre à l'Archimage à fermer ce qu'il
tient depuis trop longtemps. C'est un choix de doctrine, pas un bug : **je te le laisse.**
