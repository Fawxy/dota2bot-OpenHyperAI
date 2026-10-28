import { Result, TaskAbility, TaskBody, TaskTarget, TaskUnit, Vec } from "./types";
import { StopOpts, walkTo } from "./verbs";
import { dist, fail, now, ok, stopped, targetLost } from "./verbs_util";

export interface CastOpts extends StopOpts {
    /** Unit target (`Action_UseAbilityOnEntity`). Takes precedence over `at`. */
    target?: TaskTarget;
    /** Ground target (`Action_UseAbilityOnLocation`). With neither, `Action_UseAbility`. */
    at?: Vec;
    /** Keep running while the ability channels; `ok` only if the channel runs its full time. */
    channel?: boolean;
    /** Seconds from the first order to confirm the cast went off. Default cast point + 1. */
    timeout?: number;
}

// Minimum gap between re-orders while no sign of the cast has been seen.
const REORDER_SECS = 0.5;
// Observing a channel's start and end each lags by up to a frame; shortfalls within this read as natural.
const CHANNEL_SLACK = 0.25;

function inPhase(bot: TaskUnit, ability: TaskAbility): boolean {
    return ability.IsInAbilityPhase?.() ?? bot.IsCastingAbility?.() ?? false;
}

function channeling(bot: TaskUnit, ability: TaskAbility): boolean | undefined {
    return ability.IsChanneling?.() ?? bot.IsChanneling?.();
}

function orderFor(bot: TaskUnit, ability: TaskAbility, opts: CastOpts): ((this: void) => void) | undefined {
    const target = opts.target;
    if (target !== undefined) {
        if (bot.Action_UseAbilityOnEntity === undefined) return undefined;
        return () => bot.Action_UseAbilityOnEntity!(ability, target);
    }
    const at = opts.at;
    if (at !== undefined) {
        if (bot.Action_UseAbilityOnLocation === undefined) return undefined;
        return () => bot.Action_UseAbilityOnLocation!(ability, at);
    }
    if (bot.Action_UseAbility === undefined) return undefined;
    return () => bot.Action_UseAbility!(ability);
}

/**
 * Casts `ability` and finishes `ok` only once its effect is seen: the cooldown rose above its reading at the
 * order, or mana fell by at least half the mana cost. A cast phase that is seen and then ends without that
 * effect (two frames in a row, allowing the effect to show a frame late) fails `interrupted`; a unit target
 * that dies or vanishes first fails `no_target`.
 *
 * Re-ordering: while neither the cast phase nor the effect has been seen, the order is re-issued every
 * 0.5 s (another order in the same frame may have replaced it). Never once the phase is seen, since
 * re-issuing during the cast point risks restarting it, and only when a phase signal exists at all.
 * Failing (including `interruptIf`/`deadline`) does not cancel a cast in progress in-game.
 *
 * The default `timeout` assumes the caster is already in range and facing; pass a longer one when the order
 * has to walk the bot into cast range first.
 *
 * Channels (`channel: true`): after the effect, waits for the channel; ends `ok` if it ran within 0.25 s of
 * `GetChannelTime()`, else `interrupted`. Early ends shorter than that slack are indistinguishable from
 * natural ones. A target dying mid-channel counts as an early end.
 *
 * UNVERIFIED in-game: that `GetCooldownTimeRemaining` / mana drop are visible within a frame of the cast
 * point ending; that `IsInAbilityPhase` is true for the whole cast point; that a stun-cancelled cast starts
 * no cooldown and costs no mana; that re-issuing the same cast order before its phase starts is harmless;
 * that channelled abilities start their cooldown when the channel starts; `IsChanneling` on the handle
 * (falls back to the unit's). Abilities with neither cooldown nor mana cost (and not channelled) can never
 * be confirmed and time out; charge-based abilities may not raise the cooldown and rely on mana.
 */
