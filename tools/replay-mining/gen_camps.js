'use strict';
// node gen_camps.js [aggregate.json] [camps_data.ts]
// Rewrites only the lines between the BEGIN/END markers in camps_data.ts.

const fs = require('fs');
const path = require('path');

const BEGIN = '// BEGIN GENERATED REPLAY ENTRIES';
const END = '// END GENERATED REPLAY ENTRIES';
const DEFAULT_DATA = path.join(__dirname, '../../typescript/bots/FunLib/humaniser/camps_data.ts');
const DEFAULT_AGG = path.join(__dirname, 'out/aggregate.json');

// Approximate lane centrelines (absolute map coordinates), used only to label a meet point safe/off/mid.
// TODO (in-game/replay): refine against GetLocationAlongLane samples if misclassified camps show up.
const LANES = {
    top: [[-6500, -5500], [-6500, 5500], [-5500, 6000], [5500, 6000]],
    mid: [[-6000, -6000], [6000, 6000]],
    bot: [[6500, 5500], [6500, -5500], [5500, -6000], [-5500, -6000]],
};

function distToSegment(p, a, b) {
    const dx = b[0] - a[0];
    const dy = b[1] - a[1];
    const t = Math.max(0, Math.min(1, ((p.x - a[0]) * dx + (p.y - a[1]) * dy) / (dx * dx + dy * dy)));
    return Math.hypot(p.x - (a[0] + t * dx), p.y - (a[1] + t * dy));
}

function laneKindFor(team, p) {
    let bestLane;
    let best = Infinity;
    for (const [lane, pts] of Object.entries(LANES)) {
        for (let i = 0; i + 1 < pts.length; i++) {
            const d = distToSegment(p, pts[i], pts[i + 1]);
            if (d < best) {
                best = d;
                bestLane = lane;
            }
        }
    }
    if (bestLane === 'mid') return 'mid';
    const safeLane = team === 2 ? 'bot' : 'top';
    return bestLane === safeLane ? 'safe' : 'off';
}

const num = (v) => String(Number(v.toFixed(1)));
const vec = (p) => `Vector(${Math.round(p.x)}, ${Math.round(p.y)}, 0)`;
const vecs = (list) => `[${list.map(vec).join(', ')}]`;
const pair = (s) => `[${num(s)}, ${num(s + 30)}]`;

function buildEntry(a) {
    const side = a.team === 2 ? 'radiant' : 'dire';
    const key = `replay_${side}_${a.type}_${Math.round(a.x)}_${Math.round(a.y)}`;
    const f = [`key: "${key}"`, `team: ${a.team}`, `type: "${a.type}"`];
    if (a.meetPoint) f.push(`laneKind: "${laneKindFor(a.team, a.meetPoint)}"`);
    f.push(`near: ${vec(a)}`);
    if (a.aggroSec !== undefined) f.push(`pullAggroSec: ${pair(a.aggroSec)}`);
    if (a.halfAggroSec !== undefined) f.push(`halfAggroSec: ${pair(a.halfAggroSec)}`);
    if (a.stackAggroSec !== undefined) f.push(`stackAggroSec: ${num(a.stackAggroSec)}`);
    if (a.pullPath) f.push(`pullPath: ${vecs(a.pullPath)}`);
    if (a.meetPoint) f.push(`meetPoint: ${vec(a.meetPoint)}`);
    if (a.halfMeetPoint) f.push(`halfMeetPoint: ${vec(a.halfMeetPoint)}`);
    if (a.stackExitPath) f.push(`stackExitPath: ${vecs(a.stackExitPath)}`);
    f.push('source: "replay"');
    return `    { ${f.join(', ')} },`;
}

function run(aggPath = DEFAULT_AGG, dataPath = DEFAULT_DATA) {
    const aggregates = JSON.parse(fs.readFileSync(aggPath, 'utf8'));
    const text = fs.readFileSync(dataPath, 'utf8');
    const b = text.indexOf(BEGIN);
    const e = text.indexOf(END);
    if (b < 0 || e < b) throw new Error(`markers missing or out of order in ${dataPath}`);
    const lines = aggregates
        .filter((a) => a.aggroSec !== undefined || a.stackAggroSec !== undefined)
        .sort((x, y) => (x.team - y.team) || (x.x - y.x) || (x.y - y.y))
        .map(buildEntry);
    const head = text.slice(0, b + BEGIN.length);
    const tail = text.slice(text.lastIndexOf('\n', e) + 1);
    fs.writeFileSync(dataPath, `${head}\n${lines.map((l) => `${l}\n`).join('')}${tail}`);
    const totals = aggregates.reduce((t, a) => ({ stacks: t.stacks + a.samples.stacks, pulls: t.pulls + a.samples.pulls, half: t.half + a.samples.half }), { stacks: 0, pulls: 0, half: 0 });
    console.log(`camps covered: ${lines.length}; samples: ${totals.pulls} pulls, ${totals.half} half pulls, ${totals.stacks} stacks`);
    return { covered: lines.length, ...totals };
}

module.exports = { run, buildEntry, laneKindFor };

if (require.main === module) run(process.argv[2], process.argv[3]);
