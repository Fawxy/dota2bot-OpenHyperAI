/**
 * Which lane creeps are a laner's to take: the role input to the shared picker (states/lane_pick Choose; user 03/11/2026,
 * laning is one shared body with role as an input). A core's are all of them. A support's (slice support-lane-hits) are every
 * deny, and a last hit only when no allied core will take it:
 * - a core whose laning body is in an attempt takes this creep when the picker would move it onto this one, and otherwise
 *   only if its next swing, one attack interval after the creep it goes for next is due, can land before the others kill
 *   this one (`busy` otherwise: the second creep due at once, llhchk3: 55% of the creeps that died in a core's reach
 *   unattempted died during an attempt on another creep);
 * - any other core (a human, a bot core between attempts, OHA's) takes what Etiquette.CanTake says it can (slice 3).
 * The facts are the engine's laneTargets seen from the core; the rule is ours (rule 3).
 * The other way (Ours.CoreDenyYield, user 06/11/2026 bug-hunt mark 11): a core leaves a deny an allied support's laning body
 * is in an attempt on (DenyYield), so it goes for the next last hit or another deny instead. Last hits are unaffected.
 */
import type * as Lib from "bots/FunLib/engine/tasks";
import { Unit } from "bots/ts_libs/dota";
import * as Etiquette from "bots/FunLib/humaniser/etiquette";
import * as LaneConfig from "bots/FunLib/humaniser/lane_config";
import * as LanePick from "bots/FunLib/humaniser/states/lane_pick";
import * as Ours from "bots/FunLib/humaniser/ours";
import * as Tasks from "bots/FunLib/humaniser/tasks";

/** Why a creep is a support's: a deny, a last hit no core is near enough for, or one its core is too busy for. */
export type Claim = "deny" | "free" | "busy";

type Attacker = Unit & { GetSecondsPerAttack?(): number };

/** The core's own laneTargets, once per frame (the support's scan asks for each creep it is offered). */
const offerCache: Record<number, { t: number; offers: Lib.Verbs.LaneTarget[] } | undefined> = {};

function offersOf(core: Unit, within: number): Lib.Verbs.LaneTarget[] {
    const pid = core.GetPlayerID();
    const now = DotaTime();
    const c = offerCache[pid];
    if (c !== undefined && c.t === now) return c.offers;
    const offers = Tasks.Verbs()?.laneTargets(core as unknown as Lib.TaskUnit, { within }) ?? [];
    offerCache[pid] = { t: now, offers };
    return offers;
}

/**
 * Whether `core` will take `t` itself, from the core's facts. `judgement`: the core's next swing is taken as landable one
 * attack interval after the creep it goes for next is due, at the earliest.
 */
function coreTakes(core: Attacker, t: Lib.Verbs.LaneTarget, within: number): boolean {
    const creep = t.creep as unknown as Unit;
    const busyOn = LanePick.Attempting(core.GetPlayerID());
    if (busyOn === undefined) return Etiquette.CanTake(core, creep);
    const offers = offersOf(core, within);
    let other: Lib.Verbs.LaneTarget | undefined;
    let mine: Lib.Verbs.LaneTarget | undefined;
    for (const o of offers) {
        if (o.creep === busyOn) other = o;
        if (o.creep === t.creep) mine = o;
    }
    // The creep it waited on is no longer on offer to it: the core is free again.
    if (other === undefined) return Etiquette.CanTake(core, creep);
    // The core's body retargets through the same picker, so the creep it is on next is Choose's answer, not the one it
    // waits on now: a deny wait is dropped for any reachable last hit (slhchk2 A game 1 t=210.87, review
    // 2026-11-04-support-lane-hits-e93e444 F1).
    const next = LanePick.Choose(offers, other, CoreMine(core)) ?? other;
    if (next.creep === t.creep) return true;
    if (mine === undefined) return false;
    const free = next.due + (core.GetSecondsPerAttack?.() ?? 1);
    return math.max(free + mine.walk, mine.eta) < t.dies;
}

/**
 * The allied support (pos 4-5) whose laning body is in an attempt on deny `t` (LanePick.Attempting, as coreTakes reads the
 * core's), within Etiquette's approach range of the creep (a body that left lane mid-attempt keeps its last phase), or
 * undefined. Only denies: a core's last hits are never yielded. With Ours.CoreDenyYield off, always undefined.
 */
export function DenyYield(core: Unit, t: Lib.Verbs.LaneTarget): number | undefined {
    if (t.kind !== "deny" || !Ours.On("CoreDenyYield")) return undefined;
    // Only a pos 1-3 yields: a pos 4-5 listed in Laning.LastHit takes a core's mine, and two of them must not yield a deny
    // to each other (review 2026-11-06-deny-yield-0ee970a F4).
    const own = LaneConfig.PositionOf(core);
    if (own !== undefined && own >= 4) return undefined;
    const creep = t.creep as unknown as Unit;
    for (let i = 1; i <= 5; i++) {
        const member = GetTeamMember(i);
        if (member === null || member === undefined || member === core) continue;
        if (!member.IsAlive() || member.IsIllusion()) continue;
        const pos = LaneConfig.PositionOf(member);
        if (pos === undefined || pos < 4) continue;
        if (LanePick.Attempting(member.GetPlayerID()) !== t.creep) continue;
        if (GetUnitToUnitDistance(member, creep) > Etiquette.SETTINGS.ApproachRange) continue;
        return member.GetPlayerID();
    }
    return undefined;
}

/** A core's `mine` for LanePick.Choose: every creep but a deny an allied support is attempting (DenyYield); undefined (all) with the switch off. */
export function CoreMine(core: Unit): ((this: void, t: Lib.Verbs.LaneTarget) => boolean) | undefined {
    if (!Ours.On("CoreDenyYield")) return undefined;
    return (t) => DenyYield(core, t) === undefined;
}

/** The claim `bot` (a support) has on `t`, or undefined when an allied core will take it. */
export function SupportClaim(bot: Unit, t: Lib.Verbs.LaneTarget, within: number): Claim | undefined {
    if (t.kind === "deny") return "deny";
    const creep = t.creep as unknown as Unit;
    let busy = false;
    // GetTeamMember, not GetTeamPlayers (empty for a bot-only team).
    for (let i = 1; i <= 5; i++) {
        const member = GetTeamMember(i) as Attacker | undefined;
        if (member === null || member === undefined || member === bot) continue;
        if (!member.IsAlive() || member.IsIllusion()) continue;
        const pos = LaneConfig.PositionOf(member);
        if (pos === undefined || pos > 3) continue;
        if (coreTakes(member, t, within)) return undefined;
        if (LanePick.Attempting(member.GetPlayerID()) !== undefined && GetUnitToUnitDistance(member, creep) <= Etiquette.SETTINGS.ApproachRange) busy = true;
    }
    return busy ? "busy" : "free";
}
