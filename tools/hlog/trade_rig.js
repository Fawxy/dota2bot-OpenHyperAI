// The lane trade rig's reps (drill `lane-trade`, humaniser/drill.ts; the `trade-from-the-stand` proposal (master tag `pre-process-v5`)
// step 2): one row per trade a cast opened (`ev=trade` kind `hit` or `hitback`; `trade` on older logs; taken: result done or kill) inside a ready rig rep, from its
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
//   hpc, hph   HP the cast lost during the trade (open to end) to enemy lane creeps and to the target's attacks: the sum of
//              the `dmg` on its `ph=chit` and `ph=hhit` lines (each attack's mean damage after armour, counted when fired);
//              hpo the rest of `hpd`: spells, passives, a tower, less regen and any rig HP reset inside the trade (so it can
//              be negative; printed as "rest incl. regen/resets"). A creep's attack counts when its
//              GetLastAttackTime moves, which a swing cancelled by a step-out also does (rig1_s30, 194.8 s: three counted,
//              two landed), so hpc is an upper bound
//   s5         HP the cast lost within WINDOW s of the open, by the snapshots' own damage flags (`lostBy`): creeps, hero,
//              both, other; the measured split, at 1 s grain
//   sf         the episode began with a step-out before any attack order: the trade's `fa` = step (logs before `fa`: so > 0
//              and pr = 0 is 1, pr > 0 with so = 0 is 0, both unknown)
//   ulh, udn   last hits and denies that went untaken during the trade: enemy lane creeps (`ev=creep_death`) and our own
//              (unit_life's own deaths: near a hero of its team, at 50% HP or under) that died from open to end within the cast's attack range +
//              REACH_SLACK of it, not credited to it (`by`); the cast's place is its nearest snapshot
//   why, dur   how and when the trade ended (`creeps`: two creeps hitting us); so the step-outs
// A trade whose window or episode holds an HP reset (the recipe's rig_hp_all, sent for :55 and run 1 to 6 s late at 8x: from
// its [DOTACTL] cmd line's time to RESET_LAG after) or runs past its rep's end (the cast is held again) is listed `late`, left
// out of the summary. Untaken offers (result lost) are counted apart. Summary per hero and kind: ready reps, reps with a
// trade, trades, ordered, fired, mean first, a5, HP each way and ch5, the HP split summed and per trade, step first, the
// untaken creeps, the ends and the share ending `creeps`.
// The range read (plan "Revision after D and D2"; graded by time, so it holds with no trade open): every released snapshot
// second of the cast at 75% HP or more with the nearest enemy hero (its own snapshot within a second) inside the cast's `ar`
// + 48 (strict, both hulls) is one in-range second, split as `hero` (its `tid` an enemy hero), `creep` (`tid` a creep), or by
// its move to the next snapshot along the line to that hero: `toward` or `away` (over MOVE_STEP), else `idle`; the modes
// that held it in the seconds it was not attacking the hero (marked `(trade)` inside an open trade episode) and the hero
// seconds inside one; and the hero share within +400 (`wide`). As D2's read of the
// head-to-heads (ours 33%, OHA 52% strict), so the numbers compare.
// Usage: node trade_rig.js <file fragment> [...] [--rows] [--reps] [--json] [--no-ingest]
// --rows prints one JSON line per trade, --reps one per ready rep (its trade counts and range read).
'use strict';
const fs = require('fs');
const path = require('path');
const { Store, DB, LOGS, JOBS } = require('./store');

const DRILL = fs.readFileSync(path.join(__dirname, 'queries', 'drill.sql'), 'utf8');
const NAME = 'lane-trade';
const WINDOW = 5;
/** Two hulls (hero 24, creep 16) and a little: a creep at this past attack range is still in reach. `judgement`. */
const REACH_SLACK = 50;
/** The reset's HP lands up to this long after its cmd line's time (rig1b_s30: the line at 209, the HP at 211). */
const RESET_LAG = 3;
/** A move of this much along the line to the hero in a snapshot second is toward or away. `judgement`. */
const MOVE_STEP = 25;
const HULLS = 48;
const WIDE = 400;

const TRADES = `-- ensure: ev_trade(fa)
SELECT t, kind, result, why, dur, hpd, thpd, ld, pr, so, ag, tgt, fa FROM ev_trade
    WHERE game_id = :g AND pid = :p AND t >= :a AND t <= :b ORDER BY t`;
