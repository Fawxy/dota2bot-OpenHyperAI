# Humaniser in-game test plan

Tasks 01–06 were built and checked offline only (`tests/humaniser`: a LuaJIT syntax check plus 204 behaviour tests). This plan covers what only the real game can verify. Run it in order: session 1 checks the assumptions the rest of the design rests on, so a wrong answer there may change later code.

Setup is in [HUMANISER_DEV.md](HUMANISER_DEV.md): symlink, lobby, `sv_cheats 1`. Set `Customize.Humaniser.Debug = true` for every session.

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
- [ ] Pings (05): hero, Roshan, tower and danger pings; two humans pinging at once; a dead bot declining.
- [ ] Commands (06): `!def mid`, `!rosh`, `!smoke`, `!lion push bot`, `!back`, `!farm`, `!bhelp`, `-都来守家`; confirm FretBots `!diff` and `!info` still work.

## Session 4: regression
- [ ] `Customize.Humaniser.Enable = false`: a 20-minute game behaves like upstream (Valve laning for supports, legacy ping response, no `[Humaniser]` lines).
- [ ] With each sub-feature disabled on its own (`Perception`, `AllyLastHit`, `Pings`, `Commands`), only that feature disappears.

## Known risks to watch
- **Laning:** every allied bot on a team with a human uses OHA's laning `Think()` for the whole game, never Valve's (task 04). If laning gets worse, fall back to option B in the 04 handoff.
- **Channel delay:** delaying enemy `IsChanneling` affects every OHA use of it, not just interrupts. `Perception.Channel = false` disables only that part.
- **Commitment:** orders cap retreat while HP is above 50%, so bots may die more on orders. Ordered pushes also skip OHA's "never push alone" checks.
- **Avoidance zones:** they may only affect pathing via `GeneratePath`, not `Action_MoveToLocation`.
- **FretBots bridge option A** (`FretBridge.BridgeModifier`) is untested and off by default. Try it only after the chat mirror proves unreliable.
- **Leftover probe:** remove `SharedStateProbe` once the session 1 result is recorded.
