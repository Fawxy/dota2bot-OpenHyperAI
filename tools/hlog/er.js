// ER generator: the number tables of an Eval Report from a batch manifest, as markdown (template: master
// docs/templates/eval-report.md). The main loop adds the verdict, threats and reading; every number comes from here.
// Usage: node er.js <manifest> [--spec <er-spec.json>] [--n 5] [--out <file.md>]
//
// Sections: arms (from the logs), validity (lineup_check, when the spec names build and arms), health per game, snapshot gaps,
// metric deltas (nf.js, pooled over seeds; per seed with --per-seed), the nf.js gate, G monitors and the spec's bars.
// Spec (`er-spec/1`): { "schema": "er-spec/1", "build": "b2d2ba9", "arms": {<lineup_check arms>}, "until": "20:00",
//   "bars": [ { "id", "metric", "rule": "each" | "mean" | "delta", ... } ] }
//   each:  every game of `arms` (default ["on"]) within `min`/`max`/`eq` on a per-game metric (health keys or nf.js keys).
//   mean:  `cmp` "on<=off" or "on>=off" on the per-arm means of a per-game metric.
//   delta: pooled ON-OFF 95% CI of an nf.js metric; `met` and optional `notMet` are conditions on lo/hi/delta, e.g.
//          { "lo": { "gt": -5 } }. Neither true: inconclusive (only when notMet is given; else not met).
'use strict';

const fs = require('fs');
const path = require('path');
const { readManifest } = require('./manifest');
const { parseLog } = require('./parse');
const { runChecks } = require('./checks');
const { nfGame, noiseTable, stats } = require('./nf');
const { checkGame } = require('./lineup_check');
const { describe } = require('./bank');

const SNAP_GAP = 3; // s; a longer gap is a death (Dota runs no script for a dead bot) or a stall

/** Health counts from a log's raw lines. `ev=lua_error` counts the highest n= per (pid, where, msg): n is a running count per
 *  bot script state, so it is uncensored where the console line is squelched. */
function health(text) {
    const maxN = {};
    const h = { lua_ours: 0, lua_oha: 0, console: 0, squelch: 0, bundle_ok: 0, bundle_fail: 0, sites: {} };
    let prevErr = false;
    const field = (l, k) => {
        const m = l.match(new RegExp(` ${k}=("([^"]*)"|\\S+)`));
        return m ? (m[2] !== undefined ? m[2] : m[1]) : undefined;
    };
    for (const l of text.split(/\r?\n/)) {
        const isErr = /Script Runtime Error/.test(l);
        if (isErr) h.console++;
        if (/Message count limit/.test(l) && prevErr) h.squelch++;
        if (/\[VScript\]/.test(l)) prevErr = isErr;
        if (/\[H:tasks\] support .*bundle=ok/.test(l)) h.bundle_ok++;
        if (/bundle=fail/.test(l)) h.bundle_fail++;
        if (/\[HEV\].* ev=lua_error /.test(l)) {
            const key = [field(l, 'pid'), field(l, 'where'), field(l, 'msg')].join('|');
            maxN[key] = Math.max(maxN[key] || 0, Number(field(l, 'n')) || 1);
        }
    }
    for (const [key, n] of Object.entries(maxN)) {
        const where = key.split('|')[1];
        if (/^oha\./.test(where)) h.lua_oha += n;
        else h.lua_ours += n;
        h.sites[where] = (h.sites[where] || 0) + n;
    }
    return h;
}

/** Snapshot gaps over SNAP_GAP s per bot, split by whether the bot's deaths counter rose across the gap, and bots whose
 *  snapshots stop before the end, with whether the enemy team's summed kills rose after their last one. */
