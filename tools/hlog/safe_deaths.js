#!/usr/bin/env node
'use strict';
// Safe-here death replay (design 2026-11-19-safe-here-design.md s2 and s6.2): banked ev=cut kind=leave lines mapped into
// Safe.Inputs, the built Safe.Decide (bots/FunLib/humaniser/safe.lua) run at stay 1.0, 1.25, 1.5 and 2.0, and three tables
// that choose the `stay` bar. "today" is the game's own answer: `dec` lethal, tower, heal or threat is a leave (deadly).
//   node safe_deaths.js --batch a,b,c [--shadow] [--rows N] [--json]
//   node safe_deaths.js <log> [<log> ...] [--shadow] [--game N] [--rows N] [--json]
// --shadow: the source is the bot's own shadow read (ev=cut kind=safe, who=leave or who=retreat: the hero's place outside and inside
//   a retreat episode) instead of the old leave lines; Decide runs on the logged inputs, and Tables 4 and 5 are added (see below).
// --batch: every banked game of those batches (bank.js). --game: which game of a log (default the last: a remote job's game 1
// is a stub). --rows N: N example moments (file, pid, t) per cell of table 1 where today called and the bar missed, and the reverse.
// Table 1: our deaths with a leave line in the 10 s before: how many had a deadly answer, the median seconds from the first one
//   to the death, by heroes in reach then and the answer's reason. Deaths with no leave line in those 10 s: count only.
// Table 2: seconds a game that are deadly, by reach count and HP band; the share of them followed by that hero's death in 10 s.
// Table 3: hp / kill at the last line before each death with 2+ (and with 1) in reach, and at the last line 3 s or more before it.
//
// Our heroes: those with at least one ev=cut kind=leave line in the game. Deaths: per hero, the death is the last ev=snap before
//   the gap in its snapshots that precedes the rise of its `deaths` counter (dead heroes log no snapshots). Up to 1 s early.
//   A window is [death - 10, death + 1].
//
// A stay column is the bar under a hero's hits; with none lately (`prs`, or no reacher hitting on a line without it) Decide uses the lower
// of it and Safe.BARS.idle, so the columns above 1.0 differ only on pressed lines.
// What a replay cannot know, and what stands in for it:
//  - landing (HP per second lost by source), exit: zeros. The answer's level `costly` is not replayed; only deadly counts.
//  - reach: the Reader's test over the logged heroes (CUT_R 3,000 box): non-illusion heroes within speed x 2 + range + hull + our
//    hull of us. The Reader also counts illusions; the line's walk is the place itself (from = place).
//  - dmg: e6 if the hero hit us in the last 1 s (`eng`), else e3 (2 s windows on a leave line). The Reader's engagedWindow is 6.
//  - tower: our place within a standing enemy tower's attack range + hull (logged once per team, standing per the `ta` mask).
//    The Reader uses WorldFacts.TowerReach (the same). towerOnMe: `dt`, or a tower in `tt` whose target is us (`b`).
//  - missing 0 and away false: the unknown rule never fires (the line has `hu` sightings but no belief weights). held false:
//    a held place is not on the line. hold: `hb` or `pj`.
//  - unseen reachers (Reacher.unseen): none.
//  - Leave lines are written when the retreat read runs, so a hero not in a retreat read has none: gaps are real.
//  - Table 2's weight is the time to the same hero's next leave line capped at 2 s; a hero's last line weighs 0.
// With --shadow (inputs are exact except as noted):
//  - "today" is the hero's own act: in a retreat episode (a who=retreat line, or inside an ev=retreat start..end of kind ours) or not.
//    Table 1 and 2's "today" column is that, so a "deadly" today is "in retreat".
//  - Lines are written on a changed answer and otherwise at most every 2 s while a hero is in reach or HP is being lost: a hero out
//    of reach and not losing HP has no line, and a weight can cover up to 2 s past the last line of a spell.
//  - A hero a bar would have kept in lane has no counterfactual: Table 4's "bar deadly, not in retreat" cell shows what happened
//    while we stayed, and says nothing of what a retreat would have cost or saved. `price` (the landing, the exit) is as logged
//    by the bot at that moment, so a bar's answer is judged on the price of the walk the bot was making, not the one the bar would make.
//  - Table 4's HP and death columns: HP lost over the next 5 s = the start fraction (hpa / hpm of the line) minus the lowest
//    ev=snap hp fraction (hp is a percent) in (t, t + 5]; a death in those 5 s loses it all; moments with no snapshot in the
//    window are left out of the HP column. Snapshots join by hero (pid) then time.
//  - Table 5: an episode's start line is the latest source line of that hero at or up to 2.5 s before the start; an episode with
//    none is counted apart. Deaths in an episode: the hero's death between its start and 1 s after its end.
//  - Which heroes: those that log kind=safe lines; the header says which teams, and the report repeats per side when both do.
const fs = require('fs');
const path = require('path');
const { newState, doString, getGlobal } = require('../../tests/humaniser/harness');
const { readGames, toLua } = require('./cut');
const bank = require('./bank');

