#!/usr/bin/env node
// Which spells Valve's GetEstimatedDamageToTarget counts, measured from ApiProbe logs: for a hero about itself the true
// and false estimates differ by exactly the counted spells it cannot cast, so a second with one spell cooling and every
// other ability ready gives that spell's share (0: Valve leaves it out; Meat Hook and Sand Storm do). Writes coverage.json
// beside this file, merged with what it holds, for gen.js. Only rows with ty=7 count: earlier probes passed a mask without
// pure damage, under which every pure spell (Meat Hook) read as left out.
//   node tools/spell-damage/coverage.js <probe log>...
'use strict';
const fs = require('fs');
const path = require('path');

const OUT = path.join(__dirname, 'coverage.json');
// Seconds sampled per spell before a verdict: one cast cools for 4 to 30 of them.
const MIN_SAMPLES = 3;

function fields(line) {
    const out = {};
    const body = line.slice(line.indexOf('[HEV]'));
    for (const m of body.matchAll(/(\w+)=(\S+)/g)) out[m[1]] = m[2];
    return out;
}

function measure(file) {
    const abil = {};
    const est = [];
    for (const line of fs.readFileSync(file, 'utf8').split('\n')) {
        if (!line.includes('[HEV]')) continue;
        if (line.includes('ev=apiprobe_abil ') && line.includes(' own=1 ')) {
            const k = fields(line);
            (abil[k.pid] = abil[k.pid] || []).push({ t: Number(k.t), name: k.name, lvl: Number(k.lvl), rem: Number(k.rem) });
        } else if (line.includes('ev=apiprobe_est ') && line.includes(' own=1 ')) {
            const k = fields(line);
            if (k.ty !== '7') continue;
            est.push({ t: Number(k.t), pid: k.src, d: Number(k.ef) - Number(k.et) });
        }
    }
    const samples = {};
    for (const e of est) {
        const latest = {};
        for (const r of abil[e.pid] || []) {
            if (r.t > e.t + 0.05) break;
            latest[r.name] = r;
        }
        // rem is written on a change of sign, so what is left now is the written rem less the time since.
        const cooling = Object.values(latest).filter((r) => r.lvl > 0 && r.rem > 0 && r.rem - (e.t - r.t) > 0.2);
        if (cooling.length !== 1) continue;
        (samples[cooling[0].name] = samples[cooling[0].name] || []).push(e.d);
    }
    return samples;
}

function median(xs) {
    const s = [...xs].sort((a, b) => a - b);
    return s[Math.floor(s.length / 2)];
}

function main() {
    const files = process.argv.slice(2);
    if (files.length === 0) throw new Error('usage: coverage.js <probe log>...');
    const cover = fs.existsSync(OUT) ? JSON.parse(fs.readFileSync(OUT, 'utf8')) : {};
    for (const file of files) {
        const label = path.basename(file, '.log');
        for (const [name, ds] of Object.entries(measure(file))) {
            const prev = cover[name] || { samples: 0, counted: 0, logs: [] };
            if (prev.logs.includes(label)) continue;
            // A sample counts the spell when its share is over a few points (the estimate rounds); medians decide below.
            prev.samples += ds.length;
            prev.counted += ds.filter((d) => d > 2).length;
            prev.logs.push(label);
            prev.median = median(ds);
            cover[name] = prev;
        }
    }
    for (const c of Object.values(cover)) {
        c.verdict = c.samples < MIN_SAMPLES ? 'unmeasured' : c.counted * 2 > c.samples ? 'counted' : 'left_out';
    }
    const sorted = Object.fromEntries(Object.keys(cover).sort().map((k) => [k, cover[k]]));
    fs.writeFileSync(OUT, JSON.stringify(sorted, null, 1) + '\n');
    for (const [k, c] of Object.entries(sorted)) console.log(`${c.verdict.padEnd(10)} ${k} ${c.counted}/${c.samples}`);
}

main();
