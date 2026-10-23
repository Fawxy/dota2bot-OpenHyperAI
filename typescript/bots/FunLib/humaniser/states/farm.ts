/**
 * `farm` state (team slice 10): a core's between-waves farm trip (FarmPattern) executed by an SDK body. OHA still
 * decides every trip (StartGate, the camp plan priced against the next wave, chaining, stacks through camp jobs, the
 * stop rules in Desire) and keeps its bookkeeping (pace learning, cleared camps, trip telemetry). The body replaces
 * FarmPattern's step(): `Verbs.clearCamp` on the planned camp (deadline = the plan's leaveBy), then OHA picks the
 * next camp or the walk back to the lane front.
 */
import type * as Lib from "bots/FunLib/sdk/tasks/tasks";
import { BotMode, Unit } from "bots/ts_libs/dota";
import * as Camps from "bots/FunLib/humaniser/camps";
import * as CampJobs from "bots/FunLib/humaniser/camp_jobs";
import * as FarmPattern from "bots/FunLib/humaniser/farm_pattern";
import * as Tasks from "bots/FunLib/humaniser/tasks";

export const NAME = "farm";


/** Shadow (slice 2) scores, kept so ownership changes nothing but who executes the trip. */
const TRIP = 0.7;

/** Runs `g` until it ends or `stop()` says the trip it serves is over (OHA's Desire ended or redirected it). */
function* until(g: Lib.TaskBody, stop: () => boolean): Lib.TaskBody {
    while (true) {
        if (stop()) return { success: false, reason: "interrupted", message: "trip-changed" };
        const s = g.next();
        if (s.done) return (s.value as Lib.Result | undefined) ?? { success: true, reason: "ok" };
        yield;
    }
}

function* body(bot: Unit, ctx: Lib.Ctx): Lib.TaskBody {
    const V = Tasks.Verbs()!;
    const u = bot as unknown as Lib.TaskUnit;
    const s = FarmPattern.Settings();
    while (true) {
        const trip = FarmPattern.Live(bot);
        if (trip === undefined || trip.sdk !== true) {
            ctx.label("idle");
            yield;
            continue;
        }
        if (trip.phase === "stack") {
            // The core's stack is camp_jobs' job (its own executor); the trip waits for it as step() does.
            ctx.label("stack");
            if (CampJobs.Active(bot)) CampJobs.Think(bot);
            else FarmPattern.Exec.Stacked(bot, trip);
            yield;
            continue;
        }
        if (trip.phase === "return") {
            ctx.label("return");
            bot.Action_MoveToLocation(GetLaneFrontLocation(trip.team, trip.lane, 0));
            yield;
            continue;
        }
        const spawner = Camps.SpawnerByIdx(trip.campIdx);
        if (spawner === undefined) {
            FarmPattern.Exec.ToReturn(bot, trip, "no-camp");
            continue;
        }
        const camp = trip.campIdx;
        const hooks: Lib.Verbs.JobHooks = {
            label: (l) => {
                ctx.label(l);
                if (l === "farm") trip.phase = "farm";
            },
            urgent: ctx.urgent,
        };
        const r = yield* until(
            V.clearCamp(
                u,
                {
                    at: Camps.BoxCenter(spawner) as unknown as Lib.Vec,
                    radius: s.CampRadius,
                    arrive: s.Arrive,
                    search: s.NeutralScan,
                    deadline: trip.leaveBy,
                    onEngage: (t) => {
                        trip.farmFrom ??= t;
                    },
                },
                hooks
            ),
            () => FarmPattern.Live(bot) !== trip || trip.campIdx !== camp || trip.phase === "return"
        );
        if (FarmPattern.Live(bot) !== trip || trip.campIdx !== camp) continue;
        if (r.success) {
            FarmPattern.Exec.CampDone(bot, trip, r.message === "cleared");
        } else if (r.reason === "timeout") {
            FarmPattern.Exec.ToReturn(bot, trip, "late");
        } else if (r.reason !== "interrupted") {
            return r;
        }
    }
}

/**
 * A posture, as slice 2's shadow `farm`: `shadow` (FarmScore) scores it, so the state is chosen exactly as before.
 * Only FarmPattern's Think steps the body, and only for a trip it started as `sdk`; outside trips the body idles.
 */
export function Spec(bot: Unit, shadow: (this: void, bot: Unit) => number | undefined): Lib.StateSpec {
    return {
        name: NAME,
        kind: "posture",
        host: BotMode.Farm,
        tier: "CAMP_JOB",
        floor: 0,
        // FarmPattern's own PreemptAfter (2 s): a team_roam last-hit blip must not restart the body.
        preemptAfter: FarmPattern.Settings().PreemptAfter,
        score: () => {
            const trip = FarmPattern.Live(bot);
            if (trip !== undefined && trip.sdk === true) return TRIP;
            return shadow(bot);
        },
        body: (ctx) => body(bot, ctx),
    };
}
