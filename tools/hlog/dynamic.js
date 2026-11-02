// Dynamic-game metrics (GOALS O3/O4, O1 guard rails) from ev=snap and ev=lasthit, for 5v5 bot games where all ten
// bots log snapshots. Definitions: docs/team/slices/15-dynamic-metrics.md (master repo). Geometry, the encounter rule and the
// rotation rule follow the replay moment index (research/replay-index/moments.js) so bot and replay moments compare.
// Every metric reads the log store (docs/team/slices/retire-dynamic-a.md, -b.md and -c.md): the named queries `@dynamic_heroes`,
// `@dynamic_game`, `@dynamic_lasthits`, `@dynamic_world`, `@steals` and `@stack_rows` (rules in queries/fragments/hero_second.sql,
// hero_death.sql and lane_label.sql); `@dynamic_series` and `@dynamic_deaths` show the series and the deaths they build on.
// Roles and the lineup trust check stay here. The constants `C` are the ones the queries' comments name.
'use strict';

const fs = require('fs');
const path = require('path');
const { stealsFor } = require('./steals');

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

const QUERIES = path.join(__dirname, 'queries');
const sqlOf = name => fs.readFileSync(path.join(QUERIES, `${name}.sql`), 'utf8');

/**
 * The heroes of one stored game (@dynamic_heroes): pid -> { pid, hero, team, lpos, lh10, home, idle, rot10, lane_exit, tp_joins }.
 * Fields the log lacks are undefined.
 */
function heroes(store, file, gameNo = 1) {
    const und = o => Object.fromEntries(Object.entries(o).map(([k, v]) => [k, v ?? undefined]));
    return Object.fromEntries(store.query(sqlOf('dynamic_heroes'), { file, game: gameNo }).map(h => [h.pid, und(h)]));
}

/** Roles by behaviour (each hero's `lh10` and `home` from @dynamic_heroes): per team, the three top last-hitters at 10:00 are cores (mid core pos 2, safe-lane core pos 1,
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

// The fields of an ev=stack attempt, in the order stacks.js --json has always printed them.
const STACK_KEYS = ['t', 'pid', 'min', 'res', 'why', 'camp', 'type', 'aggro', 'before', 'after', 'fresh', 'away', 'death',
    'vis', 'box59', 'pulled59', 'bot59', 'vis59', 'exit59', 'hitd', 'tgt2', 'tgt59', 'strict59',
    'arr', 'hit0', 'dmg', 'react', 'exit', 'hpa', 'hpe', 'hp59', 'casts', 'n2', 'n59', 'lane', 'idle', 'left59', 'cause'];

/**
 * Stack attempts (slice 4, KR S.2a): every ev=stack line of one stored game before `until` (`@stack_rows` over the
 * stack_attempts view, which holds the `cause` and `left59` rules), one per trigger minute, `res` stacked | not_stacked |
 * failed (a job started) or skip (none started). `death` is a boolean; a NULL field ('?' or absent in the log) is left out.
 * Empty when the log has none (the OFF arm, older builds).
 */
function stackAttempts(store, file, gameNo = 1, until = Infinity) {
    if (!store.kinds.has('ev_stack')) return []; // no log in the store has ev=stack, so the view is skipped (refreshViews)
    // A store filled with ingest() alone has not created the view yet (ingestAll refreshes the views itself).
    if (!store.query("SELECT 1 FROM sqlite_temp_master WHERE type = 'view' AND name = 'stack_attempts'").length) store.refreshViews();
    return store.query(sqlOf('stack_rows'), { file, game: gameNo, until: Number.isFinite(until) ? until : null })
        .map(r => Object.fromEntries(STACK_KEYS.map(k => [k, k === 'death' ? r.death_flag === 1 : r[k] ?? undefined])));
}

/** Rune trips and skips of one stored game (the rune_jobs view, slice rune-rotation); empty when no log has ev=rune_job. */
function runeJobs(store, file, gameNo = 1) {
    if (!store.kinds.has('ev_rune_job')) return [];
    if (!store.query("SELECT 1 FROM sqlite_temp_master WHERE type = 'view' AND name = 'rune_jobs'").length) store.refreshViews();
    return store.query('SELECT pid, pos, kind, spawn, res, why, started, on_time, died FROM rune_jobs WHERE file = ? AND game = ? ORDER BY t, pid', file, gameNo);
}

