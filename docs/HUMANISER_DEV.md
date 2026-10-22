# Humaniser development guide

Working notes for the humaniser fork of OHA. Items marked **TODO (in-game)** still need confirming in a live lobby.

## Branches
- `humaniser`: feature work.
- `patch-currency`: brings OHA up to the live patch. It is kept separate so it can be rebased or upstreamed on its own.
- `upstream` remote: forest0xia/dota2bot-OpenHyperAI. **TODO:** fork to our org and set `origin` to the fork.

## Build
- Use yarn, which matches the checked-in `yarn.lock`. `npm install` fails on a peer conflict: `typescript-to-lua@1.26.2` pins `typescript@5.5.2`, but the project has `5.5.4`.
  ```bash
  PUPPETEER_SKIP_DOWNLOAD=1 npx --yes yarn@1 install --frozen-lockfile
  ```
  ```bash
  npm run build
  ```
- Round-trip check (21/10/2026, upstream `cb814c6`): `npm run build` on a clean checkout produced **no diff** against the checked-in Lua. The TS pipeline is trustworthy.
- `bots/Customize/general.lua` is hand-written Lua. `typescript/bots/Customize/general.ts` only re-exports it, so humaniser config lives in the Lua file under `Customize.Humaniser`.

## Dev install
On macOS, Dota reads bot scripts from:
```
~/Library/Application Support/Steam/steamapps/common/dota 2 beta/game/dota/scripts/vscripts/bots
```
On this machine that path is a symlink to the Workshop OHA item (`workshop/content/570/3246316298`). To run the dev checkout instead, re-point it (and point it back to the Workshop path to undo):
```bash
ln -sfn "$HOME/Documents/Projects/dota-bots-humaniser/oha/bots" "$HOME/Library/Application Support/Steam/steamapps/common/dota 2 beta/game/dota/scripts/vscripts/bots"
```
Edits then take effect on the next lobby start, or after `script_reload` (**TODO (in-game):** confirm which reload works mid-game for bot scripts).

### Lobby setup
**TODO (in-game):** record the exact clicks. Expected flow:
1. Play → Custom Lobbies → Create. Edit settings: Server Location = Local Host, Enable Cheats (needed for FretBots and debug draws).
2. Set Radiant and Dire bot scripts to **Local Dev Script** (not the Workshop item). Set bot difficulty per team.
3. Start the game.

