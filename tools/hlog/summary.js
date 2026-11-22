// `hlog.js timeline <batch> --count`: a batch's arms compared on the countable measures of the timeline, each with the noise floor
// of the reference arm (the same code on both seats). The statistics are pure (welch, verdict); the rest reads the store.
'use strict';

const fs = require('fs');
const path = require('path');

const MEASURES = [
    ['deaths', 'deaths', 'n'],
    ['kill_tries_by', 'kill tries by this side', 'n'],
    ['kill_tries_by_killed', 'share of those killed', 'share'],
    ['kill_tries_on', 'kill tries on this side', 'n'],
    ['struck_first', 'exchanges struck first', 'n'],
    ['struck_first_unanswered', 'share not answered', 'share'],
    ['retreat_secs', 'retreat seconds', 'n'],
    ['attack_secs', 'seconds attacking a hero', 'n'],
    ['attack_secs_laning', 'of those in mode laning', 'n'],
    ['near700_secs', 'seconds within 700 in a lane', 'n'],
];
// A share is the pooled-per-game ratio of its two counts, defined only for a game with a denominator.
const SHARES = { kill_tries_by_killed: ['kill_tries_by_k', 'kill_tries_by'], struck_first_unanswered: ['struck_first_u', 'struck_first'] };

/** mean, sample variance and n of a list of numbers (n >= 2 for a variance). */
function describe(xs) {
    const n = xs.length;
    const mean = n ? xs.reduce((a, b) => a + b, 0) / n : NaN;
    const variance = n > 1 ? xs.reduce((a, b) => a + (b - mean) ** 2, 0) / (n - 1) : NaN;
    return { n, mean, variance };
}

/**
 * a minus b as two means of per-game values, with the standard error Welch uses (not pooled: the two sides may spread
 * differently): sqrt(va/na + vb/nb). `ci` is 1.96 standard errors, the 95% half-width of a normal approximation.
 */
function welch(a, b) {
    const x = describe(a);
    const y = describe(b);
    const se = Math.sqrt(x.variance / x.n + y.variance / y.n);
    return { meanA: x.mean, meanB: y.mean, nA: x.n, nB: y.n, diff: x.mean - y.mean, se, ci: 1.96 * se };
}

/**
 * Whether a diff stands out from noise: `*` when its own interval excludes 0 and it lies outside the interval of the floor (the
 * reference arm's two sides compared the same way: how far identical code drifts), otherwise ''.
 */
function verdict(d, floor) {
    if (!Number.isFinite(d.ci) || !Number.isFinite(floor.ci)) return '';
    const clear = Math.abs(d.diff) > d.ci;
    const outsideFloor = d.diff > floor.diff + floor.ci || d.diff < floor.diff - floor.ci;
    return clear && outsideFloor ? '*' : '';
}

/** `pos` as the option gives it (`1-3`, `4`, `1,2,5`) into a filter: the positions as a list. */
function parsePos(s) {
    if (s === undefined) return [1, 2, 3, 4, 5];
    const out = new Set();
    for (const part of String(s).split(',')) {
        const m = part.match(/^(\d)(?:-(\d))?$/);
        if (!m) throw new Error(`--pos ${s} is no position list (1-3, 4, 1,2,5)`);
        const lo = Number(m[1]);
        const hi = Number(m[2] ?? m[1]);
        if (lo < 1 || hi > 5 || lo > hi) throw new Error(`--pos ${s}: positions are 1 to 5`);
        for (let p = lo; p <= hi; p++) out.add(p);
    }
    return [...out].sort();
}

