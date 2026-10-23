#!/usr/bin/env node
// Laning-body evaluation for the team slices (3-6): per bot lh at 2/5/10 min, own-lane share, deaths, HP lost to
// heroes (lane_pos hph), the SDK body's last-hit attempts (ev=lh) and its distance to the spot.
// usage: node tools/hlog/lane_eval.js <log> [--until 600] [--game N] [--json]
'use strict';

const fs = require('fs');
const { parseLog } = require('./parse');

function zoneOf(x, y) {
    if (x < -4500 && y < -4000) return 'base';
    if (x > 4000 && y > 3500) return 'base';
    if (Math.abs(x - y) < 2000) return 'mid';
    if (x < -5000 || y > 5200) return 'top';
    if (x > 5000 || y < -5200) return 'bot';
    if (Math.abs(x + y) < 1600) return 'river';
    return 'jungle';
}

function playedLane(bot) {
    const n = {};
    for (const p of bot.snaps) if (p.t >= 120 && p.t <= 360 && p.alive === 1) {
        const z = zoneOf(p.x, p.y);
        if (z === 'top' || z === 'mid' || z === 'bot') n[z] = (n[z] || 0) + 1;
    }
    return Object.keys(n).sort((a, b) => n[b] - n[a])[0] || '-';
}

function ownLane(bot, until) {
    const lane = playedLane(bot);
    const s = bot.snaps.filter(p => p.t <= until && p.alive === 1);
    if (s.length === 0 || lane === '-') return undefined;
    return Math.round((100 * s.filter(p => zoneOf(p.x, p.y) === lane).length) / s.length);
}

function at(snaps, t, key) {
    let v;
    for (const s of snaps) if (s.t <= t && typeof s[key] === 'number') v = s[key];
    return v;
}

function median(xs) {
    if (xs.length === 0) return undefined;
    const s = xs.slice().sort((a, b) => a - b);
    return s[Math.floor(s.length / 2)];
}

function evaluate(game, until) {
    const rows = [];
    for (const b of Object.values(game.bots)) {
        if (b.human) continue;
        const prof = b.profiles[b.profiles.length - 1] || {};
        const ev = name => game.events.filter(e => e.ev === name && e.pid === b.pid && e.t <= until);
        const lh = ev('lh');
        const pct = (xs, f) => (xs.length ? `${xs.filter(f).length}/${xs.length}` : '-');
        const last = lh.filter(e => e.kind === 'lasthit');
        const den = lh.filter(e => e.kind === 'deny');
        const contested = last.filter(e => e.contested === 1);
        const pos = ev('lane_pos');
        const hph = pos.length ? pos[pos.length - 1].hph : undefined;
        const holdD = pos.filter(e => e.label === 'hold' && typeof e.d === 'number').map(e => e.d);
        const owned = pos.filter(e => e.mode === 1);
        rows.push({
            team: b.team === 2 ? 'rad' : 'dire',
            pos: prof.pos,
            hero: b.hero,
            pid: b.pid,
            lane: playedLane(b),
            ownLane: ownLane(b, until),
            lh2: at(b.snaps, 120, 'lh'),
            lh5: at(b.snaps, 300, 'lh'),
            lh10: at(b.snaps, until, 'lh'),
            dn10: at(b.snaps, until, 'dn'),
            deaths: at(b.snaps, until, 'deaths'),
            hph,
            bodyLH: pct(last, e => e.result === 'ok'),
            contested: pct(contested, e => e.result === 'ok'),
            bodyDN: pct(den, e => e.result === 'ok'),
            lhFail: Object.entries(last.filter(e => e.result !== 'ok').reduce((m, e) => ((m[e.reason] = (m[e.reason] || 0) + 1), m), {}))
                .map(([k, v]) => `${k}:${v}`).join(','),
            holdD: median(holdD),
            running: owned.length ? Math.round((100 * owned.filter(e => e.running === 1).length) / owned.length) : undefined,
        });
    }
    rows.sort((a, b) => (a.team === b.team ? (a.pos || 9) - (b.pos || 9) : a.team < b.team ? 1 : -1));
    return rows;
}

function table(rows) {
    const cols = ['team', 'pos', 'hero', 'pid', 'lane', 'ownLane', 'lh2', 'lh5', 'lh10', 'dn10', 'deaths', 'hph', 'bodyLH', 'contested', 'bodyDN', 'lhFail', 'holdD', 'running'];
    const cells = [cols, ...rows.map(r => cols.map(c => (r[c] === undefined ? '-' : String(r[c]))))];
    const w = cols.map((_, i) => Math.max(...cells.map(r => r[i].length)));
    return cells.map(r => r.map((c, i) => c.padEnd(w[i])).join('  ')).join('\n');
}

function main(argv) {
    const file = argv.find(a => !a.startsWith('--'));
    const opt = k => {
        const i = argv.indexOf('--' + k);
        return i >= 0 ? argv[i + 1] : undefined;
    };
    if (!file) {
        console.error('usage: node tools/hlog/lane_eval.js <log> [--until 600] [--game N] [--json]');
        return 2;
    }
    const games = parseLog(fs.readFileSync(file, 'utf8'));
    const game = games[(Number(opt('game')) || games.length) - 1];
    if (!game) return 1;
    const rows = evaluate(game, Number(opt('until')) || 600);
    console.log(argv.includes('--json') ? JSON.stringify(rows, null, 1) : table(rows));
    return 0;
}

if (require.main === module) process.exit(main(process.argv.slice(2)));
module.exports = { evaluate };
