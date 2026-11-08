// Grades the offlane core's "missing hero" rule (CoreCamp.MissingOf, used by the lane controller's pull candidate) against where
// the enemy heroes really were. Offline, banked logs only (docs/proposals/2026-11-09-fights-and-retreat.md 5.2).
//
//   node tools/hlog/missing_grade.js [--game N ...] [--window 15] [--near 800] [--json]
//
// Per ev=lane_ctl row that evaluated the core pull candidate (cmiss present): the walk is the core's position at t to the offlane
// hard camp (the stand is not logged; the camp's centre stands in for it). Truth: an enemy hero within --near of the walk
// during [t, t+window] (enemy snapshots are in the same log). Last-seen is rebuilt from our heroes' snapshots (an enemy within
// 1800 by day / 800 by night of an alive ally was seen; towers, wards and creeps give no vision here, so time-since-seen is
// an upper bound). Rules graded: the live rule and variants, each as precision of its refusals (some counted hero truly
// present) and as the share of permitted rows where an enemy did show up.
'use strict';

const { Store } = require('./store');

const CAMP = { 2: { x: -4824, y: 3914 }, 3: { x: 4649, y: -3699 } }; // camps_data radiant_off_large / dire_off_large, centres from ev=camp
const VISION_DAY = 1800;
const VISION_NIGHT = 800;
const LOOKBACK = 300;

const args = process.argv.slice(2);
const opt = (k, d) => { const i = args.indexOf(k); return i < 0 ? d : Number(args[i + 1]); };
const games = args.flatMap((a, i) => (args[i - 1] === '--game' ? [Number(a)] : []));
const WINDOW = opt('--window', 15);
const NEAR = opt('--near', 800);

const night = t => t >= 0 && t % 600 >= 300;
const distSeg = (p, a, b) => {
    const dx = b.x - a.x, dy = b.y - a.y;
    const l2 = dx * dx + dy * dy;
    const u = l2 === 0 ? 0 : Math.max(0, Math.min(1, ((p.x - a.x) * dx + (p.y - a.y) * dy) / l2));
    return Math.hypot(p.x - (a.x + u * dx), p.y - (a.y + u * dy));
};

const RULES = {
    live: { speed: 330, cap: 4000, margin: 600, after: 3 },
    margin300: { speed: 330, cap: 4000, margin: 300, after: 3 },
    cap2000: { speed: 330, cap: 2000, margin: 600, after: 3 },
    cap2000m300: { speed: 330, cap: 2000, margin: 300, after: 3 },
    earlyTight: { speed: 330, cap: 4000, margin: 600, after: 3, early: { until: 240, cap: 1000, margin: 300 } },
    earlyNone: { speed: 330, cap: 4000, margin: 600, after: 3, early: { until: 240, cap: 0, margin: 0 } },
    visionCut: { speed: 330, cap: 4000, margin: 600, after: 3, cut: true },
    visionCut2000: { speed: 330, cap: 2000, margin: 600, after: 3, cut: true },
};

