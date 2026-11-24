'use strict';
// `hlog.js replay` (replay.js): a recorded game's units, paths and hits in the store, @unit_life reading the replay's units for that game,
// @unit_grade grading the log's against them, and the scene read's paths and hits. The replay lines are unittruth's, written by hand.
const test = require('node:test');
const assert = require('node:assert');
const fs = require('fs');
const os = require('os');
const path = require('path');
const { spawnSync } = require('child_process');
const { Store } = require('../store');
const { ingestReplay } = require('../replay');
const { secs, timelineRows } = require('../hlog');
const { scene } = require('../scene');

const line = (t, f) => `[HEV] t=${t.toFixed(3)} ev=${f}`;
const QUERIES = path.join(__dirname, '..', 'queries');
const sqlOf = n => fs.readFileSync(path.join(QUERIES, `${n}.sql`), 'utf8');

function open(logs) {
    const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'hlog-rp-'));
    const store = new Store(':memory:');
    const files = Object.entries(logs).map(([name, lines]) => {
        const f = path.join(dir, `2026-11-25T00-00-00-${name}.log`);
        const at = l => Number(l.match(/t=(\S+)/)[1]);
        fs.writeFileSync(f, [...lines].sort((a, b) => at(a) - at(b)).join('\n') + '\n');
        store.ingest(f);
        return f;
    });
    store.refreshViews();
    const gameId = f => store.query('SELECT game_id FROM games WHERE file = ?', f)[0].game_id;
    return { store, dir, files, gameId };
}

// unittruth's units and the paths a creep has: `path` is [[t, x, y]...], one a second.
const unit = (uid, kind, team, type, t0, x0, y0, extra = {}) => ({ k: 'unit', uid, ent: Number(uid.split('.')[0]), kind, team, type, name: `n_${type}`, t0, x0, y0, maxhp: 500, end: 'alive', ...extra });
const died = (t1, x1, y1, by_kind, extra = {}) => ({ t1, x1, y1, hp: 20, end: 'death', by_kind, kdt: 0, ...extra });
const pos = (uid, path) => path.map(([t, x, y]) => ({ k: 'pos', t, u: [[uid, x, y, 100]] }));
const hit = (t, ak, at, an, tk, tt, tn, dmg, extra = {}) => ({ k: 'hit', t, ak, at, an, tk, tt, tn, dmg, inf: '', ...extra });
const end = { k: 'end', netTick: 1, t: 720, deathEntries: 0, deathMatched: 0 };

