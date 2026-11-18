#!/usr/bin/env node
// The lane score (proposal docs/proposals/2026-11-19-lane-ladder.md s4): per hero, its lane and its lane opponent, the
// lane's lines read from facts only (positions, hits, HP, last hits, levels, net worth, fronts, creep deaths), never our
// decision telemetry, so it reads OHA's side too and runs on any build. One row per hero and time (--at).
// Usage: node lane_score.js <run|label|file fragment> [...] [--at 300,600] [--rows] [--json] [--no-ingest]
//   <run> matches games.label by prefix or games.file by fragment; each log's last game is read (a remote stub is skipped).
//   Default output: per time, each line's mean per hero-game by side (ours / oha) and position. --rows: one JSON line a row.
//
// Who: side `ours` when the hero's last ev=bot line has an Ours switch on, else `oha`. Lane: the commonest lane label
// (dynamic.js laneLabel) of its alive seconds 1:00-5:00, `none` if never in a lane. Opponent: of the enemy heroes in the
// same lane, the same kind (core pos 1-3, support 4-5) first, then the most seconds within 1,500 of the hero 1:00-5:00.
// Each second is the hero's latest snapshot in that whole second (bots log none while dead).
// Lines, to the time T:
//   lh dn             last hits, denies (the snapshot counters)
//   pool own_pool     enemy creeps / own creeps logged dying in the hero's lane (ev=creep_death / ev=own_creep_death of
//                     the hero's team: creeps that died with one of its heroes near); lh_share = lh / pool. Shared by two
//                     heroes of one team in a lane.
//   lvl nw            level and net worth at T;  lvl_gap  the opponent's level less the hero's at T
//   behind2 fell2     first second the opponent stood 2 levels or more above the hero (null: never, to T); fell2 1 if
//                     it did (its mean is the share fallen behind; behind2's mean is over those only)
//   att_s attd_s      seconds the hero's attack target was a hero; seconds an enemy hero's attack target was the hero (`ah`)
//   hpl_hero hpl_creep hpl_tower hpl_other   HP-% points lost (view hp_loss, deaths left out), a second with several
//                     sources split evenly among them; `other` neutral, unit and unexplained
//   ret_<class> ret_<class>_s   retreat runs and their seconds. A run: seconds (gaps of 2 s or less) in which the
//                     distance to the own fountain falls by RUN_STEP or more each second, falling RUN_MIN in all, starting
//                     outside BASE_R of the fountain, no jump over JUMP in one second (a teleport ends it). Class, first
//                     match: fountain (ends within BASE_R of it), after_hit (hit by a hero, `hit`, in the 3 s before or
//                     at its start), low_hp (starts at 50% HP or less), no_damage (no HP lost in the 5 s before, starts
//                     above 80%), other.
//   trips trip_s trip_hp trip_opp_lh trip_tp   trips home: the hero reaches BASE_R of its fountain alive, with no death
//                     since its last second in its lane (the departure). trip_s from the departure to its next second in
//                     its lane (or T), trip_hp the mean HP at departure, trip_opp_lh the opponent's last hits gained in
//                     the trips, trip_tp trips with a jump over JUMP (a teleport). Heal items in hand: not logged.
//   deaths deaths_gap deaths: rises of the deaths counter; deaths_gap their mean level gap (opponent less hero) at death
//   wave_tower_s      seconds the team's front in the hero's lane (ev=front, latest line) sat within TOWER_R of an
//                     enemy tower of that lane
//   tower_took        the team's creeps the enemy towers killed in the lane: the enemy team's ev=creep_death with tw=1
//                     and fate `other` (as view creep_fate, see creepFates). Null on builds before `tw`.
// Speed: every query filters on game_id by index; about 0.1 s a game for the store, most of it view hp_loss.
// The controller's forecast error (s4's last line) reads our telemetry: `q @lane_ctl`, `q @lever_effect`.
'use strict';
const fs = require('fs');
const { Store, DB, LOGS, JOBS } = require('./store');
const { TOWERS, laneLabel } = require('./dynamic');

