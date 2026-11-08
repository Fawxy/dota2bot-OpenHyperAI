/**
 * The missing wave (lane controller slice 2c, `docs/team/slices/lane-controller.md`; user 09/11/2026): per team and lane,
 * one enemy wave at a time is followed from its spawn, and the lane learns whether it arrived. Each second the schedule's
 * spot for the wave walks from the enemy spawn along the lane path at the lane creeps' speed, clamped to our lead lane
 * creep (a wave meets ours and stops). The wave is due (D) the first second its spot comes within DueNear of our lead (or
 * passes it); its window W is [D - WindowBefore, D + ArriveWindow]. It resolves at the window's end:
 *   `p` present: at some second of W the count of visible enemy lane creeps on the lane rose RiseMin or more above its
 *       count the second before W (the wave walked into view; a radius sighting saturates, since our lead creep is where
 *       their previous wave still fights, offline score 329 games);
 *   `a` absent: no such rise, and our lead creep stood within DueNear of the spot on at least half of W's seconds (we were
 *       there to see it; the wave was pulled, blocked or cut);
 *   `u` unknown: otherwise, or the wave never came due within GiveUp of its spawn (no own creeps, no reading).
 * The controller's next wave read takes the resolved fact (`Take`, once); an `a` resolved between reads also breaks a chosen
 * pull that has not left (lane_control PullBreak). The rule lives in `Step` alone (pure, the tests' entry) so it can be
 * swapped without touching the plumbing; the inputs are the lane push view's (LanePush.CreepsNow: the same visible enemy
 * lane creeps and lead creep its fill uses), so the offline script `absent.js` and the bot agree.
 * CANDIDATE(enemy_wave_tracker): the lane controller is its one reader.
 */
import { Lane, Team } from "bots/ts_libs/dota";
import * as LaneConfig from "bots/FunLib/humaniser/lane_config";
import * as LanePush from "bots/FunLib/humaniser/lane_push";
import * as WorldFacts from "bots/FunLib/humaniser/world_facts";

export type Sight = "p" | "a" | "u";

/** Path units and seconds. RiseMin and the window are `fitted` (the offline score on 329 banked 5v5 games, the slice file's
 *  (2c) Facts rows); Speed is derived live; DueNear and GiveUp are `judgement`. */
export const SETTINGS = {
    /** The spot this near our lead creep (or past it) is due; the lead this near the spot counts as us watching it. */
    DueNear: 300,
    /** The visible enemy lane creep count rising this much over its count before the window is the wave arriving. */
    RiseMin: 2,
    /** W = [D - WindowBefore, D + ArriveWindow]; the base count is the second before W. With under WindowBefore + 1 seconds
     *  of history at D (a wave picked up late) the base is the count at D. */
    WindowBefore: 5,
    ArriveWindow: 10,
    /** A wave not due this long after its spawn resolves `u`; the tracker then catches up to the current wave. */
    GiveUp: 60,
    /** Fallback only: the lane creeps' speed is read live (WorldFacts.Latest). */
    Speed: 325,
};

/** A wave's resolution: `due` D (undefined when it never came due). */
export interface Resolved {
    ts: number;
    ew: Sight;
    due?: number;
}

interface Tracked {
    ts: number;
    due?: number;
    /** The enemy creep count the second before W. */
    base?: number;
    seen: boolean;
    /** W seconds so far, and those with our lead within DueNear of the spot. */
    wSecs: number;
    ownNear: number;
    /** The last WindowBefore + 1 seconds before D is known: [enemy count, lead at the spot] per second, oldest first. */
    recent: [number, boolean][];
}

export interface State {
    track?: Tracked;
    resolved?: Resolved;
    /** The whole second last stepped. */
    at?: number;
}

/** What one second's step reads: the enemy spawn's path distance, their direction of travel along the path, the lane
 *  creep speed, our lead lane creep's path distance (undefined with none) and the visible enemy lane creeps on the lane. */
export interface Inputs {
    now: number;
    spawn: number;
    dir: number;
    speed: number;
    lead?: number;
    count: number;
}

