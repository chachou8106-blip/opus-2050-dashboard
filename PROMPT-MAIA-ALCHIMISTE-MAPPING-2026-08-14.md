PROMPT POUR MAIA (2e correctif) — scénario 6183820 « ZCT — Oracle L'Alchimiste Financier v5 »

Maia, le scénario ne plante plus (merci pour le correctif JSON) et l'Alchimiste propose de nouveau
— et cette fois il achète ET vend, c'est parfait. MAIS ses propositions ne sont plus **enregistrées
correctement** dans la base : je te présente le problème et te laisse choisir la correction. Ne
change QUE le module d'enregistrement concerné, ne casse rien d'autre.

────────────────────────────────────────
1) LE SYMPTÔME (constaté en base)
────────────────────────────────────────
Table `alchimiste_crypte_propositions`. Depuis la nouvelle version du prompt (14/08), chaque
proposition crée bien une ligne, MAIS ses colonnes structurées sont VIDES :
  - `paire` = NULL, `side` = NULL, `montant` = NULL, `confidence` = NULL, `prix_ref` = NULL,
    `raison` = vide.
  - Seule la colonne `resultat` (JSON) contient la vraie donnée, ex. :
        {"side":"buy","paire":"BTC-USD","montant":2.5,"tp_pct":5,"sl_pct":3.5,"confidence":0.6,"raison":"…"}

Avant le 14/08, ces colonnes étaient TOUJOURS remplies (paire, side, montant, confidence).
Donc la donnée existe, mais elle n'est plus recopiée dans les bonnes colonnes.

────────────────────────────────────────
2) POURQUOI C'EST GRAVE (ce que ça casse en aval)
────────────────────────────────────────
Plusieurs traitements lisent ces COLONNES (pas le JSON `resultat`) :
  - Le rebuild du portefeuille papier de l'Alchimiste (apprentissage) ne prend que les lignes où
    `prix_ref > 0`. Avec `prix_ref` NULL, les propositions du jour sont IGNORÉES → aucun trade
    virtuel, aucun P&L papier, donc l'Alchimiste **n'apprend pas** de ses idées du jour.
  - L'affichage console et l'exécution réelle (quand le kill-switch est armé) s'appuient aussi sur
    ces colonnes.

────────────────────────────────────────
3) PISTE DE CAUSE
────────────────────────────────────────
Le module qui ENREGISTRE la proposition (POST vers alchimiste_crypte_propositions) mappe
probablement encore les ANCIENS noms de champs de l'IA (ex. `crypto`, `sens`, `montant_usd`,
confidence sur 0–10). Or le nouveau prompt renvoie d'autres clés : `paire`, `side`, `montant`,
`confidence` (échelle 0–1), `tp_pct`, `sl_pct`, `raison`. Les anciens chemins ne trouvent plus
rien → colonnes NULL. Le JSON complet, lui, est stocké tel quel dans `resultat`, d'où l'écart.

De plus, le nouveau format de sortie **ne contient plus de prix** (avant il y avait un
`prix_actuel`). Or `prix_ref` est nécessaire en aval (rebuild papier + exécution).

────────────────────────────────────────
4) CE QUE JE TE DEMANDE
────────────────────────────────────────
Dans le module d'enregistrement de la proposition, remets les colonnes en phase avec la nouvelle
sortie de l'IA, pour CHAQUE proposition de la liste :
  - `paire`      ← la paire de la proposition (ex. BTC-USD)
  - `side`       ← buy / sell
  - `montant`    ← le montant en USD
  - `confidence` ← la confiance (nouveau format 0–1 ; à toi de voir si tu la gardes en 0–1 ou la
                   remets sur l'échelle attendue par le reste du système)
  - `raison`     ← la justification courte
  - `prix_ref`   ← le PRIX de référence de la paire. Comme l'IA ne le fournit plus, prends-le au
                   moment de l'enregistrement depuis le flux de prix Revolut X déjà présent dans le
                   scénario (le module des prix), en faisant correspondre la paire. C'est indispensable
                   pour que le portefeuille papier et l'exécution fonctionnent.
  - (`resultat` peut continuer à stocker le JSON complet, c'est utile en secours.)

Point secondaire (si simple) : le nouveau prompt renvoie aussi un tableau `destake_recommande`
(les recommandations de dé-staking). Il n'est aujourd'hui enregistré NULLE PART. Si tu peux le
persister quelque part de propre, tant mieux ; sinon, signale-le et on verra ensemble — ce n'est
pas bloquant pour le trading.

Règles : ne modifie QUE ce module d'enregistrement (et, si besoin, la petite récupération du prix).
Ne touche pas au reste du scénario. Après correction, une nouvelle proposition doit remplir
paire/side/montant/confidence/prix_ref/raison dans la table, comme avant le 14/08.
