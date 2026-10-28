# Dota 2 Bot Scripts - Claude Code Guide

## Role in the master project (read first)

This repo is the **host and baseline** of the `dota-bots-humaniser` master project, not the product. Rules for every session are in
the master `../../CLAUDE.md` (from a `worktrees/oha-<slice>` worktree also `../../`); roadmap `docs/team/PLAN.md`, goals
`docs/team/GOALS.md`, status `docs/team/BACKLOG.md` there.

- **Goal:** dynamic bot games with high-MMR/pro elements (map movement, encounters judged sensibly, support jobs, rotations,
  objective follow-ups, awareness of the human teammate). Mechanical is fine; human imitation is not the aim. End state: our own bot script on the `lua-tasks`
  SDK with **no OHA code left**.
- **Until then** OHA plays every behaviour we have not replaced, and is the baseline: each replacement sits behind a kill switch whose
  OFF arm is OHA. Our code lives in `typescript/bots/FunLib/humaniser/`.
- **Change OHA behaviour code only** to fix bugs that block or distort tests, to keep tests valid (telemetry, the
  `Customize/override.lua` loader) or to add a hook. Do not improve OHA behaviour we will replace. The patch-update tasks below
  are maintenance of the host and do not change this.
- **Process:** work in a `worktrees/oha-<slice>` worktree off `team-bots`; load skill `behaviour-areas` before changing behaviour (hook
  points: master `docs/team/OWNERSHIP.md`, one combiner per hook point). Games run only through dotactl (skill `dotactl`). A
  slice is done only with a reviewed Eval Report; verdict words are PASS, PROVISIONAL, FAIL, UNTESTED. Merge into `team-bots` with
  `git merge --no-ff`, citing the review report and an `ER-nnn` id or a `No ER: <reason>` line (git hook), then push `team-bots` to
  `origin` (fast-forward only).
- **Jitter** goes through the SDK `Skill` model, never host-side randomness. SDK paths (`repos/dota-bot-sdk/packages/lua-tasks/**`, `docs/SDK_API.md`, `docs/contracts/**`) are
  edited only from an `sdk-*` worktree; the vendored copy under `bots/FunLib/sdk/tasks` is updated by a separate re-vendor step (E0/E1 and a health run), not as part of a behaviour change.

## Project Overview

This is the **dota2bot-OpenHyperAI** project -- Lua bot scripts for Dota 2 that run in custom lobbies. Currently supports Patch 7.41 through 7.41f with 127 heroes.

## Key Documentation

- **[docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)** -- Complete codebase architecture, file map, naming conventions, all systems explained
- **[docs/PATCH_UPDATE_GUIDE.md](docs/PATCH_UPDATE_GUIDE.md)** -- Step-by-step runbook for updating when a new Dota 2 patch drops

**Read these docs FIRST before making any changes.** They contain everything needed to make targeted updates without scanning the entire repo.

## Common Tasks

### Check for New Patches

To check if there are patches we haven't updated for:
1. Fetch `https://www.dota2.com/datafeed/patchnoteslist?language=english`
2. Compare latest version against "Last updated for" in `docs/PATCH_UPDATE_GUIDE.md`
3. If newer patch exists, follow the update process below

### Patch Update (most common)

When user says "update for patch X.XX" or provides patch notes:

1. Read `docs/PATCH_UPDATE_GUIDE.md` for the step-by-step process
2. Fetch patch data: `https://www.dota2.com/datafeed/patchnotes?version=X.XX&language=english`
3. Fetch d2vpkr data (shops.txt, neutral_items.txt) for authoritative item/ability names
4. **Categorize changes**: STRUCTURAL (need code) vs NUMBER-ONLY (game API handles) vs TALENT SWAPS
5. **Always verify ability names on Liquipedia** -- patch note summaries can be wrong
6. Follow the checklist in order: items -> hero builds -> abilities -> neutrals -> actives -> map changes
7. **Always update TS sources** for any TS-generated Lua files changed (see ARCHITECTURE.md Section 13)

### Add a New Hero

1. Copy a similar existing hero from `bots/BotLib/` as template
2. Add to `FretBots/HeroNames.lua`, `FunLib/aba_hero_roles_map.lua`, `FunLib/spell_list.lua`
3. See "New Heroes" section in `docs/PATCH_UPDATE_GUIDE.md`

### Fix a Hero's Item Build

1. Read `bots/BotLib/hero_[name].lua`
2. Edit the `sRoleItemsBuyList['pos_N']` arrays
3. Items use `item_[internal_name]` format -- check `FunLib/aba_item.lua` for valid names

### Fix a Hero's Ability Logic

1. Read `bots/BotLib/hero_[name].lua`
2. The `SkillsComplement()` function controls ability casting priority
3. Each ability has a `ConsiderX()` function returning desire + target
4. See "Skill / Ability System" in `docs/ARCHITECTURE.md`

## Important Rules

- **Use `GetItemComponents()` for item recipes** -- don't hardcode component arrays
- **Use `sAbilityList[N]` references** when possible -- resilient to ability renames
- **Always update BOTH neutral item files** (Buff/ AND FretBots/)
- **Verify on Liquipedia** before trusting patch note summaries about ability names
- **Test in-game** after changes -- some things can only be verified at runtime
