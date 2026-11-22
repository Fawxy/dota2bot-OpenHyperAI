// The gold ledger: each team's net-worth change to --at split into income by source and losses, ours against OHA, summing
// exactly to the change. Measured jumps, not counts times a price: per hero, every change in `nw` between consecutive
// ev=snap rows is assigned to one line.
// Usage: node gold.js <run> [<run> ...] [--null <run> ...] [--at 600] [--arm <name>] [--by pos|arm] [--json] [--no-ingest]
//   <run> is a label prefix (bis1 takes bis1_*; name bis1r too). Labels: `h2h742_A_rad_3`, the bisect form
//   `bis1_B_offrad_2` (arm `off`, seat glued on: rad or dire) and the batch arm form `h2hlift1_B_off-dir_10` (seat after
//   a hyphen: rad, dir or dire). Ours is the seat in the label, OHA the other team. A label with no seat
//   (`stockbase2_A_stock_7`, batch.js on mirror arms) is a mirror game: Radiant stands for ours, Dire for OHA; under --null
//   the seats are averaged, so the stand-in does not matter there.
//   --null <runs>  OHA against OHA runs: adds `mirror` (both seats' mean), `we` (ours - mirror) and `they` (mirror - OHA).
//   --arm <name>   only games of that arm (the label's word before the seat).
//   --by pos       one table per hero position (ev=bot pos), one hero a side, per game.
//   --by arm       one compact table: rows = lines, columns = arms, gap (ours - OHA) per game; plus our net-worth change.
//   Values are per game, summed over a team's five heroes, from each hero's first snapshot to the last at or before --at.
//
// Lines (income, +): passive; lane_creep (melee/ranged/siege); neutral; kill; assist; bounty_rune; other_income.
//   (losses, -): death; consumable (by item); other_loss. Indented rows under a line are its parts and are not summed.
// Rules, per hero and snapshot interval, d = nw change, p = 1.46 gold/s of game time after 0:00 (measured: no discrete tick
//   shows at 1 s; quiet intervals give 1 or 2 and every hero's mean is 1.46; a dead hero's interval still gets p):
//   1. Consumable loss L: items of the consumable table (tango 30 a charge, clarity, flask, wards, tp scroll, ...; prices are what the nw fell by in clean intervals) whose count
//      fell between two ev=inv rows inside the interval (other items vanishing are recipes combining, not a loss).
//   2. income = max(0, d - p + L); loss = d - p - income. A |loss| under 2.5 and an income under 2.5 are rounding: passive.
//   3. Income goes to the interval's causes in this order: lane creeps and neutrals the hero last-hit (ev=creep_death /
//      neutral_death by=pid, each taking that game's mean for a clean single-cause interval), a bounty rune picked up by
//      the team, then the rest to kill (own kills rose) or assist (an enemy hero died, fragment ep_death, within 1500 of the hero). With no
//      kill or assist the creeps and rune share all of it (the rune first at its mean). Nothing to name it: other_income.
//   4. A loss goes to consumable first (up to L), then death (own deaths rose), else other_loss.
//   4b. A fall with no consumable of its own takes an unspent one from the neighbouring interval (the inv row can land a snapshot off).
//   4c. Unexplained income at t <= 3 s (the 0:00 bounty runes, which ev=rune_pickup does not track) and jumps shared by three or
//      more heroes of a team within 2 s are bounty_rune parts marked (inferred); other unexplained income says what is near it.
//   5. passive is the plug: d minus every other line, so lines sum to d exactly.
'use strict';
const fs = require('fs');
const path = require('path');
const { Store, DB, LOGS, JOBS, labelOf } = require('./store');
const { parseLabel } = require('./label');

