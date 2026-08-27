# Le crash de GIL — module 305 — 27/08/2026

Run manuel du 27/08 à **13:09:42** sur le scénario 7051944 : arrêt à **31 opérations** sur
`InvalidConfigurationError — The provided JSON body content is not valid JSON`, module de type
`http:MakeRequest`.

## Où, exactement

Le scénario compte 79 modules facturables, moins les 3 modules Binance `[OFF]` = 76 opérations
pour un run complet (c'est bien ce qu'ont consommé les runs verts du 25 et du 26). En comptant
dans l'ordre d'exécution, **l'opération 31 est le module 305 — ⚖️ L'ARBITRE DORÉ — GIL**.
Chachou avait raison sans avoir besoin de compter.

## Ce que le corps du module dit

Le corps enregistré du module 305 **est du JSON valide** : il passe `JSON.parse` tel quel, et il
le passe encore après neutralisation des `{{...}}`. 18 accolades ouvrantes, 18 fermantes. Ce
n'est donc pas le texte qui est cassé — c'est **une valeur injectée à l'exécution** qui le casse,
exactement comme le plantage de SYL le 13/08 (`Bad escaped character in JSON at position 5612`).

## Les quatre trous

Sur les 17 expressions du module 305, quatre injectent du texte libre sans le nettoyer :

| Position | Expression | Protection |
|---|---|---|
| 5773 | `toString(105.data.flash_intel_latest)` | guillemets + sauts de ligne — **pas les antislashs** |
| 5892 | `toString(105.data.active_circuit_breakers)` | guillemets + sauts de ligne — **pas les antislashs** |
| 6251 | `join(map(…GIL.mistakes_history; "erreur"); " ## ")` | **aucune** |
| 6345 | `toString(…GIL.latest_web_catalysts)` | **aucune** |

À comparer avec ce que le même module fait déjà pour `GIL_BIAS` et `GIL_LEARNINGS` :
`replace(… ; backslash ; …)` puis `quote`, puis `newline`, puis `carriagereturn`. Le blindage
existe dans le fichier ; il n'a simplement jamais été appliqué à ces quatre-là.

## Ce qui est certain pour le prochain run

`105.data.brain_states.GIL.latest_web_catalysts` est injecté **sans aucune protection**, et
depuis aujourd'hui 13:10:33 il contient **578 caractères de JSON bourrés de guillemets** — les
catalyseurs que la chaîne Flash réparée ce matin vient enfin d'écrire. Avant aujourd'hui ce
champ était toujours vide : le trou existait mais rien ne tombait dedans.

**Au prochain run, cette valeur casse le module 305 avec certitude.** Le même trou existe dans
le module 303 pour SYL (position 6506, 379 caractères aujourd'hui) et, en partie, dans le 301
pour JU.

## Ce que je n'ai pas pu établir

Au moment où le module 105 a lu le contexte (opération 6, vers 13:09:50), `latest_web_catalysts`
et `flash_intel_latest` étaient **encore vides** — la chaîne Flash n'écrit qu'à l'opération 24.
Je ne peux donc pas affirmer que c'est ce champ-là qui a cassé le run de 13:09. J'ai éliminé :

- `{{CTX}}` et `{{SAGES}}` : identiques pour les trois Archimages, et les modules 301 (op 27) et
  303 (op 29) sont passés sans erreur juste avant. Le poison est donc propre à GIL ou à l'une
  des expressions que seul le 305 porte.
- `mistakes_history` : les éléments portent les clés `at, consec_losses, dd, eval, phase, pnl,
  pnl_delta, run`. **La clé `erreur` n'existe pas** — `map(…; "erreur")` a toujours renvoyé du
  vide. (Voir « À décider » plus bas.)
- `recent_exec_errors`, seul champ du contexte qui contient un antislash
  (`asset \"USO\" cannot be sold short`, écrit par le run du 26/08) : **aucun module du blueprint
  ne le lit**. Ni CTX, ni SAGES, ni les corps des dix modules d'agents.

L'API Make ne donne pas les entrées/sorties par module (`executions_get-detail` ne renvoie que
le statut et l'erreur). Pour nommer le caractère exact du run de 13:09, il faut ouvrir
l'historique d'exécution dans Make, cliquer sur le module 305 et copier le champ **Body** du
panneau INPUT.

## Le correctif

`docs/maia/I-305-GIL-blindage-json.txt` (6409 → **6863**), puis
`docs/maia/J-303-SYL-blindage-json.txt` (6570 → **6943**), puis
`docs/maia/K-301-JU-blindage-json.txt` (6767 → **6918**).

Il n'invente rien : il applique aux quatre expressions nues le blindage déjà présent sur
`GIL_BIAS` et `GIL_LEARNINGS` dans le même module. Vérifié hors ligne : après les quatre
remplacements, le corps du 305 passe toujours `JSON.parse`.

## À décider — la clé `erreur` qui n'existe pas

Les trois Archimages reçoivent `MISTAKES={{join(map(…mistakes_history; "erreur"); " ## ")}}`.
Les éléments de `mistakes_history` portent une clé **`eval`**, pas `erreur`. Le champ part donc
vide depuis toujours : **aucun des trois Archimages n'a jamais reçu son propre historique
d'erreurs**, alors que la base le stocke (30 entrées par archimage, ~8 000 caractères).

C'est une chaîne livrée à moitié, comme le `verdict` du dé-staking. Corriger revient à changer
`"erreur"` en `"eval"` — mais cela change ce que les agents reçoivent, donc ce qu'ils décident.
Ce n'est pas un correctif de plantage : c'est une décision de Chachou, à prendre séparément et
après un run vert.
