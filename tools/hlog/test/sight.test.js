// sight.js: the model's rules on a synthetic map (built by `map` from ev=vmap lines), and its answers at sight-probe's
// spots on the banked map (rig3, 18/11/2026).
'use strict';
const test = require('node:test');
const assert = require('node:assert');
const fs = require('fs');
const os = require('os');
const path = require('path');
const { execFileSync } = require('child_process');

const SIGHT = path.join(__dirname, '..', 'sight.js');
const run = (env, ...a) => execFileSync(process.execPath, [SIGHT, ...a], { env: { ...process.env, ...env }, encoding: 'utf8' }).trim();

test('sight: range, a height step of two, a tree on the line, a tree at the viewer passed', () => {
    const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'sight-'));
    const map = path.join(dir, 'map.json');
    // 33 cells of 64 a row from -1024; level 2 (passable: a) west of x = 512, level 3 (b) east of it, level 4 (c) past 768.
    const row = Array.from({ length: 33 }, (_, i) => { const x = -1024 + i * 64; return x >= 768 ? 'c' : x >= 512 ? 'b' : 'a'; }).join('');
    const lines = ['[HEV] t=-90 ev=vmap kind=start bx0=-1024 by0=-1024 bx1=1024 by1=1024 step=64 src=api'];
    for (let j = 0; j < 33; j++) lines.push(`[HEV] t=-90 ev=vmap kind=h y=${-1024 + j * 64} x0=-1024 n=33 hex=${row}`);
    lines.push('[HEV] t=-89 ev=vmap kind=t xy=0:0:-400;1:0:30;2:-940:40;3:0:0');
    lines.push('[HEV] t=-88 ev=vmap kind=end rows=33 trees=3');
    const log = path.join(dir, 'probe.log');
    fs.writeFileSync(log, lines.join('\n'));
    const env = { SIGHT_MAP: map };
    assert.match(run(env, 'map', log), /33x33 cells of 64 .* 3 trees/);
    assert.match(run(env, 'see', '-500,200', '400,200'), /^yes/);
    assert.match(run(env, 'see', '-500,200', '600,200'), /^yes/, 'one level up does not block');
    assert.match(run(env, 'see', '-500,200', '900,200'), /^no: height/);
    assert.match(run(env, 'see', '-500,-400', '500,-400'), /^no: tree at 0,-400/);
    assert.match(run(env, 'see', '-900,40', '0,40'), /^no: tree at 0,30/, 'the tree at 0,30 on the line blocks; (0,0) is no tree');
    assert.match(run(env, 'see', '-940,100', '-300,100'), /^yes/, 'the tree at the viewer\'s feet is passed');
    assert.match(run(env, 'see', '-500,200', '400,200', '--night'), /^no: range/);
    fs.rmSync(dir, { recursive: true, force: true });
});

test('sight: the banked map answers sight-probe\'s spots from the cast as rig3 saw them', () => {
    const at = '2118,-5585';
    assert.match(run({}, 'see', at, '2200,-5100'), /^yes/, 'open');
    assert.match(run({}, 'see', at, '1780,-4900'), /^no: tree/, 'trees');
    assert.match(run({}, 'see', at, '1474,-5644'), /^no/, 'high');
    assert.match(run({}, 'see', at, '2180,-3409'), /^no: range/, 'far');
});
