// The lane ladder's isolation check (master docs/proposals/2026-11-19-lane-ladder.md section 3; drills `ladder-*`,
// humaniser/drill.ts): one row per in-lane hero of a ladder game (`ev=drill ph=role`, role `cast` of a ladder drill or
// `inlane`), read from its snapshots up to :until (default 10:00, the laning stage). Per hero:
//   lane       its lane from team and position (pos 1 and 5 safe, 2 mid, 3 and 4 off)
//   out        seconds in another lane or off every lane (dynamic.js laneLabel: neither its lane nor `base`)
//   base       seconds at base (the fountain or the ancient: trips home, deaths' respawns)
//   cross      seconds an enemy hero assigned to another lane had it as attack target (`tid`: auto-attacks only, so a
//              spell cast from another lane is not seen here)
//   forbid     global-spell episodes the drill's backstop cleared (`ev=drill ph=forbid`, at most one per 5 s; any line
//              means a hero file lacks its ForbidsCast hook)
// A seconds count is the sum of snapshot gaps (each capped at GAP_CAP s, so a death's gap does not count). The check holds
// for a game when every hero's `out` is at most OUT_BAR s and every `cross` is 0 (`ok`). Bars are `judgement`: a hero that
// stands a few seconds past its lane's band (LANE_R) chasing a pull is not a rotation.
// Usage: node ladder_isolation.js <file fragment> [...] [--until M:SS] [--json] [--no-ingest]
'use strict';
const fs = require('fs');
const path = require('path');
const { Store, DB, LOGS, JOBS } = require('./store');
const { laneLabel } = require('./dynamic');

const GAP_CAP = 2;
const OUT_BAR = 10;
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
        const acc = new Map(inLane.map((h) => [h.pid, { out: 0, base: 0, cross: 0 }]));
        const last = new Map();
        for (const s of snaps) {
            const prev = last.get(s.pid);
            last.set(s.pid, s.t);
            if (prev === undefined) continue;
            const dt = Math.min(GAP_CAP, s.t - prev);
            const mine = acc.get(s.pid);
            if (mine) {
                const at = laneLabel([s.x, s.y]);
                if (at === 'base') mine.base += dt;
                else if (at !== laneByPid.get(s.pid)) mine.out += dt;
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
                out: Math.round(a.out), base: Math.round(a.base), cross: Math.round(a.cross), forbid: forbid.get(h.pid) ?? 0,
            });
        }
    }
    return out;
}

/** Per game: whether the check holds (every hero within OUT_BAR s out of lane, no cross-lane attack). */
function verdicts(list) {
    const by = new Map();
    for (const r of list) {
        if (!by.has(r.file)) by.set(r.file, { file: r.file, heroes: 0, worstOut: 0, cross: 0, ok: 1 });
        const v = by.get(r.file);
        v.heroes++;
        v.worstOut = Math.max(v.worstOut, r.out);
        v.cross += r.cross;
        if (r.out > OUT_BAR || r.cross > 0) v.ok = 0;
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

module.exports = { rows, verdicts, laneOf, OUT_BAR };
