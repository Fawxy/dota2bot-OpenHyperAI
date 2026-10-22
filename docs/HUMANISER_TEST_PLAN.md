# Humaniser in-game test plan

Tasks 01–07, 09 (intent arbitration), 14 (last-hit trainer) and the telemetry work were built and checked offline only (`tests/humaniser`: a LuaJIT syntax check, 1,534 behaviour tests in 28 files, 9 replay-mining tests and 7 hlog analyser tests). This plan covers what only the real game can verify. Run it in order: session 1 checks the assumptions the rest of the design rests on, so a wrong answer there may change later code.

Setup is in [HUMANISER_DEV.md](HUMANISER_DEV.md): symlink, lobby, `sv_cheats 1`. Set `Customize.Humaniser.Debug = true` for every session.

Launch Dota with `-condebug` and keep `Telemetry.Enable = true` (see "Telemetry and log analysis"). When something looks wrong, type `!mark <note>` and keep playing. After the session, run `node tools/hlog/analyse.js`: its checks cover most of the "No Lua errors", perception, order and etiquette items below, and `--mark N` shows what each bot was doing at a mark.

## Session 1: foundations (about 15 min, FretBots off, then on)
These answers decide whether code needs to change. Record each result in `HUMANISER_DEV.md`.
- [ ] **No Lua errors** in the console for 15 minutes, with FretBots off and with it on.
- [ ] **Shared-state probe:** read the `[H:probe]` lines (see "Shared-state finding"). Is `playersInThisModule` 1 or 5? Is `bothTeamsInThisModule` true? The orders bus works either way. Perception's teammate callout only works if modules are shared.
- [ ] **Skill resolution:** each bot prints `[Humaniser] pid=... skill=...` at the horn. Check:
  - FretBots off: Valve Easy gives 0.25, Unfair gives 1.0.
  - FretBots on: votes of 1 and 9 show `fret=true/1` and `fret=true/9` with source `chat`.
  - If the source shows `default`, the chat mirror missed the vote; note when you typed it.
- [ ] **Chat hub:** bot reply chatter still answers normal team chat, `!sp ru` still switches language, and `!htest gather` makes the 2 nearest bots acknowledge and walk to you.
- [ ] **Overlay:** each bot's block shows its mode, `skill`, `delay`, `order`, `percept`, `react`, `lasthit` and `ping`/`cmd` lines. Adjust `DIRE_X` in `debug.ts` if the Dire column is off-screen.

## Session 2: ping semantics (step 0 in the "Ping response (05)" section)
- [ ] Fill in the `normal_ping` table for each ping action. If danger pings come through as `normal_ping == true`, flip `Pings.IsDangerPing`.
- [ ] Ping the ground: the 2 nearest bots acknowledge with one chat line and one return ping.

## Session 3: feature checklists
Each section of HUMANISER_DEV.md has its own checklist, taken from the handoffs:
- [ ] Perception (03): fog exit, Lotus/BKB timing at `SkillOverride = 0.1` vs `0.9`, juke, smoke gank, FPS at `host_timescale 2`.
- [ ] Ally last-hit (04): human pos 1 with bot pos 5 and pos 4, at low, mid and high difficulty; log last hits at 5 and 10 minutes.
- [ ] Pings (05): hero, Roshan, tower and danger pings; two humans pinging at once; a dead bot declining. Danger-ping a jungle camp a bot is farming: it switches camp, then returns once a bot sees the camp is clear (about 6 s), or after 10 s if nobody can see it.
- [ ] Commands (06): `!def mid`, `!rosh`, `!smoke`, `!lion push bot`, `!back`, `!farm`, `!bhelp`, `-都来守家`; confirm FretBots `!diff` and `!info` still work.
- [ ] Last-hit trainer (14): see "Last-hit trainer (14)" below.
- [ ] Transitions (12): see "Transitions (12)" below.

## Session 4: regression
- [ ] `Customize.Humaniser.Enable = false`: a 20-minute game behaves like upstream (Valve laning for supports, legacy ping response, no `[Humaniser]` lines).
- [ ] With each sub-feature disabled on its own (`Perception`, `AllyLastHit`, `Pings`, `Commands`), only that feature disappears.
- [ ] `Customize.Humaniser.Transitions.Enable = false`: see Transitions (12) item 7.

## Session 5: lane management (07)
Setup and background are in the "Lane management (07)" section of HUMANISER_DEV.md. Launch with `-condebug` and `Debug = true`; work from a lobby with at least one human.

