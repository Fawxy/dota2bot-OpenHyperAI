// A run label (games.label) read as its parts. One place for every tool that needs the arm or the seat of a game.
'use strict';

/**
 * `h2h742_A_rad_3` -> { run: 'h2h742', lineup: 'A', arm: '', seat: 2 }; `bis1_B_offrad_2` -> arm `off`, seat 2 (the arm word
 * has the seat glued on, which ledger.js's `_rad_` test never sees); `bis1r_C_noTdire_1` -> arm `noT`, seat 3;
 * `h2hlift1_B_off-dir_10` (batch.js arms `off-rad`, `off-dir`) -> arm `off`, seat 3. With no seat, `stockbase2_A_stock_7`
 * -> arm `stock`, seat 2, mirror: a mirror game, Radiant standing for ours.
 */
function parseLabel(label) {
    const m = label.match(/^(.*?)_([A-Z])_(?:ours_)?([A-Za-z]*?)-?(rad|dire?)_(\d+)$/) ||label.match(/^(.*?)()_?()(rad|dire)_(\d+)$/);
    if (m) return { run: m[1], lineup: m[2], arm: m[3], seat: m[4] === 'rad' ? 2 : 3, n: Number(m[5]) };
    const w = label.match(/^(.*?)_([A-Z])_([A-Za-z][\w-]*?)_(\d+)$/);
    if (w) return { run: w[1], lineup: w[2], arm: w[3], seat: 2, n: Number(w[4]), mirror: true };
    return undefined;
}

/**
 * The columns of view run_label: { batch, lineup, arm, seat ('rad' | 'dire' | null), rep }, each null when the label does not
 * say. Beyond parseLabel, a label with a lineup letter but no seat (`base1_A_stock_1`: a stock arm has no seat) gives batch,
 * lineup, arm and rep; a seat with no repetition number (`safe-tune1_A_rad`) still gives its seat. A label with no lineup
 * letter and no seat (`base1_smoke1`, `drill_retreat-hitback_fix1`) is all null: its first word is not known to be a batch.
 */
function runLabel(label) {
    const none = { batch: null, lineup: null, arm: null, seat: null, rep: null };
    if (typeof label !== 'string') return none;
    const p = parseLabel(label);
    // A mirror game has no seat of ours: gold.js lets Radiant stand for it, the view says NULL.
    if (p) return { batch: p.run || null, lineup: p.lineup || null, arm: p.arm || null, seat: p.mirror ? null : p.seat === 2 ? 'rad' : 'dire', rep: p.n };
    const m = label.match(/^(.*?)_([A-Z])_(?:ours_)?([\w-]*?)(?:_(\d+))?$/);
    if (!m) return none;
    const s = m[3].match(/^(.*?)-?(rad|dire?)$/);
    return {
        batch: m[1], lineup: m[2], arm: (s ? s[1] : m[3]) || null, seat: s ? (s[2] === 'rad' ? 'rad' : 'dire') : null,
        rep: m[4] === undefined ? null : Number(m[4]),
    };
}

module.exports = { parseLabel, runLabel };