const STAYS = [1.0, 1.25, 1.5, 2.0];
const HORIZON = 2;
const WINDOW_BEFORE = 10;
const WINDOW_AFTER = 1;
const WEIGHT_CAP = 2;
const FOLLOW = 10;
const GAME_SPLIT = 30;
const CHUNK = 500;
const LEAVES = new Set(['lethal', 'tower', 'heal', 'threat']);
const BANDS = [['75%+', 0.75], ['50-75%', 0.5], ['<50%', 0]];

const records = (s) => (s === undefined || s === '' ? [] : s.split(';').map((r) => r.split(',')));
const dist = (a, b) => Math.hypot(a.x - b.x, a.y - b.y);

/**
 * One leave line as Safe.Inputs, with `n` the heroes in reach. `towers`: Map team -> the logged cut_towers `tw` string; `team`:
 * our team. Pure over the line.
 */
function mapLeave(cut, towers, team) {
    const [x, y, hp, hpMax, , hull] = String(cut.b).split(',').map(Number);
    const me = { x, y };
    const reach = [];
    for (const [pid, hx, hy, , range, hhull, speed, , eng, e3, e6, ill] of records(cut.he).map((r) => r.map(Number))) {
        if (ill === 1) continue;
        if (dist(me, { x: hx, y: hy }) > speed * HORIZON + range + hhull + hull) continue;
        reach.push({ pid, hitting: eng === 1, dmg: eng === 1 ? e6 : e3 });
    }
    const enemy = team === 2 ? 3 : 2;
    const mask = parseInt(String(cut.ta).split(',')[1], 16);
    let tower = false;
    for (const [i, tx, ty, range, thull] of records(towers.get(enemy)).map((r) => r.map(Number))) {
        if (!(mask & (1 << i))) continue;
        if (dist(me, { x: tx, y: ty }) <= range + thull) tower = true;
    }
    const towerOnMe = Number(cut.dt) === 1 || records(cut.tt).some(([t, , tgt]) => Number(t) === enemy && tgt === 'b');
    return {
        n: reach.length,
        inputs: {
            hp, hpMax, reach, missing: 0, tower, towerOnMe, landing: { hero: 0, creeps: 0, tower: 0 }, away: false, held: false,
            hold: Number(cut.hb) === 1 || Number(cut.pj) === 1,
        },
    };
}

/**
 * One kind=safe line as Safe.Inputs (the mapping of tests/humaniser/fixture_drivers/safe.lua, which cut.js's safe driver feeds),
 * with `n` the heroes in reach (unseen reachers included, as the bot counted them).
 */
function mapSafe(cut) {
    const reach = records(cut.rr).map(([pid, hitting, dmg, unseen]) => ({ pid: Number(pid), hitting: hitting === '1', dmg: Number(dmg), unseen: unseen === '1' || undefined }));
    const [tower, towerOnMe] = String(cut.stw ?? '0,0').split(',');
    const [hero, creeps, tw] = String(cut.ld ?? '0,0,0').split(',').map(Number);
    return {
        n: reach.length,
        inputs: {
            hp: Number(cut.hpa), hpMax: Number(cut.hpm), reach, missing: Number(cut.mi ?? 0), tower: tower === '1', towerOnMe: towerOnMe === '1',
            landing: { hero, creeps, tower: tw }, away: Number(cut.awy) === 1, held: Number(cut.hld) === 1, hold: Number(cut.hd) === 1,
            pressed: cut.prs === undefined ? undefined : Number(cut.prs) === 1,
            drawn: cut.dr === undefined ? undefined : cut.dr === '-' ? [] : String(cut.dr).split(';').map((r) => { const [src, dmg] = r.split(','); return { src, dmg: Number(dmg) }; }),
        },
    };
}

/** Runs Safe.Decide over every row at each bar: rows[i].answers[stay] = { level, reason, kill }. */
function decideAll(rows, root) {
    const L = newState(root);
    const err = doString(L, 'dofile(HARNESS_DIR .. "/dota_stubs.lua")\nFreshHumaniser({ Enable = true })\nSAFE = require("bots/FunLib/humaniser/safe")');
    if (err !== null) throw new Error(err);
    for (let at = 0; at < rows.length; at += CHUNK) {
        const part = rows.slice(at, at + CHUNK);
        const src = part.map((r) => toLua(r.inputs)).join(',\n');
        const e = doString(L, `local out = {}
for k, i in ipairs({${src}}) do
    for _, stay in ipairs({${STAYS.join(',')}}) do
        local a = SAFE.Decide(i, stay)
        out[#out + 1] = table.concat({ a.level, a.reason, string.format("%.3f", a.kill) }, "|")
    end
end
OUT = table.concat(out, "\\n")`);
        if (e !== null) throw new Error(e);
        const got = String(getGlobal(L, 'OUT')).split('\n');
        part.forEach((r, k) => {
            r.answers = {};
            STAYS.forEach((s, j) => { const [level, reason, kill] = got[k * STAYS.length + j].split('|'); r.answers[s] = { level, reason, kill: Number(kill) }; });
        });
    }
}

