/**
 * `laning` state: go to the lane and hold a lane position (slice 1), stand like a high-MMR laner (slice 3,
 * `States.Laning.Spot = 'sdk'`), and last-hit and deny through the SDK verbs (slice 4, positions in
 * `States.Laning.LastHit`). OHA's spot (its PositionThink target) is handed over by mode_laning_generic.lua
 * through SetSpot. Where the body owns last hits, the Lua Think skips LastHitThink/DenyThink for the bot; its
 * techniques and harass still run first, so the body is resumed only on frames where none of those acted.
 */
import type * as Lib from "bots/FunLib/sdk/tasks/tasks";
import { BotMode, Unit, Vector } from "bots/ts_libs/dota";
import * as Config from "bots/FunLib/humaniser/config";
import * as LaneConfig from "bots/FunLib/humaniser/lane_config";
import * as Telemetry from "bots/FunLib/humaniser/telemetry";
import * as Tasks from "bots/FunLib/humaniser/tasks";
import * as Phase from "bots/FunLib/humaniser/transitions/phase";
import * as LaneSpot from "bots/FunLib/humaniser/states/lane_spot";

export const NAME = "laning";

/** Beyond this the body reports `walk`, within `NEAR` it reports `hold` (with hysteresis between them). */
const NEAR = 600;
const FAR = 1200;
/** A last-hit attempt is dropped when it would take the bot this far from its spot. */
const LEASH = 900;

export interface LaningSettings {
    /** 'oha': OHA's PositionThink target (slice 1). 'sdk': lane_spot.ts (slice 3). */
    Spot: "oha" | "sdk";
    /** Positions whose last hits and denies the body takes over (slice 4). */
    LastHit: number[];
    /** Seconds ahead a creep may become due for the body to go for it. */
    LastHitWithin: number;
}

const DEFAULTS: LaningSettings = { Spot: "oha", LastHit: [], LastHitWithin: 1 };

export function Settings(): LaningSettings {
    const s = (Config.Get().States as any)?.Laning as Partial<LaningSettings> | undefined;
    return {
        Spot: s?.Spot ?? DEFAULTS.Spot,
        LastHit: s?.LastHit ?? DEFAULTS.LastHit,
        LastHitWithin: s?.LastHitWithin ?? DEFAULTS.LastHitWithin,
    };
}

const spots: Record<number, ((this: void) => Vector | undefined) | undefined> = {};

export function SetSpot(bot: Unit, fn: (this: void) => Vector | undefined): void {
    spots[bot.GetPlayerID()] = fn;
}

function ohaSpot(bot: Unit): Vector | undefined {
    const fn = spots[bot.GetPlayerID()];
    if (fn === undefined) return undefined;
    const [ok, v] = pcall(fn);
    return ok ? v : undefined;
}

export function RoleOf(bot: Unit): LaneSpot.Role {
    const pos = LaneConfig.PositionOf(bot);
    return pos !== undefined && pos >= 4 ? "support" : "core";
}

interface SpotCache {
    t: number;
    v: Vector | undefined;
    info?: LaneSpot.SpotInfo;
}
const spotCache: Record<number, SpotCache | undefined> = {};

/** The spot the body holds this frame (cached per frame: holdAt and its exits read it several times). */
export function Spot(bot: Unit): Vector | undefined {
    const pid = bot.GetPlayerID();
    const now = DotaTime();
    const c = spotCache[pid];
    if (c !== undefined && c.t === now) return c.v;
    let v = ohaSpot(bot);
    let info: LaneSpot.SpotInfo | undefined;
    if (Settings().Spot === "sdk") {
        const [ok, res] = pcall(LaneSpot.Compute, bot, RoleOf(bot));
        if (ok && res !== undefined) {
            info = res;
            v = res.spot;
        }
    }
    spotCache[pid] = { t: now, v, info };
    return v;
}

/** The last computed SDK spot details for telemetry, if any. */
export function SpotInfo(bot: Unit): LaneSpot.SpotInfo | undefined {
    return spotCache[bot.GetPlayerID()]?.info;
}

/** Whether the body takes this bot's last hits and denies (read every frame by mode_laning_generic.lua). */
export function OwnsLastHit(bot: Unit): boolean {
    const pos = LaneConfig.PositionOf(bot);
    if (pos === undefined) return false;
    for (const p of Settings().LastHit) if (p === pos) return true;
    return false;
}

function distTo(bot: Unit, p: Vector | undefined): number | undefined {
    return p !== undefined ? GetUnitToLocationDistance(bot, p) : undefined;
}

function enemyHeroNear(bot: Unit, r: number): boolean {
    for (const h of bot.GetNearbyHeroes(r, true, BotMode.None)) if (h.IsAlive()) return true;
    return false;
}

function* body(bot: Unit, ctx: Lib.Ctx): Lib.TaskBody {
    const spot = () => Spot(bot) as unknown as Lib.Vec | undefined;
    const sdk = Settings().Spot === "sdk";
    // 'oha' is slice 1's hold: close to PositionThink's own move, standing still once there. 'sdk' shuffles in
    // 50-150 steps every 0.6-1.5 s (knowledge.md 1.1 idle motion) and follows the wave in 150-unit jumps.
    const hold: Lib.Verbs.HoldOpts = sdk
        ? { tolerance: 40, repath: 1.05, jitter: 0.85, scatter: 130, step: [50, 150], follow: 150, hold: "state:laning" }
        : { tolerance: 100, repath: 1, jitter: 0.3, scatter: 50, hold: "state:laning" };
    const verbs = Tasks.Verbs();
    let target: Lib.Verbs.LaneTarget | undefined;
    const pick = (): boolean => {
        if (verbs === undefined || !OwnsLastHit(bot) || (distTo(bot, Spot(bot)) ?? 0) > FAR) return false;
        target = verbs.nextLastHit(bot as unknown as Lib.TaskUnit, { within: Settings().LastHitWithin });
        return target !== undefined;
    };
    let near = false;
    while (true) {
        ctx.label(near ? "hold" : "walk");
        const r = yield* ctx.holdAt(spot, {
            ...hold,
            interruptIf: () => {
                const d = distTo(bot, Spot(bot));
                if (near ? (d ?? 0) > FAR : (d ?? math.huge) <= NEAR) return true;
                return pick();
            },
        });
        if (r.reason !== "interrupted") return r;
        if (target === undefined) {
            const d = distTo(bot, Spot(bot));
            near = d !== undefined && d <= (near ? FAR : NEAR);
            continue;
        }
        const t = target;
        target = undefined;
        const contested = enemyHeroNear(bot, 1000);
        ctx.label(t.kind);
        const opts: Lib.Verbs.LastHitOpts = {
            target: t.creep,
            maxWait: t.eta + 1.5,
            hold: "state:laning",
            interruptIf: () => (distTo(bot, Spot(bot)) ?? 0) > LEASH,
        };
        const res = t.kind === "lasthit" ? yield* ctx.lastHit(opts) : yield* ctx.deny(opts);
        Telemetry.Event("lh", [
            ["pid", bot.GetPlayerID()],
            ["kind", t.kind],
            ["result", res.success ? "ok" : "fail"],
            ["reason", res.reason],
            ["ranged", t.ranged],
            ["eta", math.floor(t.eta * 100) / 100],
            ["contested", contested],
        ]);
        if (res.reason === "dead") return res;
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
