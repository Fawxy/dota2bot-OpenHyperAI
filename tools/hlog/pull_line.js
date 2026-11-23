// ROADMAP 8a's line across a batch (plan s5): enemy last hits per creep of ours that died in the 75 s from a slot the pull's
// trigger wanted, with the other lines of that ledger and the funnel, per arm and as paired on-minus-off differences.
// Usage: node pull_line.js <run> [<run> ...] [--first] [--to 525] [--on on] [--off off] [--json] [--no-ingest]
//   Rows come from queries/pull_line.sql (its header defines every column), summed over a team's lanes in a game.
//   Arms       a game's test team is its label's seat (`<run>_<lineup>_<arm>rad|dire_<rep>`); an arm with no seat (the
//              reference arm: every switch off, so both teams are reference) gives a row per team.
//   Rates      per game: lh = o_lh / o_dead (the named line); core = e_lh_core / e_dead (our cores' last hits per creep of
//              theirs); tower = e_tower / e_dead; deny = o_deny / o_dead. A game with no death in a window has no rate.
//   Pairs      an --on game against the --off game of the same run, lineup and repetition, on the on game's seat team. The
//              mean difference, its sd and the 95% interval (Student t). --first reads only each lane's first wanted slot.
//   Null       with no on arm: two reference games of one run, lineup and team, differenced in repetition order (the spread a
//              pair shows when nothing differs).
'use strict';
const fs = require('fs');
const path = require('path');
const { Store, DB } = require('./store');
const { ingestRuns } = require('./gold');
const { runLabel } = require('./label');

const SQL = fs.readFileSync(path.join(__dirname, 'queries', 'pull_line.sql'), 'utf8');
const COUNTS = ['wanted', 'started', 'hit', 'diverted', 'o_dead', 'o_lh', 'o_lh_core', 'o_deny', 'o_tower', 'o_other', 'e_dead', 'e_lh', 'e_lh_core', 'e_deny', 'e_tower', 'e_other'];
const RATES = { lh: ['o_lh', 'o_dead'], core: ['e_lh_core', 'e_dead'], tower: ['e_tower', 'e_dead'], deny: ['o_deny', 'o_dead'] };
// Two-sided 95% Student t by degrees of freedom.
const T95 = [NaN, 12.706, 4.303, 3.182, 2.776, 2.571, 2.447, 2.365, 2.306, 2.262, 2.228, 2.201, 2.179, 2.16, 2.145, 2.131, 2.12, 2.11, 2.101, 2.093, 2.086];

/** One entry per game and team: the query's lane rows summed, with the label's parts. `labels` maps game_id to its label. */
function teamGames(rows, labels) {
    const by = new Map();
    for (const r of rows) {
        const label = labels.get(r.game_id);
        if (label === undefined) continue;
        const key = `${r.game_id}:${r.team}`;
        let g = by.get(key);
        if (!g) {
            g = { game_id: r.game_id, label, team: r.team, ...runLabel(label) };
            for (const c of COUNTS) g[c] = 0;
            by.set(key, g);
        }
        for (const c of COUNTS) g[c] += r[c];
    }
    const out = [...by.values()];
    for (const g of out) for (const [k, [n, d]] of Object.entries(RATES)) g[k] = g[d] > 0 ? g[n] / g[d] : null;
    return out;
}

const seatTeam = (g) => (g.seat === 'rad' ? 2 : g.seat === 'dire' ? 3 : null);

/** Each on game's seat team against the off game of its run, lineup and repetition (the same team there). */
function pairs(games, on, off) {
    const out = [];
    for (const a of games) {
        if (a.arm !== on || seatTeam(a) !== a.team) continue;
        const b = games.find((g) => g.arm === off && g.batch === a.batch && g.lineup === a.lineup && g.rep === a.rep && g.team === a.team
            && (seatTeam(g) === null || seatTeam(g) === g.team));
        if (b) out.push({ on: a, off: b });
    }
    return out;
}

/** Reference games of one run, lineup and team, taken two at a time in repetition order. */
function nullPairs(games, off) {
    const groups = new Map();
    for (const g of games) {
        if (g.arm !== off) continue;
        const k = `${g.batch}:${g.lineup}:${g.team}`;
        groups.set(k, [...(groups.get(k) || []), g]);
    }
    const out = [];
    for (const list of groups.values()) {
        list.sort((x, y) => x.rep - y.rep);
        for (let i = 0; i + 1 < list.length; i += 2) out.push({ on: list[i + 1], off: list[i] });
    }
    return out;
}

/** n, mean, sd and the 95% half-width of the pairs' differences on `rate`; pairs missing a rate are left out. */
function diffStats(ps, rate) {
    const d = ps.filter((p) => p.on[rate] !== null && p.off[rate] !== null).map((p) => p.on[rate] - p.off[rate]);
    const n = d.length;
    if (n === 0) return { n, mean: null, sd: null, half: null };
    const mean = d.reduce((s, x) => s + x, 0) / n;
    const sd = n > 1 ? Math.sqrt(d.reduce((s, x) => s + (x - mean) ** 2, 0) / (n - 1)) : null;
    const t = T95[Math.min(n - 1, T95.length - 1)];
    return { n, mean, sd, half: sd === null ? null : (t * sd) / Math.sqrt(n) };
}

