-- Plus rien a saisir, et l'Alchimiste recoit enfin de quoi choisir sa paire. 05/09/2026, le soir.
--
-- Chachou, mot pour mot :
--   « je ne modifie rien seul tout doit etre automatique !!! et si ca gene je supprime
--     l achat recurrent !! »
--   « et squid n existe pas sur revolut !!!! »
--   « normalement on a beaucoup plus de donnees dispo sur les crypto regarde mon scenario !
--     donc ajoute ce qu il faut pour qu il trade correctement »
-- Il a raison sur les trois. Voici la mesure de chacun, et ce qui a ete livre.

-- ===========================================================================
-- 1. SQUID N'EXISTE PAS. VERIFIE — ET C'EST PIRE QUE CA
-- ===========================================================================
-- Recherche dans prix_texte, la liste des paires reellement cotees, appel du 05/09 :
--     SQUID : ABSENT        SQD : present        FAI : present        IOTX : present
-- Or le prompt du module 10012 dit mot pour mot : « prix_ref est le cours que tu LIS dans
-- PRIX_REVOLUTX_B64 pour cette paire : si la paire ne s'y trouve pas, elle n'est pas
-- negociable et tu ne la proposes pas ».
-- Proposition 31/08 13:45 : SQUID-USD, buy 2 $, confiance 0,58, « petite mise exploratoire
-- conforme a la these de Ju sur SQUID ». prix_ref et prix_ref_modele : NULL tous les deux.
-- Il a invente une paire, et le NULL de prix_ref etait le seul indice qu'on avait.
-- La ligne est restee « expiree », donc rien n'est parti au courtier — le controle a tenu.

-- ===========================================================================
-- 2. LES ACHATS RECURRENTS SONT DESORMAIS DEDUITS. IL N'Y A PLUS RIEN A TENIR
-- ===========================================================================
-- La v13 lui demandait de tenir une ligne de table a jour. C'est encore de la saisie, donc
-- c'est encore quelque chose qui peut mentir. Table alc_achats_recurrents SUPPRIMEE.

create table if not exists public.alc_revolut_transactions (
  id text primary key, type text, statut text,
  source_devise text, source_montant numeric,
  dest_devise text,   dest_montant numeric,
  created_at timestamptz not null, processed_at timestamptz,
  provenance text not null default 'api',
  ingere_at timestamptz not null default now()
);
-- alc_ingest_transactions(jsonb) : recoit le tableau data de /api/1.0/transactions, ecrit sans
-- doublon (cle = id Revolut). Tous les objets portent les MEMES cles, a null quand la valeur
-- manque — regle du 31/08 sur les inserts groupes heterogenes.
-- revolut-x-read v14 l'appelle a CHAQUE run. L'API n'expose que 50 lignes sur 7 jours et n'a
-- pas de page suivante (metadata.next_cursor = chaine vide, mesure du 05/09), mais elle est
-- interrogee ~6 fois par jour : rien ne peut etre manque, et le journal garde tout pour
-- toujours. C'est ce qui manquait pour que le prix de revient survive au-dela de 7 jours.

-- v_alc_achats_recurrents_detectes : trois achats de la MEME devise, au MEME jour de semaine,
-- a la MEME heure (Europe/Paris) = un plan. Aucune coincidence ne tient trois fois.
-- L'ecart entre prelevements est la MEDIANE des ecarts consecutifs, jamais la moyenne sur la
-- periode : le releve d'ecran fourni saute juillet, la moyenne donnait 16,8 jours (faux), la
-- mediane donne 7,0 (juste).
--
-- RESULTAT, entierement deduit, aucune valeur saisie :
--     devises {BCH,TRX,XLM,XRP} · 6,74 USD par prelevement · hebdomadaire · ecart 7,0 j
--     6 prelevements observes · du 08/06 au 31/08 · prochain attendu le 07/09 · actif
-- Les 6,74 $ sont ses 5 GBP. Et le 07/09 est EXACTEMENT la date qu'affiche son ecran Revolut,
-- date qu'aucune de nos donnees ne contenait : la deduction est confirmee par une source
-- independante.
--
-- « et si ca gene je supprime l achat recurrent » : il n'aura rien a faire ici non plus.
-- Deux periodes sans prelevement et actif passe a false ; la phrase disparait toute seule du
-- contexte de l'Alchimiste.

