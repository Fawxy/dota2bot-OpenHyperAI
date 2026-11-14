#!/usr/bin/env node
'use strict';
// Fixture cuts (rework step 8): turns an ev=cut line (bot cut.ts) into a decision fixture's world, and checks that the
// cut replays what the game decided.
//   node cut.js <log> --pid P --t 5:12 [--kind spot|gate|leave|join] [--who CONSUMER] [--game N] [--id ID]   print a fixture
//       (YAML) for the cut at or just before t (--who: a gate cut's consumer, e.g. core_camp)
//   node cut.js <log> --check [--kind K] [--who W] [--game N] [--sample 20 | --all] [--json]   replay up to 20 cuts of each
//       answer the game gave (spot: the ev=lane_pos why, sx, sy, rp; gate: its ev=threat dec; leave: the cut's dec); --all
//       checks every cut and judges the bar (95% of each answer)
//       --jobs N replays on N worker threads (default min(6, cores); 1 replays in this process; fewer than 40 cuts always do)
//   node cut.js <log> --list [--kind K] [--who W] [--answer A] [--pid P] [--engaged 0|1]   one line per cut: time, pid, answer,
//       HP, heroes, whether an enemy hero in it is hitting the bot (the cut's engaged flag) and the burst (their damage, over 6 s
//       for a hitting hero else 3 s, over the bot's HP: the threat read's); --engaged keeps the cuts with (1) or without (0) one
// --game: which game of the log (1-based; default the last, so a remote job's stub game 1 is skipped).
const fs = require('fs'), path = require('path'), os = require('os');
const { Worker, isMainThread, parentPort, workerData } = require('worker_threads');
const { newState, doString, getGlobal } = require('../../tests/humaniser/harness');

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
        // A kind's creeps line is keyed apart: two cuts of one hero in one frame must not share creeps (the spot's carry no kind).
        else if (f.ev === 'cut_creeps') g.creeps.set(f.kind ? `${key}@${f.kind}` : key, f);
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
/** The threat read's burst: each hero's damage (6 s window when it is engaged, else 3 s) over the bot's HP. */
const burstOf = (he, hp) => he.reduce((sum, h) => sum + (h.eng ? h.e6 : h.e3), 0) / hp;
const unseenRecords = s => records(s).map(([pid, x, y, tss, sp]) => ({ pid: +pid, x: +x, y: +y, tss: +tss, sp: +sp }));
const allyRecords = s => records(s).map(([pid, x, y, r, h, sp, ret]) => ({ pid: +pid, x: +x, y: +y, range: +r, hull: +h, speed: +sp, ret: +ret }));

function botOf(game, cut) {
    const bot = game.bots.get(cut.pid);
    if (!bot) throw new Error(`no ev=bot for pid ${cut.pid}`);
    return bot;
}

/** The records the spot's and the leave's worlds share: the bot, heroes, creeps, towers and vision of one cut. */
function commonWorld(game, cut) {
    const key = `${cut.pid}@${cut.t}`;
    const cc = game.creeps.get(cut.kind === 'spot' ? key : `${key}@${cut.kind}`);
    if (!cc) throw new Error(`no ev=cut_creeps for pid ${cut.pid} at ${cut.t}`);
    const bot = botOf(game, cut);
    const team = Number(bot.team);
    const [bx, by, hp, mhp, range, hull, speed, esc] = nums(cut.b);
    const w = {
        t: Number(cut.t), team, pid: Number(cut.pid), ours: oursOf(bot),
        bot: { x: bx, y: by, hp, mhp, range, hull, speed, esc },
        ce: creepList(cc.ce), ca: creepList(cc.ca),
        he: heroRecords(cut.he), hu: unseenRecords(cut.hu), ha: allyRecords(cut.ha),
        towers: towersOf(game, team, cut.ta, cut.tt),
    };
    if (cut.vis !== undefined) { const [x0, y0, nx, ny, step, hex] = cut.vis.split(','); w.vis = { x0: +x0, y0: +y0, nx: +nx, ny: +ny, step: +step, hex }; }
    return w;
}

// Threat.Gate's consumers (ev=threat `who`); core_pull and lane_ctl call Threat.Log directly and have no gate cut.
const GATE_WHO = new Set(['core_camp', 'pull_farm', 'pull_job', 'sup_job', 'farm_trip']);

