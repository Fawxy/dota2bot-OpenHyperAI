#!/usr/bin/env node
'use strict';
// Trade replay diff (design 2026-11-19-trade-decision-design.md s7): the OLD decision's cut lines (ev=cut kind=trade with no `lv`, core_trade.ts's
// fresh decision, and kind=keep, its kill and join kept or ended each frame) mapped into the new decision's Inputs, the new Decide run
// on them (the built states/trade.lua, in the fixture harness), and a table of where its answer differs from what the game decided,
// by old answer, new answer and the new deciding gate. A diff to attribute a batch by, not a bar.
//   node trade_diff.js --batch h2hsnapcreeps1,h2hsnapcreeps1m,h2hnolost1,h2hnolost1m [--rows 2] [--json]
//   node trade_diff.js <log> [<log> ...] [--game N] [--rows 2] [--json]
// --batch: every banked game of those batches (bank.js). --game: which game of a log (default the last: a remote job's game 1 is a stub).
// --rows N: N example moments (pid, t, file) under each differing group. --json: the groups and the counts as JSON.
//
// What a replay cannot know, and what stands in for it:
//  - n: the old line has `en` (enemy heroes within 1,200), not the heroes that reach us in 2 s. `en` stands in; a row whose answer
//    changes between n 1 and n 2 is marked `~n`.
//  - the walk read (a kill's and a join's): absent, so the read here stands in; the unseen weight is 0. The pair's answer is read from `jn`.
//  - the catch read of a FRESH kill: the trade line does not carry it. A row whose answer differs between catch ok and catch failed is
//    "not replayable (catch)" and left out of the table. A running kill's catch is recomputed from the keep line's hunters (`chu`).
//  - `paid` (a hitter standing in our creeps' aggro): false, so a hit back that only the creeps' aggro favoured reads as unfavoured.
//  - a join keep line carries no read here: HP 1, burst 0, no creeps, no tower stand in.
const fs = require('fs');
const path = require('path');
const { newState, doString, getGlobal } = require('../../tests/humaniser/harness');
const { readGames, toLua } = require('./cut');
const bank = require('./bank');

const COMMIT_HP = 0.4;
const CATCH_WINDOW = 30;
const OUTRANGE = 100;
const CHUNK = 400;
/** Old lines carry no movement speed: a typical hero's (the new decision reads `ms`, and `lw` 0 on a trade line means it could not reach). */
const DEFAULT_MS = 300;

/** The new Free (states/trade.ts): the target swings at a creep, or our range is OUTRANGE over its. */
const free = (tlh, ar, tar) => tlh || (ar !== undefined && tar !== undefined && ar >= tar + OUTRANGE);

/** The keep line's hunters (`chu`: `d,reach,close,dps,spells` joined by `;`, spells `range:cp:dmg` joined by `/`). */
function parseHunters(s) {
    return String(s).split(';').filter(Boolean).map((r) => {
        const [d, reach, close, dps, sp] = r.split(',');
        const spells = String(sp || '').split('/').filter(Boolean).map((x) => { const [range, cp, dmg] = x.split(':').map(Number); return { range, cp, dmg }; });
        return { d: +d, reach: +reach, close: +close, dps: +dps, spells };
    });
}

/** states/trade.ts CatchRead over parsed hunters. */
function catchRead(hunters, thpAbs, w = CATCH_WINDOW) {
    let dmg = 0;
    const arrive = (d, r, close) => (d <= r ? 0 : close > 0 ? (d - r) / close : Infinity);
    for (const h of hunters) {
        const ta = arrive(h.d, h.reach, h.close);
        if (ta < w) dmg += h.dps * (w - ta);
        for (const s of h.spells) {
            const ts = arrive(h.d, s.range, h.close) + s.cp;
            if (ts <= w) dmg += s.dmg;
        }
    }
    return { ok: dmg >= thpAbs, dmg, first: 0, safe: w };
}

const num = (cut, k) => (cut[k] === undefined ? undefined : Number(cut[k]));
const nonDefault = (v, d) => (v === undefined || Number.isNaN(v) ? d : v);

/** What the old decision's trade line answered: `xa` for a hitter (the exchange), else `dec`. */
const oldTradeAnswer = (cut) => (Number(cut.hb) === 1 && cut.xa !== undefined ? cut.xa : cut.dec);