const FOUNTAIN = { 2: [-6850, -6461], 3: [7020, 6345] }; // dynamic.js FOUNTAIN
const C = {
    BASE_R: 1500, // within this of the own fountain is home (judgement: the fountain's heal reaches 1,200)
    RUN_STEP: 150, // a retreat second closes on the fountain by at least this (a hero walks about 300 a second)
    RUN_MIN: 800, // a retreat run closes this much in all (judgement: past a step out of a creep's aggro)
    JUMP: 1500, // more than this in one second is a teleport or a respawn
    NEAR: 1500, // opponent: seconds within this of the hero
    TOWER_R: 900, // the front within this of an enemy tower is under it (a tower's attack range 700, plus the wave's spread)
};
const LINES = ['lh', 'dn', 'pool', 'own_pool', 'lh_share', 'lvl', 'nw', 'lvl_gap', 'behind2', 'fell2', 'att_s', 'attd_s',
    'hpl_hero', 'hpl_creep', 'hpl_tower', 'hpl_other',
    'ret_fountain', 'ret_after_hit', 'ret_low_hp', 'ret_no_damage', 'ret_other',
    'ret_fountain_s', 'ret_after_hit_s', 'ret_low_hp_s', 'ret_no_damage_s', 'ret_other_s',
    'trips', 'trip_s', 'trip_hp', 'trip_opp_lh', 'trip_tp', 'deaths', 'deaths_gap', 'wave_tower_s', 'tower_took'];
const RET = ['fountain', 'after_hit', 'low_hp', 'no_damage', 'other'];

const d2 = (ax, ay, bx, by) => (ax - bx) * (ax - bx) + (ay - by) * (ay - by);
const fdist = (team, x, y) => Math.sqrt(d2(x, y, FOUNTAIN[team][0], FOUNTAIN[team][1]));

/** One game's facts from the store: heroes with per-second series, hp loss rows, creep fates, fronts. */
function load(store, gameId, until) {
    const p = { g: gameId, u: until + 1 };
    const heroes = store.query(`SELECT pid, team, pos, ours FROM (
            SELECT b.pid, b.team, b.pos, b.ours, row_number() OVER (PARTITION BY b.pid ORDER BY b.seq DESC) AS rn
            FROM ev_bot b WHERE b.game_id = :g AND b.team IS NOT NULL AND b.pos IS NOT NULL) WHERE rn = 1 ORDER BY pid`, { g: gameId })
        .map((h) => ({ pid: h.pid, team: h.team, pos: h.pos, side: String(h.ours || '').includes(':1') ? 'ours' : 'oha' }));
    const secs = store.query(`-- ensure: ev_snap(pid, x, y, alive, hp, lvl, lh, dn, nw, deaths, hit, ah, tgt)
        SELECT pid, CAST(round(t) AS INTEGER) AS s, max(seq) AS seq, x, y, alive, hp, lvl, lh, dn, nw, deaths, hit, ah, tgt
        FROM ev_snap WHERE game_id = :g AND t >= 0 AND t <= :u AND typeof(x) IN ('integer', 'real')
        GROUP BY pid, CAST(round(t) AS INTEGER) ORDER BY pid, s`, p);
    const loss = store.query(`SELECT pid, t, died, loss, src FROM hp_loss WHERE game_id = :g AND t <= :u`, p);
    // The base tables, not view creep_fate: its deny pairing scans every game's creep deaths (about 1 s a game).
    const enemy = store.query(`-- ensure: ev_creep_death(team, kind, x, y, by, tw)
        SELECT t, team, kind, x, y, CAST("by" AS TEXT) AS by, tw FROM ev_creep_death WHERE game_id = :g AND t <= :u`, p);
    const own = store.query(`-- ensure: ev_own_creep_death(team, kind, x, y, by)
        SELECT t, team, kind, x, y, CAST("by" AS TEXT) AS by FROM ev_own_creep_death WHERE game_id = :g AND t <= :u`, p);
    return { heroes, secs, loss, fates: creepFates(enemy, own), fronts: frontsOf(store, p) };
}

/**
 * As view creep_fate, without its mutual-nearest pairing: an enemy creep no one's last hit is `enemy_deny` when the
 * other team logged a deny of one of its own creeps of the same kind within 1 s and 250 units, else `other`.
 */