/** Mean level at 10:00 of the pos1 and pos3 of both teams (the rotators' lane partners; slice rune-rotation's G2), or
 *  undefined when the game has no snap at minute 10 or no lineup. */
function lanePartnerLvl10(store, file, gameNo = 1) {
    if (!store.kinds.has('ev_snap') || !store.kinds.has('ev_bot')) return undefined;
    if (!store.query("SELECT 1 FROM sqlite_temp_master WHERE type = 'view' AND name = 'hero_minute'").length) store.refreshViews();
    const r = store.query(`SELECT avg(h.lvl) AS lv, count(*) AS n FROM hero_minute h JOIN lineup l ON l.game_id = h.game_id AND l.pid = h.pid
        WHERE h.file = ? AND h.game = ? AND h.minute = 10 AND l.pos IN (1, 3)`, file, gameNo)[0];
    return r && r.n > 0 ? r.lv : undefined;
}

/** Ended jobs of one stored game (the job_ends view, slice job-chooser); empty when no log in the store has ev=job. */
function jobEnds(store, file, gameNo = 1) {
    if (!store.kinds.has('ev_job')) return [];
    if (!store.query("SELECT 1 FROM sqlite_temp_master WHERE type = 'view' AND name = 'job_ends'").length) store.refreshViews();
    return store.query('SELECT why, class, hit, pid, t FROM job_ends WHERE file = ? AND game = ?', file, gameNo);
}

/**
 * All dynamic metrics for one game of the log store (`file` as in games.file, already ingested). `end` is the last whole minute
 * of snapshots.
 */
function dynamicMetrics(store, file, gameNo = 1) {
    if (!store.query('SELECT 1 FROM games WHERE file = ? AND game = ?', file, gameNo).length) {
        throw new Error(`dynamicMetrics: ${file} game ${gameNo} is not in the store (the path must be absolute, as in games.file; ingest it first)`);
    }
    const p = { file, game: gameNo };
    const S = heroes(store, file, gameNo);
    if (!Object.keys(S).length) throw new Error(`dynamicMetrics: ${file} game ${gameNo} has no hero with a team and a snapshot`);
    const G = store.query(sqlOf('dynamic_game'), p)[0];
    const end = G.end;
    const warnings = [];
    const role = roles(S, warnings);
    const team = t => Object.values(S).filter(s => s.team === t);
    const perTeam = f => ({ 2: f(team(2), 2), 3: f(team(3), 3) });
    const sum = (arr, f) => arr.reduce((a, s) => a + f(s), 0);
    const byRole = f => Object.fromEntries(Object.values(S).map(s => [`${s.team === 2 ? 'r' : 'd'}${role[s.pid]}`, f(s)]));
    // Lineup position: pos= of the last ev=bot line (a role change re-emits it). Trusted only where pos= is (lineups.md).
    const lpos = {};
    for (const s of Object.values(S)) if (s.lpos !== undefined) lpos[s.pid] = s.lpos;
    // A team whose positions are not exactly 1-5 (e.g. a pre-Dire-fix log, all Dire pos=1) gets no lpos keys.
    for (const t of [2, 3]) {
        const ps = team(t).map(s => lpos[s.pid]).sort().join();
        if (ps !== '1,2,3,4,5') {
            warnings.push(`team ${t}: lineup positions ${ps || 'none'} are not 1-5; no lpos keys`);
            team(t).forEach(s => delete lpos[s.pid]);
        }
    }
    const byLpos = f => Object.fromEntries(Object.values(S).filter(s => lpos[s.pid]).map(s => [`${s.team === 2 ? 'r' : 'd'}${lpos[s.pid]}`, f(s)]));
    // Ally steals: a support's last hits before 10:00 with an allied core alive within STEAL_R (@dynamic_lasthits).
    const lasthits = store.query(sqlOf('dynamic_lasthits'), p)
        .filter(l => role[l.pid] >= 4 && String(l.near ?? '').split(',').some(o => o !== '' && role[o] <= 3));
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
        rotation_attempts_per_team_10: perTeam(ts => sum(ts, s => s.rot10)),
        core_lane_exit_time: byRole(s => (role[s.pid] === 1 || role[s.pid] === 3 ? s.lane_exit : undefined)),
        tp_joins_per_team: perTeam(ts => sum(ts, s => s.tp_joins)),
        ally_creep_steals: perTeam((ts, t) => sum(lasthits.filter(l => S[l.pid].team === t), l => l.n)),
        // Undefined when the game has no ev=creep_death or no trusted lineup (@steals applies the lpos rule above itself).
        audited_steals: stealsFor(store, file, gameNo, 600),
        stacks: stackAttempts(store, file, gameNo, end + 1),
        job_ends: jobEnds(store, file, gameNo),
        rune_jobs: runeJobs(store, file, gameNo),
        lane_partner_lvl10: lanePartnerLvl10(store, file, gameNo),
        idle_10s: sum(Object.values(S), s => s.idle),
        lua_error: G.lua_error_ours + G.console_lines,
        lua_error_ours: G.lua_error_ours,
        console_errors: G.console_errors,
        // Dota squelches a console message after 10 identical copies, so with a notice the console counts are lower bounds.
        console_squelches: G.squelches,
        // Censored only by a notice right after an error line: Dota squelches any repeated message, errors or not.
        console_censored: G.error_squelches > 0,
        lpos,
        lh_at_10_lpos: byLpos(s => s.lh10),
        core_lane_exit_time_lpos: byLpos(s => (lpos[s.pid] === 1 || lpos[s.pid] === 3 ? s.lane_exit : undefined)),
        role_mismatch: Object.values(S).filter(s => lpos[s.pid] && lpos[s.pid] !== role[s.pid]).length,
        // Lineup position where pos= is trusted (lpos), else the behavioural role.
        ...worldMetrics(store, file, gameNo, S, { ...role, ...lpos }),
        warnings,
    };
}

