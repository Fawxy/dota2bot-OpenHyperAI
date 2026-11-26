// The map as text, for agents. The data is `map64.txt` beside this file: towers, neutral camps, the
// boss pits, a walk grid and a height grid at 64 units. Never read that file into context; ask here.
//   node map.js build <probe log>          write map64.txt from a game that ran `rig_map_grid` (bots/rigs/mapgrid.lua) with
//                                          `--set Overrides.VisionMap=true` (the camps); the boss places are OHA's constants
//   node map.js at <x,y>                   the cell there, and what is near it
//   node map.js crop <x,y> [--half 1600] [--route "x,y;x,y;.."] [--radius 24]   a text picture, towers camps and bosses drawn in
//   node map.js check "x,y;x,y;.." [--radius 24]   a line of waypoints: walkable, how close to each tower's reach, how tight
//   node map.js see <x,y> <x,y> [--night|--range R]   can the first point see the second (tools/hlog/sight.js)
//   node map.js seen <x,y> [--half 1200] [--night|--range R]   which walkable cells around a point can see it
// A tower hits a unit whose centre is within its attack range plus its hull plus the unit's radius (WorldFacts.TowerReach
// plus the radius): `--radius` is the unit's, a hero's 24 by default. The probe reads towers on the server, so both
// teams' are true values.
'use strict';
const fs = require('fs');
const path = require('path');

const FILE = process.env.MAP_FILE || path.join(__dirname, 'map64.txt');
const ROOT = path.join(__dirname, '..', '..');

function args(argv) {
    const o = { _: [] };
    for (let i = 0; i < argv.length; i++) {
        const a = argv[i];
        if (a.startsWith('--')) {
            const v = argv[i + 1];
            if (v !== undefined && a !== '--night') { o[a.slice(2)] = v; i++; } else o[a.slice(2)] = true;
        } else o._.push(a);
    }
    return o;
}
const point = (s) => { const [x, y] = s.split(',').map(Number); return { x, y }; };
const points = (s) => s.split(';').filter(Boolean).map(point);
const kv = (s) => Object.fromEntries(s.trim().split(/\s+/).map((p) => { const i = p.indexOf('='); return [p.slice(0, i), isNaN(p.slice(i + 1)) ? p.slice(i + 1) : Number(p.slice(i + 1))]; }));

