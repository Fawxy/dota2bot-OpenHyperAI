#!/usr/bin/env node
'use strict';
// The sustain rig's reps (drill `sustain`, humaniser/drill.ts SUSTAIN_TASKS; master docs/proposals/2026-11-19-sustain-design.md
// check 3): did each forced answer get carried out? One row per hero and ready rep (`ev=drill ph=ready ok=1`, its `task`), read
// from the release to the rep's end (`rend`):
//   tango, salve, bottle  the item used: an `ev=sustain` attempt of ours with it (`k` use or step_out_use) that did not end
//                         missed, cut, released or dead; or OHA's (switch off): an `ev=regen_obs state=start` of it not `by=ours`
//                         (a bottle is not observed on OHA's side: `n/a`)
//   home                  the hero reached its fountain (a snapshot within BASE_R) and stood at HOME_HP or more there
//   ship                  a purchase of ours (`k=buy`) and the item it bought then used (`late` 1: its delivery ran past its eta)
//   tango_ship            the tango used and its purchase (`why=tango_ship`) made, not refused
// Per row also: `secs` from release to the act (the first use, the arrival, the delivery), `got` the answers of ours seen
// (k:item:ed, in order), `heal` a retreat heal leave started, `tp` a teleport used, `died` the hero died in the window.
// Usage: node sustain_rig.js <log> [<log> ...] [--rows] [--json]
// Each log's games are all read (a rig run's log holds one). Summary per task: ready reps, done, the share, median secs.
const fs = require('fs');
const { parseLog } = require('./parse');

const NAME = 'sustain';
const FOUNTAIN = { 2: [-6619, -6336], 3: [6624, 6368] };
const BASE_R = 1500;
/** The walk home ends healed at retreat's HealUntil (0.8). */
const HOME_HP = 80;
const BAD_END = new Set(['missed', 'cut', 'released', 'dead']);
const OBS = { item_tango: 'tango', item_flask: 'salve', item_clarity: 'clarity' };
const USE_TASKS = { tango: 'item_tango', salve: 'item_flask', bottle: 'item_bottle', bottle_dry: 'item_bottle' };

const r1 = (x) => (x == null ? null : Math.round(x * 10) / 10);
const median = (xs) => {
    if (!xs.length) return null;
    const s = [...xs].sort((a, b) => a - b);
    return s.length % 2 ? s[(s.length - 1) / 2] : (s[s.length / 2 - 1] + s[s.length / 2]) / 2;
};

