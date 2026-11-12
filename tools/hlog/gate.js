// The merge gate's three measures from the logs (master SCOREBOARD.md "The merge gate"): per game, ours minus OHA in team
// deaths to --until (queries/ledger_deaths.sql, pos 1-5), team net worth at --at (`nw`) and team experience at --at (`lvl`
// and `xpn` with the level table below). Ours is the label's seat, as ledger.js.
// Usage:
//   node gate.js <run> [<run> ...] [--ref <run> ...] [--tol deaths=D,nw=N,xp=X]   a row's per-game means; with --ref, the
//       difference from the reference row and, with --tol, pass or fail (a row fails when worse than the reference by more
//       than a tolerance on any measure: more deaths, less net worth, less experience)
//   node gate.js --noise <run> [<run> ...] [--rate 0.1] [--games 10]   OHA against OHA: the side effect, the within-cell
//       spread, and the tolerances at which a row of --games games that changes nothing fails --rate of the time against a
//       reference row of the same size, the three measures together (their correlation simulated, one-sided each)
//   Options: --at 600, --until 720, --json, --no-ingest.
// A cell is a lineup and seat (A_rad, A_dire, ...); the label's lineup is the letter after the run name.
'use strict';
const fs = require('fs');
const path = require('path');
const { Store, DB, LOGS, JOBS } = require('./store');
const { games } = require('./ledger');

// Experience to go from level L to L+1, 7.41 (index L-1). The batch's largest `xpn` per level checks it: one over the span
// means the table is wrong for the build's patch.
const SPAN = [240, 400, 520, 600, 680, 760, 800, 900, 1000, 1100, 1200, 1300, 1400, 1500, 1600, 1700, 1800, 1900, 2000, 2200, 2400, 2600, 2800, 3000, 4000, 5000, 6000, 7000, 7500];
const MEASURES = ['deaths', 'nw', 'xp'];
// The direction in which each measure is worse for ours: deaths up, net worth and experience down.
const WORSE = { deaths: 1, nw: -1, xp: -1 };

function xpOf(lvl, xpn) {
    if (!(lvl >= 1) || lvl > SPAN.length) return undefined;
    let total = 0;
    for (let l = 1; l < lvl; l++) total += SPAN[l - 1];
    if (lvl === SPAN.length + 1 || xpn < 0) return total;
    if (xpn > SPAN[lvl - 1]) throw new Error(`xpn ${xpn} at level ${lvl} is over its span ${SPAN[lvl - 1]}: the level table is not this patch's`);
    return total + SPAN[lvl - 1] - xpn;
}

/** One game's team totals by side: { ours: {deaths, nw, xp}, oha: {...} }. */
function measures(store, g, { at, until }) {
    const side = (team) => (team === g.seat ? 'ours' : 'oha');
    const out = { ours: { deaths: 0, nw: 0, xp: 0 }, oha: { deaths: 0, nw: 0, xp: 0 } };
    const dSql = fs.readFileSync(path.join(__dirname, 'queries', 'ledger_deaths.sql'), 'utf8');
    for (const d of store.query(dSql, { like: g.file, until, pos_lo: 1, pos_hi: 5 })) out[side(d.team)].deaths++;
    const rows = store.query(`SELECT l.team, l.pid, s.nw, s.lvl, s.xpn FROM lineup l
        JOIN ev_snap s ON s.game_id = l.game_id AND s.pid = l.pid
            AND s.seq = (SELECT s2.seq FROM ev_snap s2 WHERE s2.game_id = l.game_id AND s2.pid = l.pid AND s2.t <= :at
                AND s2.nw IS NOT NULL ORDER BY s2.t DESC, s2.seq DESC LIMIT 1)
        WHERE l.game_id = :g`, { g: g.game_id, at });
    for (const r of rows) {
        const o = out[side(r.team)];
        o.nw += r.nw;
        const xp = r.xpn === null || r.xpn === undefined ? undefined : xpOf(r.lvl, r.xpn);
        o.xp = xp === undefined || o.xp === undefined ? undefined : o.xp + xp;
    }
    return out;
}

