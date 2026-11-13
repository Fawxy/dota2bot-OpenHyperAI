#!/usr/bin/env node
'use strict';
// Fixture cuts (rework step 8): turns an ev=cut line (bot cut.ts) into a decision fixture's world, and checks that the
// cut replays what the game decided.
//   node cut.js <log> --pid P --t 5:12 [--kind spot|gate] [--who CONSUMER] [--game N] [--id ID]   print a fixture (YAML) for
//       the cut at or just before t (--who: a gate cut's consumer, e.g. core_camp)
//   node cut.js <log> --check [--kind spot|gate] [--game N] [--sample 150] [--json]   replay a sample of the game's cuts of
//       one kind (default spot) through the decision's driver and compare with what the game logged beside them
//       (spot: ev=lane_pos sx, sy, why, rp; gate: the ev=threat dec, go or threat or missing)
// --game: which game of the log (1-based; default the last, so a remote job's stub game 1 is skipped).
const fs = require('fs'), path = require('path');
const { newState, doFile, doString, getGlobal } = require('../../tests/humaniser/harness');

const FIELD_RE = /(\w+)=("([^"]*)"|\S+)/g;
/** The game clock goes back by more than this between games of one log (parse.js GAME_SPLIT_REGRESSION). */
const GAME_SPLIT = 30;
/** A replayed spot this close to the logged one (logged coordinates are floored) is the same spot. */
const SAME_SPOT = 5;

/** Raw field strings: a hex vision grid of digits must not become a number. */
function fields(text) {
    const out = {};
    for (const m of text.matchAll(FIELD_RE)) out[m[1]] = m[3] !== undefined ? m[3] : m[2];
    return out;
}

/** The log's games, each { cuts, creeps, lanePos, threats, bots, towers } keyed for joining by pid and t (threats also by consumer). */
function readGames(text) {
    const games = [];
    let g, last = -Infinity;
    for (const line of text.split('\n')) {
        if (line.includes('[DOTACTL] ')) continue;
        const i = line.indexOf('[HEV] ');
        if (i < 0) continue;
        const f = fields(line.slice(i + 6));
        const t = Number(f.t);
        if (!Number.isFinite(t)) continue;
        if (g === undefined || t < last - GAME_SPLIT) {
            // Tower places do not move: a pregame line split off by a clock jump still serves the game after it.
            g = { cuts: [], creeps: new Map(), lanePos: new Map(), threats: new Map(), bots: new Map(g?.bots || []), towers: new Map(g?.towers || []) };
            games.push(g);
        }
        last = t;
        const key = `${f.pid}@${f.t}`;
        if (f.ev === 'cut') g.cuts.push(f);
        else if (f.ev === 'cut_creeps') g.creeps.set(key, f);
        else if (f.ev === 'lane_pos') g.lanePos.set(key, f);
        else if (f.ev === 'threat') g.threats.set(`${key}@${f.who}`, f);
        else if (f.ev === 'bot' && !g.bots.has(f.pid)) g.bots.set(f.pid, f);
        else if (f.ev === 'cut_towers' && !g.towers.has(f.team)) g.towers.set(f.team, f);
    }
    return games;
}

const nums = s => s.split(',').map(Number);
const records = s => (s === undefined || s === '' ? [] : s.split(';').map(r => r.split(',')));

function creepList(s) {
    return records(s).map(([id, x, y, hp, mhp, ranged, tgt, hull]) => ({ id: +id, x: +x, y: +y, hp: +hp, mhp: +mhp, ranged: +ranged, tgt, hull: +hull }));
}

function oursOf(bot) {
    const out = {};
    for (const kv of String(bot?.ours || '').split(',')) {
        const [k, v] = kv.split(':');
        if (k) out[k] = v === '1';
    }
    return out;
}

/** The standing towers of both teams for a cut's `ta` masks (own, enemy), with the attack targets `tt` gives. */
function towersOf(game, team, ta, tt) {
    const enemy = team === 2 ? 3 : 2;
    const [ownMask, enemyMask] = String(ta).split(',').map(h => parseInt(h, 16));
    const targets = new Map(records(tt).map(([t, i, tgt]) => [`${t}:${i}`, tgt]));
    const towers = [];
    for (const [t, mask] of [[team, ownMask], [enemy, enemyMask]]) {
        const line = game.towers.get(String(t));
        if (!line) throw new Error(`no ev=cut_towers for team ${t}`);
        for (const [i, x, y, r, h] of records(line.tw).map(r => r.map(Number))) {
            if (!(mask & (1 << i))) continue;
            towers.push({ team: t, i, x, y, range: r, hull: h, tgt: targets.get(`${t}:${i}`) || '-' });
        }
    }
    return towers;
}

