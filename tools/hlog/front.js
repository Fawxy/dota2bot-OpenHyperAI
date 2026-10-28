// Lane fronts and heroes' places along their lanes at given clocks (slice 2b), from ev=front and ev=snap. The table slice 3
// checks against `--shot` screenshots. Amounts are absolute: 0 = Radiant's ancient, 1 = Dire's.
// Usage: node front.js <log> [--at 4:00,6:00,8:00]
'use strict';

const fs = require('fs');
const { parseLine } = require('./parse');

const LANES = ['top', 'mid', 'bot'];

function seconds(clock) {
    const m = String(clock).match(/^(\d+):(\d\d)$/);
    return m ? Number(m[1]) * 60 + Number(m[2]) : Number(clock);
}

/** Per clock: { t, fronts: { team: ev=front fields }, heroes: [{ pid, hero, team, ln, s, ld, x, y, t }] }, latest at or before t. */
function frontsAt(text, clocks) {
    const events = [];
    for (const line of text.split(/\r?\n/)) {
        const p = parseLine(line);
        if (p && p.line === 'event') events.push(p.e);
    }
    const heroes = {};
    for (const e of events) if (e.ev === 'bot' || e.ev === 'player') heroes[e.pid] = { hero: e.hero, team: e.team };
    return clocks.map(t => {
        const fronts = {}, snaps = {};
        for (const e of events) {
            if (e.t > t) continue;
            if (e.ev === 'front') fronts[e.team] = e;
            if (e.ev === 'snap' && e.ln !== undefined) snaps[e.pid] = e;
        }
        const list = Object.values(snaps).map(e => ({ pid: e.pid, ...(heroes[e.pid] || {}), ln: e.ln, s: e.s, ld: e.ld, x: e.x, y: e.y, t: e.t }));
        return { t, fronts, heroes: list.sort((a, b) => a.pid - b.pid) };
    });
}

function clock(t) {
    const s = Math.round(t);
    return `${Math.floor(s / 60)}:${String(s % 60).padStart(2, '0')}`;
}

function format(rows) {
    const out = [];
    for (const r of rows) {
        out.push(`== ${clock(r.t)}`);
        for (const team of [2, 3]) {
            const f = r.fronts[team];
            out.push(`front team ${team}${f ? ` (t=${f.t})` : ''}: ` +
                (f ? LANES.map(l => `${l} ${f[l]} (${f[`${l}x`]},${f[`${l}y`]})`).join('  ') : 'none'));
        }
        for (const h of r.heroes) out.push(`  pid ${h.pid} ${h.hero || '?'} team ${h.team || '?'}: ${h.ln} s=${h.s} ld=${h.ld} at (${h.x},${h.y}) t=${h.t}`);
    }
    return out.join('\n');
}

if (require.main === module) {
    const argv = process.argv.slice(2);
    if (!argv[0]) {
        console.error('usage: node front.js <log> [--at 4:00,6:00,8:00]');
        process.exit(2);
    }
    const at = argv.includes('--at') ? argv[argv.indexOf('--at') + 1] : '4:00,6:00,8:00';
    console.log(format(frontsAt(fs.readFileSync(argv[0], 'utf8'), at.split(',').map(seconds))));
}

module.exports = { frontsAt, format };
