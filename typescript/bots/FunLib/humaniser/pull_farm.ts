/**
 * Support pull farm (slice support-pull-farm, switch Ours.SupportPullFarm; plan docs/proposals/2026-11-05-pull-effect.md piece 3):
 * after an `ok` pull the support stays on the camp it pulled into and clears the neutrals that are left, with the pulled wave
 * fighting them, when the site is safe. A core whose camp trip (CoreCamp) comes to the camp takes it over: the support gives
 * it up and goes back to lane. The job chooser hosts it, after PullJob in rank.
 */
import type * as Lib from "bots/FunLib/engine/tasks";
import { DroppedItem, Unit, UnitType, Vector } from "bots/ts_libs/dota";
import * as CampClaims from "bots/FunLib/humaniser/camp_claims";
import * as Camps from "bots/FunLib/humaniser/camps";
import * as CoreCamp from "bots/FunLib/humaniser/core_camp";
import * as LaneConfig from "bots/FunLib/humaniser/lane_config";
import * as Ours from "bots/FunLib/humaniser/ours";
import * as Profile from "bots/FunLib/humaniser/profile";
import * as PullJob from "bots/FunLib/humaniser/pull_job";
import * as LaneSpot from "bots/FunLib/humaniser/states/lane_spot";
import { ForOurs as Tasks } from "bots/FunLib/humaniser/tasks";
import * as Telemetry from "bots/FunLib/humaniser/telemetry";

// All `judgement` (slice file).
export const SETTINGS = {
    /** Below the pull (0.9) and above a core's camp trip (0.8): it never competes with them for one hero. */
    Priority: 0.88,
    /** The farm starts within this many seconds of the pull's end, else the pull's neutrals are gone or the wave has moved on. */
    StartWithin: 12,
    /** The job ends after this many seconds on the camp (a clear is 7-26 s). */
    MaxFarm: 35,
    /** Ends below this share of max HP (the pull's own bail is 0.25; the camp's neutrals are already half dead). */
    AbortHP: 0.35,
    /** Neutrals this far from the camp's box centre are the camp's (core_camp's CampRadius). */
    CampRadius: 700,
    /** A core of ours (pos1-3) this close to the camp's box centre is already there: no start. */
    CoreThere: 600,
    /** Walk back to the lane front (core_camp's values). */
    ReturnArrive: 900,
    ReturnMax: 25,
    ReturnReorder: 0.5,
    /** After the clear, pick up the madstone drops by the camp before the walk back (user 06/11/2026: "they should pick up
     *  the madstone after if they do the support-pull-farm routine"): dropped items whose name holds PickName (the item is
     *  `madstone_bundle` in the OpenDota match data under docs/team/research/replay-index/cache, item_uses) within
     *  PickRadius of the camp's box centre, for at most PickMax seconds, the order re-given every ReturnReorder. `judgement`. */
    PickName: "madstone",
    PickRadius: 900,
    PickMax: 6,
};

interface Farm {
    camp: number;
    center: Vector;
    lane: number;
    left: number;
    host: number;
    ago: number;
    div: number;
    n0: number;
    g0: number;
    hp0: number;
    hit?: boolean;
    returning?: boolean;
    threatSince?: number;
    back?: number;
    nl?: number;
    /** Madstone drops seen by the camp after the clear, and those gone from the ground after our pickup order. */
    ms?: number;
    mp?: number;
}

const running: Record<number, Farm | undefined> = {};
/** The pull end (`at`) each hero's window was last settled for: one start or one skip line per pull. */
const handled: Record<number, number | undefined> = {};
const lastWhy: Record<number, string | undefined> = {};

export function ResetCache(): void {
    for (const t of [running, handled, lastWhy] as Record<number, unknown>[]) for (const [k] of pairs(t)) delete t[k as number];
}

export function Applies(bot: Unit): boolean {
    return Ours.On("SupportPullFarm") && PullJob.Applies(bot);
}

export function Priority(bot: Unit): number | undefined {
    return Applies(bot) ? SETTINGS.Priority : undefined;
}

export function Claims(bot: Unit): boolean {
    return Running(bot);
}

