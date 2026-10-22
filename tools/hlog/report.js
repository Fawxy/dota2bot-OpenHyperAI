// Human-readable views over a parsed game: summary, marks and timelines.
'use strict';

const { fmtT, modeChurn, laneFightStats, BLIP_DWELL, LANING_ROAM_CAP } = require('./checks');

const MARK_STATE_KEYS = ['mode', 'd', 'by', 'order', 'hp', 'mp', 'tgt', 'x', 'y', 'competing'];
const NOISY = new Set(['snap', 'bot', 'player']);

function pad(s, n) {
    s = String(s);
    return s.length >= n ? s : s + ' '.repeat(n - s.length);
}

function table(rows) {
    if (rows.length === 0) return '';
    const widths = rows[0].map((_, i) => Math.max(...rows.map(r => String(r[i]).length)));
    return rows.map(r => r.map((c, i) => pad(c, widths[i])).join('  ').trimEnd()).join('\n');
}

function mean(xs) {
    return xs.length === 0 ? undefined : xs.reduce((a, b) => a + b, 0) / xs.length;
}

function f2(x) {
    return x === undefined ? '-' : x.toFixed(2);
}

function who(game, pid) {
    const b = game.bots[pid];
    return b && b.hero ? `${b.hero}[${pid}]` : `pid${pid}`;
}

/** Share of snapshot time per mode, top three. */
function modeShare(bot) {
    const counts = {};
    for (const s of bot.snaps) counts[s.mode] = (counts[s.mode] || 0) + 1;
    const total = bot.snaps.length || 1;
    return Object.entries(counts)
        .sort((a, b) => b[1] - a[1])
        .slice(0, 3)
        .map(([m, n]) => `${m} ${Math.round((100 * n) / total)}%`)
        .join(', ');
}

function gameLine(game) {
    const bots = Object.values(game.bots);
    const humans = bots.filter(b => b.human).length;
    return `game ${game.index}: ${fmtT(game.minT)} to ${fmtT(game.maxT)}, ${bots.length - humans} bots, ${humans} humans, ${game.events.length} events, ${game.marks.length} marks, ${game.errors.length} errors${
        game.ended ? ', ended' : ''
    }`;
}

function f1(x) {
    return x.toFixed(1);
}

/** Switch rates per bot with upstream last-hit blips split out, and the busiest remaining mode pairs. */
function churnSection(game) {
    const churn = modeChurn(game);
    const rows = [['player', 'switches', 'blips', 'blips/min', 'other/min', 'top other pairs']];
    let blips = 0;
    let other = 0;
    let minutes = 0;
    for (const b of Object.values(game.bots).sort((x, y) => x.pid - y.pid)) {
        const c = churn[b.pid];
        if (b.human || !c) continue;
        const span = b.snaps.length > 1 ? b.snaps[b.snaps.length - 1].t - b.snaps[0].t : game.maxT - game.minT;
        const mins = Math.max(span, 1) / 60;
        const rest = c.switches.length - 2 * c.blips;
        blips += c.blips;
        other += rest;
        minutes += mins;
        const pairs = [...c.pairs.entries()].sort((x, y) => y[1].n - x[1].n).slice(0, 3);
        rows.push([who(game, b.pid), c.switches.length, c.blips, f1(c.blips / mins), f1(rest / mins), pairs.map(([k, g]) => `${k} ${g.n}`).join(', ') || '-']);
    }
    if (rows.length === 1) return [];
    return [
        '',
        `mode churn (a blip is a team_roam visit out of laning at its ${LANING_ROAM_CAP} laning cap, left within ${BLIP_DWELL}s: upstream last-hit grabs, not humaniser):`,
        table(rows),
        `all bots: ${blips} blips (${f1(blips / minutes)}/min per bot), ${other} other switches (${f1(other / minutes)}/min per bot)`,
    ];
}

function mapCounts(m) {
    return [...m.entries()].sort((a, b) => b[1] - a[1]).map(([k, n]) => `${k} ${n}`).join(', ') || '-';
}

