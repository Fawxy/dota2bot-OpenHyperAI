'use strict';
const test = require('node:test');
const assert = require('node:assert');
const path = require('path');
const { parseLog, parseLine } = require('../parse');
const { runChecks } = require('../checks');
const report = require('../report');
const { parseTime } = require('../analyse');

const HARNESS = path.resolve(__dirname, '../../../tests/humaniser');
const ROOT = path.resolve(__dirname, '../../..');

function levels(game) {
    return Object.fromEntries(runChecks(game).map(r => [r.id, r]));
}

// Two bots with the profile telemetry.ts reports at skill 0.5 (notice 0.365, react 0.335, jitter 0.325).
function header(t = -60) {
    return [
        '[Humaniser] pid=1 npc_dota_hero_lion valve=2 fret=false/0/1(inactive) allyOfHuman=true skill=0.50',
        '[Humaniser] pid=2 npc_dota_hero_lina valve=2 fret=false/0/1(inactive) allyOfHuman=true skill=0.50',
        `[HEV] t=${t} ev=bot pid=1 hero=lion team=2 schema=1 skill=0.500 notice=0.365 react=0.335 ping=1.400 chat=1.500 jitter=0.325 lapse=0.085 lapseMax=0.800 minReact=0.170 deference=0.500`,
        `[HEV] t=${t} ev=bot pid=2 hero=lina team=2 schema=1 skill=0.500 notice=0.365 react=0.335 ping=1.400 chat=1.500 jitter=0.325 lapse=0.085 lapseMax=0.800 minReact=0.170 deference=0.500`,
        `[HEV] t=${t} ev=player pid=0 hero=axe team=2 human=1`,
    ];
}

/** Console order: Dota prints every VM's lines as the game clock advances. Non-[HEV] lines stay in place. */
function ordered(lines) {
    const t = l => Number((l.match(/\[HEV\] t=(\S+)/) || [])[1]);
    const events = lines.filter(l => !Number.isNaN(t(l))).sort((a, b) => t(a) - t(b));
    return lines.map(l => (Number.isNaN(t(l)) ? l : events.shift()));
}

function snaps(pid, from, to, extra = '') {
    const out = [];
    for (let t = from; t <= to; t++) out.push(`[HEV] t=${t} ev=snap pid=${pid} x=${t * 10} y=0 alive=1 hp=100 mp=50 lvl=1 lh=0 dn=0 mode=laning d=0.300 act=2 gold=600 ${extra}`.trim());
    return out;
}

test('quoted fields with spaces, quotes and = parse back', () => {
    const { e } = parseLine('junk prefix [HEV] t=12.500 ev=cmd by=0 text="!lion def top a=b" n=3 kind=chat');
    assert.strictEqual(e.kind, 'chat');
    assert.strictEqual(e.text, '!lion def top a=b');
    assert.strictEqual(e.n, 3);
    assert.strictEqual(e.t, 12.5);
});

test('games split when the clock resets; team-wide events repeated by each module instance count once', () => {
    const order = '[HEV] t=30 ev=order_post id=1 team=2 type=DEFEND lane=2 issuer=0 responders=1,2 dur=25 kind=chat src=cmd:0:!def:1';
    const mark = '[HEV] t=40 ev=mark n=1 by=0 team=2 text=x at=40';
    const markDire = '[HEV] t=40.2 ev=mark n=1 by=0 team=3 text=x at=40';
    const log = [...header(), ...snaps(1, 0, 50), order, order, mark, markDire, ...header(-90), ...snaps(1, -89, -80)].join('\n');
    const games = parseLog(log);
    assert.strictEqual(games.length, 2);
    assert.strictEqual(games[0].events.filter(e => e.ev === 'order_post').length, 1);
    assert.strictEqual(games[0].marks.length, 1);
    assert.strictEqual(games[1].minT, -90);
});

test('a clean game passes and catches nothing', () => {
    const lines = [
        ...header(0),
        ...snaps(1, 0, 40),
        ...snaps(2, 0, 40),
        '[HEV] t=10 ev=notice pid=1 target=npc_dota_hero_axe delay=0.400 due=0.380 reason=delay',
        '[HEV] t=11 ev=react pid=1 who=npc_dota_hero_axe what=axe_berserkers_call delay=0.300',
        '[HEV] t=20 ev=order_post id=1 team=2 type=DEFEND lane=2 issuer=0 responders=1 dur=25 kind=chat src=a',
        '[HEV] t=21.6 ev=order_accept pid=1 id=1 type=DEFEND lane=2 kind=chat read=1.500 latency=1.600',
        '[HEV] t=22 ev=mode pid=1 from=laning to=defend_mid d=0.850 dwell=22',
        '[HEV] t=30 ev=lasthit pid=1 human=0 n=1 creep=c dec="take: human-away" decAge=0.100',
    ];
    const log = ordered(lines).join('\n');
    const r = levels(parseLog(log)[0]);
    for (const id of ['script_errors', 'snapshot_gaps', 'notice_delay', 'react_delay', 'order_read_delay', 'order_followed', 'lasthit_etiquette', 'intent_health'])
        assert.strictEqual(r[id].level, 'pass', `${id}: ${r[id].summary} ${r[id].details.join('; ')}`);
});

