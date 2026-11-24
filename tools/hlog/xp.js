// The experience ledger: each team's experience gained to --at split by source, ours against OHA, summing exactly to the
// gain. Measured jumps, not counts times a value: per hero, every change in experience between consecutive ev=snap rows
// (`lvl` and `xpn` through the game's level table, gate.js) is assigned to one line. gold.js's twin: same runs, labels and flags.
// Usage: node xp.js <run> [<run> ...] [--null <run> ...] [--at 600] [--arm <name>] [--by pos|arm] [--json] [--no-ingest]
//   (each flag as gold.js: --null adds the mirror columns, --by pos one table per position, --by arm one column per arm)
//
// Lines: passive; lane_creep (melee/ranged/siege, and `denied`: creeps the other side denied, which pay half); neutral;
//   kill; shrine; other. Indented rows under a line are its parts and are not summed.
// Memo rows, after the sum and not in it: kept_from_them, the experience a side's own dying lane creeps did not give the
//   other side. Nobody's experience jumps for it, so it is a count times the game's measured value per creep kind:
//     deny               half of a creep this side denied with one of them in range (a deny pays them half)
//     out_of_range_camp  all of a creep that died with none of them within 1,500, inside or within 600 of a neutral camp's
//                        box (camp_boxes.json): a pulled wave
//     out_of_range_lane  the same, anywhere else
//   Only deaths the owning team logged count (unit_life's own deaths: a living own hero within 1,500), so a wave that dies with
//   no hero of either side near is in no row.
// Rules, per hero and snapshot interval, d = experience change, p = the patch's passive rate (7.42: 50 a minute after
//   0:00; 7.41: none) times the interval:
//   1. gain = d - p; under 2 it is rounding and stays in passive.
//   2. Causes: the hero's team's ev=creep_death rows and unit_life's neutral deaths within 1,650 of the hero (1,500 is the game's
//      share range; the rest is a frame of drift), each used once per hero. A cause is expected to pay the game's value
//      for its kind (the median of clean single-cause intervals times the heroes sharing; fallbacks from the reference
//      until three samples), halved for a denied creep (fragment creep_fate), over the team's living heroes within 1,500 of it.
//   3. An interval takes the causes logged inside it, then ones logged up to 0.5 s after it (a death is logged the frame
//      after) and up to 1 s before it, while their expected sum stays under the gain; the gain is split by expected value.
//   4. An enemy hero's death (fragment ep_death) within 1,650: the causes keep their expected value and the rest is kill.
//   5. Nothing to name it: shrine when it is 150 or more after 7:00 (the wisdom shrine's grant is not logged), else other.
//   6. passive is the plug: d minus every other line, so the lines sum to d exactly.
'use strict';
const sides = require('./sides');
const { xpOf, spanOf, SPANS } = require('./gate');

const DEATHS_SQL = `WITH gm AS MATERIALIZED (SELECT +game_id AS game_id FROM games WHERE game_id = :g),
-- include: ep_death
done AS (SELECT 1)
SELECT pid, t, x, y FROM ep_death WHERE t <= :at ORDER BY t`;
const LINES = ['passive', 'lane_creep', 'neutral', 'kill', 'shrine', 'other'];
const MEMO = 'kept_from_them';
const SHAPE = { lines: LINES, change: 'xpChange', changeRow: 'xp_change', memo: [MEMO] };
/** Experience a second after 0:00 by level table (docs/reference/specifics/patch-742-strategy.md; seen as one a second or so in ev=snap xpn). */
const PASSIVE = new Map([[SPANS[7.41], 0], [SPANS[7.42], 50 / 60]]);
const SLACK = 2;
/** Experience by kind until a game has three clean samples (docs/reference/specifics/lane-creeps-and-bounties.md; the neutral is a guess). */
const FALLBACK = { melee: 57, ranged: 69, siege: 88, neutral: 40 };
const SHARE = 1500;
const NEAR = 1650;
const BEFORE = 1;
const AFTER = 0.5;
const SHRINE_FROM = 420;
const SHRINE_MIN = 150;
const CAMP_PAD = 600;
const CAMPS = Object.values(require('./camp_boxes.json'));

