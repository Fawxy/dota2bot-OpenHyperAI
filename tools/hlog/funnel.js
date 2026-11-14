// Funnels from the loss ledger's rows (ledger.js): what our hero was doing at each loss, ours against OHA, per game.
// Usage:
//   node funnel.js <run> [<run> ...] --cause <cause> [--lane mid|top|bot|base|other] [--pos N] [--min-dist D] [--held K]
//                  [--heroes N] [--hitting 0|1] [--split dist|hp|minute|core_at|src] [--json] [--no-ingest]
//   node funnel.js <run> [<run> ...] --deaths --pos N[,N] [--json] [--no-ingest]
// Creeps (--cause is a ledger.js last-hit cause: denied, far_in_lane, idle_in_reach, ...). Each step keeps the rows of the one
// before, as a count per game, ours / OHA (`-` where only our own telemetry has the data):
//   <cause> in <lane>           the rows of that cause (and lane, and the lane core's --pos)
//   core over D away            --min-dist: the lane core was D or more from the creep
//   core in its lane            the core's snapshot lane is the creep's
//   core in laning mode         its snapshot mode (within 2.5 s) is `laning`
//   held by (ours)              the nearest ev=lane_pos line's `rp` (burst, threat, missing, none; the read at the preferred
//                               point; those in a retreat episode (with its why) are listed too); the funnel goes on with --held
//                               burst|threat|missing|none|retreat (default burst)
//   HP 50% or more              the core's HP at the creep
//   heroes in the spot cut      enemy heroes in the nearest ev=cut kind=spot (3 s before): 0, 1, 2+; on with --heroes (default 1)
//   hitting                     whether one of them hit the core recently (the cut's engaged flag); on with --hitting (default 0)
//   burst                       their damage over the core's HP (the read's: 6 s window when engaged, else 3 s): under 0.35,
//                               0.35-0.5, 0.5-1, 1 or more
// --split cuts the cause's rows (all rows of the lane; the distance step does not apply to dist) by the one field, a count per
// game: dist (0-400, 400-800, 800-1500, 1500+), hp (quarters), minute (2 minutes), core_at, src (seen or unseen).
// --deaths: the deaths to --until (720) of the hero position(s), per game, ours / OHA, by the ledger's cause; then for ours the
// retreat episode it died in (and its `why`), the stay the leave rule logged in the last 15 s (ev=cut kind=leave: even, hold,
// stand), its HP when a hero first hit it in those 15 s, and the heroes hitting it (the ledger's attackers).
// Runs are label prefixes as ledger.js; --at and --until as there.
'use strict';
const fs = require('fs');
const { Store, DB, LOGS, JOBS } = require('./store');
const { ledger } = require('./ledger');

const num = (v) => (v === undefined || v === null || v === '' ? NaN : Number(v));
const records = (s) => (s === undefined || s === null || s === '' ? [] : String(s).split(';').filter(Boolean).map((r) => r.split(',').map(Number)));

/* Tables and columns a log from a build without them may lack: created empty, so the funnel counts none from them. */
const ENSURE = ['ev_snap(pid, mode, hp, hit)', 'ev_lane_pos(pid, rp, why)', 'ev_cut(pid, kind, b, he, dec)', 'ev_retreat(pid, ph, kind, ep, why)']
    .map((e) => `-- ensure: ${e}`).join('\n');