/** Lane fights (task 11) per bot, from the lanefight_* events. */
function laneFightSection(game) {
    const stats = Object.values(laneFightStats(game)).sort((a, b) => a.pid - b.pid);
    if (stats.length === 0) return [];
    const rows = [['player', 'windows', 'starts', 'took', 'ends', 'gates', 'aborts', 'mistakes', 'mem']];
    for (const b of stats)
        rows.push([who(game, b.pid), mapCounts(b.windows), mapCounts(b.starts), `${b.took}/${b.fights} took`, mapCounts(b.ends), mapCounts(b.gates), mapCounts(b.aborts), mapCounts(b.mistakes), `mem ${b.remembered}/${b.mem}${b.noCd > 0 ? ` no_cd ${b.noCd}` : ''}`]);
    const out = ['', 'lane fights (took = trades/commits where team_roam or attack took over; mem = remembered/cooldown reads):', table(rows)];
    const abandons = game.events.filter(e => e.ev === 'lanefight_abandon');
    if (abandons.length > 0) {
        const arows = [['t', 'player', 'why', 'since', 'mode', 'ally', 'ally mode', 'ally atk', 'dist', 'range', 'last atk']];
        for (const e of abandons)
            arows.push([fmtT(e.t), who(game, e.pid), e.why, f1(e.since), e.mode, e.ally === undefined ? '-' : who(game, e.ally), e.amode ?? '-', e.atk ?? '-', e.dist === undefined ? '-' : Math.round(e.dist), e.range ?? '-', e.lastatk === undefined ? '-' : f1(e.lastatk)]);
        out.push('', 'partner abandons (what the partner was doing when the commit gave up on it):', table(arows));
    }
    return out;
}

function counts(items) {
    const m = new Map();
    for (const x of items) m.set(x, (m.get(x) || 0) + 1);
    return [...m.entries()].sort((a, b) => b[1] - a[1]).map(([k, n]) => `${k} ${n}`).join(', ') || '-';
}

// FarmPattern re-logs an unchanged farm_gate reason every GateLogEvery (15 s), so a gap longer than that is time the
// reason was not holding (a trip, death, another mode) and only counts up to it.
const FARM_GATE_SPAN = 16;

/** Seconds each farm_gate reason held for `pid`: from its line to the next farm event, capped at FARM_GATE_SPAN. */
function gateTime(farm, pid) {
    const mine = farm.filter(e => e.pid === pid);
    const secs = new Map();
    mine.forEach((e, i) => {
        if (e.ev !== 'farm_gate') return;
        const next = mine[i + 1];
        const span = Math.min(next ? next.t - e.t : FARM_GATE_SPAN, FARM_GATE_SPAN);
        secs.set(e.why, (secs.get(e.why) || 0) + span);
    });
    return [...secs.entries()].sort((a, b) => b[1] - a[1]);
}

/**
 * FarmPattern per core: trips, camps, stacks and whether they landed (lane_stack), how trips ended, pace, and what
 * kept the core from starting trips (farm_gate time by reason).
 */
function farmSection(game) {
    const farm = game.events.filter(e => e.ev.startsWith('farm_'));
    if (farm.length === 0) return [];
    const rows = [['player', 'trips', 'camps', 'stacks ok/tried', 'avg s', 'returns', 'ends', 'pace', 'no trip because (s)']];
    for (const pid of [...new Set(farm.map(e => e.pid))].sort((a, b) => a - b)) {
        const of = ev => farm.filter(e => e.pid === pid && e.ev === ev);
        const starts = of('farm_trip_start');
        const ends = of('farm_trip_end');
        const stacks = [...starts, ...of('farm_trip_next')].filter(e => e.phase === 'stack');
        const outcomes = game.events.filter(e => e.ev === 'lane_stack' && e.pid === pid && stacks.some(s => s.camp === e.camp && e.t >= s.t));
        const pace = starts.length > 0 ? starts[starts.length - 1].pace : undefined;
        const gates = gateTime(farm, pid).slice(0, 4).map(([why, t]) => `${why} ${Math.round(t)}`).join(', ');
        rows.push([
            who(game, pid),
            starts.length,
            ends.reduce((a, e) => a + (e.camps || 0), 0),
            `${outcomes.filter(e => e.stacked === 1).length}/${stacks.length}`,
            f2(mean(ends.map(e => e.secs).filter(x => typeof x === 'number'))),
            counts(of('farm_trip_return').map(e => e.why)),
            counts(ends.map(e => e.why)),
            pace === undefined ? '-' : String(pace),
            gates || '-',
        ]);
    }
    return [
        '',
        'farm trips (FarmPattern; pace is the latest learned clear-time factor, 1 = prior; no-fit = no camp fits before the next wave):',
        table(rows),
    ];
}

const EQ_PAIR_MIN = 25;
const EQ_PAIR_MAX = 35;

