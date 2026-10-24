/**
 * `laning` state: go to the lane and hold a lane position (slice 1), stand like a high-MMR laner (slice 3,
 * `States.Laning.Spot = 'sdk'`), and last-hit and deny through the SDK verbs (slice 4, positions in
 * `States.Laning.LastHit`). OHA's spot (its PositionThink target) is handed over by mode_laning_generic.lua
 * through SetSpot. While the body runs it owns the laning Think's frame (team slice 14): OHA's own laning steps
 * (aggro draws, techniques, harass, and its last hits where the body does not take them) run inside the body
 * through the `assist` hook, on hold and walk frames only, never during a last-hit or deny attempt.
 * For the mode authority the state flattens OHA's last-hit spike (reason `lasthit`) where the body takes the last
 * hits, refuses team_roam's last-hit score there, and is committed during an attempt.
 */
import type * as Lib from "bots/FunLib/sdk/tasks/tasks";
import { BotMode, Unit, Vector } from "bots/ts_libs/dota";
import * as Config from "bots/FunLib/humaniser/config";
import * as HDebug from "bots/FunLib/humaniser/debug";
import * as Tasks from "bots/FunLib/humaniser/tasks";
import * as LaneConfig from "bots/FunLib/humaniser/lane_config";
import * as Telemetry from "bots/FunLib/humaniser/telemetry";
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
    const pos = LaneConfig.PositionOf(bot);
    if (pos === undefined) return false;
    for (const p of Settings().LastHit) if (p === pos) return true;
    return false;
}

type Assist = (this: void) => boolean;
const assists: Record<number, Assist | undefined> = {};

/** mode_laning_generic.lua hands over its own laning steps; true from it means one of them acted this frame. */
export function SetAssist(bot: Unit, fn: Assist): void {
    assists[bot.GetPlayerID()] = Telemetry.GuardsEnabled() ? Telemetry.Guard("States.laneAssist", fn, () => false) : fn;
}

// An error in OHA's steps must not end the body: it is reported (Guard) or logged, and the frame stays the body's.
function assist(bot: Unit): boolean {
    const fn = assists[bot.GetPlayerID()];
    if (fn === undefined) return false;
    const [ok, acted] = pcall(fn);
    if (!ok) HDebug.Log("states", `lane assist error: ${tostring(acted)}`);
    return ok && acted === true;
}

/** OHA's laning desire before 9:00 (mode_laning_generic), for a last-hit spike seen before any base score. */
const LANING_BASE = 0.446;
const lastBase: Record<number, number | undefined> = {};

/**
 * Host desire while laning is current: OHA's laning score, except that its last-hit spike (0.9) is replaced by
 * the last base score where the body takes this bot's last hits: the body wants the creep, not another mode.
 */
export function Desire(bot: Unit, owned: boolean, score: number, reason?: string): number {
    const pid = bot.GetPlayerID();
    // Never pull the bot back to lane in the middle of another mode's swing or cast (slice 14 run 3: fights cut by
    // the return to laning once the interrupt's commitment ran out).
    if (bot.GetActiveMode() !== BotMode.Laning && Telemetry.InWindup(bot)) return 0;
    if (reason !== "lasthit") {
        // Only real base scores: OHA's NONE exits (harassed, enemies at the ancient, high-ground push) say "not
        // now", and a spike right after one is a frame those checks passed.
        if (score > 0) lastBase[pid] = score;
        return score;
    }
    return owned && OwnsLastHit(bot) ? (lastBase[pid] ?? LANING_BASE) : score;
}

/** The body is in a last-hit or deny attempt (its swing must not lose the laning mode). */
export function Attempting(bot: Unit): boolean {
    const t = Tasks.Current(bot);
    return t !== undefined && t.name === "state:" + NAME && (t.label === "lasthit" || t.label === "deny");
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
        lastHits: () => OwnsLastHit(bot),
        within: Settings().LastHitWithin,
        near: NEAR,
        far: FAR,
        leash: LEASH,
        assist: () => assist(bot),
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

export function Spec(bot: Unit, owns: (bot: Unit, state: string) => boolean): Lib.StateSpec {
    const takesLastHits = (): boolean => OwnsLastHit(bot) && owns(bot, NAME);
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
        desire: (_b, score, reason) => Desire(bot, owns(bot, NAME), score, reason),
        refuses: (_b, mode, reason) => mode === BotMode.TeamRoam && reason === "lasthit" && takesLastHits(),
        committed: () => takesLastHits() && Attempting(bot),
    };
}