const DEATHS_SQL = `WITH gm AS MATERIALIZED (SELECT +game_id AS game_id FROM games WHERE game_id = :g),
-- include: ep_death
done AS (SELECT 1)
SELECT pid, t, x, y FROM ep_death WHERE t <= :at ORDER BY t`;
const PASSIVE = 1.46;
const SLACK = 2.5;
const CONSUMABLE = { tango: 30, flask: 100, clarity: 60, faerie_fire: 65, enchanted_mango: 65, smoke_of_deceit: 50, ward_observer: 0, ward_sentry: 50, tpscroll: 100, dust: 80, blood_grenade: 50 };
const FALLBACK = { lane_melee: 40, lane_ranged: 30, lane_siege: 70, lane_other: 40, neutral: 50, bounty: 50 };
const INCOME = ['passive', 'lane_creep', 'neutral', 'kill', 'assist', 'bounty_rune', 'other_income'];
const LOSS = ['death', 'consumable', 'other_loss'];
const LINES = [...INCOME, ...LOSS];
const ARMS = ['off', 'J', 'T', 'B', 'BF', 'noT', 'noF', 'noA', 'noC', 'noJ', 'all'];
const AT_WINDOW = [-1, 0.5]; // seconds either side of a snapshot interval where a creep death or rune pickup still belongs to it

function args(argv) {
    const o = { runs: [], null: [], at: 600, json: false };
    let into = o.runs;
    for (let i = 0; i < argv.length; i++) {
        const a = argv[i];
        if (a === '--null') into = o.null;
        else if (a === '--at') o.at = Number(argv[++i]);
        else if (a === '--arm') o.arm = argv[++i];
        else if (a === '--by') o.by = argv[++i];
        else if (a === '--json') o.json = true;
        else if (a === '--no-ingest') o.noIngest = true;
        else if (a === '--help' || a === '-h') o.help = true;
        else into.push(a);
    }
    return o;
}

/** Ingests only the logs of these runs (the store caches an unchanged log), local and remote-job layouts. */
function ingestRuns(store, runs) {
    const wanted = (label) => label && runs.some((r) => label.startsWith(`${r}_`));
    const files = [];
    for (const f of fs.existsSync(LOGS) ? fs.readdirSync(LOGS) : []) if (f.endsWith('.log') && wanted(labelOf(path.join(LOGS, f)))) files.push(path.join(LOGS, f));
    for (const d of fs.existsSync(JOBS) ? fs.readdirSync(JOBS) : []) {
        const f = path.join(JOBS, d, 'game.log');
        if (fs.existsSync(f) && wanted(labelOf(f))) files.push(f);
    }
    for (const f of files) store.ingest(f);
}

/** Each log's last game for the runs, with parsed label; a game with no readable seat is returned in `skipped`. */
function games(store, runs, { arm } = {}) {
    const out = [];
    const skipped = [];
    for (const run of runs) {
        const rows = store.query(`SELECT g.game_id, g.file, g.label FROM games g
            WHERE g.label LIKE :p ESCAPE '\\' AND g.game = (SELECT max(g2.game) FROM games g2 WHERE g2.file = g.file) ORDER BY g.label`,
        { p: `${run.replace(/_/g, '\\_')}\\_%` });
        for (const r of rows) {
            const p = parseLabel(r.label);
            if (!p) { skipped.push({ label: r.label, why: 'no <lineup>_<arm>[seat]_<n> in the label' }); continue; }
            if (arm !== undefined && p.arm !== arm) continue;
            out.push({ ...r, ...p });
        }
    }
    return { games: out, skipped };
}

function items(text) {
    const m = {};
    for (const part of String(text || '').split(/\s+/)) {
        const x = part.match(/^s\d+=([^:]+)(?::(\d+))?$/);
        if (!x) continue;
        const name = x[1] === 'tango_single' ? 'tango' : x[1];
        m[name] = (m[name] || 0) + (x[2] ? Number(x[2]) : 1);
    }
    return m;
}

/** Item count changes between consecutive ev=inv rows of one hero: [{ t, name, n }], n negative when the count fell. */
function itemChanges(rows) {
    const out = [];
    let prev = {};
    for (const r of rows) {
        const cur = items(r.items);
        for (const name of new Set([...Object.keys(prev), ...Object.keys(cur)])) {
            const n = (cur[name] || 0) - (prev[name] || 0);
            if (n) out.push({ t: r.t, name, n });
        }
        prev = cur;
    }
    return out;
}

const mean = (a) => a.reduce((x, y) => x + y, 0) / (a.length || 1);

