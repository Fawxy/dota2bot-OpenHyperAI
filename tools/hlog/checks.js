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

function snapshotGaps(game) {
    const fails = [];
    let botCount = 0;
    const end = game.maxT;
    for (const b of Object.values(game.bots)) {
        if (b.human || b.snaps.length === 0) continue;
        botCount++;
        for (let i = 1; i < b.snaps.length; i++) {
            const gap = b.snaps[i].t - b.snaps[i - 1].t;
            // Dota does not run a dead bot's script, so a death shows as a gap that ends in the fountain.
            if (gap > SNAP_GAP_FAIL && !nearFountain(b.snaps[i])) fails.push(`${name(game, b.pid)} no snapshot for ${gap.toFixed(1)}s from ${fmtT(b.snaps[i - 1].t)} (bot script stalled or errored)`);
        }
        const last = b.snaps[b.snaps.length - 1].t;
        if (!game.ended && end - last > SNAP_GAP_FAIL) fails.push(`${name(game, b.pid)} stopped reporting at ${fmtT(last)}, game ran to ${fmtT(end)}`);
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

// lane_fight warns once a bot has this many trades or commits and none took over, or this many cooldown reads.
const LANE_FIGHT_MIN_STARTS = 3;
const LANE_FIGHT_MIN_MEM = 4;
const NO_CD_SHARE = 0.5;

/** Per bot: lane-fight windows by type, starts by phase, ends by reason, took share, gates, aborts, mistakes, memory reads. */
function laneFightStats(game) {
    const bots = {};
    const get = pid =>
        (bots[pid] = bots[pid] || { pid, windows: new Map(), starts: new Map(), ends: new Map(), gates: new Map(), aborts: new Map(), mistakes: new Map(), fights: 0, took: 0, mem: 0, remembered: 0, noCd: 0 });
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
        else if (e.ev === 'lanefight_mem') {
            b.mem++;
            if (e.remembered === 1) b.remembered++;
            if (e.reason === 'no_cd') b.noCd++;
        }
    }
    return bots;
}

/** Lesson 22/23: fights that start but never act; and GetCooldown reading 0 on enemies (memory then needs Task 4b). */
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
        if (b.mem >= LANE_FIGHT_MIN_MEM && b.noCd / b.mem > NO_CD_SHARE)
            warns.push(`${name(game, b.pid)}: lanefight_mem reason=no_cd ${b.noCd}/${b.mem}: GetCooldown reads 0 on enemies, memory records nothing (Task 4b needed)`);
    }
    return result('lane_fight', [], warns, `${fights} trades/commits, ${took} took over`);
}

const ALL = [scriptErrors, snapshotGaps, noticeDelay, reactDelay, orderReadDelay, orderFollowed, lastHitEtiquette, intentHealth, frozenBots, trainerSelfTest, laneFight];

function runChecks(game) {
    return ALL.map(check => check(game));
}

module.exports = { runChecks, laneFightStats, fmtT, profileAt, delayBounds, modesDuring, expectedModes, modeChurn, BLIP_DWELL, LANING_ROAM_CAP };
