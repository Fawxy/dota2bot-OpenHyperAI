// The lane ladder's isolation check (master docs/proposals/2026-11-19-lane-ladder.md section 3; drills `ladder-*`,
// humaniser/drill.ts): one row per in-lane hero of a ladder game (`ev=drill ph=role`, role `cast` of a ladder drill or
// `inlane`), read from its snapshots up to :until (default 10:00, the laning stage). Per hero:
//   lane       its lane from team and position (pos 1 and 5 safe, 2 mid, 3 and 4 off)
//   away       seconds nearer another lane's line than its own (outside base): a hero that left its lane
//   off        seconds off every lane's band (dynamic.js laneLabel `other`) but nearest its own lane: its own side of
//              the lane (camps, the edge behind its towers); reported, not a fail (rung 3's camps are the hero's job)
//   base       seconds at base (the fountain or the ancient: trips home, deaths' respawns)
//   cross      seconds an enemy hero assigned to another lane had it as attack target (`tid`: auto-attacks only, so a
//              spell cast from another lane is not seen here)
//   forbid     global-spell episodes the drill's backstop cleared (`ev=drill ph=forbid`, at most one per 5 s; any line
//              means a hero file lacks its ForbidsCast hook)
// A seconds count is the sum of snapshot gaps (each capped at GAP_CAP s, so a death's gap does not count). The check holds
// for a game when every hero's `away` is at most AWAY_BAR s and every `cross` is 0 (`ok`). The bar is `judgement`: a few
// seconds nearer another lane (a chase across the river) is not a rotation.
// Usage: node ladder_isolation.js <file fragment> [...] [--until M:SS] [--json] [--no-ingest]
'use strict';
const fs = require('fs');
const path = require('path');
const { Store, DB, LOGS, JOBS } = require('./store');
const { laneLabel, POLY } = require('./dynamic');

const GAP_CAP = 2;
const AWAY_BAR = 10;

function segDist(p, a, b) {
    const dx = b[0] - a[0], dy = b[1] - a[1], l2 = dx * dx + dy * dy;
    const t = l2 ? Math.max(0, Math.min(1, ((p[0] - a[0]) * dx + (p[1] - a[1]) * dy) / l2)) : 0;
    return Math.hypot(p[0] - (a[0] + t * dx), p[1] - (a[1] + t * dy));
}

/** The lane whose line (dynamic.js POLY) is nearest a point, at any distance. */
function nearestLane(p) {
    let best = null, bd = Infinity;
    for (const [L, P] of Object.entries(POLY)) {
        for (let i = 0; i + 1 < P.length; i++) {
            const d = segDist(p, P[i], P[i + 1]);
            if (d < bd) [bd, best] = [d, L];
        }
    }
    return best;
}
const SAFE = { 2: 'bot', 3: 'top' };
const OFF = { 2: 'top', 3: 'bot' };

/** A hero's lane from its team and position. */
function laneOf(team, pos) {
    if (pos === 2) return 'mid';
    if (pos === 1 || pos === 5) return SAFE[team];
    if (pos === 3 || pos === 4) return OFF[team];
    return null;
}

const ROLES = `SELECT d.game_id, g.file, d.pid, d.team, d.pos, d.role, d.name FROM ev_drill d JOIN games g ON g.game_id = d.game_id
    WHERE d.ph = 'role' AND d.name LIKE 'ladder-%' AND g.file LIKE :like ORDER BY d.game_id, d.pid, d.t`;
const SNAPS = `SELECT pid, t, x, y, tid FROM ev_snap WHERE game_id = :g AND t <= :u ORDER BY pid, t`;
const FORBID = `SELECT pid, count(*) AS n FROM ev_drill WHERE game_id = :g AND ph = 'forbid' GROUP BY pid`;