/** One zero-filled record per game and side, from the episode rows and the hero-second sums. */
function perGame(games, eps, secs, pos, from, to) {
    const rec = new Map();
    const get = (file, side) => {
        const k = `${file}|${side}`;
        if (!rec.has(k)) rec.set(k, Object.fromEntries(['deaths', 'kill_tries_by', 'kill_tries_by_k', 'kill_tries_on', 'struck_first', 'struck_first_u',
            'retreat_secs', 'attack_secs', 'attack_secs_laning', 'near700_secs'].map(m => [m, 0])));
        return rec.get(k);
    };
    for (const g of games) for (const side of ['test', 'opp']) get(g.file, side);
    const other = s => (s === 'test' ? 'opp' : 'test');
    const mine = p => pos.includes(p);
    for (const r of eps) {
        if (r.kind === 'death' && mine(r.pos)) get(r.file, r.side).deaths++;
        else if (r.kind === 'retreat' && mine(r.pos)) get(r.file, r.side).retreat_secs += Math.max(0, Math.min(r.t1, to) - Math.max(r.t, from));
        else if (r.kind === 'exchange' && mine(r.pos)) {
            get(r.file, r.side).struck_first++;
            if (r.outcome === 'none_back') get(r.file, r.side).struck_first_u++;
        } else if (r.kind === 'kill_try') {
            if (mine(r.pos)) {
                get(r.file, r.side).kill_tries_by++;
                if (r.outcome === 'killed') get(r.file, r.side).kill_tries_by_k++;
            }
            if (mine(r.tpos)) get(r.file, other(r.side)).kill_tries_on++;
        }
    }
    const seatOf = new Map(games.map(g => [g.file, g.seat_team]));
    for (const s of secs) {
        const side = s.team === seatOf.get(s.file) ? 'test' : 'opp';
        const r = get(s.file, side);
        r.attack_secs = s.atk;
        r.attack_secs_laning = s.atk_laning;
        r.near700_secs = s.near700;
    }
    return rec;
}

/** The per-game values of a measure for the games of an arm on a side; a share leaves out the games with nothing to divide by. */
function values(rec, files, side, key) {
    const out = [];
    for (const f of files) {
        const r = rec.get(`${f}|${side}`);
        const sh = SHARES[key];
        if (sh) {
            if (r[sh[1]] > 0) out.push(r[sh[0]] / r[sh[1]]);
        } else out.push(r[key]);
    }
    return out;
}

/**
 * The summary as data: { header, skipped, problems, blocks: [{ side, rows: [{ measure, arm, games, a, ref, diff, ci, floor, floorCi, mark }] }] }.
 * games: { file, arm, seat_team }[] (seat_team null: no seat, skipped); eps, secs: the two queries' rows.
 */
function summarise({ games, eps, secs, ref, pos, from, to }) {
    const seated = games.filter(g => g.seat_team !== null);
    const skipped = games.length - seated.length;
    const rec = perGame(seated, eps, secs, pos, from, to);
    const filesOf = arm => seated.filter(g => g.arm === arm).map(g => g.file);
    const arms = [...new Set(seated.map(g => g.arm))].sort();
    const problems = [];
    const rows = { test: [], opp: [] };
    const refFiles = filesOf(ref);
    if (!arms.includes(ref)) problems.push(`no reference arm ${ref} in this batch (arms: ${arms.join(', ') || 'none'}): nothing to compare with`);
    else if (refFiles.length < 3) problems.push(`reference arm ${ref} has ${refFiles.length} games with a seat: fewer than 3, so no floor`);
    else {
        for (const arm of arms.filter(a => a !== ref)) {
            const files = filesOf(arm);
            if (files.length < 3) {
                problems.push(`arm ${arm} has ${files.length} games with a seat: fewer than 3, no numbers`);
                continue;
            }
            for (const [key, name] of MEASURES) {
                const floor = welch(values(rec, refFiles, 'test', key), values(rec, refFiles, 'opp', key));
                for (const side of ['test', 'opp']) {
                    const a = values(rec, files, side, key);
                    const b = values(rec, refFiles, side, key);
                    const d = welch(a, b);
                    rows[side].push({
                        measure: name, key, arm, games: files.length, n: Math.min(d.nA, d.nB), a: d.meanA, ref: d.meanB, diff: d.diff, ci: d.ci,
                        floor: floor.diff, floorCi: floor.ci, mark: d.nA >= 3 && d.nB >= 3 ? verdict(d, floor) : '', thin: d.nA < 3 || d.nB < 3,
                    });
                }
            }
        }
    }
    return { skipped, problems, blocks: ['test', 'opp'].map(side => ({ side, rows: rows[side] })) };
}

