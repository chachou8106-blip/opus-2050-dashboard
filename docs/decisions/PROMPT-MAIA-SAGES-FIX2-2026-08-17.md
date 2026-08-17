PROMPT MAIA — scénario 6183820 — CORRECTIF #2 des Sages (après le run 19:33 en 400 silencieux)

CONTEXTE (vérifié dans les logs du run 19:33) : le basculement de fournisseur a réussi côté transport,
mais 2 (voire 3) Sages ont renvoyé une erreur 400 masquée par stopOnHttpError=false :
- 🌌 AURORA BOREALIS (Macro, Perplexity) : 400 « response_format.type must be one of json_schema, text,
  got json_object ». Perplexity refuse json_object.
- ⭐ STELLAR NAVIGATOR (Technique, Groq gpt-oss-120b) : 400 « max completion tokens reached before
  generating a valid document ». gpt-oss est un modèle de raisonnement : max_tokens=800 est trop court.
- 📚 DEEP MEMORY (Mémoire, Groq gpt-oss-120b) : même config → même risque, à corriger aussi.
NE TOUCHE PAS à ⚔️ IRON SENTINEL (Risque, Mistral) ni à ⚡ QUANTUM PULSE (Flash, Perplexity) : ils marchent.

════════════════════════════════════════════════════════════════════════
CORRECTION 1 — 🌌 AURORA BOREALIS (Macro, module Perplexity)
════════════════════════════════════════════════════════════════════════
Dans le corps JSON, remplace le bloc `"response_format": {"type": "json_object"}` par le bloc json_schema
ci-dessous (Perplexity l'exige), et passe `"max_tokens"` de 800 à 1500. Ne touche à RIEN d'autre
(ni URL, ni clé, ni messages) :

"response_format": {
  "type": "json_schema",
  "json_schema": {
    "name": "aurora_macro",
    "schema": {
      "type": "object",
      "properties": {
        "macro_regime": {"type": "string", "enum": ["BULL","BEAR","NEUTRAL","VOLATILE"]},
        "vix_signal": {"type": "string", "enum": ["COMPLACENCY","NORMAL","FEAR","CRISIS"]},
        "spy_trend": {"type": "string", "enum": ["STRONG_UP","UP","FLAT","DOWN","STRONG_DOWN"]},
        "fear_greed_level": {"type": "string", "enum": ["EXTREME_GREED","GREED","NEUTRAL","FEAR","EXTREME_FEAR"]},
        "rate_pressure": {"type": "string", "enum": ["HAWKISH","NEUTRAL","DOVISH"]},
        "news_catalyst": {"type": "string"},
        "macro_score": {"type": "integer"},
        "urgency": {"type": "string", "enum": ["CRITICAL","HIGH","MEDIUM","LOW"]},
        "recommended_bias": {"type": "string", "enum": ["RISK_ON","RISK_OFF","NEUTRAL"]},
        "yield_curve": {"type": "string", "enum": ["NORMAL","INVERTED","FLAT"]},
        "dxy_trend": {"type": "string", "enum": ["STRONG","NEUTRAL","WEAK"]}
      },
      "required": ["macro_regime","vix_signal","spy_trend","fear_greed_level","rate_pressure","news_catalyst","macro_score","urgency","recommended_bias","yield_curve","dxy_trend"],
      "additionalProperties": false
    }
  }
}

════════════════════════════════════════════════════════════════════════
CORRECTION 2 — ⭐ STELLAR NAVIGATOR (Technique, module Groq)
════════════════════════════════════════════════════════════════════════
Dans le corps JSON : garde `"response_format": {"type": "json_object"}` (Groq l'accepte), mais
- passe `"max_tokens"` de 800 à 2000,
- ajoute la clé `"reasoning_effort": "low"` (au même niveau que "model" et "temperature").
Ne touche à rien d'autre (ni URL, ni clé, ni messages).

════════════════════════════════════════════════════════════════════════
CORRECTION 3 — 📚 DEEP MEMORY (Mémoire, module Groq)
════════════════════════════════════════════════════════════════════════
Exactement la même correction que #2 : `"max_tokens"` 800 → 2000, et ajoute `"reasoning_effort": "low"`.
Garde `json_object`. Ne touche à rien d'autre.

════════════════════════════════════════════════════════════════════════
VÉRIFICATION (importante — ne te fie PAS au statut vert des modules)
════════════════════════════════════════════════════════════════════════
Comme stopOnHttpError=false, un 400 s'affiche quand même « success ». Pour valider, ouvre le BODY de
la réponse de chaque module Sage après un run : Status Code doit être 200 et data.choices[0].message.content
doit contenir le JSON attendu (pas d'objet "error"). Les 5 Sages (Macro, Technique, Risque, Mémoire, Flash)
doivent produire un contenu non vide. Si un Sage Groq échoue encore sur les tokens, monte max_tokens à 3000.
