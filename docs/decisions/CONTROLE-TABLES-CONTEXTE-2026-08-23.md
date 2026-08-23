# Tables de contexte — contrôle et corrections, 23/08/2026

Tout ce qui suit a été **appliqué**. Rien n'est en attente.

---

## 1. Ma leçon du 15/08 partait encore dans le prompt de SYL — supprimée

`CLAUDE.md` affirmait que la « leçon épinglée » avait été retirée le 20/08. **Faux.** Le retrait
avait porté sur `oracle_brain_state.learnings`, alors que `get_oracle_context()` construit le bloc
`learnings` à partir de **`brain_lessons`** :

```sql
'learnings', COALESCE((SELECT jsonb_agg(...) FROM public.brain_lessons bl
                       WHERE bl.archimage = oracle_brain_state.archimage
                         AND bl.bias IS NOT NULL AND bl.bias <> ''), learnings)
```

La ligne y était restée : `archimage=SYL`, `run_id=lecon-manuelle-20260815`,
`eval="lecon manuelle Chachou"` — un texte de ma composition attribué à Chachou, seul des
338 enregistrements dont le `run_id` ne suit pas le format d'un vrai run.

**Supprimée**, sauvegarde `bak_20260823_lecon_manuelle`. SYL passe de 63 à 62 leçons injectées.

---

## 2. Le contexte injecté aux agents : 92 ko → 67 ko

`get_oracle_context()`, quatre corrections :

| Ce qui n'allait pas | Corrigé en |
|---|---|
| Bloc `learnings` sans `LIMIT` ni `ORDER BY DESC` : il prenait **toutes** les lignes de `brain_lessons`, 63 par agent, +16/jour, sans fin | 30 leçons les plus récentes |
| Bloc `mistakes_history` : même défaut | 20 erreurs les plus récentes |
| `alpaca_drawdown` transmettait la colonne cassée — GIL recevait 0,59 % | la mesure retenue (voir §3) |
| `active_circuit_breakers` filtrait `fired_at > now() - 24 heures` : les trois coupe-circuits **non résolus** des 20 et 21/08 avaient disparu, le bloc renvoyait `[]` | fenêtre de 30 jours — les 3 sont transmis |

Avant : 82,3 % du contexte était de la mémoire, et les quatre blocs de sécurité pesaient
2 octets chacun.

---

## 3. Le drawdown — une seule règle partout

`sync_alpaca_positions` calculait le « pic » ainsi :

```sql
SELECT COALESCE(MAX(alpaca_portfolio_value), v_portfolio_value) INTO v_peak_value
FROM oracle_brain_state WHERE archimage = v_archimage;
```

`oracle_brain_state` n'a **qu'une ligne par archimage** : ce `MAX()` rendait la valeur de la
veille. La colonne mesurait l'écart depuis la dernière synchro, plancher à zéro — pas un
drawdown. Corrigé : le pic vient de `alpaca_equity_daily`, borné par la valeur du jour.

Il reste deux mesures, et **aucune n'est fausse** — elles regardent des fenêtres différentes :

| | fenêtre | GIL | SYL | JU |
|---|---|---|---|---|
| `current_drawdown` (update-brain) | le mois renvoyé par l'API Alpaca | 6,26 % | 3,80 % | 0,36 % |
| `alpaca_drawdown_from_peak` (sync) | pic all-time sur `alpaca_equity_daily` | **11,03 %** | 2,20 % | 0,84 % |

Un garde-fou retient la plus prudente. Règle appliquée dans `iron_sentinel_validate_order`,
`dashboard_snapshot`, `get_oracle_context` et `oracle-tests` v16 : **l'écran, les prompts et la
sentinelle disent désormais le même chiffre.**

