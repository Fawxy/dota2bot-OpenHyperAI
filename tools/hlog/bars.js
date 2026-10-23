// Machine-checkable slice metrics: one JSON document per game (collect) and pass bars checked against one or
// more games (check). Everything a slice's pass bar needs is computed here, so a test verdict needs no reading.
'use strict';

const { laningMetrics, stateMetrics, median } = require('./metrics');
const { evaluate: laneEval } = require('./lane_eval');

const METRICS_SCHEMA = 'hlog-metrics/1';
const SPEC_SCHEMA = 'hlog-bars/1';
// Error sites that belong to the team's code; anything else is OHA's (often pre-existing).
const TEAM_WHERE = /^(States|Tasks|sdk|Phase)/;

function zoneOf(x, y) {
    if (x < -4500 && y < -4000) return 'base';
    if (x > 4000 && y > 3500) return 'base';
    if (Math.abs(x - y) < 2000) return 'mid';
    if (x < -5000 || y > 5200) return 'top';
    if (x > 5000 || y < -5200) return 'bot';
    if (Math.abs(x + y) < 1600) return 'river';
    return 'jungle';
}

function playedLane(bot) {
    const n = {};
    for (const p of bot.snaps) if (p.t >= 120 && p.t <= 360 && p.alive === 1) {
        const z = zoneOf(p.x, p.y);
        if (z === 'top' || z === 'mid' || z === 'bot') n[z] = (n[z] || 0) + 1;
    }
    return Object.keys(n).sort((a, b) => n[b] - n[a])[0];
}

function ownLanePct(bot, until) {
    const lane = playedLane(bot);
    const s = bot.snaps.filter(p => p.t <= until && p.alive === 1);
    if (s.length === 0 || lane === undefined) return undefined;
    return (100 * s.filter(p => zoneOf(p.x, p.y) === lane).length) / s.length;
}

const teamName = t => (t === 2 ? 'rad' : t === 3 ? 'dire' : String(t));
const ratio = (a, b) => (b > 0 ? (100 * a) / b : undefined);
const mean = xs => (xs.length ? xs.reduce((a, x) => a + x, 0) / xs.length : undefined);
const sd = xs => {
    const m = mean(xs);
    return xs.length > 1 ? Math.sqrt(xs.reduce((a, x) => a + (x - m) ** 2, 0) / (xs.length - 1)) : undefined;
};
const isTrue = v => v === 1 || v === 'true' || v === true;
const count = (xs, f) => xs.filter(f).length;

/** "3/4" (lane_eval's ok/attempts cells) -> percentage. */
function fraction(cell) {
    const m = /^(\d+)\/(\d+)$/.exec(String(cell));
    return m ? ratio(Number(m[1]), Number(m[2])) : undefined;
}

/**
 * The human's position: the one its team's latest ev=bot lines leave free, if exactly one is free. dotactl's
 * `pos:` line is not in the test log, so this is how a check knows which position the idle human took.
 */
function humanPosition(game) {
    const human = Object.values(game.bots).find(b => b.human);
    if (!human) return undefined;
    const held = new Set();
    for (const b of Object.values(game.bots)) {
        if (b.human || b.team !== human.team) continue;
        const p = (b.profiles[b.profiles.length - 1] || {}).pos;
        if (typeof p === 'number') held.add(p);
    }
    const free = [1, 2, 3, 4, 5].filter(p => !held.has(p));
    return free.length === 1 ? free[0] : undefined;
}

/** Per where+msg the highest running count (telemetry re-reports a repeating error with n=). */
function luaErrors(game, until) {
    const byKey = {};
    for (const e of game.events) {
        if (e.ev !== 'lua_error' || e.t > until) continue;
        const key = `${e.where}\u0000${e.msg}`;
        const n = typeof e.n === 'number' ? e.n : 1;
        byKey[key] = { where: String(e.where), msg: String(e.msg), n: Math.max(n, byKey[key] ? byKey[key].n : 0), first: byKey[key] ? byKey[key].first : e.t };
    }
    return Object.values(byKey);
}