const heroRecords = s => records(s).map(([pid, x, y, hp, r, h, sp, atk, eng, e3, e6, ill]) =>
    ({ pid: +pid, x: +x, y: +y, hp: +hp, range: +r, hull: +h, speed: +sp, atk: +atk, eng: +eng, e3: +e3, e6: +e6, ill: +ill }));
const unseenRecords = s => records(s).map(([pid, x, y, tss, sp]) => ({ pid: +pid, x: +x, y: +y, tss: +tss, sp: +sp }));
const allyRecords = s => records(s).map(([pid, x, y, r, h, sp, ret]) => ({ pid: +pid, x: +x, y: +y, range: +r, hull: +h, speed: +sp, ret: +ret }));

/** The fixture world for one ev=cut line of kind `gate`: the walk, the heroes, the towers and the walk's vision. */
function gateWorld(game, cut) {
    const bot = game.bots.get(cut.pid);
    if (!bot) throw new Error(`no ev=bot for pid ${cut.pid}`);
    const team = Number(bot.team);
    const [bx, by, hp, mhp, range, hull, speed, esc] = nums(cut.b);
    const [fx, fy] = nums(cut.fm), [px, py] = nums(cut.pl);
    const w = {
        t: Number(cut.t), team, pid: Number(cut.pid), who: cut.who, ours: oursOf(bot),
        bot: { x: bx, y: by, hp, mhp, range, hull, speed, esc },
        from: { x: fx, y: fy }, place: { x: px, y: py },
        he: heroRecords(cut.he), hu: unseenRecords(cut.hu), ha: allyRecords(cut.ha),
        towers: towersOf(game, team, cut.ta, undefined),
    };
    if (cut.vw !== undefined) { const [n, hex] = cut.vw.split(','); w.vw = { n: +n, hex }; }
    return w;
}

/** The fixture world for one ev=cut line, or throws naming what the log lacks. */
function worldOf(game, cut) {
    if (cut.kind === 'gate') return gateWorld(game, cut);
    if (cut.kind !== 'spot') throw new Error(`no world builder for kind ${cut.kind}`);
    const key = `${cut.pid}@${cut.t}`;
    const cc = game.creeps.get(key);
    if (!cc) throw new Error(`no ev=cut_creeps for pid ${cut.pid} at ${cut.t}`);
    const bot = game.bots.get(cut.pid);
    if (!bot) throw new Error(`no ev=bot for pid ${cut.pid}`);
    const team = Number(bot.team);
    const [bx, by, hp, mhp, range, hull, speed, esc] = nums(cut.b);
    const [fx, fy, fbx, fby] = nums(cut.fr);
    const w = {
        t: Number(cut.t), team, pid: Number(cut.pid), role: cut.role, lane: Number(cut.lane), ours: oursOf(bot),
        bot: { x: bx, y: by, hp, mhp, range, hull, speed, esc },
        front: { x: fx, y: fy, bx: fbx, by: fby },
        ce: creepList(cc.ce), ca: creepList(cc.ca),
        he: heroRecords(cut.he), hu: unseenRecords(cut.hu), ha: allyRecords(cut.ha),
        towers: towersOf(game, team, cut.ta, cut.tt),
    };
    if (cut.fed !== undefined) w.fed = Number(cut.fed);
    if (cut.hold !== undefined) { const [x, y] = nums(cut.hold); w.hold = { x, y }; }
    if (cut.vis !== undefined) { const [x0, y0, nx, ny, step, hex] = cut.vis.split(','); w.vis = { x0: +x0, y0: +y0, nx: +nx, ny: +ny, step: +step, hex }; }
    return w;
}

function toLua(v) {
    if (v === null || v === undefined) return 'nil';
    if (typeof v === 'number') return Number.isFinite(v) ? String(v) : 'nil';
    if (typeof v === 'boolean') return String(v);
    if (typeof v === 'string') return JSON.stringify(v);
    if (Array.isArray(v)) return `{${v.map(toLua).join(', ')}}`;
    return `{${Object.entries(v).map(([k, x]) => `[${JSON.stringify(k)}] = ${toLua(x)}`).join(', ')}}`;
}

