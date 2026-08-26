# Ce qu'il reste à faire faire à Maia — 26/08/2026

Tout ce qui pouvait être fait dans Supabase l'a été et est vérifié (voir
`supabase/schema/18_adn_mesure_pas_conclusion_2026-08-26.sql`). Il reste **quatre chantiers dans
Make**, dans cet ordre d'importance. Chaque remplacement a été vérifié sur le blueprint en direct :
la chaîne cherchée existe **exactement une fois** dans le module indiqué.

**Deux règles avant de commencer**, apprises cette semaine à mes dépens :

1. **Le nombre d'accolades ouvertes doit rester égal au nombre de fermantes.** Le 26/08 le scénario
   s'est arrêté à 20 opérations parce qu'un correctif avait mangé une accolade. Après chaque
   modification d'un corps JSON, recompter.
2. **Copier les chaînes telles quelles**, avec les `\"` échappés quand il y en a. Ces textes vivent
   à l'intérieur d'un corps JSON.

---

## Chantier 1 — Rendre aux agents leur autonomie (les blocs AUTOCRITIQUE)

C'est le plus important : ces blocs ne demandent pas à l'agent de se corriger, **ils lui dictent la
correction**. Trois textes seulement, à appliquer sur **dix modules**.

### 1A — sept modules : 201, 203, 205, 207, 209, 303, 305

Chercher (identique dans les sept, une occurrence par module) :

```
AUTOCRITIQUE OBLIGATOIRE. COACHING est TON resultat mesure, pas une opinion : il donne ton taux de reussite sur tes propres verdicts passes. Si ton score est FAIBLE, baisse ta conviction et resserre tes fourchettes ; s'il est FIABLE, garde ta ligne. Tu dois en tenir compte dans tes valeurs chiffrees, sans ajouter aucun champ ni aucun texte hors du schema JSON impose.
```

Remplacer par :

```
AUTOCRITIQUE OBLIGATOIRE. COACHING est TON resultat mesure, pas une opinion : il donne ton taux de reussite et le nombre de verdicts sur lesquels il est calcule. Tu dois en tenir compte dans tes valeurs chiffrees, sans ajouter aucun champ ni aucun texte hors du schema JSON impose. Ce que ce chiffre implique, c'est a toi de le decider.
```

### 1B — deux modules : 301 (JU) et 20015 (Marées)

Chercher :

```
AUTOCRITIQUE OBLIGATOIRE. CIRCUIT_BREAKERS et COACHING sont TES resultats mesures, pas une opinion. Si un motif te concerne tu DOIS en tenir compte explicitement et le dire dans ton champ de justification. repetition_identique_perdante : tu repetes le meme geste en perdant, change de these ou ne fais rien, ne repete pas. pertes_consecutives_5 : reduis les tailles et coupe les positions perdantes. drawdown_5pct ou drawdown_8pct : protection du capital prioritaire. win_rate_faible : ton probleme est la SELECTION et pas la frequence, moins de decisions et plus de conviction. Si AUCUN motif ne te concerne, n'invente pas de prudence artificielle et garde ta ligne.
```

Remplacer par :

```
AUTOCRITIQUE OBLIGATOIRE. CIRCUIT_BREAKERS et COACHING sont TES resultats mesures, pas une opinion. Chaque coupe-circuit te donne un motif, la valeur mesuree et le seuil franchi. Si un motif te concerne tu DOIS en tenir compte explicitement et dire dans ton champ de justification ce que tu en conclus et ce que tu changes. La conclusion est la tienne : aucun texte ne te dicte la correction.
```

### 1C — un module : 10012 (l'Alchimiste, argent réel)

Même chose, mais le texte commence différemment. Chercher :

```
AUTOCRITIQUE OBLIGATOIRE. CIRCUIT_BREAKERS sont TES resultats mesures, pas une opinion. Si un motif te concerne tu DOIS en tenir compte explicitement et le dire dans ton champ de justification. repetition_identique_perdante : tu repetes le meme geste en perdant, change de these ou ne fais rien, ne repete pas. pertes_consecutives_5 : reduis les tailles et coupe les positions perdantes. drawdown_5pct ou drawdown_8pct : protection du capital prioritaire. win_rate_faible : ton probleme est la SELECTION et pas la frequence, moins de decisions et plus de conviction. Si AUCUN motif ne te concerne, n'invente pas de prudence artificielle et garde ta ligne.
```

Remplacer par :

```
AUTOCRITIQUE OBLIGATOIRE. CIRCUIT_BREAKERS sont TES resultats mesures, pas une opinion. Chaque coupe-circuit te donne un motif, la valeur mesuree et le seuil franchi. Si un motif te concerne tu DOIS en tenir compte explicitement et dire dans ton champ de justification ce que tu en conclus et ce que tu changes. La conclusion est la tienne : aucun texte ne te dicte la correction.
```

