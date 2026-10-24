/** @noSelfInFile */
import { TaskUnit } from "./types";
export interface ModesConfig {
    /** Bonus the host mode gets while the bot is in it; a rival must beat the host's desire by this to take over. */
    hold: number;
    /**
     * Seconds the layer commits to an interrupt: after another mode took over from the host, that mode keeps at least
     * the desire it took over with, and the host gives way by `hold`.
     */
    interruptDwell: number;
    /** Desire the host mode holds at least while the current state's body is committed. */
    commit: number;
    /** Seconds idle (and within `idleMove`) in the asserted host mode before the layer stands aside. */
    idleAfter: number;
    /** Seconds the layer stands aside (every score passes) after an idle episode in its host mode. */
    idleBackoff: number;
    /** Units the bot may drift and still count as standing in the same place. */
    idleMove: number;
    /** A visit to another mode shorter than this, ending back in the mode it left, counts as a blip. */
    blip: number;
    /** Seconds between `ev=modes` summary lines per bot. */
    summaryEvery: number;
    /** Assert for a current state that is chosen but not owned (shadow) too. */
    shadow: boolean;
}
export declare function configure(c: Partial<ModesConfig>): void;
export type ModeHow = "pass" | "set" | "suppress";
export interface Decision {
    desire: number;
    /** pass: the host's own score; set: the layer's host desire; suppress: 0 by the layer. */
    how: ModeHow;
}
/**
 * Modes the layer decides outright: suppressed unless they host the current state. `pass`: reason tags whose score
 * an owned mode still passes (e.g. a flight from lethal danger). Replaces the previous lists.
 */
export declare function SetOwned(modes: number[], opts?: {
    pass?: string[];
}): void;
/** Whether the authority applies to this bot (kill switch, team, position); read on every call. */
export declare function SetEnabled(fn: (this: void, bot: TaskUnit) => boolean): void;
export declare function Forget(bot: TaskUnit): void;
/** Whether the layer decides this bot's mode desires now. */
export declare function Asserting(bot: TaskUnit): boolean;
/** The final desire for `mode` from the host's own `score` for it; call at the end of every mode's scoring. */
export declare function Decide(bot: TaskUnit, mode: number, score: number, reason?: string): Decision;
/** Every frame from the host's global tick: switch and blip counts, the idle watchdog, periodic `ev=modes`. */
export declare function Tick(bot: TaskUnit): void;
export declare function Stats(bot: TaskUnit): {
    switches: number;
    blips: number;
    idles: number;
    asides: number;
    asserting: boolean;
    mode?: number;
};