function run(store = new Store()) {
    const db = (sql, ...a) => store.query(sql, ...a);
    const gl = games.length ? games : db('SELECT DISTINCT game_id g FROM ev_lane_ctl WHERE cmiss IS NOT NULL').map(r => r.g);
    const out = {};
    for (const r of Object.keys(RULES)) out[r] = { rows: 0, refused: 0, refusedTrue: 0, perHero: 0, perHeroTrue: 0, allowed: 0, allowedShow: 0 };
    let nRows = 0;
    for (const g of gl) {
        const players = db('SELECT DISTINCT pid FROM ev_snap WHERE game_id = ? AND pid < 10', g).map(r => ({ pid: r.pid, team: r.pid < 5 ? 2 : 3 }));
        const snaps = {};
        for (const s of db('SELECT pid, t, x, y, alive FROM ev_snap WHERE game_id = ? ORDER BY t', g)) {
            (snaps[s.pid] = snaps[s.pid] || []).push(s);
        }
        const at = (pid, t) => {
            const a = snaps[pid];
            if (!a) return undefined;
            let lo = 0, hi = a.length - 1;
            while (lo < hi) { const m = (lo + hi + 1) >> 1; if (a[m].t <= t) lo = m; else hi = m - 1; }
            return a[lo].t <= t && t - a[lo].t < 3 ? a[lo] : undefined;
        };
        const rows = db('SELECT t, team, core, cmiss, cwhy FROM ev_lane_ctl WHERE game_id = ? AND cmiss IS NOT NULL AND core IS NOT NULL', g);
        for (const row of rows) {
            const me = at(row.core, row.t);
            const camp = CAMP[row.team];
            if (!me || !camp || !me.alive) continue;
            nRows++;
            const walk = [{ x: me.x, y: me.y }, camp];
            const allies = players.filter(p => p.team === row.team).map(p => p.pid);
            const enemies = players.filter(p => p.team !== row.team).map(p => p.pid);
            const info = [];
            for (const e of enemies) {
                const now = at(e, row.t);
                if (!now || !now.alive) continue;
                let seen = null;
                for (let u = Math.floor(row.t); u >= Math.max(row.t - LOOKBACK, -90); u--) {
                    const es = at(e, u);
                    if (!es || !es.alive) break;
                    const range = night(u) ? VISION_NIGHT : VISION_DAY;
                    if (allies.some(a => { const as = at(a, u); return as && as.alive && Math.hypot(as.x - es.x, as.y - es.y) <= range; })) { seen = { u, x: es.x, y: es.y }; break; }
                }
                if (!seen) continue;
                const tss = row.t - seen.u;
                let present = false;
                for (let u = row.t; u <= row.t + WINDOW; u++) {
                    const es = at(e, u);
                    if (es && es.alive && distSeg(es, walk[0], walk[1]) <= NEAR) { present = true; break; }
                }
                const vis = pt => allies.some(a => { const as = at(a, row.t); return as && as.alive && Math.hypot(as.x - pt.x, as.y - pt.y) <= (night(row.t) ? VISION_NIGHT : VISION_DAY); });
                const prev = at(e, seen.u - 2);
                const hpAt = db('SELECT hp FROM ev_snap WHERE game_id = ? AND pid = ? AND t <= ? ORDER BY t DESC LIMIT 1', g, e, seen.u)[0];
                let dw = 0, dn = 0;
                for (let u = seen.u; u > seen.u - 90; u -= 3) { const es = at(e, u); if (es && es.alive) { dn++; if (distSeg(es, walk[0], walk[1]) <= 1500) dw++; } }
                info.push({ dwell: dn ? dw / dn : 0, g, e, hp: hpAt && hpAt.hp, vx: prev ? (seen.x - prev.x) / 2 : 0, vy: prev ? (seen.y - prev.y) / 2 : 0, tss, seen, present, vis, visibleNow: tss <= 0.5 });
            }
            for (const [name, rule] of Object.entries(RULES)) {
                const o = out[name];
                const logged = row.cmiss > 0;
                o.agree = o.agree || { both: 0, onlyLogged: 0, onlyRebuilt: 0 };
                const counted = info.filter(i => {
                    if (i.visibleNow || i.tss <= rule.after) return false;
                    const e = rule.early && row.t < rule.early.until ? rule.early : rule;
                    const reach = Math.min(rule.speed * i.tss, e.cap) + e.margin;
                    if (distSeg(i.seen, walk[0], walk[1]) > reach) return false;
                    if (rule.cut) {
                        let open = false;
                        for (let k = 0; k <= 10 && !open; k++) {
                            const pt = { x: walk[0].x + (walk[1].x - walk[0].x) * k / 10, y: walk[0].y + (walk[1].y - walk[0].y) * k / 10 };
                            if (Math.hypot(pt.x - i.seen.x, pt.y - i.seen.y) <= reach && !i.vis(pt)) open = true;
                        }
                        if (!open) return false;
                    }
                    return true;
                });
                if (name === 'live') for (const i of info) if (!i.visibleNow && i.tss > 3) (out.unseen = out.unseen || []).push({ g: i.g, t: row.t, team: row.team, pos: (i.e % 5) + 1, tss: i.tss, sx: i.seen.x, sy: i.seen.y, vx: i.vx, vy: i.vy, hp: i.hp, dwell: i.dwell, mx: walk[0].x, my: walk[0].y, cx: camp.x, cy: camp.y, counted: counted.includes(i), present: i.present });
                const anyPresent = info.some(i => i.present && !i.visibleNow);
                o.rows++;
                if (name === 'live') o.agree[logged && counted.length ? 'both' : logged ? 'onlyLogged' : counted.length ? 'onlyRebuilt' : 'none'] = (o.agree[logged && counted.length ? 'both' : logged ? 'onlyLogged' : counted.length ? 'onlyRebuilt' : 'none'] || 0) + 1;
                if (counted.length > 0) {
                    o.refused++;
                    if (counted.some(i => i.present)) o.refusedTrue++;
                    if (name === 'live') for (const i of counted) (out.heroes = out.heroes || []).push({ pos: (i.e % 5) + 1, min: Math.floor(row.t / 120) * 2, tss: i.tss, d: distSeg(i.seen, walk[0], walk[1]), present: i.present });
                    o.perHero += counted.length;
                    o.perHeroTrue += counted.filter(i => i.present).length;
                } else {
                    o.allowed++;
                    if (anyPresent) o.allowedShow++;
                }
            }
        }
    }
    return { rows: nRows, window: WINDOW, near: NEAR, rules: out, heroes: out.heroes, unseen: out.unseen };
}

