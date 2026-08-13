# Correctif Alchimiste — « il trade ce qui n'est pas tradable » (13/08/2026)

## Symptôme
Le scénario Make **ZCT — Oracle L'Alchimiste Financier v5** (`6183820`) envoyait des
messages Discord où l'Alchimiste tentait de trader des paires **non exécutables** sur
Revolut X.

## Cause racine (preuves croisées Supabase + Make)
L'exécuteur `alc-auto` (v5) était incohérent avec la règle SPOT de Revolut X
(documentée dans `oracle_contexte` / EXECUTION / `revolut_x_spot` :
*« buy exige du cash quote ; sell exige une position détenue ; aucun short »*) :

1. **Garde-fou « sell-only » à l'envers** : `if (side !== "sell") ignore` → bloquait
   TOUS les achats, alors que sur spot l'achat (avec le cash USD) est l'action principale.
2. **Filtre `allowed_pairs` = coins stakés** : la liste `SOL,TON,ATOM,TRX` correspondait
   à des coins **100 % en stake (dispo = 0 → invendables)**.
3. **Aucune vérification des soldes réels** : l'Oracle proposait des `sell` sur des coins
   **non détenus** (NEAR, INJ, ONDO, AVAX, LINK, BNB, HYPE) ou **stakés** (SOL) →
   0 proposition réellement exécutable.

## Correctif (edge functions Supabase uniquement — Make non touché, via Maia)
- **`alc-auto` v6** : accepte **buy ET sell** ; la tradabilité vient de la réalité LIVE
  (`revolut-x-prices` pour l'univers -USD coté, `revolut-x-read` pour cash + soldes).
  - BUY : paire cotée + cash USD dispo, montant plafonné au cash restant.
  - SELL : actif **détenu et liquide** (dispo > 0, hors stake), montant plafonné à la
    valeur liquide (dispo × bid).
  - Staking-aware : un coin 100 % staké est marqué invendable avec son délai de déblocage
    (`alc_staking_delais`). Le stake/unstake **n'est pas automatisable** (API Revolut X =
    401 sur tous les endpoints staking, cf `revx-staking-probe`) → action manuelle in-app.
- **`revolut-x-trade` v7** : le gate `allowed_pairs` devient une whitelist optionnelle
  (`*`/vide = univers réel) ; les 4 cadenas monétaires (kill_switch, dry_run, max_order,
  max_daily, spot-check) sont **inchangés**.
- **`ju_crypte_config.allowed_pairs`** : passé de `SOL,TON,ATOM,TRX` (coins stakés) à `*`.

## Verrous respectés
- `kill_switch` / `dry_run` NON modifiés (geste réservé à Chachou).
- Blueprint Make NON modifié (toute modif Make passe par Maia).

## Reste à faire (hors périmètre edge functions)
La **génération** des propositions (scénario Make / Collège / Perplexity) propose encore
majoritairement des `sell` short-only. Pour que l'Alchimiste **achète** vraiment, le prompt
de proposition doit intégrer l'univers achetable (cash USD) + les positions vendables.
→ à câbler côté Make **via Maia**.
