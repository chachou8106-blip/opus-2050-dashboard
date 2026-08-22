# Outils de vérification

## audit-console-rendu.mjs — charger la console pour de vrai

Vérifier une console en lisant son code ne suffit pas : les défauts qui gênent
à l'usage sont des **valeurs fausses**, pas des blocs manquants, et on ne les
voit qu'en la faisant tourner. Ce script charge `aether.html` dans Chromium,
intercepte tous les appels réseau et leur répond avec de vraies données
extraites de Supabase (dans `mock/`), puis liste :

- les erreurs JavaScript ;
- les conteneurs vides, remplis de tirets, ou contenant `undefined` / `NaN` ;
- le contenu de chaque tableau et de chaque tuile, onglet par onglet.

### Précautions apprises à la dure

- **Servir la page en HTTP**, pas via `setContent` : `about:blank` refuse
  `sessionStorage` et interrompt le déverrouillage des zones scellées.
- **Forcer `timezoneId: 'Europe/Paris'`** : sans cela le conteneur est en UTC
  et toutes les heures paraissent fausses de deux heures. Quatre faux positifs
  ont été signalés à tort avant que ce réglage soit ajouté.
- **Échantillonner les mocks par groupe**, pas par `limit` global : un
  `order by periode desc limit 40` sur `v_rendements_periodes` ne ramène qu'une
  seule granularité, et le tableau « Performance dans le temps » paraît vide
  alors qu'il fonctionne.
- **Appeler `unlockedOK()`** pour les onglets Journal et Ops : masquer le
  cadenas ne charge pas leurs données, et leurs tuiles paraissent vides.
- **Chercher `NaN` en respectant la casse** : `/NaN/i` attrape « décisions
  gag**nan**tes » et fait passer pour cassé un rendu parfaitement correct
  (les circuit breakers ont été signalés « BRUT » trois fois pour cette raison).
- **Ne pas tirer les mocks à travers `content::jsonb`** : Postgres réordonne
  les clés d'un objet JSON, donc l'ordre des colonnes observé dans le banc
  d'essai n'est pas celui du navigateur. Corollaire utile : `autoTable()` trie
  désormais les colonnes d'identité en tête, l'ordre ne dépend plus de la source.
- **Ne pas déclencher les 26 actions d'`oracle-tests` en rafale** : les appels
  concurrents font dépasser le `statement_timeout` de 8 s à
  `dashboard_snapshot()`, et l'action `snapshot` revient avec des indicateurs
  sans valeur. Appelée seule, elle renvoie ses 27 lignes. Un défaut a été
  diagnostiqué à tort avant cette vérification.

### Console de tests

`tests.mjs` (même dossier de travail) clique les **26 boutons** de la console de
tests et vérifie, pour chaque modale, qu'elle n'est ni vide, ni brute, ni en
erreur. C'est le seul moyen de voir ces rendus : ils ne s'exécutent qu'au clic,
et l'audit de page ne les atteint jamais.

### Utilisation

    node docs/outils/audit-console-rendu.mjs

Les mocks se régénèrent en interrogeant Supabase ; leur chemin est en tête du
script.
