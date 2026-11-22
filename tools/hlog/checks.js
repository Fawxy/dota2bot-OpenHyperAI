// Two sets of checks over parsed games.
// runChecks: invariants of one game (analyse.js, er.js); each returns { id, level: pass|warn|fail|skip, summary, details }.
// TRIPWIRES: plain outcomes every full game owes, whoever decides (plan of 23/11/2026, step 2). batch.js runs them on
//   every batch; they read what happened, never our own reads, so they judge older logs and both teams. A design that
//   breaks one edits its line in the same merge.
// Usage: node checks.js <manifest | run> ...     prints only failures; exit 0 none, 1 some, 2 no games or bad usage
//   <run> is a batch name with a manifest in ~/.dotactl/batches, else a label prefix of the banked local and remote logs.
'use strict';

const fs = require('fs');
const os = require('os');
const path = require('path');
const { parseLog } = require('./parse');
const { readManifest } = require('./manifest');

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
// mode_team_roam_generic.lua wants 1.5 whenever X.GetLastHitCreep() finds a creep, and CapForLanePush holds
// that to 0.72 in the laning phase, so every last-hit attempt is a short team_roam visit out of laning. The bot
// often leaves it for attack or retreat rather than laning, so the exit mode does not matter.
const LANING_ROAM_CAP = 0.72;
const BLIP_DWELL = 2;
// Intent's Thrash.MaxSwitches: an episode fires once a bot makes more than this many switches in its window.
const THRASH_MAX_SWITCHES = 4;
const WORST_LATE_NOTICES = 5;

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
    // Errors caught by the humaniser guards: each line repeats with a running count, so keep the highest.
    const guarded = new Map();
    for (const e of game.events) {
        if (e.ev !== 'lua_error') continue;
        const key = `${e.where}: ${e.msg}`;
        const g = guarded.get(key) || { n: 0, t: e.t, tb: e.tb };
        g.n = Math.max(g.n, e.n || 1);
        guarded.set(key, g);
    }
    if (game.errors.length === 0 && guarded.size === 0) return { id: 'script_errors', level: 'pass', summary: 'no Lua errors in the console', details: [], more: 0 };
    const byText = new Map();
    for (const e of game.errors) {
        const g = byText.get(e.text) || { n: 0, t: e.t };
        g.n++;
        byText.set(e.text, g);
    }
    const when = t => (Number.isFinite(t) ? fmtT(t) : 'before the first event');
    const details = [
        ...[...guarded.entries()].map(([key, g]) => `guarded ${g.n}x from ${when(g.t)}: ${key}${g.tb ? ` (${g.tb})` : ''}`),
        ...[...byText.entries()].map(([text, g]) => `${g.n}x from ${when(g.t)}: ${text}`),
    ];
    const squelched = game.squelched ? '; Dota squelched repeats, so the real count is higher' : '';
    const parts = [];
    if (guarded.size > 0) parts.push(`${guarded.size} distinct errors caught in humaniser hooks`);
    if (game.errors.length > 0) parts.push(`${game.errors.length} console error lines (${byText.size} distinct)${squelched}`);
    return { id: 'script_errors', level: 'fail', summary: parts.join('; '), details: details.slice(0, DETAIL_LIMIT), more: Math.max(0, details.length - DETAIL_LIMIT) };
}

// Snapshots run about once a second, so the killer's count shows the kill within a few seconds of the victim going quiet.
const DEATH_KILL_WINDOW = 3;

function enemyKillSoonAfter(game, b, t) {
    for (const o of Object.values(game.bots)) {
        if (o.team === b.team || o.team === undefined) continue;
        for (let i = 1; i < o.snaps.length; i++) {
            const s = o.snaps[i];
            if (s.t > t + DEATH_KILL_WINDOW) break;
            if (s.t > t && s.kills > o.snaps[i - 1].kills) return true;
        }
    }
    return false;
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
            // dota_dev forcegamestart (scenario setups) jumps the clock from the pregame to 0:00 between two ticks.
            if (b.snaps[i - 1].t < 0 && b.snaps[i].t >= 0 && b.snaps[i].t < 2) continue;
            // Dota does not run a dead bot's script, so a death shows as a gap that ends in the fountain.
            if (gap > SNAP_GAP_FAIL && !nearFountain(b.snaps[i])) fails.push(`${name(game, b.pid)} no snapshot for ${gap.toFixed(1)}s from ${fmtT(b.snaps[i - 1].t)} (bot script stalled or errored)`);
        }
        const last = b.snaps[b.snaps.length - 1].t;
        // A death near the end leaves no fountain snapshot to excuse the gap.
        if (!game.ended && end - last > SNAP_GAP_FAIL && !enemyKillSoonAfter(game, b, last)) fails.push(`${name(game, b.pid)} stopped reporting at ${fmtT(last)}, game ran to ${fmtT(end)}`);
    }
    if (botCount === 0) return skip('snapshot_gaps', 'no bot snapshots');
    return result('snapshot_gaps', fails, [], `${botCount} bots reported continuously`);
}