export function* cast(bot: TaskUnit, ability: TaskAbility | undefined, opts: CastOpts = {}): TaskBody {
    if (ability === undefined || (ability.IsNull?.() ?? false)) return fail("not_castable", "no ability");
    const order = orderFor(bot, ability, opts);
    if (order === undefined) return fail("unsupported");
    const cost = ability.GetManaCost?.() ?? 0;
    const canSeeChannel = channeling(bot, ability) !== undefined && ability.GetChannelTime !== undefined;
    if (opts.channel === true && !canSeeChannel) return fail("unsupported");
    const canSeeEffect = ability.GetCooldownTimeRemaining !== undefined || (bot.GetMana !== undefined && cost > 0);
    if (!canSeeEffect) return fail("unsupported");
    const canSeePhase = ability.IsInAbilityPhase !== undefined || bot.IsCastingAbility !== undefined;

    if (!bot.IsAlive()) return fail("dead");
    const early = stopped(opts);
    if (early !== undefined) return early;
    if (!ability.IsFullyCastable()) return fail("not_castable");
    if (opts.target !== undefined && targetLost(opts.target)) return fail("no_target");

    const start = now();
    const timeout = opts.timeout ?? (ability.GetCastPoint?.() ?? 0) + 1;
    const cd0 = ability.GetCooldownTimeRemaining?.();
    const mana0 = bot.GetMana?.();
    const effectSeen = (): boolean => {
        const cd = ability.GetCooldownTimeRemaining?.();
        if (cd !== undefined && cd0 !== undefined && cd > cd0 + 0.05) return true;
        const mana = bot.GetMana?.();
        return cost > 0 && mana !== undefined && mana0 !== undefined && mana0 - mana >= cost * 0.5;
    };

    order();
    let orderedAt = start;
    let phaseSeen = false;
    let phaseGone = 0;
    while (true) {
        yield;
        if (!bot.IsAlive()) return fail("dead");
        if (effectSeen() || (opts.channel === true && channeling(bot, ability) === true)) break;
        if (opts.target !== undefined && targetLost(opts.target)) return fail("no_target", "target lost before cast");
        if (inPhase(bot, ability)) {
            phaseSeen = true;
            phaseGone = 0;
        } else if (phaseSeen) {
            phaseGone++;
            if (phaseGone >= 2) return fail("interrupted", "cast phase cancelled");
        }
        const stop = stopped(opts);
        if (stop !== undefined) return stop;
        if (now() - start >= timeout) return fail("timeout");
        if (canSeePhase && !phaseSeen && now() - orderedAt >= REORDER_SECS && ability.IsFullyCastable()) {
            order();
            orderedAt = now();
        }
    }
    if (opts.channel !== true) return ok();

    const channelTime = ability.GetChannelTime!();
    const castAt = now();
    let channelStart: number | undefined;
    while (true) {
        if (!bot.IsAlive()) return fail("dead");
        const ch = channeling(bot, ability) === true;
        if (channelStart === undefined) {
            if (ch) channelStart = now();
            else if (now() - castAt > CHANNEL_SLACK) return fail("interrupted", "channel never started");
        } else if (!ch) {
            if (now() - channelStart >= channelTime - CHANNEL_SLACK) return ok();
            return fail("interrupted", "channel ended early");
        } else if (now() - channelStart > channelTime + 1) {
            return fail("timeout", "still channelling past channel time");
        }
        const stop = stopped(opts);
        if (stop !== undefined) return stop;
        yield;
    }
}

const MAIN_SLOTS = 6;

function findMainItem(bot: TaskUnit, name: string): TaskAbility | undefined {
    if (bot.FindItemSlot !== undefined) {
        const slot = bot.FindItemSlot(name);
        return slot >= 0 && slot < MAIN_SLOTS ? bot.GetItemInSlot!(slot) : undefined;
    }
    for (let slot = 0; slot < MAIN_SLOTS; slot++) {
        const item = bot.GetItemInSlot!(slot);
        if (item !== undefined && item.GetName?.() === name) return item;
    }
    return undefined;
}

/**
 * Finds `itemName` in the six main inventory slots (backpack, stash, TP and neutral slots are not searched)
 * and casts it with `cast`, so the same options and confirmation apply.
 * UNVERIFIED in-game: that `FindItemSlot` returns the main-slot copy when the bot holds several.
 */
export function* useItem(bot: TaskUnit, itemName: string, opts: CastOpts = {}): TaskBody {
    if (bot.GetItemInSlot === undefined) return fail("unsupported");
    const item = findMainItem(bot, itemName);
    if (item === undefined) return fail("no_item", itemName);
    return yield* cast(bot, item, opts);
}

