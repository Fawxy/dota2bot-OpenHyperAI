// Invariant checks over one parsed game. Each returns { id, level: pass|warn|fail|skip, summary, details }.
'use strict';

// Logged values are rounded to 3 dp and sampled on frame boundaries.
const EPS = 0.01;
const FRAME_SLACK = 0.1;
const SNAP_GAP_FAIL = 10;
const ORDER_FOLLOW_WINDOW = 8;
const FROZEN_SECONDS = 10;
const FROZEN_RADIUS = 50;
const FOUNTAIN_RADIUS = 2600;
const FOUNTAINS = [
    { x: -7000, y: -6500 },
    { x: 7000, y: 6400 },
];
const LANE_NAMES = { 1: 'top', 2: 'mid', 3: 'bot' };
const DETAIL_LIMIT = 12;

function fmtT(t) {
    if (typeof t !== 'number') return String(t);
    const sign = t < 0 ? '-' : '';
    const a = Math.abs(t);
    return `${sign}${Math.floor(a / 60)}:${String(Math.floor(a % 60)).padStart(2, '0')}`;
}

function profileAt(bot, t) {
    if (!bot || bot.profiles.length === 0) return undefined;
    let p = bot.profiles[0];
    for (const q of bot.profiles) if (q.t <= t) p = q;
    return p;
}

/** Bounds of Profile.SampleDelay for a base delay, before the react floor. */
function delayBounds(p, base) {
    return { lo: base * (1 - p.jitter / 2), hi: base * (1 + p.jitter / 2) + p.lapseMax };
}

function result(id, failures, warnings, okSummary, extra) {
    const details = [...failures, ...warnings];
    const level = failures.length > 0 ? 'fail' : warnings.length > 0 ? 'warn' : 'pass';
    const summary = level === 'pass' ? okSummary : `${failures.length} fail, ${warnings.length} warn${extra ? `; ${extra}` : ''}`;
    return { id, level, summary, details: details.slice(0, DETAIL_LIMIT), more: Math.max(0, details.length - DETAIL_LIMIT) };
}

function skip(id, why) {
    return { id, level: 'skip', summary: why, details: [], more: 0 };
}

function name(game, pid) {
    const b = game.bots[pid];
    return b && b.hero ? `${b.hero}[${pid}]` : `pid ${pid}`;
}

function scriptErrors(game) {
    if (game.errors.length === 0) return { id: 'script_errors', level: 'pass', summary: 'no Lua errors in the console', details: [], more: 0 };
    const counts = new Map();
    for (const e of game.errors) counts.set(e, (counts.get(e) || 0) + 1);
    const details = [...counts.entries()].map(([text, n]) => `${n}x ${text}`);
    return { id: 'script_errors', level: 'fail', summary: `${game.errors.length} error lines (${counts.size} distinct)`, details: details.slice(0, DETAIL_LIMIT), more: Math.max(0, details.length - DETAIL_LIMIT) };
}

function snapshotGaps(game) {
    const fails = [];
    let botCount = 0;
    const end = game.maxT;
    for (const b of Object.values(game.bots)) {
        if (b.human || b.snaps.length === 0) continue;
        botCount++;
        for (let i = 1; i < b.snaps.length; i++) {
            const gap = b.snaps[i].t - b.snaps[i - 1].t;
            if (gap > SNAP_GAP_FAIL) fails.push(`${name(game, b.pid)} no snapshot for ${gap.toFixed(1)}s from ${fmtT(b.snaps[i - 1].t)} (bot script stalled or errored)`);
        }
        const last = b.snaps[b.snaps.length - 1].t;
        if (!game.ended && end - last > SNAP_GAP_FAIL) fails.push(`${name(game, b.pid)} stopped reporting at ${fmtT(last)}, game ran to ${fmtT(end)}`);
    }
    if (botCount === 0) return skip('snapshot_gaps', 'no bot snapshots');
    return result('snapshot_gaps', fails, [], `${botCount} bots reported continuously`);
}

function noticeDelay(game) {
    const fails = [];
    const warns = [];
    let n = 0;
    for (const e of game.events) {
        if (e.ev !== 'notice' || e.reason !== 'delay') continue;
        const bot = game.bots[e.pid];
        const p = profileAt(bot, e.t - e.delay);
        if (!p) continue;
        n++;
        const pNow = profileAt(bot, e.t);
        const a = delayBounds(p, p.notice);
        const b = delayBounds(pNow, pNow.notice);
        const lo = Math.min(a.lo, b.lo);
        const hi = Math.max(a.hi, b.hi);
        const where = `${fmtT(e.t)} ${name(game, e.pid)} saw ${e.target}`;
        if (e.due < lo - EPS || e.due > hi + EPS) fails.push(`${where}: sampled ${e.due}s outside profile [${lo.toFixed(3)}, ${hi.toFixed(3)}]`);
        if (e.delay < e.due - FRAME_SLACK) fails.push(`${where}: noticed after ${e.delay}s, before its sampled ${e.due}s`);
        else if (e.delay - e.due > 1) warns.push(`${where}: noticed ${(e.delay - e.due).toFixed(2)}s after it was due (the bot did not look for enemies meanwhile)`);
    }
    if (n === 0) return skip('notice_delay', 'no delayed notices');
    return result('notice_delay', fails, warns, `${n} delayed notices within profile bounds`);
}

