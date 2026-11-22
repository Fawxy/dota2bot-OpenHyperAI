// The two-hero kill rig's reps (drill `pair-kill`, humaniser/drill.ts; docs/proposals/2026-11-18-fighting-together.md "Tools";
// D10, D19): one row per rep in which both cast heroes reached ready, read from the later release to the rep's end, from
// whole snapshots (`tid`, `mode`) and the target's death (fragment ep_death). Per rep:
//   target     the enemy hero either cast hit first (`h<pid>`); none when neither hit an enemy hero
//   hit1/hit2  the pos1's and the pos5's first hit on it, seconds after release (null: never); `gap` between them
//   split      a cast hit another enemy hero in the rep
//   killed     the target died in the rep (`kt` seconds after release)
//   last1/2    each one's last hit on the target; `ret1/2` its first snapshot in mode retreat after its first hit
// Grades (judgement; the pair view's 3 s): `both` both hit within BOTH_GAP s of each other; `kill`; `together`, of reps
// where the target lived and both hit, the last hits within STOP_GAP s and the retreats (if any) within STOP_GAP s.
// The control kind (`outnum`) is reported apart: `attacked` is whether either cast hit an enemy hero at all.
// Usage: node pair_rig.js <file fragment> [...] [--rows] [--json] [--no-ingest]
'use strict';
const fs = require('fs');
const path = require('path');
const { Store, DB, LOGS, JOBS } = require('./store');

const DRILL = fs.readFileSync(path.join(__dirname, 'queries', 'drill.sql'), 'utf8');
const NAME = 'pair-kill';
const BOTH_GAP = 2;
const STOP_GAP = 3;
const CONTROLS = ['outnum'];

const SNAPS = `SELECT pid, t, tid, mode FROM ev_snap WHERE game_id = :g AND pid = :p AND t >= :a AND t <= :b ORDER BY t`;
const DEATH = `WITH gm AS MATERIALIZED (SELECT +game_id AS game_id FROM games WHERE game_id = :g),
-- include: ep_death
done AS (SELECT 1)
SELECT t FROM ep_death WHERE pid = :p AND t >= :a AND t <= :b ORDER BY t LIMIT 1`;

/** The rep rows of the games whose file matches `like`. */
function reps(store, like) {
    const rows = store.query(DRILL, { like: `%${like}%`, name: NAME });
    const by = new Map();
    for (const r of rows) {
        const k = `${r.game_id}:${r.rep}`;
        if (!by.has(k)) by.set(k, { game_id: r.game_id, file: r.file, rep: r.rep, var: r.var, cast: {} });
        by.get(k).cast[r.pos] = r;
    }
    const out = [];
    for (const v of by.values()) {
        const a = v.cast[1];
        const b = v.cast[5];
        if (!a || !b || a.released == null || b.released == null) continue;
        out.push(read(store, v, a, b));
    }
    return out;
}

const round1 = (x) => (x == null ? null : Math.round(x * 10) / 10);