**Conséquence à connaître : GIL est à 11,03 % de son plus haut du 25/07, au-dessus du seuil de
8 %. Dès la reprise du scénario, la sentinelle lui refusera toute OUVERTURE de position.** Il
pourra toujours liquider — la règle est `IF v_drawdown >= 0.08 AND NOT p_is_liquidation`. C'est
le comportement voulu d'un coupe-circuit, et il était neutralisé depuis le début : sur les
7 derniers jours, 116 ordres, 116 exécutés, 0 rejeté.

---

## 4. `oracle_contexte` — 6 fiches sur 28 réécrites

Cette table n'atteint aucun prompt (vérifié : seul `oracle-inbox` la lit, pour l'onglet Journal).

| Fiche | Disait | Dit maintenant |
|---|---|---|
| `EXECUTION/config` | `allowed_pairs` = « SOL,TON,ATOM,TRX » | `*`, et pourquoi : `alc-auto` v6 a remplacé la whitelist statique — qui pointait des coins **stakés donc invendables** — par une tradabilité calculée en direct |
| `EXECUTION/verrous` | « État actuel : kill_switch=**ON** » | `OFF` sur `ju_crypte_config` **et** `marees_config` : aucun ordre réel ne part |
| `CONSOLE/fichier` | « console_opus.html » | `aether.html`, servi par Netlify sur `main` ; `console_opus.html` est dans `legacy/` |
| `CONSOLE/oracle-inbox` | « périodes (v_rapport_periodes) » | `v_rendements_periodes` ; `v_rapport_periodes` n'est jamais appelée |
| `VUES/v_equity_points` | « JU/SYL/GIL=oracle_performance, ALCHIMISTE=… » | `v_equity_journalier` pour les trois ; `ALC_REEL` / `ALC_VIRT` ; plus rien ne s'appelle `ALCHIMISTE` |
| `TRADERS/SYL` | « Meilleure perf cumulée actuellement » | classement retiré — vrai un jour, faux le lendemain, invisible |

Deux fiches vérifiées exactes et laissées telles quelles : `FAITS/staking_delais` (correspond
ligne pour ligne à `alc_staking_delais`) et `EXECUTION/cron_indices` (job pg_cron 23).

---

## 5. `CLAUDE.md` — la liste des canaux était incomplète

C'est elle qui m'a fait nettoyer la mauvaise table le 20/08. Complétée avec :

- **`brain_lessons.bias` / `.eval`** — la vraie source des blocs `learnings` et
  `mistakes_history` ; `oracle_brain_state` ne sert que de repli.
- Les quatre consignes qui vivent **dans le code des edge functions**, hors du canal Maia :
  `collect-market-data` (le champ `directive` + 3 prompts système Perplexity),
  `marees-context` (prompt système complet de l'Archimage des Marées), `fx-context`.
- Le fait que **deux chemins écrivent `current_bias` avec des règles opposées** :
  `update-brain` tronque à 260 caractères et garde 30 leçons, `batch_write_college_run_v2`
  (la RPC appelée par Make) ne tronque pas et empile. C'est par là que `JU.current_bias` a
  atteint 1 132 caractères.

---

## Autres tables contrôlées, sans écart

| Table | Lignes | État |
|---|---|---|
| `ju_crypte_config` | 7 | conforme ; contient `arm_pin = 2050` **en clair**, hors Vault |
| `marees_config` | 4 | conforme — kill_switch OFF, 10 paires, 5 %/position, 50 % brut |
| `fonds_config` | 6 | conforme — inactif, calcul seulement, 50 % des gains |
| `alc_staking_delais` | 8 | exacte |
| `oracle_runs` | 1 | sorties de run, pas du contexte injecté |
| `_ju_brain_backup`, `bak_20260813_brain_alc_marees` | — | sauvegardes, non lues |

Ni `marees_config` ni `fonds_config` n'ont de fiche dans `oracle_contexte`, alors que
`ju_crypte_config` en a une. Non ajouté : je n'écris pas de nouvelle fiche sans qu'on me le
demande.