/** Joins to a creep row's core, each the latest line in the 2.5 s window around the creep (the cut: 3 s before). */
function joiner(store) {
    store.ensure(ENSURE);
    const near = (sql) => { const st = store.db.prepare(sql); return (r, a = 2.5) => st.get({ g: r.game_id, p: r.pid, a: r.t - a, b: r.t + 0.5 }); };
    const snap = near('SELECT mode, hp FROM ev_snap WHERE game_id = :g AND pid = :p AND t BETWEEN :a AND :b ORDER BY t DESC, seq DESC LIMIT 1');
    const lanePos = near('SELECT rp, why FROM ev_lane_pos WHERE game_id = :g AND pid = :p AND t BETWEEN :a AND :b ORDER BY t DESC, seq DESC LIMIT 1');
    const cut = near("SELECT b, he FROM ev_cut WHERE game_id = :g AND pid = :p AND kind = 'spot' AND t BETWEEN :a AND :b ORDER BY t DESC, seq DESC LIMIT 1");
    const start = store.db.prepare("SELECT ep, why, t FROM ev_retreat WHERE game_id = :g AND pid = :p AND ph = 'start' AND kind = 'ours' AND t <= :b ORDER BY t DESC, seq DESC LIMIT 1");
    const end = store.db.prepare("SELECT t FROM ev_retreat WHERE game_id = :g AND pid = :p AND ph = 'end' AND kind = 'ours' AND ep = :ep AND t >= :s ORDER BY t LIMIT 1");
    /** The retreat episode the core was in at t: its `why`, else undefined. */
    const retreat = (r) => {
        const s = start.get({ g: r.game_id, p: r.pid, b: r.t });
        if (!s) return undefined;
        const e = end.get({ g: r.game_id, p: r.pid, ep: s.ep, s: s.t });
        return !e || e.t >= r.t ? String(s.why) : undefined;
    };
    return { snap, lanePos, cut, retreat };
}

const BANDS = [['under 0.35', 0.35], ['0.35 to 0.5', 0.5], ['0.5 to 1', 1], ['1 or more', Infinity]];
const bandOf = (v) => BANDS.find(([, hi]) => v < hi)[0];

/** The spot cut's reading for a core: enemy hero count, whether one hit it, burst over HP. */
function readCut(c) {
    if (!c) return undefined;
    const he = records(c.he);
    const hp = Number(String(c.b).split(',')[2]);
    const engaged = he.some((h) => h[8]);
    const dmg = he.reduce((s, h) => s + (h[8] ? h[10] : h[9]), 0);
    return { heroes: he.length, engaged, burst: dmg / hp };
}

const heroesKey = (n) => (n >= 2 ? '2+' : String(n));

/**
 * The creep funnel: { games, steps: [{ label, ours, oha, parts?, pernote }] } with counts per game (null where ours only).
 * `rows` are ledger.js rows.creeps.
 */