const median = (a) => { const s = [...a].sort((x, y) => x - y); return s.length % 2 ? s[(s.length - 1) / 2] : (s[s.length / 2 - 1] + s[s.length / 2]) / 2; };
const bucket = (v) => (v < 15 ? '<15' : v < 40 ? '15-40' : v < 100 ? '40-100' : '100+');
const atCamp = (x, y) => CAMPS.some((c) => x >= c.x0 - CAMP_PAD && x <= c.x1 + CAMP_PAD && y >= c.y0 - CAMP_PAD && y <= c.y1 + CAMP_PAD);

/** A hero's snapshot nearest to t, when it is within 1.5 s and the hero is alive; a dead hero logs nothing. */
function at(snaps, t) {
    let lo = 0;
    let hi = snaps.length - 1;
    while (lo < hi) {
        const mid = (lo + hi) >> 1;
        if (snaps[mid].t < t) lo = mid + 1;
        else hi = mid;
    }
    const best = [snaps[lo - 1], snaps[lo]].filter(Boolean).sort((a, b) => Math.abs(a.t - t) - Math.abs(b.t - t))[0];
    return best && Math.abs(best.t - t) <= 1.5 && best.alive !== 0 ? best : undefined;
}

/** The pids of `team` alive within `range` of a point at t. */
function near(heroes, snaps, team, e, range) {
    return heroes.filter((h) => {
        if (h.team !== team) return false;
        const s = at(snaps.get(h.pid), e.t);
        return s !== undefined && Math.hypot(s.x - e.x, s.y - e.y) <= range;
    }).map((h) => h.pid);
}

function blankHero() {
    return { lines: Object.fromEntries(LINES.map((l) => [l, 0])), parts: {} };
}
const add = (rec, line, part, v) => {
    if (!v) return;
    if (LINES.includes(line)) rec.lines[line] += v;
    if (part) rec.parts[`${line}:${part}`] = (rec.parts[`${line}:${part}`] || 0) + v;
};

/** What a cause is expected to pay one hero: the kind's value, halved when denied, over the heroes sharing it. */
const expected = (e, est) => est[e.kind] * (e.denied ? 0.5 : 1) / Math.max(1, e.sharers);

/** Per hero: each snapshot interval with a gain, and the causes it could take. */
function intervals(snaps, mine, kills, passive) {
    const out = [];
    for (let i = 1; i < snaps.length; i++) {
        const x = snaps[i - 1];
        const y = snaps[i];
        const d = y.xp - x.xp;
        const gain = d - passive * Math.max(0, y.t - Math.max(x.t, 0));
        const iv = { x, y, d, gain };
        if (gain >= SLACK) {
            iv.inside = mine.filter((e) => e.t > x.t && e.t <= y.t);
            iv.after = mine.filter((e) => e.t > y.t && e.t <= y.t + AFTER);
            iv.before = mine.filter((e) => e.t > x.t - BEFORE && e.t <= x.t).reverse();
            iv.kills = kills.filter((k) => k.t > x.t - 1.5 && k.t <= y.t + AFTER);
        }
        out.push(iv);
    }
    return out;
}

/** The game's value per kind: the median of clean intervals (one cause logged inside, nothing else near, no kill) times its sharers. */
function unitValues(all) {
    const samples = {};
    for (const iv of all) {
        if (iv.gain < SLACK || iv.inside.length !== 1 || iv.after.length || iv.before.length || iv.kills.length) continue;
        const e = iv.inside[0];
        (samples[e.kind] = samples[e.kind] || []).push(iv.gain * Math.max(1, e.sharers) * (e.denied ? 2 : 1));
    }
    return Object.fromEntries(Object.keys(FALLBACK).map((k) => [k, samples[k] && samples[k].length >= 3 ? median(samples[k]) : FALLBACK[k]]));
}

