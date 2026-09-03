-- La boucle des ordres reels se referme. 03/09/2026, apres le premier trade reel.
--
-- LES TROIS TROUS CONSTATES SUR L'ORDRE DE 15:49 (BTC-USD, 2,50 $, filled)
--   a) la proposition 75 est restee oui_at = NULL, prix_exec = NULL : rien ne reliait
--      la ligne de ju_crypte_orders a la proposition qui l'avait causee ;
--   b) ju_crypte_orders n'avait AUCUNE colonne de prix, et revolut-x-trade jetait toute
--      la reponse de Revolut sauf venue_order_id et state -> le prix paye n'existait
--      nulle part, donc le spread reellement subi etait impossible a mesurer ;
--   c) aucun stop sur le compte reel.
--
-- (a) et (b) sont repares. (c) est OUTILLE mais PAS ARME : voir la fin du fichier.

-- ---------------------------------------------------------------------------
-- 1. LES COLONNES
-- ---------------------------------------------------------------------------
alter table public.ju_crypte_orders
  add column if not exists prix_exec numeric,        -- prix publie par Revolut, NULL si absent
  add column if not exists qty_exec numeric,         -- quantite de base recue, NULL si absente
  add column if not exists proposition_id bigint,    -- le lien qui manquait
  add column if not exists reponse jsonb;            -- la reponse BRUTE, pour MESURER le schema

alter table public.alchimiste_crypte_propositions
  add column if not exists order_id text;

-- Pourquoi une colonne `reponse` brute : je ne connais pas le schema de reponse de
-- Revolut X et je n'ai aucun moyen de l'interroger depuis ici. Plutot que de deviner des
-- noms de champs, revolut-x-trade v9 garde la reponse entiere. Au prochain ordre reel on
-- lira les vrais noms, et l'extraction pourra etre resserree sur du mesure.

-- ---------------------------------------------------------------------------
-- 2. LE LIEN MANQUANT DE L'ORDRE DU 03/09 15:49, REPARE
-- ---------------------------------------------------------------------------
-- Identification certaine, pas une supposition :
--   . au run de 15:45 alc-auto filtre sur run_id = 'COLLEGE-20260903-1545' : seule la
--     proposition 75 etait dans le perimetre (la 69, du run de 12h12, ne l'etait pas) ;
--   . montant plafonne de la 75 = min(50, cash 2,52) = 2,50 -> l'ordre fait 2,50 pile,
--     la 69 aurait donne 2,52 ;
--   . 1,2 seconde separe la proposition de l'ordre ;
--   . c'est le seul ordre reel de la journee.
--
-- update alchimiste_crypte_propositions
--    set oui_at = '2026-09-03 13:49:03.340168+00', order_id = '5b757821-...'
--  where id = 75 and oui_at is null;
-- update ju_crypte_orders set proposition_id = 75 where order_id = '5b757821-...';
--
-- prix_exec reste NULL : le prix paye n'a jamais ete enregistre, et je ne l'invente pas.
--
-- CE N'EST PAS QUE DE LA COMPTABILITE : la proposition 75 etait encore 'proposee' sans
-- oui_at. Un rejeu du run 1545 l'aurait RACHETEE. Le garde-fou d'idempotence d'alc-auto v7
-- s'appuie sur oui_at ; sans cette reparation il n'avait rien a mordre.
--
-- statut n'est PAS touche : alc_rebuild_virtual ne lit que 'proposee' et 'expiree'.
-- Verifie apres coup : prosrc de alc_rebuild_virtual ne contient ni oui_at, ni order_id,
-- ni prix_exec. Le carnet virtuel ne peut pas etre affecte par ces ecritures.

-- ---------------------------------------------------------------------------
-- 2 bis. LA QUANTITE, DONNEE PAR CHACHOU DEPUIS L'APP REVOLUT X (03/09 au soir)
-- ---------------------------------------------------------------------------
-- L'ordre de 15:49 a donne 0,00003173 BTC pour 2,50 $.
--
--   prix paye     = 2,50 / 0,00003173 = 78 789,79 $/BTC
--   prix_ref vise =                     78 806,06 $/BTC
--   ecart         =                        -0,0206 %
--
-- La quantite est affichee a 8 decimales, donc arrondie. Encadrement honnete :
-- quantite reelle entre 0,000031725 et 0,000031735 -> prix entre 78 777,38 et
-- 78 802,21, soit un ecart entre -0,036 % et -0,005 %. Dans tous les cas : NEGATIF.
--
-- CE QUE CA DIT, ET CE QUE CA NE DIT PAS.
-- Ca dit que sur cet ordre-la le cout d'entree n'a rien coute : le prix paye est
-- LEGEREMENT SOUS le prix vise. Coherent avec le spread aller-retour de BTC-USD
-- mesure au 07/07 (0,021 %, soit ~0,010 % par cote) : sur BTC le spread est
-- negligeable, et le prix a simplement bouge d'un cheveu entre la cotation et le fill.
-- Ca NE dit PAS que le spread moyen de la strategie est nul : c'est UN fill, sur la
-- paire la plus liquide de l'univers. TRU-USD reste a 3,299 % aller-retour.
-- Ca ne dit rien non plus d'une eventuelle commission prelevee en USD par-dessus :
-- elle ne serait pas visible dans la quantite recue.
--
-- PROVENANCE TRACEE. La colonne prix_source dit d'ou vient le chiffre :
--   'saisie_manuelle_chachou_app_revolut' ici. Les lignes futures auront prix_source
--   a NULL et reponse renseignee -> valeur extraite de l'API. Un prix saisi a la main
--   ne doit jamais pouvoir passer pour une mesure automatique.
alter table public.ju_crypte_orders
  add column if not exists prix_source text;

-- update ju_crypte_orders set qty_exec = 0.00003173, prix_exec = 78789.79,
--        prix_source = 'saisie_manuelle_chachou_app_revolut' where order_id = '5b757821-...';
-- update alchimiste_crypte_propositions set prix_exec = 78789.79 where id = 75;

-- ---------------------------------------------------------------------------
-- 3. LA SURVEILLANCE DES POSITIONS REELLES (trou c, partie outillage)
-- ---------------------------------------------------------------------------
-- Ce que la vue dit, et qui n'existait nulle part : pour chaque achat reellement execute,
-- son prix d'entree, les seuils TP/SL choisis par l'Alchimiste, le dernier prix connu,
-- et si un seuil est franchi.
--
-- prix_entree_mesure dit la verite sur l'entree : false = on utilise prix_ref (ce que le
-- modele visait), faute de prix paye. sorties_choisies dit si le TP/SL vient de l'agent
-- ou du repli 5/4.

