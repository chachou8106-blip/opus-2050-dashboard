PROMPT MAIA — scénario 6183820 — Journaliser le VERDICT de l'Alchimiste (commentaire + dé-stake)

OBJECTIF : aujourd'hui le raisonnement de l'Alchimiste (son `commentaire` et sa liste `destake_recommande`)
n'est stocké NULLE PART → impossible de savoir après coup POURQUOI il dé-stake ou pas. On ajoute UN module
qui envoie sa sortie brute à Supabase, qui l'archive et l'analyse. Côté Supabase c'est déjà prêt et testé
(table `alchimiste_crypte_verdicts`, RPC `log_alc_verdict`). Il ne reste qu'à ajouter le module d'envoi.

════════════════════════════════════════════════════════════════════════
AJOUTER 1 MODULE — « 📖 LE VERDICT SCELLÉ » (HTTP POST vers Supabase RPC)
════════════════════════════════════════════════════════════════════════
Place-le APRÈS le module de l'Alchimiste (« Tu es L'ALCHIMISTE DE LA CRYPTE… », api.perplexity.ai) —
juste après lui, ou après son parse « Le Parchemin de la Decision ». Il doit s'exécuter une fois que
l'Alchimiste a répondu. C'est un log « fire-and-forget » : il ne doit JAMAIS bloquer le run.

Configuration du module HTTP :
- Méthode : POST
- URL : https://smddzybxebwhfnitxuyp.supabase.co/rest/v1/rpc/log_alc_verdict
- En-têtes : COPIE EXACTEMENT les en-têtes (apikey + Authorization) du module Supabase déjà fonctionnel
  « 📜 LE SCEAU DES SAGES » (même projet Supabase, même clé). Ajoute Content-Type: application/json.
- « Return error if HTTP request fails » (stopOnHttpError) : DÉCOCHÉ (false) — ne bloque pas le run.
- Corps (JSON string) :

{"p_run_id":"{{ifempty(101.RUN_ID; formatDate(now; \"YYYYMMDD-HHmm\"))}}","p_raw_b64":"{{base64(10012.data.choices[1].message.content)}}"}

Explication : `10012.data.choices[1].message.content` est le JSON BRUT que produit l'Alchimiste
(propositions + destake_recommande + commentaire). On l'envoie en base64 (pour ne pas casser sur les
caractères spéciaux) ; la RPC le décode et le parse côté serveur, donc AUCUN `toString` n'est nécessaire.

NB : si l'ID interne du module Alchimiste n'est pas 10012 chez toi, remplace « 10012 » par l'ID réel du
module Alchimiste (celui dont le texte système commence par « Tu es L'ALCHIMISTE DE LA CRYPTE… »),
en gardant `.data.choices[1].message.content`.

════════════════════════════════════════════════════════════════════════
NE TOUCHE À RIEN D'AUTRE
════════════════════════════════════════════════════════════════════════
- N'ajoute que ce module. Ne modifie ni le prompt de l'Alchimiste, ni les modules prix/staking, ni les
  autres branches, ni les IDs/connexions existants.
- Après un run, la table `alchimiste_crypte_verdicts` doit recevoir 1 ligne (commentaire + destake +
  nb propositions), et `parse_ok` doit être true. C'est le signe que tout est bon.
