// Stack attempts (slice 4, KR S.2a): every ev=stack line before --until, one per trigger minute, with the per-game and
// pooled counts the ER's bars read (nf.js stack_* keys), so each attempt that was not stacked can be listed with its cause.
// Reads the log store (queries/stack_rows.sql over the stack_attempts view); a field the log left out or wrote as ? prints ?.
// Usage: node stacks.js <manifest | log...> [--until 660] [--json]
'use strict';

const path = require('path');
const { stackAttempts } = require('./dynamic');
const { logsFrom } = require('./lasthit_cause');

// A section prints when the log has any of its fields (a ? or absent field is NULL in the store, so the first one cannot say).
const any = (s, keys) => keys.some(k => s[k] !== undefined);
const clock = t => `${Math.floor(t / 60)}:${String(Math.floor(t % 60)).padStart(2, '0')}`;

/** Per log whose first game has ev=bot lines: { file (as given), attempts } of that game (the store is asked by absolute path,
 *  as in games.file). A log without ev=bot is left out, as gamesFrom left out a game without bots. */
function stacks(store, files, until) {
    if (!store.kinds.has('ev_bot')) return [];
    return files.filter(f => store.query('SELECT 1 FROM games g WHERE g.file = ? AND g.game = 1 AND EXISTS (SELECT 1 FROM ev_bot b WHERE b.game_id = g.game_id)', path.resolve(f)).length)
        .map(file => ({ file, attempts: stackAttempts(store, path.resolve(file), 1, until) }));
}

function main(argv) {
    const opt = k => (argv.includes(`--${k}`) ? argv[argv.indexOf(`--${k}`) + 1] : undefined);
    const files = logsFrom(argv.filter((a, i) => !a.startsWith('--') && !(i > 0 && argv[i - 1] === '--until')));
    if (!files.length) {
        console.error('usage: node stacks.js <manifest | log...> [--until 660] [--json]');
        process.exit(2);
    }
    const { Store, DB } = require('./store');
    const store = new Store(DB);
    for (const f of store.ingestAll(files).failed) console.error(`not ingested: ${f.file}: ${f.error}`);
    const out = stacks(store, files, Number(opt('until') ?? Infinity));
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
        for (const s of g.attempts) {
            const a = Object.fromEntries(Object.entries(s).map(([k, v]) => [k, v ?? '?']));
            console.log(`  ${clock(a.t)} pid=${a.pid} min=${a.min} ${a.res} why=${a.why}` +
                (a.res === 'skip' ? '' : ` camp=${a.camp} ${a.type} aggro=${a.aggro} before=${a.before} after=${a.after} fresh=${a.fresh} away=${a.away} death=${a.death ? 1 : 0}` +
                (!any(s, ['box59', 'pulled59', 'bot59', 'vis59', 'exit59', 'hitd', 'tgt2', 'tgt59', 'strict59']) ? '' : ` box59=${a.box59} pulled59=${a.pulled59} bot59=${a.bot59} vis59=${a.vis59} exit59=${a.exit59}` +
                    (!any(s, ['hitd', 'tgt2', 'tgt59', 'strict59']) ? '' : ` hitd=${a.hitd} tgt2=${a.tgt2} tgt59=${a.tgt59} strict59=${a.strict59}`)) +
                (!any(s, ['arr', 'hit0', 'dmg', 'react', 'exit', 'hpa', 'hpe', 'hp59', 'casts', 'lane', 'n2', 'n59']) || a.res === 'failed' ? '' : `
      arr=${a.arr} hit0=${a.hit0} dmg=${a.dmg} react=${a.react} exit=${a.exit} hp=${a.hpa}/${a.hpe}/${a.hp59} casts=${a.casts} left59=${a.left59} lane=${a.lane}
      n2=${a.n2}
      n59=${a.n59}`) +
                (s.cause === undefined || a.res === 'failed' ? '' : ` cause=${a.cause}`)));
        }
    }
    const rate = total.started ? `${((100 * total.stacked) / total.started).toFixed(1)}%` : '-';
    console.log(`total: attempts ${total.started}, stacked ${total.stacked} (${rate}), deaths ${total.deaths}, skips ${total.skips}`);
}

if (require.main === module) main(process.argv.slice(2));

module.exports = { stacks };
