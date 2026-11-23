-- Drill entries deleted with the lane body (23/11/2026, bot repo tag pre-lane-body-cut), kept here only as fixtures for the
-- drill harness code they exercise (statue, sentry, spot lists, actors, ready checks), which stays in drill.ts for the
-- features that come back. test_drill injects one into Drill.TABLE when it names it. Copied from the compiled table as it was.
local SAFE_CORE = {r = {1}}
return {
    ["lane-spot"] = {
        note = "Radiant pos1 lane-only, everyone else benched",
        cast = SAFE_CORE,
        others = "bench",
        castLaneOnly = true,
        rep = {every = 30, from = 0}
    },
    ["lane-spot-statue"] = {
        note = "Radiant pos1 lane-only, Dire pos3 a statue in its lane, everyone else benched",
        cast = SAFE_CORE,
        statue = {d = {3}},
        others = "bench",
        castLaneOnly = true,
        rep = {every = 30, from = 0}
    },
    ["lane-spot-sentry"] = {
        note = "Radiant pos1 lane-only, Dire pos3 a sentry in its lane (a statue that attacks an enemy hero inside its zone), everyone else benched",
        cast = SAFE_CORE,
        sentry = {d = {3}},
        others = "bench",
        castLaneOnly = true,
        rep = {every = 30, from = 0}
    },
    ["tower-prehit"] = {
        note = "rig: Radiant pos1, pos2 and pos3 each at the front of a small Dire wave made under its own T1 each rep (both sides' creeps there cleared first), only the tower on it, level 3; ready: the tower hitting an enemy creep within 700, no enemy hero within 2,000; then laning; 30 s reps from 0:30; seed 30",
        cast = {r = {1, 2, 3}},
        others = "bench",
        rep = {every = 30, from = 30},
        rig = {
            half = "execution",
            switch = "PreHit",
            window = 600,
            spots = {bot = {"r:bot1", 200, 0}, mid = {"r:mid1", 140, 140}, top = {"r:top1", 0, 200}},
            timeout = 28,
            keeps = {"levelup"},
            release = {modes = {"laning", "idle"}},
            idle = 0.3,
            reps = {{name = "tower", setup = {r1 = {"stand bot"}, r2 = {"stand mid"}, r3 = {"stand top"}}, ready = {towerCreep = 700, clear = 2000}}}
        }
    },
    ["retreat-hitback"] = {
        note = "rig: Radiant pos1 off our bot lane, hit by the Dire pos4 from 200 past its reach at 90%+ HP (far), by the Dire pos3 in reach at 72% (behind), as far with no creep aggro (free), the pos4 beside it not attacking (stand); then laning, attack, retreat; five 120 s reps from 0:00; seed 8",
        cast = SAFE_CORE,
        others = "bench",
        rep = {every = 120, from = 0},
        rig = {
            half = "decision",
            switch = "Trade",
            window = 600,
            spots = {side = {"r:bot1", -2750, 700}, sidenear = {"r:bot1", -2250, 700}, beside = {"r:bot1", -2600, 700}},
            timeout = 100,
            keeps = {"levelup"},
            release = {modes = {"laning", "attack", "retreat", "idle"}},
            reps = {{name = "far", aggro = true, setup = {r1 = {"heal", "stand side"}, d4 = {"heal", "attack r1 from 500 until hp 0.6", "leave"}}, ready = {hit = true, past = {100, 300}, hpAtLeast = 0.9}}, {name = "behind", aggro = true, setup = {r1 = {"heal", "stand side until hp 0.72", "stand side"}, d3 = {
                "heal",
                "walk sidenear",
                "attack r1 until hp 0.72",
                "attack r1 until hp 0.55",
                "leave"
            }}, ready = {hit = true, behind = 0.16, hpAtLeast = 0.55}}, {name = "free", aggro = false, setup = {r1 = {"heal", "stand side"}, d4 = {"heal", "attack r1 from 500 until hp 0.6", "leave"}}, ready = {hit = true, past = {100, 300}, hpAtLeast = 0.9}}, {name = "stand", aggro = true, setup = {r1 = {"heal", "stand side"}, d4 = {"heal", "stand beside"}}, ready = {near = 800}}}
        }
    },
    ["kill-reach"] = {
        note = "rig: Radiant pos1 off our bot lane, the Dire pos4 a statue 600 west of it on the same strip hit to 25% HP by the Radiant pos5, which then walks 1,400 west; control: the Dire pos3 also stands 950 west, beyond the Lich (two against one; the head count is gone, so the walk's burst decides); then laning, attack, retreat; five 120 s reps from 0:00; seed 8",
        cast = SAFE_CORE,
        others = "bench",
        rep = {every = 120, from = 0},
        rig = {
            half = "execution",
            switch = "Trade",
            window = 600,
            spots = {side = {"r:bot1", -2750, 700}, low = {"r:bot1", -3350, 700}, foe = {"r:bot1", -3700, 700}, away = {"r:bot1", -4150, 700}},
            timeout = 95,
            keeps = {"levelup"},
            release = {modes = {"laning", "attack", "retreat", "idle"}},
            reps = {{name = "reach", setup = {r1 = {"heal", "stand side"}, r5 = {"heal", "attack d4 until hp 0.25", "leave away"}, d4 = {"stand low"}}, ready = {low = {0.35, 100, 550}, foesAtMost = 1, alliesAtMost = 0, hpAtLeast = 0.5}}, {name = "reach", setup = {r1 = {"heal", "stand side"}, r5 = {"heal", "attack d4 until hp 0.25", "leave away"}, d4 = {"stand low"}}, ready = {low = {0.35, 100, 550}, foesAtMost = 1, alliesAtMost = 0, hpAtLeast = 0.5}}, {name = "outnum", setup = {r1 = {"heal", "stand side"}, r5 = {"heal", "attack d4 until hp 0.25", "leave away"}, d4 = {"stand low"}, d3 = {"heal", "stand foe"}}, ready = {low = {0.35, 100, 550}, foes = 2, alliesAtMost = 0, hpAtLeast = 0.5}}}
        }
    },
    ["lane-trade"] = {
        note = "rig: Radiant pos2 mid against the Dire pos2, Radiant pos1 in our safe lane against the Dire pos3, waves untouched, everyone else benched; the enemy hero holds its last-hit place (stand), walks up to our dying creeps and back (lasthit), or as lasthit and hits back (hitback); full HP each rep; then laning, attack, retreat with OHA's casts; 30 s reps from 1:00; seeds 30 (Sniper) and 8 (Sven)",
        cast = {r = {1, 2}},
        others = "bench",
        rep = {every = 30, from = 60},
        rig = {
            half = "execution",
            switch = "TradeNoStep",
            window = 600,
            spots = {},
            timeout = 15,
            keeps = {"levelup"},
            watch = true,
            release = {modes = {"laning", "attack", "retreat", "idle"}, abilities = true},
            reps = {{name = "stand", setup = {r1 = {"front"}, r2 = {"front"}, d2 = {"front"}, d3 = {"front"}}, ready = {near = 1500, foesAtMost = 1, alliesAtMost = 0, hpAtLeast = 0.9}}, {name = "lasthit", setup = {r1 = {"front"}, r2 = {"front"}, d2 = {"lasthit"}, d3 = {"lasthit"}}, ready = {near = 1500, foesAtMost = 1, alliesAtMost = 0, hpAtLeast = 0.9}}, {name = "hitback", setup = {r1 = {"front"}, r2 = {"front"}, d2 = {"hitback"}, d3 = {"hitback"}}, ready = {near = 1500, foesAtMost = 1, alliesAtMost = 0, hpAtLeast = 0.9}}}
        }
    },
    ["threat-missing"] = {
        note = "Radiant pos3 lane-only in its lane; Dire pos5 a statue at a spot per rep (by the pos3's pull camp, bench, Dire offlane camp, its lane); everyone else benched",
        cast = {r = {3}},
        statue = {d = {5}},
        spots = {d = {[5] = {"pull:r:off", "bench", "pull:d:off", "lane"}}},
        others = "bench",
        castLaneOnly = true,
        rep = {every = 90, from = 30}
    },
}
