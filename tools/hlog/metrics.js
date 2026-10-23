// Per-bot laning-phase metrics for before/after comparisons of humaniser builds (compare.js).
'use strict';

const HEALTHY_HP = 60;

/** The claim source in a mode event's by= text ("retreat 1.10 by transitions:caution+sticky" -> "transitions:caution"). */
function sourceOf(by) {
    if (typeof by !== 'string') return 'raw';
    const i = by.lastIndexOf(' by ');
    return (i >= 0 ? by.slice(i + 4) : by).replace(/\+sticky$/, '');
}

/** Seconds of [a, b) clipped to [0, until). */
function clip(a, b, until) {
    return Math.max(0, Math.min(b, until) - Math.max(a, 0));
}

/** Seconds of [a, b) during which the latest snap at or before each instant had hp >= HEALTHY_HP. */
function healthySeconds(snaps, a, b) {
    let total = 0;
    for (let i = 0; i < snaps.length; i++) {
        const from = Math.max(a, snaps[i].t);
        const to = Math.min(b, i + 1 < snaps.length ? snaps[i + 1].t : Infinity);
        if (to > from && snaps[i].hp >= HEALTHY_HP) total += to - from;
    }
    return total;
}

function emptyBot(b) {
    const profile = b.profiles[b.profiles.length - 1] || {};
    return {
        pid: b.pid,
        hero: b.hero,
        team: b.team,
        pos: profile.pos,
        lh: 0,
        dn: 0,
        kills: 0,
        deaths: 0,
        laningSec: 0,
        retreatSec: 0,
        retreatHealthySec: 0,
        retreatBy: {},
        cautiousSec: 0,
        commits: 0,
        commitKills: 0,
        commitSec: 0,
        trades: 0,
        pullsStarted: 0,
        stacksStarted: 0,
        rotations: 0,
        aggroWithLastHit: 0,
    };
}

/** Laning metrics up to `until` game seconds for every bot in a parsed game (parse.js). */
function laningMetrics(game, { until = 600 } = {}) {
    const out = {};
    let build;
    for (const b of Object.values(game.bots)) {
        if (b.human) continue;
        out[b.pid] = emptyBot(b);
        for (const p of b.profiles) if (p.build !== undefined && build === undefined) build = String(p.build);
        const snaps = b.snaps.filter(s => s.t <= until);
        const last = snaps[snaps.length - 1];
        if (last) {
            out[b.pid].lh = last.lh;
            out[b.pid].dn = last.dn;
        }
        // Schema 2 snapshots carry the scoreboard; older logs only show a death if a snapshot caught alive=0.
        if (last && typeof last.deaths === 'number') {
            out[b.pid].deaths = last.deaths;
            out[b.pid].kills = typeof last.kills === 'number' ? last.kills : 0;
        } else for (let i = 1; i < snaps.length; i++) if (snaps[i - 1].alive === 1 && snaps[i].alive === 0) out[b.pid].deaths++;
    }
    const open = {};
    const at = (pid, key) => (open[pid] = open[pid] || {})[key];
    const set = (pid, key, v) => ((open[pid] = open[pid] || {})[key] = v);
    const snapsOf = pid => (game.bots[pid] ? game.bots[pid].snaps : []);
    const closeLaning = (pid, t) => {
        const l = at(pid, 'laning');
        if (l === undefined) return;
        out[pid].laningSec += clip(l, t, until);
        set(pid, 'laning', undefined);
    };
    const closeRetreat = (pid, t) => {
        const r = at(pid, 'retreat');
        if (r === undefined) return;
        const m = out[pid];
        const secs = clip(r.t, t, until);
        m.retreatSec += secs;
        m.retreatBy[r.src] = (m.retreatBy[r.src] || 0) + secs;
        m.retreatHealthySec += healthySeconds(snapsOf(pid), Math.max(r.t, 0), Math.min(t, until));
        set(pid, 'retreat', undefined);
    };
    for (const e of game.events) {
        const m = out[e.pid];
        if (m === undefined) continue;
        if (e.ev === 'mode') {
            closeRetreat(e.pid, e.t);
            closeLaning(e.pid, e.t);
            if (e.to === 'laning') set(e.pid, 'laning', e.t);
            if (e.to === 'retreat') set(e.pid, 'retreat', { t: e.t, src: sourceOf(e.by) });
        } else if (e.ev === 'tr_caution') {
            const c = at(e.pid, 'caution');
            if (c !== undefined) m.cautiousSec += clip(c, e.t, until);
            set(e.pid, 'caution', e.level > 0 ? e.t : undefined);
        } else if (e.t > until) continue;
        else if (e.ev === 'lanefight_start') {
            if (e.phase === 'commit') {
                m.commits++;
                set(e.pid, 'commit', e.t);
            } else if (e.phase === 'trade') m.trades++;
        } else if (e.ev === 'lanefight_end' && e.phase === 'commit') {
            if (e.reason === 'target-dead') m.commitKills++;
            const c = at(e.pid, 'commit');
            if (c !== undefined) m.commitSec += e.t - c;
            set(e.pid, 'commit', undefined);
        } else if (e.ev === 'lane_job_start') {
            if (e.kind === 'stack') m.stacksStarted++;
            else if (e.kind !== 'contest') m.pullsStarted++;
        } else if (e.ev === 'tr_rotate' && e.go === 1) m.rotations++;
        else if (e.ev === 'lane_tech' && e.tech === 'aggro_pull' && e.lh === 1) m.aggroWithLastHit++;
    }
    for (const pid of Object.keys(out)) {
        closeRetreat(pid, until);
        closeLaning(pid, until);
        const c = at(pid, 'caution');
        if (c !== undefined) out[pid].cautiousSec += clip(c, until, until);
    }
    return { complete: game.maxT >= until, build: build || 'unknown', bots: Object.values(out) };
}