/** Per hero: the interval records, with every event the interval holds. */
function intervals(snaps, ctx, hero) {
    const out = [];
    const takeNear = (list, lo, hi) => {
        const e = list.find((x) => !x.used && x.t > lo && x.t <= hi);
        if (e) e.used = true;
        return e;
    };
    for (let i = 1; i < snaps.length; i++) {
        const x = snaps[i - 1];
        const y = snaps[i];
        const lo = x.t + AT_WINDOW[0];
        const hi = y.t + AT_WINDOW[1];
        const iv = { x, y, d: y.nw - x.nw, p: PASSIVE * Math.max(0, y.t - Math.max(x.t, 0)), units: [], kills: y.kills - x.kills, deaths: y.deaths - x.deaths };
        for (let k = y.lh - x.lh; k > 0; k--) {
            const e = takeNear(ctx.creeps.get(hero.pid) || [], lo, hi);
            iv.units.push(e ? e.cat : 'unmatched');
        }
        const changes = (ctx.items.get(hero.pid) || []).filter((e) => e.t > x.t - 0.01 && e.t <= y.t + 0.01);
        iv.lost = changes.filter((e) => e.n < 0 && e.name in CONSUMABLE).map((e) => ({ ...e, n: -e.n }));
        iv.changes = changes;
        iv.creepNear = ctx.nearby.some((c) => c.team === hero.team && c.t > lo && c.t <= hi && Math.hypot(c.x - y.x, c.y - y.y) <= 1300);
        iv.rune = (ctx.runes.get(hero.team) || []).some((r) => r.t > lo && r.t <= hi);
        iv.assist = ctx.enemyDeaths.some((e) => e.team !== hero.team && e.t > x.t - 1.5 && e.t <= y.t && Math.hypot(e.x - y.x, e.y - y.y) <= 1500);
        out.push(iv);
    }
    return out;
}

/** The game's mean per-cause gold from clean intervals (one cause, nothing else in the interval); fallbacks when none. */
function unitValues(all) {
    const samples = {};
    for (const iv of all) {
        const net = iv.d - iv.p;
        const clean = !iv.kills && !iv.deaths && !iv.lost.length && !iv.assist;
        if (!clean) continue;
        const cause = iv.units.length === 1 && !iv.rune ? iv.units[0] : iv.rune && !iv.units.length ? 'bounty' : undefined;
        if (cause && cause !== 'unmatched' && net > SLACK) (samples[cause] = samples[cause] || []).push(net);
    }
    return Object.fromEntries(Object.keys(FALLBACK).map((k) => [k, samples[k] && samples[k].length >= 3 ? mean(samples[k]) : FALLBACK[k]]));
}

function blankHero() {
    return { lines: Object.fromEntries(LINES.map((l) => [l, 0])), parts: {}, unmatchedLh: 0 };
}
const add = (rec, line, part, v) => {
    if (!v) return;
    rec.lines[line] += v;
    if (part) rec.parts[`${line}:${part}`] = (rec.parts[`${line}:${part}`] || 0) + v;
};
const bucket = (v) => (v < 30 ? '<30' : v < 60 ? '30-60' : v < 100 ? '60-100' : '100+');