function locOf(u: Unit): Vector | undefined {
    const at = u.GetLocation();
    return at === null ? undefined : at;
}

function dist(a: Vector, b: Vector): number {
    return math.sqrt((a.x - b.x) ** 2 + (a.y - b.y) ** 2);
}

function hpShare(bot: Unit): number {
    return bot.GetHealth() / math.max(1, bot.GetMaxHealth());
}

/** An ally core (pos1-3) already at the camp. */
function coreThere(bot: Unit, center: Vector): boolean {
    for (const a of GetUnitList(UnitType.AlliedHeroes) ?? []) {
        if (a === null || a === undefined || !a.IsAlive() || a === bot || (LaneConfig.PositionOf(a) ?? 9) > 3) continue;
        const at = locOf(a);
        if (at !== undefined && dist(at, center) <= SETTINGS.CoreThere) return true;
    }
    return false;
}

/** Why the support may not start on the camp now, or undefined. */
function startGate(bot: Unit, camp: Camps.Spawner, center: Vector, blocked: (bot: Unit) => string | undefined): string | undefined {
    const state = PullJob.CampStateOf(camp);
    if (state.n === 0) return "no-neutrals";
    if (CampClaims.On("core", camp.idx) !== undefined) return "core-coming";
    if (coreThere(bot, center)) return "core-there";
    const dmg = PullJob.CampDamage(bot, state, camp.type, undefined);
    if (bot.GetHealth() - dmg < bot.GetMaxHealth() * PullJob.SETTINGS.StartReserve) return "camp-dmg";
    if (CoreCamp.ThreatOnWay(bot, center)) return "threat";
    return blocked(bot) ?? PullJob.PartnerThreat(bot);
}

function fields(bot: Unit, f: Farm | undefined, camp: number): Telemetry.Fields<"pull_clear"> {
    return [
        ["pid", bot.GetPlayerID()],
        ["pos", LaneConfig.PositionOf(bot)],
        ["lane", bot.GetAssignedLane()],
        ["camp", camp],
        ["ago", f?.ago],
        ["div", f?.div],
        ["n0", f?.n0],
    ];
}

function jobLine(bot: Unit, f: Farm, phase: string, why: string): void {
    Telemetry.Event("job", [
        ["pid", bot.GetPlayerID()],
        ["job", "pullfarm"],
        ["phase", phase],
        ["why", why],
        ["host", f.host],
        ...(phase === "end" ? ([["hit", f.hit === true ? 1 : 0]] as Telemetry.Fields<"job">) : []),
    ]);
}

/** Why the farm must stop now (the task's guard, every frame), or undefined. The walk back ignores heroes: laning decides. */
function guard(bot: Unit, f: Farm): string | undefined {
    if (f.returning === true) return undefined;
    if (CampClaims.On("core", f.camp) !== undefined) return "yield";
    if (hpShare(bot) < SETTINGS.AbortHP) return "hp";
    let near = false;
    for (const e of GetUnitList(UnitType.EnemyHeroes) ?? []) {
        if (e === null || e === undefined || !e.IsAlive() || e.IsIllusion()) continue;
        const at = locOf(e);
        if (at !== undefined && dist(at, bot.GetLocation()) <= LaneSpot.HeroReach(bot, e)) near = true;
    }
    if (!near) {
        f.threatSince = undefined;
        return undefined;
    }
    const now = DotaTime();
    f.threatSince = f.threatSince ?? now;
    return now - f.threatSince >= Profile.Get(bot).reactBase ? "threat" : undefined;
}

// CANDIDATE(walkBack): core_camp's `walkBack` is the same walk to the lane front; the rule of two is met, a shared verb waits for a third consumer.
function* walkBack(bot: Unit, f: Farm, ctx: Lib.Ctx): Lib.TaskBody {
    ctx.label("return");
    f.returning = true;
    const from = DotaTime();
    let orderedAt = -math.huge;
    while (true) {
        if (!bot.IsAlive()) return { success: false, reason: "dead" };
        const now = DotaTime();
        const front = GetLaneFrontLocation(bot.GetTeam(), f.lane, 0);
        if (dist(bot.GetLocation(), front) <= SETTINGS.ReturnArrive) {
            f.back = now;
            return { success: true, reason: "ok", message: "back" };
        }
        if (now - from > SETTINGS.ReturnMax) return { success: false, reason: "timeout", message: "late" };
        if (now - orderedAt >= SETTINGS.ReturnReorder) {
            bot.Action_MoveToLocation(front);
            orderedAt = now;
        }
        yield;
    }
}