-- Historique anterieur a la fenetre API : 25 lignes recopiees de son ecran « Ordres »
-- (provenance = releve_ecran, jamais confondues avec l'API). Ce sont des FAITS dates — une
-- transaction passee ne change jamais — et non de la configuration.
-- Elles apportent aussi le prix de revient de FAI (68,95 $ pour 33 125,1 FAI le 12/06,
-- soit 0,00208150), d'OSMO (15 $ le 08/06) et de VET (1 $ le 07/06).

-- v_alc_prix_revient : prix de revient moyen par devise, calcule sur le journal.
-- A ce stade de la soiree elle n'etait transmise a personne : la couverture etait trop
-- incomplete (TRX a -0,33 de quantite nette, FAI a 33 125 pour 43 131 detenus). Un prix de
-- revient partiel presente comme complet ferait croire a l'agent qu'il gagne ou qu'il perd
-- sur une ligne ou il n'en sait rien.
-- LA SUITE EST AUX PARAGRAPHES 4 ET 5 : Chachou a fourni l'achat manquant du 22/07 puis le
-- fichier ordre_manquant.txt, la vue a ete refaite deux fois, et son drapeau s'appelle
-- aujourd'hui `transmissible` (couverture >= 90 % et aucun achat hors USD). Le drapeau
-- `complet` du paragraphe 4 n'existe plus : c'est son etat intermediaire de la soiree.

-- ===========================================================================
-- 3. « ON A BEAUCOUP PLUS DE DONNEES » — VERIFIE. ELLES ETAIENT FABRIQUEES ET JETEES
-- ===========================================================================
-- collect-market-data (module 102) produit DEJA, a chaque run :
--     universe.crypto_gainers · universe.crypto_losers
--     universe.crypto_top_mcap  (25 coins avec prix et variation 24 h, CoinGecko)
--     universe.tradeable_crypto · universe.movers_gainers · universe.most_active
-- Recherche de ces cles dans le blueprint des 80 modules : chacune apparait UNE fois, et
-- uniquement dans l'echantillon de sortie stocke du module 102. ZERO mapping les lit.
-- CTX (module 110, 9 184 caracteres), qui alimente les trois Archimages ET l'Alchimiste, ne
-- cote que quatre cryptos : BTC, ETH, SOL, DOGE. Rien d'autre.
-- Ces donnees etaient donc payees a chaque run et jetees a chaque run. C'est exactement ce que
-- Chachou soupconnait.

-- v_alc_paires_variation : variation 24 h, variation 7 j et volume 24 h par paire -USD,
-- calculees dans price_history (qui couvre les 302 paires en horaire depuis 2022).
-- Couverture mesuree : 302 paires, 302 avec variation 24 h, 302 avec 7 j, 302 avec volume.
create or replace view public.v_alc_paires_variation as
with dernier as (
  select distinct on (symbol) symbol, close, ts from price_history
  where ts > now() - interval '6 hours' order by symbol, ts desc),
h24 as (
  select distinct on (symbol) symbol, close from price_history
  where ts between now() - interval '28 hours' and now() - interval '20 hours'
  order by symbol, ts desc),
j7 as (
  select distinct on (symbol) symbol, close from price_history
  where ts between now() - interval '7 days 8 hours' and now() - interval '6 days 16 hours'
  order by symbol, ts desc),
vol as (
  select symbol, sum(volume) as vol24 from price_history
  where ts > now() - interval '24 hours' and volume is not null group by symbol)
select d.symbol as paire, d.close as dernier_close,
       round(((d.close - a.close) / nullif(a.close,0) * 100), 1) as var_24h_pct,
       round(((d.close - b.close) / nullif(b.close,0) * 100), 1) as var_7j_pct,
       v.vol24 as volume_24h
from dernier d left join h24 a using (symbol) left join j7 b using (symbol)
     left join vol v using (symbol)
where d.symbol like '%-USD';

-- revolut-x-prices v3 la joint a prix_texte. Format, mesure sur l'appel du 05/09 :
--     IOTX-USD:0.00456/0.00459 24h=+52.7% 7j=+60.4% liq=559k$
--     FAI-USD:0.00239822/0.00240100 24h=-2.3% 7j=-11.6% liq=0$
-- prix_texte : 8 122 -> 16 904 caracteres, 302 paires, mesures_jointes=true.
--
-- POURQUOI TOUTES LES PAIRES ET PAS UN TOP 15 : un classement serait MON choix de candidats.
-- C'est precisement ce que la regle du 26/08 interdit — la mesure, jamais la conclusion. On
-- transmet l'univers mesure en entier, la selection reste la sienne.
--
-- Et ce que ca lui montre desormais : 119 des 302 paires ont un volume 24 h RAPPORTE A ZERO.
-- FAI en fait partie. Son prompt lui dit deja « mefie-toi du spread sur les micro-cryptos peu
-- liquides » sans jamais lui donner de quoi savoir lesquelles. Maintenant il l'a.

-- Le module Make 10011 lit data.prix_texte et le 10012 le passe en base64 : NI L'UN NI L'AUTRE
-- N'EST MODIFIE. Aucune manipulation Make. Si une vue devient injoignable, les deux fonctions
-- retombent sur leur sortie precedente, au caractere pres.

-- ===========================================================================
-- 4. SUITE DU MEME SOIR : L'ACHAT FAI DU 22 JUILLET, ET LE PRIX DE REVIENT LIVRE
-- ===========================================================================
-- Chachou : « j ai achete que 68,95$ soit 33095 fai le 12 juin et 25$ le 22 juillet
--             10035 fai je t ai donne plusieurs fois les ordres pourquoi tu les voit pas ! »
--
-- POURQUOI JE NE LE VOYAIS PAS. Le journal ne contenait que ce que j'avais pu LIRE :
--   - les 50 lignes de l'API, qui ne remontent qu'au 30/08 ;
--   - les 25 lignes recopiees de ses deux extraits d'ecran du jour, qui vont du 07/06 au
--     29/06 puis sautent directement au 17/08.
-- JUILLET N'ETAIT DANS AUCUN DES DEUX. Ce n'est pas l'API qui a perdu la ligne, c'est moi
-- qui n'avais aucune trace durable de ce qu'il m'avait montre avant : je relisais un ecran
-- a chaque fois au lieu de conserver. C'est exactement le trou que alc_revolut_transactions
-- ferme : desormais tout ce qui passe une fois par le journal y reste.
--
-- LIGNE AJOUTEE : ecran-20260722-FAI, 25,00 $ -> 10 035 FAI, provenance releve_ecran.
--
-- FAI DEVIENT COMPLETE :
--   journal 43 160,1 FAI   detenu 43 130,76   couverture 100,1 %   complet = true
--   93,95 $ payes  ·  prix de revient 0,00217678  ·  cours 0,002399  ·  +10,2 %
-- (l'ecart de 29 FAI, 0,07 %, vient de la quantite arrondie qu'il m'a donnee ; sans effet.)
--
-- v_alc_prix_revient est refaite : elle confronte le journal a la quantite REELLEMENT detenue
-- (v_alc_reel_live_positions) et porte un drapeau `complet` = couverture entre 97 et 103 %
-- ET aucun achat en devise autre que l'USD.
--   complet = true  : FAI (100,1 %), OSMO (99,6 %)
--   complet = false : BTC 50,0 % · SOL 14,3 % · XRP 15,2 % · BCH 19,4 % · XLM 20,3 %
--                     TRX -1,0 % · VET 59,6 % · ETH 99,8 % mais un achat en EUR
--
-- revolut-x-read v15 transmet UNIQUEMENT les lignes completes, sous l'intitule
-- « PRIX DE REVIENT MESURE ... les autres lignes n ont PAS de prix de revient connu, n en
-- invente aucun ». Mesure de la sortie reelle apres deploiement :
--   FAI: paye 93.95$ au total depuis le 2026-06-12, prix de revient moyen 0.002176779$,
--        +10.2% par rapport a ton prix d achat
--   OSMO: paye 15.00$ au total depuis le 2026-06-08, prix de revient moyen 0.0448999898$,
--        -21.2% par rapport a ton prix d achat
-- soldes_texte : 2 557 -> 2 969 caracteres. Tableau `soldes` : 48 entrees, inchange.
-- ETH restera incomplete tant qu'on n'aura pas le cours EUR/USD du 07/06 : je ne convertis
-- pas une devise a un taux que je n'ai pas mesure.

-- ===========================================================================
-- 5. LE FICHIER ordre_manquant.txt : JUILLET, LE GROS TRU, ET LE PREMIER RUN REEL
-- ===========================================================================
-- 22 lignes nouvelles journalisees. Journal : 50 (api) + 47 (releve_ecran), du 07/06 au 05/09.

-- a) LE PREMIER RUN REEL DE L'ALCHIMISTE EST DATE, A LA SECONDE PRES.
-- Cinq ventes proposees le 13/08 a 21:12:05, et l'ecran montre ce qui s'est passe :
--     propose            demande     execute
--     LRC-USD  sell       50,00 $     0,60 $
--     RLC-USD  sell       40,00 $     JAMAIS PLACE
--     IDEX-USD sell       35,00 $     0,37 $
--     ANKR-USD sell       30,00 $     1,58 $
--     TRU-USD  sell       25,00 $     23,76 $ demandes, ordre ANNULE par Revolut
-- 180 $ demandes, 2,55 $ passes. Le modele dimensionnait a l'aveugle : il ne voyait que des
-- QUANTITES, jamais la valeur en dollars de ses lignes. C'est precisement ce que la v12 a
-- corrige le 05/09 en lui donnant valeur et poids par ligne.
-- Et l'unique ordre ANNULE porte sur TRU, dont le volume 24 h mesure vaut ZERO. La donnee
-- ajoutee aujourd'hui dans prix_texte (liq=) aurait signale cette paire avant l'ordre.

-- b) LA VENTE ANNULEE EST ENREGISTREE TELLE QUELLE, avec statut = 'cancelled'.
-- Les vues ne comptent que statut = 'completed' : une tentative echouee ne doit jamais
-- diminuer une quantite detenue. C'etait le piege evident de ce fichier.

