# Prompt Maia — brancher l'Alchimiste sur UNE source de staking (fin du feuilleton)

> **Statut : PRÊT. Tout est testé end-to-end, rien n'est supposé.**

## Pourquoi trois jours de tours en rond

Le dé-staking dépendait de **trois sources séparées** que le modèle devait recroiser lui-même :

| Donnée | D'où elle venait | Résultat |
|---|---|---|
| Délai de déblocage | module 20022 | jamais transmis correctement → **0 partout** |
| APY | module 20023 | correct depuis la réparation de la clé |
| Montant staké | extrait d'un gros bloc de texte (`soldes_texte`) | **inventé** : TON 787 $ écrit pour 7,91 $ réels |

Chaque correctif n'en réglait qu'un morceau, et le dernier (retrait du Base64) a cassé les montants
parce que les textes contenaient des `|`, séparateur de champs du message. **La cause de fond n'était
pas l'encodage : c'était de demander au modèle de faire une jointure à la main.**

## Ce qui a été fait côté Supabase (déjà en place, rien à faire)

1. Séparateur interne des vues staking : `|` → `;`. Plus aucune collision possible.
2. **Nouvelle vue `v_alc_staking_txt`** : une ligne par devise stakée, avec montant réel, APY et délai.
   Le modèle n'a plus rien à croiser ni à deviner.

### Mesures réelles (pas des suppositions)

| Contrôle | Résultat |
|---|---|
| Temps d'exécution | **13 ms** (1re version : 11 000 ms → HTTP 500 timeout, corrigée) |
| Appel HTTP avec les en-têtes exacts du module 20022 | **200 OK** |
| Présence de `\|` dans la réponse | **aucune** |
| Somme des 7 lignes | **150,99 $** contre **150,98 $** déclarés par Revolut — écart 1 centime |

### Contenu exact renvoyé (vérifié par appel réel)

```
SOL montant=90.27USD apy=6.16% deblocage=3jours ; ETH montant=27.02USD apy=2.45% deblocage=5jours ;
KSM montant=14.67USD apy=10.47% deblocage=7jours ; TON montant=7.91USD apy=17.67% deblocage=2jours ;
ATOM montant=5.87USD apy=21.06% deblocage=21jours ; OSMO montant=4.91USD apy=5.39% deblocage=14jours ;
TRX montant=0.34USD apy=3.26% deblocage=14jours
```

## Prompt à envoyer à Maia

```
Bonjour Maia. Dernière correction du dé-staking dans le scénario 6183820 (ZCT Oracle v5).
Deux modules à modifier : 20022 et 10012. Ne touche à AUCUN autre module.

1) MODULE 20022 (⛓️ LES CHAÎNES DU SCELLÉ) — change UNIQUEMENT l'URL :

   URL actuelle :
   https://smddzybxebwhfnitxuyp.supabase.co/rest/v1/v_alc_staking_delais_txt?select=delais_texte

   Nouvelle URL :
   https://smddzybxebwhfnitxuyp.supabase.co/rest/v1/v_alc_staking_txt?select=staking_texte

   Ne change RIEN d'autre sur ce module : ni la méthode GET, ni les en-têtes apikey, Authorization,
   Content-Type et Accept (application/vnd.pgrst.object+json), ni le timeout.

2) MODULE 10012 (L'Alchimiste de la Crypte) — dans le message "user", remplace exactement ce fragment :

   à chercher :
   STAKING_DELAIS={{ifempty(20022.data.delais_texte; emptystring)}}
   à remplacer par :
   STAKING={{ifempty(20022.data.staking_texte; emptystring)}}

   Ne touche à aucun autre champ du message user. Laisse notamment STAKING_APY, PRIX_REVOLUTX_B64,
   CTX_B64, SAGES_B64 et tous les AVIS_GIL_*_B64 exactement comme ils sont.

3) MODULE 10012 — dans le message "system", remplace ces deux phrases :

   à chercher :
   - Le champ PRIX_REVOLUTX_B64 est une chaîne Base64 : décode-la mentalement avant analyse. En revanche STAKING_DELAIS et STAKING_APY sont du TEXTE BRUT directement lisible, au format DEVISE:valeur séparé par des barres verticales (exemple : ATOM:21j | TON:2j pour les délais, ATOM:21.06% | TON:17.67% pour les APY). Utilise ces valeurs TELLES QUELLES, ne les décode pas. N'utilise JAMAIS tes connaissances générales pour l'APY ni pour les délais : si le champ est vide, dis-le explicitement au lieu de deviner, et n'écris jamais 0 par défaut.
   à remplacer par :
   - Le champ PRIX_REVOLUTX_B64 est une chaîne Base64 : décode-la mentalement avant analyse. Le champ STAKING est du TEXTE BRUT et constitue ta SEULE source pour le de-staking : il contient une entree par devise stakee, separees par des points-virgules, au format DEVISE montant=<nombre>USD apy=<nombre>% deblocage=<nombre>jours. Exemple reel : TON montant=7.91USD apy=17.67% deblocage=2jours ; ATOM montant=5.87USD apy=21.06% deblocage=21jours. Recopie ces trois nombres TELS QUELS dans montant_usd, apy_staking_pct et delai_deblocage_jours. N utilise JAMAIS tes connaissances generales ni le bloc SOLDES_REVOLUTX pour ces trois valeurs. Si le champ STAKING est vide ou vaut aucune ligne stakee, renvoie un tableau destake_recommande vide au lieu d inventer. N ecris jamais 0 par defaut.

   à chercher :
   - STAKING_DELAIS et STAKING_APY : texte brut des deux tables au format DEVISE:valeur | DEVISE:valeur, à joindre par devise de base. Le suffixe j signifie jours : ATOM:21j veut dire delai_deblocage_jours = 21. Le suffixe % est un pourcentage annuel : ATOM:21.06% veut dire apy_staking_pct = 21.06. Reporte ces nombres exactement dans le JSON de sortie.
   à remplacer par :
   - STAKING : une entree par devise stakee, deja jointe, rien a recouper. Le champ STAKING_APY reste disponible en confirmation mais STAKING fait foi en cas d ecart.

4) Ne change rien d'autre : ni le modèle sonar-pro, ni max_tokens 8000, ni la température, ni le
   schéma de sortie, ni les règles de trading, ni les modules 20023, 10011, 10014, 10023.

Puis SAUVEGARDE le scénario, et confirme-moi :
- l'URL du module 20022 pointe bien sur v_alc_staking_txt?select=staking_texte
- le message user du 10012 contient STAKING={{ifempty(20022.data.staking_texte; emptystring)}}
```

## Contrôle après le run (valeurs attendues, au centime près)

| Devise | montant_usd | apy_staking_pct | delai_deblocage_jours |
|---|---|---|---|
| SOL | 90,27 | 6,16 | **3** |
| ETH | 27,02 | 2,45 | **5** |
| KSM | 14,67 | 10,47 | **7** |
| TON | 7,91 | 17,67 | **2** |
| ATOM | 5,87 | 21,06 | **21** |
| OSMO | 4,91 | 5,39 | **14** |
| TRX | 0,34 | 3,26 | **14** |

Si un seul délai ressort encore à 0, ce n'est plus une question de format : ce sera le prompt du modèle,
et on le saura immédiatement.

## Note de méthode

Le module 20022 s'appelle toujours « LES CHAÎNES DU SCELLÉ » alors qu'il rapporte désormais tout le
staking, pas seulement les délais. Renommage volontairement **non demandé** : chaque modification Make
est un risque, et le nom n'a aucun effet fonctionnel.