test('a game with replay rows reads its units from the replay, whole; another game of the store reads its log, and the log path stays reachable', () => {
    const { store, files, gameId } = open({
        a_A_rad_1: [
            line(100, 'wave_creep_death team=2 kind=melee x=0 y=0 hp=0.05 by=none cid=7 lane=mid born=60 nd=0'),
            line(100.2, 'creep_death team=3 kind=melee x=40 y=0 hp=0.05 by=5 tw=0 cid=3'),
        ],
        b_A_rad_1: [line(100, 'wave_creep_death team=2 kind=melee x=0 y=0 hp=0.05 by=none cid=7 lane=mid born=60 nd=0'), line(100.2, 'creep_death team=3 kind=melee x=40 y=0 hp=0.05 by=5 tw=0 cid=3')],
    });
    const bot = [[80, 5000, -5500], [100, 5000, -5500]]; // a creep walking the bot lane
    ingestReplay(store, gameId(files[0]), 'a.dem', [
        unit('1500.0', 'lane', 2, 'melee', 60, -5000, -6000, died(100.1, 0, 0, 'tower', { by_team: 3 })),
        ...pos('1500.0', [[60, -5000, -6000], ...bot]),
        unit('1501.0', 'lane', 3, 'flag', 61, 6000, 5000, died(120, 10, 10, 'deny', { by_pid: 6, amb: 1 })),
        unit('1502.0', 'lane', 2, 'ranged', 60, -5000, -6000),
        unit('1600.2', 'neutral', 4, 'ogre_mauler', 60, 4649, -3699),
        { k: 'meta', until: 720, players: [] }, end,
    ]);
    const read = (like, game) => store.query(sqlOf('unit_life'), game === undefined ? { like } : { like, game });
    const a = read('%a_A_rad_1.log');
    assert.deepStrictEqual(a.map(r => [r.uid, r.kind, r.team, r.type, r.lane, r.wave, r.t1, r.by_kind, r.by_pid, r.by_src, r.src]), [
        ['1502.0', 'lane', 2, 'ranged', 'base', 2, null, null, null, null, 'replay'],
        ['1600.2', 'neutral', 4, 'ogre_mauler', null, null, null, null, null, null, 'replay'],
        ['1500.0', 'lane', 2, 'melee', 'bot', 2, 100.1, 'tower', null, 'replay', 'replay'],
        ['1501.0', 'lane', 3, 'flag', 'base', 2, 120, 'deny', 6, 'replay_amb', 'replay'],
    ].sort((x, y) => (x[6] ?? -1) - (y[6] ?? -1) || x[0].localeCompare(y[0])), 'the replay\'s rows only, none of the log\'s 2:7');
    assert.strictEqual(a.find(r => r.uid === '1600.2').camp, 2, 'a neutral at the large camp\'s spot is that camp');
    // the other game has no replay: its rows are the log's, with the enemy hero's last hit paired
    const b = read('%b_A_rad_1.log');
    assert.deepStrictEqual(b.map(r => [r.uid, r.src, r.by_kind, r.by_pid]), [['2:7', 'log', 'hero', 5]]);
    // the log's own rows for the replay's game stay reachable (@unit_grade pairs them to the replay's): the grade finds the paired death
    const grade = store.query(sqlOf('unit_grade'), { like: '%a_A_rad_1.log' });
    assert.deepStrictEqual(grade.filter(r => r.section === 'paired').map(r => [r.kind, r.by_kind, r.n, r.agree, r.wrong]), [['lane', 'tower', 1, 0, 1]],
        'the log paired 2:7 to an enemy hero (pid 5); the replay says a tower');
});

test('replaying again replaces a game\'s rows, and a changed log drops them (a game_id can be reused by another game)', () => {
    const { store, files, gameId } = open({ a_A_rad_1: [line(100, 'bot pid=0 hero=luna team=2 pos=1')] });
    const g = gameId(files[0]);
    const lines = [unit('9.0', 'lane', 2, 'melee', 60, 0, 0, died(70, 0, 0, 'hero', { by_pid: 3 })), ...pos('9.0', [[60, 0, 0], [61, 5, 5]]), hit(65, 'hero', 3, 'h', 'lane', 3, 'c', 40, { ap: 3 }), end];
    ingestReplay(store, g, 'a.dem', lines);
    ingestReplay(store, g, 'a.dem', lines);
    const n = t => store.query(`SELECT count(*) AS n FROM ${t} WHERE game_id = ${g}`)[0].n;
    assert.deepStrictEqual([n('rp_unit'), n('unit_pos'), n('unit_hit'), n('rp_game')], [1, 2, 1, 1]);
    fs.appendFileSync(files[0], line(101, 'bot pid=1 hero=lich team=2 pos=5') + '\n');
    store.ingest(files[0]);
    const rest = ['rp_game', 'rp_unit', 'unit_pos', 'unit_hit'].map(t => store.query(`SELECT count(*) AS n FROM ${t}`)[0].n);
    assert.deepStrictEqual(rest, [0, 0, 0, 0], 'nothing of the old rows is left to be read as the new game\'s');
});

