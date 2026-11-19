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
// It also prints the reopen rate (per 100 trades opened and per 100 s in an exchange), the `pair_end` split of join ends (what changed
// between the open and the last cut: the pair answer gone, its target, the counts, our HP, the odds, or none: a flip) and an upper bound on
// the hits a swing-place rule would refuse (the creeps within 500 at the open).
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

/** The pair answer `dec:tgt:ko:kt` of a cut line, or undefined. */
function pjrOf(c) {
    if (!c || !c.pjr || c.pjr === '-') return undefined;
    const [dec, tgt, ko, kt] = String(c.pjr).split(':');
    return { dec, tgt, ko: Number(ko), kt: Number(kt) };
}

const MOVE = 0.1;
/** Join episodes that ended `pair_end`, split by what changed between the open's cut and the last cut before the end: the pair answer gone
 *  (`gone`), its target (`target`), the head count `hc` or the creep count (`count`), our HP by MOVE (`hp`), either odds by MOVE
 *  (`odds`, the read moved), or none of these (`flip`: the same read crossing its line). */
function pairEnds(all, gamesByFile) {
    const out = { n: 0, classes: {}, examples: {} };
    for (const e of all) {
        if (e.level !== 'join' || e.why !== 'pair_end' || !e.open) continue;
        const game = gamesByFile.get(e.file);
        let last;
        for (const c of game.cuts) {
            if (c.kind !== 'trade' || c.pid !== e.pid) continue;
            const t = Number(c.t);
            if (t > e.end + 0.3) break;
            if (t > Number(e.open.t)) last = c;
        }
        const a = pjrOf(e.open), b = pjrOf(last);
        let cls;
        if (!last) cls = 'no_later_cut';
        else if (!b) cls = 'gone';
        else if (a && b.tgt !== a.tgt) cls = 'target';
        else if (last.hc !== e.open.hc || last.cr !== e.open.cr) cls = 'count';
        else if (Math.abs(Number(last.hp) - Number(e.open.hp)) >= MOVE) cls = 'hp';
        else if (a && (Math.abs(b.ko - a.ko) >= MOVE || Math.abs(b.kt - a.kt) >= MOVE)) cls = 'odds';
        else cls = 'flip';
        out.n++;
        out.classes[cls] = (out.classes[cls] || 0) + 1;
        (out.examples[cls] = out.examples[cls] || []).length < 2 && out.examples[cls].push(`${e.file} pid ${e.pid} t=${e.end.toFixed(1)}`);
    }
    return out;
}

function printPairEnds(pe) {
    console.log(`
pair_end join ends ${pe.n}: ` + Object.entries(pe.classes).sort((a, b) => b[1] - a[1]).map(([k, n]) => `${k} ${n}`).join(', '));
}

/** Reopen rates: per episode opened, and per hero-second inside trade episodes (the seconds a hero spent in an exchange). */
function printRates(all, games, out) {
    const sec = all.reduce((s, e) => s + Math.max(0, e.end - e.start), 0);
    let reopens = 0;
    for (const r of Object.values(out)) reopens += r.reopens;
    console.log(`reopens ${reopens} (${(reopens / games).toFixed(1)} a game): ${(reopens / all.length * 100).toFixed(1)} per 100 trades opened, ${(reopens / sec * 100).toFixed(1)} per 100 s in an exchange (${(sec / games).toFixed(0)} s a game)`);
}

/** An upper bound on the hits 4.2b and 4.3 would refuse (step 4's refusal count). The gates are not built, so this is only the open's creep
 *  count `cr` (enemy lane creeps within 500 of the hero, not of the swing place): a hit that opened with none needs no priced test and is
 *  never refused for the creeps; the rest are the most that can be. Taken: the offer was not lost (`result` not `lost`). */
function printSwing(all) {
    const hits = all.filter((e) => e.level === 'hit' && e.open && e.result !== 'lost');
    const by = {};
    for (const e of hits) { const c = Number(e.open.cr || 0); const k = c === 0 ? '0' : c <= 2 ? '1-2' : '3+'; by[k] = (by[k] || 0) + 1; }
    console.log(`hits taken ${hits.length}; enemy creeps within 500 at the open: ` + ['0', '1-2', '3+'].map((k) => `${k}: ${by[k] || 0}`).join(', ') + ' (an upper bound on the refusals; the gates are not built)');
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
    const gamesByFile = new Map();
    const all = [];
    let noOpen = 0, noReplay = 0;
    for (const log of logs) {
        const { game, eps } = episodesOf(log);
        gamesByFile.set(path.basename(log), game);
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
    const pe = pairEnds(all, gamesByFile);
    const result = { pairEnd: pe, games: logs.length, episodes: all.length, noOpenCut: noOpen, notReplayed: noReplay, levels: out };
    if (argv.includes('--json')) { console.log(JSON.stringify(result, null, 1)); return; }
    console.log(`${logs.length} games, ${all.length} episodes (no open cut ${noOpen}, not replayed ${noReplay}), per game ${(all.length / logs.length).toFixed(1)}`);
    printRates(all, logs.length, out);
    printPairEnds(pe);
    printSwing(all);
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
