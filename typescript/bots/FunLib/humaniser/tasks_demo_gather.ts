/**
 * Spike demo: the GATHER/SMOKE/BACK part of mode_assemble_generic's Orders executor as one task, gated behind
 * Customize.Humaniser.Tasks.Demo. ATTACK stays on the legacy path. See "Task runner (spike)" in HUMANISER_DEV.md.
 */
import type * as Lib from "bots/FunLib/sdk/tasks/tasks";
import { BotMode, Unit } from "bots/ts_libs/dota";
import * as Config from "bots/FunLib/humaniser/config";
import * as Orders from "bots/FunLib/humaniser/orders";
import * as Tasks from "bots/FunLib/humaniser/tasks";

// Same as ARRIVE_RADIUS in mode_assemble_generic.lua.
const ARRIVE_RADIUS = 500;

// Player ID -> id of the last order this bot reached; the executor's `orderArrived`, kept for Desire's gate.
const arrived: Record<number, number> = {};

export function IsActive(): boolean {
    return Tasks.IsActive() && Config.Get().Tasks.Demo === true;
}

function demoOrder(bot: Unit): Orders.TeamOrder | undefined {
    const order = Orders.GetFor(bot);
    if (order === undefined || (order.type !== "GATHER" && order.type !== "SMOKE" && order.type !== "BACK")) return undefined;
    return order;
}

function* gather(bot: Unit, order: Orders.TeamOrder, verbs: NonNullable<ReturnType<typeof Tasks.Verbs>>): Lib.TaskBody {
    const unit = bot as unknown as Lib.TaskUnit;
    const gone = () => Orders.GetFor(bot)?.id !== order.id;
    // Expiry also removes the order, so the walk is cut short by it; the order's own clock bounds the walk.
    const walked = yield* verbs.walkTo(unit, Orders.OrderLocation(order)!, {
        tolerance: ARRIVE_RADIUS,
        timeout: order.expiresAt - GameTime() + 1,
        interruptIf: gone,
    });
    if (!walked.success) return walked;
    // While holding, expiry is the success condition, so only an early removal (cancel/replace) interrupts.
    return yield* verbs.wait(unit, order.expiresAt - GameTime(), { interruptIf: () => gone() && GameTime() < order.expiresAt });
}

/** The executor's GATHER/SMOKE/BACK desire: the order floor until arrival, nothing while within 2x the radius. */
export function Desire(bot: Unit): number | undefined {
    const order = demoOrder(bot);
    const loc = order !== undefined ? Orders.OrderLocation(order) : undefined;
    if (order === undefined || loc === undefined) return undefined;
    const dist = GetUnitToLocationDistance(bot, loc);
    if (arrived[bot.GetPlayerID()] === order.id || dist <= ARRIVE_RADIUS) {
        arrived[bot.GetPlayerID()] = order.id;
        if (dist <= ARRIVE_RADIUS * 2) return undefined;
    }
    return Orders.DesireFloor(bot, BotMode.Assemble);
}

/** Steps the running task, or starts one for the bot's order. Returns false when the legacy Think should act. */
export function Think(bot: Unit): boolean {
    if (Tasks.Step(bot, BotMode.Assemble)) return true;
    const order = demoOrder(bot);
    const verbs = Tasks.Verbs();
    if (order === undefined || verbs === undefined || Orders.OrderLocation(order) === undefined) return false;
    if (!Tasks.Start(bot, { name: `gather:${order.id}`, host: BotMode.Assemble }, () => gather(bot, order, verbs))) return false;
    return Tasks.Step(bot, BotMode.Assemble);
}