function gaps(game) {
    const out = { gaps: 0, withDeath: 0, other: [], early: [] };
    const bots = Object.values(game.bots).filter(b => !b.human && b.snaps.length);
    const end = Math.max(...bots.map(b => b.snaps[b.snaps.length - 1].t));
    const killsAt = (team, t) => bots.filter(b => b.team !== team).reduce((a, b) => {
        const s = b.snaps.filter(x => x.t <= t && typeof x.kills === 'number').pop();
        return a + (s ? s.kills : 0);
    }, 0);
    for (const b of bots) {
        for (let i = 1; i < b.snaps.length; i++) {
            const g = b.snaps[i].t - b.snaps[i - 1].t;
            if (g <= SNAP_GAP) continue;
            out.gaps++;
            if (b.snaps[i].deaths === b.snaps[i - 1].deaths + 1) out.withDeath++;
            else out.other.push(`${b.hero}[${b.pid}] ${g.toFixed(1)} s from t=${b.snaps[i - 1].t.toFixed(0)}`);
        }
        const last = b.snaps[b.snaps.length - 1];
        if (last.t < end - SNAP_GAP) {
            const rose = killsAt(b.team, end) > killsAt(b.team, last.t);
            out.early.push(`${b.hero}[${b.pid}] last t=${last.t.toFixed(0)} hp=${last.hp}, enemy kills ${rose ? 'rose' : 'did not rise'} after`);
        }
    }
    return out;
}

const f1 = x => (Number.isFinite(x) ? x.toFixed(1) : '-');
const row = cells => `| ${cells.join(' | ')} |`;
const head = cells => `${row(cells)}\n${row(cells.map(() => '---'))}`;
const ARM_ORDER = arms => [...new Set(arms)].sort((a, b) => (a === 'off' ? 1 : b === 'off' ? -1 : a.localeCompare(b)));

function cond(c, r) {
    return Object.entries(c).every(([k, ops]) => Object.entries(ops).every(([op, v]) =>
        ({ lt: r[k] < v, le: r[k] <= v, gt: r[k] > v, ge: r[k] >= v })[op]));
}

/** One bar's value and result over the games and the noise table. */
function bar(b, games, table) {
    const val = (g, k) => (g.health[k] !== undefined ? g.health[k] : g.flat[k]);
    if (b.rule === 'each') {
        const arms = b.arms || ['on'];
        const sel = games.filter(g => arms.includes(g.arm));
        // No game of the bar's arms (a typo, or a batch without that arm) is a missing value, never a pass.
        if (!sel.length) return { value: `no games of arm ${arms.join('+')}`, result: 'not met' };
        const bad = sel.filter(g => {
            const v = val(g, b.metric);
            return !(Number.isFinite(v) && (b.max === undefined || v <= b.max) && (b.min === undefined || v >= b.min) && (b.eq === undefined || v === b.eq));
        });
        const value = bad.length ? `${sel.length - bad.length}/${sel.length} games; ${bad.map(g => `${g.label} ${val(g, b.metric)}`).join(', ')}` : `${sel.length}/${sel.length} games`;
        return { value, result: bad.length ? 'not met' : 'met' };
    }
    if (b.rule === 'mean') {
        const m = arm => stats(games.filter(g => g.arm === arm).map(g => val(g, b.metric))).mean;
        const on = m('on'), off = m('off');
        // NaN (an arm with no games or no values) compares false either way, so it is not met.
        const ok = b.cmp === 'on>=off' ? on >= off : on <= off;
        return { value: `ON ${f1(on)}, OFF ${f1(off)}`, result: ok ? 'met' : 'not met' };
    }
    const r = table[b.metric] && table[b.metric].all;
    if (!r) return { value: 'no such nf.js metric', result: 'not met' };
    const value = `${r.delta >= 0 ? '+' : ''}${f1(r.delta)} [${f1(r.lo)}, ${f1(r.hi)}]`;
    if (cond(b.met, r)) return { value, result: 'met' };
    if (b.notMet) return { value, result: cond(b.notMet, r) ? 'not met' : 'inconclusive' };
    return { value, result: 'not met' };
}

const G_MONITORS = [
    ['encounters before 10:00', g => g.flat.encounters_before10],
    ['encounters per 10 min after 10:00', g => g.flat.encounters_per_10min_after10],
    ['fights before 10:00', g => g.flat.fights_before10],
    ['fights per 10 min after 10:00', g => g.flat.fights_per_10min_after10],
    ['deaths before 10:00 (both teams)', g => g.flat.deaths_before_10],
    ['first T1 (s)', g => g.monitors.first_t1_time],
    ['first Roshan (s)', g => g.monitors.first_roshan_time],
];
const G_MISSING = ['lane equilibrium', 'lane presence', 'gold gap', 'lead changes'];

