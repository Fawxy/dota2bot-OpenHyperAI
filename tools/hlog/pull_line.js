// The pull's line across a batch (plan s5): of the own creeps of each wave the pull's trigger wanted, the share the enemy
// last-hit (wlh), beside the share that died at a camp and our denies; then the older window ledger (every lane creep dying in
// the 75 s from the slot) and the funnel, per arm and as paired on-minus-off differences.
// Usage: node pull_line.js <run> [<run> ...] [--first] [--to 525] [--lead 0] [--win 75] [--strong 6] [--lanes off|safe] [--on on] [--off off] [--json] [--no-ingest]
//   --lead 15 --win 55 narrows each window towards the wanted wave's own deaths (the query's header says how far).
//   Rows come from queries/pull_line.sql (its header defines every column), summed over a team's lanes in a game.
//   Arms       a game's test team is its label's seat (`<run>_<lineup>_<arm>rad|dire_<rep>`); an arm with no seat (the
//              reference arm: every switch off, so both teams are reference) gives a row per team.
//   Rates      per game: wlh = w_lh / w_n, the named line: of the wanted waves' own creeps, the share their heroes last-hit
//              (logs from team-bots c87cd648 on); wcamp = w_camp / w_n died at a camp; wdeny = w_deny / w_n ours denied.
//              The window ledger beside it: lh = o_lh / o_dead (8a's line before the wave line); core = e_lh_core / e_dead (our cores' last hits per creep of
//              theirs); tower = e_tower / e_dead; deny = o_deny / o_dead. A game with no death in a window has no rate.
//   Pairs      an --on game against the --off game of the same run, lineup and repetition, on the on game's seat team. The
//              mean difference, its sd and the 95% interval (Student t). --first reads only each lane's first wanted slot.
//   Strong     the stack-and-pull group's split (families proposal s5), from queries/pull_line_waves.sql: waves a diverted
//              pull of the team took into a camp of at least --strong neutrals (its `nn`; default 6, from the pull rigs: 3 met
//              13 of 61 creeps dead within 1,000 of the camp, 4 met 4 of 36, 5 met 7 of 8, 6 or more 137 of 140). Per arm, the
//              diverted waves under and over the bar, and the wanted waves whose camp the trigger saw at the bar already (`cn`,
//              the off arm's own strong camps). Paired, each on game's strong waves against the same team, lane and wave of
//              its off game, pulled or not: wlh and wcamp on those waves, the pairs with at least one.
//   Lanes      --lanes off keeps only the off lanes' rows (Radiant top, Dire bot), --lanes safe the safe lanes'; with it,
//              --strong is that lane kind's bar (the off lane's hard camp is strong unstacked: slice oha-off-pull).
//   Null       with no on arm: two reference games of one lineup and team (across the runs named), differenced in label
//              order (the spread a pair shows when nothing differs).
'use strict';
const fs = require('fs');
const path = require('path');
const { Store, DB } = require('./store');
const { ingestRuns } = require('./sides');
const { runLabel } = require('./label');

const SQL = fs.readFileSync(path.join(__dirname, 'queries', 'pull_line.sql'), 'utf8');
const WAVE_SQL = fs.readFileSync(path.join(__dirname, 'queries', 'pull_line_waves.sql'), 'utf8');
const WAVE_COUNTS = ['w_n', 'w_lh', 'w_camp'];
const COUNTS = ['wanted', 'started', 'hit', 'diverted', 'o_dead', 'o_lh', 'o_lh_core', 'o_deny', 'o_tower', 'o_other', 'e_dead', 'e_lh', 'e_lh_core', 'e_deny', 'e_tower', 'e_other', 'w_n', 'w_lh', 'w_lh_core', 'w_deny', 'w_tower', 'w_other', 'w_camp'];
const RATES = { wlh: ['w_lh', 'w_n'], wcamp: ['w_camp', 'w_n'], wdeny: ['w_deny', 'w_n'], lh: ['o_lh', 'o_dead'], core: ['e_lh_core', 'e_dead'], tower: ['e_tower', 'e_dead'], deny: ['o_deny', 'o_dead'] };
// Two-sided 95% Student t by degrees of freedom.
const T95 = [NaN, 12.706, 4.303, 3.182, 2.776, 2.571, 2.447, 2.365, 2.306, 2.262, 2.228, 2.201, 2.179, 2.16, 2.145, 2.131, 2.12, 2.11, 2.101, 2.093, 2.086];

