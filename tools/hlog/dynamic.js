// Dynamic-game metrics (GOALS O3/O4, O1 guard rails) from ev=snap and ev=lasthit, for 5v5 bot games where all ten
// bots log snapshots. Definitions: docs/team/slices/15-dynamic-metrics.md (master repo). Geometry, the encounter rule and the
// rotation rule follow the replay moment index (research/replay-index/moments.js) so bot and replay moments compare.
// Moving into the log store (docs/team/slices/retire-dynamic-a.md, part A of three): the per-second series, deaths, last hits
// at 10:00, home lanes, lineup positions, encounters, fights, idle episodes and the error counts are the named queries
// `@dynamic_heroes`, `@dynamic_game` and `@dynamic_deaths` (rules in queries/fragments/hero_second.sql, hero_death.sql and
// lane_label.sql). Rotations, lane exits, teleports, steals and the world metrics still read the parsed game (`series`) here.
'use strict';

const fs = require('fs');
const path = require('path');
const { parseLog } = require('./parse');

const C = {
    R_AWARE: 1200, // heroes within this many units count as meeting
    GAP_ENC: 5, // an encounter needs the pair apart for this many seconds first
    MERGE_ENC: 3, // an onset this close (s) to an encounter's first onset joins it
    LANE_R: 1100, // distance from a lane polyline that still counts as that lane
    BASE_R: 1800, // within this of an ancient counts as base
    FOUNTAIN_R: 1200, // within this of a fountain counts as base too (fountains lie just outside BASE_R)
    DEAD_GAP: 2.5, // bots log no snapshot while dead: a longer gap across a deaths increment is a death
    ROT_MIN_S: 10, // seconds in another lane region before 10:00 that make a rotation
    ROT_GAP: 8, // seconds of river or jungle that keep a rotation run open
    FIGHT_GAP: 15, // seconds between consecutive deaths in one fight (OpenDota teamfight convention)
    FIGHT_MIN_DEATHS: 3,
    TP_JUMP: 2500, // units moved within TP_WINDOW seconds while alive: a teleport
    TP_WINDOW: 2,
    TP_JOIN_R: 1200, // a teleport that lands this close to an ally joins them
    STEAL_R: 700, // EC-050/055; judgement
    AUDIT_BUF: 150, // slice 3: a core within attack range + this of the creep could take it; judgement
    IDLE_S: 10,
    IDLE_R: 100,
    // World events (slice 23).
    POWER_FROM: 360, // power spots hold water runes before 6:00 (RUNE_RULES)
    WISDOM_FIRST: 420, // Shrines of Wisdom fill at 7:00, then every 7:00 (RUNE_RULES)
    WISDOM_R: 300, // stand within 300 of the shrine for 3 s (Liquipedia 7.41; states/rotate.ts)
    WISDOM_CHANNEL: 3,
    WISDOM_LATE: 15, // EC-008: taken within 15 s
    SENTRY_BY: 90, // EC-006: placed by 1:30
    SMOKE_MERGE: 3, // smokes this close (s) on one team are one smoke (one cast covers the group)
    TP_MOVED: 1000, // a tp ending closer than this to its start was cancelled
    CASH_IN: 120, // EC-013: tower within 120 s of a 3+ kill burst
    ROSH_FOLLOW: 240, // EC-014: tower within 240 s of Roshan
    AEGIS_AFTER: 30, // an aegis picked up this soon after a Roshan kill names the killing team
};
// mode_rune_generic's shrine spots (states/rotate.ts SHRINE).
const SHRINE = { 2: [-7948, 768], 3: [8029, -1126] };

// 7.41 tower and ancient positions from three validated pro replays (research/replay-index, extractor meta).
const TOWERS = [
    [2, -3952, -6112], [2, -4640, -4144], [2, -6592, -3408], [2, -360, -6256], [2, 4860, -6379], [2, -3190, -2926],
    [2, -6501, -872], [2, -6336, 1856], [2, -5712, -4864], [2, -5392, -5192], [2, -1544, -1408],
    [3, 4944, 4776], [3, -128, 6016], [3, -5275, 6036], [3, 2496, 2112], [3, 524, 652], [3, 6400, 384], [3, 6336, 3032],
    [3, 3552, 5776], [3, 4272, 3759], [3, 5280, 4432], [3, 6269, -2240],
];
const ANCIENT = { 2: [-5920, -5352], 3: [5528, 5000] };
// Mean respawn position over 321 deaths in the nf0 batch (all within 400 units).
const FOUNTAIN = { 2: [-6850, -6461], 3: [7020, 6345] };

