// The cast read (fighting-together "Tools", D19): in kill chances that a side's heroes attacked, what the attackers cast, at
// whom, and what they had ready and did not cast. Fights are kill_chances.js's chances (an enemy at 40% HP or less with
// one of the side within 1,000); members are the chance's hunters whose snapshot `tid` names the low hero in [t, t + 8].
// Needs logs from slice cast-read on (ev=cast `cl`, ev=snap `rdy`); a game without them is left out and counted.
// Usage: node cast_read.js <run> [<run> ...] [--null <run> ...] [--until 720] [--json] [--no-ingest]
//   --null <runs>  OHA against OHA runs: a `mirror` column, both seats per game
// Lines, per side: `two+` fights with two or more members, `one` with one; per game, and the share where the target died
// in 12 s. Then per fight, the members' casts in [t - 3, t + 12] by class (k hard disable or immunity, u ultimate, d
// damage, o other) and the share of k, u and d casts aimed at the target (the cast's location within 300 of its
// snapshot that second; a no-target cast has no location: `none`); the fights where a member had a k ready at t, and of
// those the share where a member cast a k at the target; per fight, the k, u and d spells a member had ready at t and
// did not cast in the window.
'use strict';
const fs = require('fs');
const { Store, DB, LOGS, JOBS } = require('./store');
const { rows: chanceRows } = require('./kill_chances');

const BEFORE = 3;
const AFTER = 12;
const AT = 300;
const CLASSES = ['k', 'u', 'd', 'o'];

function args(argv) {
    const o = { runs: [], null: [], until: 720 };
    let into = o.runs;
    for (let i = 0; i < argv.length; i++) {
        const a = argv[i];
        if (a === '--null') into = o.null;
        else if (a === '--until') o.until = Number(argv[++i]);
        else if (a === '--json') o.json = true;
        else if (a === '--no-ingest') o.noIngest = true;
        else if (a === '--help' || a === '-h') o.help = true;
        else into.push(a);
    }
    return o;
}

/** `name:class;...` as [{ n, c }]. */
const parseReady = (s) => (s ? String(s).split(';').filter(Boolean).map((p) => { const i = p.lastIndexOf(':'); return { n: p.slice(0, i), c: p.slice(i + 1) }; }) : []);

/**
 * One game's fights. `chances` the game's kill_chances rows (one per hunter), `casts` its ev=cast rows {pid, t, ab, cl,
 * x, y}, `snaps` {pid, team, sec, x, y, alive, rdy} (one per hero and second). Returns one fight per chance with a member.
 */
function readGame(chances, casts, snaps) {
    const at = new Map(); // sec -> [{pid, team, x, y}]
    const ready = new Map(); // pid|sec -> rdy
    for (const s of snaps) {
        if (s.alive && s.x !== null && s.x !== undefined) {
            if (!at.has(s.sec)) at.set(s.sec, []);
            at.get(s.sec).push(s);
        }
        ready.set(`${s.pid}|${s.sec}`, s.rdy);
    }
    const teamOf = new Map(snaps.map((s) => [s.pid, s.team]));
    const readyAt = (pid, t) => {
        for (let k = 0; k <= 2; k++) if (ready.has(`${pid}|${t - k}`)) return parseReady(ready.get(`${pid}|${t - k}`));
        return [];
    };
    const aim = (c, tpid) => {
        if (c.x === null || c.x === undefined) return 'none';
        let best;
        let bd = AT;
        for (const h of at.get(Math.round(c.t)) || []) {
            const d = Math.hypot(h.x - c.x, h.y - c.y);
            if (d <= bd) { bd = d; best = h; }
        }
        if (!best) return 'ground';
        if (best.pid === tpid) return 'target';
        if (best.pid === c.pid) return 'self';
        return teamOf.get(best.pid) === teamOf.get(c.pid) ? 'ally' : 'enemy';
    };
    const byChance = new Map();
    for (const r of chances) {
        const k = `${r.pid}|${r.t}`;
        if (!byChance.has(k)) byChance.set(k, { label: r.label, side: r.side, tpid: r.pid, t: r.t, died: !!r.died, members: [] });
        if (r.hatk) byChance.get(k).members.push({ pid: r.hpid, pos: r.hpos });
    }
    const out = [];
    for (const f of byChance.values()) {
        if (!f.members.length) continue;
        for (const m of f.members) {
            m.ready = readyAt(m.pid, f.t);
            m.casts = casts.filter((c) => c.pid === m.pid && c.t >= f.t - BEFORE && c.t <= f.t + AFTER)
                .map((c) => ({ ab: c.ab, cl: c.cl || 'o', at: aim(c, f.tpid) }));
            const cast = new Set(m.casts.map((c) => c.ab));
            m.unused = m.ready.filter((s) => s.c !== 'o' && !cast.has(s.n));
        }
        out.push(f);
    }
    return out;
}

const share = (a, b) => (b ? a / b : NaN);

