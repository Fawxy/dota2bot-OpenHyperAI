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
| `thrash` / `stuck` | Intent episodes | `switches competing` / `mode d raw inMode` |
| `trainer` | Trainer verdict | `selftest kind creep deny offset window pred landed` |
| `mark` / `mark_state` | `!mark` | `n by text` / one bot's full state at the mark |
| `game_end` | An ancient fell or post-game started | |

**Checks** (`tools/hlog/checks.js`):

| Check | Fails or warns when |
|---|---|
| `script_errors` | **FAIL:** any Lua error line in the console (runtime errors and `[Humaniser] chat subscriber failed`). |
| `snapshot_gaps` | **FAIL:** a bot stops reporting for more than 10 s (its script stalled or errored). |
| `notice_delay` | **FAIL:** a sampled notice delay is outside the bot's profile bounds (`base × (1 ± jitter/2)`, plus up to `LapseMaxExtra`), or a hero is noticed before its delay elapsed. **WARN:** it was noticed more than 1 s late. |
| `react_delay` | **FAIL:** a reaction is under `MinReact` or outside the profile bounds. |
| `order_read_delay` | **FAIL:** an order's read delay is outside the `ping`/`chat` bounds, or the order was accepted before it. |
| `order_followed` | **WARN:** an accepted order's mode (assemble, roshan, `defend_<lane>`, `push_<lane>`) never appears within 8 s while the bot is alive. |
| `lasthit_etiquette` | **FAIL:** an allied bot last-hits a creep it had decided to leave for a human (`dec=skip…`). |
| `intent_health` | **WARN:** each `stuck` or `thrash` episode. |
| `frozen_bots` | **WARN:** a live bot outside fountain range doesn't move for 10 s. Independent of Intent's stuck detector. |
| `trainer_selftest` | **FAIL:** with at least 20 self-test verdicts, under 85% `PERFECT`+`OK` or at least 5% `MISSED_EASY`. |

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

## Intent arbitration (09)
`FunLib/humaniser/intent.lua` (TS: `intent.ts`), exposed as `J.Humaniser.Intent`. Tuning in its `DEFAULTS`, overridable via `Customize.Humaniser.Intent`. Kill switch: `Intent.Enable = false` makes `Resolve` return the raw desire.

### API
- `Intent.Claim(bot, { source, tier, mode, floor?, cap?, scale?, until?, except?, allowRisk? })`. Claims are keyed by `source` + `mode`, so re-posting replaces. `mode = "ANY"` applies to every mode not in `except`.
- `Intent.Resolve(bot, mode, rawDesire)` runs at the end of every OHA `GetDesire()`. Non-numbers (nil, `false`) pass through untouched, as does a nil `mode`.
- `Intent.Explain(bot, mode)` gives `<mode> <desire> by <source>[+sticky]`, or `(valve)` when the mode is Valve's C++.
- `Intent.Release(bot, source, mode)` drops a claim early.
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
- Excluded: pre-horn, dead, mode NONE, channeling, using/casting an ability, stunned, hexed, within 2,600 of the fountain.
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
| `Bar` / `BarStyle` | `true` / `'time'` | Draw the bar; `'time'` or `'hp'` |
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
| 5 | Which bar style does the user prefer? | pending |
| 6 | Optional: latency from a bot `ActionImmediate_Chat` line to a FretBots `player_chat` listener (probed by hand, no code) | pending |
| 7 | Does a Unicode text line render (plan correction 4)? | pending |

Decisions still to record, in `settings.ts` and `general.lua` in one small commit: `BarStyle`, `OutcomeOnly`, `ScreenText`.

### Plan corrections
The plan overrides the spec in four places:
1. **Incoming damage is ported, not called.** OHA's helpers scan creeps around `GetBot()` (the trainer bot, possibly in another lane), add bot-level fudge factors, and see only attacks already under way. The trainer needs the subject's lane, no fudge, and projected idle swings.
2. **`SetHelpers` exposes only `GetAttackProDelayTime` and `IsInLaningPhase`.**
3. **`IsFeatureEnabled` is not extended.** The config is nested (`Trainer.LastHit.Enable`), so the trainer has its own `IsEnabled()`.
4. **Screen text uses ASCII `-`** instead of `–`/`−`, because `DebugDrawText` may not render non-ASCII text (spike item 7).

### Behaviour decisions
- **Time bar:** the track spans now-0.5 .. now+2.0 s. The white "now" tick sits at 0.5/2.5 of the width, so your swing start (the blue tick) shows next to the window (R14).
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
