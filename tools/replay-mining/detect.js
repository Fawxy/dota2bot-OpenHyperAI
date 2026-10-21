'use strict';

// Pure detection functions over parsed replay events (see parser/main.go for the event schema).
// Divert (and so half-pull detection) needs `srcEnt` on lane-creep dmg events plus {"k":"creep",...} samples.
// The Go parser cannot attribute lane-creep damage to a unique entity, so it omits both; pulls then have
// divert === undefined, half === false, and aggregate treats them as full pulls.

const BOX_MARGIN = 300;
const DEFAULT_HALF_EXTENT = 150;
const STACK_WINDOW = [50, 58];
const PULL_WINDOW_S = 15;
const PULL_CLUSTER_S = 20;
const DIVERT_RADIUS = 1200;
const PATH_POINTS = 6;
const STACK_PATH_MAX_S = 6;

function median(values) {
    if (!values || values.length === 0) return undefined;
    const s = values.slice().sort((a, b) => a - b);
    const m = s.length >> 1;
    return s.length % 2 ? s[m] : (s[m - 1] + s[m]) / 2;
}

function dist(a, b) {
    return Math.hypot(a.x - b.x, a.y - b.y);
}

function secOfMinute(t) {
    return ((t % 60) + 60) % 60;
}

function downsamplePath(points, maxPoints, minSpacing = 150) {
    if (points.length <= 1) return points.slice();
    const kept = [points[0]];
    for (let i = 1; i < points.length - 1; i++) {
        if (dist(points[i], kept[kept.length - 1]) >= minSpacing) kept.push(points[i]);
    }
    const last = points[points.length - 1];
    if (dist(last, kept[kept.length - 1]) >= minSpacing || kept.length === 1) kept.push(last);
    else kept[kept.length - 1] = last;
    if (kept.length <= maxPoints) return kept;
    const out = [];
    for (let i = 0; i < maxPoints; i++) out.push(kept[Math.round((i * (kept.length - 1)) / (maxPoints - 1))]);
    return out;
}

function lastAtOrBefore(arr, t) {
    let lo = 0;
    let hi = arr.length - 1;
    let best = -1;
    while (lo <= hi) {
        const mid = (lo + hi) >> 1;
        if (arr[mid].t <= t) {
            best = mid;
            lo = mid + 1;
        } else hi = mid - 1;
    }
    return best < 0 ? undefined : arr[best];
}

function firstIndexAtOrAfter(arr, t) {
    let lo = 0;
    let hi = arr.length;
    while (lo < hi) {
        const mid = (lo + hi) >> 1;
        if (arr[mid].t < t) lo = mid + 1;
        else hi = mid;
    }
    return lo;
}

function push(map, key, value) {
    let list = map.get(key);
    if (!list) map.set(key, (list = []));
    list.push(value);
}

function buildIndex(events) {
    const sorted = events.map((e, i) => [e, i]).sort((a, b) => a[0].t - b[0].t || a[1] - b[1]).map((p) => p[0]);
    const idx = { heroPos: new Map(), neutral: new Map(), neutralAll: [], creeps: [], dmg: [] };
    for (const e of sorted) {
        if (e.k === 'pos') push(idx.heroPos, e.hero, e);
        else if (e.k === 'neutral') {
            push(idx.neutral, e.ent, e);
            idx.neutralAll.push(e);
        } else if (e.k === 'creep') idx.creeps.push(e);
        else if (e.k === 'dmg') idx.dmg.push(e);
    }
    return idx;
}

function inBox(camp, p, margin) {
    const hx = (camp.hx ?? DEFAULT_HALF_EXTENT) + margin;
    const hy = (camp.hy ?? DEFAULT_HALF_EXTENT) + margin;
    return Math.abs(p.x - camp.x) <= hx && Math.abs(p.y - camp.y) <= hy;
}

function campAt(camps, p, margin = BOX_MARGIN) {
    let best;
    let bestDist = Infinity;
    for (const c of camps) {
        if (!inBox(c, p, margin)) continue;
        const d = dist(c, p);
        if (d < bestDist) {
            bestDist = d;
            best = c;
        }
    }
    return best;
}

