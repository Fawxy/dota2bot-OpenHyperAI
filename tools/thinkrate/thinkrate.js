// Think interval per bot from a bare-script log (bots/bot_generic.lua): median and p90 of the game-time gap between
// consecutive Think calls, pooled over bots, plus the real-time gap. Usage: node thinkrate.js <log>...
'use strict';
const fs = require('fs');

function intervals(text) {
    const last = {}, game = [], real = [];
    for (const m of text.matchAll(/\[THINK\] pid=(\d+) dota=([-\d.]+) game=([-\d.]+) real=([-\d.]+)/g)) {
        const [pid, g, r] = [m[1], Number(m[3]), Number(m[4])];
        const p = last[pid];
        if (p && g > p.g) {
            game.push(g - p.g);
            real.push(r - p.r);
        }
        last[pid] = { g, r };
    }
    return { game, real, bots: Object.keys(last).length };
}

const q = (a, p) => { const s = [...a].sort((x, y) => x - y); return s.length ? s[Math.min(s.length - 1, Math.floor(p * s.length))] : NaN; };

if (require.main === module) {
    for (const f of process.argv.slice(2)) {
        const { game, real, bots } = intervals(fs.readFileSync(f, 'utf8'));
        console.log(`${f}: bots ${bots}, gaps ${game.length}; game-time gap median ${q(game, 0.5).toFixed(4)} p10 ${q(game, 0.1).toFixed(4)} p90 ${q(game, 0.9).toFixed(4)} s; real-time gap median ${q(real, 0.5).toFixed(4)} s`);
    }
}
module.exports = { intervals, q };
