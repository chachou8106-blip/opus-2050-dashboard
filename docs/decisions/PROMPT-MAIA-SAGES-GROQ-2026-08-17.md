PROMPT POUR MAIA — scénario 6183820 « ZCT — Oracle L'Alchimiste Financier v5 VISIONNAIRE »
CORRECTIF CRITIQUE : 4 Sages muets depuis le 15/08 (modèle Groq décommissionné)

────────────────────────────────────────────────────────────────────────
CONTEXTE (vérifié, ne rien inventer)
────────────────────────────────────────────────────────────────────────
Depuis le 15/08 à 12h36, seul le Sage Flash écrit encore dans `oracle_sages_report`.
Les 4 autres Sages — Macro, Technique, Risque, Mémoire — n'écrivent PLUS rien.
Cause racine : ces 4 Sages appellent l'API Groq avec le modèle `llama-3.3-70b-versatile`,
que Groq a DÉCOMMISSIONNÉ (annonce du 17/06/2026, arrêt pour les tiers free/developer).
Groq renvoie donc une erreur « model_decommissioned » ; comme « Return error if HTTP request
fails » (stopOnHttpError) est à FALSE sur ces modules, l'erreur passe en silence : la réponse
n'a plus de `choices[]`, le contenu est vide, donc le module « 📜 LE SCEAU DES SAGES » n'envoie
rien pour ces 4 Sages (RPC `record_sages` n'insère que les Sages non vides).
Conséquence : Risque / Macro / Technique / Mémoire ne produisent AUCUN signal → le Conseil
retombe sur des valeurs par défaut (d'où « Risque dit toujours la même chose », `market_phase`
figé sur DEFENSIVE, `consensus_level` vide). Flash marche car il tourne sur Perplexity, pas Groq.

Flash (Perplexity `sonar-pro`) et les 3 Archimages (JU=Anthropic, SYL=Perplexity, GIL=Mistral)
NE sont PAS concernés : n'y touche pas.

────────────────────────────────────────────────────────────────────────
LA CORRECTION (chirurgicale) — remplacer le modèle Groq mort dans 4 modules
────────────────────────────────────────────────────────────────────────
Dans CHACUN des 4 modules HTTP ci-dessous (ceux qui appellent
`https://api.groq.com/openai/v1/chat/completions`), dans le corps JSON de la requête,
remplace UNIQUEMENT la valeur du champ `"model"` :

    AVANT :  "model": "llama-3.3-70b-versatile"
    APRÈS :  "model": "openai/gpt-oss-120b"

Les 4 modules concernés (repère-les par leur nom / début de texte système) :
  1. 🌌 AURORA BOREALIS   — Sage Macro    (« Tu es … Macro … régimes volatilité liquidité »)
  2. ⭐ STELLAR NAVIGATOR  — Sage Technique (« Tu es … Technique … Wyckoff cycles sectoriels »)
  3. ⚔️ IRON SENTINEL      — Sage Risque   (« Tu es … Risque … Kelly drawdown sizing »)
  4. 📚 DEEP MEMORY        — Sage Mémoire  (« Tu es … Mémoire … patterns historiques »)

`openai/gpt-oss-120b` est le modèle de remplacement recommandé par Groq. Il est
compatible OpenAI : la réponse garde la même forme (`choices[].message.content`),
donc le mapping de « 📜 LE SCEAU DES SAGES » (`{{base64(20X.data.choices[1].message.content)}}`)
et les modules « 💧 DISTILLATION … » (ParseJSON) continuent de fonctionner SANS modification.

────────────────────────────────────────────────────────────────────────
NE CHANGE RIEN D'AUTRE
────────────────────────────────────────────────────────────────────────
- Ne touche PAS aux `messages` (textes système/utilisateur), NI à `temperature`,
  `max_tokens`, `response_format`, ni à aucun autre paramètre du corps.
  (Le Sage Risque garde sa `temperature` 0.3 et ses nouveaux seuils déjà en place.)
- Ne touche PAS au Sage Flash (Perplexity), ni aux Archimages, ni au Cerveau,
  ni aux modules d'exécution/parse, ni aux IDs, connexions et mappings.
- Ne modifie PAS `stopOnHttpError`.
- Après coup, une exécution complète doit tourner sans erreur, et les 5 Sages
  (Macro, Technique, Risque, Mémoire, Flash) doivent réapparaître dans
  `oracle_sages_report` au run suivant.