**Data calibration run** (first, so later sessions run on measured data)
- [ ] For every camp index, run `!hstacktest <idx>` and `!hpulltest <idx>` (and `!hpulltest <idx> half` for the pull camps) with a bot nearby; use `!hcamp` to find the index. Note which fail to start.
- [ ] Copy `console.log` out of the game folder and run `node tools/replay-mining/parse_condebug.js console.log`. Promote entries with a `suggest:` line to `source: "measured"` with `verifiedAt` (dd/mm/yyyy), as described in HUMANISER_DEV.md.
- [ ] Lane amounts: `LANE_AMOUNT_TEAM_RELATIVE`. For a Dire bot, `!hcamp` and a pull both resolve to the camp near its own lane. Pass: no pull walks to the wrong side; otherwise flip the flag in `camps.ts`.
- [ ] Spawner data: log `GetNeutralSpawners()` at 0:00. Pass: non-empty, `type` is a string or int (both accepted, note which), table key matches `idx`.
- [ ] Waves: log `DotaTime() % 30` when the first lane creeps appear, at :00 and :30, and on a later wave. Pass: always about 0.
- [ ] `GetLaneFrontAmount(team, lane, true)`: compare with the creep front by eye (`!hpt`). Pass: it follows the creeps, not the tower line.
- [ ] `GetAmountAlongLane` returns a table with `amount` and `distance`. Pass: no Lua error from `lane_state`/`camps`, overlay `eq` sensible.
- [ ] Lane creep and siege unit names match `creep_goodguys`/`creep_badguys`/siege patterns. Pass: overlay creep counts equal what you see.
- [ ] Deny detection: handle identity of an enemy hero's `GetAttackTarget()` equals the creep handle across calls. Pass: overlay deny counts rise when an enemy denies.
- [ ] Aggro drop: attack an allied creep above 50% HP with a bot drop. Pass: the order is accepted and the creeps drop aggro.
- [ ] Tower aggro drop and swap: the tower's `GetAttackTarget()` is the bot while shot; an attack on an allied creep or on an enemy hero in range switches it. Pass: the bot leaves to 1,000 from the tower; a low-HP allied core is spared by the swap.
- [ ] Creep block geometry: block at 0:00 with `Block` on and off. Pass: the meeting point is closer to our tower; tune `Radii.BlockAhead`/`BlockSide` otherwise.
- [ ] Aggro draw: the walk-back moves after the attack order do not cancel the aggro. Pass: enemy creeps follow the bot.
- [ ] Farm desire 0.7 beats laning's 0.446 (a job runs) but not retreat. Pass: the job executes in the laning phase; a bot at low HP with enemies near retreats out of it.
- [ ] Pull mechanics: one `Action_AttackUnit(neutral, true)` aggroes the whole camp, neutrals follow the lead path and reach the meet point; `RandomVector(len)` has length `len`. Pass: `job` lines show divert above 0.8 for full pulls.
- [ ] Aggro confirmation: a melee support lands the hit from the stand point within `Timing.AggroConfirm`. Pass: no `job-abort ... mistake:no-aggro` lines.
- [ ] Divert measurement: allied creeps' `GetAttackTarget()` reports the neutral while they fight it. Pass: logged `divert` matches what is seen.
- [ ] Last-hit yield: a support in a pull does not leave the meet point to last-hit. Pass: no walk-off during `lane_job`.
- [ ] Seed timings per camp (stack :53-:55 by type, pulls :15/:45, :18/:48, half +2 s) and the `unverified` off-lane hard camp: see the calibration run. Pass: `parse_condebug.js` gives at least 80% ok per camp, or a `suggest:` line to promote.
- [ ] Stacking: one queued attack at the seed second pulls the camp out before :00; the exit path keeps it out. Pass: `stack` lines grade ok for most attempts.
- [ ] Stack outcome: the stacked neutrals are back in the box by :05 (`StackOutcomeUntil`) and `StackSight` (1,200) sees the box from the exit path. Pass: `after` exceeds `before` on stacks that visibly worked; few `after=?`.
- [ ] Stack farm desire: a laning support at :45, and a support after laning, take the stack job; two supports do not both take one camp. Pass: at most one bot in the box.
- [ ] Wards and respawn: a ward in a spawn box blocks the spawn, and a camp respawns on the minute only if empty. Pass: both hold on this patch; if not, leave `CampBlock` off and note it.
- [ ] Laning vs rune desire at 0:00. Pass: lane bots that stay still block at 0:05 while others go for the bounty rune.
- [ ] `GetHeroLastSeenInfo(pid)` gives location and time for fogged enemy supports. Pass: counter-play "support unseen" fires only after 4 s unseen, never with no hint (scenario 10).
- [ ] `J.GetPosition` on enemy heroes gives an estimated role. Pass: counter-play targets the enemy support and mid, not a random hero.
- [ ] Enemy `GetAttackTarget()` is readable for last-hit detection. Pass: the harass punish fires when an enemy attacks a low-HP creep.
- [ ] Cross-bot perception: the lane core's `ScoreFor`, `Enemies` and `WeAreStronger` evaluated from another bot's module (`pickFor`, `EnemyLaners`). Pass: the plan and enemy-laner count in the support's `lane` overlay equal what the core's own overlay shows, and no extra delay is visible.
- [ ] Harass approach and step-back: `GetExtrapolatedLocation` shows an enemy walking up to a last hit; after a hit into 3 or more creeps the bot steps back. Pass: the punish lands as the enemy closes, and the step-back does not walk into the wave.
- [ ] Counter-play pull arrival: compare `enemyArrivalSec` with the front position after our shove pushes the wave far forward. Pass: no `counter ... noticed=pull` lines from a shoved wave alone.
- [ ] Rune contest: the mid bot answers an enemy pre-rune shove. Pass: contest desire only acts from :52 of the minute before the spawn, and the bot walks to the right rune.
- [ ] Counter-play contest and shove responses: contests start in at least some pulls and break-freeze or rune shoves run. Pass: not never; if never, relax `pathSafe` or the `WeAreStronger` gate.
- [ ] Pull forecast, early pull: a 0.9 support pulls a cycle earlier than a 0.3 one when the clash favours us. Pass: its `lane_job_start` comes a wave cycle before the 0.3 support's in comparable lanes.
- [ ] Pull forecast, hold: with a losing clash and a pushed-out meet point, the 0.9 support holds. Pass: no pull that cycle (`lane_plan` gate `planner` says why).
- [ ] Pre-contest: against a human support who pulls every time the lane drifts back, a 0.9 bot is often at the camp before the aggro and a 0.4 bot never is. Pass: `lane_job_start ... kind=contest ... pre=1` before the pull for 0.9, none for 0.4.
- [ ] Pre-contest, carry safety: the carry is never left alone with both enemy laners while the support watches. Pass: `lane_job_end ... kind=contest reason=enemy-in-lane pre=1` when their support stays in lane, and no carry deaths during a lookout.
- [ ] Take the pull: when both supports pull at once, or the enemy pulls while ours is away, a 0.9 carry walks to their camp and last-hits the pulled wave; a 0.4 carry stays in lane. Pass: `take-pull:` in the hlog summary with `swings` > 0 and few `outnumbered`, and no carry deaths during a take.
- [ ] Telegraph lines read naturally and stay within 1 per bot per 10 s. Pass: no spam, no wrong lane in `they're pulling <lane>`.
- [ ] `OwnLaningThink = 'all'`: compare 07-only enemy bots' lane results with `'allies'`. Pass: no obvious laning regression.
- [ ] `!freeze !shove !pull !nopull !stack [lane]` resolve the lane from the issuer and lane word, acknowledged once. Pass: one ack, correct lane.
- [ ] Lane-front ping hands the lane off for 30 s. Pass: no pulls, stacks, shoves or draws from that lane's bots, and it expires.
- [ ] `GetTeamMember(1..#GetTeamPlayers(team))` is only used for own-team units. Pass: no enemy-team reads in the logs.
- [ ] `eqPos` fairness: pull an enemy wave into fog and watch the observing bot's `lane` overlay `eq` (it reads `GetLaneFrontAmount(enemyTeam)`, not vision-filtered). Pass: the shift is small and no `rune_shove`/freeze `counter` line comes from it alone.
- [ ] Camp-job pre-emption: let another mode (rune, ward, retreat) win while a pull is due. Pass: `job-abort ... reason=preempted` within about 1 s, the support goes back to last-hitting, and no `mistake:no-camp` from a camp it never reached.