/** Assigns one interval's change to lines. `used` is the hero's set of causes already paid for. */
function assign(rec, iv, est, used) {
    let assigned = 0;
    const put = (line, part, v) => { add(rec, line, part, v); assigned += v; };
    if (iv.gain >= SLACK) {
        const taken = [];
        let sum = 0;
        for (const e of [...iv.inside, ...iv.after, ...iv.before]) {
            if (used.has(e)) continue;
            const w = expected(e, est);
            // A cause joins while the expected sum stays nearer the gain with it than without; the first always joins.
            if (taken.length && sum + w / 2 > iv.gain) continue;
            taken.push([e, w]);
            sum += w;
            used.add(e);
        }
        const kill = iv.kills.find((k) => !used.has(k));
        const forCauses = kill ? Math.min(iv.gain, sum) : (taken.length ? iv.gain : 0);
        for (const [e, w] of taken) {
            const v = forCauses * w / sum;
            if (e.kind === 'neutral') put('neutral', undefined, v);
            else put('lane_creep', e.denied ? 'denied' : e.kind, v);
        }
        const rest = iv.gain - forCauses;
        if (rest >= SLACK) {
            if (kill) { put('kill', undefined, rest); used.add(kill); }
            else if (iv.y.t >= SHRINE_FROM && rest >= SHRINE_MIN) put('shrine', '(inferred)', rest);
            else put('other', bucket(rest), rest);
        }
    }
    rec.lines.passive += iv.d - assigned;
}

