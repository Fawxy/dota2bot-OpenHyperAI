// A sight model from the map dump (Overrides.VisionMap, humaniser/vision_map.ts; master proposal
// docs/proposals/2026-11-18-vision-tool.md step M): what a unit at one point would see, which the API answers only for now.
// A point q is in sight of a viewer at p when it is within the viewer's range, no sample of the line p..q lies on ground
// two GetHeightLevel steps or more above the viewer's (HEIGHT_STEP), and no tree stands within TREE_R of the line (trees by
// the viewer's own feet, within OWN_R, are passed: a unit beside a tree sees past it). Fitted 18/11/2026 on sight-probe
// rig3 (10 grids with every other sight source logged): 95.2% of 11,560 cells agree; one step up as the block gave 90.7%,
// no height rule 94.0% with 465 cells called seen that were fogged. On 2,506 banked ev=cut grids (12 h2h games) the cells
// it calls seen are fogged 6.5% of the time (`cut`). GetHeightLevel comes in blocks of about 300: a model of the
// real terrain, not of the game's vision tiers; trees cut during a game are still standing in the map.
// Usage:
//   node sight.js map <vmap log>                     build sight_map.json beside this file from a probe game's ev=vmap lines
//   node sight.js see <x,y> <x,y> [--night|--range R] can the first point see the second; if not, why (range, height, tree)
//   node sight.js from <x,y> [--night|--range R] [--half H] [--step S]   an ASCII map of what a viewer there sees
//   node sight.js grid <log> [--rep n] [--show] [--tree-r R]   the model against each logged ph=grid (the cast and `vu`)
//   node sight.js cut <log> [...]                    precision on banked ev=cut `vis` grids (every 15th; hero range day
//                                                    1,800, night 800; other sources unlogged, so recall is a lower bound)
// The map is `sight_map.json` (SIGHT_MAP overrides the path); build it again when a patch changes the map.
'use strict';
const fs = require('fs');
const path = require('path');

const MAP = process.env.SIGHT_MAP || path.join(__dirname, 'sight_map.json');
let TREE_R = 80;
const HEIGHT_STEP = 2;
const OWN_R = 120;
const SAMPLE = 32;
const DAY = 1800;
const NIGHT = 800;

function args(argv) {
    const o = { _: [] };
    for (let i = 0; i < argv.length; i++) {
        const a = argv[i];
        if (a.startsWith('--')) {
            const k = a.slice(2);
            const v = argv[i + 1];
            if (v !== undefined && !v.startsWith('--') && !['night', 'show'].includes(k)) { o[k] = v; i++; } else o[k] = true;
        } else o._.push(a);
    }
    return o;
}

function point(s) {
    const [x, y] = s.split(',').map(Number);
    if (!Number.isFinite(x) || !Number.isFinite(y)) throw new Error(`not a point: ${s}`);
    return { x, y };
}

function field(line, k) {
    const m = line.match(new RegExp(` ${k}="([^"]*)"`)) || line.match(new RegExp(` ${k}=(\\S+)`));
    return m ? m[1] : undefined;
}

// ---- the map ----
function build(log) {
    const lines = fs.readFileSync(log, 'utf8').split(/\r?\n/).filter((l) => l.includes('ev=vmap'));
    const start = lines.find((l) => field(l, 'kind') === 'start');
    if (!start) throw new Error('no ev=vmap kind=start line');
    const step = Number(field(start, 'step'));
    const rows = [];
    const trees = [];
    for (const l of lines) {
        const k = field(l, 'kind');
        if (k === 'h') rows.push({ y: Number(field(l, 'y')), x0: Number(field(l, 'x0')), hex: field(l, 'hex') });
        else if (k === 't') for (const p of field(l, 'xy').split(';')) { const [, x, y] = p.split(":").map(Number); if (x !== 0 || y !== 0) trees.push([x, y]); }
    }
    rows.sort((a, b) => a.y - b.y);
    const end = lines.find((l) => field(l, 'kind') === 'end');
    const out = { step, x0: rows[0].x0, y0: rows[0].y, nx: rows[0].hex.length, ny: rows.length, rows: rows.map((r) => r.hex), trees, src: path.basename(log) };
    fs.writeFileSync(MAP, JSON.stringify(out));
    console.log(`sight_map.json: ${out.nx}x${out.ny} cells of ${step} from (${out.x0},${out.y0}), ${trees.length} trees` + (end ? `; end says rows ${field(end, 'rows')}, trees ${field(end, 'trees')}` : '; no end line'));
}

let M;
function load() {
    if (M) return M;
    if (!fs.existsSync(MAP)) throw new Error('no sight_map.json: node sight.js map <probe log>');
    M = JSON.parse(fs.readFileSync(MAP, 'utf8'));
    // Trees bucketed by cell of 256 for the line test.
    M.bucket = new Map();
    for (const [x, y] of M.trees) {
        const k = `${Math.floor(x / 256)},${Math.floor(y / 256)}`;
        if (!M.bucket.has(k)) M.bucket.set(k, []);
        M.bucket.get(k).push([x, y]);
    }
    return M;
}

