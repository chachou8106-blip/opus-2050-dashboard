-- Le journal des ordres REFUSES. 03/09/2026, le soir.
--
-- CE QUI MANQUAIT
-- Au run de 18h30, l'Alchimiste a propose ETH-USD pour 0,02 $ (le cash restant apres
-- l'achat BTC de 15:49). L'ordre a ete refuse, et la raison a DISPARU : dans
-- revolut-x-trade, logOrder n'est appele qu'apres un succes. Un refus partait dans la
-- reponse, puis dans Discord, et rien n'en restait en base.
-- C'est la meme famille de defaut que le .catch vide du 31/08 : un echec qui ne laisse
-- pas de trace.
--
-- Sept points de refus existent dans la fonction :
--   params · kill_switch · whitelist · paire_non_usd · plafond_ordre · plafond_jour
--   et « envoi_revolut », qui couvre tout ce qui leve dans placeRealOrder (secrets
--   manquants, side invalide, paire mal formee, spot-check en echec, refus de Revolut,
--   reponse sans venue_order_id). Les sept ecrivent desormais ici.

create table if not exists public.ju_crypte_refus (
  id uuid primary key default gen_random_uuid(),
  created_at timestamptz not null default now(),
  pair text,
  side text,
  amount_usd numeric,
  proposition_id bigint,
  dry_run boolean,
  etape text,      -- ou le refus a eu lieu
  raison text      -- le message exact, tel que rendu a l'appelant
);

comment on table public.ju_crypte_refus is
  'Ordres crypte REFUSES. Table separee de ju_crypte_orders A DESSEIN : le plafond journalier '
  'de revolut-x-trade fait la somme des amount_usd de ju_crypte_orders ou dry_run=false. Journaliser '
  'un refus la-bas ferait compter un montant jamais depense contre le plafond de 200 $/jour, et '
  'bloquerait de vrais ordres. Ici, aucun calcul de plafond ne lit cette table.';

-- POURQUOI PAS DANS ju_crypte_orders : c'est le point qui demandait de la prudence.
-- revolut-x-trade calcule le plafond du jour ainsi :
--   ju_crypte_orders?select=amount_usd&dry_run=eq.false&created_at=gte.<aujourd'hui>
-- Un refus de 9 999 $ journalise la-bas aurait sature les 200 $/jour instantanement et
-- bloque tous les ordres suivants. La table separee supprime le probleme au lieu de le
-- contourner par un filtre supplementaire dans le calcul des plafonds — on ne touche pas
-- aux cadenas monetaires pour ajouter un journal.
--
-- TESTS FAITS APRES DEPLOIEMENT (revolut-x-trade v9, version Supabase 10)
--   params        · amount 0                    -> journalise, reponse inchangee
--   plafond_ordre · 9 999 $ vs plafond 50 $      -> journalise avec proposition_id 75
--   paire_non_usd · BTC-EUR                      -> journalise
--   envoi_revolut · achat 1 $ avec 0,02 $ de cash, dry_run=false
--                   -> « SPOT-ONLY refuse: USD dispo 0.02 < 1 USD (pas de levier) »
--                      journalise. AUCUN ordre envoye : le controle de solde intervient
--                      AVANT le POST /api/1.0/orders. C'est le seul moyen d'exercer ce
--                      chemin sans depenser un centime.
--   temoin        · dry_run normal               -> ok:true, log_ok:true, pas de refus
--
-- Puis verification que le plafond du jour n'a pas bouge : 2,50 $, la seule vraie ligne.
-- Lignes de test supprimees.
--
-- LE CHEMIN D'ENVOI N'EST PAS TOUCHE : diff des 39 lignes qui vont de clientOrderId au
-- retour de placeRealOrder — identique au caractere pres.
