#!/usr/bin/env node
'use strict';
// node tools/hlog/stacktruth.js <game.log>... [--json] : grade each ev=stack attempt from its game's SourceTV replay (the .dem
// dotactl --record keeps beside the log), not from the bot's vision. The replay is read by the master's replay-index
// extractor `stacktruth.exe` (docs/team/research/replay-index.md; path in STACKTRUTH_EXE or the default below).
// Per attempt and camp (B = the line's camp, A = fcamp of a double): `true` 1 when the camp spawned at :00 of the next
// minute (a neutral of that spawner left m_bIsWaitingToSpawn in [:59.5, :02]), `log` our res/fres, and when it did not
// spawn, what stood within BLOCK of the spawner origin at :59.9 (`grade`): the likely blockers. Valve's box is not in the
// replay, so BLOCK is a radius (7.41 boxes are 600-1,100 wide), not the box.
const fs = require('fs'), path = require('path'), { spawnSync } = require('child_process');

const BLOCK = +(process.env.STACKTRUTH_BLOCK || 900);
/** EC-060's guard distance, and the second after which a neutral that first got that far out was hit too late to clear. */
const GUARD = 400, LATE = 58;
const EXE = process.env.STACKTRUTH_EXE ||
  path.join(__dirname, '../../../../docs/team/research/replay-index/data/bin/stacktruth.exe');

function readTruth(dem) {
  const p = spawnSync(EXE, [dem], { maxBuffer: 1 << 30, encoding: 'utf8' });
  if (p.status !== 0) throw new Error(`stacktruth failed on ${dem}: ${p.stderr}`);
  const t = { sp: [], nc: [], snap: {}, cs: [] };
  for (const line of p.stdout.split('\n')) {
    if (!line.startsWith('{')) continue;
    const o = JSON.parse(line);
    if (o.k === 'sp') t.sp.push(o);
    else if (o.k === 'nc') t.nc.push(o);
    else if (o.k === 'snap' && o.at === 59.9) t.snap[o.min] = o.u;
    else if (o.k === 'cs') t.cs.push(o);
  }
  return t;
}

const near = (sp, x, y) => sp.reduce((b, s) => (Math.hypot(s.x - x, s.y - y) < Math.hypot(b.x - x, b.y - y) ? s : b));

/** Our camp number -> spawner, from the attempts' own cx/cy; a camp A never logged with cx/cy is its B's nearest other spawner. */
function campMap(rows, sp) {
  const m = {};
  for (const r of rows) if (r.cx != null && m[r.camp] === undefined) m[r.camp] = near(sp, r.cx, r.cy);
  for (const r of rows) {
    if (r.fcamp == null || m[r.fcamp] !== undefined || m[r.camp] === undefined) continue;
    const b = m[r.camp];
    m[r.fcamp] = near(sp.filter((s) => s !== b), b.x, b.y);
  }
  return m;
}

/** A camp's result at :00 of the next minute and, when it did not spawn, what stood within BLOCK of its origin at :59.9: its own
 *  neutrals that never went GUARD out since :45 (`stay`: not drawn out), first went GUARD out at or after :LATE (`late`) or
 *  before it and came back (`back`, each as that second, then `>` the second it was furthest out and `:` the nearest hero's
 *  distance to it then), other camps' neutrals, lane creeps and heroes. */
function grade(s, minute, t) {
  const spawned = t.nc.some((n) => n.sp === s.ent && n.t >= minute * 60 + 59.5 && n.t <= minute * 60 + 62);
  if (spawned) return { true: 1 };
  const c = { stay: 0, late: 0, back: [], other: 0, lane: 0, hero: 0 };
  for (const [, kind, who, x, y, maxd, out, turn, hero] of t.snap[minute] || []) {
    if (Math.hypot(s.x - x, s.y - y) > BLOCK) continue;
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
    const rows = store.query(`SELECT * FROM stack_attempts WHERE file = ? AND game = 1 AND res IN ('stacked', 'not_stacked')
      ORDER BY min`, path.resolve(log));
    if (rows.length === 0) { console.error(`no landed attempts in the store for ${log}`); continue; }
    const t = readTruth(dem);
    const m = campMap(rows, t.sp);
    for (const r of rows) {
      const o = { file: path.basename(log), min: r.min, double: r.double ?? null };
      const b = m[r.camp] ? grade(m[r.camp], r.min, t) : { true: null };
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
module.exports = { grade, campMap, near };
