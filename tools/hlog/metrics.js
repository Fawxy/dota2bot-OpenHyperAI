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
        const c = at(pid, 'caution');
        if (c !== undefined) out[pid].cautiousSec += clip(c, until, until);
    }
    return { complete: game.maxT >= until, build: build || 'unknown', bots: Object.values(out) };
}

module.exports = { laningMetrics, sourceOf };
