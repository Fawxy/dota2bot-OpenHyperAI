'use strict';
// node mine.js [out dir]   reads out/*.ndjson (parser output), writes out/aggregate.json for gen_camps.js

const fs = require('fs');
const path = require('path');
const { detectStacks, detectPulls, aggregate } = require('./detect');

function mineFile(file) {
    const events = fs.readFileSync(file, 'utf8').split('\n').filter(Boolean).map((l) => JSON.parse(l));
    const camps = events.filter((e) => e.k === 'camp');
    return { stacks: detectStacks(events, camps), pulls: detectPulls(events, camps) };
}

if (require.main === module) {
    const dir = process.argv[2] || path.join(__dirname, 'out');
    const stacks = [];
    const pulls = [];
    for (const f of fs.readdirSync(dir).filter((n) => n.endsWith('.ndjson'))) {
        const r = mineFile(path.join(dir, f));
        stacks.push(...r.stacks);
        pulls.push(...r.pulls);
        console.log(`${f}: ${r.stacks.length} stacks, ${r.pulls.length} pulls`);
    }
    fs.writeFileSync(path.join(dir, 'aggregate.json'), JSON.stringify(aggregate(stacks, pulls), null, 2));
}

module.exports = { mineFile };