const LINES = `SELECT t, ph, tpid, dmg FROM ev_drill WHERE game_id = :g AND pid = :p AND ph IN ('atk', 'chit', 'hhit') AND t >= :a AND t <= :b ORDER BY t`;
const SNAPS = `-- ensure: ev_snap(tid, mode)
SELECT t, hv, hp, x, y, ar, hc, hit, tid, mode, alive FROM ev_snap WHERE game_id = :g AND pid = :p AND t >= :a AND t <= :b ORDER BY t`;
const deaths = (tbl) => `-- ensure: ${tbl}(team, x, y, by)
SELECT t, x, y, by FROM ${tbl} WHERE game_id = :g AND team = :team AND t >= :a AND t <= :b ORDER BY t`;
const LH_DEATHS = deaths('ev_creep_death');
// The own lane creeps' deaths of a game, the old ev=own_creep_death rows (near a hero of the team at half health or less: unit_life's CTE ul_odeath), read once a game.
const DN_DEATHS = `WITH ul_gm AS (SELECT :g AS game_id),
-- include: unit_life_in
-- include: unit_life_lane
SELECT t, team, x, y, coalesce(CAST(dny AS TEXT), 'none') AS by FROM ul_odeath ORDER BY t`;
const dnCache = new Map();
function ownDeaths(store, g, team, a, b) {
    if (!dnCache.has(g)) dnCache.set(g, store.query(DN_DEATHS, { g }));
    return dnCache.get(g).filter((r) => r.team === team && r.t >= a && r.t <= b);
}

/**
 * HP drops between 1 s snapshots in [a, b], each put to the source the snapshot's API flags name for its last second: `hc`
 * (a creep) alone, `hit` (a hero) alone, both, or neither (a tower, or a spell the flags miss).
 */
function lostBy(snaps, a, b) {
    const out = { creeps: 0, hero: 0, both: 0, other: 0 };
    let prev = null;
    for (const s of snaps) {
        if (s.t < a - 1 || s.t > b) continue;
        if (prev != null && s.t > a && prev.hv > s.hv) out[s.hc && s.hit ? 'both' : s.hc ? 'creeps' : s.hit ? 'hero' : 'other'] += prev.hv - s.hv;
        prev = s;
    }
    return out;
}

/**
 * The range read of one released window: per cast snapshot at `hp` 75 or more, the nearest enemy hero by its own snapshot
 * within a second; in strict range, the second's class and mode; within +WIDE, whether it attacked the hero.
 */
function rangeSeconds(own, foes, a, b, episodes = []) {
    const out = { secs: 0, hero: 0, creep: 0, toward: 0, away: 0, idle: 0, modes: {}, heroModes: {}, wide: 0, wideHero: 0, heroTrade: 0 };
    for (let i = 0; i < own.length; i++) {
        const s = own[i];
        if (s.t < a || s.t >= b || s.alive === 0 || s.hp == null || s.hp < 75 || s.x == null || s.ar == null) continue;
        let foe = null;
        let d = Infinity;
        for (const [pid, snaps] of foes) {
            const f = nearest(snaps, s.t);
            if (f == null || Math.abs(f.t - s.t) > 1 || f.alive === 0 || f.x == null) continue;
            const dd = Math.hypot(f.x - s.x, f.y - s.y);
            if (dd < d) [foe, d] = [{ ...f, pid }, dd];
        }
        if (foe == null || d > s.ar + HULLS + WIDE) continue;
        const onHero = s.tid === `h${foe.pid}`;
        out.wide += 1;
        if (onHero) out.wideHero += 1;
        if (d > s.ar + HULLS) continue;
        out.secs += 1;
        let k;
        if (onHero) k = 'hero';
        else if (typeof s.tid === 'string' && s.tid.startsWith('u')) k = 'creep';
        else {
            const n = own[i + 1];
            const step = n != null && n.t - s.t <= 1.5 && n.x != null ? ((n.x - s.x) * (foe.x - s.x) + (n.y - s.y) * (foe.y - s.y)) / Math.max(1, d) : 0;
            k = step > MOVE_STEP ? 'toward' : step < -MOVE_STEP ? 'away' : 'idle';
        }
        out[k] += 1;
        // `mode` never names our states; an open exchange is states/trade's hold whatever OHA mode carries it.
        const inTrade = episodes.some(([o, c]) => s.t >= o && s.t <= c);
        const m = inTrade ? `${s.mode} (trade)` : s.mode;
        const tally = k === 'hero' ? out.heroModes : out.modes;
        tally[m] = (tally[m] ?? 0) + 1;
        if (k === 'hero' && inTrade) out.heroTrade += 1;
    }
    return out;
}

/** The snapshot nearest `t`. */
function nearest(snaps, t) {
    let best = null;
    for (const s of snaps) if (best == null || Math.abs(s.t - t) < Math.abs(best.t - t)) best = s;
    return best;
}

