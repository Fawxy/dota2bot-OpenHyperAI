'use strict';
const test = require('node:test');
const assert = require('node:assert');
const fs = require('fs');
const os = require('os');
const path = require('path');
const { parseLog } = require('../parse');
const { collect, check } = require('../bars');
const { main } = require('../analyse');

function botLine(pid, pos, team = 2) {
    return `[HEV] t=-60 ev=bot pid=${pid} hero=h${pid} team=${team} schema=2 skill=0.500 build=abc1234 pos=${pos}`;
}

/**
 * Radiant: human pid 0, bots 1-4 at positions 1, 2, 4, 5 (so the human holds 3). Bot 2 (pos 2) reaches `lh2` last
 * hits by 10:00. Extra lines are merged in clock order.
 */
function gameLog({ lh2 = 30, extra = [] } = {}) {
    const lines = ['[HEV] t=-60 ev=player pid=0 hero=abaddon team=2 human=1'];
    const pos = { 1: 1, 2: 2, 3: 4, 4: 5 };
    for (const pid of [1, 2, 3, 4]) lines.push(botLine(pid, pos[pid]));
    for (let t = 0; t <= 620; t += 10) {
        for (const pid of [1, 2, 3, 4]) {
            const lh = pid === 2 ? Math.floor((lh2 * Math.min(t, 600)) / 600) : 0;
            lines.push(`[HEV] t=${t} ev=snap pid=${pid} x=0 y=0 alive=1 hp=100 mp=50 lvl=1 lh=${lh} dn=0 kills=0 deaths=0 mode=laning d=0.3 act=2 gold=600`);
        }
    }
    const all = [...lines, ...extra];
    const t = l => Number((l.match(/t=(\S+)/) || [])[1]);
    return all.sort((a, b) => t(a) - t(b)).join('\n');
}

const metricsOf = (log, until = 600) => collect(parseLog(log).pop(), { until });

test('the human position is the one its team leaves free, so a bar on it has no bot and is missing, not passing', () => {
    const m = metricsOf(gameLog());
    assert.strictEqual(m.game.humanPos, 3);
    const r = check([m], { bars: [{ id: 'p3', select: { team: 'rad', pos: 3 }, metric: 'laning.lh', min: 0 }] });
    assert.strictEqual(r.results[0].status, 'missing');
    assert.strictEqual(r.pass, false);
    const opt = check([m], { bars: [{ id: 'p3', select: { team: 'rad', pos: 3 }, metric: 'laning.lh', min: 0, optional: true }] });
    assert.strictEqual(opt.pass, true);
});

test('runs combine per bar: "each" needs every run, "median" the median run, minRuns guards a single lucky game', () => {
    const runs = [metricsOf(gameLog({ lh2: 30 })), metricsOf(gameLog({ lh2: 16 })), metricsOf(gameLog({ lh2: 24 }))];
    const bar = { id: 'lh10', select: { team: 'rad', pos: 2 }, metric: 'laning.lh', min: 22 };
    assert.strictEqual(check(runs, { bars: [bar] }).results[0].status, 'fail');
    const med = check(runs, { bars: [{ ...bar, over: 'median' }] }).results[0];
    assert.deepStrictEqual([med.status, med.value], ['pass', 24]);
    assert.strictEqual(check(runs.slice(0, 1), { minRuns: 2, bars: [bar] }).results[0].status, 'insufficient');
});

test('a repeating lua error counts its running total once, and only States/Tasks/sdk sites count as the team\'s', () => {
    const extra = [
        '[HEV] t=100 ev=lua_error pid=1 where=States.score.laning n=1 msg="x.lua:3: attempt to index nil"',
        '[HEV] t=200 ev=lua_error pid=1 where=States.score.laning n=10 msg="x.lua:3: attempt to index nil"',
        '[HEV] t=300 ev=lua_error pid=2 where=AllyLastHit.MayLastHit n=1 msg="ally_last_hit.lua:179: Parameter type mismatch"',
        '[HEV] t=700 ev=lua_error pid=2 where=Tasks.tick n=1 msg="late"',
    ];
    const m = metricsOf(gameLog({ extra }));
    assert.deepStrictEqual([m.game.errors.lua, m.game.errors.luaTeam], [11, 10]);
});

test('team aggregates and job metrics: gank attempts summed over a team, stack aggro error spread', () => {
    const extra = [
        '[HEV] t=200 ev=gank pid=3 pos=4 target=8 lane=3 score=2.40 result=fail msg="mode=2" label=travel left=190 away=10',
        '[HEV] t=450 ev=gank pid=3 pos=4 target=8 lane=3 score=2.40 result=ok msg=kill label=fight left=420 away=30',
        '[HEV] t=520 ev=gank pid=2 pos=2 target=9 lane=1 score=2.00 result=fail msg=escaped label=travel left=500 away=20',
        '[HEV] t=113 ev=lane_stack pid=4 camp=2 type=large aggro=53.3 planned=53 stacked=1',
        '[HEV] t=233 ev=lane_stack pid=4 camp=2 type=large aggro=52.5 planned=53 stacked=0',
    ];
    const m = metricsOf(gameLog({ extra }));
    const spec = {
        bars: [
            { id: 'team ganks', select: { team: 'human' }, metric: 'jobs.gankAttempts', agg: 'sum', range: [2, 4] },
            { id: 'pos4 kill', select: { team: 'rad', pos: 4 }, metric: 'jobs.gankFirstKill', range: [390, 580] },
            { id: 'stack rate', select: { team: 'rad', pos: 5 }, metric: 'jobs.stackedPct', min: 70 },
        ],
    };
    const r = check([m], spec);
    assert.deepStrictEqual(r.results.map(x => x.status), ['pass', 'pass', 'fail']);
    const sup = m.bots.find(b => b.pos === 5);
    assert.ok(Math.abs(sup.jobs.aggroErrSd - 0.141) < 0.01);
});

