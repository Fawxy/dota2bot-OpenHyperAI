// Before/after comparison of humaniser builds from console logs: per-position laning metrics (metrics.js) with
// mean, sd and n per build, the delta, and a noisy flag when the delta is under two pooled standard errors.
'use strict';

const fs = require('fs');
const path = require('path');
const { parseLog } = require('./parse');
const { laningMetrics } = require('./metrics');
const { table } = require('./report');
const { parseTime, LOG_DIR } = require('./analyse');

const USAGE = `usage: node tools/hlog/compare.js [--until 10:00] (--dir <dir> --builds <base>,<cand> | --base <log...> --cand <log...>)

  --dir D --builds A,B   every game in D's console.*.log files whose bot build is A (base) or B (candidate)
  --base L... --cand L...  every game in the given logs, labelled base or candidate whatever their build
  --until T              laning window end (default 10:00); games that do not reach it are skipped
  --dir defaults to ${LOG_DIR}`;

const SKIP = new Set(['pid', 'hero', 'team', 'pos', 'retreatBy']);

function stats(xs) {
    const n = xs.length;
    if (n === 0) return { n, mean: undefined, sd: undefined };
    const mean = xs.reduce((a, b) => a + b, 0) / n;
    const sd = n > 1 ? Math.sqrt(xs.reduce((a, x) => a + (x - mean) ** 2, 0) / (n - 1)) : 0;
    return { n, mean, sd };
}

/** Flattened numeric metrics of one bot: retreatBy.<source> become retreatBy:<source>. */
function flat(bot) {
    const out = {};
    for (const [k, v] of Object.entries(bot)) if (!SKIP.has(k) && typeof v === 'number') out[k] = v;
    for (const [src, v] of Object.entries(bot.retreatBy || {})) out[`retreatBy:${src}`] = v;
    return out;
}

/**
 * Rows { metric, pos, base, cand, delta, noisy } over the complete games whose build is `base` or `cand`. A metric a
 * bot did not report counts as 0 for it (a retreat source that never fired).
 */
function compareGames(games, { base, cand, until = 600, label } = {}) {
    const samples = { base: [], cand: [] };
    for (const g of games) {
        const m = laningMetrics(g, { until });
        if (!m.complete) continue;
        const arm = label ? label(g) : m.build === base ? 'base' : m.build === cand ? 'cand' : undefined;
        if (arm === undefined) continue;
        for (const b of m.bots) samples[arm].push({ pos: b.pos, values: flat(b) });
    }
    const metrics = new Set();
    const positions = new Set();
    for (const arm of ['base', 'cand']) for (const s of samples[arm]) {
        positions.add(s.pos);
        for (const k of Object.keys(s.values)) metrics.add(k);
    }
    const rows = [];
    for (const metric of [...metrics].sort()) {
        for (const pos of [...positions].sort()) {
            const pick = arm => samples[arm].filter(s => s.pos === pos).map(s => s.values[metric] || 0);
            const b = stats(pick('base'));
            const c = stats(pick('cand'));
            if (b.n === 0 || c.n === 0) {
                rows.push({ metric, pos, base: b, cand: c, delta: undefined, noisy: true });
                continue;
            }
            const delta = c.mean - b.mean;
            const se = Math.sqrt(b.sd ** 2 / b.n + c.sd ** 2 / c.n);
            rows.push({ metric, pos, base: b, cand: c, delta, noisy: se > 0 ? Math.abs(delta) < 2 * se : delta === 0 });
        }
    }
    return rows;
}

function fmt(s) {
    return s.mean === undefined ? '-' : `${s.mean.toFixed(1)}±${s.sd.toFixed(1)} (${s.n})`;
}

function render(rows) {
    const out = [['metric', 'pos', 'base', 'cand', 'delta', '']];
    for (const r of rows) out.push([r.metric, r.pos === undefined ? '?' : r.pos, fmt(r.base), fmt(r.cand), r.delta === undefined ? '-' : r.delta.toFixed(1), r.noisy ? 'noisy' : '']);
    return table(out);
}

function gamesIn(files) {
    return files.flatMap(f => parseLog(fs.readFileSync(f, 'utf8')));
}

function main(argv) {
    const opts = { base: [], cand: [] };
    let list;
    for (let i = 0; i < argv.length; i++) {
        const a = argv[i];
        if (a === '--help' || a === '-h') opts.help = true;
        else if (a === '--dir') opts.dir = argv[++i];
        else if (a === '--builds') opts.builds = argv[++i];
        else if (a === '--until') opts.until = parseTime(argv[++i]);
        else if (a === '--base' || a === '--cand') list = opts[a.slice(2)];
        else if (list) list.push(a);
    }
    if (opts.help) {
        console.log(USAGE);
        return 0;
    }
    const until = opts.until !== undefined ? opts.until : 600;
    let rows;
    if (opts.builds) {
        const [base, cand] = opts.builds.split(',');
        const dir = opts.dir || LOG_DIR;
        const files = fs.readdirSync(dir).filter(f => /^console\..*\.log$/.test(f)).map(f => path.join(dir, f));
        rows = compareGames(gamesIn(files), { base, cand, until });
    } else if (opts.base.length > 0 && opts.cand.length > 0) {
        const baseGames = new Set(gamesIn(opts.base));
        const all = [...baseGames, ...gamesIn(opts.cand)];
        rows = compareGames(all, { until, label: g => (baseGames.has(g) ? 'base' : 'cand') });
    } else {
        console.error(USAGE);
        return 2;
    }
    console.log(render(rows));
    return 0;
}

if (require.main === module) process.exit(main(process.argv.slice(2)));

module.exports = { compareGames, render, main };
