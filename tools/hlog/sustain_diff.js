#!/usr/bin/env node
'use strict';
// Sustain shadow diff (design 2026-11-19-sustain-design.md s6 check 2): where the one sustain decision, run in shadow
// (ev=cut kind=sustain, sustain_gather.ts), differs from what the game did. A diff to attribute by, not a bar.
//   node sustain_diff.js <log> [<log> ...] [--game N] [--rows 2] [--json]
// --game: which game of a log (default the last: a remote job's game 1 is a stub). --rows N: N example moments per group.
//
// Shadow episodes: a hero's run of cut lines with one answer (kind and item); a new one starts when the answer changes or
// after a gap over GAP s. What the game did: regen buff starts (ev=regen_obs state=start: tango, salve, clarity, with `by`)
// and arrivals home (a snapshot within BASE_R of the own fountain, alive, after one outside it, not a respawn).
// Matching, per hero:
//  - use (tango, salve, clarity): the game started that item's buff within [t - BEFORE, t + USE_AFTER] of the shadow's start:
//    matched, with the lead (game minus shadow, s); none: shadow only (an earlier or an extra use). A game start with no
//    shadow use of it in [t' - USE_AFTER, t' + BEFORE]: game only.
//  - home: an arrival within HOME_AFTER s after the shadow's start: matched (a trip both take); none: trip added. An
//    arrival with no shadow home in the HOME_AFTER s before: trip avoided.
//  - other uses (wand, stick, faerie fire, bottle, mango), buy, give, step-out uses of other items: shadow counts only
//    (their game side is not observed yet).
// Side: `ours` when the hero's ev=bot line has an Ours switch on, else `oha` (as lane_score.js).
const fs = require('fs');
const { parseLog } = require('./parse');

const C = { GAP: 3, BEFORE: 2, USE_AFTER: 20, HOME_AFTER: 60, BASE_R: 1500 };
const FOUNTAIN = { 2: [-6619, -6336], 3: [6928, 6372] };
const OBSERVED = { tango: 'tango', tango_single: 'tango', flask: 'salve', clarity: 'clarity' };

const num = (v) => (v === undefined || v === '' ? undefined : Number(v));
const recs = (s) => (s === undefined || s === '' ? [] : String(s).split(';').filter(Boolean).map((r) => r.split(',')));

/** `srn` (sustain_gather.ts RunText) back into Sustain.Run. */
function runOf(s, now) {
    const [kind, slot, name, age, hp0, dur, x, y] = s.split(',');
    return {
        kind, started: now - Number(age), hp0: Number(hp0),
        ...(slot === '' ? {} : { slot: Number(slot) }), ...(name === '' ? {} : { name }),
        ...(dur === '' ? {} : { dur: Number(dur) }), ...(x === '' ? {} : { at: { x: Number(x), y: Number(y) } }),
    };
}

/**
 * One cut line's fields back into sustain.ts's Inputs (the fields sustain_gather.ts CutFields writes). A step 2 line (`lb`,
 * no `kill`) carries the old danger inputs: its `tree` and `safe` are left as that line can give them, so a replay of an
 * old log is a direction only.
 */