test('check CLI: exit 0 when every bar passes, 1 when one fails, 2 for a spec of the wrong schema', () => {
    const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'hlog-bars-'));
    const log = path.join(dir, 'g.log');
    fs.writeFileSync(log, gameLog({ lh2: 30 }));
    const spec = bars => {
        const f = path.join(dir, `s${Math.random()}.json`);
        fs.writeFileSync(f, JSON.stringify(bars));
        return f;
    };
    const quiet = fn => {
        const orig = [console.log, console.error];
        console.log = console.error = () => {};
        try {
            return fn();
        } finally {
            [console.log, console.error] = orig;
        }
    };
    const pass = spec({ schema: 'hlog-bars/1', bars: [{ select: { team: 'rad', pos: 2 }, metric: 'laning.lh', min: 22 }] });
    const fail = spec({ schema: 'hlog-bars/1', bars: [{ select: { team: 'rad', pos: 2 }, metric: 'laning.lh', min: 40 }] });
    const bad = spec({ schema: 'hlog-bars/0', bars: [{ metric: 'game.maxT', min: 0 }] });
    assert.deepStrictEqual(quiet(() => [main(['check', pass, log]), main(['check', fail, log]), main(['check', bad, log])]), [0, 1, 2]);
});

test('an all-digit build sha stays the string it was, leading zero and all', () => {
    const { parseLine } = require('../parse');
    assert.strictEqual(parseLine('[HEV] t=1 ev=bot pid=1 build=0123456 pos=2').e.build, '0123456');
});

test('a forced game start (pregame clock jumps to 0:00) is not a snapshot gap; a real stall still is', () => {
    const { runChecks } = require('../checks');
    const snap = (t, x = -1000) => `[HEV] t=${t} ev=snap pid=1 x=${x} y=0 alive=1 hp=100 mp=50 lvl=1 lh=0 dn=0 mode=laning d=0.3 act=2 gold=600`;
    const lines = ['[HEV] t=-89 ev=player pid=0 hero=abaddon team=2 human=1', botLine(1, 2)];
    for (let t = -89; t <= -53; t++) lines.push(snap(t));
    for (let t = 0.033; t <= 60; t++) lines.push(snap(t));
    const gaps = log => runChecks(parseLog(log.join('\n'))[0]).find(r => r.id === 'snapshot_gaps');
    assert.strictEqual(gaps(lines).level, 'pass');
    const stalled = lines.filter(l => !/t=(2\d|3\d)\.033 /.test(l));
    assert.strictEqual(gaps(stalled).level, 'fail');
});

test('slice 14 modes: a round trip under 2 s is a blip, a longer visit is not; idle episodes and the layer share count', () => {
    const extra = [
        '[HEV] t=10 ev=mode pid=2 from=laning to=team_roam d=1.5 dwell=10 by="team_roam 1.50 by raw"',
        '[HEV] t=10.5 ev=mode pid=2 from=team_roam to=laning d=0.52 dwell=0.5 by="laning 0.52 by states"',
        '[HEV] t=40 ev=mode pid=2 from=laning to=retreat d=0.8 dwell=29.5 by="retreat 0.80 by raw"',
        '[HEV] t=45 ev=mode pid=2 from=retreat to=laning d=0.52 dwell=5 by="laning 0.52 by states"',
        '[HEV] t=200 ev=mode_idle pid=2 mode=17 secs=12.5 state=farm aside=1',
        '[HEV] t=300 ev=mode_idle pid=2 mode=1 secs=3.2 state=laning aside=0',
    ];
    const bot = metricsOf(gameLog({ extra })).bots.find(b => b.pid === 2);
    assert.strictEqual(bot.modes.switches, 4);
    assert.strictEqual(bot.modes.blips, 1);
    assert.strictEqual(bot.modes.blipsPerMin, 0.1);
    assert.deepStrictEqual([bot.modes.idleEpisodes, bot.modes.idleLong, bot.modes.idleMax, bot.modes.asides], [2, 1, 12.5, 1]);
    assert.strictEqual(bot.modes.layerSetPct, 50);
    const r = check([metricsOf(gameLog({ extra }))], { bars: [{ id: 'idle', select: { team: 'rad' }, metric: 'modes.idleLong', agg: 'max', max: 0 }] });
    assert.strictEqual(r.results[0].status, 'fail');
});