/** Assigns one interval's change to lines; returns the unexplained-income record for the team-wide pass. */
function assign(rec, iv, est, hero) {
    const { d, p } = iv;
    const net = d - p;
    const unitEst = (u) => est[u] ?? est.lane_other;
    const L = iv.lost.reduce((a, e) => a + CONSUMABLE[e.name] * e.n, 0);
    const gains = iv.units.length > 0 || iv.kills > 0 || iv.rune || iv.assist;
    const expected = iv.units.reduce((a, u) => a + unitEst(u), 0) + (iv.rune ? est.bounty : 0);
    let applyL = L > 0;
    if (applyL && !gains && net > -SLACK) applyL = false;
    // With only creeps and a rune to explain the gain, the reading closer to what they pay wins; kills and assists can absorb either.
    if (applyL && gains && !iv.kills && !iv.assist && Math.abs(net - expected) < Math.abs(net + L - expected)) applyL = false;
    const lost = applyL ? L : 0;
    let income = Math.max(0, net + lost);
    if (income < SLACK) income = 0;
    let loss = net - income;
    if (-loss < SLACK) loss = 0;
    let assigned = 0;
    const put = (line, part, v) => { add(rec, line, part, v); assigned += v; };

    let rest = income;
    const share = (cap) => { const v = Math.min(rest, cap); rest -= v; return v; };
    const restWhole = iv.kills > 0 || iv.assist;
    const creeps = iv.units.filter((u) => u !== 'unmatched');
    const loose = iv.units.length - creeps.length;
    if (income > 0) {
        const bounty = iv.rune ? share(est.bounty) : 0;
        const wants = [...creeps.map(unitEst), ...Array(loose).fill(est.lane_other)];
        const wantSum = wants.reduce((a, b) => a + b, 0);
        const forCreeps = restWhole ? share(wantSum) : (wants.length ? share(Infinity) : 0);
        let bountyAll = bounty;
        if (iv.rune && !restWhole && !wants.length) bountyAll += share(Infinity);
        put('bounty_rune', 'logged', bountyAll);
        creeps.forEach((u, i) => {
            const v = wantSum ? forCreeps * wants[i] / wantSum : 0;
            if (u === 'neutral') put('neutral', undefined, v);
            else put('lane_creep', u.replace('lane_', ''), v);
        });
        if (loose) {
            const v = wantSum ? forCreeps * (loose * est.lane_other) / wantSum : 0;
            rec.unmatchedLh += loose;
            put('other_income', 'unmatched_lh', v);
        }
        if (rest > 0) {
            if (iv.kills > 0) put('kill', undefined, rest);
            else if (iv.assist) put('assist', undefined, rest);
            else if (iv.y.t <= 3) put('bounty_rune', 'start_0:00 (inferred)', rest);
            else {
                const part = iv.creepNear ? 'creep_death_near_no_lh' : bucket(rest);
                put('other_income', part, rest);
                rec.unexplained.push({ t: iv.y.t, v: rest, hero, part, x: iv.y.x, y: iv.y.y });
            }
        }
    } else if (iv.units.length) rec.unmatchedLh += iv.units.filter((u) => u === 'unmatched').length;

    if (loss < 0) {
        let left = loss;
        if (applyL) {
            const c = -Math.min(-left, L);
            const weight = iv.lost.reduce((a, e) => a + CONSUMABLE[e.name] * e.n, 0) || 1;
            for (const e of iv.lost) put('consumable', e.name, c * (CONSUMABLE[e.name] * e.n) / weight);
            left -= c;
        }
        if (-left >= SLACK) {
            if (iv.deaths > 0) put('death', undefined, left);
            else { put('other_loss', lossPart(iv), left); rec.lossLog.push({ t: iv.y.t, v: left, hero, iv }); }
        }
    }
    rec.lines.passive += d - assigned;
}

const PRICES = [...new Set([30, 60, 90, 120, ...Object.values(CONSUMABLE).filter(Boolean)])];
function lossPart(iv) {
    const dg = iv.y.gold - iv.x.gold;
    const fall = -(iv.d - iv.p);
    if (dg < iv.d + 3 && dg > iv.d - 3 - iv.p) return 'gold_and_nw_fell';
    if (!iv.changes.length && PRICES.some((c) => Math.abs(fall - c) <= 3)) return 'consumable_price_no_inv_change';
    return `nw_fell_${bucket(fall)}`;
}

