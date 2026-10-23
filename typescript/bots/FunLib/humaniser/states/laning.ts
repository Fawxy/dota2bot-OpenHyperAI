/**
 * `laning` state (team slice 1): go to the lane and hold OHA's lane position. The spot is exactly OHA's
 * PositionThink target, handed over by mode_laning_generic.lua through SetSpot and recomputed every frame.
 * Last hits, denies, techniques and harass still run first in OHA's laning Think(); this body only replaces
 * the final PositionThink step, so it is resumed only on frames where none of those acted.
 */
import type * as Lib from "bots/FunLib/sdk/tasks/tasks";
import { BotMode, Unit, Vector } from "bots/ts_libs/dota";
import * as Phase from "bots/FunLib/humaniser/transitions/phase";

export const NAME = "laning";

/** Beyond this the body reports `walk`, within `NEAR` it reports `hold` (with hysteresis between them). */
const NEAR = 600;
const FAR = 1200;

const spots: Record<number, ((this: void) => Vector | undefined) | undefined> = {};

export function SetSpot(bot: Unit, fn: (this: void) => Vector | undefined): void {
    spots[bot.GetPlayerID()] = fn;
}

export function Spot(bot: Unit): Vector | undefined {
    const fn = spots[bot.GetPlayerID()];
    if (fn === undefined) return undefined;
    const [ok, v] = pcall(fn);
    return ok ? v : undefined;
}

function distTo(bot: Unit, p: Vector | undefined): number | undefined {
    return p !== undefined ? GetUnitToLocationDistance(bot, p) : undefined;
}

function* body(bot: Unit, ctx: Lib.Ctx): Lib.TaskBody {
    const spot = () => Spot(bot) as unknown as Lib.Vec | undefined;
    // Close to PositionThink's own move (spot + RandomVector(50) every frame), but standing still once there.
    const hold = { tolerance: 100, repath: 1, jitter: 0.3, scatter: 50, hold: "state:laning" };
    while (true) {
        ctx.label("walk");
        let r = yield* ctx.holdAt(spot, { ...hold, interruptIf: () => (distTo(bot, Spot(bot)) ?? math.huge) <= NEAR });
        if (r.reason !== "interrupted") return r;
        ctx.label("hold");
        r = yield* ctx.holdAt(spot, { ...hold, interruptIf: () => (distTo(bot, Spot(bot)) ?? 0) > FAR });
        if (r.reason !== "interrupted") return r;
    }
}

export function Spec(bot: Unit): Lib.StateSpec {
    return {
        name: NAME,
        kind: "posture",
        host: BotMode.Laning,
        // Floor 0: the state only takes over what the bot does once OHA's own arbitration chose laning.
        floor: 0,
        // OHA's last-hit blips into other modes (about 2/min per bot) must not restart the body.
        preemptAfter: 3,
        score: () => (Phase.IsLaningFor(bot) ? 0.5 : undefined),
        body: (ctx) => body(bot, ctx),
    };
}
