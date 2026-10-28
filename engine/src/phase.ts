/**
 * Game phase per team: where the game is (laning, transition, midgame, push, defend, late), chosen from a snapshot
 * the host builds, with human-paced commitment (a margin and a confirm time against flicker, a minimum dwell, urgent
 * phases that skip the dwell) and team orders that override it. A phase supplies multipliers on per-bot state scores
 * (`Apply`, or `Prior` for `States.SetPrior`) and on host mode desires (`Desire`), blended in over `blend` seconds so
 * the team moves between postures together without five bots flipping on the same frame.
 *
 * The SDK never reads the game here: the snapshot is the host's. `DotaPhases()` is a default set built from
 * pro and high-MMR tower timings; hosts may `define` their own.
 */
import { get as getAdapter } from "./adapter";
import { TaskUnit } from "./types";

/** Alive structures of one team by tier (out of 3 for T1-T3). */
export interface TowerCount {
    t1: number;
    t2: number;
    t3: number;
}

/** What the host knows about the game, built only when the phase is re-evaluated. All but `time` optional. */
export interface PhaseSnapshot {
    /** Game clock, seconds (0 = horn). */
    time: number;
    towers?: { ours: TowerCount; theirs: TowerCount };
    netWorth?: { ours: number; theirs: number };
    /** Mean hero level. */
    levels?: { ours: number; theirs: number };
    /** Heroes alive. */
    alive?: { ours: number; theirs: number };
    /** Enemy heroes seen (visible or recently) anywhere. */
    enemiesSeen?: number;
    /** Enemy heroes seen near our structures, and the deepest tier among those structures (0: none). */
    threat?: { heroes: number; tier: number };
    /** Lane fronts, -1 at our T1 ... +1 at theirs. */
    waves?: number[];
    [extra: string]: unknown;
}

export interface PhaseSpec {
    name: string;
    /** Score in [0, 1], or undefined when the phase does not apply. Errors count as undefined. */
    score(this: void, snap: PhaseSnapshot): number | undefined;
    /** Entering skips the dwell and needs only `urgentConfirm` (e.g. defend). */
    urgent?: boolean;
    /** State name -> score multiplier; "*" for states not listed. Missing: 1. */
    bias?: Record<string, number>;
    /** Host mode key (e.g. "push", "defend", "farm") -> desire multiplier. Missing: 1. */
    desire?: Record<string, number>;
}

export interface PhaseConfig {
    /** Seconds between evaluations (snapshot builds). */
    interval: number;
    /** Bonus the current phase gets over rivals. */
    margin: number;
    /** Seconds a rival must stay best before it takes over (also when the current phase stops applying). */
    confirm: number;
    /** `confirm` for urgent phases. */
    urgentConfirm: number;
    /** Seconds a phase is held before a non-urgent rival may take over while it still applies. */
    minDwell: number;
    /** Seconds over which priors move from the old phase's to the new one's. */
    blend: number;
}

const config: PhaseConfig = { interval: 0.5, margin: 0.1, confirm: 2, urgentConfirm: 1, minDwell: 20, blend: 4 };

export function configure(c: Partial<PhaseConfig>): void {
    for (const [k, v] of pairs(c)) (config as any)[k] = v;
}

export interface DotaPhaseOptions {
    /** Laning ends at the first T1 kill or this time (replays.md: first T1 at 10:51 [8:44-12:02]; 10:00-11:00). */
    laningEnd: number;
    /** Transition holds until this time while T2s stand (safe T1 14:06, mid T1 15:16 in pubs). */
    transitionEnd: number;
    /** Late from this time, or from the first T3 down. */
    lateFrom: number;
}

const DOTA_DEFAULTS: DotaPhaseOptions = { laningEnd: 600, transitionEnd: 900, lateFrom: 2100 };

function t1Down(s: PhaseSnapshot): number {
    const t = s.towers;
    return t === undefined ? 0 : 6 - t.ours.t1 - t.theirs.t1;
}

function anyBelow(s: PhaseSnapshot, tier: "t2" | "t3"): boolean {
    const t = s.towers;
    return t !== undefined && (t.ours[tier] < 3 || t.theirs[tier] < 3);
}

/**
 * The default Dota set. Scores are fixed levels except push (advantage) and defend (threat). Bias keys are
 * state names (laning, pull, stack, rotate, farm, gank).
 */