function report(manifest, { spec = {}, n = 5, perSeed = false } = {}) {
    const games = readManifest(manifest).map(g => {
        const text = fs.readFileSync(g.log, 'utf8');
        const parsed = parseLog(text);
        const game = parsed[parsed.length - 1];
        const checks = Object.fromEntries(runChecks(game).map(c => [c.id, c]));
        return { ...nfGame(g, game), facts: describe(text), health: health(text), gaps: gaps(game), checks, text };
    });
    const arms = ARM_ORDER(games.map(g => g.arm));
    const out = [];
    out.push(`<!-- generated by tools/hlog/er.js from ${path.basename(manifest)}; numbers only -->`);

    out.push('\n## Arms\n' + head(['arm', 'build', 'Dota build', '--set', 'games (N)', 'lineups', 'until', 'timescale']));
    for (const arm of arms) {
        const a = games.filter(g => g.arm === arm);
        const uniq = k => [...new Set(a.map(g => g.facts[k]))].join(', ');
        const lineups = [...new Set(a.map(g => g.lineup))].map(l => `${l} ${a.filter(g => g.lineup === l).length}`).join(', ');
        out.push(row([arm.toUpperCase(), uniq('build'), uniq('patch'), uniq('set') || 'none', a.length, lineups, uniq('until'), uniq('timescale')]));
    }

    out.push('\n## Validity');
    // Games failing lineup_check stay in the health and gap tables (they show what happened) and leave the deltas, gate,
    // G monitors and bars.
    let used = games;
    if (spec.build && spec.arms) {
        const until = spec.until ? require('./batch').seconds(spec.until) : 1200;
        const bad = games.map(g => [g.label, checkGame(g.text, { lineup: g.lineup, arm: g.arm, build: spec.build, until, arms: spec.arms })]).filter(([, p]) => p.length);
        out.push(`lineup_check (build ${spec.build}): ${games.length - bad.length}/${games.length} ok` + bad.map(([l, p]) => `\n- ${l}: ${p.join('; ')}`).join(''));
        if (bad.length) out.push(`Excluded from deltas, gate, G monitors and bars: ${bad.map(([l]) => l).join(', ')}.`);
        used = games.filter(g => !bad.some(([l]) => l === g.label));
    } else out.push('lineup_check not run: the spec names no build and arms.');

    out.push('\n## Health\n' + head(['game', 'arm', 'our `lua_error`', '`oha.*` max n', 'console `Script Runtime Error`', 'squelch', '`bundle=ok` / `fail`', 'hlog `snapshot_gaps`', '`frozen_bots` warn', 'hlog `intent_health`']));
    for (const g of games) {
        const c = g.checks, h = g.health;
        const frozen = c.frozen_bots.level === 'warn' ? c.frozen_bots.details.length + c.frozen_bots.more : 0;
        out.push(row([g.label, g.arm.toUpperCase(), h.lua_ours, h.lua_oha, h.console, h.squelch, `${h.bundle_ok} / ${h.bundle_fail}`,
            c.snapshot_gaps.level.toUpperCase(), frozen, c.intent_health.level === 'pass' ? 'PASS' : c.intent_health.summary.split(';')[0]]));
    }
    out.push('');
    for (const arm of arms) {
        const a = games.filter(g => g.arm === arm);
        const m = k => f1(stats(a.map(g => g.health[k])).mean);
        out.push(`- ${arm.toUpperCase()} (N=${a.length}): mean our \`lua_error\` ${m('lua_ours')}, \`oha.*\` ${m('lua_oha')}, console ${m('console')}; ` +
            `games with a squelch after an error ${a.filter(g => g.health.squelch).length}; \`idle_10s\` mean over games ${f1(stats(a.map(g => g.flat.idle_10s)).mean)} ` +
            `(SD ${f1(stats(a.map(g => g.flat.idle_10s)).sd)})`);
    }
    const sites = {};
    for (const g of games) for (const [w, k] of Object.entries(g.health.sites)) (sites[w] = sites[w] || []).push(`${g.label} ${k}`);
    for (const [w, l] of Object.entries(sites)) out.push(`- \`lua_error where=${w}\`: ${l.join(', ')}`);

    const G = games.map(g => g.gaps);
    out.push(`\n## Snapshot gaps\nGaps over ${SNAP_GAP} s: ${G.reduce((a, x) => a + x.gaps, 0)} in ${games.length} games; ` +
        `${G.reduce((a, x) => a + x.withDeath, 0)} end with the bot's \`deaths\` up by one.`);
    for (const g of games) {
        for (const o of g.gaps.other) out.push(`- ${g.label}: no death: ${o}`);
        for (const e of g.gaps.early) out.push(`- ${g.label}: stops early: ${e}`);
    }

    const table = arms.includes('on') && arms.includes('off') ? noiseTable(used, n) : undefined;
    if (table) {
        out.push(`\n## Metric deltas, pooled over seeds (nf.js; N per arm in the OFF/ON n columns)\n` +
            head(['metric', 'OFF mean', 'OFF SD', 'ON mean', 'ON-OFF', '95% CI', `MDE (N=${n} per seed)`]));
        for (const [k, r] of Object.entries(table)) out.push(row([k, f1(r.all.off.mean), f1(r.all.off.sd), f1(r.all.on.mean), f1(r.all.delta), `${f1(r.all.lo)} to ${f1(r.all.hi)}`, f1(r.all.mde)]));
        if (perSeed) {
            out.push('\n### Per seed\n' + head(['metric', 'seed', 'OFF mean', 'OFF SD', 'n', 'ON mean', 'ON-OFF', '95% CI']));
            for (const [k, by] of Object.entries(table)) for (const [s, r] of Object.entries(by)) if (s !== 'all') out.push(row([k, s, f1(r.off.mean), f1(r.off.sd), r.off.n, f1(r.on.mean), f1(r.delta), `${f1(r.lo)} to ${f1(r.hi)}`]));
        }
    } else out.push('\n## Metric deltas\nNot computed: the manifest lacks an ON or an OFF arm.');

    const flagged = used.filter(g => g.problems.length);
    out.push(`\n## nf.js gate\n${used.length - flagged.length}/${used.length} ok` + flagged.map(g => `\n- ${g.label}: ${g.problems.join('; ')}`).join(''));

    out.push('\n## G monitors (no bar)\n' + head(['monitor', ...arms.map(a => `${a.toUpperCase()} mean [min, max]`), 'note']));
    for (const [name, f] of G_MONITORS) {
        const per = arms.map(a => used.filter(g => g.arm === a).map(f).filter(Number.isFinite));
        const cells = per.map(v => (v.length ? `${f1(stats(v).mean)} [${f1(Math.min(...v))}, ${f1(Math.max(...v))}] (${v.length})` : '-'));
        const off = per[arms.indexOf('off')], on = per[arms.indexOf('on')];
        let note = '';
        if (off && on && off.length && on.length) {
            const m = stats(on).mean;
            if (m < Math.min(...off) || m > Math.max(...off)) note = 'ON mean outside OFF range';
        }
        out.push(row([name, ...cells, note]));
    }
    out.push(`No metric yet: ${G_MISSING.join(', ')}.`);

    if (spec.bars && spec.bars.length) {
        out.push('\n## Bar results (pre-registered)\n' + head(['id', 'metric', 'rule', 'value', 'result']));
        for (const b of spec.bars) {
            const r = b.rule === 'delta' && !table ? { value: 'no paired arms', result: 'not met' } : bar(b, used, table || {});
            const rule = b.rule === 'delta' ? `delta: met ${JSON.stringify(b.met)}${b.notMet ? `, not met ${JSON.stringify(b.notMet)}` : ''}`
                : b.rule === 'mean' ? `mean ${b.cmp}` : `each ${(b.arms || ['on']).join('+')} ${['min', 'max', 'eq'].filter(k => b[k] !== undefined).map(k => `${k} ${b[k]}`).join(' ')}`;
            out.push(row([b.id, `\`${b.metric}\``, rule, r.value, `**${r.result}**`]));
        }
    }
    return out.join('\n') + '\n';
}

function main(argv) {
    const opt = k => (argv.includes(`--${k}`) ? argv[argv.indexOf(`--${k}`) + 1] : undefined);
    if (!argv[0]) {
        console.error('usage: node er.js <manifest> [--spec <er-spec.json>] [--n 5] [--per-seed] [--out <file.md>]');
        process.exit(2);
    }
    const spec = opt('spec') ? JSON.parse(fs.readFileSync(opt('spec'), 'utf8')) : {};
    const md = report(argv[0], { spec, n: Number(opt('n') || 5), perSeed: argv.includes('--per-seed') });
    if (opt('out')) fs.writeFileSync(opt('out'), md);
    else process.stdout.write(md);
}

if (require.main === module) main(process.argv.slice(2));

module.exports = { report, health, gaps, bar, cond };