/** One row per in-lane hero of the games whose file matches `like`, up to `until` game seconds. */
function rows(store, like, until = 600) {
    const games = new Map();
    for (const r of store.query(ROLES, { like: `%${like}%` })) {
        if (!games.has(r.game_id)) games.set(r.game_id, { file: r.file, heroes: new Map() });
        // The last role line wins (a role logged before the position was known plays).
        games.get(r.game_id).heroes.set(r.pid, r);
    }
    const out = [];
    for (const [g, game] of games) {
        const inLane = [...game.heroes.values()].filter((h) => h.role === 'inlane' || h.role === 'cast');
        const laneByPid = new Map(inLane.map((h) => [h.pid, laneOf(h.team, h.pos)]));
        const teamByPid = new Map([...game.heroes.values()].map((h) => [h.pid, h.team]));
        const snaps = store.query(SNAPS, { g, u: until });
        const forbid = new Map(store.query(FORBID, { g }).map((r) => [r.pid, r.n]));
        const acc = new Map(inLane.map((h) => [h.pid, { away: 0, off: 0, base: 0, cross: 0 }]));
        const last = new Map();
        for (const s of snaps) {
            const prev = last.get(s.pid);
            last.set(s.pid, s.t);
            if (prev === undefined) continue;
            const dt = Math.min(GAP_CAP, s.t - prev);
            const mine = acc.get(s.pid);
            if (mine) {
                const at = laneLabel([s.x, s.y]);
                const own = laneByPid.get(s.pid);
                if (at === 'base') mine.base += dt;
                else if (nearestLane([s.x, s.y]) !== own) mine.away += dt;
                else if (at !== own) mine.off += dt;
            }
            // An enemy hero of another lane attacking an in-lane hero.
            const m = s.tid == null ? null : String(s.tid).match(/^h(\d+)$/);
            if (!m) continue;
            const target = Number(m[1]);
            const victim = acc.get(target);
            if (!victim || teamByPid.get(s.pid) === teamByPid.get(target)) continue;
            const attacker = game.heroes.get(s.pid);
            const attackerLane = attacker ? laneOf(attacker.team, attacker.pos) : null;
            if (attackerLane !== laneByPid.get(target)) victim.cross += dt;
        }
        for (const h of inLane) {
            const a = acc.get(h.pid);
            out.push({
                file: path.basename(game.file), name: h.name, pid: h.pid, team: h.team, pos: h.pos, lane: laneByPid.get(h.pid),
                away: Math.round(a.away), off: Math.round(a.off), base: Math.round(a.base), cross: Math.round(a.cross), forbid: forbid.get(h.pid) ?? 0,
            });
        }
    }
    return out;
}

/** Per game: whether the check holds (every hero within AWAY_BAR s nearer another lane, no cross-lane attack). */
function verdicts(list) {
    const by = new Map();
    for (const r of list) {
        if (!by.has(r.file)) by.set(r.file, { file: r.file, heroes: 0, worstAway: 0, worstOff: 0, cross: 0, ok: 1 });
        const v = by.get(r.file);
        v.heroes++;
        v.worstAway = Math.max(v.worstAway, r.away);
        v.worstOff = Math.max(v.worstOff, r.off);
        v.cross += r.cross;
        if (r.away > AWAY_BAR || r.cross > 0) v.ok = 0;
    }
    return [...by.values()];
}

function parseClock(s) {
    const m = String(s).match(/^(\d+):(\d\d)$/);
    return m ? Number(m[1]) * 60 + Number(m[2]) : Number(s);
}

function main(argv) {
    const args = argv.slice(2);
    if (args.length === 0 || args.includes('--help')) {
        console.log('Usage: node ladder_isolation.js <file fragment> [...] [--until M:SS] [--json] [--no-ingest]');
        return;
    }
    const json = args.includes('--json');
    const noIngest = args.includes('--no-ingest');
    const ui = args.indexOf('--until');
    const until = ui >= 0 ? parseClock(args[ui + 1]) : 600;
    const likes = args.filter((a, i) => !a.startsWith('--') && !(ui >= 0 && i === ui + 1));
    const store = new Store(DB);
    if (!noIngest) for (const f of store.ingestAll([LOGS, JOBS].filter((d) => fs.existsSync(d))).failed) console.error(`not ingested: ${f.file}: ${f.error}`);
    const list = likes.flatMap((l) => rows(store, l, until));
    const games = verdicts(list);
    if (json) {
        console.log(JSON.stringify({ heroes: list, games }, null, 1));
        return;
    }
    console.table(list);
    console.table(games);
}

if (require.main === module) main(process.argv);

module.exports = { rows, verdicts, laneOf, nearestLane, AWAY_BAR };
