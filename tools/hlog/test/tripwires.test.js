'use strict';
const test = require('node:test');
const assert = require('node:assert');
const fs = require('fs');
const os = require('os');
const path = require('path');
const { parseLog } = require('../parse');
const { TRIPWIRES, tripwires, tripReport } = require('../checks');

const HOME = { 2: [-7000, -6500], 3: [7000, 6400] };

/**
 * A healthy game as log text, a snapshot every 5 s from -90 to `until`. `edit(snap)` changes one snapshot or returns false
 * to drop it; `ours` is the team with a switch on; `extra` is appended raw.
 */
function log({ until = 620, ours = 2, edit = () => true, extra = [] } = {}) {
    const out = [];
    for (let pid = 0; pid < 10; pid++) {
        const team = pid < 5 ? 2 : 3;
        out.push(`[HEV] t=-90 ev=bot pid=${pid} hero=h${pid} team=${team} build=abc pos=${(pid % 5) + 1} ours=Trade:${team === ours ? 1 : 0},Threat:0`);
    }
    for (let t = -90; t <= until; t += 5) {
        for (let pid = 0; pid < 10; pid++) {
            const team = pid < 5 ? 2 : 3;
            const s = { pid, team, t, alive: 1, deaths: 0, kills: 0 };
            [s.x, s.y] = t < -80 ? HOME[team] : [0, 0];
            s.gold = t < -80 ? 600 : 100;
            s.lh = t < 60 ? 0 : Math.floor(t / 60);
            s.lvl = t < 120 ? 1 : 2;
            s.nw = 600 + Math.round(Math.max(0, t) * 1.46) + (t >= 5 ? 40 : 0) + s.lh * 40;
            if (edit(s) === false) continue;
            const fields = Object.entries(s).filter(([k, v]) => k !== 't' && k !== 'team' && v !== undefined);
            out.push(`[HEV] t=${t} ev=snap ${fields.map(([k, v]) => `${k}=${v}`).join(' ')}`);
        }
    }
    return out.concat(extra).join('\n');
}

const failed = o => tripwires(parseLog(log(o)).pop());
const ids = o => [...new Set(failed(o).map(f => f.id))];
const radiant = f => s => (s.team === 2 ? f(s) : true);

test('a healthy game prints nothing', () => {
    assert.deepStrictEqual(failed(), []);
});

test('eight wires, each with an id and what must be true', () => {
    assert.strictEqual(TRIPWIRES.length, 8);
    assert.strictEqual(new Set(TRIPWIRES.map(w => w.id)).size, 8);
    for (const w of TRIPWIRES) assert.ok(w.what);
});

test('horn_runes: a team without the 0:00 gold fails, named by its seat', () => {
    const f = failed({ edit: radiant(s => { if (s.t >= 5) s.nw -= 40; }) });
    assert.deepStrictEqual(f.map(x => [x.id, x.team, x.side]), [['horn_runes', 2, 'ours']]);
    assert.match(f[0].why, /0 of 5/);
});

test('horn_runes: the other team is judged too', () => {
    const f = failed({ edit: s => { if (s.team === 3 && s.t >= 5) s.nw -= 40; } });
    assert.deepStrictEqual(f.map(x => [x.id, x.team, x.side]), [['horn_runes', 3, 'off']]);
});

test('horn_runes: a rune taken at 0:20 counts, one after 0:30 does not', () => {
    const at = when => radiant(s => { if (s.t >= 5 && s.t < when) s.nw -= 40; });
    assert.deepStrictEqual(ids({ edit: at(20) }), []);
    assert.deepStrictEqual(ids({ edit: at(40) }), ['horn_runes']);
});

test('horn_runes: last-hit gold is not rune gold', () => {
    const edit = radiant(s => { if (s.t >= 5) s.nw -= 40; if (s.t >= 25) { s.lh += 1; s.nw += 40; } });
    assert.deepStrictEqual(ids({ edit }), ['horn_runes']);
});

test('horn_runes: two heroes spending in the same second still leave the team paid', () => {
    const edit = radiant(s => { if (s.pid < 2 && s.t >= 5) s.nw -= 30; });
    assert.deepStrictEqual(ids({ edit }), []);
});

test('horn_runes: a log with no net worth fails as unjudged, not as unpaid', () => {
    const f = failed({ edit: s => { s.nw = undefined; } });
    assert.deepStrictEqual([...new Set(f.map(x => x.id))], ['horn_runes']);
    assert.match(f[0].why, /no net worth/);
});