function jobMetrics(events) {
    const of = name => events.filter(e => e.ev === name);
    const stacks = of('lane_stack');
    const aggroErr = stacks.map(s => Math.abs(Number(s.aggro) - Number(s.planned))).filter(x => !Number.isNaN(x));
    const grades = of('lane_job');
    const exec = of('job_exec');
    const trips = of('farm_trip_end');
    const wisdom = of('wisdom');
    const ganks = of('gank');
    const runes = of('rune_trip');
    const frames = xs => xs.reduce((o, x) => ((o.sdk += Number(x.sdk || 0)), (o.legacy += Number(x.legacy || 0)), o), { sdk: 0, legacy: 0 });
    const jobFrames = frames(exec);
    const tripFrames = frames(trips);
    const okWisdom = wisdom.filter(w => w.result === 'ok');
    const kills = ganks.filter(g => g.msg === 'kill');
    const starts = {};
    for (const s of of('lane_job_start')) starts[s.kind] = (starts[s.kind] || 0) + 1;
    return {
        jobStarts: starts,
        pullsPlanned: (starts.single || 0) + (starts.double || 0) + (starts.pull || 0),
        stackAttempts: stacks.length,
        stacked: count(stacks, s => isTrue(s.stacked)),
        stackedPct: ratio(count(stacks, s => isTrue(s.stacked)), stacks.length),
        aggroErrMean: mean(aggroErr),
        aggroErrSd: sd(aggroErr),
        aggroErrMax: aggroErr.length ? Math.max(...aggroErr) : undefined,
        pullGraded: grades.length,
        pullOkPct: ratio(count(grades, g => g.grade === 'ok'), grades.length),
        jobExec: exec.length,
        jobSdkFrames: jobFrames.sdk,
        jobLegacyFrames: jobFrames.legacy,
        jobSdkPct: ratio(jobFrames.sdk, jobFrames.sdk + jobFrames.legacy),
        farmTrips: trips.length,
        farmSdkPct: ratio(tripFrames.sdk, tripFrames.sdk + tripFrames.legacy),
        farmWhy: trips.reduce((o, x) => ((o[x.why] = (o[x.why] || 0) + 1), o), {}),
        wisdomTrips: wisdom.length,
        wisdomOk: okWisdom.length,
        wisdomTakenMax: okWisdom.length ? Math.max(...okWisdom.map(w => Number(w.taken))) : undefined,
        wisdomArriveMean: mean(wisdom.filter(w => typeof w.arrived === 'number').map(w => w.arrived - w.spawn)),
        wisdomAwayMax: wisdom.length ? Math.max(...wisdom.map(w => Number(w.away))) : undefined,
        runeTrips: runes.length,
        runeOk: count(runes, r => ['ok', 'over', 'gone'].includes(String(r.msg)) || r.result === 'ok'),
        gankAttempts: ganks.length,
        gankKills: kills.length,
        gankFirstKill: kills.length ? Math.min(...kills.map(g => g.t)) : undefined,
        gankAwayMax: ganks.length ? Math.max(...ganks.map(g => Number(g.away))) : undefined,
    };
}

function stateFields(r) {
    if (r === undefined) return undefined;
    return {
        secs: r.secs,
        swPerMin: r.minutes > 0 ? r.switches / r.minutes : undefined,
        agreePct: ratio(r.agreeSec, r.compareSec),
        agreeLongPct: ratio(r.agreeLongSec, r.compareLongSec),
        laningCoverPct: ratio(r.laningCoverSec, r.laningModeSec),
        starts: r.starts,
        restartLagMax: r.restartLags.length ? Math.max(...r.restartLags) : undefined,
        ends: r.ends,
        laneDMedian: median(r.laneDHold.length ? r.laneDHold : r.laneD),
    };
}

