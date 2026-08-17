PROMPT MAIA — scénario 6183820 — L'Alchimiste ne « voit » ni prix ni staking (tables encodées vides)

CONTEXTE (vérifié, ne rien inventer) : l'Alchimiste dit « faute de données de prix, d'APY et de délais
(tables encodées vides) ». Diagnostic : les DONNÉES existent (prix Revolut X = HTTP 200 avec prix_texte ;
tables alc_staking_apy / alc_staking_delais = 8 lignes chacune). Le bug est dans le MAPPING : l'Alchimiste
reçoit `base64(toString(<module>.data))` où .data est un OBJET/ARRAY → toString() rend une chaîne vide →
tables illisibles. On lui donne les champs TEXTE déjà prêts. 3 corrections chirurgicales.

Côté Supabase (déjà fait, ne touche pas) : 2 vues texte créées et testées —
  v_alc_staking_apy_txt(apy_texte)  et  v_alc_staking_delais_txt(delais_texte).
La fonction revolut-x-prices renvoie déjà `prix_texte`.

════════════════════════════════════════════════════════════════════════
CORRECTION 1 — Module de l'Alchimiste (texte système « Tu es L'ALCHIMISTE… », appel api.perplexity.ai)
════════════════════════════════════════════════════════════════════════
Dans le CORPS UTILISATEUR (role=user), remplace EXACTEMENT ces 3 tokens (ne touche à rien d'autre) :

- `PRIX_REVOLUTX_B64={{base64(toString(ifempty(10011.data; emptyarray)))}}`
      →  `PRIX_REVOLUTX_B64={{base64(ifempty(10011.data.prix_texte; emptystring))}}`

- `STAKING_DELAIS_B64={{base64(toString(ifempty(20022.data; emptyarray)))}}`
      →  `STAKING_DELAIS_B64={{base64(ifempty(20022.data[1].delais_texte; emptystring))}}`

- `STAKING_APY_B64={{base64(toString(ifempty(20023.data; emptyarray)))}}`
      →  `STAKING_APY_B64={{base64(ifempty(20023.data[1].apy_texte; emptystring))}}`

(Si Make refuse l'indice [1], utilise `get(20022.data; 1).delais_texte` et `get(20023.data; 1).apy_texte`.)
Ne touche PAS à SOLDES_REVOLUTX (déjà en clair) ni au reste du prompt.

════════════════════════════════════════════════════════════════════════
CORRECTION 2 — Module « 🌾 LA RENTE DES SCELLÉS » (id 20023, appel Supabase REST)
════════════════════════════════════════════════════════════════════════
Change UNIQUEMENT l'URL, de la table brute vers la vue texte :
  AVANT : https://smddzybxebwhfnitxuyp.supabase.co/rest/v1/alc_staking_apy?select=...
  APRÈS : https://smddzybxebwhfnitxuyp.supabase.co/rest/v1/v_alc_staking_apy_txt?select=apy_texte
Garde la méthode GET, les en-têtes (apikey / Authorization) et tout le reste inchangés.

════════════════════════════════════════════════════════════════════════
CORRECTION 3 — Module « ⛓️ LES CHAÎNES DU SCELLÉ » (id 20022, appel Supabase REST)
════════════════════════════════════════════════════════════════════════
Change UNIQUEMENT l'URL :
  AVANT : https://smddzybxebwhfnitxuyp.supabase.co/rest/v1/alc_staking_delais?select=...
  APRÈS : https://smddzybxebwhfnitxuyp.supabase.co/rest/v1/v_alc_staking_delais_txt?select=delais_texte
Garde la méthode GET, les en-têtes et tout le reste inchangés.

════════════════════════════════════════════════════════════════════════
VÉRIFICATION
════════════════════════════════════════════════════════════════════════
Après un run, ouvre le CORPS de l'appel à l'Alchimiste : PRIX_REVOLUTX_B64, STAKING_APY_B64 et
STAKING_DELAIS_B64 ne doivent plus être vides. Résultat attendu (décodé) — prix « BTC-USD:.../... | … »,
APY « ATOM:21.06% | … | TON:17.67% | … », délais « ATOM:21j | … | TON:2j | … ». L'Alchimiste ne doit plus
écrire « faute de données de prix / tables encodées vides ».