/** Least squares through the origin of the next wave's eq change on this wave's imbalance, per lane kind. */
function fitForecast(events) {
    const byLane = new Map();
    for (const e of events) {
        if (e.ev !== 'lane_eq') continue;
        const key = `${e.team}:${e.lane}`;
        if (!byLane.has(key)) byLane.set(key, []);
        byLane.get(key).push(e);
    }
    const pairs = new Map();
    for (const list of byLane.values()) {
        list.sort((a, b) => a.t - b.t);
        for (let i = 0; i + 1 < list.length; i++) {
            const dt = list[i + 1].t - list[i].t;
            if (dt < EQ_PAIR_MIN || dt > EQ_PAIR_MAX) continue;
            if (!pairs.has(list[i].kind)) pairs.set(list[i].kind, []);
            pairs.get(list[i].kind).push({ imb: list[i].imb, d: list[i + 1].eq - list[i].eq });
        }
    }
    const rows = [];
    for (const [kind, ps] of pairs) {
        if (ps.length < 2) continue;
        const sxx = ps.reduce((a, p) => a + p.imb * p.imb, 0);
        if (sxx === 0) continue;
        const k = ps.reduce((a, p) => a + p.imb * p.d, 0) / sxx;
        const m = mean(ps.map(p => p.d));
        const resid = ps.reduce((a, p) => a + (p.d - k * p.imb) ** 2, 0);
        const total = ps.reduce((a, p) => a + (p.d - m) ** 2, 0);
        rows.push({ kind, n: ps.length, k, r2: total === 0 ? 0 : 1 - resid / total });
    }
    return rows.sort((a, b) => a.kind.localeCompare(b.kind));
}

function forecastSection(game) {
    const out = [];
    const rows = fitForecast(game.events);
    if (rows.length > 0) {
        out.push('', 'forecast fit:');
        for (const r of rows) out.push(`  ${r.kind} n=${r.n} K=${r.k.toFixed(2)} r2=${r.r2.toFixed(2)}`);
    }
    const take = game.events.filter(e => e.kind === 'contest' && e.take === 1);
    const takeEnds = take.filter(e => e.ev === 'lane_job_end');
    if (take.length > 0) {
        const n = reason => takeEnds.filter(e => e.reason === reason).length;
        const swings = takeEnds.reduce((a, e) => a + (e.swings || 0), 0);
        const started = take.filter(e => e.ev === 'lane_job_start').length;
        const aborted = take.filter(e => e.ev === 'lane_job_abort').length;
        out.push(
            '',
            `take-pull: started ${started} swings ${swings} no-creeps ${n('no-creeps')} timeout ${n('timeout')} outnumbered ${n('outnumbered')} low-hp ${n('low-hp')} lane-wave ${n('lane-wave')} aborted ${aborted}`
        );
    }
    const roleReads = game.events.filter(e => e.ev === 'lane_enemy_role');
    const LANES = { 1: 'top', 2: 'mid', 3: 'bot' };
    for (const team of [2, 3]) {
        const reads = roleReads.filter(e => e.team === team);
        if (reads.length === 0) continue;
        const byLane = new Map();
        for (const e of reads) byLane.set(e.lane, [...(byLane.get(e.lane) || []), e]);
        const list = [...byLane].sort((a, b) => a[0] - b[0]).map(([lane, es]) => {
            const last = es[es.length - 1];
            const name = `${String(last.hero).replace('npc_dota_hero_', '')}[${last.enemy}]`;
            return `${LANES[lane] || lane} ${last.role}=${name}${es.length > 1 ? ` (${es.length - 1} changes)` : ''}`;
        });
        out.push('', `enemy roles read by ${team === 2 ? 'rad' : 'dire'}: ${list.join(', ')}`);
    }
    const pullSignals = game.events.filter(e => e.ev === 'lane_signal' && (e.kind === 'pull' || e.kind === 'half_pull'));
    const skips = game.events.filter(e => e.ev === 'lane_take_skip');
    if (pullSignals.length > 0 || skips.length > 0) {
        const byReason = new Map();
        for (const e of skips) byReason.set(e.reason, (byReason.get(e.reason) || 0) + 1);
        const reasons = [...byReason].map(([r, c]) => `${r} ${c}`).join(' ') || 'none';
        out.push('', `pull signals: ${pullSignals.length} noticed ${pullSignals.filter(e => e.noticed === 1).length}; take skipped: ${reasons}`);
    }
    const pre = game.events.filter(e => e.kind === 'contest' && e.pre === 1);
    const started = pre.filter(e => e.ev === 'lane_job_start').length;
    const ends = pre.filter(e => e.ev === 'lane_job_end');
    const aborted = pre.filter(e => e.ev === 'lane_job_abort').length;
    if (started > 0 || ends.length > 0 || aborted > 0) {
        const n = (...reasons) => ends.filter(e => reasons.includes(e.reason)).length;
        out.push(
            '',
            `pre-contest: started ${started} attacked ${n('no-target', 'timeout')} no-pull ${n('no-pull')} enemy-in-lane ${n('enemy-in-lane')} aborted ${aborted}`
        );
    }
    return out;
}

