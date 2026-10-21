#!/usr/bin/env node
// Humaniser telemetry analyser. Reads Dota's console.log (launch Dota with -condebug) and reports on
// the [HEV] lines from telemetry.ts.
'use strict';

const fs = require('fs');
const os = require('os');
const path = require('path');
const { parseLog } = require('./parse');
const { runChecks } = require('./checks');
const report = require('./report');

const DEFAULT_LOG = path.join(os.homedir(), 'Library/Application Support/Steam/steamapps/common/dota 2 beta/game/dota/console.log');

const USAGE = `usage: node tools/hlog/analyse.js [console.log] [options]

  (no option)          summary and checks for the latest game
  --list               one line per game in the log
  --game N             pick game N (default: the latest)
  --check              checks only; exit code 1 if any check fails
  --mark N             state of every bot at mark N, plus the events around it
  --window S           seconds before the mark (default 20; half as much after)
  --from T --to T      timeline between two game times (seconds or m:ss)
  --pid 1,2            limit the timeline or mark events to these players
  --ev mode,lasthit    limit the timeline to these event names
  --snaps              include 1 s snapshots in timelines
  --json               dump the parsed game as JSON

default log: ${DEFAULT_LOG}`;

function parseTime(s) {
    if (s === undefined) return undefined;
    const m = /^(-?)(\d+):(\d{1,2})$/.exec(s);
    if (m) return (m[1] ? -1 : 1) * (Number(m[2]) * 60 + Number(m[3]));
    const n = Number(s);
    if (Number.isNaN(n)) throw new Error(`bad time '${s}'`);
    return n;
}

function parseArgs(argv) {
    const opts = { file: undefined };
    const takesValue = new Set(['--game', '--mark', '--window', '--from', '--to', '--pid', '--ev']);
    for (let i = 0; i < argv.length; i++) {
        const a = argv[i];
        if (a === '-h' || a === '--help') opts.help = true;
        else if (takesValue.has(a)) opts[a.slice(2)] = argv[++i];
        else if (a.startsWith('--')) opts[a.slice(2)] = true;
        else opts.file = a;
    }
    return opts;
}

function main(argv) {
    const opts = parseArgs(argv);
    if (opts.help) {
        console.log(USAGE);
        return 0;
    }
    const file = opts.file || DEFAULT_LOG;
    if (!fs.existsSync(file)) {
        console.error(`${file} not found. Add -condebug to Dota's Steam launch options, play a game, then run this again.`);
        return 2;
    }
    const games = parseLog(fs.readFileSync(file, 'utf8'));
    if (games.length === 0) {
        console.error(`no humaniser telemetry in ${file}. Is Customize.Humaniser.Telemetry.Enable = true and the dev checkout linked?`);
        return 2;
    }
    if (opts.list) {
        for (const g of games) console.log(report.gameLine(g));
        return 0;
    }
    const index = opts.game !== undefined ? Number(opts.game) : games.length;
    const game = games[index - 1];
    if (!game) {
        console.error(`no game ${opts.game}; the log has ${games.length}`);
        return 2;
    }
    if (opts.json) {
        console.log(JSON.stringify(game, null, 1));
        return 0;
    }
    const pids = opts.pid ? String(opts.pid).split(',').map(Number) : undefined;
    if (opts.mark !== undefined) {
        console.log(report.markView(game, Number(opts.mark), opts.window ? Number(opts.window) : 20, { pids, snaps: opts.snaps }));
        return 0;
    }
    if (opts.from !== undefined || opts.to !== undefined || opts.ev !== undefined) {
        const evs = opts.ev ? String(opts.ev).split(',') : undefined;
        console.log(report.timeline(game, { from: parseTime(opts.from), to: parseTime(opts.to), pids, evs, snaps: opts.snaps }));
        return 0;
    }
    const results = runChecks(game);
    if (!opts.check) console.log(report.summary(game), '\n');
    console.log(report.checksText(results));
    return opts.check && results.some(r => r.level === 'fail') ? 1 : 0;
}

if (require.main === module) process.exit(main(process.argv.slice(2)));

module.exports = { main, parseTime };