/**
 * One old fresh-decision line as a replay row, or { skip } with why. `variants` are the Inputs to run: [0] is the replay (n from `en`,
 * the catch absent); `catchOk`/`catchFail` the same with the catch read both ways when the target is a kill candidate; `n1`, `n2` the
 * replay with n fixed.
 */
function fromTrade(cut) {
    if (cut.bu === undefined) return { skip: 'no burst read (the old decision ran without Ours.TradeSafe)' };
    const n = (k) => Number(cut[k]);
    const base = (nn, c) => ({
        now: n('t'), hp: n('hp'), burst: n('bu'), n: nn, missing: 0, ms: num(cut, 'lw') === 0 ? 0 : DEFAULT_MS, towerOnMe: n('tm') === 1, creepsOnMe: n('hc'), wave: n('cr'),
        denyDue: num(cut, 'dn') === 1,
        cands: [{
            pid: n('tgt'), thp: n('thp'), thpAbs: n('thp') * 600, d: n('d'), gap: n('d') - nonDefault(num(cut, 'ar'), 0) - nonDefault(num(cut, 'hl'), 0),
            away: nonDefault(num(cut, 'aw'), 0), hitting: num(cut, 'hb') === 1,
            free: free(num(cut, 'tlh') === 1, num(cut, 'ar'), num(cut, 'tar')), ko: nonDefault(num(cut, 'ko'), 0), kt: nonDefault(num(cut, 'kt'), 0),
            paid: false, tw: false, ...(c ? { catch: c } : {}),
        }],
    });
    const en = n('en');
    const killable = n('thp') <= COMMIT_HP;
    const ok = { ok: true, dmg: 1e9, first: 0, safe: CATCH_WINDOW }, bad = { ok: false, dmg: 0, first: 0, safe: CATCH_WINDOW };
    const v = { replay: base(en), n1: base(1), n2: base(2) };
    if (killable) { v.replay = base(en, ok); v.catchOk = base(en, ok); v.catchFail = base(en, bad); v.n1 = base(1, ok); v.n2 = base(2, ok); }
    return { src: 'trade', old: oldTradeAnswer(cut), killable, variants: v };
}

/** One old keep line (a kill or join kept or ended) as a replay row. */
function fromKeep(cut) {
    const n = (k) => Number(cut[k]);
    const kind = cut.ek;
    const seen = n('sn') === 1;
    const hasHere = cut.hp !== undefined;
    const tgt = n('tgt');
    const thp = hasHere ? n('thp') : 0.5;
    const d = nonDefault(num(cut, 'd'), 0);
    const gap = d - nonDefault(num(cut, 'ar'), 0) - nonDefault(num(cut, 'hl'), 0);
    const hunters = cut.chu !== undefined && cut.cth !== undefined ? parseHunters(cut.chu) : undefined;
    const cs = hunters !== undefined ? catchRead(hunters, n('cth'), nonDefault(num(cut, 'csf'), CATCH_WINDOW)) : { ok: true, dmg: 0, first: 0, safe: CATCH_WINDOW };
    const run = {
        level: kind, target: tgt, source: kind === 'join' ? 'pair' : undefined, alive: n('alv') === 1, offered: n('oa'), started: num(cut, 'sa'),
        landed: false, soFar: 0, catchFails: 0,
    };
    if (!seen) {
        run.chaseAt = { x: nonDefault(num(cut, 'lx'), 0), y: nonDefault(num(cut, 'ly'), 0) };
        run.unseen = { at: num(cut, 'uat') === 1, tower: num(cut, 'utw') === 1, threat: num(cut, 'uth') === 1 };
        if (kind === 'kill' && hunters !== undefined) run.catch = cs;
    }
    const base = (nn) => ({
        now: n('t'), hp: hasHere ? n('hp') : 1, burst: hasHere && cut.bu !== undefined ? n('bu') : 0, n: nn, missing: 0, ms: DEFAULT_MS, towerOnMe: num(cut, 'tm') === 1,
        creepsOnMe: nonDefault(num(cut, 'hc'), 0), wave: nonDefault(num(cut, 'cr'), 0), denyDue: false,
        pair: cut.jn === 'same' ? { tgt, ko: 1, kt: 0, dec: 'join' } : cut.jn === 'other' ? { tgt: -1, ko: 1, kt: 0, dec: 'join' } : undefined,
        cands: seen ? [{
            pid: tgt, thp, thpAbs: hunters !== undefined ? n('cth') : thp * 600, d, gap, away: 0, hitting: num(cut, 'hb') === 1,
            free: false, ko: cut.jn === 'same' ? 1 : 0.3, kt: cut.jn === 'same' ? 0 : 0.2, paid: false, tw: false, catch: kind === 'kill' ? cs : undefined,
        }] : [],
        run,
    });
    const en = nonDefault(num(cut, 'en'), 1);
    return { src: 'keep', old: cut.dec, killable: false, variants: { replay: base(en), n1: base(1), n2: base(2) }, started: run.started !== undefined };
}