function creepFates(enemy, own) {
    const denies = own.filter((o) => o.by !== 'none');
    const out = enemy.map((c) => ({ t: c.t, team: c.team, side: 'enemy', x: c.x, y: c.y, tw: c.tw ?? null,
        fate: c.by !== 'none' && c.by !== 'deny' ? 'own_lh'
            : c.by === 'deny' || denies.some((o) => o.team !== c.team && o.kind === c.kind && Math.abs(o.t - c.t) <= 1
                && d2(o.x, o.y, c.x, c.y) <= 250 * 250) ? 'enemy_deny' : 'other' }));
    for (const o of own) out.push({ t: o.t, team: o.team, side: 'own', x: o.x, y: o.y, tw: null, fate: o.by !== 'none' ? 'own_deny' : 'lost' });
    return out;
}

function frontsOf(store, p) {
    return store.query(`-- ensure: ev_front(team, topx, topy, midx, midy, botx, boty)
        SELECT CAST(round(t) AS INTEGER) AS s, max(seq) AS seq, team, topx, topy, midx, midy, botx, boty
        FROM ev_front WHERE game_id = :g AND t <= :u GROUP BY team, CAST(round(t) AS INTEGER) ORDER BY team, s`, p);
}

/** Retreat runs of one hero's series (seconds sorted), each { s0, s1, cls }. */
function retreatRuns(team, ser, lossAt) {
    const runs = [];
    let cur;
    const close = () => {
        if (cur && cur.drop >= C.RUN_MIN) runs.push(cur);
        cur = undefined;
    };
    for (let i = 1; i < ser.length; i++) {
        const a = ser[i - 1], b = ser[i];
        const gap = b.s - a.s;
        const jump = Math.sqrt(d2(a.x, a.y, b.x, b.y)) > C.JUMP * Math.max(1, gap);
        const step = (fdist(team, a.x, a.y) - fdist(team, b.x, b.y)) / Math.max(1, gap);
        const ok = gap <= 2 && !jump && a.alive !== 0 && b.alive !== 0 && step >= C.RUN_STEP;
        if (!ok) { close(); continue; }
        if (!cur) {
            if (fdist(team, a.x, a.y) <= C.BASE_R) continue;
            cur = { s0: a.s, i0: i - 1, drop: 0 };
        }
        cur.s1 = b.s;
        cur.i1 = i;
        cur.drop += step * gap;
    }
    close();
    for (const r of runs) {
        const a = ser[r.i0], b = ser[r.i1];
        const hitBefore = ser.slice(0, r.i0 + 1).some((x) => x.s >= r.s0 - 3 && x.hit === 1);
        const lost5 = lossAt(r.s0 - 5, r.s0);
        r.cls = fdist(team, b.x, b.y) <= C.BASE_R ? 'fountain'
            : hitBefore ? 'after_hit'
                : a.hp <= 50 ? 'low_hp'
                    : lost5 === 0 && a.hp > 80 ? 'no_damage' : 'other';
        r.secs = r.s1 - r.s0;
    }
    return runs;
}

/** Trips home of one hero: { dep, arr, back, hp, tp } with dep its last second in lane before reaching home. */
function trips(team, lane, ser, until) {
    const out = [];
    let lastLane, inTrip = false, tp = false;
    for (let i = 0; i < ser.length; i++) {
        const x = ser[i];
        const prev = ser[i - 1];
        if (prev && Math.sqrt(d2(prev.x, prev.y, x.x, x.y)) > C.JUMP * Math.max(1, x.s - prev.s)) tp = true;
        if (prev && (x.deaths || 0) > (prev.deaths || 0)) { lastLane = undefined; inTrip = false; }
        if (x.lane === lane) {
            if (inTrip) { out[out.length - 1].back = x.s; inTrip = false; }
            lastLane = x;
            tp = false;
            continue;
        }
        if (!inTrip && lastLane && x.alive !== 0 && fdist(team, x.x, x.y) <= C.BASE_R) {
            out.push({ dep: lastLane.s, arr: x.s, back: undefined, hp: lastLane.hp, tp, depLh: lastLane.lh });
            inTrip = true;
            lastLane = undefined;
        }
    }
    for (const t of out) if (t.back === undefined) t.back = until;
    return out;
}

