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
//     "validUntil": 600, "note": "...",                           optional, copied into the bank entries
//     "er": "tools/hlog/bars/er-ER-nnn.json", "look": 9, "n": 5 }   optional: stop when decided (below)
//
// Stop when decided (GOVERNANCE.md s5): with `er` (an ER spec, relative to this repo's root unless absolute) the batch judges
// the spec's bars after each game (decide.js; `look` = games per arm at the interim look, `n` = games per seed for the
// MDE, default 5) and stops once no remaining game can change a bar, printing `decide: <reason>` after every game.
//
// Remote (dotactl serve on another machine, REQUESTS D7): "remote": true reads { host, token, client } from
//   ~/.dotactl/remote-client.json; each arm names a pushed commit instead of --set (remote jobs take none):
//   "arms": { "on": { "branch": "remote/<client>/x-on", "sha": "<40 hex>", "states": true, "ours": { "X": true } }, ... }.
//   No worktree or --build. An arm may name its own `build` (the stamp lineup_check expects, default the spec's): the
//   stamp file bots/FunLib/humaniser/build_info.lua is git-ignored, so build the arm's tree, `git add -f` that file, commit
//   and push; the stamp is then `<parent sha>+dirty` (two arms built from different trees carry different stamps). A game's game.log is saved to ~/.dotactl/logs/<time>-<label>.log
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
const { decide } = require('./decide');

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

/** "M:SS" for the server (it accepts no bare seconds). */
function clock(until) {
    const t = seconds(until);
    return `${Math.floor(t / 60)}:${String(t % 60).padStart(2, '0')}`;
}

/** The remote job body for one game: the arm's pushed commit, the lineup seed and the spec's clock. */
function remoteJob(spec, game) {
    const arm = spec.arms[game.arm];
    return { branch: arm.branch, sha: arm.sha, until: clock(spec.until), seed: game.seed, timescale: spec.timescale || 8, label: game.label };
}

/** A curfew on the host ends the job failed with dotactl's own wording (dotactl.js curfewError). */
const CURFEW = /closed by the user/i;

/**
 * Runs one game on the remote host; resolves to { ok, log, out, curfew }. Polls every `poll` ms (the server cannot
 * notify); `maxBadPolls` answers in a row without a job state (an HTTP error, an unreachable host) give up on the game.
 * `fetchFn`/`sleepFn` are for tests.
 */
async function runRemote(cfg, spec, game, { poll = 30000, maxBadPolls = 20, fetchFn = fetch, sleepFn = sleep, logs = path.join(os.homedir(), '.dotactl', 'logs') } = {}) {
    const H = { Authorization: `Bearer ${cfg.token}`, 'Content-Type': 'application/json' };
    const json = async r => { try { return await r.json(); } catch (e) { return {}; } };
    let r, job;
    try {
        r = await fetchFn(`${cfg.host}/jobs`, { method: 'POST', headers: H, body: JSON.stringify(remoteJob(spec, game)) });
        job = await json(r);
    } catch (e) {
        return { ok: false, out: `submit failed: ${e.message}` };
    }
    if (!r.ok || !job.id) return { ok: false, out: `submit ${r.status} ${job.error || ''}`.trim() };
    let j = job, bad = 0;
    while (!['done', 'failed', 'cancelled'].includes(j.state)) {
        await sleepFn(poll);
        try {
            const q = await fetchFn(`${cfg.host}/jobs/${job.id}`, { headers: H });
            const v = await json(q);
            if (q.ok && v.state) { j = v; bad = 0; continue; }
        } catch (e) { /* counted below */ }
        if (++bad >= maxBadPolls) return { ok: false, out: `job ${job.id}: no state in ${bad} polls` };
    }
    const out = `job ${job.id} ${j.state} ${j.reason || ''}`.trim();
    if (j.state !== 'done') return { ok: false, out, curfew: CURFEW.test(j.reason || '') };
    const g = await fetchFn(`${cfg.host}/jobs/${job.id}/files/game.log`, { headers: H });
    if (!g.ok) return { ok: false, out: `${out}; game.log ${g.status}` };
    const stamp = new Date().toISOString().replace(/:/g, '-').replace(/\..*/, '');
    fs.mkdirSync(logs, { recursive: true });
    const log = path.join(logs, `${stamp}-${game.label}.log`);
    fs.writeFileSync(log, Buffer.from(await g.arrayBuffer()));
    return { ok: true, log, out };
}

