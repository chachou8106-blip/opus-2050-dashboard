# Kill-switch Alchimiste — fonctionnement & secours (anti-lockout)

## Ce que c'est
`ju_crypte_config.kill_switch` arme/désarme le trading RÉEL de l'Alchimiste sur Revolut X.
- `ON`  = ordres réels actifs.
- `OFF` = désarmé, aucun ordre réel.

Contrôlé depuis le bouton dans `console_aether 2.html` (section « Espace opérationnel »),
via l'edge function `ju-killswitch`.

## Sécurité (option A)
- **DÉSARMER (OFF)** et **STATUS** : toujours libres, sans PIN. → on peut TOUJOURS revenir au sûr.
- **ARMER (ON)** : exige le PIN stocké dans `ju_crypte_config.arm_pin` (jamais exposé au client).

## ⚠️ Impossible d'être bloqué dangereusement
1. OFF ne demande jamais de code → on ne reste jamais coincé en position armée.
2. Le PIN vit dans la base → il est lisible/modifiable à tout moment.
3. En dernier recours on écrit le switch directement en base.

## Procédures de secours (SQL, via Supabase MCP `execute_sql` ou le SQL editor)
Projet : `smddzybxebwhfnitxuyp`

```sql
-- Voir l'état + le PIN
select key, value from ju_crypte_config where key in ('kill_switch','arm_pin');

-- Forcer le désarmement (sûr, à faire en cas de doute)
update ju_crypte_config set value='OFF' where key='kill_switch';

-- Forcer l'armement (argent réel !)
update ju_crypte_config set value='ON' where key='kill_switch';

-- Changer le PIN
update ju_crypte_config set value='<NOUVEAU_PIN>' where key='arm_pin';
```

PIN initial : `2050` (à changer). Le bouton demande ce PIN uniquement pour ARMER.
