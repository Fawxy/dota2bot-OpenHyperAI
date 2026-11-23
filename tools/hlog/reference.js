// Logs kept as assets of a GitHub release on this repo, so any machine reads them. By default the release is the gate's
// pinned reference and its mirror (master SCOREBOARD.md "The merge gate"), which gate.js --ref and ledger.js --null read;
// it is replaced when the pin moves. --release <tag> names another: one per batch worth keeping, logs-<batch> by custom.
// Usage:
//   node reference.js fetch [--release <tag>]                  download the release's logs that ~/.dotactl/logs lacks;
//                                                              hlog ingests them on its next run
//   node reference.js push [--release <tag>] <run> [<run> ...] replace the release with these runs' logs (label prefixes,
//                                                              as gate.js)
//   node reference.js list [--release <tag>]                   the release's logs
// The repo is public and a Dota console log names the machine's user (Steam id, Steam name, home folder), so an asset
// holds only the lines the store reads (keeps): telemetry, dotactl's facts, Lua errors. push stops on a kept line that
// still names the user (leak). Needs the `gh` CLI, logged in; assets are brotli, one per log.
'use strict';
const fs = require('fs');
const os = require('os');
const path = require('path');
const zlib = require('zlib');
const { execFileSync } = require('child_process');
const { parseLine } = require('./parse');
const { LOGS } = require('./store');

const GATE = 'gate-reference';
const EXT = '.br';

/** A line the store reads: parse.js makes something of it, or it is one of dotactl's facts. */
const keeps = (line) => line.includes('[DOTACTL] ') || parseLine(line) !== undefined;

/** What in a kept line names the machine's user, or undefined. `who` is the home folder and the login name. */
function leak(line, who = [os.homedir(), os.userInfo().username]) {
    const m = line.match(/steamid|\[U:\d:\d+\]|\b7656119\d{10}\b/i);
    if (m) return m[0];
    return who.find((w) => w && line.includes(w));
}

/** A log's text less every line the store does not read. Throws on a kept line that names the user. */
function strip(text, who) {
    const out = [];
    for (const line of text.split('\n')) {
        if (!keeps(line)) continue;
        const l = leak(line, who);
        if (l !== undefined) throw new Error(`a kept line names the user (${l}): ${line.slice(0, 160)}`);
        out.push(line);
    }
    return out.join('\n') + '\n';
}

/** The command line: { cmd, release, runs }. --release takes the next word; the default is the gate's release. */
function parseArgs(argv) {
    const out = { cmd: argv[0], release: GATE, runs: [] };
    for (let i = 1; i < argv.length; i++) {
        if (argv[i] === '--release') {
            out.release = argv[++i];
            if (!out.release || out.release.startsWith('-')) throw new Error('--release needs a tag');
        } else out.runs.push(argv[i]);
    }
    return out;
}

/** The release's title and notes: the gate's own, or a plain list of the runs. */
function describeRelease(release, runs, logs) {
    if (release === GATE) return ['Gate reference logs', `The merge gate's pinned reference and its mirror: ${runs.join(', ')} (${logs} logs, telemetry lines only). Fetch with tools/hlog/reference.js fetch.`];
    return [`Logs: ${runs.join(', ')}`, `${runs.join(', ')}: ${logs} dotactl logs, cut to the lines hlog reads and checked for the user's Steam id and home folder; brotli, one asset per log. Fetch with tools/hlog/reference.js fetch --release ${release}.`];
}

/** The log files of a run: dotactl's timestamp, then the run's label prefix. */
function logsOf(run, dir = LOGS) {
    const re = new RegExp(`^\\d{4}-\\d\\d-\\d\\dT\\d\\d-\\d\\d-\\d\\d-${run.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')}_.*\\.log$`);
    return fs.readdirSync(dir).filter((f) => re.test(f)).sort();
}

