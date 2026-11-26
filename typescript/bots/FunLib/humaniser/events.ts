/**
 * One declaration per humaniser ev= name: field -> value type. Data only (no imports, erasable syntax), so the compiler
 * types Telemetry.Event from it and tools/hlog/gen_events.js reads it with Node to write EVENTS.md and the store's column kinds.
 * Types: num (number), str (string), numstr (a string that holds a number, for example fmt() output), bool (printed 1/0),
 * mixed (number or string, for example a ? placeholder). Only str forces a text column in the store.
 * Every field may also be undefined or null (the formatter skips it). Add the event here before emitting it.
 * Out of scope: engine ev=state* events and the dynamically named events (farm_pattern trips, the engine adapter in tasks.ts).
 */

export const UNIT = {
    x: "num",
    y: "num",
    alive: "bool",
    hp: "num",
    mp: "num",
    /** Max HP and max mana, absolute (`hp`, `mp` are percentages of them). */
    hpm: "num",
    mpm: "num",
    lvl: "num",
    /** The hero's last-hit count (`GetLastHits`). */
    lh: "num",
    /** The hero's deny count (`GetDenies`). */
    dn: "num",
    kills: "num",
    deaths: "num",
    /** Unit name of the attack target. */
    tgt: "str",
    /** The attack target as `h<pid>` (hero) or `u<n>` (any other unit, the creep id of `ev=creep_death` `cid`). */
    tid: "str",
    /** Nearest lane: `top`, `mid` or `bot` (absent in older logs). */
    ln: "str",
    /** The hero's amount along that lane, 0 at Radiant's ancient to 1 at Dire's, on the writing team's lane path (compare within one team's lines only). */
    s: "num",
    /** The hero's distance from that lane's path. */
    ld: "num",
} as const;

export const BOT = {
    ...UNIT,
    /** Name of the mode holding the hero. */
    mode: "str",
    /** The active mode's desire. */
    d: "num",
    /** `GetCurrentActionType`: 0 none, 1 idle, 2 move to, 3 move directly, 4 attack, 5 attack-move, 6 use ability, 7 pick up rune, 8 pick up item, 9 drop item, 10 shrine, 11 delay. */
    act: "num",
    gold: "num",
    /** Net worth (`GetNetWorth`: gold plus items), for the head-to-head farm readout without replays (`@h2h_farm`). */
    nw: "num",
    /** `GetXPNeededToLevel`: with `lvl` and the patch's level table, the hero's experience (the merge gate's third measure
     *  without replays); -1 for non-heroes (API reference); its value at the level cap is unconfirmed. */
    xpn: "num",
    /** Laning body's last-hit scan (states/lane_pick Describe): phase, scan and pick ages, distance to the spot, offers. */
    lf: "str",
    /** What the bot could do this second, up to 12:00, both arms (slice lane-activity): reachable last hits and denies offered. */
    ol: "num",
    od: "num",
    /** Attack range, nearest visible enemy hero within 1,200 (absent if none). */
    ar: "num",
    ed: "num",
    /**
     * Damage sources, all game (view `hp_loss`): raw HP; damaged in the last second by a hero, a creep, a tower (the API's
     * flags); enemy heroes, enemy lane creeps, neutrals and enemy towers within 1,600 whose attack target is this bot.
     */
    hv: "num",
    hit: "bool",
    hc: "bool",
    ht: "bool",
    ah: "num",
    ac: "num",
    an: "num",
    at: "num",
    /**
     * Where the hero stands against the lane creeps, to 12:00 (slice snap-creeps): enemy lane creeps within 500 (protective
     * aggro: an attack on an enemy hero draws its creeps within 500 of the attacker) and within attack range + 48 (centre to
     * centre), own lane creeps within 500, and the distance to the nearest enemy and own lane creep within 1,600 (absent if none).
     */
    ce: "num",
    cr: "num",
    co: "num",
    ced: "num",
    cod: "num",
    /**
     * Which step of mode_laning_generic's Think acted most recently since the previous snapshot (slice step-telemetry): `body_hit`
     * the laning body's running last-hit or deny swing, `support_hit` / `support_aggro` / `support_hold` a support's lane rows (states/lane_table), `drill_hold` / `drill_aggro`
     * a lane-only core's wave hold and lane aggro, `aggro` a core's lane aggro or the wave hold, `etiquette` Ours.LeaveCoreCreep's cancel (with OHA's move), `oha_lh` / `oha_deny` / `oha_hold` OHA's
     * last hit, deny and hold-for-the-hit, `body` the
     * laning body's step, `oha_pos` OHA's PositionThink; `none` when the Lua Think did not run since the previous snapshot,
     * `valve` for a bot whose laning is Valve's C++ one (no Lua Think). Bots only.
     */
    step: "str",
    /** Who holds the hero, as `<mode> <desire> by <source>`; the source is empty where the mode is one of Valve's built-ins. Read by `lane_activity` and `@mode_hold`. */
    by: "str",
    order: "str",
    /** Slice cast-read: the spells the hero can cast this second (learned, shown, not passive, IsFullyCastable) as
     *  `;`-joined `name:class`: `u` ultimate, `k` hard disable or spell immunity (ability_classes), `d` damage, `o` other. */
    rdy: "str",
} as const;