-- c) TRU ENTRE DANS LE PRIX DE REVIENT, ET LE SEUIL A CHANGE POUR UNE RAISON DE PRINCIPE.
-- Achat du 11/08 02:30 : 92,06 $ pour 71 642,024 TRU. Couverture 96,9 % (73 899 detenus).
-- La v15 posait le seuil de transmission a 97 % : TRU tombait a 0,1 point en dessous et
-- l'agent n'apprenait rien d'une ligne a -32,5 %. Ce seuil, c'etait MOI qui decidais ce que
-- l'agent avait le droit de savoir — l'inverse exact de la regle du 26/08.
-- v16 : le seuil descend a 90 %, et le chiffre part TOUJOURS accompagne de sa couverture
-- (« historique connu sur 96.9% de la ligne »). L'agent recoit la mesure ET sa fiabilite,
-- il juge lui-meme. En dessous de 90 % la ligne reste hors du texte : le prix moyen ne
-- decrit alors plus la ligne, ce n'est plus une mesure imprecise mais une autre grandeur.
-- Je n'ai PAS deplace le seuil pour faire passer TRU : je l'ai deplace parce que masquer
-- une mesure fiable a 96,9 % etait une conclusion de ma main. Le principe d'abord.

-- SORTIE REELLE APRES DEPLOIEMENT (v16), mesuree :
--   FAI : paye 93.95$ depuis le 2026-06-12, revient 0.002176779$, +10.2%  (100.1% de la ligne)
--   TRU : paye 92.06$ depuis le 2026-08-11, revient 0.001285$,    -32.5%  ( 96.9% de la ligne)
--   OSMO: paye 15.00$ depuis le 2026-06-08, revient 0.0448999898$, -21.2% ( 99.6% de la ligne)
-- soldes_texte : 2 969 -> 3 270 caracteres. Tableau `soldes` : 48 entrees, inchange.
-- journal : 50 recues / 50 ecrites.
--
-- Restent sous le seuil : TRX 55,7 % · XLM 50,5 % · BTC 50,0 % · BCH 49,3 % · XRP 25,5 %
--                         SOL 14,3 % · VET 59,6 % · ETH 99,8 % mais un achat en EUR.
-- Chaque ligne d'ecran supplementaire en fait basculer une de plus, definitivement.