function reactDelay(game) {
    const fails = [];
    let n = 0;
    for (const e of game.events) {
        if (e.ev !== 'react') continue;
        const bot = game.bots[e.pid];
        const p = profileAt(bot, e.t - e.delay);
        if (!p) continue;
        n++;
        const pNow = profileAt(bot, e.t);
        const a = delayBounds(p, p.react);
        const b = delayBounds(pNow, pNow.react);
        const lo = Math.max(p.minReact, Math.min(a.lo, b.lo));
        const hi = Math.max(a.hi, b.hi);
        if (e.delay < p.minReact - EPS) fails.push(`${fmtT(e.t)} ${name(game, e.pid)} reacted to ${e.who} ${e.what} in ${e.delay}s, under MinReact ${p.minReact}`);
        else if (e.delay < lo - EPS || e.delay > hi + EPS)
            fails.push(`${fmtT(e.t)} ${name(game, e.pid)} reacted to ${e.who} ${e.what} in ${e.delay}s, outside [${lo.toFixed(3)}, ${hi.toFixed(3)}]`);
    }
    if (n === 0) return skip('react_delay', 'no reactions logged');
    return result('react_delay', fails, [], `${n} reactions within profile bounds`);
}

function orderReadDelay(game) {
    const fails = [];
    let n = 0;
    for (const e of game.events) {
        if (e.ev !== 'order_accept') continue;
        const p = profileAt(game.bots[e.pid], e.t);
        if (!p) continue;
        const base = e.kind === 'chat' ? p.chat : p.ping;
        if (typeof base !== 'number') continue;
        n++;
        const { lo, hi } = delayBounds(p, base);
        const where = `${fmtT(e.t)} ${name(game, e.pid)} ${e.type}#${e.id}`;
        if (e.read < lo - EPS || e.read > hi + EPS) fails.push(`${where}: ${e.kind} read delay ${e.read}s outside [${lo.toFixed(3)}, ${hi.toFixed(3)}]`);
        if (e.latency < e.read - FRAME_SLACK) fails.push(`${where}: accepted ${e.latency}s after posting, before its read delay ${e.read}s`);
    }
    if (n === 0) return skip('order_read_delay', 'no accepted orders');
    return result('order_read_delay', fails, [], `${n} orders accepted after a human-like read delay`);
}

function expectedModes(type, lane) {
    const l = LANE_NAMES[lane];
    switch (type) {
        case 'GATHER':
        case 'ATTACK':
        case 'SMOKE':
        case 'BACK':
            return ['assemble'];
        case 'ROSHAN':
            return ['roshan'];
        case 'DEFEND':
            return l ? [`defend_${l}`] : ['defend_top', 'defend_mid', 'defend_bot'];
        case 'PUSH':
            return l ? [`push_${l}`] : ['push_top', 'push_mid', 'push_bot'];
        default:
            return undefined;
    }
}

/** Modes the bot was in at any point in [t0, t1], from snapshots and mode-switch events. */
function modesDuring(game, pid, t0, t1) {
    const modes = new Set();
    let before;
    for (const e of game.events) {
        if (e.pid !== pid) continue;
        if (e.ev === 'snap' || e.ev === 'mode' || e.ev === 'mark_state') {
            const m = e.ev === 'mode' ? e.to : e.mode;
            if (e.t < t0) before = m;
            else if (e.t <= t1) modes.add(m);
        }
    }
    if (before) modes.add(before);
    return modes;
}

function diedDuring(game, pid, t0, t1) {
    const b = game.bots[pid];
    return b ? b.snaps.some(s => s.t >= t0 && s.t <= t1 && s.alive === 0) : false;
}

function orderFollowed(game) {
    const warns = [];
    let n = 0;
    const posts = game.events.filter(e => e.ev === 'order_post');
    for (const e of game.events) {
        if (e.ev !== 'order_accept') continue;
        const want = expectedModes(e.type, e.lane);
        if (!want) continue;
        const bot = game.bots[e.pid];
        const post = posts.find(p => p.id === e.id && p.type === e.type && (!bot || p.team === bot.team) && p.t <= e.t + EPS);
        const until = Math.min(e.t + ORDER_FOLLOW_WINDOW, post ? post.t + post.dur : Infinity);
        if (diedDuring(game, e.pid, e.t, until) || until <= e.t) continue;
        n++;
        const seen = modesDuring(game, e.pid, e.t, until);
        if (!want.some(m => seen.has(m)))
            warns.push(`${fmtT(e.t)} ${name(game, e.pid)} accepted ${e.type}#${e.id} but stayed in ${[...seen].join('/') || '?'} for ${(until - e.t).toFixed(0)}s (wanted ${want.join('/')})`);
    }
    if (n === 0) return skip('order_followed', 'no accepted orders with a target mode');
    return result('order_followed', [], warns, `${n} accepted orders acted on`);
}