/** One game: per hero lines (with the hero), or { skip } with the reason. */
function analyseGame(store, g, at) {
    const bots = new Map();
    for (const r of store.query('SELECT pid, team, pos FROM ev_bot WHERE game_id = :g ORDER BY seq', { g: g.game_id })) {
        if (!bots.has(r.pid)) bots.set(r.pid, { pid: r.pid, team: r.team, pos: r.pos });
        else if (bots.get(r.pid).pos == null && r.pos != null) bots.get(r.pid).pos = r.pos;
    }
    const push = (map, k, v) => (map.get(k) || map.set(k, []).get(k)).push(v);
    const snaps = new Map();
    for (const r of store.query(`SELECT pid, t, gold, nw, lh, kills, deaths, x, y FROM ev_snap WHERE game_id = :g AND t <= :at AND nw IS NOT NULL
        ORDER BY pid, t, seq`, { g: g.game_id, at })) push(snaps, r.pid, r);
    const has = (t, ...cols) => store.tables().includes(t) && cols.every((c) => store.colsOf(t).has(c));
    const isPid = (v) => v !== null && /^\d+$/.test(String(v));
    const creeps = new Map();
    const nearby = [];
    if (has('ev_creep_death', 'x', 'y', 'kind', 'by')) for (const r of store.query('SELECT t, team, kind, "by" AS by, x, y FROM ev_creep_death WHERE game_id = :g ORDER BY t, seq', { g: g.game_id })) {
        nearby.push(r);
        if (isPid(r.by)) push(creeps, Number(r.by), { t: r.t, cat: `lane_${['melee', 'ranged', 'siege'].includes(r.kind) ? r.kind : 'other'}` });
    }
    if (has('ev_neutral_death', 'x', 'y', 'by')) for (const r of store.query('SELECT t, team, "by" AS by, x, y FROM ev_neutral_death WHERE game_id = :g ORDER BY t, seq', { g: g.game_id })) {
        nearby.push(r);
        if (isPid(r.by)) push(creeps, Number(r.by), { t: r.t, cat: 'neutral' });
    }
    const runes = new Map();
    if (has('ev_rune_pickup', 'kind', 'team')) for (const r of store.query("SELECT t, team FROM ev_rune_pickup WHERE game_id = :g AND kind = 'bounty' ORDER BY t", { g: g.game_id })) push(runes, r.team, { t: r.t });
    const itemsOf = new Map();
    if (has('ev_inv', 'items')) {
        const invRows = new Map();
        for (const r of store.query('SELECT pid, t, items FROM ev_inv WHERE game_id = :g ORDER BY pid, t, seq', { g: g.game_id })) push(invRows, r.pid, r);
        for (const [pid, rows] of invRows) itemsOf.set(pid, itemChanges(rows));
    }
    const heroes = [...bots.values()].filter((b) => snaps.has(b.pid));
    const teams = new Set(heroes.map((h) => h.team));
    if (heroes.length < 2 || teams.size !== 2) return { skip: `${heroes.length} heroes with snapshots, ${teams.size} team(s)` };
    for (const h of heroes) if (snaps.get(h.pid).length < 2) return { skip: `hero ${h.pid} has under 2 snapshots` };
    const lastT = Math.min(...heroes.map((h) => snaps.get(h.pid).at(-1).t));
    if (lastT < at - 30) return { skip: `game ends at ${lastT.toFixed(0)} s, before --at ${at}` };
    const teamOf = new Map(heroes.map((h) => [h.pid, h.team]));
    const enemyDeaths = store.query(DEATHS_SQL, { g: g.game_id, at })
        .filter((d) => teamOf.has(d.pid))
        .map((d) => ({ team: teamOf.get(d.pid), t: d.t, x: d.x, y: d.y }));
    const ctx = { creeps, runes, items: itemsOf, enemyDeaths, nearby };
    const per = heroes.map((h) => ({ hero: h, ivs: intervals(snaps.get(h.pid), ctx, h) }));
    // The inventory row can land one snapshot off the nw fall: a fall with no consumable of its own takes a neighbour's unspent one.
    for (const { ivs } of per) {
        ivs.forEach((iv, i) => {
            if (iv.lost.length || iv.d - iv.p > -SLACK) return;
            const nb = [ivs[i - 1], ivs[i + 1]].find((n) => n && n.lost.length && n.d - n.p > -SLACK && !n.units.length && !n.kills && !n.rune && !n.assist);
            if (nb) { iv.lost = nb.lost; nb.lost = []; }
        });
    }
    const est = unitValues(per.flatMap((p) => p.ivs));
    const out = [];
    for (const { hero, ivs } of per) {
        const rec = blankHero();
        rec.unexplained = [];
        rec.lossLog = [];
        for (const iv of ivs) assign(rec, iv, est, hero);
        const s = snaps.get(hero.pid);
        rec.nwChange = s.at(-1).nw - s[0].nw;
        out.push({ hero, rec });
    }
    reclassifyTeamSync(out);
    return { heroes: out, est };
}

/** Unexplained jumps shared by three or more heroes of a team within 2 s are bounty runes the pickup log missed: moved to bounty_rune. */
function reclassifyTeamSync(out) {
    const un = out.flatMap(({ hero, rec }) => rec.unexplained.map((u) => ({ ...u, rec })));
    for (const u of un) {
        const mates = new Set(un.filter((o) => o.hero.team === u.hero.team && Math.abs(o.t - u.t) <= 2 && o.v < 120).map((o) => o.hero.pid));
        if (u.v >= 120 || mates.size < 3) continue;
        const { lines, parts } = u.rec;
        lines.other_income -= u.v;
        lines.bounty_rune += u.v;
        parts[`other_income:${u.part}`] -= u.v;
        parts['bounty_rune:team_sync (inferred)'] = (parts['bounty_rune:team_sync (inferred)'] || 0) + u.v;
    }
}