function creepFunnel(store, rows, nGames, o) {
    const j = joiner(store);
    const base = rows.filter((r) => r.cause === o.cause && (o.lane === undefined || r.lane === o.lane)
        && (o.pos === undefined || String(r.pos) === String(o.pos)));
    const count = (list) => ({ ours: list.filter((r) => r.side === 'ours').length / nGames, oha: list.filter((r) => r.side === 'oha').length / nGames });
    const steps = [];
    let cur = base;
    const step = (label, next, { oursOnly = false, parts } = {}) => {
        const c = count(next);
        steps.push({ label, ours: c.ours, oha: oursOnly ? null : c.oha, parts });
        cur = next;
    };
    const breakdown = (list, f, order) => {
        const m = new Map(order.map((k) => [k, { ours: 0 }]));
        for (const r of list) { const k = f(r); if (!m.has(k)) m.set(k, { ours: 0 }); m.get(k).ours += 1 / nGames; }
        return [...m].map(([label, v]) => ({ label, ours: v.ours }));
    };
    step(`${o.cause} in ${o.lane || 'all lanes'}`, base);
    if (o.minDist !== undefined) step(`core over ${o.minDist} away`, cur.filter((r) => r.dist >= o.minDist));
    step('core in its lane', cur.filter((r) => r.core_at === r.lane));
    for (const r of cur) r.snap = j.snap(r) || {};
    step('core in laning mode', cur.filter((r) => r.snap.mode === 'laning'));
    // From here our own telemetry only: ev=lane_pos, ev=retreat and ev=cut are written for our heroes.
    const mine = cur.filter((r) => r.side === 'ours');
    for (const r of mine) {
        const ret = j.retreat(r);
        const lp = j.lanePos(r) || {};
        r.held = lp.rp === undefined || lp.rp === null ? 'no lane_pos' : String(lp.rp);
        r.retreat = ret === undefined ? 'no' : `retreat:${ret}`;
    }
    const heldKind = o.held || 'burst';
    const heldParts = [...breakdown(mine, (r) => r.held, ['burst', 'threat', 'missing', 'none']),
        ...breakdown(mine.filter((r) => r.retreat !== 'no'), (r) => `in a retreat episode (${r.retreat.slice(8)})`, [])];
    step(`held by ${heldKind}`, mine.filter((r) => (heldKind === 'retreat' ? r.retreat !== 'no' : r.held === heldKind)), { oursOnly: true, parts: heldParts });
    step('HP 50% or more', cur.filter((r) => r.hp >= 50), { oursOnly: true });
    for (const r of cur) r.cut = readCut(j.cut(r, 3));
    const nHeroes = o.heroes === undefined ? 1 : o.heroes;
    step(`${heroesKey(nHeroes)} enemy hero in the spot cut`, cur.filter((r) => r.cut && Math.min(r.cut.heroes, 2) === Math.min(nHeroes, 2)), {
        oursOnly: true, parts: breakdown(cur, (r) => (r.cut ? heroesKey(r.cut.heroes) : 'no cut'), ['0', '1', '2+', 'no cut']),
    });
    const hitting = o.hitting === undefined ? 0 : o.hitting;
    step(hitting ? 'one is hitting' : 'none is hitting', cur.filter((r) => r.cut.engaged === !!hitting), {
        oursOnly: true, parts: breakdown(cur, (r) => (r.cut.engaged ? 'hitting' : 'not hitting'), ['not hitting', 'hitting']),
    });
    steps.push({ label: 'burst over HP', ours: cur.length / nGames, oha: null, parts: breakdown(cur, (r) => bandOf(r.cut.burst), BANDS.map(([b]) => b)) });
    steps.push({ label: 'burst under 1', ours: cur.filter((r) => r.cut.burst < 1).length / nGames, oha: null });
    return { games: nGames, steps };
}

const SPLITS = {
    dist: { f: (r) => (r.dist == null ? 'unknown' : r.dist < 400 ? '0-400' : r.dist < 800 ? '400-800' : r.dist < 1500 ? '800-1500' : '1500+'), order: ['0-400', '400-800', '800-1500', '1500+', 'unknown'] },
    hp: { f: (r) => (r.hp == null ? 'unknown' : r.hp < 25 ? 'under 25' : r.hp < 50 ? '25-50' : r.hp < 75 ? '50-75' : '75+'), order: ['under 25', '25-50', '50-75', '75+', 'unknown'] },
    minute: { f: (r) => `${Math.floor(r.t / 120) * 2}-${Math.floor(r.t / 120) * 2 + 2} min`, order: [] },
    core_at: { f: (r) => String(r.core_at), order: [] },
    src: { f: (r) => r.src, order: ['seen', 'unseen'] },
};

/** The cause's rows cut by one field, plus the lane's causes for context: { causes, parts }. */
function splitCreeps(rows, nGames, o) {
    const how = SPLITS[o.split];
    if (!how) throw new Error('--split takes dist, hp, minute, core_at or src');
    const lane = rows.filter((r) => o.lane === undefined || r.lane === o.lane);
    const per = (list) => ({ ours: list.filter((r) => r.side === 'ours').length / nGames, oha: list.filter((r) => r.side === 'oha').length / nGames });
    const causes = [...new Set(lane.map((r) => r.cause))].map((c) => ({ label: c, ...per(lane.filter((r) => r.cause === c)) }));
    causes.push({ label: 'pool', ...per(lane) });
    const sel = lane.filter((r) => r.cause === o.cause && (o.split === 'dist' || o.minDist === undefined || r.dist >= o.minDist));
    const keys = [...new Set([...how.order, ...sel.map(how.f)])].filter((k) => how.order.includes(k) || sel.some((r) => how.f(r) === k)).sort((a, b) => {
        const ia = how.order.indexOf(a), ib = how.order.indexOf(b);
        return ia >= 0 && ib >= 0 ? ia - ib : ia >= 0 ? -1 : ib >= 0 ? 1 : a.localeCompare(b, undefined, { numeric: true });
    });
    return { games: nGames, causes, parts: keys.map((k) => ({ label: k, ...per(sel.filter((r) => how.f(r) === k)) })) };
}

