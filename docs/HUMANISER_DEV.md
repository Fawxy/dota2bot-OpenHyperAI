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
- **Tiers** from `Profile.deference`: Polite `d >= PoliteMin` (0.75), Helpful `d >= HelpfulMin` (0.4), otherwise Teammate. Behaviour follows the handoff table. Helpful and Teammate both refuse the human's current attack target.
- **Config:** all thresholds live in `DEFAULTS` in `ally_last_hit.ts`, shallow-merged with `Customize.Humaniser.AllyLastHit` (lists replace the default list).
- **Laning (`mode_laning_generic.lua`, option A):** `Think()` is also defined when `AllyLastHit.OwnsLaning(bot)` is true at file load: the feature is on and the team has a human. Valve's C++ laning cannot be filtered and a defined `Think()` cannot hand back to it, so these bots use OHA's laning `Think()` for the whole game, also when no human is near. The load-time check uses `GetTeamPlayers`/`IsPlayerBot`, which upstream already reads at load (`teamHumans`). Human positions are deliberately not part of the load-time decision, because they can still change before the horn.
  - Candidate last-hit creeps go through a filter. A `take:` verdict is final. Otherwise upstream's rule applies: pos 1–2, or no other core within 700.
  - The 0.9 last-hit desire in `GetDesire()` is gated by the same filter. It is not extended to the new bots, so mode selection stays as upstream and only `Think()` changes.
  - **Support idle behaviour:** last hit, then deny, then harass, then move to the lane front (existing code). Harass is one right-click on the nearest enemy hero within attack range + 300 every `HarassInterval` (2.5 s). It needs a protected human near the bot, `J.WeAreStronger(bot, 1200)`, HP ≥ 50%, and neither unit within 850 of an enemy tower.
- **Farm (`mode_farm_generic.lua`):** the lane-creep lists used for desire and for the attack target go through `AllyLastHit.FilterCreeps`. That returns the same table when etiquette is off.
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
- [ ] Low (Valve Easy / FretBots 1): support last hits near the human = 0, denies > 0.
- [ ] Mid (Medium / 5): the support only takes creeps while the human is away or idle. Walk out of lane for 30 s.
- [ ] High (Unfair / 9): the support never takes the creep you are attacking, but does take creeps you clearly miss.
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
