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
-- LA SUITE EST AU PARAGRAPHE 4 : Chachou a fourni l'achat manquant du 22/07, FAI est passee
-- a 100,1 % de couverture, et la vue a ete refaite avec un drapeau `complet` qui decide
-- ligne par ligne. Elle EST transmise depuis revolut-x-read v15, pour les lignes completes
-- uniquement.

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
