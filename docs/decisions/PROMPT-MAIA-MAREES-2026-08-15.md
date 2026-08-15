PROMPT POUR MAIA — scénario 6183820 « ZCT — Oracle L'Alchimiste Financier v5 VISIONNAIRE »

Maia, trois changements ciblés autour de l'Archimage des Marées + un nettoyage de nommage. Change
UNIQUEMENT ce qui est décrit, ne casse rien d'autre : ne touche pas aux IDs de modules ni aux mappings
(connexions entre modules), ne modifie pas les autres archimages.

────────────────────────────────────────
1) FENTE MÉMOIRE dans le prompt de Marées (« 🌙 L'ARCHIMAGE DES MARÉES »)
────────────────────────────────────────
Aujourd'hui, le prompt de Marées ne lit de son cerveau QUE `latest_web_catalysts`. Les Sages, eux,
lisent leur doctrine apprise comme « MEMORY_CORRECTION ». Marées doit faire pareil.

Ajoute dans le message envoyé au modèle de Marées une ligne de mémoire qui injecte sa doctrine apprise,
sur le modèle des Sages qui utilisent `brain_states.SYL.current_bias` (nettoyé des guillemets et des
retours ligne). Fais de même pour Marées avec le champ :
   brain_states.MAREES.current_bias
(disponible dans le même module de cerveaux — celui qui expose déjà `brain_states.MAREES.latest_web_catalysts`).
Injecte-le sous une étiquette claire, ex. :
   MEMOIRE_MAREES={{ (nettoyage guillemets/retours-ligne de) brain_states.MAREES.current_bias }}
Et dans le texte système de Marées, ajoute : « Tiens compte de MEMOIRE_MAREES (ta doctrine apprise)
pour corriger tes erreurs passées. »

────────────────────────────────────────
2) CALIBRAGE DE LA SORTIE (dans les instructions du prompt de Marées)
────────────────────────────────────────
Le forex bouge peu (~0,5 %/jour). Les sorties doivent être atteignables. Dans le texte système de
Marées, remplace les consignes de TP/SL par :
- TAKE-PROFIT visé ≈ 1,2 % ; STOP-LOSS ≈ 0,8 % (ratio gain/risque ~1,5:1). Ordres de grandeur adaptés
  au forex sur une détention de 2 à 4 jours — pas 3 %/2 % (quasi jamais touchés).
- Demande des `tp_pct` / `sl_pct` cohérents (autour de 1,0–1,5 % / 0,6–1,0 %).
- DIVERSIFICATION : ne pas empiler plusieurs positions du MÊME SENS sur des paires corrélées (ex. ne
  pas être vendeur simultanément de GBP-JPY, USD-JPY, EUR-JPY = un seul gros pari « short JPY »).
  Max ~2 positions même sens sur un groupe corrélé (même devise de base ou de contrepartie).

NOTE (à ne PAS toucher) : le « contre-pied raisonné » déjà présent dans le prompt de Marées (contrarian
vs consensus quand il est excessif, seulement si espérance positive) est LÉGITIME — laisse-le tel quel.
(Une ancienne inversion AVEUGLE du signal existait côté base, séparément ; elle est retirée côté base,
tu n'as rien à faire là-dessus.)

────────────────────────────────────────
3) RENOMMER LES MODULES SANS NOM ALCHIMIQUE
────────────────────────────────────────
Presque tous les modules ont un nom thématique (« 🌙 L'ARCHIMAGE DES MARÉES », « 💎 LE REGISTRE DE
CRISTAL »…). Renomme ceux qui restent génériques, SANS changer leur fonction, leur ID ni leurs mappings
(nom affiché uniquement) :
- Le module HTTP qui POST vers `rpc/record_sages` (il enregistre les propositions des Sages avec le
  `run_id`) — il n'a pas de nom alchimique → nomme-le, ex. « 📜 LE SCEAU DES SAGES » (ou « 🖋️ LE GREFFIER
  DU CONSEIL »).
- « Staking délais » (lit alc_staking_delais — le délai de déblocage) → ex. « ⛓️ LES CHAÎNES DU SCELLÉ ».
- « Staking APY » (lit alc_staking_apy — le rendement) → ex. « 🌾 LA RENTE DES SCELLÉS ».
- (Optionnel, pour l'harmonie) « L'Observatoire des Cours », « Le Coffre de la Crypte », « Le Décodeur
  des Avoirs » ont un nom thématique mais sans emoji — ajoute-leur un emoji cohérent si tu veux.
Choisis les noms définitifs comme tu le sens. Si tu repères tout autre module au nom par défaut
(« HTTP », « Make a request », nom vide) → donne-lui aussi un nom alchimique. Nom uniquement, rien d'autre.

────────────────────────────────────────
RÈGLES
────────────────────────────────────────
- Ne modifie QUE ces points. Ne change pas les IDs, ni les connexions/mappings, ni les autres prompts.
- Après coup, une exécution doit tourner sans erreur.