/** Gate decisions logged with no gate cut beside them: a cut that throws is swallowed by the game's pcall and shows only so. */
function uncutGates(game, who) {
    const cutKeys = new Set(game.cuts.filter(c => c.kind === 'gate').map(c => `${c.pid}@${c.t}@${c.who}`));
    return [...game.threats].filter(([k, th]) => GATE_WHO.has(th.who) && (who === undefined || th.who === who) && !cutKeys.has(k)).length;
}

/**
 * Each decision's cut kind: its fixture driver, the world its ev=cut line makes, and how a replay is compared with the game's
 * answer. `answer` is what the game decided (sampling and the tally group by it), `check` gives { same, got, want, detail? } or
 * { error }, `brief` is the rest of a --list line.
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
            return { same: d <= SAME_SPOT && why && rp, d, why, rp, got: `${verb('stand')}/${verb('read')}`, want: `${lp.why}/${lp.rp}`, detail: `off by ${d.toFixed(0)}` };
        },
        answer: (game, cut) => (game.lanePos.get(`${cut.pid}@${cut.t}`) || {}).why ?? '?',
        brief(game, cut) {
            const lp = game.lanePos.get(`${cut.pid}@${cut.t}`) || {};
            return `${cut.role}, read ${lp.rp ?? 'off'}`;
        },
        id: (cut) => `lane.spot.cut-${cut.pid}-${Math.floor(Number(cut.t))}.001`,
        note(game, cut) {
            const lp = game.lanePos.get(`${cut.pid}@${cut.t}`) || {};
            return `The game chose ${lp.why}/${lp.rp} at (${lp.sx}, ${lp.sy})`;
        },
    },
    gate: {
        driver: 'threat_gate',
        world(game, cut) {
            const bot = botOf(game, cut);
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
        },
        check(game, cut, obs) {
            const th = game.threats.get(`${cut.pid}@${cut.t}@${cut.who}`);
            if (!th) return { error: 'no ev=threat beside it' };
            const a = obs.actions[0];
            const got = a.verb === 'hold' ? a.target : 'go';
            return { same: got === th.dec, got, want: th.dec, reach: obs.fact.reach, missing: obs.fact.missing,
                detail: `${cut.who}, reach ${obs.fact.reach} vs ${th.reach}, missing ${obs.fact.missing} vs ${th.miss}` };
        },
        answer: (game, cut) => (game.threats.get(`${cut.pid}@${cut.t}@${cut.who}`) || {}).dec ?? '?',
        brief(game, cut) {
            const th = game.threats.get(`${cut.pid}@${cut.t}@${cut.who}`) || {};
            return `${cut.who}, reach ${th.reach}, missing ${th.miss}`;
        },
        id: (cut) => `gate.${cut.who}.cut-${cut.pid}-${Math.floor(Number(cut.t))}.001`,
        note(game, cut) {
            const th = game.threats.get(`${cut.pid}@${cut.t}@${cut.who}`) || {};
            return `The game chose ${th.dec} (reach ${th.reach}, miss ${th.miss}, tower ${th.tower})`;
        },
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
        answer: (game, cut) => cut.dec,
        brief: (game, cut) => `threat ${cut.thr} (${cut.band}), ${cut.purp} budget ${cut.bud}`,
        id: (cut) => `retreat.leave.cut-${cut.pid}-${Math.floor(Number(cut.t))}.001`,
        note: (game, cut) => `The game chose ${cut.dec} (threat ${cut.thr}, ${cut.purp} budget ${cut.bud}, over ${cut.ov} s)`,
    },
    join: {
        driver: 'pair_join',
        world(game, cut) {
            const side = (s, ours) => (s ? s.split(';') : []).map(r => {
                const [pid, x, y, hp, mhp, ret] = nums(r);
                return ours ? { pid, x, y, hp, mhp, ret } : { pid, x, y, hp, mhp };
            });
            const dmg = (cut.dm ? cut.dm.split(';') : []).map(r => { const [from, to, d] = nums(r); return { from, to, d }; });
            return { t: Number(cut.t), pid: Number(cut.pid), ally: Number(cut.al), ours: side(cut.po, true), theirs: side(cut.pt, false), dmg };
        },
        check(game, cut, obs) {
            const a = obs.actions[0] || {};
            const got = a.verb === 'join' ? `join(${a.target})` : `out(${a.target})`;
            const want = cut.dec === 'join' ? `join(hero#${cut.tgt})` : `out(${cut.dec})`;
            return { same: got === want, got, want };
        },
        answer: (game, cut) => cut.dec,
        brief: (game, cut) => `ally ${cut.al}, ${cut.po.split(';').length}v${cut.pt.split(';').length}, ours ${cut.ko} theirs ${cut.kt}`,
        id: (cut) => `fights.join.cut-${cut.pid}-${Math.floor(Number(cut.t))}.001`,
        note: (game, cut) => `The game chose ${cut.dec} on ${cut.tgt} (ours ${cut.ko}, theirs ${cut.kt})`,
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

// Speed: a fresh fengari state per replay spent about 0.3 s of its time parsing the bot's Lua (about 1 MB; the harness's compile
// cache lives in the state). One state per root serves every replay: the globals and the loaded modules (package.loaded) are put
// back to what they were after the harness prelude before each one, and the compile cache stays, so a replay runs
// the cached chunks anew (fresh module tables) and parses nothing.
const RESET = `
if GLOBALS0 == nil then
    local chunks, plain = {}, dofile
    dofile = function(p) -- the fixture runner, driver and world files parse once as well
        if chunks[p] == nil then chunks[p] = assert(loadfile(p)) end
        return chunks[p]()
    end
    local found, search = {}, package.searchpath -- and each module's path is looked up (a file open per candidate) once
    package.searchpath = function(name, path, ...)
        local k = name .. " " .. path
        if found[k] == nil then found[k] = table.pack(search(name, path, ...)) end
        return table.unpack(found[k], 1, found[k].n)
    end
    GLOBALS0, LOADED0 = {}, {}
    for k, v in pairs(_G) do GLOBALS0[k] = v end
    for k, v in pairs(package.loaded) do LOADED0[k] = v end
end
for k in pairs(_G) do if GLOBALS0[k] == nil then _G[k] = nil end end
for k, v in pairs(GLOBALS0) do _G[k] = v end
for k in pairs(package.loaded) do if LOADED0[k] == nil then package.loaded[k] = nil end end
for k, v in pairs(LOADED0) do package.loaded[k] = v end
`;
const STATES = new Map();

/** Runs the decision's driver on `world` in a reset fengari state: the driver's observation. */
function replay(decision, world, root) {
    const key = root === undefined ? '' : String(root);
    if (!STATES.has(key)) STATES.set(key, newState(root));
    const L = STATES.get(key);
    const runner = JSON.stringify(path.resolve(__dirname, '../../tests/humaniser/fixture_run.lua').split(path.sep).join('/'));
    const err = doString(L, RESET + `FIXTURE = ${toLua({ decision, world })}
SKILL = nil
dofile(${runner})`);
    if (err !== null) { STATES.delete(key); throw new Error(err); }
    return JSON.parse(getGlobal(L, 'OBS_JSON'));
}