test('lua_errors: a guarded error and a console error', () => {
    assert.deepStrictEqual(ids({ extra: ['[HEV] t=620 ev=lua_error pid=1 where=Tick n=3 msg="boom"'] }), ['lua_errors']);
    assert.deepStrictEqual(ids({ extra: ['Script Runtime Error: something'] }), ['lua_errors']);
});

test('both_log: a side that logged nothing, and only that wire', () => {
    const f = failed({ edit: s => s.team !== 3 });
    assert.deepStrictEqual(f.map(x => [x.id, x.team]), [['both_log', 3]]);
});

test('both_log: silence longer than any respawn fails, a respawn does not', () => {
    const quiet = (from, to) => ({ edit: s => !(s.pid === 1 && s.t > from && s.t < to) });
    assert.deepStrictEqual(ids(quiet(400, 480)), []);
    assert.deepStrictEqual(ids(quiet(400, 560)), ['both_log']);
    assert.deepStrictEqual(ids(quiet(400, 9999)), ['both_log']);
});

test('start_items: a hero at the horn with all its starting gold', () => {
    assert.deepStrictEqual(ids({ edit: s => { if (s.pid === 1 && s.t <= 0) s.gold = 600; } }), ['start_items']);
});

test('early_death: dated by the last living snapshot', () => {
    const diesAt = t0 => ({
        edit: s => {
            if (s.pid !== 1) return true;
            if (s.t > t0 && s.t < t0 + 15) return false;
            if (s.t > t0) s.deaths = 1;
            return true;
        },
    });
    assert.deepStrictEqual(ids(diesAt(20)), ['early_death']);
    assert.deepStrictEqual(ids(diesAt(45)), []);
});

test('in_base: a minute alive at the fountain fails, a heal does not', () => {
    const home = secs => ({ edit: s => { if (s.pid === 1 && s.t >= 300 && s.t <= 300 + secs) [s.x, s.y] = HOME[2]; } });
    assert.deepStrictEqual(ids(home(35)), []);
    assert.deepStrictEqual(ids(home(90)), ['in_base']);
});

test('lane_xp: level 1 at 5:00', () => {
    assert.deepStrictEqual(ids({ edit: s => { if (s.pid === 1) s.lvl = 1; } }), ['lane_xp']);
});

test('lane_farm: a team with almost no last hits at 5:00', () => {
    const edit = radiant(s => { if (s.lh) { s.nw -= s.lh * 40; s.lh = 0; } });
    assert.deepStrictEqual(ids({ edit }), ['lane_farm']);
});

test('a game that stops before a wire\'s time is not judged by it', () => {
    assert.deepStrictEqual(ids({ until: 120, edit: s => { s.lvl = 1; s.lh = 0; } }), []);
});

test('tripReport: only failures, grouped by wire, arm and side, with the games counted', () => {
    const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'tripwires-'));
    try {
        const game = (label, o) => {
            const file = path.join(dir, `${label}.log`);
            fs.writeFileSync(file, log(o));
            return { label, arm: 'rad', log: file };
        };
        const ok = game('r_A_rad_1');
        assert.deepStrictEqual(tripReport([ok]), { failures: 0, lines: [] });
        const unpaid = { edit: radiant(s => { if (s.t >= 5) s.nw -= 40; }) };
        const r = tripReport([ok, game('r_A_rad_2', unpaid), game('r_A_rad_3', unpaid)]);
        assert.strictEqual(r.failures, 2);
        assert.match(r.lines[0], /^TRIPWIRE horn_runes arm=rad ours: 2 of 3 games/);
        assert.match(r.lines[1], /r_A_rad_2 Radiant: 0 of 5/);
        assert.ok(!r.lines.join('\n').includes('r_A_rad_1'));
    } finally {
        fs.rmSync(dir, { recursive: true, force: true });
    }
});

test('tripReport: a log it cannot read, or with no game in it, is a failure', () => {
    const missing = path.join(os.tmpdir(), 'tripwires-no-such.log');
    const r = tripReport([{ label: 'gone', log: missing }]);
    assert.strictEqual(r.failures, 1);
    assert.match(r.lines[0], /^TRIPWIRE unreadable/);
});

test('tripReport: the last game of a log is judged (a remote log opens with a stub game)', () => {
    const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'tripwires-'));
    try {
        const file = path.join(dir, 'game.log');
        fs.writeFileSync(file, `[HEV] t=500 ev=lua_error pid=1 where=Tick n=1 msg="stub"\n${log()}`);
        assert.deepStrictEqual(tripReport([{ label: 'g', log: file }]).lines, []);
    } finally {
        fs.rmSync(dir, { recursive: true, force: true });
    }
});
