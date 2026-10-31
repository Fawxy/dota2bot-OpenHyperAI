#!/usr/bin/env node
'use strict';
// node tools/hlog/stacktruth.js <game.log>... [--json] : grade each ev=stack attempt from its game's SourceTV replay (the .dem
// dotactl --record keeps beside the log), not from the bot's vision. The replay is read by the master's replay-index
// extractor `stacktruth.exe` (docs/team/research/replay-index.md; path in STACKTRUTH_EXE or the default below).
// Per attempt and camp (B = the line's camp, A = fcamp of a double): `true` 1 when the camp spawned at :00 of the next
// minute (a neutral of that spawner left m_bIsWaitingToSpawn in [:59.5, :02]) while its earlier neutrals still lived (a camp
// cleared before :00 spawns too: `true` 0, `block` `respawn`), `log` our res/fres, and when it did not
// spawn, what stood in its spawn box at :59.9 (`grade`): the blockers. The replay has no boxes; the log's `ev=camp` lines
// (bot eecba6b on) give them, and a log without them uses `camp_boxes.json` (the same lines, saved once; static map data).
const fs = require('fs'), path = require('path'), { spawnSync } = require('child_process');

/** EC-060's guard distance, and the second after which a neutral that first got that far out was hit too late to clear. */
const GUARD = 400, LATE = 58;
const EXE = process.env.STACKTRUTH_EXE ||
  path.join(__dirname, '../../../../docs/team/research/replay-index/data/bin/stacktruth.exe');

function readTruth(dem) {
  const p = spawnSync(EXE, [dem], { maxBuffer: 1 << 30, encoding: 'utf8' });
  if (p.status !== 0) throw new Error(`stacktruth failed on ${dem}: ${p.stderr}`);
  const t = { sp: [], nc: [], snap: {}, alive: {}, cs: [] };
  for (const line of p.stdout.split('\n')) {
    if (!line.startsWith('{')) continue;
    const o = JSON.parse(line);
    if (o.k === 'sp') t.sp.push(o);
    else if (o.k === 'nc') t.nc.push(o);
    else if (o.k === 'snap' && o.at === 59.9) { t.snap[o.min] = o.u; t.alive[o.min] = o.alive || {}; }
    else if (o.k === 'cs') t.cs.push(o);
  }
  return t;
}

const near = (sp, x, y) => sp.reduce((b, s) => (Math.hypot(s.x - x, s.y - y) < Math.hypot(b.x - x, b.y - y) ? s : b));
const BOXES = path.join(__dirname, 'camp_boxes.json');

/** The `ev=camp` lines of a log as {idx: {x, y, x0, y0, x1, y1}}, or undefined when it has none. */
function boxesOf(text) {
  const out = {};
  for (const m of text.matchAll(/ev=camp (.*)/g)) {
    const f = Object.fromEntries(m[1].trim().split(/\s+/).map((kv) => kv.split('=')));
    out[f.idx] = { type: f.type, x: +f.x, y: +f.y, x0: +f.x0, y0: +f.y0, x1: +f.x1, y1: +f.y1 };
  }
  return Object.keys(out).length ? out : undefined;
}

/** Our camp number -> the replay's spawner (nearest origin) with that camp's box. */
function campMap(boxes, sp) {
  const m = {};
  for (const [idx, b] of Object.entries(boxes)) m[idx] = { ...near(sp, b.x, b.y), box: b };
  return m;
}

const inBox = (b, x, y) => x >= b.x0 && x <= b.x1 && y >= b.y0 && y <= b.y1;

/** A camp's result at :00 of the next minute and, when it did not spawn, what stood in its box at :59.9: its own
 *  neutrals in its box that never went GUARD out since :45 (`stay`: not drawn out), first went GUARD out at or after :LATE (`late`) or
 *  before it and came back (`back`, each as that second, then `>` the second it was furthest out and `:` the nearest hero's
 *  distance to it then), other camps' neutrals, lane creeps and heroes. */