**Ce qui est conservé** : l'obligation d'autocritique, le fait que ces chiffres sont des mesures et
pas des opinions, et l'obligation de dire dans la justification comment on en tient compte.
**Ce qui disparaît** : les quatre corrections dictées motif par motif, et « baisse ta conviction /
garde ta ligne ».

---

## Chantier 2 — Le dé-staking : rendre au verdict la clé qu'on ne lui a jamais demandée

Le module Discord **10031** affiche `verdict`, `raison` et `gain_trade_attendu_pct`, et
`alc_record_propositions` les enregistre — mais **le prompt du 10012 ne nomme aucune des trois**.
Depuis le 25/08 le modèle ne les produit plus : les colonnes sont NULL et la proposition de
dé-staking a disparu du message.

**Module 10012**, chercher (une occurrence) :

```
{\"propositions\":[],\"destake_recommande\":[],\"commentaire\":\"<synthèse courte du cycle>\"}
```

Remplacer par :

```
{\"propositions\":[],\"destake_recommande\":[{\"devise\":\"TON\",\"montant_usd\":7.91,\"apy_staking_pct\":17.67,\"delai_deblocage_jours\":2,\"gain_trade_attendu_pct\":0,\"verdict\":\"GARDER\",\"raison\":\"une phrase courte sans guillemets\"}],\"commentaire\":\"<synthèse courte du cycle>\"}\n\nChaque element de destake_recommande DOIT porter les sept cles ci-dessus. verdict vaut exactement GARDER ou DESTAKER, jamais autre chose. gain_trade_attendu_pct est le gain net que tu attends du trade que ce capital permettrait, en pourcentage. raison explique en une phrase pourquoi tu gardes ou tu destakes.
```

Vérifié par simulation sur le corps réel : corps 6 886 → 7 395 caractères, **3 accolades ouvertes
et 3 fermées**, corps toujours valide (`model` = `sonar-pro`, 2 messages).

*Note : c'est bien l'Alchimiste qui décide GARDER ou DESTAKER. On lui demande le nom des cases à
remplir, pas ce qu'il doit y mettre.*

---

## Chantier 3 — Le Sage Flash produit enfin ses catalyseurs

`oracle_flash_intel` est vide depuis sa création. Le 404 côté Supabase est corrigé, mais le module
**211** lit trois champs que le schéma strict du **209** ne contient pas. Conséquence : **GIL reçoit
un bloc de renseignement vide à chaque run**.

**Module 209**, dans `"schema": { "properties": { … } }`, ajouter :

```
"web_intelligence": {"type": "string"},
"catalysts": {"type": "array", "items": {"type": "object", "properties": {
  "ticker": {"type": "string"}, "type": {"type": "string"}, "headline": {"type": "string"}},
  "required": ["ticker", "type", "headline"], "additionalProperties": false}}
```

et ajouter `"web_intelligence"` et `"catalysts"` à la liste `"required"`.

**Module 211**, chercher :
```
"top_ticker": "{{trim(upper(ifempty(210.trade_1.ticker; MARKET)))}}", "top_direction": "{{lower(ifempty(210.trade_1.side; neutral))}}"
```
remplacer par :
```
"top_ticker": "{{trim(upper(ifempty(210.catalysts[1].ticker; MARKET)))}}", "top_direction": "{{lower(ifempty(210.flash_sentiment; neutral))}}"
```

---

## Chantier 4 — Que les pannes ne repassent plus en silence

Les cinq Sages (**201, 203, 205, 207, 209**) ont `stopOnHttpError = false` et **aucun `onerror`**.
C'est ce qui a laissé le Sage Mémoire mourir du 21/08 au 25/08 sans le moindre signal.

Sur ces cinq modules : cocher **« Evaluate all states as errors »** et ajouter une **route d'erreur
`Resume`** renvoyant `{}`. Le scénario continue, mais l'échec apparaît dans l'historique.

---

## Et sur le scénario principal 6183820

Il n'a **jamais reçu** les correctifs du 25 et du 26. Il s'arrête toujours à 29 opérations sur 80,
au module 303. Quand tu voudras le remettre en service, il faut y appliquer, dans l'ordre :

1. Les deux remplacements du module **303** et les deux du **305** (document
   `PROMPT-MAIA-RELANCE-SCENARIO-2026-08-25.md`, §1).
2. Le `thinkingConfig` du module **207** — **avec ses trois accolades fermantes** (§2, erratum).
3. Les quatre chantiers ci-dessus.

Rappel : c'est bien le **6183820** que Supabase déclenche (`scenario_fire` → `scenario_runs_planifies`,
4 créneaux lun–ven), et l'interrupteur maître `scenario_control.actif` est sur **false** depuis le
23/08 à 00:04.