-- ===========================================================================
-- 6. LES ACHATS EN EUROS SONT CONVERTIS AU COURS MESURE, ET ETH ENTRE
-- ===========================================================================
-- J'avais ecarte ETH en disant « je ne convertis pas une devise a un taux que je n'ai pas
-- mesure ». C'etait la bonne regle, mais la mauvaise conclusion : EUR-USD EST dans
-- price_history (2 432 points horaires), je ne l'avais pas cherche. Regle du 17/08 :
-- verifier avant d'affirmer qu'une chose n'existe pas.
--
-- v_alc_prix_revient convertit desormais chaque achat non-USD au cours de sa devise lu dans
-- price_history AU PLUS PRES de l'heure de l'ordre (jointure laterale sur
-- symbol = source_devise || '-USD', tri par ecart de temps). Si la paire n'y est pas, le
-- taux reste NULL, la ligne devient non transmissible et rien n'est invente.
--   achat du 07/06 11:07 : 20,02 EUR -> taux mesure 1,152605 -> 23,08 $
--   (le point le plus proche est le 07/06 23:00 : le 7 juin 2026 est un dimanche, le forex
--    est ferme. Ecart de 12 h, assume et note.)
-- ETH : 53,08 $ payes, prix de revient 2 020,34 $, cours 2 455,59 $, +21,5 %, couverture
-- 99,8 % -> TRANSMISSIBLE. BTC beneficie de la meme conversion (116,11 $, revient 69 566 $,
-- +14,5 %) mais reste a 50 % de couverture : il lui manque des ordres, pas un taux.
--
-- SORTIE REELLE (v16 + vue convertie), mesuree :
--   FAI  100.1%  93.95$  0.002176779$   +10.2%
--   TRU   96.9%  92.06$  0.001285$      -32.5%
--   ETH   99.8%  53.08$  2020.3441699$  +21.5%
--   OSMO  99.6%  15.00$  0.0448999898$  -21.2%
-- soldes_texte : 3 270 -> 3 439 caracteres. Tableau `soldes` : 48 entrees, inchange.
-- Aucun redeploiement necessaire : la fonction lit transmissible, la vue a change seule.

