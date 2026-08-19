# Prompt Maia — RÉPARER la clé API des modules staking (cause du « Alchimiste MUET ») — 2026-08-18

> **RE-VÉRIFIÉ LE 19/08/2026 — toujours valable, rien n'a bougé.**
> Blueprint relu en lecture seule : le JWT corrompu (`ref: smddzbxebwfnitxuyuyp`) est présent
> sur **exactement 4 en-têtes** — modules **20022** (`apikey` + `Authorization`, vue
> `v_alc_staking_delais_txt`) et **20023** (`apikey` + `Authorization`, vue `v_alc_staking_apy_txt`).
> Côté base : dernière ligne dans `alc_destake_reco` le **17/08 à 20:00**, plus rien depuis ;
> la Vigie signale toujours « Alchimiste verdict » hors OK. Le prompt ci-dessous reste à envoyer tel quel.

## ⚠️ Pourquoi Maia a répondu « c'est déjà correct » (19/08, 2ᵉ tentative)

Maia a comparé les deux clés **visuellement** et a conclu qu'elles étaient identiques. Elles ne le sont pas —
mais l'erreur est compréhensible :

- Les deux JWT font **exactement 208 caractères**.
- Ils ne diffèrent que sur **12 caractères consécutifs**, aux positions **77 à 88**, en plein milieu du
  base64 :
  - correcte : `…ZiI6InNtZGR6eWJ4ZWJ3aGZuaXR4dXlw…`
  - corrompue : `…ZiI6InNtZGR6YnhlYndmbml0eHV5dXlw…`
- Une fois décodés : `ref: smddzybxebwhfnitxuyp` (bonne) contre `ref: smddzbxebwfnitxuyuyp` (corrompue).

**Mécanisme de la panne, confirmé :** l'en-tête et la **signature** des deux JWT sont **identiques**, seul
le payload diffère. Le jeton a donc été **édité à la main** sans être re-signé → la signature ne correspond
plus au contenu → Supabase répond **401 Invalid API key**. Ce n'est pas un problème de droits, c'est un
jeton mathématiquement invalide.

### Moyen de contrôle infaillible (à donner à Maia)

Ne pas comparer à l'œil. Tester la présence d'une **sous-chaîne discriminante** dans la valeur de l'en-tête :

| Sous-chaîne | Signification |
|---|---|
| `ZiI6InNtZGR6eWJ4ZWJ3aGZuaXR4dXlw` | ✅ clé correcte |
| `ZiI6InNtZGR6YnhlYndmbml0eHV5dXlw` | ❌ clé corrompue, à remplacer |

## Diagnostic (prouvé, ne rien inventer)
Depuis la modification du 17/08 ~20:50, les modules **20022** (⛓️ LES CHAÎNES DU SCELLÉ, délais)
et **20023** (🌾 LA RENTE DES SCELLÉS, APY) portent une **clé anon Supabase corrompue**
(le JWT contient `smddzbxebwfnitxuyuyp` au lieu de `smddzybxebwhfnitxuyp`).
Conséquence à chaque run : HTTP **401 Invalid API key** → données staking **vides** → l'Alchimiste
rend `"destake_recommande": []` → plus aucune ligne de dé-stake écrite (Vigie : « Alchimiste verdict MUET »).
Les propositions de trading, elles, fonctionnent (module 10023 a la bonne clé).

## À faire dans Make — modules 20022 et 20023 UNIQUEMENT
Dans **chacun** des deux modules HTTP `20022` et `20023`, remplacer la valeur des **2 en-têtes**
`apikey` et `Authorization` par la clé anon CORRECTE (la même que dans le module 10023) :

- En-tête `apikey` → valeur exacte :
```
eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InNtZGR6eWJ4ZWJ3aGZuaXR4dXlwIiwicm9sZSI6ImFub24iLCJpYXQiOjE3Nzk4ODk4NzksImV4cCI6MjA5NTQ2NTg3OX0.ppjgF79OokQ-2jE8UCp26U-E-YZPcmf6TNnYEKHGKSM
```
- En-tête `Authorization` → valeur exacte :
```
Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InNtZGR6eWJ4ZWJ3aGZuaXR4dXlwIiwicm9sZSI6ImFub24iLCJpYXQiOjE3Nzk4ODk4NzksImV4cCI6MjA5NTQ2NTg3OX0.ppjgF79OokQ-2jE8UCp26U-E-YZPcmf6TNnYEKHGKSM
```

## NE RIEN CHANGER D'AUTRE
- Ne pas toucher aux URLs (`v_alc_staking_delais_txt` / `v_alc_staking_apy_txt`) ni à l'en-tête
  `Accept: application/vnd.pgrst.object+json` (corrects).
- Ne pas toucher aux modules 10012 (Alchimiste), 10014 (parse), 10023 (RPC), 10031 (Discord).
- Ne pas toucher au prompt.

## Vérification après enregistrement
Relancer un run : `alc_destake_reco` doit recevoir de nouvelles lignes (TON, ATOM, KSM…),
la section « DE-STAKING » réapparaît dans le rapport Discord, et la Vigie repasse
« Alchimiste verdict : OK ». Bonus attendu : les **vrais** APY (TON 17,67 %, ATOM 21,06 %)
seront enfin transmis — si le LLM les restitue mal malgré tout, appliquer ensuite le prompt
`PROMPT-MAIA-ALCHIMISTE-BASE64-2026-08-18.md` (texte brut au lieu de base64).
