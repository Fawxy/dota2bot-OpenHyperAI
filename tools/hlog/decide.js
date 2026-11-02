// Stop when decided (master GOVERNANCE.md s5; skill eval-run rule 7a): after each game of a batch, whether any game still to
// run can change a bar of the ER spec. batch.js calls it when its spec names `er`; `look` (games per arm) adds the interim
// look, without it only the maximum N counts as a look.
//   each:   a game outside the bounds decides it (not met); otherwise (no valid game yet included) open until the maximum N.
//   pooled: with `cap` (most `den` one game can add) it is decided once the remaining games of the bar's arms cannot lift the
//           rate to `min` (or `den` to `minDen`), or cannot pull it below `min`; without `cap`, or when a game already added
//           more than `cap`, open until the maximum N. The interim look does not decide it: the look's CI rule is for delta
//           bars, and a pooled rate still open there can go either way.
//   delta, mean: decided only at the interim look or the maximum N.
// Stop: a bar decided not met (an each or pooled bar: the verdict is FAIL whatever follows), every bar decided, or the
// interim look with every bar met. At the look with a bar not met or still open the batch goes on (whether a delta bar is
// unreachable at the maximum N is the main loop's call).
'use strict';

/** Per-bar state 'met' | 'not met' | 'open' from barResults rows ({ b, result, n, num, den, maxDen }) and the games per arm. */
function states(results, counts) {
    const { on, off, look, max } = counts;
    const atLook = look > 0 && on === look && off === look;
    const atMax = on >= max && off >= max;
    return results.map(r => {
        const b = r.b;
        if (atMax) return r.result === 'met' ? 'met' : 'not met';
        // No valid game of the bar's arm yet (the first ON game failed lineup_check, say) is not a failure before the end.
        if (b.rule === 'each') return r.result === 'not met' ? (r.n !== 0 ? 'not met' : 'open') : atLook ? 'met' : 'open';
        if (b.rule === 'pooled') {
            if (!(b.cap > 0 && Number.isFinite(r.num) && Number.isFinite(r.den)) || r.maxDen > b.cap) return 'open';
            const rem = (b.arms || ['on']).reduce((s, a) => s + Math.max(0, max - (counts[a] || 0)), 0);
            const c = b.cap * rem, minDen = b.minDen || 1;
            if (r.den + c < minDen || (r.den + c > 0 && (r.num + c) / (r.den + c) < b.min)) return 'not met';
            if (r.den >= minDen && r.num / (r.den + c) >= b.min) return 'met';
            return 'open';
        }
        if (atLook) return r.result === 'met' ? 'met' : 'not met';
        return 'open';
    });
}

/** { stop, reason, states } for a batch after its latest game. */
function decide(results, counts) {
    const st = states(results, counts);
    const ids = s => results.filter((_, i) => st[i] === s).map(r => r.b.id);
    const failed = results.filter((r, i) => st[i] === 'not met' && ['each', 'pooled'].includes(r.b.rule)).map(r => r.b.id);
    const atMax = counts.on >= counts.max && counts.off >= counts.max;
    // A look at the maximum N is the maximum N: nothing is left to go on to.
    const atLook = !atMax && counts.look > 0 && counts.on === counts.look && counts.off === counts.look;
    // A cap a game has already exceeded: the slice file's cap is wrong, so the bar is judged only at the maximum N.
    const overCap = results.filter(r => r.b.rule === 'pooled' && r.b.cap > 0 && r.maxDen > r.b.cap).map(r => `${r.b.id} (a game added ${r.maxDen} > cap ${r.b.cap})`);
    const note = overCap.length && !atMax ? `; over cap, open until the maximum N: ${overCap.join('; ')}` : '';
    if (failed.length) return { stop: true, reason: `bar not met: ${failed.join('; ')}`, states: st };
    if (atLook && st.every(s => s === 'met')) return { stop: true, reason: 'interim look: every bar met', states: st };
    if (!st.includes('open') && !atLook) return { stop: true, reason: 'every bar decided', states: st };
    if (atLook) {
        const why = r => (r.b.rule === 'each' && r.n === 0 ? `${r.b.id} (no valid game)` : r.b.id);
        const open = results.filter((_, i) => st[i] === 'open').map(why);
        const parts = [['not met', ids('not met')], ['open', open]].filter(([, l]) => l.length).map(([k, l]) => `${k} ${l.join('; ')}`);
        return { stop: false, reason: `interim look: ${parts.join(', ')}; going on to the maximum N${note}`, states: st };
    }
    return { stop: false, reason: `open: ${ids('open').length} of ${results.length} bars${note}`, states: st };
}

module.exports = { decide, states };