/** World-event metrics (slice 23 definitions; the rules are in queries/dynamic_world.sql) for the heroes S of one stored game, with
 *  `role` pid -> position. Logs without ev=rune_pickup, ward_place, building_fall or tp give undefined counts (pre-slice-23
 *  builds), except the snapshot-only wisdom proxy. */
function worldMetrics(store, file, gameNo, S, role) {
    const rows = store.query(sqlOf('dynamic_world'), { file, game: gameNo });
    const G = rows.find(r => r.kind === 'game');
    const T = Object.fromEntries(rows.filter(r => r.kind === 'team').map(r => [r.team, r]));
    const world = G.world === 1;
    const perTeam = f => (world ? { 2: f(2), 3: f(3) } : undefined);
    const frac = (n, of) => (of ? n / of : undefined);
    const sum = xs => xs.reduce((a, r) => a + r.n, 0);
    const runes = (team, kind) => rows.filter(r => r.kind === 'rune' && r.team === team && r.rune === kind);
    const midShare = (team, kind) => frac(sum(runes(team, kind).filter(r => role[r.pid] === 2)), sum(runes(team, kind)));
    const sentry = Object.fromEntries(rows.filter(r => r.kind === 'sentry').map(r => [r.pid, r.t]));
    const byRole = f => Object.fromEntries(Object.values(S).filter(s => role[s.pid] >= 4).map(s => [`${s.team === 2 ? 'r' : 'd'}${role[s.pid]}`, f(s)]));
    return {
        mid_power_rune_pct: perTeam(t => midShare(t, 'power')),
        mid_water_rune_pct: perTeam(t => midShare(t, 'water')),
        power_rune_pickups: perTeam(t => sum(runes(t, 'power'))),
        wisdom_rune_taken_within_15s: { 2: frac(T[2].taken, T[2].fills), 3: frac(T[3].taken, T[3].fills) },
        first_sentry_time: world ? byRole(s => sentry[s.pid]) : undefined,
        sentry_by_90s: perTeam(t => T[t].sentry90),
        smoke_uses_per_team: perTeam(t => T[t].smokes),
        tp_joins_per_team_ev: perTeam(t => T[t].tpj),
        first_t1_time: world ? G.t1 ?? undefined : undefined,
        cash_in_kills_pct: perTeam(t => frac(T[t].cashed, T[t].bursts)),
        first_roshan_time: world ? G.rosh ?? undefined : undefined,
        towers_after_roshan_240: world ? frac(G.rosh_ok, G.rosh_open) : undefined,
    };
}

module.exports = { POLY, dynamicMetrics, heroes, stackAttempts, jobEnds, runeJobs, lanePartnerLvl10, worldMetrics, laneLabel, roles, C };
