--[[
This is a place for you to customize the Open Hyper AI bots.

1. When modiftying this file, be VERY careful to the spelling, punctuation and variable names - it's very easy to cause 
   syntax errors and mess up the entire logic for all bots, and could be hard for you to debug.
2. In the case you saw the bots having some random names or picks (heroes not what you have set or without "OHA" name suffix), 
   that means you had made some mistakes/errors while modifying this file. 
3. In any case this file got messed up and caused the bots to malfunction, you can try to restore the file. Either you have a 
   copy to replace, or resubscribe the script, or download from github.
4. To avoid these customize files from getting overridden by workshop updates, you can copy 
   the entire Customize folder to under: <Steam\steamapps\common\dota 2 beta\game\dota\scripts\vscripts\game>
   and then modify the settings in <Steam\steamapps\common\dota 2 beta\game\dota\scripts\vscripts\game\Customize> directory.
5. Note there is a list of known to-be-improved (aka weak) heroes, check out [Appendix - 2] on the bottom of this file.

- Workshop: https://steamcommunity.com/sharedfiles/filedetails/?id=3246316298
- Github: https://github.com/forest0xia/dota2bot-OpenHyperAI
--]]


-- The variable to hold the settings. Only modify if you know exactly what you are doing.
local Customize = { }

-- Set it to true to turn on ALL of the custom settings in this file, or set it to false to turn off the settings.
Customize.Enable = true

-- Set the localization code to make bots speak the specific language when possible (not guaranteed to 100% localized). 
-- Currently supprot: "en" for "English", "zh" for "中文", "ru" for Russian, "ja" for Japanese
-- https://en.wikipedia.org/wiki/List_of_ISO_639_language_codes
Customize.Localization = "en"

-- To ban some heroes for bots - Set the heroes you DO NOT want the bots to pick. Use hero internal names.
-- Hero name ref: https://github.com/forest0xia/dota2bot-OpenHyperAI/discussions/71
-- Please note that it is not 100% guaranteed that the banned hero will not be picked; for example if you banned too many heroes 
-- like near 100% of the heroes, bots will need to randomly pick heroes regardless of the ban list to continue the game.
Customize.Ban = {
    'example_npc_dota_hero_internal_name_to_ban',
}

--[[
1. To pick heroes for the Radiant bots. You have to use hero's internal name.
2. Hero internal name ref: https://github.com/forest0xia/dota2bot-OpenHyperAI/discussions/71
3. Don't need to provide a value for all 5 bots, any empty/missing value will fallback to a Random value.
4. The position is ranked by the order of the names you put in the below list, pos 1 - 5, from top to down.
5. There are sample team picks in Appendix section below. 
6. Check Appendix to ensure you DO NOT pick more than 1 "weak" heroes in a team for your game experience.
--]]
Customize.Radiant_Heros = {
    'Random',
    'Random',
}

-- Same notes as above for picking heroes but for the Dire side.
Customize.Dire_Heros = {
    'Random',
}

--[[
1. To allow bots to randomly pick heroes that can be the same/repeated. 
2. WARNING: Setting this to true CAN reduce the gaming experience due to the fact some heroes are kind of weak or buggy
   at the moment (listed below) and are intentionally having reduced chances to get picked by bots. Setting this to true
   may cause the bots to pick multiple weak heroes. See Appendix below about "weak" heroes.
--]]
Customize.Allow_Repeated_Heroes = false

-- The max number of weak heroes allowed in a team the bots can pick.
Customize.Weak_Hero_Cap = 1

-- The weak penalty curve for bots picking weak heroes:
--   { type="linear", k=0.25 }         ->  penalty = max(0, 1 - k * (weakPicked/cap))
--   { type="quad",   k=1.0 }          ->  penalty = (1 - min(1, weakPicked/cap))^2
--   { type="exp",    base=0.6 }       ->  penalty = base^(weakPicked)  (more weak -> smaller)
Customize.Weak_Penalty = { type = "exp", base = 0.6 }

-- Exact match on unit names by default; set Customize.Strict_Ban_Match = false to allow guarded substring matches (length ≥ 6).
Customize.Strict_Ban_Match = true