const dist = (a, b) => Math.hypot(a[0] - b[0], a[1] - b[1]);

/** Lane polylines from ancient through each lane's towers to the other ancient (as moments.js `lanes`). */
function lanePolys() {
    const laneOf = ([x, y]) =>
        (x < -5800 && y > -4000) || (y > 5500 && x < 3000) ? 'top' : (y < -5500 && x > -4500) || (x > 5800 && y < 4000) ? 'bot' : 'mid';
    const by = { top: [], mid: [], bot: [] };
    for (const [team, x, y] of TOWERS) if (dist([x, y], ANCIENT[team]) >= 1500) by[laneOf([x, y])].push({ team, x, y });
    const poly = {};
    for (const L of Object.keys(by)) {
        const key = { top: [b => b.y, b => b.x], bot: [b => b.x, b => b.y], mid: [b => b.x + b.y, b => b.x + b.y] }[L];
        const rad = by[L].filter(b => b.team === 2).sort((a, b) => key[0](a) - key[0](b));
        const dire = by[L].filter(b => b.team === 3).sort((a, b) => key[1](a) - key[1](b));
        poly[L] = [ANCIENT[2], ...rad.map(b => [b.x, b.y]), ...dire.map(b => [b.x, b.y]), ANCIENT[3]];
    }
    return poly;
}
const POLY = lanePolys();

function segDist(p, a, b) {
    const dx = b[0] - a[0], dy = b[1] - a[1], l2 = dx * dx + dy * dy;
    const t = l2 ? Math.max(0, Math.min(1, ((p[0] - a[0]) * dx + (p[1] - a[1]) * dy) / l2)) : 0;
    return Math.hypot(p[0] - (a[0] + t * dx), p[1] - (a[1] + t * dy));
}

/** 'base' | 'top' | 'mid' | 'bot' | 'other' for a map point. */
function laneLabel(p) {
    for (const t of [2, 3]) if (dist(p, ANCIENT[t]) < C.BASE_R || dist(p, FOUNTAIN[t]) < C.FOUNTAIN_R) return 'base';
    let best = 'other', bd = C.LANE_R;
    for (const [L, P] of Object.entries(POLY)) {
        for (let i = 0; i + 1 < P.length; i++) {
            const d = segDist(p, P[i], P[i + 1]);
            if (d < bd) [bd, best] = [d, L];
        }
    }
    return best;
}

/** True when the gap after snapshot i is dead time: bots log no snapshot while dead, so a gap > DEAD_GAP that crosses a
 *  deaths increment, or that runs to the end of the game (`last`), is a death. */
function deadAfter(snaps, i, last) {
    const a = snaps[i], b = snaps[i + 1];
    if (!b) return last - a.t > C.DEAD_GAP;
    return b.t - a.t > C.DEAD_GAP && typeof b.deaths === 'number' && b.deaths > (a.deaths || 0);
}

/** Per bot: snapshots resampled to whole seconds up to the last snapshot of any bot. Each second holds the latest snap at or
 *  before it, or during a death gap (deadAfter) a copy of it with alive=0. */
function series(game) {
    const out = {};
    const bots = Object.values(game.bots).filter(b => b.team !== undefined && b.snaps.some(s => typeof s.x === 'number'));
    const last = Math.max(...bots.map(b => Math.max(...b.snaps.map(s => s.t))));
    for (const b of bots) {
        const snaps = b.snaps.filter(s => typeof s.x === 'number').sort((a, c) => a.t - c.t);
        const sec = {};
        let i = 0, dead;
        for (let t = Math.ceil(snaps[0].t); t <= Math.floor(last); t++) {
            while (i + 1 < snaps.length && snaps[i + 1].t <= t) i++;
            if (t > snaps[i].t && deadAfter(snaps, i, last)) {
                if (!dead || dead.from !== snaps[i]) dead = { ...snaps[i], alive: 0, from: snaps[i] };
                sec[t] = dead;
            } else sec[t] = snaps[i];
        }
        out[b.pid] = { pid: b.pid, hero: b.hero, team: b.team, sec, snaps, last };
    }
    return out;
}

const at = (s, t) => s.sec[Math.floor(t)];
const pos = snap => [snap.x, snap.y];
const alive = snap => snap && snap.alive !== 0;