const STAYS = ['even', 'hold', 'stand'];

/** The deaths funnel for the positions: counts per game by cause for both sides, then ours' context. */
function deathFunnel(store, rows, nGames, o) {
    const pos = new Set(o.pos);
    const sel = rows.filter((r) => pos.has(Number(r.pos)));
    const per = (list) => ({ ours: list.filter((r) => r.side === 'ours').length / nGames, oha: list.filter((r) => r.side === 'oha').length / nGames });
    const causes = [...new Set(sel.map((r) => r.cause))].map((c) => ({ label: c, ...per(sel.filter((r) => r.cause === c)) }));
    const mine = sel.filter((r) => r.side === 'ours');
    const retreat = joiner(store).retreat; // (also ensures the tables the statements below read)
    const stay = store.db.prepare("SELECT dec FROM ev_cut WHERE game_id = :g AND pid = :p AND kind = 'leave' AND dec IN ('even', 'hold', 'stand') AND t BETWEEN :a AND :b ORDER BY t DESC, seq DESC LIMIT 1");
    const firstHit = store.db.prepare('SELECT hp FROM ev_snap WHERE game_id = :g AND pid = :p AND t BETWEEN :a AND :b AND hit > 0 ORDER BY t, seq LIMIT 1');
    for (const r of mine) {
        r.retreat = retreat(r) === undefined ? 'no' : `retreat:${retreat(r)}`;
        const w = { g: r.game_id, p: r.pid, a: r.t - 15, b: r.t };
        const s = stay.get(w);
        r.stay = s ? `stay:${s.dec}` : 'no stay';
        const h = firstHit.get(w);
        r.hit = !h || h.hp == null ? 'no hit' : h.hp < 25 ? 'HP under 25' : h.hp < 50 ? 'HP 25-50' : h.hp < 75 ? 'HP 50-75' : 'HP 75+';
        r.heroes = r.attackers >= 2 ? '2+ heroes' : `${r.attackers} hero${r.attackers === 1 ? '' : 'es'}`;
    }
    const part = (key, order) => {
        const m = new Map(order.map((k) => [k, 0]));
        for (const r of mine) m.set(r[key], (m.get(r[key]) || 0) + 1 / nGames);
        return [...m].map(([label, ours]) => ({ label, ours, oha: null }));
    };
    return {
        games: nGames, causes: [...causes, { label: 'total', ...per(sel) }],
        ours: [
            { label: 'in a retreat episode at death', parts: part('retreat', ['no', 'retreat:threat', 'retreat:lethal', 'retreat:tower', 'retreat:heal']) },
            { label: 'a stay in the last 15 s', parts: part('stay', ['no stay', ...STAYS.map((s) => `stay:${s}`)]) },
            { label: 'HP when a hero first hit it in the last 15 s', parts: part('hit', ['no hit', 'HP under 25', 'HP 25-50', 'HP 50-75', 'HP 75+']) },
            { label: 'heroes hitting it', parts: part('heroes', ['0 heroes', '1 hero', '2+ heroes']) },
        ],
    };
}

const f2 = (v) => (v === null ? '-' : v.toFixed(2));
const line = (label, ours, oha, indent = 0) => `${' '.repeat(indent)}${label}`.padEnd(46) + f2(ours).padStart(8) + f2(oha).padStart(8);