function inputsOf(c) {
    const items = recs(c.it).map(([slot, name, uses, hp, mp, dur, br, tr, rf, sh, rd]) => ({
        slot: +slot, name, charges: +uses, hp: +hp, mp: +mp, dur: +dur, breaks: br === '1', tree: tr === '1', refill: rf === '1', share: sh === '1',
        ready: rd === undefined ? undefined : rd === '1',
    }));
    const tr = c.tr !== undefined ? String(c.tr).split(',').map(Number) : undefined;
    const ss = c.ss !== undefined ? String(c.ss).split(',').map(Number) : undefined;
    const dl = c.dl !== undefined ? String(c.dl).split(',').map(Number) : undefined;
    const old = c.kill === undefined && c.lb !== undefined;
    return {
        now: num(c.t), hp: num(c.hpa), hpMax: num(c.hpm), mp: num(c.mpa), mpMax: num(c.mpm), items,
        tree: tr ? (old ? { walk: 0, safe: tr[0] <= 600 && (tr[1] < 0 || tr[0] < tr[1]) } : { walk: tr[0], safe: tr[1] === 1, start: tr[2] === undefined ? undefined : tr[2] === 1 }) : undefined,
        nextDue: num(c.nd),
        hitRecently: num(c.hr) === 1,
        safe: old
            ? { kill: (num(c.lb) || 0) / 1.5, hitting: num(c.hr) === 1 && (num(c.rc) || 0) > 0, reach: num(c.rc) || 0 }
            : { kill: num(c.kill) || 0, hitting: num(c.sh) === 1, reach: num(c.rc) || 0, ...(c.spr === undefined ? {} : { pressed: num(c.spr) === 1 }) },
        regenLeft: num(c.rl) || 0, manaLeft: num(c.ml) || 0,
        safeSpot: ss ? Object.assign({ x: ss[0], y: ss[1], walk: ss[2] }, ss[3] === undefined ? {} : { ok: ss[3] === 1 }) : undefined,
        delivery: dl ? { hp: dl[0], mp: dl[1], eta: dl[2] } : undefined,
        gold: num(c.gd), courier: c.co !== undefined ? { eta: num(c.co) } : undefined,
        shop: recs(c.shp).map(([name, cost, hp, mp]) => ({ name, cost: +cost, hp: +hp, mp: +mp })),
        home: num(c.ho), idle: num(c.idl) === 1, atFountain: num(c.af) === 1,
        allies: recs(c.als).map(([pid, missing, heals]) => ({ pid: +pid, missing: +missing, heals: +heals })),
        ...(c.rom === undefined ? {} : { room: num(c.rom) === 1 }),
        ...(c.srn === undefined || c.srn === '' ? {} : { run: runOf(String(c.srn), num(c.t)) }),
    };
}

/** Shadow episodes per pid: { pid, t, kind, name, why } at each answer change. */
function episodes(cuts) {
    const last = new Map();
    const out = [];
    for (const c of cuts) {
        const key = `${c.ak}:${c.anm ?? ''}`;
        const p = last.get(c.pid);
        if (p === undefined || p.key !== key || c.t - p.t > C.GAP) out.push({ pid: c.pid, t: c.t, kind: c.ak, name: c.anm, why: c.why });
        last.set(c.pid, { key, t: c.t });
    }
    return out;
}

/** Arrivals home per pid: { pid, t, hp } (a snapshot within BASE_R of the own fountain after one outside it, deaths unchanged). */
function arrivals(snaps, teamOf) {
    const prev = new Map();
    const out = [];
    for (const s of snaps) {
        const f = FOUNTAIN[teamOf(s.pid)];
        if (!f || s.x === undefined) continue;
        const home = Math.hypot(s.x - f[0], s.y - f[1]) <= C.BASE_R;
        const p = prev.get(s.pid);
        if (p && home && !p.home && s.alive !== 0 && (s.deaths || 0) === (p.deaths || 0)) out.push({ pid: s.pid, t: s.t, hp: s.hp });
        prev.set(s.pid, { home, deaths: s.deaths });
    }
    return out;
}

const median = (xs) => {
    if (xs.length === 0) return null;
    const s = [...xs].sort((a, b) => a - b);
    return s.length % 2 ? s[(s.length - 1) / 2] : (s[s.length / 2 - 1] + s[s.length / 2]) / 2;
};