**Scenarios 2-14** (spec numbering; run each at `SkillOverride = 0.9`, then at `0.2` or `0.4` where the spec gives a gate, and compare). The checklist with the exact expectations is in HUMANISER_DEV.md.
- [ ] 2 Full pull, 3 half pull (never at 0.4), 4 stack pull
- [ ] 5 Creep block at 0:00, 6 aggro pull and tower-aggro drop
- [ ] 7 No pull while the partner is in danger
- [ ] 8 Harass timing (human goes for 20 last hits: 0.9 punishes most, 0.2 some, at random times)
- [ ] 9 Enemy pull detection, with `OwnLaningThink = 'all'` (human support pulls: 0.9 reacts most times, 0.2 rarely; under `'allies'` enemy bots only notice)
- [ ] 10 Fairness: all enemies fogged, no last-seen hints, no `counter pid=...` lines
- [ ] 11 Bot duo: never two aggro draws in one 3 s window; absent core covered
- [ ] 12 Human core (`!freeze`, `!shove`, inferred plan, lane-front ping hands-off for 30 s)
- [ ] 13 Human support (bot core reads your pulls and aggro draws, does not contest your camps)
- [ ] 14 Mid: block at 0:00, shove 15-20 s before runes, hands-off beside a human mid
- [ ] Overlay shows `lane`, `lane_tech`, `lane_exec` and `lane_job` lines updating, and no more than 1 chat line per bot per 10 s from the lane telegraphs.

