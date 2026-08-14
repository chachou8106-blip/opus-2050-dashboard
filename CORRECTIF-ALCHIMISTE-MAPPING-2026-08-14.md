# Correctif — enregistrement des propositions Alchimiste (14/08/2026)

## Ce que Maia a trouvé (et pourquoi c'était le bon réflexe)
Le module Make « Le Registre de Cristal » (ID 10023) ne mappe PAS les colonnes : il envoie
seulement le JSON brut de l'IA (base64 `p_raw_b64`) + `p_run_id` / `p_tolerance` / `p_validity_hours`
à la fonction Supabase `public.alc_record_propositions`. **C'est cette fonction qui extrait les
colonnes.** Maia a donc eu raison de ne rien toucher côté Make et de renvoyer vers Supabase.

## La cause exacte
`alc_record_propositions` lisait les ANCIENNES clés de l'IA, alors que le nouveau prompt en produit
d'autres :

| Colonne     | Ancienne clé lue        | Nouvelle clé IA |
|-------------|-------------------------|-----------------|
| paire       | `crypto`                | `paire`         |
| side        | `sens`                  | `side`          |
| prix_ref    | `prix_actuel`           | *(absente)*     |
| montant     | `montant_usd`           | `montant`       |
| confidence  | `gain_net_estime_pct`   | `confidence`    |
| raison      | `raison_courte`         | `raison`        |

→ toutes les colonnes ressortaient NULL (seul `resultat` JSON était rempli).

## Le correctif (100 % Supabase, aucune modif Make)
`alc_record_propositions` réécrite (même signature, donc le module Make est inchangé) :
- lit les **nouvelles clés** avec repli sur les anciennes (`coalesce`) → rétro-compatible ;
- **prix_ref** : comme l'IA ne fournit plus de prix, la fonction va chercher le **dernier cours**
  de la paire dans `price_history` (interval 1h). C'est ce que Make ne pouvait pas faire ;
- persiste les **recommandations de dé-staking** (`destake_recommande`) dans une nouvelle table
  `alc_destake_reco` (avant : perdues).

## Effets
- Colonnes `paire/side/montant/confidence/prix_ref/raison` de nouveau remplies à chaque run.
- Le rebuild du portefeuille papier (`alc_rebuild_virtual`, filtre `prix_ref > 0`) reprend les
  propositions → l'Alchimiste **réapprend** (trades virtuels + P&L + brain state).
- Les 4 propositions du 14/08 ont été **rétro-remplies** depuis leur `resultat` + lookup prix
  (BUY BTC, SELL TRX, SELL BTC, BUY ETH), et le portefeuille virtuel a été reconstruit.

## Conséquence pour Maia
Le 2e prompt Maia (`PROMPT-MAIA-ALCHIMISTE-MAPPING`) **n'est plus nécessaire** : rien à changer
dans le scénario, tout est réglé côté base.