/** The latest series row at or before second s (series sorted). */
function at(ser, s) {
    let lo = 0, hi = ser.length - 1, best;
    while (lo <= hi) {
        const m = (lo + hi) >> 1;
        if (ser[m].s <= s) { best = ser[m]; lo = m + 1; } else hi = m - 1;
    }
    return best;
}

/** Rows for one game: one per hero and time. `facts` as load() returns. */
function score(facts, ats) {
    const until = Math.max(...ats);
    const by = new Map(facts.heroes.map((h) => [h.pid, { ...h, ser: [] }]));
    for (const r of facts.secs) {
        const h = by.get(r.pid);
        if (h) h.ser.push({ ...r, lane: laneLabel([r.x, r.y]) });
    }
    const heroes = [...by.values()].filter((h) => h.ser.length);
    for (const h of heroes) {
        const n = {};
        for (const x of h.ser) if (x.s >= 60 && x.s <= 300 && x.alive !== 0 && ['top', 'mid', 'bot'].includes(x.lane)) n[x.lane] = (n[x.lane] || 0) + 1;
        h.lane = Object.keys(n).sort((a, b) => n[b] - n[a])[0] || 'none';
    }
    const core = (pos) => pos <= 3;
    for (const h of heroes) {
        const cands = heroes.filter((e) => e.team !== h.team && e.lane === h.lane && h.lane !== 'none').map((e) => {
            let near = 0;
            for (const x of h.ser) {
                if (x.s < 60 || x.s > 300) continue;
                const y = at(e.ser, x.s);
                if (y && y.s === x.s && d2(x.x, x.y, y.x, y.y) <= C.NEAR * C.NEAR) near++;
            }
            return { e, kind: core(e.pos) === core(h.pos) ? 1 : 0, near };
        }).sort((a, b) => b.kind - a.kind || b.near - a.near || a.e.pid - b.e.pid);
        h.opp = cands.length ? cands[0].e : undefined;
    }
    const lossBy = new Map();
    for (const r of facts.loss) {
        if (!lossBy.has(r.pid)) lossBy.set(r.pid, []);
        lossBy.get(r.pid).push(r);
    }
    const fates = facts.fates.map((f) => ({ ...f, lane: laneLabel([f.x, f.y]) }));
    const frontBy = { 2: [], 3: [] };
    for (const f of facts.fronts) if (frontBy[f.team]) frontBy[f.team].push(f);
    const towersOf = (team, lane) => TOWERS.filter(([t, x, y]) => t !== team && laneLabel([x, y]) === lane);
    const tagged = fates.some((f) => f.tw !== null && f.tw !== undefined);

    const rows = [];
    for (const h of heroes) {
        const losses = lossBy.get(h.pid) || [];
        const lossAt = (a, b) => losses.filter((r) => !r.died && r.t > a && r.t <= b).reduce((s, r) => s + r.loss, 0);
        const runs = retreatRuns(h.team, h.ser, lossAt);
        const trs = trips(h.team, h.lane, h.ser, until);
        const towers = towersOf(h.team, h.lane);
        for (const T of ats) {
            const me = at(h.ser, T) || {};
            const op = h.opp ? at(h.opp.ser, T) : undefined;
            const row = { label: facts.label, game_id: facts.game_id, pid: h.pid, team: h.team, pos: h.pos, side: h.side, lane: h.lane,
                opp: h.opp ? h.opp.pid : null, at: T };
            row.lh = me.lh ?? null;
            row.dn = me.dn ?? null;
            const inLane = fates.filter((f) => f.t <= T && f.lane === h.lane);
            row.pool = inLane.filter((f) => f.team === h.team && f.side === 'enemy').length;
            row.own_pool = inLane.filter((f) => f.team === h.team && f.side === 'own').length;
            row.lh_share = row.pool && row.lh !== null ? Math.round((1000 * row.lh) / row.pool) / 1000 : null;
            row.lvl = me.lvl ?? null;
            row.nw = me.nw ?? null;
            row.lvl_gap = op && me.lvl != null && op.lvl != null ? op.lvl - me.lvl : null;
            row.behind2 = null;
            row.fell2 = h.opp ? 0 : null;
            if (h.opp) {
                for (const x of h.ser) {
                    if (x.s > T) break;
                    const y = at(h.opp.ser, x.s);
                    if (y && x.lvl != null && y.lvl != null && y.lvl - x.lvl >= 2) { row.behind2 = x.s; row.fell2 = 1; break; }
                }
            }
            const live = h.ser.filter((x) => x.s <= T && x.alive !== 0);
            row.att_s = live.filter((x) => typeof x.tgt === 'string' && x.tgt.startsWith('npc_dota_hero')).length;
            row.attd_s = live.filter((x) => (x.ah || 0) > 0).length;
            const hpl = { hero: 0, creep: 0, tower: 0, other: 0 };
            for (const r of losses) {
                if (r.died || r.t > T) continue;
                const srcs = String(r.src).split('+').map((s) => s.replace('?', '')).map((s) => (s in hpl ? s : 'other'));
                for (const s of srcs) hpl[s] += r.loss / srcs.length;
            }
            for (const k of Object.keys(hpl)) row[`hpl_${k}`] = Math.round(hpl[k] * 10) / 10;
            for (const c of RET) {
                const mine = runs.filter((r) => r.s0 <= T && r.cls === c);
                row[`ret_${c}`] = mine.length;
                row[`ret_${c}_s`] = mine.reduce((s, r) => s + Math.min(r.s1, T) - r.s0, 0);
            }
            const tt = trs.filter((t) => t.dep <= T);
            row.trips = tt.length;
            row.trip_s = tt.reduce((s, t) => s + Math.min(t.back, T) - t.dep, 0);
            row.trip_hp = tt.length ? Math.round(tt.reduce((s, t) => s + t.hp, 0) / tt.length) : null;
            row.trip_opp_lh = h.opp ? tt.reduce((s, t) => {
                const a = at(h.opp.ser, t.dep), b = at(h.opp.ser, Math.min(t.back, T));
                return s + (a && b && a.lh != null && b.lh != null ? b.lh - a.lh : 0);
            }, 0) : null;
            row.trip_tp = tt.filter((t) => t.tp).length;
            const ds = [];
            for (let i = 1; i < h.ser.length && h.ser[i].s <= T + 1; i++) {
                const a = h.ser[i - 1], b = h.ser[i];
                if ((b.deaths || 0) > (a.deaths || 0) && a.s <= T) {
                    const y = h.opp ? at(h.opp.ser, a.s) : undefined;
                    ds.push(y && y.lvl != null && a.lvl != null ? y.lvl - a.lvl : null);
                }
            }
            row.deaths = ds.length;
            const gaps = ds.filter((g) => g !== null);
            row.deaths_gap = gaps.length ? Math.round((10 * gaps.reduce((s, g) => s + g, 0)) / gaps.length) / 10 : null;
            const k = { top: ['topx', 'topy'], mid: ['midx', 'midy'], bot: ['botx', 'boty'] }[h.lane];
            row.wave_tower_s = k ? (frontBy[h.team] || []).filter((f) => f.s <= T && f[k[0]] != null
                && towers.some(([, x, y]) => d2(f[k[0]], f[k[1]], x, y) <= C.TOWER_R * C.TOWER_R)).length : null;
            row.tower_took = tagged ? inLane.filter((f) => f.team !== h.team && f.side === 'enemy' && f.tw === 1 && f.fate === 'other').length : null;
            rows.push(row);
        }
    }
    return rows;
}