function main() {
    const res = run();
    if (args.includes('--dump')) { require('fs').writeFileSync(args[args.indexOf('--dump') + 1], JSON.stringify(res.unseen)); process.exit(0); }
    if (args.includes('--json')) console.log(JSON.stringify(res, null, 1));
    else {
        console.log(`rows ${res.rows} (core pull candidate evaluations), truth = enemy within ${res.near} of the walk within ${res.window} s`);
        console.log('rule           refused  precision(rows)  perHero  precision(heroes)  allowed  enemy-showed-up');
        console.log('live rebuilt vs logged cmiss>0:', JSON.stringify(res.rules.live.agree));
        const bucket = (title, key, edges) => {
            console.log(title);
            for (let i = 0; i < edges.length - 1; i++) {
                const h = (res.heroes || []).filter(x => x[key] >= edges[i] && x[key] < edges[i + 1]);
                if (h.length) console.log(`  ${edges[i]}-${edges[i + 1]}: ${h.length} counted, ${(h.filter(x => x.present).length / h.length).toFixed(2)} truly near`);
            }
        };
        for (const c of [true, false]) {
            const u = (res.unseen || []).filter(x => x.counted === c);
            console.log(`unseen heroes ${c ? 'counted' : 'not counted'} by the live rule: ${u.length}, ${(u.filter(x => x.present).length / Math.max(1, u.length)).toFixed(2)} truly near the walk`);
        }
        bucket('live-counted heroes by seconds unseen (precision that the hero really came near the walk):', 'tss', [3, 8, 15, 30, 60, 1e9]);
        bucket('by enemy position (pid within team + 1):', 'pos', [1, 2, 3, 4, 5, 6]);
        bucket('by game minute (even minutes):', 'min', [0, 2, 4, 6, 8, 10, 12, 99]);
        bucket('by last-seen distance to the walk (units):', 'd', [0, 600, 1200, 2000, 3000, 1e9]);
        for (const [k, o] of Object.entries(res.rules).filter(([k]) => k !== 'heroes' && k !== 'unseen')) {
            const f = (a, b) => (b ? (a / b).toFixed(2) : '-');
            console.log(`${k.padEnd(14)} ${String(o.refused).padStart(7)}  ${f(o.refusedTrue, o.refused).padStart(15)}  ${String(o.perHero).padStart(7)}  ${f(o.perHeroTrue, o.perHero).padStart(16)}  ${String(o.allowed).padStart(7)}  ${f(o.allowedShow, o.allowed).padStart(15)} (${o.allowedShow})`);
        }
    }

}

if (require.main === module) main();
module.exports = { run, RULES };
