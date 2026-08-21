# Prompt Maia — restaurer le module 10012 dans la version qui a marché

> **Statut : PRÊT.** Blueprint relu le 19/08 à 13:53 UTC — le 10012 est toujours dans l'ancienne
> version Base64, la sauvegarde de restauration n'a jamais eu lieu (dernière modification Make : 12:01).

## Pourquoi (trois runs, trois résultats différents, même configuration)

Le module 20022 est correct et le reste : clé valide, URL en alias, il renvoie le texte complet.
Le problème est en aval, dans le module **10012**, qui transmet ce texte **encodé en Base64** au modèle
en lui demandant de « décoder mentalement ». Ce décodage n'est pas fiable, et ça se voit :

| Run | Configuration du 10012 | Montants écrits dans `alc_destake_reco` |
|---|---|---|
| 11:11 UTC | Base64 | 7 lignes, **tous à 0** |
| **11:56 UTC** | **texte brut + nouveau prompt** | **7 lignes, 21 valeurs sur 21 exactes** |
| 12:00 UTC | Base64 (restauré par la sauvegarde de 11:58) | 7 lignes, **tous à 0** |
| 15:48 (13:48 UTC) | Base64 | **5 lignes** — 4 justes, SOL faux, **ETH et TON disparus** |

Un décodage Base64 correct donnerait le même résultat à chaque fois. Ce n'est pas le cas.

### Détail du run de 15:48 (planning)

Le run lui-même est allé au bout : **76 opérations sur 76**, succès, 5 Sages `ok`, 6 ordres passés.
Seule la partie staking est fausse :

| Devise | Écrit | Attendu | Délai | APY |
|---|---|---|---|---|
| SOL | **78,48** | 90,27 | 3 j ✅ | 6,16 ✅ |
| KSM | 14,67 ✅ | 14,67 | 7 j ✅ | 10,47 ✅ |
| ATOM | 5,87 ✅ | 5,87 | 21 j ✅ | 21,06 ✅ |
| OSMO | 4,91 ✅ | 4,91 | 14 j ✅ | 5,39 ✅ |
| TRX | 0,34 ✅ | 0,34 | 14 j ✅ | 3,26 ✅ |
| ETH | **absent** | 27,02 | 5 j | 2,45 |
| TON | **absent** | 7,91 | 2 j | 17,67 |

Total enregistré **104,27 $** contre **150,98 $** réellement stakés : 31 % du staking manque, dont TON,
la ligne au meilleur rendement (17,67 %).

Les délais et les APY sont **tous justes** — c'est l'alias du 20022 qui fonctionne, la donnée arrive
complète. Seuls les montants se perdent, et deux devises sautent.

## Prompt à envoyer à Maia