/** One rep's row: hits, target, kill, stops. */
function read(store, v, a, b) {
    const t0 = Math.max(a.released, b.released);
    const t1 = Math.min(a.stop, b.stop);
    const sa = store.query(SNAPS, { g: v.game_id, p: a.pid, a: t0, b: t1 });
    const sb = store.query(SNAPS, { g: v.game_id, p: b.pid, a: t0, b: t1 });
    const enemy = new Set(store.query(`SELECT pid FROM lineup WHERE game_id = :g AND team <> :t`, { g: v.game_id, t: a.team }).map((r) => `h${r.pid}`));
    const heroHit = (s) => s.tid != null && enemy.has(String(s.tid));
    const firstAny = [...sa, ...sb].filter(heroHit).sort((x, y) => x.t - y.t)[0];
    const row = { file: path.basename(v.file), rep: v.rep, var: v.var, released: round1(t0), target: firstAny ? String(firstAny.tid) : null };
    row.attacked = firstAny ? 1 : 0;
    const on = (s) => s.filter((x) => String(x.tid) === row.target);
    const ha = on(sa);
    const hb = on(sb);
    row.hit1 = ha.length ? round1(ha[0].t - t0) : null;
    row.hit2 = hb.length ? round1(hb[0].t - t0) : null;
    row.gap = row.hit1 != null && row.hit2 != null ? round1(Math.abs(row.hit1 - row.hit2)) : null;
    row.split = [...sa, ...sb].some((s) => heroHit(s) && String(s.tid) !== row.target) ? 1 : 0;
    row.killed = 0;
    row.kt = null;
    if (row.target) {
        const died = store.query(DEATH, { g: v.game_id, p: Number(row.target.slice(1)), a: t0 - 1, b: t1 })[0];
        if (died) {
            row.killed = 1;
            row.kt = round1(died.t - t0);
        }
    }
    row.last1 = ha.length ? round1(ha[ha.length - 1].t - t0) : null;
    row.last2 = hb.length ? round1(hb[hb.length - 1].t - t0) : null;
    const ret = (s, h) => {
        if (!h.length) return null;
        const x = s.find((y) => y.t >= h[0].t && y.mode === 'retreat');
        return x ? round1(x.t - t0) : null;
    };
    row.ret1 = ret(sa, ha);
    row.ret2 = ret(sb, hb);
    row.control = CONTROLS.includes(v.var) ? 1 : 0;
    row.both = row.gap != null && row.gap <= BOTH_GAP ? 1 : 0;
    row.together = null;
    if (!row.killed && row.hit1 != null && row.hit2 != null) {
        const stops = Math.abs(row.last1 - row.last2) <= STOP_GAP;
        const rets = (row.ret1 == null) === (row.ret2 == null) && (row.ret1 == null || Math.abs(row.ret1 - row.ret2) <= STOP_GAP);
        row.together = stops && rets ? 1 : 0;
    }
    return row;
}

/** Per rep kind: reps, both hit within the gap, kills, together of the lived; controls: attacked. */
function summary(rows) {
    const kinds = {};
    for (const r of rows) (kinds[r.var] ??= []).push(r);
    const out = {};
    for (const [k, rs] of Object.entries(kinds)) {
        const lived = rs.filter((r) => r.together != null);
        out[k] = {
            reps: rs.length,
            control: rs[0].control,
            attacked: rs.filter((r) => r.attacked).length,
            both: rs.filter((r) => r.both).length,
            kill: rs.filter((r) => r.killed).length,
            together: `${lived.filter((r) => r.together).length} of ${lived.length}`,
        };
    }
    return out;
}

if (require.main === module) {
    const argv = process.argv.slice(2);
    const likes = argv.filter((a) => !a.startsWith('--'));
    if (!likes.length || argv.includes('--help')) {
        console.log(fs.readFileSync(__filename, 'utf8').split('\n').filter((l) => l.startsWith('//')).map((l) => l.slice(3)).join('\n'));
        process.exit(likes.length ? 0 : 2);
    }
    const store = new Store(DB);
    if (!argv.includes('--no-ingest')) for (const f of store.ingestAll([LOGS, JOBS].filter((d) => fs.existsSync(d))).failed) console.error(`not ingested: ${f.file}: ${f.error}`);
    const rows = likes.flatMap((l) => reps(store, l));
    if (argv.includes('--rows')) console.log(rows.map((r) => JSON.stringify(r)).join('\n'));
    else if (argv.includes('--json')) console.log(JSON.stringify(summary(rows)));
    else {
        console.log(`pair-kill reps with both casts ready: ${rows.length}; both = first hits within ${BOTH_GAP} s, together = stops within ${STOP_GAP} s`);
        for (const [k, s] of Object.entries(summary(rows))) {
            console.log(`${k.padEnd(8)} ${s.control ? 'control ' : ''}reps ${s.reps}  attacked ${s.attacked}  both ${s.both}  kill ${s.kill}  together ${s.together}`);
        }
    }
}

module.exports = { reps, summary, BOTH_GAP, STOP_GAP };
