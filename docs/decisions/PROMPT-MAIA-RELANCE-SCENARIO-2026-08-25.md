# Relancer le scénario 6183820 — instructions Maia, 25/08/2026

> Vérifié sur le blueprint **en direct** des deux scénarios, le 25/08 vers 15 h.
> Rien ici n'est supposé : chaque chaîne ci-dessous a été extraite du blueprint, et le résultat
> après remplacement a été comparé octet par octet à la copie 7051944 qui a tourné avec succès
> aujourd'hui (statut 1, 76 opérations).

---

## 0. Ce que dit la comparaison avec le blueprint d'avant le 13/08

Blueprint fourni par Chachou (avant le 13/08) contre celui de Make aujourd'hui : **78 modules
avant, 80 aujourd'hui**. Aucun module supprimé. Deux ajoutés (20022 ⛓️ LES CHAÎNES DU SCELLÉ,
20023 🌾 LA RENTE DES SCELLÉS) et **quatre Sages changés de moteur** :

| Module | Avant le 13/08 | Aujourd'hui | Verdict |
|---|---|---|---|
| 201 AURORA BOREALIS | Groq `llama-3.3-70b-versatile` | Groq `openai/gpt-oss-120b` | sain — modèle Groq décommissionné le 17/06, remplacement légitime |
| 203 STELLAR NAVIGATOR | Groq `llama-3.3-70b-versatile` | Groq `openai/gpt-oss-120b` | sain |
| 205 IRON SENTINEL | Groq `llama-3.3-70b-versatile` | **Mistral** `mistral-large-latest` | fonctionne, mais changement non justifié |
| 207 DEEP MEMORY | **Groq** `llama-3.3-70b-versatile` | **Gemini** `gemini-3.5-flash` | **mort** — la clé renvoie `API_KEY_INVALID` |

Chachou avait raison sur les trois points : le Sage Mémoire tournait sur Groq, ce n'est pas lui
qui l'a déplacé, et il est mort le 21/08 à 15:20 (dernière ligne dans `oracle_sages_report`).

---

## 1. LE BLOCAGE PRINCIPAL — module 303, et lui seul

Le scénario 6183820 s'arrête à **29 opérations sur 80**. Le module n° 29 dans l'ordre
d'exécution est le **303 🌙 LE PROPHÈTE D'ARGENT — SYL**.
Erreur : `InvalidConfigurationError — The provided JSON body content is not valid JSON`.

**Conséquence : tout ce qui vient après le 303 n'a jamais tourné depuis le 21/08 09:19** —
GIL (305), les ordres Alpaca (500/520/540), l'Alchimiste (10009→10031), **les Marées
(20014→20021)** et les hérauts Discord. Les Marées ne sont pas en panne : le scénario ne les
atteint jamais.

### Module 303 — champ `jsonStringBodyContent`

**Remplacement 1** (une seule occurrence dans le module) :

- chercher exactement :
```
\ + "bias\"); \ + " ## \"));
```
- remplacer par exactement :
```
"bias"); " ## "));
```

**Remplacement 2** (une seule occurrence dans le module) :

- chercher exactement :
```
\ + "erreur\"); \ + " ## \")}}{{\}} ## \
```
- remplacer par exactement :
```
"erreur"); " ## ")}}
```

Après ces deux remplacements le corps du 303 est **identique octet pour octet** à celui de
7051944, qui a tourné sans erreur aujourd'hui à 14:35.

### Module 305 ⚖️ L'ARBITRE DORÉ — GIL — même champ, même défaut

**Remplacement 1** (une seule occurrence dans le module) :

- chercher exactement :
```
\"bias\"); \" ## \"));
```
- remplacer par exactement :
```
"bias"); " ## "));
```

**Remplacement 2** (une seule occurrence dans le module) :

- chercher exactement :
```
\"erreur\"); \" ## \")}}
```
- remplacer par exactement :
```
"erreur"); " ## ")}}
```

---

## 2. Module 207 📚 DEEP MEMORY — le remettre sur Groq

Trois changements dans le module, rien d'autre.

**a) URL** — remplacer
`https://generativelanguage.googleapis.com/v1beta/models/gemini-3.5-flash:generateContent`
par `https://api.groq.com/openai/v1/chat/completions`

**b) En-tête** — supprimer l'en-tête `x-goog-api-key` et le remplacer par un en-tête
`Authorization` dont la valeur est **exactement celle de l'en-tête `Authorization` du module
201 🌌 AURORA BOREALIS** (copier-coller depuis le 201 ; cette clé Groq fonctionne, 201 et 203
répondent tous les jours). Garder `Content-Type: application/json`.