/** One game as { ours: team totals, oha: team totals } plus per-position hero rows. */
function gameResult(store, g, at) {
    const a = analyseGame(store, g, at);
    if (a.skip) return { skip: a.skip };
    const side = (team) => (team === g.seat ? 'ours' : 'oha');
    const res = { label: g.label, arm: g.arm, ours: totals(), oha: totals(), pos: {}, est: a.est };
    for (const { hero, rec } of a.heroes) {
        const t = res[side(hero.team)];
        fold(t, rec);
        const key = `${side(hero.team)}:${hero.pos}`;
        res.pos[key] = totals();
        fold(res.pos[key], rec);
    }
    return res;
}
const totals = () => ({ nwChange: 0, lines: Object.fromEntries(LINES.map((l) => [l, 0])), parts: {}, unmatchedLh: 0 });
function fold(t, rec) {
    t.nwChange += rec.nwChange;
    t.unmatchedLh += rec.unmatchedLh;
    for (const l of LINES) t.lines[l] += rec.lines[l];
    for (const [k, v] of Object.entries(rec.parts)) t.parts[k] = (t.parts[k] || 0) + v;
}

function run(store, runs, o) {
    const { games: gs, skipped } = games(store, runs, o);
    const results = [];
    for (const g of gs) {
        const r = gameResult(store, g, o.at);
        if (r.skip) skipped.push({ label: g.label, why: r.skip });
        else results.push(r);
    }
    return { games: results, skipped };
}

const avg = (a) => a.reduce((x, y) => x + y, 0) / (a.length || 1);

/** Rows: the net-worth change, each line with its parts, the sum of the lines, as per-game means of `pick(game)` totals. */
function rows(result, nul, pickOurs = (g) => g.ours, pickOha = (g) => g.oha, wider = []) {
    const keys = new Set();
    const all = [...result.games, ...(nul ? nul.games : [])];
    for (const g of all) for (const t of [g.ours, g.oha]) for (const k of Object.keys(t.parts)) keys.add(k);
    for (const t of wider) for (const k of Object.keys(t.parts)) keys.add(k);
    const spec = [{ row: 'nw_change', get: (t) => t.nwChange }];
    for (const l of LINES) {
        spec.push({ row: l, get: (t) => t.lines[l] });
        for (const k of [...keys].filter((k) => k.startsWith(`${l}:`)).sort()) spec.push({ row: `  ${k.slice(l.length + 1)}`, get: (t) => t.parts[k] || 0, part: true });
    }
    spec.push({ row: 'sum_of_lines', get: (t) => LINES.reduce((a, l) => a + t.lines[l], 0) });
    return spec.map(({ row, get, part }) => {
        const ours = avg(result.games.map((g) => get(pickOurs(g))));
        const oha = avg(result.games.map((g) => get(pickOha(g))));
        const r = { row, ours, oha, gap: ours - oha, part: !!part };
        if (nul) {
            r.mirror = avg(nul.games.flatMap((g) => [get(g.ours), get(g.oha)]));
            r.we = ours - r.mirror;
            r.they = r.mirror - oha;
        }
        return r;
    });
}

const f1 = (v) => (Math.round(v * 10) / 10).toFixed(1);
function printRows(rs, head) {
    const cols = Object.keys(rs[0]).filter((k) => k !== 'row' && k !== 'part');
    console.log(head);
    console.log(`${'line'.padEnd(26)} ${cols.map((c) => c.padStart(8)).join(' ')}`);
    for (const r of rs) console.log(`${r.row.padEnd(26)} ${cols.map((c) => f1(r[c]).padStart(8)).join(' ')}`);
    const chg = rs.find((r) => r.row === 'nw_change');
    const sum = rs.find((r) => r.row === 'sum_of_lines');
    console.log(`check: sum_of_lines - nw_change = ${cols.map((c) => `${c} ${(sum[c] - chg[c]).toFixed(6)}`).join(', ')}`);
}

