# Prompt Maia — RÉPARER la clé API des modules staking (cause du « Alchimiste MUET ») — 2026-08-18

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