/** The game's own answer as an answer in the same shape. */
function today(cut) {
    const leave = LEAVES.has(cut.dec);
    return { level: leave ? 'deadly' : 'safe', reason: cut.dec === 'tower' ? 'tower' : cut.dec === 'heal' ? 'other' : leave ? 'kill' : 'stay' };
}

/** Per game of a log: { deaths: [{ pid, t }], ev } where ev holds the arb ends and retreat starts and ends in order. */
function deathsOf(text) {
    const games = [];
    let g, last = -Infinity;
    let snaps = [], ev = [];
    const flush = () => { if (g !== undefined) { games.push({ deaths: deathsFromSnaps(snaps), ev, snaps }); snaps = []; ev = []; } };
    for (const line of text.split('\n')) {
        if (line.includes('[DOTACTL] ')) continue;
        const i = line.indexOf('[HEV] ');
        if (i < 0) continue;
        const t = Number((line.slice(i + 6).match(/(?:^| )t=(\S+)/) || [])[1]);
        if (!Number.isFinite(t)) continue;
        if (g === undefined || t < last - GAME_SPLIT) { flush(); g = true; }
        last = t;
        const kind = (line.match(/ ev=(snap|arb|retreat) /) || [])[1];
        if (!kind) continue;
        const f = {};
        for (const m of line.slice(i + 6).matchAll(/(\w+)=("([^"]*)"|\S+)/g)) f[m[1]] = m[3] !== undefined ? m[3] : m[2];
        if (kind === 'snap') { if (f.deaths !== undefined) snaps.push({ pid: f.pid, t, x: +f.x, y: +f.y, hp: +f.hp, deaths: +f.deaths }); }
        else if (kind === 'arb' && f.ph === 'end') ev.push({ kind: 'arbEnd', pid: f.pid, t });
        else if (kind === 'retreat' && (f.ph === 'start' || f.ph === 'end') && f.kind !== 'plain') ev.push({ kind: 'retreat', ph: f.ph, pid: f.pid, t, why: f.why, res: f.res, secs: Number(f.secs), hpl: Number(f.hpl) });
    }
    flush();
    return games;
}

/**
 * A death is the last snapshot before the gap in the hero's snapshots that precedes the rise of its `deaths` counter: dead
 * heroes log no snapshots, and the counter rises at the first snapshot after the respawn. A gap with no rise (a logging pause)
 * is no death; a teleport or blink with the hero alive leaves no gap.
 */
function deathsFromSnaps(snaps) {
    const by = new Map();
    for (const s of snaps) { if (!by.has(s.pid)) by.set(s.pid, []); by.get(s.pid).push(s); }
    const out = [];
    for (const [pid, list] of by) {
        for (let i = 1; i < list.length; i++) {
            for (let k = list[i - 1].deaths; k < list[i].deaths; k++) out.push({ pid, t: list[i - 1].t });
        }
    }
    return out;
}

/** Retreat episodes of kind ours, paired start to end per hero: [{ pid, t0, t1 (Infinity if never ended), why, res, secs, hpl }]. */
function episodesOf(ev) {
    const open = new Map(), out = [];
    for (const e of ev) {
        if (e.kind !== 'retreat') continue;
        if (e.ph === 'start') { if (!open.has(e.pid)) open.set(e.pid, e); continue; }
        const st = open.get(e.pid);
        if (!st) continue;
        open.delete(e.pid);
        out.push({ pid: e.pid, t0: st.t, t1: e.t, why: st.why, res: e.res, secs: e.secs, hpl: e.hpl });
    }
    for (const st of open.values()) out.push({ pid: st.pid, t0: st.t, t1: Infinity, why: st.why });
    return out;
}

/** What held a hero at time t: not held by us (an arb end earlier), a retreat episode running (its why), else the read running. */
function stateAt(ev, pid, t) {
    if (ev.some((e) => e.kind === 'arbEnd' && e.pid === pid && e.t <= t)) return { state: 'notheld' };
    let open;
    for (const e of ev) {
        if (e.kind !== 'retreat' || e.pid !== pid || e.t > t) continue;
        if (e.ph === 'start') { if (open === undefined) open = e; } else open = undefined;
    }
    return open ? { state: 'retreat', why: open.why || '?' } : { state: 'read' };
}

const SHADOW_WHO = new Set(['leave', 'retreat']);
const EPISODE_LOOKBACK = 2.5;
const LOSS_HORIZON = 5;

/** The rows and deaths of one log's game: { rows (source lines in time order), deaths, episodes, snaps (pid -> [{ t, hp }]), heroes }. */
function gameOfLog(log, gameNo, shadow) {
    const text = fs.readFileSync(log, 'utf8');
    const games = readGames(text);
    const gi = gameNo !== undefined ? gameNo - 1 : games.length - 1;
    const g = games[gi];
    const empty = { rows: [], deaths: [], episodes: [], snaps: new Map(), heroes: new Map() };
    if (!g) return empty;
    const file = path.basename(log);
    const rows = [];
    for (const cut of g.cuts) {
        const bot = g.bots.get(cut.pid);
        if (shadow) {
            if (cut.kind !== 'safe' || !SHADOW_WHO.has(cut.who) || cut.hpa === undefined || !bot) continue;
            const m = mapSafe(cut);
            rows.push({ file, pid: cut.pid, t: Number(cut.t), who: cut.who, team: bot.team, pos: bot.pos, n: m.n, inputs: m.inputs, kill0: m.inputs.reach.reduce((s, r) => s + r.dmg, 0) });
            continue;
        }
        if (cut.kind !== 'leave') continue;
        if (!bot || cut.he === undefined || cut.b === undefined) continue;
        const m = mapLeave(cut, new Map([...g.towers].map(([k, v]) => [Number(k), v.tw])), Number(bot.team));
        if (!g.towers.has(String(bot.team === '2' ? 3 : 2))) continue;
        rows.push({ file, pid: cut.pid, t: Number(cut.t), dec: cut.dec, n: m.n, inputs: m.inputs, kill0: m.inputs.reach.reduce((s, r) => s + r.dmg, 0) });
    }
    const ours = new Set(rows.map((r) => r.pid));
    const dg = deathsOf(text)[gi] || { deaths: [], ev: [], snaps: [] };
    const deaths = dg.deaths.filter((d) => ours.has(d.pid)).map((d) => ({ ...d, file, ...stateAt(dg.ev, d.pid, d.t) }));
    const heroes = new Map();
    for (const pid of ours) { const b = g.bots.get(pid); if (b) heroes.set(pid, { team: b.team, pos: b.pos, oursOn: String(b.ours || '').split(',').some((kv) => kv.endsWith(':1')) }); }
    const episodes = shadow ? episodesOf(dg.ev).filter((e) => ours.has(e.pid)) : [];
    const snaps = new Map();
    if (shadow) {
        rows.sort((a, b) => a.t - b.t);
        for (const s of dg.snaps) { if (!snaps.has(s.pid)) snaps.set(s.pid, []); snaps.get(s.pid).push({ t: s.t, hp: s.hp }); }
        for (const r of rows) {
            r.retreat = r.who === 'retreat' || episodes.some((e) => e.pid === r.pid && r.t > e.t0 + 0.001 && r.t <= e.t1);
            r.dec = r.retreat ? 'threat' : 'stay';
        }
    }
    return { rows, deaths, episodes, snaps, heroes };
}

const median = (a) => { if (!a.length) return undefined; const s = [...a].sort((x, y) => x - y); const h = s.length >> 1; return s.length % 2 ? s[h] : (s[h - 1] + s[h]) / 2; };
const pct = (a, q) => { if (!a.length) return undefined; const s = [...a].sort((x, y) => x - y); return s[Math.min(s.length - 1, Math.floor(q * s.length))]; };
const fmt = (v, d = 1) => (v === undefined ? '-' : Number.isFinite(v) ? v.toFixed(d) : 'inf');
const bandOf = (r) => { const s = r.inputs.hp / r.inputs.hpMax; return BANDS.find(([, lo]) => s >= lo)[0]; };
const reachKey = (n) => (n >= 2 ? '2+' : String(n));
const BARS = ['today', ...STAYS.map(String)];
const answerOf = (r, bar) => (bar === 'today' ? today({ dec: r.dec }) : r.answers[bar]);

/** Everything the tables need, from the games: [{ file, rows, deaths }]. */
function analyse(games, shadow = false) {
    const t1 = {}, t2 = {}, t3 = {}, t4 = {}, t4ex = {}, t5 = { all: { n: 0, noLine: 0, len: [], hpl: [], died: 0 }, bar: {} };
    const examples = {};
    let nDeaths = 0, noLine = 0;
    const perDeath = [];
    const notCalled = {};
    for (const g of games) {
        const byPid = new Map();
        for (const r of g.rows) { if (!byPid.has(r.pid)) byPid.set(r.pid, []); byPid.get(r.pid).push(r); }
        for (const list of byPid.values()) list.sort((a, b) => a.t - b.t).forEach((r, i) => { const nx = list[i + 1]; r.w = nx ? Math.min(WEIGHT_CAP, nx.t - r.t) : 0; });
        for (const d of g.deaths) {
            nDeaths++;
            const win = (byPid.get(d.pid) || []).filter((r) => r.t >= d.t - WINDOW_BEFORE && r.t <= d.t + WINDOW_AFTER);
            const ownKey = d.state === 'retreat' ? `retreat:${d.why}` : d.state === 'notheld' ? 'not held' : 'read running';
            for (const bar of BARS) {
                if (win.some((r) => answerOf(r, bar).level === 'deadly')) continue;
                const c = notCalled[bar] || (notCalled[bar] = {});
                c[ownKey] = (c[ownKey] || 0) + 1;
            }
            if (!win.length) { noLine++; continue; }
            perDeath.push({ d, win, all: byPid.get(d.pid) });
        }
        for (const r of g.rows) {
            for (const bar of BARS) {
                const a = answerOf(r, bar);
                if (a.level !== 'deadly' || r.w === 0) continue;
                const k = `${bar}\t${reachKey(r.n)}\t${bandOf(r)}`;
                const c = t2[k] || (t2[k] = { sec: 0, died: 0 });
                c.sec += r.w;
                if (g.deaths.some((d) => d.pid === r.pid && d.t >= r.t && d.t <= r.t + FOLLOW)) c.died += r.w;
            }
        }
    }
    if (shadow) for (const g of games) shadowTables(g, t4, t4ex, t5);
    for (const { d, win } of perDeath) {
        for (const bar of BARS) {
            const first = win.find((r) => answerOf(r, bar).level === 'deadly');
            const rec = t1[bar] || (t1[bar] = { n: 0, called: 0, lead: [], byReach: {}, byReason: {} });
            rec.n++;
            if (!first) continue;
            rec.called++;
            rec.lead.push(d.t - first.t);
            const rk = reachKey(first.n), why = answerOf(first, bar).reason;
            for (const [m, k] of [[rec.byReach, rk], [rec.byReason, why]]) { const c = m[k] || (m[k] = { n: 0, lead: [] }); c.n++; c.lead.push(d.t - first.t); }
        }
        const lastRow = win[win.length - 1];
        const before = [...win].reverse().find((r) => r.t <= d.t - 3);
        const key = reachKey(lastRow.n);
        (t3.age = t3.age || []).push(d.t - lastRow.t);
        const c = t3[key] || (t3[key] = { last: [], before: [], nLast: 0 });
        const ratio = (r) => (r.kill0 > 0 ? r.inputs.hp / r.kill0 : Infinity);
        c.nLast++;
        c.last.push(ratio(lastRow));
        if (before) c.before.push(ratio(before));
        const today0 = win.find((r) => answerOf(r, 'today').level === 'deadly');
        for (const bar of STAYS.map(String)) {
            const nw = win.find((r) => answerOf(r, bar).level === 'deadly');
            const rk = reachKey((today0 || nw || lastRow).n);
            if (today0 && !nw) (examples[`today-only\t${bar}\t${rk}`] = examples[`today-only\t${bar}\t${rk}`] || []).push({ file: d.file, pid: d.pid, t: today0.t });
            if (nw && !today0) (examples[`bar-only\t${bar}\t${rk}`] = examples[`bar-only\t${bar}\t${rk}`] || []).push({ file: d.file, pid: d.pid, t: nw.t });
        }
    }
    return { t1, t2, t3, t4, t4ex, t5, notCalled, examples, nDeaths, noLine, withLine: perDeath.length };
}

/** HP fraction lost by the row's hero over the next LOSS_HORIZON s (all of it on a death); undefined with no snapshot in the window. */
function lostOf(g, r) {
    const start = r.inputs.hp / r.inputs.hpMax;
    if (g.deaths.some((d) => d.pid === r.pid && d.t >= r.t && d.t <= r.t + LOSS_HORIZON)) return start;
    const list = g.snaps.get(r.pid) || [];
    let lo = 0, hi = list.length;
    while (lo < hi) { const mid = (lo + hi) >> 1; if (list[mid].t > r.t) hi = mid; else lo = mid + 1; }
    let low;
    for (let i = lo; i < list.length && list[i].t <= r.t + LOSS_HORIZON; i++) low = low === undefined ? list[i].hp / 100 : Math.min(low, list[i].hp / 100);
    return low === undefined ? undefined : Math.max(0, start - low);
}

const CELLS = [['DR', 'deadly + in retreat'], ['DN', 'deadly + NOT in retreat (stayed)'], ['SR', 'not deadly + in retreat (left)'], ['SN', 'neither']];
const cellOf = (deadly, retreat) => (deadly ? 'D' : 'S') + (retreat ? 'R' : 'N');

/** Tables 4 and 5 of one game, added into t4 (cells), t4ex (examples) and t5 (episodes). */
function shadowTables(g, t4, t4ex, t5) {
    const byPid = new Map();
    for (const r of g.rows) { if (!byPid.has(r.pid)) byPid.set(r.pid, []); byPid.get(r.pid).push(r); }
    for (const r of g.rows) {
        if (r.n < 1 || !(r.w > 0)) continue;
        const lost = lostOf(g, r);
        const died = g.deaths.some((d) => d.pid === r.pid && d.t >= r.t && d.t <= r.t + FOLLOW);
        for (const bar of STAYS.map(String)) {
            const cell = cellOf(r.answers[bar].level === 'deadly', r.retreat);
            for (const scope of r.pos === '2' ? ['all', 'mid'] : ['all']) {
                const c = t4[`${scope}\t${bar}\t${cell}`] || (t4[`${scope}\t${bar}\t${cell}`] = { sec: 0, lostSec: 0, lost: 0, died: 0, n: 0 });
                c.sec += r.w; c.n++;
                if (died) c.died += r.w;
                if (lost !== undefined) { c.lostSec += r.w; c.lost += r.w * lost; }
            }
            if (cell === 'DN' || cell === 'SR') (t4ex[`${cell}\t${bar}`] = t4ex[`${cell}\t${bar}`] || []).push({ file: r.file, pid: r.pid, t: r.t });
        }
    }
    for (const e of g.episodes) {
        const list = byPid.get(e.pid) || [];
        const dead = g.deaths.some((d) => d.pid === e.pid && d.t >= e.t0 && d.t <= e.t1 + 1);
        const len = Number.isFinite(e.secs) ? e.secs : undefined;
        const hpl = Number.isFinite(e.hpl) ? e.hpl : undefined;
        t5.all.n++;
        if (dead) t5.all.died++;
        if (len !== undefined) t5.all.len.push(len);
        if (hpl !== undefined) t5.all.hpl.push(hpl);
        const start = [...list].reverse().find((r) => r.t <= e.t0 + 0.001 && r.t >= e.t0 - EPISODE_LOOKBACK);
        if (!start) { t5.all.noLine++; continue; }
        for (const bar of STAYS.map(String)) {
            const b = t5.bar[bar] || (t5.bar[bar] = { began: 0, not: 0, notDied: 0, notLen: [], notHpl: [] });
            if (start.answers[bar].level === 'deadly') { b.began++; continue; }
            b.not++;
            if (dead) b.notDied++;
            if (len !== undefined) b.notLen.push(len);
            if (hpl !== undefined) b.notHpl.push(hpl);
        }
    }
}

function report(res, nGames, show, shadow = false) {
    const out = [];
    const src = shadow ? 'source line' : 'leave line';
    out.push(`safe_deaths: ${nGames} games, ${res.nDeaths} deaths of our heroes (heroes with ${src}s); ${res.withLine} with a ${src} in the 10 s before, ${res.noLine} with none (the read could not have seen those)`);
    out.push('', `Table 1: deaths with a ${src} in the 10 s before; deadly = ${shadow ? 'today in a retreat episode' : 'today a leave decision'}, else Safe.Decide at that stay`);
    out.push('  bar      n   deadly  median lead s | by reach at first deadly (n, median s) | by reason (n, median s)');
    for (const bar of BARS) {
        const r = res.t1[bar];
        if (!r) continue;
        const cell = (m, ks) => ks.map((k) => `${k}: ${m[k] ? `${m[k].n}, ${fmt(median(m[k].lead))}` : '0'}`).join('  ');
        const reasons = Object.keys(r.byReason).sort();
        out.push(`  ${bar.padEnd(6)} ${String(r.n).padStart(4)} ${String(r.called).padStart(6)}  ${fmt(median(r.lead)).padStart(6)}        | ${cell(r.byReach, ['0', '1', '2+'])} | ${cell(r.byReason, reasons)}`);
    }
    out.push('  not called, by state at the death (all deaths, those with no line too): not held = an arb end earlier; retreat:<why> = episode running; else read running');
    for (const bar of BARS) {
        const c = res.notCalled[bar] || {};
        const n = Object.values(c).reduce((a, v) => a + v, 0);
        out.push(`  ${bar.padEnd(6)} ${String(n).padStart(4)}  ${Object.entries(c).sort((a, b) => b[1] - a[1]).map(([k, v]) => `${k}: ${v}`).join('  ')}`);
    }
    out.push('', `Table 2: deadly seconds a game (weight: time to the hero's next ${src}, cap 2 s), by heroes in reach and HP band; died10 = share followed by that hero's death within 10 s`);
    out.push('  bar      reach  HP band   sec/game  died10');
    for (const bar of BARS) {
        for (const rk of ['0', '1', '2+']) {
            for (const [band] of BANDS) {
                const c = res.t2[`${bar}\t${rk}\t${band}`];
                if (!c) continue;
                out.push(`  ${bar.padEnd(8)} ${rk.padEnd(5)}  ${band.padEnd(8)} ${fmt(c.sec / nGames).padStart(8)}  ${fmt(100 * c.died / c.sec, 0).padStart(5)}%`);
            }
        }
    }
    out.push('', 'Table 3: hp / kill (kill = sum of dmg in reach) at the last line before the death and the last line 3 s or more before it; group = heroes in reach at the last line');
    out.push('  reach   n   last: median [p25-p75]   share<1.0 <1.25 <1.5 <2.0  | 3 s before (n): median [p25-p75]  share<1.0 <1.25 <1.5 <2.0');
    for (const rk of ['1', '2+']) {
        const c = res.t3[rk];
        const label = rk;
        if (!c) { out.push(`  ${label.padEnd(4)}   0`); continue; }
        const stat = (a) => `${fmt(median(a), 2)} [${fmt(pct(a, 0.25), 2)}-${fmt(pct(a, 0.75), 2)}]  ${STAYS.map((s) => fmt(100 * a.filter((v) => v < s).length / Math.max(1, a.length), 0).padStart(3) + '%').join(' ')}`;
        out.push(`  ${label.padEnd(4)} ${String(c.nLast).padStart(3)}   ${stat(c.last)}  | (${c.before.length}) ${stat(c.before)}`);
    }
    out.push(`  last line had 0 in reach: ${(res.t3['0'] || { nLast: 0 }).nLast} deaths (no kill to divide by); median age of the last line before the death ${fmt(median(res.t3.age || []), 2)} s`);
    if (show > 0) {
        out.push('', `Examples (up to ${show} per cell): deaths where today called a leave and the bar did not (today-only), and the reverse (bar-only)`);
        for (const [k, list] of Object.entries(res.examples).sort()) {
            const [which, bar, rk] = k.split('\t');
            out.push(`  ${which} stay ${bar} reach ${rk}: ${list.length}`);
            for (const e of list.slice(0, show)) out.push(`      ${e.file} pid ${e.pid} t=${e.t}`);
        }
    }
    if (shadow) out.push(...shadowReport(res, nGames, show));
    return out.join('\n');
}

/** Tables 4 and 5 as lines. */
function shadowReport(res, nGames, show) {
    const out = [];
    const bars = STAYS.map(String);
    const block = (scope, label) => {
        out.push(`  ${label}`, '  bar    cell                                  sec/game  HP lost 5 s  died10   moments');
        for (const bar of bars) {
            for (const [cell, name] of CELLS) {
                const c = res.t4[`${scope}\t${bar}\t${cell}`];
                if (!c) { out.push(`  ${bar.padEnd(6)} ${name.padEnd(36)}  ${'0.0'.padStart(8)}`); continue; }
                const lost = c.lostSec > 0 ? `${fmt(100 * c.lost / c.lostSec, 1)}%` : '-';
                out.push(`  ${bar.padEnd(6)} ${name.padEnd(36)}  ${fmt(c.sec / nGames).padStart(8)}  ${lost.padStart(10)}  ${`${fmt(100 * c.died / c.sec, 0)}%`.padStart(6)}  ${String(c.n).padStart(7)}`);
            }
        }
    };
    out.push('', 'Table 4: heroes in reach, by what the bar says (deadly = leave) and what the hero did (in a retreat episode). HP lost 5 s = weighted mean share of max HP lost over the next 5 s; died10 = weighted share followed by the hero\'s death within 10 s');
    block('all', 'all heroes');
    block('mid', 'our mid only (ev=bot pos=2)');
    const t5 = res.t5;
    const mean = (a) => (a.length ? a.reduce((x, y) => x + y, 0) / a.length : undefined);
    out.push('', 'Table 5: retreat episodes (ev=retreat start/end, kind ours). "would not have begun": episodes whose start line the bar does not call deadly');
    out.push(`  all: ${fmt(t5.all.n / nGames)} a game (${t5.all.n}); ${t5.all.noLine} with no source line in the ${EPISODE_LOOKBACK} s up to the start (not in the bar columns); HP lost mean ${fmt(100 * (mean(t5.all.hpl) ?? NaN), 1)}% of max; ${t5.all.died} with the hero's death in or just after; length mean ${fmt(mean(t5.all.len))} s median ${fmt(median(t5.all.len))} s`);
    out.push('  bar    began deadly  would NOT have begun | of those: HP lost mean | deaths | length mean s (median)');
    for (const bar of bars) {
        const b = t5.bar[bar] || { began: 0, not: 0, notDied: 0, notLen: [], notHpl: [] };
        out.push(`  ${bar.padEnd(6)} ${String(b.began).padStart(12)} ${String(b.not).padStart(20)} | ${`${fmt(100 * (mean(b.notHpl) ?? NaN), 1)}%`.padStart(19)} | ${String(b.notDied).padStart(6)} | ${fmt(mean(b.notLen))} (${fmt(median(b.notLen))})`);
    }
    if (show > 0) {
        out.push('', `Table 4 examples (up to ${show} per cell): stayed = the bar is deadly and the hero did not retreat; left = the bar is not deadly and the hero was in a retreat`);
        for (const [k, list] of Object.entries(res.t4ex).sort()) {
            const [cell, bar] = k.split('\t');
            out.push(`  ${cell === 'DN' ? 'stayed' : 'left'} stay ${bar}: ${list.length}`);
            for (const e of list.slice(0, show)) out.push(`      ${e.file} pid ${e.pid} t=${e.t}`);
        }
    }
    return out;
}

function logsOf(argv) {
    const i = argv.indexOf('--batch');
    if (i < 0) return argv.filter((a, j) => !a.startsWith('--') && !['--game', '--rows'].includes(argv[j - 1]));
    const names = new Set(argv[i + 1].split(','));
    return bank.load().filter((e) => names.has(e.batch)).map((e) => e.log).filter((l) => fs.existsSync(l));
}

function main(argv) {
    const opt = (k) => { const i = argv.indexOf(k); return i >= 0 ? argv[i + 1] : undefined; };
    if (argv.includes('--help') || argv.length === 0) { console.log(fs.readFileSync(__filename, 'utf8').split('\n').slice(2, 13).map((l) => l.replace(/^\/\/ ?/, '')).join('\n')); return; }
    const logs = logsOf(argv);
    if (!logs.length) { console.error('no logs'); process.exit(1); }
    const gameNo = opt('--game') !== undefined ? Number(opt('--game')) : undefined;
    const shadow = argv.includes('--shadow');
    const games = logs.map((l) => gameOfLog(l, gameNo, shadow)).filter((g) => g.rows.length > 0);
    decideAll(games.flatMap((g) => g.rows));
    const show = Number(opt('--rows') ?? 0);
    const teams = [...new Set(games.flatMap((g) => g.rows.map((r) => r.team)))].filter((t) => t !== undefined).sort();
    const sides = shadow && teams.length > 1 ? teams.map((t) => [t, sideOf(games, t)]) : [];
    if (argv.includes('--json')) { console.log(JSON.stringify({ games: games.length, ...analyse(games, shadow) }, null, 1)); return; }
    const out = [];
    if (shadow) out.push(shadowHeader(games, teams, logs.length));
    out.push(report(analyse(games, shadow), games.length, show, shadow));
    for (const [t, sg] of sides) out.push('', `==== side: team ${t} (${t === '2' ? 'Radiant' : 'Dire'}) only ====`, report(analyse(sg, shadow), sg.length, show, shadow));
    console.log(out.join('\n'));
}

/** The games restricted to one team's heroes (rows, deaths, episodes). */
function sideOf(games, team) {
    return games.map((g) => {
        const mine = new Set(g.rows.filter((r) => r.team === team).map((r) => r.pid));
        return { ...g, rows: g.rows.filter((r) => mine.has(r.pid)), deaths: g.deaths.filter((d) => mine.has(d.pid)), episodes: g.episodes.filter((e) => mine.has(e.pid)) };
    }).filter((g) => g.rows.length > 0);
}

function shadowHeader(games, teams, nLogs) {
    const lines = [`safe_deaths --shadow: ${nLogs} logs, ${games.length} with kind=safe lines (who=leave or retreat)`];
    for (const t of teams) {
        const heroes = games.flatMap((g) => [...g.heroes.values()].filter((h) => h.team === t));
        lines.push(`  team ${t} (${t === '2' ? 'Radiant' : 'Dire'}): ${heroes.length} heroes log lines; ${heroes.filter((h) => h.oursOn).length} of them with an Ours switch on (ev=bot ours=)`);
    }
    lines.push(`  lines come from ${teams.length > 1 ? 'BOTH teams' : `team ${teams[0] ?? '-'} only`}${teams.length > 1 ? '; the report repeats for each side below' : ''}`);
    lines.push('  Cannot be known: a hero the bar would have kept in lane has no counterfactual (Table 4 "NOT in retreat" cells show what happened while we stayed, not what a retreat would have done);');
    lines.push('  `price` (landing, exit) is as logged at that moment; lines stop when a hero is out of reach with no HP loss, so a weight may span up to 2 s past a spell\'s last line.');
    return lines.join('\n');
}

if (require.main === module) main(process.argv.slice(2));
module.exports = { mapLeave, mapSafe, deathsFromSnaps, stateAt, episodesOf, decideAll, today, analyse };