function fresh(ts: number): Tracked {
    return { ts, seen: false, wSecs: 0, ownNear: 0, recent: [] };
}

/** Resolves the wave and follows the next one; after a GiveUp (60 s, two waves) the current wave, not one already 30 s old. */
function resolve(st: State, w: Tracked, ew: Sight, cycle: number, t: number): Resolved {
    st.resolved = { ts: w.ts, ew, due: w.due };
    st.track = fresh(math.max(w.ts + cycle, math.floor(t / cycle) * cycle));
    return st.resolved;
}

/** One second of the rule for the wave `st` follows (idempotent within a second); `cycle` the wave cycle (30 s). Returns the
 *  resolution this second made, if any. */
export function Step(st: State, i: Inputs, cycle: number): Resolved | undefined {
    const s = SETTINGS;
    const t = math.floor(i.now);
    if (st.at === t) return undefined;
    st.at = t;
    if (st.track === undefined) st.track = fresh(math.floor(t / cycle) * cycle);
    const w = st.track;
    if (t < w.ts) return undefined;
    const raw = i.spawn + i.dir * i.speed * (t - w.ts);
    const passed = i.lead !== undefined && i.dir * (raw - i.lead) > 0;
    const spot = passed ? i.lead! : raw;
    const own = i.lead !== undefined && math.abs(i.lead - spot) <= s.DueNear;
    if (w.due === undefined) {
        if (i.lead !== undefined && i.dir * (raw - i.lead) >= -s.DueNear) {
            w.due = t;
            // The history holds up to WindowBefore + 1 seconds: the oldest is the second before W (the base), the rest are W's.
            const [b] = w.recent.length > s.WindowBefore ? w.recent.shift()! : [i.count];
            w.base = b;
            for (const [c, o] of w.recent) {
                w.wSecs++;
                if (c - b >= s.RiseMin) w.seen = true;
                if (o) w.ownNear++;
            }
            w.recent = [];
        } else {
            w.recent.push([i.count, own]);
            if (w.recent.length > s.WindowBefore + 1) w.recent.shift();
            return t >= w.ts + s.GiveUp ? resolve(st, w, "u", cycle, t) : undefined;
        }
    }
    if (t <= w.due + s.ArriveWindow) {
        w.wSecs++;
        if (i.count - w.base! >= s.RiseMin) w.seen = true;
        if (own) w.ownNear++;
    }
    if (t >= w.due + s.ArriveWindow) return resolve(st, w, w.seen ? "p" : w.ownNear * 2 >= w.wSecs ? "a" : "u", cycle, t);
    return undefined;
}

/** The resolved fact not yet read, cleared by this call (one wave read takes it). */
export function Take(st: State): Resolved | undefined {
    const r = st.resolved;
    st.resolved = undefined;
    return r;
}

// ------------------------------------------------------------------------------------------------- the game's view

const states: Record<string, State> = {};

export function ResetCache(): void {
    for (const k in states) delete states[k];
}

export function StateOf(team: number, lane: Lane): State {
    const key = `${team}:${lane}`;
    let st = states[key];
    if (st === undefined) {
        st = {};
        states[key] = st;
    }
    return st;
}

/** The tracker's second for `team`'s side of `lane` (the calling script must be `team`'s); a frame within a stepped second
 *  costs nothing. Returns the resolution this second made, if any. */
export function Tick(team: number, lane: Lane, now: number): Resolved | undefined {
    const st = StateOf(team, lane);
    if (st.at === math.floor(now)) return undefined;
    const [path, , own, enemy] = LanePush.CreepsNow(team, lane);
    if (path === undefined) return undefined;
    const e = team === Team.Radiant ? Team.Dire : Team.Radiant;
    const [spawn, dir] = LanePush.SpawnOf(path, e);
    return Step(
        st,
        { now, spawn, dir, speed: WorldFacts.Latest("lane_creep_speed", SETTINGS.Speed), lead: LanePush.LeadOf(own, team), count: enemy.length },
        LaneConfig.Settings().Timing.WaveCycle,
    );
}
