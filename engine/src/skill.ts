import { get } from "./adapter";
import { SkillProfile, TaskUnit } from "./types";

/** Last-hit error half-width (fraction of own damage) at skill 0 and 1. */
export const LAST_HIT_ERROR_LOW = 0.15;
export const LAST_HIT_ERROR_HIGH = 0.02;
/** Seconds of swing-timing error per unit of last-hit error: 0.02 -> 0.04 s, 0.15 -> 0.3 s. */
export const TIMING_PER_ERROR = 2;
/** Chance per creep of a lapse (a clearly late swing) at skill 0 and 1, when the profile has no `lapse`. */
export const LAPSE_LOW = 0.15;
export const LAPSE_HIGH = 0.01;

export function lerp(low: number, high: number, t: number): number {
    return low + (high - low) * t;
}

/** Uniform [0, 1) from the adapter's `random` (tests seed it), else `math.random`. */
export function random(): number {
    const a = get();
    if (a !== undefined && a.random !== undefined) return a.random();
    return math.random();
}

/** The bot's skill in [0, 1], read through the adapter every call; 1 when the host gives none. */
export function of(bot: TaskUnit): number {
    const a = get();
    const s = a !== undefined && a.skill !== undefined ? a.skill(bot) : undefined;
    if (s === undefined) return 1;
    return math.max(0, math.min(1, s));
}

export function profile(bot: TaskUnit): SkillProfile {
    const a = get();
    const p = a !== undefined && a.profile !== undefined ? a.profile(bot) : undefined;
    return p ?? { react: 0, jitter: 0 };
}

/** `secs` scaled by a uniform factor in 1 +- jitter/2 of the bot's profile. */
export function jitter(bot: TaskUnit, secs: number): number {
    const j = profile(bot).jitter;
    return secs * (1 - j / 2 + random() * j);
}

/** One sampled reaction delay: the profile's `react` +- jitter/2. 0 when the host gives no profile. */
export function react(bot: TaskUnit): number {
    return jitter(bot, profile(bot).react);
}

/** Half-width of the per-creep damage-estimate error: the host's `lastHitError`, else lerped from skill. */
export function lastHitError(bot: TaskUnit): number {
    const a = get();
    if (a !== undefined && a.lastHitError !== undefined) return math.max(0, a.lastHitError(bot));
    return lerp(LAST_HIT_ERROR_LOW, LAST_HIT_ERROR_HIGH, of(bot));
}

export function lapseChance(bot: TaskUnit): number {
    return profile(bot).lapse ?? lerp(LAPSE_LOW, LAPSE_HIGH, of(bot));
}

/** Gaussian sigma (s) of a timed action's error at skill 0 and 1. */
export const TIMING_SIGMA_LOW = 1.5;
export const TIMING_SIGMA_HIGH = 0.2;
/** Draws past this many sigmas are clamped, so one roll can never wreck a job outright. */
export const TIMING_CLAMP = 2.5;

/** Standard normal (Box-Muller) from `random()`. */
export function gauss(): number {
    const u1 = math.max(1e-6, random());
    const u2 = random();
    return math.sqrt(-2 * math.log(u1)) * math.cos(2 * Math.PI * u2);
}

export function timingSigma(bot: TaskUnit): number {
    return lerp(TIMING_SIGMA_LOW, TIMING_SIGMA_HIGH, of(bot));
}

/** One sampled timing error in seconds for a timed action (pull/stack aggro, rune arrival); positive is late. */
export function timingError(bot: TaskUnit): number {
    const s = timingSigma(bot);
    return math.max(-TIMING_CLAMP * s, math.min(TIMING_CLAMP * s, gauss() * s));
}