-- ===========================================================================
-- 7. ETAT DE LA COUVERTURE, ET CE QU'IL RESTE A CHERCHER
-- ===========================================================================
-- Portefeuille hors cash : 1 055,27 $ sur 40 lignes.
--   avec prix de revient ............  240,62 $   22,8 %
--   ordres partiels .................  514,02 $   (BTC 50 %, SOL 14 %, XRP 26 %, BCH 49 %,
--                                                  XLM 51 %, TRX 56 %, VET 60 %)
--   aucun ordre connu ...............  300,63 $   sur 36 lignes
--
-- Les trois lignes qui pesent et dont on ne sait RIEN : UNI 96,36 $ · MEW 54,82 $ ·
-- HFT 49,04 $ = 200 $ a elles seules, soit les deux tiers de la zone inconnue.
-- Puis KSM 18,80 $ · DASH 12,33 $ · TON 8,64 $ · FORTH 8,02 $ · SHIB 7,86 $ · DOGE 7,26 $ ·
-- ATOM 6,50 $, et 26 lignes a moins de 3 $ qui ne changeront jamais une decision.
--
-- BTC : il manque 0,00167 BTC (la moitie de la ligne), donc des achats entre le 08/06 et le
-- 29/08 que les extraits d'ecran ne couvrent pas.
-- SOL : il manque 1,1775 SOL sur 1,3738 — l'essentiel de la ligne.

-- ===========================================================================
-- 8. DEUXIEME RELEVE COMPLET : 18 LIGNES DE PLUS, ET DEUX CHOSES A VOIR
-- ===========================================================================
-- Journal : 115 lignes (50 api + 65 releve_ecran), du 07/06 au 05/09.
-- Ajoutees : le prelevement recurrent du 10/08, les quatre allers-retours HFT du 06/08,
-- l'achat UNI du 06/08, les prelevements du 03/08, 27/07 et le XRP du 20/07.

-- a) UNI ENTRE, ET C'EST LA MEILLEURE LIGNE DU PORTEFEUILLE.
--    06/08 11:34 : 25 UNI pour 100,26 $, soit 4,0104 $ l'unite. Cours 6,3225 $ : +57,7 %.
--    Couverture 97,6 % (14,88 au journal apres une vente, 15,24 detenus).

-- b) HFT : LA LIGNE N'EST PAS TRANSMISSIBLE, MAIS LE CHIFFRE EST TROP GROS POUR ETRE TU.
--    Quatre ordres le 06/08 au soir :
--      21:09  vente  1 609,4791 HFT @ 0,03318   ->  53,40 $
--      23:12  achat  2 766,866  HFT @ 0,03513   ->  97,20 $
--      23:20  vente  4 039,2108 HFT @ 0,03497   -> 141,25 $
--      23:21  achat  4 005,1499 HFT @ 0,03523   -> 141,12 $
--    Prix de revient des achats connus : 0,03519. Cours du jour : 0,00651. -81,5 %.
--    VERIFIE dans price_history, ce n'est pas un artefact : moyenne journaliere HFT-USD
--      05/08 0,016504 · 06/08 0,026440 · 07/08 0,018946 · 08/08 0,012350 · 05/09 0,00651
--    Il a achete 141 $ a 23:21 le 06/08, au sommet exact d'un pic qui a fait x1,6 dans la
--    journee et qui s'est effondre le lendemain.
--    La ligne reste NON transmissible : couverture 14,9 %, il manque ~6 410 HFT achetes
--    avant le 06/08. Le prix de revient global sera different — mais la chute du cours,
--    elle, est mesuree et ne depend d'aucune ligne manquante.

