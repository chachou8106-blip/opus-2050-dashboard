-- Les achats recurrents sortent du prompt, et on mesure comment l'Alchimiste choisit ses cryptos.
-- 05/09/2026.
--
-- Demande de Chachou, mot pour mot :
--   « si tu corrige t ecris rien en dur c'est interdit car autant demain ca change et t aura
--     ecris quelques choses en dur comme tout les conneries que tu as fais tout le mois d aout !
--     et une question me vient comment il choisi les differentes crypto a achete car moi par
--     exemple j avais pris le risque fai mais lui comment il choisi ? »

-- ===========================================================================
-- 1. LA FICHE AP EST RETIREE, ET POURQUOI IL A RAISON
-- ===========================================================================
-- docs/maia/AP-10012-achats-recurrents.txt proposait d'ecrire dans le PROMPT du module 10012 :
--   « BCH, TRX, XLM et XRP sont rachetes chaque semaine (5 GBP) par un plan Revolut. »
-- C'est un fait vrai AUJOURD'HUI. Le jour ou Chachou change son plan — un montant, une devise,
-- une ligne de plus — la phrase continue de partir dans le prompt et ment, sans que personne
-- ne s'en apercoive. C'est exactement le mecanisme des huit tickers en dur du module 401 et des
-- APY en dur de generate_daily_journal §6.
-- La fiche n'est pas appliquee. Elle reste au depot comme trace de la tentative.

-- ===========================================================================
-- 2. LA TABLE : LE PLAN VIT LA, ET NULLE PART AILLEURS
-- ===========================================================================
create table if not exists public.alc_achats_recurrents (
  id             bigserial primary key,
  devises        text[]      not null,                      -- {BCH,TRX,XLM,XRP}
  montant        numeric     not null,                      -- 5
  devise_montant text        not null default 'GBP',
  frequence      text        not null default 'hebdomadaire',
  actif          boolean     not null default true,
  note           text,
  maj_at         timestamptz not null default now(),
  maj_par        text default 'chachou'
);
comment on table public.alc_achats_recurrents is
  'Plans d''achat programmes DANS Revolut, hors robot. Lu a chaque appel par revolut-x-read '
  'qui en fabrique une phrase pour soldes_texte. Chachou modifie la ligne, la phrase suit. '
  'Rien de tout ceci n''est ecrit dans un prompt ni dans du code.';

-- Ligne 1 (deja inseree) : {BCH,TRX,XLM,XRP}, 5, GBP, hebdomadaire, actif.
-- Ses achats du 17, 24 et 31 aout a 14:04-14:05 le confirment : quatre ordres de 1,68 a 1,72 $
-- chaque dimanche, soit 6,77 $ = 5 GBP au cours du jour. Ce n'etait pas le robot.

