PROMPT POUR MAIA — scénario 6183820 « ZCT — Oracle L'Alchimiste Financier v5 VISIONNAIRE »

Maia, le scénario de l'Alchimiste plante depuis hier soir et je te demande de le RÉPARER,
en changeant UNIQUEMENT ce qui est nécessaire, sans rien casser d'autre. Je te présente le
problème et des pistes de cause ; c'est TOI qui décides du correctif exact.

────────────────────────────────────────
1) LE SYMPTÔME (ce que disent les logs)
────────────────────────────────────────
- Chaque exécution s'arrête en erreur avec :
    « The provided JSON body content is not valid JSON. »
    name: InvalidConfigurationError — causeModule: http / MakeRequest
- Module fautif : le module HTTP « MakeRequest » qui appelle
    https://api.perplexity.ai/chat/completions
  (c'est la requête IA de l'Alchimiste, celle dont le corps commence par {"model":"sonar-pro"...}).
- Le corps est un JSON écrit à la main (Body content type = JSON, champ « Request content » /
  jsonStringBodyContent).

────────────────────────────────────────
2) LA CHRONOLOGIE (quand ça a commencé)
────────────────────────────────────────
- Dernière exécution automatique RÉUSSIE : 13/08 à 19:10 (avant les dernières modifications).
- Modifications apportées ensuite : 13/08 entre 19:45 et 21:40 — ajout des données de staking
  (délai de déblocage + APY) et réécriture du prompt de l'Alchimiste.
- Depuis ces modifications, toute exécution échoue avec l'erreur ci-dessus
  (dernier échec constaté : 14/08 à 10:38).
- Donc la régression est arrivée AVEC ces modifications, pas avant.

────────────────────────────────────────
3) PISTES DE CAUSE (à vérifier, pas à appliquer aveuglément)
────────────────────────────────────────
Dans le message « user » de la requête Perplexity (module 10012), le corps JSON assemble une
grande chaîne de la forme SOLDES_REVOLUTX=…|PRIX_REVOLUTX=…|STAKING_DELAIS=…|STAKING_APY=…|…

Trois champs y injectent, à mon avis, une valeur STRUCTURÉE (tableau ou objet) BRUTE au milieu
de cette chaîne JSON, alors que tout le reste du corps n'injecte que des CHAÎNES :
  a) PRIX_REVOLUTX = {{ ifempty(10011.data ; emptystring) }}
       → `10011.data` semble être le tableau/objet complet des prix.
         Dans la version qui fonctionnait, ce champ pointait sur une CHAÎNE de texte
         (le champ « texte » des prix), pas sur l'objet entier.
  b) STAKING_DELAIS = {{ ifempty(20022.data ; emptyarray) }}
       → `20022.data` est le TABLEAU renvoyé par la requête alc_staking_delais.
  c) STAKING_APY = {{ ifempty(20023.data ; emptyarray) }}
       → `20023.data` est le TABLEAU renvoyé par la requête alc_staking_apy.

Hypothèse : quand un tableau/objet est inséré tel quel à l'intérieur d'un corps JSON écrit à la
main, les crochets, guillemets et virgules de ce tableau ne sont pas échappés pour le JSON qui
les entoure → le corps final n'est plus un JSON valide → l'erreur ci-dessus. Le fait que le repli
soit `emptyarray` confirme que ces champs valent bien des tableaux.

Point de comparaison utile : dans la version qui fonctionnait (avant hier soir), TOUTES les
valeurs injectées dans ce corps étaient des chaînes de texte simples (champ texte des soldes,
champ texte des prix, et pour le reste des valeurs passées en base64 / toString). Aucune valeur
structurée brute n'était insérée dans le JSON.

────────────────────────────────────────
4) CE QUE JE TE DEMANDE
────────────────────────────────────────
- Objectif : que l'Alchimiste reçoive TOUJOURS les données de staking (délai + APY) et les prix,
  MAIS que le corps de la requête Perplexity redevienne un JSON valide.
- La contrainte est simple : tout ce qui est inséré dans ce corps JSON doit être une CHAÎNE de
  texte correctement échappée — jamais un tableau/objet brut.
- À toi de choisir COMMENT tu t'y prends (par exemple : transformer chaque tableau en une chaîne
  de texte propre avant injection, ou pointer sur un champ « texte » déjà mis en forme, ou toute
  autre méthode que tu juges plus robuste). Je te laisse décider de la meilleure solution.
- Vérifie aussi le champ PRIX_REVOLUTX : il pointait avant sur une chaîne de texte des prix ;
  s'il pointe maintenant sur l'objet entier, remets-le sur la bonne valeur de type chaîne.

Règles à respecter absolument :
- Ne modifie QUE le strict nécessaire pour corriger ce corps JSON. Ne touche à rien d'autre
  (les autres modules, le reste du scénario, les autres prompts restent inchangés).
- Ne supprime pas les données de staking : elles doivent rester dans le prompt, mais sous une
  forme qui n'invalide pas le JSON.
- Après correction, l'exécution doit repartir sans l'erreur « not valid JSON ».