function printCreeps(r, o) {
    console.log(`${r.games} games; ${o.cause}${o.lane ? ` in ${o.lane}` : ''}; per game, ours / OHA ('-': our own telemetry only)`);
    for (const s of r.steps) {
        console.log(line(s.label, s.ours, s.oha));
        for (const p of s.parts || []) console.log(line(p.label, p.ours, null, 3));
    }
}

function printSplit(r, o) {
    console.log(`${r.games} games; ${o.lane ? `${o.lane} lane` : 'all lanes'}; per game, ours / OHA`);
    for (const c of r.causes) console.log(line(c.label, c.ours, c.oha));
    console.log(`${o.cause} by ${o.split}${o.split !== 'dist' && o.minDist !== undefined ? ` (core over ${o.minDist} away)` : ''}`);
    for (const p of r.parts) console.log(line(p.label, p.ours, p.oha, 3));
}

function printDeaths(r, o) {
    console.log(`${r.games} games; deaths of pos ${o.pos.join(',')} to ${o.until} s; per game, ours / OHA ('-': our own telemetry only)`);
    for (const c of r.causes) console.log(line(c.label, c.ours, c.oha));
    for (const g of r.ours) {
        console.log(g.label);
        for (const p of g.parts) console.log(line(p.label, p.ours, null, 3));
    }
}

function args(argv) {
    const o = { runs: [], until: 720, at: 600 };
    for (let i = 0; i < argv.length; i++) {
        const a = argv[i];
        const v = () => argv[++i];
        if (a === '--cause') o.cause = v();
        else if (a === '--lane') o.lane = v();
        else if (a === '--pos') o.pos = v();
        else if (a === '--min-dist') o.minDist = num(v());
        else if (a === '--held') o.held = v();
        else if (a === '--heroes') o.heroes = num(v());
        else if (a === '--hitting') o.hitting = num(v());
        else if (a === '--split') o.split = v();
        else if (a === '--deaths') o.deaths = true;
        else if (a === '--until') o.until = num(v());
        else if (a === '--at') o.at = num(v());
        else if (a === '--json') o.json = true;
        else if (a === '--no-ingest') o.noIngest = true;
        else if (a === '--help' || a === '-h') o.help = true;
        else o.runs.push(a);
    }
    return o;
}

/** Runs the funnel the options name on a store; returns { kind, result }. */
function run(store, o) {
    if (o.deaths) {
        if (o.pos === undefined) throw new Error('--deaths needs --pos N');
        const L = ledger(store, o.runs, o);
        o = { ...o, pos: String(o.pos).split(',').map(Number) };
        return { kind: 'deaths', o, result: deathFunnel(store, L.rows.deaths, L.games.length, o) };
    }
    if (!o.cause) throw new Error('--cause <cause> or --deaths');
    const L = ledger(store, o.runs, o);
    return o.split
        ? { kind: 'split', o, result: splitCreeps(L.rows.creeps, L.games.length, o) }
        : { kind: 'creeps', o, result: creepFunnel(store, L.rows.creeps, L.games.length, o) };
}

if (require.main === module) {
    const o = args(process.argv.slice(2));
    if (o.help || !o.runs.length) {
        console.log(fs.readFileSync(__filename, 'utf8').split('\n').filter((l) => l.startsWith('//')).map((l) => l.slice(3)).join('\n'));
        process.exit(o.help ? 0 : 2);
    }
    const store = new Store(DB);
    if (!o.noIngest) for (const f of store.ingestAll([LOGS, JOBS].filter((d) => fs.existsSync(d))).failed) console.error(`not ingested: ${f.file}: ${f.error}`);
    const { kind, o: oo, result } = run(store, o);
    if (o.json) console.log(JSON.stringify(result));
    else (kind === 'deaths' ? printDeaths : kind === 'split' ? printSplit : printCreeps)(result, oo);
}

module.exports = { run, creepFunnel, splitCreeps, deathFunnel, readCut, bandOf };