/** The diff of one game: groups keyed `side kind item verdict` with counts, leads and example moments. */
function diffGame(game, file) {
    const ev = game.events;
    const bots = new Map();
    for (const e of ev) if (e.ev === 'bot') bots.set(e.pid, e);
    const sideOf = (pid) => (/:1/.test(String(bots.get(pid)?.ours || '')) ? 'ours' : 'oha');
    const teamOf = (pid) => bots.get(pid)?.team ?? (pid < 5 ? 2 : 3);
    const cuts = ev.filter((e) => e.ev === 'cut' && e.kind === 'sustain');
    const eps = episodes(cuts);
    const starts = ev.filter((e) => e.ev === 'regen_obs' && e.state === 'start');
    const arr = arrivals(ev.filter((e) => e.ev === 'snap'), teamOf);
    const until = cuts.length ? Math.max(...cuts.map((c) => c.t)) : 0;
    const groups = new Map();
    const add = (pid, kind, item, verdict, t, lead) => {
        const k = `${sideOf(pid)} ${kind} ${item || '-'} ${verdict}`;
        const g = groups.get(k) || { side: sideOf(pid), kind, item: item || '-', verdict, n: 0, leads: [], rows: [] };
        g.n++;
        if (lead !== undefined) g.leads.push(lead);
        g.rows.push({ pid, t, file });
        groups.set(k, g);
    };
    // A game start matches one shadow use at most (the first in time); a second shadow episode before it is shadow only.
    const taken = new Set();
    for (const e of eps) {
        if (e.kind === 'none') continue;
        const obs = OBSERVED[e.name];
        if ((e.kind === 'use' || e.kind === 'step_out_use') && obs) {
            const hit = starts.find((s) => !taken.has(s) && s.pid === e.pid && s.item === obs && s.t >= e.t - C.BEFORE && s.t <= e.t + C.USE_AFTER);
            if (hit) taken.add(hit);
            add(e.pid, 'use', obs, hit ? 'matched' : 'shadow_only', e.t, hit ? hit.t - e.t : undefined);
        } else if (e.kind === 'home') {
            const hit = arr.find((a) => a.pid === e.pid && a.t >= e.t && a.t <= e.t + C.HOME_AFTER);
            add(e.pid, 'home', e.why, hit ? 'matched' : 'trip_added', e.t);
        } else add(e.pid, e.kind, e.name, 'shadow_only', e.t);
    }
    const shadowed = new Set(cuts.map((c) => c.pid));
    for (const s of starts) {
        if (!shadowed.has(s.pid) || s.t > until) continue;
        const had = eps.some((e) => e.pid === s.pid && (e.kind === 'use' || e.kind === 'step_out_use') && OBSERVED[e.name] === s.item && e.t >= s.t - C.USE_AFTER && e.t <= s.t + C.BEFORE);
        if (!had) add(s.pid, 'use', s.item, `game_only_${s.by || 'oha'}`, s.t);
    }
    for (const a of arr) {
        if (!shadowed.has(a.pid) || a.t > until + C.HOME_AFTER) continue;
        const had = eps.some((e) => e.pid === a.pid && e.kind === 'home' && e.t <= a.t && e.t >= a.t - C.HOME_AFTER);
        if (!had) add(a.pid, 'home', '-', 'trip_avoided', a.t);
    }
    return { groups, heroes: shadowed.size, cuts: cuts.length };
}

function main(argv) {
    const args = argv.slice(2);
    const opt = { rows: 0, json: false, game: undefined };
    const files = [];
    for (let i = 0; i < args.length; i++) {
        if (args[i] === '--rows') opt.rows = Number(args[++i]);
        else if (args[i] === '--game') opt.game = Number(args[++i]);
        else if (args[i] === '--json') opt.json = true;
        else files.push(args[i]);
    }
    if (files.length === 0) {
        console.error('usage: node sustain_diff.js <log> [<log> ...] [--game N] [--rows 2] [--json]');
        return 2;
    }
    const all = new Map();
    let heroes = 0, cuts = 0, games = 0;
    for (const f of files) {
        const gs = parseLog(fs.readFileSync(f, 'utf8'));
        const g = opt.game !== undefined ? gs[opt.game - 1] : gs[gs.length - 1];
        if (!g) continue;
        games++;
        const d = diffGame(g, f);
        heroes += d.heroes;
        cuts += d.cuts;
        for (const [k, v] of d.groups) {
            const a = all.get(k) || { ...v, n: 0, leads: [], rows: [] };
            a.n += v.n;
            a.leads.push(...v.leads);
            a.rows.push(...v.rows);
            all.set(k, a);
        }
    }
    const list = [...all.values()].sort((a, b) => a.side.localeCompare(b.side) || a.kind.localeCompare(b.kind) || b.n - a.n);
    if (opt.json) {
        console.log(JSON.stringify({ games, heroes, cuts, groups: list.map((g) => ({ ...g, lead: median(g.leads), rows: g.rows.slice(0, opt.rows) })) }, null, 1));
        return 0;
    }
    console.log(`games ${games}, shadowed hero-games ${heroes}, cut lines ${cuts}; per game:`);
    console.log('side  kind          item         verdict            per_game  lead_s');
    for (const g of list) {
        const lead = median(g.leads);
        console.log(`${g.side.padEnd(5)} ${g.kind.padEnd(13)} ${String(g.item).padEnd(12)} ${g.verdict.padEnd(18)} ${(g.n / Math.max(1, games)).toFixed(2).padStart(8)}  ${lead === null ? '-' : lead.toFixed(1)}`);
        for (const r of g.rows.slice(0, opt.rows)) console.log(`        pid ${r.pid} t ${r.t} ${r.file}`);
    }
    return 0;
}

if (require.main === module) process.exitCode = main(process.argv);
module.exports = { inputsOf, runOf, episodes, arrivals, diffGame, C };
