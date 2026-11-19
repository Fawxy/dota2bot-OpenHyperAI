#!/usr/bin/env node
'use strict';
// Safe-here death replay (design 2026-11-19-safe-here-design.md s2 and s6.2): banked ev=cut kind=leave lines mapped into
// Safe.Inputs, the built Safe.Decide (bots/FunLib/humaniser/safe.lua) run at stay 1.0, 1.25, 1.5 and 2.0, and three tables
// that choose the `stay` bar. "today" is the game's own answer: `dec` lethal, tower, heal or threat is a leave (deadly).
//   node safe_deaths.js --batch a,b,c [--rows N] [--json]
//   node safe_deaths.js <log> [<log> ...] [--game N] [--rows N] [--json]
// --batch: every banked game of those batches (bank.js). --game: which game of a log (default the last: a remote job's game 1
// is a stub). --rows N: N example moments (file, pid, t) per cell of table 1 where today called and the bar missed, and the reverse.
// Table 1: our deaths with a leave line in the 10 s before: how many had a deadly answer, the median seconds from the first one
//   to the death, by heroes in reach then and the answer's reason. Deaths with no leave line in those 10 s: count only.
// Table 2: seconds a game that are deadly, by reach count and HP band; the share of them followed by that hero's death in 10 s.
// Table 3: hp / kill at the last line before each death with 2+ (and with 1) in reach, and at the last line 3 s or more before it.
//
// Our heroes: those with at least one ev=cut kind=leave line in the game. Deaths: per hero, the ev=snap `deaths` counter rising
//   (it rises at the first snap after the respawn); the death is the last snap with hp above 0 before the hero's hp read 0 or
//   it jumped more than 1,200 in under 3 s (the respawn). Up to a snapshot interval (1 s) early. The rule is core_death's.
//   A window is [death - 10, death + 1].
//
// What a replay cannot know, and what stands in for it:
//  - landing (HP per second lost by source), exit: zeros. The answer's level `costly` is not replayed; only deadly counts.
//  - reach: the Reader's test over the logged heroes (CUT_R 3,000 box): non-illusion heroes within speed x 2 + range + hull + our
//    hull of us. The Reader also counts illusions; the line's walk is the place itself (from = place).
//  - dmg: e6 if the hero hit us in the last 1 s (`eng`), else e3 (2 s windows on a leave line). The Reader's engagedWindow is 6.
//  - tower: our place within a standing enemy tower's attack range + hull (logged once per team, standing per the `ta` mask).
//    The Reader uses WorldFacts.TowerReach (the same). towerOnMe: `dt`, or a tower in `tt` whose target is us (`b`).
//  - missing 0 and away false: the unknown rule never fires (the line has `hu` sightings but no belief weights). held false:
//    a held place is not on the line. hold: `hb` or `pj`.
//  - unseen reachers (Reacher.unseen): none.
//  - Leave lines are written when the retreat read runs, so a hero not in a retreat read has none: gaps are real.
//  - Table 2's weight is the time to the same hero's next leave line capped at 2 s; a hero's last line weighs 0.
const fs = require('fs');
const path = require('path');
const { newState, doString, getGlobal } = require('../../tests/humaniser/harness');
const { readGames, toLua } = require('./cut');
const bank = require('./bank');

const STAYS = [1.0, 1.25, 1.5, 2.0];
const HORIZON = 2;
const WINDOW_BEFORE = 10;
const WINDOW_AFTER = 1;
const WEIGHT_CAP = 2;
const FOLLOW = 10;
const GAME_SPLIT = 30;
const CHUNK = 500;
const LEAVES = new Set(['lethal', 'tower', 'heal', 'threat']);
const BANDS = [['75%+', 0.75], ['50-75%', 0.5], ['<50%', 0]];

const records = (s) => (s === undefined || s === '' ? [] : s.split(';').map((r) => r.split(',')));
const dist = (a, b) => Math.hypot(a.x - b.x, a.y - b.y);