**c) Corps** — remplacer intégralement `jsonStringBodyContent` par :

```
{"model": "openai/gpt-oss-120b", "temperature": 0.01, "reasoning_effort": "low", "max_tokens": 2000, "response_format": {"type": "json_object"}, "messages": [{"role": "system", "content": "Tu es DEEP MEMORY analyste institutionnel de performance et expert en finance comportementale. Tu etudies les taux de reussite, les sequences de gains et pertes, les derives de comportement, les patterns gagnants et defaillants. IMPORTANT : tu ne dois jamais conserver un point de vue fixe. A chaque execution, tu dois changer d angle d analyse, puis remettre en cause ta premiere lecture. AUTO-CHALLENGE : Est-ce que j observe un vrai pattern ou un biais de confirmation sur peu de donnees ? Quel archimage est en train de sur-adapter ? Quelle correction recommandee risque d etre contre-productive ? Schema : {\"ju_win_rate\":0,\"syl_win_rate\":0,\"gil_win_rate\":0,\"alc_win_rate\":0,\"marees_win_rate\":0,\"best_archimage\":\"JU|SYL|GIL|EQUAL\",\"best_agent\":\"JU|SYL|GIL|ALCHIMISTE|MAREES|EQUAL\",\"failed_pattern\":\"max 100 chars no quotes\",\"winning_pattern\":\"max 100 chars no quotes\",\"correction_directive\":\"max 120 chars no quotes\",\"correction_cible\":\"JU|SYL|GIL|ALCHIMISTE|MAREES|COLLEGE\"} Regles d analyse, appliquees a CHAQUE agent et pas seulement a JU : au-dessus de 55 pour cent de win rate egal excellent ; en dessous de 45 pour cent egal correction obligatoire ; win rate egal wins divise par wins plus losses multiplie par 100. DETECTION OVER-TRADING : pour chaque agent, si RUNS superieur a 10 et win rate inferieur a 40 pour cent alors le probleme est la SELECTION et pas la frequence, recommande de reduire a 5 a 10 decisions de haute conviction. CIBLAGE : correction_cible doit designer l agent dont le win rate est le plus faible parmi ceux qui ont au moins 10 runs ; si tous sont au-dessus de 50 pour cent mets COLLEGE. VOLUME INSUFFISANT : si un agent a moins de 10 runs, mets son win rate mais ne fonde aucune correction sur lui. alc_win_rate et marees_win_rate entiers 0 a 100. CONTRAINTES : JSON valide uniquement. Pas de saut de ligne. Pas de guillemets internes. ANALYSE CORRELATION : les actifs du meme secteur comptent comme une seule position pour le risque, par exemple NVDA plus AMD plus SOXL egal exposition SEMI. REMISE EN QUESTION : indique ton degre de certitude et ce qui invaliderait ton signal ; pas d avis tranche si les donnees sont faibles. LANGUE : les valeurs des champs texte doivent etre redigees en francais clair. Ne change rien au format JSON, ni aux cles, ni aux tickers. Ne renvoie AUCUN texte en dehors de l objet JSON. AUTOCRITIQUE OBLIGATOIRE. COACHING est TON resultat mesure, pas une opinion : il donne ton taux de reussite sur tes propres verdicts passes. Si ton score est FAIBLE, baisse ta conviction et resserre tes fourchettes ; s'il est FIABLE, garde ta ligne. Tu dois en tenir compte dans tes valeurs chiffrees, sans ajouter aucun champ ni aucun texte hors du schema JSON impose."}, {"role": "user", "content": "JU_W={{ifempty(105.data.brain_states.JU.wins; 0)}} JU_L={{ifempty(105.data.brain_states.JU.losses; 0)}} JU_RUNS={{ifempty(105.data.brain_states.JU.total_runs; 0)}} JU_PNL={{ifempty(105.data.brain_states.JU.cumulative_pnl; 0)}} JU_BIAS={{replace(replace(ifempty(105.data.brain_states.JU.current_bias; neutral); newline; ); quote; )}} SYL_W={{ifempty(105.data.brain_states.SYL.wins; 0)}} SYL_L={{ifempty(105.data.brain_states.SYL.losses; 0)}} SYL_RUNS={{ifempty(105.data.brain_states.SYL.total_runs; 0)}} SYL_PNL={{ifempty(105.data.brain_states.SYL.cumulative_pnl; 0)}} SYL_BIAS={{replace(replace(ifempty(105.data.brain_states.SYL.current_bias; neutral); newline; ); quote; )}} GIL_W={{ifempty(105.data.brain_states.GIL.wins; 0)}} GIL_L={{ifempty(105.data.brain_states.GIL.losses; 0)}} GIL_RUNS={{ifempty(105.data.brain_states.GIL.total_runs; 0)}} GIL_PNL={{ifempty(105.data.brain_states.GIL.cumulative_pnl; 0)}} GIL_BIAS={{replace(replace(ifempty(105.data.brain_states.GIL.current_bias; neutral); newline; ); quote; )}} ALC_W={{ifempty(105.data.brain_states.CRYPTE_JU.wins; 0)}} ALC_L={{ifempty(105.data.brain_states.CRYPTE_JU.losses; 0)}} ALC_RUNS={{ifempty(105.data.brain_states.CRYPTE_JU.total_runs; 0)}} MAR_W={{ifempty(105.data.brain_states.MAREES.wins; 0)}} MAR_L={{ifempty(105.data.brain_states.MAREES.losses; 0)}} MAR_RUNS={{ifempty(105.data.brain_states.MAREES.total_runs; 0)}}|COACHING={{replace(replace(ifempty(105.data.sages_coaching; emptystring); newline; ); quote; )}}"}]}
```