// The classes the old and the new answer are compared in, and the labels the table prints.
const oldTradeClass = (a) => (a === 'trade' ? 'trade' : a === 'kill' ? 'kill' : 'none');
const newClass = (a) => (a.level === 'hit' || a.level === 'hitback' ? 'trade' : a.level);
const newLabel = (a) => (a.level === 'none' ? `none:${a.reason}` : a.level === 'join' || a.source !== undefined ? `${a.level}(${a.source ?? '-'})` : a.level);
const oldKeepClass = (a) => (a === 'keep' || a === 'kill_up' ? 'keep' : 'end');
// A running join the pair no longer answers for that carries on as the kill on the same target is the old `kill_up`: kept.
const newKeepClass = (a, run) => (a.level !== 'none' && a.target === run.target && (a.ended === undefined || (run.level === 'join' && a.level === 'kill')) ? 'keep' : 'end');
const newKeepLabel = (a, run) => {
    if (newKeepClass(a, run) === 'keep') return a.reason === 'kill_up' || a.level !== run.level ? `keep (${a.level})` : 'keep';
    return `end:${a.ended ?? a.reason}${a.level !== 'none' ? ` (then ${a.level}${a.target !== run.target ? ` on another` : ''})` : ''}`;
};

/** Parses one line of the Lua batch output: `level|target|source|reason|ended`. */
function parseAnswer(line) {
    const [level, target, source, reason, ended] = line.split('|');
    return { level, target: target === '' ? undefined : Number(target), source: source || undefined, reason, ended: ended || undefined };
}

/** Runs the new Decide over every Inputs in `inputs` (one fengari state, chunks of CHUNK); the answers in the same order. */
function decideAll(inputs, root) {
    const L = newState(root);
    const err = doString(L, 'dofile(HARNESS_DIR .. "/dota_stubs.lua")\nFreshHumaniser({ Enable = true })\nTRADE = require("bots/FunLib/humaniser/states/trade")');
    if (err !== null) throw new Error(err);
    const out = [];
    for (let at = 0; at < inputs.length; at += CHUNK) {
        const rows = inputs.slice(at, at + CHUNK).map(toLua).join(',\n');
        const e = doString(L, `local out = {}
for k, i in ipairs({${rows}}) do
    local a = TRADE.Decide(i)
    out[k] = table.concat({ a.level, tostring(a.target or ""), tostring(a.source or ""), a.reason, tostring(a.ended or "") }, "|")
end
OUT = table.concat(out, "\\n")`);
        if (e !== null) throw new Error(e);
        out.push(...String(getGlobal(L, 'OUT')).split('\n'));
    }
    return out.map(parseAnswer);
}

/**
 * Rows in, report out: { groups, counts }. A group is one (source, old answer, new answer, deciding gate) where the classes differ;
 * `approx` counts its rows whose answer moves with n.
 */
function diffRows(rows, root) {
    const flat = [], at = [];
    rows.forEach((r, i) => { for (const [k, v] of Object.entries(r.variants)) { at.push([i, k]); flat.push(v); } });
    const got = decideAll(flat, root);
    got.forEach((a, j) => { const [i, k] = at[j]; (rows[i].answers = rows[i].answers || {})[k] = a; });
    const counts = { trade: { same: 0, differ: 0, notReplayable: 0, skipped: 0 }, keep: { same: 0, differ: 0, notReplayable: 0, skipped: 0 } };
    const groups = new Map();
    for (const r of rows) {
        const c = counts[r.src];
        if (r.skip) { c.skipped++; continue; }
        const a = r.answers.replay;
        let oldC, newC, oldL, newL;
        if (r.src === 'trade') {
            if (r.killable && newClass(r.answers.catchOk) !== newClass(r.answers.catchFail)) { c.notReplayable++; continue; }
            oldC = oldTradeClass(r.old); newC = newClass(a); oldL = r.old === 'trade' || r.old === 'kill' ? r.old : `none:${r.old}`; newL = newLabel(a);
        } else {
            const run = r.variants.replay.run;
            oldC = oldKeepClass(r.old); newC = newKeepClass(a, run); oldL = r.old === 'keep' ? 'keep' : `end:${r.old}`; newL = newKeepLabel(a, run);
        }
        if (oldC === newC) { c.same++; continue; }
        c.differ++;
        const key = `${r.src}\t${oldL}\t${newL}`;
        const g = groups.get(key) || { src: r.src, old: oldL, new: newL, n: 0, approx: 0, examples: [] };
        g.n++;
        const moves = newClass(r.answers.n1) !== newClass(r.answers.n2) || (r.answers.n1.level !== r.answers.n2.level);
        if (moves) g.approx++;
        g.examples.push({ pid: r.pid, t: r.t, file: r.file });
        groups.set(key, g);
    }
    return { groups: [...groups.values()].sort((x, y) => y.n - x.n), counts };
}

