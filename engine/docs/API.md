# Engine API (lua-tasks v0.2): design

Date: 23/10/2026. Status: work packages 1-4 built and tested offline (fengari + LuaJIT); runner and `attackAndConfirm` verified in-game; cast/item/rune and SimpleHost checks outstanding. Supersedes nothing; extends lua-tasks (now `engine/` in the bot repo) without breaking the
OHA integration (`task`, `Step`, `Tick`, `Cancel`, `Urgent`, `Label`, `Verbs.*` keep their signatures).

## Direction (aligned 28/10/2026 to the master `docs/team/PLAN.md`)
This document describes what is built. The project goal changed after it was written: the end state is a bot script on this SDK
with no OHA code left, and the SDK holds only the kernel, engine facts (each citing a source) and atomic actions (master
`CLAUDE.md` hard rule 3). Nothing below is removed by this note; the sections stay accurate until their replacement lands.
Slice 0b (29/10/2026) moved this package into the bot repo as `engine/`, moved the job verbs (with `campNeutral`, `aggroLead`,
`runeArriveBy`, `runeLeaveAt`, their OHA defaults and wording) to bot code and deleted `Phase`. Slice 5 moved the `nextLastHit` biases to bot
code (`laneTargets` returns the facts; `laneFarm` takes `pick`). Scheduled to be added: one travel ETA and rune timing (BACKLOG 1.2), kill timing and
incoming damage (2.2), per-patch camp and rune data. Jitter stays in `Skill`. Public verbs and facts will get contracts under
`docs/contracts/`. Where this document names OHA files or values (the friction table, the Adapter table, the job verbs), read them
as the current host's source, not as SDK vocabulary.

## Why
The live-LLM readout is dead (HTTP bridge NO-GO, `BRIDGE_SPIKE.md`). The goal is an ergonomic way to write bot
behaviour: one readable body per behaviour, resumed each frame, built from verbs that check their own effects.
The O2 stack spike (OHA `stack_task.ts`) is the reference consumer. Its friction points drive this design:

| Friction in `stack_task.ts` | v0.2 answer |
|---|---|
| `Tasks.Verbs()!`, `bot as unknown as Lib.TaskUnit` on every verb call | `ctx` passed to the body, with verbs bound to the bot |
| `Tasks.Label(bot, ..)`, `Tasks.Urgent(bot, ..)` | `ctx.label(..)`, `ctx.urgent(..)` |
| `if (!r.success) return r` after every verb | `yield* ctx.must(verb)`: a failed verb ends the task with its result |
| `interruptIf: () => DotaTime() >= until` | `deadline` option on every verb (`timeout` when passed) |
| hand-rolled retry `do { .. } while (..)` | `retry`, `watch`, `withTimeout`, `race` combinators |
| only OHA can host tasks | `SimpleHost`: an `Adapter` plus mode-file glue for any bot script |

## Conventions (all verbs)
- A verb is `function*(bot, ..., opts?) : TaskBody`. It yields once per frame and returns a `Result`.
- It **checks its own effect** (moved, attack landed, cooldown started) and fails with a specific `Reason`
  rather than assuming an order worked.
- Common opts: `deadline?: number` (absolute game time, `now()` clock; fails `timeout` once reached) and
  `interruptIf?: () => boolean` (fails `interrupted`). Verb-specific timeouts stay relative seconds.
- A verb that relies on unverified Dota API behaviour says so in its doc comment (`UNVERIFIED in-game: ...`).
- Optional `TaskUnit`/handle methods are feature-detected; a missing one fails `unsupported`, never errors.

## Task context
```ts
Tasks.task(bot, { name: "stack", host: BotMode.Farm }, (ctx) => body(ctx));

function* body(ctx: Ctx): TaskBody {
    ctx.urgent(true);
    ctx.label("travel");
    yield* ctx.must(ctx.walkTo(stand, { deadline: aggroAt + late }));
    ctx.label("wait");
    yield* ctx.waitUntil(aggroAt, { hold: "lane:job_wait" });
    ...
    return ctx.ok();
}
```
`ctx` holds `bot`, `now()`, `elapsed()`, `label`, `urgent`, `ok()`, `fail(reason, message?)` (a value),
`abort(reason, message?)` (throws: ends the task from any depth), `must(gen)` and every verb bound to the bot.
Bodies that ignore the argument keep working.