const num = (x, share) => (Number.isFinite(x) ? (share ? x.toFixed(2) : Math.abs(x) >= 10 ? x.toFixed(0) : x.toFixed(1)) : 'n/a');

function text(s, o) {
    const out = [`${o.batch}: per-game means over the window ${o.fromText} to ${o.toText}, positions ${o.pos.join(',')}${o.lane ? `, lane ${o.lane}` : ''}; `
        + `diff ± is 1.96 standard errors of the difference of two means (Welch); floor is the same measure for the ${o.ref} arm's own two sides `
        + `(its test side minus its opp side, same ± rule); * marks a diff whose interval excludes 0 and which lies outside the floor's interval; `
        + `a share is the mean of each game's share, not the pooled one; the reference arm's own means are the ref columns`];
    if (s.skipped) out.push(`skipped ${s.skipped} games with no seat (stock or mirror)`);
    for (const p of s.problems) out.push(p);
    for (const b of s.blocks) {
        if (!b.rows.length) continue;
        out.push('', b.side === 'test' ? 'TEST side (the seat the label names)' : 'OPP side (the other team)');
        const lines = [['measure', 'arm', 'games', `arm ${b.side}`, `ref ${b.side}`, 'diff ± 95%', `floor (ref test - ref opp)`]];
        for (const r of b.rows) {
            const sh = SHARES[r.key] !== undefined;
            lines.push([r.measure, r.arm, String(r.games) + (sh || r.thin ? ` (n=${r.n})` : ''), num(r.a, sh), num(r.ref, sh),
                r.thin ? 'n<3' : `${r.diff >= 0 ? '+' : ''}${num(r.diff, sh)} ± ${num(r.ci, sh)}${r.mark ? ' *' : ''}`,
                `${r.floor >= 0 ? '+' : ''}${num(r.floor, sh)} ± ${num(r.floorCi, sh)}`]);
        }
        const w = lines[0].map((_, i) => Math.max(...lines.map(l => l[i].length)));
        for (const l of lines) out.push(l.map((c, i) => (i < 2 ? c.padEnd(w[i]) : c.padStart(w[i]))).join(' | '));
    }
    return out.join('\n');
}

/** Runs the count for a batch from the store. o: ref (default off), from, to (seconds; default 0 to 600), pos (list), lane. */
function countBatch(store, batch, o) {
    const games = store.query(`SELECT g.file, r.arm, r.seat_team FROM games g JOIN run_label r ON r.game_id = g.game_id
        WHERE r.batch = ? AND g.game = (SELECT max(g2.game) FROM games g2 WHERE g2.file = g.file) ORDER BY g.file`, batch);
    if (!games.length) throw new Error(`no games of batch ${batch} (the exact run name: base1 is not h2hbase1)`);
    for (const g of games) store.fillHeroSec({ like: g.file });
    const read = f => fs.readFileSync(path.join(__dirname, 'queries', f), 'utf8');
    const lane = o.lane ?? null;
    const eps = store.query(read('timeline_count.sql'), {
        like: null, batch, arm: null, game: null, lane, hero: null, kind: 'death,retreat,exchange,kill_try', pid: null, from: o.from, to: o.to,
    });
    const secs = store.db.prepare(read('timeline_count_secs.sql')).all({
        batch, arm: null, from: o.from, to: o.to, pos: o.pos.join(','), lane,
    });
    return summarise({ games, eps, secs, ref: o.ref, pos: o.pos, from: o.from, to: o.to });
}

module.exports = { describe, welch, verdict, parsePos, summarise, text, countBatch, MEASURES };