/** The lines for one side's fights over n games, per kind (`two`: two or more members, `one`). */
function tally(fights, n) {
    const out = {};
    for (const [kind, keep] of [['two', (f) => f.members.length >= 2], ['one', (f) => f.members.length === 1]]) {
        const fs_ = fights.filter(keep);
        const casts = fs_.flatMap((f) => f.members.flatMap((m) => m.casts));
        const aimed = casts.filter((c) => c.cl !== 'o');
        const kReady = fs_.filter((f) => f.members.some((m) => m.ready.some((s) => s.c === 'k')));
        const unused = fs_.flatMap((f) => f.members.flatMap((m) => m.unused));
        const per = {};
        for (const c of CLASSES) per[c] = share(casts.filter((x) => x.cl === c).length, fs_.length);
        const unusedPer = {};
        for (const c of ['k', 'u', 'd']) unusedPer[c] = share(unused.filter((x) => x.c === c).length, fs_.length);
        out[kind] = {
            fights: fs_.length / n,
            n: fs_.length,
            died: share(fs_.filter((f) => f.died).length, fs_.length),
            casts: per,
            atTarget: share(aimed.filter((c) => c.at === 'target').length, aimed.length),
            aimedNone: share(aimed.filter((c) => c.at === 'none').length, aimed.length),
            kReady: share(kReady.length, fs_.length),
            kUsed: share(kReady.filter((f) => f.members.some((m) => m.casts.some((c) => c.cl === 'k' && c.at === 'target'))).length, kReady.length),
            unused: unusedPer,
        };
    }
    return out;
}

/** Fights of the runs' games that carry the cast-read fields; `skipped` the games without them. */
function collect(store, runs, until) {
    const { games, rows } = chanceRows(store, runs, { until });
    const fights = [];
    const used = [];
    const skipped = [];
    for (const g of games) {
        const id = store.query('SELECT game_id FROM games WHERE file = ?', g.file)[0]?.game_id;
        const has = id !== undefined && store.query('SELECT 1 FROM ev_snap WHERE game_id = ? AND rdy IS NOT NULL LIMIT 1', id).length > 0;
        if (!has) { skipped.push(g.label); continue; }
        used.push(g);
        const casts = store.query('SELECT pid, t, ab, cl, x, y FROM ev_cast WHERE game_id = ? AND t <= ?', id, until + AFTER);
        const snaps = store.query(`SELECT s.pid, l.team, s.sec, s.x, s.y, s.alive, s.rdy FROM (
                SELECT pid, CAST(round(t) AS INTEGER) AS sec, x, y, alive, rdy,
                    row_number() OVER (PARTITION BY pid, CAST(round(t) AS INTEGER) ORDER BY seq DESC) AS rn
                FROM ev_snap WHERE game_id = ? AND t <= ?) s
            JOIN lineup l ON l.game_id = ? AND l.pid = s.pid WHERE s.rn = 1`, id, until + AFTER + 1, id);
        fights.push(...readGame(rows.filter((r) => r.file === g.file), casts, snaps));
    }
    return { games: used, fights, skipped };
}

function print(cols, ns) {
    const names = Object.keys(cols);
    const pct = (v) => (Number.isNaN(v) ? '-' : `${Math.round(100 * v)}%`);
    const num = (v) => (Number.isNaN(v) ? '-' : v.toFixed(1));
    const line = (label, f) => console.log(`${label.padEnd(22)} ${names.map((c) => f(cols[c]).padStart(16)).join('')}`);
    console.log(`fights a side's heroes attacked (kill chances); ${names.map((c) => `${c} ${ns[c]} games`).join(', ')}`);
    line('', (c) => names.find((k) => cols[k] === c));
    for (const kind of ['two', 'one']) {
        const k = (c) => c[kind];
        console.log(kind === 'two' ? 'two+ members' : 'one member');
        line('  per game, died', (c) => `${num(k(c).fights)}, ${pct(k(c).died)}`);
        line('  casts k/u/d/o', (c) => CLASSES.map((x) => num(k(c).casts[x])).join('/'));
        line('  k+u+d at target', (c) => pct(k(c).atTarget));
        line('    no location', (c) => pct(k(c).aimedNone));
        line('  k ready at t', (c) => pct(k(c).kReady));
        line('    k cast at target', (c) => pct(k(c).kUsed));
        line('  ready unused k/u/d', (c) => ['k', 'u', 'd'].map((x) => num(k(c).unused[x])).join('/'));
    }
}

if (require.main === module) {
    const o = args(process.argv.slice(2));
    if (o.help || !o.runs.length) {
        console.log(fs.readFileSync(__filename, 'utf8').split('\n').filter((l) => l.startsWith('//')).map((l) => l.slice(3)).join('\n'));
        process.exit(o.runs.length || o.help ? 0 : 2);
    }
    const store = new Store(DB);
    if (!o.noIngest) for (const f of store.ingestAll([LOGS, JOBS].filter((d) => fs.existsSync(d))).failed) console.error(`not ingested: ${f.file}: ${f.error}`);
    const main = collect(store, o.runs, o.until);
    if (main.skipped.length) console.error(`left out (no cast-read fields): ${main.skipped.join(', ')}`);
    if (!main.games.length) throw new Error(`no games with cast-read fields for ${o.runs.join(', ')}`);
    const n = main.games.length;
    const cols = { ours: tally(main.fights.filter((f) => f.side === 'ours'), n), oha: tally(main.fights.filter((f) => f.side === 'oha'), n) };
    const ns = { ours: n, oha: n };
    if (o.null.length) {
        const nul = collect(store, o.null, o.until);
        if (nul.skipped.length) console.error(`--null left out: ${nul.skipped.join(', ')}`);
        if (nul.games.length) { cols.mirror = tally(nul.fights, 2 * nul.games.length); ns.mirror = nul.games.length; }
    }
    if (o.json) console.log(JSON.stringify(cols));
    else print(cols, ns);
}

module.exports = { readGame, tally, parseReady };
