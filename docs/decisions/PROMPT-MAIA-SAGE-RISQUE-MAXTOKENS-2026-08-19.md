# Prompt Maia — le Sage Risque casse le run (JSON tronqué) — module 205

> **Statut : PRÊT, non envoyé.** Cause d'échec du run manuel du 19/08 à 10:12.

## Diagnostic (prouvé, chiffré)

Le run lancé depuis la console à **10:12:54** a bien démarré, puis **a échoué à 10:13:03** :

```
DataError : Source is not valid JSON   —   module ParseJSON
19 opérations exécutées (un run complet en fait 76)
```

Le module qui casse est le **206 · 💧 DISTILLATION DU RISQUE**, qui parse la sortie du
**205 · ⚔️ IRON SENTINEL (Sage Risque)**.

### Pourquoi le JSON est invalide : il est coupé en plein milieu

Le module 205 est plafonné à **`max_tokens: 800`** — le plus bas des cinq Sages — alors qu'il produit
**la sortie la plus longue de tous**. Comparaison mesurée sur les 7 derniers jours :

| Sage | Modèle | `max_tokens` | Sortie max observée | Marge |
|---|---|---|---|---|
| **Risque (205)** | mistral-large-latest | **800** | **2 948 car. ≈ 819 tokens** | ❌ **dépassé** |
| Technique (203) | gpt-oss-120b | 2000 | 1 246 car. ≈ 346 tokens | ✅ 5,8× |
| Macro (201) | sonar-pro | 1500 | 1 447 car. ≈ 402 tokens | ✅ 3,7× |
| Flash (209) | sonar-pro | 1500 | 521 car. ≈ 145 tokens | ✅ 10× |
| Mémoire (207) | gpt-oss-120b | 2000 | 439 car. ≈ 122 tokens | ✅ 16× |

Historique des sorties du Sage Risque — elles ont **grossi** et tapent maintenant le plafond :

| Quand | Tokens estimés | |
|---|---|---|
| 14/08 19:15 | 288 | ok |
| 15/08 10:36 | 333 | ok |
| 17/08 17:33 | 774 | ⚠️ au plafond |
| 17/08 18:11 | 785 | ⚠️ au plafond |
| 17/08 19:59 | 791 | ⚠️ au plafond |
| 17/08 20:55 | **819** | ⚠️ **dépassé** |
| 18/08 14:29 | 766 | ⚠️ au plafond |

Quand le modèle dépasse 800, sa réponse est tronquée en plein milieu d'une chaîne → JSON invalide →
le module 206 plante → **tout le run s'arrête**. D'où l'intermittence : échecs les **18/08 16:31**,
**19/08 07:04** et **19/08 10:13**, succès entre les deux.

### Pourquoi la sortie est si longue : 8 champs sur 16 ne servent à personne

Le schéma déclaré du Sage Risque contient **8 champs courts**. Mais le prompt en réclame **8 de plus** :

- explicitement : « AJOUTE AU SCHEMA : `take_profit_multiplier`, `use_bracket_orders`, `max_notional_per_trade` »
- implicitement, via le bloc LANGUE : `prophet_vision`, `portfolio_rationale`, `rationale`,
  `memory_summary`, `evaluations` — cinq **textes libres en français**, très coûteux en tokens.

**Vérification faite dans tout le scénario** : le module **215 · 🔮 LA MATRICE DES SIGNAUX** — le seul
consommateur de la sortie du Sage Risque — ne lit **que les 8 champs du schéma** :

```
206.risk_level  206.risk_score  206.sizing_multiplier  206.max_single_position_pct
206.cash_floor_pct  206.crypto_max_pct  206.drawdown_alert  206.hedge_recommendation
```

Les 8 autres champs ne sont lus **nulle part**. Le modèle brûle donc la moitié de son budget de tokens
à écrire du texte que la chaîne ignore — et c'est précisément ce qui fait déborder le plafond.