-- c) TRX passe a 100,1 % de couverture et devient transmissible (16,35 $, +0,8 %).

-- SORTIE REELLE, six lignes desormais :
--   UNI  97.6%  100.26$  4.0104$          +57.7%
--   FAI 100.1%   93.95$  0.002176779$     +10.2%
--   TRU  96.9%   92.06$  0.001285$        -32.5%
--   ETH  99.8%   53.08$  2020.3441699$    +21.5%
--   TRX 100.1%   16.35$  0.3306590733$     +0.8%
--   OSMO 99.6%   15.00$  0.0448999898$    -21.2%
-- soldes_texte : 3 439 -> 3 766 caracteres. Tableau `soldes` : 48 entrees, inchange.

-- COUVERTURE DU PORTEFEUILLE : 1 055,27 $ hors cash
--   avec prix de revient .... 348,36 $   33,0 %   (etait 22,8 % il y a une heure)
--   ordres partiels ......... 551,68 $   HFT 14,9 % · SOL 14,3 % · XRP 44,8 % · BTC 50,0 %
--                                        VET 59,6 % · BCH 72,5 % · XLM 74,4 %
--   aucun ordre connu ....... 155,23 $   sur 34 lignes, dont MEW 54,82 $ et KSM 18,80 $
--
-- Ce qui manque encore, par ordre d'utilite :
--   MEW  54,82 $  aucun ordre           SOL   1,1775 manquants sur 1,3738
--   HFT  ~6 410 unites avant le 06/08   BTC   0,00167 manquant sur 0,00334
--   XRP  17,7 manquants sur 32,09       KSM  18,80 $ aucun ordre

-- ===========================================================================
-- 9. MEW ENTRE — ET L'ECRAN « TRANSACTION » REMONTE PLUS LOIN QUE L'ECRAN « ORDRES »
-- ===========================================================================
-- Chachou a colle une ligne dans un TROISIEME format, celui de l'ecran Transaction :
--     USD -> MEW · 21 juil., 21:19 · Achat · Termine(e) · 129 865,77224251 MEW · 50,00 $
--
-- MEW : 50,00 $ pour 129 865,77 MEW, prix de revient 0,000385013, cours 0,000419 : +8,8 %.
-- Couverture 99,5 % (130 514,13 detenus) -> TRANSMISSIBLE.
--
-- CE QUI EST INTERESSANT N'EST PAS LA LIGNE, C'EST L'ECRAN.
-- Cet achat du 21/07 n'apparait dans AUCUN des deux extraits de l'ecran « Ordres » fournis
-- ce soir, qui couvrent pourtant juillet. L'ecran « Transaction » de l'application montre
-- donc des mouvements que l'ecran « Ordres » ne montre pas — probablement parce que MEW a
-- ete achete autrement qu'au carnet d'ordres. Meme constat pour le FAI du 22/07, absent du
-- second releve alors que Chachou l'a donne de memoire.
-- CONSEQUENCE PRATIQUE : pour les lignes qui restent a zero (KSM, DASH, TON, FORTH, SHIB,
-- DOGE, ATOM...), c'est l'ecran TRANSACTION qu'il faut regarder, pas l'ecran ORDRES.
--
-- COUVERTURE : 1 055,42 $ hors cash
--   avec prix de revient .... 403,09 $   38,2 %   (22,8 % -> 33,0 % -> 38,2 % ce soir)
--   ordres partiels ......... 551,89 $
--   aucun ordre connu ....... 100,44 $   sur 33 lignes, la plus grosse KSM a 18,80 $
-- soldes_texte : 3 766 -> 3 931 caracteres. Sept lignes avec prix de revient.

