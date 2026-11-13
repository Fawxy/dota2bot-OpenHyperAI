#!/usr/bin/env node
'use strict';
// Fixture cuts (rework step 8): turns an ev=cut line (bot cut.ts) into a decision fixture's world, and checks that the
// cut replays what the game decided.
//   node cut.js <log> --pid P --t 5:12 [--kind spot|leave] [--game N] [--id ID]   print a fixture (YAML) for the cut at or just before t
//   node cut.js <log> --check [--kind spot|leave] [--game N] [--sample 150] [--json]   replay a sample of the game's cuts
//       through the decision's driver and compare with what the game logged (kind spot, the default: the ev=lane_pos beside
//       it, sx, sy, why, rp; kind leave: the cut's own dec)
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
        // A kind's creeps line is keyed apart: two cuts of one hero in one frame must not share creeps (the spot's carry no kind).
        else if (f.ev === 'cut_creeps') g.creeps.set(f.kind ? `${key}@${f.kind}` : key, f);
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

/** The records every kind's world shares: the bot, heroes, creeps, towers and vision of one cut. */
function commonWorld(game, cut) {
    const key = `${cut.pid}@${cut.t}`;
    const cc = game.creeps.get(cut.kind === 'spot' ? key : `${key}@${cut.kind}`);
    if (!cc) throw new Error(`no ev=cut_creeps for pid ${cut.pid} at ${cut.t}`);
    const bot = game.bots.get(cut.pid);
    if (!bot) throw new Error(`no ev=bot for pid ${cut.pid}`);
    const team = Number(bot.team);
    const enemy = team === 2 ? 3 : 2;
    const [bx, by, hp, mhp, range, hull, speed, esc] = nums(cut.b);
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
        t: Number(cut.t), team, pid: Number(cut.pid), ours: oursOf(bot),
        bot: { x: bx, y: by, hp, mhp, range, hull, speed, esc },
        ce: creepList(cc.ce), ca: creepList(cc.ca),
        he: records(cut.he).map(([pid, x, y, hp2, r, h, sp, atk, eng, e3, e6, ill]) =>
            ({ pid: +pid, x: +x, y: +y, hp: +hp2, range: +r, hull: +h, speed: +sp, atk: +atk, eng: +eng, e3: +e3, e6: +e6, ill: +ill })),
        hu: records(cut.hu).map(([pid, x, y, tss, sp]) => ({ pid: +pid, x: +x, y: +y, tss: +tss, sp: +sp })),
        ha: records(cut.ha).map(([pid, x, y, r, h, sp, ret]) => ({ pid: +pid, x: +x, y: +y, range: +r, hull: +h, speed: +sp, ret: +ret })),
        towers,
    };
    if (cut.vis !== undefined) { const [x0, y0, nx, ny, step, hex] = cut.vis.split(','); w.vis = { x0: +x0, y0: +y0, nx: +nx, ny: +ny, step: +step, hex }; }
    return w;
}

/**
 * Each decision's cut kind: its fixture driver, the world its ev=cut line makes, and how a replay is compared with the game's
 * answer. `check` gives { same, got, want, ... } or throws; `also` is the numbers checkOne adds to its row.
 */
const DECISIONS = {
    spot: {
        driver: 'lane_spot',
        world(game, cut) {
            const w = commonWorld(game, cut);
            const [fx, fy, fbx, fby] = nums(cut.fr);
            Object.assign(w, { role: cut.role, lane: Number(cut.lane), front: { x: fx, y: fy, bx: fbx, by: fby } });
            if (cut.fed !== undefined) w.fed = Number(cut.fed);
            if (cut.hold !== undefined) { const [x, y] = nums(cut.hold); w.hold = { x, y }; }
            return w;
        },
        check(game, cut, obs) {
            const lp = game.lanePos.get(`${cut.pid}@${cut.t}`);
            if (!lp) return { error: 'no ev=lane_pos beside it' };
            const verb = v => (obs.actions.find(a => a.verb === v) || {}).target;
            const d = Math.hypot(obs.fact.x - Number(lp.sx), obs.fact.y - Number(lp.sy));
            const why = verb('stand') === lp.why, rp = (verb('read') ?? 'none') === (lp.rp ?? 'off');
            return { same: d <= SAME_SPOT && why && rp, d, why, rp, got: `${verb('stand')}/${verb('read')}`, want: `${lp.why}/${lp.rp}` };
        },
        note: (cut, lp) => `The game chose ${lp.why}/${lp.rp} at (${lp.sx}, ${lp.sy}); write the right action, not this.`,
    },
    leave: {
        driver: 'retreat_leave',
        world(game, cut) {
            const w = commonWorld(game, cut);
            Object.assign(w, { budget: Number(cut.bud), over: Number(cut.ov), hold: Number(cut.th), dt: Number(cut.dt) });
            return w;
        },
        check(game, cut, obs) {
            const a = obs.actions[0] || {};
            const got = `${a.verb}(${a.target})`;
            const want = ['lethal', 'tower', 'heal', 'threat'].includes(cut.dec) ? `leave(${cut.dec})` : `stay(${cut.dec})`;
            return { same: got === want, got, want };
        },
        note: cut => `The game chose ${cut.dec} (threat ${cut.thr}, ${cut.purp} budget ${cut.bud}, over ${cut.ov} s); write the right action, not this.`,
    },
};

