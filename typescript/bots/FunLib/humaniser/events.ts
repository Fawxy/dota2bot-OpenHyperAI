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
    lh: "num",
    dn: "num",
    kills: "num",
    deaths: "num",
    tgt: "str",
    ln: "str",
    s: "num",
    ld: "num",
} as const;

export const BOT = {
    ...UNIT,
    mode: "str",
    d: "num",
    act: "num",
    gold: "num",
    /** Laning body's last-hit scan (states/lane_pick Describe): phase, scan and pick ages, distance to the spot, offers. */
    lf: "str",
    /** What the bot could do this second, up to 12:00, both arms (slice lane-activity): reachable last hits and denies offered. */
    ol: "num",
    od: "num",
    /** Attack range, nearest visible enemy hero within 1,200 (absent if none), hit by a hero in the last second. */
    ar: "num",
    ed: "num",
    hit: "bool",
    by: "str",
    order: "str",
} as const;

export const EVENTS = {
    lua_error: {
        pid: "mixed",
        where: "str",
        n: "num",
        msg: "str",
        tb: "str",
    },
    front: {
        team: "num",
        top: "num",
        topx: "num",
        topy: "num",
        mid: "num",
        midx: "num",
        midy: "num",
        bot: "num",
        botx: "num",
        boty: "num",
    },
    bot: {
        pid: "num",
        hero: "str",
        team: "num",
        schema: "num",
        humaniser: "bool",
        skill: "num",
        ally: "bool",
        build: "str",
        pos: "num",
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
    mode: {
        pid: "num",
        from: "str",
        to: "str",
        d: "num",
        dwell: "num",
        by: "str",
    },
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
    rune_pickup: {
        pid: "num",
        team: "num",
        rune: "num",
        kind: "str",
        x: "num",
        y: "num",
    },
    ward_place: {
        pid: "num",
        team: "num",
        kind: "str",
        x: "num",
        y: "num",
    },
    building_fall: {
        team: "num",
        kind: "str",
        id: "num",
        tier: "num",
    },
    roshan_kill: {
        team: "num",
        at: "num",
    },
    smoke_use: {
        pid: "num",
        team: "num",
        x: "num",
        y: "num",
    },
    tp: {
        pid: "num",
        team: "num",
        fx: "num",
        fy: "num",
        x: "num",
        y: "num",
        dur: "num",
        dist: "num",
    },
    aegis: {
        pid: "num",
        team: "num",
    },
    creep_revive: {
        team: "num",
        kind: "str",
        hp: "num",
    },
    creep_death: {
        team: "num",
        kind: "str",
        x: "num",
        y: "num",
        hp: "num",
        by: "mixed",
        /** 1 when one of the logging team's towers was attacking the creep on the frame before it died. */
        tw: "bool",
        bm: "str",
        bs: "num",
        p1d: "num",
        p1r: "num",
        p1t: "bool",
        p1a: "num",
        p2d: "num",
        p2r: "num",
        p2t: "bool",
        p2a: "num",
        p3d: "num",
        p3r: "num",
        p3t: "bool",
        p3a: "num",
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
    own_creep_death: {
        team: "num",
        kind: "str",
        x: "num",
        y: "num",
        hp: "num",
        by: "mixed",
    },
    player: {
        pid: "num",
        hero: "str",
        team: "num",
        human: "bool",
    },
    snap: {
        pid: "num",
        human: "bool",
        ...BOT,
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
    oha_idle: {
        pid: "num",
        mode: "num",
        held: "num",
    },
    /** Each neutral camp's spawn box once per game, from the first stack job (replay grading, hlog stacktruth.js). */
    camp: {
        idx: "num",
        team: "num",
        type: "str",
        x: "num",
        y: "num",
        x0: "num",
        y0: "num",
        x1: "num",
        y1: "num",
    },
    /** Overrides.VisionProbe (scenario games only): whether the camp's neutrals are in sight from one candidate stand point. */
    visprobe: {
        pid: "num",
        camp: "num",
        k: "num",
        x: "num",
        y: "num",
        reach: "num",
        seen: "num",
        vis: "num",
        night: "num",
    },
    stuck: {
        pid: "num",
        mode: "str",
        d: "num",
        raw: "num",
        inMode: "num",
    },
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
        adv: "num",
        eq: "num",
        a: "num",
        e: "num",
        ap: "num",
        ep: "num",
        of: "num",
        ef: "num",
        ot: "num",
        et: "num",
        cyc: "num",
        cn: "num",
        chp: "num",
        cpw: "num",
        cl: "num",
        clx: "num",
        cly: "num",
        cnn: "num",
        cnp: "num",
        fx: "num",
        fy: "num",
        dead: "num",
        ee: "str",
        ag: "str",
        cc: "str",
        tw: "num",
        twh: "num",
        ec: "str",
        ed: "str",
        ns: "str",
    },
    /** Slice lane-aggro: one line per draw (lane_aggro). */
    aggro: {
        pid: "num",
        /** `core`, or `support` (its lane core away). */
        role: "str",
        /** `feed` (enemy wave onto our ranged creep), `tower` (their creeps drawn out of their tower), `drag` (a dying creep
         *  away from an enemy hero) or `back` (wave_hold's drag: their wave behind our T1 to our next wave). */
        kind: "str",
        /** feed: `denied` (our deny), `lost` (it died otherwise), `alive` (not dead in FeedWatch); drag: `ok` (our last hit),
         *  `lost`, `alive`; tower: `ok` (a drawn creep out of the tower's reach), `stayed`; back: `ok` (a drawn creep within
         *  BackOut of the point behind our T1 at the walk's end), `stayed`; all: `no_draw` (no creep took us within DrawCheck), `hurt`, `died`, `cancelled`, `stale` (not stepped for StaleActing/StaleWatch: the caller lost the frame). */
        result: "str",
        tgt: "num",
        /** Enemy lane creeps within 500 at the order; most targeting the bot during the walk; most on the fed creep after it. */
        near: "num",
        drawn: "num",
        /** Enemy creeps near at the order that moved MovedR since (drawn off their fight), most at once. */
        mv: "num",
        onr: "num",
        /** feed: the fed creep's HP fraction at the result line, when alive. */
        rhp: "num",
        /** HP the bot lost from the start to the hand-back (min HP), and its HP fraction at the start. */
        dhp: "num",
        hp: "num",
        /** Lane push reading at a feed: clash between the T1s (0 ours) and its state. */
        q: "num",
        st: "str",
        /** drag: enemy hero to creep distance at the hand-back. */
        hd: "num",
        /** feed: seconds from the order to the drop order. */
        drop: "num",
        dur: "num",
        /** feed: the clash's distance from our T1 along the lane now, and forecast (own + move), against the lane's target point. */
        own: "num",
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
    },
    /** Slice core-in-lane (wave_hold, Ours.CoreHold): one line per hold of their wave while ours is gone, at its end. */
    wave_hold: {
        pid: "num",
        lane: "num",
        /** The last branch: `hold` (at the lane target, lane_spot input `hold`), `drag` (lane_aggro `back` behind our T1),
         *  `retreat` (OHA's retreat took the core). */
        br: "str",
        /** `met` (our wave reached theirs), `cleared` (none of theirs left), `tower` (theirs reached our T1, hold branch),
         *  `hurt`, `left` (not stepped; `md`), `died`, `timeout`. */
        res: "str",
        /** Why our wave was gone (logged only): `pull` (an ally's pull job on the lane), `aggro` (our lane-aggro tower move in
         *  the last 20 s), `other`. */
        why: "str",
        /** Their lane creeps in the stretch at the start; our last hits and denies during the attempt. */
        n: "num",
        lh: "num",
        dn: "num",
        /** Their front's distance from our T1 along the lane at the start, its least during the attempt, and when the waves met. */
        own0: "num",
        omin: "num",
        mo: "num",
        /** 1 when one of their creeps came within our T1's range (700) during the attempt. */
        tw: "num",
        /** The lane's target point (lane_aggro TargetOf). */
        tgt: "num",
        /** Seconds to our next wave at the hold point at the start; at the last branch read: seconds the drag needs and to our
         *  next wave behind the T1. */
        nw: "num",
        ds: "num",
        nb: "num",
        /** The enemy hero whose reach made the threat, at the last read that saw one. */
        thr: "num",
        /** Branch changes during the attempt. */
        sw: "num",
        hp: "num",
        dhp: "num",
        dur: "num",
        /** The bot's active mode when the attempt was left. */
        md: "num",
    },
    /** Slice lane-aggro: why a laner that owns the move did not draw (the first gate that said no), on change, at most every 3 s. */
    aggro_skip: {
        pid: "num",
        role: "str",
        /** A shared gate (`cooldown`, `lane`, `hp`, `trading`, `tower`, `pull`, `reach`), `drag`, or `tower:<why>` / `feed:<why>`. */
        why: "str",
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
    // Slice job-chooser: one start and one end per started job attempt, in both arms of Ours.JobChooser.
    job: {
        pid: "num",
        job: "str",
        phase: "str",
        why: "str",
        host: "num",
        hit: "num",
    },
    stack: {
        pid: "num",
        min: "num",
        res: "str",
        why: "str",
        camp: "num",
        type: "str",
        start: "num",
        aggro: "mixed",
        before: "mixed",
        after: "mixed",
        fresh: "mixed",
        away: "num",
        death: "num",
        cx: "mixed",
        cy: "mixed",
        dist: "mixed",
        near: "mixed",
        inbox: "mixed",
        vis: "mixed",
        box59: "mixed",
        pulled59: "mixed",
        bot59: "mixed",
        vis59: "mixed",
        exit59: "mixed",
        hitd: "mixed",
        tgt2: "mixed",
        tgt59: "mixed",
        strict59: "mixed",
        arr: "mixed",
        hit0: "mixed",
        dmg: "mixed",
        react: "mixed",
        exit: "mixed",
        hpa: "mixed",
        hpe: "mixed",
        hp59: "mixed",
        casts: "str",
        n2: "str",
        n59: "str",
        trk: "str",
        lane: "mixed",
        idle: "num",
        // Slice double-stack: camp A of a double (hit first), or `double=0` when the partner's walk did not fit.
        double: "num",
        dwhy: "str",
        fres: "str",
        fcamp: "num",
        ftype: "str",
        faggro: "mixed",
        fbefore: "mixed",
        ffresh: "mixed",
        fbox59: "mixed",
        fhitd: "mixed",
        farr: "mixed",
        fseen: "num",
        fchk: "mixed",
        fhit0: "mixed",
        fhpa: "mixed",
        fauto: "mixed",
        fn2: "str",
        fn59: "str",
        ftrk: "str",
        early: "num",
        fearly: "num",
        // Valve's window of the camp (`w0-w1`) and the confirmed hit's offset from it (0 inside); `f` for camp A.
        win: "str",
        woff: "mixed",
        fwin: "str",
        fwoff: "mixed",
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
    lh: {
        pid: "num",
        kind: "str",
        result: "str",
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
    /** One per in-lane trade window (states/core_trade): taken (`done`, `kill`) or offered and not taken (`lost`). */
    trade: {
        pid: "num",
        /** `core` (Core in lane's trade) or `support` (Support in lane's harass, slice support-spot). */
        role: "str",
        /** 1 when the core's lane fights are ours (slice lane-fight, `Ours.CoreLaneFight`): its kill cut is the commit's 40%. */
        lf: "num",
        /** `trade`, `kill` (a commit) or `fight` (a lane fight from the play roll: rolled here or joined). */
        kind: "str",
        tgt: "num",
        /** A `fight`'s play id (`ev=play` id) and 1 when the hero joined another hero's play, 0 when it rolled its own. */
        play: "num",
        join: "num",
        result: "str",
        why: "str",
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
        kind: "str",
        tgt: "num",
        w: "num",
        fl: "num",
        fc: "num",
        fh: "num",
        fr: "num",
        ft: "num",
        ff: "num",
        fth: "num",
        al: "num",
        en: "num",
        zero: "str",
        sure: "str",
        pc: "num",
        draw: "num",
        fire: "num",
        id: "num",
    },
    // One line per fired play's end (Plays.End): res kill (target dead with a play hero within KillNear, up to KillAfter s
    // after the end) | trade (target and initiator dead) | died | forced (target under ForcedHp or moved ForcedMoved) | none,
    // or the consumer's own; written up to KillAfter s after the end (dur stays the play's own length); why the consumer's end reason or timeout (Plays.Tick); join heroes that joined; dur seconds.
    play_end: {
        id: "num",
        pid: "num",
        kind: "str",
        tgt: "num",
        res: "str",
        why: "str",
        join: "num",
        dur: "num",
    },
    // Slice rune-spawn: the team's 6:00 plan, once per team at RunePlan PlanAt and again each time a planned support's start
    // gate drops it: mid / sup the planned heroes' pids, ms / ss their spots' rune ids; why no-free-support or no-mid when a
    // side is empty, swap:<gate> when the spot went to the other support, drop:<gate> when no support was free for it.
    rune_plan: {
        team: "num",
        mid: "num",
        ms: "num",
        sup: "num",
        ss: "num",
        why: "str",
    },
    rune_try: {
        pid: "num",
        rune: "num",
        res: "str",
        d: "num",
        act0: "num",
        act: "num",
        st: "num",
        dt: "num",
    },
    // Slice core-next-gold (CoreCamp): an in-lane core's camp trip. phase start, next (a chained camp), skip (a camp fitted and a
    // gate held it: one line per wave window `win` and why), end. clash: the forecast's next clash second; ret: the planned
    // return; clr: clear estimate; gold, loss (forecast lane gold lost by the return), net; end: back (arrival), g0/g1 net worth.
    core_camp: {
        pid: "num",
        pos: "num",
        lane: "num",
        phase: "str",
        clash: "num",
        win: "num",
        camp: "num",
        type: "str",
        ret: "num",
        clr: "num",
        hpc: "num",
        src: "str",
        clrt: "num",
        hpt: "num",
        clrm: "num",
        hpm: "num",
        n0: "num",
        nu: "str",
        nl: "num",
        gold: "num",
        loss: "num",
        net: "num",
        why: "str",
        after: "str",
        res: "str",
        label: "str",
        camps: "num",
        back: "num",
        g0: "num",
        g1: "num",
        secs: "num",
        pace: "num",
        hp: "num",
        hpr: "num",
        min: "num",
        h_dead: "num",
        h_mode: "num",
        h_hp: "num",
        h_far: "num",
        h_wave: "num",
        h_camp: "num",
        h_fc: "num",
        h_clash: "num",
        h_gap: "num",
        h_plan: "num",
        h_skip: "num",
        h_trip: "num",
    },
    rune_job: {
        pid: "num",
        pos: "num",
        kind: "str",
        spawn: "num",
        res: "str",
        why: "str",
        label: "str",
        side: "str",
        left: "num",
        arr: "num",
        away: "num",
        died: "num",
        hit: "num",
        idle: "num",
        phase: "str",
        ta: "num",
        te: "num",
        hid: "num",
        sh: "num",
        sph: "num",
        via: "num",
        route: "str",
        vclr: "num",
        vage: "num",
        voff: "num",
        vbad: "num",
        vpts: "str",
        play: "num",
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
    pull_job: {
        pid: "num",
        pos: "num",
        lane: "num",
        camp: "num",
        slot: "num",
        res: "str",
        why: "str",
        label: "str",
        div: "num",
        n: "num",
        left: "num",
        away: "num",
        died: "num",
        hit: "num",
        idle: "num",
        wd: "num",
        nn: "num",
        dt: "num",
        cn: "num",
        cs: "num",
        chp: "num",
        cv: "num",
        cdmg: "num",
        php: "num",
        se: "num",
        // sh the hit's shift from the plan's slot at the order, s0 the first creep-timed shift, lv creep reads (slice pull-half;
        // before it, the wave body's shift and LiveRead's readings).
        sh: "num",
        lv: "num",
        s0: "num",
        // Slice pull-half: the pull's kind (full or half); its creep-timed hit (pull_timing CreepTimer) at the order: hr geo
        // (timed on the aimed creep: a full pull's front one, a half pull's second) or plan (never read), hc creeps read, hn
        // the creep after the aimed one and hb the back creep: predicted distance past the meet point at the neutrals' arrival.
        // A half pull's clearance search on that hit: hf the nearest the front two creeps come to an aggro source (the
        // neutrals, or the hit puller in HalfAcquire's frame), hu the nearest the third comes, hm the smaller of hf - 500 and
        // 500 - hu (negative: no hit keeps the front two out and turns the third), hs how far short of the meet point the
        // puller stands (HalfStandBack); hi the live step-in's offset from that point towards the meet point when the wave
        // engaged (negative: back towards the camp).
        pk: "str",
        hr: "str",
        hc: "num",
        hn: "num",
        hb: "num",
        hf: "num",
        hu: "num",
        hm: "num",
        hs: "num",
        hi: "num",
        ht: "num",
        g4: "num",
        gh: "num",
        na: "num",
        gu: "num",
        gd: "num",
        wa: "num",
        // nm: the first tagged neutral 50 from where it stood at the hit (the camp's start; phchk2 replays 0.4-2.3 s after
        // the order).
        nm: "num",
    },
    // Slice pull-half (the half-pull harness): one line per lane creep of ours seen near the watch after the hit, written
    // with the pull's pull_job line. ci its order of appearance (0 first, about the front), rg ranged (1|0), tr 1 when its
    // attack target became one of the camp's neutrals before the line was written, else 0. The rest are read at the turn
    // (tr 1) or at its nearest approach to the puller (tr 0): tt seconds after the hit (ht), dp its distance to the puller,
    // dn to the nearest tagged neutral alive, ph 1 when a tagged neutral had the puller as its attack target, pv the puller's
    // speed over the last frame (0 standing), po the puller's distance off the lane path, ca the creep's distance along the
    // lane past the meet point (negative: short of it). The measurement behind HalfHeroAggro (EC-090: no written rule).
    // The creep's decision frame, before its target shows: lt seconds after the hit its distance off the lane path first
    // rose PullJob Leave above its own least so far (it left the lane), ld its distance to the puller and ln to the nearest
    // tagged neutral then; unset when it never left.
    pull_creep: {
        pid: "num",
        slot: "num",
        camp: "num",
        ci: "num",
        rg: "num",
        tr: "num",
        tt: "num",
        dp: "num",
        dn: "num",
        ph: "num",
        pv: "num",
        po: "num",
        ca: "num",
        lt: "num",
        ld: "num",
        ln: "num",
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
        slot: "num",
        ph: "str",
        wc: "num",
        won: "num",
        whe: "num",
        wcr: "num",
        wid: "num",
        wd: "num",
        nn: "num",
        ntp: "num",
        ntc: "num",
        ntx: "num",
        nd: "num",
        nh: "num",
        nt: "str",
        pd: "num",
        tn: "num",
        tp: "num",
        tc: "num",
        td: "num",
        th: "num",
    },
    // Slice support-lane: one line per judgement decision (bot-structure s2). kind: the decision (pull); go 1|0; want: the
    // reading asked for it; why: what held it back (a start check, partner, late) or `lane` when the reading did not want it;
    // pull fields: slot (planned hit second), st (push state OUT|HOLD|IN), q (clash between the T1s, 0 ours 1 theirs), mv
    // (clash move over 30 s from our side), cf (the same with our walking wave removed), tw (tower rule decided), ms (cost);
    // the camp as the API returns it at the decision: cn neutrals in its box, cs of them CanBeSeen, chp their health, cv the
    // camp's origin visible (1|0), cdmg its expected damage on the puller over the pull (PullJob CampDamage; set once the lane
    // wants the pull), php the puller's HP. why empty | one (a seen camp down to one neutral; PullJob CampGate) | camp-dmg (cdmg would leave php under StartReserve) | enemy-site (se, the nearest enemy
    // hero to the stand or meet point, within PullJob SiteEnemy).
    choice: {
        pid: "num",
        kind: "str",
        go: "num",
        want: "num",
        why: "str",
        src: "str",
        lane: "num",
        slot: "num",
        st: "str",
        q: "num",
        mv: "num",
        cf: "num",
        tw: "num",
        ms: "num",
        cn: "num",
        cs: "num",
        chp: "num",
        cv: "num",
        cdmg: "num",
        php: "num",
        se: "num",
        // Slice pull-half: the pull's kind for kind=pull (full or half); hm a half pull's clearance margin when it stayed for
        // want of one (why=half-geo; pull_job hm).
        pk: "str",
        hm: "num",
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
        d: "num",
        owned: "bool",
        running: "bool",
        label: "str",
        mode: "num",
        /** The spot's anchor (creep, front, wave, fed: lane_aggro's fed creep going down), or oha. */
        spot: "str",
        pushed: "num",
        why: "str",
        hm: "num",
        ut: "num",
        sx: "num",
        sy: "num",
        hph: "num",
        /** The nearest visible enemy hero (slice support-spot): its distance, its ready damaging abilities (trained, not
         *  passive, off cooldown, mana for it) and the longest cast range among them (0 with none ready). */
        ne: "num",
        nk: "num",
        nr: "num",
    },
} as const;

export type EventName = keyof typeof EVENTS;
