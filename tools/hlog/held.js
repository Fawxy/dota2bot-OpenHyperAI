// How much of the first ten minutes our side's heroes were held by our code, and what happened under each driver (master
// ARCHITECTURE.md, Measures). Our code holds a hero from its `ev=arb ph=own` until `ev=arb ph=end why=<clock|tower|lost>`
// (Phase.LaningHeld); outside that OHA's own modes play it. Ours is the label's seat (_rad_ / _dire_), as ledger.js.
// Usage: node held.js <run> [<run> ...] [--at 600] [--json] [--no-ingest]
//   Held share   hero-seconds under the hold out of hero-seconds from 0:00 to --at (default 10:00), the team and by position.
//                A hero with no ph=own line is never held. Dead time counts as held while the hold has not ended.
//   Hold ends    count of ph=end per why, before --at and after (to the end of the log).
//   By driver    our heroes' deaths and seconds in OHA's retreat mode (ev=snap mode) to --at, split by who was driving at the
//                time: held, or OHA (the hold ended, or the hero was never held). Deaths per hero-minute of that driver.
// The ph=own lines of a remote or restarted log can sit in the log's stub game: arb lines are read across the whole file.
// gate.js prints this beneath its row.
'use strict';
const fs = require('fs');
const path = require('path');
const { Store, DB, LOGS, JOBS } = require('./store');
const { games } = require('./ledger');

const POS = [1, 2, 3, 4, 5];
const DEATHS = fs.readFileSync(path.join(__dirname, 'queries', 'ledger_deaths.sql'), 'utf8');
// A snapshot stands for the time to the next one, at most this long (a gap is a hero not logging, not a mode held).
const SNAP_CAP = 2;

/** { own, end, why } per pid from the file's arb lines; the first own and the first end win. */
function holds(store, file) {
    const out = {};
    const rows = store.query(`SELECT a.pid, a.t, a.ph, a.why FROM ev_arb a JOIN games g ON g.game_id = a.game_id
        WHERE g.file = :file AND a.ph IN ('own', 'end') ORDER BY a.t, a.seq`, { file });
    for (const r of rows) {
        const h = (out[r.pid] = out[r.pid] || {});
        if (r.ph === 'own' && h.own === undefined) h.own = r.t;
        if (r.ph === 'end' && h.end === undefined) { h.end = r.t; h.why = r.why || 'unknown'; }
    }
    return out;
}

/** Seconds of [0, at] the hold covered for one hero. */
function heldSeconds(h, at) {
    if (!h || h.own === undefined) return 0;
    return Math.max(0, Math.min(h.end ?? Infinity, at) - Math.max(h.own, 0));
}

const isHeld = (h, t) => !!h && h.own !== undefined && t >= h.own && t < (h.end ?? Infinity);

function blank() {
    return {
        games: 0, heroSec: 0, heldSec: 0, byPos: Object.fromEntries(POS.map((p) => [p, { heroSec: 0, heldSec: 0 }])),
        ends: {}, deaths: { held: 0, oha: 0 }, retreatSec: { held: 0, oha: 0 },
    };
}

/** One game's contribution added to `acc` (a blank()). `g` is a ledger.js game: { game_id, file, seat }. */
function addGame(store, g, at, acc) {
    const hs = holds(store, g.file);
    const heroes = store.query('SELECT pid, pos FROM lineup WHERE game_id = :g AND team = :team', { g: g.game_id, team: g.seat });
    const byPid = Object.fromEntries(heroes.map((h) => [h.pid, h]));
    acc.games++;
    for (const h of heroes) {
        const held = heldSeconds(hs[h.pid], at);
        acc.heroSec += at;
        acc.heldSec += held;
        if (acc.byPos[h.pos]) { acc.byPos[h.pos].heroSec += at; acc.byPos[h.pos].heldSec += held; }
    }
    for (const [pid, h] of Object.entries(hs)) {
        if (h.end === undefined || !byPid[pid]) continue;
        const e = (acc.ends[h.why] = acc.ends[h.why] || { before: 0, after: 0 });
        e[h.end < at ? 'before' : 'after']++;
    }
    for (const d of store.query(DEATHS, { like: g.file, until: at, pos_lo: 1, pos_hi: 5 })) {
        if (d.team !== g.seat) continue;
        acc.deaths[isHeld(hs[d.pid], d.t) ? 'held' : 'oha']++;
    }
    for (const h of heroes) {
        const snaps = store.query(`SELECT t, mode FROM ev_snap WHERE game_id = :g AND pid = :pid AND t >= 0 AND t <= :at ORDER BY t, seq`,
            { g: g.game_id, pid: h.pid, at });
        snaps.forEach((s, i) => {
            if (s.mode !== 'retreat') return;
            const dt = Math.min(i + 1 < snaps.length ? snaps[i + 1].t - s.t : SNAP_CAP, SNAP_CAP);
            acc.retreatSec[isHeld(hs[h.pid], s.t) ? 'held' : 'oha'] += dt;
        });
    }
}