-- ===========================================================================
-- 10. L'ECRAN TRANSACTION DEBLOQUE SOL, XRP ET BTC — ET REVELE DEUX CHOSES
-- ===========================================================================
-- 7 lignes ajoutees, toutes ABSENTES de l'ecran Ordres : des achats regles en GBP, EUR ou
-- USDT, qui ne passent visiblement pas par le carnet.
--   18/06 20:27  GBP -> SOL   55,00 £ -> 1,007166 SOL
--   02/07 23:09  GBP -> SOL   10,00 £ -> 0,160025 SOL
--   02/07 23:09  GBP -> XRP   10,00 £ -> 12,000936 XRP
--   02/07 23:08  EUR -> XRP    5,55 € -> 5,711042 XRP
--   02/07 23:08  EUR -> BTC    5,55 € -> 0,00010029 BTC
--   08/06 18:27  EUR -> HFT    0,83 € -> 88,7411709 HFT
--   05/06 19:25  USDT -> BTC  100 USDT -> 0,0015708 BTC
-- GBP-USD est dans price_history (2 433 points) : les achats en livres sont convertis au
-- cours mesure, comme les euros.

-- a) DECOUVERTE : L'ECRAN ORDRES DONNE LE BRUT, L'ECRAN TRANSACTION LE NET.
-- Les neuf achats XRP recurrents figurent dans les deux ecrans avec des quantites
-- differentes, et l'ecart est CONSTANT :
--     03/08  Ordres 1,57      Transaction 1,56858     -0,090 %
--     27/07  Ordres 1,49187   Transaction 1,49052     -0,090 %
--     20/07  Ordres 1,51433   Transaction 1,51296     -0,090 %
--     13/07  Ordres 1,54204   Transaction 1,54065     -0,090 %
-- 0,09 %, c'est EXACTEMENT le frais taker Revolut X annonce dans le prompt du 10012.
-- L'ecran Ordres montre la quantite remplie AVANT frais, l'ecran Transaction ce qui arrive
-- reellement sur le compte. Les neuf lignes ont ete corrigees au NET.

-- b) LES 100 USDT DU 05/06 NE SONT PAS VALORISABLES, ET J'AI VERIFIE POURQUOI.
-- USDT-USD n'est pas dans price_history (EUR-USD, GBP-USD, EUR-GBP, USDC-USD y sont).
-- J'ai voulu deduire le taux depuis le BTC recu : 0,0015708 BTC au cours de l'instant
-- (60 814 $) = 95,53 $, soit un USDT implicite a 0,9553. Aberrant pour un stablecoin.
-- Controle du rapprochement price_history / prix Revolut sur quatre achats BTC recents :
--     04/09 21:17  79 778,75 vs 79 797,70   -0,02 %
--     04/09 18:33  79 727,01 vs 79 466,10   +0,33 %
--     04/09 09:39  80 749,35 vs 81 147,40   -0,49 %
--     03/09 15:49  78 789,79 vs 80 553,00   -2,19 %
-- Les closes horaires collent a 0,5 % pres en general, mais derapent a 2 % sur un mouvement
-- intra-horaire. Impossible d'en tirer un taux de change a 0,1 % pres. On n'invente donc pas :
-- taux NULL, nb_achats_sans_taux = 1, BTC reste NON transmissible malgre 100,0 % de
-- couverture. Il suffirait de la contre-valeur en dollars de ces 100 USDT pour debloquer.

