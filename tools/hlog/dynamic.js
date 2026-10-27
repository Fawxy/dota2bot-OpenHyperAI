// Dynamic-game metrics (GOALS O3/O4, O1 guard rails) from ev=snap and ev=lasthit, for 5v5 bot games where all ten
// bots log snapshots. Definitions: docs/team/slices/15-dynamic-metrics.md (master repo). Geometry, the encounter rule and the
// rotation rule follow the replay moment index (research/replay-index/moments.js) so bot and replay moments compare.
'use strict';

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
    IDLE_S: 10,
    IDLE_R: 100,
};

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

/** Last value of a counter field at or before t (0 if none). */
function counterAt(s, field, t) {
    let v = 0;
    for (const snap of s.snaps) {
        if (snap.t > t) break;
        if (typeof snap[field] === 'number') v = snap[field];
    }
    return v;
}

/** Modal lane label over [a, b) seconds, ignoring base/other. */
function modalLane(s, a, b) {
    const n = {};
    for (let t = a; t < b; t++) {
        const snap = s.sec[t];
        if (!alive(snap)) continue;
        const L = laneLabel(pos(snap));
        if (L !== 'base' && L !== 'other') n[L] = (n[L] || 0) + 1;
    }
    return Object.entries(n).sort((x, y) => y[1] - x[1])[0]?.[0];
}

/** Roles by behaviour: per team, the three top last-hitters at 10:00 are cores (mid core pos 2, safe-lane core pos 1,
 *  off-lane core pos 3), the other two supports (more last hits = pos 4). Avoids the bots-mode Dire pos= artefact.
 *  Fallbacks (no mid core, no safe-lane core) are reported in `warnings`. */
function roles(S, warnings = []) {
    const out = {};
    for (const team of [2, 3]) {
        const bots = Object.values(S).filter(s => s.team === team);
        bots.forEach(s => ((s.lh10 = counterAt(s, 'lh', 600)), (s.home = modalLane(s, 60, 300))));
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

/** Encounters with onset in [from, to): an opposing pair, both alive, comes within R_AWARE after >= GAP_ENC s apart; an onset
 *  within MERGE_ENC s of the current encounter's first onset joins it (moments.js rule). The scan starts at 0, so pairs already
 *  together at `from` do not open an encounter. */
function encounters(S, from, to) {
    const rad = Object.values(S).filter(s => s.team === 2), dire = Object.values(S).filter(s => s.team === 3);
    const onsets = [];
    for (const a of rad) {
        for (const b of dire) {
            let apart = C.GAP_ENC;
            for (let t = 0; t < to; t++) {
                const sa = a.sec[t], sb = b.sec[t];
                const close = alive(sa) && alive(sb) && dist(pos(sa), pos(sb)) <= C.R_AWARE;
                if (close && apart >= C.GAP_ENC && t >= from) onsets.push(t);
                if (close) apart = 0;
                else apart++;
            }
        }
    }
    onsets.sort((x, y) => x - y);
    let n = 0, first = -Infinity;
    for (const t of onsets) {
        if (t - first > C.MERGE_ENC) {
            n++;
            first = t;
        }
    }
    return n;
}

/** Death times of every hero, sorted. A deaths increment after a gap > DEAD_GAP is dated at the last snapshot before the gap
 *  (the death, not the respawn); a bot dead at the end of the game adds one death at its last snapshot. */
function deathTimes(S) {
    const out = [];
    for (const s of Object.values(S)) {
        const snaps = s.snaps;
        let prev = 0;
        for (let i = 0; i < snaps.length; i++) {
            if (typeof snaps[i].deaths !== 'number') continue;
            const t = i > 0 && snaps[i].t - snaps[i - 1].t > C.DEAD_GAP ? snaps[i - 1].t : snaps[i].t;
            for (let k = prev; k < snaps[i].deaths; k++) out.push({ t, team: s.team });
            prev = snaps[i].deaths;
        }
        const lastSnap = snaps[snaps.length - 1];
        if (s.last - lastSnap.t > C.DEAD_GAP) out.push({ t: lastSnap.t, team: s.team });
    }
    return out.sort((a, b) => a.t - b.t);
}

/** Fights: runs of deaths with <= FIGHT_GAP s between consecutive deaths and >= FIGHT_MIN_DEATHS deaths. */
function fights(deaths, from, to) {
    const ds = deaths.filter(d => d.t >= from && d.t < to);
    let n = 0, run = 0, last = -Infinity;
    for (const d of ds) {
        if (d.t - last <= C.FIGHT_GAP) run++;
        else {
            if (run >= C.FIGHT_MIN_DEATHS) n++;
            run = 1;
        }
        last = d.t;
    }
    if (run >= C.FIGHT_MIN_DEATHS) n++;
    return n;
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

/** Idle episodes: alive, outside base and fountain, within IDLE_R of one spot for >= IDLE_S seconds (each counted once). */
function idles(s, from, to) {
    let n = 0, anchor, start;
    for (let t = from; t < to; t++) {
        const snap = s.sec[t];
        if (!alive(snap) || laneLabel(pos(snap)) === 'base') {
            anchor = undefined;
            continue;
        }
        if (!anchor || dist(anchor, pos(snap)) > C.IDLE_R) {
            anchor = pos(snap);
            start = t;
        } else if (t - start === C.IDLE_S) n++;
    }
    return n;
}

/** All dynamic metrics for one parsed game. `end` is the last whole minute of snapshots. */
function dynamicMetrics(game) {
    const S = series(game);
    const end = Math.floor(Object.values(S)[0].last / 60) * 60;
    const warnings = [];
    const role = roles(S, warnings);
    const deaths = deathTimes(S);
    const team = t => Object.values(S).filter(s => s.team === t);
    const perTeam = f => ({ 2: f(team(2), 2), 3: f(team(3), 3) });
    const sum = (arr, f) => arr.reduce((a, s) => a + f(s), 0);
    const byRole = f => Object.fromEntries(Object.values(S).map(s => [`${s.team === 2 ? 'r' : 'd'}${role[s.pid]}`, f(s)]));
    const errors = game.events.filter(e => e.ev === 'lua_error').length + game.errors.length;
    return {
        end,
        bots: Object.values(S).length,
        roles: byRole(s => s.hero),
        pids: byRole(s => s.pid),
        lh_at_10: byRole(s => counterAt(s, 'lh', 600)),
        deaths_before_10: perTeam((ts, t) => deaths.filter(d => d.t < 600 && d.team === t).length),
        encounters_per_10min: { before10: encounters(S, 0, 600), after10: end > 600 ? (encounters(S, 600, end) * 600) / (end - 600) : undefined },
        fights_per_10min: { before10: fights(deaths, 0, 600), after10: end > 600 ? (fights(deaths, 600, end) * 600) / (end - 600) : undefined },
        rotation_attempts_per_team_10: perTeam(ts => sum(ts, s => rotations(s, 600))),
        core_lane_exit_time: byRole(s => (role[s.pid] === 1 || role[s.pid] === 3 ? laneExit(s, end) : undefined)),
        tp_joins_per_team: perTeam(ts => sum(ts, s => tpJoins(S, s, 600, end))),
        ally_creep_steals: perTeam(ts => steals(game, Object.fromEntries(ts.map(s => [s.pid, s])), role, 600)),
        idle_10s: sum(Object.values(S), s => idles(s, 0, end)),
        lua_error: errors,
        warnings,
    };
}

module.exports = { dynamicMetrics, laneLabel, encounters, fights, rotations, laneExit, tpJoins, idles, series, roles, deathTimes, C };