test('each broken behaviour is reported by its check', () => {
    const lines = [
        ...header(0),
        ...snaps(1, 0, 20),
        ...snaps(1, 35, 40),
        ...snaps(2, 0, 40),
        // Sampled faster than the profile allows, and noticed before it was due.
        '[HEV] t=10 ev=notice pid=1 target=npc_dota_hero_axe delay=0.050 due=0.250 reason=delay',
        // Under MinReact.
        '[HEV] t=11 ev=react pid=2 who=npc_dota_hero_axe what=axe_berserkers_call delay=0.100',
        // Read a chat order in a fraction of a human's time, then ignored it.
        '[HEV] t=15 ev=order_post id=4 team=2 type=ROSHAN issuer=0 responders=2 dur=40 kind=chat src=b',
        '[HEV] t=15.2 ev=order_accept pid=2 id=4 type=ROSHAN kind=chat read=0.200 latency=0.200',
        // Took a creep it had decided to leave for the human.
        '[HEV] t=18 ev=lasthit pid=2 human=0 n=1 creep=c dec="skip: core" decAge=0.200',
        '[HEV] t=19 ev=stuck pid=2 mode=farm d=0.400 raw=0.400 inMode=3',
        'Script Runtime Error: bots/FunLib/humaniser/telemetry.lua:120: attempt to index a nil value',
    ];
    const log = ordered(lines).join('\n');
    const r = levels(parseLog(log)[0]);
    assert.strictEqual(r.script_errors.level, 'fail');
    assert.strictEqual(r.snapshot_gaps.level, 'fail', r.snapshot_gaps.summary);
    assert.strictEqual(r.notice_delay.details.length, 2, r.notice_delay.details.join('; '));
    assert.strictEqual(r.react_delay.level, 'fail');
    assert.strictEqual(r.order_read_delay.level, 'fail');
    assert.strictEqual(r.order_followed.level, 'warn');
    assert.strictEqual(r.lasthit_etiquette.level, 'fail');
    assert.strictEqual(r.intent_health.level, 'warn');
});

test('a bot standing still away from base is flagged; one in the fountain is not', () => {
    const still = [];
    for (let t = 0; t <= 15; t++) still.push(`[HEV] t=${t} ev=snap pid=1 x=0 y=0 alive=1 hp=100 mp=50 lvl=1 lh=0 dn=0 mode=farm d=0.4 act=1 gold=0`);
    for (let t = 0; t <= 15; t++) still.push(`[HEV] t=${t} ev=snap pid=2 x=-7000 y=-6500 alive=1 hp=100 mp=50 lvl=1 lh=0 dn=0 mode=none d=0 act=1 gold=0`);
    const r = levels(parseLog(ordered([...header(0), ...still]).join('\n'))[0]);
    assert.strictEqual(r.frozen_bots.level, 'warn');
    assert.strictEqual(r.frozen_bots.details.length, 1);
    assert.match(r.frozen_bots.details[0], /lion\[1\] stood still 15s/);
});

test('times accept seconds or m:ss', () => {
    assert.strictEqual(parseTime('5:12'), 312);
    assert.strictEqual(parseTime('-0:30'), -30);
    assert.strictEqual(parseTime('42.5'), 42.5);
});

test('real Lua telemetry from a scripted session analyses cleanly', () => {
    const { lua, lauxlib, lualib, to_luastring } = require(path.join(HARNESS, 'node_modules/fengari'));
    const L = lauxlib.luaL_newstate();
    lualib.luaL_openlibs(L);
    const prelude = `package.path = "${ROOT}/?.lua;" .. package.path\nunpack = unpack or table.unpack\nHARNESS_DIR = "${HARNESS}"\n`;
    lauxlib.luaL_dostring(L, to_luastring(prelude));
    const status = lauxlib.luaL_dofile(L, to_luastring(path.join(HARNESS, 'hlog_session.lua')));
    assert.strictEqual(status, 0, status !== 0 ? lua.lua_tojsstring(L, -1) : '');
    lauxlib.luaL_dostring(L, to_luastring('return table.concat(HLOG_LINES, "\\n")'));
    const text = lua.lua_tojsstring(L, -1);

    const games = parseLog(text);
    assert.strictEqual(games.length, 1);
    const game = games[0];
    assert.deepStrictEqual(Object.keys(game.bots).map(Number).sort(), [0, 1, 2]);
    assert.strictEqual(game.marks.length, 1);
    assert.strictEqual(game.marks[0].text, 'bots went mid');
    const accepts = game.events.filter(e => e.ev === 'order_accept');
    assert.ok(accepts.length >= 1, 'a bot accepted the !def order');
    const r = levels(game);
    assert.strictEqual(r.order_read_delay.level, 'pass', r.order_read_delay.details.join('; '));
    assert.strictEqual(r.order_followed.level, 'pass', r.order_followed.details.join('; '));
    assert.match(report.markView(game, 1, 20), /defend_mid/);
});