Le prompt système et le message utilisateur sont **repris tels quels** du module Gemini actuel :
mêmes 21 variables, même schéma JSON à 9 champs, même bloc COACHING, même consigne
d'autocritique. Seule l'enveloppe change (format `chat/completions` au lieu du format Gemini).
Réglages alignés sur le 201 : `openai/gpt-oss-120b`, `reasoning_effort: low`,
`temperature: 0.01`, `response_format: json_object`. `max_tokens` est à 2000 (contre 1500 pour
le 201) parce que le schéma du Mémoire a 9 champs.

**d) Les deux modules qui lisent la sortie du 207** — la réponse Groq n'a pas la même forme que
la réponse Gemini. Dans les modules **208 💧 DISTILLATION MÉMOIRE** et **10032 📜 LE SCEAU DES
SAGES**, remplacer :

```
207.data.candidates[1].content.parts[1].text
```
par
```
207.data.choices[1].message.content
```

C'est exactement la référence utilisée pour les modules 201, 203 et 205, et c'était celle du 207
avant le 13/08.

---

## 3. Rendre les pannes visibles (à faire, sinon ça recommencera en silence)

Les cinq modules Sages ont `stopOnHttpError = false` et **aucun `onerror`**. C'est pour ça que
le Mémoire est mort quatre jours sans que rien ne le signale : Gemini répondait HTTP 400, Make
passait à la suite, le Sceau n'écrivait rien pour ce Sage.

Sur les modules **201, 203, 205, 207, 209**, cocher **« Evaluate all states as errors »**
(`stopOnHttpError = true`) et leur ajouter une **route d'erreur `Resume`** renvoyant un JSON
vide, pour que le scénario continue mais que l'échec apparaisse dans l'historique d'exécution.

---

## 4. Les Marées — ce qui est établi et ce qui reste à confirmer

- Le moteur du module 20015 🌙 L'ARCHIMAGE DES MARÉES **n'a pas été touché** : c'était déjà
  `gemini-ai:createACompletionGeminiPro`, connexion « Zen Chez Toi Gemini » (7346284), modèle
  `gemini-3.5-flash`, avant comme après le 13/08.
- Dernière proposition en base : **21/08 09:05**, soit le dernier run complet avant la casse du
  303. Les Marées se sont donc tues **parce que le scénario s'arrêtait avant elles**.
- Le run réussi de 7051944 aujourd'hui à 14:35 a compté **76 opérations**. 80 modules moins les
  3 modules Binance `[OFF]` = 77 attendues : **un module n'a pas tourné**. Les seuls modules
  filtrés sont ceux déjà listés, donc il s'agit d'un module resté sans bundle — très
  probablement le **20018 📜 LE REGISTRE DES MARÉES**, parce que le 20017 lit
  `{{20016.livre_cible}}` et n'a rien reçu. Autrement dit l'Archimage a répondu, mais sans
  livre cible exploitable.
- **À confirmer au prochain run** : ouvrir la sortie du module 20015 dans l'historique
  d'exécution et regarder si `livre_cible` est présent et non vide. Tant que ce n'est pas
  vérifié, je ne conclus pas.

---

## Ordre d'application

1. Module 303 (2 remplacements) — **c'est le seul correctif indispensable pour que le scénario
   aille au bout**.
2. Module 305 (2 remplacements).
3. Module 207 + modules 208 et 10032.
4. `stopOnHttpError` sur les 5 Sages.

Après le point 1, un run doit passer de 29 à ~76 opérations.