function grade(s, minute, t) {
  const spawned = t.nc.some((n) => n.sp === s.ent && n.t >= minute * 60 + 59.5 && n.t <= minute * 60 + 62);
  if (spawned) return (t.alive?.[minute]?.[s.ent] ?? 0) > 0 ? { true: 1 } : { true: 0, block: 'respawn' };
  const c = { stay: 0, late: 0, back: [], other: 0, lane: 0, hero: 0 };
  for (const [, kind, who, x, y, maxd, out, turn, hero] of t.snap[minute] || []) {
    if (!inBox(s.box, x, y)) continue;
    if (kind === 'n' && who === s.ent) {
      if (maxd <= GUARD) c.stay++;
      else if (out >= LATE) c.late++;
      else c.back.push(turn === undefined ? `${out}` : `${out}>${turn}:${hero}`);
    }
    else if (kind === 'n') c.other++;
    else if (kind === 'l') c.lane++;
    else c.hero++;
  }
  const parts = [];
  if (c.stay) parts.push(`stay:${c.stay}`);
  if (c.late) parts.push(`late:${c.late}`);
  if (c.back.length) parts.push(`back:${c.back.length}@${c.back.join('/')}`);
  for (const k of ['other', 'lane', 'hero']) if (c[k]) parts.push(`${k}:${c[k]}`);
  return { true: 0, block: parts.join(',') || 'none', c };
}

function main() {
  const args = process.argv.slice(2), json = args.includes('--json');
  const logs = args.filter((a) => !a.startsWith('--'));
  const { Store, DB } = require('./store');
  const store = new Store(DB);
  for (const f of store.ingestAll(logs).failed) console.error(`not ingested: ${f.file}: ${f.error}`);
  const out = [];
  for (const log of logs) {
    const dem = log.replace(/\.log$/, '.dem');
    if (!fs.existsSync(dem)) { console.error(`no replay for ${log}`); continue; }
    // A double whose B failed (no hit) may still have hit A: grade A there, and B only where its hit landed.
    // The replay is of the log's last game (a restarted start leaves an earlier one in the log).
    const rows = store.query(`SELECT * FROM stack_attempts WHERE file = ?1 AND game = (SELECT max(game) FROM stack_attempts
      WHERE file = ?1) AND (res IN ('stacked', 'not_stacked') OR (double = 1 AND fres IN ('stacked', 'not_stacked', 'unseen')))
      ORDER BY min`, path.resolve(log));
    if (rows.length === 0) { console.error(`no landed attempts in the store for ${log}`); continue; }
    const boxes = boxesOf(fs.readFileSync(log, 'utf8')) ?? JSON.parse(fs.readFileSync(BOXES, 'utf8'));
    const t = readTruth(dem);
    const m = campMap(boxes, t.sp);
    for (const r of rows) {
      const o = { file: path.basename(log), min: r.min, double: r.double ?? null };
      const landed = r.res === 'stacked' || r.res === 'not_stacked';
      const b = landed && m[r.camp] ? grade(m[r.camp], r.min, t) : { true: null };
      Object.assign(o, { camp: r.camp, before: r.before, log: r.res, true: b.true, block: b.block ?? '' });
      if (r.double === 1 && r.fcamp != null) {
        const a = m[r.fcamp] ? grade(m[r.fcamp], r.min, t) : { true: null };
        Object.assign(o, { fcamp: r.fcamp, fbefore: r.fbefore, flog: r.fres, ftrue: a.true, fblock: a.block ?? '' });
      }
      out.push(o);
    }
  }
  if (json) { console.log(JSON.stringify(out, null, 1)); return; }
  for (const o of out) console.log([o.file, o.min, o.camp, o.log, o.true, o.block, o.fcamp ?? '', o.flog ?? '', o.ftrue ?? '', o.fblock ?? ''].join('\t'));
}

if (require.main === module) main();
module.exports = { grade, campMap, boxesOf, near };
