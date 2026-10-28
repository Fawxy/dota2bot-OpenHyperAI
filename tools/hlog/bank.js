// Log bank: an index of every kept dotactl run log, one JSON object per line in ~/.dotactl/bank.jsonl (next to the logs it
// indexes). Each entry records the facts a later analysis needs to decide whether a log can stand in for a new game (skill
// eval-run, "Offline first"; GOVERNANCE.md s5 banked OFF arm): build, the arm's --set line, seed, --until, Dota patch and the
// ev= kinds the log carries. batch.js adds every batch it runs; voided logs are deleted with their entries (`prune`).
// Usage:
//   node bank.js add <manifest> [--valid-until 600] [--note "..."]     index a manifest's ok games (re-adding replaces)
//   node bank.js list [--arm off] [--seed 30] [--lineup A] [--until 1200] [--build abc1234] [--has creep_death] [--json]
//   node bank.js prune                                                  drop entries whose log file is gone
// Options: --bank <file> (default ~/.dotactl/bank.jsonl).
'use strict';

const fs = require('fs');
const os = require('os');
const path = require('path');
const { readManifest } = require('./manifest');

const BANK = path.join(os.homedir(), '.dotactl', 'bank.jsonl');

/** Facts of one game read from its log text. */
function describe(text) {
    const start = (text.match(/\[DOTACTL\] ev=start ([^\n]*)/) || [, ''])[1];
    const kv = k => (start.match(new RegExp(`(?:^| )${k}=(?:"([^"]*)"|(\\S+))`)) || []).slice(1).find(v => v !== undefined);
    const stop = text.match(/\[DOTACTL\] t=([\d.]+) ev=stop/);
    const evs = new Set();
    for (const m of text.matchAll(/\[HEV\] t=\S+ ev=(\w+)/g)) evs.add(m[1]);
    return {
        build: (text.match(/ ev=bot [^\n]*?build=(\S+)/) || [])[1],
        set: kv('set') || '',
        mode: kv('mode'),
        timescale: kv('timescale') !== undefined ? Number(kv('timescale')) : undefined,
        worktree: kv('worktree'),
        patch: (text.match(/\[Client\] Build: (\d+)/) || [])[1],
        // --until is not in the log; the stop clock rounded down to the minute gives it (ev=stop lands just after it).
        until: stop ? Math.floor(Number(stop[1]) / 60) * 60 : undefined,
        evs: [...evs].sort(),
    };
}

function load(file = BANK) {
    if (!fs.existsSync(file)) return [];
    return fs.readFileSync(file, 'utf8').split(/\r?\n/).filter(Boolean).map(l => JSON.parse(l));
}

function save(entries, file = BANK) {
    fs.mkdirSync(path.dirname(file), { recursive: true });
    fs.writeFileSync(file, entries.map(e => JSON.stringify(e)).join('\n') + (entries.length ? '\n' : ''));
}

/** Entries for a manifest's ok games. `validUntil` (s): metrics after it are not comparable with current builds. */
function entriesFor(manifest, { validUntil, note } = {}) {
    const batch = path.basename(manifest).replace(/\.[^.]*$/, '');
    return readManifest(manifest).map(g => ({
        label: g.label,
        batch,
        arm: g.arm,
        lineup: g.lineup,
        seed: g.seed,
        date: (path.basename(g.log).match(/^(\d{4}-\d\d-\d\d)/) || [])[1],
        log: g.log.replace(/\\/g, '/'),
        ...describe(fs.readFileSync(g.log, 'utf8')),
        ...(validUntil !== undefined ? { validUntil } : {}),
        ...(note ? { note } : {}),
    }));
}

/** Adds or replaces (same log path) the given entries. */
function add(entries, file = BANK) {
    const logs = new Set(entries.map(e => e.log));
    save([...load(file).filter(e => !logs.has(e.log)), ...entries], file);
}

/** Entries matching every given filter. `until`: the game ran at least that far. `has`: carries that ev= kind. */
function query(entries, { arm, seed, lineup, until, build, has } = {}) {
    return entries.filter(e =>
        (arm === undefined || e.arm === arm) &&
        (seed === undefined || e.seed === Number(seed)) &&
        (lineup === undefined || e.lineup === lineup) &&
        (until === undefined || e.until >= Number(until)) &&
        (build === undefined || (e.build || '').startsWith(build)) &&
        (has === undefined || e.evs.includes(has)));
}

/** Removes entries whose log is gone; returns them. */
function prune(file = BANK) {
    const all = load(file);
    const gone = all.filter(e => !fs.existsSync(e.log));
    save(all.filter(e => fs.existsSync(e.log)), file);
    return gone;
}

function main(argv) {
    const opt = k => (argv.includes(`--${k}`) ? argv[argv.indexOf(`--${k}`) + 1] : undefined);
    const file = opt('bank') || BANK;
    const [cmd, arg] = argv;
    if (cmd === 'add' && arg) {
        const v = opt('valid-until');
        const entries = entriesFor(arg, { validUntil: v !== undefined ? Number(v) : undefined, note: opt('note') });
        add(entries, file);
        console.log(`${entries.length} entries from ${path.basename(arg)} -> ${file}`);
    } else if (cmd === 'list') {
        const rows = query(load(file), { arm: opt('arm'), seed: opt('seed'), lineup: opt('lineup'), until: opt('until'), build: opt('build'), has: opt('has') });
        if (argv.includes('--json')) return console.log(JSON.stringify(rows, null, 1));
        for (const e of rows) {
            const valid = e.validUntil !== undefined ? ` valid to ${e.validUntil}s` : '';
            console.log(`${e.label.padEnd(14)} ${e.arm.padEnd(3)} ${e.lineup} seed=${e.seed} until=${e.until} build=${e.build} patch=${e.patch} set="${e.set}"${valid}`);
        }
        console.log(`${rows.length} entries`);
    } else if (cmd === 'prune') {
        const gone = prune(file);
        for (const e of gone) console.log(`removed ${e.label} (${e.log})`);
        console.log(`${gone.length} removed`);
    } else {
        console.error('usage: node bank.js add <manifest> [--valid-until s] [--note text] | list [filters] [--json] | prune  [--bank file]');
        process.exit(2);
    }
}

if (require.main === module) main(process.argv.slice(2));

module.exports = { BANK, describe, load, save, entriesFor, add, query, prune };
