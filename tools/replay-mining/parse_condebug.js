'use strict';
// node parse_condebug.js <console.log>

const fs = require('fs');
const { median } = require('./detect');

const MIN_ATTEMPTS = 5;
const MIN_OK_RATE = 0.8;
const LINE = /\[H:lane\]\s+(job|stack)\s+(.*)$/;

function parseFields(rest) {
    const f = {};
    for (const tok of rest.trim().split(/\s+/)) {
        const i = tok.indexOf('=');
        if (i > 0) f[tok.slice(0, i)] = tok.slice(i + 1);
    }
    return f;
}

function suggest(g, okAggro) {
    const a = median(okAggro);
    const round = (v) => Number(v.toFixed(1));
    if (g.kind === 'stack') return `{ stackAggroSec: ${round(a)}, source: "measured" }  // camp ${g.camp}`;
    const s = ((a % 30) + 30) % 30;
    const field = g.kind === 'half' ? 'halfAggroSec' : 'pullAggroSec';
    const key = g.key ? `key: "${g.key}", ` : '';
    return `{ ${key}${field}: [${round(s)}, ${round(s + 30)}], source: "measured" }  // camp ${g.camp}, kind ${g.kind}`;
}

function summarise(lines) {
    const groups = new Map();
    for (const line of lines) {
        const m = LINE.exec(line);
        if (!m) continue;
        const f = parseFields(m[2]);
        const kind = m[1] === 'stack' ? 'stack' : f.kind;
        if (kind === undefined || f.camp === undefined) continue;
        const id = `${f.camp}|${kind}`;
        if (!groups.has(id)) groups.set(id, { camp: Number(f.camp), kind, key: undefined, attempts: 0, ok: 0, errors: [], okAggro: [] });
        const g = groups.get(id);
        if (f.key && f.key !== '-') g.key = f.key;
        const aggro = Number(f.aggro);
        const planned = Number(f.planned);
        g.attempts++;
        if (Number.isFinite(aggro) && Number.isFinite(planned)) g.errors.push(aggro - planned);
        if (f.grade === 'ok') {
            g.ok++;
            if (Number.isFinite(aggro)) g.okAggro.push(aggro);
        }
    }
    return [...groups.values()]
        .sort((a, b) => a.camp - b.camp || a.kind.localeCompare(b.kind))
        .map((g) => {
            const successRate = g.ok / g.attempts;
            const eligible = g.attempts >= MIN_ATTEMPTS && successRate >= MIN_OK_RATE && g.okAggro.length > 0;
            return {
                camp: g.camp,
                kind: g.kind,
                attempts: g.attempts,
                ok: g.ok,
                successRate,
                medianAggroError: median(g.errors),
                suggestion: eligible ? suggest(g, g.okAggro) : undefined,
            };
        });
}

if (require.main === module) {
    if (!process.argv[2]) {
        console.error('usage: node parse_condebug.js <console.log>');
        process.exit(1);
    }
    for (const r of summarise(fs.readFileSync(process.argv[2], 'utf8').split('\n'))) {
        const err = r.medianAggroError === undefined ? 'n/a' : r.medianAggroError.toFixed(2);
        console.log(`camp ${r.camp} ${r.kind}: ${r.ok}/${r.attempts} ok (${(r.successRate * 100).toFixed(0)}%), median aggro error ${err}s`);
        if (r.suggestion) console.log(`  suggest: ${r.suggestion}`);
    }
}

module.exports = { summarise };
