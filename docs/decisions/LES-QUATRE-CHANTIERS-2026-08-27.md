# Les quatre chantiers ouverts par le run vert — 27/08/2026

## Chantiers 1 et 4 : une seule et même cause

Le run du 27/08 15:36 a porté **trois identifiants différents** — `20260827-1736` pour les
catalyseurs, `1737` pour les Sages, `1738` pour le collège — et le module 305 recevait
`CTX=|SAGES=|`, c'est-à-dire rien.

C'est le même défaut : **une variable Make ne se lit pas par son nom.**

| Forme | Modules | Résultat |
|---|---|---|
| `{{101.value}}` | 10003, 10004, 10005, 10023, 20013, 20018 | **fonctionne** |
| `{{101.RUN_ID}}` | 211, 10032, 401, 960, 981, 982 | vide → chacun retombe sur sa propre horloge |
| `{{CTX}}` / `{{SAGES}}` | 301, 303, 305 | vide → les Archimages décident aveugles |

La preuve est en base, et elle est sans appel :

| Table | Écrite par un module qui lit… | Lignes avec le préfixe `COLLEGE-` |
|---|---|---|
| `alc_destake_reco` | `101.value` | **203 / 203** |
| `marees_propositions` | `101.value` | **117 / 117** |
| `oracle_college_runs` | `101.RUN_ID` | **0 / 278** |
| `oracle_sages_report` | `101.RUN_ID` | **0 / 1002** |
| `oracle_flash_intel` | `101.RUN_ID` | **0 / 9** |

Les modules qui lisent `101.value` reçoivent bien `COLLEGE-…`. Les autres n'ont jamais rien reçu.

**Ce n'est pas une régression de mon fait** : la forme `{{CTX}}` est identique dans le blueprint
d'avant le 13/08 et dans le scénario principal 6183820. Les trois Archimages ont toujours
travaillé sans contexte de marché et sans la synthèse des cinq Sages. C'est, de loin, le plus
gros de ce qu'on a trouvé.

Correctifs : `docs/maia/M-301-303-305-variables-ctx-sages.txt` puis
`docs/maia/N-run-id-unique.txt`.

Vérifié : aucune fonction ni vue Supabase ne joint ces tables sur une égalité de `run_id`, et
aucune n'analyse le préfixe `COLLEGE-` autrement que comme valeur de repli. Aligner les
identifiants ne casse rien et ne peut que réparer.

## Chantier 2 : `syl_top_catalyst_ticker` disait `GLD` depuis toujours

Le module 982 envoie `syl_top_catalyst` = `{{304.trade_1.ticker}}` — **le premier trade de
l'Archimage SYL**, pas un catalyseur. SYL trade GLD à chaque run, d'où la constante sur
278 runs. Et `syl_catalyst_direction` n'était écrite par personne : NULL partout.

**Fait côté Supabase, testé** : `batch_write_college_run_v2` enregistre désormais
`syl_catalyst_direction`. La fonction a été modifiée par remplacement de chaîne sur sa propre
définition (7542 caractères) plutôt que retapée, avec un garde-fou qui refuse d'agir si l'ancrage
n'est pas trouvé une fois et une seule. Testé avec un run factice : les trois colonnes
s'écrivent, ligne de test supprimée.

Reste côté Make : `docs/maia/O-982-vrai-catalyseur.txt` — pointer `syl_top_catalyst` sur
`210.top_catalyst_ticker` et ajouter `syl_catalyst_direction` depuis `210.flash_sentiment`,
les deux champs que le Sage Flash produit depuis ce matin.

## Chantier 3 : les propositions de l'Alchimiste, même défaut que le dé-staking

Le FORMAT DE SORTIE du module 10012 montre `\"propositions\":[]` — **un tableau vide, sans une
seule clé décrite.** Le mot `confidence` n'apparaît pas une seule fois dans les 7120 caractères
du prompt. `alc_record_propositions` attend pourtant `paire`, `side`, `montant`, `confidence` et
`raison` (ou leurs synonymes `crypto`, `sens`, `montant_usd`, `gain_net_estime_pct`,
`raison_courte`).

Le modèle inventait donc ses propres noms. Conséquence, lisible en base :

| Date | Lignes écrites | Contenu |
|---|---|---|
| 21/08 | 1 | `LINK-USD buy 2.47 conf 0.58` — complète |
| 25/08 | 1 | `paire`, `side`, `montant`, `confidence`, `raison` **tous NULL** |
| 26/08 | 5 | **tous NULL** |
| 27/08 | 0 | aucune proposition |

C'est exactement le défaut que j'ai corrigé le 26/08 sur `destake_recommande` — dans le même
module, sur l'autre tableau. **J'ai réparé une moitié et laissé l'autre.**

Correctif : `docs/maia/P-10012-cles-des-propositions.txt`.

## Ordre d'application

1. **M** — les trois Archimages retrouvent leur contexte (301 → 6777, 303 → 6580, 305 → 6411)
2. **N** — un seul identifiant par run (211 → 411, 10032 → 409, 401 → 4795, 960 → 1422,
   981 → 3596, 982 → 1699)
3. **O** — le vrai catalyseur (982 → 1815, **après N**)
4. **P** — les clés des propositions (10012 → 7593)

Puis un run de contrôle : 76 opérations, un seul `run_id` dans les cinq tables, `CTX=` non vide
dans le panneau INPUT du module 301, et `alchimiste_crypte_propositions` de nouveau renseignée.
