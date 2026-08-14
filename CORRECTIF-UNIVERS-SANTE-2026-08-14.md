# Univers Revolut X + alerte santé — clarification & correctif (14/08/2026)

## Le constat (« réactive le rafraîchissement de l'univers »)
Il n'y avait **aucun rafraîchissement à réactiver**. L'alerte « Univers Revolut X (tickers) —
figé depuis 37 j » pointait sur une table **abandonnée**.

Vérifications en base (projet `smddzybxebwhfnitxuyp`) :
- `revolut_univers_complet` : 303 lignes, **dernière écriture 07/07/2026**, plus jamais mise à jour.
- **Aucun** job pg_cron, **aucune** edge function, **aucun** scénario ne l'alimente.
- Seuls deux objets la lisent encore : ma vue `v_data_health` (l'alerte) et la fonction
  `flash_route` (routage crypto, avec repli sur une liste de majors → dégradation sans casse).

L'univers **réel et vivant** a migré depuis longtemps vers `price_history`, alimentée **chaque
heure** par les ingests (klines / gate / revx) :
- **311 symboles distincts rafraîchis sur les 3 dernières heures** (324 au total) — plus large
  que la vieille table ne l'a jamais été.

## Le correctif appliqué (migration `v_data_health_repoint_univers_to_live`)
La ligne d'alerte « univers » ne surveille plus la table morte mais la **vraie source live** :
> dernière heure où l'univers complet (≥ 200 symboles distincts) a été rafraîchi dans
> `price_history` (seuil 6 h).

Résultat : la ligne « Univers tradable (live) » passe **OK** (≈ 1 h). Fini la fausse alerte des
37 jours. Si un jour l'ingestion casse pour de vrai (univers qui rétrécit), l'alerte se
redéclenchera — cette fois à juste titre.

## Ce qui reste FIGE (à raison)
« Propositions Alchimiste » reste **FIGE (~20 h)** : c'est la conséquence directe du plantage du
scénario Make 6183820 (voir `PROMPT-MAIA-ALCHIMISTE-JSON-2026-08-14.md`). Cette alerte est
**vraie** et se résorbera d'elle-même dès que Maia aura corrigé le module 10012 et que
l'Alchimiste tournera de nouveau.

## Option (non appliquée, pour info)
`flash_route` gagnerait à lire l'univers live (`price_history`) plutôt que la table morte, pour
router correctement les cryptos listées après le 07/07. Changement fonctionnel à part — non
touché ici sans ton feu vert.
