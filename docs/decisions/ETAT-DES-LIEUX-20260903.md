# État des lieux avant le week-end — 03/09/2026

Audit complet demandé par Chachou avant de laisser tourner jusqu'à mardi.
Tout est mesuré. Rien n'est supposé.

---

## 1. Pourquoi l'Alchimiste virtuel est bon et le réel mauvais

**Parce que le réel n'a jamais tradé.** Pas une seule fois.

```sql
select statut, count(*) from alchimiste_crypte_propositions where paire is not null group by statut;
  expiree    62
  proposee    1
```

```
propositions validées par Chachou (oui_at)  :  0
propositions exécutées (prix_exec)          :  0
durée de vie d'une proposition              :  360 minutes = 6 heures
```

**63 propositions depuis le 13/08. Zéro exécutée. Toutes expirées au bout de 6 heures.**

Et la cause est en une ligne :

```sql
select value from ju_crypte_config where key='kill_switch';  ->  OFF
```

`revolut-x-trade` n'envoie un ordre réel que si `kill_switch = 'ON'`. Il est sur
**OFF depuis toujours** — c'est le verrou de sécurité, et il fait exactement son
travail. Aucune proposition ne peut partir.

### Ce que les deux portefeuilles mesurent réellement

| | Virtuel (`alchimiste_virtual_trades`) | Réel (Revolut X) |
|---|---|---|
| Trades depuis le 13/08 | **59** | **0** |
| Clos | 57 | — |
| TP / SL | 5 % / 4 %, appliqués **automatiquement** | jamais posés |
| Rendement | **+10,12 %** | **−2,65 %** |
| Réussite | **77,8 %** | pas de trade à noter |
| Valeur | aucune (symbolique) | 939,41 $ |

Les deux partent des **mêmes décisions** — l'Alchimiste propose, et le virtuel
enregistre chaque proposition pour la noter. Mais ensuite :

- le **virtuel** l'exécute immédiatement au prix proposé, et la ferme tout seul
  dès que TP 5 % ou SL 4 % est touché ;
- le **réel** ne fait rien. Sa performance de −2,65 % est celle de ses cryptos
  dormantes et de son staking, pas celle de l'Alchimiste.

Origine 557,18 $ + apports 379,00 $ = 936,18 $ versés, valeur actuelle 939,41 $.

**Donc non, ce ne sont pas les mêmes.** Le virtuel mesure la stratégie ;
le réel mesure un portefeuille qui dort.

### Pour passer des trades en vrai

Le verrou est `kill_switch`. Le passer sur `ON` arme l'exécution réelle sur
Revolut X — et à partir de là, les propositions partent **automatiquement**,
sans validation manuelle, dans les 6 heures.

**Je ne le touche pas** : c'est la règle, et elle est bonne. Si tu veux
commencer, deux façons :

1. **À la main, sans rien armer** — l'Alchimiste te donne déjà tout ce qu'il
   faut : paire, sens, montant, `prix_ref`. Tu reproduis sur Revolut X, et tu
   poses le TP à +5 % et le SL à −4 % du prix d'entrée, comme le virtuel.
   Zéro risque de dérive, tu gardes la main.
2. **Armer le kill-switch** — l'exécution devient automatique. À décider en
   connaissance de cause, et pas un vendredi avant un week-end sans surveillance.

---

## 2. La console — ce qui marche, ce qui décroche

### Les 26 fonctions de la console de tests : toutes vivantes

Appelées une par une avec la clé `anon` du fichier. **26 sur 26 en 200**, toutes
avec des données réelles :

| Bloc | Retour |
|---|---|
| sages | 5 lignes |
| coaching | 5 notes (Mémoire 81,4 % · Macro 59,5 % · Technique 58,8 % · Risque 55,7 % · Flash 52,3 %) |
| alchimiste / marées | objets complets |
| **dossiers Archimages** | JU 7 090 o · SYL 5 724 o · GIL 6 372 o |
| **dossiers Sages** | Macro 9 808 o · Technique 7 538 o · Flash 27 410 o · Risque 26 263 o · Mémoire 14 935 o |
| positions | 68 lignes |
| runs | 40 lignes |
| equity / hero / kelly / directional / learning | objets complets |
| bt_alchimiste / bt_exits | 48 lignes chacun |
| bt_archimages / breakers / friction | 3 lignes chacun |
| sante_sources | 16 lignes |
| snapshot | 27 lignes |

