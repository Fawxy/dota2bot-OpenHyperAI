/** @noSelfInFile */
import { TaskFactory } from "./runner";
import { Result, TaskUnit } from "./types";
/** A posture holds while chosen and never ends by itself; a job has a goal and ends ok or with a reason. */
export type StateKind = "posture" | "job";
export interface StateSpec {
    name: string;
    kind: StateKind;
    /** Mode id the body runs under. */
    host: number;
    tier?: string;
    /** Claim floor for the host mode. Default 0: the state only acts when the host's own arbitration picks it. */
    floor?: number;
    /** Seconds away from the host before the task is preempted. Default 3 for postures, 0 for jobs. */
    preemptAfter?: number;
    /** Seconds without a Step before the task is preempted. Default math.huge (the preempt rule bounds it). */
    stallAfter?: number;
    /** Score in [0, 1], or undefined when the state does not apply now. Errors count as undefined. */
    score(this: void, bot: TaskUnit): number | undefined;
    body: TaskFactory;
    /** Passed to the task: a returned string ends it `interrupted` with that message (e.g. a job's safety checks). */
    guard?: (this: void) => string | undefined;
    /** Called once per task end (any reason, including preempts that the layer restarts), after the layer's own. */
    onEnd?: (this: void, result: Result, info: {
        label?: string;
        steps: number;
    }) => void;
    /**
     * Mode authority (`Modes`): the host mode's desire while this state is current, from the host's own score for
     * that mode and its reason tag. Default: the host's score. Undefined also means the host's score.
     */
    desire?: (this: void, bot: TaskUnit, score: number, reason?: string) => number | undefined;
    /** Mode authority: true for another mode's score this state replaces (that score reads as 0 while current). */
    refuses?: (this: void, bot: TaskUnit, mode: number, reason?: string) => boolean;
    /** Mode authority: true while the body is mid-action; the host mode then holds at least `Modes` `commit`. */
    committed?: (this: void, bot: TaskUnit) => boolean;
}
export interface StatesConfig {
    /** Seconds between selections. */
    interval: number;
    /** Bonus the current state gets over rivals. */
    sticky: number;
    /** Seconds a posture is held before another posture may take over. */
    minDwell: number;
    /** Raw score a rival needs to break a running owned job. */
    jobBreak: number;
    /** Seconds a failed job cannot be chosen again. */
    cooldown: number;
    /** Seconds after a task ended before it is restarted outside its host mode (or after an error). */
    restart: number;
}
export declare function configure(c: Partial<StatesConfig>): void;
/** Which states the SDK runs for which bot; read at every selection, so it may change during the game. */
export declare function SetOwned(fn: (this: void, bot: TaskUnit, state: string) => boolean): void;
/** Registers (or replaces) a bot's states. The current state is kept if a spec of that name remains. */
export declare function define(bot: TaskUnit, specs: StateSpec[]): void;
export declare function Forget(bot: TaskUnit): void;
type Prior = (this: void, bot: TaskUnit, state: string, raw: number) => number | undefined;
/**
 * A prior on every raw score (e.g. `Phase.Prior()`), applied before stickiness and the job-break check; undefined
 * from it makes the state not applicable. A failing prior is logged and the raw score used. Nil removes it.
 */
export declare function SetPrior(fn: Prior | undefined): void;
/** Every frame from the host's global tick, before the runner's Tick. Selects at `interval`, starts and restarts. */
export declare function Tick(bot: TaskUnit): void;
/** From the host mode's Think(): steps the current owned state's task when it runs on `host`; false otherwise. */
export declare function Step(bot: TaskUnit, host: number): boolean;
/** The current state's spec (chosen, owned or not), for the mode authority. */
export declare function CurrentSpec(bot: TaskUnit): StateSpec | undefined;
export declare function Current(bot: TaskUnit): {
    name: string;
    kind: StateKind;
    host: number;
    since: number;
    score?: number;
    owned: boolean;
    running: boolean;
    starts: number;
} | undefined;
export {};
