// Dynamic-game metrics (GOALS O3/O4, O1 guard rails) from ev=snap and ev=lasthit, for 5v5 bot games where all ten
// bots log snapshots. Definitions: docs/team/slices/15-dynamic-metrics.md (master repo). Geometry and the encounter rule
// follow the replay moment index (research/replay-index.md) so bot and replay moments compare.
'use strict';

const C = {
    R_AWARE: 1200, // heroes within this many units count as meeting
    GAP_ENC: 5, // an encounter needs the pair apart for this many seconds first
    MERGE_ENC: 3, // onsets this close (s) are one encounter
    LANE_R: 1100, // distance from a lane polyline that still counts as that lane
    BASE_R: 1800, // within this of an ancient counts as base
    ROT_MIN_S: 10, // seconds in another lane region before 10:00 that make a rotation
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
    for (const t of [2, 3]) if (dist(p, ANCIENT[t]) < C.BASE_R) return 'base';
    let best = 'other', bd = C.LANE_R;
    for (const [L, P] of Object.entries(POLY)) {
        for (let i = 0; i + 1 < P.length; i++) {
            const d = segDist(p, P[i], P[i + 1]);
            if (d < bd) [bd, best] = [d, L];
        }
    }
    return best;
}

/** Per bot: snapshots resampled to whole seconds (latest snap at or before each second), from first to last snap. */
function series(game) {
    const out = {};
    for (const b of Object.values(game.bots)) {
        const snaps = b.snaps.filter(s => typeof s.x === 'number').sort((a, c) => a.t - c.t);
        if (snaps.length === 0 || b.team === undefined) continue;
        const sec = {};
        let i = 0;
        for (let t = Math.ceil(snaps[0].t); t <= Math.floor(snaps[snaps.length - 1].t); t++) {
            while (i + 1 < snaps.length && snaps[i + 1].t <= t) i++;
            sec[t] = snaps[i];
        }
        out[b.pid] = { pid: b.pid, hero: b.hero, team: b.team, sec, snaps };
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
 *  off-lane core pos 3), the other two supports (more last hits = pos 4). Avoids the bots-mode Dire pos= artefact. */
function roles(S) {
    const out = {};
    for (const team of [2, 3]) {
        const bots = Object.values(S).filter(s => s.team === team);
        bots.forEach(s => ((s.lh10 = counterAt(s, 'lh', 600)), (s.home = modalLane(s, 60, 300))));
        bots.sort((a, b) => b.lh10 - a.lh10);
        const cores = bots.slice(0, 3), sups = bots.slice(3);
        const safe = team === 2 ? 'bot' : 'top';
        const mid = cores.find(s => s.home === 'mid') || cores[0];
        const rest = cores.filter(s => s !== mid);
        const p1 = rest.find(s => s.home === safe) || rest[0];
        const p3 = rest.find(s => s !== p1);
        [[mid, 2], [p1, 1], [p3, 3], [sups[0], 4], [sups[1], 5]].forEach(([s, r]) => s && (out[s.pid] = r));
    }
    return out;
}

/** Encounter onsets: an opposing pair, both alive, comes within R_AWARE after >= GAP_ENC s apart; onsets within MERGE_ENC merge. */
function encounters(S, from, to) {
    const rad = Object.values(S).filter(s => s.team === 2), dire = Object.values(S).filter(s => s.team === 3);
    const onsets = [];
    for (const a of rad) {
        for (const b of dire) {
            let apart = C.GAP_ENC, near = false;
            for (let t = from; t < to; t++) {
                const sa = a.sec[t], sb = b.sec[t];
                const close = alive(sa) && alive(sb) && dist(pos(sa), pos(sb)) <= C.R_AWARE;
                if (close && !near && apart >= C.GAP_ENC) onsets.push(t);
                if (close) apart = 0;
                else apart++;
                near = close;
            }
        }
    }
    onsets.sort((x, y) => x - y);
    let n = 0, last = -Infinity;
    for (const t of onsets) {
        if (t - last > C.MERGE_ENC) n++;
        last = t;
    }
    return n;
}

/** Death times of every hero (a deaths counter increment), sorted. */
function deathTimes(S) {
    const out = [];
    for (const s of Object.values(S)) {
        let prev = 0;
        for (const snap of s.snaps) {
            if (typeof snap.deaths !== 'number') continue;
            for (let k = prev; k < snap.deaths; k++) out.push({ t: snap.t, team: s.team });
            prev = snap.deaths;
        }
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

/** Rotation episodes before `until`: >= ROT_MIN_S consecutive seconds in a lane region other than the home lane. */
function rotations(s, until) {
    if (!s.home) return 0;
    let n = 0, run = 0;
    for (let t = 90; t < until; t++) {
        const snap = s.sec[t];
        const L = alive(snap) ? laneLabel(pos(snap)) : 'dead';
        const away = L === 'top' || L === 'mid' || L === 'bot' ? L !== s.home : false;
        if (away) {
            run++;
            if (run === C.ROT_MIN_S) n++;
        } else run = 0;
    }
    return n;
}

/** First whole minute >= 5:00 after which under half of the next 60 s is spent alive in the home lane; undefined if never. */
function laneExit(s, until) {
    if (!s.home) return undefined;
    for (let t = 300; t + 60 <= until; t += 60) {
        let inLane = 0, seen = 0;
        for (let u = t; u < t + 60; u++) {
            const snap = s.sec[u];
            if (!alive(snap)) continue;
            seen++;
            if (laneLabel(pos(snap)) === s.home) inLane++;
        }
        if (seen > 0 && inLane / seen < 0.5) return t;
    }
    return undefined;
}

/** Teleport-like jumps (>= TP_JUMP within TP_WINDOW while alive) landing within TP_JOIN_R of an alive ally. */
function tpJoins(S, s, from, to) {
    let n = 0;
    for (let t = from; t < to; t++) {
        const a = s.sec[t - C.TP_WINDOW], b = s.sec[t];
        if (!alive(a) || !alive(b) || dist(pos(a), pos(b)) < C.TP_JUMP) continue;
        // The jump must not start at a respawn (dead at any second in the window).
        let dead = false;
        for (let u = t - C.TP_WINDOW; u <= t; u++) if (!alive(s.sec[u])) dead = true;
        if (dead) continue;
        const ally = Object.values(S).some(o => o !== s && o.team === s.team && alive(o.sec[t]) && dist(pos(o.sec[t]), pos(b)) <= C.TP_JOIN_R);
        if (ally) n++;
        t += C.TP_WINDOW; // one jump counts once
    }
    return n;
}

/** Support last hits (from ev=lasthit) before `until` while an allied core is within STEAL_R. */
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

/** Idle episodes: alive, outside base, within IDLE_R of one spot for >= IDLE_S seconds (each episode counted once). */
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

/** All dynamic metrics for one parsed game. `end` defaults to the last whole minute of snapshots. */
function dynamicMetrics(game) {
    const S = series(game);
    const last = Math.max(...Object.values(S).map(s => s.snaps[s.snaps.length - 1].t));
    const end = Math.floor(last / 60) * 60;
    const role = roles(S);
    const deaths = deathTimes(S);
    const team = t => Object.values(S).filter(s => s.team === t);
    const perTeam = f => ({ 2: f(team(2)), 3: f(team(3)) });
    const sum = (arr, f) => arr.reduce((a, s) => a + f(s), 0);
    const byRole = f => Object.fromEntries(Object.values(S).map(s => [`${s.team === 2 ? 'r' : 'd'}${role[s.pid]}`, f(s)]));
    const errors = game.events.filter(e => e.ev === 'lua_error').length + game.errors.length;
    return {
        end,
        bots: Object.values(S).length,
        roles: byRole(s => s.hero),
        pids: byRole(s => s.pid),
        lh_at_10: byRole(s => counterAt(s, 'lh', 600)),
        deaths_before_10: perTeam(ts => sum(ts, s => counterAt(s, 'deaths', 600))),
        encounters_per_10min: { before10: encounters(S, 0, 600), after10: end > 600 ? (encounters(S, 600, end) * 600) / (end - 600) : undefined },
        fights_per_10min: { before10: fights(deaths, 0, 600), after10: end > 600 ? (fights(deaths, 600, end) * 600) / (end - 600) : undefined },
        rotation_attempts_per_team_10: perTeam(ts => sum(ts, s => rotations(s, 600))),
        core_lane_exit_time: byRole(s => (role[s.pid] === 1 || role[s.pid] === 3 ? laneExit(s, end) : undefined)),
        tp_joins_per_team: perTeam(ts => sum(ts, s => tpJoins(S, s, 600, end))),
        ally_creep_steals: perTeam(ts => steals(game, Object.fromEntries(ts.map(s => [s.pid, s])), role, 600)),
        idle_10s: sum(Object.values(S), s => idles(s, 0, end)),
        lua_error: errors,
    };
}

module.exports = { dynamicMetrics, laneLabel, encounters, fights, rotations, laneExit, tpJoins, idles, series, roles, deathTimes, C };
