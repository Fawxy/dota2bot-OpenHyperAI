#!/usr/bin/env node
'use strict';
// Fixture cuts (rework step 8): turns an ev=cut line (bot cut.ts) into a decision fixture's world, and checks that the
// cut replays what the game decided.
//   node cut.js <log> --pid P --t 5:12 [--game N] [--id ID]   print a fixture (YAML) for the cut at or just before t
//   node cut.js <log> --check [--game N] [--sample 150] [--json]   replay a sample of the game's cuts through the
//       decision's driver and compare with what the game logged beside them (kind spot: ev=lane_pos sx, sy, why, rp)
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

/** The log's games, each { cuts, creeps, lanePos, bots, towers } keyed for joining by pid and t. */
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
            g = { cuts: [], creeps: new Map(), lanePos: new Map(), bots: new Map(g?.bots || []), towers: new Map(g?.towers || []) };
            games.push(g);
        }
        last = t;
        const key = `${f.pid}@${f.t}`;
        if (f.ev === 'cut') g.cuts.push(f);
        else if (f.ev === 'cut_creeps') g.creeps.set(key, f);
        else if (f.ev === 'lane_pos') g.lanePos.set(key, f);
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

/** The fixture world for one ev=cut line (kind spot), or throws naming what the log lacks. */
function worldOf(game, cut) {
    if (cut.kind !== 'spot') throw new Error(`no world builder for kind ${cut.kind}`);
    const key = `${cut.pid}@${cut.t}`;
    const cc = game.creeps.get(key);
    if (!cc) throw new Error(`no ev=cut_creeps for pid ${cut.pid} at ${cut.t}`);
    const bot = game.bots.get(cut.pid);
    if (!bot) throw new Error(`no ev=bot for pid ${cut.pid}`);
    const team = Number(bot.team);
    const enemy = team === 2 ? 3 : 2;
    const [bx, by, hp, mhp, range, hull, speed, esc] = nums(cut.b);
    const [fx, fy, fbx, fby] = nums(cut.fr);
    const [ownMask, enemyMask] = String(cut.ta).split(',').map(h => parseInt(h, 16));
    const targets = new Map(records(cut.tt).map(([t, i, tgt]) => [`${t}:${i}`, tgt]));
    const towers = [];
    for (const [t, mask] of [[team, ownMask], [enemy, enemyMask]]) {
        const line = game.towers.get(String(t));
        if (!line) throw new Error(`no ev=cut_towers for team ${t}`);
        for (const [i, x, y, r, h] of records(line.tw).map(r => r.map(Number))) {
            if (!(mask & (1 << i))) continue;
            towers.push({ team: t, i, x, y, range: r, hull: h, tgt: targets.get(`${t}:${i}`) || '-' });
        }
    }
    const w = {
        t: Number(cut.t), team, pid: Number(cut.pid), role: cut.role, lane: Number(cut.lane), ours: oursOf(bot),
        bot: { x: bx, y: by, hp, mhp, range, hull, speed, esc },
        front: { x: fx, y: fy, bx: fbx, by: fby },
        ce: creepList(cc.ce), ca: creepList(cc.ca),
        he: records(cut.he).map(([pid, x, y, hp2, r, h, sp, atk, eng, e3, e6, ill]) =>
            ({ pid: +pid, x: +x, y: +y, hp: +hp2, range: +r, hull: +h, speed: +sp, atk: +atk, eng: +eng, e3: +e3, e6: +e6, ill: +ill })),
        hu: records(cut.hu).map(([pid, x, y, tss, sp]) => ({ pid: +pid, x: +x, y: +y, tss: +tss, sp: +sp })),
        ha: records(cut.ha).map(([pid, x, y, r, h, sp, ret]) => ({ pid: +pid, x: +x, y: +y, range: +r, hull: +h, speed: +sp, ret: +ret })),
        towers,
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

/** One cut against its ev=lane_pos: { same, why, rp, d } or { error }. */
function checkOne(game, cut, root) {
    const lp = game.lanePos.get(`${cut.pid}@${cut.t}`);
    if (!lp) return { error: 'no ev=lane_pos beside it' };
    let obs;
    try { obs = replay('lane_spot', worldOf(game, cut), root); } catch (e) { return { error: String(e.message).split('\n')[0] }; }
    const verb = v => (obs.actions.find(a => a.verb === v) || {}).target;
    const d = Math.hypot(obs.fact.x - Number(lp.sx), obs.fact.y - Number(lp.sy));
    const why = verb('stand') === lp.why, rp = (verb('read') ?? 'none') === (lp.rp ?? 'off');
    return { same: d <= SAME_SPOT && why && rp, d, why, rp, got: `${verb('stand')}/${verb('read')}`, want: `${lp.why}/${lp.rp}` };
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
    if (!game || !game.cuts.length) { console.error(`no ev=cut lines in game ${gi + 1} of ${log}`); process.exit(1); }
    const root = opt('--root');
    if (argv.includes('--check')) {
        const n = Number(opt('--sample', 150));
        const step = Math.max(1, Math.floor(game.cuts.length / n));
        const rows = [];
        for (let i = 0; i < game.cuts.length && rows.length < n; i += step) rows.push({ cut: game.cuts[i], r: checkOne(game, game.cuts[i], root) });
        const ok = rows.filter(x => x.r.same).length, errs = rows.filter(x => x.r.error);
        const summary = { cuts: game.cuts.length, checked: rows.length, same: ok, errors: errs.length,
            why: rows.filter(x => x.r.why).length, read: rows.filter(x => x.r.rp).length, near: rows.filter(x => x.r.d <= SAME_SPOT).length };
        if (argv.includes('--json')) { console.log(JSON.stringify({ summary, rows }, null, 1)); return; }
        console.log(`cuts ${summary.cuts}, checked ${summary.checked}: same spot, limit and read ${ok}; spot within ${SAME_SPOT} ${summary.near}, limit ${summary.why}, read ${summary.read}; errors ${summary.errors}`);
        for (const { cut, r } of rows.filter(x => !x.r.same).slice(0, 15)) {
            console.log(`  pid ${cut.pid} t=${cut.t} (${mmss(Number(cut.t))}): ${r.error || `off by ${r.d.toFixed(0)}, replay ${r.got}, game ${r.want}`}`);
        }
        return;
    }
    const pid = opt('--pid'), t = clock(opt('--t'));
    const mine = game.cuts.filter(c => c.pid === pid && Number(c.t) <= t + 1e-6);
    if (!mine.length) { console.error(`no ev=cut for pid ${pid} at or before ${opt('--t')}`); process.exit(1); }
    const cut = mine[mine.length - 1];
    const world = worldOf(game, cut);
    const id = opt('--id', `lane.spot.cut-${pid}-${Math.floor(Number(cut.t))}.001`);
    const lp = game.lanePos.get(`${cut.pid}@${cut.t}`) || {};
    const lines = [
        `id: ${id}`, 'source: log', `ref: {log: ${path.basename(log)}, t: ${cut.t}}`, 'status: quarantined', 'decision: lane_spot',
        `# Cut by tools/hlog/cut.js. The game chose ${lp.why}/${lp.rp} at (${lp.sx}, ${lp.sy}); write the right action, not this.`,
        'world:',
        ...Object.entries(world).map(([k, v]) => `  ${k}: ${JSON.stringify(v)}`),
        'expect:', '  must: []', 'notes: >', '  TODO: the situation, and why the expectation is the right action.',
    ];
    console.log(lines.join('\n'));
}

if (require.main === module) main(process.argv.slice(2));
module.exports = { readGames, worldOf, replay, checkOne };
