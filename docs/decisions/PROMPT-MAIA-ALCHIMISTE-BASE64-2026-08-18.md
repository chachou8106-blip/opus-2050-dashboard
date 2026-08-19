# Prompt Maia — Alchimiste : retirer le Base64 (cause du faux APY) — 2026-08-18

> ## 🔺 CONFIRMÉ PAR LE RUN DU 19/08 À 10:28 — à envoyer
>
> Après réparation de la clé staking, l'Alchimiste a de nouveau écrit 7 lignes dans `alc_destake_reco`.
> Résultat en demi-teinte, qui **prouve** que le Base64 est bien le coupable :
>
> | | Attendu (vues Supabase) | Écrit par l'Alchimiste |
> |---|---|---|
> | **APY** | TON 17,67 · ATOM 21,06 · KSM 10,47 | ✅ **exacts** |
> | **Délais de déblocage** | TON 2j · ATOM 21j · KSM 7j · OSMO 14j · SOL 3j · TRX 14j · ETH 5j | ❌ **0 pour les 7** |
>
> La vue `v_alc_staking_delais_txt` envoie pourtant bien `ATOM:21j | ETH:5j | KSM:7j | OSMO:14j | SOL:3j | TON:2j | TRX:14j`.
> Le modèle décode donc le Base64 **partiellement** : il sort les APY justes et met les délais à zéro.
> (Le 18/08 c'était l'inverse — délais justes, APY inventés. Le décodage mental n'est pas fiable, point.)
>
> **Conséquence concrète** : avec un délai à 0, un futur arbitrage pourrait conclure à tort qu'un dé-stake
> est instantané et sans coût. Les 7 verdicts « GARDER » du run restent justes (APY 21 % contre 6 % de gain
> attendu), mais la donnée enregistrée est fausse.
>

## Diagnostic (vérifié, ne rien inventer)
Les 2 modules HTTP staking **lisent les bonnes données** :
- `20022` (⛓️ LES CHAÎNES DU SCELLÉ) → `GET v_alc_staking_delais_txt?select=delais_texte` + `Accept: application/vnd.pgrst.object+json` ✅
- `20023` (🌾 LA RENTE DES SCELLÉS) → `GET v_alc_staking_apy_txt?select=apy_texte` + même Accept ✅

Ces vues renvoient bien les vraies valeurs (ex. `TON:17.67% | ATOM:21.06% | KSM:10.47% …`).

**La panne est dans le module `10012` « L'Alchimiste de la Crypte »** : il transmet ces valeurs au LLM **encodées en Base64** (`STAKING_APY_B64={{base64(...)}}`) et lui demande de « décoder mentalement ». `sonar-pro` n'y arrive pas → il **devine** l'APY depuis ses connaissances (d'où TON 5 % au lieu de 17,67 % ; les délais tombent justes seulement parce que ce sont des constantes réseau connues). **Solution : envoyer le texte brut, sans Base64.**

## À faire dans Make (module 10012 uniquement, via Maia)
Édite le corps (JSON body) du module **10012 « L'Alchimiste de la Crypte »**.

### 1) Remplacer les mappings encodés par du texte brut

> **[19/08] Périmètre réduit à 2 champs sur 3, volontairement.** Le Base64 sert aussi de protection :
> il empêche des guillemets ou des sauts de ligne de casser le corps JSON de la requête. J'ai donc
> vérifié le contenu réel avant de proposer :
>
> | Champ | Contenu | Guillemets | Sauts de ligne | Antislash | Verdict |
> |---|---|---|---|---|---|
> | `STAKING_DELAIS` | 65 car. — `ATOM:21j \| ETH:5j \| …` | non | non | non | ✅ sûr en clair |
> | `STAKING_APY` | 86 car. — `ATOM:21.06% \| ETH:2.45% \| …` | non | non | non | ✅ sûr en clair |
> | `PRIX_REVOLUTX` | vient de l'edge function 10011, format non vérifié | ? | ? | ? | ⚠️ **on n'y touche pas** |
>
> `CTX_B64`, `SAGES_B64` et les `AVIS_GIL_*_B64` restent en Base64 : ce sont de gros blocs de texte
> libre, le Base64 y est indispensable.

| Chercher (exact) | Remplacer par |
|---|---|
| `STAKING_DELAIS_B64={{base64(ifempty(20022.data.delais_texte; emptystring))}}` | `STAKING_DELAIS={{ifempty(20022.data.delais_texte; emptystring)}}` |
| `STAKING_APY_B64={{base64(ifempty(20023.data.apy_texte; emptystring))}}` | `STAKING_APY={{ifempty(20023.data.apy_texte; emptystring)}}` |

### 2) Mettre à jour le prompt système (2 phrases) pour dire que c'est du texte brut
Chercher :
> « Les champs PRIX_REVOLUTX_B64, STAKING_DELAIS_B64 et STAKING_APY_B64 sont des chaînes Base64 : décode-les mentalement avant analyse ; ils contiennent les tableaux/objets correspondants. »

Remplacer par :
> « Les champs PRIX_REVOLUTX, STAKING_DELAIS et STAKING_APY sont du **TEXTE BRUT** directement lisible, au format « DEVISE:valeur | DEVISE:valeur » (ex. « TON:17.67% | ATOM:21.06% »). **Utilise ces valeurs telles quelles.** Ne les décode pas. **N'utilise JAMAIS tes connaissances générales pour l'APY : si STAKING_APY est vide, dis-le explicitement au lieu de deviner.** »

Chercher :
> « STAKING_DELAIS_B64 et STAKING_APY_B64 : données encodées des deux tables, à joindre par devise de base. »

Remplacer par :
> « STAKING_DELAIS et STAKING_APY : texte brut des deux tables (DEVISE:valeur | …), à joindre par devise de base. »

### 3) Ne rien changer d'autre
- Ne pas toucher aux modules 20022 / 20023 / 10011 (ils sont corrects).
- Ne pas toucher aux en-têtes ni aux URLs.
- Garder `stopOnHttpError`, le modèle `sonar-pro`, la température, `max_tokens`.

## Vérification après enregistrement
Au prochain run, l'Alchimiste doit écrire dans `alc_destake_reco` **les vraies valeurs** :
`TON apy≈17.67 / délai 2j`, `ATOM apy≈21.06 / 21j`, `KSM apy≈10.47 / 7j`. Si l'APY colle enfin à `v_staking_point`, c'est réglé.