function noticeDelay(game) {
    const fails = [];
    const late = [];
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
        else if (e.delay - e.due > 1) late.push({ e, by: e.delay - e.due, where });
    }
    if (n === 0) return skip('notice_delay', 'no delayed notices');
    if (late.length === 0) return result('notice_delay', fails, [], `${n} delayed notices within profile bounds`);
    const perBot = countBy(late, l => l.e.pid);
    const worst = [...late].sort((x, y) => y.by - x.by);
    const details = [
        ...fails,
        `late by bot: ${perBot.map(([pid, k]) => `${name(game, pid)} ${k}`).join(', ')}`,
        ...worst.slice(0, WORST_LATE_NOTICES).map(l => `${l.where}: noticed ${l.by.toFixed(2)}s after it was due (the bot did not look for enemies meanwhile)`),
    ];
    const summary = `${fails.length} fail, ${late.length} late notices across ${perBot.length} bots; worst ${worst[0].by.toFixed(2)}s`;
    return grouped('notice_delay', fails.length > 0 ? 'fail' : 'warn', summary, details);
}

/** [[key, count], ...], most frequent first; keys keep their first-seen order on ties. */
function countBy(items, key) {
    const m = new Map();
    for (const x of items) m.set(key(x), (m.get(key(x)) || 0) + 1);
    return [...m.entries()].sort((a, b) => b[1] - a[1]);
}