test('@unit_grade: the log\'s killer is graded against the replay\'s by the replay\'s by_kind; what only one side has is counted apart', () => {
    const { store, files } = open({
        g_A_rad_1: [
            // 2:1 an enemy hero's last hit (pid 5), paired to the enemy's line; the replay agrees
            line(100, 'wave_creep_death team=2 kind=melee x=0 y=0 hp=0.05 by=none cid=1 lane=mid born=60 nd=0'),
            line(100.2, 'creep_death team=3 kind=melee x=0 y=0 hp=0.05 by=5 tw=0 cid=40'),
            // 2:2 the log names a deny (our pid 1); the replay says an enemy hero (pid 6): wrong. 2.5 s and 400 units off: still paired, not t_ok or spot_ok
            line(200, 'wave_creep_death team=2 kind=melee x=0 y=0 hp=0.05 by=1 cid=2 lane=mid born=60 nd=0'),
            // 2:3 nobody is named; the replay says a neutral killed it: the log cannot know (log_unknown)
            line(300, 'wave_creep_death team=2 kind=melee x=1000 y=0 hp=0.05 by=none cid=3 lane=mid born=60 nd=0'),
            // 2:4 only the log has it; and a sighting of a creep that went into fog
            line(400, 'wave_creep_death team=2 kind=melee x=2000 y=0 hp=0.05 by=none cid=4 lane=mid born=60 nd=0'),
            line(450, 'creep_death team=3 kind=ranged x=-2000 y=0 hp=0.05 by=6 tw=0 cid=44'),
        ],
    });
    ingestReplay(store, store.query('SELECT game_id FROM games')[0].game_id, 'g.dem', [
        unit('1.0', 'lane', 2, 'melee', 60, 0, 0, died(100, 0, 0, 'hero', { by_pid: 5 })),
        unit('2.0', 'lane', 2, 'melee', 60, 0, 0, died(202.5, 400, 0, 'hero', { by_pid: 6 })),
        unit('3.0', 'lane', 2, 'melee', 60, 0, 0, died(300, 1000, 0, 'neutral')),
        unit('5.0', 'neutral', 4, 'ogre_mauler', 60, 0, 0, died(500, 3000, 0, 'creep')),
        unit('6.0', 'lane', 3, 'melee', 60, 0, 0),
        end,
    ]);
    const rows = store.query(sqlOf('unit_grade'), { like: '%g_A_rad_1.log' });
    const pick = (sec, kind, by) => rows.find(r => r.section === sec && r.kind === kind && r.by_kind === by);
    const paired = (kind, by) => { const r = pick('paired', kind, by); return r && [r.n, r.agree, r.log_unknown, r.wrong, r.t_ok, r.spot_ok]; };
    assert.deepStrictEqual(paired('lane', 'hero'), [2, 1, 0, 1, 1, 1], 'two hero deaths: pid 5 agreed; the deny that was pid 6 is wrong, 2.5 s and 400 units off');
    assert.deepStrictEqual(paired('lane', 'neutral'), [1, 0, 1, 0, 1, 1]);
    assert.strictEqual(pick('replay_only', 'neutral', 'creep').n, 1);
    assert.strictEqual(pick('log_only', 'lane', null).n, 1, 'cid 4, which the replay has no death for (6.0 is alive)');
    assert.strictEqual(pick('log_sighting', 'lane', null).n, 1);
});