/** One entry per game and team: the query's lane rows summed, with the label's parts and that team's wave rows (`waves`,
 *  from pull_line_waves.sql). `labels` maps game_id to its label. */
function teamGames(rows, labels, waveRows = []) {
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
    for (const g of out) {
        for (const [k, [n, d]] of Object.entries(RATES)) g[k] = g[d] > 0 ? g[n] / g[d] : null;
        g.waves = [];
    }
    for (const w of waveRows) by.get(`${w.game_id}:${w.team}`)?.waves.push(w);
    return out;
}

const OFF_LANE = { 2: 1, 3: 3 };
/** Whether a row (team 2 or 3, lane 1 to 3) is of the lane kind `lanes` names (off, safe); every row without one. */
const laneKind = (r, lanes) => !lanes || (lanes === 'off' ? OFF_LANE[r.team] === r.lane : r.lane !== 2 && OFF_LANE[r.team] !== r.lane);
const isStrong = (w, strong) => w.diverted && w.nn !== null && w.nn !== undefined && w.nn >= strong;

/** Sums of the wave counts over `waves`, with wlh and wcamp. */
function waveSums(waves) {
    const s = { waves: waves.length };
    for (const c of WAVE_COUNTS) s[c] = waves.reduce((a, w) => a + w[c], 0);
    s.wlh = s.w_n > 0 ? s.w_lh / s.w_n : null;
    s.wcamp = s.w_n > 0 ? s.w_camp / s.w_n : null;
    return s;
}