/** Every metric a slice bar uses, for one parsed game (parse.js) up to `until` game seconds. Plain JSON. */
function collect(game, { until = 600, file } = {}) {
    const lan = laningMetrics(game, { until });
    const lane = Object.fromEntries(laneEval(game, until).map(r => [r.pid, r]));
    const states = Object.fromEntries(stateMetrics(game, { until }).map(r => [r.pid, r]));
    const human = Object.values(game.bots).find(b => b.human);
    const errors = luaErrors(game, until);
    const bots = [];
    for (const m of lan.bots) {
        const b = game.bots[m.pid];
        const l = lane[m.pid] || {};
        const events = game.events.filter(e => e.pid === m.pid && e.t <= until);
        const ownedPos = events.filter(e => e.ev === 'lane_pos' && e.owned === 1 && e.spot !== undefined);
        bots.push({
            pid: m.pid,
            hero: m.hero,
            team: teamName(m.team),
            pos: m.pos,
            humanTeam: human !== undefined && human.team === m.team,
            lane: playedLane(b),
            laning: { ...m, ownLane: ownLanePct(b, until), pid: undefined, hero: undefined, team: undefined, pos: undefined, retreatBy: undefined },
            laneEval: {
                lh2: l.lh2, lh5: l.lh5, lh10: l.lh10, dn10: l.dn10, deaths: l.deaths, hph: l.hph,
                bodyLhPct: fraction(l.bodyLH), bodyLhTries: count(events, e => e.ev === 'lh' && e.kind === 'lasthit'),
                contestedPct: fraction(l.contested), bodyDnPct: fraction(l.bodyDN), holdD: l.holdD, runningPct: l.running,
                // Slice 3: the spot follows the creeps most of the time, and moves when the wave pushes.
                spotCreepPct: ratio(count(ownedPos, e => e.spot === 'creep'), ownedPos.length),
                pushedLines: count(ownedPos, e => typeof e.pushed === 'number' && e.pushed > 0),
            },
            states: stateFields(states[m.pid]),
            jobs: jobMetrics(events),
        });
    }
    const teamTotals = side => {
        const own = bots.filter(b => b.team === side);
        const sum = k => own.reduce((a, b) => a + (b.jobs[k] || 0), 0);
        return { gankAttempts: sum('gankAttempts'), gankKills: sum('gankKills'), stacked: sum('stacked'), jobSdkPct: ratio(sum('jobSdkFrames'), sum('jobSdkFrames') + sum('jobLegacyFrames')) };
    };
    const allJob = bots.reduce((o, b) => ((o.sdk += b.jobs.jobSdkFrames), (o.legacy += b.jobs.jobLegacyFrames), o), { sdk: 0, legacy: 0 });
    return JSON.parse(JSON.stringify({
        schema: METRICS_SCHEMA,
        file,
        game: {
            index: game.index,
            build: lan.build,
            until,
            maxT: game.maxT,
            complete: lan.complete,
            // Dota drops repeats of a message past its count limit; telemetry from then on may be missing lines.
            squelched: game.squelched === true,
            humanTeam: human ? teamName(human.team) : undefined,
            humanHero: human ? human.hero : undefined,
            humanPos: humanPosition(game),
            errors: {
                lua: errors.reduce((a, e) => a + e.n, 0),
                luaTeam: errors.filter(e => TEAM_WHERE.test(e.where)).reduce((a, e) => a + e.n, 0),
                luaWhere: errors.reduce((o, e) => ((o[e.where] = (o[e.where] || 0) + e.n), o), {}),
                script: game.errors.filter(e => /script runtime error/i.test(e.text)).length,
                console: game.errors.length,
            },
            jobSdkPct: ratio(allJob.sdk, allJob.sdk + allJob.legacy),
            stateLines: game.events.filter(e => e.ev === 'state' || e.ev === 'state_start').length,
            rad: teamTotals('rad'),
            dire: teamTotals('dire'),
            // The human's team owns the jobs in the team arms, and --human dire swaps sides, so bars use these.
            human: human ? teamTotals(teamName(human.team)) : undefined,
            other: human ? teamTotals(human.team === 2 ? 'dire' : 'rad') : undefined,
        },
        bots,
    }));
}

// ---- checking ----

function getPath(obj, dotted) {
    let v = obj;
    for (const k of dotted.split('.')) {
        if (v === undefined || v === null) return undefined;
        v = v[k];
    }
    return v;
}

function matches(bot, sel, metrics) {
    if (!sel) return true;
    const one = (want, have) => (Array.isArray(want) ? want.includes(have) : want === have);
    if (sel.team !== undefined) {
        const team = sel.team === 'human' ? metrics.game.humanTeam : sel.team === 'bots' ? (metrics.game.humanTeam === 'rad' ? 'dire' : 'rad') : sel.team;
        if (!one(team, bot.team)) return false;
    }
    for (const k of ['pos', 'hero', 'pid', 'lane']) if (sel[k] !== undefined && !one(sel[k], bot[k])) return false;
    return true;
}

const AGGS = {
    sum: xs => xs.reduce((a, x) => a + x, 0),
    mean,
    min: xs => Math.min(...xs),
    max: xs => Math.max(...xs),
    median,
    count: xs => xs.length,
};

function inBar(v, bar) {
    if (bar.eq !== undefined && typeof bar.eq !== 'number') return v === bar.eq;
    if (typeof v !== 'number' || Number.isNaN(v)) return false;
    if (bar.min !== undefined && v < bar.min) return false;
    if (bar.max !== undefined && v > bar.max) return false;
    if (bar.range && (v < bar.range[0] || v > bar.range[1])) return false;
    if (bar.eq !== undefined && v !== bar.eq) return false;
    return true;
}