test('scene on a recorded game: the puller\'s hits taken and dealt, the neutrals\' deaths with their killers, and where a lane creep went at the camp', () => {
    const camp = { x: 4649, y: -3699 }; // camp 2
    const out = [line(-90, 'bot pid=0 hero=luna team=2 pos=1'), line(-90, 'bot pid=5 hero=axe team=3 pos=1')];
    for (let t = 160; t <= 200; t++) out.push(line(t, `snap pid=0 x=${camp.x + 300} y=${camp.y} alive=1 hp=90 ln=bot s=0.5 ld=40 mode=farm`));
    const { store, files } = open({ s_A_rad_1: out });
    const walk = (uid, ts, f) => pos(uid, ts.map(t => [t, ...f(t)]));
    ingestReplay(store, store.query('SELECT game_id FROM games')[0].game_id, 's.dem', [
        // 81.1 walks to 200 from the camp by 175 and is 900 from it by 185; 82.0 reaches it and a neutral kills it at 180
        unit('81.1', 'lane', 3, 'melee', 150, 0, 0),
        ...walk('81.1', [165, 170, 175, 180, 185], t => [camp.x + (t < 175 ? 200 + (175 - t) * 20 : 200 + (t - 175) * 70), camp.y]),
        unit('82.0', 'lane', 3, 'ranged', 150, 0, 0, died(180, camp.x, camp.y + 100, 'neutral', { by_name: 'npc_dota_neutral_ogre_mauler', by_team: 4 })),
        ...walk('82.0', [165, 170, 175, 180], () => [camp.x, camp.y + 100]),
        unit('300.0', 'neutral', 4, 'ogre_mauler', 60, camp.x, camp.y, died(190, camp.x, camp.y, 'hero', { by_pid: 0 })), ...walk('300.0', [165, 175, 185], () => [camp.x, camp.y]),
        hit(170, 'neutral', 4, 'npc_dota_neutral_ogre_mauler', 'hero', 2, 'npc_dota_hero_luna', 50, { tp: 0 }),
        hit(171, 'neutral', 4, 'npc_dota_neutral_ogre_mauler', 'hero', 2, 'npc_dota_hero_luna', 34, { tp: 0 }),
        hit(188, 'hero', 2, 'npc_dota_hero_luna', 'neutral', 4, 'npc_dota_neutral_ogre_mauler', 120, { ap: 0 }),
        hit(188, 'hero', 2, 'npc_dota_hero_luna', 'lane', 3, 'npc_dota_creep_badguys_melee', 40, { ap: 0 }),
        end,
    ]);
    const r = scene(store, files[0], { pid: 0, from: '2:45', to: '3:15', every: 10 }, { secs, timelineRows, target: 's_A_rad_1' });
    const text = r.lines.join('\n');
    assert.match(r.lines[0], /units: replay/);
    assert.match(text, /luna took 84 from neutral ogre_mauler \(2 hits\)/, 'who hit the puller');
    assert.match(text, /luna hit neutral ogre_mauler for 120 \(1 hit\)/);
    assert.ok(!/lane creep for 40/.test(text), 'a hero\'s hits on lane creeps are the creeps\' deaths, not lines');
    assert.match(text, /81\.1 D melee reached 200 from camp 2 \(large\), turned back \(900 from it at 3:05\); still alive/, 'where it went');
    assert.match(text, /82\.0 D ranged reached 100 from camp 2.*died at 3:00.*killed by neutral ogre_mauler/);
    assert.match(text, /300\.0 neutral ogre_mauler died .* camp 2: last hit by R1 luna/);
    // the log-only scene of the same game says what it cannot know
    const bare = open({ t_A_rad_1: out });
    const l = scene(bare.store, bare.files[0], { pid: 0, from: '2:45', to: '3:15', every: 10 }, { secs, timelineRows, target: 't_A_rad_1' });
    assert.match(l.lines[1], /not known in an unrecorded game/);
});

test('hlog.js replay <dem> runs the extractor beside the log and ingests what it wrote', () => {
    const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'hlog-rpcli-'));
    const base = path.join(dir, '2026-11-25T00-00-00-c_A_rad_1');
    fs.writeFileSync(`${base}.log`, `${line(-90, 'bot pid=0 hero=luna team=2 pos=1')}\n${line(100, 'snap pid=0 x=1 y=1 alive=1 hp=90')}\n`);
    fs.writeFileSync(`${base}.dem`, 'not a replay');
    const out = path.join(dir, 'out.ndjson');
    fs.writeFileSync(out, [unit('7.0', 'lane', 2, 'melee', 60, 0, 0, died(90, 0, 0, 'hero', { by_pid: 0 })), end].map(l => JSON.stringify(l)).join('\n'));
    const exe = path.join(dir, 'fake-unittruth');
    fs.writeFileSync(exe, `#!/bin/sh\ncat ${out}\n`, { mode: 0o755 });
    const run = args => spawnSync(process.execPath, [path.join(__dirname, '..', 'hlog.js'), '--db', path.join(dir, 's.sqlite'), '--no-ingest', ...args], { encoding: 'utf8', env: { ...process.env, UNITTRUTH_EXE: exe } });
    const r = run(['replay', `${base}.dem`]);
    assert.strictEqual(r.status, 0, r.stderr);
    assert.match(r.stdout, /1 units/);
    const q = run(['q', '@unit_life', '--p', 'like=%c_A_rad_1.log', '--json']);
    assert.deepStrictEqual(JSON.parse(q.stdout).map(x => [x.uid, x.by_kind, x.by_pid, x.src]), [['7.0', 'hero', 0, 'replay']]);
    const none = run(['replay', path.join(dir, 'gone.dem')]);
    assert.notStrictEqual(none.status, 0);
});
