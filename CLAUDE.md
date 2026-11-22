# Dota 2 Bot Scripts - Claude Code Guide

## Role in the master project (read first)

This repo is the **host and baseline** of the `dota-bots-humaniser` master project, not the product. Rules for every session are in
the master `../../CLAUDE.md` (from a `worktrees/oha-<slice>` worktree also `../../`); open work `docs/team/ROADMAP.md`, the plan
`docs/proposals/2026-11-23-laning-plan-after-the-bisect.md` there.

- **Goal:** as the master `CLAUDE.md` states it: bots that make advantageous decisions, laning first. Our bot script runs on
  our `lua-tasks` engine; OHA and Valve's built-in modes play what we leave them.
- **Stock is the baseline and the default.** The direction is one decider per hero that yields to stock unless it has a
  decision (the plan, section 3). A feature has a kill switch `Ours.<Feature>` whose off arm is stock, and merges switched on
  only when its arm beats the reference arm (the plan, section 5); we never scale OHA's desires. The per-mode code in
  `typescript/bots/FunLib/humaniser/` is as built and is not extended.
- **Change OHA behaviour code only** to fix bugs that block or distort tests, to keep tests valid (telemetry, the
  `Customize/override.lua` loader) or to add a hook. Do not improve OHA behaviour we will replace. The patch-update tasks below
  are maintenance of the host and do not change this.
- **Process:** work in a `worktrees/oha-<slice>` worktree off `team-bots`; load the master skill `bot-structure` before changing bot
  code (who runs a hero in which mode: master `docs/team/WHO-DECIDES.md`). Games run only through dotactl (skill `dotactl`). Merge into `team-bots`
  with `git merge --no-ff`; the merge message is the slice record (master `docs/templates/slice.md`) with a `Check:` or
  `No check: <reason>` line, and a `Review:` verdict when it changes bot runtime code (git hook); then push `team-bots` to
  `origin` (fast-forward only).
- **Engine changes** follow the master skill `engine-change`: the engine is `engine/` in this repo (lua-tasks, built into
  `bots/FunLib/engine`); a merge that changes its source or docs carries an `Engine-review:` verdict (git hook).

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
