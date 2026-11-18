// The lane trade rig's reps (drill `lane-trade`, humaniser/drill.ts; master docs/proposals/2026-11-18-trade-from-the-stand.md
// step 2): one row per trade a cast opened (`ev=trade` kind `trade`, taken: result done or kill) inside a ready rig rep, from its
// release to the next rep's start. The trade's open is its end line's time less `dur`. The rig's own truth, the cast's `watch`
// lines: `ph=atk` (an attack fired at an enemy hero) and `ph=chit` (an enemy lane creep's attack fired at the cast). Per trade:
//   hero, var  the cast's hero and the rep kind (stand, lasthit, hitback); n its order among the rep's trades (1 = first)
//   ordered    an attack order given: the trade's `pr` (orders given clear of creeps) over 0, or an attack fired in it
//   fired      an attack fired at the target between open and end (the rig's truth; the trade's own `ld` beside it)
//   first      seconds from open to the first attack fired at the target, within WINDOW s (null: none)
//   a5         attacks fired at the target within WINDOW s of the open
//   hpd, thpd  HP lost by the cast and the target over the trade (its own fields); hp5, thp5 the same over WINDOW s, the sum of
//              drops between 1 s snapshots (`hv`)
//   ch5        enemy creep attacks fired at the cast within WINDOW s; ag the trade's most creeps on it at once
//   why, dur   how and when the trade ended; so the step-outs
// A trade opening within WINDOW s of its rep's end is cut by the next rep's setup (the cast is held again): listed `late`, left
// out of the summary. Untaken offers (result lost) are counted apart. Summary per hero and kind: ready reps, reps with a
// trade, trades, ordered, fired, mean first, a5, HP each way and ch5, and the ends.
// Usage: node trade_rig.js <file fragment> [...] [--rows] [--json] [--no-ingest]
'use strict';
const fs = require('fs');
const path = require('path');
const { Store, DB, LOGS, JOBS } = require('./store');

const DRILL = fs.readFileSync(path.join(__dirname, 'queries', 'drill.sql'), 'utf8');
const NAME = 'lane-trade';
const WINDOW = 5;

const TRADES = `SELECT t, kind, result, why, dur, hpd, thpd, ld, pr, so, ag, tgt FROM ev_trade
    WHERE game_id = :g AND pid = :p AND t >= :a AND t <= :b ORDER BY t`;
const LINES = `SELECT t, ph, tpid FROM ev_drill WHERE game_id = :g AND pid = :p AND ph IN ('atk', 'chit') AND t >= :a AND t <= :b ORDER BY t`;
const SNAPS = `SELECT t, hv FROM ev_snap WHERE game_id = :g AND pid = :p AND t >= :a AND t <= :b ORDER BY t`;
const HERO = `SELECT hero FROM ev_bot WHERE game_id = :g AND pid = :p AND hero IS NOT NULL LIMIT 1`;

const round1 = (x) => (x == null ? null : Math.round(x * 10) / 10);

/** HP lost between 1 s snapshots in [a, b]: drops only, so a regen tick does not hide a hit. */
function lost(snaps, a, b) {
    let sum = 0;
    let prev = null;
    for (const s of snaps) {
        if (s.t < a - 1 || s.t > b) continue;
        if (prev != null && s.t > a && prev > s.hv) sum += prev - s.hv;
        prev = s.hv;
    }
    return Math.round(sum);
}