function pooled(list) {
    const s = { games: list.length };
    for (const c of COUNTS) s[c] = list.reduce((a, g) => a + g[c], 0);
    for (const [k, [n, d]] of Object.entries(RATES)) s[k] = s[d] > 0 ? s[n] / s[d] : null;
    return s;
}

const f2 = (x) => (x === null || x === undefined || Number.isNaN(x) ? '-' : x.toFixed(2));
const f1 = (x) => (x === null || x === undefined ? '-' : x.toFixed(1));

function report(games, { on, off }) {
    const out = [];
    const side = (g) => (seatTeam(g) === null ? 'both' : seatTeam(g) === g.team ? 'test' : 'opp');
    const groups = new Map();
    for (const g of games) {
        const k = `${g.arm} ${side(g)}`;
        groups.set(k, [...(groups.get(k) || []), g]);
    }
    out.push('arm side    team-games  wanted started hit diverted | ours dead: enemy-lh deny tower other | theirs dead: our-lh (cores) deny tower other | lh/dead  core/dead  (per team-game, rates pooled)');
    for (const [k, list] of [...groups].sort()) {
        const p = pooled(list);
        const per = (c) => f1(p[c] / p.games);
        out.push(`${k.padEnd(11)} ${String(p.games).padStart(4)}       ${per('wanted')} ${per('started')} ${per('hit')} ${per('diverted')} | ${per('o_dead')}: ${per('o_lh')} ${per('o_deny')} ${per('o_tower')} ${per('o_other')} | ${per('e_dead')}: ${per('e_lh')} (${per('e_lh_core')}) ${per('e_deny')} ${per('e_tower')} ${per('e_other')} | ${f2(p.lh)}  ${f2(p.core)}`);
    }
    const ps = pairs(games, on, off);
    const title = ps.length > 0 ? `pairs (${on} minus ${off}, the ${on} game's seat team)` : `null pairs (two ${off} games of one lineup and team)`;
    const use = ps.length > 0 ? ps : nullPairs(games, off);
    out.push('', `${title}: ${use.length}`);
    for (const p of use) out.push(`  ${p.on.label} team ${p.on.team} - ${p.off.label}: lh ${f2(p.on.lh)} - ${f2(p.off.lh)} = ${f2(p.on.lh === null || p.off.lh === null ? null : p.on.lh - p.off.lh)}; wanted ${p.on.wanted} / ${p.off.wanted}, started ${p.on.started}, diverted ${p.on.diverted}`);
    for (const r of Object.keys(RATES)) {
        const s = diffStats(use, r);
        out.push(`  ${r.padEnd(5)} n ${s.n}  mean ${f2(s.mean)}  sd ${f2(s.sd)}  95% ${s.half === null ? '-' : `${f2(s.mean - s.half)} to ${f2(s.mean + s.half)}`}`);
    }
    return out.join('\n');
}

function main(argv) {
    const o = { runs: [], on: 'on', off: 'off', to: null, first: null };
    for (let i = 0; i < argv.length; i++) {
        const a = argv[i];
        if (a === '--first') o.first = 1;
        else if (a === '--to') o.to = Number(argv[++i]);
        else if (a === '--on') o.on = argv[++i];
        else if (a === '--off') o.off = argv[++i];
        else if (a === '--json') o.json = true;
        else if (a === '--no-ingest') o.noIngest = true;
        else if (a === '--help' || a === '-h') o.help = true;
        else o.runs.push(a);
    }
    if (o.help || o.runs.length === 0) {
        console.log(fs.readFileSync(__filename, 'utf8').split('\n').filter((l) => l.startsWith('//')).map((l) => l.slice(3)).join('\n'));
        return o.help ? 0 : 2;
    }
    const store = new Store(DB);
    if (!o.noIngest) ingestRuns(store, o.runs);
    const all = [];
    for (const run of o.runs) {
        // A log's last game is the run's (a remote log opens with a stub game).
        const gs = store.query(`SELECT g.game_id, g.label FROM games g WHERE g.label LIKE :p ESCAPE '\\'
            AND g.game = (SELECT max(g2.game) FROM games g2 WHERE g2.file = g.file)`, { p: `${run.replace(/_/g, '\\_')}\\_%` });
        const labels = new Map(gs.map((g) => [g.game_id, g.label]));
        const rows = store.query(SQL, { like: `%${run}_%`, to: o.to, win: null, first: o.first });
        all.push(...teamGames(rows, labels));
    }
    store.close();
    if (o.json) console.log(JSON.stringify(all));
    else console.log(report(all, o));
    return 0;
}

if (require.main === module) process.exit(main(process.argv.slice(2)));
module.exports = { teamGames, pairs, nullPairs, diffStats, report };