function lastHitEtiquette(game) {
    const fails = [];
    let botHits = 0;
    let checked = 0;
    for (const e of game.events) {
        if (e.ev !== 'lasthit' || e.human === 1) continue;
        const bot = game.bots[e.pid];
        if (bot && bot.allyOfHuman === false) continue;
        botHits++;
        if (typeof e.dec !== 'string') continue;
        checked++;
        if (e.dec.startsWith('skip')) fails.push(`${fmtT(e.t)} ${name(game, e.pid)} last-hit ${e.creep || 'a creep'} it had decided to leave (${e.dec}, ${e.decAge}s earlier)`);
    }
    if (botHits === 0) return skip('lasthit_etiquette', 'no allied bot last hits');
    return result('lasthit_etiquette', fails, [], `${checked}/${botHits} allied bot last hits had a decision; none on creeps left for a human`);
}

function intentHealth(game) {
    const warns = [];
    for (const e of game.events) {
        if (e.ev === 'stuck') warns.push(`${fmtT(e.t)} ${name(game, e.pid)} stuck in ${e.mode} (desire ${e.d}, ${Number(e.inMode).toFixed(1)}s in mode)`);
        if (e.ev === 'thrash') warns.push(`${fmtT(e.t)} ${name(game, e.pid)} thrashing: ${e.switches} switches in ${e.window}s, now ${e.mode} (${e.competing})`);
    }
    return result('intent_health', [], warns, 'no stuck or thrash episodes');
}

function nearFountain(s) {
    return FOUNTAINS.some(f => Math.hypot(s.x - f.x, s.y - f.y) < FOUNTAIN_RADIUS);
}

/** Independent of the intent stuck detector: alive, away from base, and not moving for FROZEN_SECONDS. */
function frozenBots(game) {
    const warns = [];
    let n = 0;
    for (const b of Object.values(game.bots)) {
        if (b.human || b.snaps.length === 0) continue;
        n++;
        let anchor;
        for (const s of b.snaps) {
            if (s.alive !== 1 || nearFountain(s) || (anchor && Math.hypot(s.x - anchor.x, s.y - anchor.y) > FROZEN_RADIUS)) {
                if (anchor && anchor.last.t - anchor.t >= FROZEN_SECONDS)
                    warns.push(`${name(game, b.pid)} stood still ${(anchor.last.t - anchor.t).toFixed(0)}s from ${fmtT(anchor.t)} at (${anchor.x}, ${anchor.y}) in ${[...anchor.modes].join('/')}`);
                anchor = s.alive === 1 && !nearFountain(s) ? { x: s.x, y: s.y, t: s.t, last: s, modes: new Set([s.mode]) } : undefined;
                continue;
            }
            if (!anchor) anchor = { x: s.x, y: s.y, t: s.t, last: s, modes: new Set([s.mode]) };
            anchor.last = s;
            anchor.modes.add(s.mode);
        }
        if (anchor && anchor.last.t - anchor.t >= FROZEN_SECONDS)
            warns.push(`${name(game, b.pid)} stood still ${(anchor.last.t - anchor.t).toFixed(0)}s from ${fmtT(anchor.t)} at (${anchor.x}, ${anchor.y}) in ${[...anchor.modes].join('/')}`);
    }
    if (n === 0) return skip('frozen_bots', 'no bot snapshots');
    return result('frozen_bots', [], warns, `no bot stood still for ${FROZEN_SECONDS}s+ away from base`);
}

function trainerSelfTest(game) {
    const verdicts = game.events.filter(e => e.ev === 'trainer' && e.selftest === 1);
    if (verdicts.length < 20) return skip('trainer_selftest', `${verdicts.length} self-test verdicts (need 20)`);
    const count = k => verdicts.filter(v => v.kind === k).length;
    const good = (count('PERFECT') + count('OK')) / verdicts.length;
    const easy = count('MISSED_EASY') / verdicts.length;
    const line = `${verdicts.length} verdicts, PERFECT+OK ${(good * 100).toFixed(0)}%, MISSED_EASY ${(easy * 100).toFixed(0)}%`;
    const fails = [];
    if (good < 0.85) fails.push(`PERFECT+OK ${(good * 100).toFixed(1)}% < 85%`);
    if (easy >= 0.05) fails.push(`MISSED_EASY ${(easy * 100).toFixed(1)}% >= 5%`);
    return result('trainer_selftest', fails, [], line, line);
}

const ALL = [scriptErrors, snapshotGaps, noticeDelay, reactDelay, orderReadDelay, orderFollowed, lastHitEtiquette, intentHealth, frozenBots, trainerSelfTest];

function runChecks(game) {
    return ALL.map(check => check(game));
}

module.exports = { runChecks, fmtT, profileAt, delayBounds, modesDuring, expectedModes };