const gh = (args, opts = {}) => execFileSync('gh', args, { cwd: __dirname, encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'], ...opts });

function assets(release) {
    let out;
    try {
        out = gh(['release', 'view', release, '--json', 'assets', '-q', '.assets[].name']);
    } catch (e) {
        if (/release not found/i.test(String(e.stderr))) return undefined;
        throw e;
    }
    return out.split('\n').filter((n) => n.endsWith(EXT));
}

const brotli = (buf) => new Promise((resolve, reject) => zlib.brotliCompress(buf, { params: {
    [zlib.constants.BROTLI_PARAM_QUALITY]: 11, [zlib.constants.BROTLI_PARAM_LGWIN]: 24, [zlib.constants.BROTLI_PARAM_SIZE_HINT]: buf.length,
} }, (err, out) => (err ? reject(err) : resolve(out))));

async function push(runs, release = GATE) {
    const files = runs.flatMap((r) => {
        const fsOf = logsOf(r);
        if (!fsOf.length) throw new Error(`${r}: no log in ${LOGS}`);
        return fsOf;
    });
    const tmp = fs.mkdtempSync(path.join(os.tmpdir(), 'hlog-ref-'));
    // Every log is stripped before any is uploaded: one leak stops the push with the release untouched.
    const texts = files.map((f) => [f, Buffer.from(strip(fs.readFileSync(path.join(LOGS, f), 'utf8')))]);
    let bytes = 0;
    const queue = texts.slice();
    await Promise.all(Array.from({ length: 4 }, async () => {
        for (let job = queue.shift(); job; job = queue.shift()) {
            const out = await brotli(job[1]);
            bytes += out.length;
            fs.writeFileSync(path.join(tmp, job[0] + EXT), out);
        }
    }));
    if (assets(release) !== undefined) gh(['release', 'delete', release, '--yes', '--cleanup-tag']);
    const [title, notes] = describeRelease(release, runs, files.length);
    gh(['release', 'create', release, '--title', title, '--latest=false', '--notes', notes]);
    const paths = files.map((f) => path.join(tmp, f + EXT));
    for (let i = 0; i < paths.length; i += 20) gh(['release', 'upload', release, ...paths.slice(i, i + 20)]);
    fs.rmSync(tmp, { recursive: true });
    return { logs: files.length, bytes };
}

function fetch(release = GATE) {
    const have = assets(release);
    if (have === undefined) throw new Error(`no ${release} release on this repo`);
    fs.mkdirSync(LOGS, { recursive: true });
    const want = have.filter((n) => !fs.existsSync(path.join(LOGS, n.slice(0, -EXT.length))));
    if (!want.length) return { logs: have.length, fetched: 0 };
    const tmp = fs.mkdtempSync(path.join(os.tmpdir(), 'hlog-ref-'));
    for (let i = 0; i < want.length; i += 20) gh(['release', 'download', release, '-D', tmp, ...want.slice(i, i + 20).flatMap((n) => ['-p', n])]);
    for (const n of want) fs.writeFileSync(path.join(LOGS, n.slice(0, -EXT.length)), zlib.brotliDecompressSync(fs.readFileSync(path.join(tmp, n))));
    fs.rmSync(tmp, { recursive: true });
    return { logs: have.length, fetched: want.length };
}

if (require.main === module) {
    (async () => {
        const { cmd, release, runs } = parseArgs(process.argv.slice(2));
        if (cmd === 'fetch' && !runs.length) {
            const r = fetch(release);
            console.log(`${r.fetched} of ${r.logs} logs fetched into ${LOGS}`);
        } else if (cmd === 'push' && runs.length) {
            const r = await push(runs, release);
            console.log(`${r.logs} logs pushed to release ${release}, ${(r.bytes / 1e6).toFixed(1)} MB`);
        } else if (cmd === 'list' && !runs.length) {
            const a = assets(release);
            console.log(a === undefined ? `no ${release} release` : a.map((n) => n.slice(0, -EXT.length)).join('\n'));
        } else {
            console.log(fs.readFileSync(__filename, 'utf8').split('\n').filter((l) => l.startsWith('//')).map((l) => l.slice(3)).join('\n'));
            process.exit(cmd === '--help' || cmd === '-h' ? 0 : 2);
        }
    })().catch((e) => {
        console.error(e.stderr ? String(e.stderr).trim() : e.message);
        process.exit(1);
    });
}

module.exports = { keeps, leak, strip, logsOf, parseArgs, describeRelease };
