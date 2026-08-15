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
exactement sur le modèle des Sages. Les Sages utilisent :
   {{ ... brain_states.SYL.current_bias ... }}  (nettoyé des guillemets et retours ligne)
Fais de même pour Marées, avec le champ :
   brain_states.MAREES.current_bias
(disponible dans le même module de cerveaux — celui qui expose déjà `brain_states.MAREES.latest_web_catalysts`).
Injecte-le sous une étiquette claire, ex. :
   MEMOIRE_MAREES={{ (nettoyage guillemets/retours-ligne de) brain_states.MAREES.current_bias }}
Et dans le texte système de Marées, ajoute une phrase : « Tiens compte de MEMOIRE_MAREES (ta doctrine
apprise) pour corriger tes erreurs passées. »

────────────────────────────────────────
2) CALIBRAGE DE LA SORTIE (dans les instructions du prompt de Marées)
────────────────────────────────────────
Le forex bouge peu (~0,5 %/jour). Les sorties doivent être atteignables. Dans le texte système de
Marées, remplace les consignes de TP/SL par :
- TAKE-PROFIT visé ≈ 1,2 % ; STOP-LOSS ≈ 0,8 % (ratio gain/risque ~1,5:1). Ce sont des ordres de
  grandeur adaptés au forex sur une détention de 2 à 4 jours — pas 3 %/2 % (quasi jamais touchés).
- Demande au modèle de fournir `tp_pct` et `sl_pct` cohérents avec ça (autour de 1,0–1,5 % / 0,6–1,0 %).
- DIVERSIFICATION : ne pas empiler plusieurs positions du MÊME SENS sur des paires corrélées (ex. ne
  pas être vendeur simultanément de GBP-JPY, USD-JPY, EUR-JPY = un seul gros pari « short JPY »).
  Max ~2 positions même sens sur un groupe corrélé (même devise de base ou de contrepartie).
(Côté base, les seuils de simulation ont été alignés en conséquence — inutile d'y toucher.)

────────────────────────────────────────
3) RENOMMER LES MODULES SANS NOM ALCHIMIQUE
────────────────────────────────────────
Presque tous les modules ont un nom thématique (« 🌙 L'ARCHIMAGE DES MARÉES », « 💎 LE REGISTRE DE
CRISTAL », « 📜 LE GRIMOIRE DES AVOIRS »…). Deux modules gardent un nom générique — renomme-les dans
le même univers alchimique, SANS changer leur fonction, leur ID, ni leurs mappings (juste le nom
affiché) :
- « Staking délais » (le module qui lit alc_staking_delais — le délai de déblocage) →
  suggestion : « ⛓️ LES CHAÎNES DU SCELLÉ » (ou « ⏳ LE SABLIER DES SCELLÉS »).
- « Staking APY » (le module qui lit alc_staking_apy — le rendement) →
  suggestion : « 🌾 LA RENTE DES SCELLÉS » (ou « 💠 LA DÎME ALCHIMIQUE »).
Choisis les noms définitifs comme tu le sens pour rester cohérente avec le reste. Et si tu repères
tout autre module ayant encore un nom par défaut (« HTTP », « Make a request », un nom vide, etc.),
donne-lui aussi un nom alchimique cohérent — même règle : nom uniquement, rien d'autre.

────────────────────────────────────────
RÈGLES
────────────────────────────────────────
- Ne modifie QUE ces points. Ne change pas les IDs, ni les connexions/mappings, ni les autres prompts.
- Le contre-pied de Marées (on trade l'inverse du signal) est géré côté base — n'y touche pas.
- Après coup, une exécution doit tourner sans erreur.