**Aucun bloc vide, aucune erreur.** Tes Sages et tes Archimages ont bien tous
leurs dossiers.

### Ce qui décroche : le planificateur

C'est la conséquence directe de ton changement — tu as mis le planificateur dans
Make, donc la table `scenario_control` n'est plus mise à jour par personne.

```
scenario-switch  ->  maitre_on      : false
                     last_action    : "stop"
                     last_action_at : 2026-08-22 22:04   (il y a 12 jours)
                     dernier_run    : 2026-08-21 19:15   (il y a 13 jours)
                     heures         : 09h00 · 15h45 · 18h30 · 21h15
```

Alors que la réalité est :

```
dernier run réel (oracle_college_runs)  :  2026-09-03 10:15:24
minutes_depuis_dernier_run              :  104
```

**Trois affichages sont donc faux dans la console :**

| Panneau | Ce qu'il montre | La réalité |
|---|---|---|
| Onglet Commandes, `scenChip` | ● **Coupé** | le scénario tourne |
| Audit, « Planning scénario » | **coupé** | actif, dans Make |
| Audit, « Dernier run déclenché » | **21/08 19:15** | 03/09 10:15 |

Le bandeau du haut, lui, est juste : `rEtatCollege()` regarde d'abord
`minutes_depuis_dernier_run` (104 ≤ 180) et affiche « Collège actif » —
il ne tombe sur `maitre_on` que si le dernier run date de plus de 3 heures.

### Face ID : le serveur répond correctement

```
ju-passkey action unlock-options  ->  200
  rpId              : oracle-financier.netlify.app
  allowCredentials  : 1 clé enregistrée (transports internal, hybrid)
  challenge         : présent
  userVerification  : preferred
```

Rien de cassé côté serveur. Si ça déconne, c'est **côté navigateur**, et la
piste la plus probable est le `rpId` : la passkey n'est valable que sur
**`oracle-financier.netlify.app`** exactement. Elle échoue si tu ouvres la
console depuis une autre adresse (aperçu Netlify, autre domaine, IP), depuis un
autre appareil que celui où tu l'as enregistrée, ou depuis un navigateur qui ne
partage pas ce trousseau.

Le repli PIN reste disponible dans tous les cas.

### Kill-switch

```
ju_crypte_config.kill_switch  ->  OFF     (verrou en place, aucun ordre réel ne part)
```

Cohérent avec le point 1.

---

## 3. Ce qui reste ouvert

| Sujet | État |
|---|---|
| Module 10031, séparateurs `" — "` | fiche `AF`, pas encore appliquée — tes ordres sortent collés dans Discord |
| `scenario_control` figé au 22/08 | à reconnecter au planificateur Make, ou à retirer de la console |
| Poussières Alpaca 1e-9 | impossibles à fermer (minimum d'ordre 2e-9), filtrées côté agents depuis aujourd'hui |
| Coupe-circuit GIL `drawdown_8pct` | actif depuis le 25/08 |

---

## 4. Ce qu'il faut surveiller jusqu'à mardi

Les trois corrections de ce matin n'ont chacune qu'**un seul run** derrière elles
(10:15). Ce qui vaut la peine d'être regardé mardi :

- le **Sage Mémoire** tient-il sur plusieurs runs avec son `responseSchema` ?
  (`v_sages_pannes` doit rester à 0 run muet consécutif)
- l'**Alchimiste** produit-il un JSON valide à chaque fois depuis le retrait du
  `commentaire` ? (une proposition enregistrée par run)
- les **runs** montent-ils bien à 76 opérations ?
- le **P&L lu par JU et GIL** reste-t-il propre maintenant que les poussières
  sont filtrées (JU 8 220 $, GIL 26 682 $, et non plus 144 881 $ et 215 007 $)
