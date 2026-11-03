# Contract: `hpForecast` / `forecastHp` (fact)

```
name / version / owner:  hpForecast / 1 (slice pre-hit, 04/11/2026: first contract) / engine (main loop)
layer:          game fact (no choice, no action)
intent:         A creep's HP over the next seconds from the hits the attacker index already sees, for a caller that plans
                beyond the one swing lastHit makes.
applicability:  A bot handle and a visible lane creep; horizon in seconds, finite (cut to 10 s).
inputs:         bot, creep, horizon. forecastHp(f, t): the forecast and seconds from now.
sources:        Valve API reads only: GetIncomingTrackingProjectiles (is_attack, caster, location),
                GetAttackProjectileSpeed, GetAttackDamage, GetSecondsPerAttack, GetActualIncomingDamage (physical),
                GetHealth, GetHealthRegen, GetAttackTarget (the attacker index, per frame), the wind-up reading
                (GetAnimActivity / GetAnimCycle / GetAttackPoint, as windupLanding: UNVERIFIED that the attack point is a
                fraction of the attack cycle), GetNearbyTowers / GetNearbyHeroes for the attacker kinds.
result:         { hp, regen, horizon, hits[{ t, damage, by: tower|creep|hero|self }] sorted by t, unphased, unphasedTower }.
                hits: every attack projectile in flight (the bot's own included), every wind-up seen landing within the
                horizon, and for a tower or lane creep its latest known hit repeated every attack cycle while it attacks
                the creep now. unphased: DPS after armour of the attackers on it with no hit in flight or wind-up, spread
                from 0.45 s on. unphasedTower: a tower is among those. forecastHp = hp + regen t - hits by t -
                unphased max(0, t - 0.45); below 0 means dead by then.
assumptions:    repeats keep today's distance and so flight time; an attacker stays on the creep (UNVERIFIED in-game: towers
                re-target on hero aggro or when the creep leaves range); heroes are not repeated (their attacks are choices).
outcomes:       none (a query); an empty forecast (hits {}, unphased 0) when no one attacks the creep.
timing:         one projectile scan and the per-frame attacker index (shared with lastHit's belief); O(attackers x
                horizon / attack cycle).
skill:          none (exact; a caller adds error where it decides).
consumers:      bot `states/pre_hit` (a core's pre-hit under its tower, in game from slice pre-hit); named: a support's
                pre-hit for its core (slice pre-hit open item, user 04/11/2026), staggering two creeps due at once
                (docs/proposals/2026-11-04-prehit-and-feints.md "Pre-hit: potential" item 2).
status:         offline-verified (engine test_prehit: forecast within 1 HP of the sim between hits); in game: check run
                prhchk1 (slice pre-hit).
```