```
Bonjour Maia. Scénario 6183820, module 10012 (L'Alchimiste de la Crypte) uniquement.

Contexte : ce module a été remis dans son ancienne version Base64 lors d'une sauvegarde a 11:58.
Il faut le remettre dans l'état ou il etait a 11:47, qui avait donne un resultat parfait au run de
11:56 (les 7 devises stakees, 21 valeurs sur 21 exactes au centime). Depuis le retour au Base64,
le run de 12:00 a ecrit 7 montants a zero et celui de 15:48 n'a ecrit que 5 devises sur 7, dont
une fausse, en perdant ETH et TON.

Ne touche a AUCUN autre module. Le 20022 est correct : ne modifie ni sa cle, ni son URL, ni ses
en-tetes. Les modules 20023, 10010, 10011, 10014, 10023, 205 et 207 ne doivent pas bouger non plus.

1) MESSAGE "user" du module 10012 — remplace ce fragment :
STAKING_DELAIS_B64={{base64(ifempty(20022.data.delais_texte; emptystring))}}|STAKING_APY_B64={{base64(ifempty(20023.data.apy_texte; emptystring))}}
   par celui-ci :
STAKING_DELAIS={{ifempty(20022.data.delais_texte; emptystring)}}|STAKING_APY={{ifempty(20023.data.apy_texte; emptystring)}}

   Aucun autre champ de ce message ne change : PRIX_REVOLUTX_B64, CTX_B64, SAGES_B64 et tous les
   AVIS_GIL_* restent en base64. Il n'y a aucun nouveau champ a mapper, donc aucun blocage de Make
   possible : le chemin 20022.data.delais_texte est deja utilise aujourd'hui, il est simplement
   enveloppe dans base64().

2) MESSAGE "system" du module 10012 — trois remplacements de texte, rien d'autre.

  (a) a chercher :
  - STAKING est fourni à partir de deux tables : alc_staking_delais (devise, unbonding_jours stocké en texte) et alc_staking_apy (devise, apy_pct). Fais la jointure par devise de base, en ignorant la casse ; pour une paire comme SOL-USD, la devise de base est SOL. GRAM = TON : traite ces deux libellés comme le même actif. Convertis unbonding_jours en nombre.
      a remplacer par :
  - Le staking t'est fourni DEJA CONSOLIDE dans le champ STAKING_DELAIS : une entree par devise stakee, avec montant, APY et delai reunis. Tu n'as AUCUNE jointure a faire. Pour une paire comme SOL-USD, la devise de base est SOL. GRAM = TON : traite ces deux libelles comme le meme actif. Tu dois produire une ligne destake_recommande pour CHAQUE devise presente dans STAKING_DELAIS, sans en omettre aucune, meme celles de faible montant.

  (b) a chercher :
  - Les champs PRIX_REVOLUTX_B64, STAKING_DELAIS_B64 et STAKING_APY_B64 sont des chaînes Base64 : décode-les mentalement avant analyse ; ils contiennent les tableaux/objets correspondants.
      a remplacer par :
  - Le champ PRIX_REVOLUTX_B64 est une chaine Base64 : decode-la mentalement avant analyse. Le champ STAKING_DELAIS est du TEXTE BRUT et constitue ta SEULE source pour le de-staking : malgre son nom il contient TOUT, une entree par devise stakee, separees par des points-virgules, au format DEVISE montant=<nombre>USD apy=<nombre>% deblocage=<nombre>jours. Exemple reel : TON montant=7.91USD apy=17.67% deblocage=2jours ; ATOM montant=5.87USD apy=21.06% deblocage=21jours. Recopie ces trois nombres TELS QUELS dans montant_usd, apy_staking_pct et delai_deblocage_jours. N utilise JAMAIS tes connaissances generales ni le bloc SOLDES_REVOLUTX pour ces trois valeurs. Si le champ est vide ou vaut aucune ligne stakee, renvoie un tableau destake_recommande vide au lieu d inventer. N ecris jamais 0 par defaut.

  (c) a chercher :
  - STAKING_DELAIS_B64 et STAKING_APY_B64 : données encodées des deux tables, à joindre par devise de base.
      a remplacer par :
  - STAKING_DELAIS : une entree par devise stakee, montant apy et delai deja reunis, rien a recouper. Le champ STAKING_APY reste disponible en confirmation mais STAKING_DELAIS fait foi en cas d ecart.

3) Ne change rien d'autre dans le 10012 : ni le modele sonar-pro, ni max_tokens 8000, ni la
   temperature 0.4, ni le format de sortie, ni les regles de trading, ni le bloc REVOLUT X = SPOT.

SAUVEGARDE, puis confirme-moi les deux points suivants, qui sont le seul controle fiable :
  1. le message user du 10012 contient bien STAKING_DELAIS= et STAKING_APY= SANS le suffixe _B64
     et SANS base64( autour
  2. le message system ne contient plus la phrase "STAKING_DELAIS_B64 et STAKING_APY_B64"

Si Make affiche un avertissement du type "chemins dynamiques non verifies", ignore-le et sauvegarde
quand meme : les chemins 20022.data.delais_texte et 20023.data.apy_texte sont deja en service
aujourd'hui, ils ne changent pas.
```

## Contrôle après le prochain run

Les 7 devises doivent être présentes, avec ces montants au centime :
SOL 90,27 · ETH 27,02 · KSM 14,67 · TON 7,91 · ATOM 5,87 · OSMO 4,91 · TRX 0,34 → total **150,99 $**
(contre 150,98 $ déclarés par Revolut).

Délais attendus : SOL 3 j · ETH 5 j · KSM 7 j · TON 2 j · ATOM 21 j · OSMO 14 j · TRX 14 j.

## Ajout par rapport à la version de 11:47

Une phrase de plus dans le remplacement (a) : « Tu dois produire une ligne destake_recommande pour
CHAQUE devise presente dans STAKING_DELAIS, sans en omettre aucune, meme celles de faible montant. »
Le run de 15:48 a montré que le modèle peut **omettre des devises entières** (ETH et TON), pas
seulement se tromper de chiffre. La version de 11:47 avait sorti les 7 lignes, mais rien ne le lui
imposait explicitement.
