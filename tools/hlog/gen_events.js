'use strict';
// Writes EVENTS.md and events.json from the typed declaration (typescript/bots/FunLib/humaniser/events.ts, data only; Node
// strips the types). `node gen_events.js` writes both; `--check` exits 1 when either is stale (test/events.test.js runs it).
const fs = require('fs');
const path = require('path');

const SRC = path.join(__dirname, '../../typescript/bots/FunLib/humaniser/events.ts');
const MD = path.join(__dirname, 'EVENTS.md');
const JSON_OUT = path.join(__dirname, 'events.json');

// `bool` prints 1/0. Only `str` is forced to a text column; the others (`numstr`: a number printed from a string, `mixed`: a number or a
// `?` placeholder) are left to the store's inference, which keeps a column numeric until a value is not a number.
const STORE_KIND = { num: 'num', bool: 'num', numstr: 'num', mixed: 'num', str: 'text' };
const tableName = ev => `ev_${String(ev).replace(/\W/g, '_')}`;

// events.ts is read as TypeScript, so Node must strip types itself (Node >= 22.18); the file must use erasable syntax only.
function load() {
    try {
        return require(SRC).EVENTS;
    } catch (e) {
        throw new Error(`cannot read events.ts (needs Node >= 22.18 for type stripping, erasable syntax only; running ${process.version}): ${e.message}`);
    }
}

// Field and event meanings: the comment (`/** */` or `//` lines) right above a field or an event in events.ts. They go to
// EVENTS.md only; events.json (and so the store version) ignores them, so a comment edit never empties the store. A field
// from a spread (`...BOT`) keeps the comment it has where it is declared.
function docs(text) {
    const consts = {};
    const events = {};
    let pending = [];
    let inComment = false;
    let top = null;
    let ev = null;
    const take = () => {
        const d = pending.join(' ').replace(/\s+/g, ' ').trim();
        pending = [];
        return d || undefined;
    };
    for (const raw of text.split(/\r?\n/)) {
        const line = raw.trim();
        if (inComment) {
            const end = line.indexOf('*/');
            pending.push((end >= 0 ? line.slice(0, end) : line).replace(/^\*\s?/, ''));
            if (end >= 0) inComment = false;
            continue;
        }
        if (line.startsWith('/**')) {
            const body = line.slice(3);
            const end = body.indexOf('*/');
            pending.push(end >= 0 ? body.slice(0, end) : body);
            if (end < 0) inComment = true;
            continue;
        }
        if (line.startsWith('//')) {
            pending.push(line.slice(2));
            continue;
        }
        let m;
        if ((m = /^export const (\w+) = \{/.exec(line))) {
            top = { spreads: [], fields: {} };
            consts[m[1]] = top;
            ev = null;
            pending = [];
            continue;
        }
        if (top && top === consts.EVENTS && !ev && (m = /^(\w+): \{$/.exec(line))) {
            ev = { spreads: [], fields: {}, doc: take() };
            events[m[1]] = ev;
            continue;
        }
        const into = ev || top;
        if (into && (m = /^\.\.\.(\w+),?$/.exec(line))) {
            into.spreads.push(m[1]);
            pending = [];
            continue;
        }
        if (into && (m = /^(\w+): "\w+",?$/.exec(line))) {
            const d = take();
            if (d) into.fields[m[1]] = d;
            continue;
        }
        if (line === '},' && ev) ev = null;
        else if (line.startsWith('} as const')) top = ev = null;
        if (line) pending = [];
    }
    const fieldDoc = (blk, f) => blk.fields[f] ?? blk.spreads.map(s => consts[s] && fieldDoc(consts[s], f)).find(Boolean);
    return { event: e => events[e]?.doc, field: (e, f) => (events[e] ? fieldDoc(events[e], f) : undefined) };
}

// An event's section: its comment, the fields with no meaning on one line, then one line per field with a meaning.
function section(ev, fields, doc) {
    const plain = [];
    const meant = [];
    for (const [f, t] of Object.entries(fields)) {
        const d = doc.field(ev, f);
        if (d) meant.push(`- \`${f}\` ${t}: ${d}`);
        else plain.push(`\`${f}\` ${t}`);
    }
    const out = [`## ${ev}`, ''];
    if (doc.event(ev)) out.push(doc.event(ev), '');
    if (plain.length) out.push(plain.join(', '), '');
    if (meant.length) out.push(...meant, '');
    return out;
}

const NO_DOCS = { event: () => undefined, field: () => undefined };

function build(events, doc = NO_DOCS) {
    const kinds = {};
    for (const [ev, fields] of Object.entries(events)) {
        const k = {};
        for (const [f, t] of Object.entries(fields)) {
            if (!STORE_KIND[t]) throw new Error(`${ev}.${f}: unknown type ${t}`);
            if (STORE_KIND[t] === 'text') k[f] = 'text';
        }
        if (Object.keys(k).length) kinds[tableName(ev)] = k;
    }
    const json = JSON.stringify({ generated: 'by gen_events.js from events.ts; do not edit', events, kinds }, null, 1) + '\n';
    const md = [
        '# Humaniser events (generated)',
        '',
        'Generated by `node tools/hlog/gen_events.js` from `typescript/bots/FunLib/humaniser/events.ts`; do not edit. Every',
        '`[HEV] ev=<name>` line the humaniser prints through `Telemetry.Event` is listed with its fields. `bool` prints as',
        '1/0. Any field may be absent on a line (a nil value is not printed). The store reads the same declaration from',
        '`events.json` (`str` columns are text; the others are inferred from the values).',
        '',
        `${Object.keys(events).length} typed events.`,
        '',
        ...Object.entries(events).flatMap(([ev, fields]) => section(ev, fields, doc)),
        '## Untyped',
        '',
        'Printed through `Telemetry.EventUntyped`, name or fields built at run time, so nothing checks them: the',
        '`farm_pattern` trip events (`farm_trip_*`, one name per trip step) and the engine adapter events in `tasks.ts`',
        '(`ev=state*` and the like). The store infers their column kinds.',
        '',
    ].join('\n');
    return { json, md };
}

function main() {
    const { json, md } = build(load(), docs(fs.readFileSync(SRC, "utf8")));
    const check = process.argv.includes('--check');
    let stale = false;
    for (const [file, want] of [[JSON_OUT, json], [MD, md]]) {
        const have = fs.existsSync(file) ? fs.readFileSync(file, 'utf8').replace(/\r\n/g, '\n') : undefined;
        if (have === want) continue;
        stale = true;
        if (check) console.error(`stale: ${path.basename(file)} (run node tools/hlog/gen_events.js)`);
        else fs.writeFileSync(file, want);
    }
    if (check && stale) process.exit(1);
    if (!check) console.log(`wrote EVENTS.md and events.json (${Object.keys(load()).length} events)`);
}

if (require.main === module) main();
module.exports = { load, build, docs, tableName, STORE_KIND };
