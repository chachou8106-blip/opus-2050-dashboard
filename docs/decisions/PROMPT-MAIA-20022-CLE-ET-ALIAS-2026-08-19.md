# Prompt Maia — réparer le module 20022 (clé + alias) et finir le dé-staking

> **Statut : PRÊT. Tout est mesuré, rien n'est supposé.**
> Blueprint relu deux fois d'affilée le 19/08 à 12:30 — lectures identiques.

## Constat (lu dans le blueprint, pas déduit)

Maia a raison : **la clé Supabase du module 20022 est invalide.** C'est une corruption
**différente** de celle du 17/08.

| Module | Payload décodé du JWT |
|---|---|
| 20023, 10023 et les 32 autres en-têtes du scénario | `{"iss":"supabase","ref":"smddzybxebwhfnitxuyp",…}` ✅ |
| **20022 — `apikey` ET `Authorization`** | `{"iss":"HS256","ref":"smddzybxebwhfnitxuyp",…}` ❌ |

`HS256` est un fragment de l'**en-tête** du jeton recopié dans le **payload**. Le `ref` est correct
cette fois, la signature est intacte — mais elle ne correspond plus au contenu signé, donc le jeton
est mathématiquement invalide. Sur les 36 en-têtes JWT du scénario, **seuls ces 2 sont touchés**.

### Preuve par appel réel (depuis Supabase, mêmes en-têtes que le module)

| Clé utilisée | Réponse |
|---|---|
| `iss:supabase` (correcte) | **200** + `{"delais_texte":"SOL montant=90.27USD apy=6.16% deblocage=3jours ; …"}` |
| `iss:HS256` (celle du 20022) | **401** `{"message":"Invalid API key"}` |

### Effet de bord qui explique le blocage de Make

La dernière sortie mémorisée du 20022 dans le blueprint est **le 401 lui-même** :
```json
"20022": {"data": {"hint": "Double check your Supabase anon or service_role API key.",
                   "message": "Invalid API key"}, "statusCode": 401}
```
Make ne connaît donc plus **aucun champ de données** pour ce module. C'est la raison exacte pour
laquelle il refusait `staking_texte` la dernière fois — ce n'était pas un caprice de l'éditeur, mais
la conséquence directe de la clé cassée. **D'où l'ordre des opérations ci-dessous : la clé d'abord,
le rafraîchissement ensuite.**

### Second désalignement à corriger dans la foulée

- Le 20022 demande aujourd'hui `?select=staking_texte`
- Le 10012 lit toujours `20022.data.delais_texte`

Un run dans cet état enverrait un champ vide. L'alias PostgREST (`delais_texte:staking_texte`) règle
les deux d'un coup : la réponse reprend la clé que Make connaît déjà, sans qu'aucun mapping ne bouge.

## Prompt à envoyer à Maia