/** Creep deaths in `rows` not credited to `pid` within the cast's attack range + REACH_SLACK of it (its nearest snapshot). */
function untaken(rows, snaps, pid) {
    return rows.filter((d) => {
        if (String(d.by) === String(pid) || d.x == null) return false;
        const s = nearest(snaps, d.t);
        return s != null && s.x != null && s.ar != null && Math.hypot(s.x - d.x, s.y - d.y) <= s.ar + REACH_SLACK;
    }).length;
}

/** Began with a step-out: the trade's `fa`, else what `so` and `pr` alone say. */
function stepFirst(x) {
    if (x.fa != null) return x.fa === 'step' ? 1 : 0;
    if ((x.so ?? 0) > 0 && (x.pr ?? 0) === 0) return 1;
    if ((x.so ?? 0) === 0 && (x.pr ?? 0) > 0) return 0;
    return null;
}
const HERO = `SELECT hero FROM ev_bot WHERE game_id = :g AND pid = :p AND hero IS NOT NULL LIMIT 1`;
const ENEMIES = `SELECT DISTINCT pid FROM ev_bot WHERE game_id = :g AND team IS NOT NULL AND team <> :team`;
const RESETS = `SELECT d.t FROM dx_cmd d JOIN games g ON g.log_id = d.log_id WHERE g.game_id = :g AND d.cmd LIKE 'rig_hp_all%' ORDER BY d.t`;