function parseRef(s, prefix) {
    return typeof s === 'string' && s.startsWith(prefix) ? Number(s.slice(prefix.length)) : undefined;
}

function neutralPos(idx, ent, t, hint) {
    const track = idx.neutral.get(ent);
    const sample = track && lastAtOrBefore(track, t);
    if (sample) return sample;
    return hint ? { x: hint[0], y: hint[1] } : undefined;
}

function campEnts(idx, camp, t) {
    const ents = new Set();
    for (const [ent, track] of idx.neutral) {
        const s = lastAtOrBefore(track, t);
        if (s && s.alive && inBox(camp, s, BOX_MARGIN)) ents.add(ent);
    }
    return ents;
}

function aliveBuckets(idx, camp, from, to) {
    const buckets = new Map();
    for (let i = firstIndexAtOrAfter(idx.neutralAll, from); i < idx.neutralAll.length; i++) {
        const e = idx.neutralAll[i];
        if (e.t > to) break;
        if (!e.alive || !inBox(camp, e, BOX_MARGIN)) continue;
        const sec = Math.floor(e.t);
        if (!buckets.has(sec)) buckets.set(sec, new Set());
        buckets.get(sec).add(e.ent);
    }
    return buckets;
}

function countBefore(idx, camp, t) {
    const buckets = aliveBuckets(idx, camp, t - 5, t - 1e-9);
    if (buckets.size === 0) return undefined;
    return buckets.get(Math.max(...buckets.keys())).size;
}

function countAfter(idx, camp, nextMinute) {
    const buckets = aliveBuckets(idx, camp, nextMinute, nextMinute + 5);
    if (buckets.size === 0) return undefined;
    return Math.max(...[...buckets.values()].map((s) => s.size));
}

function heroPath(idx, slot, from, to) {
    const track = idx.heroPos.get(slot) || [];
    const pts = [];
    for (let i = firstIndexAtOrAfter(track, from - 0.5); i < track.length && track[i].t <= to; i++) pts.push({ x: track[i].x, y: track[i].y });
    return downsamplePath(pts, PATH_POINTS);
}

function heroHits(idx, camps, onHit) {
    for (const ev of idx.dmg) {
        const slot = parseRef(ev.src, 'hero:');
        const ent = parseRef(ev.dst, 'neutral:');
        if (slot === undefined || ent === undefined) continue;
        const pos = neutralPos(idx, ent, ev.t, ev.campHint);
        const camp = pos && campAt(camps, pos);
        const heroSample = camp && idx.heroPos.has(slot) && lastAtOrBefore(idx.heroPos.get(slot), ev.t);
        if (!camp || !heroSample) continue;
        onHit(ev, slot, ent, camp, heroSample.team);
    }
}

function detectStacks(events, camps) {
    const idx = buildIndex(events);
    const seen = new Set();
    const stacks = [];
    heroHits(idx, camps, (ev, slot, _ent, camp, team) => {
        const sec = secOfMinute(ev.t);
        if (sec < STACK_WINDOW[0] || sec > STACK_WINDOW[1]) return;
        const minute = Math.floor(ev.t / 60);
        const dedupe = `${camp.x},${camp.y},${minute}`;
        if (seen.has(dedupe)) return;
        seen.add(dedupe);
        const before = countBefore(idx, camp, ev.t);
        const after = countAfter(idx, camp, (minute + 1) * 60);
        if (before === undefined || after === undefined || after <= before) return;
        const ents = campEnts(idx, camp, ev.t);
        let end = ev.t + STACK_PATH_MAX_S;
        for (let s = 1; s <= STACK_PATH_MAX_S; s++) {
            const left = [...ents].every((e) => {
                const p = lastAtOrBefore(idx.neutral.get(e), ev.t + s);
                return p && !inBox(camp, p, 0);
            });
            if (left) {
                end = ev.t + s;
                break;
            }
        }
        stacks.push({ camp, team, minute, aggroSec: sec, path: heroPath(idx, slot, ev.t, end) });
    });
    return stacks;
}