/** Roles by behaviour (each hero's `lh10` and `home` set from @dynamic_heroes): per team, the three top last-hitters at 10:00 are cores (mid core pos 2, safe-lane core pos 1,
 *  off-lane core pos 3), the other two supports (more last hits = pos 4). Avoids the bots-mode Dire pos= artefact.
 *  Fallbacks (no mid core, no safe-lane core) are reported in `warnings`. */
function roles(S, warnings = []) {
    const out = {};
    for (const team of [2, 3]) {
        const bots = Object.values(S).filter(s => s.team === team);
        bots.sort((a, b) => b.lh10 - a.lh10);
        const cores = bots.slice(0, 3), sups = bots.slice(3);
        const safe = team === 2 ? 'bot' : 'top';
        const mid = cores.find(s => s.home === 'mid') || cores[0];
        if (mid && mid.home !== 'mid') warnings.push(`team ${team}: no core plays mid; pos 2 = top farmer ${mid.hero}`);
        const rest = cores.filter(s => s !== mid);
        const p1 = rest.find(s => s.home === safe) || rest[0];
        if (p1 && p1.home !== safe) warnings.push(`team ${team}: no core plays the safe lane; pos 1 = ${p1.hero}`);
        const p3 = rest.find(s => s !== p1);
        [[mid, 2], [p1, 1], [p3, 3], [sups[0], 4], [sups[1], 5]].forEach(([s, r]) => s && (out[s.pid] = r));
    }
    return out;
}

/** Rotations before `until` (moments.js rule): from 1:00, a run of >= ROT_MIN_S seconds in one lane region other than home;
 *  up to ROT_GAP s of river or jungle keep the run open (not counted), and another lane, base or death closes it. */
function rotations(s, until) {
    if (!s.home) return 0;
    let n = 0, run = null, gap = 0;
    const close = () => {
        if (run && run.n >= C.ROT_MIN_S) n++;
        run = null;
        gap = 0;
    };
    for (let t = 60; t <= until; t++) {
        const snap = s.sec[t];
        const L = t < until && alive(snap) ? laneLabel(pos(snap)) : 'x';
        if ((L === 'top' || L === 'mid' || L === 'bot') && L !== s.home) {
            if (run && run.L !== L) close();
            if (!run) run = { L, n: 0 };
            run.n++;
            gap = 0;
        } else if (run && L === 'other' && ++gap <= C.ROT_GAP) {
            // a short river or jungle stretch keeps the run open
        } else close();
    }
    return n;
}

/** First whole minute >= 5:00 after which under half of the next 60 s (alive and outside base) is in the home lane;
 *  undefined if never. */
function laneExit(s, until) {
    if (!s.home) return undefined;
    for (let t = 300; t + 60 <= until; t += 60) {
        let inLane = 0, seen = 0;
        for (let u = t; u < t + 60; u++) {
            const snap = s.sec[u];
            if (!alive(snap)) continue;
            const L = laneLabel(pos(snap));
            if (L === 'base') continue;
            seen++;
            if (L === s.home) inLane++;
        }
        if (seen > 0 && inLane / seen < 0.5) return t;
    }
    return undefined;
}

/** Teleport-like jumps (>= TP_JUMP within TP_WINDOW, alive throughout) landing outside base within TP_JOIN_R of an alive ally. */
function tpJoins(S, s, from, to) {
    let n = 0;
    for (let t = from; t < to; t++) {
        const a = s.sec[t - C.TP_WINDOW], b = s.sec[t];
        if (!alive(a) || !alive(b) || dist(pos(a), pos(b)) < C.TP_JUMP) continue;
        // The jump must not start at a respawn (dead at any second in the window).
        let dead = false;
        for (let u = t - C.TP_WINDOW; u <= t; u++) if (!alive(s.sec[u])) dead = true;
        if (dead || laneLabel(pos(b)) === 'base') continue;
        const ally = Object.values(S).some(o => o !== s && o.team === s.team && alive(o.sec[t]) && dist(pos(o.sec[t]), pos(b)) <= C.TP_JOIN_R);
        if (ally) n++;
        t += C.TP_WINDOW; // one jump counts once
    }
    return n;
}

/** Support last hits (from ev=lasthit; any unit, not only creeps) before `until` while an allied core is within STEAL_R. */
function steals(game, S, role, until) {
    let n = 0;
    for (const e of game.events) {
        if (e.ev !== 'lasthit' || e.t >= until || !S[e.pid] || !(role[e.pid] >= 4)) continue;
        const me = at(S[e.pid], e.t);
        if (!alive(me)) continue;
        const near = Object.values(S).some(o => o.team === S[e.pid].team && role[o.pid] <= 3 && alive(at(o, e.t)) && dist(pos(at(o, e.t)), pos(me)) <= C.STEAL_R);
        if (near) n += e.n || 1;
    }
    return n;
}

