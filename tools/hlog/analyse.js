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
const { laningMetrics } = require('./metrics');

const LOG_DIR = path.join(os.homedir(), 'Library/Application Support/Steam/steamapps/common/dota 2 beta/game/dota');
const DEFAULT_LOG = path.join(LOG_DIR, 'console.log');

/** Once a lobby gets a match ID, Dota moves the rest of the log to console.<matchid>.log. Prefer the newest of those. */
function latestLog(dir = LOG_DIR) {
    let names = [];
    try {
        names = fs.readdirSync(dir).filter(n => /^console\.\d+\.log$/.test(n));
    } catch (_) {}
    if (names.length === 0) return path.join(dir, 'console.log');
    const newest = names.map(n => path.join(dir, n)).sort((a, b) => fs.statSync(b).mtimeMs - fs.statSync(a).mtimeMs)[0];
    return newest;
}

const USAGE = `usage: node tools/hlog/analyse.js [log file] [options]

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
  --laning [--until T] per-position laning metrics to T (default 10:00), as compare.js computes them

default log: the newest console.<matchid>.log in ${LOG_DIR}, else ${DEFAULT_LOG}`;

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
    const takesValue = new Set(['--game', '--mark', '--window', '--from', '--to', '--pid', '--ev', '--until']);
    for (let i = 0; i < argv.length; i++) {
        const a = argv[i];
        if (a === '-h' || a === '--help') opts.help = true;
        else if (takesValue.has(a)) opts[a.slice(2)] = argv[++i];
        else if (a.startsWith('--')) opts[a.slice(2)] = true;
        else opts.file = a;
    }
    return opts;
}

const LANING_COLS = ['lh', 'dn', 'kills', 'deaths', 'laningSec', 'retreatSec', 'retreatHealthySec', 'cautiousSec', 'commits', 'trades', 'pullsStarted', 'stacksStarted', 'rotations'];

// Rough map zones, close to research/replays.md's (OpenDota lane_pos): bases, then the three lane bands, then river.
function zoneOf(x, y) {
    if (x < -4500 && y < -4000) return 'base';
    if (x > 4000 && y > 3500) return 'base';
    if (Math.abs(x - y) < 2000) return 'mid';
    if (x < -5000 || y > 5200) return 'top';
    if (x > 5000 || y < -5200) return 'bot';
    if (Math.abs(x + y) < 1600) return 'river';
    return 'jungle';
}

// The lane a bot actually played: its most common lane zone over 2:00-6:00. The bot line's pos is read at its
// first tick, before roles settle and before a human's !pos swap, so it is not trusted for this.
function playedLane(bot) {
    const n = {};
    for (const p of bot.snaps) if (p.t >= 120 && p.t <= 360 && p.alive === 1) {
        const z = zoneOf(p.x, p.y);
        if (z === 'top' || z === 'mid' || z === 'bot') n[z] = (n[z] || 0) + 1;
    }
    const best = Object.keys(n).sort((a, b) => n[b] - n[a])[0];
    return best || '-';
}

/** Share of alive snapshots from the first one to `until` in the played lane's zone (research: cores 78-84%, supports 64%). */
function ownLaneShare(bot, until) {
    const lane = playedLane(bot);
    const s = bot.snaps.filter(p => p.t <= until && p.alive === 1);
    if (s.length === 0 || lane === '-') return '-';
    return ((100 * s.filter(p => zoneOf(p.x, p.y) === lane).length) / s.length).toFixed(0);
}

function laningTable(game, until) {
    const m = laningMetrics(game, { until });
    const team = t => (t === 2 ? 'rad' : t === 3 ? 'dire' : String(t));
    const bots = m.bots.slice().sort((a, b) => (a.team === b.team ? a.pid - b.pid : a.team - b.team));
    const rows = [['team', 'pos@load', 'lane', 'player', 'ownLane%', ...LANING_COLS]];
    for (const b of bots) {
        const cells = LANING_COLS.map(k => (Number.isInteger(b[k]) ? b[k] : b[k].toFixed(1)));
        rows.push([team(b.team), b.pos ?? '-', playedLane(game.bots[b.pid]), `${b.hero}[${b.pid}]`, ownLaneShare(game.bots[b.pid], until), ...cells]);
    }
    const head = `laning metrics to ${Math.floor(until / 60)}:${String(until % 60).padStart(2, '0')}, build ${m.build}${m.complete ? '' : ' (game ends before this)'}`;
    return head + '\n' + report.table(rows);
}

function main(argv) {
    const opts = parseArgs(argv);
    if (opts.help) {
        console.log(USAGE);
        return 0;
    }
    const file = opts.file || latestLog();
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
    if (opts.laning) {
        console.log(laningTable(game, opts.until !== undefined ? parseTime(opts.until) : 600));
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

module.exports = { main, parseTime, latestLog, LOG_DIR };