/** One game: per hero lines (with the hero), or { skip } with the reason. */
function analyseGame(store, g, at_) {
    const bots = new Map();
    for (const r of store.query('SELECT pid, team, pos FROM ev_bot WHERE game_id = :g ORDER BY seq', { g: g.game_id })) {
        if (!bots.has(r.pid)) bots.set(r.pid, { pid: r.pid, team: r.team, pos: r.pos });
        else if (bots.get(r.pid).pos == null && r.pos != null) bots.get(r.pid).pos = r.pos;
    }
    const has = (t, ...cols) => store.tables().includes(t) && cols.every((c) => store.colsOf(t).has(c));
    if (!has('ev_snap', 'xpn', 'lvl')) return { skip: 'no xpn in the snapshots' };
    const span = spanOf(store.query('SELECT lvl, max(xpn) AS xpn FROM ev_snap WHERE game_id = :g AND xpn IS NOT NULL GROUP BY lvl', { g: g.game_id }));
    const push = (map, k, v) => (map.get(k) || map.set(k, []).get(k)).push(v);
    const snaps = new Map();
    for (const r of store.query(`SELECT pid, t, lvl, xpn, x, y, alive FROM ev_snap WHERE game_id = :g AND t <= :at AND xpn IS NOT NULL AND lvl IS NOT NULL
        ORDER BY pid, t, seq`, { g: g.game_id, at: at_ })) push(snaps, r.pid, { ...r, xp: xpOf(r.lvl, r.xpn, span) });
    const heroes = [...bots.values()].filter((b) => snaps.has(b.pid));
    const teams = new Set(heroes.map((h) => h.team));
    if (heroes.length < 2 || teams.size !== 2) return { skip: `${heroes.length} heroes with experience snapshots, ${teams.size} team(s)` };
    for (const h of heroes) if (snaps.get(h.pid).length < 2) return { skip: `hero ${h.pid} has under 2 snapshots` };
    const lastT = Math.min(...heroes.map((h) => snaps.get(h.pid).at(-1).t));
    if (lastT < at_ - 30) return { skip: `game ends at ${lastT.toFixed(0)} s, before --at ${at_}` };

    // Causes by the team that gains from them: the enemy creeps and the neutrals each team's module saw die.
    const causes = new Map();
    const isPid = (v) => v !== null && /^\d+$/.test(String(v));
    // One read of the game's unit lives: the denied enemy creeps (fragment creep_fate), the neutral deaths and the own side's deny chances (CTEs ul_nlife, ul_odeath of unit_life's fragments).
    const lives = store.query(`WITH gm AS (SELECT :g AS game_id),
-- include: creep_fate
-- include: unit_life_neutral
SELECT 'denied' AS part, seq AS a, NULL AS t, NULL AS team, NULL AS kind, NULL AS x, NULL AS y, NULL AS by, NULL AS near_r, NULL AS near_d
    FROM creep_fate WHERE side = 'enemy' AND fate = 'enemy_deny'
UNION ALL
SELECT 'neutral', NULL, t1, NULL, NULL, x1, y1, NULL, near_r, near_d FROM ul_nlife WHERE t1 IS NOT NULL AND t1 <= :at2
UNION ALL
SELECT 'own', seq, t, team, kind, x, y, CAST(dny AS TEXT), NULL, NULL FROM ul_odeath WHERE t <= :at
ORDER BY 3, 2`, { g: g.game_id, at: at_, at2: at_ + AFTER });
    if (has('ev_creep_death', 'x', 'y', 'kind', 'by')) {
        const denied = new Set(lives.filter((r) => r.part === 'denied').map((r) => r.a));
        for (const r of store.query('SELECT seq, t, team, kind, x, y FROM ev_creep_death WHERE game_id = :g AND t <= :at ORDER BY t, seq', { g: g.game_id, at: at_ + AFTER })) {
            push(causes, r.team, { t: r.t, x: r.x, y: r.y, kind: r.kind in FALLBACK ? r.kind : 'melee', denied: denied.has(r.seq) });
        }
    }
    // A neutral's death is a cause for each team with a hero within 1,500 of it (the rows ev=neutral_death had, one per logging team).
    for (const r of lives.filter((l) => l.part === 'neutral')) for (const [team, near] of [[2, r.near_r], [3, r.near_d]]) {
        if (near) push(causes, team, { t: r.t, x: r.x, y: r.y, kind: 'neutral', denied: false });
    }
    for (const [team, list] of causes) {
        list.sort((a, b) => a.t - b.t);
        for (const e of list) {
            e.near = new Set(near(heroes, snaps, team, e, NEAR));
            e.sharers = near(heroes, snaps, team, e, SHARE).length;
        }
    }
    const teamOf = new Map(heroes.map((h) => [h.pid, h.team]));
    const deaths = store.query(DEATHS_SQL, { g: g.game_id, at: at_ }).filter((d) => teamOf.has(d.pid)).map((d) => ({ team: teamOf.get(d.pid), t: d.t, x: d.x, y: d.y }));

    const passive = PASSIVE.get(span) ?? 0;
    const per = heroes.map((h) => {
        const mine = (causes.get(h.team) || []).filter((e) => e.near.has(h.pid));
        const kills = deaths.filter((d) => {
            if (d.team === h.team) return false;
            const s = at(snaps.get(h.pid), d.t);
            return s !== undefined && Math.hypot(s.x - d.x, s.y - d.y) <= NEAR;
        });
        return { hero: h, ivs: intervals(snaps.get(h.pid), mine, kills, passive) };
    });
    const est = unitValues(per.flatMap((p) => p.ivs));
    const out = [];
    for (const { hero, ivs } of per) {
        const rec = blankHero();
        const used = new Set();
        for (const iv of ivs) assign(rec, iv, est, used);
        const s = snaps.get(hero.pid);
        rec.xpChange = s.at(-1).xp - s[0].xp;
        out.push({ hero, rec });
    }

    // The memo: what each team's own dying creeps did not give the other side, on the team's first hero so it folds once.
    for (const r of lives.filter((l) => l.part === 'own')) {
        const holder = out.find((o) => o.hero.team === r.team);
        const other = [...teams].find((t) => t !== r.team);
        if (!holder || other === undefined) continue;
        const value = est[r.kind in FALLBACK ? r.kind : 'melee'];
        if (!near(heroes, snaps, other, r, SHARE).length) add(holder.rec, MEMO, atCamp(r.x, r.y) ? 'out_of_range_camp' : 'out_of_range_lane', value);
        else if (isPid(r.by)) add(holder.rec, MEMO, 'deny', value / 2);
    }
    return { heroes: out, est };
}

if (require.main === module) sides.main(process.argv.slice(2), { file: __filename, shape: SHAPE, analyse: analyseGame });

module.exports = {
    analyseGame,
    gameResult: (store, g, at_) => sides.gameResult(store, g, at_, SHAPE, analyseGame),
    run: (store, runs, o) => sides.run(store, runs, o, SHAPE, analyseGame),
    rows: (...a) => sides.rows(SHAPE, ...a),
    LINES,
    MEMO,
    SHAPE,
};
