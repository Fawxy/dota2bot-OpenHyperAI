// One batch of paired games from a JSON spec: one-shot `dotactl run` per game, arms interleaved, then lineup_check and the log
// bank. Run it as a background shell job (skill eval-run, "Running a batch"); it never holds the client between games.
// Usage: node batch.js <spec.json> [--dry-run]
//
// Spec (paths relative to the master root unless absolute):
//   { "name": "s1", "worktree": "oha-health", "build": "b2d2ba9",
//     "lineups": ["A", "B", "C", "A", "B"],                       one rep per entry
//     "arms": { "on":  { "set": [], "states": true },             arm order rotates by one each rep
//               "off": { "set": ["Humaniser.Enable=false", "Humaniser.States.Enable=false"], "states": false } },
//     "until": "20:00", "timescale": 8, "mode": "bots", "args": [],   args: extra dotactl run arguments
//     "validUntil": 600, "note": "..." }                          optional, copied into the bank entries
//
// Remote (dotactl serve on another machine, REQUESTS D7): "remote": true reads { host, token, client } from
//   ~/.dotactl/remote-client.json; each arm names a pushed commit instead of --set (remote jobs take none):
//   "arms": { "on": { "branch": "remote/<client>/x-on", "sha": "<40 hex>", "states": true, "ours": { "X": true } }, ... }.
//   No worktree or --build; the build stamp is the commit's. A game's game.log is saved to ~/.dotactl/logs/<time>-<label>.log
//   so hlog ingests it; a failed job is retried once like a local run. `ours` is checked by lineup_check (ev=bot ours).
//
// Manifest: ~/.dotactl/batches/<name>.manifest, one `status=ok|fail label=... seed= arm= lineup= log=...` line per game.
// Resumable: a label already `status=ok` is skipped. `--build` goes to the first game this run starts. A failed game is retried
// once (with `--build` again if that game was the build), then the batch stops (exit 1). The curfew stops it (exit 3); a
// usage error is exit 2. Labels are <name>_<lineup>_<arm>_<rep>.
'use strict';

const fs = require('fs');
const os = require('os');
const path = require('path');
const { spawnSync } = require('child_process');
const { readManifest } = require('./manifest');
const { checkGame, SEEDS } = require('./lineup_check');
const bank = require('./bank');

const MASTER = path.resolve(__dirname, '../../../..');
const BATCHES = path.join(os.homedir(), '.dotactl', 'batches');

function seconds(until) {
    const m = String(until).match(/^(\d+):(\d\d)$/);
    return m ? Number(m[1]) * 60 + Number(m[2]) : Number(until);
}

/** The games of a spec in run order: { label, rep, lineup, seed, arm, set }. */
function plan(spec) {
    const arms = Object.keys(spec.arms);
    const games = [];
    spec.lineups.forEach((lineup, i) => {
        const rep = i + 1;
        const order = arms.map((_, k) => arms[(k + i) % arms.length]);
        for (const arm of order) {
            games.push({ label: `${spec.name}_${lineup}_${arm}_${rep}`, rep, lineup, seed: SEEDS[lineup], arm, set: spec.arms[arm].set || [] });
        }
    });
    return games;
}

/** dotactl run arguments for one game. */
function runArgs(spec, game, build) {
    // dotactl resolves a bare name under repos/, so pass the worktree as an absolute path (a name means worktrees/<name>).
    const args = ['run', '--worktree', path.isAbsolute(spec.worktree) ? spec.worktree : path.resolve(MASTER, 'worktrees', spec.worktree)];
    if (build) args.push('--build');
    args.push('--mode', spec.mode || 'bots', '--seed', String(game.seed), '--timescale', String(spec.timescale || 8),
        '--until', String(spec.until), '--no-analyse', '--label', game.label);
    for (const s of game.set) args.push('--set', s);
    return args.concat(spec.args || []);
}

const sleep = ms => new Promise(r => setTimeout(r, ms));

/** The remote job body for one game: the arm's pushed commit, the lineup seed and the spec's clock. */
function remoteJob(spec, game) {
    const arm = spec.arms[game.arm];
    return { branch: arm.branch, sha: arm.sha, until: String(spec.until), seed: game.seed, timescale: spec.timescale || 8, label: game.label };
}

/** Runs one game on the remote host; resolves to { ok, log, out }. Polls every `poll` ms (the server cannot notify). */
async function runRemote(cfg, spec, game, { poll = 30000 } = {}) {
    const H = { Authorization: `Bearer ${cfg.token}`, 'Content-Type': 'application/json' };
    const r = await fetch(`${cfg.host}/jobs`, { method: 'POST', headers: H, body: JSON.stringify(remoteJob(spec, game)) });
    const job = await r.json();
    if (!r.ok || !job.id) return { ok: false, out: `submit ${r.status} ${JSON.stringify(job)}` };
    let j = job;
    while (!['done', 'failed', 'cancelled'].includes(j.state)) {
        await sleep(poll);
        try { j = await (await fetch(`${cfg.host}/jobs/${job.id}`, { headers: H })).json(); } catch (e) { /* retry next poll */ }
    }
    const out = `job ${job.id} ${j.state} ${j.error || ''}`;
    if (j.state !== 'done') return { ok: false, out };
    const g = await fetch(`${cfg.host}/jobs/${job.id}/files/game.log`, { headers: H });
    if (!g.ok) return { ok: false, out: `${out}; game.log ${g.status}` };
    const stamp = new Date().toISOString().replace(/:/g, '-').replace(/\..*/, '');
    const log = path.join(os.homedir(), '.dotactl', 'logs', `${stamp}-${game.label}.log`);
    fs.writeFileSync(log, Buffer.from(await g.arrayBuffer()));
    return { ok: true, log, out };
}

