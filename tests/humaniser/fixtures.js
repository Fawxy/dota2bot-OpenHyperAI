// E1 decision-fixture runner: loads tests/fixtures/**/*.yaml, runs each active fixture's driver
// (fixture_drivers/<decision>.lua) at every skill sample, and checks the observation against `expect`.
// Schema, drivers and expectation terms: tests/fixtures/README.md.
// Usage: node fixtures.js [--root <dir with bots/>] [--json] [--controls] [fixture files or ids...]
//   --controls: run each fixture against the bots/ of its `control.commit` instead (negative control, see README).
const fs = require('fs');
const os = require('os');
const path = require('path');
const { execSync } = require('child_process');
const YAML = require('yaml');
const { newState, doFile, doString, getGlobal } = require('./harness');

const FIXTURE_DIR = path.resolve(__dirname, '../fixtures');
const DRIVER_DIR = path.join(__dirname, 'fixture_drivers');
const REQUIRED = ['id', 'source', 'ref', 'status', 'decision', 'world', 'expect'];
const SOURCES = ['replay', 'log', 'playtest', 'evidence-card'];
const STATUSES = ['active', 'quarantined', 'retired'];
// Each driver's action verbs (tests/fixtures/README.md). A term with another verb is a schema error, so a misspelled
// verb in mustNot cannot pass by never matching.
const VERBS = {
    laning_mode: ['lastHit', 'deny', 'hold', 'move', 'attempt'],
    team_roam: ['lastHit', 'deny', 'hold', 'move', 'attempt'],
    retreat_desire: [],
    lane_prethink: ['attack', 'move', 'commit'],
    kill_check: ['kill', 'noKill'],
    lane_fight: ['commitEnd', 'committing'],
    core_trip: ['noTrip', 'trip'],
};

function listFixtures(dir) {
    if (!fs.existsSync(dir)) return [];
    return fs.readdirSync(dir, { withFileTypes: true }).flatMap(e => {
        const p = path.join(dir, e.name);
        if (e.isDirectory()) return listFixtures(p);
        return /\.ya?ml$/.test(e.name) ? [p] : [];
    });
}