/**
 * One leave line as Safe.Inputs, with `n` the heroes in reach. `towers`: Map team -> the logged cut_towers `tw` string; `team`:
 * our team. Pure over the line.
 */
function mapLeave(cut, towers, team) {
    const [x, y, hp, hpMax, , hull] = String(cut.b).split(',').map(Number);
    const me = { x, y };
    const reach = [];
    for (const [pid, hx, hy, , range, hhull, speed, , eng, e3, e6, ill] of records(cut.he).map((r) => r.map(Number))) {
        if (ill === 1) continue;
        if (dist(me, { x: hx, y: hy }) > speed * HORIZON + range + hhull + hull) continue;
        reach.push({ pid, hitting: eng === 1, dmg: eng === 1 ? e6 : e3 });
    }
    const enemy = team === 2 ? 3 : 2;
    const mask = parseInt(String(cut.ta).split(',')[1], 16);
    let tower = false;
    for (const [i, tx, ty, range, thull] of records(towers.get(enemy)).map((r) => r.map(Number))) {
        if (!(mask & (1 << i))) continue;
        if (dist(me, { x: tx, y: ty }) <= range + thull) tower = true;
    }
    const towerOnMe = Number(cut.dt) === 1 || records(cut.tt).some(([t, , tgt]) => Number(t) === enemy && tgt === 'b');
    return {
        n: reach.length,
        inputs: {
            hp, hpMax, reach, missing: 0, tower, towerOnMe, landing: { hero: 0, creeps: 0, tower: 0 }, away: false, held: false,
            hold: Number(cut.hb) === 1 || Number(cut.pj) === 1,
        },
    };
}

/** Runs Safe.Decide over every row at each bar: rows[i].answers[stay] = { level, reason, kill }. */
function decideAll(rows, root) {
    const L = newState(root);
    const err = doString(L, 'dofile(HARNESS_DIR .. "/dota_stubs.lua")\nFreshHumaniser({ Enable = true })\nSAFE = require("bots/FunLib/humaniser/safe")');
    if (err !== null) throw new Error(err);
    for (let at = 0; at < rows.length; at += CHUNK) {
        const part = rows.slice(at, at + CHUNK);
        const src = part.map((r) => toLua(r.inputs)).join(',\n');
        const e = doString(L, `local out = {}
for k, i in ipairs({${src}}) do
    for _, stay in ipairs({${STAYS.join(',')}}) do
        local a = SAFE.Decide(i, stay)
        out[#out + 1] = table.concat({ a.level, a.reason, string.format("%.3f", a.kill) }, "|")
    end
end
OUT = table.concat(out, "\\n")`);
        if (e !== null) throw new Error(e);
        const got = String(getGlobal(L, 'OUT')).split('\n');
        part.forEach((r, k) => {
            r.answers = {};
            STAYS.forEach((s, j) => { const [level, reason, kill] = got[k * STAYS.length + j].split('|'); r.answers[s] = { level, reason, kill: Number(kill) }; });
        });
    }
}

/** The game's own answer as an answer in the same shape. */
function today(cut) {
    const leave = LEAVES.has(cut.dec);
    return { level: leave ? 'deadly' : 'safe', reason: cut.dec === 'tower' ? 'tower' : cut.dec === 'heal' ? 'other' : leave ? 'kill' : 'stay' };
}