// ---------------------------------------------------------------------------------------------- states (H2)

/** BOT_MODE ids as telemetry's ModeName prints them (debug.ts). */
const MODE_NAMES = {
    0: 'none', 1: 'laning', 2: 'attack', 3: 'roam', 4: 'retreat', 5: 'secret_shop', 6: 'side_shop', 7: 'rune',
    8: 'push_top', 9: 'push_mid', 10: 'push_bot', 11: 'defend_top', 12: 'defend_mid', 13: 'defend_bot',
    14: 'assemble', 16: 'team_roam', 17: 'farm', 18: 'defend_ally', 19: 'evasive', 20: 'roshan', 21: 'item', 22: 'ward',
};

/**
 * OHA interrupts (PLAN 2.1: not states): while one of these is the active mode the state is kept but its host
 * is not expected to run, so those seconds are left out of agreement. Ids: attack 2, retreat 4, shops 5/6,
 * push 8-10, defend 11-13, assemble 14, team_roam 16, defend_ally 18, evasive 19, roshan 20, item 21, ward 22.
 */
const INTERRUPT_MODES = new Set([2, 4, 5, 6, 8, 9, 10, 11, 12, 13, 14, 16, 18, 19, 20, 21, 22].map(id => MODE_NAMES[id]));

/** Host modes a state agrees with (states/*.ts `host`; rotate's ganks run in roam). */
const STATE_HOSTS = { laning: ['laning'], pull: ['farm'], stack: ['farm'], rotate: ['rune', 'roam'], farm: ['farm'] };

/** Mode episodes shorter than this (s) are blips (e.g. farm's 0.3 s last-hit grabs from lane); agreeLong leaves them out. */
const BLIP = 2;

/** For each snapshot time (ascending), the length of the active-mode episode around it, from ev=mode transitions. */
function episodeLengths(modes, times, end) {
    const out = [];
    let i = 0;
    for (const t of times) {
        while (i < modes.length && modes[i].t <= t) i++;
        const start = i > 0 ? modes[i - 1].t : -Infinity;
        const stop = i < modes.length ? modes[i].t : end;
        out.push(stop - start);
    }
    return out;
}

function median(xs) {
    if (xs.length === 0) return undefined;
    const s = xs.slice().sort((a, b) => a - b);
    const m = s.length >> 1;
    return s.length % 2 ? s[m] : (s[m - 1] + s[m]) / 2;
}

function modeLabel(msg) {
    const m = /^mode=(\d+)$/.exec(String(msg));
    return m ? MODE_NAMES[m[1]] || `mode_${m[1]}` : msg;
}

/**
 * Per bot: seconds per state (from 1 s snapshots, alive only), switches/min, agreement of the state's host
 * with the active mode outside interrupts, task starts and restart lag, task end reasons, lane_pos distance.
 * The restart lag is from the host mode becoming active again (after the end) to the restart. Snapshots before
 * `from` (default 0:00: pre-horn rune and ward walks) are not counted.
 */