function summary(game) {
    const out = [gameLine(game), ''];
    const rows = [['player', 'team', 'skill', 'ally', 'lh/dn', 'switches', 'notice n/avg', 'react n/avg', 'orders acc/dec', 'stuck', 'thrash', 'time in mode']];
    const by = (ev, pid) => game.events.filter(e => e.ev === ev && e.pid === pid);
    const players = Object.values(game.bots).sort((a, b) => (a.team || 0) - (b.team || 0) || a.pid - b.pid);
    for (const b of players) {
        const last = b.snaps[b.snaps.length - 1];
        const p = b.profiles[b.profiles.length - 1];
        const notices = by('notice', b.pid).filter(e => e.reason === 'delay');
        const reacts = by('react', b.pid);
        rows.push([
            `${b.hero || '?'}[${b.pid}]${b.human ? ' (human)' : ''}`,
            b.team === 2 ? 'rad' : b.team === 3 ? 'dire' : '?',
            p ? p.skill.toFixed(2) : '-',
            b.human ? '-' : b.allyOfHuman === undefined ? '?' : b.allyOfHuman ? 'yes' : 'no',
            last ? `${last.lh}/${last.dn}` : '-',
            by('mode', b.pid).length,
            `${notices.length}/${f2(mean(notices.map(e => e.delay)))}`,
            `${reacts.length}/${f2(mean(reacts.map(e => e.delay)))}`,
            `${by('order_accept', b.pid).length}/${by('order_decline', b.pid).length}`,
            by('stuck', b.pid).length,
            by('thrash', b.pid).length,
            b.human ? '-' : modeShare(b),
        ]);
    }
    out.push(table(rows));
    out.push(...churnSection(game));
    out.push(...laneFightSection(game));
    out.push(...farmSection(game));
    out.push(...forecastSection(game));
    const orders = game.events.filter(e => e.ev === 'order_post');
    const cmds = game.events.filter(e => e.ev === 'cmd');
    const pings = game.events.filter(e => e.ev === 'ping');
    out.push('', `orders posted ${orders.length} (${[...new Set(orders.map(o => o.type))].join(', ') || '-'}), commands ${cmds.length}, pings ${pings.length}`);
    if (game.marks.length > 0) {
        out.push('', 'marks:');
        for (const m of game.marks) out.push(`  #${m.n} ${fmtT(m.t)} by ${who(game, m.by)}: ${m.text || '(no note)'}`);
    }
    return out.join('\n');
}

function checksText(results) {
    const icon = { pass: 'PASS', warn: 'WARN', fail: 'FAIL', skip: 'skip' };
    const out = [];
    for (const r of results) {
        out.push(`${icon[r.level]}  ${r.id}: ${r.summary}`);
        for (const d of r.details) out.push(`        ${d}`);
        if (r.more > 0) out.push(`        ... ${r.more} more`);
    }
    return out.join('\n');
}

function eventText(game, e) {
    const skip = new Set(['t', 'ev', 'pid']);
    const fields = Object.entries(e)
        .filter(([k]) => !skip.has(k))
        .map(([k, v]) => `${k}=${typeof v === 'string' && v.includes(' ') ? JSON.stringify(v) : v}`)
        .join(' ');
    return `${pad(fmtT(e.t) + ` (${e.t.toFixed(1)})`, 14)} ${pad(e.pid !== undefined ? who(game, e.pid) : '', 22)} ${pad(e.ev, 13)} ${fields}`;
}

/** Events in [from, to], optionally for some players and event names. Snapshots only when asked. */
function timeline(game, { from = -Infinity, to = Infinity, pids, evs, snaps = false } = {}) {
    const lines = [];
    for (const e of game.events) {
        if (e.t < from || e.t > to) continue;
        if (pids && e.pid !== undefined && !pids.includes(e.pid)) continue;
        if (evs ? !evs.includes(e.ev) : !snaps && NOISY.has(e.ev)) continue;
        lines.push(eventText(game, e));
    }
    return lines.join('\n');
}

function markView(game, n, window, opts = {}) {
    const m = game.marks.find(x => x.n === n);
    if (!m) return `no mark #${n} in game ${game.index} (it has ${game.marks.length})`;
    const out = [`mark #${m.n} at ${fmtT(m.t)} by ${who(game, m.by)}: ${m.text || '(no note)'}`, ''];
    const states = game.events.filter(e => e.ev === 'mark_state' && Math.abs(e.t - m.t) <= 1 && e.n === m.n);
    // Both teams' VMs report state for an all-chat mark; keep the first line per player.
    const seen = new Set();
    const rows = [['player', ...MARK_STATE_KEYS]];
    for (const s of states) {
        if (seen.has(s.pid)) continue;
        seen.add(s.pid);
        rows.push([who(game, s.pid), ...MARK_STATE_KEYS.map(k => (s[k] === undefined ? '-' : s[k]))]);
    }
    out.push('state at the mark:', table(rows), '', `events ${fmtT(m.t - window)} to ${fmtT(m.t + window / 2)}:`);
    out.push(timeline(game, { from: m.t - window, to: m.t + window / 2, pids: opts.pids, snaps: opts.snaps }));
    return out.join('\n');
}

module.exports = { summary, fitForecast, checksText, timeline, markView, gameLine };