function build(log) {
    let head; const P = [], H = [], towers = new Set(); let camps = [];
    for (const l of fs.readFileSync(log, 'utf8').split('\n')) {
        let m;
        if ((m = l.match(/ev=vmap kind=camp xy=(\S+)/))) {
            camps = m[1].split(';').map((c) => { const [idx, team, type, x, y, x0, y0, x1, y1] = c.split(':'); return `idx=${idx} team=${team} level=${type} x=${x} y=${y} x0=${x0} y0=${y0} x1=${x1} y1=${y1}`; });
            continue;
        }
        if (!/ev=rig/.test(l)) continue;
        if ((m = l.match(/msg="(map_head [^"]+)"/))) { head = m[1].replace('map_head ', ''); P.length = 0; H.length = 0; towers.clear(); }
        else if ((m = l.match(/map_p y=(-?\d+) p=([^"]+)"/))) P.push(m[2]);
        else if ((m = l.match(/map_h y=(-?\d+) h=([^"]+)"/))) H.push(m[2]);
        else if ((m = l.match(/msg="map_tower ([^"]+)"/))) towers.add(m[1]);
    }
    if (!head || P.length === 0) throw new Error('no map_head/map_p lines in ' + log);
    if (camps.length === 0) console.error('warning: no ev=vmap kind=camp line (run with --set Overrides.VisionMap=true)');
    const lua = (f) => fs.readFileSync(path.join(ROOT, 'bots', 'FunLib', f), 'utf8');
    const vec = (src, name) => { const m = src.match(new RegExp(name + '\\s*=\\s*Vector\\((-?\\d+),\\s*(-?\\d+)')); return m ? `x=${m[1]} y=${m[2]}` : undefined; };
    const u = lua('utils.lua'), j = lua('jmz_func.lua');
    // Roshan and the tormentor each have two places and swap by day and night (jmz_func GetCurrentRoshanLocation).
    const bosses = [['roshan_radiant_pit', vec(u, 'RadiantRoshanLoc')], ['roshan_dire_pit', vec(u, 'DireRoshanLoc')],
        ['tormentor_radiant', vec(j, 'RadiantTormentorLoc')], ['tormentor_dire', vec(j, 'DireTormentorLoc')]]
        .filter((b) => b[1]).map((b) => `name=${b[0]} ${b[1]} src=oha_constant`);
    const out = ['# Dota map at 64 units. Built by tools/map/map.js build; query it with that script, do not read it.',
        '# Rows run north to south, columns west to east from x0. Cell of (x, y): row (y1 - y) / step, column (x - x0) / step.',
        '# walk: # terrain not walkable, T a tree within half a step (drawn fatter than it is), else ground height / 32 in base 36',
        '#   (0 river, 4 the lane shelf, 8 high ground). height: the same digit for every cell.',
        '# towers: reach to a point = range + hull; add the unit radius. bosses: OHA constants, not read from the game.',
        '', '[head]', head, '', '[towers]', ...[...towers].sort(), '', '[camps]', ...camps, '', '[bosses]', ...bosses, '', '[walk]', ...P, '', '[height]', ...H, ''];
    fs.writeFileSync(FILE, out.join('\n'));
    console.log(`${FILE}: ${P.length} rows, ${towers.size} towers, ${camps.length} camps, ${bosses.length} boss places, ${fs.statSync(FILE).size} bytes`);
}

let M;
function load() {
    if (M) return M;
    const sec = {}; let cur;
    for (const l of fs.readFileSync(FILE, 'utf8').split('\n')) {
        const m = l.match(/^\[(\w+)\]$/);
        if (m) { cur = sec[m[1]] = []; continue; }
        // Before the first section a `#` line is a comment; inside the grids it is a row of cliff.
        if (cur && l !== '') cur.push(l);
    }
    const h = kv(sec.head[0]);
    M = { x0: h.x0, y1: h.y1, x1: h.x1, y0: h.y0, step: h.step, walk: sec.walk, height: sec.height,
        towers: sec.towers.map(kv).map((t) => ({ ...t, reach: t.range + t.hull })), camps: sec.camps.map(kv), bosses: sec.bosses.map(kv) };
    return M;
}
const col = (x) => Math.round((x - load().x0) / M.step);
const row = (y) => Math.round((M.y1 - y) / M.step);
function walk(x, y) { const r = load().walk[row(y)]; return (r && r[col(x)]) || '#'; }
function height(x, y) { const r = load().height[row(y)]; return r && r[col(x)] ? parseInt(r[col(x)], 36) * 32 : undefined; }
const open = (c) => c !== '#' && c !== 'T';
// The flat levels are every 128 units (river, lane shelf, high ground, above). A ramp is a walkable run of cells between
// them that touches two different ones; a run that touches only one is raised or sunken ground.
let R;
function ramps() {
    if (R) return R;
    const g = load().walk;
    const level = (r, c) => { const d = g[r] && g[r][c]; return d && /[0-9a-z]/.test(d) ? parseInt(d, 36) : undefined; };
    const between = (z) => z !== undefined && z % 4 !== 0;
    const done = new Set(); R = new Set();
    for (let r = 0; r < g.length; r++) {
        for (let c = 0; c < g[r].length; c++) {
            if (!between(level(r, c)) || done.has(`${r},${c}`)) continue;
            const run = [`${r},${c}`], ends = new Set(), todo = [[r, c]]; done.add(run[0]);
            while (todo.length) {
                const [a, b] = todo.pop();
                for (let i = a - 1; i <= a + 1; i++) {
                    for (let j = b - 1; j <= b + 1; j++) {
                        const z = level(i, j), k = `${i},${j}`;
                        if (z === undefined) continue;
                        if (!between(z)) ends.add(z);
                        else if (!done.has(k)) { done.add(k); run.push(k); todo.push([i, j]); }
                    }
                }
            }
            if (ends.size > 1) for (const k of run) R.add(k);
        }
    }
    return R;
}
const ramp = (x, y) => ramps().has(`${row(y)},${col(x)}`);
const dist = (a, b) => Math.hypot(a.x - b.x, a.y - b.y);

function things(p, r) {
    load();
    const out = [];
    for (const t of M.towers) if (dist(p, t) <= r) out.push({ kind: 'tower', name: t.name.replace('npc_dota_', ''), x: t.x, y: t.y, d: Math.round(dist(p, t)), reach: t.reach });
    for (const c of M.camps) if (dist(p, c) <= r) out.push({ kind: 'camp', name: `camp ${c.idx} ${c.level} team ${c.team}`, x: c.x, y: c.y, d: Math.round(dist(p, c)), box: [c.x0, c.y0, c.x1, c.y1] });
    for (const b of M.bosses) if (dist(p, b) <= r) out.push({ kind: 'boss', name: b.name, x: b.x, y: b.y, d: Math.round(dist(p, b)) });
    return out.sort((a, b) => a.d - b.d);
}
const line = (t) => `  ${t.name} at ${t.x},${t.y}, ${t.d} away` + (t.reach ? `, reach ${t.reach}` : '') + (t.box ? `, box ${t.box[0]},${t.box[1]} to ${t.box[2]},${t.box[3]}` : '');

function at(p) {
    const c = walk(p.x, p.y);
    console.log(`${p.x},${p.y}: ${c === '#' ? 'not walkable' : c === 'T' ? 'tree' : 'walkable'}, ground height ${height(p.x, p.y)}`);
    for (const t of things(p, 2000)) console.log(line(t));
}

function crop(p, o, mark) {
    load();
    const half = Number(o.half || 1600), radius = Number(o.radius || 24), S = M.step;
    const route = o.route ? points(o.route) : [];
    const cx = Math.round(p.x / S) * S, cy = Math.round(p.y / S) * S, n = Math.floor(half / S);
    const near = things(p, half * 1.5);
    const lines = [];
    for (let j = n; j >= -n; j--) {
        const y = cy + j * S; let s = '';
        for (let i = -n; i <= n; i++) {
            const x = cx + i * S, q = { x, y }; let c = walk(x, y);
            const m = mark && open(c) ? mark(q) : undefined;
            if (ramp(x, y)) c = '/'; else if (c === '4') c = '.'; else if (c === '0') c = ' ';
            if (m) c = m;
            for (const t of near) {
                if (t.kind === 'tower') { if (dist(q, t) < S * 0.6) c = 'O'; else if (Math.abs(dist(q, t) - (t.reach + radius)) < S / 2 && open(walk(x, y))) c = 'o'; }
                else if (t.kind === 'camp') { if (dist(q, t) < S * 0.6) c = t.name.split(' ')[2][0].toUpperCase(); }
                else if (dist(q, t) < S * 0.6) c = t.name.startsWith('roshan') ? 'R' : 'X';
            }
            for (let k = 0; k < route.length; k++) {
                if (dist(q, route[k]) < S * 0.6) c = '*';
                else if (k > 0) {
                    const a = route[k - 1], b = route[k], L = dist(a, b), t = Math.max(0, Math.min(1, ((x - a.x) * (b.x - a.x) + (y - a.y) * (b.y - a.y)) / (L * L)));
                    if (Math.hypot(x - (a.x + t * (b.x - a.x)), y - (a.y + t * (b.y - a.y))) < S * 0.5 && c !== '*') c = '+';
                }
            }
            if (i === 0 && j === 0 && mark) c = '@';
            s += c;
        }
        lines.push(String(y).padStart(6) + ' ' + s);
    }
    console.log(`x ${cx - n * S} to ${cx + n * S}, one character ${S} units, north up. '.' shelf (height 128), blank river, digit height/32,`);
    console.log(`/ ramp between two levels, # cliff, T tree, O tower, o its reach plus radius ${radius}, S M L A camp by level, R Roshan pit, X tormentor` + (route.length ? ', * waypoint, + route' : ''));
    console.log(lines.join('\n'));
    for (const t of near.filter((t) => dist(p, t) <= half * 1.2)) console.log(line(t));
}

function check(route, o) {
    load();
    const radius = Number(o.radius || 24);
    let len = 0, gap = Infinity; const bad = []; const hs = new Set(); const hit = new Map();
    for (let k = 1; k < route.length; k++) {
        const a = route[k - 1], b = route[k], L = dist(a, b); len += L;
        if (L === 0) continue;
        for (let t = 0; t <= L; t += 16) {
            const q = { x: a.x + ((b.x - a.x) * t) / L, y: a.y + ((b.y - a.y) * t) / L };
            const c = walk(q.x, q.y);
            if (!open(c)) bad.push(`${Math.round(q.x)},${Math.round(q.y)} ${c === 'T' ? 'tree' : 'cliff'}`); else hs.add(height(q.x, q.y));
            for (const tw of M.towers) { const m = dist(q, tw) - (tw.reach + radius); if (m < 400 && (!hit.has(tw.name) || m < hit.get(tw.name))) hit.set(tw.name, m); }
            for (let r = M.step; r <= 384 && r < gap; r += M.step) {
                let blocked = false;
                for (let d = 0; d < 16; d++) if (!open(walk(q.x + r * Math.cos((d * Math.PI) / 8), q.y + r * Math.sin((d * Math.PI) / 8)))) { blocked = true; break; }
                if (blocked) { gap = r; break; }
            }
        }
    }
    console.log(`length ${Math.round(len)}; ground heights ${[...hs].sort((a, b) => a - b).join(', ')}; nearest wall or tree within ${gap === Infinity ? 'more than 384' : gap}`);
    console.log(bad.length ? `NOT walkable at ${bad.length} samples, first: ${[...new Set(bad)].slice(0, 5).join('; ')}` : 'walkable all the way');
    for (const [name, m] of hit) console.log(`  ${name.replace('npc_dota_', '')}: ${m < 0 ? `INSIDE its reach by ${Math.round(-m)}` : `clear of its reach by ${Math.round(m)}`} (unit radius ${radius})`);
    if (hit.size === 0) console.log('  no tower within 400 of its reach');
}

function sight() { return require(path.join(ROOT, 'tools', 'hlog', 'sight.js')); }
const range = (o) => (o.range ? Number(o.range) : o.night ? 800 : 1800);

function seen(p, o) {
    const s = sight(); s.load();
    const r = range(o); let yes = 0, no = 0; const why = {};
    crop(p, { half: o.half || 1200, radius: o.radius }, (q) => {
        const v = s.see(q, p, r);
        if (v.ok) { yes++; return '+'; }
        no++; why[v.why] = (why[v.why] || 0) + 1; return v.why === 'tree' ? 't' : v.why === 'height' ? 'h' : '-';
    });
    console.log(`@ the point; walkable cells that see it '+' (${yes}); that do not: 't' a tree in the way, 'h' higher ground in the way, '-' out of range ${r} (${no}: ${JSON.stringify(why)})`);
}

function main() {
    const o = args(process.argv.slice(2)); const [cmd, a, b] = o._;
    if (cmd === 'build') return build(a);
    if (cmd === 'at') return at(point(a));
    if (cmd === 'crop') return crop(point(a), o);
    if (cmd === 'check') return check(points(a), o);
    if (cmd === 'see') { const s = sight(); s.load(); return console.log(JSON.stringify(s.see(point(a), point(b), range(o)))); }
    if (cmd === 'seen') return seen(point(a), o);
    console.log(fs.readFileSync(__filename, 'utf8').split('\n').filter((l) => l.startsWith('//')).map((l) => l.slice(3)).join('\n'));
}
if (require.main === module) main();
module.exports = { load, walk, height, things };