export const EVENTS = {
    /** A Lua error caught by a Guard, or one escaping an OHA entry point (`where=oha.<file>.<fn>`, `Telemetry.Entry`, which re-raises it unchanged). Repeats update `n`. */
    lua_error: {
        pid: "mixed",
        /** The guard site, or `oha.<file>.<fn>` for an error escaping an OHA entry point (mode `GetDesire`/`Think`/`OnStart`/`OnEnd`, item and ability thinks). */
        where: "str",
        /** Count so far; `check` counts the highest `n` once per where and msg, not the sum of the lines. */
        n: "num",
        /** The error message; `"` is written as `'`, so free text is lossy. */
        msg: "str",
        tb: "str",
    },
    /** Once a second per team: the team's wave front in each lane, from `GetLaneFrontLocation`. Read by `@front_at`. */
    front: {
        /** The writing team. Amounts follow its lane path, so the two teams' amounts for one place differ; compare within one team's lines, or across teams by map position. */
        team: "num",
        /** Top lane front, as an amount along the lane: 0 at Radiant's ancient to 1 at Dire's. */
        top: "num",
        /** Top front, map x. */
        topx: "num",
        /** Top front, map y. */
        topy: "num",
        /** Mid lane front amount (as `top`). */
        mid: "num",
        /** Mid front, map x. */
        midx: "num",
        /** Mid front, map y. */
        midy: "num",
        /** Bot lane front amount (as `top`). */
        bot: "num",
        /** Bot front, map x. */
        botx: "num",
        /** Bot front, map y. */
        boty: "num",
    },
    /** One line per bot at start and again when its profile or position changes. The only event that carries `schema`, `build` and `ours`. */
    bot: {
        pid: "num",
        hero: "str",
        team: "num",
        /** Log format version. */
        schema: "num",
        humaniser: "bool",
        skill: "num",
        ally: "bool",
        /** The bot build as `<sha>[+dirty]`; always a string, even when all digits. */
        build: "str",
        /** The lineup position, 1-5. */
        pos: "num",
        /** Every `Ours` switch in name order as `Switch:1|0,...`. Views call a hero ours when a switch is on, else OHA (`@rule_counts`). */
        ours: "str",
        notice: "num",
        react: "num",
        ping: "num",
        chat: "num",
        jitter: "num",
        lapse: "num",
        lapseMax: "num",
        minReact: "num",
        deference: "num",
    },
    /** A hero's last hit. The older `ally_creep_steals` metric reads it. */
    lasthit: {
        pid: "num",
        human: "bool",
        n: "num",
        creep: "str",
        dec: "str",
        decAge: "num",
    },
    deny: {
        pid: "num",
        human: "bool",
        n: "num",
    },
    /** A hero's change of mode. View `mode_time` sums the seconds per hero per mode. */
    mode: {
        pid: "num",
        from: "str",
        to: "str",
        d: "num",
        dwell: "num",
        by: "str",
    },
    /** Slice arbiter-shadow: the arbiter's pick for an owned hero beside the mode Valve holds it in, on a change of either. `grp` the doctrine group 1-6, or `base` (the lane) or `oha`; `agree` 1 when `act` is the pick's host or the pick is `oha`; `dwell` seconds the previous pick and mode pair lasted. */
    arb: {
        pid: "num",
        pick: "str",
        grp: "mixed",
        host: "str",
        act: "str",
        agree: "num",
        job: "str",
        lever: "str",
        prev: "str",
        dwell: "num",
        /** The laning hold (Phase.LaningHeld): `own` at the hero's first laning read, `end` when it hands the hero to OHA (`why`: `clock` or `tower`; `lost` only before 19/11/2026). */
        ph: "str",
        why: "str",
    },
    /** Team-wide: written once per module instance, de-duplicated by `parse.js` within 1 s. */
    mark: {
        n: "num",
        by: "num",
        team: "num",
        text: "str",
        at: "num",
    },
    mark_state: {
        n: "num",
        pid: "num",
        hero: "str",
        competing: "str",
        ...BOT,
    },
    /** A rune at a spawn spot vanished with an own hero within 400 and no visible enemy hero nearer. A power spot's rune that vanishes within 0.15 s of a 2-minute spawn tick is a despawn and is not logged. Not tracked before 0:01. */
    rune_pickup: {
        /** The hero credited: the own hero within 400 (an invisible enemy's pickup is credited to it too). */
        pid: "num",
        team: "num",
        rune: "num",
        /** `water` (a power spot before 6:00, judged by pickup time), `power` or `bounty`. */
        kind: "str",
        x: "num",
        y: "num",
    },
    /** A new observer or sentry ward appeared in the allied ward list. Hero summons are skipped. */
    ward_place: {
        /** The nearest own hero within 800; omitted when none. */
        pid: "num",
        team: "num",
        /** `obs` (observer) or `sentry`. */
        kind: "str",
        x: "num",
        y: "num",
    },
    /** An own tower or barracks known alive became dead or missing (checked at 1 Hz). */
    building_fall: {
        team: "num",
        /** `tower` or `rax` (barracks). */
        kind: "str",
        id: "num",
        /** Tower tier 1-3; 4 is the base. */
        tier: "num",
    },
    /** `GetRoshanKillTime()` increased (checked at 1 Hz). Both teams log it; de-duplicate on `at`. */
    roshan_kill: {
        team: "num",
        /** The kill time `GetRoshanKillTime()` returned. */
        at: "num",
    },
    /** The `modifier_smoke_of_deceit` appeared on the hero. */
    smoke_use: {
        pid: "num",
        team: "num",
        x: "num",
        y: "num",
    },
    /** A hero's teleport ended (`modifier_teleporting` gone); the landing is read 0.1 s later. */
    tp: {
        pid: "num",
        team: "num",
        fx: "num",
        fy: "num",
        /** Landing x, read 0.1 s after the teleport ended. */
        x: "num",
        /** Landing y, read 0.1 s after the teleport ended. */
        y: "num",
        dur: "num",
        /** Distance from `fx` `fy` to the landing; under 1,000 means the teleport was cancelled. */
        dist: "num",
    },
    /** The hero started holding `item_aegis` (checked at 1 Hz). */
    aegis: {
        pid: "num",
        team: "num",
    },
    /** A creep logged dead was seen alive again: it had left vision at half HP or less. */
    creep_revive: {
        team: "num",
        /** `melee`, `ranged`, `siege`, `neutral` or `ancient`. */
        kind: "str",
        hp: "num",
        /** The creep's id for this log (Telemetry CreepId), as on its `ev=creep_death` row; absent on logs before 25/11/2026. */
        cid: "num",
    },
    /** The first frame a lane creep of the logging team, or any neutral, is in the team's unit list (`Telemetry.Creeps`, 0:00 to `Telemetry.CreepDeathUntil`, both arms). Each team numbers its own creeps (`cid` is unique per team only), so a lane creep is `team` + `cid`; a neutral both teams see is two rows, merged by the reader (hlog `unit_life`). Pair: `unit_gone`. */
    unit_seen: {
        /** The logging team: the owner of a lane creep; for a neutral, the team that saw it. */
        team: "num",
        cid: "num",
        /** `lane` or `neutral`. */
        kind: "str",
        /** The unit's name without `npc_dota_`: shows a flag bearer, an upgraded melee creep, a neutral's name. */
        type: "str",
        /** A lane creep's lane nearest where it was first seen (`top`, `mid`, `bot`). */
        lane: "str",
        /** A neutral's nearest camp spawner index within 1,200; absent when none. */
        camp: "num",
        x: "num",
        y: "num",
    },
    /** The frame a unit with a `unit_seen` left the unit list dead. A lane creep: any frame it leaves the owner's list, at any health and place (a team sees its own creeps everywhere; at high `hp` it can be a change of owner). A neutral: only when `IsAlive()` is false or its handle is invalid; one that leaves the list alive (out of vision) is held, written `hid=1` if it is later found dead, and never when it is seen again. */
    unit_gone: {
        team: "num",
        cid: "num",
        /** Where it was last listed. */
        x: "num",
        y: "num",
        /** HP share when last listed. */
        hp: "num",
        /** The pid of an own hero whose denies (own lane creep) or last hits (neutral) rose this frame and took the nearest unclaimed gone unit within 1,200, else `none`. An enemy hero's last hit of an own creep is never here: the logging team reads an enemy hero's `GetLastHits` and `GetDenies` as -1, and its towers' targets as nothing, so the other team's `creep_death` is still the only source (hlog `unit_life` pairs it). */
        by: "mixed",
        /** 1 when the neutral was found dead only after it had left the list alive, so `t` is when that was noticed. */
        hid: "bool",
    },
    /** An ENEMY lane creep (as seen by the logging team) that was seen last frame and is gone this frame at 50% health or less, within 1,500 of a living own hero. Logged per team by a frame job (`Telemetry.Creeps`, 0:00 to `Telemetry.CreepDeathUntil`, 720 s), in both arms. */
    creep_death: {
        /** The logging team: the team whose module saw the death. A row is an enemy lane creep seen by that team, so the same creep is also, for its owner, a `unit_gone`. */
        team: "num",
        /** `melee`, `ranged` or `siege`. */
        kind: "str",
        /** The creep's x as last frame read it (a dead creep's handle is never called). */
        x: "num",
        /** The creep's y as last frame read it. */
        y: "num",
        /** The creep's HP as last frame read it. */
        hp: "num",
        /** Who got it: the pid of an own hero whose last hits rose this frame (each rise takes its nearest unclaimed death within 1,200), `deny` for a visible enemy hero whose denies rose, else `none`. `deny` has never been seen; view `creep_fate` names enemy denies from the other team's log. */
        by: "mixed",
        /** 1 when one of the logging team's towers was attacking the creep on the frame before it died. */
        tw: "bool",
        /** The killer's mode name when its last tracked attack on this creep started. Absent when that attack was not tracked (at 8x about a third of right-clicks). */
        bm: "str",
        /** Seconds from that attack's start to the death; absent with `bm`. */
        bs: "num",
        /** Own core at OHA position 1: its distance to the creep. Cores are logged only within 1,500. */
        p1d: "num",
        /** Position 1 core's attack range. */
        p1r: "num",
        /** 1 if the position 1 core was attacking this creep last frame. */
        p1t: "bool",
        /** Seconds since the position 1 core's last attack started, if that attack was on this creep (`GameTime` clock, as `GetLastAttackTime`). */
        p1a: "num",
        /** Own core at OHA position 2: its distance to the creep (within 1,500 only). */
        p2d: "num",
        /** Position 2 core's attack range. */
        p2r: "num",
        /** 1 if the position 2 core was attacking this creep last frame. */
        p2t: "bool",
        /** Seconds since the position 2 core's last attack started, if on this creep. */
        p2a: "num",
        /** Own core at OHA position 3: its distance to the creep (within 1,500 only). */
        p3d: "num",
        /** Position 3 core's attack range. */
        p3r: "num",
        /** 1 if the position 3 core was attacking this creep last frame. */
        p3t: "bool",
        /** Seconds since the position 3 core's last attack started, if on this creep. */
        p3a: "num",
        /** The creep's id for this log (Telemetry CreepId; joins an ev=idle_swing). */
        cid: "num",
    },
    /** The human player's state, printed every frame (noisy). Bots log `snap` instead. */
    player: {
        pid: "num",
        hero: "str",
        team: "num",
        human: "bool",
    },
    /** A hero's snapshot, about once a second, for bots and humans. Read by `hero_minute`, `lane_activity`, `hp_loss` and most views. */
    snap: {
        pid: "num",
        human: "bool",
        ...BOT,
    },
    /** Item layout when it changes (checked at the snapshot cadence) and at the first snapshot: `s<slot>=<name>[:<charges>]`, empty slots omitted; slots 0-5 main, 6-8 backpack, 9-14 stash, 15 TP, 16 neutral. */
    inv: {
        pid: "num",
        items: "str",
    },
    game_end: {
        pid: "num",
        radiantAncient: "bool",
        direAncient: "bool",
    },
    intent_cadence: {
        pid: "num",
        rf: "str",
        modes: "str",
        lapses: "str",
    },
    thrash: {
        pid: "num",
        switches: "num",
        window: "num",
        mode: "str",
        competing: "str",
    },
    /** Perf probe (Telemetry.Perf): which clock the bot VM has, once per VM. */
    perf_probe: {
        vm: "str",
        os_clock: "num",
        real_time: "num",
        res_us: "num",
        spins: "num",
        spin_cpu_ms: "num",
        spin_real_ms: "num",
        /** The clock found: `os.clock`, `RealTime` or `none` (`none` leaves the probe off). */
        src: "str",
    },
    /** Perf probe: one window per VM. entry_ms all script time through OHA entry points, ours_ms inside our guards, log_ms event printing. */
    perf: {
        pid: "mixed",
        vm: "str",
        /** The window's length in game seconds (`PerfInterval`, 10). */
        dt: "num",
        cpu_ms: "num",
        /** Wall time of the window. */
        real_ms: "num",
        entry_ms: "num",
        ours_ms: "num",
        log_ms: "num",
        /** Event lines printed in the window. */
        log_n: "num",
    },
    /** The window's largest rows (`PerfTop`, 25). Rows overlap across kinds; sum within `entry` only. */
    perf_top: {
        vm: "str",
        /** `entry` (an OHA entry point), `ours` (an outermost guarded call), `sub` (a guarded call made directly from an outermost
         *  one), `step` (an unguarded step of the tick, `Tick:<step>`) or `fn` (`PerfDeep`: an exported function, `<module>.<fn>`, or a span inside one, `<module>.<fn>:<part>`). */
        kind: "str",
        /** `oha.<file>.<fn>` for `entry`; for `sub`, `outer>inner` (inclusive). */
        where: "str",
        n: "num",
        ms: "num",
        max_ms: "num",
    },
    /** A check by OHA's `J.CheckBotIdleState`: a bot moved under 100 in 3 s in farm or item mode (or idle), and OHA would clear its actions and attack-move it to its lane front. A line is a check, not a relocation: OHA re-checks on following frames. */
    oha_idle: {
        pid: "num",
        mode: "num",
        /** 1 when a running job of ours kept the bot, 0 when OHA relocated it. */
        held: "num",
        /** Distance from the hero to where OHA sends it (its assigned lane's own front, `GetLaneFrontLocation` amount 0), as it fires. */
        d: "num",
    },
    /** Each neutral camp's spawn box once per game, from the first stack job (replay grading, hlog stacktruth.js). */
    camp: {
        /** The spawner's index (as `ev=pull_job` `camp`). */
        idx: "num",
        team: "num",
        type: "str",
        /** The spawner's origin, x. */
        x: "num",
        /** The spawner's origin, y. */
        y: "num",
        /** Spawn box, first x edge. */
        x0: "num",
        /** Spawn box, first y edge. */
        y0: "num",
        /** Spawn box, second x edge. */
        x1: "num",
        /** Spawn box, second y edge. */
        y1: "num",
    },
    /** Overrides.VisionMap (probe games only, `vision_map.ts`): the map's height grid and trees for a sight model. `kind`
     *  start (the box and `step`, `src` api | fallback), h (a row: `y`, `x0`, `n` cells, `hex` one digit a cell, the
     *  height level plus 8 when passable), t (`xy` "index:x:y" joined by ";"), end (`rows`, `trees`),
     *  camp (`xy` "idx:team:type:x:y:minx:miny:maxx:maxy" joined by ";", the neutral camps). */
    vmap: {
        kind: "str",
        bx0: "num",
        by0: "num",
        bx1: "num",
        by1: "num",
        step: "num",
        src: "str",
        y: "num",
        x0: "num",
        n: "num",
        hex: "str",
        xy: "str",
        rows: "num",
        trees: "num",
    },
    /** Overrides.ApiProbe (probe games only, `api_probe.ts`): a hero about itself once a second, the truth for the other team's
     *  `apiprobe_enemy` row of the same second. -1 is a nil read, -2 a failed one. */
    apiprobe_own: {
        team: "num",
        pid: "num",
        seen: "num",
        loc: "num",
        x: "num",
        y: "num",
        alive: "num",
        hp: "num",
        mp: "num",
        lvl: "num",
        ms: "num",
        nw: "num",
        nmod: "num",
        cds: "num",
        nitem: "num",
        it0: "str",
        tgt: "num",
        chan: "num",
        cast: "num",
    },
    /**
     * Overrides.LaneReadProbe (lane_hits_probe.ts): one creep leaving LaneHits' read (dead, or out of the lane list or sight),
     * with the read's last prediction of the hit that kills it and who took it that frame.
     */
    lane_hits_check: {
        /** The reading team. */
        team: "num",
        lane: "num",
        /** 1 the reading team's own creep, 0 an enemy creep. */
        own: "num",
        cid: "num",
        /** HP at the last read. */
        hp: "num",
        /** The predicted killing hit's kind: `hero`, `self` (the reader hero), `creep`, `tower`, or `none` (no hit within the horizon kills it). */
        pby: "str",
        /** Its hero's player id (-1 not a hero). */
        ppid: "num",
        /** Seconds from the last read to that hit, and to its commit (-1 none). */
        pt: "num",
        pc: "num",
        /** Seconds from the last read to this line (one frame for a death). */
        age: "num",
        /** Heroes of the team whose denies (own creep) or last hits (enemy creep) rose this frame, `;`-joined player ids. */
        rose: "str",
        /** `dead`, or `left` (alive, out of the read). */
        end: "str",
    },
    /**
     * Overrides.SwingProbe (swing_probe.ts): one own hero's attack on a lane creep, from the first frame its wind-up is seen
     * to its truth. Times in seconds after that frame: `pf`/`pl` the predicted fire and landing by the engine's formula before slice oha-engine-windup (kept for comparison), `fire` the
     * fire by GetLastAttackTime, `seen` the frame it was seen, `land` the landing seen (melee: the fire frame; ranged: the
     * hero's projectile gone from the creep). -1: never. `cyc`, `pt`, `spa` the raw reads at the first frame.
     */
    swing_probe: {
        /** The hero's player id (absent for a creep or tower). */
        pid: "num",
        /** The attacker: `hero` of ours, `creep` (a lane creep of ours, a few followed at a time) or `tower` (ours). */
        kind: "str",
        /** A creep's or tower's Telemetry.CreepId (absent for a hero). */
        aid: "num",
        /** Telemetry.CreepId of the target. */
        cid: "num",
        /** 1 our own creep (a deny attempt), 0 the enemy's. */
        own: "num",
        rng: "num",
        cyc: "num",
        pt: "num",
        spa: "num",
        pf: "num",
        pl: "num",
        /** GetAttackSpeed at the first frame. */
        aspd: "num",
        /** Predicted fire as attack point / attack speed x (1 - cycle): the attack point read as seconds (swingprobe1). */
        pf2: "num",
        /** Predicted flight of a ranged hit (0 melee). */
        fl: "num",
        fire: "num",
        seen: "num",
        land: "num",
        /** The attack target at the fire was still the creep (1), another (0); -1 never fired. */
        same: "num",
        /** A ranged hit's projectile was seen at the creep. */
        proj: "num",
        hp0: "num",
        /** HP the creep lost from the frame before the landing to the landing frame (others' hits in that frame included); -1 no landing. */
        drop: "num",
        /** The hero's attack damage after the creep's armour. */
        dmg: "num",
        /** The hero's last hits or denies rose by the frame after the landing. */
        kill: "num",
        /** `land`, `cancel`, `retarget`, `gone`, `lost`. */
        end: "str",
        /** end=retarget: the new target, `creep` (another lane creep), `hero`, `none` or `other`. */
        to: "str",
        /** Seconds after first sight of the end (any end): how far into the wind-up a cancel or retarget came. */
        age: "num",
        /** Ranged: predicted landing from the projectile's own position on its first frame (engine flightsAt), seconds after first sight. */
        pl3: "num",
        /** HP lost over the landing frame and the next (a hit's damage that shows a frame late). */
        drop2: "num",
        /** Ranged, after the fire: per frame 1 the hero's projectile listed at the creep, 0 not (40 frames at most). The landing is the first of two absent frames in a row. */
        pres: "str",
        /** After the fire: the largest one-frame HP loss of the creep, and when (seconds after first sight; -1 none). */
        big: "num",
        bigat: "num",
        /** The longest frame gap over the record. */
        gap: "num",
        /** Before the fire, per frame from the first `dt:cycle` (seconds after first sight, GetAnimCycle), `;`-joined, `x` appended off the attack activity (30 frames at most). */
        wc: "str",
    },
    /** Overrides.ApiProbe: the team's reporter about an enemy hero handle it holds; a hero out of sight has no row (its handle is null). */
    apiprobe_enemy: {
        team: "num",
        pid: "num",
        vis: "num",
        loc: "num",
        x: "num",
        y: "num",
        alive: "num",
        hp: "num",
        mp: "num",
        lvl: "num",
        ms: "num",
        nw: "num",
        nmod: "num",
        cds: "num",
        nitem: "num",
        it0: "str",
        tgt: "num",
        chan: "num",
        cast: "num",
    },
    /** Overrides.ApiProbe: one cast callback; `vis` whether the caster was visible to `team` as it fired (-2: its handle was null). */
    apiprobe_cast: {
        team: "num",
        pid: "num",
        own: "num",
        vis: "num",
        ability: "str",
    },
    /** Overrides.ApiProbe: damage callbacks for one player in one second: `n` fired, `fog` of them with the hero not visible to `team`. */
    apiprobe_dmg: {
        team: "num",
        pid: "num",
        own: "num",
        n: "num",
        fog: "num",
        sum: "num",
    },
    /** Overrides.ApiProbe: the argument shape of the first damage callback, once per team. */
    apiprobe_dmgshape: {
        team: "num",
        args: "str",
    },
    /** Overrides.ApiProbe: one ability handle's reads, `own` 1 for a hero about itself (the truth) and 0 for the team's reporter
     *  about a visible enemy; written on a change (rem only by its sign) or every 10 s. `aest` is the ability's own 3 s
     *  estimate on the nearest hero of the other side. */
    apiprobe_abil: {
        team: "num",
        pid: "num",
        own: "num",
        slot: "num",
        name: "str",
        lvl: "num",
        rdy: "num",
        fc: "num",
        mok: "num",
        rem: "num",
        cd: "num",
        scd: "num",
        dmg: "num",
        mc: "num",
        aest: "num",
    },
    /** Overrides.ApiProbe: `src`'s unit GetEstimatedDamageToTarget over 3 s on `dst` (the nearest hero of the other side),
     *  with bCurrentlyAvailable true (`et`) and false (`ef`); once a second for each own hero and each visible enemy. On an
     *  enemy row `ec` is SpellReady.DamageOn, the figure our reads use; the enemy team's own row for the pair is its truth.
     *  `ty` is the damage-type mask of all three (7 with pure; rows without it used 3, no pure). */
    apiprobe_est: {
        team: "num",
        src: "num",
        dst: "num",
        own: "num",
        dist: "num",
        et: "num",
        ef: "num",
        ty: "num",
        ec: "num",
    },
    /** Overrides.ApiProbe: one GetIncomingTeleports entry, once a second. */
    apiprobe_tp: {
        team: "num",
        pid: "num",
        own: "num",
        x: "num",
        y: "num",
        rem: "num",
    },
    /** Overrides.VisionProbe (scenario games only): whether the camp's neutrals are in sight from one candidate stand point. */
    visprobe: {
        pid: "num",
        camp: "num",
        /** -1 the stand point the job uses; 0-7 the points at the stand offset past the box edge, east then anticlockwise. */
        k: "num",
        x: "num",
        y: "num",
        /** 0 when the point was not reached in 10 s. */
        reach: "num",
        /** The camp's neutrals in sight inside its box after 1 s there. */
        seen: "num",
        /** 1 when the origin was visible. */
        vis: "num",
        /** Night, by `GetTimeOfDay`. */
        night: "num",
    },
    stuck: {
        pid: "num",
        mode: "str",
        d: "num",
        raw: "num",
        inMode: "num",
    },
    /** Team-wide: written once per module instance, de-duplicated by `parse.js` within 1 s. */
    order_post: {
        id: "num",
        team: "num",
        type: "str",
        lane: "num",
        issuer: "num",
        responders: "str",
        dur: "num",
        kind: "str",
        src: "str",
    },
    order_decline: {
        pid: "num",
        id: "num",
        type: "str",
        reason: "str",
    },
    order_accept: {
        pid: "num",
        id: "num",
        type: "str",
        lane: "num",
        kind: "str",
        read: "num",
        latency: "num",
    },
    /** Team-wide: written once per module instance, de-duplicated by `parse.js` within 1 s. */
    ping: {
        by: "num",
        team: "num",
        context: "str",
        danger: "bool",
        x: "num",
        y: "num",
        order: "str",
    },
    trainer: {
        pid: "num",
        selftest: "bool",
        kind: "str",
        creep: "str",
        deny: "bool",
        offset: "num",
        window: "num",
        pred: "num",
        landed: "num",
    },
    /** Team-wide: written once per module instance, de-duplicated by `parse.js` within 1 s. */
    cmd: {
        by: "num",
        team: "num",
        name: "str",
        args: "str",
        only: "str",
        text: "str",
    },
    lane_eq: {
        team: "num",
        lane: "num",
        kind: "str",
        eq: "num",
        imb: "num",
        feq: "num",
        a: "num",
        e: "num",
    },
    /**
     * Slice lane-read, once a second per team and lane to 12:00, both arms. Amounts run from Radiant's ancient (0) but along
     * the writing team's lane path, so they are comparable within one team's lines only (lr1: Dire's read 0.07-0.16 lower).
     * adv 0..2 and a/e/ap/ep over creeps near our front (enemy ones visible only); of/ef fronts, ot/et nearest alive towers;
     * cyc second in the 30 s cycle; cn/chp/cpw/cl own creeps in the whole lane (count, HP,
     * HP-weighted power, lead amount, lead map position clx/cly): the other team's ground truth; cnn/cnp own creeps near the enemy's front (count, power),
     * the enemy reading's e/ep without fog; fx/fy our front's map position. ee per enemy `pid:v|seen:dist[:hp:lvl]` (v = visible,
     * else seconds since seen; hp percent), dead enemies; ag per allied hero `pid:now:since` (since -1 if never).
     * cc every own creep in the lane by ascending amount `kind:amount_in_thousandths:hp` (kind m/r/s/f), tw/twh our nearest alive tower's tier
     * (0 when all are down) and HP (slice lane-census, for the lane forecast's start state and tower crash timing).
     * Slice lane-read-ec: ec every visible enemy lane creep in the lane, as cc; ed per enemy in ee's order
     * `pid:dist_to_our_tower:ally=dist,...` (-1 with no tower); ns alive enemy pids never seen, joined by `;`.
     */
    lane_read: {
        team: "num",
        lane: "num",
        /** Creep advantage 0..2 (1 even) over the creeps within 1,200 of the team's front, enemy ones visible only. */
        adv: "num",
        /** Where the waves meet between the nearest towers: -1 at our tower, 1 at theirs. */
        eq: "num",
        /** Own creeps near our front (count). */
        a: "num",
        /** Enemy creeps near our front (count, visible ones only). */
        e: "num",
        /** Own creeps near our front, HP-weighted power. */
        ap: "num",
        /** Enemy creeps near our front, HP-weighted power (visible ones only). */
        ep: "num",
        /** Our front's amount along the lane. */
        of: "num",
        /** Their front's amount along the lane. */
        ef: "num",
        /** Our nearest alive tower's amount. */
        ot: "num",
        /** Their nearest alive tower's amount. */
        et: "num",
        /** The second in the 30 s wave cycle. */
        cyc: "num",
        /** Own creeps in the whole lane (count): the other team's ground truth, not a reading. */
        cn: "num",
        /** HP of own creeps in the whole lane. */
        chp: "num",
        /** HP-weighted power of own creeps in the whole lane. */
        cpw: "num",
        /** The lead own creep's amount along the lane. */
        cl: "num",
        /** The lead own creep's map x. */
        clx: "num",
        /** The lead own creep's map y. */
        cly: "num",
        /** Own creeps near the enemy's front (count). */
        cnn: "num",
        /** Own creeps near the enemy's front (power). */
        cnp: "num",
        /** Our front's map x. */
        fx: "num",
        /** Our front's map y. */
        fy: "num",
        /** Enemies dead; also counts enemies found dead before they were seen. */
        dead: "num",
        /** Per enemy, `pid:v:dist:hp%:lvl` when visible, else `pid:secs_since_seen:dist` from its last-seen spot. */
        ee: "str",
        /** Per allied hero in the lane, `pid:creeps_on_it_now:secs_since_last` (one decimal, -1 never). */
        ag: "str",
        /** Every own creep in the lane as `kind:amount_in_thousandths:hp` (kind m, r, s or f), by ascending amount. */
        cc: "str",
        /** Tier of our nearest alive tower on the lane; 0 when all are down. */
        tw: "num",
        /** That tower's HP. */
        twh: "num",
        /** Every visible enemy lane creep in the whole lane, in `cc`'s format. */
        ec: "str",
        /** Per enemy in `ee`'s order, `pid:dist_to_our_tower:ally=dist,...`; -1 when all our towers on the lane are down. */
        ed: "str",
        /** Alive enemy pids never seen this game, joined by `;` (in practice only the first 30 s). */
        ns: "str",
    },
    /** Slice lane-aggro: one line per draw (lane_aggro). */
    aggro: {
        /** The laner that drew. */
        pid: "num",
        /** `core`, or `support` (its lane core away). */
        role: "str",
        /** `feed` (enemy wave onto our ranged creep), `tower` (their creeps drawn out of their tower) or `back` (wave_hold's drag: their wave behind our T1 to our next wave). */
        kind: "str",
        /** feed: `denied` (our deny), `lost` (it died otherwise), `alive` (not dead in FeedWatch); tower: `ok` (a drawn creep out of the tower's reach), `stayed`; back: `ok` (a drawn creep within
         *  BackOut of the point behind our T1 at the walk's end), `stayed`; all: `no_draw` (no creep took us within DrawCheck), `hurt`, `died`, `short` (feed: no enemy creep within DrawR at the order after the approach, no order), `cancelled` (before the order: no visible enemy hero to order on, or the feed's ranged creep or the tower move's creep died during the approach), `unsafe` (feed, tower: an enemy hero came into reach of the approach point, or the feed's walk-back point, during the approach), `stale` (not stepped for StaleActing/StaleWatch: the caller lost the frame). */
        result: "str",
        /** The enemy hero the draw order was given on. */
        tgt: "num",
        /** Enemy lane creeps within 500 at the order; most targeting the bot during the walk; most on the fed creep after it. */
        near: "num",
        /** Most enemy creeps targeting the hero during the walk. */
        drawn: "num",
        /** Enemy creeps near at the order that moved MovedR since (drawn off their fight), most at once. */
        mv: "num",
        /** Most enemy creeps on the fed creep after the drop. */
        onr: "num",
        /** feed: the fed creep's HP fraction at the result line, when alive. */
        rhp: "num",
        /** HP the bot lost from the start to the hand-back (min HP), and its HP fraction at the start. */
        dhp: "num",
        /** The bot's HP fraction at the start. */
        hp: "num",
        /** Lane push reading at a feed: clash between the T1s (0 ours) and its state. */
        q: "num",
        /** Lane push state at a feed: `OUT`, `HOLD` or `IN`. */
        st: "str",
        /** feed: seconds from the order to the drop order. */
        drop: "num",
        /** Slice trade-count, result `unsafe` of a feed or tower move: 1 when the approach's unsafe check (the one each frame of the walk asks) already held at the start, 0 when it came later. Absent otherwise. */
        ato: "num",
        /** Seconds the attempt took. */
        dur: "num",
        /** feed: the clash's distance from our T1 along the lane now, and forecast (own + move), against the lane's target point. */
        own: "num",
        /** feed: the clash's distance from our T1 forecast ahead (own + move). */
        fc: "num",
        /** Distance to the order's hero at the order (any visible enemy hero may be named). */
        td: "num",
        /** tower: enemy creeps drawn at the order that stood out of the tower's reach (TowerOrderR) at the result; back: those
         *  within BackOut of the point behind our T1. */
        out: "num",
        /** feed: 1 once the laning spot anchored on the fed creep (lane_spot input `fed`, `ev=lane_pos spot=fed`), else 0. */
        sty: "num",
        /** back: draw orders given (the first and each re-draw). */
        nd: "num",
        /** back: who asked, `drag` (wave_hold's drag behind our T1) or `hold` (wave_hold's hold draw, a point 150 past the
         *  hold point: its `result` is nearly free, read `drawn` for the aggro taken). */
        src: "str",
        /** feed, tower: the bot's distance to the approach point at the start, and the seconds it got to walk there (feed: the
         *  walk at its move speed + 0.4 s, at most 3.5 s). */
        ad: "num",
        apt: "num",
        /** stale: the first other mode seen holding the bot during the gap (else the active mode), the task label (`-` none) when the
         *  frame came back, and the seconds it was away. */
        md: "num",
        lbl: "str",
        gap: "num",
    },
    /** Slice core-in-lane (wave_hold, Ours.CoreHold): one line per hold of their wave while ours is gone, at its end. */
    wave_hold: {
        /** The holding core. */
        pid: "num",
        /** The lane held. */
        lane: "num",
        /** The last branch: `hold` (at the lane target, lane_spot input `hold`), `drag` (lane_aggro `back` behind our T1),
         *  `retreat` (OHA's retreat took the core). */
        br: "str",
        /** `met` (one of our creeps not in the start's clash fighting one of theirs), `cleared` (none of theirs left), `tower` (theirs reached our T1, hold branch),
         *  `hurt`, `left` (no laning host for LeftAfter: another mode, or the laning body not running; `md`), `died`, `timeout`, `unsafe` (an enemy hero pushed the held spot inside
         *  the hold point's floor), `concede` (the cost rule: over budget with no drag in time, or the drag's draw did not start;
         *  `cr`). */
        res: "str",
        /** Slice trade-count: for `met`, `cleared`, `tower`, `unsafe` and `concede` (not the failed drag), 1 when the first read ended it (the start frame reads at once: the end held on the open's own inputs), 0 when a later read did; absent for the ends that are no read (`hurt`, `timeout`, `left`, `died`). */
        ato: "num",
        /** Why our wave was gone (logged only): `pull` (an ally's pull job on the lane), `aggro` (our lane-aggro tower move in
         *  the last 20 s), `other`. */
        why: "str",
        /** The start: `gone` (our wave gone from the lane outside our T1's range) or `forecast` (our wave still fighting within
         *  200 past the hold point, lane_push's run has their front inside our T1's fire (`rch`) in `fc` seconds; `why` is
         *  `losing`). */
        trig: "str",
        fc: "num",
        /** The hold point's distance from our T1: the lane target, or their front when nearer, never inside `rch` + 50. */
        hd: "num",
        /** Our T1's fire reach to a creep's centre (attack range plus both hull radii, from the API; fallback 860): the
         *  start's late floor and the hold point's floor are this plus 50. */
        rch: "num",
        /** Hold draws: lane_aggro `back` draws the holding core gave to take their wave's aggro at the hold point. */
        hdr: "num",
        /** Reads of the attempt made while the laning body's last-hit or deny swing held the frame (slice hold-through-swing:
         *  the read runs from States.Tick, so a swing no longer ends the attempt `left`). */
        hs: "num",
        /** Their lane creeps in the stretch at the start; our last hits and denies during the attempt. */
        n: "num",
        /** Our last hits during the attempt. */
        lh: "num",
        /** Our denies during the attempt. */
        dn: "num",
        /** Their front's distance from our T1 along the lane at the start, its least during the attempt, and when the waves met. */
        own0: "num",
        /** Their front's least distance from our T1 during the attempt. */
        omin: "num",
        /** Their front's distance from our T1 when the waves met. */
        mo: "num",
        /** Seconds from one of our creeps (not in the start's clash) first within 700 of their front to the attempt's end, to the read's 0.25 s. */
        mn: "num",
        /** 1 when one of their creeps came within our T1's range (700) during the attempt. */
        tw: "num",
        /** The lane's target point (lane_push TargetOf). */
        tgt: "num",
        /** Seconds to our next wave at the hold point at the start; at the last branch read: seconds the drag needs and to our
         *  next wave behind the T1. */
        nw: "num",
        /** At the last read: seconds the drag needs. */
        ds: "num",
        /** At the last read: seconds to our next wave behind the T1. */
        nb: "num",
        /** At the last branch read: seconds until our nearest lane creep already on the map and not fighting reaches the hold
         *  point (absent when none is within NearSecs' walk). */
        nl: "num",
        /** 1 when our creeps already walking (`nl`) turned a drag or concede the spawn schedule alone would give into a hold, at any read. */
        lv: "num",
        /** At the last branch read: seconds the core stands as their wave's target before our creeps reach the hold point
         *  (`tk`), the wave's expected damage on it over them (`cost`), the hold's budget (`bud`, TankShare of max HP). */
        tk: "num",
        /** At the last read: the HP lost plus the loss rate times `tk`. */
        cost: "num",
        /** The hold's HP budget (`TankShare` of max HP). */
        bud: "num",
        /** The core's HP loss rate in the cost (`rt`, HP a second) and its source (`rs`: `seen` once hit for 1 s, else `fit`,
         *  the wave's full rate times AggroShare); `cr` on `concede`: `cost` (over budget, no drag in time) or `drag` (the
         *  drag's draw did not start: lane_aggro's StartBack needs a visible enemy hero to order the attack on). */
        rt: "num",
        /** The loss rate's source: `seen` (hit for 1 s) or `fit` (the wave's full rate times `AggroShare`). */
        rs: "str",
        /** On `concede`: `cost` (over budget, no drag in time) or `drag` (the drag's draw did not start). */
        cr: "str",
        /** The enemy hero whose reach made the threat, at the last read that saw one. */
        thr: "num",
        /** Branch changes during the attempt. */
        sw: "num",
        /** The core's HP share at the start. */
        hp: "num",
        /** HP lost during the attempt. */
        dhp: "num",
        /** Seconds the attempt lasted; its start is `t - dur`. */
        dur: "num",
        /** The bot's active mode when the attempt was left. */
        md: "num",
    },
    /**
     * Slice core-in-lane: why the wave hold did not start for a core that owns it while their wave (2+ creeps) is at or inside
     * the lane target, at most every 5 s per bot and reason. `why`: `ours` (our wave there and no forecast start), `late` (their
     * front inside our T1's range + 50), `rest`, `reach`, `hp`; `ours_far` (their wave further out and walking in unopposed
     * while a creep of ours keeps the start off).
     */
    wave_hold_skip: {
        pid: "num",
        lane: "num",
        why: "str",
        /** Their front's distance from our T1 and their creeps in the stretch. */
        front: "num",
        n: "num",
        /** Our lane creeps from our T1's range out (`on`) and inside it (`oin`, from 400 behind the T1). */
        on: "num",
        oin: "num",
        /** Our T1's fire reach (as ev=wave_hold `rch`). */
        rch: "num",
        /** Forecast seconds until their front is inside our T1's range (on `rest`, `reach`, `hp` after a forecast start). */
        fc: "num",
        /** On `ours`/`ours_far`: the first creep of ours that keeps the start off, its distance from our T1 and its attack
         *  target (`none`, `lane`, `hero`, `tower`, `other`: a neutral or anything else). */
        ob: "num",
        obt: "str",
    },
    /** Slice lane-aggro: why a laner that owns the move did not draw (the first gate that said no), on change, at most every 3 s. */
    aggro_skip: {
        pid: "num",
        role: "str",
        /** A shared gate (`cooldown`, `lane`, `hp`, `trading`, `tower`, `pull`, `reach`), or `tower:<why>` / `feed:<why>`
         *  (`feed:inside_hold`: the walk back would draw their creeps inside the wave hold point; `feed:ctl_shove`: the lane
         *  controller's live decision is a shove; `feed:ctl_forced`: a drill forces another lever; `feed:no_ranged_fed`, `_low`,
         *  `_none`: our ranged creeps within 1200 are all fed already, the best is under FeedCreepHp, or there is none). */
        why: "str",
        /** feed:approach_far: the bot's distance to the approach point. */
        ad: "num",
    },
    /** Slice deaggro: one line per shed attempt (an attack order on our lane creep to move a tower's or enemy creeps' aggro). */
    deaggro: {
        pid: "num",
        /** Attackers on us at the order: `tower`, `lane` or `mixed`. */
        kind: "str",
        /** `ok` (no unlocked attacker still on us), `still_hit` (some still on us after ConfirmFor), `gone` (we died),
         *  `stale` (the caller stopped watching). From the trade's shed after a swing, when no order went out: `locked`, `no_unit`, `none`, `open`
         *  (`Deaggro.Shed`'s reason), with `n` the creeps on us. */
        result: "str",
        /** Attackers on us at the order; of them locked (we stood inside their attack range); covered by the order's target. */
        n: "num",
        lk: "num",
        cov: "num",
        /** On `still_hit`: unlocked attackers still on us. */
        left: "num",
        /** Unlocked attackers that died or left sight before the result (off us, but not by a switch). */
        dead: "num",
        /** Seconds from the order to the result. */
        dt: "num",
        /** Our HP fraction at the order and lost by the result. */
        hp: "num",
        dhp: "num",
    },
    lane_tech: {
        pid: "num",
        tech: "str",
        reason: "str",
        lh: "bool",
    },
    lane_job_start: {
        pid: "num",
        kind: "str",
        camp: "num",
        key: "str",
        data: "str",
        aggroAt: "num",
        forced: "bool",
        core: "bool",
        timing: "str",
        pre: "num",
        take: "num",
    },
    lane_cover: {
        pid: "num",
        state: "str",
        partner: "num",
        via: "str",
        dur: "num",
        kind: "str",
    },
    lane_job: {
        pid: "num",
        kind: "str",
        camp: "num",
        key: "str",
        aggro: "num",
        planned: "num",
        divert: "num",
        grade: "str",
    },
    lane_job_abort: {
        pid: "num",
        kind: "str",
        camp: "num",
        key: "str",
        reason: "str",
        phase: "str",
        acted: "bool",
        divert: "num",
        to: "str",
        toBy: "str",
        toAge: "num",
        logLag: "num",
        pre: "num",
        take: "num",
        competing: "str",
        hold: "str",
        holdAge: "num",
        focusAge: "num",
        farmAge: "num",
        partner: "num",
        php: "num",
        pnear: "num",
        pclose: "num",
        ploss: "num",
    },
    lane_job_end: {
        pid: "num",
        kind: "str",
        camp: "num",
        reason: "str",
        pre: "num",
        take: "num",
        swings: "num",
    },
    lane_job_hold: {
        pid: "num",
        hold: "str",
        kind: "str",
        camp: "num",
        phase: "str",
        state: "str",
        reason: "str",
        hp: "num",
        partner: "num",
        php: "num",
        pnear: "num",
        pclose: "num",
        ploss: "num",
    },
    lane_plan: {
        pid: "num",
        owner: "str",
        eq: "num",
        meet: "num",
        want: "num",
        front: "num",
        efront: "num",
        tower: "num",
        etower: "num",
        gate: "str",
        camp: "num",
        travel: "num",
        timing: "str",
        tech: "str",
        reason: "str",
        score: "num",
        fscore: "num",
        w: "num",
        imb: "num",
        feq: "num",
        apow: "num",
        epow: "num",
        plan: "str",
        pullOk: "bool",
        partner: "bool",
        laners: "num",
        second: "num",
        why: "str",
        late: "num",
        gap: "num",
    },
    lane_job_ping: {
        pid: "num",
        kind: "str",
        camp: "num",
        partner: "num",
    },
    lane_stack: {
        pid: "num",
        camp: "num",
        type: "str",
        aggro: "num",
        planned: "num",
        before: "num",
        after: "mixed",
        grade: "str",
        stacked: "bool",
        assumed: "bool",
    },
    // Slice 4 (stack_job): one line per trigger minute; "?" where a phase never ran.
    /** Drills (humaniser/drill.ts): `ph=role` per hero when its role is known or changes (`role` cast, bench, statue,
     *  laneonly, play); `ph=rep` once per rep per team with a cast (`input` on or off: off is a control rep; `start` the rep's
     *  clock; `forces` the forced context, absent for natural reps); `ph=unknown` once when Overrides.Drill names no entry; `ph=removed` once per knob drills replaced (Solo,
     *  StackEvery, LaneOnly; `name` the key) still set, which now does nothing. `role` may also be `inlane` (the lane
     *  ladder's hold); ph=forbid when an in-lane hero `pid` began a global spell `ability` and its order was cleared (at
     *  most once per 5 s per hero). */
    drill: {
        ph: "str",
        name: "str",
        pid: "num",
        team: "num",
        pos: "num",
        role: "str",
        rep: "num",
        input: "str",
        start: "num",
        forces: "str",
        /** ph=spot: a statue's spot for the rep (`lane`, `bench`, `pull:<r|d>:<safe|off>`) and the point it holds. */
        spot: "str",
        x: "num",
        y: "num",
        /** retreat-linger: ph=linger_go (the HP trigger: the chaser `pid` backs off the target `tpid`, the cast, at HP share `thp`,
         *  distance `d`, the rep's end time `rend`), ph=linger (it first stands at the stand-off: the window's clock) and ph=linger_end
         *  (`res` contact|timeout|died|no_standoff|rep_end, `secs` from the window's start, `dmin` the closest distance since
         *  the stand-off, `dmax` the furthest, `dend` the last seen distance, `uns` seconds the cast was out of sight, `clamp` 1 when the
         *  tower pull-back moved the point). */
        tpid: "num",
        thp: "num",
        d: "num",
        res: "str",
        secs: "num",
        dmin: "num",
        clamp: "num",
        dmax: "num",
        dend: "num",
        uns: "num",
        rend: "num",
        /** Rigs (an entry with `rig`): ph=rep and ph=ready carry the rep's kind `var`; ph=step when a rig hero `pid` moves to
         *  step `i` (0-based) `step` of its setup; ph=ready once per rep and cast hero: `ok` 1 when every ready check held (the
         *  cast is released), 0 at the timeout with the first failing check `fail` (setup|early|sightkey|sees|unseen|hp|hplow|holds|lacks|clear|near|hit|past|behind|lone|lonehit|burst: the rep is
         *  invalid), `secs` from the rep's start, the cast's HP share `hp`; ph=spot once per rig spot: its point `x`, `y`, how
         *  far it moved to be passable `d`, the nearest Radiant and Dire tower `rt`, `dt`; ph=wait when the cast's first
         *  failing ready check `fail` changes; ph=buy per purchase try (`step` the item, `res` the API's result, `gold`); ph=ready
         *  also carries `rend` (the rep's end), `win` (the end of the stage the rule lives in; a rep ending after it is outside)
         *  and `rel` (the release list's modes but `idle`, comma-separated); ph=wait and ph=ready carry `d`, the nearest hero
         *  that hit the cast in the last second, as distance past the cast's trade reach; in a `lone` rep also `bu`, the lone
         *  enemy hero's estimated damage over 3 s as a share of the cast's HP. */
        var: "str",
        /** In a `lone` rep, on ph=wait and ph=ready: the lone enemy hero's estimated damage over 3 s as a share of the cast's HP. */
        bu: "num",
        /** lane-trade (rig `watch`, released cast `pid`): ph=atk per attack it fired at enemy hero `tpid` (`d` the distance), ph=chit
         *  per attack an enemy lane creep fired at it and ph=hhit per attack enemy hero `tpid` fired at it, each with `dmg` (the
         *  attacker's mean attack damage after the cast's armour). Its actors: ph=swing when a `lasthit` actor `pid` walks up to
         *  one of our creeps (`d` the distance), ph=answer when a `hitback` actor starts attacking hero `tpid` that hit it. */
        dmg: "num",
        /** ph=forbid: the global spell's ability name. */
        ability: "str",
        win: "num",
        rel: "str",
        i: "num",
        step: "str",
        ok: "num",
        fail: "str",
        hp: "num",
        /** ph=ready: the cast's mana share. */
        mp: "num",
        /** ph=ready in a rig with per-hero tasks (the sustain rig): the task this hero's setup forced (`tango`, `ship`, ...). */
        task: "str",
        rt: "num",
        dt: "num",
        gold: "num",
        /** Rig sight (slice rig-sight): on ph=wait and ph=ready, per enemy hero key of the rep with a `stand` step, `key:s`
         *  comma-separated, s 1 an enemy hero in the cast team's sight within 200 of its stand point, 0 the point fogged and
         *  none seen there, 2 the point in sight and nobody there. Ready checks `sees` and `unseen` fail `sees`, `unseen` or
         *  `sightkey` (an own-team key or one with no stand step). */
        sight: "str",
        /** GetHeightLevel: of the cast's place on ph=ready, of the spot on ph=spot. */
        hl: "num",
        /** ph=grid (a rig with `grid`), at ready: IsLocationVisible around the cast at `x`, `y`, as `x0,y0,nx,ny,step,hex`
         *  (sight.ts VisionGridBox: bit i is cell (i % nx, floor(i / nx)) from the south-west corner). */
        vg: "str",
        /** ph=grid: the team's other sight sources (allied heroes but the cast, creeps, wards, buildings) within the box plus
         *  2,000, `x:y:range` joined by ";" (sight.ts Viewers), and `vr` the cast's own GetCurrentVisionRange. */
        vu: "str",
        vr: "num",
        /** burst-read: ph=cast per spell order of a `burst` actor `pid` (`spell`, its `lvl`, `s` seconds from the burst's first
         *  order, the actor's `mana`, the target `tgt`); ph=trace every 0.25 s for the rig's `trace` seconds after ready (`s` from
         *  ready, the cast's `hp` and `mhp`, `est` the summed GetEstimatedDamageToTarget(true, cast, 3, all) of the `n` enemy
         *  heroes in sight within 1,700, the nearest one's unit name `foe`, mana share `fmana`, level `flvl` and distance `d`,
         *  `root` 1 when the cast is rooted, `alive`). */
        spell: "str",
        lvl: "num",
        s: "num",
        mana: "num",
        tgt: "num",
        mhp: "num",
        est: "num",
        n: "num",
        foe: "str",
        fmana: "num",
        flvl: "num",
        root: "num",
        alive: "num",
    },
    // Slice job-chooser: one start and one end per started job attempt, in both arms of Ours.JobChooser.
    job: {
        pid: "num",
        /** The attempt id: a number unique per hero within a game, allocated when a decision goes (or the job starts with no decision line) and shared by the go `ev=choice` line of a decider row's attempt, this job's `start` and `end` lines and its result line (`ev=pull_job`, `ev=stack`, `ev=rune_job`; none for `rune_detour`, whose `end` line is its result). On `job=creep` it is allocated at the go (creep_row.ts) and is on the go `ev=choice kind=creep` line, the start and the end; absent on logs before oha-creep-swing, whose creep lines join by `cid`. */
        aid: "num",
        /** On `start`: what the attempt acts on, `<kind>:<id>`: `camp:<spawner index>` (`job=pull`, `job=stack`: as the result line's `camp`) or `rune:<rune id>` (`job=rune_detour`: as its `ev=choice` `rune`). Absent for `job=rune`, whose lines log no rune id, and on `end`. */
        tgt: "str",
        /** `stack`, `rune`, `pull`, `rune_detour` or `creep` (creep_row.ts: one attempt on a creep, its end `why` the engine lastHit's reason). */
        job: "str",
        /** `start` (`why=trigger`) or `end`. */
        phase: "str",
        /** On `end`: the job's `ev=stack`, `ev=rune_job` or `ev=pull_job` `why`. */
        why: "str",
        /** The hosting mode's number. */
        host: "num",
        /** 1 when hero damage landed during the job. */
        hit: "num",
        /** On `end` of a decider row's job the engine ended because the host mode lost the hero (`why=preempted`): what took it, `retreat` (the decider let go for stock's retreat, or the retreat mode outbid the hold) or the mode's name; `late_back` (`job=creep`, `why=cancelled`; only in logs banked before the creep row held hard from the go: the row ended its own soft attempt because the hero came back too late). */
        cut: "str",
        /** With `cut=retreat`: the hero's HP share then. */
        hp: "num",
        /** `job=rune_detour`: the seconds the path by the rune was read to add when the walk started. */
        ex: "num",
        /** `job=rune_detour` end: 1 on a pickup: the verb's ok, or one step's gold gain reaching RuneDetour TookGold (GetRuneStatus stays available while a second rune lies on the spot). */
        took: "num",
        /** `job=rune_detour` end: the largest gold gain between two steps of the walk. */
        gj: "num",
        /** `job=creep` start and end: the attempt's kind, `lh` a last hit of their ranged creep or `dn` a deny of one of ours (creep_row.ts `KindOf`). */
        k: "str",
        /** `job=creep` start: the number of other heroes already holding a claim on the creep when this attempt took its own (creep_claim.ts). */
        oc: "num",
        /** `job=creep` end: 1 when the hero's claim on the creep was held and released by this end. Every start has an end with `cl=1`. */
        cl: "num",
        /** `job=creep` end: 1 when the attempt ended because a hero with a lower `creep` cell took a claim on the creep before this hero's swing was ordered (`why=interrupted`; creep_row `yieldsTo`, Ours.SupportCreeps). Absent otherwise. */
        yd: "num",
        /** `job=creep` start, when a tower of ours was attacking the creep (Ours.TowerCreeps, the leftover rule, creep_row `Verdict`): `lf` the creep's HP just before the killing tower shot, `tT` the tower's damage on it after armour, `ts` the tower shots before that one, `vd` the verdict (`wait`, `prehit`; `none` is refused and never starts). */
        lf: "num",
        tT: "num",
        ts: "num",
        vd: "str",
        /** `job=creep` end, on an attempt the leftover rule covers: the plain attacks (pre-hits) ordered before the last hit. */
        ph: "num",
        /** `job=creep` end, when the leftover rule gave the attempt up: `tgt` the tower's target was no longer the creep (or the tower was gone), else the verdict's refusal (`nowindow`, `mates`, `none`). Absent otherwise. */
        tl: "str",
        /** `job=creep`: the creep's id (as the read's `ev=choice kind=creep` `cid` and the hero's team's `creep_death` `cid`). */
        cid: "num",
        /** `job=creep` start: the engine's walk into range and due (s) at the read that went. */
        gw: "num",
        gd: "num",
        /** `job=creep` start: the hero's attack range. */
        rng: "num",
        /** `job=creep` start: the engine's attackReach of the creep at the go (attack range and both hulls, centre to centre): inside it a swing starts without a move. hlog's `lost_inrange` reads it. */
        rch: "num",
        /** `job=creep` start: seconds until the hero can order its swing from inside the verb's range (the walk to the engine's attackReach of the creep (attack range and both hulls, centre to centre), at its move speed) and the spare at go (`gd` less it; negative: the creep came due first). */
        gn: "num",
        sp: "num",
        /** `job=creep` start: the last reason the row refused this creep while it was about to come due (`held`, `acting`, `row` (another task runs for the hero), a cell's, `claimed`, `wait`, `human`, `notime_new`, `notime_held`, `notime_acting`, `notime_row`, `notime`, ...), and the hero's mode name then when that was `held`; absent when it went at the first such read. */
        hw: "str",
        hm: "str",
        /** `job=creep` start: seconds from the first read where the creep was about to come due to the go. */
        hs: "num",
        /** `job=creep` start: 1 when the hero's attack target was this creep at the go; `nw` 1 when the go came at the first read that listed the creep. */
        sa: "num",
        nw: "num",
        /** `job=creep` start: the lead in force at the go (s): the creep was about to come due within the walk plus this, one own attack cycle or `CreepRow.SETTINGS.EarlyLead` when that is longer. */
        ld: "num",
        /** `job=creep` end: seconds the attempt spent in each phase of the engine's lastHit (`onPhase`): `pw` walk (outside reach), `pq` wait (in reach, no swing ordered), `ps` swing (ordered, up to the end); 0 for a phase never entered. */
        pw: "num",
        pq: "num",
        ps: "num",
        /** `job=creep` end: only in logs banked before the row held hard from the go in every attempt: seconds from the go to the hold turning hard (0 once it did; -1 never). Not emitted now. */
        hc: "num",
        /** `job=creep` end: only in banked logs: the creep's due (s) when the hold turned hard. Not emitted now. */
        hd: "num",
        /** `job=creep` end: seconds from the go to the verb's swing order; -1 when none. */
        so: "num",
        /** `job=creep` end: how many times another mode had the hero (a gap between the row's steps over `Round`, the end's own included) and for how many seconds in all. */
        tk: "num",
        tks: "num",
        /** `job=creep` end: seconds from the go to the row's first step (the wait for the host mode's next call); -1 when it never stepped. Not `tin`: that is the first step inside the verb's range. */
        wt: "num",
        /** `job=creep` end: seconds from the start to the first step that ended inside the verb's range (centre distance against the engine's attackReach); -1 never. */
        tin: "num",
        /** `job=creep` end: 1 when the engine's lastHit ordered its swing, 0 when it ended before one (`why=ok` with 0: the hero's last-hit count rose from a swing ordered before the verb's, message `hit=other`); absent on a cut (`why=preempted`). */
        sw: "num",
        /** `job=creep` end: the hero's HP (absolute) at the start and at the end. */
        hp0: "num",
        hp1: "num",
        /** `job=creep` end: the verb's result message (engine docs/API.md "Message": what the swing was based on, or what held it); the runner's on a cut. */
        msg: "str",
    },
    /** One line per trigger minute (3, 5, 7) of the pos5's stack job (`Ours.StackExecute`; none with the switch off). Written after the job's walk-off, once the box was read, the hero died, or `ReadUntil` (5 s, 12 s on a double) passed, so `t` is up to that after the `ev=job phase=end` line. Pair by `start`..`t`. */
    stack: {
        pid: "num",
        /** The attempt id: a number unique per hero within a game, allocated when a decision goes and shared by its `ev=job` and, for the stack row, `ev=choice kind=stack go=1` lines. */
        aid: "num",
        /** The trigger minute. */
        min: "num",
        /** `stacked` (a neutral not seen during the job appeared in the box after :00), `not_stacked`, `unseen` (hit landed, box never in sight after :00), `failed` (no hit landed) or `skip` (no job started). A log's stacked rate is a lower bound; the replay grades it (`stacktruth.js`). */
        res: "str",
        /** On `failed`, the job's end reason (`missed:mistake:no-aggro`, `no_target:mistake:no-camp`, `cancelled:hit`, `preempted:mode=N`, `dead`). On `skip`, the last gate (`low-hp`, `enemy-near`, `hit`, `busy`, `late`, `no-camp`, `refused`). */
        why: "str",
        /** Slice trade-count: 0 when the job ended on a start gate (`cancelled:hit`, `interrupted:threat`, a low-HP or enemy-near end) that was clear at its start; absent for any other end. */
        ato: "num",
        /** The camp's spawner index. */
        camp: "num",
        /** The camp type. */
        type: "str",
        /** The second the attempt started. */
        start: "num",
        /** The second of the minute the hit was confirmed (a neutral targets the bot). */
        aggro: "mixed",
        /** Visible neutrals in the box at the hit. */
        before: "mixed",
        /** Visible neutrals in the box after :00. */
        after: "mixed",
        /** The spawned neutrals (not seen during the job). */
        fresh: "mixed",
        /** The second of the minute the box was first read after :00; `?` never. */
        chk: "mixed",
        /** Seconds from the job's start to its end (the walk back to lane is not counted). */
        away: "num",
        /** 1 when the bot died before the job's end. */
        death: "num",
        /** The camp's spawner origin x. */
        cx: "mixed",
        /** The camp's spawner origin y. */
        cy: "mixed",
        /** The bot's distance to the origin. */
        dist: "mixed",
        /** Visible neutrals within `NeutralSearch` of the bot. */
        near: "mixed",
        /** Of those, the ones inside the box. */
        inbox: "mixed",
        /** 1 when the origin is visible. */
        vis: "mixed",
        /** At :59.5 after a landed hit: visible neutrals in the box. */
        box59: "mixed",
        /** At :59.5: visible neutrals near the bot outside the box. */
        pulled59: "mixed",
        /** At :59.5: 1 when the bot stands in the box. */
        bot59: "mixed",
        /** At :59.5: the origin visible. */
        vis59: "mixed",
        /** At :59.5: the bot's distance to the exit point. */
        exit59: "mixed",
        /** The bot's distance to the origin at the hit. */
        hitd: "mixed",
        /** The hit neutral's distance to the origin 2 s after the hit. */
        tgt2: "mixed",
        /** The hit neutral's distance to the origin at :59.5. */
        tgt59: "mixed",
        /** At :59.5: visible neutrals in the bare box (no margin). */
        strict59: "mixed",
        /** The second the bot reached the stand. */
        arr: "mixed",
        /** The second of the hit order. */
        hit0: "mixed",
        /** The second the aimed neutral first lost HP (the hit landed). */
        dmg: "mixed",
        /** The second a camp neutral first targeted the bot (the camp turned). */
        react: "mixed",
        /** The walk-off second. */
        exit: "mixed",
        /** The bot's HP % at the hit order. */
        hpa: "mixed",
        /** The bot's HP % at the walk-off. */
        hpe: "mixed",
        /** The bot's HP % at :59.5. */
        hp59: "mixed",
        /** Spells cast during the job, `name@second`. */
        casts: "str",
        /** Each camp neutral 2 s after the hit, `name:dist:in|out:a|-`. */
        n2: "str",
        /** Each camp neutral at :59.5, same format. */
        n59: "str",
        /** The pulled neutrals from the hit to :59.5 as `name:max:drop`: the furthest it got from its origin while seen, and the second it stopped targeting the bot (`-` never gave up, `n` never targeted the bot, `name:?` never seen). */
        trk: "str",
        /** The most lane creeps within `LANE_NEAR` of the origin from the hit to the job's end (a partial pull). */
        lane: "mixed",
        /** OHA idle relocations the job held while it ran; 0 when none. */
        idle: "num",
        // Slice double-stack: camp A of a double (hit first), or `double=0` when the partner's walk did not fit.
        double: "num",
        /** Why it ran single: `walk`, `far`, `late` or `carry`. */
        dwhy: "str",
        /** Camp A's result, as `res` (or `unseen`). */
        fres: "str",
        /** B's `Stacking.StackCount` after this line's outcome (read by `core_camp` and `farm_pattern`). */
        scount: "num",
        /** A's stack count. */
        fscount: "num",
        /** Camp A's spawner index. */
        fcamp: "num",
        /** Camp A's type. */
        ftype: "str",
        /** A: the second its hit was confirmed. */
        faggro: "mixed",
        /** A: visible neutrals at the hit. */
        fbefore: "mixed",
        /** A: spawned neutrals in its box after :00 (often `unseen`: nothing walks to A). */
        ffresh: "mixed",
        /** A: visible neutrals in the box at :59.5. */
        fbox59: "mixed",
        /** A: the bot's distance to the origin at the hit. */
        fhitd: "mixed",
        /** A: the arrival second. */
        farr: "mixed",
        /** A: 1 when its box was in sight while the outcome was read. */
        fseen: "num",
        /** A: the second its box was first read after :00; `?` never. */
        fchk: "mixed",
        /** A: the hit order second. */
        fhit0: "mixed",
        /** A: HP % at that order. */
        fhpa: "mixed",
        /** A: the first second before the order that the attack target was a neutral in A's box (an auto-attack while waiting); `?` none. */
        fauto: "mixed",
        /** A's neutrals 2 s after its hit. */
        fn2: "str",
        /** A's neutrals at :59.5. */
        fn59: "str",
        /** A's pulled neutrals, as `trk`. */
        ftrk: "str",
        /** Seconds B's hit was pulled forward for stacks already in the box (`PileEarlier`). */
        early: "num",
        /** The same for A's hit. */
        fearly: "num",
        // Valve's window of the camp (`w0-w1`) and the confirmed hit's offset from it (0 inside); `f` for camp A.
        win: "str",
        /** The confirmed hit's offset from the window: negative before, positive after, 0 inside; `?` no confirmed hit. */
        woff: "mixed",
        /** A's stack window. */
        fwin: "str",
        /** A's hit offset from its window. */
        fwoff: "mixed",
    },
    // Regen slice, step 0: a timed regen buff (tango, salve, clarity) seen on a hero, in every arm whoever cast it.
    // state start|refresh|end; dur the full duration read live at the start, left what remained at the event; why on an end: full
    // (ran out), early (ended with time left) or dead; miss the HP (tango, salve) or mana (clarity) missing at the start; src the
    // damage sources in the 2 s before an end (hero, creep, tower; - for none); drop the most HP
    // the hero lost over those 2 s (0 on a start; a buff that ends early with src - and drop 0 was not ended by damage).
    regen_obs: {
        pid: "num",
        /** On a start: `ours` when our code ordered the item within 3 s (item_use.ts), else `oha`. */
        by: "str",
        /** Max HP, absolute (`hp`, `mp` are shares). */
        hpm: "num",
        /** `tango`, `salve` or `clarity`. */
        item: "str",
        /** `start`, `refresh` or `end`. */
        state: "str",
        /** On an end: `full` (ran out), `early` (ended with time left) or `dead`. */
        why: "str",
        hp: "num",
        mp: "num",
        /** HP (clarity: mana) missing at the start. */
        miss: "num",
        /** The full duration read live at the start. */
        dur: "num",
        /** What remained at the event. */
        left: "num",
        /** The damage sources flagged in the 2 s before an end: `hero`, `creep`, `tower`, `-` (the flags miss some damage). */
        src: "str",
        /** The most HP lost over those 2 s (the break signal). */
        drop: "num",
    },
    // Regen slice: a window in which a regen item could have been used (the hero alive, not attacking, not hit by a hero in the 2 s
    // before, for at least 1 s) with an item in hand and HP missing at least that item's full effect. miss0 and missmax the HP missing at
    // the window's start and at most; tg tangos in hand (charges, singles count 1) and sv salves; tge and sve what one use gives in full,
    // read from the item; tree the distance to the nearest visible, passable tree within 1,200 at the start (-1 none, or no tango);
    // under a tango or salve already running; used the items whose buff started inside the window (- for none).
    regen_win: {
        pid: "num",
        mode: "num",
        /** Seconds the window lasted. */
        len: "num",
        /** HP missing at the start. */
        miss0: "num",
        /** The most HP missing. */
        missmax: "num",
        /** Tangos in hand (charges). */
        tg: "num",
        /** Salves in hand. */
        sv: "num",
        /** What one tango use gives in full. */
        tge: "num",
        /** What one salve use gives in full. */
        sve: "num",
        /** Distance to the nearest visible passable tree within 1,200 at the start; -1 none. */
        tree: "num",
        /** 1 when a tango or salve was already running at the start. */
        under: "bool",
        /** The items whose buff started inside the window; `-` none. */
        used: "str",
    },
    lane_job_supply: {
        pid: "num",
        item: "str",
        state: "str",
        kind: "str",
        phase: "str",
        hp: "num",
        mp: "num",
        reason: "str",
    },
    lane_signal: {
        pid: "num",
        kind: "str",
        lane: "num",
        camp: "num",
        enemy: "num",
        noticed: "bool",
        inferred: "bool",
    },
    lane_enemy_role: {
        team: "num",
        lane: "num",
        role: "str",
        enemy: "num",
        hero: "str",
        members: "mixed",
    },
    lane_take_skip: {
        pid: "num",
        kind: "str",
        camp: "num",
        reason: "str",
    },
    notice: {
        pid: "num",
        target: "str",
        delay: "num",
        due: "num",
        reason: "str",
    },
    react: {
        pid: "num",
        who: "str",
        what: "str",
        delay: "num",
    },
    lanefight_watch: {
        pid: "num",
        polls: "num",
        visible: "num",
        casts: "num",
        jumps: "num",
    },
    lanefight_window: {
        pid: "num",
        window: "str",
        target: "num",
        noticed: "num",
    },
    lanefight_gate: {
        pid: "num",
        gate: "str",
        target: "num",
        margin: "num",
        why: "str",
    },
    lanefight_start: {
        pid: "num",
        phase: "str",
        target: "num",
        margin: "num",
        via: "str",
        with: "num",
        sync: "num",
        window: "str",
        human: "num",
    },
    lanefight_commit: {
        pid: "num",
        target: "num",
        margin: "mixed",
        role: "str",
    },
    lanefight_end: {
        pid: "num",
        phase: "str",
        reason: "str",
        hits: "num",
        took: "num",
    },
    lanefight_mistake: {
        pid: "num",
        kind: "str",
        ability: "str",
        target: "num",
        after: "num",
    },
    lanefight_abandon: {
        pid: "num",
        why: "str",
        since: "num",
        mode: "str",
        ally: "num",
        amode: "str",
        atk: "str",
        dist: "num",
        range: "num",
        lastatk: "num",
    },
    lanefight_recheck: {
        pid: "num",
        reason: "str",
        pass: "num",
        margin: "num",
        after: "num",
    },
    lanefight_abort: {
        pid: "num",
        phase: "str",
        reason: "str",
    },
    lanefight_call: {
        pid: "num",
        target: "num",
        said: "num",
        pinged: "num",
    },
    rune_skip: {
        pid: "num",
        spawn: "num",
        target: "num",
        status: "num",
        raw: "num",
        desire: "num",
        laning: "str",
        gate: "str",
    },
    tr_rotate: {
        pid: "num",
        spawn: "num",
        go: "bool",
        side: "str",
        leaveAt: "num",
        reason: "str",
        enemies: "num",
        ours: "num",
    },
    tr_rune_hold: {
        pid: "num",
        spawn: "num",
        state: "str",
        reason: "str",
        mid: "num",
    },
    /** Slice threat: one consumer's decision on a threat read (threat.ts Log): consumer, decision (`go`, or since oha-safe-rest the trip gate's Safe.At
     *  reason when it held: `kill`, `tower`, `unknown`; older logs `threat`, `missing`), place, horizon (s), threat,
     *  band, heroes in reach and their pids, burst (share of HP), allies in reach, tower, missing weight sum, its pids and the
     *  longest unseen (s), mcut the unseen heroes dropped because the walk within their reach is in sight, the bot's HP share;
     *  dep the place's depth between the teams' towers (0 ours, 1 theirs), which scales the belief. */
    threat: {
        pid: "num",
        who: "str",
        dec: "str",
        x: "num",
        y: "num",
        hz: "num",
        dep: "num",
        threat: "num",
        band: "str",
        reach: "num",
        rpid: "str",
        burst: "num",
        ally: "num",
        esc: "bool",
        tower: "bool",
        miss: "num",
        mpid: "str",
        mtss: "num",
        mcut: "num",
        hp: "num",
    },
    /** Slice retreat (retreat.ts): one start and one end per episode of our retreat, and one start per plain walk (kind
     *  plain: heroes our retreat does not own). Start: why (threat, lethal, tower, heal, forced), the read at entry (thr, band,
     *  reach, burst, tower; budget, unp and the old purpose-budget are retired), the safe-here answer that decided it (lv, ra, kill), the work it left (purp), the anchor kind, its route cost and the next-best anchor's (alt), and
     *  for a forced drill rep the start spot. End: res (gone: nobody in reach; safe: a place Safe.At does not call deadly for a fresh place; healed: a heal walk back over HealBack with the lane nearer than the fountain; anchor, died, cut), secs, HP lost (hpl, share of max), whether the
     *  walk passed enemy tower (twr) or wave (wave) reach, hero damage taken (dmgh, share of max). ph=skip: a drill rep the
     *  cast started under the low-HP bar (healed instead). ph=read: an owned hero out of an episode whose read changed band
     *  (the chase drill grades the band on reps with no entry), with crp: an enemy creep hit it in the last second. ph=stay:
     *  once per spell, a deadly place the hero stays in for a hit back or a join (`why`), with the answer (lv, ra, kill). */
    retreat: {
        /** `start` or `end` of an episode, `read` (a band change out of an episode), `stay` (once per spell a hit back or join holds the hero in a deadly place), `skip`, `items`, `use`, `items_off`. */
        ph: "str",
        pid: "num",
        /** `plain` for a walk by a hero our retreat does not own; else our episode. */
        kind: "str",
        /** The episode number. */
        ep: "num",
        /** On `start`: `threat`, `lethal`, `tower`, `heal` or `forced`. On `stay`: `join` while our pair joins the fight (`Ours.PairJoin`), `hitback` while Trade.Holds says the hit back runs. Older logs: `stand`, or absent for the retired RetreatOdds hold. */
        why: "str",
        /** The hero's HP share at the line. */
        hp: "num",
        /** On `start` and `stay`: the safe-here answer's level, HP over kill line (absent with nobody in reach) and kill line in HP. */
        lv: "str",
        ra: "num",
        kill: "num",
        /** The read's threat. */
        thr: "num",
        /** The read's band at the line; `ph=read` is logged on a band change. */
        band: "str",
        /** Enemy heroes able to reach the hero within the read's horizon. */
        reach: "num",
        /** Allies the read counts (not in retreat, able to reach us within its horizon). */
        al: "num",
        /** Their estimated damage over the hero's HP. */
        burst: "num",
        /** The reaching heroes counted as engaged (hitting us within a second) by the read. */
        eng: "num",
        /** RetreatOdds (start, stay): the engaged heroes with none of our lane creeps within creep aggro of them. */
        unp: "num",
        /** 1 when an enemy tower's reach covers the spot. */
        tower: "bool",
        /** 1 when the read sees an escape. */
        esc: "bool",
        /** The retreat's budget. */
        budget: "num",
        /** The budget's purpose. */
        purp: "str",
        /** The chosen anchor's kind. */
        anchor: "str",
        /** Its route cost. */
        cost: "num",
        /** The next-best anchor's cost. */
        alt: "num",
        /** The chosen anchor's exposed route points, the least on any anchor (a route around exists when it is lower), and 1 when a healing item is held. */
        exp: "num",
        minexp: "num",
        regen: "bool",
        /** Distance to the anchor. */
        dist: "num",
        /** In a drill, the forced start spot. */
        spot: "str",
        /** In a drill, the rep. */
        rep: "num",
        /** On `end`: `gone` (nobody in reach), `safe` (the band's dwell), `healed` (older logs only: the retired HealStop), `anchor`, `died` or `cut`. */
        res: "str",
        /** Seconds the episode lasted. */
        secs: "num",
        /** HP lost during the episode, as a share of max. */
        hpl: "num",
        /** 1 when the walk passed enemy tower reach. */
        twr: "bool",
        /** 1 when the walk passed enemy wave reach. */
        wave: "bool",
        /** Hero damage taken, as a share of max. */
        dmgh: "num",
        /** On `ph=read`: 1 when an enemy creep hit the hero in the last second. */
        crp: "bool",
        /** Older logs only (the retired HealItems, ph=items, use, items_off): HP to HealBack, the usable heal items, the set used (or the item, on use), what it restores, a tree near, why not. */
        need: "num",
        held: "str",
        set: "str",
        got: "num",
        tree: "bool",
        skip: "str",
        ed: "num",
        ets: "num",
        x: "num",
        y: "num",
    },
    tr_caution: {
        pid: "num",
        level: "num",
        alone: "bool",
        missing: "num",
        lane: "num",
    },
    tr_tp: {
        team: "num",
        enemy: "num",
        x: "num",
        y: "num",
        remaining: "num",
    },
    tr_tp_react: {
        pid: "num",
        enemy: "num",
        mode: "str",
        lane: "num",
        until: "num",
    },
    tr_ward: {
        pid: "num",
        lane: "num",
        result: "str",
        dist: "num",
    },
    tr_ward_go: {
        pid: "num",
        key: "str",
        x: "num",
        y: "num",
    },
    farm_gate: {
        pid: "num",
        why: "str",
        lvl: "num",
        hp: "numstr",
        mode: "str",
        lane: "num",
        dist: "num",
        left: "numstr",
        camp: "num",
        window: "numstr",
        best: "numstr",
        open: "num",
        pace: "numstr",
    },
    /** One last-hit or deny attempt by a bot whose laning body owns its last hits (`laneFarm`). Read by `@lh_swings`, `@lasthit_cores` and `@support_hits`. */
    lh: {
        pid: "num",
        /** `lasthit` or `deny`. */
        kind: "str",
        /** `ok` or `fail`. */
        result: "str",
        /** The engine verb's end reason: `missed`, `taken_by_other`, `denied`, `interrupted`, `timeout`, ... A creep gone at the landing with no attack fired is `taken_by_other`; `missed` means it was alive at the landing or our attack fired and did not kill it. */
        reason: "str",
        ranged: "bool",
        eta: "num",
        contested: "bool",
        /** Reachable last hits and denies offered at this attempt's pick. */
        ol: "num",
        od: "num",
        /** The most last hits other than this attempt's creep offered while it waited to swing. */
        ow: "num",
        /** At the pick: seconds to walk into attack range, and until the others kill the creep (laneTargets facts). */
        walk: "num",
        dies: "num",
        /** A support's claim on the creep (states/lane_claims): `deny`, `free` (no core near enough), `busy` (its core in an attempt on another creep). */
        claim: "str",
        /** The creep's place at the end (alive), or at the last scan that offered it (dead): `ca` seconds since it was read (0 alive). */
        cx: "num",
        cy: "num",
        ca: "num",
        /** 1 when this bot pre-hit the creep earlier (states/pre_hit): last hits per pre-hit. */
        ph: "bool",
        /** A core's first attempt reported after it left a deny to the allied support (this pid) whose laning body was in an attempt on it (Ours.CoreDenyYield). */
        yd: "num",
        /** A deny: the pre-deny swings this bot spent on the creep before it (states/idle_swing); absent for none. */
        pre: "num",
        /**
         * Ours.CoreContest: 1 when the attempt was a melee core's walk-in past MAX_WALK; `cc` its priced
         * HP (% of max) at the pick, `cn` the enemy heroes whose reach covered the creep, `dh` HP-% lost from the pick to the end.
         */
        cw: "bool",
        cc: "num",
        cn: "num",
        dh: "num",
        /** The verb's message. Before any swing: `w=<s waited> why=range|cd|hp50|wait|start`; ` sw=1` when the body dropped the attempt for another creep, ` sw=0` when its creep was no longer offered and nothing else was; a swing ends `end= dt= fa= lhp= fg=` and may carry `obs idps ew er ec oc`. Unpacked by `@lh_swings`. */
        msg: "str",
    },
    /**
     * Ours.CoreContest: a walk-in the price refused, once per creep and reason. at pick (not started) | walk (a running
     * walk-in released); why cost | hp | two | tower (states/contest PriceOf); cc the priced HP (% of max), n the enemy heroes
     * covering the creep, ex seconds inside the deepest reach, walk dies the laneTargets facts, hf the core's HP share.
     */
    contest_skip: {
        pid: "num",
        at: "str",
        why: "str",
        cc: "num",
        n: "num",
        ex: "num",
        walk: "num",
        dies: "num",
        hf: "num",
    },
    /**
     * Slice lane-control 2a (shadow; design 2026-11-06-lane-controller s5.9): kind=wave once per wave per team and lane at
     * cycle second LaneControl ReadAt, kind=chk LaneControl Horizon s after it. wave the 30 s cycle's spawn second (joins a
     * chk to its decision); mode safe|shove; rule R1-R6 (s5.1); tgt the target point (from our T1 along the lane); own mv st
     * the lane push reading now (st OUT|HOLD|IN); need own + mv - tgt (the design's 30 s need); m45 the plain forecast's clash
     * at Horizon (from our T1), p45 the same with this wave pulled (lane_push WaveGoneFrom), pe the pull's predicted effect
     * PullScale x (p45 - m45), n45 m45 - tgt (the need the levers are chosen on); intent back|hold|forward|reset; lever the
     * chosen set joined by + (none), who each one's owner (pid, core, sup, both), left the chosen set's predicted clash past
     * the target, short 1 when no set reached the band; rej lever:why for each unusable lever; core sup the present laners'
     * pids; dep seconds to the support's next departure; away 1 when their laners are known dead or elsewhere (R5); why a
     * decision with no reading; ms the reading's cost. Slice 4a: pby who the pull lever went to (sup|core; absent with no
     * puller), cwhy why the offlane pos3 did not take it (missing|loss|no_plan), cmiss the enemy heroes missing near its walk
     * to the hard camp (CoreCamp MissingOf; under Ours.Threat the belief's counted heroes when their weight refuses, else 0), cmw
     * the belief's weight sum (Ours.Threat only), closs the lane gold it would lose while away (CoreCamp LossBetween). The missing wave:
     * ew the enemy wave tracker's resolution taken at this read (enemy_wave.ts: one enemy wave followed at a time, its
     * scheduled spot walked to our lead creep, resolved ArriveWindow s after it came due): p present (the visible enemy lane
     * creep count rose RiseMin over its count before the window), a absent (no rise, and our lead creep stood at the spot
     * for half the window: pulled, blocked or cut), u unknown (nobody there to see, the wave never came due, or nothing
     * resolved since the last read); ewd that wave's seconds from spawn to due (absent when it never came due). ewp only on
     * an `a` read with SkipPullOnMissingWave whose pull was on offer (rej pull:ew): 1 when Choose with the pull on offer would
     * have taken it (the skip changed the set), 0 when the model refused it anyway; a pull refused for its own reason keeps
     * that reason and no ewp. kind=break why=ew: an absent resolution between reads took this wave's live decision's pull
     * (and the core's hold beside it) before the pull job's slot settled; the job then refuses `why=ew`.
     */
    lane_ctl: {
        team: "num",
        lane: "num",
        /** `wave` (once per wave per team and lane at cycle second 2), `chk` (45 s later, the reading then; `wave` joins them) or `break` (a `shove` decision broke before its wave ended; `why` `enemy` or `core_low`). */
        kind: "str",
        /** The 30 s cycle's spawn second; joins a `chk` to its decision. */
        wave: "num",
        /** `safe` or `shove`. */
        mode: "str",
        /** The ruleset row that set the mode (R1-R6; R4 not built). */
        rule: "str",
        /** The target point, distance from our T1 along the lane. */
        tgt: "num",
        /** The lane push reading: the clash's distance from our T1 now. */
        own: "num",
        /** The lane push reading: the clash's move over the horizon. */
        mv: "num",
        /** The lane push reading's state: `OUT`, `HOLD` or `IN`. */
        st: "str",
        /** `own` + `mv` - `tgt`. */
        need: "num",
        /** The plain forecast's clash at the horizon, from our T1. */
        m45: "num",
        /** The same forecast with this wave pulled (`WaveGoneFrom`). */
        p45: "num",
        /** The pull's predicted effect: `PullScale` x `DivertShare` x (`p45` - `m45`). */
        pe: "num",
        /** `m45` - `tgt`: the need the levers answer. */
        n45: "num",
        /** `back`, `hold`, `forward` or `reset` (a support departure within 60 s). */
        intent: "str",
        /** The chosen set joined by `+` (`pull+hold`, `predeny`, `setup`, `none`, ...). */
        lever: "str",
        /** Each lever's owner: pid, `core`, `sup` or `both`. */
        who: "str",
        /** The clash past the target predicted after the chosen set. */
        left: "num",
        /** 1 when no set reached the band. */
        short: "bool",
        /** The harness's forced lever (Overrides.ForceLever: `feed`, `setup`, `none`); absent when none is forced. */
        frc: "str",
        /** `lever:why` for each unusable lever (`pull:away`, `pull:stack`, `pull:ew`, ...). */
        rej: "str",
        /** The present core laner's pid. */
        core: "num",
        /** The present support laner's pid. */
        sup: "num",
        /** Seconds to the support's next leave on its own calendar (`Calendar.NextLeave`). */
        dep: "num",
        /** The pull window against that calendar: `free`, `fits`, or `clash:<kind>` (`stack` or `rune`). */
        fit: "str",
        /** The stack minute the pull took. */
        yld: "num",
        /** Who the pull lever went to: `sup` or `core`; absent with no puller. */
        pby: "str",
        /** Why the offlane pos3 did not take the pull: `missing`, `loss` or `no_plan`. */
        cwhy: "str",
        /** Enemy heroes missing near the pos3's walk to the hard camp. */
        cmiss: "num",
        /** The missing belief's weight sum (`Ours.Threat` only). */
        cmw: "num",
        /** The lane gold the pos3 would lose while away. */
        closs: "num",
        /** 1 when their laners are known dead or elsewhere (rule R5). */
        away: "bool",
        /** Why a decision has no reading. */
        why: "str",
        /** The reading's cost in milliseconds. */
        ms: "num",
        /** The missing enemy wave's resolution: `p` (present: arrived), `a` (absent: did not, with our creeps there to see) or `u` (unknown). */
        ew: "str",
        /** On an `a` read whose pull was on offer: 1 when the choice without the skip would have held the pull. */
        ewp: "num",
        /** Seconds from the missing wave's spawn to its due second at our lead creep. */
        ewd: "num",
    },
    /**
     * An owned laner's idle swing (states/idle_swing): one attack when the picker had no last hit, deny or pre-hit to offer.
     * `kind` predeny (our creep under half HP that no enemy hero reaches before our hits kill it) or shove (an enemy creep outside
     * their tower), `mode` the lane's mode (`safe`, or `shove` forced by Overrides.ForceShove). `result` ok once the attack fired.
     * At the pick: `walk` (s), the creep's `hp` and fraction `hf`; predeny: our kill time `kill` (s, absent past the horizon), the
     * nearest enemy hero's reach `reach` (s, -1 none near), `focus` 1 when an allied hero was already hitting it. `dn` / `lh` 1
     * when this bot's deny / last-hit count rose during the swing (the swing took the creep itself).
     */
    idle_swing: {
        pid: "num",
        /** `predeny`, `setup` or `shove`. */
        kind: "str",
        /** predeny and setup: this bot's ok swings on the creep before this one (0: its first; a new creep starts at 0). */
        n: "num",
        /** The creep's place at the pick. */
        cx: "num",
        cy: "num",
        /** The lane's mode: `safe` or `shove`. */
        mode: "str",
        /** `ok` once the attack fired. */
        result: "str",
        /** The attack verb's end reason. */
        reason: "str",
        ranged: "bool",
        /** Seconds to walk into range at the pick. */
        walk: "num",
        /** The creep's HP at the pick. */
        hp: "num",
        /** The creep's HP fraction at the pick. */
        hf: "num",
        /** Our kill time in seconds; absent past the 6 s horizon. */
        kill: "num",
        /** The nearest enemy hero's walk into range plus attack point in seconds; -1 none within 1,600. */
        reach: "num",
        /** 1 when an allied hero was already hitting the creep. */
        focus: "bool",
        /** setup: our hits to the kill at the pick, this swing included. */
        hits: "num",
        /** The creep's id (Telemetry CreepId), the same as on its ev=creep_death. */
        cid: "num",
        /** 1 when this bot's deny count rose during the swing. */
        dn: "bool",
        /** 1 when this bot's last-hit count rose during the swing. */
        lh: "bool",
        contested: "bool",
        /** The attack verb's message. */
        msg: "str",
    },
    /** A core's pre-hit on an enemy creep our tower is attacking (states/pre_hit): one per attempt. */
    prehit: {
        pid: "num",
        /** ok once our attack fired (attackAndConfirm), fail missed / no_target (the creep died first) / interrupted / dead. */
        result: "str",
        reason: "str",
        ranged: "bool",
        /** At the decision: walk into range (s), when the forecast has the creep dead (s), its HP, our earliest landing t0 (s), our low-roll damage. */
        walk: "num",
        dies: "num",
        hp: "num",
        t0: "num",
        lo: "num",
        /** The plan (states/pre_hit Plan): pre-hits before the kill, the kill's landing (s), the HP it lands on and its margin from the kill range's edges. */
        np: "num",
        tk: "num",
        hk: "num",
        mg: "num",
        /** Reachable last hits offered at the pick. */
        ol: "num",
        contested: "bool",
    },
    /**
     * Forecast probe after a pre-hit `go` (states/pre_hit): the creep's real HP on later scans (`hs`, "s:hp" from the decision)
     * beside the forecast's (`fs`, spread, without our hit) until it dies (`dead`, `end` s) or 2.5 s pass. At the decision:
     * `hp`, our low roll `lo`, the tower's hit after armour `tw` and `GetSecondsPerAttack` `twp`, the forecast's own tower hit
     * `td`, its known hits within 1 s by kind (`kt` tower, `kc` creep, `kh` hero, `ks` self), unphased attackers `nu` and their
     * DPS `ud`, and our lane creeps `ac` and other own heroes `ah` attacking the creep; `fdies` the forecast's death time.
     */
    prehit_fc: {
        pid: "num",
        hp: "num",
        lo: "num",
        tw: "num",
        td: "num",
        twp: "num",
        kt: "num",
        kc: "num",
        kh: "num",
        ks: "num",
        nu: "num",
        ud: "num",
        ac: "num",
        ah: "num",
        end: "num",
        dead: "bool",
        fdies: "num",
        hs: "str",
        fs: "str",
        fire: "str",
    },
    /**
     * An enemy hero hit this in-lane hero within 1 s and no exchange opened (states/trade): at most one per hero per 5 s.
     * `why` is the answer's reason: the first gate that failed (`tower`, `burst`, `hp`, `lost`, `unfavoured`, `no_reach`, `deny`,
     * `creeps`, `wave`, `missing`, `catch`) or `no_target`. Logs of builds before the one trade decision carry the older respects
     * (`outnumbered`, `low_hp`, `behind`, `gap`, `hb_<respect>`).
     */
    trade_no: {
        pid: "num",
        role: "str",
        why: "str",
        /** The nearest hero that hit us: its pid, distance, attack range, HP fraction; `agg` 1 with one of our lane creeps within creep aggro of it. */
        tgt: "num",
        d: "num",
        reach: "num",
        har: "num",
        agg: "num",
        hp: "num",
        thp: "num",
        /** As `ev=trade`: heroes within 1200, enemy lane creeps within 500, enemy units attacking us. */
        en: "num",
        al: "num",
        cr: "num",
        hc: "num",
        mode: "num",
        md: "num",
    },
    /**
     * Slice join-after (D19, shadow): after a taken `join` or `trade` window of ours ends, PairJoin's weighing read once a second
     * for `PairJoin.SETTINGS.AfterWindow` s with no hit needed (the bot as the hit ally), so the banked logs say whether the
     * fight still favoured us when it ended, and for how long. One line per window, at its end. Reads only.
     */
    join_after: {
        pid: "num",
        /** The ended window's `ev=trade` kind (`join` or `trade`), end reason (`why`) and target pid. */
        kind: "str",
        why: "str",
        tgt: "num",
        /** How the watch ended: `full` (the whole window), `reopen` (any trade window started: hit, hit back, kill or join), `dead` (the bot died, or a missed sample showed it had), `stage` (past the laning stage). */
        res: "str",
        /**
         * The samples, `;`-joined, each `dt:dec:ko:kt:thp:d:hp:no:nt`: seconds since the end; PairJoin's answer (`j` join, `l`
         * losing, `o` outnumbered (older logs only), `n` no enemy hero seen within FoeRange); our and their best kill share (3 places); the ended
         * window's target's HP share and distance (-1 when unseen or dead); our HP share; our heroes and theirs in the weighing
         * (ours not in retreat, the bot included).
         */
        s: "str",
    },
    /** One per in-lane exchange (states/trade): taken (`done`, `kill`) or offered and not taken (`lost`). */
    trade: {
        pid: "num",
        /** `core` or `support` by position, logged and never read. */
        role: "str",
        /** Older logs only (the lane-fight switches): 1 when the laner's lane fights were ours. */
        lf: "num",
        /** `hit`, `hitback`, `kill` or `join` (a lane fight from the play roll is a join on its play). Older logs: `trade`, `kill`, `fight` or `join`. */
        kind: "str",
        /** The target hero's pid. */
        tgt: "num",
        /** 1 for a hit back (the level `hitback`); older logs: a hit back taken as a trade. */
        hb: "num",
        /** A `fight`'s play id (`ev=play` id) and 1 when the hero joined another hero's play, 0 when it rolled its own. */
        play: "num",
        join: "num",
        /** `done` (taken), `kill` (the game says the target died, `IsHeroAlive`) or `lost` (offered, not taken within 1 s; `mode`/`md` is the mode that held the core). */
        result: "str",
        /** How the window ended. A `fight`'s `why` adds `hp` (under the roll's HP floor), `play_end` and `time`; a `join`'s is `pair_end` (PairJoin no longer joins), `retarget` or `time`; any other kind ends `pair_join` when a join on another hero takes over. A `trade`'s adds `hold_time` (slice trade-lands: a deny or join on another hero waited for the first attack and 4 s since the start ran out; a fault). */
        why: "str",
        /** Seconds the window lasted. */
        dur: "num",
        /** HP the bot and the target lost from the trade's start to its end. */
        hpd: "num",
        thpd: "num",
        /** Slice trade-landed: seconds from the start to the bot's first hit on the target (an attack fired at it, by
         *  GetLastAttackTime); absent when none did. */
        ld: "num",
        /** Inputs when the window opened: HP fractions, heroes within 1200, enemy lane creeps within 500. */
        hp: "num",
        thp: "num",
        en: "num",
        al: "num",
        cr: "num",
        /** Aggro-free attacks (EC-053): attack orders given clear of creeps, steps out of them, most enemy creeps on the core at once. */
        pr: "num",
        so: "num",
        ag: "num",
        /** The episode's first act: `step` (a step out of the creeps before any attack order) or `order` (an attack order
         *  first); absent when Think never acted (the target unseen, or not taken). */
        fa: "str",
        /** Slice trade-count: 1 when the end's reason `why` already held when the exchange opened (a gate of some level failing on the open's inputs read fresh, or `no_clear` with `fa` `step`), 0 when it came later; absent for an end that can only come later (target dead or lost, `losing`, `pair_end`, a mode took the hero...). Read-only. */
        ato: "num",
        /** The bot's active mode at the end, and its desire. */
        mode: "num",
        md: "num",
    },
    job_exec: {
        pid: "num",
        kind: "str",
        camp: "num",
        result: "str",
        reason: "str",
        msg: "str",
        label: "str",
        sdk: "num",
        legacy: "num",
    },
    wisdom_gate: {
        pid: "num",
        spawn: "num",
        why: "str",
    },
    rune_trip: {
        pid: "num",
        pos: "num",
        spawn: "num",
        side: "str",
        result: "str",
        msg: "str",
        label: "str",
        left: "num",
        arrived: "num",
        away: "num",
    },
    wisdom: {
        pid: "num",
        pos: "num",
        spawn: "num",
        result: "str",
        reason: "str",
        label: "str",
        left: "num",
        arrived: "num",
        taken: "num",
        away: "num",
    },
    // Slice rune-rotation: one line per rune trip or skip (RuneJob). res ok|fail|skip; why: the verb's end reason or the
    // skip's gate; arr: when the bot reached the spot (wait or channel label); died: dead at the trip's end.
    // Slice rune-spawn (6:00 trip under the spot plan): why plan-other (a skip: the plan gave the other spot to the mid or the
    // other support); phase the act at the spawn (take, deny, off, cross, none); ta / te our and the soonest enemy hero's
    // seconds to the rune's spot at the decision; hid seconds hidden at the stand; sh / sph the stand's and the spot's
    // GetHeightLevel; play the id of the play this trip ran on (kind contest: the shrine roll that sent it; power: a rune
    // fight), gank the id of the gank rolled after it (ev=play / ev=play_end carry their rolls and results). Kind contest:
    // pos5 to the enemy wisdom shrine at 7:00 on a fired shrine roll (skip why roll / busy otherwise).
    // Slice rune-spawn: one line when a hero starts ordering a rune pickup (res try) and one when that try ends: gone (the rune
    // left the spot), left (the hero walked off, or ordered another rune), gave_up (RunePickup GiveUpAfter s of orders within
    // Near with the rune still available: unpickable for the team until the next river spawn). d distance to the spot; act0 and
    // act the hero's current action type at the first order and now; st GetRuneStatus; dt seconds since the first order.
    // Slice rune-spawn, library plays: one line per chance offered (Plays.Roll), fired or not. w the weight after the hard
    // zeros and MaxWeight; fl fc fh fr ft ff the level, count, HP-and-mana, power-rune, tower and forecast factors; al/en our
    // and their heroes within Radius of the place (initiator and target always counted); fth the target-HP factor; zero the
    // hard zero (hp, outnumbered, tower, unknown-kind, or the kind's own), in-play (the initiator is already in a play) or
    // no-rng (a positive weight with no engine Skill rng: no draw); sure the kind's sure-tier reason (the play commits with no
    // weighted roll) and pc its commit chance at the initiator's skill (Curve SureCommit; 1 at skill 1: no draw); draw the
    // Skill draw (against pc for a sure chance, else w); fire 1 when the play fired; id the play.
    play: {
        pid: "num",
        /** The play's kind. */
        kind: "str",
        /** The target. */
        tgt: "num",
        /** The weight after the hard zeros and `MaxWeight`. */
        w: "num",
        /** Level factor. */
        fl: "num",
        /** Count factor. */
        fc: "num",
        /** HP-and-mana factor. */
        fh: "num",
        /** Power-rune factor. */
        fr: "num",
        /** Tower factor. */
        ft: "num",
        /** Forecast factor. */
        ff: "num",
        /** Target-HP factor. */
        fth: "num",
        /** Our heroes within `Radius` of the place. */
        al: "num",
        /** Their heroes within `Radius` of the place. */
        en: "num",
        /** The hard zero: `hp`, `outnumbered`, `tower`, `unknown-kind`, the kind's own, `in-play` or `no-rng`. */
        zero: "str",
        /** The sure tier's reason (the play commits with no weighted roll). */
        sure: "str",
        /** The sure tier's commit chance at the initiator's skill. */
        pc: "num",
        /** The `Skill` draw, against `pc` for a sure chance, else `w`. */
        draw: "num",
        /** 1 when the play fired. */
        fire: "num",
        /** The play's id. */
        id: "num",
    },
    // One line per fired play's end (Plays.End): res kill (target dead with a play hero within KillNear, up to KillAfter s
    // after the end) | trade (target and initiator dead) | died | forced (target under ForcedHp or moved ForcedMoved) | none,
    // or the consumer's own; written up to KillAfter s after the end (dur stays the play's own length); why the consumer's end reason or timeout (Plays.Tick); join heroes that joined; dur seconds.
    play_end: {
        /** The play's id. */
        id: "num",
        pid: "num",
        kind: "str",
        tgt: "num",
        /** `kill`, `trade`, `died`, `forced` or `none`, or the consumer's own. */
        res: "str",
        /** The end reason (`timeout`, `timeout:no-kill`, `interrupted:escaped`, `interrupted:hp`, `trip:preempted:mode=N`, ...). */
        why: "str",
        /** Heroes that joined. */
        join: "num",
        /** The play's own length in seconds. */
        dur: "num",
    },
    // Slice rune-spawn: the team's 6:00 plan, once per team at RunePlan PlanAt and again each time a planned support's start
    // gate drops it: mid / sup the planned heroes' pids, ms / ss their spots' rune ids; why no-free-support, no-near-support (a free support is nearer the mid's spot) or no-mid when a
    // side is empty, swap:<gate> when the spot went to the other support, drop:<gate> when no support was free for it.
    /** Probe (slice world-facts): the live API value beside the constant a context still holds; once per fact and team per game. */
    world_fact: {
        team: "num",
        /** `fountain_x`, `fountain_y` (the home shop's place against retreat's fountain constant), `tower_reach`, `tower_range`, `hero_radius`, `lane_creep_speed`, `neutral_speed`, `neutral_speed_<small|medium|large|ancient>` or `lane_t1_<lane>_<team>` (a T1's place along its lane path; constant the 7.41 data's); `attack_period` and `attack_point` are fallbacks logged on first use. */
        fact: "str",
        /** The shared `WorldFacts` read; -1 for a fallback a caller took. */
        live: "num",
        /** The old constant (for a fallback, the value used). */
        constant: "num",
        /** Times a reader returned its constant so far (a failed read, or `Latest` asked before the first read). */
        fell: "num",
    },
    /** The team's 6:00 rune plan, once at plan time and again each time a planned support's start gate drops it. */
    rune_plan: {
        team: "num",
        /** The mid's pid. */
        mid: "num",
        /** The mid's spot, as rune id (0 top, 1 bot). */
        ms: "num",
        /** The planned support's pid. */
        sup: "num",
        /** The support's spot, as rune id. */
        ss: "num",
        /** `no-free-support`, `no-near-support` (a free support is nearer the mid's spot) or `no-mid`; later `swap:<gate>` (the other support took it) or `drop:<gate>` (none free). */
        why: "str",
    },
    /** One line when a hero starts ordering a rune pickup (`res=try`) and one when the try ends (`gone`, `left`, `gave_up`). */
    rune_try: {
        pid: "num",
        rune: "num",
        /** `try`, `gone` (the rune left the spot), `left` (the hero walked off or ordered another rune) or `gave_up` (`GiveUpAfter` seconds of orders within range with the rune still available). */
        res: "str",
        /** Distance to the spot. */
        d: "num",
        /** The hero's current action type at the first order. */
        act0: "num",
        /** The hero's current action type now. */
        act: "num",
        /** `GetRuneStatus`. */
        st: "num",
        /** Seconds since the first order. */
        dt: "num",
    },
    // Slice core-next-gold (CoreCamp): an in-lane core's camp trip. phase start, next (a chained camp), refuse (the camp found
    // priced past the trip's budget at sight or engage, CoreCamp admits: its plan price hpc/clr, the live price hpe/clre, hp,
    // hpr, pace, lvl; the core walks back), skip (a camp fitted and a
    // gate held it: one line per wave window `win` and why), end. clash: the forecast's next clash second; ret: the planned
    // return; clr: clear estimate; gold, loss (forecast lane gold lost by the return), net; end: back (arrival), g0/g1 net worth;
    // nmiss (skip or nexthold why=missing): enemy heroes unseen that could be at the camp or on the walk, mtss the longest of
    // their time_since_seen (s, rounded), mpid their player ids (comma list). nexthold: a chained camp after a clear held by a
    // start gate (why: the gate; after: how the last camp ended), the core walks back. nocamp (one per core, minute and why,
    // while the no-camp gate holds): lvl, ncand (camps in the trip list), noff (enemy camps among them), camp/type/cd (the
    // nearest trip camp and its distance to the lane front), why (what dropped it: far, cleared, empty, pulled, ally,
    // trip, reserved), near/nd/nwhy=list (the nearest camp of any team, when it is not in the trip list). clre/hpe (end, next,
    // nexthold): the model's clear seconds and HP fraction for the neutrals the core met at engage, before the learned factors
    // (what pace and HP rate learn against; absent when none was seen at engage).
    core_camp: {
        pid: "num",
        pos: "num",
        lane: "num",
        /** `start`, `next` (a chained camp), `skip`, `nexthold`, `nocamp`, `gates`, `refuse`, `admit` (drills only) or `end`. */
        phase: "str",
        /** The forecast's next clash second. */
        clash: "num",
        /** The wave window, `clash` / 30. */
        win: "num",
        /** The camp's spawner index. */
        camp: "num",
        /** The camp's type. */
        type: "str",
        /** The planned return second to the clash point. */
        ret: "num",
        /** The clear estimate in seconds with the core's pace. */
        clr: "num",
        /** The clear's HP cost as a fraction of max HP, with the core's learned HP rate. */
        hpc: "num",
        /** Where the clear model's neutrals came from: `live`, `seen` or `table`. */
        src: "str",
        /** The type table's clear seconds, logged to compare with the model. */
        clrt: "num",
        /** The type table's HP cost, logged to compare with the model. */
        hpt: "num",
        /** Measured: seconds from engaging the last camp to clearing or leaving it. */
        clrm: "num",
        /** Measured: HP fraction lost there. */
        hpm: "num",
        /** The model's clear seconds for the neutrals met at engage, before the learned factors. */
        clre: "num",
        /** The model's HP fraction for the neutrals met at engage, before the learned factors. */
        hpe: "num",
        /** Count of the priced neutrals. */
        n0: "num",
        /** Each priced neutral as `name/hp/damage/seconds per attack/share of a physical hit taken`. */
        nu: "str",
        /** Neutrals still seen alive there when it left. */
        nl: "num",
        /** The camp's gold. */
        gold: "num",
        /** The forecast's lane gold lost by the return: enemy lane creeps the run kills until `ret`, times 40 gold and the core's 0.5 share. */
        loss: "num",
        net: "num",
        /** On `skip`/`nexthold`: the gate that held it (`enemy-near`, `hit`, a higher job's name, `mate-job`, `rune`, `threat`, `missing`, ...). On `nocamp`: what dropped the camp (`far`, `cleared`, `empty`, `pulled`, `ally`, `trip`, `reserved`; `none` for an empty list). On `end`: how it ended (`back`, `wave`, `interrupted:threat`, `interrupted:hp`, `timeout:late`, `cancelled:<why>`, `dead`). */
        why: "str",
        /** Enemy heroes unseen that could be at the camp or on the walk. */
        nmiss: "num",
        /** The longest `time_since_seen` among them, rounded seconds. */
        mtss: "num",
        /** Their player ids as a comma list. */
        mpid: "str",
        /** The core's level. */
        lvl: "num",
        /** Camps in the core's trip list. */
        ncand: "num",
        /** Enemy camps among them (the offlaner's large camp). */
        noff: "num",
        /** The nearest trip camp's distance to the lane front. */
        cd: "num",
        /** The nearest camp of any team, when it is not in the trip list. */
        near: "num",
        /** That camp's distance. */
        nd: "num",
        /** `list`: why `near` is shown. */
        nwhy: "str",
        /** How the last camp ended: `cleared`, `empty`, ... */
        after: "str",
        res: "str",
        /** The task's step: `farm` or `return`. */
        label: "str",
        /** Camps taken in the trip. */
        camps: "num",
        /** Arrival second on the walk back; absent when it did not walk back. */
        back: "num",
        /** Net worth at the start. */
        g0: "num",
        /** Net worth at the end. */
        g1: "num",
        /** Seconds on the trip. */
        secs: "num",
        /** The core's learned clear pace (starts at 1). */
        pace: "num",
        /** HP fraction at the end. */
        hp: "num",
        /** The learned HP rate (starts at 1). */
        hpr: "num",
        /** On `gates`: the game minute (once a minute per core; the last laning minute is not written). */
        min: "num",
        /** Seconds the core was dead. */
        h_dead: "num",
        /** Seconds held by the mode gate. */
        h_mode: "num",
        /** Seconds held by the low-HP gate. */
        h_hp: "num",
        /** Seconds held by the far gate. */
        h_far: "num",
        /** Seconds held by the wave gate. */
        h_wave: "num",
        /** Seconds held by the no-camp gate. */
        h_camp: "num",
        /** Seconds held by the no-forecast gate. */
        h_fc: "num",
        /** Seconds held by the no-clash gate. */
        h_clash: "num",
        /** Seconds held by the gap gate. */
        h_gap: "num",
        /** Seconds held by the no-plan gate. */
        h_plan: "num",
        /** Seconds a camp fitted but a start gate held it. */
        h_skip: "num",
        /** Seconds on a trip. */
        h_trip: "num",
        /** On `admit`: the verdict, `hp`, `time` or `ok`. */
        v: "str",
        /** On `admit`: `LatestLeave`. */
        lb: "num",
    },
    /** One line per rune or wisdom trip (`Ours.RuneRotation`; OHA has none) or per trip it did not start (`res=skip`). View `rune_jobs` reads it. */
    rune_job: {
        pid: "num",
        /** The attempt id: a number unique per hero within a game, allocated when a decision goes (at the job start: a trip has no choice line) and shared by its `ev=job` lines. */
        aid: "num",
        /** The hero's lineup position. */
        pos: "num",
        /** `power`, `wisdom`, `contest` (the enemy shrine play's trip) or `water` (the mid's 2:00 and 4:00 trips, `Ours.MidWater`). */
        kind: "str",
        /** The rune's game time. */
        spawn: "num",
        /** `ok`, `fail` or `skip`. */
        res: "str",
        /** The `runeRun` verb's end reason (`ok`, `no_target:rune missing`, `timeout:late`, `preempted:mode=N`, `cancelled:retreat`, `cancelled:off`, `missed`) or, on a skip, the gate that held it (`late`, `low-hp`, `enemy-near`, `hit`, `busy`, `acting`, a higher job's name, `dead`, `refused`, `plan-other`). */
        why: "str",
        /** The verb's last label. */
        label: "str",
        /** `top` or `bot` (power). */
        side: "str",
        /** The second the trip started. */
        left: "num",
        /** When the bot reached the spot (the verb's `wait` or `channel` label). */
        arr: "num",
        away: "num",
        /** 1 when dead at the trip's end. */
        died: "num",
        /** 1 when hero damage landed during the job. */
        hit: "num",
        /** OHA idle relocations the job held. */
        idle: "num",
        /** The act at the spawn: `take`, `deny`, `off`, `cross` or `none`. */
        phase: "str",
        /** Our arrival, seconds from the spawn. */
        ta: "num",
        /** The soonest enemy's arrival, seconds from the spawn. */
        te: "num",
        /** Seconds hidden at the stand. */
        hid: "num",
        /** The stand's `GetHeightLevel`. */
        sh: "num",
        /** The spot's `GetHeightLevel`. */
        sph: "num",
        /** The contest route's waypoint count. */
        via: "num",
        /** `path` (Valve's `GeneratePath` walk) or `edge` (the map-edge route, taken when the path passes nearer than `TowerAvoid` to an enemy tower and nearer than the edge route). */
        route: "str",
        /** The route's least distance to an enemy tower. */
        vclr: "num",
        /** The path answer's age in seconds. */
        vage: "num",
        /** How far from the hero's start the path was asked. */
        voff: "num",
        /** Path answers dropped since the hero's last contest line, for not running from its start to the shrine. */
        vbad: "num",
        /** The waypoints as `x,y;x,y;...`. */
        vpts: "str",
        /** The id of the play this trip ran on. */
        play: "num",
        /** The id of the gank rolled after it. */
        gank: "num",
        /** A river-rune trip: both river spots as the API reported them when the pickup began (`rs0`) and at the trip's end
         *  (`rs1`), `RUNE_POWERUP_1` first, each `<GetRuneStatus>:<GetRuneType>`. */
        rs0: "str",
        rs1: "str",
        /** Where the hero stood at the trip's end. */
        x: "num",
        y: "num",
    },
    // Slice support-lane: one line per started pull (PullJob). res ok|fail; why: the verb's end reason (ok, timeout:late,
    // no_target:mistake:no-camp, ...) or the chooser's cancel; label: the verb's last label; slot: the planned hit second;
    // div: the largest share of our wave seen attacking a neutral during the watch (creeps within the watch radius of the meet
    // point or of the camp origin), n: that wave's size (0: never seen);
    // wd: the nearest any of our lane creeps came to the meet point during lead and watch, nn: the most neutrals seen within
    // MeetWatch (800) of it, where ev=pull_watch's nn uses WaveSize (1200) (n=0 with a large wd: the wave was not there in time; with nn=0: the neutrals were not).
    // dt: div's share kept sampling for PullJob TrailSec after the job (the wave goes on fighting once the puller has left;
    // the line is written when that trail ends, so `t` is up to TrailSec after the job end); absent on a failed job.
    // cn, cs, chp, cv, cdmg, php: the camp and the puller at the start, as on ev=choice (on a
    // cancelled:empty / cancelled:one / cancelled:camp-dmg line, at the walk's cancel instead). why cancelled:empty /
    // cancelled:one / cancelled:camp-dmg: the camp seen on the walk (CampRead CampGate, StartReserve); interrupted:bail: the puller stepped
    // back from neutrals hitting it too hard after the hit (label bail; PullJob BailReserve).
    // Slice pull-diag: sh the live shift the hit took (hit second = slot + sh; slice pull-timing: the wave's body against
    // the plan, which already holds the lane's WaveAhead; slice pull-live: read again every LiveEvery s up to the order, so
    // sh is the last before it), lv the live readings taken (0: sh is 0 because nothing was seen; before slice pull-live
    // 1 or 0), sf the shift the last reading's front creep alone would have given; ht the game time the verb's hit
    // was confirmed (label lead began; absent when it never got there). The camp's own neutrals are tagged at ht (in its
    // box, or attacking the puller within PullJob TagRadius); on them, sampled every PullJob WatchEvery to the trail's end:
    // g4 the first time one was past PullJob Left (400, EC-084: the give-up timer starts there), gh the farthest any came
    // from the camp origin, na the first time one came within PullJob Acquire of our lane creeps, gu the first time every
    // tagged neutral that went past Left was back PullJob HomeMargin from its own farthest point with no attack target (they
    // gave up; a chasing neutral out of attack range also reads no target, so movement decides), gd the nearest of them to
    // our lane creeps at gu, wa the first time a lane creep not already there at ht came within PullJob ArriveR of the meet
    // point.
    // Slice support-pull-farm (PullFarm): the support clearing its own pull's camp. phase start, skip (the window after an ok pull
    // closed with `why` the gate that held it) and end. ago: seconds from the pull's end to this line's decision, div: the pull's
    // diverted share then, n0 neutrals on the camp at the decision; end: nl neutrals left, back (arrival at the lane front),
    // g0/g1 net worth, secs on the job, hp0/hp share of max HP at start and end, died; ms madstone drops (dropped items named
    // *madstone*, PullFarm PickName) seen by the camp after the clear, mp of them gone from the ground after our pickup order.
    // The kills (PullFarm LastHit, user 06/11/2026): lh the support's last hits over the farm, lt the clear's waits for a killing
    // hit and lk those that got it; fl 1 when the camp's final neutral was the support's kill (0 not; none when the clear did
    // not end cleared), fd the support's distance to it then; mi madstone charges gained in its item slots over the farm.
    pull_clear: {
        pid: "num",
        pos: "num",
        lane: "num",
        /** `start`, `skip` or `end`. */
        phase: "str",
        camp: "num",
        /** Seconds from the pull's end to this line's decision. */
        ago: "num",
        /** The pull's diverted share then. */
        div: "num",
        /** Neutrals on the camp at the decision. */
        n0: "num",
        /** On `end`: `back`, `interrupted:yield|hp|threat`, `timeout:late`, `preempted:...`. On `skip`: the last gate that held it (`core-coming`, `core-there`, `no-neutrals`, `threat`, `camp-dmg`, `rune`, `stack`, `late`, `refused`). */
        why: "str",
        res: "str",
        label: "str",
        /** Neutrals left at the end. */
        nl: "num",
        /** Arrival second at the lane front. */
        back: "num",
        /** Net worth at the start. */
        g0: "num",
        /** Net worth at the end. */
        g1: "num",
        /** Seconds on the job. */
        secs: "num",
        /** HP share of max at the start. */
        hp0: "num",
        /** HP share of max at the end. */
        hp: "num",
        /** 1 when the support died. */
        died: "num",
        /** Madstone drops (dropped items named `*madstone*`) within 900 of the camp after the clear. */
        ms: "num",
        /** Of those, the ones gone from the ground after the support's pickup order. */
        mp: "num",
        /** The support's last hits over the farm. */
        lh: "num",
        /** The clear's waits for a killing hit. */
        lt: "num",
        /** Of those, the ones that got it. */
        lk: "num",
        /** 1 when the camp's final neutral was the support's kill, 0 when not; unset when the clear did not end cleared. */
        fl: "num",
        /** The support's distance to that neutral then. */
        fd: "num",
        /** Madstone charges gained in its item slots over the farm. */
        mi: "num",
    },
    /** Once a game: how each seeded lane pull camp (camps_data with `laneKind`) resolved, the pull's camp choice's input. */
    pull_camp_seed: {
        /** The camps_data entry. */
        key: "str",
        /** The nearest spawner of its type and team to the lane's tower (`ev=camp` `idx`); absent with none. */
        idx: "num",
        /** Its distance to that tower (the limit is `PullCampMaxTowerDist`, or the entry's `maxTowerDist`). */
        td: "num",
        /** Its distance to the lane (the limit is `PullCampMaxLaneDist`). */
        ld: "num",
        /** 1 when it became the entry's pull camp. */
        ok: "num",
    },
    /** One line per pull the support's pull job started (`Ours.SupportPull`). Views `pull_attempts`, `pull_waves` and `pull_watch_cases` read it. */
    pull_job: {
        pid: "num",
        /** The attempt id: a number unique per hero within a game, allocated when a decision goes and shared by its `ev=choice kind=pull go=1` and `ev=job` lines. */
        aid: "num",
        /** The puller's lineup position. */
        pos: "num",
        /** The lane pulled. */
        lane: "num",
        /** The camp's spawner index. */
        camp: "num",
        /** The planned hit second. */
        slot: "num",
        /** `ok` or `fail`. */
        res: "str",
        /** The `pull` verb's end reason (`ok`, `timeout:late`, `no_target:mistake:no-camp`, `*:mistake:no-aggro`, `*:lead`, `interrupted:bail`) or a cancel (`cancelled:<why>`: the chooser's, or `empty`, `one`, `camp-dmg`). */
        why: "str",
        /** The verb's last label: travel, wait, aggro, lead, watch or bail. */
        label: "str",
        /** The largest share of our wave seen attacking a neutral during the lead and watch (creeps within 800 of the meet point or the camp origin). */
        div: "num",
        /** That wave's size, counted when its first creep is seen on a neutral; 0 when none ever was. */
        n: "num",
        left: "num",
        away: "num",
        /** 1 when the puller died during the job. */
        died: "num",
        /** 1 when a hero damaged the puller (neutrals do not count). */
        hit: "num",
        /** OHA idle relocations the job held while it ran. */
        idle: "num",
        /** The nearest any of our lane creeps came to the meet point during the lead and watch. */
        wd: "num",
        /** The most neutrals seen within 800 of the meet point (`ev=pull_watch` `nn` uses 1,200). */
        nn: "num",
        /** The same share as `div`, sampled on for `TrailSec` (10 s) past the later of the job end and the wave's due time; only on `ok` lines, written when the trail ends so `t` is up to that much after the job end. */
        dt: "num",
        /** The camp at the start: neutrals in its box (on a `cancelled:empty` or `camp-dmg` line, the camp the walk saw). */
        cn: "num",
        /** Of them, those `CanBeSeen`. */
        cs: "num",
        /** Their HP. */
        chp: "num",
        /** 1 when the camp's origin is visible to the team. */
        cv: "num",
        /** 1 when the counted box's four corners are visible (telemetry only; in drills they never all read visible). */
        cfv: "num",
        /** The camp's expected damage on the puller over `HitSeconds`. */
        cdmg: "num",
        /** The puller's HP. */
        php: "num",
        /** The nearest seen enemy hero's distance to the stand or meet point; not on walk cancels. */
        se: "num",
        /** The camp as the puller's record knows it (CampRead Known, families proposal s5): rn its neutrals, rsrc `seen` (a look
         *  set it) or `rules` (the spawn rule or a stack's unseen set since), rage seconds since the last look that set it. */
        rn: "num",
        rsrc: "str",
        rage: "num",
        /** Of rn, the neutrals last seen whose handles still read alive (whether a neutral dying in fog reads dead is not known). */
        rh: "num",
        // sh the hit's shift from the plan's slot at the order, s0 the first creep-timed shift, lv creep reads. The hit is
        // timed on the wave's front creep (pull_timing CreepTimer): hr geo (timed on it) or plan (never read), hc creeps
        // read, hn the creep after the front one and hb the back creep: predicted distance past the meet point at the
        // neutrals' arrival.
        sh: "num",
        /** The timed reads taken; 0 with `hr=plan` (the slot stood). */
        lv: "num",
        /** The first timed shift. */
        s0: "num",
        /** The neutral speed the pull's timing used, read again at every timing read; absent when the pull had no wave timing. */
        nsp: "num",
        /** `geo` (the hit was timed on the wave's front creep) or `plan` (never read). */
        hr: "str",
        /** The creeps read. */
        hc: "num",
        /** On the timed hit, the predicted distance past the meet point at the neutrals' arrival of the creep after the front one (negative: short of it). */
        hn: "num",
        /** The same for the back creep. */
        hb: "num",
        /** The game time the hit was confirmed (label `lead` began); absent when the verb never got there. */
        ht: "num",
        /** The first time a tagged neutral was past 400 from the camp origin (the give-up timer starts there). */
        g4: "num",
        /** The farthest any tagged neutral came from the camp origin. */
        gh: "num",
        /** The first time a tagged neutral came within 500 of our lane creeps. */
        na: "num",
        /** The first time every tagged neutral that passed 400 was walking home (150 back from its farthest point, no attack target). */
        gu: "num",
        /** The nearest of them to our creeps at `gu`. */
        gd: "num",
        /** The first time a lane creep not already within 300 of the meet point at `ht` came within 300 of it. */
        wa: "num",
        // nm: the first tagged neutral 50 from where it stood at the hit (the camp's start; phchk2 replays 0.4-2.3 s after
        // the order).
        nm: "num",
        // The shed (PullJob ShedMargin, user 06/11/2026): shs the time the puller began walking out of the neutrals' range
        // once our creeps fought them while a neutral still hit it, shh its HP share of max then; unset when it never shed.
        shs: "num",
        shh: "num",
        // Banked logs only (the stay, Ours.SupportPullStay, deleted at oha-pull-row's close; pullchain1, pullstay6): on a pull that ended ok and stayed: st its end (`done` none of our creeps and no
        // neutral left at the camp, `left` neutrals left uncleared, `cleared`, `timeout:late` the backstop, `dead`, or the cut:
        // `preempted:<msg>:<what took it>`), ss its seconds; sdt deny tries and sdk denies got, slt neutral last-hit tries and slk got.
        st: "str",
        ss: "num",
        sdt: "num",
        sdk: "num",
        slt: "num",
        slk: "num",
    },
    // Slice support-lane: one sample per started pull per PullJob WatchLogEvery during its lead, watch and trail (ph lead|watch|
    // trail). Ours near the meet point or the camp origin (within MeetWatch of either): wc creeps, of them won on a neutral, whe on a hero, wcr on anything
    // else, wid idle; wd the nearest of our lane creeps to the meet point. Neutrals within WaveSize of it: nn, of them ntp on the
    // puller, ntc on a creep, ntx idle; the neutral within WatchNeutralSearch nearest our creeps there (the meet point when none): nd its distance, nh its
    // distance from its camp origin, nt its target (p puller, h other hero, c creep, o other, x none). pd: the puller to the meet point.
    // Slice pull-diag: the camp's own neutrals tagged at the hit (see pull_job): tn alive, tp of them attacking the puller
    // (in attack range; a chase out of range reads no target, as for ntp/nt), tc on a creep, td the nearest of them to our lane creeps near the watch (to the meet point when none), th the farthest of them
    // from the camp origin. nd/nh/nt above may name another camp's neutral (nh over 3000 in banked logs).
    pull_watch: {
        pid: "num",
        /** The pull's planned hit second; joins `ev=pull_job`. */
        slot: "num",
        /** `lead`, `watch` or `trail`. */
        ph: "str",
        /** Our lane creeps near the meet point or camp origin. */
        wc: "num",
        /** Of them, those on a neutral. */
        won: "num",
        /** Of them, those on a hero. */
        whe: "num",
        /** Of them, those on anything else. */
        wcr: "num",
        /** Of them, those idle. */
        wid: "num",
        /** The nearest of our lane creeps to the meet point. */
        wd: "num",
        /** Neutrals within 1,200 of the meet point. */
        nn: "num",
        /** Of them, those on the puller (attacking in range; a chase out of range reads no target). */
        ntp: "num",
        /** Of them, those on a creep. */
        ntc: "num",
        /** Of them, those idle. */
        ntx: "num",
        /** The neutral within 3,000 of the meet point nearest our creeps there (the meet point when none): its distance. May name another camp's neutral. */
        nd: "num",
        /** That neutral's distance from its camp origin. */
        nh: "num",
        /** That neutral's target: `p` puller, `h` other hero, `c` creep, `o` other, `x` none. */
        nt: "str",
        /** The puller's distance to the meet point. */
        pd: "num",
        /** Tagged neutrals alive (the camp's own, tagged at the confirmed hit). */
        tn: "num",
        /** Tagged neutrals attacking the puller. */
        tp: "num",
        /** Tagged neutrals on a creep. */
        tc: "num",
        /** The nearest tagged neutral to our creeps near the watch. */
        td: "num",
        /** The farthest tagged neutral from the camp origin. */
        th: "num",
        // shd 1 once the puller has begun its shed (pull_job shs), unset before.
        shd: "num",
    },
    // Slice support-lane: one line per judgement decision (bot-structure s2). kind: the decision (pull); go 1|0; want: the
    // reading asked for it; why: what held it back (a start check, partner, late) or `lane` when the reading did not want it;
    // pull fields: slot (planned hit second), st (push state OUT|HOLD|IN), q (clash between the T1s, 0 ours 1 theirs), mv
    // (clash move over 30 s from our side), own (the clash's distance from our T1 along the lane), tgt (the lane's target
    // point, LanePush TargetOf; before slice pull-gate the pull was wanted when own + mv passed it by PullJob WantPast and st was not IN), cf (logs
    // before slice pull-trigger only: the move with our walking wave removed), tw (tower rule decided), ms (cost);
    // the camp as the API returns it at the decision: cn neutrals in its box, cs of them CanBeSeen, chp their health, cv the
    // camp's origin visible (1|0), cfv its whole box visible (1|0; `one`/`empty` are read only then), cdmg its expected damage on the puller over the pull (PullJob CampDamage; set once the lane
    // wants the pull), php the puller's HP. why empty | one (a seen camp down to one neutral; CampRead CampGate) | camp-dmg (cdmg would leave php under StartReserve) | enemy-site (se, the nearest enemy
    // hero to the stand or meet point, within PullJob SiteEnemy; Ours.Threat off) | threat | missing (SafeGather.TripGate at the camp, `ev=threat who=pull_job`;
    // Ours.Threat on).
    choice: {
        pid: "num",
        /** The attempt id, on a line with `go=1` only (`kind=pull`, `stack`, `rune_detour`, `creep`): shared by the `ev=job` lines and the result line of the job it starts. Absent on `go=0`, on `shadow` and `decider` lines, and on `kind=creep` lines before oha-creep-swing. */
        aid: "num",
        /** The decision; `pull`, `rune_detour` (rune_detour.ts: one line per pass), `stack` (the stack row, stack_job.ts: once a minute at its leave time, `want` the puller's record of the camp under the pull's bar, `slot` the hit second), `creep` (creep_offer.ts: one line per hero and lane creep, `src=shadow go=0 why=off` where the creep row (creep_row.ts, Ours.LaneCreeps) is off, else `src=own` with the row's `go`, its first reason `why` and its latest `lw`, written when the creep leaves the hero's nearby lists; `want` 1 when arriving in time was ever possible, `slot` the second it was first offered; the fields below marked kind=creep hold the offer's answers as they stood when arriving first became possible, else at the largest slack), `shadow` (Ours.ChoiceShadow) or `decider` (decider.ts, every hero of both teams: one line per change of `held`, `let`, `win` or `hs`, and one per begin (`beg`), the creep row's at its read's moment). */
        kind: "str",
        /** kind=decider: the row the decider holds the hero with, `-` when it yields to the host's own code. */
        held: "str",
        /** kind=decider, while a row holds: its strength as asked this round, `hard` (Decider.HARD) or `soft` (Decider.SOFT, OHA's Lua modes capped under it); a row's strength may change while it holds (no row does today: all are hard). */
        hs: "str",
        /** kind=decider: `retreat` when a row wanted the hero but the decider yielded because the retreat file's desire led every other mode's (stock would retreat); absent otherwise. */
        let: "str",
        /** kind=decider: the row the decider began (started its task) since its last line; a begin always writes a line. Present with `let` when the row was begun in the round the decider let go (its task is then cut by the runner's preemptAfter). */
        beg: "str",
        /** kind=decider, with `beg`: the row's offer, its target (`camp:<idx>`, `rune:<rune>`, `creep:<cid>`) and the game time it had to go by (absent where the row has no such limit: the rune detour). */
        btgt: "str",
        bby: "num",
        /** kind=decider, with `beg`: the running task the begin replaced, which a higher row takes the hero from (a lower row's name, or an older job's task name: `stack`, `rune`); absent when none ran. */
        over: "str",
        /** 1 when the pull started. */
        go: "num",
        /** 1 when the reading wanted a pull. */
        want: "num",
        /** What held a wanted pull back: a start check (`enemy-near`, `busy`, `acting`, `late`, `refused`), `empty`, `one`, `camp-dmg`, `weak` (the record, or the puller's look on arrival, under the bar: CampRead StrongAt); for kind=stack also `strong` and `empty` (not wanted: the record at the bar, or 0, which the mark refills) and `low-hp`; on logs before the pull became a decider row also a higher job's name, `partner-low`, `partner-gank`, `enemy-site`, `threat`, `missing`; `lane` when not wanted; `no-read` when the run left no clash. `off` on every `src=shadow` line, wanted or not: it stands in for `lane` and `no-read` too, so a shadow line whose run left no clash shows only by its missing `st`. Also `ctl`, `no_ctl`, `ew` and `drill` from the lane controller and drills. For kind=creep with `src=own`, the creep row's first reason once the creep was about to come due (`early` only if it never was) (CreepRow.Consider, Claim): `busy`, `kind`, `early`, `notime_new`, `notime_held`, `notime_acting`, `notime` (the hero cannot be in the verb's range before the creep comes due: at its first read about to come due, after a refusal for `held` or `acting`, or neither), `acting`, `held` (stock's retreat holds the hero; Valve's attack does not, the hold is hard), `stock` (logs before oha-creep-early only), `tried`, `claimed`, `wait`, `human` (a support's last hit, Ours.SupportCreeps: a lower-cell hero holds a claim on the creep, has it on offer and has not refused it yet, or is a human in the lane; creep_row FreeFor), `late`, `outdmg`, `race`, `covered`, `tower`, `etower`, `given`, `mate`, `nowindow` (Ours.TowerCreeps: a tower is attacking the creep and no pre-hits make the hero's hit the last, `Verdict` `none`), `mates` (the same, a pre-hit would race our own creeps attacking it), `notarget` (a melee creep inside our tower's range that the tower is not attacking), `other` (it went for another creep), `refused`. */
        why: "str",
        /** `kind=creep`, `go=0`, `src=own`: the creep row's latest reason as given at its last read of the creep (the set of `why`, `early` and `kind` too), so `notime_held`, `notime_acting`, `notime_row` and `notime`, which `why` overwrites with an earlier one, can be counted. */
        lw: "str",
        /** Who decided: `own` or `ping`; `shadow` for a puller whose pull is switched off (PullJob.Shadow: `go=0 why=off`, the slot and `want` as the pull would have read them). */
        src: "str",
        /** The lane. */
        lane: "num",
        /** The planned hit second. */
        slot: "num",
        /** `kind=rune_detour`: the own jungle bounty's rune id. */
        rune: "num",
        /** `kind=rune_detour`: the smallest detour the pass read (s): the walk by the rune to the lane front, less the walk there. */
        ex: "num",
        /** `kind=rune_detour`: the distance to the rune at that read. */
        dr: "num",
        /** `kind=creep`: the creep's id (`Telemetry.CreepId`, as on `creep_death` and `unit_seen`). */
        cid: "num",
        /** `kind=creep`: the creep's kind, `m` melee, `r` ranged, `s` siege, `f` flag (`LaneRead.CreepKind`). */
        ck: "str",
        /** `kind=creep`: `t` their creep (a last hit), `o` ours (a deny). */
        who: "str",
        /** `kind=creep`: seconds from `slot` (floored to 0.1 s) to the first read where arriving was possible; absent when it never was. */
        wo: "num",
        /** `kind=creep`: seconds from the first read where arriving was possible to the last such read, gaps between them included; absent when it never was. */
        wl: "num",
        /** `kind=creep`: the engine's seconds to walk into attack range (centre distance less attack range, no hulls; the stand spot behind `pc` to `exs` adds the hulls). */
        walk: "num",
        /** `kind=creep`: the engine's seconds until a swing ordered then is due. */
        due: "num",
        /** `kind=creep`: the engine's seconds until the creep dies to the others' damage; -1 for never. */
        dies: "num",
        /** `kind=creep`: `dies` less the walk and the swing's slack (`LaneOffers.ARRIVE_SLACK`); above 0 is on time; read as 99 at most. */
        slk: "num",
        /** `kind=creep`: the hero's HP share (0 to 1). */
        hpp: "num",
        /** `kind=creep`: the hero's active mode's name. */
        mode: "str",
        /** `kind=creep`: the creep's HP. */
        crhp: "num",
        /** `kind=creep`: other targets in the hero's reach now (walk 0) that come due before the hero would be back (twice the walk plus the swing's slack). */
        g2: "num",
        /** `kind=creep`: of `g2`, the ranged ones. */
        g2r: "num",
        /** `kind=creep`: their lane creeps within acquisition range of the stand spot (the point at attack range from the creep on the hero's line to it; the hero's own place when in range). */
        pc: "num",
        /** `kind=creep`: their summed damage a second. */
        pd: "num",
        /** `kind=creep`: 1 when the stand spot is inside an enemy tower's attack range. */
        ptw: "num",
        /** `kind=creep`: visible enemy heroes whose attack range (and hulls) covers the stand spot. */
        eh: "num",
        /** `kind=creep`: the longest, among those, of the seconds the straight walk to the stand spot spends inside that hero's range (the hero taken as standing still). */
        exs: "num",
        /** `kind=creep`: every visible enemy hero, `pid:distance to the stand spot:attack range:hit damage:seconds an attack:exposure seconds`, joined by `;`. */
        en: "str",
        /** `kind=creep`: whose hit the lane read's forecast says kills the creep: `me`, `mate`, `foe`, `creep`, `tower` or `none` (nothing in the horizon). */
        kb: "str",
        /** `kind=creep`: seconds until that hit lands. */
        kt: "num",
        /** `kind=creep`: the hero's hit damage. */
        md: "num",
        /** `kind=creep`: the highest hit damage among visible enemy heroes within their own attack range of the creep. */
        ed: "num",
        /** `kind=creep`: how many such enemy heroes. */
        ein: "num",
        /** `kind=creep`: 1 when the hero's attack target was this creep at any read while it was offered (stock was on it). */
        atk: "num",
        /** `kind=creep`: visible enemy heroes whose hit is at least ours (`md`) that can walk into their own attack range of the creep before `due` (the race). */
        erc: "num",
        /** `kind=creep`: the soonest of those walks (s); absent when `erc` is 0. */
        ert: "num",
        /** `kind=creep`: 1 when the creep is inside one of our towers' attack range (and both hulls). */
        otw: "num",
        /** `kind=creep`, `go=1`: seconds from `slot` to the read that started the row's attempt. */
        gat: "num",
        /** `kind=creep`, `go=1`: the engine's walk into range (s) at that read. */
        gw: "num",
        /** `kind=creep`: `GetHeightLevel` (0 to 7) of the hero's place when the answers were taken; absent when the API gave none. */
        hh: "num",
        /** `kind=creep`: `GetHeightLevel` of the stand spot when the answers were taken; absent when the API gave none. */
        sh: "num",
        /** `kind=creep`: `GetHeightLevel` of the creep when the answers were taken; absent when the API gave none. */
        ch: "num",
        /** `kind=creep`: the hero's attack range (above 320 it attacks with a projectile, as the engine's lasthit.ts reads it). */
        ra: "num",
        /** `kind=creep`: the height level of each visible enemy hero, `pid:level` (`-` when the API gave none), joined by `;` in `en`'s order. */
        enh: "str",
        /** Lane push state: `OUT`, `HOLD` or `IN`. */
        st: "str",
        /** The clash point between the T1s: 0 ours, 1 theirs. */
        q: "num",
        /** The clash's 30 s move from our side. */
        mv: "num",
        /** Older logs only: the same move with our walking wave removed. */
        cf: "num",
        /** The clash's distance from our T1 along the lane. */
        own: "num",
        /** The lane's target point (`LanePush.TargetOf`). */
        tgt: "num",
        /** 1 when the tower rule decided. */
        tw: "num",
        /** The runs' real milliseconds. */
        ms: "num",
        /** The camp as the API returns it: neutrals in its box. */
        cn: "num",
        /** Of them, those `CanBeSeen`. */
        cs: "num",
        /** Their HP. */
        chp: "num",
        /** 1 when the camp's origin is visible to the team. */
        cv: "num",
        /** 1 when the counted box's four corners are visible (telemetry only). */
        cfv: "num",
        /** The camp's expected damage on the puller over `HitSeconds`; set once the lane wants the pull. */
        cdmg: "num",
        /** The puller's HP. */
        php: "num",
        /** The nearest seen enemy hero's distance to the stand or meet point. */
        se: "num",
        /** The camp as the puller's record knows it (CampRead Known, families proposal s5): rn its neutrals, rsrc `seen` (a look
         *  set it) or `rules` (the spawn rule or a stack's unseen set since), rage seconds since the last look that set it. */
        rn: "num",
        rsrc: "str",
        rage: "num",
        /** Of rn, the neutrals last seen whose handles still read alive (whether a neutral dying in fog reads dead is not known). */
        rh: "num",
        // Slice pull-gate (Decision 06/11/2026): the pull trigger's inputs, from the lane with the pulled wave gone (LanePush
        // WaveGoneFrom): pa the clash's distance from our T1 PullJob ArriveAfter s after the slot (wanted past tgt + WantPast),
        // ap ep the HP of our and their creeps in lane before that pair of waves (wanted with ep <= PowerRatio x ap).
        pa: "num",
        ap: "num",
        /** The HP of their creeps in lane before the pulled wave and the one spawned with it. */
        ep: "num",
        // hold 1 when our lane core could hold their wave (PullJob CoreToHold); rule which trigger wanted the pull: new (the
        // above), old (own + mv past tgt + WantPast and st not IN, counted only with hold 1) or both; absent when neither.
        hold: "num",
        rule: "str",
        // pw 1 when the pulled wave was found near its scheduled spot (or was still to spawn), 0 when it was not and pa ap
        // were forecast with it in the lane.
        pw: "num",
        // kind=shadow (Ours.ChoiceShadow, choice_shadow.ts): one line per hero of ours about every second and on each change of active
        // mode. A frame's values are logged on the next frame, beside the active mode Valve picked from them.
        /** kind=shadow and decider: the active mode (debug ModeName, as ev_snap `mode`): Valve's pick from the frame's desires (decider: the last round's). */
        win: "str",
        /** kind=shadow: the mode OHA's own computed desires pick (argmax of the `d_` numbers); absent when none was computed. */
        top: "str",
        /** kind=shadow: `top`'s desire. */
        tv: "num",
        /** kind=shadow, when `top` is not `win`: `zeroed` (the gate lowered top's desire), `held` (the gate raised win's: DriveAfter's lane floor), `outbid` (win's desire is ours, set by the gate before OHA's code, or carries an Intent claim), `valve` (Valve's own mode or arbitration; a branch of ours inside win's own body, `mix`, is already in win's desire, so it is never the cause). */
        how: "str",
        /** kind=shadow, with `how`: the module and switch of ours that made the difference (`ArbiterDrive:DriveDecide(<pick>)`, `ArbiterDrive:DriveAfter borrowed(<pick>)`, `ArbiterDrive:DriveAfter lane_floor`, `JobChooser:host`, `JobChooser:Hold(job)`, `Retreat:Hold(episode)`, `Retreat:Desire`, `Trade:Desire`, `Intent:<claim>`, `Drill:InLaneDenies`, `Drill:RigDesire`), or `Valve:<mode>` / `Valve:arbitration`. */
        by: "str",
        /** kind=shadow: modes where a branch of ours inside the mode's own GetDesire acted in the frame's call (laning: the body's bOwnsThink last hit at 0.9 or a drill's lane-only hold, marked by ChoiceShadow.MarkMix; team_roam: Trade.OwnsFights skipped OHA's fight branches; rune: DeniesOhaRune). Context only, never `by`. */
        mix: "str",
        /** kind=shadow: `<mode>=<source>` for each computed mode an Intent claim or stickiness moved (Intent.Explain's `by` not raw), read at the mode's call. */
        clm: "str",
        /** kind=shadow: modes whose value came from Ours.ChoiceProbe (OHA's code run where the drive zeroed it; the drive's 0 returned). */
        pr: "str",
        /** kind=shadow: `<mode>:<desire>` for each mode the gate returned other than its own desire (drive, hold, DriveAfter). */
        gate: "str",
        /** kind=shadow, under ArbiterDrive: the drive's pick in the frame of the values (Arbiter.PickThisFrame, read at the frame's calls). */
        pick: "str",
        /** kind=shadow, under ArbiterDrive: the arbiter's candidates that apply in that frame, `<name>:<group>` (Arbiter.Candidates). */
        cand: "str",
        /** kind=shadow: the drive's lane desire (Arbiter SETTINGS.LaneDesire) while the pick is the lane. */
        lfl: "num",
        /** kind=shadow: our retreat desire (Retreat.Desire through the retreat file) when it answered first. */
        rdes: "num",
        /** kind=shadow: our trade's attack desire (Trade.Desire) when it answered first. */
        tdes: "num",
        /** kind=shadow: the chooser's host desire, in farm (its only host, Chooser HOST): on the hold path, or under the drive when farm is the pick's host or the pick is OHA's (DriveDecide's farmHost); absent when the drive zeroes farm for another pick. */
        hdes: "num",
        /** kind=shadow: mode_laning_generic's own desire as the one real call returned it (Intent-resolved), or `-<reason>` when its OHA code was not computed: `-drive` (Arbiter.DriveDecide set it before OHA's code), `-hold` (a retreat episode or a job), `-ours` (our desire answered first: retreat, attack under Trade, the chooser's host), `-valve` (no fresh Lua value: Valve's built-in or a non-number), `-probe` (Ours.ChoiceProbe ran the code and it errored or gave no number), `-drill`, `-rig`. */
        d_laning: "mixed",
        /** kind=shadow: as `d_laning`, for mode_attack_generic. */
        d_attack: "mixed",
        /** kind=shadow: as `d_laning`, for mode_retreat_generic. kind=decider, with `let`: the retreat file's last value, the one that led. */
        d_retreat: "mixed",
        /** kind=shadow: as `d_laning`, for mode_farm_generic. */
        d_farm: "mixed",
        /** kind=shadow: as `d_laning`, for mode_team_roam_generic. */
        d_team_roam: "mixed",
        /** kind=shadow: as `d_laning`, for mode_roam_generic. */
        d_roam: "mixed",
        /** kind=shadow: as `d_laning`, for mode_rune_generic. */
        d_rune: "mixed",
        /** kind=shadow: as `d_laning`, for mode_ward_generic. */
        d_ward: "mixed",
        /** kind=shadow: as `d_laning`, for mode_assemble_generic. */
        d_assemble: "mixed",
        /** kind=shadow: as `d_laning`, for mode_assemble_with_humans_generic. */
        d_assemble_h: "mixed",
        /** kind=shadow: as `d_laning`, for mode_defend_tower_top_generic. */
        d_defend_top: "mixed",
        /** kind=shadow: as `d_laning`, for mode_defend_tower_mid_generic. */
        d_defend_mid: "mixed",
        /** kind=shadow: as `d_laning`, for mode_defend_tower_bot_generic. */
        d_defend_bot: "mixed",
        /** kind=shadow: as `d_laning`, for mode_push_tower_top_generic. */
        d_push_top: "mixed",
        /** kind=shadow: as `d_laning`, for mode_push_tower_mid_generic. */
        d_push_mid: "mixed",
        /** kind=shadow: as `d_laning`, for mode_push_tower_bot_generic. */
        d_push_bot: "mixed",
        /** kind=shadow: as `d_laning`, for mode_roshan_generic. */
        d_roshan: "mixed",
        /** kind=shadow: as `d_laning`, for mode_secret_shop_generic. */
        d_secret_shop: "mixed",
        /** kind=shadow: as `d_laning`, for mode_side_shop_generic. */
        d_side_shop: "mixed",
        /** kind=shadow: as `d_laning`, for mode_outpost_generic. */
        d_outpost: "mixed",
    },
    gank: {
        pid: "num",
        pos: "num",
        target: "num",
        lane: "num",
        score: "str",
        result: "str",
        msg: "str",
        label: "str",
        left: "num",
        engaged: "num",
        away: "num",
    },
    lane_pos: {
        pid: "num",
        /** The hero's distance from its preferred laning spot. */
        d: "num",
        owned: "bool",
        running: "bool",
        /** The task label; the laning body walking to a last hit or deny reads here. */
        label: "str",
        mode: "num",
        /** The spot's anchor (creep, front, wave, fed: lane_aggro's fed creep going down), or oha. */
        spot: "str",
        pushed: "num",
        /** The first limit the preferred point broke, which usually placed the spot: `pref`, `kill` or `unknown` (Safe.At called the place deadly; `tower` too when it was that), `creep`, `hp` (only the HP margin moved it), `tower` or `xp` (the XP-only spot or the fallback). Older logs: `hero`. */
        why: "str",
        /** The HP margin on the creep rings. */
        hm: "num",
        /** 1 when a core's spot stands closer than the open-lane limits allow (our tower's cover, `Ours.LaneSpotTower`); else 0. With `Ours.LaneSpotThreat` it counts the creep cover and our tower's cover for heroes. */
        ut: "num",
        /** The spot itself, x (one sample a second). */
        sx: "num",
        /** The spot itself, y. */
        sy: "num",
        /** HP lost to heroes so far; a lower bound once the core left laning. */
        hph: "num",
        /** The nearest visible enemy hero (slice support-spot): its distance, its ready damaging abilities (trained, not
         *  passive, off cooldown, mana for it) and the longest cast range among them (0 with none ready). */
        ne: "num",
        /** That hero's ready damaging abilities. */
        nk: "num",
        /** The longest cast range among them; 0 with none ready. */
        nr: "num",
        /** A core's spot on the rearmost clash (their creeps between our T1 and our front, the waves crossed): the clash's
         *  distance from our T1 along the lane and our front's; absent when the spot anchored on our front as usual. */
        cl: "num",
        fo: "num",
        /** Ours.LaneSpotThreat: the threat read at the chosen spot (burst, threat) and the old hero limits' verdict there. */
        rb: "num",
        /** The read's threat at the chosen spot. */
        rt: "num",
        /** Safe.At reads made this frame. */
        rn: "num",
        /** Safe.At at the chosen spot: level (`safe`, `costly`, `deadly`) and HP over kill line (absent with nobody in reach); at the preferred point `pl` and `pq`. */
        sl: "str",
        sr: "num",
        pl: "str",
        pq: "num",
        /** What the old hero limits say at the spot: `hero`, `hp`, `creep`, `tower` or `none`. */
        ob: "str",
        /** The read's `missing` and unseen pids (comma-joined) at the chosen spot; the old limits' (`op`) and the read's (`rp`) verdicts at the preferred point. */
        rm: "num",
        mp: "str",
        op: "str",
        rp: "str",
        /** Heroes the read counted as engaged (hitting us within a second) at the chosen spot, and 1 when a reaching hero's attack target is us. */
        re: "num",
        rat: "num",
    },
    /** A decision's API inputs in the frame it decided (cut.ts): `kind` names the decision; the record formats are cut.ts's. */
    cut: {
        pid: "num",
        /** The decision: `spot` (LaneSpot.Compute, beside ev=lane_pos), `gate` (SafeGather.TripGate, beside its ev=threat), `leave` (retreat's LeaveWhy; the answer is `dec`), `join` (PairJoin.Decide, in shadow; `dec`), `lane` (states/lane_table Walk: the row that acted, `row`, with the rows that wanted the frame and gave no order, `skip`), `trade` (states/trade.ts Decide; `lv`, `why`), `sustain` (sustain.ts Decide in shadow; `ak`, `why`), `safe` (safe_gather.ts Shadow: safe.ts Decide in shadow beside each consumer, `who` = leave, retreat, spot, pref, trade, trade_walk or a gate's consumer; `lv`, `why`), `pick` (states/laning.ts choose: the laning body's creep pick, LanePick.Choose; `ans`, `ak`). Older logs: `trade` is the retired CoreTrade.Decide (told apart by its `dec`, `rch` and `kh` fields and no `lv`), `trade2` is the same line as today's `trade`, and `keep` is the retired CoreTrade.KeepAnswer. */
        kind: "str",
        /** The spot's role input (`trade`: the trading hero's): `core` or `support`. */
        role: "str",
        /** `gate`: the consumer that asked (ev=threat `who`). */
        who: "str",
        /** `gate`: the walk's start, x,y (SafeGather.TripGate's `from`). */
        fm: "str",
        /** `gate`: the walk's end, x,y (the camp or place the trip goes to). kind=trade: a running play near us, `id:kind:tgt:zero` (`-` for no zero); absent: none. kind=safe: the place read, x,y. */
        pl: "str",
        /** The bot's assigned lane. */
        lane: "num",
        /** The bot: x, y, HP, max HP, attack range, hull, movement speed, 1 when an escape item is ready, 1 when an enemy hero damaged it in the safe read's press window (absent on logs before 20/11/2026). */
        b: "str",
        /** GetLaneFrontLocation(team, lane, 0) and (-400): x, y, x, y. */
        fr: "str",
        /** The spot's `fed` input: lane_aggro's fed creep (CreepId). */
        fed: "num",
        /** The spot's `hold` input: wave_hold's hold point, x,y. */
        hold: "str",
        /** Enemy heroes in sight within 3,000 of the bot or its lane front (`gate`: of the walk's box): pid, x, y, HP, range, hull, speed, attacking the bot, damaged the bot within Threat EngagedRecent, GetEstimatedDamageToTarget over 3 s and 6 s, illusion. */
        he: "str",
        /** Enemy heroes alive and unseen with a sighting: pid, last-seen x, y, seconds unseen, last speed Threat read (-1 none). */
        hu: "str",
        /** Our other heroes within 3,000 of either: pid, x, y, range, hull, speed, in our retreat. */
        ha: "str",
        /** Towers standing, hex masks over cut.ts TOWER_IDS: ours, theirs. */
        ta: "str",
        /** Towers within 3,000 of either: team, TOWER_IDS index, attack target. */
        tt: "str",
        /** With an unseen enemy: IsLocationVisible on a grid over the bot and its lane front, `x0,y0,nx,ny,step,hex` (cut.ts visionGrid). */
        vis: "str",
        /** kind=leave: what the game decided, `lethal`, `tower`, `heal`, `threat` (leave) or `under`, `join`, `hitback` (stay; older logs `even`, `hold`, `stand`). Logged when the answer changes, and while an enemy hero is in the read's reach every Retreat CutEvery s (on a frame that made a fresh read). */
        dec: "str",
        /** kind=leave, older logs: the budget the read was held against (by purpose `purp`: free, busy or committed). */
        bud: "num",
        /** kind=leave: the budget's purpose. */
        purp: "str",
        /** kind=leave, older logs: seconds the read had been over budget before this decision (-1 not over); the hold timer. */
        ov: "num",
        /** kind=leave, older logs: Profile.ThreatHold, the seconds the read must stay over budget. */
        th: "num",
        /** kind=leave, older logs: RetreatOdds' engaged heroes with none of our lane creeps within creep aggro of them. */
        unp: "num",
        /** kind=leave: 1 when an enemy tower damaged the bot within 0.5 s. */
        dt: "num",
        /** kind=leave: 1 when Trade.Holds held a join for the bot (LeaveWhy stays `join`); absent otherwise. */
        pj: "num",
        /** kind=leave: 1 when Trade.Holds held a hit back for the bot (LeaveWhy stays `hitback`); absent otherwise. Older kind=trade lines: 1 when the target is hitting the core. */
        hb: "num",
        /** kind=leave, older logs: the read's threat and band, for reading a line without replaying it. */
        thr: "num",
        band: "str",
        /** `gate`, with an unseen enemy: IsLocationVisible at Threat's walk points, `n,hex` (n steps, bit i of the hex the i-th of n + 1 points; cut.ts walkVision). */
        vw: "str",
        /** kind=join (pair_join.ts, D10 in shadow): the ally hit by a hero within PairJoin HitRecent, within AllyRange of the bot (the lowest HP share). Logged every PairJoin Every s while the answer changes, else every CutEvery s, to 12:00. The answer is `dec`: `join` or `losing` (older logs also `outnumbered`). */
        al: "num",
        /** kind=join: our heroes within OursRange of the ally, the bot and the ally included: pid, x, y, HP, max HP, in our retreat. */
        po: "str",
        /** kind=join: enemy heroes in sight within FoeRange of the ally: pid, x, y, HP, max HP. */
        pt: "str",
        /** kind=join: GetEstimatedDamageToTarget over PairJoin Window between the two sides, both ways: from pid, to pid, damage. */
        dm: "str",
        /** kind=join: our best target (the enemy our heroes do best on, by damage over its HP), -1 none. */
        tgt: "num",
        /** kind=join: our best kill share, our heroes' damage on `tgt` over its HP. kind=trade (slice trade-free-cut): the
         *  bot's GetEstimatedDamageToTarget on the target over PairJoin Window, over the target's HP. */
        ko: "num",
        /** kind=join: theirs, their heroes' best kill share on one of ours. kind=trade: the target's on the bot, over the bot's HP. */
        kt: "num",
        /** kind=join: each member's reach for Ours.JoinArrive, both sides, `;`-joined: pid, reach (attack range plus hull), movement speed, hull. Absent on older lines (counted whole). */
        jar: "str",
        /** kind=join: 1 with `Ours.JoinArrive` on (absent: off): a hero's damage counts for the share of Window left after its walk into its own range of the target. */
        jav: "num",
        /** Older kind=join lines only (the `ours` record is retired): `hit` (an ally hit by a hero) or `ours` (an ally with a fight of its own open). */
        on: "str",
        /** Older kind=join lines only, on=ours: the enemy hero the ally's episode was on, its kind `ek`, age `oa`, whether the ally was attacking it `aa`, and `free`. */
        fo: "num",
        aa: "num",
        free: "str",
        /** Older kind=trade lines (the retired core_trade.ts, D18/D19; no `lv`): CoreTrade.Decide's inputs on a fresh decision with
         *  an enemy hero in reach and no trade running. `tgt` the target; `dec` the answer: `trade`, `kill`, a respect (`tower`,
         *  `outnumbered`, `low_hp`, `behind`, `creeps`, `wave`, `burst`, `unfavoured`, `deny`) or `gap`. The bot's and the target's
         *  HP share. In today's kind=trade `hp` is our HP share and `thp` is absent (the candidates carry it). */
        hp: "num",
        thp: "num",
        /** kind=trade: enemy heroes in sight, and our heroes (the bot included, at least 1), within 1,200 of the bot. */
        en: "num",
        ally: "num",
        /** kind=trade: enemy lane creeps within 500 of the bot, and those attacking it (plus 2 per enemy tower attacking it). */
        cr: "num",
        hc: "num",
        /** kind=trade: 1 when the bot or the target is within an enemy tower's reach. */
        tw: "num",
        /** kind=trade: the kill HP share (0.4 when the core's lane fights are ours, `lf` 1; else 0.25). */
        kh: "num",
        lf: "num",
        /** kind=trade: the HP-share gap a lost trade left (`recoverTo`); absent when none. */
        gap: "num",
        /** kind=trade: the distance to the target and the trade's reach (attack range, both hulls, the role's walk-in). */
        d: "num",
        rch: "num",
        /** kind=trade: 1 when the target's attack target is a lane creep (a last-hit or deny swing). */
        tlh: "num",
        /** Today's kind=trade: `bu` and `tm` as the cut's threat read and tower on us. Older kind=trade lines (retired `Ours.TradeSafe`): the threat read's burst in reach over the bot's HP
         *  (retreat's stay read), and 1 when the bot's attack point is in an enemy tower's reach or a tower attacks it. The
         *  answer adds the respect `burst` (their burst at our HP or more). */
        bu: "num",
        tm: "num",
        /** Older kind=trade lines (retired `Ours.TradeLands`): `aw` the target's speed away from
         *  the bot along the line between them (negative: towards; 0 when unknown or in range), from its movement over the last 0.5 to
         *  1 s; `lw` 1 when the bot can reach attack range within 1.5 s (in range already counts). With `d`, `ar`, `hl` (both hulls)
         *  and `ms`: `d - ar - hl` over `ms - aw` is the walk-in time. `hl`, `ms`, `tms` as kind=keep's. */
        aw: "num",
        lw: "num",
        /** kind=trade (slice trade-free-cut): the bot's and the target's attack range, and 1 when the target's attack target is the bot. */
        ar: "num",
        tar: "num",
        tme: "num",
        /** Older kind=trade lines (retired `Ours.TradeFree`): 1 when it asked question 2 (free or favoured) in place of `gap`; absent off. */
        tf: "num",
        /** kind=trade (slice trade-free round 2), with `tf`: 1 when the laning body is offered a deny now (Laning.DenyDue), which
         *  outbids the trade. */
        dn: "num",
        /** Older kind=trade lines with `lf` 1 (retired fight-safe): the lane-fight gate's answer (CoreTrade.FightAnswer): `roll` (a chance may be
         *  offered), `kill` (the commit comes first), the core's refusal (`tower`, `outnumbered`, with `Ours.FightSafe` `burst`) or
         *  the roll's hard zero (`hp`, `outnumbered`, `tower`, `behind` with the switch off). */
        fg: "str",
        /** kind=trade with `lf` 1: the roll's own inputs for its hard zeros: our and their heroes within the play radius of the
         *  target (initiator and target counted), and the target's distance to its nearest tower. */
        fpo: "num",
        fpt: "num",
        ftd: "num",
        /** Older kind=trade lines with `lf` 1: 1 when the fight gate asked the burst in place of `behind` (retired FightSafe), 0 off. */
        fs: "num",
        /** kind=trade: what Desire opened on this decision, since `dec` is the trade rule's answer only: `trade`, `kill`, `fight`
         *  (a lane fight rolled), `play` (a running play joined), `hitback` (a hit back on a hitter) or `none`. */
        did: "str",
        /** Older kind=trade lines (retired), with `hb`: CoreTrade.Exchange's answer, whether the exchange is taken as a hit back
         *  retreat waits for (`trade`, `kill`) or why not (`hb_hp`, `hb_burst` or Answer's refusal). */
        xa: "str",
        /** Older kind=keep lines (retired CoreTrade.KeepAnswer; `dec` its answer, `keep` for none, every end and a keep at most
         *  each 0.5 s): the episode's kind (`kill` or `join`), the target alive (IsHeroAlive) and seen (1/0), seconds since the
         *  offer and since the start (absent: not started), and for a join PairJoin's answer this frame (`none`, `same`,
         *  `other`). `hp` to `tm` are Gather's on the target with trade's names, present only where the answer reads them. */
        ek: "str",
        alv: "num",
        sn: "num",
        oa: "num",
        sa: "num",
        jn: "str",
        /** kind=keep, the chase's terms (read by nothing yet): our hull plus the target's when seen, our and the target's move
         *  speed (unseen: Threat's last read, -1 none), our ready damage spells (SpellReady.ReadyDamage: name,cast range,cast
         *  point,behaviour,damage records), and while unseen our team's last sighting x, y and its age (s). `d` is to the
         *  target, or to that sighting. */
        hl: "num",
        ms: "num",
        tms: "num",
        sp: "str",
        lx: "num",
        ly: "num",
        tss: "num",
        /**
         * kind=trade (states/trade.ts, the one trade decision: D18, D19, D24, D10; driver `trade`; named `trade2` on logs from before the old
         * one went): every decision's inputs and answer,
         * logged when the answer changes, every 0.5 s while an exchange runs, else every 2 s, to 12:00. `role` is `core` or `support` by
         * position, logged and never read. `hp` our HP share, `svh` and `svb` `Safe.At` here (held; `svh` without a hold, for a hit, `svb` with one, for
         * a hit back, kill and join) as `level,ratio,reason` (ratio of our HP to the kill line, `-` when nothing reaches), `n` the enemy heroes within 1,600
         * (older lines `bu` `n` `mi`: the threat read here), `tm` 1 when a tower attacks us, `hc` enemy creeps attacking us (a tower counts 2), `cr` enemy
         * lane creeps within 500, `dn` 1 when a deny is due, `ms` our movement speed (absent on older lines: Decide reads 300).
         */
        n: "num",
        mi: "num",
        svh: "str",
        svb: "str",
        /** kind=trade, with `Ours.TradeSwing` on (absent: the rule is off): `cover:due:atk`: seconds our own attack order's aggro cooldown still covers a swing (0 none), seconds to the next last hit or deny this laner would take (`-` none in sight), our attack point in seconds. */
        swg: "str",
        /** kind=trade: 1 with `Ours.TradeHold` on (absent: off): a running hit is not asked the favoured test before its first attack fires. */
        thd: "num",
        /** kind=trade: 1 with `Ours.JoinHold` on (absent: off): a pair join is judged on arrival within 2 s and carried to its first attack through a lapsed pair answer. */
        jhd: "num",
        /** kind=trade: 1 with `Ours.CreepRead` on (absent: off): each candidate record then ends with the swing place's safe answers (level, ratio, reason without a hold, then with one; `-` when not asked) and `oc`, our creeps' share on it. */
        crd: "num",
        /** kind=trade: the pair answer `dec:tgt:ko:kt` (not `pj`, which kind=leave keeps as a number). Absent: no pair answer. */
        pjr: "str",
        /**
         * kind=trade: one record per candidate (an enemy hero within 1,600), `;`-joined, fields `,`-separated:
         * pid, thp, thpAbs, d, gap, away, arr (1/0: we reach attack range within `walkHit`, for reading; Decide recomputes it from gap, away and `ms`), hit (1/0), free, ko, kt, paid, tw (our attack point in an enemy tower's reach), then the walk answer
         * wlv, wra, wwhy (`Safe.At` along the walk to it, away and with a hold: level, ratio, reason; `-` when not asked; older lines: burst, heroes, unseen weight), the catch read cok, cdm, csf (ok, damage, seconds to its safety; `-` when not asked) and lo (1 when an exchange with it ended `losing` and the six quiet seconds have not passed: it vetoes hit and hit back), then sw (1/0: it damaged us within its seconds per attack plus 0.25 s, the stay bar of a running hit back on it; absent on older lines), then near and kc (with `swg`: enemy lane creeps inside the aggro radius of us or of the swing place, and their damage on us over 3 s from their arrival over our HP; `-` without it).
         */
        cd: "str",
        /**
         * kind=trade: the running exchange, `:`-joined: level, target, source (`-` none), alive, offered, started, landed, soFar, catchFails,
         * seconds since the last failed catch read, seconds of the step out, chase x, chase y, the unseen catch read ok (`-` where absent).
         * Absent: no exchange running. Its unseen reads are `uat`, `utw`, `uth`.
         */
        run: "str",
        /** kind=trade: the answer: level (`none`, `hit`, `hitback`, `kill`, `join`), target pid (absent for none), source (`pair`, `play`), how (`verb:aggro`, with `@x,y` for a move) and why (the rule, or for none the first gate that failed); `ed` is why a running exchange ended this frame, `higher` when another candidate won the order. */
        lv: "str",
        src: "str",
        how: "str",
        why: "str",
        ed: "str",
        /** kind=trade: the hunters of the lowest-HP kill candidate, as below. Older kind=keep lines (a started kill): CatchRead's hunters as `;`-joined `d,reach,close,dps,spells` records
         *  (spells `/`-joined `range:cp:dmg`, damage after the target's resistances), the target's HP (seen, or as last seen),
         *  and the read's damage within the window and seconds to its first (-1 none); `csf` the window, the seconds until the
         *  target reaches its own tower's reach at its speed towards it (CATCH_WINDOW when not heading there). */
        chu: "str",
        cth: "num",
        cdm: "num",
        cft: "num",
        csf: "num",
        /** kind=keep, a started kill on an unseen target (1/0): we stand at its predicted place, that place or we inside an
         *  enemy tower's reach, more enemy heroes near than ours, unseen enemies other than the target weighing on the walk. */
        uat: "num",
        utw: "num",
        uou: "num",
        uth: "num",
        /** kind=keep, a join on a seen target: 1 when it is at the kill bar and Decide calls `kill` (it becomes the kill). */
        kup: "num",
        /** kind=lane: the hero's position, 1 to 5. */
        pos: "num",
        /** kind=lane: the lane table row that acted (the step name of ev=snap `step`). Logged when the row or `skip` changes, else every 5 s. */
        row: "str",
        /** kind=lane: `,`-joined rows before `row` that wanted the frame and gave no order (rows whose run is their own scan are not listed); absent when none. */
        skip: "str",
        /** kind=lane: 1 under lane-only (a drill). */
        lo: "num",
        /**
         * kind=sustain (sustain_gather.ts: in shadow for every hero; with `Ours.Sustain` a held hero's line is the answer sustain_act.ts carries out, `act` 1): HP, max HP, mana, max mana, absolute.
         * Older logs (step 2) carry `bua` (the stay read's burst), `lb` (laneBurst, the kill line's stand-in) and `tr` as `d,enemyD`, and no `kill`, `sh` or `nd`.
         */
        hpa: "num",
        hpm: "num",
        mpa: "num",
        mpm: "num",
        /** kind=sustain: heal and mana items in slots 0-8, `slot,name,uses,hp,mp,dur,breaks,tree,refill,share,ready` per `;` (hp, mp: one use, absolute; ready 1: castable now, in slots 0-5 and off cooldown). */
        it: "str",
        /** kind=sustain: the nearest visible passable tree within 1,200, read only with a tree item held: `walk,safe,start`, seconds to walk into cast range, 1 when the safe-here read over that walk is not deadly, and 1 when a walk may start here (0: deadly where we stand). */
        tr: "str",
        /** kind=sustain: a hero damaged us in the last 2 s (1/0). */
        hr: "num",
        /** kind=sustain: the safe-here read here (2 s): `kill` (as kind=safe's field), `sh` a reacher is hitting us (1/0), `rc` visible heroes in its reach. */
        sh: "num",
        rc: "num",
        /** kind=sustain: the same read's `prs` (kind=safe), which picks the kill line's bar. */
        spr: "num",
        /** kind=sustain: seconds until the next last hit or deny is due in our lane (Laning.NextDue); absent with no creep near. */
        nd: "num",
        /** kind=sustain: 1 when sustain_act.ts carries this answer out (`Ours.Sustain`, a held hero). */
        act: "num",
        /** kind=sustain: HP and mana the running regen buffs still restore. */
        rl: "num",
        ml: "num",
        /** kind=sustain: the safe spot (retreat's `threat` anchor) `x,y,walk seconds,ok` (ok 0: the safe-here read there calls it deadly; read only under the kill line, else 1). */
        ss: "str",
        /** kind=sustain: regen on its way, whoever bought it (heal and mana items in the stash or on the courier) `hp,mp,eta seconds` (absent: none); `rom` 1 when a slot in 0-8 is free for one to land in. */
        dl: "str",
        rom: "num",
        /** kind=sustain: the executor's running answer (`Sustain.Inputs.run`; absent in shadow and with none running) as `kind,slot,name,seconds since its start,hp0,dur,x,y`, an absent part empty. */
        srn: "str",
        /** kind=sustain: the purchase sent with a use (rule 2's tango and ship). */
        alb: "str",
        /** kind=sustain: gold; the courier's delivery seconds when free (absent: busy or dead); the shop `name,cost,hp,mp` per `;`; seconds to the fountain and back. */
        gd: "num",
        co: "num",
        shp: "str",
        ho: "num",
        /** kind=sustain: idle (a camp job runs), at the fountain (1/0). */
        idl: "num",
        af: "num",
        /** kind=sustain: allies within 800, `pid,missing HP,heal uses` per `;`. */
        als: "str",
        /** kind=sustain: the answer's kind (`none`, `use`, `step_out_use`, `give`, `buy`, `home`, `wait`), item and ally pid; its rule is `why`, a running answer's end `ed`. kind=pick: `ak` is the chosen target's verb kind (`lasthit`, `deny`, `prehit`, `none`). */
        ak: "str",
        anm: "str",
        ato: "num",
        /**
         * kind=safe (safe_gather.ts: the safe-here answer a consumer asked for, logged when its level or reason changes and else every `CutEvery` while a hero is in reach or the landing price is over 0; an asker of many places a frame, `pick_in` and `spot_c`, logs one line per level each `CutEvery`, a different ask of the frame each time; the consumer is `who`, the place read is `pl` as `x,y`, our HP and max HP are `hpa` and `hpm`, `mi` the unseen belief's weight sum):
         * `rr` one record per reacher, `;`-joined, `pid,hitting,dmg,unseen` (hitting 1/0: the read's engaged window, so a gate's read has none; dmg absolute, over the read's long window when hitting; unseen 1: a lane opponent last seen
         * under 10 s ago whose run reaches the place, at the damage it last had); absent: none in reach. `stw` `tower,towerOnMe` (1/0; `tower` by the tower's reach to a point; towerOnMe since 20/11/2026 only when a tower on the hero can reach the place, by its reach plus the hero's hull, so `0,1` is a place in that band; before that whatever the place), `ld` HP a second lost over the last 2 s to `hero,creeps,tower`,
         * `ex` seconds to walk out of every visible reacher's range from the place read (from the hero's own place before 20/11/2026; absent with none in reach; with Ours.ExitWindow a reacher not hitting us has its `dmg` over `ex` + 1 s in half-second steps up, at most 4 s), `awy` the walk leaves our creeps and tower, `hld` the caller holds a standing answer here,
         * `hd` the caller has a hold (a hit back or join). The answer: `lv` (`safe`, `costly`, `deadly`), `kill` the reachers' summed damage, `ra` HP over kill (absent with no kill), `pr` the price (HP a second lost), `why` the rule
         * (`tower`, `kill`, `unknown`, `hero`, `creeps`, `safe`). Logged on a change of `lv` or `why`, else every 2 s while a hero is in reach or `pr` is over 0.
         */
        rr: "str",
        stw: "str",
        ld: "str",
        ex: "num",
        awy: "num",
        hld: "num",
        hd: "num",
        /** kind=safe: an enemy hero damaged us in the last `SafeGather.SETTINGS.PressWindow` s (1/0): the kill bar is `stay` with it, `idle` without. */
        prs: "num",
        /** kind=safe, `Ours.TowerRead` on: `Safe.Inputs.drawn`, ";"-joined `src,dmg` rows (`tower`: its damage on us over the kill window from when it would be on us); `-`: on, nothing drawn; absent: the switch is off. */
        dr: "str",
        kill: "num",
        ra: "num",
        pr: "num",
        /**
         * kind=pick (states/laning.ts `choose`, the laning body's creep pick: every input of LanePick.Choose and its answer, before the walk-in's price may refuse it (contestPick), so tools/hlog/cut.js replays it with no game; `pid`, and `pos`, the pick-table column read).
         * `ord` is the order of kinds (`lasthit,pre_hit,deny,idle_swing` for a core). `tg` one record per offered target, `;`-joined, `n,kind,eta,due,walk,dies,ranged,mine`: n is its place in the offer (1-based), kind `lasthit` or `deny`,
         * times in seconds (6 places; -1 for an infinite `dies`), ranged 1/0, mine 1/0 (the role's filter, asked once during the pick). `cur` the offer the attempt is waiting on (-1: its creep is not among them; absent: no wait).
         * `pre` the pre-hit offered, `n,eta,walk,dies` (n: the offer on the same creep, -1 none; absent: none). `far` present when the walk-in limit was given: `n,ok` per creep it was asked about, `;`-joined, `-` when none.
         * `idle` present when the idle swing was asked: `0` none found, else `n,kind,eta,due,walk,dies,ranged`. The answer: `ans` (`n` of the offer chosen, `pre`, `idle` or `none`) and `ak` (its kind, `none`).
         * `sd` (absent: 0) the creeps this scan's filter refused because their hit place read deadly (`Ours.PickSafe`); they show as mine 0 in `tg`. A replay ignores it.
         * Logged when the answer (creep or kind) or `sd` being nonzero changes, else every 5 s while targets are offered; scans with nothing offered and nothing chosen are left out.
         */
        sd: "num",
        ord: "str",
        tg: "str",
        cur: "num",
        pre: "str",
        far: "str",
        idle: "str",
        ans: "str",
    },
    /**
     * Sustain (steps 3-5, `Ours.Sustain`): one attempt sustain_act.ts carried out, at its end. `k` the answer's kind (`use`, `step_out_use`, `give`, `wait`; `buy` for a purchase and its delivery), `it` the item, `to` the ally (give),
     * `why` the rule, `hp0`/`hp1` HP at the order and at the end (absolute), `mp0`/`mp1` mana, `sec` seconds from the order, `ed` how it ended: `started` (the buff or the charge went), `done`, `topped`,
     * `interrupted` (a hero reached us on a step-out), `cut` (the hero left the laning mode mid-walk), `released` (the hero is no longer held), `missed` (no effect by the deadline), `dead`;
     * a wait: `done` (the answer changed); a delivery (a purchase, or regen on the way a wait adopted, `it` stash): `delivered` (nothing left in the stash or on the courier), `failed` (the purchase was refused: `res` its PURCHASE_ITEM_* code), `late` (not delivered by its eta plus `LateSlack`), `courier_dead`.
     */
    sustain: {
        pid: "num",
        k: "str",
        it: "str",
        to: "num",
        why: "str",
        hp0: "num",
        hp1: "num",
        mp0: "num",
        mp1: "num",
        sec: "num",
        ed: "str",
        /** Walk seconds to the tree or the safe spot when the order was given (absent: no walk). */
        wk: "num",
        /** A purchase: ActionImmediate_PurchaseItem's result code; the courier orders given; the eta read at the purchase (s). */
        res: "num",
        cor: "num",
        eta: "num",
    },
    /** Sustain (step 2): an item's values as sustain_gather.ts reads them, the first time a hero of this team holds it: one use's HP, mana, duration, and the charges it held. A 0 where the item restores something is a wrong special-value key. */
    sustain_item: {
        name: "str",
        hp: "num",
        mp: "num",
        dur: "num",
        ch: "num",
    },
    /** Sustain (step 2): a lane regen purchase by OHA's rules (item_purchase_generic.lua), with the rule (`why`), gold before, HP and mana %. */
    sustain_buy: {
        pid: "num",
        item: "str",
        why: "str",
        gold: "num",
        hp: "num",
        mp: "num",
    },
    /** Sustain (step 2): the hero's courier changed state (`st`: GetCourierState's raw COURIER_STATE_* value; the first smoke game maps them), at distance `d` from the hero. */
    sustain_courier: {
        pid: "num",
        st: "num",
        dead: "num",
        d: "num",
    },
    /** Sustain: OHA's retreat teleport home would have cast and sustain held it (SustainAct.HoldsTeleport), once per run of refusals; `why` is OHA's case (1: no enemy near, 3: level 9+ and at most one enemy), `hp` %. A refused case 1 may fall through to OHA's escape (case 2) in the same call, so a refusal followed by an `ev=cast ab=item_tpscroll` at the same `t` is an escape, not a held trip. */
    sustain_tp: {
        pid: "num",
        why: "str",
        hp: "num",
    },
    /** Slice oha-burst-left-out: the first time in a game, per level, a hero's castable spell that Valve's estimate leaves out (or never measured) is added to its burst read (SpellReady.AddedOn), once per hero, spell and spell level (a new level logs again, to show the value follows the level on an enemy handle). */
    burst_add: {
        /** The caster's player id. */
        pid: "num",
        /** The ability's name. */
        ab: "str",
        /** `left_out` (measured left out of the estimate) or `unknown` (never measured; counted anyway). */
        st: "str",
        /** The AbilityValues key read from SPELL_ADDED, and the raw value it gave before the target's resistances (a per-second key is multiplied by the window later). */
        key: "str",
        val: "num",
        /** The ability's level. */
        lvl: "num",
        /** 1 when the caster is on our team. */
        own: "num",
    },
    /** Slice chase-log: a cast by a hero on this script's team (InstallCastCallback, logged on the hero's next tick). */
    cast: {
        pid: "num",
        /** The ability's name. */
        ab: "str",
        /** Slice cast-read: its class, as ev=snap `rdy` (absent for an item or no name). */
        cl: "str",
        /** The callback's location (absent at 0,0: a no-target cast), and its distance to the episode's target when seen
         *  (the callback names no target unit: its `unit` is the caster). */
        x: "num",
        y: "num",
        el: "num",
        /** The hero's trade exchange at the log: its kind, target pid, the target seen (1/0) and its distance when seen. */
        ek: "str",
        etg: "num",
        es: "num",
        ed: "num",
        /** Seconds from the callback to this line. */
        lag: "num",
        /** The first cast per hero only: the callback table's keys as key:type, `|`-joined (its shape is unprobed). */
        ks: "str",
    },
    /** Slice chase-log: a trade exchange that lost sight of its target (`ph=lost`), then what followed within 12 s. */
    chase: {
        pid: "num",
        /** `lost`; then `seen` (the target visible again), `dead`, `gone` (neither in 12 s) or `next` (a new loss replaced it). */
        ph: "str",
        role: "str",
        /** The episode's kind and target. */
        ek: "str",
        tgt: "num",
        /** lost: seconds since the episode started; our HP share, the target's when last seen, the kill bar. */
        dur: "num",
        hp: "num",
        thp: "num",
        kh: "num",
        /** lost: our place, our team's last sighting of the target and its age (s), our distance to it and that distance past
         *  our attack range and both hulls. */
        x: "num",
        y: "num",
        lx: "num",
        ly: "num",
        tss: "num",
        d: "num",
        gap: "num",
        /** lost: our move speed, the target's last read (Threat.SeenSpeed, -1 none), and its heading over its last seen
         *  0.5 to 1 s: speed and direction (degrees, atan2 of dy, dx). */
        ms: "num",
        tms: "num",
        hv: "num",
        hd: "num",
        /** lost: our ready damage spells (as ev=cut kind=keep `sp`). */
        sp: "str",
        /** After: seconds since the loss; our hero alive; when seen, our distance to it and its HP share; our HP share; our
         *  mode; the kind of our episode on the same target then, if any. */
        dt: "num",
        alive: "num",
        mode: "num",
        onk: "str",
    },
    /** The lane creeps of an ev=cut, the same frame and pid (cut.ts). */
    cut_creeps: {
        pid: "num",
        /** `leave` for a kind=leave cut's creeps (absent for the spot's), so two cuts in one frame do not share a line. */
        kind: "str",
        /** Enemy lane creeps in sight within 3,000 of the bot or its lane front: id, x, y, HP, max HP, ranged, attack target, hull. */
        ce: "str",
        /** Our lane creeps within 3,000 of either, as `ce`. */
        ca: "str",
    },
    /** Once per team per game, before its first ev=cut: every standing tower as TOWER_IDS index, x, y, attack range, hull, attack damage, seconds per attack (the last two since `Ours.TowerRead`). */
    cut_towers: {
        team: "num",
        tw: "str",
    },
} as const;

export type EventName = keyof typeof EVENTS;