-- ETAT APRES CE RELEVE : 1 058,83 $ hors cash
--   avec prix de revient .... 592,39 $   55,9 %   (22,8 -> 33,0 -> 38,2 -> 55,9 ce soir)
--   ordres partiels ......... 366,05 $   BTC (bloque par l'USDT) · HFT 16,1 % · BCH 72,5 %
--                                        XLM 74,4 % · VET 59,6 %
--   aucun ordre connu ....... 100,39 $   sur 33 lignes, la plus grosse KSM a 18,65 $
--
-- Neuf lignes transmises, dont trois nouvelles :
--   SOL  99.2%  105.98$  77.728012$   +32.4%      XRP 100.0%  36.05$  1.12304625$  +26.0%
--   UNI  97.6%  100.26$  4.0104$      +58.3%      MEW  99.5%  50.00$  0.00038501$   +8.6%
--   FAI 100.1%   93.95$  0.00217678$  +10.2%      TRX 100.1%  16.35$  0.33065907$   +0.8%
--   TRU  96.9%   92.06$  0.001285$    -30.1%      OSMO 99.6%  15.00$  0.04489999$  -21.2%
--   ETH  99.8%   53.08$  2020.344170$ +21.6%

-- ===========================================================================
-- 11. LE RELEVE TRANSACTION COMPLET : 99,1 % DU PORTEFEUILLE A UN PRIX DE REVIENT
-- ===========================================================================
-- Journal reconstruit sur le releve « Transaction » integral (quantites NETTES, apres frais),
-- qui remplace toutes les recopies partielles de l'ecran « Ordres ». 154 lignes, du 05/06 au
-- 05/09 : 50 de l'API, 104 du releve.

-- a) LE TAUX USDT EST ENFIN MESURABLE — PAR SES PROPRES CONVERSIONS.
-- Six conversions EUR -> USDT figurent au releve. Divisees par EUR-USD mesure dans
-- price_history au meme instant :
--   28/04 1,012637 · 03/05 1,014370 · 12/05 1,011723
--   15/05 1,012081 · 26/05 1,011329 · 07/06 1,013848
-- Six mesures independantes dans une fourchette de 0,3 %. Ce n'est pas le peg de l'USDT qui
-- vaut 1,0127 : c'est le SPREAD Revolut sur EUR->USDT. Table alc_taux_reference : une ligne
-- par devise absente de price_history, avec la METHODE ecrite et la dispersion. Le prix de
-- revient d'un achat regle en USDT peut donc etre surestime d'environ 1,3 % ; c'est ecrit.
-- Cela debloque BTC (100 USDT du 05/06), KSM et ATOM.

-- b) KSM ET ATOM SONT ENTRES PAR UNE MISE EN STAKING LIBELLEE EN USDT.
--   « Staking de KSM · 07/06 13:28 · 18,887911 USDT »   -> 5,09289588 KSM
--   « Staking de ATOM · 05/06 19:28 · 6,817325 USDT »   -> 4,200854 ATOM
-- Les autres mises en staking sont libellees dans l'actif lui-meme (SOL, TON, TRX, OSMO, ETH).
-- Ces deux-la sont donc des ACQUISITIONS, pas des mouvements internes : c'est la seule
-- explication de la presence de KSM et d'ATOM, qu'aucun achat ne couvrait.

-- c) DEUX PIEGES DE RAPPROCHEMENT, ATTRAPES PAR L'ECART DE QUANTITE.
--   - La vente UNI du 02/09 est DANS la fenetre de l'API : recopiee, elle faisait double.
--     UNI tombait a 33,6 % de couverture. Ligne supprimee -> 100,0 %.
--   - La vente de 1 TRX du 05/07 figure sur l'ecran Ordres et PAS sur l'ecran Transaction.
--     Le journal affichait 35,1183 TRX pour 34,1259 detenus : l'ecart de 0,9924 la reclamait.
--     Reintegree -> 100,0 %.
-- Dans les deux cas, c'est la confrontation a la quantite REELLEMENT detenue qui a signale
-- l'erreur. Un journal qu'on ne confronte a rien ne se corrige jamais.

-- COUVERTURE FINALE : 1 058,83 $ hors cash
--   avec prix de revient .... 1 049,19 $   99,1 %
--   sans .................... 9,64 $ sur 8 lignes (VET 59,5 %, NKN, FET, MLN, POLS, MON,
--                             FLR, ZKJ — aucune au-dessus de 2,40 $)
-- Trajet de la soiree : 22,8 % -> 33,0 % -> 38,2 % -> 55,9 % -> 99,1 %.

-- LE CHIFFRE QUE PERSONNE N'AVAIT JAMAIS VU :
--   1 282,82 $ investis · 1 046,66 $ aujourd'hui · -236,16 $ soit -18,4 %
-- Les trois quarts de la perte tiennent en une ligne : HFT, -269 $ sur 354,93 $ investis.
-- En face : UNI +59,1 %, SOL +32,4 %, XRP +26,0 %, ETH +21,6 %, BTC +19,0 %.

-- revolut-x-read v17 : le bloc s'ouvre sur ce bilan, puis une ligne par devise, la plus
-- chere d'abord, au format « HFT 0.0269251765$ -75.6% (354.93$ investis) ».
-- Ecrit comme en v16, le bloc pesait 9 200 caracteres ; il en fait 4 620 avec 30 lignes.
-- Tableau `soldes` : 48 entrees, inchange. Aucun module Make, aucun prompt touche.
