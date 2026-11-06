/**
 * Each hero's own calendar (slice lane-control 3, design s5.5; user 07/11/2026: core and support keep their own calendars):
 * the departures this hero has booked, each described by the job that owns it. A support's calendar holds its rune trips
 * (fixed: never traded for lane control, s5.5 rule 1) and the stack minutes it still means to take (tentative: a stack may
 * give way to the lane, s5.4); a core's calendar is empty until its camp trips join (slice 4). The lane controller reads it
 * for the reset wave (R2) and to tell whether a support's pull fits before its next departure; the pull job reads it for
 * its priority. The calendar decides nothing: the controller is the one combiner (rule 6).
 */
import { Unit } from "bots/ts_libs/dota";

/** All `judgement` (slice file, Decisions). */
export const SETTINGS = {
    /** A pull fits before a departure when it ends this long before the departure's leave. */
    FitMargin: 5,
    /** A cached calendar is reused within this many seconds (the stack's camp choice walks the camps). */
    CacheFor: 1,
};

export interface Entry {
    kind: "stack" | "rune";
    /** The stack minute or the rune's spawn second. */
    key: number;
    /** From this second the job claims the hero: lower-ranked jobs do not start (the chooser's Claims). */
    claim: number;
    /** The estimated second the hero walks out of lane. */
    leave: number;
    /** The estimated second it is back where it left from. */
    back: number;
    /** Fixed: never traded for lane control (a rune trip). Tentative: may give way to the lane (a stack). */
    fixed: boolean;
    /** The job runs now. */
    running?: boolean;
}

const cache: Record<number, { at: number; entries: Entry[] } | undefined> = {};

export function ResetCache(): void {
    for (const [k] of pairs(cache)) cache[k as number] = undefined;
}

/** The hero's entries still ahead of it or running at `now`, by leave time. */
export function Of(bot: Unit, now: number): Entry[] {
    const pid = bot.GetPlayerID();
    const c = cache[pid];
    if (c !== undefined && now >= c.at && now - c.at < SETTINGS.CacheFor) return c.entries;
    // Lazy: the jobs' imports reach the chooser, which reaches the pull job, which reads this module.
    const StackJob = require("bots/FunLib/humaniser/stack_job") as typeof import("bots/FunLib/humaniser/stack_job");
    const RuneJob = require("bots/FunLib/humaniser/rune_job") as typeof import("bots/FunLib/humaniser/rune_job");
    const entries: Entry[] = [...StackJob.CalendarEntries(bot, now), ...RuneJob.CalendarEntries(bot, now)];
    entries.sort((a, b) => a.leave - b.leave);
    cache[pid] = { at: now, entries };
    return entries;
}

/** Seconds from `now` to the first leave at or after it, or undefined with none. */
export function NextLeave(entries: Entry[], now: number): number | undefined {
    let best: number | undefined;
    for (const e of entries) if (!e.running && e.leave >= now && (best === undefined || e.leave - now < best)) best = e.leave - now;
    return best;
}

export type Fit = "free" | "fits" | "clash";

/**
 * Whether a job from `start` to `end` (a pull) can run: `free` when no entry claims the hero in that time, `fits` when the
 * entries that do all still leave FitMargin after `end` (their claim has begun but their walk has not), else `clash` with
 * the first entry that does not (a running job always clashes).
 */
export function FitOf(entries: Entry[], start: number, end: number): LuaMultiReturn<[Fit, Entry | undefined]> {
    let fits: Entry | undefined;
    let clash: Entry | undefined;
    for (const e of entries) {
        if (e.claim > end || e.back <= start) continue;
        if (e.running || e.leave < end + SETTINGS.FitMargin) {
            // A fixed or running clash is the one that decides (the pull cannot take its time); a tentative one only
            // when no other clashes (lctl4: a stack reported first hid the rune trip that then took the support).
            if (e.running || e.fixed) return $multi("clash", e);
            clash = clash ?? e;
        } else fits = fits ?? e;
    }
    if (clash !== undefined) return $multi("clash", clash);
    if (fits !== undefined) return $multi("fits", fits);
    return $multi("free", undefined);
}
