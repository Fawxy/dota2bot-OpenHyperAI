/** @noSelfInFile */
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
    towers?: {
        ours: TowerCount;
        theirs: TowerCount;
    };
    netWorth?: {
        ours: number;
        theirs: number;
    };
    /** Mean hero level. */
    levels?: {
        ours: number;
        theirs: number;
    };
    /** Heroes alive. */
    alive?: {
        ours: number;
        theirs: number;
    };
    /** Enemy heroes seen (visible or recently) anywhere. */
    enemiesSeen?: number;
    /** Enemy heroes seen near our structures, and the deepest tier among those structures (0: none). */
    threat?: {
        heroes: number;
        tier: number;
    };
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
export declare function configure(c: Partial<PhaseConfig>): void;
export interface DotaPhaseOptions {
    /** Laning ends at the first T1 kill or this time (replays.md: first T1 at 10:51 [8:44-12:02]; 10:00-11:00). */
    laningEnd: number;
    /** Transition holds until this time while T2s stand (safe T1 14:06, mid T1 15:16 in pubs). */
    transitionEnd: number;
    /** Late from this time, or from the first T3 down. */
    lateFrom: number;
}
/**
 * The default Dota set. Scores are fixed levels except push (advantage) and defend (threat). Bias keys are
 * state names (laning, pull, stack, rotate, farm, gank).
 */
export declare function DotaPhases(opts?: Partial<DotaPhaseOptions>): PhaseSpec[];
export declare function Reset(): void;
/** Sets a team's phases (default: `DotaPhases()`). The current phase is kept if a spec of that name remains. */
export declare function define(team: number, specs: PhaseSpec[]): void;
/**
 * From the host's tick, per team (any frame rate). Re-evaluates at most every `interval`, calling `build` only
 * then. Returns the current phase name (undefined until a phase applies).
 */
export declare function Tick(team: number, build: (this: void) => PhaseSnapshot): string | undefined;
/** Forces `phase` for `secs` (team orders bus, a human's call). False for an unknown phase name. */
export declare function Order(team: number, phase: string, secs: number, source: string): boolean;
export declare function ClearOrder(team: number): void;
export declare function Current(team: number): {
    name: string;
    since: number;
    score?: number;
    ordered?: string;
    until?: number;
} | undefined;
/** The current multiplier for a state's score (1 with no phase). */
export declare function Bias(team: number, state: string): number;
/** The current multiplier for a host mode desire key (1 with no phase). */
export declare function Desire(team: number, key: string): number;
/** A state score with the team's phase prior applied, clamped to [0, 1]; undefined stays undefined. */
export declare function Apply(team: number, state: string, raw: number | undefined): number | undefined;
/** A `States.SetPrior` function: the bot's team phase prior on every state score. Bots without GetTeam: raw. */
export declare function Prior(): (this: void, bot: TaskUnit, state: string, raw: number) => number | undefined;