function grouped(id, level, summary, details) {
    return { id, level, summary, details: details.slice(0, DETAIL_LIMIT), more: Math.max(0, details.length - DETAIL_LIMIT) };
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

function pairKey(a, b) {
    return a < b ? `${a}<->${b}` : `${b}<->${a}`;
}

function tally(map, key, t) {
    const g = map.get(key) || { n: 0, t };
    g.n++;
    map.set(key, g);
}

function byCount(map) {
    return [...map.entries()].sort((a, b) => b[1].n - a[1].n);
}

/**
 * Per bot: its mode switches with upstream last-hit blips marked, counts of the other switches per mode pair,
 * and its thrash episodes split into blip-driven ones and genuine ones keyed by their dominant mode pair.
 */
function modeChurn(game) {
    const bots = {};
    const get = pid => (bots[pid] = bots[pid] || { pid, switches: [], blips: 0, pairs: new Map(), thrash: { blip: 0, genuine: new Map() } });
    const prev = {};
    for (const e of game.events) {
        if (e.ev !== 'mode') continue;
        const b = get(e.pid);
        const sw = { e, blip: false };
        b.switches.push(sw);
        const p = prev[e.pid];
        if (p && !p.blip && p.e.from === 'laning' && p.e.to === 'team_roam' && Math.abs(p.e.d - LANING_ROAM_CAP) < EPS && e.from === 'team_roam' && e.dwell <= BLIP_DWELL) {
            p.blip = sw.blip = true;
            b.blips++;
        }
        prev[e.pid] = sw;
    }
    for (const b of Object.values(bots)) for (const sw of b.switches) if (!sw.blip) tally(b.pairs, pairKey(sw.e.from, sw.e.to), sw.e.t);
    for (const e of game.events) {
        if (e.ev !== 'thrash') continue;
        const b = get(e.pid);
        const real = b.switches.filter(sw => !sw.blip && sw.e.t > e.t - e.window - FRAME_SLACK && sw.e.t <= e.t + FRAME_SLACK);
        // Without the blips this window would not have reached Intent's threshold, so the blips caused the episode.
        if (real.length <= THRASH_MAX_SWITCHES) {
            b.thrash.blip++;
            continue;
        }
        tally(b.thrash.genuine, countBy(real, sw => pairKey(sw.e.from, sw.e.to))[0][0], e.t);
    }
    return bots;
}

const TOP_GROUPS = 3;

function topGroups(groups) {
    const shown = groups.slice(0, TOP_GROUPS).map(([k, x]) => `${k} ${x.n}x from ${fmtT(x.t)}`);
    const rest = groups.slice(TOP_GROUPS).reduce((a, [, x]) => a + x.n, 0);
    return rest > 0 ? `${shown.join(', ')}, ${rest}x other` : shown.join(', ');
}

function intentHealth(game) {
    const churn = modeChurn(game);
    const stuck = {};
    for (const e of game.events) if (e.ev === 'stuck') tally((stuck[e.pid] = stuck[e.pid] || new Map()), e.mode, e.t);
    const pids = new Set([...Object.keys(churn), ...Object.keys(stuck)].map(Number));
    const rows = [];
    let genuine = 0;
    let blip = 0;
    let stuckN = 0;
    for (const pid of pids) {
        const c = churn[pid];
        const g = c ? byCount(c.thrash.genuine) : [];
        const s = stuck[pid] ? byCount(stuck[pid]) : [];
        const gN = g.reduce((a, [, x]) => a + x.n, 0);
        const sN = s.reduce((a, [, x]) => a + x.n, 0);
        const bN = c ? c.thrash.blip : 0;
        genuine += gN;
        blip += bN;
        stuckN += sN;
        if (gN + sN === 0) continue;
        const parts = [`${name(game, pid)}: ${gN + bN} thrash episodes (${bN} last-hit blips)`];
        if (g.length > 0) parts.push(topGroups(g));
        if (s.length > 0) parts.push(`stuck ${sN}x: ${topGroups(s)}`);
        rows.push({ n: gN + sN, line: parts.join('; ') });
    }
    const blipNote = `${blip} last-hit blip episode${blip === 1 ? '' : 's'} not counted (upstream team_roam, see mode churn)`;
    if (genuine + stuckN === 0) return grouped('intent_health', 'pass', blip > 0 ? `no stuck or genuine thrash episodes; ${blipNote}` : 'no stuck or thrash episodes', []);
    rows.sort((a, b) => b.n - a.n);
    return grouped('intent_health', 'warn', `${genuine} genuine thrash and ${stuckN} stuck episodes; ${blipNote}`, rows.map(r => r.line));
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

// lane_fight warns once a bot has this many trades or commits and none took over.
const LANE_FIGHT_MIN_STARTS = 3;

/** Per bot: lane-fight windows by type, starts by phase, ends by reason, took share, gates, aborts, mistakes. */
function laneFightStats(game) {
    const bots = {};
    const get = pid =>
        (bots[pid] = bots[pid] || { pid, windows: new Map(), starts: new Map(), ends: new Map(), gates: new Map(), aborts: new Map(), mistakes: new Map(), fights: 0, took: 0 });
    const add = (m, k) => m.set(k, (m.get(k) || 0) + 1);
    for (const e of game.events) {
        if (typeof e.ev !== 'string' || !e.ev.startsWith('lanefight_')) continue;
        const b = get(e.pid);
        if (e.ev === 'lanefight_window') add(b.windows, e.window);
        else if (e.ev === 'lanefight_start') add(b.starts, e.phase);
        else if (e.ev === 'lanefight_end') {
            add(b.ends, e.reason);
            // A wait never takes over by design; only trades and commits count towards the took share.
            if (e.phase === 'trade' || e.phase === 'commit') {
                b.fights++;
                if (e.took === 1) b.took++;
            }
        } else if (e.ev === 'lanefight_gate') add(b.gates, e.gate);
        else if (e.ev === 'lanefight_abort') add(b.aborts, e.reason);
        else if (e.ev === 'lanefight_mistake') add(b.mistakes, e.kind);
    }
    return bots;
}

/** Lesson 22: fights that start but never act. */
function laneFight(game) {
    const stats = Object.values(laneFightStats(game)).sort((a, b) => a.pid - b.pid);
    if (stats.length === 0) return skip('lane_fight', 'no lane-fight events');
    const warns = [];
    let fights = 0;
    let took = 0;
    for (const b of stats) {
        fights += b.fights;
        took += b.took;
        if (b.fights >= LANE_FIGHT_MIN_STARTS && b.took === 0)
            warns.push(`${name(game, b.pid)}: ${b.fights} trades/commits ended and none took over (ends: ${[...b.ends.entries()].map(([k, n]) => `${k} ${n}`).join(', ')})`);
    }
    return result('lane_fight', [], warns, `${fights} trades/commits, ${took} took over`);
}

// FarmPattern trips: how each one ended. Ends a trip is meant to have (back at the front, wave arrived, enemy, low HP,
// death, order, run) are fine; pre-emption by another mode (named in `to`), or the walk back timing out, means
// something out-bid or stalled it. Leaving many camps unfinished means the clear-time estimate runs short.
const FARM_OK_ENDS = new Set(['back', 'wave', 'enemy', 'low-hp', 'dead', 'order', 'run', 'retreat']);
// Valve's C++ attack mode (0.95) taking the core into a fight is the intended way out of a trip.
const FARM_OK_PREEMPT = new Set(['attack']);
const FARM_LATE_SHARE = 0.4;
const FARM_LATE_MIN = 3;

function farmTrips(game) {
    const starts = game.events.filter(e => e.ev === 'farm_trip_start');
    if (starts.length === 0) return skip('farm_trips', 'no farm trips');
    const ends = game.events.filter(e => e.ev === 'farm_trip_end');
    const returns = game.events.filter(e => e.ev === 'farm_trip_return');
    const odd = new Map();
    for (const e of ends) {
        if (FARM_OK_ENDS.has(e.why) || (e.why === 'preempted' && FARM_OK_PREEMPT.has(e.to))) continue;
        const key = `${name(game, e.pid)} ${e.why}${e.to ? ` -> ${e.to}` : ''}`;
        tally(odd, key, e.t);
    }
    const warns = byCount(odd).map(([k, g]) => `${k} ${g.n}x, first at ${fmtT(g.t)}`);
    const pids = [...new Set(returns.map(e => e.pid))];
    for (const pid of pids) {
        const mine = returns.filter(e => e.pid === pid);
        const late = mine.filter(e => e.why === 'late').length;
        if (late >= FARM_LATE_MIN && late / mine.length > FARM_LATE_SHARE)
            warns.push(`${name(game, pid)} left ${late}/${mine.length} camps unfinished: the clear estimate runs short`);
    }
    const okLine = `${starts.length} trips by ${new Set(starts.map(e => e.pid)).size} cores, all ended as planned`;
    return result('farm_trips', [], warns, okLine);
}

const ALL = [scriptErrors, snapshotGaps, noticeDelay, reactDelay, orderReadDelay, orderFollowed, lastHitEtiquette, intentHealth, frozenBots, farmTrips, trainerSelfTest, laneFight];

function runChecks(game) {
    return ALL.map(check => check(game));
}

// Tripwires. The margins are from 782 banked team-games with every switch of ours off (679 games, 06/11 to 23/11/2026).
const HORN_BY = 30;
const RUNE_JUMP = 20; // net worth in one snapshot interval: a bounty pays each hero 40, passive gold about 1.5 a second
const RUNE_HEROES = 3; // of five, so that one or two spending in that second do not hide the team's gold
const STARTING_GOLD = 600; // game fact; the most any banked hero held at the horn is 335
const RESPAWN_MAX = 100; // game fact: a dead hero logs nothing, and no respawn is longer
const EARLY_DEATH = 30; // the waves meet about now
const BASE_STAY = 60; // judgement; the longest stay of a switches-off hero is 37
const LANE_BY = 300;
const LANE_LEVEL = 2;
const LANE_LAST_HITS = 15; // judgement; the lowest switches-off team had 21
const TEAM_NAMES = { 2: 'Radiant', 3: 'Dire' };
const EXAMPLES = 3;

const lastBy = (b, t) => b.snaps.filter(s => s.t <= t).pop();
const logging = heroes => heroes.filter(b => b.snaps.length > 0);

function luaErrors(game) {
    const r = scriptErrors(game);
    return r.level === 'fail' ? `${r.summary}: ${r.details[0].slice(0, 200)}` : undefined;
}

function bothLog(game, heroes) {
    const seen = logging(heroes);
    if (seen.length !== 5) return `${seen.length} of 5 heroes logged`;
    for (const b of seen) {
        const times = [...b.snaps.map(s => s.t), game.maxT];
        for (let i = 1; i < times.length; i++) {
            if (times[i] - times[i - 1] > RESPAWN_MAX) return `${name(game, b.pid)} silent ${(times[i] - times[i - 1]).toFixed(0)} s from ${fmtT(times[i - 1])}`;
        }
    }
    return undefined;
}

function startItems(game, heroes) {
    const idle = logging(heroes).filter(b => {
        const s = lastBy(b, -0.01);
        return s && !(s.gold < STARTING_GOLD);
    });
    return idle.length ? `${idle.map(b => name(game, b.pid)).join(', ')} had not spent at the horn` : undefined;
}

/** A hero is paid by a jump in net worth with no last hit or kill of its own in that interval. */
function hornRunes(game, heroes) {
    const seen = logging(heroes);
    if (seen.length === 0) return undefined; // both_log says it
    if (!seen.some(b => b.snaps.some(s => typeof s.nw === 'number'))) return 'no net worth in the log, so not judged';
    const paid = seen.filter(b => b.snaps.some((s, i) => {
        const p = b.snaps[i - 1];
        return p && s.t > -1 && s.t <= HORN_BY && s.lh === p.lh && s.kills === p.kills && s.nw - p.nw >= RUNE_JUMP;
    }));
    if (paid.length >= RUNE_HEROES) return undefined;
    const modes = countBy(seen.map(b => lastBy(b, 0)).filter(Boolean), s => s.mode).map(([m, n]) => `${m} ${n}`).join(', ');
    return `${paid.length} of ${seen.length} paid by ${fmtT(HORN_BY)}; modes at 0:00: ${modes}`;
}

function earlyDeath(game, heroes) {
    for (const b of logging(heroes)) {
        for (let i = 1; i < b.snaps.length; i++) {
            const p = b.snaps[i - 1];
            if (p.t >= EARLY_DEATH) break;
            if (b.snaps[i].deaths > p.deaths) return `${name(game, b.pid)} died at ${fmtT(p.t)} in ${p.mode}`;
        }
    }
    return undefined;
}

function inBase(game, heroes) {
    const stays = [];
    for (const b of logging(heroes)) {
        let from;
        let longest;
        for (const s of b.snaps) {
            if (s.t < 0 || s.alive !== 1 || !nearFountain(s)) {
                from = undefined;
                continue;
            }
            from = from || s;
            const secs = s.t - from.t;
            if (secs >= BASE_STAY && (!longest || secs > longest.secs)) longest = { secs, at: from.t, mode: s.mode };
        }
        if (longest) stays.push(`${name(game, b.pid)} ${longest.secs.toFixed(0)} s from ${fmtT(longest.at)} in ${longest.mode}`);
    }
    return stays.length ? stays.join(', ') : undefined;
}

function laneXp(game, heroes) {
    const low = logging(heroes).filter(b => {
        const s = lastBy(b, LANE_BY);
        return s && !(s.lvl >= LANE_LEVEL);
    });
    return low.length ? `${low.map(b => name(game, b.pid)).join(', ')} under level ${LANE_LEVEL}` : undefined;
}

function laneFarm(game, heroes) {
    const at = logging(heroes).map(b => lastBy(b, LANE_BY)).filter(Boolean);
    if (at.length === 0) return undefined; // both_log says it
    const n = at.reduce((a, s) => a + (s.lh || 0), 0);
    return n < LANE_LAST_HITS ? `${n} last hits` : undefined;
}

// `from`: the game time a game must have reached to be judged. `game`: judged once a game, not once a team.
// prettier-ignore
const TRIPWIRES = [
    { id: 'lua_errors',  from: -Infinity,   find: luaErrors,  game: true, what: 'no Lua error' },
    { id: 'both_log',    from: -Infinity,   find: bothLog,    what: 'five heroes a team log all game' },
    { id: 'start_items', from: 0,           find: startItems, what: 'every hero has spent at the horn' },
    { id: 'horn_runes',  from: HORN_BY,     find: hornRunes,  what: 'the team has 0:00 bounty gold by 0:30' },
    { id: 'early_death', from: EARLY_DEATH, find: earlyDeath, what: 'nobody dies before the waves meet (0:30)' },
    { id: 'in_base',     from: BASE_STAY,   find: inBase,     what: 'nobody alive stays a minute in base' },
    { id: 'lane_xp',     from: LANE_BY,     find: laneXp,     what: 'every hero is level 2 by 5:00' },
    { id: 'lane_farm',   from: LANE_BY,     find: laneFarm,   what: 'the team has 15 last hits by 5:00' },
];

/** One game's failed tripwires: { id, what, why, team, side }. `side` is `ours` when the team has a switch of ours on. */
function tripwires(game) {
    const bots = Object.values(game.bots);
    const teams = [2, 3].map(team => {
        const heroes = bots.filter(b => b.team === team);
        const ours = heroes.some(b => b.profiles.some(p => /:1(,|$)/.test(String(p.ours || ''))));
        return { team, heroes, side: ours ? 'ours' : 'off' };
    });
    const out = [];
    for (const { id, what, from, find, game: once } of TRIPWIRES) {
        if (game.maxT < from) continue;
        for (const { team, heroes, side } of once ? [{ heroes: bots, side: 'game' }] : teams) {
            const why = find(game, heroes);
            if (why) out.push({ id, what, why, team, side });
        }
    }
    return out;
}

/**
 * A batch's failures as printable lines, grouped by wire, arm and side: { failures, lines }, both empty when all pass.
 * `games` are manifest rows ({ label, arm, log }); each log's last game is judged.
 */
function tripReport(games) {
    const groups = new Map();
    const perArm = new Map();
    let failures = 0;
    for (const g of games) {
        const arm = g.arm ? ` arm=${g.arm}` : '';
        perArm.set(arm, (perArm.get(arm) || 0) + 1);
        let found;
        try {
            const game = parseLog(fs.readFileSync(g.log, 'utf8')).pop();
            found = game ? tripwires(game) : [{ id: 'unreadable', what: 'the log holds a game', why: 'no game in the log', side: 'game' }];
        } catch (e) {
            found = [{ id: 'unreadable', what: 'the log can be judged', why: e.message, side: 'game' }];
        }
        for (const f of found) {
            failures++;
            const head = `TRIPWIRE ${f.id}${arm} ${f.side}`;
            if (!groups.has(head)) groups.set(head, { arm, what: f.what, labels: new Set(), examples: [] });
            const group = groups.get(head);
            group.labels.add(g.label);
            group.examples.push(`  ${g.label}${f.team ? ` ${TEAM_NAMES[f.team]}` : ''}: ${f.why}`);
        }
    }
    const lines = [];
    for (const [head, g] of groups) {
        lines.push(`${head}: ${g.labels.size} of ${perArm.get(g.arm)} games (${g.what})`, ...g.examples.slice(0, EXAMPLES));
        if (g.examples.length > EXAMPLES) lines.push(`  and ${g.examples.length - EXAMPLES} more`);
    }
    return { failures, lines };
}

/** The games a command-line argument names: a manifest, a batch with one, or a run's banked logs (newest per label). */
function gamesFor(arg) {
    if (fs.existsSync(arg) && fs.statSync(arg).isFile()) return readManifest(arg);
    const manifest = path.join(os.homedir(), '.dotactl', 'batches', `${arg}.manifest`);
    if (fs.existsSync(manifest)) return readManifest(manifest);
    const { LOGS, JOBS, labelOf } = require('./store');
    const list = dir => (fs.existsSync(dir) ? fs.readdirSync(dir).map(f => path.join(dir, f)) : []);
    const files = [...list(LOGS).filter(f => f.endsWith('.log')), ...list(JOBS).map(d => path.join(d, 'game.log')).filter(f => fs.existsSync(f))];
    const newest = new Map();
    for (const log of files) {
        const label = labelOf(log);
        if (!label || !(label === arg || label.startsWith(`${arg}_`))) continue;
        const mtime = fs.statSync(log).mtimeMs;
        if (!newest.has(label) || mtime > newest.get(label).mtime) newest.set(label, { label, log, mtime });
    }
    return [...newest.values()].sort((a, b) => a.label.localeCompare(b.label));
}

function main(argv) {
    const help = argv.includes('--help') || argv.includes('-h');
    if (help || argv.length === 0 || argv.some(a => a.startsWith('-'))) {
        const head = fs.readFileSync(__filename, 'utf8').split(/\r?\n/);
        console.log(head.slice(0, head.indexOf("'use strict';")).map(l => l.replace(/^\/\/ ?/, '')).join('\n'));
        for (const w of TRIPWIRES) console.log(`  ${w.id.padEnd(12)} ${w.what}`);
        return help ? 0 : 2;
    }
    const games = [];
    for (const arg of argv) {
        const found = gamesFor(arg);
        if (found.length === 0) {
            console.error(`no games for ${arg}`);
            return 2;
        }
        games.push(...found);
    }
    const { failures, lines } = tripReport(games);
    for (const line of lines) console.log(line);
    return failures ? 1 : 0;
}

module.exports = { TRIPWIRES, tripwires, tripReport, runChecks, laneFightStats, fmtT, profileAt, delayBounds, modesDuring, expectedModes, modeChurn, BLIP_DWELL, LANING_ROAM_CAP };

if (require.main === module) process.exitCode = main(process.argv.slice(2));
