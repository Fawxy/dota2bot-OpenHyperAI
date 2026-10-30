// Stop when decided (master GOVERNANCE.md s5; skill eval-run rule 7a): after each game of a batch, whether any game still to
// run can change a bar of the ER spec. batch.js calls it when its spec names `er` (and optionally `look`, games per arm).
//   each:   a game outside the bounds decides it (not met); otherwise (no valid game yet included) open until the look or
//           the maximum N.
//   pooled: with `cap` (most `den` one game can add) it is decided once the remaining ON games cannot lift the rate to `min`
//           (or `den` to `minDen`), or cannot pull it below `min`; without `cap`, open until the look or the maximum N.
//   delta, mean: decided only at the interim look or the maximum N.
// Stop: a bar decided not met (an each or pooled bar: the verdict is FAIL whatever follows), every bar decided, or the
// interim look with every bar met. At the look with a bar not met the batch goes on (whether the bar is unreachable at
// the maximum N is the main loop's call).
'use strict';

/** Per-bar state 'met' | 'not met' | 'open' from barResults rows ({ b, result, num, den }) and the games per arm. */
function states(results, { on, off, look, max }) {
    const atLook = look > 0 && on === look && off === look;
    const atMax = on >= max && off >= max;
    const remOn = Math.max(0, max - on);
    return results.map(r => {
        const b = r.b;
        if (atLook || atMax) return r.result === 'met' ? 'met' : 'not met';
        // No valid game of the bar's arm yet (the first ON game failed lineup_check, say) is not a failure mid-batch.
        if (b.rule === 'each') return r.result === 'not met' && r.n !== 0 ? 'not met' : 'open';
        if (b.rule === 'pooled' && b.cap > 0 && Number.isFinite(r.num) && Number.isFinite(r.den)) {
            const c = b.cap * remOn, minDen = b.minDen || 1;
            if (r.den + c < minDen || (r.den + c > 0 && (r.num + c) / (r.den + c) < b.min)) return 'not met';
            if (r.den >= minDen && r.num / (r.den + c) >= b.min) return 'met';
        }
        return 'open';
    });
}

/** { stop, reason, states } for a batch after its latest game. */
function decide(results, counts) {
    const st = states(results, counts);
    const ids = s => results.filter((_, i) => st[i] === s).map(r => r.b.id);
    const failed = results.filter((r, i) => st[i] === 'not met' && ['each', 'pooled'].includes(r.b.rule)).map(r => r.b.id);
    const atLook = counts.look > 0 && counts.on === counts.look && counts.off === counts.look;
    if (failed.length) return { stop: true, reason: `bar not met: ${failed.join('; ')}`, states: st };
    if (atLook && st.every(s => s === 'met')) return { stop: true, reason: 'interim look: every bar met', states: st };
    if (!st.includes('open') && !atLook) return { stop: true, reason: 'every bar decided', states: st };
    if (atLook) return { stop: false, reason: `interim look: not met ${ids('not met').join('; ')}; going on to the maximum N`, states: st };
    return { stop: false, reason: `open: ${ids('open').length} of ${results.length} bars`, states: st };
}

module.exports = { decide, states };