## Décision retenue : lever le plafond ET encadrer les textes

On **garde** les champs de raisonnement (`prophet_vision`, `rationale`…) : ils ne servent pas au pipeline
mais ils sont **affichés dans la console AETHER** (dossier du Sage) et expliquent ses décisions.
En revanche on les **borne**, pour que la panne ne puisse pas revenir.

## Prompt à envoyer à Maia

```
Bonjour Maia. Le run du 19/08 à 10:12 a échoué : "Source is not valid JSON" au module 206
(💧 DISTILLATION DU RISQUE). La cause est le module 205 (⚔️ IRON SENTINEL, Sage Risque) : il est
plafonné à max_tokens 800 alors que sa réponse atteint 819 tokens, donc le JSON est coupé en plein
milieu et le parsing échoue. C'est arrivé aussi les 18/08 à 16:31 et 19/08 à 07:04.

Ne modifie QUE le module 205. Deux changements :

1) Dans le corps de la requête, remplace :
     "max_tokens": 800
   par :
     "max_tokens": 2000
   (c'est la valeur déjà utilisée par les modules 203 et 207, qui ne plantent jamais)

2) Dans le message "system" du module 205, remplace la phrase qui commence par "LANGUE :" par
   celle-ci, qui borne la longueur des textes pour que la réponse ne puisse plus déborder :

LANGUE : les valeurs des champs texte du JSON (prophet_vision, portfolio_rationale, rationale, memory_summary, evaluations) doivent etre redigees en francais clair et faire 200 caracteres maximum chacune. Ne change rien au format JSON, ni aux cles, ni aux tickers. Ne renvoie AUCUN texte en dehors de l objet JSON.

Ne touche à rien d'autre : ni le modèle mistral-large-latest, ni la température, ni le response_format,
ni le schéma, ni les autres règles du prompt, ni aucun autre module (surtout pas 206, 207, 20022, 20023).

Puis SAUVEGARDE le scénario, et confirme-moi que max_tokens vaut bien 2000 sur le module 205.
```

## Vérification après application

- Relire le blueprint : `max_tokens` = 2000 sur le 205, aucun autre module modifié.
- Lancer un run : il doit dépasser 19 opérations et aller jusqu'au bout (~76).
- Contrôler en base : nouvelle ligne dans `oracle_sages_report` pour `Risque`, nouvelle ligne dans
  `oracle_college_runs`, et — enfin testable — de nouvelles lignes dans `alc_destake_reco`
  (le correctif de clé staking du 10:06 n'a **jamais pu être testé**, le run mourant avant d'atteindre
  les modules 20022/20023).

## Deux points annexes constatés sur ce run (aucun n'est une panne)

### « dust_unsellable » dans le journal de debug

C'est le message normal du système face aux **poussières crypto** : des reliquats de positions à quantité
quasi nulle (`0,000000001` SOL, XRP, BTC) qu'Alpaca refuse de vendre car sous le minimum négociable.
Le système les **saute proprement à chaque run** — c'est le comportement voulu, pas une erreur.
Ce sont exactement les lignes fantômes déjà filtrées côté console le 19/08.
Le seul vrai défaut est cosmétique : elles polluent le compteur « ignorés » de chaque run.
Un nettoyage côté Alpaca (vente forcée ou radiation) les ferait disparaître définitivement.

### Aucun message Discord

Normal : le module Discord (**10031**) se situe tout à la fin de la chaîne. Le run s'étant arrêté à la
19ᵉ opération, il n'a jamais été atteint. Le Discord reviendra dès que le run ira au bout.

### La console a, elle, parfaitement fonctionné

`v_scenario_etat` confirme : run déclenché à **10:12:54**, coupure automatique appliquée à **10:20:00**.
Le mécanisme /start + arrêt différé a fait exactement son travail. L'absence de run dans la liste de la
console vient du fait que `oracle_college_runs` n'est écrit qu'en fin de chaîne — jamais atteinte.