function cellOf(label) {
    const m = label.match(/_([A-Z])_(rad|dire)_\d+$/);
    return m ? `${m[1]}_${m[2]}` : label;
}

/** Per game: { label, cell, d: {deaths, nw, xp} (ours minus OHA), ours, oha }. */
function rowOf(store, runs, o) {
    return games(store, runs).map((g) => {
        const m = measures(store, g, o);
        const d = Object.fromEntries(MEASURES.map((k) => [k, m.ours[k] === undefined || m.oha[k] === undefined ? undefined : m.ours[k] - m.oha[k]]));
        return { label: g.label, cell: cellOf(g.label), d, ours: m.ours, oha: m.oha };
    });
}

const mean = (a) => a.reduce((x, y) => x + y, 0) / a.length;

/**
 * OHA against OHA. Per measure: the seat effect (Radiant minus Dire: a game's d is it with the sign of the ours seat) and the
 * pooled within-cell variance of d, cells being lineup and seat. Null tolerances by simulation: two independent rows of
 * `n` games, each game's d drawn from a normal with the pooled covariance; a row fails when its mean is worse than the
 * reference's by more than k standard errors of the difference on any measure; k is found so that `rate` of rows fail.
 */
function noise(rows, { rate = 0.1, n = 10, sims = 200000, seed = 1 } = {}) {
    const ok = rows.filter((r) => MEASURES.every((k) => r.d[k] !== undefined));
    const cells = {};
    for (const r of ok) (cells[r.cell] = cells[r.cell] || []).push(r);
    const seat = {};
    for (const k of MEASURES) seat[k] = mean(ok.map((r) => (/_rad$/.test(r.cell) ? r.d[k] : -r.d[k])));
    const cov = MEASURES.map(() => MEASURES.map(() => 0));
    let df = 0;
    for (const list of Object.values(cells)) {
        if (list.length < 2) continue;
        const mu = MEASURES.map((k) => mean(list.map((r) => r.d[k])));
        for (const r of list) MEASURES.forEach((a, i) => MEASURES.forEach((b, j) => { cov[i][j] += (r.d[a] - mu[i]) * (r.d[b] - mu[j]); }));
        df += list.length - 1;
    }
    if (df < 2) throw new Error(`only ${df} degrees of freedom: too few repeated cells`);
    for (const row of cov) for (let j = 0; j < row.length; j++) row[j] /= df;
    const sd = MEASURES.map((_, i) => Math.sqrt(cov[i][i]));
    const corr = cov.map((row, i) => row.map((v, j) => v / (sd[i] * sd[j])));
    // The difference of two row means, standardised per measure, is normal with this correlation; the row fails when any
    // measure's standardised difference exceeds k in its worse direction (so deaths up with net worth down fail together).
    const L = cholesky(corr);
    let s = seed >>> 0;
    const rand = () => { s = (s + 0x6D2B79F5) >>> 0; let t = s; t = Math.imul(t ^ (t >>> 15), t | 1); t ^= t + Math.imul(t ^ (t >>> 7), t | 61); return ((t ^ (t >>> 14)) >>> 0) / 4294967296; };
    const gauss = () => Math.sqrt(-2 * Math.log(1 - rand())) * Math.cos(2 * Math.PI * rand());
    const worst = [];
    for (let i = 0; i < sims; i++) {
        const z = MEASURES.map(() => gauss());
        const x = L.map((row) => row.reduce((a, v, j) => a + v * z[j], 0));
        worst.push(Math.max(...x.map((v, j) => v * WORSE[MEASURES[j]])));
    }
    worst.sort((a, b) => a - b);
    const k = worst[Math.floor((1 - rate) * sims)];
    const seDiff = sd.map((v) => v * Math.sqrt(2 / n));
    const tol = Object.fromEntries(MEASURES.map((m, i) => [m, k * seDiff[i]]));
    return { games: ok.length, df, seat, sd: Object.fromEntries(MEASURES.map((m, i) => [m, sd[i]])), corr, k, n, rate, tol };
}

