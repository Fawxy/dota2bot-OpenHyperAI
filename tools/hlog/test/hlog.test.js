'use strict';
const test = require('node:test');
const assert = require('node:assert');
const path = require('path');
const { parseLog, parseLine } = require('../parse');
const { runChecks, modeChurn } = require('../checks');
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

test('a death gap ending in the fountain is not a stall; repeated errors group across console timestamps', () => {
    const at = (pid, t, x, y) => `[HEV] t=${t} ev=snap pid=${pid} x=${x} y=${y} alive=1 hp=100 mp=50 lvl=1 lh=0 dn=0 mode=laning d=0.3 act=2 gold=0`;
    const lines = [
        ...header(0),
        ...snaps(2, 0, 40),
        at(1, 0, 500, 500),
        at(1, 1, 500, 500),
        ...[20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31, 32, 33, 34, 35, 36, 37, 38, 39, 40].map(t => at(1, t, 6900, 6400)),
        '10/22 06:59:00 [VScript] Script Runtime Error: error in error handling',
        '10/22 06:59:03 [VScript] Script Runtime Error: error in error handling',
        '10/22 06:59:03 [VScript] Message count limit of 10 hit. Subsequent duplicate messages will be squelched.',
    ];
    const r = levels(parseLog(ordered(lines).join('\n'))[0]);
    assert.strictEqual(r.snapshot_gaps.level, 'pass', r.snapshot_gaps.details.join('; '));
    assert.strictEqual(r.script_errors.details.length, 1, r.script_errors.details.join('; '));
    assert.match(r.script_errors.details[0], /^2x from /);
    assert.match(r.script_errors.summary, /squelched/);
});

test('a bot that dies shortly before the log ends is not a stall; one that goes quiet with no enemy kill is', () => {
    const enemy = '[HEV] t=0 ev=bot pid=3 hero=axe team=3 schema=1 skill=0.500 notice=0.365 react=0.335 ping=1.400 chat=1.500 jitter=0.325 lapse=0.085 lapseMax=0.800 minReact=0.170 deference=0.500';
    const run = killAt => {
        const kills = [];
        for (let t = 0; t <= 40; t++) kills.push(...snaps(3, t, t, `kills=${killAt !== undefined && t >= killAt ? 1 : 0}`));
        const lines = [...header(0), enemy, ...snaps(1, 0, 20), ...snaps(2, 0, 40), ...kills];
        return levels(parseLog(ordered(lines).join('\n'))[0]).snapshot_gaps;
    };
    const died = run(21);
    assert.strictEqual(died.level, 'pass', died.details.join('; '));
    const stalled = run(undefined);
    assert.strictEqual(stalled.level, 'fail', stalled.summary);
    assert.match(stalled.details[0], /lion\[1\] stopped reporting at 0:20/);
});

test('times accept seconds or m:ss', () => {
    assert.strictEqual(parseTime('5:12'), 312);
    assert.strictEqual(parseTime('-0:30'), -30);
    assert.strictEqual(parseTime('42.5'), 42.5);
});

/** Runs a scripted Lua session from the offline harness and returns the [HEV] lines it left in HLOG_LINES. */
function luaSession(file) {
    const { lua, lauxlib, lualib, to_luastring } = require(path.join(HARNESS, 'node_modules/fengari'));
    const L = lauxlib.luaL_newstate();
    lualib.luaL_openlibs(L);
    const prelude = `package.path = "${ROOT}/?.lua;" .. package.path\nunpack = unpack or table.unpack\nHARNESS_DIR = "${HARNESS}"\n`;
    lauxlib.luaL_dostring(L, to_luastring(prelude));
    const status = lauxlib.luaL_dofile(L, to_luastring(path.join(HARNESS, file)));
    assert.strictEqual(status, 0, status !== 0 ? lua.lua_tojsstring(L, -1) : '');
    lauxlib.luaL_dostring(L, to_luastring('return table.concat(HLOG_LINES, "\\n")'));
    return lua.lua_tojsstring(L, -1);
}

