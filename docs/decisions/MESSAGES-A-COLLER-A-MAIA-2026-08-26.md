# Messages à coller à Maia — 26/08/2026

**À envoyer un par un, dans l'ordre. Après chaque envoi, lance un run sur 7051944 et vérifie qu'il
fait bien 76 opérations avant de passer au suivant.** Si un run s'arrête plus tôt, ne continue pas :
dis-le-moi, je regarde les logs.

Tout se fait sur le scénario **7051944 (la copie)**. Le 6183820 ne doit pas être touché.

---

## Envoi 1 — rendre aux agents leur autonomie

> Bonjour Maia. Travaille **uniquement sur le scénario 7051944**, ne touche pas au 6183820.
>
> Règles impératives pour cette intervention :
> - Tu fais **uniquement des remplacements de texte**. Tu ne supprimes aucun module, aucun champ,
>   aucune variable, aucune connexion. Tu n'ajoutes rien d'autre que ce qui est demandé.
> - Les textes ci-dessous vivent **à l'intérieur du corps JSON** des modules. Recopie-les
>   exactement, caractère pour caractère, y compris les apostrophes.
> - **Après chaque modification, vérifie que le nombre d'accolades ouvertes `{` est égal au nombre
>   d'accolades fermantes `}` dans le corps du module.** Une modification précédente en avait mangé
>   une et le scénario s'est arrêté.
>
> **A) Dans les SEPT modules 201, 203, 205, 207, 209, 303 et 305**, chercher ce texte (il est
> identique dans les sept, une seule occurrence par module) :
>
> ```
> AUTOCRITIQUE OBLIGATOIRE. COACHING est TON resultat mesure, pas une opinion : il donne ton taux de reussite sur tes propres verdicts passes. Si ton score est FAIBLE, baisse ta conviction et resserre tes fourchettes ; s'il est FIABLE, garde ta ligne. Tu dois en tenir compte dans tes valeurs chiffrees, sans ajouter aucun champ ni aucun texte hors du schema JSON impose.
> ```
>
> et le remplacer par :
>
> ```
> AUTOCRITIQUE OBLIGATOIRE. COACHING est TON resultat mesure, pas une opinion : il donne ton taux de reussite et le nombre de verdicts sur lesquels il est calcule. Tu dois en tenir compte dans tes valeurs chiffrees, sans ajouter aucun champ ni aucun texte hors du schema JSON impose. Ce que ce chiffre implique, c'est a toi de le decider.
> ```
>
> **B) Dans les DEUX modules 301 et 20015**, chercher :
>
> ```
> AUTOCRITIQUE OBLIGATOIRE. CIRCUIT_BREAKERS et COACHING sont TES resultats mesures, pas une opinion. Si un motif te concerne tu DOIS en tenir compte explicitement et le dire dans ton champ de justification. repetition_identique_perdante : tu repetes le meme geste en perdant, change de these ou ne fais rien, ne repete pas. pertes_consecutives_5 : reduis les tailles et coupe les positions perdantes. drawdown_5pct ou drawdown_8pct : protection du capital prioritaire. win_rate_faible : ton probleme est la SELECTION et pas la frequence, moins de decisions et plus de conviction. Si AUCUN motif ne te concerne, n'invente pas de prudence artificielle et garde ta ligne.
> ```
>
> et le remplacer par :
>
> ```
> AUTOCRITIQUE OBLIGATOIRE. CIRCUIT_BREAKERS et COACHING sont TES resultats mesures, pas une opinion. Chaque coupe-circuit te donne un motif, la valeur mesuree et le seuil franchi. Si un motif te concerne tu DOIS en tenir compte explicitement et dire dans ton champ de justification ce que tu en conclus et ce que tu changes. La conclusion est la tienne : aucun texte ne te dicte la correction.
> ```
>
> **C) Dans le module 10012 uniquement**, chercher (attention, le début diffère : pas de
> « et COACHING ») :
>
> ```
> AUTOCRITIQUE OBLIGATOIRE. CIRCUIT_BREAKERS sont TES resultats mesures, pas une opinion. Si un motif te concerne tu DOIS en tenir compte explicitement et le dire dans ton champ de justification. repetition_identique_perdante : tu repetes le meme geste en perdant, change de these ou ne fais rien, ne repete pas. pertes_consecutives_5 : reduis les tailles et coupe les positions perdantes. drawdown_5pct ou drawdown_8pct : protection du capital prioritaire. win_rate_faible : ton probleme est la SELECTION et pas la frequence, moins de decisions et plus de conviction. Si AUCUN motif ne te concerne, n'invente pas de prudence artificielle et garde ta ligne.
> ```
>
> et le remplacer par :
>
> ```
> AUTOCRITIQUE OBLIGATOIRE. CIRCUIT_BREAKERS sont TES resultats mesures, pas une opinion. Chaque coupe-circuit te donne un motif, la valeur mesuree et le seuil franchi. Si un motif te concerne tu DOIS en tenir compte explicitement et dire dans ton champ de justification ce que tu en conclus et ce que tu changes. La conclusion est la tienne : aucun texte ne te dicte la correction.
> ```
>
> Confirme-moi le nombre de modules modifiés : il doit être de 10.