-- To allow bots do trash talking in different scenarios: got fb, killing a human, etc. Disable this also disables GPT chat.
Customize.Allow_Trash_Talk = true

-- To allow bots response with GPT generated text to your chats in global channel. Disable Allow_Trash_Talk can disable this.
Customize.Allow_AI_GPT_Response = true

-- Set the level of bots' trash talks. Disable Allow_Trash_Talk can disable this.
-- 1 => no trash talks from ally bots, no taunt from enemy after it gets a kill. 2 => ally bots also trash talk to you, allow taunt from enemy after it gets a kill.
Customize.Trash_Talk_Level = 1

-- To set the names for the Radiant bots. Don't need to provide a value for all 5 bots, missing names will have a Random value.
Customize.Radiant_Names = {
    'Random',
    'Random',
}

-- Same notes as above for setting the bots' names but for the Dire side.
Customize.Dire_Names = {
    'Random',
}

-- The desire level that the bots will group up and push the same lane. 
-- 1 is mild meaning bots will group up only when convenient; 3 is bots will almost always try to push together.
-- Group pushing may increase the difficulty but can reduce the game experience. 
Customize.Force_Group_Push_Level = 1

-- The Enhanced Fretbots mode settings:
-- For more about Fretbots mode: https://github.com/forest0xia/dota2bot-OpenHyperAI/discussions/68
-- Note: these settings below will override the pre-defind settings in Fretbots folder.
Customize.Fretbots = {
    -- Default difficulty, a number between: [0, 10]
    Default_Difficulty = 2,

    -- Default ally bots bonus scale comparing to enemy bots, a number between: [0, 1]
    Default_Ally_Scale = 0.5,

    -- Set whether or not allowing the team to vote for difficulty. If false, will directly apply the default difficulty.
    Allow_To_Vote = true,

    -- Set to false disables all sounds from Fretbots mode
    Play_Sounds = true,

    -- Set to play chatwheel taunt sounds when human player died
    Player_Death_Sound = true,
}

-- Make bots think less, 0: fully think through, 1 to 10: think less and less frequently.
-- Bots can become slow or dumb in reaction and decision making if you set this value to a higher number.
-- When doing Local Host, you can potentially improve PC performance (FPS) by setting this to 1 to 10, which sacrifices some bot IQ/performance.
-- This won't be very effective for FPS improvement because Valve has a lot of compute on their side that your PC have to handle for Local Hosting.
Customize.ThinkLess = 1;