/**
 * Audited steals (slice 3, KR H.2) from ev=creep_death: a lane creep last-hit before `until` by an own pos4/pos5 (lineup
 * position) while an own core logged on it was attacking it (p<N>t=1) or within its attack range + AUDIT_BUF. One case per
 * creep, with the support's ev=snap mode. Undefined when the game has no ev=creep_death (older builds) or no lineup positions.
 */
function auditedSteals(game, S, lpos, until) {
    const deaths = game.events.filter(e => e.ev === 'creep_death');
    if (!deaths.length || !Object.keys(lpos).length) return undefined;
    const cases = [];
    for (const d of deaths) {
        if (d.t >= until || !(lpos[d.by] >= 4)) continue;
        const cores = Object.keys(d).map(k => k.match(/^p(\d+)d$/)).filter(Boolean).map(m => Number(m[1]));
        const why = cores
            .map(c => ({ core: c, d: d[`p${c}d`], r: d[`p${c}r`], attacking: d[`p${c}t`] === 1 }))
            .filter(c => c.attacking || c.d <= c.r + C.AUDIT_BUF);
        if (!why.length) continue;
        const snap = S[d.by] ? at(S[d.by], d.t) : undefined;
        // The mode when the killing swing started (`bm`, logged from build after f5be4cb); else the last snapshot's.
        const snapMode = snap ? snap.mode : undefined;
        cases.push({ t: d.t, team: d.team, pid: d.by, pos: lpos[d.by], mode: d.bm !== undefined ? d.bm : snapMode, snapMode, swing: d.bs, kind: d.kind, cores: why });
    }
    return cases;
}

const QUERIES = path.join(__dirname, 'queries');
const sqlOf = name => fs.readFileSync(path.join(QUERIES, `${name}.sql`), 'utf8');

/**
 * All dynamic metrics for one game of the log store (`file` as in games.file, already ingested). `end` is the last whole minute
 * of snapshots. `parsed` is that game from parseLog (read from `file` when omitted): the part-B and C metrics still use it.
 */
