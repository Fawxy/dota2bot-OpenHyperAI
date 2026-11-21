// The priced leave's replay (decision centre pilot step 3; master docs/proposals/decision-centre/step2-3-decider.md s8): runs the real
// LeavePrice.Decide (the built bots/FunLib/humaniser/leave_price.lua) in fengari on banked leaves' inputs, at each margin.
// Usage: node tests/humaniser/leave_replay.js <rows.json> <out.json> [--margins 0,30,60]
//   rows.json: [{ id, i: Inputs, inc }] (master tools/dc/replay.js writes it); out.json: [{ id, M: { <margin>: Result } }].
const fs = require('fs');
const path = require('path');
const { newState, doString, getGlobal } = require('./harness');

const args = process.argv.slice(2);
if (args.length < 2 || args.includes('--help')) {
    console.log('node tests/humaniser/leave_replay.js <rows.json> <out.json> [--margins 0,30,60]');
    process.exit(args.includes('--help') ? 0 : 1);
}
const mi = args.indexOf('--margins');
const margins = (mi >= 0 ? args[mi + 1] : '0,30,60').split(',').map(Number);
const rows = JSON.parse(fs.readFileSync(args[0], 'utf8'));

const lit = (v) => {
    if (v === null || v === undefined) return 'nil';
    if (typeof v === 'number') return Number.isFinite(v) ? String(v) : '1e9';
    if (typeof v === 'boolean') return v ? 'true' : 'false';
    if (typeof v === 'string') return JSON.stringify(v);
    if (Array.isArray(v)) return `{${v.map(lit).join(',')}}`;
    return `{${Object.entries(v).map(([k, x]) => `[${JSON.stringify(k)}]=${lit(x)}`).join(',')}}`;
};

const L = newState(path.resolve(__dirname, '../..'));
const src = `dofile(HARNESS_DIR .. "/dota_stubs.lua")
FreshHumaniser({ Enable = false })
local LP = require("bots/FunLib/humaniser/leave_price")
local ROWS = ${lit(rows)}
local MARGINS = ${lit(margins)}
local out = {}
local function num(x) if x == nil then return "null" end return string.format("%.4f", x) end
for _, r in ipairs(ROWS) do
    local per = {}
    for _, m in ipairs(MARGINS) do
        LP.SETTINGS.Margin = m
        local x = LP.Decide(r.i, r.inc)
        per[#per + 1] = string.format('"%d":{"pick":"%s","hard":%s,"stay":%s,"leave":%s,"d":%s,"pds":%s,"pdl":%s,"pks":%s,"pkl":%s,"F":%s,"W":%s,"M":%d}',
            m, x.pick, x.hard and ('"' .. x.hard .. '"') or "null", num(x.stay), num(x.leave), num(x.d), num(x.pds), num(x.pdl), num(x.pks), num(x.pkl), num(x.F), num(x.W), x.M)
    end
    out[#out + 1] = string.format('{"id":%s,"M":{%s}}', string.format("%q", tostring(r.id)), table.concat(per, ","))
end
REPLAY_OUT = "[" .. table.concat(out, ",\\n") .. "]"
`;
const err = doString(L, src);
if (err) { console.error(err); process.exit(1); }
fs.writeFileSync(args[1], getGlobal(L, 'REPLAY_OUT'));
console.log(`leave_replay: ${rows.length} rows x ${margins.length} margins -> ${args[1]}`);
