# Passage au réel — checklist argent réel

> Cadre de sécurité pour engager (ou augmenter) du capital réel sur l'Alchimiste (Revolut X, au
> comptant). À relire à chaque montée en charge. Rien ici ne doit être fait sans l'accord explicite
> de Chachou. Voir `ARCHITECTURE.md` et `RUNBOOK.md`.

---

## Principe
Le passage au réel est **progressif, une stratégie à la fois**, et **seulement après validation en
simulation**. Aujourd'hui, seul l'**Alchimiste** est candidat au réel (Revolut X, spot). JU/SYL/GIL
et Marées restent en simulation.

## Garde-fous structurels déjà en place
- **Au comptant uniquement** (Revolut X) : pas de levier, pas de short → **aucune liquidation forcée**.
  Perte maximale = capital engagé.
- **Kill-switch** (`ju_crypte_config.kill_switch`) : OFF = aucun ordre réel. OFF toujours libre
  (anti-lockout). ARMER exige PIN ou Face ID. Voir `README-KILLSWITCH.md`.
- **`dry_run`** sur `alc-auto` : `true` = simulation, aucun ordre réel envoyé.
- **Plafonds argent** dans `revolut-x-trade` : l'achat est plafonné au cash USD disponible ; la vente
  au seul actif détenu et **liquide** (hors staking).

## Avant d'armer (checklist)
- [ ] Le kill-switch est **compris** par l'opérateur (OFF = sûr, à tout moment).
- [ ] `v_data_health` est **tout au vert** (prix, univers, portefeuille, propositions à jour).
- [ ] Le scénario Make 6183820 tourne **vert** (dernières exécutions sans erreur).
- [ ] Les propositions s'enregistrent **avec toutes les colonnes** (paire/side/montant/prix_ref) :
      `select * from alchimiste_crypte_propositions order by id desc limit 5;`
- [ ] Le portefeuille papier de l'Alchimiste **apprend** (trades virtuels récents,
      `v_alc_virtuel_resume`, WR raisonnable).
- [ ] Les **règles spot** sont respectées par l'IA (achat cash USD ; vente actif détenu liquide ;
      pas de vente d'un actif staké).
- [ ] Le **montant par trade** est borné et cohérent avec le capital réel.
- [ ] Un **petit test** en réel (montant minime) a été validé avant toute montée en charge.
- [ ] REVX_API_KEY / REVX_PRIVATE_KEY valides ; `revolut-x-read` renvoie bien les soldes réels.

## Indicateurs de qualité à surveiller (avant/pendant le réel)
- **Win rate** et surtout **asymétrie gain moyen / perte moyenne** de l'Alchimiste
  (`oracle_brain_state` CRYPTE_JU). Au 14/08 : WR 38,5 %, gain moy +0,56 % vs perte moy −2,84 %
  → **discipline de sortie à corriger avant d'augmenter le capital réel.**
- **Liquidité / spread** : éviter les micro-cryptos illiquides (pertes historiques dues au spread).
- **Corrélation** entre stratégies (décorrélation = protection du portefeuille).
- **Staking** : dé-staker coûte un délai de déblocage — ne le recommander que si le gain de trade
  attendu dépasse le rendement de staking abandonné (`v_staking_point`, `alc_destake_reco`).

## En cas de doute
Passer le kill-switch sur **OFF** (toujours autorisé). Aucun ordre réel ne partira. Puis diagnostiquer
à froid avec le RUNBOOK.

## Montée en charge (règle)
Le capital augmente **au rythme des résultats prouvés**, stratégie par stratégie. Les gains sont
destinés à être réinvestis dans un fonds dédié (feuille de route AETHER). Ne pas accélérer sur la
base d'un historique court (< 6–12 mois) : les métriques (Sharpe/Sortino/Calmar) ne se stabilisent
que dans la durée.
