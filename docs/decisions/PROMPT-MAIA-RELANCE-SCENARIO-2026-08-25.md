# Relancer le scénario 6183820 — instructions Maia, 25/08/2026

> Vérifié sur le blueprint **en direct**, et pour le module 207 **testé pour de vrai** contre
> l'API Gemini avec la nouvelle clé (12 appels). Rien ici n'est supposé.

---

## 0. Rectifications — trois choses que j'avais écrites de travers

1. **« Remettre le 207 sur Groq »** : non. Le passage de Groq à Mistral (205) et à Gemini (207)
   a été fait **parce que le quota Groq était dépassé** après l'allongement des prompts des Sages
   et des Archimages. Les remettre sur Groq ferait revenir la panne de quota. **Le 207 reste sur
   Gemini** ; le vrai défaut est ailleurs (§2).
2. **Le planning des runs** : il est dans **Supabase**, pas dans l'intervalle Make. Table
   `scenario_runs_planifies`, lue toutes les 5 min par le job pg_cron `scenario_fire_5min` →
   `scenario_fire()`. Mon avertissement sur « 900 s contre 3600 s » ne servait à rien.
3. **Les coupe-circuits** : `iron_sentinel_validate_order` n'est **pas** la seule fonction qui
   écrit dans `oracle_circuit_breakers`. `check_circuit_breakers` y écrit aussi, et c'est elle qui
   a posé la ligne `drawdown_8pct` de GIL du 25/08 16:19 (voir §5).

---

## 1. Le blocage principal — module 303, et lui seul

Le scénario 6183820 s'arrête à **29 opérations sur 80**. Le 29ᵉ module dans l'ordre d'exécution
est le **303 🌙 LE PROPHÈTE D'ARGENT — SYL**.
Erreur : `InvalidConfigurationError — The provided JSON body content is not valid JSON`.