/** Replay rows from one log's last (or chosen) game: every kind=trade and kind=keep cut, in order. */
function rowsOfLog(log, gameNo) {
    const games = readGames(fs.readFileSync(log, 'utf8'));
    const g = gameNo !== undefined ? games[gameNo - 1] : games[games.length - 1];
    const rows = [];
    for (const cut of g ? g.cuts : []) {
        let r;
        // cut.js's readGames names the retired decision's trade line `trade_old` (it has no `lv`; today's `trade` and the earlier
        // `trade2` lines have it), so old and new lines are told apart there, by that field.
        if (cut.kind === 'trade_old') r = fromTrade(cut);
        else if (cut.kind === 'keep') r = fromKeep(cut);
        else continue;
        rows.push({ ...r, pid: cut.pid, t: Number(cut.t), file: path.basename(log) });
    }
    return rows;
}

function logsOf(argv) {
    const i = argv.indexOf('--batch');
    if (i < 0) return argv.filter((a, j) => !a.startsWith('--') && !['--game', '--rows'].includes(argv[j - 1]));
    const names = new Set(argv[i + 1].split(','));
    return bank.load().filter((e) => names.has(e.batch)).map((e) => e.log).filter((l) => fs.existsSync(l));
}

function main(argv) {
    const opt = (k) => { const i = argv.indexOf(k); return i >= 0 ? argv[i + 1] : undefined; };
    if (argv.includes('--help') || argv.length === 0) { console.log(fs.readFileSync(__filename, 'utf8').split('\n').slice(2, 11).map((l) => l.replace(/^\/\/ ?/, '')).join('\n')); return; }
    const logs = logsOf(argv);
    if (!logs.length) { console.error('no logs'); process.exit(1); }
    const gameNo = opt('--game') !== undefined ? Number(opt('--game')) : undefined;
    const rows = logs.flatMap((l) => rowsOfLog(l, gameNo));
    const { groups, counts } = diffRows(rows);
    const show = Number(opt('--rows') ?? 0);
    if (argv.includes('--json')) { console.log(JSON.stringify({ games: logs.length, counts, groups }, null, 1)); return; }
    console.log(`trade_diff: ${logs.length} games, ${counts.trade.same + counts.trade.differ + counts.trade.notReplayable + counts.trade.skipped} trade cuts, ${counts.keep.same + counts.keep.differ + counts.keep.notReplayable + counts.keep.skipped} keep cuts`);
    for (const k of ['trade', 'keep']) {
        const c = counts[k];
        console.log(`  ${k}: replayed ${c.same + c.differ} (same class ${c.same}, differs ${c.differ}); not replayable (catch) ${c.notReplayable}; skipped ${c.skipped}`);
    }
    console.log('  n is approximate (the old line\'s `en`); `~n` counts the rows whose answer moves between n 1 and n 2. A fresh kill\'s catch read is not on the old line.');
    console.log('  src    count  ~n  old answer -> new answer (deciding gate)');
    for (const g of groups) {
        console.log(`  ${g.src.padEnd(6)} ${String(g.n).padStart(5)} ${String(g.approx).padStart(3)}  ${g.old} -> ${g.new}`);
        for (const e of g.examples.slice(0, show)) console.log(`           pid ${e.pid} t=${e.t} ${e.file}`);
    }
}

if (require.main === module) main(process.argv.slice(2));
module.exports = { fromTrade, fromKeep, diffRows, rowsOfLog, decideAll, catchRead, parseHunters };