function dynamicMetrics(store, file, gameNo = 1, parsed) {
    if (!store.query('SELECT 1 FROM games WHERE file = ? AND game = ?', file, gameNo).length) {
        throw new Error(`dynamicMetrics: ${file} game ${gameNo} is not in the store (the path must be absolute, as in games.file; ingest it first)`);
    }
    const p = { file, game: gameNo };
    const H = Object.fromEntries(store.query(sqlOf('dynamic_heroes'), p).map(h => [h.pid, h]));
    if (!Object.keys(H).length) throw new Error(`dynamicMetrics: ${file} game ${gameNo} has no hero with a team and a snapshot`);
    const G = store.query(sqlOf('dynamic_game'), p)[0];
    const game = parsed || parseLog(fs.readFileSync(file, 'utf8'))[gameNo - 1];
    const S = series(game);
    const pids = Object.keys(S).join();
    if (pids !== Object.keys(H).join()) throw new Error(`dynamicMetrics: series heroes ${pids} differ from @dynamic_heroes ${Object.keys(H).join()}`);
    for (const s of Object.values(S)) Object.assign(s, { hero: H[s.pid].hero ?? undefined, lh10: H[s.pid].lh10, home: H[s.pid].home ?? undefined });
    const end = G.end;
    const warnings = [];
    const role = roles(S, warnings);
    const deaths = [];
    for (const d of store.query(sqlOf('dynamic_deaths'), p)) for (let k = 0; k < d.n; k++) deaths.push({ t: d.t, team: d.team });
    const team = t => Object.values(S).filter(s => s.team === t);
    const perTeam = f => ({ 2: f(team(2), 2), 3: f(team(3), 3) });
    const sum = (arr, f) => arr.reduce((a, s) => a + f(s), 0);
    const byRole = f => Object.fromEntries(Object.values(S).map(s => [`${s.team === 2 ? 'r' : 'd'}${role[s.pid]}`, f(s)]));
    // Lineup position: pos= of the last ev=bot line (a role change re-emits it). Trusted only where pos= is (lineups.md).
    const lpos = {};
    for (const s of Object.values(S)) if (H[s.pid].lpos !== null) lpos[s.pid] = H[s.pid].lpos;
    // A team whose positions are not exactly 1-5 (e.g. a pre-Dire-fix log, all Dire pos=1) gets no lpos keys.
    for (const t of [2, 3]) {
        const ps = team(t).map(s => lpos[s.pid]).sort().join();
        if (ps !== '1,2,3,4,5') {
            warnings.push(`team ${t}: lineup positions ${ps || 'none'} are not 1-5; no lpos keys`);
            team(t).forEach(s => delete lpos[s.pid]);
        }
    }
    const byLpos = f => Object.fromEntries(Object.values(S).filter(s => lpos[s.pid]).map(s => [`${s.team === 2 ? 'r' : 'd'}${lpos[s.pid]}`, f(s)]));
    const rate = n => (end > 600 ? (n * 600) / (end - 600) : undefined);
    return {
        end,
        bots: G.bots,
        roles: byRole(s => s.hero),
        pids: byRole(s => s.pid),
        lh_at_10: byRole(s => s.lh10),
        deaths_before_10: { 2: G.deaths10_r, 3: G.deaths10_d },
        deaths_total: G.deaths,
        encounters_per_10min: { before10: G.enc10, after10: rate(G.enc_after) },
        fights_per_10min: { before10: G.fights10, after10: rate(G.fights_after) },
        rotation_attempts_per_team_10: perTeam(ts => sum(ts, s => rotations(s, 600))),
        core_lane_exit_time: byRole(s => (role[s.pid] === 1 || role[s.pid] === 3 ? laneExit(s, end) : undefined)),
        tp_joins_per_team: perTeam(ts => sum(ts, s => tpJoins(S, s, 600, end))),
        ally_creep_steals: perTeam(ts => steals(game, Object.fromEntries(ts.map(s => [s.pid, s])), role, 600)),
        audited_steals: auditedSteals(game, S, lpos, 600),
        idle_10s: sum(Object.values(H), h => h.idle),
        lua_error: G.lua_error_ours + G.console_lines,
        lua_error_ours: G.lua_error_ours,
        console_errors: G.console_errors,
        // Dota squelches a console message after 10 identical copies, so with a notice the console counts are lower bounds.
        console_squelches: G.squelches,
        // Censored only by a notice right after an error line: Dota squelches any repeated message, errors or not.
        console_censored: G.error_squelches > 0,
        lpos,
        lh_at_10_lpos: byLpos(s => s.lh10),
        core_lane_exit_time_lpos: byLpos(s => (lpos[s.pid] === 1 || lpos[s.pid] === 3 ? laneExit(s, end) : undefined)),
        role_mismatch: Object.values(S).filter(s => lpos[s.pid] && lpos[s.pid] !== role[s.pid]).length,
        // Lineup position where pos= is trusted (lpos), else the behavioural role.
        ...worldMetrics(game, S, { ...role, ...lpos }, deaths, end),
        warnings,
    };
}

/** World-event metrics (slice 23 definitions) from ev=rune_pickup, ward_place, smoke_use, tp, building_fall, roshan_kill and
 *  aegis, plus the shrine proxy from snapshots. Logs without these events give undefined counts (pre-slice-23 builds), except
 *  the snapshot-only wisdom proxy. */
