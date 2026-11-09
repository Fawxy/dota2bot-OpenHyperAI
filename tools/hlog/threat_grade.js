// Offline grade of the threat read's inputs against what happened (docs/proposals/2026-11-09-fights-and-retreat.md 5.1b):
//   hits    layer 1: every hit our heroes took from an enemy hero, was the hero in the `reach` set two seconds earlier; and the
//           share of hits that came out of fog, with the live missing rule's recall on them
//   deaths  layer 3: for every death of a lineup hero in laning, who could have reached it 5 s before (a death with nobody in
//           reach and no tower or creep cause is a bug in the read, cause `read`)
//   caution layer 1 for Caution.Missing: enemy arrivals near the bot while the rule's count is above 0 against 0
//
//   node tools/hlog/threat_grade.js [hits|deaths|caution|all] [--until 600] [--game N ...] [--json]
//
// Truth is the enemy team's snapshots in the same log (1 s cadence, HP in percent), so games where only one team logs are
// skipped. A hit is an HP drop of at least 8 points between consecutive snapshots of a living hero with an enemy hero within
// HIT_RANGE at the later one; attackers are the enemy heroes within that range. Reach is speed x 2 s + RANGE_PAD (blink and
// teleport are the misses it lists). Vision (what we saw) is rebuilt from our heroes' snapshots only, so towers, wards and
// creeps are missing from it and unseen times are upper bounds.
'use strict';

const { Store } = require('./store');

const args = process.argv.slice(2);
const mode = ['hits', 'deaths', 'caution', 'all'].find(m => args.includes(m)) || 'all';
const opt = (k, d) => { const i = args.indexOf(k); return i < 0 ? d : Number(args[i + 1]); };
const only = args.flatMap((a, i) => (args[i - 1] === '--game' ? [Number(a)] : []));
const UNTIL = opt('--until', 600);
const HIT_DROP = 8;
const HIT_RANGE = 800;
const SPEED = 330;
const RANGE_PAD = 800;
const REACH_2S = SPEED * 2 + RANGE_PAD;
const REACH_5S = SPEED * 5 + RANGE_PAD;
const LOOKBACK = 120;

const night = t => t >= 0 && t % 600 >= 300;
const dist = (a, b) => Math.hypot(a.x - b.x, a.y - b.y);
const teamOf = pid => (pid < 5 ? 2 : 3);

function loadGame(store, g) {
    const snaps = {};
    for (const s of store.query('SELECT pid, t, x, y, hp, alive FROM ev_snap WHERE game_id = ? AND pid < 10 AND t <= ? ORDER BY t', g, UNTIL + 30)) (snaps[s.pid] = snaps[s.pid] || []).push(s);
    if (Object.keys(snaps).length < 10) return undefined;
    const at = (pid, t) => {
        const a = snaps[pid];
        if (!a) return undefined;
        let lo = 0, hi = a.length - 1;
        while (lo < hi) { const m = (lo + hi + 1) >> 1; if (a[m].t <= t) lo = m; else hi = m - 1; }
        return a[lo].t <= t && t - a[lo].t < 3 ? a[lo] : undefined;
    };
    return { snaps, at };
}

/** Last sighting of `enemy` by `team` at or before t, rebuilt from the team's heroes' positions. */
function lastSeen(G, enemy, team, t) {
    for (let u = Math.floor(t); u >= Math.max(t - LOOKBACK, -90); u--) {
        const es = G.at(enemy, u);
        if (!es || !es.alive) return undefined;
        const range = night(u) ? 800 : 1800;
        for (let a = team === 2 ? 0 : 5; a < (team === 2 ? 5 : 10); a++) {
            const as = G.at(a, u);
            if (as && as.alive && dist(as, es) <= range) return { u, x: es.x, y: es.y };
        }
    }
    return undefined;
}