function cholesky(a) {
    const n = a.length;
    const L = a.map(() => Array(n).fill(0));
    for (let i = 0; i < n; i++) {
        for (let j = 0; j <= i; j++) {
            let sum = a[i][j];
            for (let k = 0; k < j; k++) sum -= L[i][k] * L[j][k];
            L[i][j] = i === j ? Math.sqrt(Math.max(sum, 1e-12)) : sum / L[j][j];
        }
    }
    return L;
}

/** A row's per-game means of d, and against a reference row its difference and verdict per measure. */
function judge(row, ref, tol) {
    const m = (rows, k) => mean(rows.map((r) => r.d[k]).filter((v) => v !== undefined));
    const out = {};
    for (const k of MEASURES) {
        const e = { row: m(row, k) };
        if (ref) {
            e.ref = m(ref, k);
            e.diff = e.row - e.ref;
            if (tol && tol[k] !== undefined) e.fails = WORSE[k] * e.diff > tol[k];
        }
        out[k] = e;
    }
    return out;
}

function args(argv) {
    const o = { runs: [], ref: [], at: 600, until: 720 };
    let into = o.runs;
    for (let i = 0; i < argv.length; i++) {
        const a = argv[i];
        if (a === '--ref') into = o.ref;
        else if (a === '--noise') o.noise = true;
        else if (a === '--tol') o.tol = Object.fromEntries(argv[++i].split(',').map((p) => p.split('=')).map(([k, v]) => [k, Number(v)]));
        else if (a === '--rate') o.rate = Number(argv[++i]);
        else if (a === '--games') o.n = Number(argv[++i]);
        else if (a === '--at') o.at = Number(argv[++i]);
        else if (a === '--until') o.until = Number(argv[++i]);
        else if (a === '--json') o.json = true;
        else if (a === '--no-ingest') o.noIngest = true;
        else if (a === '--help' || a === '-h') o.help = true;
        else into.push(a);
    }
    return o;
}

if (require.main === module) {
    const o = args(process.argv.slice(2));
    if (o.help || !o.runs.length) {
        console.log(fs.readFileSync(__filename, 'utf8').split('\n').filter((l) => l.startsWith('//')).map((l) => l.slice(3)).join('\n'));
        process.exit(o.help ? 0 : 2);
    }
    const store = new Store(DB);
    if (!o.noIngest) for (const f of store.ingestAll([LOGS, JOBS].filter((d) => fs.existsSync(d))).failed) console.error(`not ingested: ${f.file}: ${f.error}`);
    const row = rowOf(store, o.runs, o);
    const r0 = (v) => (v === undefined ? '?' : Math.round(v));
    if (o.noise) {
        const z = noise(row, { rate: o.rate, n: o.n });
        if (o.json) console.log(JSON.stringify({ games: row, noise: z }));
        else {
            console.log(`${z.games} games, ${z.df} degrees of freedom; rows of ${z.n} games, ${z.rate * 100}% of null rows fail; k = ${z.k.toFixed(2)}`);
            for (const k of MEASURES) console.log(`${k.padEnd(7)} seat (Radiant minus Dire) ${r0(z.seat[k])}  within-cell sd ${r0(z.sd[k])}  tolerance per game ${r0(z.tol[k])}`);
            console.log(`correlation deaths-nw ${z.corr[0][1].toFixed(2)}, deaths-xp ${z.corr[0][2].toFixed(2)}, nw-xp ${z.corr[1][2].toFixed(2)}`);
        }
    } else {
        const ref = o.ref.length ? rowOf(store, o.ref, o) : undefined;
        const j = judge(row, ref, o.tol);
        if (o.json) console.log(JSON.stringify({ games: row, judge: j }));
        else {
            for (const r of row) console.log(`${r.label.padEnd(24)} ${MEASURES.map((k) => `${k} ${r0(r.d[k])}`).join('  ')}`);
            for (const k of MEASURES) {
                const e = j[k];
                console.log(`${k.padEnd(7)} row ${r0(e.row)}` + (ref ? `  ref ${r0(e.ref)}  diff ${r0(e.diff)}` : '') + (e.fails === undefined ? '' : e.fails ? '  FAILS' : '  passes'));
            }
        }
    }
}

module.exports = { xpOf, measures, rowOf, noise, judge, SPAN };