-- Humaniser: makes bots perceive and react at human speed and behave like teammates.
-- Every sub-feature has its own Enable flag; with Enable = false behaviour matches upstream OHA.
-- Full defaults and tuning curves live in FunLib/humaniser/config.lua; anything set here overrides them.
Customize.Humaniser = {
    Enable = true,
    -- Draws per-bot debug text on screen and enables HDebug.Log output. Requires sv_cheats 1 to see draws.
    Debug = false,
    -- Bot skill in [0, 1] combines Valve lobby difficulty and FretBots difficulty with these weights.
    ValveWeight = 0.5,
    FretWeight = 0.5,
    -- A number in [0, 1] forces every bot's skill. nil = use difficulty. Held at 1 for all work until the Difficulty
    -- roadmap section tunes skill (user 04/11/2026); lobby difficulty and FretBots are ignored while it is set.
    SkillOverride = 1,
    FretBridge = {
        -- Force the FretBots level (0-10) bots assume, if the chat-vote mirror gets it wrong. nil = detect.
        FretBotsLevelOverride = nil,
        -- Experimental: a modifier FretBots stamps with the applied difficulty. nil = off.
        BridgeModifier = nil,
    },
    Perception = { Enable = true },
    AllyLastHit = { Enable = true },
    Pings = { Enable = true },
    Commands = { Enable = true },
    -- Lane management (task 07). Each flag switches one behaviour; Enable = false restores upstream laning.
    Lane = {
        Enable = true,
        -- Who gets OHA's laning Think() for in-lane techniques: 'allies' (allies of humans), 'all' (every bot), 'off'.
        OwnLaningThink = 'allies',
        Plan = true, Block = true, FullPull = true, StackPull = true,
        AggroPull = true, Freeze = true, Shove = true, Stack = true, Harass = true,
        Mid = true, CounterPlay = true, Telegraph = true,
        CampBlock = false, -- stretch: verify in-game that wards still block spawns first
    },
    -- Lane fights (task 11): lane trades and kill setups with imperfect memory of enemy cooldowns.
    -- Enable = false restores the previous behaviour. Every tunable lives in FunLib/humaniser/lane_fight_config.
    -- Needs the Lane feature: with Lane.Enable = false (or every Lane flag off) lane fights are off too.
    LaneFight = {
        Enable = true,
        Memory = true, -- remember which enemy abilities were cast, with skill-dependent accuracy
        Trade = true, -- trade hits when the enemy's cooldowns are down
        Kill = true, -- commit to kill setups
        CallKills = true, -- ping a kill setup for human allies
        Teams = 'all', -- 'all' | 'allies' (bots whose team has a human) | 'enemies'
    },
    -- Lane safety and laning-phase transitions (task 12). Enable = false restores upstream behaviour for all of it.
    Transitions = {
        Enable = true,
        MidRunes = true,  -- the mid laner walks to and takes power runes
        Rotation = true,  -- a spare pos 4/5 rotates to the power rune beside our mid
        Caution = true,   -- an alone core or a lane with a missing enemy plays safer (independent of Teleports)
        Teleports = true, -- bots back off from, or set up on, an enemy TP into their lane (independent of Caution)
        LaneWard = true,  -- the lane support wards the gank path between about 2:30 and 4:30
        Phase = true,     -- per-bot end of laning: cores with a farm item and a safe jungle farm; supports above level 6 leave between 6:00 and 8:00 with a smoke or an attack order
        LostLane = true,  -- a lost lane: the core goes to the jungle, a support roams or suggests it to a human
    },
    -- Intent arbitration (task 09): one priority order for features that change mode desires, a short
    -- stickiness bonus for the active mode, and a stuck-mode detector. Tuning in FunLib/humaniser/intent.lua.
    Intent = { Enable = true },
    -- Last-hit accuracy (task 10): low-skill bots misjudge last hits and try fewer denies. Skill 1.0 is upstream.
    -- Only acts where OHA owns laning Think(); enemy bots need Lane.OwnLaningThink = 'all' for an effect.
    -- RequireOwnedLaning = false also applies it to team roam's last-hit grab for bots on Valve laning.
    LastHitSkill = { Enable = true, RequireOwnedLaning = true },
    -- Core farm pattern: pos 1-3 take a camp between waves (or stack one), back for the next wave; 5:00-20:00.
    -- Tuning in FunLib/humaniser/farm_pattern.lua. Stacks also need Lane.Enable and Lane.Stack.
    FarmPattern = { Enable = true },
    -- Last-hit trainer (task 14): practice feedback for the human. Nothing runs in game until "!trainer on".
    Trainer = {
        LastHit = {
            Enable = true,
            Bar = true,
            OutcomeOnly = false, -- true if the human's swing timing can't be read (spike fallback)
            ScreenText = true, -- false sends verdicts and summaries to team chat instead (spike fallback)
            Denies = true, Chat = 'off', -- 'off' | 'misses' | 'all'
            EasyWindow = 0.3, Checkpoints = { 300, 600 },
            -- Calibration: the lowest-PID bot on each team times its last hits from the trainer's window.
            SelfTest = false,
        },
    },
    -- Machine-readable "[HEV]" event lines (decisions, mode switches, last hits, 1 s snapshots) for
    -- tools/hlog. Launch Dota with -condebug to write them to game/dota/console.log. "!mark <note>" in
    -- chat records a mark and every bot's state at that moment. Never changes bot behaviour.
    -- Also runs with Humaniser.Enable = false (A/B games): snapshots, mode switches and lua_error still
    -- print; humaniser-only events and !mark (no humaniser chat hub) do not.
    Telemetry = {
        Enable = true,
        SnapshotInterval = 1.0,
        MarkAck = true, -- the team's lowest-PID bot replies "mark N saved" in team chat
        -- Run humaniser entry points under xpcall; an error prints "ev=lua_error where=... msg=... tb=..."
        -- (repeats every LuaErrorRepeat s with a count) and the hook falls back to its feature-off value.
        -- Also wraps the OHA entry points (mode, item and ability thinks) under pcall: an error escaping one prints
        -- ev=lua_error where=oha.<file>.<fn> and is raised again unchanged (H.1, slice 1).
        LuaErrors = true,
        LuaErrorRepeat = 10,
    },
    -- tasks: the engine's coroutine task runner (FunLib/engine, built from engine/). Demo gates the GATHER demo task.
    Tasks = { Enable = true, Demo = false },
    -- Behaviour states (humaniser/states, on the engine's States; needs Tasks.Enable). Enable = false restores OHA
    -- exactly. Shadow: choose and log a state for every bot in Teams; Own: state -> positions our body runs
    -- (replaces the default list). Teams: who may own ('allies' = allies of a human, or 'all'); ShadowTeams: who
    -- is shadowed ('allies' or 'all'). A shadowed bot outside Teams only logs its state; nothing it does changes.
    -- Laning: Spot 'oha' (OHA's PositionThink target) or 'sdk' (creep/tower rings, idle steps; slice 3);
    -- LastHit: positions whose last hits and denies the laning body takes over (slice 4).
    States = { Enable = true, Shadow = true, Own = { laning = { 2 }, stack = { 4, 5 }, rotate = { 4 } }, Teams = 'allies', ShadowTeams = 'all',
        Laning = { Spot = 'oha', LastHit = {} },
        -- Rotate.Power: an owned rotate state also walks OHA's power-rune rotations (transitions/rotation decides; slice 9).
        Rotate = { Power = false } },
}

-- Decisions taken over from OHA, one kill switch each (false = OHA's own decision). Defaults: FunLib/humaniser/ours.lua.
-- LeaveCoreCreep (slice 3): pos4/pos5 leave a lane creep an allied core can take.
-- StackExecute (slice 4): the pos5 stacks its nearest camp at minutes 3, 5 and 7 (placeholder trigger).
-- CoreLastHit (slice 5): pos1-3 (both teams) take lane last hits and denies through the laning state's body. On by user
-- decision 02/11/2026 although worse than OHA on the creep-economy bar (ER-008, ER-009, ER-010 FAIL: share flat, more deaths):
-- our code ends up enabled; the row stays open for fixes (set false for OHA's laning).
-- CoreTrade (slice core-in-lane): with CoreLastHit on, the cores' attack mode is ours in lane (trades on enemy heroes) and
-- OHA's Lua port of the attack mode outside lane; false leaves Valve's attack mode.
-- CoreLastHitDire (slice 5 re-run): false keeps the Dire cores on Valve's laning when CoreLastHit is on (Radiant only).
-- SupportDeny (slice l1-support-deny): pos4-5 go for every own creep they can deny, before anything else in lane, whatever the
-- core is doing. SupportDenyDire: false keeps the Dire supports on OHA's deny when SupportDeny is on (Radiant only).
-- SupportLastHit (slice support-lane-hits): with SupportDeny on, the support's body also takes the last hits no allied core will
-- take (its core out of reach, or in an attempt on another creep and unable to swing again in time); false keeps them OHA's.
-- CoreDenyYield (user 06/11/2026): a core leaves a deny an allied support's laning body is in an attempt on and goes for the next
-- last hit or deny; false: a core takes every creep.
-- RuneRotation (slice rune-rotation): pos4 to the 6:00 power rune and its own 7:00 wisdom shrine, pos5 to the 6:00 rune when
-- it has no stack that minute; hosted by the job chooser (needs JobChooser). Off: OHA's rune mode and the rotation nudges.
-- RuneSpawn (slice rune-spawn): the team's 6:00 power rune as one plan (mid and supports) with the plays rolled from it, and the
-- give-up on a 0:00 river bounty that a pickup does not take (rune_pickup). Off: OHA's rune mode and its own pickup guard.
-- SupportPull (slice support-lane): pos4/5 pull our wave into the lane's first pull camp when the lane push reading wants it
-- (hosted by the job chooser, needs JobChooser). Off: the old camp-job pulls (task 07 lane planner).
-- LaneSpot (slice lane-positioning): with CoreLastHit on, pos1-3 stand on our lane spot (states/lane_spot: enemy heroes' reach and creep
-- rings widened below half HP, every enemy tower's range, the XP limit), and with SupportDeny and SupportHarass on pos4-5 too.
-- Off: OHA's PositionTarget (cores) and PositionThink (supports).
-- SupportHarass (slice support-spot): with SupportDeny on, pos4-5 harass enemy heroes in lane through our attack mode (the
-- trade rule with a support's reach, hits that draw no creep aggro) and, with LaneSpot on, stand on our lane spot instead of
-- OHA's PositionThink. Off: Valve's attack mode and OHA's positioning and harass for supports.
-- LaneSpotTower (slice tower-spot): with LaneSpot on, our own towers relax a core's spot limits in their range above 25% HP (enemy
-- creeps attacking something else keep a 200 ring, enemy heroes our tower would punish a short reach). Supports, and off: the
-- open-lane limits everywhere.
-- LaneSpotThreat (slice retreat): with LaneSpot on, the spot's enemy-hero limit is the threat read of the walk to it over 3 s (burst
-- under 0.35 of our HP, missing under 0.5, not `pressured`) instead of the hero reach and the HP margin on it. Off: the old hero limits.
-- CoreLaneFight (slice lane-fight): with CoreLastHit and CoreTrade on, an in-lane pos1-3's fights are ours: it commits on a target at
-- 40% HP or less with even numbers or more (our attack mode), joins an ally's running play near it (hum/plays), and rolls a
-- lane_fight play when no clear window decides; team roam keeps only its non-fight branches for it and LaneFight makes no claim.
-- Off: team roam's fight branches, LaneFight's claims and the trade's 25% kill cut.
-- LaneAggro (slice lane-aggro): an in-lane pos1-3, and a pos4-5 whose lane core is away, draws enemy lane creeps on purpose: `feed`
-- walks the enemy wave onto our ranged creep for our deny (tilting the clash toward our tower), `drag` walks a creep about to die
-- away from an enemy hero for a safe last hit. Off: no draws; OHA-era lane_tech keeps its aggro pull.
-- CoreContest (slice contest-walkin): with CoreLastHit on, a melee pos1-3 walks in from its lane spot (up to 2.5 s) for a last
-- hit on a creep dying inside one enemy hero's reach when the walk-in's HP price passes, and walks back. Off: a 1 s walk at most.
-- CoreHold (slice core-in-lane): with CoreLastHit and LaneSpot on, an in-lane core whose wave is gone holds their incoming wave at
-- the lane's target point (states/wave_hold), or under an enemy hero's threat with time to spare drags it behind our T1 to our
-- next wave (lane_aggro `back`, needs LaneAggro). Off: no hold.
-- SupportPullFarm (slice support-pull-farm): with SupportPull and JobChooser on, the support that pulled clears the neutrals the
-- wave left on the camp when the site is safe, and gives the camp up to a core whose camp trip comes. Off: it walks back to lane.
-- PreDeny (slice idle-swing): an owned laner with no last hit, deny or pre-hit on offer hits our lane creep below half HP that
-- no enemy hero reaches before our hits kill it, both laners on one creep (states/idle_swing). Off: it stands.
-- LaneControl (slice lane-control 2a): the lane controller's per-wave reading, mode, intent and chosen levers, logged as
-- ev=lane_ctl. Off: no reading and no line.
-- LaneControlDrive (slice lane-control 2b): under LaneControl, the decision drives the levers (the idle swing's mode and setup,
-- lane aggro's feed, the support's pull), each keeping its own gates. Off: shadow, each lever on its own trigger.
-- CorePull (slice lane-control 4a): the offlane pos3 pulls its hard camp when the lane controller names it. Off: supports only.
-- ArbiterShadow (slice arbiter-shadow): per owned hero, the arbiter's pick beside Valve's active mode as ev=arb. Logging only.
-- RetreatOdds (slice even-fight, missed): with Retreat on, an even fight with the hitters inside our creep aggro is held, left
-- only on lethal, a tower or the heal floor. Off by default: the hold does not hit back, so it costs deaths (user 11/11/2026:
-- on again after leave-together and hit-back). Off: the budget alone.
-- HitBack (slice hit-back, D24, missed): with CoreTrade on, a laner hit by an enemy hero standing inside our creeps' aggro
-- trades back (past the trade's wave and behind refusals), under a due last hit. Off by default: its lost exchanges reopen
-- and step out instead of swinging (user 13/11/2026). Off: the trade rule alone.
-- HealStop (slice heal-stop, D3): with Retreat on, a heal walk ends where HP is back over half, nobody is in reach and our
-- lane front is nearer than our fountain. Off: on to the fountain and 0.8 HP.
-- HealItems (slice heal-items, D6 stop-gap): with Retreat and HealStop on, a heal start uses the held items that restore HP to
-- half (one tango, a salve, salve and tango; never two tangoes) and waits at our tower. Off: the walk home. Off by default: in
-- games the plan skipped nearly every start (a hero within reach) while holding the items from OHA (slice heal-items, missed).
-- Team (head-to-head scope, unset by default): "radiant" or "dire" (any case, or 2/3) turns every switch above off on the other
-- team, whose contexts then run OHA's path (the Customize.Humaniser features stay on both teams). Set it per run with
-- `--set Ours.Team=radiant`; unset or any other value: both teams.
Customize.Ours = { LeaveCoreCreep = true, StackExecute = true, DoubleStack = true, JobChooser = true, CoreLastHit = true, CoreTrade = true, CoreLastHitDire = true, SupportDeny = true, SupportDenyDire = true, SupportLastHit = true, CoreDenyYield = true, PreHit = true, RuneRotation = true, RuneSpawn = true, SupportPull = true, LaneSpot = true, SupportHarass = true, LaneSpotTower = true, LaneSpotThreat = true, CoreLaneFight = true, LaneAggro = true, CoreContest = true, CoreHold = true, CoreCampTrip = true, SupportPullFarm = true, PreDeny = true, LaneControl = true, LaneControlDrive = true, CorePull = true, Threat = true, Retreat = true, RetreatOdds = false, HitBack = false, HealStop = true, HealItems = false, ArbiterShadow = true, Team = "dire" }

-- Test-harness knobs. ClockOffset (s): added to DotaTime() by the humaniser's game-phase clock (Config.Now) only,
-- so a scenario can make "is it the mid game" logic think it is later; world-timed code (camps, runes) keeps DotaTime().
-- RoleByHero: all-bot teams take positions by hero weight, not slot order (dota_bot_populate lineups; hero_selection.lua).
-- Drill (name, "" = off): a drill from humaniser/drill.ts's table (who plays, who is benched in the fountain, a statue in
-- lane or lane-only, the reps and the forced context; dotactl --drill <name> sets it; drills replaced the old Solo,
-- StackEvery and LaneOnly knobs). StackFar: no 25 s away skip (slice double-stack: execution apart from getting there;
-- scenario and drill games only; drill stack implies it). CampForce: an owned core's
-- camp trip starts whenever an open camp is in reach, without the decision's gates (slice core-next-gold, harness games only;
-- "" off, so drill core-camp can imply it: an explicit false here would win over the drill).
-- AdmitLog: the trip's price check at the camp logs its verdict (`phase=admit`) and refuses nobody (drills only; baked into a
-- remote drill arm).
-- ForceShove: lanes whose owned laners shove (idle swing on enemy creeps outside their tower) instead of pre-denying, as
-- comma-separated `bot`, `r:bot`, `d:top`, `all` (r Radiant, d Dire, no prefix both); "" off (slice idle-swing, harness only).
-- ForceLever: `<lanes>=<lever>` (lanes as ForceShove, lever `feed`, `setup` or `none`): the lane controller's lever set in those
-- lanes is that lever alone (or empty) every wave, whatever the need; "" off (drills only).
Customize.Overrides = { ClockOffset = 0, RoleByHero = true, Drill = "", CampForce = "", AdmitLog = "", ForceShove = "", ForceLever = "" }

-- Per-turn overrides written by dotactl (--set / --scenario): Customize/override.lua returns
-- { ["Humaniser.States.Enable"] = false, ... }. Loaded last so it wins; a missing file is the normal case.
-- Numeric parts index arrays, so "Radiant_Heros.1" sets Customize.Radiant_Heros[1] (lineup lock).
do
    local path = GetScriptDirectory() == 'bots' and 'bots.Customize.override' or GetScriptDirectory()..'/Customize/override'
    local ok, overrides = pcall(require, path)
    if ok and type(overrides) == 'table' then
        for key, value in pairs(overrides) do
            local node, rest = Customize, tostring(key)
            for part in rest:gmatch('([^.]+)%.') do
                part = tonumber(part) or part
                if type(node[part]) ~= 'table' then node[part] = {} end
                node = node[part]
            end
            local last = rest:match('([^.]+)$')
            node[tonumber(last) or last] = value
            print('[Customize] override '..rest..' = '..tostring(value))
        end
    end
end

return Customize




--[[

----------------------------------------------------------------------------------------------------
|                                        --- Appendix ---                                          |
----------------------------------------------------------------------------------------------------

[Appendix - 1] -- Some sample team picks: --

    -- -- All Pudges
    -- "npc_dota_hero_pudge",
    -- "npc_dota_hero_pudge",
    -- "npc_dota_hero_pudge",
    -- "npc_dota_hero_pudge",
    -- "npc_dota_hero_pudge",

    -- -- All Spirits/Pandas
    -- "npc_dota_hero_void_spirit",
    -- "npc_dota_hero_storm_spirit",
    -- "npc_dota_hero_ember_spirit",
    -- "npc_dota_hero_brewmaster",
    -- "npc_dota_hero_earth_spirit",

    -- -- Traditional -- --
    -- "npc_dota_hero_chaos_knight",
    -- "npc_dota_hero_sniper",
    -- "npc_dota_hero_axe",
    -- "npc_dota_hero_zuus",
    -- "npc_dota_hero_warlock",

    -- -- Rubick mid, and good team fights -- --
    -- "npc_dota_hero_clinkz",
    -- "npc_dota_hero_rubick",
    -- "npc_dota_hero_enigma",
    -- "npc_dota_hero_earth_spirit",
    -- "npc_dota_hero_techies",

    -- -- Invoker mid, and good team fights -- --
    -- "npc_dota_hero_arc_warden",
    -- 'npc_dota_hero_invoker',
    -- "npc_dota_hero_enigma",
    -- "npc_dota_hero_nyx_assassin",
    -- "npc_dota_hero_zuus",


[Appendix - 2] -- List of to-be-improved (aka weak) heroes, as of 2024/10/20 --

    They are relatively weaker than others and can still get selected by bots, 
    but there SHOULD NOT have more than 1 of those in a team to ensure the bar of gaming experience for human players.

    Those are weak due to:
        1, Some have bugs from Valve side, which I've spent a lot of effrot with to improve and fix things. 
        2, It's not easy to implement the hero in a good way in terms of doing it via coding with the code base we have.
        3, I do not play some of those heroes a lot myself so can't make good bots, 

    It's a matter of time to get everything improved, but I don't have a lot of time to do everything to make bots better. 
    So I put them here, and hopefully make it easy for you to use, or learn, or improve the script. 
    I'd appreciate any actual help from you to make the bots better, and I'm certain we can achieve it by contributing together.

    -- -- List A. Weak ones, meaning they are too far from being able to apply their power:
        'npc_dota_hero_chen',
        'npc_dota_hero_keeper_of_the_light',
        'npc_dota_hero_winter_wyvern',
        'npc_dota_hero_ancient_apparition',
        'npc_dota_hero_phoenix',
        'npc_dota_hero_tinker',
        'npc_dota_hero_pangolier',
        'npc_dota_hero_tusk',
        'npc_dota_hero_morphling',
        'npc_dota_hero_visage',
        'npc_dota_hero_void_spirit',
        'npc_dota_hero_pudge',
        'npc_dota_hero_ember_spirit',

    -- -- List B. Buggy ones, meaning they have bugs on Valves side:
        'npc_dota_hero_muerta',
        'npc_dota_hero_marci',
        'npc_dota_hero_lone_druid',
        'npc_dota_hero_primal_beast',
        'npc_dota_hero_dark_willow',
        'npc_dota_hero_elder_titan',
        'npc_dota_hero_hoodwink',
        'npc_dota_hero_wisp',
]]--