/** The games of the runs: each log's last game whose label starts with or file contains the run. */
function games(store, runs) {
    const out = [];
    const seen = new Set();
    for (const run of runs) {
        const rows = store.query(`SELECT g.game_id, g.file, g.label FROM games g
            WHERE (g.label LIKE :p ESCAPE '\\' OR g.file LIKE :f) AND g.game = (SELECT max(g2.game) FROM games g2 WHERE g2.file = g.file)
            ORDER BY g.label, g.file`, { p: `${run.replace(/_/g, '\\_')}%`, f: `%${run}%` });
        for (const r of rows) if (!seen.has(r.game_id)) { seen.add(r.game_id); out.push(r); }
    }
    return out;
}

function laneScore(store, runs, ats) {
    const rows = [];
    const gs = games(store, runs);
    for (const g of gs) rows.push(...score({ ...load(store, g.game_id, Math.max(...ats)), label: g.label, game_id: g.game_id }, ats));
    return { games: gs, rows };
}

/** Mean of each line per hero-game by time, side and position. */
function summary(rows) {
    const groups = new Map();
    for (const r of rows) {
        const k = `${r.at}|${r.side}|${r.pos}`;
        if (!groups.has(k)) groups.set(k, { at: r.at, side: r.side, pos: r.pos, n: 0, rows: [] });
        const gr = groups.get(k);
        gr.n++;
        gr.rows.push(r);
    }
    for (const gr of groups.values()) {
        for (const l of LINES) {
            const v = gr.rows.map((r) => r[l]).filter((x) => x !== null && x !== undefined);
            gr[l] = v.length ? v.reduce((s, x) => s + x, 0) / v.length : null;
        }
        delete gr.rows;
    }
    return [...groups.values()].sort((a, b) => a.at - b.at || a.side.localeCompare(b.side) || a.pos - b.pos);
}

