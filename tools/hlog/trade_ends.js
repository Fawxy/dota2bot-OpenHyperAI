#!/usr/bin/env node
'use strict';
// Trade ends against their open (step 4.1 of docs/proposals/2026-11-20-step4-exchanges.md): for every trade episode (one `ev=trade` line)
// of the runs, replay the end reason's gate on the episode's first cut line (the last `ev=cut kind=trade` with no running exchange, on the
// episode's target, at or before its start) and report, per level it opened as: episodes, taken, ends already true at open, and reopens on
// the same target within 5 s, split by how the earlier episode ended.
//   node trade_ends.js <run> [<run> ...] [--json] [--rows N]
// <run>: a batch label (h2h742): every ~/.dotactl/logs file with `-<run>_` in its name, its last game. --rows N: N example moments per row.
//
// What "true at open" is: Trade.OpenFails on the open's inputs gives the first failing gate of each level on the target, read fresh
// (no running exchange); an end whose reason is among them (`gate`), or `no_clear` with the episode's first act a step out (`think`, from
// `fa`), was already true when the exchange opened. Any other end (`later`: the target died, `losing`, `pair_end`, a mode took the hero...)
// came from a change after the open, and has no flag. A reopen's earlier end is `at open` (the exchange started when it could not
// finish: the wrong-open cause), `later gate` (a gate that held at open and flipped: the re-asking cause) or `later only`.
const fs = require('fs');
const os = require('os');
const path = require('path');
const { readGames, worldOf, replay } = require('./cut');

const LOGS = path.join(os.homedir(), '.dotactl', 'logs');
const REOPEN = 5;

function logsOf(run) {
    return fs.readdirSync(LOGS).filter((f) => f.includes(`-${run}_`) && f.endsWith('.log')).sort().map((f) => path.join(LOGS, f));
}

/** One log's episodes: { pid, tgt, kind, why, result, start, end, fa, open (the first cut) }, in time order per hero. */
function episodesOf(log) {
    const games = readGames(fs.readFileSync(log, 'utf8'));
    const game = games[games.length - 1];
    if (!game) return { game, eps: [] };
    const byPid = new Map();
    for (const c of game.cuts) {
        if (c.kind !== 'trade') continue;
        if (!byPid.has(c.pid)) byPid.set(c.pid, []);
        byPid.get(c.pid).push(c);
    }
    const eps = [];
    for (const e of game.trades) {
        const end = Number(e.t), dur = Number(e.dur || 0);
        const start = end - dur;
        const cuts = byPid.get(e.pid) || [];
        let open;
        for (const c of cuts) {
            if (Number(c.t) > start + 0.2) break;
            if (c.run === undefined && c.lv !== 'none' && c.tgt === e.tgt) open = c;
        }
        eps.push({ pid: e.pid, tgt: e.tgt, kind: e.kind, why: e.why, result: e.result, start, end, fa: e.fa, open, file: path.basename(log) });
    }
    eps.sort((a, b) => (a.pid === b.pid ? a.end - b.end : Number(a.pid) - Number(b.pid)));
    return { game, eps };
}