function cellOf(x, y) {
    const m = load();
    const i = Math.round((x - m.x0) / m.step);
    const j = Math.round((y - m.y0) / m.step);
    if (i < 0 || j < 0 || i >= m.nx || j >= m.ny) return 0;
    return parseInt(m.rows[j][i], 16);
}
const level = (x, y) => cellOf(x, y) & 7;

function treesNear(x, y, r) {
    const m = load();
    const out = [];
    for (let a = Math.floor((x - r) / 256); a <= Math.floor((x + r) / 256); a++)
        for (let b = Math.floor((y - r) / 256); b <= Math.floor((y + r) / 256); b++)
            for (const t of m.bucket.get(`${a},${b}`) || []) if (Math.hypot(t[0] - x, t[1] - y) <= r) out.push(t);
    return out;
}

/** Whether p sees q, and if not, why: {ok, why, at}. */
function see(p, q, range) {
    const d = Math.hypot(q.x - p.x, q.y - p.y);
    if (d > range) return { ok: false, why: 'range', d };
    const hp = level(p.x, p.y);
    const n = Math.max(1, Math.ceil(d / SAMPLE));
    for (let s = 1; s <= n; s++) {
        const x = p.x + ((q.x - p.x) * s) / n;
        const y = p.y + ((q.y - p.y) * s) / n;
        if (level(x, y) >= hp + HEIGHT_STEP) return { ok: false, why: 'height', at: [Math.round(x), Math.round(y)], d };
        if (Math.hypot(x - p.x, y - p.y) <= OWN_R) continue;
        const t = treesNear(x, y, TREE_R);
        if (t.length > 0) return { ok: false, why: 'tree', at: t[0], d };
    }
    return { ok: true, d };
}

function rangeOf(o) {
    if (o.range) return Number(o.range);
    return o.night ? NIGHT : DAY;
}

function ascii(p, range, half, step, model, truth) {
    const out = [];
    for (let y = p.y + half; y >= p.y - half; y -= step) {
        let s = '';
        for (let x = p.x - half; x <= p.x + half; x += step) {
            if (Math.abs(x - p.x) < step / 2 && Math.abs(y - p.y) < step / 2) { s += '@'; continue; }
            const v = model ? model({ x, y }) : see(p, { x, y }, range).ok;
            if (truth) { const t = truth(x, y); s += v && t ? '#' : !v && !t ? '.' : v ? '+' : '-'; }
            else s += v ? '#' : treesNear(x, y, 60).length ? 'T' : '.';
        }
        out.push(s);
    }
    return out.join('\n');
}

// ---- the logged grids ----
function grids(log) {
    const lines = fs.readFileSync(log, 'utf8').split(/\r?\n/);
    const out = [];
    for (const l of lines) {
        if (!l.includes('ph=grid')) continue;
        const t = Number(field(l, 't'));
        const [x0, y0, nx, ny, st, hex] = field(l, 'vg').split(',');
        const vu = (field(l, 'vu') || '').split(';').filter(Boolean).map((p) => { const [x, y, r] = p.split(':').map(Number); return { x, y, r }; });
        const vr = field(l, 'vr') !== undefined ? Number(field(l, 'vr')) : undefined;
        out.push({ t, rep: Number(field(l, 'rep')), v: field(l, 'var'), at: { x: Number(field(l, 'x')), y: Number(field(l, 'y')) }, x0: +x0, y0: +y0, nx: +nx, ny: +ny, st: +st, hex, vu, vr });
    }
    return out;
}

function bit(g, i, j) {
    const k = j * g.nx + i;
    return (parseInt(g.hex[k >> 2], 16) >> (3 - (k & 3))) & 1;
}

/** Day 0:00 to 5:00, night 5:00 to 10:00, and so on. */
const isNight = (t) => Math.floor(t / 300) % 2 === 1;

/** Whether any of the grid's viewers sees q: the cast at its range, then each logged other source (`vu`) at its own. */
function seenBy(g, range, q) {
    if (see(g.at, q, range).ok) return true;
    for (const u of g.vu) if (Math.abs(u.x - q.x) <= u.r && Math.abs(u.y - q.y) <= u.r && see(u, q, u.r).ok) return true;
    return false;
}