/** Runs the decision's driver on `world` in a fresh fengari state: the driver's observation. */
function replay(decision, world, root) {
    const L = newState(root);
    let err = doString(L, `FIXTURE = ${toLua({ decision, world })}\nSKILL = nil\n`);
    if (err === null) err = doFile(L, path.join(__dirname, '../../tests/humaniser/fixture_run.lua'));
    if (err !== null) throw new Error(err);
    return JSON.parse(getGlobal(L, 'OBS_JSON'));
}

function clock(s) {
    const m = String(s).match(/^(-?\d+):(\d\d(?:\.\d+)?)$/);
    return m ? Number(m[1]) * 60 + Math.sign(Number(m[1]) || 1) * Number(m[2]) : Number(s);
}
const mmss = t => `${Math.floor(t / 60)}:${String(Math.floor(t % 60)).padStart(2, '0')}`;

/** One gate cut against the ev=threat the gate logged for it: { same, got, want } or { error }. */
function checkGate(game, cut, root) {
    const th = game.threats.get(`${cut.pid}@${cut.t}@${cut.who}`);
    if (!th) return { error: 'no ev=threat beside it' };
    let obs;
    try { obs = replay('threat_gate', worldOf(game, cut), root); } catch (e) { return { error: String(e.message).split('\n')[0] }; }
    const a = obs.actions[0];
    const got = a.verb === 'hold' ? a.target : 'go';
    return { same: got === th.dec, got, want: th.dec, reach: obs.fact.reach, missing: obs.fact.missing, wantReach: Number(th.reach), wantMiss: Number(th.miss) };
}

/** One cut against what the game logged beside it: spot { same, why, rp, d }, gate { same, got, want }, or { error }. */
function checkOne(game, cut, root) {
    if (cut.kind === 'gate') return checkGate(game, cut, root);
    const lp = game.lanePos.get(`${cut.pid}@${cut.t}`);
    if (!lp) return { error: 'no ev=lane_pos beside it' };
    let obs;
    try { obs = replay('lane_spot', worldOf(game, cut), root); } catch (e) { return { error: String(e.message).split('\n')[0] }; }
    const verb = v => (obs.actions.find(a => a.verb === v) || {}).target;
    const d = Math.hypot(obs.fact.x - Number(lp.sx), obs.fact.y - Number(lp.sy));
    const why = verb('stand') === lp.why, rp = (verb('read') ?? 'none') === (lp.rp ?? 'off');
    return { same: d <= SAME_SPOT && why && rp, d, why, rp, got: `${verb('stand')}/${verb('read')}`, want: `${lp.why}/${lp.rp}` };
}

// Threat.Gate's consumers (ev=threat `who`); core_pull and lane_ctl call Threat.Log directly and have no gate cut.
const GATE_WHO = new Set(['core_camp', 'pull_farm', 'pull_job', 'sup_job', 'farm_trip']);

/** Gate decisions logged with no gate cut beside them: a cut that throws is swallowed by the game's pcall and shows only so. */
function uncutGates(game, who) {
    const cutKeys = new Set(game.cuts.filter(c => c.kind === 'gate').map(c => `${c.pid}@${c.t}@${c.who}`));
    return [...game.threats].filter(([k, th]) => GATE_WHO.has(th.who) && (who === undefined || th.who === who) && !cutKeys.has(k)).length;
}

