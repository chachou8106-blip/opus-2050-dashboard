# Le crash de GIL — module 305 — 27/08/2026

Run manuel du 27/08 à **13:09:42** sur le scénario 7051944 : arrêt à **31 opérations** sur
`InvalidConfigurationError — The provided JSON body content is not valid JSON`.

Le scénario compte 79 modules facturables, moins les 3 modules Binance `[OFF]` = 76 opérations
pour un run complet. L'opération 31 est le module **305 — ⚖️ L'ARBITRE DORÉ — GIL**.

## La cause, lue dans le panneau INPUT du module

```
…|CIRCUIT_BREAKERS=[{object},{object},{object}]|MEMORY_CORRECTION= ## \ ## \ ## \ ## \ …
… ## \|MES_ERREURS= ## \ ## \ ## \ … ## \|GIL_CATALYSTS=[]
```

`MEMORY_CORRECTION` et `MES_ERREURS` sortent une suite de ` ## ` séparés par des **antislashs
seuls**. Un antislash seul dans une chaîne JSON n'est pas un échappement valide : le corps
cesse d'être du JSON, et Make refuse la requête.

D'où viennent-ils : les deux expressions écrivent leurs guillemets internes échappés.

| Module | Expression | Résultat |
|---|---|---|
| 301 JU | `join(map(…learnings; "bias"); " ## ")` | passe |
| 303 SYL | `join(map(…learnings; "bias"); " ## ")` | passe |
| **305 GIL** | `join(map(…learnings; \"bias\"); \" ## \")` | **plante** |

Make conserve l'antislash dans la valeur produite : le séparateur devient ` ## \` et la clé
devient `bias\`, qui n'existe pas — d'où les trente valeurs vides collées par un séparateur
empoisonné. Les trois `replace(… ; backslash ; …)` qui suivent n'y peuvent rien : l'antislash
est introduit par l'expression elle-même, pas par la donnée.

## Qui l'a introduit — c'est moi

| Instantané | Forme | Taille |
|---|---|---|
| copie 25/08 15 h | `"bias"` sans antislash | 6434 |
| copie 26/08 16 h | `"bias"` sans antislash | 6434 |
| copie 26/08 restaurée V1 | `"bias"` sans antislash | 6434 |
| **copie 26/08 après mon prompt A** | **`\"bias\"` avec antislash** | 7051 |
| copie 27/08 | `\"bias\"` avec antislash | 6409 |

En appliquant mon prompt A du 26/08 sur le module 305, Maia a réécrit le champ et a échappé
les guillemets à l'intérieur des `{{...}}`. Mes trois contrôles — taille exacte, équilibre des
accolades, `JSON.parse` — ne pouvaient pas le voir. Pire : l'échappement rend le corps **plus**
valide au sens JSON strict. C'est précisément pour cela que le 305 passait `JSON.parse` brut
alors que le 301 et le 303, eux, échouent — et que ce sont eux qui tournent.

**Leçon : un corps de module Make n'est pas du JSON ordinaire. À l'intérieur d'un `{{...}}`,
les guillemets doivent rester nus. Ajouter au contrôle : aucune expression ne doit contenir
d'antislash.**

## Une affirmation que je dois retirer

J'ai écrit ce matin que `{{toString(…latest_web_catalysts)}}`, non protégé, casserait le
prochain run à coup sûr, parce que le champ contient 578 caractères de JSON pleins de
guillemets. **C'est faux.** Le panneau INPUT montre ce que `toString()` produit réellement sur
un tableau de collections Make :

```
CIRCUIT_BREAKERS=[{object},{object},{object}]        GIL_CATALYSTS=[]
```

Pas de guillemets, pas de JSON — `[{object}]`. Ces expressions ne peuvent pas casser le corps.
Le blindage supplémentaire que j'avais préparé (fichiers I, J, K) était inutile : supprimé.

Corollaire utile : cela confirme le choix du **format délimité** pour la chaîne Flash. Si
j'avais laissé `toString(210.catalysts)` dans le module 211, `oracle_flash_intel` aurait reçu
`[{object},{object}]`.

## Le correctif

`docs/maia/L-305-GIL-antislashs-parasites.txt` — deux remplacements, **6409 → 6401**
(huit antislashs en moins, rien d'autre). Il aligne le 305 sur ce que font déjà le 301 et le 303.

## Deux choses vues au passage, à traiter après un run vert

**1. `CTX` et `SAGES` sont vides.** Le corps envoyé commence par `CTX=|SAGES=|GIL_WR=0.5|…`.
Les deux variables du scénario (modules 110 et 215) arrivent vides au module 305 : l'Archimage
décide sans aucun contexte de marché ni aucune synthèse des Sages. Les champs `GIL_*` sont bien
remplis, eux, car ils viennent directement du module 105.

Ce n'est **pas** une régression de mon fait : les trois Archimages référencent la variable sous
la forme `{{CTX}}` (et non `{{110.CTX}}`), et cette forme est **identique dans le blueprint
d'avant le 13/08, dans le scénario principal 6183820 et dans la copie d'aujourd'hui**. Les
modules 110 et 215 déclarent bien `name: CTX` / `name: SAGES`, `scope: roundtrip`, et tous deux
s'exécutent (opérations 13 et 25) avant les Archimages (27, 29, 31).

Un `CTX=` totalement vide n'est pas un CTX dont les valeurs seraient vides : dans ce cas on
verrait les libellés (`DATE=|VIX=|FED=…`). C'est la variable elle-même qui n'arrive pas.
À confirmer au prochain run en regardant aussi le panneau INPUT du module **301** : si JU
affiche lui aussi `CTX=` vide, le problème est systémique et ancien.

## Correctif appliqué et vérifié — 27/08 15:09

Module 305 : **6401 caractères** (6409 avant). Plus aucune expression `{{...}}` ne contient
d'antislash, ni dans le 305, ni dans le 301, ni dans le 303. `mistral-large-latest`,
`max_tokens 8000`, prompt système et bloc AUTOCRITIQUE intacts. Diff des 80 modules entre les
deux enregistrements : **un seul module modifié, le 305**.

**2. La clé `erreur` n'existe pas.** Les éléments de `mistakes_history` portent les clés
`at, consec_losses, dd, eval, phase, pnl, pnl_delta, run`. `map(…; "erreur")` renvoie donc du
vide depuis toujours : **aucun des trois Archimages n'a jamais reçu son propre historique
d'erreurs**, alors que la base en stocke 30 par archimage. Corriger revient à écrire `"eval"` —
mais cela change ce que les agents reçoivent, donc ce qu'ils décident. C'est un arbitrage de
Chachou, pas un correctif de plantage.