function print(sum) {
    const f = (v) => (v === null ? '-' : Math.abs(v) >= 100 ? String(Math.round(v)) : (Math.round(v * 10) / 10).toFixed(1));
    for (const T of [...new Set(sum.map((s) => s.at))]) {
        const cols = sum.filter((s) => s.at === T);
        console.log(`== to ${Math.floor(T / 60)}:${String(T % 60).padStart(2, '0')}, mean per hero-game (n heroes in the column head)`);
        console.log(`${'line'.padEnd(16)} ${cols.map((c) => `${c.side === 'ours' ? 'o' : 'h'}${c.pos}/${c.n}`.padStart(7)).join(' ')}`);
        for (const l of LINES) console.log(`${l.padEnd(16)} ${cols.map((c) => f(c[l]).padStart(7)).join(' ')}`);
    }
}

function args(argv) {
    const o = { runs: [], at: [300, 600] };
    for (let i = 0; i < argv.length; i++) {
        const a = argv[i];
        if (a === '--at') o.at = argv[++i].split(',').map(Number);
        else if (a === '--rows') o.rows = true;
        else if (a === '--json') o.json = true;
        else if (a === '--no-ingest') o.noIngest = true;
        else if (a === '--help' || a === '-h') o.help = true;
        else o.runs.push(a);
    }
    if (o.at.some((t) => !(t > 0))) throw new Error('--at takes seconds, comma separated');
    return o;
}

if (require.main === module) {
    const o = args(process.argv.slice(2));
    if (o.help || !o.runs.length) {
        console.log(fs.readFileSync(__filename, 'utf8').split('\n').filter((l) => l.startsWith('//')).map((l) => l.slice(3)).join('\n'));
        process.exit(o.runs.length || o.help ? 0 : 2);
    }
    const store = new Store(DB);
    if (!o.noIngest) for (const f of store.ingestAll([LOGS, JOBS].filter((d) => fs.existsSync(d))).failed) console.error(`not ingested: ${f.file}: ${f.error}`);
    const res = laneScore(store, o.runs, o.at);
    if (!res.games.length) { console.error(`no games for ${o.runs.join(', ')}`); process.exit(1); }
    if (o.rows) console.log(o.json ? JSON.stringify(res.rows) : res.rows.map((r) => JSON.stringify(r)).join('\n'));
    else if (o.json) console.log(JSON.stringify({ games: res.games, summary: summary(res.rows) }));
    else { console.log(`${res.games.length} games; o = ours, h = OHA, then the position`); print(summary(res.rows)); }
}

module.exports = { laneScore, score, summary, retreatRuns, trips, creepFates, games, C, LINES };