create or replace view public.v_alc_positions_reelles as
with achats as (
  select p.id, p.run_id, p.paire, p.montant, p.prix_ref, p.prix_exec,
         coalesce(p.prix_exec, p.prix_ref) as prix_entree,
         (p.prix_exec is not null) as prix_entree_mesure,
         coalesce(p.tp_pct, 5) as tp_pct, coalesce(p.sl_pct, 4) as sl_pct,
         (p.tp_pct is not null and p.sl_pct is not null) as sorties_choisies,
         p.order_id, p.oui_at
  from public.alchimiste_crypte_propositions p
  where p.oui_at is not null and lower(p.side) = 'buy'
),
ventes as (
  select p.paire, p.oui_at
  from public.alchimiste_crypte_propositions p
  where p.oui_at is not null and lower(p.side) = 'sell'
),
dernier as (
  select distinct on (ph.symbol) ph.symbol, ph.close, ph.ts
  from public.price_history ph
  where ph.interval = '1h'
  order by ph.symbol, ph.ts desc
)
select a.id, a.run_id, a.paire, a.montant, a.order_id, a.oui_at,
       a.prix_ref, a.prix_exec, a.prix_entree, a.prix_entree_mesure,
       a.tp_pct, a.sl_pct, a.sorties_choisies,
       d.close as prix_actuel, d.ts as prix_actuel_ts,
       round(((d.close / nullif(a.prix_entree,0) - 1) * 100)::numeric, 3) as variation_pct,
       round((a.prix_entree * (1 + a.tp_pct/100))::numeric, 6) as seuil_tp,
       round((a.prix_entree * (1 - a.sl_pct/100))::numeric, 6) as seuil_sl,
       exists (select 1 from ventes v where v.paire = a.paire and v.oui_at > a.oui_at) as vendue_depuis,
       case
         when d.close is null then 'prix indisponible'
         when exists (select 1 from ventes v where v.paire = a.paire and v.oui_at > a.oui_at) then 'cloturee par une vente'
         when d.close >= a.prix_entree * (1 + a.tp_pct/100) then 'TP FRANCHI'
         when d.close <= a.prix_entree * (1 - a.sl_pct/100) then 'SL FRANCHI'
         else 'en cours'
       end as etat
from achats a
left join dernier d on d.symbol = a.paire
order by a.oui_at desc;

-- Premiere lecture, 03/09 17:43 :
--   id 75 · BTC-USD · entree 78 806,06 (prix_ref, pas mesure) · TP 5 % / SL 3 % choisis
--   prix actuel 80 712,46 (bougie de 17:00) · +2,419 % · TP 82 746,36 · SL 76 441,88
--   etat : en cours

-- ---------------------------------------------------------------------------
-- 4. CE QUE JE N'AI PAS FAIT, ET POURQUOI (trou c, partie execution)
-- ---------------------------------------------------------------------------
-- La vente automatique sur franchissement de seuil N'EST PAS ARMEE. Deux faits me
-- manquent, et aucun ne se devine :
--
--   1. LA QUANTITE ACHETEE -> LEVE le 03/09 au soir : 0,00003173 BTC (cf 2 bis).
--      La vente pourrait donc etre calculee sur une quantite REELLE et non estimee.
--      Il reste la derive entre le calcul et le fill : une vente doit viser une marge
--      (vendre 99 % de la valeur detenue) pour ne pas mordre sur le reste du BTC.
--
--   2. LA FORME D'UNE VENTE PARTIELLE. revolut-x-trade envoie un quote_size en dollars.
--      Si le SL est franchi, la position vaut MOINS que ce qu'on a paye : demander a
--      vendre 2,50 $ de BTC alors qu'on n'en detient que 2,42 $ mordrait sur le reste du
--      portefeuille BTC. Il faudrait vendre en quantite de base (base_size), et je n'ai
--      aucun moyen de verifier depuis ici que l'API l'accepte.
--
-- Le point 1 est leve. Le point 2 ne l'est pas, et il suffit a bloquer : je ne peux
-- pas exercer une vente sans vendre du vrai BTC. La surveillance signale, Chachou coupe
-- a la main, et l'armement de la vente automatique attend son accord explicite en
-- connaissance du risque (regle du 20/08).