/** Our deaths per pid for each game of a log: [{ pid, t }] by game index (cut.js's split rule). */
function deathsOf(text) {
    const games = [];
    let g, last = -Infinity;
    const snaps = [];
    const flush = () => { if (g !== undefined) games.push(deathsFromSnaps(snaps.splice(0))); };
    for (const line of text.split('\n')) {
        if (line.includes('[DOTACTL] ')) continue;
        const i = line.indexOf('[HEV] ');
        if (i < 0) continue;
        const t = Number((line.slice(i + 6).match(/(?:^| )t=(\S+)/) || [])[1]);
        if (!Number.isFinite(t)) continue;
        if (g === undefined || t < last - GAME_SPLIT) { flush(); g = true; }
        last = t;
        if (!line.includes(' ev=snap ')) continue;
        const f = {};
        for (const m of line.slice(i + 6).matchAll(/(\w+)=("([^"]*)"|\S+)/g)) f[m[1]] = m[2];
        if (f.deaths === undefined) continue;
        snaps.push({ pid: f.pid, t, x: +f.x, y: +f.y, hp: +f.hp, deaths: +f.deaths });
    }
    flush();
    return games;
}

function deathsFromSnaps(snaps) {
    const by = new Map();
    for (const s of snaps) { if (!by.has(s.pid)) by.set(s.pid, []); by.get(s.pid).push(s); }
    const out = [];
    for (const [pid, list] of by) {
        let lastOk, frozen = false, prev;
        for (const s of list) {
            if (prev !== undefined && s.deaths > prev.deaths) {
                if (lastOk !== undefined) out.push({ pid, t: lastOk });
                frozen = false; lastOk = undefined;
            }
            if (prev !== undefined && !frozen && s.t - prev.t < 3 && Math.hypot(s.x - prev.x, s.y - prev.y) > 1200) frozen = true;
            if (s.hp <= 0 && prev !== undefined && prev.hp > 0) frozen = true;
            if (!frozen && s.hp > 0) lastOk = s.t;
            prev = s;
        }
    }
    return out;
}

/** The rows and deaths of one log's game: { rows (leave lines in order), deaths }. */
function gameOfLog(log, gameNo) {
    const text = fs.readFileSync(log, 'utf8');
    const games = readGames(text);
    const gi = gameNo !== undefined ? gameNo - 1 : games.length - 1;
    const g = games[gi];
    if (!g) return { rows: [], deaths: [] };
    const file = path.basename(log);
    const rows = [];
    for (const cut of g.cuts) {
        if (cut.kind !== 'leave') continue;
        const bot = g.bots.get(cut.pid);
        if (!bot || cut.he === undefined || cut.b === undefined) continue;
        const m = mapLeave(cut, new Map([...g.towers].map(([k, v]) => [Number(k), v.tw])), Number(bot.team));
        if (!g.towers.has(String(bot.team === '2' ? 3 : 2))) continue;
        rows.push({ file, pid: cut.pid, t: Number(cut.t), dec: cut.dec, n: m.n, inputs: m.inputs, kill0: m.inputs.reach.reduce((s, r) => s + r.dmg, 0) });
    }
    const ours = new Set(rows.map((r) => r.pid));
    const deaths = (deathsOf(text)[gi] || []).filter((d) => ours.has(d.pid)).map((d) => ({ ...d, file }));
    return { rows, deaths };
}

const median = (a) => { if (!a.length) return undefined; const s = [...a].sort((x, y) => x - y); const h = s.length >> 1; return s.length % 2 ? s[h] : (s[h - 1] + s[h]) / 2; };
const pct = (a, q) => { if (!a.length) return undefined; const s = [...a].sort((x, y) => x - y); return s[Math.min(s.length - 1, Math.floor(q * s.length))]; };
const fmt = (v, d = 1) => (v === undefined ? '-' : Number.isFinite(v) ? v.toFixed(d) : 'inf');
const bandOf = (r) => { const s = r.inputs.hp / r.inputs.hpMax; return BANDS.find(([, lo]) => s >= lo)[0]; };
const reachKey = (n) => (n >= 2 ? '2+' : String(n));
const BARS = ['today', ...STAYS.map(String)];
const answerOf = (r, bar) => (bar === 'today' ? today({ dec: r.dec }) : r.answers[bar]);

/** Everything the tables need, from the games: [{ file, rows, deaths }]. */
function analyse(games) {
    const t1 = {}, t2 = {}, t3 = {};
    const examples = {};
    let nDeaths = 0, noLine = 0;
    const perDeath = [];
    for (const g of games) {
        const byPid = new Map();
        for (const r of g.rows) { if (!byPid.has(r.pid)) byPid.set(r.pid, []); byPid.get(r.pid).push(r); }
        for (const list of byPid.values()) list.forEach((r, i) => { const nx = list[i + 1]; r.w = nx ? Math.min(WEIGHT_CAP, nx.t - r.t) : 0; });
        for (const d of g.deaths) {
            nDeaths++;
            const win = (byPid.get(d.pid) || []).filter((r) => r.t >= d.t - WINDOW_BEFORE && r.t <= d.t + WINDOW_AFTER);
            if (!win.length) { noLine++; continue; }
            perDeath.push({ d, win, all: byPid.get(d.pid) });
        }
        for (const r of g.rows) {
            for (const bar of BARS) {
                const a = answerOf(r, bar);
                if (a.level !== 'deadly' || r.w === 0) continue;
                const k = `${bar}\t${reachKey(r.n)}\t${bandOf(r)}`;
                const c = t2[k] || (t2[k] = { sec: 0, died: 0 });
                c.sec += r.w;
                if (g.deaths.some((d) => d.pid === r.pid && d.t >= r.t && d.t <= r.t + FOLLOW)) c.died += r.w;
            }
        }
    }
    for (const { d, win } of perDeath) {
        for (const bar of BARS) {
            const first = win.find((r) => answerOf(r, bar).level === 'deadly');
            const rec = t1[bar] || (t1[bar] = { n: 0, called: 0, lead: [], byReach: {}, byReason: {} });
            rec.n++;
            if (!first) continue;
            rec.called++;
            rec.lead.push(d.t - first.t);
            const rk = reachKey(first.n), why = answerOf(first, bar).reason;
            for (const [m, k] of [[rec.byReach, rk], [rec.byReason, why]]) { const c = m[k] || (m[k] = { n: 0, lead: [] }); c.n++; c.lead.push(d.t - first.t); }
        }
        const lastRow = win[win.length - 1];
        const before = [...win].reverse().find((r) => r.t <= d.t - 3);
        const key = reachKey(lastRow.n);
        (t3.age = t3.age || []).push(d.t - lastRow.t);
        const c = t3[key] || (t3[key] = { last: [], before: [], nLast: 0 });
        const ratio = (r) => (r.kill0 > 0 ? r.inputs.hp / r.kill0 : Infinity);
        c.nLast++;
        c.last.push(ratio(lastRow));
        if (before) c.before.push(ratio(before));
        const today0 = win.find((r) => answerOf(r, 'today').level === 'deadly');
        for (const bar of STAYS.map(String)) {
            const nw = win.find((r) => answerOf(r, bar).level === 'deadly');
            const rk = reachKey((today0 || nw || lastRow).n);
            if (today0 && !nw) (examples[`today-only\t${bar}\t${rk}`] = examples[`today-only\t${bar}\t${rk}`] || []).push({ file: d.file, pid: d.pid, t: today0.t });
            if (nw && !today0) (examples[`bar-only\t${bar}\t${rk}`] = examples[`bar-only\t${bar}\t${rk}`] || []).push({ file: d.file, pid: d.pid, t: nw.t });
        }
    }
    return { t1, t2, t3, examples, nDeaths, noLine, withLine: perDeath.length };
}

function report(res, nGames, show) {
    const out = [];
    out.push(`safe_deaths: ${nGames} games, ${res.nDeaths} deaths of our heroes (heroes with leave lines); ${res.withLine} with a leave line in the 10 s before, ${res.noLine} with none (the read could not have seen those)`);
    out.push('', 'Table 1: deaths with a leave line in the 10 s before; deadly = today a leave decision, else Safe.Decide at that stay');
    out.push('  bar      n   deadly  median lead s | by reach at first deadly (n, median s) | by reason (n, median s)');
    for (const bar of BARS) {
        const r = res.t1[bar];
        if (!r) continue;
        const cell = (m, ks) => ks.map((k) => `${k}: ${m[k] ? `${m[k].n}, ${fmt(median(m[k].lead))}` : '0'}`).join('  ');
        const reasons = Object.keys(r.byReason).sort();
        out.push(`  ${bar.padEnd(6)} ${String(r.n).padStart(4)} ${String(r.called).padStart(6)}  ${fmt(median(r.lead)).padStart(6)}        | ${cell(r.byReach, ['0', '1', '2+'])} | ${cell(r.byReason, reasons)}`);
    }
    out.push('', 'Table 2: deadly seconds a game (weight: time to the hero\'s next leave line, cap 2 s), by heroes in reach and HP band; died10 = share followed by that hero\'s death within 10 s');
    out.push('  bar      reach  HP band   sec/game  died10');
    for (const bar of BARS) {
        for (const rk of ['0', '1', '2+']) {
            for (const [band] of BANDS) {
                const c = res.t2[`${bar}\t${rk}\t${band}`];
                if (!c) continue;
                out.push(`  ${bar.padEnd(8)} ${rk.padEnd(5)}  ${band.padEnd(8)} ${fmt(c.sec / nGames).padStart(8)}  ${fmt(100 * c.died / c.sec, 0).padStart(5)}%`);
            }
        }
    }
    out.push('', 'Table 3: hp / kill (kill = sum of dmg in reach) at the last line before the death and the last line 3 s or more before it; group = heroes in reach at the last line');
    out.push('  reach   n   last: median [p25-p75]   share<1.0 <1.25 <1.5 <2.0  | 3 s before (n): median [p25-p75]  share<1.0 <1.25 <1.5 <2.0');
    for (const rk of ['1', '2+']) {
        const c = res.t3[rk];
        const label = rk;
        if (!c) { out.push(`  ${label.padEnd(4)}   0`); continue; }
        const stat = (a) => `${fmt(median(a), 2)} [${fmt(pct(a, 0.25), 2)}-${fmt(pct(a, 0.75), 2)}]  ${STAYS.map((s) => fmt(100 * a.filter((v) => v < s).length / Math.max(1, a.length), 0).padStart(3) + '%').join(' ')}`;
        out.push(`  ${label.padEnd(4)} ${String(c.nLast).padStart(3)}   ${stat(c.last)}  | (${c.before.length}) ${stat(c.before)}`);
    }
    out.push(`  last line had 0 in reach: ${(res.t3['0'] || { nLast: 0 }).nLast} deaths (no kill to divide by); median age of the last line before the death ${fmt(median(res.t3.age || []), 2)} s`);
    if (show > 0) {
        out.push('', `Examples (up to ${show} per cell): deaths where today called a leave and the bar did not (today-only), and the reverse (bar-only)`);
        for (const [k, list] of Object.entries(res.examples).sort()) {
            const [which, bar, rk] = k.split('\t');
            out.push(`  ${which} stay ${bar} reach ${rk}: ${list.length}`);
            for (const e of list.slice(0, show)) out.push(`      ${e.file} pid ${e.pid} t=${e.t}`);
        }
    }
    return out.join('\n');
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
    const games = logs.map((l) => gameOfLog(l, gameNo)).filter((g) => g.rows.length > 0);
    decideAll(games.flatMap((g) => g.rows));
    const res = analyse(games);
    if (argv.includes('--json')) { console.log(JSON.stringify({ games: games.length, ...res }, null, 1)); return; }
    console.log(report(res, games.length, Number(opt('--rows') ?? 0)));
}

if (require.main === module) main(process.argv.slice(2));
module.exports = { mapLeave, deathsFromSnaps, decideAll, today, analyse };