```
Bonjour Maia. Tu as raison : la clé Supabase du module 20022 est invalide. J'ai décodé le jeton,
son champ iss vaut "HS256" au lieu de "supabase" — un fragment de l'en-tete du JWT recopié dans le
payload. La signature ne correspond donc plus au contenu, d'ou le 401 Invalid API key. C'est une
corruption differente de celle du 17/08 (qui portait sur le ref du projet).

Fais les etapes dans cet ordre exact, l'ordre compte.

ETAPE 1 — MODULE 20022 (chaines du scelle) : remplace la valeur des DEUX en-tetes.

  en-tete "apikey", valeur exacte :
eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InNtZGR6eWJ4ZWJ3aGZuaXR4dXlwIiwicm9sZSI6ImFub24iLCJpYXQiOjE3Nzk4ODk4NzksImV4cCI6MjA5NTQ2NTg3OX0.ppjgF79OokQ-2jE8UCp26U-E-YZPcmf6TNnYEKHGKSM

  en-tete "Authorization", valeur exacte :
Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InNtZGR6eWJ4ZWJ3aGZuaXR4dXlwIiwicm9sZSI6ImFub24iLCJpYXQiOjE3Nzk4ODk4NzksImV4cCI6MjA5NTQ2NTg3OX0.ppjgF79OokQ-2jE8UCp26U-E-YZPcmf6TNnYEKHGKSM

  Controle a faire sans comparer a l'oeil : la valeur doit CONTENIR la sous-chaine
  eyJpc3MiOiJzdXBhYmFzZSIs   (correcte)
  et ne doit PLUS contenir
  eyJpc3MiOiJIUzI1NiIs       (corrompue)
  C'est le seul controle fiable : les deux jetons ne different que sur ces caracteres.

ETAPE 2 — MODULE 20022 : change l'URL.

  URL actuelle :
  https://smddzybxebwhfnitxuyp.supabase.co/rest/v1/v_alc_staking_txt?select=staking_texte

  Nouvelle URL :
  https://smddzybxebwhfnitxuyp.supabase.co/rest/v1/v_alc_staking_txt?select=delais_texte:staking_texte

  C'est un simple renommage de colonne cote API : la reponse reprendra la cle delais_texte, celle
  que Make connait deja, tout en contenant le texte complet du staking. Ne change RIEN d'autre sur
  ce module : ni la methode GET, ni le timeout 120, ni l'en-tete Accept application/vnd.pgrst.object+json.

ETAPE 3 — MODULE 20022 : execute CE SEUL MODULE une fois (Run this module only), pour que Make
  reapprenne sa structure de sortie. Aujourd'hui la seule sortie qu'il a en memoire est le 401
  ("Invalid API key"), c'est pour cela qu'il ne reconnait aucun champ. Le resultat attendu est un
  200 avec une cle delais_texte qui commence par : SOL montant=90.27USD apy=6.16% deblocage=3jours
  Si ce module renvoie encore 401, ARRETE-TOI et dis-le moi : inutile de continuer.

ETAPE 4 — MODULE 10012 (L'Alchimiste de la Crypte) : NE TOUCHE PAS au message "user".
  Il doit rester exactement tel quel, avec STAKING_DELAIS={{ifempty(20022.data.delais_texte; emptystring)}}.
  Aucun nouveau champ a mapper, donc aucun blocage possible.

ETAPE 5 — MODULE 10012, message "system" UNIQUEMENT : trois remplacements de texte.

  (a) a chercher :
  - STAKING est fourni à partir de deux tables : alc_staking_delais (devise, unbonding_jours stocké en texte) et alc_staking_apy (devise, apy_pct). Fais la jointure par devise de base, en ignorant la casse ; pour une paire comme SOL-USD, la devise de base est SOL. GRAM = TON : traite ces deux libellés comme le même actif. Convertis unbonding_jours en nombre.
      a remplacer par :
  - Le staking t'est fourni DEJA CONSOLIDE dans le champ STAKING_DELAIS : une entree par devise stakee, avec montant, APY et delai reunis. Tu n'as AUCUNE jointure a faire. Pour une paire comme SOL-USD, la devise de base est SOL. GRAM = TON : traite ces deux libelles comme le meme actif.

  (b) a chercher :
  - Le champ PRIX_REVOLUTX_B64 est une chaîne Base64 : décode-la mentalement avant analyse. En revanche STAKING_DELAIS et STAKING_APY sont du TEXTE BRUT directement lisible, au format DEVISE:valeur séparé par des barres verticales (exemple : ATOM:21j | TON:2j pour les délais, ATOM:21.06% | TON:17.67% pour les APY). Utilise ces valeurs TELLES QUELLES, ne les décode pas. N'utilise JAMAIS tes connaissances générales pour l'APY ni pour les délais : si le champ est vide, dis-le explicitement au lieu de deviner, et n'écris jamais 0 par défaut.
      a remplacer par :
  - Le champ PRIX_REVOLUTX_B64 est une chaine Base64 : decode-la mentalement avant analyse. Le champ STAKING_DELAIS est du TEXTE BRUT et constitue ta SEULE source pour le de-staking : malgre son nom il contient TOUT, une entree par devise stakee, separees par des points-virgules, au format DEVISE montant=<nombre>USD apy=<nombre>% deblocage=<nombre>jours. Exemple reel : TON montant=7.91USD apy=17.67% deblocage=2jours ; ATOM montant=5.87USD apy=21.06% deblocage=21jours. Recopie ces trois nombres TELS QUELS dans montant_usd, apy_staking_pct et delai_deblocage_jours. N utilise JAMAIS tes connaissances generales ni le bloc SOLDES_REVOLUTX pour ces trois valeurs. Si le champ est vide ou vaut aucune ligne stakee, renvoie un tableau destake_recommande vide au lieu d inventer. N ecris jamais 0 par defaut.

  (c) a chercher :
  - STAKING_DELAIS et STAKING_APY : texte brut des deux tables au format DEVISE:valeur | DEVISE:valeur, à joindre par devise de base. Le suffixe j signifie jours : ATOM:21j veut dire delai_deblocage_jours = 21. Le suffixe % est un pourcentage annuel : ATOM:21.06% veut dire apy_staking_pct = 21.06. Reporte ces nombres exactement dans le JSON de sortie.
      a remplacer par :
  - STAKING_DELAIS : une entree par devise stakee, montant apy et delai deja reunis, rien a recouper. Le champ STAKING_APY reste disponible en confirmation mais STAKING_DELAIS fait foi en cas d ecart.

ETAPE 6 — Ne change rien d'autre : ni le modele sonar-pro, ni max_tokens 8000, ni la temperature,
  ni le schema de sortie, ni les regles de trading, ni les modules 20023, 10011, 10014, 10023, 205.

Puis SAUVEGARDE, et confirme-moi ces trois points :
  1. les 2 en-tetes du 20022 contiennent bien eyJpc3MiOiJzdXBhYmFzZSIs
  2. l'URL du 20022 se termine bien par ?select=delais_texte:staking_texte
  3. le test du module 20022 est passe en 200 et a renvoye un champ delais_texte non vide
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

Somme des 7 lignes : **150,99 $** contre **150,98 $** déclarés par Revolut (écart : 1 centime).

## Point à surveiller

C'est la **deuxième** corruption de la clé sur ce même module en deux jours, sur deux caractères
différents à chaque fois. Le jeton n'est jamais retapé à la main normalement — il est copié.
Si cela se reproduit une troisième fois, il faudra cesser de le coller en clair dans l'en-tête et
passer par une Connection Make ou une variable de scénario, pour qu'il ne soit plus éditable
par erreur.
