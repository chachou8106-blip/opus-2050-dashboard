# Connexion Darwinex — plan d'exécution (2026-08-18)

## Ce qui EXISTE déjà (vérifié, rien à construire côté Supabase)
- **`mt5-bridge` v3** (edge function, déployée) : sert le livre exact par mode —
  `?mode=JU | SYL | GIL | COLLEGE` → `SYMBOLE;poids_signé_%` (négatif = short).
  Protégé par token (`?token=` ou header `X-Bridge-Token`, env `MT5_BRIDGE_TOKEN`). Lecture seule.
- **RPC `mt5_book`** : testée le 18/08 — COLLEGE renvoie le portefeuille agrégé live
  (XLU 8,37 % · SPY 5,24 % · XLF 4,87 % · … · ETHUSD 0,62 %).
- **L'EA MetaTrader** de réplication existe déjà (le « Trading Algo » mentionné dans suivi.html).

## Correspondance DARWIN ↔ mode du bridge
| DARWIN | mode bridge | contenu |
|---|---|---|
| $JUL | `JU` | Actions US |
| $SYL | `SYL` | Paniers ETF |
| $GIL | `GIL` | Contrarian |
| **Æ $AET** | `COLLEGE` | JU+SYL+GIL agrégés (pondérés Méta-Cerveau) |

## Ce qu'il reste à faire (côté Darwinex / MT5 — actions Chachou)
1. Dans l'espace Darwinex : créer les **comptes stratégie MT5** (un par DARWIN visé ;
   commencer par UN seul — recommandé : `COLLEGE` ou le forex Marées*).
2. Sur le VPS / la machine MT5 : brancher l'EA existant sur le serveur MT5 Darwinex
   (login + mot de passe du compte stratégie, saisis DANS MetaTrader — jamais dans Supabase/git).
3. Configurer l'EA : URL = `https://smddzybxebwhfnitxuyp.supabase.co/functions/v1/mt5-bridge?mode=<MODE>`
   + le token bridge (déjà en variable d'env de la fonction — ne pas le coller ailleurs).
4. Activer « Trading Algo » dans MetaTrader **uniquement quand les 4 gates du réel sont vertes**.

## Points de vigilance (à vérifier avant le premier ordre réel)
- **Mapping des symboles** : Darwinex nomme ses CFD actions/ETF différemment (ex. suffixes).
  Prévoir une table de correspondance dans l'EA ou filtrer les tickers non disponibles.
- **Crypto** : ETHUSD & co ne sont pas répliquables sur Darwinex → l'EA doit ignorer les
  tickers crypto (l'Alchimiste reste sur Revolut X).
- **Marées (forex)** : univers 100 % compatible Darwinex — candidat naturel au premier DARWIN réel*
  (mais pas encore de mode dédié dans mt5_book ; à ajouter SEULEMENT si on lance Marées en premier).
- **Risk Engine Darwinex** : normalise le VaR du DARWIN — ne pas sur-dimensionner les poids.

*Décision à prendre au point d'étape du 28/08.
