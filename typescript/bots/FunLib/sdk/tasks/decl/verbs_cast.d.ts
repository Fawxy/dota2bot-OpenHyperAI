/** @noSelfInFile */
import { TaskAbility, TaskBody, TaskTarget, TaskUnit, Vec } from "./types";
export interface StopOpts {
    /** Absolute game time (`now()` clock); the verb fails `timeout` once it is reached. */
    deadline?: number;
    interruptIf?: (this: void) => boolean;
}
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
export declare function cast(bot: TaskUnit, ability: TaskAbility | undefined, opts?: CastOpts): TaskBody;
/**
 * Finds `itemName` in the six main inventory slots (backpack, stash, TP and neutral slots are not searched)
 * and casts it with `cast`, so the same options and confirmation apply.
 * UNVERIFIED in-game: that `FindItemSlot` returns the main-slot copy when the bot holds several.
 */
export declare function useItem(bot: TaskUnit, itemName: string, opts?: CastOpts): TaskBody;
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
export declare function pickUpRune(bot: TaskUnit, rune: number, opts?: RuneOpts): TaskBody;