function main(argv) {
    const runs = argv.filter((a, i) => !a.startsWith('--') && argv[i - 1] !== '--rows');
    if (argv.includes('--help') || !runs.length) {
        console.log(fs.readFileSync(__filename, 'utf8').split('\n').slice(2, 7).map((l) => l.replace(/^\/\/ ?/, '')).join('\n'));
        process.exit(runs.length ? 0 : 2);
    }
    const rows = Number(argv[argv.indexOf('--rows') + 1] || 0) || (argv.includes('--rows') ? 2 : 0);
    const logs = runs.flatMap(logsOf);
    if (!logs.length) { console.error('no logs'); process.exit(1); }
    let kinds;
    const all = [];
    let noOpen = 0, noReplay = 0;
    for (const log of logs) {
        const { game, eps } = episodesOf(log);
        for (const e of eps) {
            if (e.open === undefined) { noOpen++; e.level = undefined; all.push(e); continue; }
            e.level = e.open.lv;
            try {
                const obs = replay('trade', worldOf(game, e.open));
                const main = obs.actions[0] || {};
                if (main.verb !== e.open.lv || main.target !== `hero#${e.open.tgt}`) throw new Error('replay differs from the cut');
                const opens = obs.actions.find((a) => a.verb === 'opens');
                e.opens = opens === undefined || opens.target === '-' ? [] : opens.target.split(',');
                if (kinds === undefined) {
                    const k = obs.actions.find((a) => a.verb === 'endkinds');
                    kinds = Object.fromEntries(k.target.split(',').map((x) => x.split('=')));
                }
            } catch (err) { noReplay++; e.opens = undefined; }
            all.push(e);
        }
    }
    const kindOf = (why) => (kinds && kinds[why]) || 'later';
    /** 1 true at open, 0 came later, undefined later-only. */
    const atOpen = (e) => {
        const k = kindOf(e.why);
        if (e.opens === undefined) return undefined;
        if (k === 'gate') return e.opens.includes(e.why) ? 1 : 0;
        if (k === 'think') return e.fa === 'step' ? 1 : 0;
        return undefined;
    };
    const out = {};
    const level = (e) => e.level || 'no_open_cut';
    for (const e of all) {
        const r = (out[level(e)] = out[level(e)] || { episodes: 0, taken: 0, ends: {}, reopens: 0, reopenFrom: {}, examples: {} });
        r.episodes++;
        if (e.result !== 'lost') r.taken++;
        const a = atOpen(e);
        const k = `${e.why}`;
        const x = (r.ends[k] = r.ends[k] || { n: 0, atOpen: 0, later: 0, laterOnly: 0 });
        x.n++;
        if (a === 1) x.atOpen++; else if (a === 0) x.later++; else x.laterOnly++;
        e.a = a;
    }
    const byHero = new Map();
    for (const e of all) { const k = `${e.file}:${e.pid}`; if (!byHero.has(k)) byHero.set(k, []); byHero.get(k).push(e); }
    for (const list of byHero.values()) {
        for (let i = 1; i < list.length; i++) {
            const p = list[i - 1], e = list[i];
            if (e.tgt !== p.tgt || e.start - p.end > REOPEN || e.start < p.end - 0.5) continue;
            const r = out[level(e)];
            r.reopens++;
            const from = p.a === 1 ? 'at open' : p.a === 0 ? 'later gate' : 'later only';
            const key = `${from}: ${p.why}`;
            r.reopenFrom[key] = (r.reopenFrom[key] || 0) + 1;
            if (rows) (r.examples[key] = r.examples[key] || []).length < rows && r.examples[key].push(`${e.file} pid ${e.pid} t=${e.start.toFixed(1)}`);
        }
    }
    const result = { games: logs.length, episodes: all.length, noOpenCut: noOpen, notReplayed: noReplay, levels: out };
    if (argv.includes('--json')) { console.log(JSON.stringify(result, null, 1)); return; }
    console.log(`${logs.length} games, ${all.length} episodes (no open cut ${noOpen}, not replayed ${noReplay}), per game ${(all.length / logs.length).toFixed(1)}`);
    for (const [lv, r] of Object.entries(out)) {
        const ends = Object.entries(r.ends).sort((a, b) => b[1].n - a[1].n);
        const tAt = ends.reduce((s, [, x]) => s + x.atOpen, 0), tLater = ends.reduce((s, [, x]) => s + x.later, 0), tOnly = ends.reduce((s, [, x]) => s + x.laterOnly, 0);
        console.log(`\n${lv}: ${r.episodes} episodes (${r.taken} taken), ends true at open ${tAt}, came later ${tLater}, later only ${tOnly}; reopens within ${REOPEN} s on the same target ${r.reopens} (${(r.reopens / logs.length).toFixed(1)} a game)`);
        for (const [why, x] of ends) console.log(`    end ${why.padEnd(14)} ${String(x.n).padStart(5)}   at open ${String(x.atOpen).padStart(4)}   later ${String(x.later).padStart(4)}   later only ${String(x.laterOnly).padStart(4)}`);
        for (const [k, n] of Object.entries(r.reopenFrom).sort((a, b) => b[1] - a[1])) console.log(`    reopen after ${k.padEnd(26)} ${String(n).padStart(4)}${r.examples[k] ? `   e.g. ${r.examples[k].join('; ')}` : ''}`);
    }
}

if (require.main === module) main(process.argv.slice(2));
module.exports = { episodesOf };
