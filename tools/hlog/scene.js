'use strict';
// `hlog.js scene`: who was where, and what happened, at a place and time in one game (docs/proposals/2026-11-25-scene-and-unit-lives.md s3).
// Frames every `every` seconds read the heroes' latest snapshots (queries/scene_snaps.sql), each team's lane front (scene_front.sql) and the
// towers still standing (scene_falls.sql); between frames come the timeline's rows for the heroes in the scene (timelineRows) and the lane
// creep and neutral deaths inside the radius (scene_deaths.sql). Unit source is the log: no live-creep or camp count.
const fs = require('fs');
const path = require('path');
const { POLY, TOWERS, C, laneLabel } = require('./dynamic');

const QUERIES = path.join(__dirname, 'queries');
const sql = name => fs.readFileSync(path.join(QUERIES, `${name}.sql`), 'utf8');

const LANES = ['top', 'mid', 'bot'];
const MAX_WINDOW = 60;
const MAX_LINES = 80;
const FRESH = 2; // a snapshot older than this (s) at a frame is no hero there: bots log none while dead
const UNIT_UNTIL = 720; // Telemetry.CreepDeathUntil
const KINDS = 'death,retreat,exchange,kill_try,job,decision,mode,cast';
const NOT_KNOWN = 'not known in an unrecorded game';

const clock = t => `${t < 0 ? '-' : ''}${Math.floor(Math.abs(t) / 60)}:${String(Math.floor(Math.abs(t) % 60)).padStart(2, '0')}`;
const dist = (a, b) => Math.hypot(a.x - b.x, a.y - b.y);
const teamLetter = t => (t === 2 ? 'R' : t === 3 ? 'D' : '?');

/** Each lane's length in world units (the polyline of dynamic.js POLY, as view lane_segments). */
const LANE_LEN = Object.fromEntries(Object.entries(POLY).map(([L, P]) => [
    L, P.slice(1).reduce((n, p, i) => n + Math.hypot(p[0] - P[i][0], p[1] - P[i][1]), 0)]));

/**
 * Every tower with the API's tower constant (top 1-3 = 0-2, mid 3-5, bot 6-8: ev=building_fall's `id`) from POLY's order: in a lane the
 * polyline runs Radiant's tiers 3, 2, 1 then Dire's 1, 2, 3. Base towers (id 9, 10) have no lane and are not told apart, so they stand.
 */
const LANE_TOWERS = LANES.flatMap((L, li) => POLY[L].slice(1, 7).map(([x, y], i) => {
    const team = i < 3 ? 2 : 3;
    const tier = i < 3 ? 3 - i : i - 2;
    return { team, x, y, lane: L, tier, id: li * 3 + tier - 1 };
}));

function selectorCmd(o) {
    return [o.hero !== undefined ? `--hero ${o.hero}` : '', o.pid !== undefined ? `--pid ${o.pid}` : '', o.lane ? `--lane ${o.lane}` : '',
        o.xy ? `--xy ${o.xy.x},${o.xy.y}` : '', o.r !== 1600 ? `--r ${o.r}` : '', o.every !== 5 ? `--every ${o.every}` : ''].filter(Boolean).join(' ');
}

function parseOptions(o, secs) {
    const sel = ['hero', 'pid', 'lane', 'xy'].filter(k => o[k] !== undefined);
    if (sel.length !== 1) throw new Error('scene needs one of --hero H, --pid N, --lane top|mid|bot, --xy x,y');
    if (o.at !== undefined && (o.from !== undefined || o.to !== undefined)) throw new Error('scene takes --at T or --from T --to T, not both');
    if (o.at === undefined && (o.from === undefined || o.to === undefined)) throw new Error('scene needs --at T, or --from T and --to T');
    if (o.lane !== undefined && !LANES.includes(o.lane)) throw new Error(`no lane ${o.lane}; one of: ${LANES.join(' ')}`);
    let xy;
    if (o.xy !== undefined) {
        const m = String(o.xy).match(/^(-?\d+(?:\.\d+)?),(-?\d+(?:\.\d+)?)$/);
        if (!m) throw new Error(`--xy ${o.xy} is not x,y (world units, e.g. 5200,-5600)`);
        xy = { x: Number(m[1]), y: Number(m[2]) };
    }
    const num = (k, d) => {
        if (o[k] === undefined) return d;
        const n = Number(o[k]);
        if (!(n > 0)) throw new Error(`--${k} ${o[k]} is not a positive number`);
        return n;
    };
    const at = o.at === undefined ? undefined : secs(o.at);
    const every = num('every', 5);
    const from = at ?? secs(o.from);
    const to = at ?? secs(o.to);
    if (to < from) throw new Error(`--to ${o.to} is before --from ${o.from}`);
    return { hero: o.hero, pid: o.pid === undefined ? undefined : Number(o.pid), lane: o.lane, xy, r: num('r', 1600), every, at, from, to };
}