**Regression (scenario 15)**
- [ ] `Lane.Enable = false`: a 20-minute game behaves like the pre-07 branch (laning, farm, rune and ping behaviour; no `[H:lane]` lines).
- [ ] Every `Lane.*` flag false (with `Enable = true`): same result. This is the only full check that `mode_laning_generic.lua` and `mode_farm_generic.lua` behave exactly as before: offline tests pin their hook call sites but cannot run them.
- [ ] Each flag off on its own: only that behaviour disappears (`Harass = false` restores 04's original poke).

**With intent arbitration (09)**
- [ ] A support's pull starts on time while it has just switched into laning (no late `job-abort reason=late` lines caused by laning's dwell bonus); the overlay's `intent:` line shows `farm 0.7x by lane:<kind>` during the job.
- [ ] `!def mid` during a camp job: the order wins, the job ends `preempted` about 1 s later, and the bot's cycle lock is free again (no stuck "one per cycle").
- [ ] A support under 25% HP with a stack due: retreat wins (`conflicts=intent:survival>lane:stack` in the summary).
- [ ] No `[H:intent] stuck mode=farm` or `mode=laning` lines while a bot waits at a stand point, holds the stack exit until :01, waits for its aggro hit, holds a freeze posture or waits out a tower swap.
- [ ] The self-test bot (`Trainer.LastHit.SelfTest = true`) still times its last hits on a team whose bots run 07's laning techniques.

## Last-hit trainer (14)
Setup: Local Host lobby, cheats on, `Debug = true`, then `!trainer on`. Details are in the "Last-hit trainer (task 14)" section of HUMANISER_DEV.md.
- [ ] **Spike results recorded** in `HUMANISER_DEV.md` (`!trainer spike`), and the `OutcomeOnly` and `ScreenText` defaults decided. Also check:
  - draws are visible with and without Debug
  - the bars are smooth, and the think rate is noted
  - the countdown bar reads at a glance: the white line stays put, the marker turns green as it crosses it, and the green zone's length matches how forgiving the creep is
  - which human-hero reads work
  - `GetAttackProDelayTime` gives sane values on the human
  - a Unicode text line renders or doesn't
  - optional: latency from bot chat to a FretBots `player_chat` listener
- [ ] **Free lane against Valve Passive bots:** the bar appears over the right creep and the green zone slides smoothly. Starting on the tick gets mostly `PERFECT`.
- [ ] **Deliberately early and late swings** are graded `EARLY` and `LATE`, with sensible HP and source reasons.
- [ ] **Cancelled swings and denies** are classified correctly.
- [ ] **Ignored creeps:** deliberately ignoring wide-window creeps shows `MISSED_EASY`, and the 5:00 checkpoint names the leak.
- [ ] **Self-test:** the bot scores at least 85% `PERFECT` + `OK` and under 5% `MISSED_EASY` (`!trainer stats selftest`).
- [ ] **`!trainer stats` and the auto summaries print.** `!trainer off` removes all drawing and text.
- [ ] **Draws with Debug off:** with `Debug = false`, trainer draws appear and HDebug's columns don't.
- [ ] **Draws with Debug on:** with `Debug = true`, the trainer text doesn't overlap HDebug's columns.
- [ ] **Frame cost:** with 2 bars and 2 watched creeps (spike item 7), no visible FPS drop at `host_timescale 1`. If it's noticeable, lower `MaxWatched` or raise `WatchInterval` (keep `BAR_STICKINESS` at or above `WatchInterval`), and record the values here: _?_
- [ ] **Counter timing:** last hits read `PERFECT`/`OK`, not all `LATE`. If everything is `LATE`, `GetLastHits`/`GetDenies` update after the death frame and `creepObservations` needs a death hold (R12).
- [ ] **Attack reads:** `GetLastAttackTime` is the attack start (not projectile release); `ACTIVITY_ATTACK2` counts as an attack; `GetAnimCycle`/`GetAttackPoint`/`GetAttackSpeed` units give a sensible swing start; cached creep handles stay valid and `IsAlive()` doesn't error.
- [ ] **Regression:** with `Trainer.LastHit.Enable = false`, no `[H:trainer]` lines, no trainer chat and no draws.