test('real Lua telemetry from a scripted session analyses cleanly', () => {
    const text = luaSession('hlog_session.lua');

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

/** Upstream team_roam grabbing a last hit in lane: laning -> team_roam at its 0.72 cap, back within a fraction of a second. */
function blips(pid, from, n, step = 0.8) {
    const out = [];
    for (let i = 0; i < n; i++) {
        const t = from + i * step;
        out.push(`[HEV] t=${t.toFixed(3)} ev=mode pid=${pid} from=laning to=team_roam d=0.720 dwell=0.400 by="team_roam 0.72 by raw"`);
        out.push(`[HEV] t=${(t + 0.3).toFixed(3)} ev=mode pid=${pid} from=team_roam to=laning d=0.446 dwell=0.300 by="laning 0.45 by raw"`);
    }
    return out;
}

function flips(pid, from, n, a, b, step = 0.8) {
    const out = [];
    for (let i = 0; i < n; i++) {
        const t = from + i * step;
        const [x, y] = i % 2 === 0 ? [a, b] : [b, a];
        out.push(`[HEV] t=${t.toFixed(3)} ev=mode pid=${pid} from=${x} to=${y} d=0.900 dwell=0.800 by="${y} 0.90 by raw"`);
    }
    return out;
}

const thrash = (pid, t, mode, competing) => `[HEV] t=${t} ev=thrash pid=${pid} switches=5 window=5 mode=${mode} competing="${competing}"`;

test('last-hit blip churn is counted, not warned', () => {
    const lines = [
        ...header(0),
        ...snaps(1, 0, 120),
        ...snaps(2, 0, 120),
        ...blips(1, 10, 6),
        thrash(1, 14.3, 'laning', 'laning=0.45 team_roam=0.00'),
        ...blips(1, 60, 6),
        thrash(1, 64.3, 'team_roam', 'team_roam=0.72 laning=0.45'),
    ];
    const game = parseLog(ordered(lines).join('\n'))[0];
    const r = levels(game).intent_health;
    assert.strictEqual(r.level, 'pass', `${r.summary} ${r.details.join('; ')}`);
    assert.match(r.summary, /2 last-hit blip/);
    const churn = modeChurn(game)[1];
    assert.strictEqual(churn.blips, 12);
    assert.strictEqual(churn.thrash.blip, 2);
    assert.match(report.summary(game), /lion\[1\]\s+24\s+12\s+6\.0\s+0\.0/);
});

test('genuine thrash stays visible, grouped per bot and mode pair with first times', () => {
    const lines = [
        ...header(0),
        ...snaps(1, 0, 120),
        ...snaps(2, 0, 120),
        ...blips(1, 10, 6),
        thrash(1, 14.3, 'laning', 'laning=0.45 team_roam=0.00'),
        ...flips(2, 20, 6, 'attack', 'retreat'),
        thrash(2, 24, 'retreat', 'retreat=0.90 attack=0.85'),
        ...flips(2, 50, 6, 'attack', 'retreat'),
        thrash(2, 54, 'attack', 'attack=0.90 retreat=0.85'),
        // Blips mixed into a retreat/team_roam fight still leave enough real switches to thrash on their own.
        ...flips(2, 90, 6, 'retreat', 'team_roam'),
        ...blips(2, 90.4, 2),
        thrash(2, 94.5, 'team_roam', 'team_roam=0.72 retreat=0.60'),
        '[HEV] t=100 ev=stuck pid=2 mode=farm d=0.400 raw=0.400 inMode=3',
        '[HEV] t=110 ev=stuck pid=2 mode=farm d=0.400 raw=0.400 inMode=3',
    ];
    const game = parseLog(ordered(lines).join('\n'))[0];
    const r = levels(game).intent_health;
    assert.strictEqual(r.level, 'warn');
    assert.strictEqual(r.details.length, 1, r.details.join('; '));
    assert.match(r.details[0], /^lina\[2\]: 3 thrash episodes \(0 last-hit blips\); attack<->retreat 2x from 0:24, retreat<->team_roam 1x from 1:34; stuck 2x: farm 2x from 1:40$/);
    assert.match(r.summary, /3 genuine thrash and 2 stuck episodes; 1 last-hit blip episode/);
    assert.match(report.summary(game), /attack<->retreat 12/);
});

test('late notices aggregate per bot with the worst few listed', () => {
    const late = (pid, t, delay) => `[HEV] t=${t} ev=notice pid=${pid} target=npc_dota_hero_axe delay=${delay} due=0.380 reason=delay`;
    const lines = [
        ...header(0),
        ...snaps(1, 0, 60),
        ...snaps(2, 0, 60),
        ...[5, 10, 15, 20, 25, 30, 35, 40].map((t, i) => late(1, t, (1.5 + i * 0.1).toFixed(3))),
        late(2, 12, '3.000'),
        late(2, 13, '0.400'),
    ];
    const r = levels(parseLog(ordered(lines).join('\n'))[0]).notice_delay;
    assert.strictEqual(r.level, 'warn');
    assert.match(r.summary, /0 fail, 9 late notices across 2 bots; worst 2\.62s/);
    assert.strictEqual(r.details[0], 'late by bot: lion[1] 8, lina[2] 1');
    assert.strictEqual(r.details.length, 6, r.details.join('; '));
    assert.match(r.details[1], /^0:12 lina\[2\] saw npc_dota_hero_axe: noticed 2\.62s after/);
    assert.match(r.details[2], /^0:40 lion\[1\]/);
});

test('a capped team_roam visit is a blip whichever mode it exits to, but not once it lasts or starts outside laning', () => {
    const mode = (t, from, to, d, dwell) => `[HEV] t=${t} ev=mode pid=1 from=${from} to=${to} d=${d} dwell=${dwell}`;
    const lines = [
        ...header(0),
        ...snaps(1, 0, 60),
        mode(10, 'laning', 'team_roam', 0.72, 5),
        mode(10.4, 'team_roam', 'attack', 0.95, 0.4),
        mode(11, 'attack', 'laning', 0.446, 0.6),
        mode(20, 'laning', 'team_roam', 0.72, 9),
        mode(24, 'team_roam', 'laning', 0.446, 4),
        mode(30, 'laning', 'retreat', 0.9, 6),
        mode(31, 'retreat', 'team_roam', 0.72, 1),
        mode(31.3, 'team_roam', 'retreat', 0.9, 0.3),
    ];
    const c = modeChurn(parseLog(ordered(lines).join('\n'))[0])[1];
    assert.strictEqual(c.blips, 1);
    assert.deepStrictEqual([...c.pairs.keys()].sort(), ['attack<->laning', 'laning<->retreat', 'laning<->team_roam', 'retreat<->team_roam']);
    assert.strictEqual(c.pairs.get('retreat<->team_roam').n, 2);
});

test('errors caught by humaniser guards fail the check once per hook and message, at their highest count', () => {
    const lines = [
        ...header(0),
        ...snaps(1, 0, 30),
        ...snaps(2, 0, 30),
        '[HEV] t=8 ev=lua_error pid=1 where=Intent.Resolve n=1 msg="intent.lua:40: attempt to index a nil value" tb="intent.lua:40 <- mode_team_roam_generic.lua:81"',
        '[HEV] t=18 ev=lua_error pid=1 where=Intent.Resolve n=37 msg="intent.lua:40: attempt to index a nil value" tb="intent.lua:40 <- mode_team_roam_generic.lua:81"',
    ];
    const r = levels(parseLog(ordered(lines).join('\n'))[0]);
    assert.strictEqual(r.script_errors.level, 'fail');
    assert.strictEqual(r.script_errors.details.length, 1, r.script_errors.details.join('; '));
    assert.match(r.script_errors.details[0], /^guarded 37x from 0:08: Intent\.Resolve: intent\.lua:40/);
});

/** A lane-fight episode for pid: a window, a start, then its end. */
function fight(pid, t, { window = 'spell', phase = 'trade', reason = 'hits', took = 1, via } = {}) {
    const start = phase === 'commit' ? `margin=1.200 via=${via || 'solo'}` : `window=${window}`;
    const out = [
        `[HEV] t=${t} ev=lanefight_window pid=${pid} window=${window} target=6 noticed=1`,
        `[HEV] t=${t + 0.3} ev=lanefight_start pid=${pid} phase=${phase} target=6 ${start}`,
    ];
    if (phase === 'commit') out.push(`[HEV] t=${t + 0.3} ev=lanefight_commit pid=${pid} target=6 margin=1.200 role=solo`);
    out.push(`[HEV] t=${t + 2.5} ev=lanefight_end pid=${pid} phase=${phase} reason=${reason} hits=2 took=${took}`);
    return out;
}

const mem = (pid, t, extra) => `[HEV] t=${t} ev=lanefight_mem pid=${pid} enemy=6 ability=lion_impale ${extra}`;

test('the summary lists lane fights per bot: windows, starts, ends, took share, gates and mistakes', () => {
    const lines = [
        ...header(0),
        ...snaps(1, 0, 60),
        ...snaps(2, 0, 60),
        ...fight(1, 10, { window: 'spell' }),
        ...fight(1, 20, { window: 'level', reason: 'mode:laning', took: 0 }),
        ...fight(1, 30, { phase: 'commit', reason: 'target-dead' }),
        '[HEV] t=40 ev=lanefight_gate pid=1 gate=low-hp',
        '[HEV] t=41 ev=lanefight_gate pid=1 gate=low-hp',
        '[HEV] t=42 ev=lanefight_gate pid=1 gate=respect:their_ult',
        '[HEV] t=43 ev=lanefight_abort pid=1 phase=commit reason=escape',
        '[HEV] t=44 ev=lanefight_mistake pid=1 kind=bad_memory ability=lion_impale target=6 after=0.500',
        mem(1, 9, 'cls=key cd=12 remembered=1 src=poll'),
    ];
    const game = parseLog(ordered(lines).join('\n'))[0];
    const text = report.summary(game);
    const row = text.split('\n').find(l => /^lion\[1\]/.test(l) && l.includes('spell'));
    assert.ok(row, text);
    assert.match(row, /spell 2, level 1/);
    assert.match(row, /trade 2, commit 1/);
    assert.match(row, /2\/3 took/);
    assert.match(row, /hits 1, mode:laning 1, target-dead 1/);
    assert.match(row, /low-hp 2, respect:their_ult 1/);
    assert.match(row, /escape 1/);
    assert.match(row, /bad_memory 1/);
    assert.match(row, /mem 1\/1/);
    assert.ok(!text.split('\n').some(l => /^lina\[2\].*took/.test(l)), 'a bot with no lane-fight events gets no row');
    assert.strictEqual(levels(game).lane_fight.level, 'pass', levels(game).lane_fight.summary);
});

test('lane_fight warns when no start ever took over, and when GetCooldown reads nothing on enemies', () => {
    const lines = [
        ...header(0),
        ...snaps(1, 0, 60),
        ...fight(1, 10, { reason: 'mode:laning', took: 0 }),
        ...fight(1, 20, { reason: 'mode:retreat', took: 0 }),
        ...fight(1, 30, { phase: 'commit', reason: 'mode:laning', took: 0 }),
        '[HEV] t=35 ev=lanefight_start pid=1 phase=wait_partner target=6 margin=1.100 with=2 human=0',
        '[HEV] t=38 ev=lanefight_end pid=1 phase=wait_partner reason=partner_timeout hits=0 took=0',
        mem(1, 5, 'remembered=0 reason=no_cd'),
        mem(1, 6, 'remembered=0 reason=no_cd').replace('lion_impale', 'lion_voodoo'),
        mem(1, 7, 'remembered=0 reason=no_cd').replace('lion_impale', 'lion_finger_of_death'),
        mem(1, 8, 'cls=key cd=12 remembered=1 src=jump'),
    ];
    const r = levels(parseLog(ordered(lines).join('\n'))[0]).lane_fight;
    assert.strictEqual(r.level, 'warn', r.summary);
    assert.ok(r.details.some(d => /lion\[1\].*3 trades\/commits.*none took over/.test(d)), r.details.join('; '));
    assert.ok(r.details.some(d => /no_cd 3\/4/.test(d) && /Task 4b/.test(d)), r.details.join('; '));

    const one = [...header(0), ...snaps(1, 0, 60), ...fight(1, 10, { reason: 'mode:laning', took: 0 })];
    assert.strictEqual(levels(parseLog(ordered(one).join('\n'))[0]).lane_fight.level, 'pass', 'one start that never took over is too few to warn');
    assert.strictEqual(levels(parseLog(ordered([...header(0), ...snaps(1, 0, 20)]).join('\n'))[0]).lane_fight.level, 'skip');
});

test('farm_trips: a trip handed to a fight by Valve attack mode is a planned end, one taken by rune is not', () => {
    const game = parseLog(
        [
            ...header(),
            '[HEV] t=340 ev=farm_trip_start pid=1 camp=7 type=small phase=go',
            '[HEV] t=354 ev=farm_trip_end pid=1 camp=7 type=small phase=stack why=preempted camps=1 secs=14 to=attack',
            '[HEV] t=400 ev=farm_trip_start pid=1 camp=7 type=small phase=go',
            '[HEV] t=410 ev=farm_trip_end pid=1 camp=7 type=small phase=go why=preempted camps=1 secs=10 to=rune',
        ].join('\n')
    )[0];
    const r = levels(game).farm_trips;
    assert.strictEqual(r.details.length, 1, r.details.join('; '));
    assert.match(r.details[0], /preempted -> rune 1x/);
});
test('real FarmPattern telemetry: trips summarised per core, a trip lost to another mode is flagged with the winner', () => {
    const games = parseLog(luaSession('hlog_farm_session.lua'));
    assert.strictEqual(games.length, 1);
    const game = games[0];
    const ends = game.events.filter(e => e.ev === 'farm_trip_end');
    assert.deepStrictEqual(ends.map(e => e.why), ['back', 'preempted']);
    assert.strictEqual(ends[1].to, 'rune');
    const r = levels(game).farm_trips;
    assert.strictEqual(r.level, 'warn', r.summary);
    assert.strictEqual(r.details.length, 1, r.details.join('; '));
    assert.match(r.details[0], /preempted -> rune 1x, first at 8:27/);
    // Trip 1 left its camp unfinished, so trip 2 starts with the pace grown by LateGrowth (1.15).
    const row = report.summary(game).split('\n').find(l => /^pid1 /.test(l));
    assert.ok(row, report.summary(game));
    assert.match(row, /^pid1\s+2\s+2\s+0\/0\s+\S+\s+late 1\s+back 1, preempted 1\s+1\.15\s+wave 16$/);
    const gate = game.events.find(e => e.ev === 'farm_gate');
    assert.strictEqual(gate.why, 'wave', 'the 9:05 check logs the live wave');
});
test('forecast fit recovers K from lane_eq pairs', () => {
    const ev = (t, eq, imb) => ({ ev: 'lane_eq', t, team: 2, lane: 1, kind: 'safe', eq, imb });
    const rows = report.fitForecast([ev(70, -0.5, 0.5), ev(100, -0.35, -0.25), ev(130, -0.425, 0.0), ev(160, -0.425, 0.4)]);
    assert.strictEqual(rows.length, 1);
    assert.strictEqual(rows[0].n, 3);
    assert.ok(Math.abs(rows[0].k - 0.3) < 1e-9);
});
test('forecast fit skips pairs more than one cycle apart', () => {
    const ev = (t, eq, imb) => ({ ev: 'lane_eq', t, team: 2, lane: 1, kind: 'safe', eq, imb });
    assert.strictEqual(report.fitForecast([ev(70, -0.5, 0.5), ev(160, 0, 0)]).length, 0);
});
test('summary reports the forecast fit and pre-contest outcomes', () => {
    const game = parseLog(
        [
            ...header(),
            '[HEV] t=70 ev=lane_eq team=2 lane=1 kind=safe eq=-0.500 imb=0.500 feq=-0.300 a=3 e=3',
            '[HEV] t=80 ev=lane_job_start pid=2 kind=contest camp=3 pre=1',
            '[HEV] t=81 ev=lane_job_start pid=2 kind=contest camp=3',
            '[HEV] t=85 ev=lane_job_end pid=2 kind=contest camp=3 reason=timeout pre=1',
            '[HEV] t=95 ev=lane_job_end pid=2 kind=contest camp=3 reason=no-pull pre=1',
            '[HEV] t=96 ev=lane_job_end pid=2 kind=contest camp=3 reason=no-target pre=0',
            '[HEV] t=110 ev=lane_job_start pid=2 kind=contest camp=3 pre=1',
            '[HEV] t=112 ev=lane_job_abort pid=2 kind=contest camp=3 reason=partner-low-hp phase=lookout pre=1',
            '[HEV] t=113 ev=lane_job_abort pid=2 kind=contest camp=3 reason=dead phase=travel',
            '[HEV] t=100 ev=lane_eq team=2 lane=1 kind=safe eq=-0.350 imb=-0.250 feq=-0.400 a=3 e=3',
            '[HEV] t=130 ev=lane_eq team=2 lane=1 kind=safe eq=-0.425 imb=0.000 feq=-0.425 a=3 e=3',
        ].join('\n')
    )[0];
    const text = report.summary(game);
    assert.match(text, /forecast fit:\n {2}safe n=2 K=0\.30 r2=1\.00/);
    assert.match(text, /pre-contest: started 2 attacked 1 no-pull 1 enemy-in-lane 0 aborted 1/);
});
test('summary reports take-pull outcomes and swings', () => {
    const game = parseLog(
        [
            ...header(),
            '[HEV] t=80 ev=lane_job_start pid=0 kind=contest camp=2 take=1',
            '[HEV] t=90 ev=lane_job_end pid=0 kind=contest camp=2 reason=no-creeps pre=0 take=1 swings=3',
            '[HEV] t=100 ev=lane_job_start pid=0 kind=contest camp=2 take=1',
            '[HEV] t=104 ev=lane_job_end pid=0 kind=contest camp=2 reason=outnumbered pre=0 take=1 swings=1',
            '[HEV] t=110 ev=lane_job_start pid=0 kind=contest camp=2 take=1',
            '[HEV] t=112 ev=lane_job_abort pid=0 kind=contest camp=2 reason=mode-end phase=travel take=1',
            '[HEV] t=114 ev=lane_job_end pid=0 kind=contest camp=2 reason=low-hp pre=0 take=1 swings=0',
            '[HEV] t=115 ev=lane_job_end pid=0 kind=contest camp=2 reason=lane-wave pre=0 take=1 swings=0',
            '[HEV] t=116 ev=lane_signal pid=0 kind=pull lane=3 camp=2 enemy=8 noticed=1 inferred=0',
            '[HEV] t=116.5 ev=lane_signal pid=0 kind=half_pull lane=3 camp=2 enemy=-1 noticed=0 inferred=0',
            '[HEV] t=117 ev=lane_signal pid=4 kind=stack lane=3 camp=5 enemy=8 noticed=1 inferred=0',
            '[HEV] t=117.5 ev=lane_take_skip pid=0 kind=pull camp=2 reason=lane-creeps',
            '[HEV] t=118 ev=lane_take_skip pid=0 kind=pull camp=2 reason=lane-creeps',
            '[HEV] t=118.5 ev=lane_take_skip pid=1 kind=pull camp=2 reason=owner',
            '[HEV] t=118.6 ev=lane_enemy_role team=2 lane=3 role=support enemy=7 hero=npc_dota_hero_ursa members=7,8',
            '[HEV] t=118.7 ev=lane_enemy_role team=2 lane=3 role=support enemy=8 hero=npc_dota_hero_lion members=7,8',
            '[HEV] t=118.8 ev=lane_enemy_role team=2 lane=2 role=mid enemy=9 hero=npc_dota_hero_lina members=9',
            '[HEV] t=120 ev=lane_job_start pid=4 kind=contest camp=2',
            '[HEV] t=125 ev=lane_job_end pid=4 kind=contest camp=2 reason=timeout pre=0',
        ].join('\n')
    )[0];
    const text = report.summary(game);
    assert.match(text, /take-pull: started 3 swings 4 no-creeps 1 timeout 0 outnumbered 1 low-hp 1 lane-wave 1 aborted 1/);
    assert.match(text, /pull signals: 2 noticed 1; take skipped: lane-creeps 2 owner 1/);
    assert.match(text, /enemy roles read by rad: mid mid=lina\[9\], bot support=lion\[8\] \(1 changes\)/);
    assert.doesNotMatch(text, /enemy roles read by dire/);
    assert.doesNotMatch(text, /pre-contest:/);
});

// ---- laning metrics and before/after compare

function botLine(pid, build, pos, t = -60) {
    return `[HEV] t=${t} ev=bot pid=${pid} hero=h${pid} team=2 schema=2 skill=0.500 notice=0.365 react=0.335 ping=1.400 chat=1.500 jitter=0.325 lapse=0.085 lapseMax=0.800 minReact=0.170 deference=0.500 build=${build} pos=${pos}`;
}

function snapAt(pid, t, { lh = 0, dn = 0, hp = 100, alive = 1 } = {}) {
    return `[HEV] t=${t} ev=snap pid=${pid} x=0 y=0 alive=${alive} hp=${hp} mp=50 lvl=1 lh=${lh} dn=${dn} mode=laning d=0.300 act=2 gold=600`;
}

const { laningMetrics } = (() => {
    try {
        return require('../metrics');
    } catch (e) {
        return {};
    }
})();

test('laningMetrics: lh and dn are read from the last snap at or before 10:00', () => {
    const lines = [botLine(1, 'aaa', 1)];
    for (let t = 0; t <= 660; t += 30) lines.push(snapAt(1, t, { lh: t / 15, dn: t / 60 }));
    const m = laningMetrics(parseLog(lines.join('\n'))[0]);
    const b = m.bots.find(x => x.pid === 1);
    assert.strictEqual(b.lh, 40);
    assert.strictEqual(b.dn, 10);
    assert.strictEqual(b.pos, 1);
    assert.strictEqual(m.build, 'aaa');
    assert.strictEqual(m.complete, true);
});

test('laningMetrics: retreatHealthySec counts retreat time only while hp >= 60', () => {
    const lines = [botLine(1, 'aaa', 1)];
    for (let t = 0; t <= 620; t++) lines.push(snapAt(1, t, { hp: t >= 105 && t <= 110 ? 40 : 80 }));
    lines.push('[HEV] t=100 ev=mode pid=1 from=laning to=retreat d=0.9 dwell=5 by="retreat 0.90 by raw"');
    lines.push('[HEV] t=110 ev=mode pid=1 from=retreat to=laning d=0.9 dwell=10 by="laning 0.90 by raw"');
    const b = laningMetrics(parseLog(lines.sort(byT).join('\n'))[0]).bots.find(x => x.pid === 1);
    assert.strictEqual(b.retreatSec, 10);
    assert.strictEqual(b.retreatHealthySec, 5);
});

test('laningMetrics: retreatBy splits retreat time by the claim source in the mode event by= text', () => {
    const lines = [botLine(1, 'aaa', 1), snapAt(1, 0), snapAt(1, 620)];
    lines.push('[HEV] t=100 ev=mode pid=1 from=laning to=retreat d=1.1 dwell=5 by="retreat 1.10 by transitions:caution+sticky"');
    lines.push('[HEV] t=110 ev=mode pid=1 from=retreat to=retreat d=0.8 dwell=10 by="retreat 0.80 by raw"');
    lines.push('[HEV] t=114 ev=mode pid=1 from=retreat to=laning d=0.9 dwell=4 by="laning 0.90 by raw"');
    const b = laningMetrics(parseLog(lines.sort(byT).join('\n'))[0]).bots.find(x => x.pid === 1);
    assert.strictEqual(b.retreatBy['transitions:caution'], 10);
    assert.strictEqual(b.retreatBy.raw, 4);
});

test('laningMetrics: deaths, caution time, commits, kills, pulls, stacks, rotations and aggro draws with a last hit', () => {
    const lines = [botLine(1, 'aaa', 5), snapAt(1, 0), snapAt(1, 100, { alive: 0 }), snapAt(1, 130), snapAt(1, 200, { alive: 0 }), snapAt(1, 620)];
    lines.push('[HEV] t=10 ev=tr_caution pid=1 level=0.500 alone=1 missing=0 lane=1');
    lines.push('[HEV] t=40 ev=tr_caution pid=1 level=0 alone=0 missing=0 lane=1');
    lines.push('[HEV] t=50 ev=lanefight_start pid=1 phase=commit target=7');
    lines.push('[HEV] t=54 ev=lanefight_end pid=1 phase=commit reason=target-dead hits=4 took=1');
    lines.push('[HEV] t=60 ev=lanefight_start pid=1 phase=commit target=7');
    lines.push('[HEV] t=66 ev=lanefight_end pid=1 phase=commit reason=chase hits=1 took=1');
    lines.push('[HEV] t=70 ev=lanefight_start pid=1 phase=trade target=7');
    lines.push('[HEV] t=72 ev=lanefight_end pid=1 phase=trade reason=hits hits=3 took=1');
    lines.push('[HEV] t=80 ev=lane_job_start pid=1 kind=full camp=2');
    lines.push('[HEV] t=80.5 ev=lane_job_start pid=1 kind=contest camp=2');
    lines.push('[HEV] t=81 ev=lane_job_start pid=1 kind=stack camp=3');
    lines.push('[HEV] t=82 ev=tr_rotate pid=1 spawn=360 go=1 side=top leaveAt=340 reason=ok');
    lines.push('[HEV] t=83 ev=tr_rotate pid=1 spawn=480 go=0 side=top leaveAt=460 reason=roll');
    lines.push('[HEV] t=84 ev=lane_tech pid=1 tech=aggro_pull reason=x lh=1');
    lines.push('[HEV] t=85 ev=lane_tech pid=1 tech=aggro_pull reason=x lh=0');
    const b = laningMetrics(parseLog(lines.sort(byT).join('\n'))[0]).bots.find(x => x.pid === 1);
    assert.deepStrictEqual(
        [b.deaths, b.cautiousSec, b.commits, b.commitKills, b.commitSec, b.trades, b.pullsStarted, b.stacksStarted, b.rotations, b.aggroWithLastHit],
        [2, 30, 2, 1, 10, 1, 1, 1, 1, 1]
    );
});

test('laningMetrics: a game that ends before until is complete=false', () => {
    const m = laningMetrics(parseLog([botLine(1, 'aaa', 1), snapAt(1, 0), snapAt(1, 300)].join('\n'))[0]);
    assert.strictEqual(m.complete, false);
});

function byT(a, b) {
    const t = l => Number((l.match(/t=(\S+)/) || [])[1]);
    return t(a) - t(b);
}

test('compare: picks games by build, skips incomplete ones, and flags a delta under 2 pooled SE as noisy', () => {
    const { compareGames } = require('../compare');
    const game = (build, lhs, until = 620) => {
        const lines = [];
        lhs.forEach((lh, i) => lines.push(botLine(i + 1, build, 1)));
        lhs.forEach((lh, i) => lines.push(snapAt(i + 1, 0), snapAt(i + 1, until - 30, { lh }), snapAt(i + 1, until, { lh })));
        return parseLog(lines.sort(byT).join('\n'))[0];
    };
    const games = [game('base', [20, 22]), game('base', [21, 23]), game('base', [99], 300), game('cand', [40, 42]), game('cand', [41, 43]), game('other', [0])];
    const rows = compareGames(games, { base: 'base', cand: 'cand' });
    const lh = rows.find(r => r.metric === 'lh' && r.pos === 1);
    assert.strictEqual(lh.base.n, 4);
    assert.strictEqual(lh.cand.n, 4);
    assert.ok(Math.abs(lh.delta - 20) < 1e-9);
    assert.strictEqual(lh.noisy, false);
    const noisy = compareGames([game('base', [10, 30]), game('cand', [12, 31])], { base: 'base', cand: 'cand' }).find(r => r.metric === 'lh' && r.pos === 1);
    assert.strictEqual(noisy.noisy, true);
});

test('laningMetrics: deaths and kills come from the snapshot scoreboard fields when present', () => {
    const lines = [botLine(1, 'aaa', 1), snapAt(1, 0), snapAt(1, 590).replace('gold=600', 'gold=600 kills=2 deaths=3'), snapAt(1, 620).replace('gold=600', 'gold=600 kills=5 deaths=4')];
    const b = laningMetrics(parseLog(lines.join('\n'))[0]).bots.find(x => x.pid === 1);
    assert.deepStrictEqual([b.kills, b.deaths], [2, 3]);
});

test('stateMetrics: agreement leaves out interrupts and (for agreeLong) mode blips; switches, restart lag and end reasons', () => {
    const { stateMetrics } = require('../metrics');
    const modeAt = t => (t >= 10 && t < 20 ? 'retreat' : (t >= 30 && t < 35) || t === 40 || t >= 50 ? 'farm' : 'laning');
    const lines = [botLine(1, 'aaa', 2, -5)];
    for (let t = 0; t < 60; t++) lines.push(snapAt(1, t).replace('mode=laning', `mode=${modeAt(t)}`));
    const modes = [[9.5, 'laning', 'retreat'], [19.5, 'retreat', 'laning'], [29.5, 'laning', 'farm'], [34.5, 'farm', 'laning'], [39.8, 'laning', 'farm'], [40.3, 'farm', 'laning'], [49.5, 'laning', 'farm']];
    for (const [t, from, to] of modes) lines.push(`[HEV] t=${t} ev=mode pid=1 from=${from} to=${to} d=0.5 dwell=1`);
    lines.push(
        '[HEV] t=0 ev=state pid=1 from=none to=laning score=0.5 owned=1 why=start',
        '[HEV] t=0 ev=state_start pid=1 state=laning n=1',
        '[HEV] t=12.5 ev=state_task pid=1 state=laning result=fail reason=preempted msg="mode=4" label=hold steps=9',
        '[HEV] t=20 ev=state_start pid=1 state=laning n=2 gap=7.5 after=preempted',
        '[HEV] t=22 ev=lane_pos pid=1 d=120 owned=1 running=1 label=hold mode=1',
        '[HEV] t=50 ev=state pid=1 from=laning to=pull score=0.8 owned=0 why=best',
    );
    const r = stateMetrics(parseLog(lines.sort(byT).join('\n'))[0], { until: 60 }).find(x => x.pid === 1);
    assert.deepStrictEqual([r.secs.laning, r.secs.pull, r.interruptSec, r.compareSec], [50, 10, 10, 50]);
    // laning agrees 0-9, 20-29, 35-39, 41-49; pull (farm) 50-59; farm 30-34 and the blip at 40 do not.
    assert.strictEqual(r.agreeSec, 44);
    assert.deepStrictEqual([r.agreeLongSec, r.compareLongSec], [44, 49]);
    assert.strictEqual(r.switches, 1);
    assert.deepStrictEqual(r.restartLags, [0.5]);
    assert.deepStrictEqual(r.ends, { 'preempted:retreat': 1 });
    assert.deepStrictEqual([r.starts, r.laneDHold], [2, [120]]);
    assert.deepStrictEqual(r.disagree, { 'laning/farm': 6 });
});