// Expectation terms. An action term `verb` or `verb(target)` holds when some observed action matches. A comparison
// `<value> <op> <value>` compares numbers, where a value is a number literal, `desire.<mode>` or `fact.<name>`.
const CMP = /^\s*([\w.#-]+)\s*(<=|>=|==|!=|<|>)\s*([\w.#-]+)\s*$/;
const ACTION = /^\s*(\w+)(?:\(([^)]*)\))?\s*$/;

/** Schema problems for one parsed fixture (empty when valid). */
function validate(fx) {
    const p = [];
    for (const k of REQUIRED) if (fx[k] === undefined) p.push(`missing ${k}`);
    if (fx.source !== undefined && !SOURCES.includes(fx.source)) p.push(`source ${fx.source} not in ${SOURCES.join('|')}`);
    if (fx.status !== undefined && !STATUSES.includes(fx.status)) p.push(`status ${fx.status} not in ${STATUSES.join('|')}`);
    if (fx.status === 'retired' && !fx.reason) p.push('retired without a reason');
    if (fx.decision && !fs.existsSync(path.join(DRIVER_DIR, `${fx.decision}.lua`))) p.push(`no driver ${fx.decision}`);
    if (fx.expect && !fx.expect.must && !fx.expect.mustNot) p.push('expect has neither must nor mustNot');
    if (fx.control && !(/^[0-9a-f]{7,40}$/.test(fx.control.commit || '') && ['pass', 'fail'].includes(fx.control.outcome)))
        p.push('control needs {commit: <sha>, outcome: pass|fail}');
    const sk = fx.conditions && fx.conditions.skill;
    if (Array.isArray(sk) && !(sk.length === 2 && sk.every(x => typeof x === 'number' && x >= 0 && x <= 1) && sk[0] <= sk[1]))
        p.push('conditions.skill must be [lo, hi] within 0-1');
    const verbs = VERBS[fx.decision];
    for (const t of [...((fx.expect && fx.expect.must) || []), ...((fx.expect && fx.expect.mustNot) || [])]) {
        if (CMP.test(t)) continue;
        const m = String(t).match(ACTION);
        if (!m) p.push(`cannot parse term "${t}"`);
        else if (verbs && !verbs.includes(m[1])) p.push(`verb ${m[1]} is not one of ${fx.decision}'s (${verbs.join(', ') || 'none'})`);
    }
    return p;
}

/** Skill samples: [lo, hi] gives lo, the midpoint and hi; a number gives itself; none gives one run at the default. */
function skills(fx) {
    const s = fx.conditions && fx.conditions.skill;
    if (Array.isArray(s)) return [...new Set([s[0], (s[0] + s[1]) / 2, s[1]])];
    if (typeof s === 'number') return [s];
    return [null];
}

/** JSON value as a Lua literal. */
function toLua(v) {
    if (v === null || v === undefined) return 'nil';
    if (typeof v === 'boolean') return String(v);
    if (typeof v === 'number') return Number.isFinite(v) ? String(v) : 'nil';
    // Lua decimal escapes for anything outside printable ASCII, and for quote and backslash.
    if (typeof v === 'string') return luaString(v);
    if (Array.isArray(v)) return `{${v.map(toLua).join(', ')}}`;
    return `{${Object.entries(v).map(([k, x]) => `[${luaString(k)}] = ${toLua(x)}`).join(', ')}}`;
}

/** A Lua string literal: UTF-8 bytes, with decimal escapes for anything outside printable ASCII and for " and \. */
function luaString(s) {
    const bytes = Buffer.from(String(s), 'utf8').toString('latin1');
    return `"${bytes.replace(/[^\x20-\x7e]|["\\]/g, c => '\\' + c.charCodeAt(0))}"`;
}

/** Runs the driver once. Returns { obs } or { error }. */
function observe(fx, skill, root) {
    const L = newState(root);
    let err = doString(L, `FIXTURE = ${toLua(fx)}\nSKILL = ${skill === null ? 'nil' : skill}\n`);
    if (err === null) err = doFile(L, path.join(__dirname, 'fixture_run.lua'));
    if (err !== null) return { error: err };
    try {
        return { obs: JSON.parse(getGlobal(L, 'OBS_JSON')) };
    } catch (e) {
        return { error: `observation is not JSON: ${e.message}` };
    }
}

function value(tok, obs) {
    if (/^-?\d+(\.\d+)?$/.test(tok)) return Number(tok);
    const [kind, ...rest] = tok.split('.');
    const name = rest.join('.');
    const bag = kind === 'desire' ? obs.desire : kind === 'fact' ? obs.fact : undefined;
    if (!bag || !rest.length) throw new Error(`unknown value ${tok}`);
    const v = bag[name];
    if (typeof v !== 'number') throw new Error(`${tok} was not observed`);
    return v;
}

function holds(term, obs, eps) {
    const c = term.match(CMP);
    if (c) {
        const a = value(c[1], obs), b = value(c[3], obs);
        switch (c[2]) {
            case '<': return a < b - eps;
            case '<=': return a <= b + eps;
            case '>': return a > b + eps;
            case '>=': return a >= b - eps;
            case '==': return Math.abs(a - b) <= eps;
            case '!=': return Math.abs(a - b) > eps;
        }
    }
    const m = term.match(ACTION);
    if (!m) throw new Error(`cannot parse term "${term}"`);
    return (obs.actions || []).some(x => x.verb === m[1] && (m[2] === undefined || x.target === m[2].trim()));
}

/** Problems with one observation against the fixture's expect block (empty when it passes). */
function judge(fx, obs) {
    const eps = (fx.tolerance && fx.tolerance.value) ?? 1e-6;
    const out = [];
    for (const t of fx.expect.must || []) {
        try { if (!holds(t, obs, eps)) out.push(`must "${t}" failed`); } catch (e) { out.push(`must "${t}": ${e.message}`); }
    }
    for (const t of fx.expect.mustNot || []) {
        try { if (holds(t, obs, eps)) out.push(`mustNot "${t}" held`); } catch (e) { out.push(`mustNot "${t}": ${e.message}`); }
    }
    return out;
}

const describe = obs => (obs.actions || []).map(a => (a.target ? `${a.verb}(${a.target})` : a.verb)).join(' ') +
    ` ${JSON.stringify({ desire: obs.desire, fact: obs.fact })}`;

function runFixture(fx, root) {
    return skills(fx).map(skill => {
        const r = observe(fx, skill, root);
        const problems = r.error ? [`error: ${r.error}`] : judge(fx, r.obs);
        // A term on a value the driver never observed is an error too: the fixture did not reach its decision.
        const error = !!r.error || problems.some(p => /not observed|unknown value|cannot parse/.test(p));
        return { skill, error, problems, seen: r.obs ? describe(r.obs) : undefined };
    });
}

/** bots/ of `commit`, exported once into the temp directory. */
function controlRoot(commit) {
    const dir = path.join(os.tmpdir(), `fixture-control-${commit}`);
    // The marker is written after a complete extract, so an interrupted one is redone.
    if (!fs.existsSync(path.join(dir, '.complete'))) {
        fs.rmSync(dir, { recursive: true, force: true });
        fs.mkdirSync(dir, { recursive: true });
        const repo = path.resolve(__dirname, '../..');
        execSync(`git -C "${repo}" archive ${commit} bots | tar -x -C "${dir.split(path.sep).join('/')}"`, { stdio: 'inherit', shell: 'bash' });
        fs.writeFileSync(path.join(dir, '.complete'), commit);
    }
    return dir;
}

/** Negative control: each fixture with `control: {commit, outcome}` must fail on behaviour (a guard: pass) on that commit's bots/. */
function controls(fixtures, invalid) {
    let bad = invalid;
    for (const { fx } of fixtures) {
        if (!fx.control || fx.status !== 'active') continue;
        const runs = runFixture(fx, controlRoot(fx.control.commit));
        const passed = runs.every(r => !r.problems.length);
        // A bug fixture must fail on behaviour: failing by error proves only that the old code lacked something.
        const errored = runs.some(r => r.error);
        const ok = fx.control.outcome === 'pass' ? passed : !passed && !errored;
        const how = passed ? 'passes' : runs.some(r => r.error) ? 'fails (by error)' : 'fails';
        if (!ok) bad++;
        console.log(`${ok ? 'ok  ' : 'BAD '} ${fx.id}: ${how} at ${fx.control.commit}, expected ${fx.control.outcome}`);
    }
    console.log(`\ncontrols: ${bad ? `${bad} not as expected` : 'all as expected'}`);
    process.exit(bad ? 1 : 0);
}

function main(argv) {
    const rootAt = argv.indexOf('--root');
    const root = rootAt >= 0 ? path.resolve(argv[rootAt + 1]) : undefined;
    const json = argv.includes('--json');
    const picks = argv.filter((a, i) => !a.startsWith('--') && (rootAt < 0 || i !== rootAt + 1));
    const results = [];
    const loaded = [];
    let invalid = 0;
    for (const file of listFixtures(FIXTURE_DIR)) {
        const fx = YAML.parse(fs.readFileSync(file, 'utf8'));
        const rel = path.relative(FIXTURE_DIR, file).split(path.sep).join('/');
        if (picks.length && !picks.some(p => rel.includes(p) || fx.id === p)) continue;
        const problems = validate(fx);
        if (problems.length) {
            invalid++;
            results.push({ id: fx.id || rel, file: rel, status: 'invalid', problems });
            continue;
        }
        if (fx.status === 'retired') continue;
        loaded.push({ fx, rel });
    }
    const seen = new Map();
    for (const { fx, rel } of loaded) {
        if (seen.has(fx.id)) {
            invalid++;
            results.push({ id: fx.id, file: rel, status: 'invalid', problems: [`duplicate id (also ${seen.get(fx.id)})`] });
        } else seen.set(fx.id, rel);
    }
    if (argv.includes('--controls')) {
        for (const r of results) console.log(`INVALID ${r.file}: ${r.problems.join('; ')}`);
        return controls(loaded, invalid);
    }
    for (const { fx, rel } of loaded) {
        const runs = runFixture(fx, root);
        results.push({ id: fx.id, file: rel, status: fx.status, pass: runs.every(r => !r.problems.length), runs });
    }
    const active = results.filter(r => r.status === 'active');
    const passed = active.filter(r => r.pass).length;
    if (json) console.log(JSON.stringify({ root: root || null, results, active: active.length, passed }, null, 1));
    else {
        for (const r of results) {
            if (r.status === 'invalid') { console.log(`INVALID ${r.file}: ${r.problems.join('; ')}`); continue; }
            const tag = r.pass ? 'pass' : 'FAIL';
            console.log(`${tag.padEnd(4)} ${r.status === 'quarantined' ? '(quarantined) ' : ''}${r.id}`);
            for (const run of r.runs) {
                if (!run.problems.length) continue;
                console.log(`       skill ${run.skill ?? 'default'}: ${run.problems.join('; ')}`);
                if (run.seen) console.log(`         seen: ${run.seen}`);
            }
        }
        const rate = active.length ? ((100 * passed) / active.length).toFixed(1) : '-';
        console.log(`\nfixture_pass_rate ${passed}/${active.length} active (${rate}%)${invalid ? `; ${invalid} invalid` : ''}`);
    }
    process.exit(passed === active.length && !invalid ? 0 : 1);
}

if (require.main === module) main(process.argv.slice(2));

module.exports = { validate, skills, toLua, holds, judge };
