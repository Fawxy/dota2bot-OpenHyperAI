'use strict';
const test = require('node:test');
const assert = require('node:assert');
const { runLabel, parseLabel } = require('../label');

test('runLabel: every label shape in the logs, as batch, lineup, arm, seat and rep', () => {
    const row = (batch, lineup, arm, seat, rep) => ({ batch, lineup, arm, seat, rep });
    const cases = {
        'h2hlift1_A_owncore-rad_3': row('h2hlift1', 'A', 'owncore', 'rad', 3),
        'h2hlift1_B_owncorenolift-dir_10': row('h2hlift1', 'B', 'owncorenolift', 'dire', 10),
        'base1_B_offrad_2': row('base1', 'B', 'off', 'rad', 2),
        'base1_A_restdire_1': row('base1', 'A', 'rest', 'dire', 1),
        'bis1r_C_noTdire_1': row('bis1r', 'C', 'noT', 'dire', 1),
        'h2hbase1_A_tpbarrad_4': row('h2hbase1', 'A', 'tpbar', 'rad', 4),
        'h2h742_A_rad_3': row('h2h742', 'A', null, 'rad', 3),
        'base1_A_stock_1': row('base1', 'A', 'stock', null, 1),
        'sd3_B_on_2': row('sd3', 'B', 'on', null, 2),
        'safe-tune1_A_rad': row('safe-tune1', 'A', null, 'rad', null),
        'h2hX_ours_C_ours_off-rad_2': row('h2hX_ours', 'C', 'off', 'rad', 2),
        'h2hX_rad_3': row('h2hX', null, null, 'rad', 3),
        'base1_smoke1': row(null, null, null, null, null),
        'drill_retreat-hitback_fix1': row(null, null, null, null, null),
    };
    for (const [label, want] of Object.entries(cases)) assert.deepStrictEqual(runLabel(label), want, label);
    assert.deepStrictEqual(runLabel(null), row(null, null, null, null, null));
});

test('parseLabel keeps what gold.js and gate.js read: the run, lineup, arm, numeric seat and repetition', () => {
    assert.deepStrictEqual(parseLabel('h2hlift1_B_off-dir_10'), { run: 'h2hlift1', lineup: 'B', arm: 'off', seat: 3, n: 10 });
    assert.deepStrictEqual(parseLabel('base1_A_stock_1'), { run: 'base1', lineup: 'A', arm: 'stock', seat: 2, n: 1, mirror: true });
});