function detectPulls(events, camps) {
    const idx = buildIndex(events);
    const lastCluster = new Map();
    const pulls = [];
    heroHits(idx, camps, (ev, slot, _ent, camp, team) => {
        const clusterKey = `${slot}|${camp.x},${camp.y}`;
        if (ev.t - (lastCluster.get(clusterKey) ?? -Infinity) < PULL_CLUSTER_S) return;
        lastCluster.set(clusterKey, ev.t);
        const ents = campEnts(idx, camp, ev.t);
        const laneSrc = `lanecreep:${team}`;
        const hits = [];
        for (let i = firstIndexAtOrAfter(idx.dmg, ev.t); i < idx.dmg.length && idx.dmg[i].t <= ev.t + PULL_WINDOW_S; i++) {
            const d = idx.dmg[i];
            if (d.t > ev.t && d.src === laneSrc && ents.has(parseRef(d.dst, 'neutral:'))) hits.push(d);
        }
        if (hits.length === 0) return;
        const first = hits[0];
        const meet = neutralPos(idx, parseRef(first.dst, 'neutral:'), first.t, first.campHint);
        if (!meet) return;
        const meetPt = { x: meet.x, y: meet.y };
        const early = hits.filter((h) => h.t <= first.t + 5);
        const hasDivert = early.every((h) => h.srcEnt !== undefined && h.srcEnt >= 0);
        const engaged = new Set(early.map((h) => h.srcEnt));
        const nearby = new Set();
        for (let i = firstIndexAtOrAfter(idx.creeps, first.t - 1); i < idx.creeps.length && idx.creeps[i].t <= first.t; i++) {
            const c = idx.creeps[i];
            if (c.team === team && dist(c, meetPt) <= DIVERT_RADIUS) nearby.add(c.ent);
        }
        const denom = Math.max(nearby.size, engaged.size);
        const divert = !hasDivert ? undefined : denom > 0 ? engaged.size / denom : 0;
        pulls.push({
            camp,
            team,
            aggroSec: secOfMinute(ev.t),
            meet: meetPt,
            path: heroPath(idx, slot, ev.t, first.t),
            divert,
            half: divert !== undefined && divert < 0.6 && divert > 0,
        });
    });
    return pulls;
}

function round50(v) {
    return Math.round(v / 50) * 50;
}

function closestBy(items, target, secOf) {
    let best;
    for (const it of items) if (!best || Math.abs(secOf(it) - target) < Math.abs(secOf(best) - target)) best = it;
    return best;
}

function medianPoint(points) {
    if (points.length === 0) return undefined;
    return { x: median(points.map((p) => p.x)), y: median(points.map((p) => p.y)) };
}

function aggregate(stacks, pulls) {
    const groups = new Map();
    const group = (camp, team) => {
        const key = `${round50(camp.x)},${round50(camp.y)},${team}`;
        if (!groups.has(key)) groups.set(key, { key, camp, team, stacks: [], full: [], half: [] });
        return groups.get(key);
    };
    for (const s of stacks) group(s.camp, s.team).stacks.push(s);
    for (const p of pulls) group(p.camp, p.team)[p.half ? 'half' : 'full'].push(p);

    const mod30 = (p) => ((p.aggroSec % 30) + 30) % 30;
    const out = [];
    for (const g of groups.values()) {
        const entry = {
            key: g.key,
            team: g.team,
            type: g.camp.type,
            x: g.camp.x,
            y: g.camp.y,
            samples: { stacks: g.stacks.length, pulls: g.full.length, half: g.half.length },
        };
        if (g.full.length > 0) {
            entry.aggroSec = median(g.full.map(mod30));
            const rep = closestBy(g.full, entry.aggroSec, mod30);
            entry.pullPath = rep.path;
            entry.meetPoint = rep.meet;
        }
        if (g.half.length > 0) {
            entry.halfAggroSec = median(g.half.map(mod30));
            entry.halfMeetPoint = medianPoint(g.half.map((p) => p.meet));
        }
        if (g.stacks.length > 0) {
            entry.stackAggroSec = median(g.stacks.map((s) => s.aggroSec));
            entry.stackExitPath = closestBy(g.stacks, entry.stackAggroSec, (s) => s.aggroSec).path;
        }
        out.push(entry);
    }
    return out;
}

module.exports = { detectStacks, detectPulls, aggregate, downsamplePath, median };
