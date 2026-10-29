// Audited steals (slice 3, KR H.2): every lane creep an own support (pos4/pos5) last-hit before --until while an own core
// could take it (dynamic.js auditedSteals), one line per case with the support's mode and the cores that could take it,
// so each remaining case can be judged a bug or a metric false positive.
// Usage: node steals.js <manifest | log...> [--until 600] [--json]
'use strict';

const { dynamicMetrics, auditedSteals, series } = require('./dynamic');
const { gamesFrom, logsFrom } = require('./lasthit_cause');

const clock = t => `${Math.floor(t / 60)}:${String(Math.floor(t % 60)).padStart(2, '0')}`;

/** Per game: { file, cases } (cases undefined for a log without ev=creep_death). */
function steals(files, until) {
    return gamesFrom(files).map(([file, game]) => {
        const m = dynamicMetrics(game);
        return { file, cases: until === 600 ? m.audited_steals : auditedSteals(game, series(game), m.lpos, until) };
    });
}

function main(argv) {
    const opt = k => (argv.includes(`--${k}`) ? argv[argv.indexOf(`--${k}`) + 1] : undefined);
    const files = logsFrom(argv.filter((a, i) => !a.startsWith('--') && !(i > 0 && argv[i - 1] === '--until')));
    if (!files.length) {
        console.error('usage: node steals.js <manifest | log...> [--until 600] [--json]');
        process.exit(2);
    }
    const out = steals(files, Number(opt('until') ?? 600));
    if (argv.includes('--json')) return console.log(JSON.stringify(out, null, 1));
    for (const g of out) {
        if (!g.cases) {
            console.log(`${g.file}\n  no ev=creep_death or lineup positions`);
            continue;
        }
        const laning = g.cases.filter(c => c.mode === 'laning').length;
        const ours = g.cases.filter(c => c.mode === 'laning' || c.mode === 'team_roam').length;
        console.log(`${g.file}\n  audited_steals ${g.cases.length} (laning ${laning}, laning or team_roam ${ours})`);
        for (const c of g.cases) {
            const cores = c.cores.map(k => `p${k.core} ${k.attacking ? 'attacking' : `d=${k.d} r=${k.r}`}`).join(', ');
            console.log(`  ${clock(c.t)} t=${c.t} team=${c.team} pid=${c.pid} pos${c.pos} mode=${c.mode}${c.swing !== undefined ? ` swing=${c.swing.toFixed(2)}s` : ''}${c.snapMode !== c.mode ? ` (snap ${c.snapMode})` : ''} ${c.kind} | ${cores}`);
        }
    }
}

if (require.main === module) main(process.argv.slice(2));
module.exports = { steals };