/** Per answer of the game: `same/checked` of the replayed rows. */
function tally(game, rows) {
    const out = {};
    for (const { cut, r } of rows) {
        const k = DECISIONS[cut.kind].answer(game, cut);
        const [same, n] = (out[k] || '0/0').split('/').map(Number);
        out[k] = `${same + (r.same ? 1 : 0)}/${n + 1}`;
    }
    return out;
}

/** Up to n cuts of each answer the game gave, evenly spread over the game: a rare answer is checked as well as a common one. */
function sampleByAnswer(game, pool, n) {
    const groups = new Map();
    for (const [i, cut] of pool.entries()) {
        const a = DECISIONS[cut.kind].answer(game, cut);
        if (!groups.has(a)) groups.set(a, []);
        groups.get(a).push(i);
    }
    const picked = [];
    for (const idx of groups.values()) {
        const k = Math.min(n, idx.length);
        for (let j = 0; j < k; j++) picked.push(idx[Math.floor(j * idx.length / k)]);
    }
    return picked.sort((a, b) => a - b).map(i => pool[i]);
}

/**
 * The replay bar (eval-run): 95% of each answer the game gave, judged over all the game's cuts (--all). On a sample it is a
 * quick look only: at a true rate near 95%, 20 cuts of an answer fall short about one time in five. The answers that miss it.
 */
