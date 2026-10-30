// Writes a replay (the master replay index's manta extractor NDJSON: one `k=s` row per game second, `k=meta` with players)
// as humaniser [HEV] telemetry, so the log store and dynamicMetrics run on a replay unchanged once its output file is ingested
// (WO-021 R4; EC-058/059 review L8).
// Snapshots are 1 Hz like bot logs, and none are written while a hero is dead (bots log none), so dynamic.js infers deaths
// from gaps exactly as it does for bots. pid = replay player index 0-9.
// Rows stop at the ancient kill (the `_fort` log line), as the replay index's batch_a_analyze.js `load` does, unless --until
// is given.
// Usage: node replay_to_hlog.js <replay.ndjson> <heroes.json (OpenDota constants)> [--until <s>] > replay.log
'use strict';

const fs = require('fs');

// Extractor row columns (replay index batch_a_analyze.js `series`).
const COL = { x: 0, y: 1, hp: 2, alive: 5, lh: 6, kills: 9, deaths: 10, lvl: 15 };

/** NDJSON text + OpenDota heroes constants -> [HEV] lines. */
function replayToHlog(ndjson, heroes, until) {
    const L = ndjson.split('\n').filter(Boolean).map(l => JSON.parse(l));
    const meta = L.find(x => x.k === 'meta');
    if (until === undefined) {
        const forts = L.filter(x => x.k === 'log' && /_fort$/.test(x.tgt)).map(x => x.ts - meta.gameStart);
        until = forts.length ? Math.floor(Math.max(...forts)) : Infinity;
    }
    const name = {};
    for (const h of Object.values(heroes)) name[h.id] = h.name.replace('npc_dota_hero_', '');
    const out = meta.players.map((p, i) => `[HEV] t=-90.000 ev=bot pid=${i} hero=${name[p.heroId]} team=${p.team} schema=2`);
    for (const row of L.filter(x => x.k === 's' && x.t >= 0 && x.t <= until).sort((a, b) => a.t - b.t)) {
        row.p.forEach((r, i) => {
            if (!r || r[COL.alive] !== 1 || r[COL.x] <= -90000) return;
            const f = Object.entries(COL).map(([k, c]) => `${k}=${k === 'alive' ? 1 : Math.round(r[c])}`).join(' ');
            out.push(`[HEV] t=${row.t.toFixed(3)} ev=snap pid=${i} ${f}`);
        });
    }
    return out;
}

if (require.main === module) {
    const [file, heroesFile] = process.argv.slice(2);
    const i = process.argv.indexOf('--until');
    const until = i > 0 ? Number(process.argv[i + 1]) : undefined;
    const heroes = JSON.parse(fs.readFileSync(heroesFile, 'utf8'));
    process.stdout.write(replayToHlog(fs.readFileSync(file, 'utf8'), heroes, until).join('\n') + '\n');
}

module.exports = { replayToHlog, COL };