/** The value(s) one bar reads from one game's metrics: game.* paths read the game, others the selected bots. */
function barValues(metrics, bar) {
    if (bar.metric.startsWith('game.')) return [{ who: 'game', v: getPath(metrics, bar.metric) }];
    const bots = metrics.bots.filter(b => matches(b, bar.select, metrics));
    const vals = bots.map(b => ({ who: `${b.team} p${b.pos} ${b.hero}[${b.pid}]`, v: getPath(b, bar.metric) }));
    if (!bar.agg || bar.agg === 'each') return vals;
    const nums = vals.map(x => x.v).filter(v => typeof v === 'number');
    if (bar.agg !== 'count' && nums.length === 0) return [{ who: `${bar.agg} of ${bots.length}`, v: undefined }];
    return [{ who: `${bar.agg} of ${bots.length}`, v: AGGS[bar.agg](bar.agg === 'count' ? vals : nums) }];
}

function barText(bar) {
    const parts = [];
    if (bar.range) parts.push(`in [${bar.range[0]}, ${bar.range[1]}]`);
    if (bar.min !== undefined) parts.push(`>= ${bar.min}`);
    if (bar.max !== undefined) parts.push(`<= ${bar.max}`);
    if (bar.eq !== undefined) parts.push(`== ${bar.eq}`);
    return parts.join(' and ');
}

/**
 * Checks a bar spec against the metrics of one or more games (one per run). Per bar, `over` says how runs combine:
 * "each" (default: every run passes), "median" (the median across runs passes), "any" (one run passes).
 * A bar with no value in a run (the selected bot is the human, a metric that needs events the game lacks) is
 * "missing", which fails; an `optional` bar ignores missing values instead. Returns { pass, results }.
 */
function check(runs, spec) {
    if (spec.schema !== undefined && spec.schema !== SPEC_SCHEMA) throw new Error(`spec schema ${spec.schema}, expected ${SPEC_SCHEMA}`);
    if (!Array.isArray(spec.bars) || spec.bars.length === 0) throw new Error('spec has no bars');
    const results = [];
    const minRuns = spec.minRuns || 1;
    for (const bar of spec.bars) {
        if (typeof bar.metric !== 'string') throw new Error(`bar ${bar.id || '?'} has no metric`);
        if (bar.agg && bar.agg !== 'each' && !AGGS[bar.agg]) throw new Error(`bar ${bar.id}: unknown agg ${bar.agg}`);
        // An optional bar judges the values that exist (a support with one stack has no spread; the human's own
        // position has no bot) and is skipped when there are none.
        const perRun = runs.map(m => barValues(m, bar).filter(x => !bar.optional || x.v !== undefined));
        const over = bar.over || spec.over || 'each';
        const flat = perRun.flat();
        const present = flat.filter(x => typeof x.v === 'number' || typeof x.v === 'boolean');
        let status, value;
        if (present.length === 0) status = 'missing';
        else if (over === 'median') {
            value = median(present.map(x => x.v));
            status = inBar(value, bar) ? 'pass' : 'fail';
        } else if (over === 'any') status = present.some(x => inBar(x.v, bar)) ? 'pass' : 'fail';
        else status = flat.every(x => inBar(x.v, bar)) ? 'pass' : flat.some(x => x.v === undefined) && present.every(x => inBar(x.v, bar)) ? 'missing' : 'fail';
        const runsWithValue = perRun.filter(r => r.some(x => x.v !== undefined)).length;
        if (status === 'pass' && runsWithValue < minRuns) status = 'insufficient';
        if (status === 'missing' && bar.optional) status = 'skipped';
        results.push({ id: bar.id || bar.metric, metric: bar.metric, select: bar.select, agg: bar.agg, over, bar: barText(bar), status, value, runs: perRun });
    }
    const pass = results.every(r => r.status === 'pass' || r.status === 'skipped');
    return { schema: 'hlog-check/1', spec: spec.name, pass, results };
}

function fmtV(v) {
    if (v === undefined) return '-';
    if (typeof v !== 'number') return String(v);
    return Number.isInteger(v) ? String(v) : v.toFixed(2);
}

function checkText(result) {
    const lines = [`${result.spec || 'bars'}: ${result.pass ? 'PASS' : 'FAIL'}`];
    for (const r of result.results) {
        const vals = r.runs.map(run => run.map(x => `${x.who} ${fmtV(x.v)}`).join(', ') || 'no match').join(' | ');
        const med = r.over === 'median' && r.value !== undefined ? ` median ${fmtV(r.value)};` : '';
        lines.push(`  ${r.status.toUpperCase().padEnd(12)} ${r.id}: ${r.metric} ${r.bar};${med} ${vals}`);
    }
    return lines.join('\n');
}

module.exports = { collect, check, checkText, humanPosition, METRICS_SCHEMA, SPEC_SCHEMA };