export interface RuneOpts extends StopOpts {
    /** Walk until within this distance of the rune before ordering the pick-up. Default 150. */
    tolerance?: number;
    /** Seconds for the whole verb, walk included. Default 15. */
    timeout?: number;
    /** Seconds from the pick-up order for the rune to disappear before failing `missed`. Default 2. */
    confirmFor?: number;
    /** Overrides `GetRuneSpawnLocation(rune)`. */
    at?: Vec;
    /** Host proof that we got it (gold, modifier, bottle). When given, it decides ok vs `taken_by_other`. */
    confirmed?: (this: void) => boolean;
}

type RuneStatusFn = (this: void, rune: number) => number;
type RuneSpawnFn = (this: void, rune: number) => Vec;

function dotaGlobal<T>(name: string): T | undefined {
    return rawget(_G as unknown as { [k: string]: T | undefined }, name);
}

/**
 * Walks to the rune at location constant `rune`, orders `Action_PickUpRune` and finishes `ok` when the
 * rune's status leaves `RUNE_STATUS_AVAILABLE` while we are within `tolerance` having ordered the pick-up
 * (or, with `confirmed`, when that says so). A rune that disappears before then fails `taken_by_other`;
 * one already reported missing fails `no_target` without moving. Re-orders the pick-up every 0.5 s.
 *
 * Reads the Dota globals `GetRuneStatus`, `GetRuneSpawnLocation` and `RUNE_STATUS_AVAILABLE`/`_MISSING`
 * through `_G`, failing `unsupported` when absent.
 *
 * UNVERIFIED in-game: that `GetRuneStatus` leaves `AVAILABLE` within a frame of the pick-up; that a rune
 * vanishing while we stand on it with a pick-up ordered was ours (another hero grabbing it at the same
 * moment reads as ok unless `confirmed` is given); that `Action_PickUpRune` is a no-op once it is gone.
 */
export function* pickUpRune(bot: TaskUnit, rune: number, opts: RuneOpts = {}): TaskBody {
    const status = dotaGlobal<RuneStatusFn>("GetRuneStatus");
    const available = dotaGlobal<number>("RUNE_STATUS_AVAILABLE");
    const missing = dotaGlobal<number>("RUNE_STATUS_MISSING");
    const spawnAt = dotaGlobal<RuneSpawnFn>("GetRuneSpawnLocation");
    const loc = opts.at ?? (spawnAt !== undefined ? spawnAt(rune) : undefined);
    if (status === undefined || available === undefined || missing === undefined) return fail("unsupported");
    if (loc === undefined || bot.Action_PickUpRune === undefined) return fail("unsupported");

    if (!bot.IsAlive()) return fail("dead");
    if (status(rune) === missing) return fail("no_target", "rune missing");
    const tolerance = opts.tolerance ?? 150;
    const confirmFor = opts.confirmFor ?? 2;
    const start = now();
    const deadline = start + (opts.timeout ?? 15);
    // Unknown (unscouted) counts as present until seen one way or the other; missing before we ever saw it
    // available means there was nothing to take.
    let seen = false;
    const gone = (): boolean => {
        const s = status(rune);
        if (s === available) seen = true;
        return s === missing || (seen && s !== available);
    };
    const lost = (): Result => (seen ? fail("taken_by_other") : fail("no_target", "rune missing"));

    const walked = yield* walkTo(bot, loc, {
        tolerance,
        timeout: deadline - start,
        stuckSecs: 3,
        interruptIf: () => gone() || stopped(opts) !== undefined,
    });
    if (!walked.success) {
        if (walked.reason !== "interrupted") return walked;
        if (gone()) return lost();
        return stopped(opts) ?? walked;
    }
    if (gone()) return lost();
    if (!seen) return fail("no_target", "rune not seen at location");

    let orderedAt = now();
    const firstOrder = orderedAt;
    bot.Action_PickUpRune(rune);
    while (true) {
        yield;
        if (!bot.IsAlive()) return fail("dead");
        if (gone()) {
            if (opts.confirmed !== undefined) return opts.confirmed() ? ok() : fail("taken_by_other");
            return dist(bot.GetLocation(), loc) <= tolerance ? ok() : fail("taken_by_other");
        }
        const stop = stopped(opts);
        if (stop !== undefined) return stop;
        if (now() >= deadline) return fail("timeout");
        if (now() - firstOrder >= confirmFor) return fail("missed");
        if (now() - orderedAt >= REORDER_SECS) {
            bot.Action_PickUpRune(rune);
            orderedAt = now();
        }
    }
}
