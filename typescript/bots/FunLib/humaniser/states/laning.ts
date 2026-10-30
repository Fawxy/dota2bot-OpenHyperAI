/**
 * `laning` state: go to the lane and hold a lane position (slice 1), stand like a high-MMR laner (slice 3,
 * `States.Laning.Spot = 'sdk'`), and last-hit and deny through the SDK verbs (slice 4, positions in
 * `States.Laning.LastHit`). OHA's spot (its PositionThink target) is handed over by mode_laning_generic.lua
 * through SetSpot. Where the body owns last hits, the Lua Think skips LastHitThink/DenyThink for the bot; its
 * techniques and harass still run first, so the body is resumed only on frames where none of those acted.
 */
import type * as Lib from "bots/FunLib/engine/tasks";
import { BotMode, Unit, Vector } from "bots/ts_libs/dota";
import * as Config from "bots/FunLib/humaniser/config";
import * as LaneConfig from "bots/FunLib/humaniser/lane_config";
import * as Telemetry from "bots/FunLib/humaniser/telemetry";
import * as Phase from "bots/FunLib/humaniser/transitions/phase";
import * as LaneSpot from "bots/FunLib/humaniser/states/lane_spot";
import * as LanePick from "bots/FunLib/humaniser/states/lane_pick";
import * as CoreLastHit from "bots/FunLib/humaniser/states/core_last_hit";

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

let settings: LaningSettings | undefined;

/** Read once: Customize is fixed for the game (tests reload the module with each config). */
export function Settings(): LaningSettings {
    if (settings !== undefined) return settings;
    const s = (Config.Get().States as any)?.Laning as Partial<LaningSettings> | undefined;
    settings = {
        Spot: s?.Spot ?? DEFAULTS.Spot,
        LastHit: s?.LastHit ?? DEFAULTS.LastHit,
        LastHitWithin: s?.LastHitWithin ?? DEFAULTS.LastHitWithin,
    };
    return settings;
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
/** The last SDK spot, kept for HOLD_OVER s when the enemy wave drops out of view (it dies, fog), so the bot does
 * not shuttle to OHA's spot and back between waves. */
const lastSdk: Record<number, { t: number; info: LaneSpot.SpotInfo } | undefined> = {};
const HOLD_OVER = 4;

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
            lastSdk[pid] = { t: now, info: res };
        } else {
            const held = lastSdk[pid];
            if (held !== undefined && now - held.t <= HOLD_OVER) {
                info = held.info;
                v = held.info.spot;
            }
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
    if (CoreLastHit.Applies(bot)) return true;
    const pos = LaneConfig.PositionOf(bot);
    if (pos === undefined) return false;
    for (const p of Settings().LastHit) if (p === pos) return true;
    return false;
}

function* body(bot: Unit, ctx: Lib.Ctx): Lib.TaskBody {
    const sdk = Settings().Spot === "sdk";
    // 'oha' is slice 1's hold: close to PositionThink's own move, standing still once there. 'sdk' shuffles in
    // 50-150 steps every 0.6-1.5 s (knowledge.md 1.1 idle motion) and follows the wave in 150-unit jumps.
    const hold: Lib.Verbs.HoldOpts = sdk
        ? { tolerance: 40, repath: 1.05, jitter: 0.85, scatter: 130, step: [50, 150], follow: 150, hold: "state:laning" }
        : { tolerance: 100, repath: 1, jitter: 0.3, scatter: 50, hold: "state:laning" };
    return yield* ctx.laneFarm(() => Spot(bot) as unknown as Lib.Vec | undefined, {
        hold,
        lastHits: () => {
            const spot = Spot(bot);
            LanePick.NoteScan(bot.GetPlayerID(), DotaTime(), spot !== undefined ? GetUnitToLocationDistance(bot, spot) : undefined);
            return OwnsLastHit(bot);
        },
        within: Settings().LastHitWithin,
        pick: (targets) => {
            const chosen = LanePick.Choose(targets);
            LanePick.NotePick(bot.GetPlayerID(), DotaTime(), targets, chosen);
            return chosen;
        },
        label: (l) => {
            ctx.label(l);
            LanePick.NotePhase(bot.GetPlayerID(), l);
        },
        near: NEAR,
        far: FAR,
        leash: LEASH,
        retarget: true,
        onAttempt: (t, res, contested) =>
            Telemetry.Event("lh", [
                ["pid", bot.GetPlayerID()],
                ["kind", t.kind],
                ["result", res.success ? "ok" : "fail"],
                ["reason", res.reason],
                ["ranged", t.ranged],
                ["eta", math.floor(t.eta * 100) / 100],
                ["contested", contested],
                ["msg", res.message],
            ]),
    });
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