/** Each pair whose on game pulled at least one wave into a strong camp: those waves, and the same lane and wave of the off game. */
function strongPairs(ps, strong) {
    const out = [];
    for (const p of ps) {
        const on = p.on.waves.filter((w) => isStrong(w, strong));
        if (on.length === 0) continue;
        const keys = new Set(on.map((w) => `${w.lane}:${w.wave}`));
        out.push({ on: waveSums(on), off: waveSums(p.off.waves.filter((w) => keys.has(`${w.lane}:${w.wave}`))), label: p.on.label, team: p.on.team });
    }
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

/** Reference games of one lineup and team across the runs named, taken two at a time in label order. */
function nullPairs(games, off) {
    const groups = new Map();
    for (const g of games) {
        if (g.arm !== off) continue;
        const k = `${g.lineup}:${g.team}`;
        groups.set(k, [...(groups.get(k) || []), g]);
    }
    const out = [];
    for (const list of groups.values()) {
        list.sort((x, y) => (x.label < y.label ? -1 : 1));
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

function report(games, { on, off, strong = 6 }) {
    const out = [];
    const side = (g) => (seatTeam(g) === null ? 'both' : seatTeam(g) === g.team ? 'test' : 'opp');
    const groups = new Map();
    for (const g of games) {
        const k = `${g.arm} ${side(g)}`;
        groups.set(k, [...(groups.get(k) || []), g]);
    }
    out.push('arm side    team-games  wanted started hero-hit diverted | ours dead: enemy-lh deny tower other | theirs dead: our-lh (cores) deny tower other | wave: creeps enemy-lh (cores) deny tower other at-camp | wlh lh/dead core/dead  (per team-game, rates pooled)');
    for (const [k, list] of [...groups].sort()) {
        const p = pooled(list);
        const per = (c) => f1(p[c] / p.games);
        out.push(`${k.padEnd(11)} ${String(p.games).padStart(4)}       ${per('wanted')} ${per('started')} ${per('hit')} ${per('diverted')} | ${per('o_dead')}: ${per('o_lh')} ${per('o_deny')} ${per('o_tower')} ${per('o_other')} | ${per('e_dead')}: ${per('e_lh')} (${per('e_lh_core')}) ${per('e_deny')} ${per('e_tower')} ${per('e_other')} | ${per('w_n')}: ${per('w_lh')} (${per('w_lh_core')}) ${per('w_deny')} ${per('w_tower')} ${per('w_other')} ${per('w_camp')} | ${f2(p.wlh)} ${f2(p.lh)}  ${f2(p.core)}`);
    }
    out.push('', `strong camp (a diverted pull met ${strong} or more neutrals): arm side | diverted under the bar: waves creeps wlh wcamp | at or over: waves creeps wlh wcamp | wanted waves with the camp at the bar when the trigger read it (cn), of wanted`);
    for (const [k, list] of [...groups].sort()) {
        const ws = list.flatMap((g) => g.waves);
        const under = waveSums(ws.filter((w) => w.diverted && !isStrong(w, strong)));
        const over = waveSums(ws.filter((w) => isStrong(w, strong)));
        const wanted = ws.filter((w) => w.wanted);
        const ready = wanted.filter((w) => w.cn !== null && w.cn !== undefined && w.cn >= strong).length;
        out.push(`  ${k.padEnd(11)} | ${under.waves} ${under.w_n} ${f2(under.wlh)} ${f2(under.wcamp)} | ${over.waves} ${over.w_n} ${f2(over.wlh)} ${f2(over.wcamp)} | ${ready} of ${wanted.length}`);
    }
    const ps = pairs(games, on, off);
    const title = ps.length > 0 ? `pairs (${on} minus ${off}, the ${on} game's seat team)` : `null pairs (two ${off} games of one lineup and team)`;
    const use = ps.length > 0 ? ps : nullPairs(games, off);
    out.push('', `${title}: ${use.length}`);
    for (const p of use) out.push(`  ${p.on.label} team ${p.on.team} - ${p.off.label}: wlh ${f2(p.on.wlh)} - ${f2(p.off.wlh)}; lh ${f2(p.on.lh)} - ${f2(p.off.lh)} = ${f2(p.on.lh === null || p.off.lh === null ? null : p.on.lh - p.off.lh)}; wanted ${p.on.wanted} / ${p.off.wanted}, started ${p.on.started}, diverted ${p.on.diverted}`);
    for (const r of Object.keys(RATES)) {
        const s = diffStats(use, r);
        out.push(`  ${r.padEnd(5)} n ${s.n}  mean ${f2(s.mean)}  sd ${f2(s.sd)}  95% ${s.half === null ? '-' : `${f2(s.mean - s.half)} to ${f2(s.mean + s.half)}`}`);
    }
    if (ps.length > 0) {
        const sp = strongPairs(ps, strong);
        out.push('', `strong-camp pairs (the on game's waves pulled into ${strong}+ neutrals, against the same waves of its off game): ${sp.length}`);
        for (const p of sp) out.push(`  ${p.label} team ${p.team}: ${p.on.waves} waves; wlh ${f2(p.on.wlh)} - ${f2(p.off.wlh)} (creeps ${p.on.w_n} / ${p.off.w_n}); wcamp ${f2(p.on.wcamp)} - ${f2(p.off.wcamp)}`);
        for (const r of ['wlh', 'wcamp']) {
            const s = diffStats(sp, r);
            out.push(`  ${r.padEnd(5)} n ${s.n}  mean ${f2(s.mean)}  sd ${f2(s.sd)}  95% ${s.half === null ? '-' : `${f2(s.mean - s.half)} to ${f2(s.mean + s.half)}`}`);
        }
    }
    return out.join('\n');
}

function main(argv) {
    const o = { runs: [], on: 'on', off: 'off', to: null, first: null, lead: null, win: null, strong: 6 };
    for (let i = 0; i < argv.length; i++) {
        const a = argv[i];
        if (a === '--first') o.first = 1;
        else if (a === '--to') o.to = Number(argv[++i]);
        else if (a === '--lead') o.lead = Number(argv[++i]);
        else if (a === '--win') o.win = Number(argv[++i]);
        else if (a === '--strong') o.strong = Number(argv[++i]);
        else if (a === '--lanes') o.lanes = argv[++i];
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
        const rows = store.query(SQL, { like: `%${run}_%`, to: o.to, win: o.win, lead: o.lead, first: o.first });
        const waves = store.query(WAVE_SQL, { like: `%${run}_%`, to: o.to });
        all.push(...teamGames(rows.filter((r) => laneKind(r, o.lanes)), labels, waves.filter((w) => laneKind(w, o.lanes))));
    }
    store.close();
    if (o.json) console.log(JSON.stringify(all));
    else console.log(report(all, o));
    return 0;
}

if (require.main === module) process.exit(main(process.argv.slice(2)));
module.exports = { laneKind, teamGames, pairs, nullPairs, diffStats, strongPairs, report };
