// Validity check for a dotactl batch manifest (WO-016 rule, WO-021): per game, the lineup (heroes and positions per team,
// master docs/team/lineups.md), the build stamp, every --set key of the game's arm, that the arm's state layer ran or did not,
// and that the game reached --until. The arm's --set keys must match exactly (none missing, none extra). Prints ok or the problems per game; exit 1 if any game has a problem.
// Usage: node lineup_check.js <manifest> <build> [--lineups <json>] [--arms <json>] [--until 1200]
'use strict';

const fs = require('fs');
const { readManifest } = require('./manifest');

// Lineups A/B/C (seeds 30, 8, 25): heroes by position 1-5, Radiant (2) and Dire (3).
const LINEUPS = {
    A: { 2: ['luna', 'sniper', 'pudge', 'earthshaker', 'jakiro'], 3: ['dragon_knight', 'zuus', 'sand_king', 'bounty_hunter', 'lich'] },
    B: { 2: ['sven', 'lion', 'tiny', 'warlock', 'witch_doctor'], 3: ['skeleton_king', 'oracle', 'bristleback', 'lich', 'omniknight'] },
    C: { 2: ['nevermore', 'necrolyte', 'windrunner', 'lich', 'lion'], 3: ['skeleton_king', 'dragon_knight', 'axe', 'bane', 'witch_doctor'] },
};
// Seeds that give each lineup in `--mode bots` (lineups.md).
const SEEDS = { A: 30, B: 8, C: 25 };
// Per arm: every --set the arm passes, and whether ev=state lines (the state layer) must appear.
const ARMS = {
    off: { set: ['Humaniser.Enable=false', 'Humaniser.States.Enable=false'], states: false },
    on: { set: ['Humaniser.States.Teams=all', 'Humaniser.Lane.OwnLaningThink=all'], states: true },
};

/** Problems with one game's log text (empty when valid). */
function checkGame(text, { lineup, arm, build, until = 1200, lineups = LINEUPS, arms = ARMS }) {
    const p = [];
    const pos = {}; // last ev=bot line per pid wins (a role change re-emits it)
    for (const m of text.matchAll(/ev=bot pid=(\d+) hero=(\w+) team=(\d) .*?build=(\S+) pos=(\d)/g)) {
        pos[m[1]] = { hero: m[2], team: Number(m[3]), build: m[4], pos: Number(m[5]) };
    }
    const bots = Object.values(pos);
    if (bots.length !== 10) p.push(`${bots.length} bots`);
    const want = lineups[lineup];
    if (!want) p.push(`unknown lineup ${lineup}`);
    for (const b of bots) {
        if (want && want[b.team][b.pos - 1] !== b.hero) p.push(`${b.hero} team ${b.team} pos ${b.pos}`);
        if (!b.build.startsWith(build)) p.push(`build ${b.build}`);
    }
    const spec = arms[arm];
    const set = (text.match(/ev=start [^\n]*?set="([^"]*)"/) || [, ''])[1];
    const states = (text.match(/ ev=state /g) || []).length;
    if (!spec) p.push(`unknown arm ${arm}`);
    else {
        const given = set.split(/[,\s]+/).filter(Boolean);
        const missing = spec.set.filter(k => !given.includes(k));
        if (missing.length) p.push(`${arm} arm: --set lacks ${missing.join(', ')} (set="${set}")`);
        // The arm's --set line exactly (WO-016): an extra key, such as an Enable=false on ON, is a different arm.
        const extra = given.filter(k => !spec.set.includes(k));
        if (extra.length) p.push(`${arm} arm: --set has extra ${extra.join(', ')} (set="${set}")`);
        if (spec.states !== states > 0) p.push(`${arm} arm: ev=state ${states}`);
    }
    const stop = text.match(/\[DOTACTL\] t=([\d.]+) ev=stop/);
    if (!stop || Number(stop[1]) < until) p.push(`stopped at t=${stop ? stop[1] : '?'}`);
    return [...new Set(p)];
}

function main(argv) {
    const opt = k => (argv.includes(`--${k}`) ? argv[argv.indexOf(`--${k}`) + 1] : undefined);
    const [manifest, build] = argv;
    if (!manifest || !build) {
        console.error('usage: node lineup_check.js <manifest> <build> [--lineups <json>] [--arms <json>] [--until 1200]');
        process.exit(2);
    }
    const lineups = opt('lineups') ? JSON.parse(fs.readFileSync(opt('lineups'), 'utf8')) : LINEUPS;
    const arms = opt('arms') ? JSON.parse(fs.readFileSync(opt('arms'), 'utf8')) : ARMS;
    const until = Number(opt('until') || 1200);
    let bad = 0;
    for (const g of readManifest(manifest)) {
        const p = checkGame(fs.readFileSync(g.log, 'utf8'), { lineup: g.lineup, arm: g.arm, build, until, lineups, arms });
        console.log(`${g.label.padEnd(14)} ${p.length ? p.join('; ') : 'ok'}`);
        if (p.length) bad++;
    }
    process.exit(bad ? 1 : 0);
}

if (require.main === module) main(process.argv.slice(2));

module.exports = { checkGame, LINEUPS, SEEDS, ARMS };