/** The rows of one game: one per ready hero-rep of the sustain rig. */
function readGame(game, file) {
    const ev = game.events;
    const team = new Map();
    for (const e of ev) if (e.ev === 'drill' && e.ph === 'role' && e.team !== undefined) team.set(e.pid, e.team);
    const ready = ev.filter((e) => e.ev === 'drill' && e.ph === 'ready' && e.name === NAME);
    const rows = [];
    for (const r of ready) {
        if (Number(r.ok) !== 1) continue;
        const pid = r.pid;
        const a = r.t;
        const b = r.rend !== undefined ? Number(r.rend) : a + 60;
        const inWin = (e) => e.pid === pid && e.t >= a && e.t <= b;
        const sus = ev.filter((e) => e.ev === 'sustain' && inWin(e));
        // A sustain line is logged at the attempt's end; it began `sec` before.
        const began = (e) => e.t - (Number(e.sec) || 0);
        const used = (item) => sus.find((e) => (e.k === 'use' || e.k === 'step_out_use') && e.it === item && !BAD_END.has(e.ed));
        const delivered = sus.find((e) => e.k === 'buy' && e.ed === 'delivered');
        const snaps = ev.filter((e) => e.ev === 'snap' && inWin(e));
        const f = FOUNTAIN[team.get(pid) ?? 2];
        const atHome = snaps.find((s) => s.x !== undefined && Math.hypot(s.x - f[0], s.y - f[1]) <= BASE_R && Number(s.hp) >= HOME_HP);
        const deaths = snaps.map((s) => Number(s.deaths) || 0);
        const row = {
            file,
            rep: r.rep,
            pid,
            task: r.task,
            released: r1(a),
            hp: r.hp,
            mp: r.mp,
            got: sus.map((e) => `${e.k}:${String(e.it || '').replace(/^item_/, '')}:${e.ed}`).join(' '),
            heal: ev.some((e) => e.ev === 'retreat' && e.ph === 'start' && e.why === 'heal' && inWin(e)) ? 1 : 0,
            tp: ev.some((e) => e.ev === 'tp' && inWin(e)) ? 1 : 0,
            died: deaths.length > 1 && Math.max(...deaths) > deaths[0] ? 1 : 0,
            done: 0,
            secs: null,
            by: null,
        };
        const task = r.task;
        if (USE_TASKS[task]) {
            const item = USE_TASKS[task];
            const ours = used(item);
            const oha = OBS[item] ? ev.find((e) => e.ev === 'regen_obs' && e.state === 'start' && e.by !== 'ours' && e.item === OBS[item] && inWin(e)) : undefined;
            if (ours) Object.assign(row, { done: 1, secs: r1(began(ours) - a), by: 'ours' });
            else if (oha) Object.assign(row, { done: 1, secs: r1(oha.t - a), by: 'oha' });
            else if (!OBS[item] && !sus.length) row.done = null;
        } else if (task === 'home') {
            if (atHome) Object.assign(row, { done: 1, secs: r1(atHome.t - a) });
        } else if (task === 'ship') {
            // The first purchase of ours and a use of what it bought after it began: shipped and used, whatever its delivery line
            // says (fix2: a delivery ended `late`, the wait adopted the stash, and the tango came and was eaten). `late` marks it.
            const buy = sus.find((e) => e.k === 'buy' && e.it !== 'stash');
            const after = buy ? sus.find((e) => (e.k === 'use' || e.k === 'step_out_use') && e.it === buy.it && began(e) >= began(buy) && !BAD_END.has(e.ed)) : undefined;
            row.late = buy && buy.ed === 'late' ? 1 : 0;
            if (buy && after) Object.assign(row, { done: 1, secs: r1(began(after) - a), by: 'ours' });
        } else if (task === 'tango_ship') {
            const t = used('item_tango');
            const buy = sus.find((e) => e.k === 'buy' && e.it !== 'stash' && e.why === 'tango_ship');
            if (t && buy && buy.ed !== 'failed') Object.assign(row, { done: 1, secs: r1(began(t) - a), by: 'ours' });
        }
        rows.push(row);
    }
    const m = ready.length;
    const n = ready.filter((r) => Number(r.ok) === 1).length;
    const fails = {};
    for (const r of ready) if (Number(r.ok) !== 1) fails[r.fail] = (fails[r.fail] || 0) + 1;
    return { rows, ready: { n, m, fails } };
}

/** Per task: ready reps, done (of those graded), the share, median secs. */
function summary(rows) {
    const by = {};
    for (const r of rows) (by[r.task] ??= []).push(r);
    const out = {};
    for (const [t, rs] of Object.entries(by)) {
        const graded = rs.filter((r) => r.done !== null);
        const done = graded.filter((r) => r.done === 1);
        out[t] = { reps: rs.length, graded: graded.length, done: done.length, share: graded.length ? r1((100 * done.length) / graded.length) : null, secs: median(done.map((r) => r.secs)), died: rs.filter((r) => r.died).length };
    }
    return out;
}

function main(argv) {
    const files = argv.filter((a) => !a.startsWith('--'));
    if (!files.length || argv.includes('--help')) {
        console.log(fs.readFileSync(__filename, 'utf8').split('\n').filter((l) => l.startsWith('//')).map((l) => l.slice(3)).join('\n'));
        return files.length ? 0 : 2;
    }
    const rows = [];
    const ready = [];
    for (const f of files) {
        for (const g of parseLog(fs.readFileSync(f, 'utf8'))) {
            const res = readGame(g, require('path').basename(f));
            if (!res.ready.m) continue;
            rows.push(...res.rows);
            ready.push({ file: require('path').basename(f), game: g.index, ...res.ready });
        }
    }
    if (argv.includes('--rows')) {
        console.log(rows.map((r) => JSON.stringify(r)).join('\n'));
        return 0;
    }
    const sum = summary(rows);
    if (argv.includes('--json')) {
        console.log(JSON.stringify({ ready, tasks: sum }));
        return 0;
    }
    for (const r of ready) console.log(`${r.file} game ${r.game}: ready ${r.n} of ${r.m}${Object.keys(r.fails).length ? `  fail ${Object.entries(r.fails).map(([k, v]) => `${k}=${v}`).join(' ')}` : ''}`);
    console.log('task        reps  graded  done  share  secs  died');
    for (const [t, s] of Object.entries(sum)) {
        console.log(`${t.padEnd(11)} ${String(s.reps).padStart(4)}  ${String(s.graded).padStart(6)}  ${String(s.done).padStart(4)}  ${String(s.share ?? '-').padStart(5)}  ${String(s.secs ?? '-').padStart(4)}  ${String(s.died).padStart(4)}`);
    }
    return 0;
}

if (require.main === module) process.exitCode = main(process.argv.slice(2));

module.exports = { readGame, summary };