function armTable(result) {
    const by = new Map();
    for (const g of result.games) (by.get(g.arm) || by.set(g.arm, []).get(g.arm)).push(g);
    const arms = [...by.keys()].sort((a, b) => (ARMS.indexOf(a) + 1 || 99) - (ARMS.indexOf(b) + 1 || 99));
    const keys = result.games.flatMap((g) => [g.ours, g.oha]);
    const per = arms.map((a) => rows({ games: by.get(a) }, undefined, undefined, undefined, keys));
    const names = per[0].map((r) => r.row);
    const table = names.map((n) => ({ row: n, ...Object.fromEntries(arms.map((a, j) => [a, per[j].find((r) => r.row === n).gap])) }));
    table.push({ row: 'ours_nw_change', ...Object.fromEntries(arms.map((a, j) => [a, per[j].find((r) => r.row === 'nw_change').ours])) });
    table.push({ row: 'check_sum_minus_change', ...Object.fromEntries(arms.map((a, j) => [a, per[j].find((r) => r.row === 'sum_of_lines').gap - per[j].find((r) => r.row === 'nw_change').gap])) });
    table.push({ row: 'games', ...Object.fromEntries(arms.map((a) => [a, by.get(a).length])) });
    return { arms, table };
}

if (require.main === module) {
    const o = args(process.argv.slice(2));
    if (o.help || !o.runs.length) {
        console.log(fs.readFileSync(__filename, 'utf8').split('\n').filter((l) => l.startsWith('//')).map((l) => l.slice(3)).join('\n'));
        process.exit(o.runs.length || o.help ? 0 : 2);
    }
    const store = new Store(DB);
    if (!o.noIngest) ingestRuns(store, [...o.runs, ...o.null]);
    const result = run(store, o.runs, o);
    const nul = o.null.length ? run(store, o.null, { ...o, arm: undefined }) : undefined;
    for (const s of [...result.skipped, ...(nul ? nul.skipped : [])]) console.error(`skipped ${s.label}: ${s.why}`);
    if (!result.games.length) throw new Error('no games');
    const head = `${result.games.length} games${nul ? `, mirror ${nul.games.length} games` : ''}; per game, ours / OHA, gap = ours - OHA; first snapshot to ${o.at} s`
        + (nul ? '; mirror = OHA against OHA, both seats; we = ours - mirror, they = mirror - OHA' : '')
        + (result.games.some((g) => g.mirror) ? `; ${result.games.filter((g) => g.mirror).length} mirror games (no seat in the label): ours = Radiant, OHA = Dire` : '');
    if (o.by === 'arm') {
        const { arms, table } = armTable(result);
        if (o.json) console.log(JSON.stringify({ arms, table }));
        else {
            console.log(`${result.games.length} games; gap = ours - OHA per game, first snapshot to ${o.at} s`);
            console.log(`${'line'.padEnd(26)} ${arms.map((a) => a.padStart(7)).join(' ')}`);
            for (const r of table) console.log(`${r.row.padEnd(26)} ${arms.map((a) => f1(r[a]).padStart(7)).join(' ')}`);
        }
    } else if (o.by === 'pos') {
        const out = {};
        for (const pos of [1, 2, 3, 4, 5]) {
            const sel = (side) => (g) => g.pos[`${side}:${pos}`] || totals();
            const m = nul ? { games: nul.games.map((g) => ({ ours: g.pos[`ours:${pos}`] || totals(), oha: g.pos[`oha:${pos}`] || totals() })) } : undefined;
            const withParts = { games: result.games.map((g) => ({ ours: sel('ours')(g), oha: sel('oha')(g) })) };
            out[pos] = rows(withParts, m);
            if (!o.json) printRows(out[pos], `== pos ${pos}: one hero a side; ${head}`);
        }
        if (o.json) console.log(JSON.stringify(out));
    } else {
        const rs = rows(result, nul);
        if (o.json) console.log(JSON.stringify({ games: result.games.length, skipped: result.skipped, rows: rs, unmatchedLh: avg(result.games.map((g) => g.ours.unmatchedLh + g.oha.unmatchedLh)) }));
        else {
            printRows(rs, head);
            console.log(`last hits with no creep_death/neutral_death row: ${f1(avg(result.games.map((g) => g.ours.unmatchedLh)))} ours, ${f1(avg(result.games.map((g) => g.oha.unmatchedLh)))} OHA per game`);
        }
    }
}

module.exports = { parseLabel, games, analyseGame, gameResult, run, rows, armTable, items, itemChanges, LINES, PASSIVE };