`must`/`abort` throw a marked table; the runner's resume `pcall` recognises it and finishes the task with the
carried result instead of `error`. Generators that are not run by the runner (e.g. inside `race`) propagate it.

**Hazard: loops that never yield.** A verb that fails or finishes on its first resume returns without yielding
(e.g. a walk whose `deadline` has passed). A body that loops over such verbs without checking their results
spins forever inside one frame; nothing can preempt it (Dota's VM gives the runner no instruction hook). Loop
only on results: `must` the step that can fail, or `yield` when retrying by hand. `retry` yields between
attempts for the same reason.

## Combinators
- `watch(gen, check)`: steps `gen`; before each step `check()` may return a message to end with `interrupted`.
- `withTimeout(gen, secs)`: `timeout` after `secs`.
- `retry(times, factory, shouldRetry?)`: re-runs `factory()` while it fails and `shouldRetry(result)` allows.
- `race(...gens)`: steps all each frame, returns the first finished result. Only one branch should issue
  actions; the others should be watchers (`waitUntil`, conditions), or the last order of the frame wins.

## Skill and profile (PLAN 2.6, request S3)
Execution quality scales with the bot's skill. The host supplies it through optional adapter fields, read on
every use (never cached by the SDK), so a mid-game difficulty change applies at once:

| Adapter field | OHA source | Default |
|---|---|---|
| `skill(bot): number` in [0, 1] | `Difficulty.GetSkill(bot)` | 1 |
| `profile(bot): { react, jitter, aimError?, lapse? }` | `Profile.Get(bot)`: `reactBase`, `jitter`, `aimError`, `lapseChance` | `{ react: 0, jitter: 0 }` |
| `lastHitError(bot): number` | `LastHitSkill.ErrorWidth(bot)` (pressure x1.5 included) | `lerp(0.15, 0.02, skill)` |
| `random(): number` in [0, 1) | `RandomFloat(0, 1)` | `math.random()` |
| `attackClock(): number` | `GameTime()` (the clock of `GetLastAttackTime`) | none: attack cooldown not counted |

`ctx.skill()`, `ctx.react()` (one sampled reaction delay, `react * (1 +- jitter/2)`) and `ctx.jitter(secs)`
expose these to bodies. They are functions rather than the plain `ctx.skill` field PLAN 2.6 sketched, so every
read goes through the adapter. Bodies and verbs never read OHA directly.

## lastHit v2 and deny (request S4)
`lastHit(bot, opts)` last-hits an enemy lane creep, `deny(bot, opts)` an allied one. Options: `target`,
`searchRadius` (default attack range + 300), `maxWait` (s to wait for the creep to become due, default 1.5),
`deadline`, `interruptIf`, `hold` (tag passed to the adapter's `hold` while standing in range).

**Choosing.** Without `target`: the creep within `searchRadius` (for `lastHit`, allowed by `lastHitFilter`)
closest to dying to the bot's hit; above skill 0.6, a ranged/siege creep (by unit name) that is killable now
wins over a melee one.

**Lane targets (`Verbs.laneTargets(bot, opts)`, a query, not a verb).** The lane creeps a laner could go for
next, in no order: `{ creep, kind: "lasthit"|"deny", eta, walk, ranged }[]`. Considers enemy creeps (filtered by
`lastHitFilter`) and allied ones (`deny: false` / `lastHit: false` turn a side off) within `radius` (max(800, range
+ 400)) that become killable at most `within` (1 s) after the bot could be in range: eta = max(walk into range,
(believed HP at our hit - own damage) / incoming DPS), exact (no skill error; the verbs add it when they swing);
`walk` = seconds into attack range at the current speed; `ranged` = a ranged or siege creep (by unit name). Facts
only: which one to take is the caller's choice (slice 5 moved the old `nextLastHit` priority biases to bot code).
Per-frame creep queries are cached per bot.

**`laneFarm(bot, spot, opts)` / `ctx.laneFarm`** (posture verb, src/lane.ts): holds `spot()` (holdAt with
`opts.hold`), and while `lastHits()` allows, breaks off for the creep `opts.pick(targets)` chooses from
`laneTargets` (no `pick`: it only holds), swings through
`lastHit`/`deny` (maxWait eta + 1.5 s, dropped beyond `leash` 900 from the spot), then walks back. Labels
`walk`/`hold`/`lasthit`/`deny` (ctx binds the task label); `onAttempt(target, result, contested)` after every
attempt (contested: an enemy hero within `contestRadius` 1000). Scans for the next creep every `scanEvery` (0.1 s), never beyond the leash. Never ends ok by itself.

**When to swing.** The verb walks into attack range, then each frame computes the own hit time
`t = attackPoint / attackSpeed (+ cooldown left, with attackClock) (+ max(0, dist - 39) / projectileSpeed for
ranged bots)` and fires once `HP + regen * t - incoming(t) <= ownDamage` while `HP + regen * t - incoming(t) >
0` (no swing at a creep someone else kills first). `incoming(t)` counts, after armour
(`GetActualIncomingDamage`): attack projectiles in flight (`GetIncomingTrackingProjectiles`) that arrive within
t, and every visible creep, hero or tower of either team whose attack on the creep is in its wind-up and lands
within t (`(attackPoint - animCycle) * secondsPerAttack`, plus projectile travel for ranged attackers; OHA's
`GetCreepAttackActivityWillRealDamage`). Only hits landing at least a frame margin before ours count (0.034 s,
or 1.2x the observed frame time up to 0.3 s: a hit in the same frame may be applied after ours). With the
adapter's `attackClock` the verb does not order a swing while the attack cooldown has more than that margin
left (unseen future hits would land inside the longer horizon). `deny` also requires the creep below 50% max HP. Turn time is not
modelled; tower "tap first" tricks are the body's.

**Outcome after the swing.** `GetLastAttackTime` rises when the attack fires (a ranged hero's projectile
leaving), so the verb judges by the predicted landing time `swingAt + tHit`: last-hit/deny count up -> ok; creep
gone before landing -> `taken_by_other` (`denied` when an enemy hero was on it); gone after landing or alive
`CONFIRM_SLACK` (0.5 s) past it -> `missed`. Incoming damage reads attackers through one per-frame index by attack
target (attack activities 1503 and 1504); `CanBeSeen` filters enemies only.

**Skill error.** Per bot and creep the verb rolls, once (kept in a weak table until the creep is gone, so
re-calling the verb does not re-roll towards perfect): `eps` in [-1, 1] scaling the believed own damage by
`1 + eps * w`, and a timing shift `(2u - 1) * 2w` seconds, where `w = lastHitError(bot)` (0.04 s at skill 1,
0.25 s at skill 0.2). A lapse (`profile.lapse`, else `lerp(0.15, 0.01, skill)`) adds 0.15-0.4 s of lateness.
A negative shift shortens the prediction horizon: a late swing, lost to others (`taken_by_other`/`denied`). A
positive shift extends it with the attackers' DPS (hits not yet started): an early swing that lands while the
creep is still too healthy (`missed`). There is no random "don't try": a low-skill bot always swings, badly.

**Results.** `ok` once the bot's last-hit (deny) count rises. `missed`: its attack landed (`GetLastAttackTime`
rose) without the kill, or nothing resolved within `t + 0.5` s. `taken_by_other`: the creep died before our
hit (for `deny`: to an enemy last hit). `denied` (lastHit only): an enemy hero was attacking it as it died.
`timeout`, `no_target`, `etiquette` (every candidate vetoed by `lastHitFilter`), `dead`, `interrupted`,
`unsupported` (no `GetAttackDamage`/`GetAttackPoint`; `deny` also needs `GetDenies`).

Offline (sim, 30 fps, a creep contested by three allied melee creeps, 120 trials): skill 1 lands 100%, 0.6 65%,
0.2 50% with both early and late misses. In game the prediction sees less than the sim, so skill 1 should land
below 100% of contested creeps (the 75-85% target of knowledge.md §1.2).

UNVERIFIED in-game: the wind-up formula's units (attack point as a cycle fraction), `GetLastAttackTime` rising
at landing for ranged heroes, projectile `location`/`caster` fields, and `GetNearbyTowers` returning towers
whose `GetAttackTarget` is the creep.

## Job verbs
Moved to bot code in slice 0b: `typescript/bots/FunLib/humaniser/job_verbs.ts` (reference in the bot's
`docs/HUMANISER_DEV.md`, "Job verbs"). They are built from the verbs, `ownHitTime` and `Skill` below.

## Work packages
1. Core: `ctx`, `must`/`abort`, `deadline`, combinators (`Flow`). Done.
2. Cast/item verbs: `cast`, `useItem`, `pickUpRune` with effect confirmation. Done (`verbs_cast.ts`).
3. `SimpleHost`: adapter and mode-file glue for non-OHA bots, `body(fn)` for Lua-authored bodies, and
   `examples/generic/`. Done.
4. O2 stack body ported to v0.2 (later `Verbs.stack`, WP6). Moved to bot code in slice 0b.
5. Skill/profile on the adapter and `ctx` (S3), `lastHit` v2 and `deny` (S4). Done offline
   (`test_lasthit.lua`); in-game check pending (slice 4).
6. Job verbs and `Skill.timingError`. The job verbs moved to bot code in slice 0b; `Skill.timingError` stays.

## Public surface (bundle `tasks.lua`)
| Export | What |
|---|---|
| `Tasks.task/Step/Tick/Cancel/Urgent/Label/Current/Last/Describe` | runner (unchanged signatures; bodies now receive `ctx`) |
| `Verbs.walkTo/walkPath/wait/waitUntil/retreatTo/lastHit/deny/attackAndConfirm` | movement and combat verbs, all with `deadline` |
| `Verbs.incomingDamage/incomingDps/ownHitTime` | the last-hit prediction, for bodies that pick creeps themselves |
| `Skill.of/profile/react/jitter/lastHitError/random` | skill and human-timing helpers read through the adapter |
| `Verbs.cast/useItem/pickUpRune` | ability, item and rune verbs |
| `Skill.timingError/timingSigma/gauss` | skill-scaled timing error for timed actions |
| `Flow.watch/withTimeout/retry/race/until` | combinators |
| `must`, `abort` | failure propagation |
| `SimpleHost.install/desire/think/onEnd/wrapMode/body/SetEnabled/ClaimOf` | standalone host |
| `init`, `Supported` | adapter injection, coroutine probe |
| `Verbs.holdAt` / `ctx.holdAt` | posture verb: keep near a moving point (tolerance, repath cadence + jitter, scatter, `hold` tag); never ends ok; scattered spots are built by the adapter's optional `vector(x, y, z)`. `step: [min, max]` makes each new spot an idle step of that length from the bot (kept within `scatter` of the point); `follow` (default tolerance/2) is how far the point must move to force a new spot before `repath` |
| `States.define/configure/SetOwned/SetPrior/Tick/Step/Current/Forget` | behaviour states (below) |

## Behaviour states (`States`, team slice 1)
A bot has at most one state; each is `{ name, kind: "posture"|"job", host, floor?, tier?, preemptAfter?,
stallAfter?, score(bot), body, guard?, onEnd? }` (`guard` and `onEnd` are passed to the state's task; `onEnd`
also sees preempts the layer restarts). `States.Tick(bot)` (every frame, before `Tasks.Tick`) selects every `interval`
(0.25 s): highest score wins, the current state gets `+sticky` (0.1); a posture is held `minDwell` (3 s) against
other postures unless its own score turns undefined; a running owned job is only left for a raw score >=
`jobBreak` (0.9) or when its body ends (failure: `cooldown` 5 s). An owned state (`SetOwned(fn(bot, name))`,
read at every selection) runs its body as task `state:<name>` on `host` (floor 0, posture `preemptAfter` 3,
`stallAfter` huge); after an interrupt or death it is restarted on the first frame the host mode is active
(after an error: not before `restart` s). A job whose task is not running (preempted, dead) and whose scorer
has withdrawn it is left at once (`why=n/a`). It never replaces another task. `States.Step(bot, host)` from the
host's Think. Events through the adapter's optional `event(name, fields)` (else `log`): `state` (pid from to
score owned why=start|best|n/a|break|ended|own|disown), `state_start` (pid state n gap after), `state_task`
(pid state result reason msg label steps). `States.SetPrior(fn(bot, state, raw))` multiplies/replaces every raw
score before stickiness and the job-break check (no consumer since `Phase` was deleted in slice 0b); a failing prior is
logged, the raw score kept.

## In-game checks outstanding
Verified on 23/10/2026 (match 9057344728, OHA O2 stack task): bundle loads, a task's claim wins its host
mode, the host's `Think` steps it, `walkPath` drives the bot, labels and `onEnd` report phases.

Verified on 23/10/2026 (dotactl log `2026-10-23T07-11-27-sdk_stack_aggro_diag_3.log`, OHA O2 stack task, camp 2):
`attackAndConfirm` ordered the aggro at 713.4 and finished `ok` at 714.6 with `GetLastAttackTime()` risen
(723.50 to 863.13; it runs on a different clock from `DotaTime()`, which the verb never compares against); the
exit walk ran and the task ended cleanly (OHA: `lane_stack ... aggro=54.6 planned=53.5 stacked=1`). A thrown
error in a body ends the task with `error` and is logged (`stack_task.lua` diag bug). Item 13 answered by OHA's
`SharedStateProbe`: required modules are shared per team (`playersInThisModule=4 bothTeamsInThisModule=false`).

Found while testing (OHA, not SDK): `CampJobs.CampNeutral` needs the neutral strictly inside the spawn box,
but idle neutrals stand just outside it, and from camp 1's stand point the box is out of sight; 22 natural
stack attempts over 3 games ended `mistake:no-camp`. The spike passed with a pick using `Radii.BoxMargin`.
The job verbs' `campNeutral` (bot code since slice 0b, `humaniser/job_verbs`) applies the margin (300) itself; the caller should pass the box, not its pick.

Runner and combat:
1. Done (above).

Cast/item/rune verbs (`verbs_cast.ts`):
2. Cooldown (`GetCooldownTimeRemaining`) or mana drop is visible within a frame of the cast point ending.
3. `IsInAbilityPhase()` holds for the whole cast point (fallback `bot:IsCastingAbility()`, any ability).
4. A stun-cancelled cast starts no cooldown and costs no mana.
5. Re-issuing a cast order before its phase starts is harmless (re-ordered every 0.5 s until seen).
6. Channelled abilities start their cooldown when the channel starts; `ability:IsChanneling()` works.
7. Abilities with no cooldown and no mana cost cannot be confirmed (they time out); charge-based ones rely on mana.
8. `FindItemSlot` returns a main-slot copy with duplicates; TP (15) and neutral (16) slots are not searched.
9. `GetRuneStatus` leaves `AVAILABLE` within a frame of pick-up; `Action_PickUpRune` is harmless once it is gone.
10. A rune vanishing in range with our pick-up ordered is assumed ours unless `confirmed` is passed.

SimpleHost:
11. `GetDesire` is called every frame for every mode, including while the bot is dead.
12. `GetActiveMode()` during `GetDesire` returns the previous frame's mode; `OnEnd` runs before the switch.
13. Done (above): modules are shared per team. SimpleHost keys by player ID, so this is safe.
14. The example: `require(GetScriptDirectory().."/tasks")` loads the bundle, Dota `Vector` works as a verb
    location, and floor 0.75 beats laning at 0:30.