/** The fixture world for one ev=cut line, or throws naming what the log lacks. */
function worldOf(game, cut) {
    const d = DECISIONS[cut.kind];
    if (!d) throw new Error(`no world builder for kind ${cut.kind}`);
    return d.world(game, cut);
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

/** Per answer of the game: `same/checked` of the replayed rows. */
function tally(rows) {
    const out = {};
    for (const { cut, r } of rows) {
        const [same, n] = (out[cut.dec] || '0/0').split('/').map(Number);
        out[cut.dec] = `${same + (r.same ? 1 : 0)}/${n + 1}`;
    }
    return out;
}

function clock(s) {
    const m = String(s).match(/^(-?\d+):(\d\d(?:\.\d+)?)$/);
    return m ? Number(m[1]) * 60 + Math.sign(Number(m[1]) || 1) * Number(m[2]) : Number(s);
}
const mmss = t => `${Math.floor(t / 60)}:${String(Math.floor(t % 60)).padStart(2, '0')}`;

/** One cut against what the game decided: { same, got, want, ... } or { error }. */
function checkOne(game, cut, root) {
    const d = DECISIONS[cut.kind];
    if (!d) return { error: `no check for kind ${cut.kind}` };
    let obs;
    try { obs = replay(d.driver, worldOf(game, cut), root); } catch (e) { return { error: String(e.message).split('\n')[0] }; }
    return d.check(game, cut, obs);
}

function main(argv) {
    const opt = (k, d) => { const i = argv.indexOf(k); return i >= 0 ? argv[i + 1] : d; };
    const log = argv.find((a, i) => !a.startsWith('--') && (i === 0 || !argv[i - 1].startsWith('--')));
    if (!log || argv.includes('--help')) {
        console.log(fs.readFileSync(__filename, 'utf8').split('\n').slice(2, 12).map(l => l.replace(/^\/\/ ?/, '')).join('\n'));
        process.exit(log ? 0 : 1);
    }
    const games = readGames(fs.readFileSync(log, 'utf8'));
    const kind = opt('--kind', 'spot');
    const gi = opt('--game') !== undefined ? Number(opt('--game')) - 1 : games.length - 1;
    const game = games[gi];
    const cuts = game ? game.cuts.filter(c => c.kind === kind) : [];
    if (!cuts.length) { console.error(`no ev=cut kind=${kind} lines in game ${gi + 1} of ${log}`); process.exit(1); }
    const root = opt('--root');
    if (argv.includes('--check')) {
        const n = Number(opt('--sample', 150));
        const step = Math.max(1, Math.floor(cuts.length / n));
        const rows = [];
        for (let i = 0; i < cuts.length && rows.length < n; i += step) rows.push({ cut: cuts[i], r: checkOne(game, cuts[i], root) });
        const ok = rows.filter(x => x.r.same).length, errs = rows.filter(x => x.r.error);
        const summary = { cuts: cuts.length, checked: rows.length, same: ok, errors: errs.length };
        if (kind === 'spot') Object.assign(summary, { why: rows.filter(x => x.r.why).length, read: rows.filter(x => x.r.rp).length, near: rows.filter(x => x.r.d <= SAME_SPOT).length });
        else summary.byDecision = tally(rows);
        if (argv.includes('--json')) { console.log(JSON.stringify({ summary, rows }, null, 1)); return; }
        if (kind === 'spot') console.log(`cuts ${summary.cuts}, checked ${summary.checked}: same spot, limit and read ${ok}; spot within ${SAME_SPOT} ${summary.near}, limit ${summary.why}, read ${summary.read}; errors ${summary.errors}`);
        else console.log(`kind ${kind}: cuts ${summary.cuts}, checked ${summary.checked}: same as the game decided ${ok}; errors ${summary.errors}\n  by the game's answer (same/checked): ${Object.entries(summary.byDecision).map(([k, v]) => `${k} ${v}`).join(', ')}`);
        for (const { cut, r } of rows.filter(x => !x.r.same).slice(0, 15)) {
            console.log(`  pid ${cut.pid} t=${cut.t} (${mmss(Number(cut.t))}): ${r.error || (r.d !== undefined ? `off by ${r.d.toFixed(0)}, replay ${r.got}, game ${r.want}` : `replay ${r.got}, game ${r.want}`)}`);
        }
        return;
    }
    const pid = opt('--pid'), t = clock(opt('--t'));
    const mine = cuts.filter(c => c.pid === pid && Number(c.t) <= t + 1e-6);
    if (!mine.length) { console.error(`no ev=cut for pid ${pid} at or before ${opt('--t')}`); process.exit(1); }
    const cut = mine[mine.length - 1];
    const world = worldOf(game, cut);
    const d = DECISIONS[kind];
    const id = opt('--id', `${d.driver.replace('_', '.')}.cut-${pid}-${Math.floor(Number(cut.t))}.001`);
    const lp = game.lanePos.get(`${cut.pid}@${cut.t}`) || {};
    const lines = [
        `id: ${id}`, 'source: log', `ref: {log: ${path.basename(log)}, t: ${cut.t}}`, 'status: quarantined', `decision: ${d.driver}`,
        `# Cut by tools/hlog/cut.js. ${d.note(cut, lp)}`,
        'world:',
        ...Object.entries(world).map(([k, v]) => `  ${k}: ${JSON.stringify(v)}`),
        'expect:', '  must: []', 'notes: >', '  TODO: the situation, and why the expectation is the right action.',
    ];
    console.log(lines.join('\n'));
}

if (require.main === module) main(process.argv.slice(2));
module.exports = { readGames, worldOf, replay, checkOne };