function hits(store, games) {
    const r = { hits: 0, heroHits: 0, towerOrCreep: 0, attackers: 0, inReach: 0, hitsAnyInReach: 0, misses: [], fog: 0, fogCounted: 0, fogNoSighting: 0 };
    for (const g of games) {
        const G = loadGame(store, g);
        if (!G) continue;
        r.games = (r.games || 0) + 1;
        for (let pid = 0; pid < 10; pid++) {
            const a = G.snaps[pid];
            for (let i = 1; i < a.length; i++) {
                const p = a[i - 1], c = a[i];
                if (c.t > UNTIL || !p.alive || !c.alive || c.t - p.t > 2.5 || p.hp - c.hp < HIT_DROP) continue;
                r.hits++;
                const foes = [];
                for (let e = teamOf(pid) === 2 ? 5 : 0; e < (teamOf(pid) === 2 ? 10 : 5); e++) {
                    const es = G.at(e, c.t);
                    if (es && es.alive && dist(es, c) <= HIT_RANGE) foes.push(e);
                }
                if (!foes.length) { r.towerOrCreep++; continue; }
                r.heroHits++;
                let any = false, fogHit = false, fogCounted = false, noSight = false;
                for (const e of foes) {
                    r.attackers++;
                    const before = G.at(e, c.t - 2), me = G.at(pid, c.t - 2);
                    const d = before && me ? dist(before, me) : Infinity;
                    if (d <= REACH_2S) { r.inReach++; any = true; } else r.misses.push({ g, t: c.t, d: Math.round(d) });
                    const seen = lastSeen(G, e, teamOf(pid), c.t - 2);
                    const seenNow = seen && seen.u >= c.t - 2.5;
                    if (!seenNow) {
                        fogHit = true;
                        if (!seen) noSight = true;
                        else {
                            const tss = c.t - 2 - seen.u;
                            if (tss > 3 && dist(seen, c) <= Math.min(SPEED * (tss + 2), 4000) + 600) fogCounted = true;
                        }
                    }
                }
                if (any) r.hitsAnyInReach++;
                if (fogHit) { r.fog++; if (fogCounted) r.fogCounted++; if (noSight) r.fogNoSighting++; }
            }
        }
    }
    return r;
}

function deaths(store, games) {
    const out = { n: 0, byCause: {}, read: [] };
    const gset = new Set(games);
    const cd = require('child_process').execFileSync('node', [require('path').join(__dirname, 'hlog.js'), 'q', '@core_deaths', '--p', 'pos_lo=1', '--p', 'pos_hi=5', '--p', `until=${UNTIL}`, '--json', '--no-ingest'], { maxBuffer: 1 << 28 }).toString();
    const list = JSON.parse(cd);
    const fileGame = {};
    for (const r of store.query('SELECT game_id g, file FROM games')) fileGame[r.file] = r.g;
    let cache = {};
    for (const d of list) {
        const g = fileGame[d.file];
        if (g === undefined || !gset.has(g)) continue;
        const G = cache[g] || (cache = { [g]: loadGame(store, g) })[g];
        if (!G) continue;
        const me = G.at(d.pid, d.t - 5), now = G.at(d.pid, d.t);
        if (!me || !now) continue;
        out.n++;
        let reach = 0, near = 0, fog = 0;
        for (let e = teamOf(d.pid) === 2 ? 5 : 0; e < (teamOf(d.pid) === 2 ? 10 : 5); e++) {
            const b = G.at(e, d.t - 5);
            if (b && b.alive && dist(b, me) <= REACH_5S) {
                reach++;
                const s = lastSeen(G, e, teamOf(d.pid), d.t - 5);
                if (!s || s.u < d.t - 7.5) fog++;
            }
            const n = G.at(e, d.t);
            if (n && n.alive && dist(n, now) <= HIT_RANGE) near++;
        }
        const band = reach === 0 ? 'none' : 'reach';
        const k = (out.byCause[d.cause] = out.byCause[d.cause] || { n: 0, nobodyInReach: 0, heroNearAtDeath: 0, reachMeans: 0, fogReach: 0 });
        k.n++;
        if (band === 'none') { k.nobodyInReach++; out.read.push({ g, t: d.t, pid: d.pid, cause: d.cause, near }); }
        if (near > 0) k.heroNearAtDeath++;
        if (reach > 0) k.reachMeans++;
        if (fog > 0) k.fogReach++;
    }
    return out;
}