/** The trade rows of the games whose file matches `like`, and the per-rep counts the summary needs. */
function reps(store, like) {
    const rows = store.query(DRILL, { like: `%${like}%`, name: NAME }).filter((r) => r.released != null);
    const trades = [];
    const repRows = [];
    const heroes = new Map();
    const heroOf = (g, p) => {
        const k = `${g}:${p}`;
        if (!heroes.has(k)) heroes.set(k, store.query(HERO, { g, p })[0]?.hero ?? `pid${p}`);
        return heroes.get(k);
    };
    for (const r of rows) {
        const hero = heroOf(r.game_id, r.pid);
        // A trade ending after the rep's stop may still have opened inside it.
        const ts = store.query(TRADES, { g: r.game_id, p: r.pid, a: r.released, b: r.stop + 30 });
        const opened = ts.map((x) => ({ ...x, open: x.t - (x.dur ?? 0) })).filter((x) => x.kind === 'trade' && x.open >= r.released && x.open < r.stop);
        const taken = opened.filter((x) => x.result !== 'lost');
        repRows.push({ file: path.basename(r.file), game_id: r.game_id, rep: r.rep, var: r.var, hero, trades: taken.length, lost: opened.length - taken.length });
        const lines = store.query(LINES, { g: r.game_id, p: r.pid, a: r.released, b: r.stop + 30 });
        const own = store.query(SNAPS, { g: r.game_id, p: r.pid, a: r.released - 1, b: r.stop + 30 });
        taken.forEach((x, i) => {
            const atk = lines.filter((l) => l.ph === 'atk' && l.tpid === x.tgt);
            const in5 = atk.filter((l) => l.t >= x.open && l.t <= x.open + WINDOW);
            const tsnaps = store.query(SNAPS, { g: r.game_id, p: x.tgt, a: x.open - 1, b: x.open + WINDOW });
            const fired = atk.some((l) => l.t >= x.open && l.t <= x.t);
            trades.push({
                file: path.basename(r.file), rep: r.rep, var: r.var, hero, n: i + 1, open: round1(x.open), tgt: x.tgt,
                late: x.open + WINDOW > r.stop ? 1 : 0,
                ordered: (x.pr ?? 0) > 0 || fired ? 1 : 0, pr: x.pr, so: x.so,
                fired: fired ? 1 : 0, ld: x.ld,
                first: in5.length ? round1(in5[0].t - x.open) : null,
                a5: in5.length,
                hpd: x.hpd, thpd: x.thpd,
                hp5: lost(own, x.open, x.open + WINDOW), thp5: lost(tsnaps, x.open, x.open + WINDOW),
                ch5: lines.filter((l) => l.ph === 'chit' && l.t >= x.open && l.t <= x.open + WINDOW).length,
                ag: x.ag, why: x.why, dur: x.dur,
            });
        });
    }
    return { trades, reps: repRows };
}

const mean = (xs) => (xs.length ? round1(xs.reduce((a, b) => a + b, 0) / xs.length) : null);

/** Per hero and rep kind: ready reps, reps with a trade, graded trades and their means; the ends counted. */
function summary({ trades, reps: rs }) {
    const out = {};
    const key = (x) => `${x.hero} ${x.var}`;
    for (const r of rs) {
        const s = (out[key(r)] ??= { ready: 0, withTrade: 0, lost: 0, trades: 0, late: 0 });
        s.ready += 1;
        if (r.trades > 0) s.withTrade += 1;
        s.lost += r.lost;
    }
    const by = {};
    for (const t of trades) (by[key(t)] ??= []).push(t);
    for (const [k, all] of Object.entries(by)) {
        const s = out[k];
        const ts = all.filter((t) => !t.late);
        s.late = all.length - ts.length;
        s.trades = ts.length;
        s.ordered = ts.filter((t) => t.ordered).length;
        s.fired = ts.filter((t) => t.fired).length;
        s.first = mean(ts.filter((t) => t.first != null).map((t) => t.first));
        s.a5 = mean(ts.map((t) => t.a5));
        s.hpd = mean(ts.map((t) => t.hpd ?? 0));
        s.thpd = mean(ts.map((t) => t.thpd ?? 0));
        s.hp5 = mean(ts.map((t) => t.hp5));
        s.thp5 = mean(ts.map((t) => t.thp5));
        s.ch5 = mean(ts.map((t) => t.ch5));
        s.why = {};
        for (const t of ts) s.why[t.why] = (s.why[t.why] ?? 0) + 1;
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
    const all = { trades: [], reps: [] };
    for (const l of likes) {
        const r = reps(store, l);
        all.trades.push(...r.trades);
        all.reps.push(...r.reps);
    }
    if (argv.includes('--rows')) console.log(all.trades.map((r) => JSON.stringify(r)).join('\n'));
    else if (argv.includes('--json')) console.log(JSON.stringify(summary(all)));
    else {
        console.log(`lane-trade: ${all.reps.length} ready reps, ${all.trades.length} taken trades; graded within ${WINDOW} s of the open (late: opened within ${WINDOW} s of the rep's end)`);
        for (const [k, s] of Object.entries(summary(all))) {
            const why = Object.entries(s.why ?? {}).map(([w, n]) => `${w} ${n}`).join(', ');
            console.log(`${k.padEnd(22)} ready ${s.ready}  with trade ${s.withTrade}  trades ${s.trades} (late ${s.late}, lost ${s.lost})  ordered ${s.ordered ?? 0}  fired ${s.fired ?? 0}  first ${s.first ?? '-'} s  a5 ${s.a5 ?? '-'}  hp ${s.hpd ?? '-'}/${s.thpd ?? '-'} (5 s ${s.hp5 ?? '-'}/${s.thp5 ?? '-'})  ch5 ${s.ch5 ?? '-'}  ends: ${why}`);
        }
    }
}

module.exports = { reps, summary, WINDOW };
