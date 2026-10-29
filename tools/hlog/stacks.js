// Stack attempts (slice 4, KR S.2a): every ev=stack line before --until, one per trigger minute, with the per-game and
// pooled counts the ER's bars read (nf.js stack_* keys), so each attempt that was not stacked can be listed with its cause.
// Usage: node stacks.js <manifest | log...> [--until 660] [--json]
'use strict';

const { stackAttempts } = require('./dynamic');
const { gamesFrom, logsFrom } = require('./lasthit_cause');

const clock = t => `${Math.floor(t / 60)}:${String(Math.floor(t % 60)).padStart(2, '0')}`;

function stacks(files, until) {
    return gamesFrom(files).map(([file, game]) => ({ file, attempts: stackAttempts(game, until) }));
}

function main(argv) {
    const opt = k => (argv.includes(`--${k}`) ? argv[argv.indexOf(`--${k}`) + 1] : undefined);
    const files = logsFrom(argv.filter((a, i) => !a.startsWith('--') && !(i > 0 && argv[i - 1] === '--until')));
    if (!files.length) {
        console.error('usage: node stacks.js <manifest | log...> [--until 660] [--json]');
        process.exit(2);
    }
    const out = stacks(files, Number(opt('until') ?? Infinity));
    if (argv.includes('--json')) return console.log(JSON.stringify(out, null, 1));
    const total = { started: 0, stacked: 0, deaths: 0, skips: 0 };
    for (const g of out) {
        const started = g.attempts.filter(a => a.res !== 'skip');
        const stacked = started.filter(a => a.res === 'stacked').length;
        total.started += started.length;
        total.stacked += stacked;
        total.deaths += started.filter(a => a.death).length;
        total.skips += g.attempts.length - started.length;
        console.log(`${g.file}\n  attempts ${started.length}, stacked ${stacked}, skips ${g.attempts.length - started.length}`);
        for (const a of g.attempts) {
            console.log(`  ${clock(a.t)} pid=${a.pid} min=${a.min} ${a.res} why=${a.why}` +
                (a.res === 'skip' ? '' : ` camp=${a.camp} ${a.type} aggro=${a.aggro} before=${a.before} after=${a.after} away=${a.away} death=${a.death ? 1 : 0}` +
                (a.box59 === undefined ? '' : ` box59=${a.box59} pulled59=${a.pulled59} bot59=${a.bot59} vis59=${a.vis59} exit59=${a.exit59}` +
                    (a.hitd === undefined ? '' : ` hitd=${a.hitd} tgt2=${a.tgt2} tgt59=${a.tgt59} strict59=${a.strict59}`)) +
                (a.cause === undefined || a.res === 'failed' ? '' : ` cause=${a.cause}`)));
        }
    }
    const rate = total.started ? `${((100 * total.stacked) / total.started).toFixed(1)}%` : '-';
    console.log(`total: attempts ${total.started}, stacked ${total.stacked} (${rate}), deaths ${total.deaths}, skips ${total.skips}`);
}

if (require.main === module) main(process.argv.slice(2));

module.exports = { stacks };
