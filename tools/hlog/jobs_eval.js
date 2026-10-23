#!/usr/bin/env node
// Support-clock metrics for team slices 7-9 (stack, pull, rotate states) from one dotactl test log:
//   node tools/hlog/jobs_eval.js <log> [--until 10:00]
// Per bot (latest ev=bot line: team, pos, hero): camp-job starts and aborts, stack attempts and outcomes
// (lane_stack), pull grades (lane_job), who executed each job (job_exec: SDK body frames vs step() frames),
// wisdom shrine trips (wisdom) and job-state task endings (state_task).
'use strict';
const fs = require('fs');

function parseTime(s) {
    if (s === undefined) return Infinity;
    const m = /^(\d+):(\d\d)$/.exec(s);
    return m ? Number(m[1]) * 60 + Number(m[2]) : Number(s);
}

function fields(line) {
    const i = line.indexOf('[HEV] ');
    if (i < 0) return undefined;
    const out = {};
    const re = /(\w+)=("[^"]*"|\S+)/g;
    let m;
    while ((m = re.exec(line.slice(i + 6))) !== null) out[m[1]] = m[2].replace(/^"|"$/g, '');
    out.t = Number(out.t);
    return out;
}

function mmss(t) {
    if (t === undefined || Number.isNaN(t)) return '-';
    const s = Math.round(t);
    return `${Math.floor(s / 60)}:${String(Math.abs(s % 60)).padStart(2, '0')}`;
}

function main() {
    const args = process.argv.slice(2);
    const file = args.find(a => !a.startsWith('--') && args[args.indexOf(a) - 1] !== '--until');
    const ui = args.indexOf('--until');
    const until = ui >= 0 ? parseTime(args[ui + 1]) : Infinity;
    if (!file) {
        console.error('usage: node tools/hlog/jobs_eval.js <log> [--until 10:00]');
        process.exit(2);
    }
    const bots = {};
    const per = pid => (bots[pid] ??= { starts: {}, aborts: {}, grades: {}, stacks: [], exec: [], wisdom: [], tasks: {}, trips: [], ganks: [] });
    for (const line of fs.readFileSync(file, 'utf8').split('\n')) {
        const e = fields(line);
        if (e === undefined || e.t > until) continue;
        if (e.ev === 'bot') Object.assign(per(e.pid), { hero: e.hero, team: e.team, pos: e.pos });
        else if (e.ev === 'lane_job_start') per(e.pid).starts[e.kind] = (per(e.pid).starts[e.kind] ?? 0) + 1;
        else if (e.ev === 'lane_job_abort') per(e.pid).aborts[e.reason] = (per(e.pid).aborts[e.reason] ?? 0) + 1;
        else if (e.ev === 'lane_job') per(e.pid).grades[e.grade] = (per(e.pid).grades[e.grade] ?? 0) + 1;
        else if (e.ev === 'lane_stack') per(e.pid).stacks.push(e);
        else if (e.ev === 'job_exec') per(e.pid).exec.push(e);
        else if (e.ev === 'wisdom') per(e.pid).wisdom.push(e);
        else if (e.ev === 'farm_trip_end') per(e.pid).trips.push(e);
        else if (e.ev === 'gank') per(e.pid).ganks.push(e);
        else if (e.ev === 'state_task' && e.state !== 'laning') {
            const k = `${e.state}:${e.result === 'ok' ? 'ok' : e.msg ?? e.reason}`;
            per(e.pid).tasks[k] = (per(e.pid).tasks[k] ?? 0) + 1;
        }
    }
    const fmt = o => Object.entries(o).map(([k, v]) => `${k}=${v}`).join(' ') || '-';
    console.log(`jobs_eval ${file}${until < Infinity ? ` until ${mmss(until)}` : ''}`);
    let sdkFrames = 0, legacyFrames = 0;
    for (const pid of Object.keys(bots).sort((a, b) => a - b)) {
        const b = bots[pid];
        const active = Object.keys(b.starts).length + b.stacks.length + b.exec.length + b.wisdom.length + b.trips.length + b.ganks.length;
        if (active === 0) continue;
        const stacked = b.stacks.filter(s => s.stacked === 'true' || s.stacked === '1');
        const err = b.stacks.map(s => Math.abs(Number(s.aggro) - Number(s.planned))).filter(x => !Number.isNaN(x));
        const meanErr = err.length ? (err.reduce((a, x) => a + x, 0) / err.length).toFixed(2) : '-';
        for (const x of [...b.exec, ...b.trips]) {
            sdkFrames += Number(x.sdk ?? 0);
            legacyFrames += Number(x.legacy ?? 0);
        }
        console.log(`pid ${pid} team=${b.team} pos=${b.pos} ${b.hero}`);
        console.log(`  starts: ${fmt(b.starts)} | aborts: ${fmt(b.aborts)} | pull grades: ${fmt(b.grades)}`);
        console.log(`  stacks: ${stacked.length}/${b.stacks.length} stacked (first ${mmss(stacked[0]?.t)}), |aggro-planned| mean ${meanErr} s [${err.map(x => x.toFixed(2)).join(' ')}]`);
        if (b.exec.length) console.log(`  sdk jobs: ${b.exec.length} (${fmt(b.exec.reduce((o, x) => ((o[`${x.kind}:${x.result === 'ok' ? 'ok' : x.msg ?? x.reason}`] = (o[`${x.kind}:${x.result === 'ok' ? 'ok' : x.msg ?? x.reason}`] ?? 0) + 1), o), {}))})`);
        if (Object.keys(b.tasks).length) console.log(`  state tasks: ${fmt(b.tasks)}`);
        if (b.trips.length) {
            const why = b.trips.reduce((o, x) => ((o[x.why] = (o[x.why] ?? 0) + 1), o), {});
            const camps = b.trips.reduce((a, x) => a + Number(x.camps ?? 0), 0);
            console.log(`  farm trips: ${b.trips.length} (${camps} camps; ${fmt(why)}; sdk trips ${b.trips.filter(x => x.sdk !== undefined).length})`);
        }
        for (const g of b.ganks) {
            console.log(`  gank ${mmss(Number(g.left))} -> pid ${g.target} lane ${g.lane} score ${g.score}: ${g.result} ${g.msg ?? ''} away ${Number(g.away).toFixed(1)} s`);
        }
        for (const w of b.wisdom) {
            console.log(`  wisdom ${mmss(Number(w.spawn))}: ${w.result}${w.reason ? ` (${w.reason})` : ''} left ${mmss(Number(w.left))} arrived ${mmss(Number(w.arrived))} taken +${w.taken ?? '-'} s away ${Number(w.away).toFixed(1)} s`);
        }
    }
    const total = sdkFrames + legacyFrames;
    console.log(`SDK-executed share of owned job and trip frames: ${total ? ((100 * sdkFrames) / total).toFixed(1) : '-'}% (${sdkFrames}/${total})`);
}

main();