/** The measure over the games of the runs: totals (see blank) plus `perGame` held shares. */
function heldShare(store, runs, { at = 600 } = {}) {
    const acc = blank();
    for (const g of games(store, runs)) addGame(store, g, at, acc);
    return acc;
}

const pct = (a, b) => (b ? `${(100 * a / b).toFixed(1)}%` : '?');

function format(acc, at) {
    const mm = `${Math.floor(at / 60)}:${String(at % 60).padStart(2, '0')}`;
    const lines = [`held share, ours, 0:00 to ${mm} (hero-seconds under the hold; dead time counts as held until the hold ends; no ph=own = never held)`];
    lines.push(`  team   ${pct(acc.heldSec, acc.heroSec)}  (${Math.round(acc.heroSec - acc.heldSec)} of ${acc.heroSec} hero-seconds not held, ${acc.games} games)`);
    for (const p of POS) {
        const b = acc.byPos[p];
        lines.push(`  pos ${p}  ${pct(b.heldSec, b.heroSec)}  (${Math.round(b.heroSec - b.heldSec)} of ${b.heroSec} not held)`);
    }
    const whys = Object.keys(acc.ends).sort();
    const total = whys.reduce((n, w) => n + acc.ends[w].before + acc.ends[w].after, 0);
    lines.push(`hold ends by reason, before / after ${mm}: ${total} in all`);
    for (const w of whys) lines.push(`  ${w.padEnd(7)} ${acc.ends[w].before} / ${acc.ends[w].after}`);
    const heldMin = acc.heldSec / 60, ohaMin = (acc.heroSec - acc.heldSec) / 60;
    const rate = (n, m) => (m ? (n / m).toFixed(3) : '?');
    lines.push(`outcomes by who was driving, to ${mm}, our heroes (OHA driving = hold ended or never held)`);
    lines.push(`  held         ${acc.deaths.held} deaths in ${heldMin.toFixed(0)} hero-min = ${rate(acc.deaths.held, heldMin)}/hero-min;  retreat mode ${acc.retreatSec.held.toFixed(0)} s (${pct(acc.retreatSec.held, acc.heldSec)} of held time)`);
    lines.push(`  OHA driving  ${acc.deaths.oha} deaths in ${ohaMin.toFixed(0)} hero-min = ${rate(acc.deaths.oha, ohaMin)}/hero-min;  retreat mode ${acc.retreatSec.oha.toFixed(0)} s (${pct(acc.retreatSec.oha, acc.heroSec - acc.heldSec)} of that time)`);
    return lines.join('\n');
}

function args(argv) {
    const o = { runs: [], at: 600 };
    for (let i = 0; i < argv.length; i++) {
        const a = argv[i];
        if (a === '--at') o.at = Number(argv[++i]);
        else if (a === '--json') o.json = true;
        else if (a === '--no-ingest') o.noIngest = true;
        else if (a === '--help' || a === '-h') o.help = true;
        else o.runs.push(a);
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
    const acc = heldShare(store, o.runs, o);
    console.log(o.json ? JSON.stringify(acc) : format(acc, o.at));
}

module.exports = { heldShare, holds, heldSeconds, format };
