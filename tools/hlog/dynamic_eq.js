// Equality check for retiring dynamic.js into the log store (docs/team/slices/retire-dynamic-a.md, parts A-C): this
// dynamicMetrics (queries) against an older dynamic.js (script, e.g. a team-bots checkout from before the part) on every game of
// the given logs, the whole result deep-equal. Exits 1 on any difference. Deleted with part C.
// Usage: node dynamic_eq.js <old tools/hlog dir> [--db <file>] [log | dir | manifest ...]   (default ~/.dotactl/logs; db in tmp)
'use strict';

const assert = require('assert');
const fs = require('fs');
const os = require('os');
const path = require('path');
const { Store, LOGS } = require('./store');
const { parseLog } = require('./parse');
const D = require('./dynamic');

/** The old module's result in this one's shape: part A added `deaths_total`. */
function oldMetrics(OLD, game) {
    const m = OLD.dynamicMetrics(game);
    if (OLD.deathTimes) m.deaths_total = OLD.deathTimes(OLD.series(game)).length;
    return m;
}

function main(argv) {
    const db = argv.includes('--db') ? argv[argv.indexOf('--db') + 1] : path.join(os.tmpdir(), 'hlog-dynamic-eq.sqlite');
    const rest = argv.slice(1).filter((a, i, all) => a !== '--db' && all[i - 1] !== '--db');
    if (!argv[0] || !fs.existsSync(path.join(argv[0], 'dynamic.js'))) {
        console.error('usage: node dynamic_eq.js <old tools/hlog dir> [--db <file>] [log | dir | manifest ...]');
        process.exit(2);
    }
    const OLD = require(path.resolve(argv[0], 'dynamic.js'));
    const store = new Store(db);
    for (const f of store.ingestAll(rest.length ? rest : [LOGS]).failed) console.error(`not ingested: ${f.file}: ${f.error}`);
    const n = { same: 0, differ: 0, bothThrow: 0 };
    const parsed = {};
    for (const g of store.query('SELECT file, game FROM games ORDER BY game_id')) {
        if (!fs.existsSync(g.file)) continue;
        const game = (parsed[g.file] = parsed[g.file] || parseLog(fs.readFileSync(g.file, 'utf8')))[g.game - 1];
        let a, b, ea, eb;
        try { a = oldMetrics(OLD, game); } catch (e) { ea = e.message; }
        try { b = D.dynamicMetrics(store, g.file, g.game, game); } catch (e) { eb = e.message; }
        if (ea && eb) n.bothThrow++;
        else {
            try {
                if (ea || eb) throw new Error(`old ${ea || 'ok'}, new ${eb || 'ok'}`);
                assert.deepStrictEqual(b, a);
                n.same++;
            } catch (e) {
                n.differ++;
                console.log(`${g.file} game ${g.game}: ${e.message.slice(0, 2000)}`);
            }
        }
    }
    console.log(JSON.stringify(n));
    store.close();
    if (n.differ) process.exitCode = 1;
}

if (require.main === module) main(process.argv.slice(2));