Son `jsonStringBodyContent` contient quatre séquences `\ ` (antislash + espace, échappement
interdit en JSON) et un fragment parasite `{{\}} ## \`.

**Tout ce qui vient après le 303 n'a pas tourné depuis le 21/08 09:19** : GIL, les ordres Alpaca,
l'Alchimiste, les Marées, les hérauts Discord.

### Module 303 — champ `jsonStringBodyContent`

**Remplacement 1** (une seule occurrence) — chercher exactement :

```
\ + "bias\"); \ + " ## \"));
```
remplacer par exactement :
```
"bias"); " ## "));
```

**Remplacement 2** (une seule occurrence) — chercher exactement :

```
\ + "erreur\"); \ + " ## \")}}{{\}} ## \
```
remplacer par exactement :
```
"erreur"); " ## ")}}
```

Après ces deux remplacements, le corps du 303 est **identique octet pour octet** à celui du
scénario 7051944, qui tourne.

### Module 305 ⚖️ L'ARBITRE DORÉ — GIL — même champ, même famille de défaut

**Remplacement 1** — chercher exactement :
```
\"bias\"); \" ## \"));
```
remplacer par exactement :
```
"bias"); " ## "));
```

**Remplacement 2** — chercher exactement :
```
\"erreur\"); \" ## \")}}
```
remplacer par exactement :
```
"erreur"); " ## ")}}
```

---

## 2. Module 207 📚 DEEP MEMORY — `Source is not valid JSON` : cause trouvée et testée

La clé Gemini refaite fonctionne. Le défaut est ailleurs : **`gemini-3.5-flash` est un modèle à
raisonnement, et ses jetons de réflexion sont décomptés de `maxOutputTokens`, qui est à 2000.**

Douze appels réels avec le corps exact du module et la nouvelle clé :

| Configuration | Réflexion | Réponse | Total | Résultat |
|---|---|---|---|---|
| actuelle (2000, pas de `thinkingConfig`) | 1900 | **84** | 1984 | `MAX_TOKENS` → **JSON tronqué** |
| actuelle | 1620 | 134 | 1754 | JSON valide |
| actuelle | 1718 | 190 | 1908 | JSON valide |
| actuelle | 1679 | 139 | 1818 | JSON valide |
| **`thinkingBudget: 0`** | **0** | 145 | **145** | JSON valide, à chaque fois |

**Un appel sur quatre part en `MAX_TOKENS`** : la réflexion mange 1900 des 2000 jetons, il ne
reste que 84 jetons pour la réponse, le JSON est coupé au milieu — et c'est exactement le
`DataError — Source is not valid JSON` que le module 208 renvoie derrière.

### Le correctif, dans le corps du module 207 — un seul remplacement

Chercher exactement :
```
"generationConfig":{"temperature":0.01,"maxOutputTokens":2000,"responseMimeType":"application/json"}
```
remplacer par exactement :
```
"generationConfig":{"temperature":0.01,"maxOutputTokens":2000,"responseMimeType":"application/json","thinkingConfig":{"thinkingBudget":0}}
```

Ne toucher à rien d'autre : ni l'URL, ni la clé, ni le prompt.

**Effet secondaire utile : 145 jetons de sortie au lieu de ~1900, soit 13 fois moins de quota
Gemini consommé par run.** C'est le même problème de quota qui avait fait fuir Groq.

### Le module 20015 🌙 L'ARCHIMAGE DES MARÉES tourne sur le même modèle

Son `generationConfig` est `{"imageConfig":{},"thinkingConfig":{}}` — la réflexion est donc
active, sans budget, et elle consomme le même quota Gemini que le 207. Il n'a pas encore planté,
mais il est exposé au même `MAX_TOKENS`. À surveiller ; si le 20016 sort un
`Source is not valid JSON`, c'est ça.

---

## 2 bis. Module 209 ⚡ QUANTUM PULSE — il ne produit pas ce que le 211 lui demande

Détail et preuves : `docs/decisions/AUDIT-TABLES-ET-PROMPTS-2026-08-25.md` §3 et §4.

Son `response_format` est un `json_schema` strict (`additionalProperties: false`) à 8 champs. Le
module **211 ⚡ FLASH INTEL LOGGER** lit trois champs absents de ce schéma : `web_intelligence`,
`trade_1` et `catalysts`. Résultat : `catalysts` vaut toujours `[]`, la table `oracle_flash_intel`
est **vide depuis sa création**, et **GIL reçoit un bloc de renseignement vide à chaque run**
(son prompt lit `105.data.flash_intel_latest`).

**Dans le module 209**, à l'intérieur de `"schema": { "properties": { ... } }`, ajouter :

```
"web_intelligence": {"type": "string"},
"catalysts": {"type": "array", "items": {"type": "object", "properties": {
  "ticker": {"type": "string"}, "type": {"type": "string"}, "headline": {"type": "string"}},
  "required": ["ticker", "type", "headline"], "additionalProperties": false}}