## Transitions (12)
Setup and design are in the "Transitions (12)" section of HUMANISER_DEV.md. Launch with `-condebug` and `Debug = true` (the overlay shows a `phase:` line: laning or post, `busy`, `spare`, `alone`, `rot`). Items 1-7 are the spec's in-game scenarios; 8-9 are data checks; 10 is the mid-rune check; 11-12 are assumptions only the game can confirm; 13 is the post-laning and review-fix check.
- [ ] **1. 6:00 rune, pos 4 idle, stable lane:** the pos 4 leaves about 25-20 s before the spawn and arrives about 3-5 s before it at high skill (`SkillOverride = 0.9`). At `0.2` it is sometimes late or skips (the `[H:transitions]` rotation line names the reason). Our mid takes the rune.
- [ ] **2. Pos 5 with a stable lane and a healthy carry:** it rotates when the pos 4 is busy (low HP, an accepted order, a camp job). With an enemy hero within 1,200 of the carry, or the carry under 75% HP, it stays.
- [ ] **3. A support leaves its lane:** the remaining core plays visibly safer: it stands 150-300 units further back, stops trading with the enemy laners, and backs off when an enemy laner goes unseen for 4 s. At low skill it adjusts later and only partly. Lane plan: no `SHOVE` while it is alone.
- [ ] **4. Enemy TP into our lane:** bots in that lane back off before `time_remaining` runs out. At skill above 0.7 with `WeAreStronger`, they set up on the TP spot instead, 600 units from it toward our tower (never closer than 850 to a live enemy T1). Walk a skill-0.9 bot into a TP on both sides of the 0.7 line.
- [ ] **5. Lost lane:** die twice to a lane kill inside 4 minutes. A bot core goes to the jungle and says `going jungle` (lane swap is out of scope, plan call 3). A bot support beside a human core says `lane lost, i'll roam?` and waits; it leaves only on a ping or command, or once the human leaves.
- [ ] **6. Etiquette and ownership:** with FretBots on and off, and with a human in a side lane, mid and as a support: nothing breaks etiquette (04) or lane ownership (07). In particular a bot does not rotate away from a lane a human pinged in the last 30 s.
- [ ] **7. Regression:** with `Transitions.Enable = false` the game plays like the branch before 12: no rotations, no alone-core caution, no TP reaction, no lane wards, farm gated by the laning phase as upstream, no `[H:transitions]` lines. Then each flag off on its own (`MidRunes`, `Rotation`, `Caution`, `Teleports`, `LaneWard`, `Phase`, `LostLane`): only that behaviour disappears. `Caution` and `Teleports` are independent: with `Caution = false` a TP still backs the core off; with `Teleports = false` the alone-core and missing-enemy caution still work. Offline, `test_transitions_core.lua` ("Regression pin") covers every hook, but the laning, ward and farm mode files are only source-pinned.
- [ ] **8. TP to a fogged tower:** `GetIncomingTeleports()` lists an enemy TP whose destination is in fog (the enemy T1 of our lane). Log the entries (`playerid`, `location`, `time_remaining`) while an enemy TPs to its own lane tower with no vision there. Pass: the entry appears with a usable `location`. Fail: the API hides fogged destinations; then item 4's TP reaction only works with vision, and the spec's open question is answered.
- [ ] **9. `GANK_ANCHORS` calibration:** the six points in `lane_ward.ts` (team x lane) are first-pass river spots from `aba_ward_utility`. Walk to each, compare with the lane's real gank path, and adjust the coordinates. Pass: in 2:30-4:30 the lane support wards a spot that covers the path, not one that is merely nearest.
- [ ] **10. Mid takes power runes:** with a bot mid (Telemetry on), watch the 6:00 and 8:00 power runes, once with a bottle and once without. From about 15 s before the spawn the mid walks to its side's power spot, waits there (it does not drift back to lane or flicker between rune and laning), and takes the rune. It still turns away when outnumbered, hurt, or a human ally is at the rune. Read any `rune_skip` lines: `gate` names the first refusal (`idle`, `outnumbered`, `no_rune`, `bounty`, ...), `laning` the competing desires. When the rune appears at the other spot, the mid crosses to it; an unseen spot is not checked more than about 15 s after the spawn. On the Dire side before 6:00, watch for a bot stuck on the `RUNE_POWERUP_2` spot (its upstream gate is bypassed there). With `Transitions.MidRunes = false`, the mid behaves as upstream.
- [ ] **11. Death edge needs `ItemUsageThink` while dead:** `Transitions.Tick` runs from `ItemUsageThink`, and the lost-lane death count (and the busy "dead" state) reads the alive-to-dead edge there. Kill a bot core in lane twice and read the intent overlay. Pass: the second death posts the `transitions:lostlane` Laning cap and `FarmAllowedInLaning` turns true (the core leaves for the jungle, `going jungle`). Nothing is logged for the death itself. Fail (Tick is not called while dead): deaths are missed; move the death sample to a hook that runs while dead.
- [ ] **12. TP setup point:** the setup spot is clamped to at least 850 from a live enemy T1 (`TpTowerClear`). With a 0.9 bot set to set up on a TP to the enemy T1, it should stand just outside tower range, not under the tower. Check the tower does not hit it before the enemies land. Related: an enemy missing longer than `MissingMaxAge` 60 s no longer counts, so a core should not stay passive for minutes while an enemy farms the jungle; tune the cap if it does.
- [ ] **13. After laning:** past 10:00 (or once a lane's T1 falls) no bot is cautious for missing enemies (attack and retreat desires as upstream), no `ss <lane>` lines appear, enemy TPs into a lane force no back-off or setup, and no support rotates or says `coming mid for rune`; the mid still goes for power runes. During laning, a rotating support that reaches the spot with our mid beside it lets the mid take the rune. With our mid within about 2,500 of the spot, the support stands on the spawned rune without taking it until the mid arrives; it takes it at once when an enemy hero comes within about 1,200, about 3 s after the spawn when our mid isn't coming, and at 15 s regardless (`tr_rune_hold` lines). A lane support whose lane ward is rejected (enemy nearer, or more than 3,200 away) still wards upstream's closest spot. A core sent to the jungle by a lost lane stays there until laning ends, with one `going jungle` line.

## Known risks to watch
- **Laning:** every allied bot on a team with a human uses OHA's laning `Think()` for the whole game, never Valve's (task 04). If laning gets worse, fall back to option B in the 04 handoff.
- **Channel delay:** delaying enemy `IsChanneling` affects every OHA use of it, not just interrupts. `Perception.Channel = false` disables only that part.
- **Commitment:** orders cap retreat while HP is above 50%, so bots may die more on orders. Ordered pushes also skip OHA's "never push alone" checks.
- **Avoidance zones:** they may only affect pathing via `GeneratePath`, not `Action_MoveToLocation`.
- **FretBots bridge option A** (`FretBridge.BridgeModifier`) is untested and off by default. Try it only after the chat mirror proves unreliable.
- **Leftover probe:** remove `SharedStateProbe` once the session 1 result is recorded.
- **Lane `OwnLaningThink = 'all'`:** it gives every bot, the enemy team included, OHA's laning `Think()` for the whole game in place of Valve's C++ laning. Only use it deliberately; compare lane results against `'allies'`.
- **Camp jobs:** pulls and stacks run at desire 0.7, so supports leave their lane for them (a pull is gated on partner safety, but a stack after laning has no partner). If supports die or vanish more than before, raise `Thresholds.StableEnemyRadius` or turn off `Stack` / the pull flags.
- **Untrusted seed paths:** pull and stack seconds, paths and the off-lane hard camp come from public guides and derived geometry and have not been measured on this patch (`data=seed` or `unverified` in `job-start`). Bad data means failed pulls and wasted trips, not errors; fix by promoting measured entries.
- **Replay data:** the Go replay parser is uncompiled and stack-only; half-pull data must be measured in-game.