---

## Envoi 2 — le dé-staking retrouve son verdict

> Toujours sur le scénario **7051944** uniquement. Mêmes règles : remplacement de texte seulement,
> rien de supprimé, et tu recomptes les accolades après.
>
> Dans le corps du module **10012**, chercher (une seule occurrence) :
>
> ```
> {\"propositions\":[],\"destake_recommande\":[],\"commentaire\":\"<synthèse courte du cycle>\"}
> ```
>
> et le remplacer par :
>
> ```
> {\"propositions\":[],\"destake_recommande\":[{\"devise\":\"TON\",\"montant_usd\":7.91,\"apy_staking_pct\":17.67,\"delai_deblocage_jours\":2,\"gain_trade_attendu_pct\":0,\"verdict\":\"GARDER\",\"raison\":\"une phrase courte sans guillemets\"}],\"commentaire\":\"<synthèse courte du cycle>\"}\n\nChaque element de destake_recommande DOIT porter les sept cles ci-dessus. verdict vaut exactement GARDER ou DESTAKER, jamais autre chose. gain_trade_attendu_pct est le gain net que tu attends du trade que ce capital permettrait, en pourcentage. raison explique en une phrase pourquoi tu gardes ou tu destakes.
> ```
>
> Ne change rien d'autre dans ce module : ni l'URL, ni le modèle sonar-pro, ni max_tokens 8000, ni
> les règles de staking déjà présentes.
>
> Le corps doit passer de 6 886 à 7 395 caractères, avec 3 accolades ouvertes et 3 fermées.

---

## Envoi 3 — le Sage Flash produit enfin ses catalyseurs

> Toujours sur **7051944**. Deux modules à modifier, rien à supprimer.
>
> **Module 209** : dans `response_format` → `json_schema` → `schema` → `properties`, **ajouter** ces
> deux propriétés aux huit qui existent déjà (ne supprime aucune des huit) :
>
> ```
> "web_intelligence": {"type": "string"},
> "catalysts": {"type": "array", "items": {"type": "object", "properties": {"ticker": {"type": "string"}, "type": {"type": "string"}, "headline": {"type": "string"}}, "required": ["ticker", "type", "headline"], "additionalProperties": false}}
> ```
>
> et **ajouter** `"web_intelligence"` et `"catalysts"` à la liste `"required"` du même schéma, sans
> retirer les entrées existantes.
>
> **Module 211** : chercher
>
> ```
> "top_ticker": "{{trim(upper(ifempty(210.trade_1.ticker; MARKET)))}}", "top_direction": "{{lower(ifempty(210.trade_1.side; neutral))}}"
> ```
>
> et remplacer par
>
> ```
> "top_ticker": "{{trim(upper(ifempty(210.catalysts[1].ticker; MARKET)))}}", "top_direction": "{{lower(ifempty(210.flash_sentiment; neutral))}}"
> ```

---

## Envoi 4 — que les pannes ne repassent plus en silence

> Toujours sur **7051944**. Sur les cinq modules **201, 203, 205, 207 et 209** :
>
> - activer l'option **« Evaluate all states as errors »** (elle est aujourd'hui désactivée sur les
>   cinq) ;
> - ajouter à chacun une **route d'erreur (error handler) de type `Resume`** qui renvoie un objet
>   JSON vide `{}`.
>
> Objectif : quand un de ces modèles répond une erreur HTTP, le scénario continue son cours mais
> l'échec apparaît dans l'historique d'exécution. Aujourd'hui l'erreur passe totalement inaperçue —
> c'est ce qui a laissé le Sage Mémoire mort pendant cinq jours sans aucun signal.
>
> Ne modifie ni les prompts, ni les URL, ni les clés de ces modules.

---

## Ce que je vérifie après chaque envoi

| Envoi | Contrôle |
|---|---|
| 1 | run à 76 opérations ; `COACHING` dans les prompts ne contient plus de verbe d'ordre |
| 2 | `alc_destake_reco.verdict` repasse à `GARDER`/`DESTAKER` au lieu de NULL, et la proposition de dé-staking revient dans le message Discord |
| 3 | `oracle_flash_intel` reçoit enfin des lignes, et `get_oracle_context().flash_intel_latest` n'est plus vide |
| 4 | une panne LLM apparaît en erreur dans l'historique au lieu de passer en silence |