/** The last element of a time-sorted list with t <= ft, or undefined. */
function latest(list, ft) {
    let r;
    for (const e of list) { if (e.t <= ft) r = e; else break; }
    return r;
}

/**
 * The scene as rows and a header. store: an open Store with views refreshed; file: the log's absolute path; timelineRows: hlog.js's.
 * o: game, at | from + to, one of hero | pid | lane | xy, r, every (strings or numbers as given on the command line).
 * Returns { header, rows, next, lines }: rows {t, kind: front|hero|timeline|creep|neutral|note, ...}; lines the text view.
 */
function scene(store, file, o0, { secs, timelineRows, target }) {
    const o = parseOptions(o0, secs);
    if (o.to - o.from > MAX_WINDOW) {
        throw new Error(`a window of ${Math.round(o.to - o.from)} s is over ${MAX_WINDOW} s; narrow it: node hlog.js scene ${target}${o0.game === undefined ? '' : ` --game ${o0.game}`} `
            + `--from ${clock(o.from)} --to ${clock(o.from + MAX_WINDOW)} ${selectorCmd(o)}`);
    }
    const game = o0.game === undefined ? null : Number(o0.game);
    const g = store.query('SELECT game_id, game, label, build, max_t FROM games WHERE file = :file AND (:game IS NULL OR game = :game) ORDER BY game DESC LIMIT 1', { file, game })[0];
    if (!g) throw new Error(`no game ${o0.game ?? ''} in ${file}`);
    const game_id = g.game_id;
    // The window an event is read in: a lone frame reads a frame either side.
    const evLo = o.at === undefined ? o.from : o.from - o.every;
    const evHi = o.at === undefined ? o.to : o.to + o.every;
    const lo = evLo - FRESH - 3;

    const snapRows = store.query(sql('scene_snaps'), { game_id, lo, hi: evHi });
    const roster = new Map();
    const snaps = new Map();
    for (const r of snapRows) {
        if (!roster.has(r.pid)) { roster.set(r.pid, { pid: r.pid, team: r.team, hero: r.hero, pos: r.pos }); snaps.set(r.pid, []); }
        if (r.t !== null && r.x !== null) snaps.get(r.pid).push(r);
    }
    if (o.hero !== undefined && ![...roster.values()].some(h => h.hero === o.hero)) {
        throw new Error(`no hero ${o.hero} in that game; of: ${[...roster.values()].map(h => h.hero).join(' ')}`);
    }
    const focusPid = o.pid ?? [...roster.values()].find(h => h.hero === o.hero)?.pid;
    if (o.pid !== undefined && !roster.has(o.pid)) throw new Error(`no pid ${o.pid} in that game; of: ${[...roster.keys()].join(' ')}`);
    const who = pid => roster.get(pid);
    const seat = h => `${teamLetter(h.team)}${h.pos ?? ''}`;
    const named = pid => (who(pid) ? `${seat(who(pid))} ${who(pid).hero}` : `pid ${pid}`);

    const fronts = { 2: [], 3: [] };
    for (const f of store.query(sql('scene_front'), { game_id, lo, hi: evHi })) fronts[f.team]?.push(f);
    if (o.lane && !fronts[2].length && !fronts[3].length) throw new Error('this game has no ev=front lines, so --lane has no front to read; use --hero or --xy');
    const falls = store.query(sql('scene_falls'), { game_id, hi: evHi }).filter(f => f.kind === 'tower');
    const standing = ft => LANE_TOWERS.filter(t => !falls.some(f => f.team === t.team && f.id === t.id && f.t < ft));

    const frameTimes = [];
    if (o.at !== undefined) frameTimes.push(o.at);
    else for (let t = o.from; t <= o.to + 1e-9; t += o.every) frameTimes.push(t);

    const rows = [];
    const seen = new Set();
    const centers = [];
    const frontAt = (team, ft, lane) => {
        const f = latest(fronts[team], ft);
        return f && ft - f.t <= FRESH + 3 && f[lane] !== null ? { s: f[lane], x: f[`${lane}x`], y: f[`${lane}y`] } : undefined;
    };
    for (const ft of frameTimes) {
        const fresh = [];
        for (const [pid, list] of snaps) {
            const s = latest(list, ft);
            if (s && ft - s.t <= FRESH && s.alive !== 0 && !(s.hp !== null && s.hp <= 0)) fresh.push({ ...who(pid), ...s });
        }
        const focus = focusPid === undefined ? undefined : fresh.find(h => h.pid === focusPid);
        let pts = [];
        let laneHere = o.lane;
        let members = [];
        if (focusPid !== undefined) {
            if (ft > g.max_t) { rows.push({ t: ft, kind: 'note', text: `the log ends at ${clock(g.max_t)}` }); continue; }
            let last = focus ?? latest(snaps.get(focusPid), ft);
            // A hero dead through the whole window has none in the list: its last snapshot before it.
            last ??= store.query('SELECT t, x, y FROM ev_snap WHERE game_id = ? AND pid = ? AND t < ? AND x IS NOT NULL ORDER BY t DESC LIMIT 1', game_id, focusPid, lo)[0];
            if (!last) { rows.push({ t: ft, kind: 'note', text: `${named(focusPid)}: no snapshot of this hero up to ${clock(ft)}` }); continue; }
            pts = [last];
            members = fresh.filter(h => h.pid === focusPid || dist(h, last) <= o.r);
            if (!focus) rows.push({ t: ft, kind: 'note', text: `${named(focusPid)}: dead (no snapshot since ${clock(last.t)}, at (${last.x},${last.y}))` });
            laneHere = focus && focus.ld <= C.LANE_R && LANES.includes(focus.ln) ? focus.ln : laneLabel([last.x, last.y]);
        } else if (o.xy) {
            pts = [o.xy];
            members = fresh.filter(h => dist(h, o.xy) <= o.r);
            laneHere = laneLabel([o.xy.x, o.xy.y]);
        } else {
            for (const team of [2, 3]) {
                const f = frontAt(team, ft, o.lane);
                if (f) pts.push(f);
            }
            members = fresh.filter(h => h.ln === o.lane && pts.some(p => dist(h, p) <= o.r));
        }
        centers.push({ t: ft, pts });
        if (!LANES.includes(laneHere)) laneHere = undefined;

        const fr = laneHere ? { 2: frontAt(2, ft, laneHere), 3: frontAt(3, ft, laneHere) } : {};
        if (fr[2] || fr[3]) {
            const gap = fr[2] && fr[3] ? Math.round(dist(fr[2], fr[3])) : null;
            rows.push({
                t: ft, kind: 'front', lane: laneHere, rad_s: fr[2]?.s ?? null, dire_s: fr[3]?.s ?? null, gap,
                text: `fronts ${laneHere} R ${fr[2] ? `s=${fr[2].s.toFixed(2)}` : '?'} D ${fr[3] ? `s=${fr[3].s.toFixed(2)}` : '?'}${gap === null ? '' : ` (gap ${gap})`}`,
            });
        }
        const towers = standing(ft);
        members.sort((a, b) => a.team - b.team || (a.pos ?? 9) - (b.pos ?? 9) || a.pid - b.pid);
        for (const h of members) {
            seen.add(h.pid);
            let enemy;
            for (const e of fresh) if (e.team !== h.team) { const d = dist(h, e); if (!enemy || d < enemy.d) enemy = { d: Math.round(d), pid: e.pid }; }
            let ahead = null;
            if (LANES.includes(h.ln) && h.ld <= C.LANE_R && h.s !== null) {
                const f = frontAt(h.team, ft, h.ln);
                if (f) ahead = Math.round((h.team === 2 ? h.s - f.s : f.s - h.s) * LANE_LEN[h.ln]);
            }
            let tower = null;
            for (const t of towers) {
                const d = dist(h, t);
                if (d <= C.TOWER_R && (!tower || d < tower.d)) tower = { d, own: t.team === h.team, name: `T${t.tier} ${t.lane}` };
            }
            const target = h.tid ? (/^h\d+$/.test(h.tid) ? named(Number(h.tid.slice(1))) : /^u\d+$/.test(h.tid)
                ? `${h.tid} ${(h.tgt ?? '').includes('goodguys') ? 'R' : (h.tgt ?? '').includes('badguys') ? 'D' : ''} ${(h.tgt ?? '').replace(/^npc_dota_creep_(good|bad)guys_/, '')}`.replace(/\s+/g, ' ').trim()
                : h.tid) : null;
            const bits = [
                `(${h.x},${h.y})`,
                h.s !== null && h.ln ? `${h.ln} s=${Number(h.s).toFixed(2)}` : '',
                ahead === null ? '' : `${Math.abs(ahead)} ${ahead < 0 ? 'behind' : 'ahead of'} front`,
                `hp ${h.hp}`,
                h.by ?? h.mode ?? '',
                target ? `-> ${target}` : '',
                enemy ? `enemy ${enemy.d} (${named(enemy.pid)})` : '',
                tower ? `in range of ${tower.own ? 'own' : 'enemy'} ${tower.name} tower` : '',
            ].filter(Boolean);
            rows.push({
                t: ft, kind: 'hero', pid: h.pid, team: h.team, pos: h.pos, hero: h.hero, x: h.x, y: h.y, ln: h.ln ?? null, s: h.s ?? null,
                front_ahead: ahead, enemy_pid: enemy?.pid ?? null, enemy_d: enemy?.d ?? null, tower: tower ? `${tower.own ? 'own' : 'enemy'} ${tower.name}` : null,
                hp: h.hp, mode: h.mode ?? null, by: h.by ?? null, target, label: `${seat(h)} ${h.hero}`, text: bits.join('  '),
            });
        }
        if (!members.length) rows.push({ t: ft, kind: 'note', text: 'no hero in the scene' });
    }

    const centerAt = t => {
        let c = centers[0];
        for (const e of centers) { if (e.t <= t) c = e; else break; }
        return c?.pts ?? [];
    };
    const cmds = [];
    if (seen.size) {
        const tl = timelineRows(store, file, { game: g.game, from: evLo, to: evHi, kind: KINDS });
        for (const r of tl) {
            if (r.t === null || r.t > evHi || (r.t1 ?? r.t) < evLo || r.pid === null) continue;
            if (!seen.has(r.pid) && !seen.has(r.other_pid)) continue;
            rows.push({
                t: r.t, kind: 'timeline', what: r.kind, pid: r.pid, team: r.team, pos: r.pos, hero: r.hero, t1: r.t1, detail: r.detail,
                label: `${teamLetter(r.team)}${r.pos ?? ''} ${r.hero}`, text: `${r.kind.padEnd(9)}${r.detail}`,
            });
        }
    }
    const unitCut = Math.min(evHi, UNIT_UNTIL);
    const deaths = evLo <= UNIT_UNTIL ? store.query(sql('scene_deaths'), { game_id, lo: evLo, hi: unitCut }) : [];
    for (const d of deaths) {
        if (!centerAt(d.t).some(p => Math.hypot(d.x - p.x, d.y - p.y) <= o.r)) continue;
        const by = pid => (typeof pid === 'number' || /^\d+$/.test(String(pid))) && who(Number(pid)) ? named(Number(pid)) : null;
        const place = `(${d.x},${d.y})`;
        if (d.side === 'neutral') {
            const k = by(d.pid);
            rows.push({ t: d.t, kind: 'neutral', x: d.x, y: d.y, camp: d.camp, pid: k ? Number(d.pid) : null, text: `neutral died ${place} camp ${d.camp}: ${k ? `last hit by ${k}` : 'no hero credited'}` });
            continue;
        }
        const creepTeam = d.side === 'enemy' ? (d.team === 2 ? 3 : 2) : d.team;
        const k = by(d.pid);
        const fate = d.fate === 'own_lh' ? `last hit by ${k}` : d.fate === 'own_deny' ? `denied by ${k}` : 'nobody got it';
        rows.push({ t: d.t, kind: 'creep', team: creepTeam, creep: d.kind, x: d.x, y: d.y, fate: d.fate, pid: k ? Number(d.pid) : null, text: `${teamLetter(creepTeam)} ${d.kind ?? 'creep'} died ${place}: ${fate}` });
    }

    const order = { front: 0, hero: 1, note: 1, timeline: 2, creep: 3, neutral: 3 };
    rows.sort((a, b) => a.t - b.t || order[a.kind] - order[b.kind]);

    const place = o.xy ? `(${o.xy.x},${o.xy.y}) r ${o.r}` : o.lane ? `${o.lane} lane` : `${who(focusPid).hero} r ${o.r}`;
    const win = o.at === undefined ? `${clock(o.from)}-${clock(o.to)}` : `${clock(o.at)}`;
    const units = o.to > UNIT_UNTIL
        ? `log to ${clock(UNIT_UNTIL)}; no unit is logged after ${clock(UNIT_UNTIL)} (CreepDeathUntil ${UNIT_UNTIL} s)`
        : 'log (deaths only)';
    const header = [
        `scene ${g.label ?? path.basename(file)} game ${g.game}  ${place}  ${win}  units: ${units}`,
        `creeps alive, camp counts: ${NOT_KNOWN}`,
    ];

    const sel = selectorCmd(o);
    const gameArg = o0.game === undefined ? '' : ` --game ${o0.game}`;
    const tlSel = o.lane ? `--lane ${o.lane}` : seen.size ? `--hero ${[...seen].map(who).find(h => h.pid === focusPid)?.hero ?? who([...seen][0]).hero}` : '';
    cmds.push(`node hlog.js timeline ${target}${gameArg} --from ${clock(evLo)} --to ${clock(evHi)} ${tlSel}`.trim());
    const onScreen = focusPid !== undefined && seen.has(focusPid) ? focusPid : [...seen][0];
    if (onScreen !== undefined) cmds.push(`node hlog.js events ${target}${gameArg} --pid ${onScreen} --from ${clock(evLo)} --to ${clock(evHi)}`);
    const nearest = rows.find(r => r.kind === 'hero' && r.pid === onScreen && r.enemy_pid !== null);
    if (nearest) cmds.push(`node hlog.js scene ${target}${gameArg} ${o.at === undefined ? `--from ${clock(o.from)} --to ${clock(o.to)}` : `--at ${clock(o.at)}`} --pid ${nearest.enemy_pid}${o.r !== 1600 ? ` --r ${o.r}` : ''}${o.every !== 5 ? ` --every ${o.every}` : ''}`);

    const lines = [...header];
    const width = Math.max(0, ...rows.filter(r => r.label).map(r => r.label.length)) + 2;
    for (const r of rows) {
        const stamp = clock(r.t) + (r.kind === 'timeline' && r.t1 !== null && r.t1 !== r.t ? `-${clock(r.t1)}` : '');
        const body = r.label ? `${r.label.padEnd(width)}${r.text}` : r.text;
        lines.push(`${(r.kind === 'hero' || r.kind === 'note' ? '' : stamp).padEnd(12)}${body}`);
    }
    if (!rows.length) lines.push('(nothing in that window)');
    if (lines.length + cmds.length + 1 > MAX_LINES) {
        const mid = o.from + (o.to - o.from) / 2;
        throw new Error(`the output would be ${lines.length + cmds.length + 1} lines, over ${MAX_LINES}; narrow it: node hlog.js scene ${target}${gameArg} --from ${clock(o.from)} `
            + `--to ${clock(Math.max(o.from, Math.floor(mid)))} ${sel}   (or a smaller --r, or a larger --every)`);
    }
    lines.push('next:', ...cmds.map(c => `  ${c}`));
    return { header: { label: g.label ?? null, game: g.game, place, window: win, units, creeps_and_camps: NOT_KNOWN }, rows: rows.map(({ text, label, ...r }) => (r.kind === 'note' ? { ...r, text } : r)), next: cmds, lines };
}

module.exports = { scene, LANE_LEN, LANE_TOWERS };
