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

## ⚠️ 19/08 11:42 — Make a bloqué la 2ᵉ moitié : contournement par alias PostgREST

Maia a appliqué l'URL sur le module 20022, mais Make a **refusé** la modification du module 10012 :
il n'accepte pas une référence à `20022.data.staking_texte` tant qu'il n'a pas « appris » la nouvelle
structure de sortie du module amont.

**État actuel : cassé.** Le 20022 renvoie désormais la clé `staking_texte`, alors que le 10012 lit
toujours `20022.data.delais_texte` — qui n'existe plus. Un run maintenant donnerait un champ vide.

**Contournement, testé par appel HTTP réel (200 OK)** : PostgREST sait renommer une colonne à la volée
avec la syntaxe `alias:colonne`. En demandant `?select=delais_texte:staking_texte`, la réponse porte la
clé **`delais_texte`** — celle que Make connaît déjà — tout en contenant le texte complet :

```json
{"delais_texte":"SOL montant=90.27USD apy=6.16% deblocage=3jours ; ETH montant=27.02USD apy=2.45% deblocage=5jours ; …"}
```

Conséquence : **le mapping du module 10012 n'a plus besoin d'être modifié du tout**. Seules les phrases
du prompt système changent — du texte pur, que Make ne valide pas. Plus aucun blocage possible.

Le nom de variable reste `STAKING_DELAIS` alors qu'il porte tout le staking : c'est volontaire.
Le nom n'a aucun effet, seul compte ce que le prompt système en dit.

## Prompt à envoyer à Maia

```
Bonjour Maia. Suite de la correction du dé-staking, scénario 6183820. Make a bloqué la 2e partie
la dernière fois ; cette version contourne le problème et ne demande AUCUN nouveau champ.

Attention : le scénario est actuellement dans un état cassé. Le module 20022 renvoie la clé
staking_texte alors que le module 10012 lit encore 20022.data.delais_texte, qui n'existe plus.
Il ne faut pas lancer de run avant d'avoir appliqué ce qui suit.

1) MODULE 20022 (⛓️ LES CHAÎNES DU SCELLÉ) — change UNIQUEMENT l'URL :

   URL actuelle :
   https://smddzybxebwhfnitxuyp.supabase.co/rest/v1/v_alc_staking_txt?select=staking_texte

   Nouvelle URL :
   https://smddzybxebwhfnitxuyp.supabase.co/rest/v1/v_alc_staking_txt?select=delais_texte:staking_texte

   C'est un simple renommage de colonne côté API : la réponse portera de nouveau la clé
   delais_texte, celle que Make connaît déjà, mais elle contiendra le texte complet du staking.
   Ne change RIEN d'autre : ni la méthode GET, ni les en-têtes, ni le timeout de 120.

2) MODULE 10012 (L'Alchimiste de la Crypte) — NE TOUCHE PAS au message "user".
   Il doit rester exactement tel quel, avec STAKING_DELAIS={{ifempty(20022.data.delais_texte; emptystring)}}.
   Aucun nouveau champ à mapper, donc aucun blocage possible.

3) MODULE 10012 — dans le message "system" uniquement, remplace ces deux phrases :

   à chercher :
   - Le champ PRIX_REVOLUTX_B64 est une chaîne Base64 : décode-la mentalement avant analyse. En revanche STAKING_DELAIS et STAKING_APY sont du TEXTE BRUT directement lisible, au format DEVISE:valeur séparé par des barres verticales (exemple : ATOM:21j | TON:2j pour les délais, ATOM:21.06% | TON:17.67% pour les APY). Utilise ces valeurs TELLES QUELLES, ne les décode pas. N'utilise JAMAIS tes connaissances générales pour l'APY ni pour les délais : si le champ est vide, dis-le explicitement au lieu de deviner, et n'écris jamais 0 par défaut.
   à remplacer par :
   - Le champ PRIX_REVOLUTX_B64 est une chaîne Base64 : décode-la mentalement avant analyse. Le champ STAKING_DELAIS est du TEXTE BRUT et constitue ta SEULE source pour le de-staking : malgre son nom il contient TOUT, une entree par devise stakee, separees par des points-virgules, au format DEVISE montant=<nombre>USD apy=<nombre>% deblocage=<nombre>jours. Exemple reel : TON montant=7.91USD apy=17.67% deblocage=2jours ; ATOM montant=5.87USD apy=21.06% deblocage=21jours. Recopie ces trois nombres TELS QUELS dans montant_usd, apy_staking_pct et delai_deblocage_jours. N utilise JAMAIS tes connaissances generales ni le bloc SOLDES_REVOLUTX pour ces trois valeurs. Si le champ est vide ou vaut aucune ligne stakee, renvoie un tableau destake_recommande vide au lieu d inventer. N ecris jamais 0 par defaut.

   à chercher :
   - STAKING_DELAIS et STAKING_APY : texte brut des deux tables au format DEVISE:valeur | DEVISE:valeur, à joindre par devise de base. Le suffixe j signifie jours : ATOM:21j veut dire delai_deblocage_jours = 21. Le suffixe % est un pourcentage annuel : ATOM:21.06% veut dire apy_staking_pct = 21.06. Reporte ces nombres exactement dans le JSON de sortie.
   à remplacer par :
   - STAKING_DELAIS : une entree par devise stakee, montant apy et delai deja reunis, rien a recouper. Le champ STAKING_APY reste disponible en confirmation mais STAKING_DELAIS fait foi en cas d ecart.

4) Ne change rien d'autre : ni le modèle sonar-pro, ni max_tokens 8000, ni la température, ni le
   schéma de sortie, ni les règles de trading, ni les modules 20023, 10011, 10014, 10023.

Puis SAUVEGARDE, et confirme-moi que l'URL du 20022 se termine bien par
?select=delais_texte:staking_texte
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