export function DotaPhases(opts?: Partial<DotaPhaseOptions>): PhaseSpec[] {
    const o: DotaPhaseOptions = { ...DOTA_DEFAULTS, ...(opts ?? {}) };
    const laning = (s: PhaseSnapshot) => s.time < o.laningEnd && t1Down(s) === 0;
    return [
        {
            name: "laning",
            score: (s) => (laning(s) ? 0.6 : undefined),
        },
        {
            // 10:00-15:00, or until a T2 falls: T1s fall one by one, cores leave won/lost lanes,
            // supports smoke and rotate around the falling towers.
            name: "transition",
            score: (s) => (!laning(s) && s.time < o.transitionEnd && t1Down(s) < 4 && !anyBelow(s, "t2") ? 0.5 : undefined),
            bias: { laning: 0.6, pull: 0.7, rotate: 1.1, farm: 1.3, gank: 1.2 },
        },
        {
            // Lanes are over: farm the jungle and waves, fight around objectives (12:00-15:00 row).
            name: "midgame",
            score: (s) => (laning(s) ? undefined : 0.4),
            bias: { laning: 0.3, pull: 0.5, stack: 1.2, farm: 1.4, gank: 1.1 },
            desire: { farm: 1.2 },
        },
        {
            // An advantage worth cashing in: enemies dead, a net worth lead, waves on their side.
            name: "push",
            score: (s) => {
                if (laning(s)) return undefined;
                if (s.alive !== undefined && s.alive.ours < 3) return undefined;
                let adv = 0;
                if (s.alive !== undefined) adv += 0.15 * math.max(0, s.alive.ours - s.alive.theirs);
                const nw = s.netWorth;
                if (nw !== undefined && nw.theirs > 0) adv += math.min(0.3, math.max(0, (nw.ours - nw.theirs) / nw.theirs) * 1.5);
                const w = s.waves;
                if (w !== undefined && w.length > 0) {
                    let sum = 0;
                    for (const f of w) sum += f;
                    adv += 0.2 * math.max(0, sum / w.length);
                }
                return adv >= 0.2 ? math.min(1, 0.3 + adv) : undefined;
            },
            bias: { laning: 0.3, pull: 0.3, stack: 0.5, farm: 0.6, gank: 0.8 },
            desire: { push: 1.5, farm: 0.6 },
        },
        {
            // Two or more heroes on our structures (a tower under attack by 2+ enemies). During
            // laning only a 3-hero dive or a threat past T1 is a team matter; a 2-hero T1 dive is the lane's.
            name: "defend",
            urgent: true,
            score: (s) => {
                const th = s.threat;
                if (th === undefined || th.heroes < 2) return undefined;
                if (laning(s) && th.tier <= 1 && th.heroes < 3) return undefined;
                return math.min(1, 0.75 + 0.05 * (th.heroes - 2) + (th.tier >= 3 ? 0.05 : 0));
            },
            bias: { laning: 0.5, pull: 0.3, stack: 0.3, farm: 0.4, gank: 0.5, rotate: 0.6 },
            desire: { defend: 1.6, farm: 0.5, push: 0.6 },
        },
        {
            // High ground in reach for one side, or the clock says items and buybacks decide: group, farm less alone.
            name: "late",
            score: (s) => (!laning(s) && (s.time >= o.lateFrom || anyBelow(s, "t3")) ? 0.55 : undefined),
            bias: { laning: 0.2, pull: 0.2, stack: 0.6, farm: 1.1 },
            desire: { push: 1.2, farm: 0.8 },
        },
    ];
}

interface Order {
    phase: PhaseSpec;
    until: number;
    source: string;
}

interface TeamPhase {
    specs: PhaseSpec[];
    current?: PhaseSpec;
    previous?: PhaseSpec;
    since: number;
    score?: number;
    lastEval?: number;
    pending?: PhaseSpec;
    pendingSince: number;
    order?: Order;
    /** After an order ends, the next change needs no dwell. */
    released: boolean;
}

let teams: Record<number, TeamPhase | undefined> = {};

export function Reset(): void {
    teams = {};
}

function teamOf(team: number): TeamPhase {
    let t = teams[team];
    if (t === undefined) {
        t = { specs: DotaPhases(), since: 0, pendingSince: 0, released: false };
        teams[team] = t;
    }
    return t;
}

/** Sets a team's phases (default: `DotaPhases()`). The current phase is kept if a spec of that name remains. */
export function define(team: number, specs: PhaseSpec[]): void {
    const t = teamOf(team);
    t.specs = specs;
    const name = t.current?.name;
    t.current = name !== undefined ? specs.find((s) => s.name === name) : undefined;
    t.previous = undefined;
    t.pending = undefined;
}

function log(msg: string): void {
    getAdapter()?.log("phase", msg);
}

function emit(fields: [string, unknown][]): void {
    const a = getAdapter();
    if (a === undefined) return;
    if (a.event !== undefined) {
        a.event("phase", fields);
        return;
    }
    const parts = ["ev=phase"];
    for (const [k, v] of fields) if (v !== undefined) parts.push(k + "=" + tostring(v));
    a.log("phase", parts.join(" "));
}

function change(team: number, t: TeamPhase, next: PhaseSpec, score: number | undefined, why: string, now: number): void {
    const prev = t.current;
    t.previous = prev;
    t.current = next;
    t.since = now;
    t.score = score;
    t.pending = undefined;
    t.released = false;
    emit([
        ["team", team],
        ["from", prev?.name ?? "none"],
        ["to", next.name],
        ["score", score],
        ["why", why],
        ["order", t.order?.source],
    ]);
}