function manifestLine(status, game, extra) {
    return `status=${status} label="${game.label}" seed=${game.seed} arm=${game.arm} lineup=${game.lineup} ${extra}`;
}

async function main(argv) {
    const specFile = argv[0];
    if (!specFile) {
        console.error('usage: node batch.js <spec.json> [--dry-run]');
        process.exit(2);
    }
    const spec = JSON.parse(fs.readFileSync(specFile, 'utf8'));
    for (const k of ['name', spec.remote ? 'arms' : 'worktree', 'build', 'lineups', 'arms', 'until']) {
        if (spec[k] === undefined) {
            console.error(`spec lacks ${k}`);
            process.exit(2);
        }
    }
    const dotactl = path.resolve(MASTER, spec.dotactl || 'repos/dotactl/dotactl.js');
    const manifest = path.join(BATCHES, `${spec.name}.manifest`);
    const games = plan(spec);
    if (argv.includes('--dry-run')) {
        games.forEach((g, i) => console.log(`${g.label.padEnd(14)} ${spec.remote ? `POST /jobs ${JSON.stringify(remoteJob(spec, g))}` : `node dotactl.js ${runArgs(spec, g, i === 0).join(' ')}`}`));
        return;
    }
    const cfg = spec.remote ? JSON.parse(fs.readFileSync(path.join(os.homedir(), '.dotactl', 'remote-client.json'), 'utf8')) : undefined;
    fs.mkdirSync(BATCHES, { recursive: true });
    if (!fs.existsSync(manifest)) fs.writeFileSync(manifest, '');
    const done = () => new Set(readManifest(manifest).map(g => g.label));
    let built = false;
    for (const game of games) {
        if (done().has(game.label)) continue;
        for (let attempt = 1; ; attempt++) {
            if (cfg) {
                const rr = await runRemote(cfg, spec, game);
                fs.writeFileSync(path.join(BATCHES, `${spec.name}-last.out`), rr.out);
                if (rr.ok) {
                    fs.appendFileSync(manifest, manifestLine('ok', game, `log="${rr.log}"`) + '\n');
                    console.log(`ok ${game.label} ${rr.out}`);
                    break;
                }
                fs.appendFileSync(manifest, manifestLine('fail', game, `remote="${rr.out}" attempt=${attempt}`) + '\n');
                console.log(`fail ${game.label} ${rr.out} attempt ${attempt}`);
                if (attempt >= 2) process.exit(1);
                continue;
            }
            const r = spawnSync(process.execPath, [dotactl, ...runArgs(spec, game, !built)], { cwd: MASTER, encoding: 'utf8', maxBuffer: 1 << 26 });
            const out = `${r.stdout || ''}${r.stderr || ''}`;
            fs.writeFileSync(path.join(BATCHES, `${spec.name}-last.out`), out);
            if (/closed by the user/i.test(out)) {
                console.log('curfew: stopping');
                process.exit(3);
            }
            const log = ((out.match(/^log: (.+)$/m) || [])[1] || '').trim().replace(/\\/g, '/');
            if (r.status === 0 && log) {
                built = true;
                fs.appendFileSync(manifest, manifestLine('ok', game, `log="${log}"`) + '\n');
                console.log(`ok ${game.label} ${(out.match(/lineup: .*/) || [''])[0].slice(0, 120)}`);
                break;
            }
            fs.appendFileSync(manifest, manifestLine('fail', game, `rc=${r.status} attempt=${attempt} log="${log}"`) + '\n');
            console.log(`fail ${game.label} rc=${r.status} attempt ${attempt}`);
            if (attempt >= 2) process.exit(1);
        }
    }
    // Validity, then the bank: only games that pass lineup_check are banked.
    const ok = [];
    let bad = 0;
    for (const g of readManifest(manifest)) {
        const p = checkGame(fs.readFileSync(g.log, 'utf8'), { lineup: g.lineup, arm: g.arm, build: spec.build, until: seconds(spec.until), arms: spec.arms });
        console.log(`check ${g.label.padEnd(14)} ${p.length ? p.join('; ') : 'ok'}`);
        if (p.length) bad++;
        else ok.push(g.label);
    }
    const entries = bank.entriesFor(manifest, { validUntil: spec.validUntil, note: spec.note }).filter(e => ok.includes(e.label));
    bank.add(entries);
    console.log(`banked ${entries.length}; ${bad} failed lineup_check`);
    console.log('done');
    process.exit(bad ? 1 : 0);
}

if (require.main === module) main(process.argv.slice(2)).catch(e => { console.error(e); process.exit(1); });

module.exports = { plan, runArgs, seconds, remoteJob };
