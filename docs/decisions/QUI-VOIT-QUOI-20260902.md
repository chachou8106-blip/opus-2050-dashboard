# Pourquoi Marées voit plus que les autres

Question de Chachou, 02/09/2026. Mesuré sur le blueprint du scénario 7051944 et
sur le code de l'edge function, pas de mémoire.

## Ce que chaque agent lit réellement

Toutes les références `{{NNN.xxx}}` extraites du corps de chaque module :

| Agent | Module | Position dans le flux | Modules lus |
|---|---|---|---|
| JU | 301 | **27** | 105, 110 (CTX), 215 (SAGES), 9990 (son coffre Alpaca) |
| SYL | 303 | **29** | 103 (son coffre), 105, 110, 215 |
| GIL | 305 | **31** | 104 (son coffre), 105, 110, 215 |
| Alchimiste | 10012 | **69** | 105, 110, 215, **306**, 10010, 10011, 20022, 20023 |
| Marées | 20015 | **76** | 105, **20014** |

## La raison : l'ordre d'exécution, pas une faveur

Les trois Archimages tournent aux positions **27, 29 et 31**. Les ordres, eux,
ne partent qu'aux positions 41 (JU), 47 (SYL) et 52 (GIL).

**Quand JU parle, SYL et GIL n'ont pas encore parlé.** Dans Make, une expression
ne peut référencer qu'un module qui a *déjà tourné* : les trois Archimages ne
peuvent donc physiquement pas se voir. Ce n'est pas un oubli de câblage, c'est
la conséquence directe de leur place dans le flux.

Marées tourne en **dernier, position 76** — après les décisions, après
l'exécution des ordres, après leur enregistrement en base, après l'Alchimiste.

## Et surtout : Marées ne lit pas des modules Make, il lit une fonction Supabase

`20014` n'est pas un module de calcul, c'est un appel à l'edge function
**`marees-context`**. Et cette fonction va chercher en base ce que le run vient
d'écrire :

```ts
sb('oracle_sages_report?select=sage_name,sage_output,created_at&order=created_at.desc&limit=5'),
sb('oracle_college_orders?select=archimage,symbol,side,rationale,created_at&order=created_at.desc&limit=24'),
sb('alchimiste_crypte_propositions?select=paire,side,confidence,raison&statut=eq.proposee&order=proposed_at.desc&limit=10'),
fetch(`${SUPABASE_URL}/functions/v1/fx-context`)
```

qu'elle assemble en :

```ts
conseil: {
  sages: sages || [],                    // les 5 Sages, sortie complète
  archimages_actions: college || [],     // 24 derniers ordres AVEC leur rationale
  alchimiste_revolut: alch || []         // propositions de l'Alchimiste en attente
},
fx_context: fx
```

C'est là toute la différence. Un module Make est prisonnier de sa position dans
le flux ; une fonction Supabase lit la base, donc **tout ce qui y est déjà**.

## Une asymétrie réelle, celle-là : l'Alchimiste

L'Alchimiste tourne en position **69**, donc après tout le monde. Il pourrait
voir les trois Archimages. Or il ne lit que **306** — les ordres de **GIL**.
Pas 302 (JU), pas 304 (SYL).

Rien ne l'en empêche : les deux modules ont tourné bien avant lui. C'est une
lacune de câblage, pas une contrainte. Elle est corrigeable en ajoutant les
références 302 et 304 à son corps.

## Faut-il pour autant tout montrer à tout le monde ?

C'est une décision de conception, pas une évidence, et elle revient à Chachou.

Trois agents qui se lisent en cascade finissent par se ressembler : le second
s'ancre sur le premier, le troisième sur les deux. On y perdrait la
décorrélation qui est la raison d'être du Collège — et elle est déjà partielle.
Mesuré sur les rendements quotidiens des jours communs (`v_comparaison`) :
JU/SYL 0,43, GIL/JU 0,42, GIL/SYL 0,10, moyenne 0,32.

Si l'objectif est que chaque Archimage sache ce que les autres ont fait, la voie
propre est celle de Marées : une fonction Supabase qui leur sert les décisions
du run **précédent** — sans créer d'ancrage à l'intérieur du run courant.