const erPath = spec => (path.isAbsolute(spec.er) ? spec.er : path.resolve(__dirname, '../..', spec.er));

/** decide.js on the manifest so far: the ER spec's bars on the valid games, against the look and the maximum N. */
function judge(spec, manifest, games) {
    const { loadGames, validGames, barResults } = require('./er');
    const { noiseTable } = require('./nf');
    const er = JSON.parse(fs.readFileSync(erPath(spec), 'utf8'));
    const all = loadGames(manifest);
    const { used } = validGames(all, er);
    const count = arm => all.filter(g => g.arm === arm).length;
    const table = used.some(g => g.arm === 'on') && used.some(g => g.arm === 'off') ? noiseTable(used, spec.n || 5) : undefined;
    const max = games.filter(g => g.arm === 'on').length;
    return decide(barResults(er, used, table), { on: count('on'), off: count('off'), look: spec.look, max });
}

/**
 * Whether the batch stops before its next game. Judged once both arms have a game; an error while judging is printed and the
 * batch goes on, since judging must never be what stops a batch (review 2026-10-30 eval-cost cc9740e M2).
 */
function decided(spec, manifest, games, judgeFn = judge) {
    const ok = readManifest(manifest);
    if (!spec.er || !ok.some(g => g.arm === 'on') || !ok.some(g => g.arm === 'off')) return false;
    let d;
    try { d = judgeFn(spec, manifest, games); } catch (e) {
        console.log(`decide: error ${e.message}; going on`);
        return false;
    }
    console.log(`decide: ${d.reason}`);
    return d.stop;
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
    if (spec.er !== undefined) {
        // A wrong ER spec path would otherwise surface only after the first pair of games.
        try { JSON.parse(fs.readFileSync(erPath(spec), 'utf8')); } catch (e) {
            console.error(`spec er: ${erPath(spec)} is missing or not JSON (relative to the bot repo root)`);
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
    let cfg;
    if (spec.remote) {
        // A parse error would quote the file (the token) on stderr: report only that it is not JSON.
        try { cfg = JSON.parse(fs.readFileSync(path.join(os.homedir(), '.dotactl', 'remote-client.json'), 'utf8')); } catch (e) {
            console.error('~/.dotactl/remote-client.json is missing or not JSON ({ "host", "token", "client" })');
            process.exit(2);
        }
    }
    fs.mkdirSync(BATCHES, { recursive: true });
    if (!fs.existsSync(manifest)) fs.writeFileSync(manifest, '');
    const done = () => new Set(readManifest(manifest).map(g => g.label));
    let built = false;
    for (const game of games) {
        if (done().has(game.label)) continue;
        // On resume and after every game; a look is only checked when the arms are level, so mid-pair it never stops.
        if (decided(spec, manifest, games)) break;
        for (let attempt = 1; ; attempt++) {
            if (cfg) {
                const rr = await runRemote(cfg, spec, game);
                fs.writeFileSync(path.join(BATCHES, `${spec.name}-last.out`), rr.out);
                if (rr.ok) {
                    fs.appendFileSync(manifest, manifestLine('ok', game, `log="${rr.log}"`) + '\n');
                    console.log(`ok ${game.label} ${rr.out}`);
                    break;
                }
                if (rr.curfew) {
                    console.log('curfew: stopping');
                    process.exit(3);
                }
                fs.appendFileSync(manifest, manifestLine('fail', game, `remote="${rr.out.replace(/"/g, "'")}" attempt=${attempt}`) + '\n');
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

module.exports = { plan, runArgs, seconds, remoteJob, runRemote, judge, decided };
