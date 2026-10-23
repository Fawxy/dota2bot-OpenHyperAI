/**
 * `rotate` state (team slice 9), first case: the pos 4's Shrine of Wisdom trip. High-MMR supports leave lane to be at
 * their own shrine as it fills (7:00, then every 7 minutes; research/replays.md: pos 4 takes 63% of wisdom runes,
 * typically 7:03-7:15) and stand in it for its 3 s. OHA's rune mode only sends the nearest ally after the spawn. The
 * body is the SDK's `runeRun` in shrine mode (arrive skill-scaled early, stand within 300 for 3 s), hosted by the
 * rune mode. Power-rune rotations stay transitions/rotation's for now.
 */
import type * as Lib from "bots/FunLib/sdk/tasks/tasks";
import { BotMode, Team, Unit, Vector } from "bots/ts_libs/dota";
import * as LaneConfig from "bots/FunLib/humaniser/lane_config";
import * as Tasks from "bots/FunLib/humaniser/tasks";
import * as Telemetry from "bots/FunLib/humaniser/telemetry";
import * as Busy from "bots/FunLib/humaniser/transitions/busy";
import * as Runes from "bots/FunLib/humaniser/transitions/runes";

export const NAME = "rotate";

/** mode_rune_generic's shrine spots (7.38+: Shrines of Wisdom, one in each team's offlane jungle). */
const SHRINE: Record<number, [number, number, number]> = {
    [Team.Radiant]: [-7948.152344, 768.207825, 256],
    [Team.Dire]: [8029.234375, -1125.811768, 256],
};

/** Above laning (0.5 + stickiness), below the job break, like the camp jobs. */
const SCORE = 0.75;
/** Liquipedia/7.41: stand within 300 of the shrine for 3 s. */
const CHANNEL = 3;
const RADIUS = 300;
/** Not at the shrine this long after it fills: the trip is not worth it any more (lane, enemy support). */
const LATE_BY = 15;
const PICKUP_FOR = 20;
/** Walking paths are longer than the straight line (transitions settings PathFactor). */
const PATH_FACTOR = 1.2;
const DANGER_RADIUS = 1200;
const DANGER_HP = 0.5;

const WISDOM_POSITIONS: Record<number, boolean> = { [4]: true };

interface Trip {
    team: number;
    spawn: number;
    startedAt: number;
    arrivedAt?: number;
    channelAt?: number;
    ended?: string;
}

const trips: Record<number, Trip | undefined> = {};
/** Spawns a bot's trip is over for (done, failed or skipped): not chosen again. */
const doneFor: Record<number, number | undefined> = {};

export function ResetCache(): void {
    for (const [k] of pairs(trips)) trips[k as number] = undefined;
    for (const [k] of pairs(doneFor)) doneFor[k as number] = undefined;
}

export function ShrineFor(team: number): Vector {
    const s = SHRINE[team] ?? SHRINE[Team.Radiant];
    return Vector(s[0], s[1], s[2]);
}

function planFor(bot: Unit, spawn: number): Lib.Verbs.RunePlan {
    return {
        at: ShrineFor(bot.GetTeam()) as unknown as Lib.Vec,
        spawnAt: spawn,
        channel: CHANNEL,
        radius: RADIUS,
        tolerance: RADIUS - 100,
        lateBy: LATE_BY,
        pickupFor: PICKUP_FOR,
    };
}

/** The wisdom spawn a trip now would be for: the next fill, or one that filled under LATE_BY s ago. */
function spawnNow(now: number): number {
    return Runes.NextSpawn("wisdom", now - LATE_BY);
}

/** When to leave lane for `spawn`: the SDK's skill-scaled arrival, less the walk (path factor on the straight line). */
export function LeaveAt(bot: Unit, spawn: number): number | undefined {
    const V = Tasks.Verbs();
    if (V === undefined) return undefined;
    const u = bot as unknown as Lib.TaskUnit;
    const plan = planFor(bot, spawn);
    const d = GetUnitToLocationDistance(bot, ShrineFor(bot.GetTeam()));
    return V.runeArriveBy(u, plan) - (d * PATH_FACTOR) / math.max(1, bot.GetCurrentMovementSpeed());
}

function danger(bot: Unit): string | undefined {
    const enemies = bot.GetNearbyHeroes(DANGER_RADIUS, true, BotMode.None) ?? [];
    const allies = bot.GetNearbyHeroes(DANGER_RADIUS, false, BotMode.None) ?? [];
    if (enemies.length > allies.length) return "outnumbered";
    if (bot.WasRecentlyDamagedByAnyHero(2) && bot.GetHealth() / math.max(1, bot.GetMaxHealth()) < DANGER_HP) return "damaged";
    return undefined;
}