```

et ajouter `"web_intelligence"` et `"catalysts"` à la liste `"required"`.

**Dans le module 211**, remplacer :
```
"top_ticker": "{{trim(upper(ifempty(210.trade_1.ticker; MARKET)))}}", "top_direction": "{{lower(ifempty(210.trade_1.side; neutral))}}"
```
par :
```
"top_ticker": "{{trim(upper(ifempty(210.catalysts[1].ticker; MARKET)))}}", "top_direction": "{{lower(ifempty(210.flash_sentiment; neutral))}}"
```

Le 404 côté Supabase qui bloquait ce module est **déjà corrigé** (surcharge `log_flash_intel`
à cinq arguments, testée : `catalysts_logged: 1`, routage vers les 5 agents).

---

## 3. Rendre les pannes visibles

Les cinq modules Sages ont `stopOnHttpError = false` et **aucun `onerror`**. C'est pour ça que le
Mémoire est mort quatre jours sans que rien ne le signale.

Sur les modules **201, 203, 205, 207, 209** : cocher **« Evaluate all states as errors »** et leur
ajouter une **route d'erreur `Resume`** renvoyant `{}`, pour que le scénario continue mais que
l'échec apparaisse dans l'historique.

---

## 4. Les Marées — elles écrivent, en fait

Vérifié dans les logs Supabase du run réussi de 12:35 :

```
2026-08-25T12:38:02  POST | 200 | /rest/v1/rpc/marees_record_propositions | Make/production
```

Le module 20018 a bien appelé Supabase, et Supabase a répondu **200**. Rien n'a bougé dans
`marees_propositions` pour une raison de conception, pas de panne : depuis ma modification du
20/08, cette table n'est plus un journal de tous les runs mais un **livre cible**. Une position
déjà ouverte et toujours proposée est « tenue » — elle n'est pas réinsérée. Les trois positions
ouvertes (EUR-GBP sell du 21/08, EUR-USD sell du 18/08, USD-JPY buy du 14/08) ont été reproposées
telles quelles : 0 nouvelle, 0 fermée, 3 tenues.

**Avant le 20/08, chaque run réinsérait le livre entier** — d'où l'impression que « ça écrivait ».
Une position tenue 34 runs comptait alors pour 34 trades, ce qui faussait le win rate. Le
changement est volontaire ; ce qui manque, c'est une trace visible du run quand rien ne change.
Le résumé part déjà sur Discord via le module 20021.

---

## 5. Les coupe-circuits — ils existent et ils marchent

Deux fonctions écrivent dans `oracle_circuit_breakers` :

- **`check_circuit_breakers`** — insère et met à jour. Lancée par le job pg_cron
  `directional_kelly_breakers` (`19 */2 * * *`). C'est elle qui a posé
  `GIL / drawdown_8pct / 0.1023 / poids_plancher_0.05` le **25/08 à 16:19**.
- `iron_sentinel_validate_order` — insère aussi.

**Le trou n'est pas là.** Il est que `iron_sentinel_validate_order` **n'est appelée par personne** :
zéro occurrence dans les deux blueprints Make, dans les edge functions et dans les fonctions SQL.
`execute-trades` écrit `validated: true` en dur, ne lit jamais `notional_validated` et n'appelle
jamais la sentinelle. Sur les 7 derniers jours : 116 ordres, 116 exécutés, 0 rejeté.

Coupe-circuits actuellement **non résolus**, qui partiront dans les prompts au prochain run :

| Agent | Motif | Valeur | Depuis |
|---|---|---|---|
| GIL | `drawdown_8pct` | 10,23 % | 25/08 16:19 |
| GIL | `drawdown_5pct` | 6,26 % | 20/08 16:19 |
| MAREES | `win_rate_faible` | 30,8 % | 21/08 09:53 |

---

## 6. Le planning — pourquoi rien ne partira même une fois tout réparé

Le déclenchement vient de Supabase : `scenario_fire_5min` (pg_cron, toutes les 5 min) →
`scenario_fire(false)` → lit `scenario_runs_planifies`, démarre le scénario **6183820** via l'API
Make, et le coupe 3 minutes après.

| Créneau | Heure (Paris) | Jours | Actif | Dernier tir |
|---|---|---|---|---|
| Matin Europe | 09:00 | lun–ven | oui | **21/08** |
| Ouverture US | 15:45 | lun–ven | oui | **21/08** |
| Mi-séance US | 18:30 | lun–ven | oui | **21/08** |
| Avant clôture US | 21:15 | lun–ven | oui | **21/08** |

Les quatre créneaux sont actifs, mais **`scenario_control.actif = false` depuis le 23/08 à 00:04**.
Tant que cet interrupteur maître est sur OFF, `scenario_fire` sort sur « maitre off » et ne
démarre rien.

**Ordre d'application :**

1. Module 303 (2 remplacements) — indispensable, le scénario passe de 29 à ~76 opérations.
2. Module 305 (2 remplacements).
3. Module 207 (1 remplacement, `thinkingBudget: 0`).
4. `stopOnHttpError` sur les 5 Sages.
5. Remettre `scenario_control.actif` à `true` — **décision de Chachou**, c'est ce qui relance les
   4 runs quotidiens.