function main(argv) {
    const opt = (k, d) => { const i = argv.indexOf(k); return i >= 0 ? argv[i + 1] : d; };
    const log = argv.find((a, i) => !a.startsWith('--') && (i === 0 || !argv[i - 1].startsWith('--')));
    if (!log || argv.includes('--help')) {
        console.log(fs.readFileSync(__filename, 'utf8').split('\n').slice(2, 9).map(l => l.replace(/^\/\/ ?/, '')).join('\n'));
        process.exit(log ? 0 : 1);
    }
    const games = readGames(fs.readFileSync(log, 'utf8'));
    const gi = opt('--game') !== undefined ? Number(opt('--game')) - 1 : games.length - 1;
    const game = games[gi];
    const kind = opt('--kind', 'spot');
    const cuts = game ? game.cuts.filter(c => c.kind === kind) : [];
    if (!cuts.length) { console.error(`no ev=cut kind=${kind} lines in game ${gi + 1} of ${log}`); process.exit(1); }
    const root = opt('--root');
    const who = opt('--who');
    const pool = who === undefined ? cuts : cuts.filter(c => c.who === who);
    if (argv.includes('--check')) {
        const n = Number(opt('--sample', 150));
        const step = Math.max(1, Math.floor(pool.length / n));
        const rows = [];
        for (let i = 0; i < pool.length && rows.length < n; i += step) rows.push({ cut: pool[i], r: checkOne(game, pool[i], root) });
        const ok = rows.filter(x => x.r.same).length, errs = rows.filter(x => x.r.error);
        const summary = { cuts: pool.length, checked: rows.length, same: ok, errors: errs.length };
        if (kind === 'gate') {
            summary.uncut = uncutGates(game, who);
            summary.byDecision = {};
            for (const { r } of rows) if (!r.error) { const d = summary.byDecision[r.want] ||= { checked: 0, same: 0 }; d.checked++; if (r.same) d.same++; }
        } else Object.assign(summary, { why: rows.filter(x => x.r.why).length, read: rows.filter(x => x.r.rp).length, near: rows.filter(x => x.r.d <= SAME_SPOT).length });
        if (argv.includes('--json')) { console.log(JSON.stringify({ summary, rows }, null, 1)); return; }
        if (kind === 'gate') {
            const by = Object.entries(summary.byDecision).map(([d, v]) => `${d} ${v.same}/${v.checked}`).join(', ');
            console.log(`gate cuts ${summary.cuts}, checked ${summary.checked}: same decision ${ok} (${by}); errors ${summary.errors}; gate decisions without a cut ${summary.uncut}`);
        } else console.log(`cuts ${summary.cuts}, checked ${summary.checked}: same spot, limit and read ${ok}; spot within ${SAME_SPOT} ${summary.near}, limit ${summary.why}, read ${summary.read}; errors ${summary.errors}`);
        for (const { cut, r } of rows.filter(x => !x.r.same).slice(0, 15)) {
            const what = r.error || (kind === 'gate' ? `${cut.who}: replay ${r.got}, game ${r.want} (reach ${r.reach} vs ${r.wantReach}, missing ${r.missing} vs ${r.wantMiss})`
                : `off by ${r.d.toFixed(0)}, replay ${r.got}, game ${r.want}`);
            console.log(`  pid ${cut.pid} t=${cut.t} (${mmss(Number(cut.t))}): ${what}`);
        }
        return;
    }
    const pid = opt('--pid'), t = clock(opt('--t'));
    const mine = pool.filter(c => c.pid === pid && Number(c.t) <= t + 1e-6);
    if (!mine.length) { console.error(`no ev=cut kind=${kind} for pid ${pid} at or before ${opt('--t')}`); process.exit(1); }
    const cut = mine[mine.length - 1];
    const world = worldOf(game, cut);
    const gate = kind === 'gate';
    const th = gate ? game.threats.get(`${cut.pid}@${cut.t}@${cut.who}`) || {} : {};
    const lp = gate ? {} : game.lanePos.get(`${cut.pid}@${cut.t}`) || {};
    const id = opt('--id', gate ? `gate.${cut.who}.cut-${pid}-${Math.floor(Number(cut.t))}.001` : `lane.spot.cut-${pid}-${Math.floor(Number(cut.t))}.001`);
    const game_said = gate ? `${th.dec} (reach ${th.reach}, miss ${th.miss}, tower ${th.tower})` : `${lp.why}/${lp.rp} at (${lp.sx}, ${lp.sy})`;
    const lines = [
        `id: ${id}`, 'source: log', `ref: {log: ${path.basename(log)}, t: ${cut.t}}`, 'status: quarantined', `decision: ${gate ? 'threat_gate' : 'lane_spot'}`,
        `# Cut by tools/hlog/cut.js. The game chose ${game_said}; write the right action, not this.`,
        'world:',
        ...Object.entries(world).map(([k, v]) => `  ${k}: ${JSON.stringify(v)}`),
        'expect:', '  must: []', 'notes: >', '  TODO: the situation, and why the expectation is the right action.',
    ];
    console.log(lines.join('\n'));
}

if (require.main === module) main(process.argv.slice(2));
module.exports = { readGames, worldOf, replay, checkOne, uncutGates };