function score(bot: Unit): number | undefined {
    const pid = bot.GetPlayerID();
    const trip = trips[pid];
    if (trip !== undefined && trip.ended === undefined) {
        if (DotaTime() <= trip.spawn + PICKUP_FOR) return SCORE;
        // Kept past its pickup window by a preempt or a death: over, so the state layer can leave it.
        close(bot, trip, { success: false, reason: "timeout", message: "expired" }, undefined);
        return undefined;
    }
    if (!bot.IsAlive() || WISDOM_POSITIONS[LaneConfig.PositionOf(bot) ?? 0] !== true) return undefined;
    const now = DotaTime();
    const spawn = spawnNow(now);
    if (spawn === math.huge || doneFor[pid] === spawn) return undefined;
    const leave = LeaveAt(bot, spawn);
    if (leave === undefined || now < leave) return undefined;
    // The same lane checks a power-rune rotation passes (task 12): no trip while busy or while the lane needs us.
    if (Busy.IsBusy(bot, spawn)[0] || !Busy.LaneCanSpare(bot, false)[0] || danger(bot) !== undefined) return undefined;
    return SCORE;
}

function* body(bot: Unit, ctx: Lib.Ctx): Lib.TaskBody {
    const pid = bot.GetPlayerID();
    const now = DotaTime();
    const spawn = trips[pid]?.spawn ?? spawnNow(now);
    if (trips[pid] === undefined || trips[pid]!.ended !== undefined) trips[pid] = { team: bot.GetTeam(), spawn, startedAt: now };
    const trip = trips[pid]!;
    const hooks: Lib.Verbs.JobHooks = {
        label: (l) => {
            ctx.label(l);
            if (l === "wait" || (l === "channel" && trip.arrivedAt === undefined)) trip.arrivedAt = DotaTime();
            if (l === "channel") trip.channelAt = DotaTime();
        },
        urgent: ctx.urgent,
    };
    return yield* Tasks.Verbs()!.runeRun(bot as unknown as Lib.TaskUnit, planFor(bot, spawn), hooks);
}

function ended(bot: Unit, r: Lib.Result, info: { label?: string; steps: number }): void {
    const trip = trips[bot.GetPlayerID()];
    if (trip === undefined || trip.ended !== undefined) return;
    // Preempted (a fight, retreat) or dead: the state layer restarts the body while the trip is still worth it.
    if ((r.reason === "preempted" || r.reason === "dead") && DotaTime() <= trip.spawn + LATE_BY) return;
    close(bot, trip, r, info.label);
}

function close(bot: Unit, trip: Trip, r: Lib.Result, label: string | undefined): void {
    const pid = bot.GetPlayerID();
    trip.ended = r.success ? "ok" : r.message ?? r.reason;
    doneFor[pid] = trip.spawn;
    const now = DotaTime();
    Telemetry.Event("wisdom", [
        ["pid", pid],
        ["pos", LaneConfig.PositionOf(bot)],
        ["spawn", trip.spawn],
        ["result", r.success ? "ok" : "fail"],
        ["reason", r.success ? undefined : trip.ended],
        ["label", label],
        ["left", trip.startedAt],
        ["arrived", trip.arrivedAt],
        // Shrine taken: the channel ended this many seconds after the fill (bar: within 15 s).
        ["taken", r.success ? now - trip.spawn : undefined],
        ["away", now - trip.startedAt],
    ]);
}

/** Bots not owning `rotate` keep the shadow score (slice 2: OHA's power-rune rotation or the mid's rune claim). */
export function Spec(
    bot: Unit,
    owned?: (this: void, bot: Unit, state: string) => boolean,
    shadow?: (this: void, bot: Unit) => number | undefined
): Lib.StateSpec {
    return {
        name: NAME,
        kind: "job",
        host: BotMode.Rune,
        tier: "TRANSITION",
        floor: SCORE,
        // A trip that cannot be stepped for this long lost to another mode (fight, retreat) and is restarted later.
        preemptAfter: 1,
        score: () => {
            if (owned === undefined || owned(bot, NAME)) return score(bot);
            return shadow !== undefined ? shadow(bot) : undefined;
        },
        guard: () => danger(bot),
        onEnd: (r, info) => ended(bot, r, info),
        body: (ctx) => body(bot, ctx),
    };
}

/** The bot is on (or committed to) a shrine trip for the current fill: OHA's own wisdom logic leaves the shrine to it. */
export function OnTrip(bot: Unit): boolean {
    const trip = trips[bot.GetPlayerID()];
    return trip !== undefined && trip.ended === undefined;
}

/** Some ally of `team` is on a shrine trip: the shrine is taken for this fill. */
export function ShrineTaken(team: number): boolean {
    for (const [, trip] of pairs(trips)) {
        if (trip !== undefined && trip.ended === undefined && trip.team === team) return true;
    }
    return false;
}