/** When the HP resets ran in the game (none when the log holds no console steps). */
function resetsOf(store, g) {
    try {
        return store.query(RESETS, { g }).map((r) => r.t);
    } catch {
        return [];
    }
}

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
    const resets = new Map();
    for (const r of rows) {
        const hero = heroOf(r.game_id, r.pid);
        if (!resets.has(r.game_id)) resets.set(r.game_id, resetsOf(store, r.game_id));
        const hpSet = resets.get(r.game_id);
        // A trade ending after the rep's stop may still have opened inside it.
        const ts = store.query(TRADES, { g: r.game_id, p: r.pid, a: r.released, b: r.stop + 30 });
        const opened = ts.map((x) => ({ ...x, open: x.t - (x.dur ?? 0) })).filter((x) => (x.kind === 'hit' || x.kind === 'hitback' || x.kind === 'trade') && x.open >= r.released && x.open < r.stop);
        const taken = opened.filter((x) => x.result !== 'lost');
        const lines = store.query(LINES, { g: r.game_id, p: r.pid, a: r.released, b: r.stop + 30 });
        const own = store.query(SNAPS, { g: r.game_id, p: r.pid, a: r.released - 1, b: r.stop + 30 });
        const foes = store.query(ENEMIES, { g: r.game_id, team: r.team }).map((e) => [e.pid, store.query(SNAPS, { g: r.game_id, p: e.pid, a: r.released - 2, b: r.stop + 2 })]);
        repRows.push({ file: path.basename(r.file), game_id: r.game_id, rep: r.rep, var: r.var, hero, trades: taken.length, lost: opened.length - taken.length, range: rangeSeconds(own, foes, r.released, r.stop, taken.map((x) => [x.open, x.t])) });
        taken.forEach((x, i) => {
            const atk = lines.filter((l) => l.ph === 'atk' && l.tpid === x.tgt);
            const in5 = atk.filter((l) => l.t >= x.open && l.t <= x.open + WINDOW);
            const tsnaps = store.query(SNAPS, { g: r.game_id, p: x.tgt, a: x.open - 1, b: x.open + WINDOW });
            const fired = atk.some((l) => l.t >= x.open && l.t <= x.t);
            const during = (ph, who) => lines.filter((l) => l.ph === ph && l.t >= x.open && l.t <= x.t && (who == null || l.tpid === who)).reduce((s, l) => s + (l.dmg ?? 0), 0);
            const hpc = during('chit');
            const hph = during('hhit', x.tgt);
            trades.push({
                file: path.basename(r.file), rep: r.rep, var: r.var, hero, n: i + 1, open: round1(x.open), tgt: x.tgt,
                late: Math.max(x.open + WINDOW, x.t) > r.stop || hpSet.some((t) => t + RESET_LAG >= x.open && t <= Math.max(x.open + WINDOW, x.t)) ? 1 : 0,
                ordered: (x.pr ?? 0) > 0 || fired ? 1 : 0, pr: x.pr, so: x.so,
                fired: fired ? 1 : 0, ld: x.ld,
                first: in5.length ? round1(in5[0].t - x.open) : null,
                a5: in5.length,
                hpd: x.hpd, thpd: x.thpd, hpc, hph, hpo: (x.hpd ?? 0) - hpc - hph,
                s5: lostBy(own, x.open, x.open + WINDOW),
                sf: stepFirst(x),
                ulh: untaken(store.query(LH_DEATHS, { g: r.game_id, team: r.team, a: x.open, b: x.t }), own, r.pid),
                udn: untaken(ownDeaths(store, r.game_id, r.team, x.open, x.t), own, r.pid),
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
        const g = (s.range ??= { secs: 0, hero: 0, creep: 0, toward: 0, away: 0, idle: 0, modes: {}, heroModes: {}, wide: 0, wideHero: 0, heroTrade: 0 });
        for (const k of ['secs', 'hero', 'heroTrade', 'creep', 'toward', 'away', 'idle', 'wide', 'wideHero']) g[k] += r.range[k];
        for (const t of ['modes', 'heroModes']) for (const [m, n] of Object.entries(r.range[t])) g[t][m] = (g[t][m] ?? 0) + n;
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
        const sum = (f) => ts.reduce((a, t) => a + (t[f] ?? 0), 0);
        s.split = { creeps: sum('hpc'), hero: sum('hph'), other: sum('hpo'), creepsPer: mean(ts.map((t) => t.hpc)), heroPer: mean(ts.map((t) => t.hph)) };
        s.split5 = {};
        for (const k of ['creeps', 'hero', 'both', 'other']) s.split5[k] = ts.reduce((a, t) => a + t.s5[k], 0);
        const known = ts.filter((t) => t.sf != null);
        s.stepFirst = `${known.filter((t) => t.sf === 1).length} of ${known.length}`;
        s.ulh = sum('ulh');
        s.udn = sum('udn');
        s.why = {};
        for (const t of ts) s.why[t.why] = (s.why[t.why] ?? 0) + 1;
        s.creepsEnd = ts.length ? Math.round((100 * (s.why.creeps ?? 0)) / ts.length) : null;
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
    else if (argv.includes('--reps')) console.log(all.reps.map((r) => JSON.stringify(r)).join('\n'));
    else if (argv.includes('--json')) console.log(JSON.stringify(summary(all)));
    else {
        console.log(`lane-trade: ${all.reps.length} ready reps, ${all.trades.length} taken trades; graded within ${WINDOW} s of the open (late: an HP reset in the window, or past the rep's end)`);
        const pct = (n, d) => (d ? `${Math.round((100 * n) / d)}%` : '-');
        for (const [k, s] of Object.entries(summary(all))) {
            const g = s.range;
            const list = (t) => Object.entries(t).sort((a, b) => b[1] - a[1]).map(([m, n]) => `${m} ${n}`).join(', ');
            const modes = `${list(g.modes)}; on the hero: ${list(g.heroModes)}`;
            console.log(`${k.padEnd(22)} in range ${g.secs} s: hero ${pct(g.hero, g.secs)} (in a trade ${g.heroTrade} s) creep ${pct(g.creep, g.secs)} toward ${pct(g.toward, g.secs)} away ${pct(g.away, g.secs)} idle ${pct(g.idle, g.secs)}; not on the hero, held by: ${modes}; +${WIDE}: ${g.wide} s, hero ${pct(g.wideHero, g.wide)}`);
            const why = Object.entries(s.why ?? {}).map(([w, n]) => `${w} ${n}`).join(', ');
            console.log(`${k.padEnd(22)} ready ${s.ready}  with trade ${s.withTrade}  trades ${s.trades} (late ${s.late}, lost ${s.lost})  ordered ${s.ordered ?? 0}  fired ${s.fired ?? 0}  first ${s.first ?? '-'} s  a5 ${s.a5 ?? '-'}  hp ${s.hpd ?? '-'}/${s.thpd ?? '-'} (5 s ${s.hp5 ?? '-'}/${s.thp5 ?? '-'})  ch5 ${s.ch5 ?? '-'}  lost to creeps/hero/rest incl. regen/resets ${s.split ? `${s.split.creeps}/${s.split.hero}/${s.split.other}` : '-'}  5 s by flags c/h/b/o ${s.split5 ? `${s.split5.creeps}/${s.split5.hero}/${s.split5.both}/${s.split5.other}` : '-'}  creeps end ${s.creepsEnd ?? '-'}%  step first ${s.stepFirst ?? '-'}  untaken lh/dn ${s.ulh ?? '-'}/${s.udn ?? '-'}  ends: ${why}`);
        }
    }
}

module.exports = { reps, summary, rangeSeconds, WINDOW };
