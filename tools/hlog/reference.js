// The gate's pinned reference and its mirror (master SCOREBOARD.md "The merge gate"), kept as assets of one GitHub release
// on this repo so gate.js --ref and ledger.js --null read them on any machine. One release, replaced when the pin moves.
// Usage:
//   node reference.js fetch                    download the release's logs that ~/.dotactl/logs lacks; hlog ingests them
//                                              on its next run
//   node reference.js push <run> [<run> ...]   replace the release with these runs' logs (label prefixes, as gate.js)
//   node reference.js list                     the release's logs
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

const RELEASE = 'gate-reference';
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

/** The log files of a run: dotactl's timestamp, then the run's label prefix. */
function logsOf(run, dir = LOGS) {
    const re = new RegExp(`^\\d{4}-\\d\\d-\\d\\dT\\d\\d-\\d\\d-\\d\\d-${run.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')}_.*\\.log$`);
    return fs.readdirSync(dir).filter((f) => re.test(f)).sort();
}

const gh = (args, opts = {}) => execFileSync('gh', args, { cwd: __dirname, encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'], ...opts });

function assets() {
    let out;
    try {
        out = gh(['release', 'view', RELEASE, '--json', 'assets', '-q', '.assets[].name']);
    } catch (e) {
        if (/release not found/i.test(String(e.stderr))) return undefined;
        throw e;
    }
    return out.split('\n').filter((n) => n.endsWith(EXT));
}

const brotli = (buf) => new Promise((resolve, reject) => zlib.brotliCompress(buf, { params: {
    [zlib.constants.BROTLI_PARAM_QUALITY]: 11, [zlib.constants.BROTLI_PARAM_LGWIN]: 24, [zlib.constants.BROTLI_PARAM_SIZE_HINT]: buf.length,
} }, (err, out) => (err ? reject(err) : resolve(out))));

async function push(runs) {
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
    if (assets() !== undefined) gh(['release', 'delete', RELEASE, '--yes', '--cleanup-tag']);
    gh(['release', 'create', RELEASE, '--title', 'Gate reference logs', '--latest=false', '--notes',
        `The merge gate's pinned reference and its mirror: ${runs.join(', ')} (${files.length} logs, telemetry lines only). Fetch with tools/hlog/reference.js fetch.`]);
    const paths = files.map((f) => path.join(tmp, f + EXT));
    for (let i = 0; i < paths.length; i += 20) gh(['release', 'upload', RELEASE, ...paths.slice(i, i + 20)]);
    fs.rmSync(tmp, { recursive: true });
    return { logs: files.length, bytes };
}

function fetch() {
    const have = assets();
    if (have === undefined) throw new Error(`no ${RELEASE} release on this repo`);
    fs.mkdirSync(LOGS, { recursive: true });
    const want = have.filter((n) => !fs.existsSync(path.join(LOGS, n.slice(0, -EXT.length))));
    if (!want.length) return { logs: have.length, fetched: 0 };
    const tmp = fs.mkdtempSync(path.join(os.tmpdir(), 'hlog-ref-'));
    for (let i = 0; i < want.length; i += 20) gh(['release', 'download', RELEASE, '-D', tmp, ...want.slice(i, i + 20).flatMap((n) => ['-p', n])]);
    for (const n of want) fs.writeFileSync(path.join(LOGS, n.slice(0, -EXT.length)), zlib.brotliDecompressSync(fs.readFileSync(path.join(tmp, n))));
    fs.rmSync(tmp, { recursive: true });
    return { logs: have.length, fetched: want.length };
}

if (require.main === module) {
    const [cmd, ...rest] = process.argv.slice(2);
    (async () => {
        if (cmd === 'fetch') {
            const r = fetch();
            console.log(`${r.fetched} of ${r.logs} logs fetched into ${LOGS}`);
        } else if (cmd === 'push' && rest.length) {
            const r = await push(rest);
            console.log(`${r.logs} logs pushed to release ${RELEASE}, ${(r.bytes / 1e6).toFixed(1)} MB`);
        } else if (cmd === 'list') {
            const a = assets();
            console.log(a === undefined ? `no ${RELEASE} release` : a.map((n) => n.slice(0, -EXT.length)).join('\n'));
        } else {
            console.log(fs.readFileSync(__filename, 'utf8').split('\n').filter((l) => l.startsWith('//')).map((l) => l.slice(3)).join('\n'));
            process.exit(cmd === '--help' || cmd === '-h' ? 0 : 2);
        }
    })().catch((e) => {
        console.error(e.stderr ? String(e.stderr).trim() : e.message);
        process.exit(1);
    });
}

module.exports = { keeps, leak, strip, logsOf };