function evaluate(team: number, t: TeamPhase, snap: PhaseSnapshot, now: number): void {
    const cur = t.current;
    let best: PhaseSpec | undefined;
    let bestRaw: number | undefined;
    let bestEff = -Infinity;
    let curRaw: number | undefined;
    for (const spec of t.specs) {
        const [ok, v] = pcall(() => spec.score(snap));
        if (!ok) log("score " + spec.name + " error: " + tostring(v));
        const raw = ok ? (v as number | undefined) : undefined;
        if (raw === undefined) continue;
        if (spec === cur) curRaw = raw;
        const eff = spec === cur ? raw + config.margin : raw;
        if (eff > bestEff) {
            bestEff = eff;
            best = spec;
            bestRaw = raw;
        }
    }
    if (best === undefined) return;
    if (cur === undefined) {
        change(team, t, best, bestRaw, "start", now);
        return;
    }
    if (best === cur) {
        t.score = curRaw;
        t.pending = undefined;
        return;
    }
    const applies = curRaw !== undefined;
    const urgent = best.urgent === true;
    if (applies && !urgent && !t.released && now - t.since < config.minDwell) {
        t.pending = undefined;
        return;
    }
    if (t.pending !== best) {
        t.pending = best;
        t.pendingSince = now;
    }
    if (now - t.pendingSince < (urgent ? config.urgentConfirm : config.confirm)) return;
    change(team, t, best, bestRaw, t.released ? "released" : applies ? "best" : "n/a", now);
}

/**
 * From the host's tick, per team (any frame rate). Re-evaluates at most every `interval`, calling `build` only
 * then. Returns the current phase name (undefined until a phase applies).
 */
export function Tick(team: number, build: (this: void) => PhaseSnapshot): string | undefined {
    const a = getAdapter();
    if (a === undefined) return undefined;
    const t = teamOf(team);
    const now = a.now();
    if (t.order !== undefined && now >= t.order.until) {
        t.order = undefined;
        t.released = true;
        t.lastEval = undefined;
    }
    if (t.order === undefined && (t.lastEval === undefined || now - t.lastEval >= config.interval)) {
        t.lastEval = now;
        const [ok, snap] = pcall(build);
        if (ok) evaluate(team, t, snap as PhaseSnapshot, now);
        else log("snapshot error: " + tostring(snap));
    }
    return t.current?.name;
}

/** Forces `phase` for `secs` (team orders bus, a human's call). False for an unknown phase name. */
export function Order(team: number, phase: string, secs: number, source: string): boolean {
    const t = teamOf(team);
    const spec = t.specs.find((s) => s.name === phase);
    const a = getAdapter();
    if (spec === undefined || a === undefined) return false;
    const now = a.now();
    t.order = { phase: spec, until: now + secs, source };
    if (t.current !== spec) change(team, t, spec, undefined, "order", now);
    return true;
}

export function ClearOrder(team: number): void {
    const t = teams[team];
    if (t === undefined || t.order === undefined) return;
    t.order = undefined;
    t.released = true;
    t.lastEval = undefined;
}

export function Current(team: number): { name: string; since: number; score?: number; ordered?: string; until?: number } | undefined {
    const t = teams[team];
    if (t === undefined || t.current === undefined) return undefined;
    return { name: t.current.name, since: t.since, score: t.score, ordered: t.order?.source, until: t.order?.until };
}

function blended(t: TeamPhase | undefined, pick: (this: void, p: PhaseSpec) => Record<string, number> | undefined, key: string): number {
    if (t === undefined || t.current === undefined) return 1;
    const of = (p: PhaseSpec | undefined): number => {
        if (p === undefined) return 1;
        const m = pick(p);
        if (m === undefined) return 1;
        return m[key] ?? m["*"] ?? 1;
    };
    const to = of(t.current);
    if (t.previous === undefined || config.blend <= 0) return to;
    const now = getAdapter()?.now() ?? t.since;
    const f = math.min(1, math.max(0, (now - t.since) / config.blend));
    const from = of(t.previous);
    return from + (to - from) * f;
}

/** The current multiplier for a state's score (1 with no phase). */
export function Bias(team: number, state: string): number {
    return blended(teams[team], (p) => p.bias, state);
}

/** The current multiplier for a host mode desire key (1 with no phase). */
export function Desire(team: number, key: string): number {
    return blended(teams[team], (p) => p.desire, key);
}

/** A state score with the team's phase prior applied, clamped to [0, 1]; undefined stays undefined. */
export function Apply(team: number, state: string, raw: number | undefined): number | undefined {
    if (raw === undefined) return undefined;
    return math.min(1, math.max(0, raw * Bias(team, state)));
}

/** A `States.SetPrior` function: the bot's team phase prior on every state score. Bots without GetTeam: raw. */
export function Prior(): (this: void, bot: TaskUnit, state: string, raw: number) => number | undefined {
    return (bot, state, raw) => {
        const team = bot.GetTeam !== undefined ? bot.GetTeam() : undefined;
        return team === undefined ? raw : Apply(team, state, raw);
    };
}