function* body(bot: Unit, f: Farm, ctx: Lib.Ctx): Lib.TaskBody {
    const hooks = { label: (l: string) => ctx.label(l), urgent: ctx.urgent };
    const r = yield* Tasks.Jobs()!.clearCamp(
        bot as unknown as Lib.TaskUnit,
        { at: f.center as unknown as Lib.Vec, radius: SETTINGS.CampRadius, deadline: f.left + SETTINGS.MaxFarm },
        hooks
    );
    f.nl = campLeft(f.center);
    if (!r.success) return r;
    yield* pickUp(bot, f, ctx);
    return yield* walkBack(bot, f, ctx);
}

/** The madstone drops on the ground within PickRadius of the camp, keyed by where they lie (a handle may not compare equal
 *  between calls). */
function madstones(center: Vector): Map<string, DroppedItem> {
    const out = new Map<string, DroppedItem>();
    for (const d of GetDroppedItemList() ?? []) {
        if (d === undefined || d === null || d.item === undefined || d.item === null || d.location === undefined) continue;
        if (string.find(d.item.GetName(), SETTINGS.PickName, 1, true)[0] === undefined || dist(d.location, center) > SETTINGS.PickRadius) continue;
        out.set(`${math.floor(d.location.x)},${math.floor(d.location.y)}`, d);
    }
    return out;
}

/** Picks up the madstone drops by the cleared camp (SETTINGS PickName), nearest first, for at most PickMax seconds. */
function* pickUp(bot: Unit, f: Farm, ctx: Lib.Ctx): Lib.TaskBody {
    let left = madstones(f.center);
    f.ms = left.size;
    f.mp = 0;
    const done: Lib.Result = { success: true, reason: "ok" };
    if (f.ms === 0) return done;
    ctx.label("pickup");
    const from = DotaTime();
    let ordered: string[] = [];
    let orderedAt = -math.huge;
    while (bot.IsAlive() && DotaTime() - from <= SETTINGS.PickMax) {
        let best: DroppedItem | undefined;
        let bestKey: string | undefined;
        for (const [k, d] of left) {
            if (best === undefined || dist(bot.GetLocation(), d.location) < dist(bot.GetLocation(), best.location)) {
                best = d;
                bestKey = k;
            }
        }
        if (best === undefined || bestKey === undefined) break;
        if (DotaTime() - orderedAt >= SETTINGS.ReturnReorder) {
            bot.Action_PickUpItem(best.item);
            if (ordered.indexOf(bestKey) < 0) ordered.push(bestKey);
            orderedAt = DotaTime();
        }
        yield;
        const now = madstones(f.center);
        f.mp += ordered.filter((k) => !now.has(k)).length;
        ordered = ordered.filter((k) => now.has(k));
        left = now;
    }
    return done;
}

function campLeft(center: Vector): number {
    let n = 0;
    for (const u of GetUnitList(UnitType.NeutralCreeps) ?? []) {
        if (u === null || u === undefined || !u.IsAlive()) continue;
        const at = locOf(u);
        if (at !== undefined && dist(at, center) <= SETTINGS.CampRadius) n++;
    }
    return n;
}