function score(g, range) {
    // A grid with its other sources (`vu`) is scored whole; one without, inside the cast's range only (the rest is other
    // units' sight the model cannot place).
    const c = { tp: 0, tn: 0, fp: 0, fn: 0 };
    for (let j = 0; j < g.ny; j++)
        for (let i = 0; i < g.nx; i++) {
            const x = g.x0 + i * g.st;
            const y = g.y0 + j * g.st;
            if (g.vr === undefined && Math.hypot(x - g.at.x, y - g.at.y) > range) continue;
            const m = g.vr === undefined ? see(g.at, { x, y }, range).ok : seenBy(g, range, { x, y });
            const t = bit(g, i, j) === 1;
            c[m && t ? 'tp' : !m && !t ? 'tn' : m ? 'fp' : 'fn']++;
        }
    return c;
}

function main() {
    const o = args(process.argv.slice(2));
    const [cmd, a, b] = o._;
    if (o['tree-r']) TREE_R = Number(o['tree-r']);
    if (cmd === 'map') return build(a);
    if (cmd === 'see') {
        const p = point(a), q = point(b);
        const r = see(p, q, rangeOf(o));
        const lv = `levels ${level(p.x, p.y)} -> ${level(q.x, q.y)}`;
        console.log(r.ok ? `yes (${Math.round(r.d)} away, ${lv})` : `no: ${r.why}${r.at ? ` at ${r.at.join(',')}` : ''} (${Math.round(r.d)} away, ${lv})`);
        return;
    }
    if (cmd === 'from') {
        const p = point(a);
        console.log(ascii(p, rangeOf(o), Number(o.half || 1600), Number(o.step || 100)));
        console.log(`@ viewer (level ${level(p.x, p.y)}), # seen, . not, T tree; range ${rangeOf(o)}`);
        return;
    }
    if (cmd === 'grid') {
        const all = { tp: 0, tn: 0, fp: 0, fn: 0 };
        for (const g of grids(a)) {
            if (o.rep && g.rep !== Number(o.rep)) continue;
            const range = o.range ? Number(o.range) : g.vr !== undefined ? g.vr : isNight(g.t) ? NIGHT : DAY;
            const c = score(g, range);
            for (const k in all) all[k] += c[k];
            const n = c.tp + c.tn + c.fp + c.fn;
            console.log(`rep ${g.rep} ${g.v} t=${g.t} range ${range}: agree ${((100 * (c.tp + c.tn)) / n).toFixed(1)}% of ${n} (model says seen, fogged: ${c.fp}; says fogged, seen: ${c.fn})`);
            if (o.show) {
                console.log(ascii(g.at, range, Math.min(range, 1600), g.st, g.vr === undefined ? undefined : (q) => seenBy(g, range, q), (x, y) => {
                    const i = Math.round((x - g.x0) / g.st), j = Math.round((y - g.y0) / g.st);
                    return i >= 0 && j >= 0 && i < g.nx && j < g.ny && bit(g, i, j) === 1;
                }));
                console.log('# both seen, . both fogged, + model only, - grid only');
            }
        }
        const n = all.tp + all.tn + all.fp + all.fn;
        console.log(`all: agree ${((100 * (all.tp + all.tn)) / n).toFixed(1)}% of ${n}; model seen but fogged ${all.fp}, model fogged but seen ${all.fn} (tree r ${TREE_R})`);
        return;
    }
    if (cmd === 'cut') {
        const c = { tp: 0, tn: 0, fp: 0, fn: 0 };
        let n = 0;
        for (const f of o._.slice(1)) {
            const ls = fs.readFileSync(f, "utf8").split(/\r?\n/).filter((l) => l.includes("ev=cut ") && l.includes(" vis="));
            for (let k = 0; k < ls.length; k += 15) {
                const l = ls[k];
                const t = Number(field(l, 't'));
                const [bx, by] = field(l, 'b').split(',').map(Number);
                const [x0, y0, nx, ny, st, hex] = field(l, 'vis').split(',');
                const g = { x0: +x0, y0: +y0, nx: +nx, ny: +ny, st: +st, hex };
                const range = isNight(t) ? NIGHT : DAY;
                n++;
                for (let j = 0; j < g.ny; j++)
                    for (let i = 0; i < g.nx; i++) {
                        const x = g.x0 + i * g.st, y = g.y0 + j * g.st;
                        if (Math.hypot(x - bx, y - by) > range * 0.9) continue;
                        const m = see({ x: bx, y: by }, { x, y }, range).ok;
                        const v = bit(g, i, j) === 1;
                        c[m && v ? 'tp' : !m && !v ? 'tn' : m ? 'fp' : 'fn']++;
                    }
            }
        }
        console.log(`${n} grids: of cells called seen, fogged ${((100 * c.fp) / (c.tp + c.fp)).toFixed(1)}%; of cells seen, called seen at least ${((100 * c.tp) / (c.tp + c.fn)).toFixed(1)}% (tree r ${TREE_R})`);
        return;
    }
    console.log(fs.readFileSync(__filename, 'utf8').split('\n').filter((l) => l.startsWith('//')).join('\n'));
}

if (require.main === module) main();
module.exports = { see, level, treesNear, load };
