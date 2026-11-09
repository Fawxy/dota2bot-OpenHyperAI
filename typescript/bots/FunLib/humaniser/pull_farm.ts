/**
 * Support pull farm (slice support-pull-farm, switch Ours.SupportPullFarm; plan docs/proposals/2026-11-05-pull-effect.md piece 3):
 * after an `ok` pull the support stays on the camp it pulled into and clears the neutrals that are left, with the pulled wave
 * fighting them, when the site is safe. A core whose camp trip (CoreCamp) comes to the camp takes it over: the support gives
 * it up and goes back to lane. The job chooser hosts it, after PullJob in rank. It applies to every puller PullJob takes
 * (the pos5, or a lone pos4 on its lane's pull camp: the off-lane's large camp) and takes the neutrals' last hits so the
 * camp's madstone goes to it (SETTINGS LastHit, user 06/11/2026).
 */
import type * as Lib from "bots/FunLib/engine/tasks";
import { DamageType, DroppedItem, Unit, UnitType, Vector } from "bots/ts_libs/dota";
import * as CampClaims from "bots/FunLib/humaniser/camp_claims";
import * as Camps from "bots/FunLib/humaniser/camps";
import * as CoreCamp from "bots/FunLib/humaniser/core_camp";
import * as Threat from "bots/FunLib/humaniser/threat";
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
    /** The start check (`camp-dmg`): the camp's damage on the support over ClearSeconds of its hits must leave it
     *  ClearReserve of its max HP. The clear stands in the camp, so its window is not the pull's HitSeconds (the puller
     *  walks away): these are the values the gate had while it shared the pull's (8 s of lead at a 0.5 hit share, 0.3). */
    ClearSeconds: 4,
    ClearReserve: 0.3,
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
    /** The kills are the support's (user 06/11/2026: when a camp is finished by a hero close enough, maybe the one with the
     *  last hit, the madstone goes straight into its inventory, otherwise it drops on the floor and is often contested; the
     *  support should take the last hits, at least the camp's last neutral, and stay close at the kill). While a unit of ours
     *  other than the support attacks a camp neutral (the pulled wave) and the neutral holds at most LastHitHits of the
     *  support's hits, the clear waits in range for the hit that kills it (the engine's lastHit) instead of attacking; above
     *  that, or with no one else on it, it attacks. LastHitAll: every neutral (the gold too), else only the camp's last.
     *  Whether the last hit decides the madstone, and how close "close enough" is, is UNVERIFIED (pull_clear fl, fd, mi).
     *  `judgement`. */
    LastHit: true,
    LastHitAll: true,
    LastHitHits: 2,
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
    /** Last hits over the farm (GetLastHits), lastHit tries and kills; the camp's final neutral: 1 when its kill was the
     *  support's, the support's distance to it then; madstone charges gained in the inventory over the farm. */
    lh0: number;
    lt?: number;
    lk?: number;
    fl?: number;
    fd?: number;
    mi0: number;
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
    const dmg = PullJob.CampDamage(bot, state, camp.type, SETTINGS.ClearSeconds);
    if (bot.GetHealth() - dmg < bot.GetMaxHealth() * SETTINGS.ClearReserve) return "camp-dmg";
    // Ours.Threat: the shared gate on the camp (`threat`, and since slice threat 3 `missing` too); off, the old reach test.
    if (Ours.On("Threat")) {
        const why = Threat.Gate(bot, bot.GetLocation(), center, "pull_farm").why;
        if (why !== undefined) return why;
    } else if (CoreCamp.ThreatOnWay(bot, center)) return "threat";
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

/** Madstone charges in `bot`'s item slots (inventory, backpack, stash and neutral slot). */
function madstoneCharges(bot: Unit): number {
    let n = 0;
    for (let slot = 0; slot <= 16; slot++) {
        const it = bot.GetItemInSlot(slot);
        if (it === null || it === undefined || string.find(it.GetName(), SETTINGS.PickName, 1, true)[0] === undefined) continue;
        n += math.max(1, it.GetCurrentCharges?.() ?? 1);
    }
    return n;
}

/** A unit of ours other than `bot` (the pulled wave's creeps, an ally hero) attacking `n`. */
function othersOn(bot: Unit, n: Unit): boolean {
    for (const kind of [UnitType.AlliedCreeps, UnitType.AlliedHeroes]) {
        for (const u of GetUnitList(kind) ?? []) {
            if (u !== null && u !== undefined && u !== bot && u.IsAlive() && u.GetAttackTarget() === n) return true;
        }
    }
    return false;
}

/** The clear waits for the killing hit on `n` (SETTINGS LastHit). */
function takeLastHit(bot: Unit, n: Unit, camp: Unit[]): boolean {
    if (!SETTINGS.LastHit || (!SETTINGS.LastHitAll && camp.length > 1) || !othersOn(bot, n)) return false;
    const hit = n.GetActualIncomingDamage(bot.GetAttackDamage(), DamageType.Physical);
    return n.GetHealth() <= SETTINGS.LastHitHits * math.max(1, hit);
}

function* body(bot: Unit, f: Farm, ctx: Lib.Ctx): Lib.TaskBody {
    const hooks = { label: (l: string) => ctx.label(l), urgent: ctx.urgent };
    let lh = bot.GetLastHits();
    const r = yield* Tasks.Jobs()!.clearCamp(
        bot as unknown as Lib.TaskUnit,
        {
            at: f.center as unknown as Lib.Vec,
            radius: SETTINGS.CampRadius,
            deadline: f.left + SETTINGS.MaxFarm,
            lastHit: (n, camp) => takeLastHit(bot, n as unknown as Unit, camp as unknown as Unit[]),
            onLastHit: (_n, res) => {
                f.lt = (f.lt ?? 0) + 1;
                if (res.success) f.lk = (f.lk ?? 0) + 1;
            },
            onGone: (_n, at, left) => {
                const now = bot.GetLastHits();
                const mine = now > lh;
                lh = now;
                if (left > 0) return;
                f.fl = mine ? 1 : 0;
                f.fd = math.floor(dist(bot.GetLocation(), at as unknown as Vector) + 0.5);
            },
        },
        hooks
    );
    // A clear that ended with the final neutral not the support's target when it died: not its kill.
    if (r.success && r.message === "cleared" && f.fl === undefined) f.fl = 0;
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
        ["lh", bot.GetLastHits() - f.lh0],
        ["lt", f.lt],
        ["lk", f.lk],
        ["fl", f.fl],
        ["fd", f.fd],
        ["mi", madstoneCharges(bot) - f.mi0],
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
        lh0: bot.GetLastHits(),
        mi0: madstoneCharges(bot),
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