function worldMetrics(game, S, role, deaths, end) {
    const of = ev => game.events.filter(e => e.ev === ev);
    const has = ev => of(ev).length > 0;
    const world = ['rune_pickup', 'ward_place', 'building_fall', 'tp'].some(has);
    const perTeam = f => (world ? { 2: f(2), 3: f(3) } : undefined);
    const share = (xs, pred) => (xs.length ? xs.filter(pred).length / xs.length : undefined);
    const isMid = e => role[e.pid] === 2;
    const runes = (team, kind) => of('rune_pickup').filter(e => e.team === team && e.kind === kind);
    const wards = of('ward_place');
    const falls = of('building_fall').sort((a, b) => a.t - b.t);
    const t1 = falls.find(e => e.kind === 'tower' && e.tier === 1);
    // Roshan: both loggers report a kill; one kill per distinct kill time. Timed by log time t (within 1 s of the kill):
    // the time base of GetRoshanKillTime (`at`) is unverified.
    const roshans = [];
    for (const e of of('roshan_kill').sort((a, b) => a.t - b.t)) if (!roshans.some(r => r.at === e.at)) roshans.push(e);
    const aegis = of('aegis');
    const byRole = f => Object.fromEntries(Object.values(S).filter(s => role[s.pid] >= 4).map(s => [`${s.team === 2 ? 'r' : 'd'}${role[s.pid]}`, f(s)]));
    return {
        mid_power_rune_pct: perTeam(t => share(runes(t, 'power'), isMid)),
        mid_water_rune_pct: perTeam(t => share(runes(t, 'water'), isMid)),
        power_rune_pickups: perTeam(t => runes(t, 'power').length),
        wisdom_rune_taken_within_15s: { 2: wisdom(S, 2, end), 3: wisdom(S, 3, end) },
        first_sentry_time: world ? byRole(s => wards.find(e => e.kind === 'sentry' && e.pid === s.pid)?.t) : undefined,
        sentry_by_90s: perTeam(t => (wards.some(e => e.kind === 'sentry' && e.team === t && e.t <= C.SENTRY_BY) ? 1 : 0)),
        smoke_uses_per_team: perTeam(t => {
            // From the horn (pregame smokes are not map movement); a smoke within SMOKE_MERGE s of a group's first joins it.
            let n = 0, first = -Infinity;
            for (const e of of('smoke_use').filter(e => e.team === t && e.t >= 0).sort((a, b) => a.t - b.t)) {
                if (e.t - first > C.SMOKE_MERGE) {
                    n++;
                    first = e.t;
                }
            }
            return n;
        }),
        tp_joins_per_team_ev: perTeam(t =>
            of('tp').filter(e => {
                if (e.team !== t || e.t < 600 || e.t >= 1800 || e.dist <= C.TP_MOVED) return false;
                return Object.values(S).some(o => {
                    if (o.pid === e.pid || o.team !== t) return false;
                    for (let u = Math.floor(e.t) - 1; u <= Math.floor(e.t) + 1; u++) if (alive(o.sec[u]) && dist(pos(o.sec[u]), [e.x, e.y]) <= C.TP_JOIN_R) return true;
                    return false;
                });
            }).length),
        first_t1_time: world ? t1?.t : undefined,
        cash_in_kills_pct: perTeam(t => {
            // Bursts by team t: 3+ deaths of the other team, <= FIGHT_GAP s apart.
            const bursts = [];
            let run = [];
            for (const d of deaths.filter(d => d.team !== t)) {
                if (run.length && d.t - run[run.length - 1].t > C.FIGHT_GAP) {
                    if (run.length >= C.FIGHT_MIN_DEATHS) bursts.push(run[run.length - 1].t);
                    run = [];
                }
                run.push(d);
            }
            if (run.length >= C.FIGHT_MIN_DEATHS) bursts.push(run[run.length - 1].t);
            const open = bursts.filter(b => b + C.CASH_IN <= end);
            return share(open, b => falls.some(f => f.team !== t && f.t > b && f.t <= b + C.CASH_IN));
        }),
        first_roshan_time: world ? roshans[0]?.t : undefined,
        towers_after_roshan_240: world
            ? share(roshans.filter(r => r.t + C.ROSH_FOLLOW <= end), r => {
                  const a = aegis.find(e => e.t >= r.t && e.t <= r.t + C.AEGIS_AFTER);
                  return falls.some(f => f.t > r.t && f.t <= r.t + C.ROSH_FOLLOW && (a === undefined || f.team !== a.team));
              })
            : undefined,
    };
}

/** Share of a shrine's fills (from WISDOM_FIRST every WISDOM_FIRST, up to end - WISDOM_LATE) that some hero takes: within
 *  WISDOM_R of the shrine for WISDOM_CHANNEL consecutive seconds, the run starting by fill + WISDOM_LATE. Snapshot proxy. */
function wisdom(S, shrineTeam, end) {
    const fills = [];
    for (let f = C.WISDOM_FIRST; f + C.WISDOM_LATE <= end; f += C.WISDOM_FIRST) fills.push(f);
    if (!fills.length) return undefined;
    const spot = SHRINE[shrineTeam];
    const taken = f => {
        for (let t0 = f; t0 <= f + C.WISDOM_LATE; t0++) {
            const there = s => {
                for (let u = t0; u < t0 + C.WISDOM_CHANNEL; u++) if (!alive(s.sec[u]) || dist(pos(s.sec[u]), spot) > C.WISDOM_R) return false;
                return true;
            };
            if (Object.values(S).some(there)) return true;
        }
        return false;
    };
    return fills.filter(taken).length / fills.length;
}

module.exports = { POLY, dynamicMetrics, auditedSteals, worldMetrics, wisdom, laneLabel, rotations, laneExit, tpJoins, series, roles, C };
