/** @noSelfInFile */
import { SkillProfile, TaskUnit } from "./types";
/** Last-hit error half-width (fraction of own damage) at skill 0 and 1. */
export declare const LAST_HIT_ERROR_LOW = 0.15;
export declare const LAST_HIT_ERROR_HIGH = 0.02;
/** Seconds of swing-timing error per unit of last-hit error: 0.02 -> 0.04 s, 0.15 -> 0.3 s. */
export declare const TIMING_PER_ERROR = 2;
/** Chance per creep of a lapse (a clearly late swing) at skill 0 and 1, when the profile has no `lapse`. */
export declare const LAPSE_LOW = 0.15;
export declare const LAPSE_HIGH = 0.01;
export declare function lerp(low: number, high: number, t: number): number;
/** Uniform [0, 1) from the adapter's `random` (tests seed it), else `math.random`. */
export declare function random(): number;
/** The bot's skill in [0, 1], read through the adapter every call; 1 when the host gives none. */
export declare function of(bot: TaskUnit): number;
export declare function profile(bot: TaskUnit): SkillProfile;
/** `secs` scaled by a uniform factor in 1 +- jitter/2 of the bot's profile. */
export declare function jitter(bot: TaskUnit, secs: number): number;
/** One sampled reaction delay: the profile's `react` +- jitter/2. 0 when the host gives no profile. */
export declare function react(bot: TaskUnit): number;
/** Half-width of the per-creep damage-estimate error: the host's `lastHitError`, else lerped from skill. */
export declare function lastHitError(bot: TaskUnit): number;
export declare function lapseChance(bot: TaskUnit): number;
/** Gaussian sigma (s) of a timed action's error at skill 0 and 1. */
export declare const TIMING_SIGMA_LOW = 1.5;
export declare const TIMING_SIGMA_HIGH = 0.2;
/** Draws past this many sigmas are clamped, so one roll can never wreck a job outright. */
export declare const TIMING_CLAMP = 2.5;
/** Standard normal (Box-Muller) from `random()`. */
export declare function gauss(): number;
export declare function timingSigma(bot: TaskUnit): number;
/** One sampled timing error in seconds for a timed action (pull/stack aggro, rune arrival); positive is late. */
export declare function timingError(bot: TaskUnit): number;
