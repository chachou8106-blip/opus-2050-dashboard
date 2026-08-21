# Prompt Maia — ajouter au CTX les 3 indicateurs que le Sage Macro réclamait

> **Statut : PRÊT.** Tout le travail Supabase est fait et vérifié. Il ne reste qu'une ligne de texte
> à rallonger dans Make.

## D'où vient la demande

Au run de 22:18, le Sage Macro — enfin réparé — a terminé sa réponse par `;DXY missing`. Il avait
raison : son prompt système lui réclame `dxy_trend`, le ratio or/argent et le spread de crédit
HYG-LQD, alors qu'**aucun des trois n'existait dans les 92 champs de CTX**. Il l'a signalé au lieu
d'inventer — exactement le comportement voulu.

## Ce qui a été fait côté Supabase (rien à faire, déjà en place)

1. **Ingestion** : `HYG`, `LQD` et `UUP` ajoutés au cron `ingest-indices-daily` (21:00 UTC), et
   chargés immédiatement sur 30 jours — HYG 252 bougies, LQD 225, UUP 254, plus GLD et SLV
   rafraîchis à 365 chacun.
   `UUP` (Invesco DB US Dollar Index Bullish) sert de **mandataire coté du dollar index** : le DXY
   lui-même n'est pas un instrument négociable, donc pas disponible via Alpaca.

2. **Vue `v_macro_extra`** — calcul des trois indicateurs. Valeurs mesurées ce soir :

| Indicateur | Valeur |
|---|---|
| UUP | 27,90 |
| Variation du dollar sur 20 séances | −1,03 % |
| **`dxy_trend`** | **NEUTRAL** (seuils : ≥ +1,5 % STRONG, ≤ −1,5 % WEAK) |
| **`ratio_or_argent`** | **6,893** |
| HYG / LQD | 79,70 / 106,59 |
| **`credit_hyg_lqd_20j_pct`** | **+0,10** |

Le spread de crédit est la performance relative du haut rendement contre l'investment grade sur
20 séances : **positif = appétit pour le risque** (les spreads se resserrent), **négatif = fuite vers
la qualité** (ils s'écartent). +0,10 aujourd'hui, donc neutre à légèrement favorable au risque.

3. **`get_oracle_context()`** expose désormais le bloc `macro_extra`, vérifié :

```json
{"hyg":79.70,"lqd":106.59,"uup":27.9000,"dxy_trend":"NEUTRAL",
 "dxy_var_20j_pct":-1.03,"ratio_or_argent":6.893,"credit_hyg_lqd_20j_pct":0.10}
```

C'est le même module 105 que CTX utilise déjà pour `FLASH_INTEL` et `CIRCUIT_BREAKERS` — donc un
chemin déjà éprouvé, aucun nouveau module, aucun risque de blocage Make.

## Prompt à envoyer à Maia

```
Bonjour Maia. Scenario 6183820. Deux modules : 110 et 201. Aucun nouveau module a creer.

Contexte : le Sage Macro repond "DXY missing" parce que son prompt lui reclame trois indicateurs
qui n'existent dans aucun des 92 champs de CTX. Ils viennent d'etre calcules cote Supabase et sont
disponibles dans 105.data.macro_extra — le meme module 105 que CTX utilise deja pour FLASH_INTEL
et CIRCUIT_BREAKERS.

1) MODULE 110 (CREUSET DU CONTEXTE) — variable CTX.
   La valeur se termine actuellement par :
   |CIRCUIT_BREAKERS={{replace(replace(ifempty(toString(105.data.active_circuit_breakers); "[]"); newline; ); quote; )}}

   AJOUTE a la toute fin, sans rien supprimer ni reordonner, ces quatre champs :
|DXY_TREND={{ifempty(105.data.macro_extra.dxy_trend; "INCONNU")}}|DXY_VAR20J={{ifempty(105.data.macro_extra.dxy_var_20j_pct; 0)}}|OR_ARGENT={{ifempty(105.data.macro_extra.ratio_or_argent; 0)}}|CREDIT_HYG_LQD={{ifempty(105.data.macro_extra.credit_hyg_lqd_20j_pct; 0)}}

2) MODULE 201 (Sage Macro) — message "system" uniquement. Une phrase a remplacer.

   a chercher :
INDICATEURS SUPPLEMENTAIRES a integrer : DXY dollar index, ratio Gold sur Silver, credit spreads HYG contre LQD.
   a remplacer par :
INDICATEURS SUPPLEMENTAIRES, tous fournis dans CTX : DXY_TREND vaut STRONG NEUTRAL ou WEAK et alimente directement dxy_trend ; DXY_VAR20J est la variation du dollar en pourcentage sur 20 seances ; OR_ARGENT est le ratio or sur argent, un ratio qui monte signale l aversion au risque ; CREDIT_HYG_LQD est la performance du haut rendement moins celle de l investment grade sur 20 seances, positif egale appetit pour le risque et spreads qui se resserrent, negatif egale fuite vers la qualite. Ces quatre cles existent desormais : ne les declare plus manquantes.

3) Ne change rien d'autre : ni le message "user" du 201 (il doit rester CTX={{110.value}}), ni le
   modele openai/gpt-oss-120b, ni l'URL Groq, ni aucun autre module.

Puis SAUVEGARDE et confirme-moi que la variable CTX du module 110 se termine bien par
CREDIT_HYG_LQD={{ifempty(105.data.macro_extra.credit_hyg_lqd_20j_pct; 0)}}
```

## Contrôle après le prochain run

```sql
select created_at, sage_output->>'dxy_trend' as dollar,
       left(sage_output->>'news_catalyst', 70) as catalyseur
from oracle_sages_report where sage_name = 'Macro'
order by created_at desc limit 3;
```

`news_catalyst` ne doit plus contenir « missing », et `dxy_trend` doit valoir **NEUTRAL** — non plus
par défaut, mais parce que le dollar a reculé de 1,03 % sur 20 séances, sous le seuil de ±1,5 %.

## Note de méthode

Le DXY officiel (indice ICE) n'est pas un instrument négociable et n'est donc pas accessible via
Alpaca. UUP en est le mandataire coté usuel. La tendance qu'on en tire est fiable ; le **niveau**
absolu de UUP (27,90) n'est pas la valeur du DXY et ne doit pas être lu comme telle — c'est pourquoi
seul `DXY_TREND` et sa variation sont transmis au Sage, jamais le niveau brut.