function finish(bot: Unit, f: Farm, r: Lib.Result, label: string | undefined): void {
    running[bot.GetPlayerID()] = undefined;
    CampClaims.Set("pullfarm", bot.GetPlayerID(), undefined);
    const why = r.success ? (r.message ?? "ok") : `${r.reason}${r.message !== undefined ? ":" + r.message : ""}`;
    jobLine(bot, f, "end", why);
    const r1 = (x: number | undefined) => (x !== undefined ? math.floor(x * 10 + 0.5) / 10 : undefined);
    Telemetry.Event("pull_clear", [
        ["phase", "end"],
        ...fields(bot, f, f.camp),
        ["res", r.success ? "ok" : "fail"],
        ["why", why],
        ["label", label],
        ["nl", f.nl ?? (label === "return" ? 0 : campLeft(f.center))],
        ["back", r1(f.back)],
        ["g0", f.g0],
        ["g1", bot.GetNetWorth()],
        ["secs", r1(DotaTime() - f.left)],
        ["hp0", math.floor(f.hp0 * 100 + 0.5) / 100],
        ["hp", math.floor(hpShare(bot) * 100 + 0.5) / 100],
        ["died", bot.IsAlive() ? 0 : 1],
        ["ms", f.ms],
        ["mp", f.mp],
    ]);
}

/**
 * Every frame while the chooser asks: true while a farm runs or as one starts. A farm may start only in the StartWithin
 * seconds after this hero's ok pull, on the pull's own camp; the window closes with one skip line naming the gate that held it.
 */
export function Wants(bot: Unit, blocked: (bot: Unit) => string | undefined, host: number): boolean {
    if (!Applies(bot)) return false;
    const pid = bot.GetPlayerID();
    Tasks.Tick(bot);
    if (running[pid] !== undefined) return true;
    if (Tasks.Jobs() === undefined || !LaneConfig.InLaningPhase() || !bot.IsAlive()) return false;
    const pull = PullJob.Finished(bot);
    if (pull === undefined || handled[pid] === pull.at) return false;
    const now = DotaTime();
    const camp = Camps.SpawnerByIdx(pull.camp);
    const ago = now - pull.at;
    if (camp === undefined) return false;
    const center = Camps.BoxCenter(camp);
    const f: Farm = {
        camp: pull.camp,
        center,
        lane: bot.GetAssignedLane(),
        left: now,
        host,
        ago: math.floor(ago * 10 + 0.5) / 10,
        div: pull.div,
        n0: PullJob.CampStateOf(camp).n,
        g0: bot.GetNetWorth(),
        hp0: hpShare(bot),
    };
    const why = ago > SETTINGS.StartWithin ? lastWhy[pid] ?? "late" : startGate(bot, camp, center, blocked);
    if (why !== undefined) {
        lastWhy[pid] = why;
        if (ago > SETTINGS.StartWithin || why === "no-neutrals" || why === "core-coming" || why === "core-there") {
            handled[pid] = pull.at;
            lastWhy[pid] = undefined;
            Telemetry.Event("pull_clear", [["phase", "skip"], ...fields(bot, f, pull.camp), ["why", why]]);
        }
        return false;
    }
    handled[pid] = pull.at;
    lastWhy[pid] = undefined;
    const ok = Tasks.Start(bot, { name: "pullfarm", host, preemptAfter: 1, stallAfter: 4, guard: () => guard(bot, f), onEnd: (r, info) => finish(bot, f, r, info.label) }, (ctx: Lib.Ctx) =>
        body(bot, f, ctx)
    );
    if (!ok) {
        Telemetry.Event("pull_clear", [["phase", "skip"], ...fields(bot, f, pull.camp), ["why", "refused"]]);
        return false;
    }
    running[pid] = f;
    CampClaims.Set("pullfarm", pid, f.camp);
    jobLine(bot, f, "start", "trigger");
    Telemetry.Event("pull_clear", [["phase", "start"], ...fields(bot, f, f.camp), ["hp0", math.floor(f.hp0 * 100 + 0.5) / 100]]);
    return true;
}

export function Step(bot: Unit, host: number): boolean {
    return running[bot.GetPlayerID()] !== undefined && Tasks.Step(bot, host);
}

export function Running(bot: Unit): boolean {
    return running[bot.GetPlayerID()] !== undefined;
}

export function End(bot: Unit, why: string): void {
    if (running[bot.GetPlayerID()] !== undefined) Tasks.Cancel(bot, "cancelled", why);
}

export function NoteHit(bot: Unit): void {
    const f = running[bot.GetPlayerID()];
    if (f !== undefined) f.hit = true;
}

export function NoteIdleHeld(_bot: Unit): void {}