function barMisses(byAnswer) {
    return Object.entries(byAnswer).filter(([, v]) => { const [same, n] = v.split('/').map(Number); return same < 0.95 * n; }).map(([k, v]) => `${k} ${v}`);
}

/** Distances and HP for a fixture's notes, so they copy numbers rather than estimate them. */
function factsOf(w) {
    const d = (u, p) => Math.round(Math.hypot(u.x - p.x, u.y - p.y));
    const b = w.bot;
    const at = w.place ? `, ${d(b, w.place)} from the place` : '';
    const out = [`# bot pid ${w.pid}: HP ${Math.round(100 * b.hp / b.mhp)}% (${b.hp} of ${b.mhp})${at}`];
    for (const [label, list] of [['enemy', w.he], ['unseen', w.hu], ['ally', w.ha]]) {
        for (const u of list || []) {
            let line = `# ${label} pid ${u.pid}: ${d(u, b)} from the bot${w.place ? `, ${d(u, w.place)} from the place` : ''}`;
            if (label === 'enemy') line += `, HP ${u.hp}, damage ${u.e3} / ${u.e6} (short / long window)${u.atk ? ', attacking the bot' : ''}${u.eng ? ', hit it recently' : ''}`;
            if (label === 'unseen') line += ` (where last seen), unseen ${u.tss} s`;
            out.push(line);
        }
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

async function main(argv) {
    const opt = (k, d) => { const i = argv.indexOf(k); return i >= 0 ? argv[i + 1] : d; };
    const log = argv.find((a, i) => !a.startsWith('--') && (i === 0 || !argv[i - 1].startsWith('--')));
    if (!log || argv.includes('--help')) {
        console.log(fs.readFileSync(__filename, 'utf8').split('\n').slice(2, 14).map(l => l.replace(/^\/\/ ?/, '')).join('\n'));
        process.exit(log ? 0 : 1);
    }
    const games = readGames(fs.readFileSync(log, 'utf8'));
    const kind = opt('--kind', 'spot');
    const gi = opt('--game') !== undefined ? Number(opt('--game')) - 1 : games.length - 1;
    const game = games[gi];
    const cuts = game ? game.cuts.filter(c => c.kind === kind) : [];
    if (!cuts.length) { console.error(`no ev=cut kind=${kind} lines in game ${gi + 1} of ${log}`); process.exit(1); }
    const root = opt('--root');
    const who = opt('--who');
    const pool = who === undefined ? cuts : cuts.filter(c => c.who === who);
    const d = DECISIONS[kind];
    if (argv.includes('--list')) {
        const answer = opt('--answer'), pid = opt('--pid'), engaged = opt('--engaged');
        for (const cut of pool) {
            const a = d.answer(game, cut);
            if ((answer !== undefined && a !== answer) || (pid !== undefined && cut.pid !== pid)) continue;
            const [, , hp, mhp] = nums(cut.b);
            const he = heroRecords(cut.he);
            const hitting = he.some(h => h.eng);
            if (engaged !== undefined && hitting !== (engaged === '1')) continue;
            console.log(`${mmss(Number(cut.t))} t=${cut.t} pid ${cut.pid} ${a}: HP ${Math.round(100 * hp / mhp)}%, enemies in the cut ${he.length}, allies ${records(cut.ha).length}, hitting ${hitting ? 1 : 0}, burst ${burstOf(he, hp).toFixed(2)}; ${d.brief(game, cut)}`);
        }
        return;
    }
    if (argv.includes('--check')) {
        const n = Number(opt('--sample', 20));
        const picked = argv.includes('--all') ? pool : sampleByAnswer(game, pool, n);
        const jobs = Number(opt('--jobs', Math.min(6, os.availableParallelism())));
        const results = await checkMany(log, gi, game, picked, root, picked.length < MIN_PARALLEL ? 1 : jobs);
        const rows = picked.map((cut, i) => ({ cut, r: results[i] }));
        const ok = rows.filter(x => x.r.same).length, errs = rows.filter(x => x.r.error);
        const summary = { cuts: pool.length, checked: rows.length, same: ok, errors: errs.length, byDecision: tally(game, rows) };
        summary.barMisses = barMisses(summary.byDecision);
        if (kind === 'spot') Object.assign(summary, { why: rows.filter(x => x.r.why).length, read: rows.filter(x => x.r.rp).length, near: rows.filter(x => x.r.d <= SAME_SPOT).length });
        if (kind === 'gate') summary.uncut = uncutGates(game, who);
        if (argv.includes('--json')) { console.log(JSON.stringify({ summary, rows }, null, 1)); return; }
        if (kind === 'spot') console.log(`cuts ${summary.cuts}, checked ${summary.checked}: same spot, limit and read ${ok}; spot within ${SAME_SPOT} ${summary.near}, limit ${summary.why}, read ${summary.read}; errors ${summary.errors}`);
        else console.log(`kind ${kind}: cuts ${summary.cuts}, checked ${summary.checked}: same as the game decided ${ok}; errors ${summary.errors}`
            + (kind === 'gate' ? `; gate decisions without a cut ${summary.uncut}` : ''));
        console.log(`  by the game's answer (same/checked): ${Object.entries(summary.byDecision).map(([k, v]) => `${k} ${v}`).join(', ')}`);
        const judged = argv.includes('--all') ? 'bar (95% of each answer)' : 'on this sample, the bar (95% of each answer; judge it with --all)';
        console.log(`  ${judged}: ${summary.barMisses.length ? `missed by ${summary.barMisses.join(', ')}` : 'met'}`);
        for (const { cut, r } of rows.filter(x => !x.r.same).slice(0, 15)) {
            console.log(`  pid ${cut.pid} t=${cut.t} (${mmss(Number(cut.t))}): ${r.error || `replay ${r.got}, game ${r.want}${r.detail ? ` (${r.detail})` : ''}`}`);
        }
        return;
    }
    const pid = opt('--pid'), t = clock(opt('--t'));
    const mine = pool.filter(c => c.pid === pid && Number(c.t) <= t + 1e-6);
    if (!mine.length) { console.error(`no ev=cut kind=${kind} for pid ${pid} at or before ${opt('--t')}`); process.exit(1); }
    const cut = mine[mine.length - 1];
    const world = worldOf(game, cut);
    const id = opt('--id', d.id(cut));
    const lines = [
        `id: ${id}`, 'source: log', `ref: {log: ${path.basename(log)}, t: ${cut.t}}`, 'status: quarantined', `decision: ${d.driver}`,
        `# Cut by tools/hlog/cut.js. ${d.note(game, cut)}; write the right action, not this.`,
        ...factsOf(world),
        'world:',
        ...Object.entries(world).map(([k, v]) => `  ${k}: ${JSON.stringify(v)}`),
        'expect:', '  must: []', 'notes: >', '  TODO: the situation, and why the expectation is the right action.',
    ];
    console.log(lines.join('\n'));
}

/** Fewer cuts than this are replayed in-process: starting a worker costs more than it saves. */
const MIN_PARALLEL = 40;

/**
 * checkOne for each cut, in order. With jobs > 1 the cuts (interleaved, so each worker gets a like mix) are replayed on worker
 * threads, each reading the log itself and keeping its own Lua state; the results are the same as in-process.
 */
async function checkMany(log, gi, game, cuts, root, jobs) {
    if (jobs <= 1) return cuts.map(cut => checkOne(game, cut, root));
    const index = new Map(game.cuts.map((c, i) => [c, i]));
    const out = new Array(cuts.length);
    await Promise.all(Array.from({ length: Math.min(jobs, cuts.length) }, (_, w) => new Promise((resolve, reject) => {
        const slots = [];
        for (let i = w; i < cuts.length; i += Math.min(jobs, cuts.length)) slots.push(i);
        const worker = new Worker(__filename, { workerData: { log, gi, root, cutIdx: slots.map(i => index.get(cuts[i])) } });
        worker.once('message', rs => { rs.forEach((r, k) => { out[slots[k]] = r; }); resolve(); });
        worker.once('error', reject);
    })));
    return out;
}

if (!isMainThread && workerData && workerData.cutIdx) {
    const game = readGames(fs.readFileSync(workerData.log, 'utf8'))[workerData.gi];
    parentPort.postMessage(workerData.cutIdx.map(i => checkOne(game, game.cuts[i], workerData.root)));
} else if (require.main === module) main(process.argv.slice(2)).catch(e => { console.error(e); process.exit(1); });
module.exports = { burstOf, heroRecords, readGames, worldOf, replay, checkOne, checkMany, uncutGates, sampleByAnswer, barMisses, factsOf };
