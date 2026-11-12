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
    /** Who holds the hero, as `<mode> <desire> by <source>`; the source is empty where the mode is one of Valve's built-ins. Read by `lane_activity` and `@mode_hold`. */
    by: "str",
    order: "str",
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
    },
    /** An ENEMY lane creep (as seen by the logging team) that was seen last frame and is gone this frame at 50% health or less, within 1,500 of a living own hero. Logged per team by a frame job (`Telemetry.Creeps`, 0:00 to `Telemetry.CreepDeathUntil`, 720 s), in both arms. Mirror: `own_creep_death`. */
    creep_death: {
        /** The logging team: the team whose module saw the death. A row is an enemy lane creep seen by that team, so the same creep may also be in the other team's `own_creep_death`. */
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
    /** Slice lane-farm-logs: a neutral creep that died within 1,500 of one of the logging team's heroes. `by` the hero whose
     *  last hits rose (a pid) or `none`; `camp` the nearest camp's spawner index within 1,200; `np`/`nd` the nearest own hero. */
    neutral_death: {
        team: "num",
        kind: "str",
        x: "num",
        y: "num",
        hp: "num",
        by: "mixed",
        camp: "num",
        np: "num",
        nd: "num",
    },
    /** Mirror of `creep_death` for the logging team's OWN lane creeps (same job, range, 50% rule and limit). Joined to the other team's `creep_death` in view `creep_fate`. */
    own_creep_death: {
        /** The logging team, which owns the creep. A `creep_death` row is the other team's view of an enemy creep; this row is the owner's view of its own. */
        team: "num",
        kind: "str",
        x: "num",
        y: "num",
        hp: "num",
        /** The pid of an own hero whose denies rose (each rise takes its nearest unclaimed death within 1,200), else `none`: an enemy last hit, a tower or creep kill, or not attributable. The other team's `creep_death` with `by=none` is paired to a denier here. */
        by: "mixed",
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
    /** The window's 25 largest rows. Rows overlap across kinds; sum within `entry` only. */
    perf_top: {
        vm: "str",
        /** `entry` (an OHA entry point), `ours` (an outermost guarded call) or `sub` (a guarded call made directly from an outermost one). */
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
        /** `met` (our wave reached theirs), `cleared` (none of theirs left), `tower` (theirs reached our T1, hold branch),
         *  `hurt`, `left` (not stepped; `md`), `died`, `timeout`, `unsafe` (an enemy hero pushed the held spot inside
         *  the hold point's floor), `concede` (the cost rule: over budget with no drag in time, or the drag's draw did not start;
         *  `cr`). */
        res: "str",
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
     *  StackEvery, LaneOnly; `name` the key) still set, which now does nothing. */
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
         *  cast is released), 0 at the timeout with the first failing check `fail` (setup|hp|hplow|holds|lacks|clear|near|hit|past|behind: the rep is
         *  invalid), `secs` from the rep's start, the cast's HP share `hp`; ph=spot once per rig spot: its point `x`, `y`, how
         *  far it moved to be passable `d`, the nearest Radiant and Dire tower `rt`, `dt`; ph=wait when the cast's first
         *  failing ready check `fail` changes; ph=buy per purchase try (`step` the item, `res` the API's result, `gold`); ph=ready
         *  also carries `rend` (the rep's end), `win` (the end of the stage the rule lives in; a rep ending after it is outside)
         *  and `rel` (the release list's modes but `idle`, comma-separated); ph=wait and ph=ready carry `d`, the nearest hero
         *  that hit the cast in the last second, as distance past the cast's trade reach. */
        var: "str",
        win: "num",
        rel: "str",
        i: "num",
        step: "str",
        ok: "num",
        fail: "str",
        hp: "num",
        rt: "num",
        dt: "num",
        gold: "num",
    },
    // Slice job-chooser: one start and one end per started job attempt, in both arms of Ours.JobChooser.
    job: {
        pid: "num",
        /** `stack`, `rune` or `pull`. */
        job: "str",
        /** `start` (`why=trigger`) or `end`. */
        phase: "str",
        /** On `end`: the job's `ev=stack`, `ev=rune_job` or `ev=pull_job` `why`. */
        why: "str",
        /** The hosting mode's number. */
        host: "num",
        /** 1 when hero damage landed during the job. */
        hit: "num",
    },
    /** One line per trigger minute (3, 5, 7) of the pos5's stack job (`Ours.StackExecute`; none with the switch off). Written after the job's walk-off, once the box was read, the hero died, or `ReadUntil` (5 s, 12 s on a double) passed, so `t` is up to that after the `ev=job phase=end` line. Pair by `start`..`t`. */
    stack: {
        pid: "num",
        /** The trigger minute. */
        min: "num",
        /** `stacked` (a neutral not seen during the job appeared in the box after :00), `not_stacked`, `unseen` (hit landed, box never in sight after :00), `failed` (no hit landed) or `skip` (no job started). A log's stacked rate is a lower bound; the replay grades it (`stacktruth.js`). */
        res: "str",
        /** On `failed`, the job's end reason (`missed:mistake:no-aggro`, `no_target:mistake:no-camp`, `cancelled:hit`, `preempted:mode=N`, `dead`). On `skip`, the last gate (`low-hp`, `enemy-near`, `hit`, `busy`, `late`, `no-camp`, `refused`). */
        why: "str",
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
    lanefight_mem: {
        pid: "num",
        enemy: "num",
        ability: "str",
        remembered: "num",
        reason: "str",
        cls: "str",
        cd: "num",
        src: "str",
    },
    lanefight_watch: {
        pid: "num",
        polls: "num",
        visible: "num",
        casts: "num",
        recorded: "num",
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
    tr_laning: {
        pid: "num",
        laning: "bool",
        why: "str",
    },
    tr_lost: {
        pid: "num",
        lost: "bool",
        reason: "str",
        deaths: "num",
        levelGap: "num",
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
    /** Slice threat: one consumer's decision on a threat read (threat.ts Log): consumer, decision, place, horizon (s), threat,
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
     *  reach, burst, tower), the budget and its purpose, the anchor kind, its route cost and the next-best anchor's (alt), and
     *  for a forced drill rep the start spot. End: res (gone: nobody in reach; safe: the band's dwell; healed: a heal walk back over HealBack with the lane nearer than the fountain; anchor, died, cut), secs, HP lost (hpl, share of max), whether the
     *  walk passed enemy tower (twr) or wave (wave) reach, hero damage taken (dmgh, share of max). ph=skip: a drill rep the
     *  cast started under the low-HP bar (healed instead). ph=read: an owned hero out of an episode whose read changed band
     *  (the chase drill grades the band on reps with no entry), with crp: an enemy creep hit it in the last second. ph=stay
     *  (RetreatOdds): once per over-budget spell, the read held only because the heroes in reach do not outnumber us. */
    retreat: {
        /** `start` or `end` of an episode, `read` (a band change out of an episode), `stay` (once per over-budget spell the `Ours.RetreatOdds` hold keeps in lane), `skip`, `items`, `use`, `items_off`. */
        ph: "str",
        pid: "num",
        /** `plain` for a walk by a hero our retreat does not own; else our episode. */
        kind: "str",
        /** The episode number. */
        ep: "num",
        /** On `start`: `threat`, `lethal`, `tower`, `heal` or `forced`. */
        why: "str",
        /** The hero's HP share at the line. */
        hp: "num",
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
        /** On `end`: `gone` (nobody in reach), `safe` (the band's dwell), `healed` (a heal walk back over `HealBack` with the lane nearer than the fountain; `Ours.HealStop`), `anchor`, `died` or `cut`. */
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
        /** HealItems (ph=items, use, items_off): HP to HealBack, the usable heal items, the set used (or the item, on use), what it restores, a tree near, why not. */
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
        /** The creep's id (Telemetry CreepId), the same as on its ev=creep_death or ev=own_creep_death. */
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
     * An enemy hero hit this in-lane hero within 1 s and no trade opened (states/core_trade): at most one per hero per 5 s.
     * `why`: `no_target` (no enemy hero within `reach`), `play` (a play drives the hero), a trade respect (`tower`,
     * `outnumbered`, `low_hp`, `behind`, `creeps`, `wave`), `gap` (waiting for the HP gap a lost trade left), or `hb_<respect>`
     * (the hit back itself refused).
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
    /** One per in-lane trade window (states/core_trade): taken (`done`, `kill`) or offered and not taken (`lost`). */
    trade: {
        pid: "num",
        /** `core` (Core in lane's trade) or `support` (Support in lane's harass, slice support-spot). */
        role: "str",
        /** 1 when the core's lane fights are ours (slice lane-fight, `Ours.CoreLaneFight`): its kill cut is the commit's 40%. */
        lf: "num",
        /** `trade`, `kill` (a commit) or `fight` (a lane fight from the play roll: rolled here or joined). */
        kind: "str",
        /** The target hero's pid. */
        tgt: "num",
        /** 1 for a hit back (slice hit-back, `Ours.HitBack`): opened on a hero hitting us inside our creeps' aggro. */
        hb: "num",
        /** A `fight`'s play id (`ev=play` id) and 1 when the hero joined another hero's play, 0 when it rolled its own. */
        play: "num",
        join: "num",
        /** `done` (taken), `kill` (the game says the target died, `IsHeroAlive`) or `lost` (offered, not taken within 1 s; `mode`/`md` is the mode that held the core). */
        result: "str",
        /** How the window ended. A `fight`'s `why` adds `hp` (under the roll's HP floor), `play_end` and `time`. */
        why: "str",
        /** Seconds the window lasted. */
        dur: "num",
        /** HP the bot and the target lost from the trade's start to its end. */
        hpd: "num",
        thpd: "num",
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
        /** `tower_reach`, `tower_range`, `hero_radius`, `lane_creep_speed`, `neutral_speed` or `neutral_speed_<small|medium|large|ancient>`; `attack_period` and `attack_point` are fallbacks logged on first use. */
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
        /** The hero's lineup position. */
        pos: "num",
        /** `power`, `wisdom` or `contest` (the enemy shrine play's trip). */
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
    // cancelled:one / cancelled:camp-dmg: the camp seen on the walk (PullJob CampGate, StartReserve); interrupted:bail: the puller stepped
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
    /** One line per pull the support's pull job started (`Ours.SupportPull`). Views `pull_attempts`, `pull_waves` and `pull_watch_cases` read it. */
    pull_job: {
        pid: "num",
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
    // wants the pull), php the puller's HP. why empty | one (a seen camp down to one neutral; PullJob CampGate) | camp-dmg (cdmg would leave php under StartReserve) | enemy-site (se, the nearest enemy
    // hero to the stand or meet point, within PullJob SiteEnemy; Ours.Threat off) | threat | missing (Threat.Gate at the camp, `ev=threat who=pull_job`;
    // Ours.Threat on).
    choice: {
        pid: "num",
        /** The decision; `pull` today. */
        kind: "str",
        /** 1 when the pull started. */
        go: "num",
        /** 1 when the reading wanted a pull. */
        want: "num",
        /** What held a wanted pull back: a start check (`enemy-near`, a higher job's name, `partner-low`, `partner-gank`, `acting`, `late`, `refused`), `empty`, `one`, `camp-dmg`, `enemy-site`, `threat`, `missing`; `lane` when not wanted; `no-read` when the run left no clash. Also `ctl`, `no_ctl`, `ew` and `drill` from the lane controller and drills. */
        why: "str",
        /** Who decided: `own` or `ping`. */
        src: "str",
        /** The lane. */
        lane: "num",
        /** The planned hit second. */
        slot: "num",
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
        /** The first limit the preferred point broke, which usually placed the spot: `pref`, `hero`, `creep`, `hp` (only the HP margin moved it), `tower` or `xp`. */
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
        /** Reads made this frame. */
        rn: "num",
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
} as const;

export type EventName = keyof typeof EVENTS;