function stateMetrics(game, { until = 600, from = 0 } = {}) {
    const rows = {};
    const evs = {};
    for (const e of game.events) {
        if (e.t > until || e.pid === undefined) continue;
        if (e.ev === 'state' || e.ev === 'state_start' || e.ev === 'state_task' || e.ev === 'lane_pos' || e.ev === 'mode') {
            (evs[e.pid] = evs[e.pid] || []).push(e);
        }
    }
    for (const b of Object.values(game.bots)) {
        if (b.human) continue;
        const list = evs[b.pid] || [];
        const changes = list.filter(e => e.ev === 'state');
        if (changes.length === 0) continue;
        const profile = b.profiles[b.profiles.length - 1] || {};
        const r = {
            pid: b.pid, team: b.team, pos: profile.pos, hero: b.hero,
            secs: {}, switches: 0, minutes: 0, agreeSec: 0, compareSec: 0, interruptSec: 0, noneSec: 0,
            agreeLongSec: 0, compareLongSec: 0, laningModeSec: 0, laningCoverSec: 0, disagree: {}, starts: 0, restartLags: [], restartGaps: [], ends: {}, laneD: [], laneDHold: [],
        };
        let k = 0;
        let state = 'none';
        const snaps = b.snaps.filter(p => p.t <= until);
        const episodes = episodeLengths(list.filter(e => e.ev === 'mode'), snaps.map(p => p.t), Math.min(until, game.maxT));
        for (let i = 0; i < snaps.length; i++) {
            const p = snaps[i];
            while (k < changes.length && changes[k].t <= p.t) state = changes[k++].to;
            if (p.alive !== 1 || p.t < from) continue;
            const dt = i + 1 < snaps.length ? Math.min(Math.max(snaps[i + 1].t - p.t, 0), 2) : 1;
            r.secs[state] = (r.secs[state] || 0) + dt;
            // Slice 1's bar: the laning state covers the time Dota's laning mode is active.
            if (p.mode === 'laning') {
                r.laningModeSec += dt;
                if (state === 'laning') r.laningCoverSec += dt;
            }
            if (state === 'none') {
                r.noneSec += dt;
                continue;
            }
            if (INTERRUPT_MODES.has(p.mode)) {
                r.interruptSec += dt;
                continue;
            }
            r.compareSec += dt;
            const agrees = (STATE_HOSTS[state] || []).includes(p.mode);
            if (episodes[i] >= BLIP) {
                r.compareLongSec += dt;
                if (agrees) r.agreeLongSec += dt;
            }
            if (agrees) r.agreeSec += dt;
            else {
                const key = `${state}/${p.mode}`;
                r.disagree[key] = (r.disagree[key] || 0) + dt;
            }
        }
        const first = changes[0].t;
        const last = Math.min(until, game.maxT);
        r.minutes = Math.max(0, last - Math.max(first, from)) / 60;
        for (const e of changes) if (e.from !== e.to && e.from !== 'none' && e.t >= from) r.switches++;
        // Mode transitions in order, for the restart lag.
        const modes = list.filter(e => e.ev === 'mode');
        let lastEnd;
        for (const e of list) {
            if (e.ev === 'state_task') {
                const key = e.reason === 'preempted' || e.reason === 'cancelled' ? `${e.reason}:${modeLabel(e.msg)}` : String(e.reason);
                r.ends[key] = (r.ends[key] || 0) + 1;
                lastEnd = e;
            } else if (e.ev === 'state_start') {
                r.starts++;
                if (typeof e.gap === 'number') r.restartGaps.push(e.gap);
                if (lastEnd !== undefined && e.after === 'preempted') {
                    const host = (STATE_HOSTS[e.state] || [])[0];
                    let back;
                    for (const m of modes) if (m.t >= lastEnd.t && m.t <= e.t && m.to === host) back = m.t;
                    if (back !== undefined) r.restartLags.push(e.t - back);
                }
                lastEnd = undefined;
            } else if (e.ev === 'lane_pos' && typeof e.d === 'number') {
                r.laneD.push(e.d);
                if (e.owned === 1 && e.label === 'hold') r.laneDHold.push(e.d);
            }
        }
        rows[b.pid] = r;
    }
    return Object.values(rows);
}

module.exports = { laningMetrics, sourceOf, stateMetrics, median, MODE_NAMES, INTERRUPT_MODES, STATE_HOSTS, BLIP };