-- ===========================================================================
-- 3. revolut-x-read v13 — LA PHRASE EST FABRIQUEE, PAS ECRITE
-- ===========================================================================
-- La fonction lit alc_achats_recurrents (actif = true) et ajoute a la fin de soldes_texte :
--
--   || ACHATS RECURRENTS PROGRAMMES PAR LE PROPRIETAIRE, HORS ROBOT (Revolut les execute seul,
--   tu n'en es ni l'auteur ni le destinataire ; c'est une information de contexte, pas une
--   consigne): BCH, TRX, XLM, XRP rachetes automatiquement par Revolut (5 GBP au total,
--   hebdomadaire, repartis entre ces 4 lignes) [<note>]
--
-- Regle du 26/08 respectee : le FAIT est transmis, jamais le verbe d'action. Chachou l'a
-- tranche ainsi — « il en tient compte comme il veut ».
--
-- TESTE EN REEL apres deploiement (appel pg_net, reponse 6169) :
--   ok=true · count=48 · tableau `soldes` : 48 entrees, INCHANGE (alc-auto n'est pas affecte)
--   soldes_texte : 2 548 caracteres, la phrase est bien en fin de chaine
-- Aucun module Make, aucun prompt n'a ete touche.
-- Si la table est vide, absente ou injoignable, la phrase disparait et la sortie redevient v12.

-- ===========================================================================
-- 4. L'HISTORIQUE REVOLUT : LA QUESTION EST TRANCHEE, PAR MESURE
-- ===========================================================================
-- Chachou a colle son ecran « Ordres » (BTC/SOL/ETH/LTC/TRX/XRP/XLM/BCH, jusqu'au 17 aout).
-- Cet ecran n'a PAS d'equivalent API sur cette cle. Sonde des huit chemins, 05/09 :
--   /api/1.0/balances      200      /api/1.0/transactions  200
--   /api/1.0/trades        401      /api/1.0/orders        401
--   /api/1.0/fills         401      /api/1.0/positions     401
--   /api/1.0/portfolio     401      /api/1.0/statements    401
--
-- Et /api/1.0/transactions ne se pagine pas. Trois requetes, trois reponses de 10 560 octets
-- au caractere pres : ?limit=200, ?count=200, ?from=1755000000000 sont IGNORES.
-- Le corps porte metadata.next_cursor = "" (chaine vide) : Revolut declare lui-meme qu'il n'y
-- a pas de page suivante. 50 lignes, du 30/08 01:07 au 05/09 08:57.
--
-- CONCLUSION : le prix de revient des lignes heritees (FAI 103 $, UNI 95 $, TRU 64 $, MEW 55 $,
-- HFT 49 $ — un tiers du portefeuille) est INACCESSIBLE par l'API. La seule source est l'ecran
-- de l'application. Ce n'est pas « a chercher encore » : c'est ferme.

-- ===========================================================================
-- 5. COMMENT L'ALCHIMISTE CHOISIT SES CRYPTOS — MESURE, PAS SUPPOSITION
-- ===========================================================================
-- 81 propositions depuis le 13/08, 19 paires distinctes nommees sur les 302 qu'il recoit.
--   BTC 25 · TRU 9 · ETH 7 · TRX 5 · DOGE 3 · XLM 3 · AVAX 3 · SOL 3 · HFT 3 · le reste 1 ou 2
--
-- Croisement de ces 19 paires avec les 48 lignes du portefeuille :
--   deja detenues ......... 16   (ANKR BTC DOGE ETH HFT IDEX LRC LTC MEW OSMO RLC SOL TRU TRX XLM XRP)
--   jamais detenues ....... 3    (AVAX, LINK, SQUID)
-- En 23 jours il a donc « decouvert » TROIS noms, dont deux figurent parmi les majeures citees
-- partout. Il ne choisit pas dans 302 paires : il choisit dans ce qu'il a deja, plus la poignee
-- de majeures que le contexte lui nomme.
--
-- POURQUOI, ET CE N'EST PAS UN DEFAUT DU MODELE :
--   a) Les 302 paires lui arrivent par revolut-x-prices en bid/ask INSTANTANE. Pas de variation,
--      pas de volume, pas de tendance. Devant « ABC-USD bid 0,0271 ask 0,0273 », rien ne
--      distingue une paire d'une autre : il n'y a aucune information a exploiter.
--   b) Le contexte macro (module 110, variable CTX) ne cote que QUATRE cryptos : BTC, ETH, SOL,
--      DOGE. Ce sont les seuls noms sur lesquels il dispose d'un chiffre. D'ou ses propres
--      motifs, releves dans ses propositions : « respectant la recommandation de rester large
--      sur BTC ETH SOL », « le contexte fourni est haussier avec une preference explicite pour
--      BTC/ETH ». Cette « recommandation » n'existe nulle part : personne ne l'a ecrite. Il la
--      deduit du fait que ce sont les seules valeurs qu'on lui chiffre.
--
-- CE QUE LA BASE SAIT DEJA ET QU'ON NE LUI ENVOIE PAS :
-- price_history couvre les 302 paires en horaire (0 paire sans historique recent). Le classement
-- des variations mesure ce matin :
--   IOTX-USD  +52,7 % /24h  (+60,0 % /7j)      NEAR-USD  +12,8 %  (+19,9 %)
--   BLZ-USD   +33,8 %       (+34,0 %)          PERP-USD  +11,1 %  ( +1,9 %)
--   DASH-USD  +25,3 %       (+65,8 %)          STRK-USD  +11,0 %  (+16,1 %)
--   ZEN-USD   +16,8 %       (+42,3 %)          XCN-USD   +10,0 %  (+21,2 %)
-- Aucun de ces huit noms n'a jamais ete propose. FAI, la ligne que Chachou a prise lui-meme,
-- n'a jamais ete nommee non plus : il ne peut pas la voir bouger.
--
-- LA SUITE EST UNE DECISION DE CHACHOU, PAS UNE LIVRAISON :
-- ajouter var_24h et var_7j (et le volume) a chaque paire dans revolut-x-prices, c'est-a-dire
-- lui donner la MESURE qui manque. On ne lui dit toujours pas quoi acheter — c'est le contraire :
-- aujourd'hui il choisit parmi 5 noms parce qu'on ne lui en chiffre que 5.
-- Cout : le champ prix_texte passerait de ~8 100 a ~13 000 caracteres. A tester avant.