**With FretBots** (discussion #68): in the console, once the game has loaded, run `sv_cheats 1`, then `script_reload_code fretbots`. **TODO (in-game):** confirm the exact command.
**Without FretBots:** skip that step. The humaniser must still work, with `GetFret().active = false`.

### Useful console commands
| Command | Use |
|---|---|
| `sv_cheats 1` | Required for debug draws and `host_timescale` |
| `host_timescale 2` | Speed up the game (perf check) |
| `dota_bot_debug_team 2` / `3` | **TODO (in-game):** confirm. Valve's own bot debug overlay |
| `dota_bot_debug_clear` | **TODO (in-game):** confirm |

## Debug overlay
Set `Customize.Humaniser.Debug = true` in `bots/Customize/general.lua`. The module is `typescript/bots/FunLib/humaniser/debug.ts`, required as `HDebug`.

- `DebugDrawText` is **screen-space only**, so text can't float above a hero. Each bot gets a text block: Radiant on the left (x=10), Dire on the right (x=1100), one row per team slot. Adjust `DIRE_X` for your resolution.
- The first line of each block is `hero [pid] <active mode> <active desire>`.
- The second line lists the top-3 **reported** desires. The bot API exposes only the active mode and its desire. Mode files must call `HDebug.RecordDesire(bot, BOT_MODE_X, desire)` to appear here. Modes whose `GetDesire()` returns nil fall back to Valve's C++ desire, which can't be read.
- `HDebug.Text(bot, key, text)` adds a persistent line per key. `HDebug.Circle(...)` wraps `DebugDrawCircle`.
- `HDebug.Log(tag, ...)` prints `[H:tag] ...`. It bypasses OHA's `print` override (which stays silent unless `Utils.DebugMode`) through `Utils.RawPrint`, set in `aba_global_overrides.lua`.
- Drawing runs from `ItemUsageThink`, before its throttle, so it happens every frame.

## Shared-state finding
**TODO (in-game).** This blocks the design of tasks 02, 05 and 06.

How to run the check: enable Debug and start a game with bots on both teams. Every 5 s, each bot logs:
```
[H:probe] pid=<id> team=<2|3> total=<n> mine=<n> playersInThisModule=<k> bothTeamsInThisModule=<bool>
```
- If `playersInThisModule` reaches 5 (and `total` is about 5 × `mine`), `require`d modules are **shared per team**.
- If it stays at 1, each bot has its own module instance.
- If `bothTeamsInThisModule=true`, Radiant and Dire share a VM.

Result: _not yet recorded._ Afterwards, delete `SharedStateProbe` from `debug.ts` and its call in `ability_item_usage_generic.lua`.

## Offline checks (no game needed)
```bash
cd tests/humaniser && npm install && npm run check
```
- `syntax` parses every `.lua` under `bots/` as LuaJIT, Dota's dialect. The checker also accepts `break;`, which upstream uses and LuaJIT allows.
- `test` runs `tests/humaniser/test_*.lua` in fengari (Lua 5.3 in JS) against the stubs in `dota_stubs.lua`. `FreshHumaniser(cfg)` loads a new module instance with the given `Customize.Humaniser`. Two instances in one test stand in for "modules are not shared between bots".
- These check logic and wiring only. Valve API semantics (ping types, chat callback delivery, modifier stacks) still need the in-game checks marked TODO in this file.
- `hlog` runs the telemetry analyser's tests (`tools/hlog/test`), including `hlog_session.lua`: a scripted `!def mid` + `!mark` session through the real modules whose `[HEV]` output must pass the analyser's checks.

## Telemetry and log analysis
`Customize.Humaniser.Telemetry.Enable = true` (on in `general.lua`, off in the `config.ts` defaults) makes every bot print machine-readable `[HEV]` lines. They're independent of `Debug` and never change behaviour. The only visible effect is the `mark N saved` reply to `!mark`. The module is `typescript/bots/FunLib/humaniser/telemetry.ts`.

**Setup, once:** add `-condebug` to Dota's Steam launch options (next to `-console`). Dota then writes its console to `…/dota 2 beta/game/dota/console.log`. **TODO (in-game):** confirm that bot-VM prints reach that file, and whether it's overwritten or appended per launch. The analyser splits games on clock resets either way.

**While playing:** type `!mark <what looks wrong>` in chat (team or all). The team's lowest-PID bot replies `mark N saved`. Every bot logs its state at that moment (`mark_state`), including Dire's bots when you use all chat.

**Afterwards:**
```bash
node tools/hlog/analyse.js                 # latest game: per-player summary and checks
node tools/hlog/analyse.js --mark 2        # every bot's state at mark 2, plus the 20 s before it
node tools/hlog/analyse.js --from 4:30 --to 5:10 --pid 3 --ev mode,lasthit,order_accept
node tools/hlog/analyse.js --check         # checks only; exit 1 on any FAIL (e.g. after an all-bot run)
node tools/hlog/analyse.js --list          # games in the log; --game N picks one
```

**Humaniser off (A/B games):** telemetry has its own switch. With `Customize.Humaniser.Enable = false` and `Telemetry.Enable = true`, `Humaniser.Tick` runs only `Telemetry.Tick`: snapshots, `mode`, `lasthit`/`deny`, `game_end`, `lua_error`, and a `bot` line with `humaniser=0` and the read-only `skill`/`ally` (the profile is not built, because building it draws `RandomFloat`). Every humaniser hook still early-returns as before, so behaviour is upstream OHA. Not available off: every humaniser-only event, `by`/`order` on snapshots, and `!mark` (the humaniser chat hub isn't installed; upstream installs its own callback). `Customize.Enable = false` still turns telemetry off with everything else.

**Lua error guard (`Telemetry.LuaErrors`, default on with telemetry):** read once at load. `Humaniser.Tick` and the hooks other files call every frame (`Intent.Resolve`; `Lane` camp-job, rune, harass and think hooks; `AllyLastHit.FilterCreeps`/`MayLastHit`; `Orders` desire floors and AVOID filters; `Commands.ShouldUseOrderedSmoke`; `Perception` filters) run under `xpcall`. A throw is printed as `lua_error`, once per `where`+`msg` and again at most every `LuaErrorRepeat` s with the count, and is swallowed: the hook returns its feature-off value (raw desire, unfiltered list, `false`, `0`), so a humaniser bug degrades to upstream behaviour instead of losing the whole `GetDesire`/`Think` call. Reporting runs after `xpcall` returns, so a stack overflow, which Valve's handler prints only as `error in error handling`, is still attributed to its entry point. If the console shows `error in error handling` and there's no `lua_error`, the error came from outside the guarded entry points (upstream OHA or Valve code). Cost: roughly 0.03 µs per guarded call under the LuaJIT interpreter on an M4, so expect about 0.1 µs in Dota's Lua. Perception filters are called most often (every enemy `GetNearbyHeroes`/`GetUnitList`), which is well under 1 ms per frame for ten bots. Set `LuaErrors = false` to remove the wrappers.

**Line format:** `[HEV] t=<DotaTime> ev=<name> k=v ...`. A value with spaces, `"` or `=` is double-quoted with inner quotes turned into single quotes. Order posts, pings, commands and marks are emitted by every module instance. The analyser de-duplicates them, so the log looks the same whether or not modules are shared.

| `ev` | When | Key fields |
|---|---|---|
| `bot` | First tick, and whenever the profile changes | `skill ally notice react ping chat jitter lapse lapseMax minReact deference` |
| `player` / `snap` | Human allies are reported by the team's lowest-PID bot | Every `SnapshotInterval` (1 s): `x y alive hp mp lvl lh dn tgt`, plus for bots `mode d act gold by order` |
| `mode` | Active mode changed | `from to d dwell by` |
| `lasthit` / `deny` | Last-hit or deny counter rose | `human creep dec decAge` (`dec` = the etiquette decision on the creep it was attacking the frame before) |
| `notice` / `react` | Perception noticed an enemy, or knew of a cast | `target delay due reason` / `who what delay` |
| `order_post` / `order_accept` / `order_decline` | Orders bus | `id type lane responders dur kind` / `read latency` / `reason` |
| `ping` / `cmd` | Human ping or chat command | `context danger order` / `name args only text` |
| `thrash` / `stuck` | Intent episodes | `switches window mode competing` / `mode d raw inMode` |
| `trainer` | Trainer verdict | `selftest kind creep deny offset window pred landed` |
| `mark` / `mark_state` | `!mark` | `n by text` / one bot's full state at the mark |
| `lane_plan` | Laning phase, at most once per wave cycle, gate and bot: the first moment in the cycle farm's GetDesire reaches that gate (the gates are re-checked every frame, so `far` then `planner` in one cycle means the bot came back in reach) | `gate` (`no-camp`: the lane has no resolved pull camp; `far`: the window is shut only because the stand point is over `MaxTravel` away, with `camp travel`; `late`: in reach, but the bot would reach the stand point after `aggro + JobStartLate`, with `camp travel`; `planner`: the planner was asked, with `camp tech reason score fscore w imb feq apow epow plan pullOk partner laners`, `fscore` being the forecast score the pull branch used, `w` the `Foresight` weight, `imb` the clash imbalance, `feq` the forecast eq and `apow`/`epow` the ally and enemy wave power; `far`, `late` and `planner` add `timing`, `wave` or `seed`, for the first camp's full pull; `double-unfit`: the planner chose a full pull that would have been a double, but the double cannot fit, with `camp second why late gap`, `why` being `no-wave`, `far`, `join` or `reach`, see "Double pulls"), then `owner` (`ok` or `MayRunCampJob`'s reason) `eq meet want front efront tower etower` (eqPos, the meet amount, and the eqPos inputs: own and enemy front amounts and tower amounts, all from `GetAmountAlongLane` through `Camps.ToTeamAmount`) |
| `lane_job_start` / `lane_job_abort` / `lane_job` | A camp job (pull, stack, contest) registered / aborted / a pull graded | `pid kind camp key data aggroAt forced timing` (`timing`: `wave`, `live` or `seed`, see "Pull timing from wave arrival"; a pre-contest adds `pre=1`, see "Pre-contest") / `pid kind camp key reason phase acted divert` (`phase` the job was in, `acted` whether farm's Think ever ran it; a `partner-low-hp` / `partner-dived` abort adds the partner reading `partner php pnear pclose ploss`; a pre-contest's abort adds `pre=1`) / `pid kind camp key aggro planned divert grade`, as the `[H:lane]` lines |
| `lane_job_end` | A stack job's walk-off ended (its outcome follows on `lane_stack`) / a contest ended | `pid kind camp` / `pid kind=contest camp reason pre` (`reason`: `no-target`, `timeout`, `enemy-in-lane` or `no-pull`; `pre` 1 for a pre-contest, else 0), as the `contest-end` line |
| `lane_job_hold` | `hold=partner`, once per job: the start gate (`PartnerSafe`) fails while the job runs on under its commitment (`PartnerHolding`). `hold=retreat`: retreat is first held below a pull that has drawn its camp (`state=on`), and released for the rest of the job (`state=off`, at most once) | `pid hold kind camp phase`, then `partner php pnear pclose ploss` (partner) or `state reason hp` (retreat; `reason` is `neutrals` for `on`, else `hp`, `hero-hit`, `hero-attack` or `tower`) |
| `lane_job_ping` | A support pings the camp it leaves for, for a human lane partner (first Think of the job) | `pid kind camp partner` |
| `lane_cover` | A core starts or stops playing safe while its support is on a camp | `pid state` (`start`/`end`) `partner via` (`job`: this module holds the support's job; `camp`: the support is seen at a pull camp) `kind` / `dur` |
| `lane_stack` | A stack's outcome settled, as the `[H:lane] stack` line | `pid camp type aggro planned before after grade stacked assumed` (`grade` is timing only; `stacked=1` when the count rose, or when assumed; `assumed=1` is the `stack-assumed` case) |
| `lane_eq` | Once per team and lane per wave cycle, at the first snapshot refresh at or after `Timing.EqSampleAt` (10 s) into the cycle. The sample for fitting `ForecastModel.K` | `team lane kind eq imb feq a e` (`kind` safe, off or mid; `a`/`e` ally and enemy creep counts) |
| `game_end` | An ancient fell or post-game started | |
| `lua_error` | A guarded humaniser entry point threw (`Telemetry.LuaErrors`) | `pid where n msg tb` (`where` e.g. `Intent.Resolve`, `Perception.FilterNearbyEnemies`, `Tick`; `n` running count; `tb` up to six `file.lua:line(fn)` frames, absent for a stack overflow) |

**Checks** (`tools/hlog/checks.js`):

| Check | Fails or warns when |
|---|---|
| `script_errors` | **FAIL:** any Lua error line in the console (runtime errors and `[Humaniser] chat subscriber failed`). |
| `snapshot_gaps` | **FAIL:** a bot stops reporting for more than 10 s (its script stalled or errored). |
| `notice_delay` | **FAIL:** a sampled notice delay is outside the bot's profile bounds (`base × (1 ± jitter/2)`, plus up to `LapseMaxExtra`), or a hero is noticed before its delay elapsed. **WARN:** it was noticed more than 1 s late; reported as a count per bot plus the five worst. |
| `react_delay` | **FAIL:** a reaction is under `MinReact` or outside the profile bounds. |
| `order_read_delay` | **FAIL:** an order's read delay is outside the `ping`/`chat` bounds, or the order was accepted before it. |
| `order_followed` | **WARN:** an accepted order's mode (assemble, roshan, `defend_<lane>`, `push_<lane>`) never appears within 8 s while the bot is alive. |
| `lasthit_etiquette` | **FAIL:** an allied bot last-hits a creep it had decided to leave for a human (`dec=skip…`). |
| `intent_health` | **WARN:** `stuck` episodes and genuine `thrash` episodes, one line per bot: episodes grouped by mode (stuck) or by the most frequent mode pair in the thrash window, each with its count and first time for `--from`. A thrash episode whose window has at most `Thrash.MaxSwitches` (4) switches once last-hit blips are removed is counted as a blip episode in the summary, not warned. |
| `frozen_bots` | **WARN:** a live bot outside fountain range doesn't move for 10 s. Independent of Intent's stuck detector. |
| `trainer_selftest` | **FAIL:** with at least 20 self-test verdicts, under 85% `PERFECT`+`OK` or at least 5% `MISSED_EASY`. |

**Mode churn** (summary section): OHA's `mode_team_roam_generic.lua` wants 1.5 whenever `X.GetLastHitCreep()` finds a killable creep, and `CapForLanePush` holds that to 0.72 in the laning phase. Every last-hit attempt is therefore a short team_roam visit out of laning. The analyser calls a team_roam visit entered from laning at exactly 0.72 and left within 2 s (to any mode) a *blip*. The section lists, per bot, total switches, blips, blips/min, other switches/min and the top three non-blip mode pairs. Blips are upstream behaviour, not a humaniser fault.

**Hands-off regression run:** an all-bot lobby (spectate, `host_timescale 4`, about 15 minutes of game time), then `analyse.js --check`. That covers errors, stalls, perception bounds, thrash and freezes. Etiquette, orders and pings need a human on the team.

## Humaniser core (task 02): design notes
All of these are built to work whichever way the shared-state check turns out.

- **Config:** `FunLib/humaniser/config.lua` holds every default and tuning curve. `Customize.Humaniser` overrides them, and any key it lacks falls back to the default. Config is read through `custom_loader`, so a user copy in `game/Customize` wins.
- **Chat hub (`chat.lua`):** one `InstallChatCallback` per script context, with named subscribers and messages de-duplicated within 0.25 s. Humaniser code must never call `InstallChatCallback` directly. With the humaniser enabled, the reply-chatter callback in `ability_item_usage_generic.lua` subscribes here and ignores `!` commands other than `!sp`. With it disabled, the upstream install path runs unchanged.
- **Orders bus (`orders.lua`):**
  - Orders are keyed by a deterministic `sourceKey`, so every bot posting the same ping or chat line creates the order once.
  - Responders are ranked nearest-first at creation, ties broken by player ID, so every bot computes the same set.
  - Each bot reads an order after `Profile.SampleDelay(bot, 'ping')`. Declines are per bot and do not promote the next candidate.
  - The first non-declined responder is the only one who acknowledges in chat.
  - `J.ModeAnnounce` is injected via `Orders.SetAnnouncer`, because orders cannot require `jmz_func` (circular).
- **Assemble executor:** `mode_assemble_generic.lua` runs accepted GATHER, ATTACK and SMOKE orders first. ATTACK hands off within 900 units of a visible target; GATHER and SMOKE hold near the point. With no order active, the legacy ping path runs.

### FretBots bridge
FretBots runs in a separate VScript context, so the bot side infers its settings. Sources in priority order:
1. **`FretBridge.FretBotsLevelOverride`:** manual override.
2. **Option A, modifier stacks (off by default):** set `FretBridge.BridgeModifier` to a modifier name. `Settings:WriteHumaniserBridge()` in `FretBots/Settings.lua` then writes `difficulty*10 + allyScale*100*1000` as its stack count on every bot, once votes are final or the difficulty is clamped. Lua modifiers look unusable (`LinkLuaModifier` is commented out in `FretBots.lua`), so this needs a built-in modifier whose stack count has no gameplay effect. **TODO (in-game):** find one and confirm `GetModifierStackCount` reads it.
3. **Option B, chat mirror:** plain numbers typed before the horn count as difficulty votes (0–10); numbers typed in the first 40 s count as ally-scale votes (0–1). One vote per player, averaged, like `Settings:DoChatVoteParse`. It can't see votes typed before bot scripts start, or FretBots' host-limit clamp.
4. **Option C, defaults:** `Customize.Fretbots.Default_Difficulty` / `Default_Ally_Scale`.

**Is FretBots active?** FretBots gives every bot `modifier_special_bonus_cooldown_reduction` at start. The bot side treats that as the marker, but only while the bot is level 9 or below and within the first 5 minutes, because a level-10+ talent can grant the same modifier.

**Skill:** `ValveWeight*valve + FretWeight*fret`, normalised by the weight sum. `fret = level/10`; for allies of humans it is also multiplied by `allyScale`, as FretBots does with ally bonuses. `[Humaniser] pid=... skill=...` is printed once per bot when the game starts, even with Debug off.

## Ally last-hit etiquette (task 04)
Allied bots leave a human core's lane creeps alone. `Customize.Humaniser.AllyLastHit.Enable = false` (or `Humaniser.Enable = false`) restores upstream laning and farm exactly, including whether laning `Think()` is defined.

### Design
- **Predicate:** `J.Humaniser.AllyLastHit.MayLastHit(bot, creep) -> (allowed, reason)` in `FunLib/humaniser/ally_last_hit.lua`. Reasons start with `skip:` (held back), `take:` (a protected human is near but etiquette allows it) or `free:` (etiquette does not apply). Allied creeps (denies) are always allowed.
- **Protected human:** an alive, non-bot ally whose `J.GetPosition` is in `ProtectPositions` (default `{1, 2, 3}`), within `ProtectRange` (1000) of the creep, during `J.IsInLaningPhase()`. A bot in `OwnFarmPositions` (default `{1, 2}`) is only restricted when the human has the same `GetAssignedLane()`.
- **One rule at every difficulty:** near a protected human the bot denies, and takes an enemy creep only when the human is going to miss it. It never takes the human's current attack target. This replaces the handoff's tier table, where Polite never last-hit and Teammate last-hit normally.
- **Tiers** from `Profile.deference` (Polite `d >= PoliteMin` 0.75, Helpful `d >= HelpfulMin` 0.4, otherwise Teammate) only change what counts as a miss, through `MissRules`:

  | Tier | Away: beyond attack range + | Idle for | Deny race | Human trading with a hero |
  |---|---|---|---|---|
  | Polite | 400 | 6 s | no | no |
  | Helpful | 150 | 3 s | yes | no |
  | Teammate | 75 | 1.5 s | yes | yes |

  "Away" also needs the human not to be walking towards the creep. Reasons on the overlay: `skip: human-target`, `skip: <tier>`, `take: human-away|human-idle|deny-race|human-busy`.
- **Config:** all thresholds live in `DEFAULTS` in `ally_last_hit.ts`, shallow-merged with `Customize.Humaniser.AllyLastHit` (lists replace the default list). `MissRules` merges per tier and per field, e.g. `MissRules = { polite = { IdleSeconds = 4 } }`.
- **Laning (`mode_laning_generic.lua`, option A):** `Think()` is also defined when `AllyLastHit.OwnsLaning(bot)` is true at file load: the feature is on and the team has a human. Valve's C++ laning cannot be filtered and a defined `Think()` cannot hand back to it, so these bots use OHA's laning `Think()` for the whole game, also when no human is near. The load-time check uses `GetTeamPlayers`/`IsPlayerBot`, which upstream already reads at load (`teamHumans`). Human positions are deliberately not part of the load-time decision, because they can still change before the horn.
  - Candidate last-hit creeps go through a filter. A `take:` verdict is final. Otherwise upstream's rule applies: pos 1–2, or no other core within 700.
  - The 0.9 last-hit desire in `GetDesire()` is gated by the same filter. It is not extended to the new bots, so mode selection stays as upstream and only `Think()` changes.
  - `Think()` runs small steps in order: `LastHitThink`, `DenyThink`, `HarassThink` (humaniser bots only), then `PositionThink`. Last hit comes before deny on purpose: near a human, a last hit is only allowed when the human will miss it. Lane management (07) adds steps here.
  - **Support idle behaviour:** last hit, then deny, then harass, then move to the lane front (existing code). Harass is one right-click on the nearest enemy hero within attack range + 300 every `HarassInterval` (2.5 s). It needs a protected human near the bot, `J.WeAreStronger(bot, 1200)`, HP ≥ 50%, and neither unit within 850 of an enemy tower.
- **Farm (`mode_farm_generic.lua`):** the lane-creep lists used for desire and for the attack target go through `AllyLastHit.FilterCreeps`. That returns the same table when etiquette is off.
- **Team roam (`mode_team_roam_generic.lua`):** its own last-hit grab (`X.GetLastHitCreep`, desire 1.5, which outranks laning) also checks `MayLastHit`. Without this a pos 3 bot could still take the human's creeps.
- **Overlay** (`Debug = true`): line `lasthit: <tier> d=<deference> <last skip reason> @<time>`.

### Assumptions to confirm in-game
- **TODO (in-game):** the bot side can read `GetAttackTarget()`, `GetLastAttackTime()`, `GetAnimActivity()` and `GetExtrapolatedLocation()` for an allied human, and `GetAttackTarget()` for enemy heroes (used to spot a deny race).
- **TODO (in-game):** `GetAssignedLane()` on a human hero returns the lane they are actually playing. This only matters for the pos 1–2 bot edge case.
- **TODO (in-game):** `GetTeamPlayers`/`IsPlayerBot` already report humans when `mode_laning_generic.lua` loads. If not, `OwnsLaning` is false and the bot keeps Valve's laning, so last hits are not filtered.
- **TODO (in-game):** OHA's laning `Think()` holds up compared with Valve's for every allied bot, including pos 1–2 bots with no human nearby. If laning gets noticeably worse, consider option B from the handoff.
- **TODO (in-game):** a `GetLastAttackTime()` change ends the harass window after one attack, rather than cancelling the swing.
- Valve Easy maps to skill 0.25, so deference is exactly 0.75: the Polite boundary. Tune `PoliteMin` if FretBots ally scaling moves easy allies across it.

### Manual test checklist
Setup: human pos 1 safelane, bot pos 5 and bot pos 4 in the same lane. Log `GetLastHits()` for bots and human at 5 and 10 min.
- [ ] Every difficulty: while you are farming actively, support last hits near you = 0 and denies > 0.
- [ ] Low (Valve Easy / FretBots 1): the support only takes creeps after you leave the lane or stop attacking for 6 s.
- [ ] Mid (Medium / 5): it takes creeps once you are away or idle for 3 s, or an enemy is about to deny them.
- [ ] High (Unfair / 9): it also takes creeps while you trade hits with an enemy hero, but never the creep you are attacking.
- [ ] A pos 3 bot in your lane does not take your creeps through team roam.
- [ ] Human pos 5, bot pos 1: the bot carry farms normally; nothing is protected.
- [ ] Regression: with `AllyLastHit.Enable = false`, laning and farm match upstream.
- [ ] No idle support: the bot never stands still for more than 3 s in lane. Watch the overlay mode text and the `lasthit:` line.

## Perception (task 03)
Module: `typescript/bots/FunLib/humaniser/perception.ts`. Tuning lives in its `DEFAULTS`, merged under `Customize.Humaniser.Perception` (`Perception.Enable` is the kill switch). With the humaniser or perception disabled, every hook returns the engine's own result unchanged.

**Part A, notice delay.** Hooks in `aba_global_overrides.lua` (perception is required lazily on first call, so there is no load-order dependency):
- `CDOTA_Bot_Script:GetNearbyHeroes(r, true)` → `FilterNearbyEnemies(self, list)`. Filtered only when `self` is on our team; the observer is always `GetBot()`. Enemy callers and ally lists pass through.
- `GetUnitList(UNIT_LIST_ENEMY_HEROES)` and `GetUnitList(UNIT_LIST_ENEMIES)` (hero entries only) → `FilterUnitList`. Covers `J.GetEnemiesNearLoc`.
- Per observer (keyed by player ID) and per enemy handle (weak-keyed table) a sighting `{firstVisible, noticeAt, lastSeen, noticed}` is kept. A new sighting is hidden until `noticeAt = now + SampleDelay(bot,'notice')`. A noticed hero seen again within `Permanence` (2 s) is visible at once. Immediate notice: damaged the observer within 0.3 s, within 300 units, or a teammate noticed it at least 1 s ago (only possible when modules are shared; otherwise it never fires).
- Filtering is O(n) over the original list and returns the original table when nothing is hidden; decisions are cached per handle per `DotaTime()`. Every 0.25 s the observer refreshes `lastSeen` for tracked heroes still in vision (`CanBeSeen`), so a hero in view but outside the radius of recent queries keeps permanence. No extra `GetUnitList` calls.

**Part B, reaction delay** (`jmz_func.lua`, next to `J.IsWillBeCastUnitTargetSpell`):
- `IsWillBeCastUnitTargetSpell` / `IsWillBeCastPointSpell` gate on `HPerception.IsCastKnown(caster, abilityName)`. A cast is a new event when its ability changes or it has not been seen for `EventGap` (0.5 s); it is known `SampleDelay(bot,'react')` after first seen.
- The human-caster "perfect timing" branch: with perception on, a bot below `WaitForWindowSkill` (0.7) fires as soon as the cast is known; at or above it, it fires once known and inside the original optimal window (`nPoint * (1 - nCycle) < 0.27`). With perception off the original condition is unchanged.
- The five `Is*ProjectileIncoming` predicates read `HPerception.GetIncomingTrackingProjectiles(unit)` (also `J.GetIncomingTrackingProjectiles`, used by Templar Assassin's trap). Enemy projectiles are identified by caster + ability name (or `attack`); an identity absent from a call is dropped, and one not checked for `IdentityTimeout` (2 s) is forgotten. Allied projectiles pass. Cached per frame per target.
- `IsChanneling` on enemy units (stretch, `Perception.Channel`): true only once the observer has seen the channel for its react delay. A channel following a cast the observer was tracking inherits that cast's `knownAt`, so it is not delayed twice.
- Not routed: the `GetLinearProjectiles` sites (Puck, Ancient Apparition, Rubick's AA copy, Shredder) and Oracle's `GetIncomingTrackingProjectiles` all track the bot's own projectiles, and `J.GetCreepAttackProjectileWillRealDamage` / `J.GetAttackProjectileDamageByRange` are last-hit damage maths, not reactions.

**Overlay** (Debug on): `percept: hidden=<pending heroes> noticed=<n> lastNotice=<s>` and `react: pendingCasts=<n> lastReact=<s>`. Logs: `[H:perception] pid=.. noticed <hero> after <s>s (<delay|close|damaged|teammate>)` and `pid=.. react <caster> <ability> known after <s>s`.

**Assumptions needing in-game confirmation (TODO (in-game))**
- `GetNearbyHeroes(r, true)` and `UNIT_LIST_ENEMY_HEROES` return only currently visible heroes, and handles stay stable while a hero is in and out of fog (permanence depends on this).
- `hUnit:IsNull()` is safe on stale illusion handles in the refresh pass.
- `WasRecentlyDamagedByHero(hero, 0.3)` works with an enemy hero handle.
- `GetIncomingTrackingProjectiles()` entries give `caster` for enemy projectiles when the caster is visible (nil-caster projectiles share one identity per ability).
- Whether modules are shared per team (teammate callout only works if they are; see "Shared-state finding").
- Cost at `host_timescale 2`: the hooks add a few table lookups per call; check for FPS drop.
- The reaction predicates are polled often enough (ability/item thinks every ~0.06–0.12 s) that the 0.5 s cast `EventGap` does not split one cast into two events.

**Manual test checklist** (compare `SkillOverride = 0.1` vs `0.9`, then real lobby and FretBots difficulty; record `HDebug.Log('perception', ...)` lines)
- [ ] Fog exit: walk out of fog into a lone enemy bot (e.g. Lion). Gap between visible and the bot's first action involving you: median about 0.5 s at low skill, 0.2 s at high.
- [ ] Lotus/BKB: cast a targeted disable on a bot holding Lotus Orb or BKB, 10 times each. Low skill rarely responds in time; high skill mostly does; never 10/10 at 0.9 unless the cast point is long.
- [ ] Juke: break vision for about 1 s and reappear. The bot re-acquires instantly.
- [ ] Smoke gank: 3 heroes appear next to a farming bot. A low-skill bot starts retreating noticeably later.
- [ ] Regression: 20 minutes with `Perception.Enable = false` behaves as before. With it on: no Lua errors, no visible FPS drop at `host_timescale 2`.
- [ ] Overlay shows `percept` and `react` lines updating.

## Ping response (05)
`FunLib/humaniser/pings.lua` (TS: `pings.ts`). Tuning lives in its `DEFAULTS`, overridable via `Customize.Humaniser.Pings`. Kill switch: `Pings.Enable = false`; every legacy ping reader then runs unchanged.

- **Interpreter:** every bot's `Tick` runs `Pings.Tick`, which scans at most once per team per frame (per module instance), only in `GAME_STATE_GAME_IN_PROGRESS`. It reads `GetMostRecentPing()` of **every** human ally and skips a ping it has already handled (`pid`, `time`) or one older than 3 s when first seen. The sourceKey is `ping:<pid>:<time>`, so each instance posts the same order once.
- **Classification** (first match wins), using only team-visible state: within 600 of the Roshan pit → `ROSHAN` (all, 25 s); visible enemy hero within 300 → `ATTACK` on that hero (nearest 2 within 4,000, plus anyone within 1,600, 8 s); enemy lane building within 700 → `PUSH` its lane (nearest 3, 20 s); own lane building within 700 → `DEFEND` its lane (nearest 2, plus bots beyond 5,000 with a TP ready, 20 s); rune or Tormentor spot within 800 → no order (rune/Tormentor modes keep their own ping handling); danger ping → `AVOID` (1,200 radius, everyone, 10 s); otherwise `GATHER` (nearest 2, 8 s). The building check is our own (towers, rax, fort; not outposts or fillers) rather than `J.IsPingCloseToValidTower`, which skips invulnerable towers that a human may still mean. A ping from a smoked human brings the whole team and replaces that human's `SMOKE` order.
- **Danger vs normal:** one function, `Pings.IsDangerPing`, currently `normal_ping == false`. Flip it there if step 0 says otherwise.
- **Mode wiring** (`Orders.DesireFloor`): `mode_roshan_generic.lua` checks the order before the `shouldKillRoshan and initDPSFlag` gate (issue #164), but only while Roshan is alive, the bot is above 30% HP and fewer than 2 enemies were last seen near the pit; the earlier gates (enemies near the bot, ancient threatened, Roshan about to switch sides) still apply. `aba_push.ts` returns the floor right after the "enemies at our ancient" gate; `aba_defend.ts` right after the "enemies very close, fight instead" cap. ATTACK/GATHER run in the assemble executor. With `Pings` enabled, the legacy ping branches in assemble, Roshan, push and defend are skipped so a ping isn't handled twice.
- **Accepting and acknowledging:** the core read delay (`Profile.SampleDelay('ping')`) and decline reasons apply. The spokesperson answers in team chat and pings back once at the order location. Every humaniser line is limited to 1 per bot per 10 s (`Orders.Say`), and ack pings to 1 per bot per 10 s.
- **AVOID:** the first bot in a module instance to accept calls `AddAvoidanceZone(Vector(x, y, radius), duration)`; the zone is removed when the order expires or is cancelled. AVOID does not hide the order a bot is executing (`GetFor` skips it).
- **Commitment:** `mode_retreat_generic.lua` passes its desire through `Orders.CapRetreatDesire`. With an accepted order (not `BACK`) and HP above 50%, retreat is capped at `DesireFloor - 0.1` (0.75); below 50% the bot retreats normally.
- **Staying out:** `Orders.AvoidsLocation(bot, loc)` and `Orders.FilterAvoided(bot, units)` apply once the bot has read the ping. Farm skips camps (`ClosestCamp`), lane fronts and lane creeps inside a zone, and drops a preferred camp that falls inside one. Team roam skips hero targets inside a zone unless the bot is already in it. Plain roam needs nothing: its only travel-to-target code, lane ganking, is commented out upstream.
- **AVOID is never declined:** before this change a dead, channeling or low-HP bot declined it, said a decline line, and ignored the zone after respawning.
- **Forgetting:** a danger ping lasts `Avoid.Duration` (10 s) at most. After `Avoid.MinSeconds` (4 s) it is forgotten early once the pinged spot is visible (`IsLocationVisible`) and no enemy hero has been seen within the radius for `Avoid.ClearSeconds` (2 s). The enemy check reads the perception-filtered unit list, so if modules are not shared, bots may forget it a moment apart.

**TODO (in-game) — step 0, ping semantics.** With Debug on, every new ping logs `[H:pings] <context> by <pid> @<time> danger=<bool>`. Do each of these once and record `danger` (and so `normal_ping`) in the table:

| Action | normal_ping |
|---|---|
| Alt+click ground | _?_ |
| Ping wheel "danger" | _?_ |
| Ping wheel "attack" / "enemy" | _?_ |
| Alt+click enemy hero | _?_ |
| Alt+click own / enemy tower | _?_ |
| Ctrl+Alt+click (danger) | _?_ |

If "attack" pings come back `normal_ping = false`, OHA's push/defend `not normal_ping` checks were right and `IsDangerPing` needs another signal (or AVOID should be dropped).

Other **TODO (in-game)** checks:
- Does `GetMostRecentPing()` work on a human ally's handle from a bot script, and does `ping.time` use `GameTime()`?
- Does `AddAvoidanceZone` take a duration, are zones per team, and do `Action_MoveToLocation` paths respect them (or only `GeneratePath`)?
- Does `ActionImmediate_Ping(x, y, true)` show as a normal ping to the human?
- Classification reads unit positions at the moment each bot first sees the ping. If module instances are per bot and see the ping on different frames, an enemy hero right at the 300 edge could classify differently. Check the `[H:pings]` lines from different bots agree.

**Manual test checklist** (human + 4 allied bots vs 5 bots, with and without FretBots):
- [ ] Ping an enemy hero in a side lane: the 2 nearest bots acknowledge, rotate and fight; the others keep farming.
- [ ] Ping Roshan at 20 minutes with the team healthy: all bots go, even when OHA's `shouldKillRoshan` would be false.
- [ ] Ping Roshan with 3 enemies visible at the pit: bots decline or hesitate.
- [ ] Ping our T2 while it is under attack: the nearest bots and a TP bot come and stay until the wave is cleared or 20 s pass.
- [ ] Danger-ping the enemy jungle entrance: bots stop pathing through it for about 10 s.
- [ ] Two humans ping different things at once: both are handled, with separate responders.
- [ ] A dead bot sends one decline line and doesn't spam.
- [ ] Overlay shows each bot's accepted order and time left (`order:`), any AVOID (`avoid:`) and the last ping (`ping:`).
- [ ] No more than 1 line per bot per 10 s from pings.

## Chat commands (06)
`FunLib/humaniser/commands.lua` (TS: `commands.ts`). Tuning in its `DEFAULTS`, overridable via `Customize.Humaniser.Commands`. Kill switch: `Commands.Enable = false`.

| Command | Order |
|---|---|
| `!def [lane]` / `!defend` | `DEFEND` lane, all able bots, 25 s. No lane: the lane whose creep front is deepest toward our ancient, with visible enemy heroes there counting most |
| `!push [lane]` | `PUSH` lane, nearest 3, 30 s. No lane: the lane nearest the issuer |
| `!rosh` / `!roshan` | `ROSHAN`, all, 40 s (same Roshan wiring as 05) |
| `!group` / `!g` | `GATHER` at the issuer, all, 15 s |
| `!go` | `ATTACK` at the issuer's ping from the last 15 s (and the enemy hero there), else their attack target; all, 10 s |
| `!smoke` | `SMOKE`: follow the issuer; the first responder with smoke in an active slot uses it once 3+ allied heroes are within 600. Nobody on the team has smoke: one bot says "no smoke" |
| `!back` | Cancel all orders; bots within 3,000 of the issuer move to the nearest own tower with no visible enemy hero within 1,500 (`BACK`, 8 s) |
| `!farm` | Cancel all orders (`RELEASE`); one bot says "ok" |
| `!bhelp` | One bot prints the command list |
| `-都来守家` | Alias for `!def`; the legacy `aba_role.ShouldTpToDefend` path still runs too |

- **Lanes:** `top`/`t`, `mid`/`m`/`middle`, `bot`/`b`/`bottom` are map lanes and mean the same for both teams, because Valve's `LANE_*` are absolute. "Mirrored for Dire" is implemented as `safe`/`s` and `off`/`o`: safe = bot for Radiant, top for Dire.
- **Targeting one bot:** `!2 def top` (team slot, the `!3pos` convention) or `!lion def top` / `!lion !def top`. Hero names match the unit name without `npc_dota_hero_`, with or without underscores (`crystalmaiden`), exactly or as a unique substring of 3+ characters. Ambiguous names (duplicate heroes) are ignored. The 3-character minimum keeps FretBots' `!me`, `!vo`, `!kb`, `!sp` from ever reading as selectors. `!farm` and `!bhelp` can't be targeted.
- **Issuers:** human allies in team chat only, in `GAME_STATE_GAME_IN_PROGRESS`. Bots and all-chat are ignored; a player not on the team logs `[H:commands] [WARN] ...` (Debug).
- **Determinism:** every module instance subscribes to the chat hub (`commands:<team>`) and parses every line. The sourceKey is `cmd:<pid>:<text>:<n>`, where `n` counts repeats of that text by that player, so instances agree without depending on frame timing and a repeated command re-posts. Bots read command orders with `Profile.SampleDelay('chat')` (`delayKind = 'chat'`).
- **Replies** ("no smoke", help, release ok) are queued for the team's lowest-PID bot and spoken in its own `Tick`, within the 10 s line limit. Order acknowledgements come from the spokesperson (`say_order_ack_<type>[_<lane>]`).
- **Chatter:** the reply-chatter subscriber already ignores `!` lines; FretBots' LLM reply ignores team chat and `!` lines; FretBots' host `PCallText` only sees a harmless syntax error.
- **Not done:** `!wards` (optional stretch).

**Chat only works after the horn.** `hero_selection.lua`'s `UpdateLaneAssignments` re-installs its own chat callback every frame until the horn, so a hub installed only in pre-game never received a message (found on the `spike` branch, 22/10/2026). The hub now installs again once the game is in progress (`[H:chat] reinstalled`); a command typed before the horn does nothing. Work inside the callback is queued (`Chat.Defer`, `Chat.DeferCall`) and run on the next `Tick`, because printing inside the engine's callback coincided with game crashes. That includes the `cmd` telemetry event.

**TODO (in-game):**
- Does the chat callback fire for team-only lines from the human, with `team_only = true`, and only once per bot context?
- Does `GetTeamMember(i)` inside the chat callback resolve to the issuer's team (needed for the issuer's location)? If Radiant and Dire share a VM, the callback's `GetTeam()` may belong to either team.
- Does `FindItemSlot('item_smoke_of_deceit')` on another bot return its slot (used to choose the smoke holder)?
- Does `GetAttackTarget()` on a human's hero return their target (`!go` without a ping)?

**Manual test checklist:**
- [ ] `!def mid` while mid T1 is under attack: bots go, at least one TPs if far, and they stay about 25 s or until the wave is cleared.
- [ ] `!rosh` at 18 minutes: the team goes even if OHA's own Roshan desire is low.
- [ ] `!smoke` with a support carrying smoke: bots gather on you, smoke is used once 3+ allies are close, and the group follows your next ping.
- [ ] `!lion push bot` moves only Lion.
- [ ] `!back` and `!farm` cancel cleanly, with no stuck bots.
- [ ] `!def mid` triggers no bot or LLM chatter reply; FretBots `!diff` and `!info` still work.
- [ ] An enemy-team human typing `!def` has no effect on our bots.
- [ ] `!bhelp` lists the commands, once.
- [ ] `-都来守家` still makes bots TP to defend.
- [ ] With `Commands.Enable = false`, behaviour matches upstream.

## Lane management (07)

Overview of the whole feature; the per-phase sections below it (camp data, lane state, techniques, camp jobs, stacking) keep their own detail and in-game TODOs. Spec: `handoffs/07-lane-management.md`. Kill switches: `Humaniser.Enable = false`, `Lane.Enable = false`, or every `Lane.*` flag false each restore the pre-07 behaviour (scenario 15). Offline, `test_lane_regression.lua` exercises the facade hooks, pings, chat commands and rune mode with the flags off (no action, no `GetUnitList` scan, unchanged desire) against a positive control; the laning and farm mode files cannot be loaded offline, so their hook call sites are source-pinned only. Full equivalence of those two files needs the in-game regression check in the test plan.

### Module map
All in `typescript/bots/FunLib/humaniser/` (generated Lua beside the TS). Imports only point down this list; a lower module that needs something from a higher one reads it through a probe registered in `lane_hooks`.

| Module | Role |
|---|---|
| `lane_config` | `DEFAULTS` for every number, `Settings()` deep merge of `Customize.Humaniser.Lane`, `IsActive()`, `Knows(tech, skill)` gates, curves, `Roll`/`Jitter`/`Gauss`, injected `J.*` helpers |
| `lane_hooks` | Probe registry (`IsRotationPlanned`, `IsStacked`, `TechniqueOverride`) so lower modules can ask higher ones without a `require` cycle |
| `camps_data` | Seed and generated camp entries (`source`: `seed`, `replay`, `measured`; `unverified`, `verifiedAt`) |
| `camps` | Resolves `GetNeutralSpawners()` against the data; derives meet points, pull paths and stack exits from lane geometry; team-relative/absolute lane amount conversion |
| `lane_state` | One snapshot per (team, lane), refreshed every `Timing.SnapshotRefresh` s: eqPos, creeps, wave timing, history; per-observer `ScoreFor` (exposure, laneScore) and `Enemies` |
| `lane_plan` | Shared lane plan (core plan inferred from a human core, `LANE_*` orders), human-pull detection, lane-front hands-off |
| `lane_roles` | Duo-lane partnership rules: who draws aggro, camp-job owner, partner safety, absent-core cover |
| `lane_planner` | Picks one technique per wave cycle with one attempt roll (`Plan`, `Commit`) |
| `lane_tech` | In-lane techniques run from the laning `Think()` hooks: block, aggro pull and drop, tower-aggro drop, freeze/hold positioning, shove |
| `camp_jobs` | Camp-job executor from `mode_farm_generic.lua`: full, half, double and stack pulls, stack jobs, contest jobs |
| `stacking` | Who stacks which camp, outcome bookkeeping, "stacked" state |
| `harass` | The one shared harass tool (timed punish plus idle poke) |
| `lane_mid` | Mid playbook: pre-rune shove window, ranged deny, hands-off beside a human mid |
| `counterplay` | Fair detection of enemy pulls, freezes, stacks, missing mid, rune shoves, and the responses (punish, contest, break freeze, camp block) |
| `lane_debug` | `!hpt`, `!hcamp` and the registry for `!hpulltest`, `!hstacktest` |
| `lane` | Facade: `Tick`, `OwnsLaning`, `PreThink`, `Think`, `AdjustPosition`, `PickDeny`, `MayDeny`, `SupersedesHarass`, `HarassThink`, `CampJobDesire/Think/OnEnd/Active`, `RuneContestDesire`, `PreferStackedCamp`. Hand-written Lua calls only this |

Hand-written Lua touched: `mode_laning_generic.lua` (hooks), `mode_farm_generic.lua` (camp-job desire, think, on-end, stacked-camp preference), `mode_rune_generic.lua` (`J.GetNextPowerRuneSpawnTime`, contest desire as a floor on the power-rune desire), `jmz_func.lua` (`Lane.SetHelpers`, `J.GetNextPowerRuneSpawnTime`), `localization.lua`, `Customize/general.lua`.

### Flags
`Customize.Humaniser.Lane.<Flag>` in `bots/Customize/general.lua`. `IsActive()` is true when `Lane.Enable` and any consumer flag (everything below except `Telegraph`) is on; every engine call in the lane code sits behind it, so an inactive system adds no `GetUnitList` scan and issues no action.

| Flag | Default | Turning it off disables |
|---|---|---|
| `Enable` | true | Everything |
| `OwnLaningThink` | `'allies'` | See below |
| `Plan` | true | Shared lane plan and inference, `LANE_*` orders, `!freeze !shove !pull !nopull !stack [lane]`, the lane-front ping hands-off, and the planner's use of the plan |
| `Block` | true | Creep block at 0:00 |
| `FullPull` / `HalfPull` / `StackPull` | true | That pull kind (`StackPull` also gates double pulls and the stack pull itself) |
| `AggroPull` | true | Aggro draw and drop, tower-aggro drop, tower swap |
| `Freeze` | true | Freeze/hold positioning and zoning |
| `Shove` | true | Shoves, including shove-before-rotating |
| `Stack` | true | Stack jobs |
| `Harass` | true | The shared harass tool; 04's original `HarassThink` runs again |
| `Mid` | true | Mid playbook (pre-rune shove window, ranged deny, human-mid hands-off) |
| `CounterPlay` | true | All counter-play detection and responses |
| `Telegraph` | true | Chat lines only (`pulling in 5`, `half pull`, `shoving then rotating`, `stacked big camp`, `they're pulling <lane>`, `their sup is missing`, `they're freezing`, `ss mid`). Never keeps the lane system active on its own |
| `Forecast` | true | Off: the `Foresight` weight is 0, so the planner's pull branch reads `laneScore` as before. See "Pull forecast" |
| `PreContest` | true | Predicts the enemy pull (`pull_expected` signal) from the mirrored lane forecast, for skill >= `Gates.PreContest` (0.7). See "Pull forecast" |
| `CampBlock` | false | Stretch: ward in the enemy pull camp's spawn box. Verify in-game first |

All other tuning (`Gates`, `Curves`, `Eq`, `Planner`, `ForecastModel`, `Timing`, `Thresholds`, `Radii`, `Infer`, `Camps`, `Orders`, `HarassIdle`) lives in `lane_config.ts` `DEFAULTS`, overridable by table under `Customize.Humaniser.Lane`.

### `OwnLaningThink`
`Lane.OwnsLaning(bot)` is read once at `mode_laning_generic.lua` load, like 04's `OwnsLaning`, and is false when no in-lane flag (`Block`, `AggroPull`, `Freeze`, `Shove`, `Harass`, `Mid`) is on. A bot that owns its laning runs OHA's laning `Think()` for the whole game (Valve's C++ laning cannot be filtered, and a defined `Think()` cannot hand back).
- `'allies'`: allies of a human. These are the bots 04 already gives OHA's Think. This only decides who runs the in-lane techniques; enemy-team bots still run every lane behaviour that lives outside laning `Think()` (see the split below).
- `'all'`: every bot, **enemy team included**, runs OHA's laning `Think()` for the whole game instead of Valve's. Blast radius: the enemy's laning gets only the upstream OHA behaviour plus 07's techniques, so game balance changes for every lane. Use it for experiments.
- `'off'`: nobody is given the Think by 07 (a bot 04 owns keeps it).
- 04's last-hit filter stays limited to allies of humans, whatever this is set to.
- **What follows `OwnLaningThink` and what does not.** Only behaviour run from laning `Think()` follows it: the in-lane techniques (block, aggro pull and drop, tower-aggro drop, freeze/hold, shove), harass, and the counter-play responses issued there (punish, camp contest, stack attack, camp block). Everything else follows the `Lane.*` flags alone and so, by default, also runs for enemy-team bots: camp jobs (pulls, from `mode_farm_generic.lua`), stacking, counter-play noticing and its telegraphs (from `Lane.Tick`), the rune contest (`mode_rune_generic.lua`) and the stacked-camp preference (farm mode). With the default `'allies'` an enemy bot therefore pulls, stacks and notices your pulls, but never punishes or contests them; scenario 9 needs `'all'`.
- **Harass:** with `Lane.Harass` on, every bot whose laning Think 04 or 07 owns uses the single shared tool in `harass.ts`: a timed punish of enemy last-hit attempts plus an idle poke equivalent to 04's, with 04's gates (protected human near, `WeAreStronger`, HP, tower range) as inputs for allies of humans. With it off, 04's `HarassThink` runs unchanged (its text is pinned by the `04 HarassThink text pinned` test).

### Design notes
- **Shared lane snapshot, per-observer perception:** `lane_state` keeps one snapshot per (team, lane). Exposure and `laneScore` depend on what the observer may see, so they are computed per observer in `ScoreFor`, never stored in the snapshot. At most one allied and one enemy creep scan per team per refresh and one enemy-hero scan per observer per refresh.
- **Planner:** `LanePlanner.Plan` re-decides live every call from current inputs. It keeps only one attempt roll per (cycle, technique) and one committed technique per wave cycle (`Commit`); `hold`, `none`, hands-off and safety aborts apply immediately. Freeze and hold are postures and never commit. A technique chosen under an order (`!pull`, `!stack`) skips the roll only for the ordered technique.
- **Camp-job window:** the start window (`aggro - travel - JobStartSlack` to `aggro + JobStartLate`) only gates the start. A running job holds `Timing.JobDesire` (0.7) until it finishes or aborts (as a CAMP_JOB claim when intent is on, see "Intent integration (09)").
- **Aggro confirmation:** a pull confirms the aggro hit (`GetLastAttackTime` or a neutral targeting the bot) before leading; no confirmation within `Timing.AggroConfirm` aborts the job.
- **Stack outcome:** the peak neutral count in the box, sampled from :02 to :05 while the box is in sight.
- **Human mid:** a passing bot never touches a human mid's wave (deny included); the mid-assigned bot still acts. The passing bot still sheds tower aggro (the safety drop), attacking only creeps it may touch.
- **Counter-play path safety** ignores the lane's own enemy laners (they stand near our lane; counting them would block every contest).
- **One shared harass tool** for 04 and 07, see above.
- **Counter-play telegraphs** are deduplicated per team per signal instance: two laners noticing one pull post one line.
- **Orders:** `LANE_*` orders sit on the 05/06 orders bus at priority -1, are never declined and never hide an executed order. Durations: freeze/shove 90 s, pull/nopull 120 s, stack 60 s, lane-front hands-off 30 s.

### Intent integration (09)
Intent arbitration (`intent.ts`) arrived on `humaniser` while 07 was in progress; these are the integration points as merged. With `Intent.Enable = false` every one of them falls back to 07's own behaviour.
- **Camp-job desire is a claim.** `mode_farm_generic.lua` returns `Lane.CampJobRawDesire(bot, CampJobDesire(bot))` for a live job: with intent on that posts a same-frame `CAMP_JOB` floor (`lane:<kind>`, 0.7, or 0.65 for a contest) on FARM and returns a raw 0, so the job counts as a lifted floor: `intent:survival` caps it below a low-HP retreat and any HUMAN_ORDER/SURVIVAL claim outranks it. Without intent (or for Meepo / a tempest double, which intent leaves out) it returns the job's desire as before. `CampJobDesire` itself (side effects: starting a job, committing the one-technique lock) is unchanged and still runs every farm `GetDesire`, so a job farm loses to a higher claim is ended `preempted` after `JobPreemptAfter` (1 s) without Think, releasing the cycle's lock when it never acted.
- **Other errands wait.** The same call caps ward, team_roam, roam, rune and the shops (`lane:job_focus`, CAMP_JOB, at the job's desire − `JobFocusMargin`) for the job's whole life; attack, defend and push stay free, and retreat too except while a pull's camp chases the bot (`lane:job_hold`). See "Lane management: camp jobs and pulls".
- **Cover.** A core whose support is on a camp gets a `lane:cover` LANE_PLAN scale (`CoverRetreatScale`) on its retreat (`CampJobs.CoverTick`).
- **Stickiness.** The same call posts a `lane:camp_job` claim with `unsticks = true` (normal `ClaimTTL`): while it is live no other mode gets the dwell/thrash bonus, so laning's (or any active mode's) stickiness cannot push a pull past its short start window. FARM itself keeps its bonus once active.
- **Stuck detector.** `Intent.Hold(bot, source)` (new, a no-op with intent off) marks deliberate stand-stills, which the stuck detector skips and after which its idle/still timers restart: camp-job wait at the stand point (`lane:job_wait`), waiting for the aggro hit to land (`lane:job_aggro`), the stack exit hold until `:00 + StackExitUntil` (`lane:stack_exit`), the end-of-path pull watch (`lane:job_watch`), the freeze/hold posture (`lane:freeze` / `lane:hold`) and the tower-swap wait (`lane:swap`). While a job runs, farm's raw desire is 0 (below `Stuck.MinDesire`), so the detector does not watch camp jobs at all; 07's own late / no-aggro / preempted timeouts end stalled jobs. The holds still cover the laning-mode stand-stills and keep the job phases correct if the raw path changes.
- **Laning last-hit suppression** (`and not Lane.CampJobActive(bot)` on laning's 0.9 return) stays as raw-desire logic: it must work without intent, and a CAMP_JOB cap on laning would only duplicate it.
- **Rune contest** stays `math.max(PowerRuneDesire, RuneContestDesire)` inside the power-rune branch, then through `Intent.Resolve`. As a floor claim it would also lift rune mode past that branch's own early-outs (enemy picking the rune, other runes), which 07 never did.
- **Lane orders.** `LANE_*` (priority -1, never declined) are skipped when `Orders.GetFor` picks the executed order, so `DesireFloor` / `CapRetreatDesire` never turn them into HUMAN_ORDER claims: no mode floors, no retreat cap, stickiness stays on. The lane-front ping during laning still posts `LANE_HANDSOFF`, not GATHER.
- **Run mode** (`runMode`) still aborts the job (`CampJobAbort(bot, "run")`) and skips `CampJobThink`; that frame's raw is ABSOLUTE × 1.1 and posts no job claim.
- **Laning `Think()`**: 14's step layout with 07's steps added: `Lane.PreThink`, `LastHitThink` (self-test first), `DenyThink` (07's `MayDeny`/`PickDeny`), `Lane.Think`, harass (07's shared tool or 04's), upstream, `PositionThink` (07's `AdjustPosition`). Defined when `bHumaniserLaning or bLaneLaning or bTrainerSelfTest` (or upstream's own conditions).

### Data method
- **Seeds:** `camps_data.ts` seed entries come from public guides (Liquipedia "Pulling", Dotafire, bo3.gg; accessed 21/10/2026). Small camp pull :15/:45, hard camp :18/:48, half pulls +2 s (now only the fallback for pulls: see "Pull timing from wave arrival"), stacks small 54.5, medium 54.0, large 53.5, ancient 53.0. The off-lane hard camp is `unverified`. Seeds claim the nearest spawner of their team (the other team's with `enemySide`) and type within `Camps.PullCampMaxTowerDist` (2500) of their own lane's T1 (T2 if dead) whose distance to its nearest lane point is at most `Camps.PullCampMaxLaneDist` (2400); an entry's `maxTowerDist` overrides the first. The off-lane seeds are `enemySide`: on the 7.41 map (entity lump of `maps/dota.vpk`, read 22/10/2026) the off lane pulls the enemy's hard camp beside their safe-lane T1. Dire `dire_off_large` resolves `neutralcamp_good_2` at (4649, -3699), 2180 from Dire's bot T1 (2688 from Radiant's), meet point about (6207, -3831); Radiant `radiant_off_large` resolves `neutralcamp_evil_1` at (-4824, 3915), 2554 from Radiant's top T1 (2168 from Dire's), meet point about (-6223, 4139). Both carry `maxTowerDist: 2800`, so a dead off-lane T1 (T2 ~4400-5100 away) drops the pull. Each team's own hard camp behind its off-lane T2 (`good_13` (-8313, -553), `evil_7` (7928, -120)) was the old off-lane seed: 12-20 s from the lane (console.9055874680 `gate=far` every wave), now a stack camp only. `good_2` is not Radiant's safe-lane hard camp at the default 2500 (2688 from its T1). One camp can hold a job for each team (evil_1: Dire's `dire_safe_large` and Radiant's `radiant_off_large`): `Resolve()` lists one entry per team, `CampJobData.team` is the job's team (not the spawner's), `ByIdx(idx, team)` returns that team's job (else the spawner team's), and camp jobs read their data with the bot's team. Stack claims are kept per pid and only an ally's blocks; `IsStacked` stays per camp (one physical stack). A core's stack camp skips the enemy-side camp our off lane pulls, and a camp block (`CampBlock`) skips our own camps, so the safe lane never wards its own hard camp against the enemy off-lane pull. The old `aba_site.ts` stack data is never used (pre-7.33).
- **Replay mining** (`tools/replay-mining`, see its README): `node fetch_replays.js --count 50 --out ./replays` (OpenDota, needs `bunzip2`), `go run ./parser <dem> > out/<id>.ndjson`, `node mine.js` (writes `out/aggregate.json`), `node gen_camps.js` (rewrites only the generated block between the `BEGIN/END GENERATED REPLAY ENTRIES` markers in `camps_data.ts`), `detect.js` holds the detection rules. The Go parser has not been compiled or run against a real replay (written from memory of manta's API); fix its entity and property names on first use. It cannot attribute lane-creep damage to one entity, so replay data is stack-only for timing; **half-pull divert data comes only from in-game measurement.**
- **Measurement:** run with `-condebug` and `Debug = true`; `!hpt` logs your position as a `Vector(...)` literal, `!hcamp` the nearest spawner box and its resolved job (`data=<seed|replay|measured|unverified>`), `!hpulltest <idx> [half]` and `!hstacktest <idx>` make your nearest bot run that camp. Then `node tools/replay-mining/parse_condebug.js <console.log>`: per camp and kind it prints attempts, ok rate and median aggro error, and a `suggest:` line once there are 5 or more attempts with at least 80% ok.
- **Promoting an entry:** paste the suggested seconds into the camp's `camps_data.ts` entry, set `source: "measured"` and `verifiedAt: "dd/mm/yyyy"` (the date of the run), and remove `unverified` if it was set. Replay entries are overwritten by `gen_camps.js`; measured ones belong above the generated block.

### Overlay and log formats
Overlay keys (Debug): `lane` (`eq`, `want`, `score`, creep counts, seconds to next wave, plan), `lane_tech` (planner choice and reason), `lane_exec` (`tech=<tech>@<sec> <phase>`), `lane_job` (`job=<kind>@<plannedSec> <phase> out=<divert>`).

Console lines (all `[H:lane] ...`, captured by `-condebug`):
- `pid=.. tech=<tech> @<cycleSec> reason=<reason>`: a technique started
- `mistake pid=.. <kind>` (for example `block-lost`) and `pid=.. mistake: double-draw`: deliberate or measured mistakes
- `job-start pid=.. kind=.. camp=.. key=.. data=<seed|replay|measured|unverified> aggroAt=.. forced=..`
- `job pid=.. kind=<full|half|stackpull|double> camp=.. key=.. aggro=.. planned=.. divert=.. grade=..`: graded completed pull, read by `parse_condebug.js`
- `job-abort pid=.. kind=.. camp=.. key=.. reason=.. divert=..`: any abort; not parsed, so aborts never count against a camp's timing
- `stack pid=.. camp=.. type=.. aggro=.. planned=.. before=.. after=<n|?> grade=<ok|mistake:early|mistake:late|unknown> stacked=<0|1>`: read by `parse_condebug.js`; `stack-assumed ...` is not parsed
- `harass pid=.. kind=<punish|poke> etiquette=<bool>`
- `counter pid=.. noticed=<kind> lane=.. camp=.. enemy=..`, `counter pid=.. camp-block camp=..`, `contest-end pid=.. camp=.. reason=.. pre=<0|1>`
- `hpt`, `hcamp`, `hpulltest`, `hstacktest` debug-command output

### TODO (in-game), consolidated
Items spelled out in the phase sections below (camp data, lane state, techniques, camp jobs, stacking) are not repeated: absolute vs team-relative lane amounts, spawner `type`/`idx`, waves at :00/:30, `GetLaneFrontAmount` ignoring towers, lane-creep unit names, deny detection through `GetAttackTarget()`, aggro drop above 50% HP, tower aggro drop and swap, block geometry, aggro triggered by the order, spawn boxes at 0:00, farm desire 0.7 against laning, one attack aggroing a whole camp, allied creeps targeting neutrals (divert measurement), seed timings per camp (stack :53-:55 by type, now Valve's windows where the camp is known; pulls :15/:45, :18/:48, half pulls +2 s), the `unverified` off-lane hard camp, `RandomVector(len)`, aggro confirmation, last-hit yield during a job, stack outcome by :05, `StackSight`.

Also to confirm:
- `GetAmountAlongLane(lane, location)` returns a table (`amount`, `distance`) and not a number; the code reads `.amount`.
- The neutral respawn-on-the-minute rule when the box is empty, and that wards in a spawn box still block the spawn on the current patch (gate for `CampBlock`, and for any ward-based stack denial).
- Laning desire against rune desire at 0:00: bots going to the bounty rune skip the 0:05 block; check the block still happens for the lane bots that stay.
- Job desire 0.7 beats the laning mode's 0.446 but not retreat: a bot in danger must still retreat out of a job.
- `GetHeroLastSeenInfo(pid)` returns a usable location and time for enemy supports in fog (counter-play "support unseen" and "last seen toward its camp").
- `J.GetPosition` on enemy heroes gives the estimated role (counter-play picks the enemy support and mid; the lane plan counts enemy laners).
- An enemy hero's `GetAttackTarget()` is readable for last-hit detection (harass punish `IsLastHitAttempt`), not only for the deny race.
- Cross-bot perception: `ScoreFor`, `Enemies` and `WeAreStronger` are evaluated for the lane's core from another bot's module (`lane_plan` `pickFor` and `EnemyLaners`). The enemy list comes from the observing bot's perception, so check the core's plan and enemy-laner count agree with what the core itself would see, and that the extra perception delay is acceptable.
- Harass: `GetExtrapolatedLocation` gives a usable approach direction for an enemy walking up to a last hit (`Thresholds.ApproachEpsilon`, `Radii.ApproachExtrapolate`), and the step-back (`AggroDanceStep`, `AggroDanceBack`) after a hit into 3 or more creeps looks natural and does not walk into the wave.
- Counter-play, expected pull arrival: `enemyArrivalSec` is the median first-reach of 3 creeps at our measured front; check it against the front position, because a wave our shove pushed far forward can read as a late or missing wave and be taken for a pull (false "pull" signal).
- Counter-play, rune contest: `RuneContestDesire` only acts from :52 of the minute before the spawn, because `GetBestRune` skips a power rune marked missing before then. Check the mid bot actually walks to the right rune (rune mode's own choice).
- Counter-play, contest and shove responses: path safety counts every enemy other than the puller and this lane's laners, so contests may rarely start; the shove override still needs `WeAreStronger` and HP, so a "not stronger" break-freeze or rune shove falls back to zoning. Judge whether either is too timid.
- `Orders.Say` chat lines: the telegraph lines listed under the `Telegraph` flag read naturally and respect the 10 s limit.
- 07-only bots (enemy team under `OwnLaningThink = 'all'`) laning with OHA's `Think()` instead of Valve's: compare lane results with `'allies'`.
- `!freeze`, `!shove`, `!pull`, `!nopull`, `!stack` resolve the lane from the issuer's position and the lane word, and bots acknowledge once.
- A ping on the lane front during laning hands the lane off for 30 s (no pulls, stacks, shoves or aggro draws from that lane's bots), and it expires.
- `GetTeamMember(1..#GetTeamPlayers(team))` is only valid for the caller's own team; every lane use is own-team, so confirm nothing reads it for the enemy.
- Fairness leak in `eqPos`: it reads `GetLaneFrontAmount(enemyTeam, ...)`, which is not vision-filtered, so an enemy wave pulled into fog still moves `eqPos` and the `rune_shove` and freeze signals built on it. Judge whether the shift is large enough to matter; if so, take the enemy front from visible enemy creeps only.

### Manual test checklist (spec scenarios; compare `SkillOverride = 0.9` with `0.2` / `0.4` where noted)
- [ ] 1 Data: the data calibration run produces `camps_data.ts` entries for every standard pull and stack camp; `!hstacktest` and `!hpulltest` succeed for each entry marked `measured`.
- [ ] 2 Full pull: push our wave to the enemy T1. The safelane bot (0.9) pulls on the next cycle, divert fraction above 0.8, equilibrium moves back toward our tower.
- [ ] 3 Half pull: with a small drift toward the enemy, a 0.9 bot picks a half pull with divert 0.3-0.6. At 0.4 it never attempts one (gate 0.6).
- [ ] 4 Stack pull: the bot stacks the small camp, pulls it on a later cycle, and the wave is fully killed.
- [ ] 5 Creep block: at 0:00 the first meeting point is measurably closer to our tower than with `Block = false`.
- [ ] 6 Aggro pull: one aggro pull shifts the meeting point toward our tower and the bot drops tower aggro correctly.
- [ ] 7 No pull when the partner is in danger: with 2 enemies visible on our carry the support stays. Once a pull is under way the support keeps going while the enemy laners only stand near the carry, and turns back within about half a second when they start hitting it (`lane_job_hold`, `reason=partner-dived`).
- [ ] 8 Harass timing: a human goes for 20 last hits next to a 0.9 bot: most attempts are punished. At 0.2 only some, at random timings.
- [ ] 9 Enemy pull detection (needs `OwnLaningThink = 'all'`: with `'allies'` enemy bots notice but never punish or contest): a human support pulls or half-pulls; 0.9 enemy bots punish or follow most times, 0.2 rarely.
- [ ] 10 Fairness: with all enemies fogged and no last-seen hints, counter-play never fires (no `counter pid=...` lines).
- [ ] 11 Bot duo: a bot pos 1 and bot pos 5 never draw aggro in the same 3 s window; the pos 5 does most draws while pos 1 last-hits; when pos 1 leaves for over a wave cycle, pos 5 holds the wave near our tower.
- [ ] 12 Human core: with a human pos 1 and a bot pos 5 the bot blocks with you, pulls, stacks, zones and draws aggro (not within about 3 s of you doing it); it infers your freeze (stops hitting the wave, no full pull) and your shove (helps); `!freeze` and `!shove` override; a lane-front ping stops lane jobs for 30 s.
- [ ] 13 Human support: with a bot pos 1 and a human pos 5 the bot core runs its own plan, reads your pulls and aggro draws as inputs, and does not contest your camp jobs.
- [ ] 14 Mid: the mid bot blocks at 0:00 and shoves about 15-20 s before rune spawns; with a human mid, passing bots leave the wave alone (no deny either).
- [ ] 15 Regression: `Lane.Enable = false`, then every `Lane.*` flag false: laning, farm, rune and ping behaviour match the pre-07 build; no `[H:lane]` lines.

## Lane management: camp data (task 07)

`camps.ts` resolves `GetNeutralSpawners()` against `camps_data.ts`; seed camps get meet points, pull paths and stack exits derived from lane geometry. Debug commands (need `Humaniser.Debug` and the Lane feature, human issuers): `!hpt` logs the issuer's position as a `Vector(...)` literal, `!hcamp` logs the nearest spawner box and its resolved job.

**TODO (in-game):**
- Engine lane amounts are read in the calling script's frame (`LANE_AMOUNT_TEAM_RELATIVE = true`, see "Lane amount frames" below): `camps.ts` `ToTeamAmount`/`ToAbsAmount` mirror only when `team` differs from `GetTeam()`, so a script reasoning about the other team (enemy camps' half-meet points, enemy lane state) still gets that team's frame. Measured for `GetAmountAlongLane`; `GetLocationAlongLane` is assumed to use the same frame. If a Dire bot's freeze/hold point or half-pull meet point lands on the wrong side of the wave, that assumption is wrong.
- Is a neutral spawner's `type` a string (OHA) or an int (API doc)? Both are accepted; confirm which, and that the table key is the spawner index.

## Lane management: lane state (task 07)

`lane_state.ts` keeps one snapshot per (team, lane), refreshed at most every `Timing.SnapshotRefresh` seconds and only while the lane system is active (Lane enabled and at least one consumer flag on). With Debug on, each bot's `lane` overlay line shows `eq`, `want`, `score`, ally/enemy creep counts and the seconds to the next wave.

**Lane amount frames (console.9055745679, bots-only game).** `GetLaneFrontAmount` answers in the calling script's frame (0 = own base) whichever team is asked: own and enemy fronts read the same value where the waves meet, and before the horn every bot, Radiant or Dire, read own 0 / enemy 1. Dire's `GetAmountAlongLane` of tower locations is also measured from the Dire base (Dire read Dire top T1 0.53 and Radiant top T1 0.70, while Radiant read them as 0.55 and 0.37). So `lane_state` takes both fronts from `GetAmountAlongLane(GetLaneFrontLocation(...))`, the same read and `Camps.ToTeamAmount` conversion as the towers, and `meetAmount` is their mean. `eqPos` does not change if that conversion runs the wrong way, so it is right for both teams whatever `LANE_AMOUNT_TEAM_RELATIVE` says; the stored `ourFront`/`ourTowerAmount` etc. only read in our team's frame for Dire once that flag is true. A front behind its own side's tower means that side has no wave in lane (it reads that side's base), so the other front is used alone (`MeetAmount`).

**TODO (in-game):**
- Waves spawn at :00 and :30 of `DotaTime()` on the current patch (`cycleSec = DotaTime() % 30`).
- `GetLaneFrontLocation(team, lane, 0)` has no ignore-towers flag, unlike the old `GetLaneFrontAmount(..., true)` read; check it still gives the creep front near a tower (inside tower range `eqPos` clamps anyway).
- Confirmed (console.9055828679.log): first-wave `eq` ≈ 0 in every lane for both teams (waves meet about midway between the T1s).
- Lane creeps are recognised by unit names containing `creep_goodguys`, `creep_badguys`, `goodguys_siege`, `badguys_siege`; ranged by `ranged`. Confirm against `GetUnitName()` for current lane creeps and siege.
- Enemy deny counting compares `GetAttackTarget()` of a visible enemy hero to the enemy lane creep handle by identity; confirm handles compare equal across calls.

## Lane management: in-lane techniques (task 07)

`lane_tech.ts` runs inside `mode_laning_generic.lua`'s `Think()` for bots whose laning is owned by `Lane.OwnsLaning` (`Lane.OwnLaningThink`: `'allies'` = allies of humans, `'all'` = every bot including the enemy team, `'off'`). `PreThink` (before last hits) runs the creep block, the aggro pull (draw, walk back for `Timing.WalkBack`, drop on an allied creep) and the tower-aggro drop; `Think` (after deny) shoves; `AdjustPosition` holds a freeze/hold position or zones for a support. A technique only starts when `LanePlanner.Plan` names it and commits on its first action; the tower-aggro drop is a safety reaction outside the planner. Freeze and hold are positions, not actions, so they never commit (committing would lock out the planner's own "freeze: drag back" aggro pull). Each start logs `[H:lane] pid=.. tech=<tech> @<cycleSec> reason=<reason>`, mistakes `[H:lane] mistake pid=.. <kind>`; the overlay line `lane_exec` shows `tech=<tech>@<sec> <phase>`.

**TODO (in-game):**
- Aggro drop: the attack order on an allied creep above 50% HP may be refused as an invalid deny; check the creeps still drop aggro.
- Tower-aggro drop: an enemy tower's `GetAttackTarget()` returns the bot while it is being shot; attacking an allied creep (or hero) in range makes the tower switch, then the bot leaves to 1,000 from it.
- Tower swap: attacking an enemy hero inside the tower's range pulls the tower off a low-HP allied core.
- Creep block: the block point (120 ahead, ±50 to the side of the lead creep) actually slows the wave; tune `Radii.BlockAhead`/`BlockSide`.
- Aggro draw: creep aggro is triggered by the attack order itself, so the walk-back moves issued on the next frames do not cancel it.

## Lane management: camp jobs and pulls (task 07)

`camp_jobs.ts` runs full, half and double pulls from `mode_farm_generic.lua` (desire hook before the farm mode's laning-phase early exit, Think hook before the ThinkLess throttle, OnEnd aborts a running job). In the laning phase a job is scheduled when the planner picks `full_pull`/`half_pull`/`stack_pull` and the start window is open (`aggro − travel − JobStartSlack` to `aggro + JobStartLate`, travel ≤ `MaxTravel`, straight-line distance over current move speed, and only while `now + travel ≤ aggro + JobStartLate`, since a later start can only end as `late`) for an aggro in a minute the camps have spawned in (`CampsUp`: from `Timing.NeutralFirstSpawn`, 1:00, so never before the horn and never at 0:15/0:45). The window only gates the start: a job then keeps `Timing.JobDesire` (0.7) through travel, wait, aggro, lead and watch until it is done, `JobMaxAfterAggro` (15 s) after the aggro, or aborted (flag off, dead, own HP below `Thresholds.JobMinHP`, not allowed to run a camp job, partner low or dived (see "Partner commitment" below), `LANE_HANDSOFF`, mode ended, farm mode starting a run, `preempted`, `late`). Farm's GetDesire registers a job whether or not farm wins the frame, so a job whose desire was queried but which farm's Think has not run for `Timing.JobPreemptAfter` (1 s) while another mode is active ends as `preempted`; a bot still walking `JobStartLate` after its aggro second ends as `late`. Neither touches the camp's stack mark: only a bot standing at its stand point and seeing no neutral (`mistake:no-camp`) clears it. A job aborted before farm's Think ever ran it releases the cycle's technique (the commit) and is not registered again for the same aggro, so another technique may still run that cycle. A double pull is a full pull at skill ≥ `Gates.StackPull` with a second pull camp, hard camp first (see "Double pulls" below). Logs: `[H:lane] job-start pid=.. kind=.. camp=.. key=.. data=<seed|replay|measured|unverified> aggroAt=.. forced=..`, `[H:lane] job-abort ... reason=..` for every abort (safety, mode end, no camp, unconfirmed aggro; not read by the parser, so aborts never count against a camp's timing), and the graded `[H:lane] job pid=.. kind=<full|half|stackpull|double> camp=.. key=.. aggro=.. planned=.. divert=.. grade=..` line read by `tools/replay-mining/parse_condebug.js`. `!hpulltest <idx> [half]` (Debug) makes the issuer's nearest bot run that pull, bypassing the planner and the owner check. Overlay key `lane_job`: `job=<kind>@<plannedSec> <phase> out=<divert>`.

**Partner commitment.** The start gate (`LaneRoles.PartnerSafe`: partner HP ≥ `PartnerMinHP` and fewer than `PartnerDangerEnemies` visible enemies within `PartnerDangerRadius`) also used to be the continue check, every frame. In a two-lane the enemy laners stand 800-1,250 from the core most of the time, so it flipped every few frames: in console.9055828679, 12 of 38 jobs ended `partner-unsafe` 0.3-8 s after a start that passed it, almost all in travel, with the core at 63-100% HP and both laners at their usual distance. A running job (pull or stack) now checks `LaneRoles.PartnerHolding` instead: it turns back only when the partner is below `PartnerBailHP` (0.35, under the start's 0.4 for hysteresis) or is being dived, meaning a visible enemy within `Radii.PartnerDive` (700) while the partner has lost at least `PartnerDiveLoss` (12%) of its HP over the last `Timing.PartnerHPWindow` (2 s), held for `Timing.PartnerBailConfirm` (0.4 s, the support's reaction). Two laners standing next to an unhurt core no longer end a pull; the one genuine dive in that game (core 98 to 63% in 6 s, enemies at 260-380) would still have. `lane_job_hold` logs the first frame of a job where only the commitment kept it going, and partner aborts carry the reading (`php pnear pclose ploss`).

**Stand point and aggro timing.** The stand point (`Camps.StandPoint`) is on the ray from the spawner origin, where the neutrals idle, toward the job's first waypoint (pull) or exit (stack), `StandOffset` past the box edge but at most `Radii.StandReach` (450) from the origin. Box-edge stands left the camp out of sight on 7.41's large, off-centre boxes (console.9055828679: every job on evil_2, the Dire safe small, 432-680 from its origin behind the box's tree line, and evil_8, the Dire ancient, 1,017 away, all `mistake:no-camp`). A stand with no camp neutral in sight from `StandApproachLead` (3 s) before the aggro moves in once to `StandApproach` (150) from the origin; `mistake:no-camp` is only called there, a bot still walking in gets the travel phase's `JobStartLate`. `aggroAt` is when the hit should land: the attack order goes out `J.GetAttackProDelayTime` (walk into range, wind-up, projectile; `AggroLeadDefault` 0.4 without it, at most `AggroLeadMax`) before it, from wherever the camp is first seen on the way in rather than only from the stand point (skywrath reached camp 17's stand 1-2 s late and logged aggro 54.7/55.1 for 53.5). The logged `aggro` is the hit: `GetLastAttackTime()` (taken as the release) plus the flight for a ranged hero, or the frame a neutral turns on the bot. Stack exits that run off the map (evil_7, ~200 from the east edge: the walk-off stopped 350 past the box and the trolls shot from inside it) turn by 45° steps, the side farther from the lane first, until every `ExitCheckStep` sample of the walk is `IsLocationPassable`.

**Pull forecast.** The planner used to read `laneScore = desiredEq - eqPos` from where the waves meet now. When the waves are not yet balanced that is where the lane is about to move, not where it will end up. `lane_state` weighs each side's creeps in the lane (`allyPower`, `enemyPower`: visible creeps only, HP weighted by type with `ForecastModel.TypeWeight` melee 1.0, ranged 1.6, siege 1.0) and takes `imbalance = (ally - enemy) / (ally + enemy + ForecastModel.PowerFloor)`, in -1..1. `forecastEq = clamp(eqPos + ForecastModel.K * imbalance, -1, 1)` (`K` 0.4) is where the waves meet after the current clash. A bot blends it in by skill: `foresight = Curves.Foresight(skill)` (0 at skill 0, 1 at skill 1) and `forecastScore = LaneScore(desired, eqPos + foresight * (forecastEq - eqPos), exposure)` (`ForecastScore`, `ObserverView.forecastScore`). `LanePlanner.Choose` uses `forecastScore` (falling back to `laneScore` when an input has none) only in the default pull branch: the full pull, stack pull and half pull checks and the final aggro correction. The freeze branch, cover-core branch and mid tower check keep `laneScore`. A lane we are about to win reads as more pushed out, so a skilled bot pulls earlier; one about to lose reads as less pushed out, so it does not pull a wave it will lose. `Lane.Forecast = false` makes `ForesightOf` return 0, which gives today's choices at every skill. Telemetry: `lane_plan` `gate=planner` carries `fscore w imb feq apow epow`.

**Fitting K.** `lane_eq` samples `eq`, `imb` and `feq` once per wave cycle. `tools/hlog` pairs each sample with the same lane's next one, 25 to 35 s later, and fits `eq(next) - eq(this) = K * imb(this)` by least squares through the origin, one row per lane kind: `forecast fit:` then `<kind> n=<pairs> K=<fit> r2=<fit quality>` in the summary. K is how far the lane's eq moves per unit of imbalance, so a fitted K well away from `ForecastModel.K` (0.4) means that setting should move to it; `ForecastModel.K` is the setting to change. r2 is the share of the eq changes that imbalance explains: near 0, K says nothing (towers, denies, hero fights and pulls move eq too), and a negative r2 means the fit does worse than predicting the mean change. Trust a row with n of a few dozen. The summary also prints `pre-contest: started <n> attacked <n> no-pull <n> enemy-in-lane <n> aborted <n>` from the `pre=1` contests (`attacked` = ended `no-target` or `timeout`; `aborted` = a safety abort on `lane_job_abort`), so `started` is the sum of the other four.

**Expected enemy pull.** `Counter.EnemyPullExpected` mirrors `forecastEq` to the enemy's side: their eq is `-forecastEq`, and when `LaneScore(enemyDesiredEq, -forecastEq, 0) <= Planner.FullPullBelow` (the lane has drifted toward our tower, far enough from where they want it that they would full-pull; with the default `Eq.Safe` = `Eq.Off` = -0.7 that is `forecastEq <= 0.2`) their support will want to pull. It returns the next aggro time of the enemy pull camp's wave-timed seconds (`PullTiming.ForCamp(camp, false)`) when the camps are up (`CampsUp`), and `undefined` when no enemy support is seen in our lane (`isLaner`), the camp has no pull seconds or the lane is not drifting. `Counter.Tick` posts it as a `pull_expected` signal (`campIdx`, `enemyPid`, `aggroAt`; instance key `pexp:<camp>:<cycle of aggroAt>`) only with `Lane.PreContest` on and skill >= `Gates.PreContest`, checked before the `CounterNotice` roll so no roll is spent below the gate. Unlike the other signals it stays live until its own `aggroAt`, not `Timing.CounterSignalTTL`: it is first seen just after the previous aggro, about a slot before its own. It is an input for a pre-emptive contest: noticing it posts no chat line. It reads only `LaneState.Enemies`, the snapshot and public camp data. `PreContest = false` leaves the existing pull detection and contest unchanged.

**Pre-contest.** A noticed `pull_expected` is answered from `respondToPull` (laning Think, so it follows `OwnLaningThink` like the reactive contest) by the lane's camp-job owner, with nothing committed this cycle, no live camp job and `LaneRoles.PartnerSafe`. The support waits at a lookout on the enemy camp's lead path (`PullTiming.LeadPath`), `Radii.PreContestStand` (400) along it from the spawner origin (`CampJobs.LookoutPoint`). It sets out so it arrives `Timing.PreContestLead` (2 s) before the expected aggro, and leaves at most a second before it needs to; a lookout over `Timing.MaxTravel` (12 s) away, one it can no longer reach in time, or an unsafe route (`pathSafe`, the puller excepted) starts nothing. The signal can be a slot old by then, so at departure `EnemyPullExpected` is run again on the current snapshot, with a fresh look for their support in lane; it starts only if that still gives the same `aggroAt`. After a pre-contest ends `enemy-in-lane` or `no-pull` the bot starts no other in that lane for `Timing.PreContestCooldown` (60 s, `CampJobs.PreContestResting`), so a lane the enemy keeps not pulling does not take the support out every cycle. The job is the `contest` job (it commits `contest` for the cycle, so our own pull and the pre-contest never both run) with a `lookout` phase ahead of the attack: it walks to the lookout and holds there (`Intent.Hold`, `lane:precontest`). The first sight of the puller at the camp (`contestTarget`) switches it to the existing attack logic, and `ContestMax` (10 s) counts from that moment, not from the start, since the lookout itself waits out the aggro. It ends `enemy-in-lane` when the expected puller is seen within `Radii.Exposure` of our front from `aggroAt - PreContestLead` on (they are not pulling, so the carry is not left alone), and `no-pull` when nothing has shown by `aggroAt + Timing.PreContestWait` (4 s); the usual safety aborts apply. The responded signal is not answered again, and the camp's reactive `pull` / `half_pull` signals in the aggro's wave cycle and the next count as answered (the observer records the pre-contest's camp and cycle), whether seen before or after it started, so the pull, if it comes, is not contested a second time. Every pre-contest end on `lane_job_end` carries `pre=1`, and so does a safety abort on `lane_job_abort`.

**Pull timing from wave arrival.** `pull_timing.ts` replaces the seed pull seconds with ones derived from our wave (`PullTiming.FromWave`, on). Our wave spawns at :00 and :30 (`WaveSlots`) at the lane's melee spawner and walks the lane's path_corner chain at `CreepSpeed` 325; the neutrals walk from the spawner origin along the job's lead path (box edge, meet point) at `NeutralSpeed` for the camp type; the aggro second is the wave's arrival at the meet point minus that walk minus `Lead` (1.5 s), so the neutrals are there just before the wave. A half pull uses its own (later) meet point and adds `HalfPullLater`. Sources: lane creep `MovementSpeed` 325 for every melee, ranged, siege and flagbearer creep, and the neutral speeds, from `scripts/npc/npc_units.txt` in `pak01_dir.vpk` (read 22/10/2026; Liquipedia's creep pages also list 325); the six lane paths (spawner origin then the `NPCFirstWaypoint` chain) from the entity lump of `maps/dota.vpk`, stored in `pull_timing.ts` (`PullTiming.LanePaths` overrides them per `<radiant|dire>_<lane>`). `NeutralSpeed` (small 290, medium 300, large 300, ancient 290) is a judgement: the camp chases the puller, so the first neutral to the meet moves at about the slower of the camp's fastest member (small camps: kobold 290, Vhoul 270, harpy storm 310, fel beast 350) and a support's ~300. Only `seed` camps are derived; `replay`/`measured` seconds are measurements and are kept. A meet point more than `PathMaxOffset` (500) from our lane's path (another map, a moved camp), a missing spawner or lane, or `FromWave` off keeps the seed seconds. `timing=wave|live|seed` on `job-start`/`lane_job_start` and `timing` on `lane_plan` say which was used.

Derived for 7.41 (8,479 / 8,319 along the path, 26.1 / 25.6 s): `radiant_safe_small` (good_1) :20.7/:50.7 and `dire_safe_small` (evil_2) :20.5/:50.5, against seeds :15/:45. In game evil_2's meet point (`GetLocationAlongLane`, read from the bots' watch positions in console.9055874680: about (-4005, 5520)) is ~340 off the Dire top creep path, so with the first `PathMaxOffset` of 300 its full pull, and every double pull on it, fell back to the seed (`timing=seed` on all of snapfire's doubles in console.9055921786, only its half pull derived); from that meet it is :21.7/:51.7 (8,322 along, 25.6 s), inside Valve's 21-23. The game ships its own pull hints in `scripts/creep_pull_timings.txt` (the `dota_hud_show_creep_spawn_camp_names` overlay): good_1 radiant 19-21/49-51, evil_2 dire 21-23/51-53, so the seeds were 5-6 s early, which fits every 9055874680 pull grading `no-divert` (neutrals at the meet ~:19, wave ~:26). The same formula (offline, straight-line neutral walk) gives the safe-lane hard camps (good_2 radiant, evil_1 dire) :31/:30 against Valve's 27-29 and seeds :18, and the off-lane pulls of those camps (dire on good_2, radiant on evil_1) :17/:21 against Valve's 17-19/19-20. The safe-lane hard camps come out ~2-3 s late; 7.41's patch notes say safe-lane creeps are "slightly accelerated" and off-lane ones slowed for a couple of seconds after leaving base until 7:30, with no figure, which the live reading below picks up.

The live reading (`PullTiming.LiveShift`, once at `Start`): once the pulled wave is `LiveFrom` (2 s) out of the barracks, the lead creep among our lane creeps within `LiveMaxOffset` (600) of the lane path and `LiveWindow` (5 s of walk) of where the wave should be moves the aggro by how early or late it is, at most `LiveMaxShift` (4 s); `timing=live`. The lane front from `lane_state` is not used: it is our frontmost creep, the previous wave, not the one being pulled. The job keeps the unshifted second as `slot` for `skipped`, and `plannedSec`/`baseAggro` carry the shift so `aggro`/`planned` stay comparable. A wave stopped short of the meet point by an enemy wave pushed past it is not modelled. The watch now also waits until `WatchAfterWave` (3 s) after the wave should reach the meet point (`waveAt`), within `JobMaxAfterAggro`. `PullTiming.ForCamp` gives a camp's derived seconds (seed fallback) outside the job too: `lane_plan`'s human-pull detection and `counterplay`'s enemy-pull suspicion (the enemy's wave on the enemy's lane path) read it instead of the seed `pullAggroSec`.

**Double pulls.** The second camp used to be led in once the first camp had engaged, timed into the first camp's meet. On 7.41 that cannot fit: the safe hard camp (evil_1 / good_2) is 6-9 s of neutral walk from the small camp's meet (via its own box edge), plus the support's walk from the meet to it, so it would reach the meet 10-16 s after the wave, which by then has finished the small camp; that second stage never started. The double is now the classic order, hard camp first: the job hits the hard camp from its side facing the small camp (`Camps.StandPoint` toward the small camp's stand), walks to the small camp's stand, hits it on its own wave-derived second and leads both to the small camp's meet; the hard camp's hit lands `before` = the walk between the stands at the bot's speed + `DoublePullHitGap` (1 s) ahead. The small camp's hit is the graded pull's (`aggro`, `planned`, `slot`, `waveAt`, the live shift); the hard camp's chase does not confirm it, only `GetLastAttackTime()`. `CampJobs.DoubleGeometry` checks the fit from the real geometry: the hard camp, chasing from its origin through the small camp's stand and lead path at `NeutralSpeed`, must reach the meet by `DoublePullJoin` (3 s) after the wave, and the walk between the stands must be at most `DoublePullMaxGap` (6 s; good_2 to good_1 is 4.8 at 300, 5.1 at 280). 7.41 (300 move speed): Dire evil_1 then evil_2, walk 1,140 (3.8 s), evil_1 hit :16.9 for evil_2's :21.7, evil_1 at the meet about 2.5 s before the wave (in practice it trails the bot, so with the small camp); Radiant good_2 then good_1, walk 1,440 (4.8 s), good_2 hit :14.6 for good_1's :20.4, 2.7 s before the wave. A double that cannot fit (`no-wave`: the small camp is seed-timed, so the hard camp cannot be placed against the wave; `far`; `join`; `reach`: the bot cannot stand at the hard camp by its hit) is not planned: the job is a plain full pull and `lane_plan gate=double-unfit` says why. The double's start window is the hard camp's hit's (`hit − travel − JobStartSlack`), and while that opens later than the small camp's own, a full pull is not started in its place. **TODO (in-game):** the hard camp keeps chasing over the ~1,300-1,900 to the meet; a bot walking to the small camp with the hard camp on it is not covered by the retreat hold (phase `travel`).

**The core plays safe meanwhile.** `CampJobs.CoverTick` (from `Lane.Tick`) has a core whose lane support is on a camp job post a `lane:cover` LANE_PLAN scale of `Thresholds.CoverRetreatScale` (1.25) on its own retreat, so it backs off sooner from the threat it would have stood against with the support beside it, and turns off 07's harass and forward harass stand point (`CampJobs.Covering`; those only run for bots whose laning Think 07 owns). The core knows from the support's job when modules are shared, otherwise from seeing the support away from the front (`SupportNearFront`) within `Radii.CoverCamp` (1,200) of one of the lane's pull camps, which also covers a human support's pull. A human core cannot be told that way, so the support pings the camp's stand point on its first Think of the job (`Orders.Ping`, which shares the ack pings' one-per-10 s limit), only when its lane partner is human and `Telegraph` is on; `lane_job_ping` logs it, `lane_cover` logs each core's caution start and end.

**Other errands wait.** Intent claims only order within one mode, so the job's CAMP_JOB floor on farm never ranked it over another mode's raw desire: in the same game ward (0.79-0.81) ended three jobs and team_roam (0.77-1.5) three. While a job is live `Lane.CampJobRawDesire` also posts a `lane:job_focus` CAMP_JOB cap at the job's desire − `Thresholds.JobFocusMargin` (0.02) on ward, team_roam, roam, rune, side shop and secret shop. Attack (Valve's), retreat, defend, push, laning and every HUMAN_ORDER/SURVIVAL claim are untouched, so a fight, a retreat (five jobs in that game, at 58-86% HP with retreat at 0.80-0.87) and an order still win. The caps cover the whole job rather than only the committed phases: a support walking to its pull does not stop to ward, and the travel phase is where ward took all three. Without intent there are no caps (farm returns the plain job desire).

**The camp chasing the bot is not a reason to retreat.** No pull finished in console.9055921786: 8 of 25 aborts were `mode-end` in lead or watch, with the bot at 49-80% HP and retreat at 0.79-0.90 "by raw". That is upstream retreat's laning-phase creep-damage branch (`mode_retreat_generic.lua`, `GetNearbyCreeps(1200, true)` includes neutrals): more than 15% of the bot's HP in 3 s from creeps targeting it gives `RemapValClamped(hp, 0.9, 0.5, 0.75, 0.9)`, exactly 0.795 at 78% and 0.893 at 52%, over the job's 0.7. Once the camp has been hit (the aggro phase after the attack order, lead, watch, and for a double pull everything after the hard camp's hit, including the walk to the small camp and the wait for its hit; pulls only, not stacks or contests) `Lane.CampJobRawDesire` also caps RETREAT at the job's desire − `JobFocusMargin` (`lane:job_hold`, CAMP_JOB), unless a real threat is there: own HP below `Thresholds.JobHoldMinHP` (0.5, ten points above `JobMinHP` so retreat takes over while a chased bot still has the HP to get out; the job itself aborts at 0.4), damage from an enemy hero or a tower in the last `Timing.JobHoldHeroHit` (1.5 s), a visible enemy hero whose attack target is the bot, or an enemy tower within 1,000 shooting it. The neutrals' own damage never releases it. The first threat releases the hold for the rest of the job, so a hit from a laner is not forgotten 1.5 s later. HUMAN_ORDER and SURVIVAL claims sit on higher tiers and still win; below `Survival.HP` (25%) the hold is long released. The same hold gates farm's own `X.ShouldRun` "don't trade into creeps below 70% HP" branch (level < 5, damaged by a creep in the last second, target healthier), which ended a pull in watch at 68% (`reason=run`, ogre 1:27). `lane_job_hold hold=retreat` logs the hold and its release.

**TODO (in-game):**
- `GetNeutralSpawners()` returns the spawn boxes at 0:00 (empty results are no longer cached, so a late answer is picked up).
- Farm desire 0.7 beats the laning mode's desire during the laning phase, so the farm mode (and its Think hook) actually runs the job.
- One `Action_AttackUnit(neutral, true)` aggroes the whole camp and the neutrals follow the bot along the lead path; neutrals reach the meet point before losing interest.
- `GetAttackTarget()` on allied lane creeps reports the neutral while they fight it (divert measurement); compare logged `divert` with what is seen.
- Seed pull seconds (small :15/:45, hard :18/:48, half +2 s) and the unverified off-lane hard camp (`data=unverified` in `job-start`): collect `job` lines and run `parse_condebug.js`.
- Wave-derived pull seconds (see "Pull timing from wave arrival"; good_1 :20.7, evil_2 :20.5): collect `job` lines with `timing=wave|live` and check `divert`; compare `live` shifts with the 7.41 safe/off-lane creep speed change; if hard camps still read late against `creep_pull_timings.txt`, lower their `NeutralSpeed` or measure the neutrals' walk. Earlier (console.9055828679, 9055874680) the :15/:45 seeds left the neutrals at the meet ~7 s before the wave (`no-divert`).
- `RandomVector(len)` returns a vector of length `len` (path noise).
- Aggro confirmation: after the attack order the job waits up to `Timing.AggroConfirm` (2 s) for `GetLastAttackTime()` (GameTime clock) to pass the order time or a neutral to target the bot before leading; check a melee support lands the hit from the stand point.
- Logged `aggro` treats `GetLastAttackTime()` as the projectile release; if it is the swing start, logged aggros read early by the wind-up. Compare `stack`/`job` aggro with the planned second after the early order (`AggroLead*`).
- evil_2 / evil_8 jobs see the camp from the new stand points (no `mistake:no-camp` with the camp up), and the walk-in (`StandApproach`) still lands the hit near the planned second.
- `IsLocationPassable` false on trees could turn an exit 45° that was fine; check evil_7 now exits north (about (7967, 1195)) and open camps keep their away-from-lane exit.
- `mode_laning_generic.lua`'s 0.9 last-hit desire yields while `Lane.CampJobActive(bot)`; check the support no longer leaves a pull at the meet point to last-hit.
- Retreat hold: pulls reach the wave with neutrals on the bot (no `mode-end` in lead/watch with `lane_job_hold hold=retreat state=on` and no `off`); `off` lines name a real threat. If chased supports now die or drop far below 0.5, raise `JobHoldMinHP`.

## Lane management: stacking (task 07)

`stacking.ts` decides who stacks and which camp; the stack job runs in `camp_jobs.ts` like a pull. Who: a pos 4/5 bot whose active mode is `BOT_MODE_LANING`/`FARM`/`NONE` (a job started under retreat, roam or defend wins farm's 0.7 only in that mode's dip and ends as `mode-end`); in the laning phase one with a stable lane (no enemy within `StableEnemyRadius` seen in the last `StableSeenWithin` s, HP > `StableMinHP`) and a safe partner; after laning one with no accepted order, HP above `StableMinHP` and no visible enemy within `StableEnemyRadius`. One attempt roll per minute (`Curves.StackAttempt`, 0.2 to 0.9); an accepted `!stack` order skips the roll, not the safety checks. Camp: our lane's pull camp (laning phase), then the nearest camp (not ancient) within `StackCoreCamp` of each core in position order, then our nearest ancient (a second stack in a row only above `Gates.MultiStackAncients`). A hands-off lane (`LANE_HANDSOFF`) gets no stack, checked before the roll. Camps with a visible enemy hero or another ally in the box (plus `BoxMargin`), or claimed by another ally's live stack job (claimed at its start, released on abort, expiring at its walk-off end), are skipped, as are camps whose stand point cannot be reached within `MaxTravel` and by the stack second. A stack is the wave cycle's technique: it starts only if nothing was committed in the cycle, and commits `stack`. The start window is `min(StackMoveFrom, aggroSec − travel − JobStartLate)` to `aggroSec`, only in a minute the camps have spawned in (from `Timing.NeutralFirstSpawn`, so the first stack is at 1:53-1:55; before this a negative pre-horn `DotaTime()` read as second :42 of minute −2 and sent supports out of lane to empty boxes); the job then holds `JobDesire` through travel, wait, one queued attack at `aggroSec + jitter` (confirmed as for pulls; `aggroSec` is `Stacking.AggroSec`, below), and the walk along `exitPath` until the next :00 + `StackExitUntil`. The walk-off past :00 does not claim the new cycle, so the :15 pull stays available. Outcome: neutral count in the box before the aggro, and the peak count sampled each frame from :00 + `StackOutcomeAt` to :00 + `StackOutcomeUntil` while the bot is within `StackSight` of the spawner origin (where the camp idles) and the origin is visible (`IsLocationVisible`; settled early once the count exceeds the before count); unseen outcomes are assumed stacked when the aggro was in the camp's stack window (below), else `StackAssumedFrom`..`StackAssumedTo` (logged `stack-assumed`). Log (read by `parse_condebug.js`): `[H:lane] stack pid=.. camp=.. type=.. aggro=.. planned=.. before=.. after=<n|?> grade=<ok|mistake:early|mistake:late|unknown> stacked=<0|1>`; the grade is timing only (early before `StackEarlyBefore`, late after `StackLateAfter`) so the parser's timing calibration is not skewed by blocked spawns or undercounts, and `stacked` (the count rose, or assumed) is the outcome that `IsStacked` and the telegraph use. A stack whose aggro landed is graded even if the job is aborted during the walk-off (the neutrals still left the box). A stacked camp stays stacked for its minute and the next (`IsStacked`, read by the planner through `LaneHooks.IsStacked`); a completed stack pull, or a job finding the box empty, clears it. "stacked big camp" (`say_lane_stacked_big`) after an observed stack of a large or ancient camp with grade ok, for allies of humans, at most once per `StackTelegraphCooldown` per bot. `!hstacktest <idx>` (Debug) makes the issuer's nearest bot stack that camp at its next reachable stack second (safety checks only).

**Stack seconds from Valve's windows.** 7.41 ships a stack window per camp in `scripts/creep_pull_timings.txt` (`stack_start`/`stack_end`, the second range the `dota_hud_show_creep_spawn_camp_names` overlay shows for landing the hit), stored in `stacking.ts` by spawner origin (`WINDOWS`, matched within 300; camps are 1,300+ apart). A camp on its type's default second (`camps_data` `DEFAULT_STACK_SEC`: small 54.5, medium 54.0, large 53.5, ancient 53.0) stacks at `StackWindowAt` (0.5) through its window (`StackFromValve`, on); a replay or measured stack second is kept. Most windows are later than the seeds (evil_2 and good_1 55-57, so :56 for 54.5; evil_1 54-56, :55 for 53.5; most medium and large camps 55-56, :55.5), a few earlier (good_2 and good_8 52-54, :53 for 53.5 / 53.0; evil_8 53-55, :54). The hit landing (`aggro`, `GetLastAttackTime()` plus flight, or a neutral turning on the bot) is what the windows mean and what the job schedules. console.9055921786's two completed stacks were both `stacked=0`: skywrath hit evil_1 at :53.76, before its 54-56 window, and its walk-off was ended at :58.3 by `unstable` (the start gate's `LaneStable` re-read every frame, an enemy coming into view within 1,200); ogre hit good_2 at :53.73 (inside 52-54) but counted the box at 8:02, night (hero vision 800), from ~1,100 off the origin and read 2 of 3. A running stack now checks only HP (`StableMinHP`, `low-hp`) and `PartnerHolding` in the laning phase (retreat still out-bids farm when the support is in real danger), and the outcome needs the origin visible. Snapfire's evil_2 attempt (4:54.7, `mistake:no-aggro`) attacked from its stand and chased a neutral moving out of the box west for 2 s without a hit landing; the cause is not clear from 1 s snapshots.

**TODO (in-game):**
- One queued `Action_AttackUnit` at the camp's stack second (Valve's window, else the seed: small 54.5, medium 54.0, large 53.5, ancient 53.0) pulls the whole camp out of the box before :00 and the walk along the derived exit (`Radii.StackExit`, 900, past the box edge, directly away from the nearest lane) keeps them out (turned when that walk is not passable, see "Stand point and aggro timing"). Before 22/10/2026 the 900 was measured from the box centre, which left a 200-400 walk-off from the stand point on 7.41's 600-1100 wide boxes (console.9055745679: warlock on the Radiant top medium, grimstroke and witch doctor on the Dire triangle hard camp); collect `stack` lines and run `parse_condebug.js`.
- By :05 (`StackOutcomeUntil`) the stacked neutrals are back inside the box (+ `BoxMargin`) so the peak `after` counts them; if they take longer, `after` undercounts and real stacks read as failed.
- `StackSight` (1,200) and `IsLocationVisible` on the spawner origin as "can see the camp" from the end of the exit path; trees may still hide neutrals in a visible box.
- Farm desire 0.7 wins over the laning mode at :45 for a laning support, and after laning over whatever a support would otherwise do.
- Stack pull (scenario 4): a stacked pull camp kills the whole wave; it is graded with the full-pull threshold (`FullPullMin`).

## Intent arbitration (09)
`FunLib/humaniser/intent.lua` (TS: `intent.ts`), exposed as `J.Humaniser.Intent`. Tuning in its `DEFAULTS`, overridable via `Customize.Humaniser.Intent`. Kill switch: `Intent.Enable = false` makes `Resolve` return the raw desire.

### API
- `Intent.Claim(bot, { source, tier, mode, floor?, cap?, scale?, until?, except?, allowRisk? })`. Claims are keyed by `source` + `mode`, so re-posting replaces. `mode = "ANY"` applies to every mode not in `except`.
- `Intent.Resolve(bot, mode, rawDesire)` runs at the end of every OHA `GetDesire()`. Non-numbers (nil, `false`) pass through untouched, as does a nil `mode`.
- `Intent.Explain(bot, mode)` gives `<mode> <desire> by <source>[+sticky]`, or `(valve)` when the mode is Valve's C++.
- `Intent.Release(bot, source, mode)` drops a claim early.
- `Claim` returns false when intent is off or leaves the unit out, so a caller that moved its desire into a claim can fall back to applying it itself.
- `unsticks = true` on a claim: while it is live, every other mode gets no stickiness bonus (07's camp jobs).
- `Intent.Hold(bot, source, until?)` marks a deliberate stand-still for `ClaimTTL` (or until `until`); the stuck detector skips the bot meanwhile and restarts its idle/still timers afterwards. `Intent.HeldBy(bot)` reports the live hold's source.
- `onlyLifted = true` makes a claim clamp a mode only where a claim floor has already lifted it above its scaled raw desire.
- State is keyed by player ID. Meepo and Arc Warden's tempest double share a player ID between units, so `Claim`, `Resolve` and `Tick` ignore every Meepo and the double: their desires pass through unresolved (upstream behaviour).

### Resolution
1. Multiply all `scale` claims together, clamp to `1 ± ScaleClamp` (0.3), apply to the raw desire.
2. Sort the floor/cap claims by tier (`MOOD < TRANSITION < CAMP_JOB < LANE_PLAN < FIGHT < HUMAN_ORDER < SURVIVAL`), then expiry, then `source`, and apply them in that order. Each one clamps the running value, so a higher tier always has the last word and, within a tier, the later-expiring claim does; equal expiry falls back to the source name, so every bot resolves the same way.
3. SURVIVAL claims are skipped for a mode that has a HUMAN_ORDER claim with `allowRisk = true`.
4. Stickiness, then floor at 0. The resolved value goes to `HDebug.RecordDesire`, so the overlay's top-3 now covers every OHA mode.

### Claim lifetime
Claims without `until` live `ClaimTTL` (0.2 s), not "until end of frame" as the handoff says. The engine evaluates modes in its own order and `Tick` runs from `ItemUsageThink`, so a same-frame lifetime would hide a claim from modes evaluated before it was posted. Claims that are consumed by the `GetDesire()` that posts them use `until = GameTime()`.

### Order hooks (migrated)
- `Orders.DesireFloor` still returns the floor and now also posts a same-frame HUMAN_ORDER floor claim. `Orders.OrderFloor` is the pure query. Every call site returns the floor immediately after calling `DesireFloor`, so the claim never outlives the call site's own gates (ancient under attack for push, close enemies for defend). Roshan was reordered for this: it checks its HP and pit-enemy gates with `OrderFloor` first, then calls `DesireFloor`.
- `Orders.CapRetreatDesire` still returns the capped desire and also posts it as a HUMAN_ORDER cap on RETREAT (only while HP > 50%, as before).
- Both are deliberately not post-hoc floors in `Resolve`: applying the order floor after the fact would override push's "ancient under attack" gate and Roshan's HP gate.

### Survival
When retreat resolves to at least `Survival.MinRetreat` (0.5) and HP is below `Survival.HP` (25%), retreat posts a SURVIVAL cap (`intent:survival`, `onlyLifted`) on every other mode at retreat's desire − 0.05. It only touches a mode that a claim floor (camp job, lane plan, mood) lifted above its own raw desire; OHA's raw desires (a buggy-hero attack override at 0.9 to finish a kill, defend near the ancient) are left exactly as upstream. 08's guard rails add their own SURVIVAL claims.

### Stickiness and thrash
- The active mode gets +`Sticky.Bonus` (0.06) for `MinDwell` (1 s) after it became active, decaying to 0 over `Decay` (1 s). No bonus:
  - on a zero desire;
  - on a mode with any cap claim (including the stuck cap), so stickiness never lifts a mode past a feature's cap;
  - while any SURVIVAL/HUMAN_ORDER claim was posted in the last `ClaimTTL`;
  - when retreat's latest resolved desire (within 0.5 s) is at least the mode's desire, so stickiness never keeps a bot in a fight it wants out of.
- Valve C++ modes (attack for most heroes) never get a bonus, so OHA modes have a slight edge over them for 1-2 s after becoming active.
- More than `Thrash.MaxSwitches` (4) switches in `Thrash.Window` (5 s): the mode switched into gets 0.12 for 3 s, and `[H:intent] thrash pid=... now=<mode> <competing modes and desires>` is logged.

### Stuck-mode detector (#167)
- Frozen = active mode unchanged ≥ 1.5 s, active desire ≥ 0.1, and **both** idle (`GetCurrentActionType()` IDLE/NONE with nothing queued) and within 50 units for ≥ 1.5 s. The handoff says idle **or** still; that would flag a laner standing to wait for a last hit and knock its laning desire down. `Stuck.Match = "idle_or_still"` restores the handoff's rule.
- Excluded: pre-horn, dead, mode NONE, channeling, using/casting an ability, stunned, hexed, within 2,600 of the fountain, and while a feature holds the bot (`Intent.Hold`, e.g. 07's camp-job waits and freeze posture).
- Laning within `Stuck.LaneFrontRadius` (1,200) of either team's creep front in its assigned lane is not a freeze. Laning's `PositionThink` moves the bot to the front minus its attack range and the move completes, so a laner waiting for the first wave (the front is where its own or the enemy's wave has walked to) or for a last hit is idle and still there. Without this, 141 of 153 episodes in a 16-minute bots-only game were laners waiting in lane, each capping laning by 0.15. A laner frozen away from its wave (jungle, base path, a stale spot after the wave died) is still flagged; a freeze right at the front is not.
- The 0.1 minimum is checked against the mode's raw desire where it is ours, because the active desire already includes the stuck cap.
- Known false positive: the rune mode's wisdom shrine wait (`Action_ClearActions`, 3.5 s standing at ABSOLUTE desire) counts as an episode. Harmless, since 0.85 still wins, but it shows in the counts as `rune`.
- Response: `[H:intent] stuck pid= mode= desire= since=` once per episode, a per-mode episode count, and an `intent:stuck` LANE_PLAN cap of raw − 0.15 that is refreshed while the bot stays frozen and expires 2 s after it moves. Orders (HUMAN_ORDER) and SURVIVAL still win over it. On a Valve C++ mode the cap has no effect; the log still names the mode.

### Wiring
- Lua: farm, outpost, roam, roshan, secret/side shop, team_roam, ward and retreat wrap their existing `return res`. Laning, rune and assemble keep their `GetDesire()` untouched and are wrapped right after it (`local GetDesireRaw = GetDesire`). `mode_attack_generic.lua` wraps the buggy-hero override only; other heroes' attack desire is Valve's.
- TS: `GetPushDesire` / `GetDefendDesire` wrap their helper, so `bot.pushDesire` / `bot.defendDesire` hold the resolved value.
- Not wrapped: `mode_assemble_with_humans_generic.lua` (always 0, nothing to arbitrate) and `mode_retreat_generic_wip.lua` (not a mode file the engine loads).
- `Intent.Tick` runs from `Humaniser.Tick` (mode-switch tracking, stuck detection, summary).

### Telemetry
- Overlay (Debug): `intent: <active mode> <desire> by <source>`.
- End of game (always printed, once per bot, when an ancient falls or the game reaches POST_GAME; `Intent.Summary = false` turns it off): `[H:intent] summary pid= <hero> switches= thrash= stuck=<mode>:<n>,... conflicts=<winner>><loser>:<n>,...`. A conflict is counted once per episode: from the first frame one claim overrides another claim's value on a mode until a frame where that mode resolves with no override.

### For 07, 08, 11, 12
Post claims instead of editing desires: camp jobs as `CAMP_JOB` floors on the job's mode, the lane plan as `LANE_PLAN`, tilt and mistakes as `MOOD` scales, 08's guard rails as `SURVIVAL` caps. 07's `PlanSustain` / `PlanMinDwell` stay: they damp the plan, this damps the modes.

**TODO (in-game):**
- `BOT_MODE_OUTPOST` exists as a global. If it is nil, outpost desire passes through unresolved (no error).
- `GetCurrentActionType()` returns IDLE/NONE for a bot frozen as in #167, rather than a MOVE_TO to its own position. If the freezes don't get logged, try `Stuck.Match = "idle_or_still"` in a test game and check the false-positive rate in lane.
- Bot scripts still run when the ancient dies, so the summary prints.

**Manual test checklist:**
- [ ] #167 repro: pos 3/4 bots in lane for 10 min. Compare `[H:intent] thrash` / `stuck` counts and the summary with `Intent.Enable = false`; freezes over 3 s are gone or logged with the mode named.
- [ ] `!def mid` while a bot is on a camp job (07) or tilted (08): the order wins every time.
- [ ] A bot under 20% HP with a stack job due: retreat wins.
- [ ] `Intent.Enable = false`: behaviour matches the `humaniser` branch (the overlay's top-3 desire line goes back to empty).
- [ ] No visible FPS drop at `host_timescale 2`.

## Last-hit accuracy (task 10)
Low-skill bots misjudge last hits and deny less. `Customize.Humaniser.LastHitSkill.Enable = false` (or `Humaniser.Enable = false`) restores upstream exactly, and skill 1.0 is always upstream.

- **Module:** `FunLib/humaniser/last_hit_skill.lua`, `J.Humaniser.LastHitSkill.WillKill(bot, creep, damage, delay, isDeny)`. It replaces the bare kill check in laning's `GetBestLastHitCreep` (last hit and move-to lookahead), `GetBestDenyCreep`, mid's ranged deny (`LaneMid.PickDeny`) and team roam's `X.GetLastHitCreep`. Farm mode never times a last hit, so it is not wrapped.
- **Per creep, per bot,** kept until the creep is gone: an error `eps` in [-1, 1] and whether the bot tries at all. Damage is judged as `damage * (1 + eps * e)`, where `e = lerp(0.15, 0.02, skill)`, ×1.5 when the bot was hit by a hero, or attacked one, in the last 2 s (time-latched, so turning to a creep does not end it at once). The try rate is `lerp(0.75, 0.98, skill)`, or `lerp(0.35, 0.9, skill)` for denies. Because the rolls are kept, `GetDesire` (laning 0.9, team roam 1.5) and `Think` agree on the same creep, so nothing flickers under intent arbitration and no claim is needed.
- **Ranged priority:** for `0.6 < skill < 1`, the bot takes a ranged or siege creep first when several are killable together.
- **Valve laning:** with `RequireOwnedLaning = true` (default) only bots whose laning `Think()` OHA owns are affected, everywhere. Each other bot logs `[Humaniser] LastHitSkill: pid=<pid> <hero> is on Valve laning; no effect (set Lane.OwnLaningThink='all')` once. Enemy bots are only owned with `Lane.OwnLaningThink = 'all'`. The trainer's self-test bot always stays exact.
- **Overlay** (`Debug = true`): `cs: e=<e> attempts=<n> misses=<n>`. An attempt is a last-hit or deny swing the bot issued (`NoteAttempt` beside the attack in laning and team roam), not a kill check. Each 0.25 s, attempts whose creep has gone count as hits up to how far `GetLastHits()` (`GetDenies()` for denies) moved since the previous tick; the rest are misses. A spell last hit in the same tick can hide one miss.

### Manual test checklist
Setup: 1v0 lane, bot alone, `Lane.OwnLaningThink = 'all'`, `Debug = true`, 10 minutes per run. Record last hits, denies and the final `cs:` line.
- [ ] `SkillOverride = 0.2`: about 35–45 last hits, low denies.
- [ ] `SkillOverride = 0.5`: about 50–60, moderate denies.
- [ ] `SkillOverride = 0.9`: about 70+, high denies.
- [ ] Same bot under harass loses noticeably more last hits than in the free run.
- [ ] Regression: `LastHitSkill.Enable = false` matches the current branch within normal variance.
- [ ] The `intent:` overlay shows no thrash episodes from laning ↔ team roam flips.

## Last-hit trainer (task 14)
`FunLib/humaniser/trainer/` (TS: `api.ts`, `settings.ts`, `incoming.ts`, `predict.ts`, `judge.ts`, `stats.ts`, `format.ts`, `watch.ts`, `draw.ts`, `trainer.ts`, `spike.ts`). Tuning in `settings.ts` `DEFAULTS`, overridable via `Customize.Humaniser.Trainer.LastHit`. Kill switch: `Trainer.LastHit.Enable = false`. The trainer then does nothing: no helper calls, no chat, no `[H:trainer]` lines. Only the lowest-PID bot on each team runs it, and nothing happens in game until `!trainer on` (or `SelfTest = true`).

### Commands
| Command | Effect |
|---|---|
| `!trainer` | Status line: `trainer off - bar on - chat off - denies on` |
| `!trainer on` / `off` | Start (stats reset; already on just replies the status) or stop all drawing, text and chat |
| `!trainer bar on\|off` | Show or hide the bar |
| `!trainer denies on\|off` | Grade denies |
| `!trainer chat off\|misses\|all` | Send verdicts to team chat |
| `!trainer stats` | Print the summary and the biggest leak; also shown as screen text for 15 s |
| `!trainer stats selftest` | The trainer bot's own score (see self-test) |
| `!trainer reset` | Clear stats; replies `trainer stats reset` |
| `!trainer spike` | Toggle the spike probe (only with `Debug = true`) |

`trainer` takes no bot selector (`!lion trainer` and `!2 trainer on` don't parse). Unknown subcommands print the usage line. Replies are queued per team (capped at 8 lines) and spoken by the trainer bot, one line per 0.5 s.

### Config keys (`Customize.Humaniser.Trainer.LastHit`)
| Key | Default | Meaning |
|---|---|---|
| `Enable` | `true` | Kill switch |
| `Bar` | `true` | Draw the countdown bar |
| `OutcomeOnly` | `false` | Spike fallback: grade outcomes only if swing timing can't be read |
| `ScreenText` | `true` | `false` sends verdicts and summaries to team chat |
| `Denies` / `Chat` | `true` / `'off'` | Grade denies; `'off'`, `'misses'` or `'all'` |
| `EasyWindow` | `0.3` | Seconds of window that make a creep an "easy" one |
| `Checkpoints` | `{300, 600}` | Summary times in game seconds |
| `SelfTest` | `false` | The trainer bot times its last hits from the trainer's window |
| `TextX`, `TextY` | `560`, `40` | Screen text position (not in `general.lua`) |
| `WatchInterval`, `MaxWatched` | `0.1`, `2` | Prediction refresh and watched-creep budget (not in `general.lua`) |

### Spike results (Phase 0, Task 1 Step 7)
The spike has not been run. Every result below is **pending (run `!trainer spike`)**: Local Host lobby, cheats on, `Debug = true`, `!trainer spike`.

| # | Question | Result |
|---|---|---|
| 1 | Are draws visible with `Debug = true`, and with `Debug = false` (change `HDebug.IsEnabled()` locally)? | pending |
| 2 | Bars smooth or flickering? Think rate? | pending |
| 3 | Which human-hero reads work? | pending |
| 4 | Is `GetAttackProDelayTime` sane on the human? | pending |
| 5 | Which bar style does the user prefer? | Neither. In game, both moved against a reference that also moved (the window resized; the HP style's damage line sat at a different spot per creep), and the two looked alike. Replaced by the countdown bar (22/10/2026). |
| 6 | Optional: latency from a bot `ActionImmediate_Chat` line to a FretBots `player_chat` listener (probed by hand, no code) | pending |
| 7 | Does a Unicode text line render (plan correction 4)? | pending |

Decisions still to record, in `settings.ts` and `general.lua` in one small commit: `OutcomeOnly`, `ScreenText`.

### Plan corrections
The plan overrides the spec in four places:
1. **Incoming damage is ported, not called.** OHA's helpers scan creeps around `GetBot()` (the trainer bot, possibly in another lane), add bot-level fudge factors, and see only attacks already under way. The trainer needs the subject's lane, no fudge, and projected idle swings.
2. **`SetHelpers` exposes only `GetAttackProDelayTime` and `IsInLaningPhase`.**
3. **`IsFeatureEnabled` is not extended.** The config is nested (`Trainer.LastHit.Enable`), so the trainer has its own `IsEnabled()`.
4. **Screen text uses ASCII `-`** instead of `–`/`−`, because `DebugDrawText` may not render non-ASCII text (spike item 7).

### Behaviour decisions
- **Countdown bar:** 200 units wide at 80 units/s. The white swing line is fixed 60 in from the left, the same place on every creep. The window is drawn from that line leftwards, its length the window's duration (cut at 0.75 s), so its line end never moves. The tall marker is now: yellow while counting down (up to 1.75 s ahead), the window colour inside it, red once it has closed. The blue tick is your swing start on the same scale, so its distance past the line is how late you started. Each drawn bar also gets a screen line, `<melee|ranged|siege>: <WAIT|READY|ATTACK|DENY|LATE>`, 150 px below `TextY` (the bot API has no world-space text). READY covers the last 0.3 s before the window opens.
- **`uncertain` (amber):** compares the close edge always, and the open edge only when it's in the future. A close capped at the 2 s horizon is ignored (R15, R15b).
- **Cancelled swings:** a creep whose only swings were cancelled still counts as an easy miss, with no swing. EARLY hits shield the creep (R9).
- **One verdict per creep death** (R7). When two swings are in flight and the creep dies to the player, the older swing is credited if its landing time was no more than 0.1 s ago (R8).
- **Allied heroes:** their denies count against our own creeps, and their last hits against enemy creeps (R10).
- **Prediction budget:** 2 bars + `MaxWatched` applies per subject. A self-test lobby with a human runs up to 8 predictions per frame (R11).
- **Counter matching:** last-hit counters are matched looking back up to 0.15 s before the death frame (R12).
- **Bar stickiness:** bars stay put unless another creep's window closes more than 0.2 s sooner (`BAR_STICKINESS`). Keep it at or above `WatchInterval`.
- **Creep ids** are `tostring(handle)`.
- **SelfTest** switches the trainer on at game start; `!trainer off` still turns it off.
- **One-player warning** goes through `HDebug.Log`, so it only prints with Debug on.

### Merge note with 07 (lane management)
Done in the `h-07-lane` merge as described below; the resulting step order is in "Lane management (07) > Intent integration (09)".

07 (`h-07-lane`) branched from `535087f`, before the laning `Think()` step refactor this branch builds on, so 07's `mode_laning_generic.lua` still has the older inline `Think()`. That file will not merge textually:
- Take the step layout (`LastHitThink`, `DenyThink`, `HarassThink`, `PositionThink`) from this branch, then port 07's lane-management logic into it as steps by hand.
- Keep the self-test branches at the top of `LastHitThink` (`SelfTestHolding`, then `SelfTestTarget`) and `DenyThink` (return false) as they are. They must run before any of 07's steps can issue an order, or the self-test bot's swings get cancelled.
- The `Think()` definition condition needs both 07's `or bLaneLaning` and this branch's `or bTrainerSelfTest`.

The other shared files (`general.lua`, `config.ts`, `index.ts`, `commands.ts`, `jmz_func.lua`, this document) only gained additions next to existing blocks, so their conflicts are additive siblings: keep both sides. New Dota API typings live in `trainer/api.ts`, not `ts_libs/dota/*`.

### Self-test lobby recipe
Calibrates the predictor against a bot that last-hits from the trainer's own window.
1. Put the human in a different lane from the trainer bot (the lowest-PID bot on the team).
2. Set `Humaniser.Lane.Enable = false` (07) and `Trainer.LastHit.SelfTest = true`.
3. Play 10 minutes.
4. Run `!trainer stats selftest`. Pass: at least 85% `PERFECT` + `OK` and under 5% `MISSED_EASY`.

### Regression check
`Trainer.LastHit.Enable = false` (with `Debug = true`): `!trainer on`, then play. No `[H:trainer]` lines, no trainer chat, no draws.

**TODO (in-game):**
- `GetLastAttackTime` semantics (attack start vs projectile release). The idle-swing projection assumes attack start.
- `IsAlive()` on cached handles that may have gone invalid.
- Do `GetLastHits` and `GetDenies` rise on the creep's death frame, or within the 0.15 s look-back? If counters update later, every last hit reads LATE. The fix would be a short death hold in `creepObservations` (R12).
- `ACTIVITY_ATTACK2` (1504) is treated as an attack.
- Swing-timing units: `cycle < GetAttackPoint()` and `swingStart = now - cycle / GetAttackSpeed()`.
- Unit-handle identity is stable across frames (`SelectCreeps` target matching and the ids rely on it).
- Frame cost with 2 bars and 2 watched creeps (spike item 7).

**Manual test checklist:** see the "Last-hit trainer (14)" block in [HUMANISER_TEST_PLAN.md](HUMANISER_TEST_PLAN.md).