function caution(store, games) {
    const out = { with: { n: 0, near: 0 }, without: { n: 0, near: 0 }, byCount: {} };
    for (const g of games) {
        const G = loadGame(store, g);
        if (!G) continue;
        const ev = store.query('SELECT t, pid, missing FROM ev_tr_caution WHERE game_id = ? ORDER BY t', g);
        const by = {};
        for (const e of ev) (by[e.pid] = by[e.pid] || []).push(e);
        for (const pid of Object.keys(by).map(Number)) {
            if (pid > 9) continue;
            const steps = by[pid];
            const missingAt = t => { let m = 0; for (const s of steps) { if (s.t <= t) m = s.missing; else break; } return m; };
            // the rule only reports while laning and alone/missing; sample the 60-second window around a lane's first reports only
            const first = steps[0].t, last = Math.min(UNTIL, steps[steps.length - 1].t + 30);
            for (let t = Math.max(first, 0); t <= last; t += 5) {
                const me = G.at(pid, t);
                if (!me || !me.alive) continue;
                let near = false;
                for (let u = t; u <= t + 15 && !near; u++) {
                    const m2 = G.at(pid, u);
                    if (!m2) break;
                    for (let e = teamOf(pid) === 2 ? 5 : 0; e < (teamOf(pid) === 2 ? 10 : 5); e++) { const es = G.at(e, u); if (es && es.alive && dist(es, m2) <= 1000) { near = true; break; } }
                }
                // visible enemies would explain the arrival: count only arrivals from heroes unseen at t
                let fogNear = false;
                if (near) {
                    for (let u = t; u <= t + 15 && !fogNear; u++) {
                        const m2 = G.at(pid, u);
                        if (!m2) break;
                        for (let e = teamOf(pid) === 2 ? 5 : 0; e < (teamOf(pid) === 2 ? 10 : 5); e++) {
                            const es = G.at(e, u);
                            if (es && es.alive && dist(es, m2) <= 1000) { const s = lastSeen(G, e, teamOf(pid), t); if (!s || s.u < t - 2.5) { fogNear = true; break; } }
                        }
                    }
                }
                const m = missingAt(t);
                const k = m > 0 ? out.with : out.without;
                k.n++;
                if (fogNear) k.near++;
                const c = (out.byCount[Math.min(m, 3)] = out.byCount[Math.min(m, 3)] || { n: 0, near: 0 });
                c.n++;
                if (fogNear) c.near++;
            }
        }
    }
    return out;
}

function main() {
    const store = new Store();
    const games = only.length ? only : store.query("SELECT DISTINCT game_id g FROM ev_tr_caution").map(r => r.g).filter(g => store.query('SELECT 1 FROM ev_snap WHERE game_id = ? AND pid = 9 LIMIT 1', g).length);
    const res = {};
    if (mode === 'hits' || mode === 'all') res.hits = hits(store, games);
    if (mode === 'deaths' || mode === 'all') res.deaths = deaths(store, games);
    if (mode === 'caution' || mode === 'all') res.caution = caution(store, games);
    if (args.includes('--json')) console.log(JSON.stringify(res, null, 1));
    else {
        const f = (a, b) => (b ? (a / b).toFixed(2) : '-');
        console.log(`games ${games.length}, until ${UNTIL} s`);
        if (res.hits) {
            const h = res.hits;
            console.log(`hits: ${h.hits} HP drops >= ${HIT_DROP}: ${h.heroHits} with an enemy hero within ${HIT_RANGE} (${h.towerOrCreep} tower/creep only)`);
            console.log(`  reach recall: attackers in reach 2 s before ${h.inReach}/${h.attackers} = ${f(h.inReach, h.attackers)}; hits with some attacker in reach ${f(h.hitsAnyInReach, h.heroHits)}; misses (beyond ${REACH_2S}): ${h.misses.length}`);
            console.log(`  out of fog: ${h.fog}/${h.heroHits} hits (${f(h.fog, h.heroHits)}); live missing rule covered ${f(h.fogCounted, h.fog)} of them; no sighting in ${LOOKBACK} s: ${h.fogNoSighting}`);
        }
        if (res.deaths) {
            console.log(`deaths (lineup pos 1-5, laning, enemy snapshots present): ${res.deaths.n}`);
            for (const [c, k] of Object.entries(res.deaths.byCause)) console.log(`  ${c.padEnd(10)} n=${k.n} nobody in reach 5 s before: ${k.nobodyInReach}; hero within ${HIT_RANGE} at death: ${k.heroNearAtDeath}; some reach hero was unseen: ${k.fogReach}`);
        }
        if (res.caution) {
            const c = res.caution;
            console.log(`caution: fog arrivals within 15 s (enemy within 1000 of the bot, unseen at the sample): missing>0 ${f(c.with.near, c.with.n)} (n ${c.with.n}), missing=0 ${f(c.without.near, c.without.n)} (n ${c.without.n})`);
            for (const [m, k] of Object.entries(c.byCount)) console.log(`  missing ${m}${m === '3' ? '+' : ''}: ${f(k.near, k.n)} (n ${k.n})`);
        }
    }

}

if (require.main === module) main();
module.exports = { hits, deaths, caution, loadGame, lastSeen };
