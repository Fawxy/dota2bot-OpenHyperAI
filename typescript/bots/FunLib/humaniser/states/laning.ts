/**
 * `laning` state: go to the lane and hold a lane position (slice 1), stand like a high-MMR laner (slice 3,
 * `States.Laning.Spot = 'sdk'`, and for cores `Ours.LaneSpot`), and last-hit and deny through the SDK verbs (slice 4, positions in
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
import * as SupportDeny from "bots/FunLib/humaniser/states/support_deny";
import * as Ours from "bots/FunLib/humaniser/ours";
import * as LaneClaims from "bots/FunLib/humaniser/states/lane_claims";
import * as PreHit from "bots/FunLib/humaniser/states/pre_hit";
import * as IdleSwing from "bots/FunLib/humaniser/states/idle_swing";
import * as Tasks from "bots/FunLib/humaniser/tasks";
import * as Contest from "bots/FunLib/humaniser/states/contest";

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
/** lane_aggro's fed creep per bot (the lane_spot input `fed`), set while its feed watch runs. */
const fedCreep: Record<number, Unit | undefined> = {};

/** lane_aggro: the creep this bot fed their wave onto, or undefined when its watch ends. */
export function SetFed(bot: Unit, creep: Unit | undefined): void {
    fedCreep[bot.GetPlayerID()] = creep;
}

export function ClearFed(): void {
    for (const k in fedCreep) fedCreep[k as unknown as number] = undefined;
    for (const k in holdPoint) holdPoint[k as unknown as number] = undefined;
}

/** wave_hold's hold point per bot (the lane_spot input `hold`), set while a hold runs. */
const holdPoint: Record<number, Vector | undefined> = {};

/** wave_hold: the point this bot holds their wave at, or undefined when the hold ends. */
export function SetHold(bot: Unit, at: Vector | undefined): void {
    holdPoint[bot.GetPlayerID()] = at;
}

/**
 * Ours.LaneSpot: this bot stands on our spot whatever States.Laning.Spot says: cores under Ours.CoreLastHit, and since slice
 * support-spot supports whose lane hits and harass are ours (Ours.SupportHarass; their attacks on heroes run in our attack
 * mode, so the body's hold no longer cancels them).
 */
export function OwnsSpot(bot: Unit): boolean {
    if (!Ours.On("LaneSpot")) return false;
    return CoreLastHit.Applies(bot) || (OwnsSupportHits(bot) && SupportDeny.Harass(bot));
}

/** The spot the body holds this frame (cached per frame: holdAt and its exits read it several times). OHA's spot only when
 * ours is not on for the bot or cannot be computed (no lane direction, an error). */
export function Spot(bot: Unit): Vector | undefined {
    const pid = bot.GetPlayerID();
    const now = DotaTime();
    const c = spotCache[pid];
    if (c !== undefined && c.t === now) return c.v;
    let v: Vector | undefined;
    let info: LaneSpot.SpotInfo | undefined;
    if (Settings().Spot === "sdk" || OwnsSpot(bot)) {
        const [ok, res] = pcall(LaneSpot.Compute, bot, RoleOf(bot), fedCreep[pid], holdPoint[pid]);
        if (ok && res !== undefined) {
            info = res;
            v = res.spot;
        }
    }
    if (v === undefined) v = ohaSpot(bot);
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

/**
 * Whether the body takes this support's lane hits (Ours.SupportDeny): its denies, and with Ours.SupportLastHit the last hits
 * no core will take (states/lane_claims). Stepped only by its support_lane step, so OHA's positioning and harass keep the
 * other frames.
 */
export function OwnsSupportHits(bot: Unit): boolean {
    return !OwnsLastHit(bot) && SupportDeny.Applies(bot);
}

/**
 * The creeps this laner may take: for a core all but a deny an allied support is attempting (LaneClaims.CoreMine; all with
 * Ours.CoreDenyYield off), the support's claims otherwise.
 */
// OwnsLastHit is checked first: a bot listed in Laning.LastHit takes a core's mine (CoreMine) even at pos 4-5; DenyYield
// never yields for a pos 4-5, so two of them cannot yield to each other (review 2026-11-06-deny-yield-0ee970a F4).
function claimsFor(bot: Unit): ((this: void, t: Lib.Verbs.LaneTarget) => boolean) | undefined {
    if (OwnsLastHit(bot)) return LaneClaims.CoreMine(bot);
    if (!OwnsSupportHits(bot)) return undefined;
    const lastHits = SupportDeny.LastHits(bot);
    const within = Settings().LastHitWithin;
    return (t) => (t.kind === "deny" ? true : lastHits && LaneClaims.SupportClaim(bot, t, within) !== undefined);
}

/**
 * The claims on each support's last few picks, for its ev=lh (`claim`): a retarget picks the next creep before the attempt it
 * replaces reports, so the claim is looked up by creep.
 */
const claims: Record<number, { creep: Lib.TaskCreep; claim: LaneClaims.Claim | undefined }[] | undefined> = {};
const CLAIMS_KEPT = 4;

function noteClaim(pid: number, creep: Lib.TaskCreep, claim: LaneClaims.Claim | undefined): void {
    let list = claims[pid];
    if (list === undefined) {
        list = [];
        claims[pid] = list;
    }
    list.push({ creep, claim });
    if (list.length > CLAIMS_KEPT) list.shift();
}

function claimOf(pid: number, creep: Lib.TaskCreep): LaneClaims.Claim | undefined {
    const list = claims[pid];
    if (list === undefined) return undefined;
    for (let i = list.length - 1; i >= 0; i--) if (list[i].creep === creep) return list[i].claim;
    return undefined;
}

/**
 * Where each bot's attempt creep was last seen alive, for its ev=lh (`cx`, `cy`, `ca`): a creep that died ends the attempt,
 * and a dead creep's handle no longer answers, so the end reads the place from the last scan that offered it.
 */
const seen: Record<number, { creep: Lib.TaskCreep; x: number; y: number; t: number } | undefined> = {};

function noteSeen(pid: number, creep: Lib.TaskCreep): void {
    const at = creep.GetLocation();
    if (at === undefined) return;
    seen[pid] = { creep, x: at.x, y: at.y, t: DotaTime() };
}

function placeOf(pid: number, creep: Lib.TaskCreep): [number | undefined, number | undefined, number | undefined] {
    // A creep can read alive with no location (prhfc2 game C t=155.533), and a removed creep's handle raises on IsAlive
    // (prhchk5 game A on 1, t=215.833).
    const at = !(creep.IsNull?.() ?? false) && creep.IsAlive() ? creep.GetLocation() : undefined;
    if (at !== undefined) return [math.floor(at.x), math.floor(at.y), 0];
    const s = seen[pid];
    if (s === undefined || s.creep !== creep) return [undefined, undefined, undefined];
    return [math.floor(s.x), math.floor(s.y), math.floor((DotaTime() - s.t) * 100) / 100];
}

/** The idle swing the body last picked, per bot, so its phase label and attempt line name it (states/idle_swing). */
const idlePicks: Record<number, Lib.Verbs.LaneTarget | undefined> = {};

/** The price of each creep the pick last asked `far` about, per bot, so a chosen walk-in starts with the price it was chosen on. */
const farPrices: Record<number, { creep: Lib.TaskCreep; price: Contest.Price }[] | undefined> = {};

/** Ours.CoreContest: a melee core may walk past MAX_WALK to a last hit whose walk-in price passes (states/contest). */
function farFor(bot: Unit): LanePick.Far | undefined {
    if (!Contest.Applies(bot)) return undefined;
    const pid = bot.GetPlayerID();
    const asked: { creep: Lib.TaskCreep; price: Contest.Price }[] = [];
    farPrices[pid] = asked;
    return (t) => {
        if (t.walk > Contest.CONTEST_WALK || Contest.Refused(pid, t.creep)) return false;
        const price = Contest.PriceFor(bot, t);
        asked.push({ creep: t.creep, price });
        if (!price.ok && Contest.NoteSkip(pid, t.creep, price.why, "pick")) logSkip(bot, t, price, "pick");
        return price.ok;
    };
}

function logSkip(bot: Unit, t: Lib.Verbs.LaneTarget, price: Contest.Price, at: string): void {
    Telemetry.Event("contest_skip", [
        ["pid", bot.GetPlayerID()],
        ["at", at],
        ["why", price.why],
        ["cc", math.floor(price.cost * 1000) / 10],
        ["n", price.heroes],
        ["ex", math.floor(price.exposure * 100) / 100],
        ["walk", math.floor(t.walk * 100) / 100],
        ["dies", t.dies === math.huge ? -1 : math.floor(t.dies * 100) / 100],
        ["hf", math.floor((bot.GetHealth() / math.max(bot.GetMaxHealth(), 1)) * 100) / 100],
    ]);
}

function choose(bot: Unit, targets: Lib.Verbs.LaneTarget[], current?: Lib.Verbs.LaneTarget, pre?: Lib.Verbs.LaneTarget): Lib.Verbs.LaneTarget | undefined {
    const pid = bot.GetPlayerID();
    const claims = claimsFor(bot);
    const far = farFor(bot);
    // A creep whose walk-in the price released is not picked again: from nearer, the plain reach rule would take it unpriced.
    const mine: ((this: void, t: Lib.Verbs.LaneTarget) => boolean) | undefined =
        far === undefined ? claims : (t) => !Contest.Refused(pid, t.creep) && (claims === undefined || claims(t));
    let idle: Lib.Verbs.LaneTarget | undefined;
    const chosen = LanePick.Choose(
        targets,
        current,
        mine,
        pre,
        () => {
            const verbs = Tasks.Verbs();
            idle = verbs !== undefined ? IdleSwing.Find(bot, verbs, mine) : undefined;
            return idle;
        },
        far,
    );
    idlePicks[pid] = idle !== undefined && chosen === idle ? idle : undefined;
    return chosen;
}

/**
 * A walk-in starts when the pick chose a last hit beyond MAX_WALK; while it runs its price is read again every scan, and a
 * price that no longer passes (a second hero came, HP fell) refuses the creep, which releases the attempt through laneFarm's
 * dropLost. Any other undefined pick keeps the wait, as for every core attempt.
 */
function contestPick(bot: Unit, chosen: Lib.Verbs.LaneTarget | undefined, current: Lib.Verbs.LaneTarget | undefined): Lib.Verbs.LaneTarget | undefined {
    const pid = bot.GetPlayerID();
    if (current !== undefined && Contest.Running(pid, current.creep) !== undefined && (chosen === undefined || chosen.creep === current.creep)) {
        const price = Contest.PriceFor(bot, current, true);
        if (!price.ok) {
            Contest.Refuse(pid, current.creep);
            if (Contest.NoteSkip(pid, current.creep, price.why, "walk")) logSkip(bot, current, price, "walk");
            return undefined;
        }
    }
    if (chosen !== undefined && chosen.kind === "lasthit" && chosen.walk > LanePick.MAX_WALK && Contest.Running(pid, chosen.creep) === undefined) {
        for (const fp of farPrices[pid] ?? []) {
            if (fp.creep === chosen.creep) Contest.Start(pid, chosen.creep, fp.price, bot.GetHealth(), DotaTime());
        }
    }
    return chosen;
}

/**
 * A core's last yield (Ours.CoreDenyYield) not yet reported, for its ev=lh `yd`: the support it left a deny to, and when. The
 * next attempt reported carries it if it ends within YIELD_REPORT_SECS of the yield; in smoke game deny-yield_fn1 most yields
 * came with nothing else on offer, so the yield and the next attempt are often seconds apart (ev=snap's `yc` counts every
 * yield). An older yield is dropped unreported (review 2026-11-06-deny-yield-0ee970a F2: a stale yd on a later last hit).
 */
const yields: Record<number, { sup: number; t: number } | undefined> = {};
const YIELD_REPORT_SECS = 6;

/** After a core's pick: whether the pick without the yield was a deny an allied support is attempting, so the core yielded it. */
function noteYield(bot: Unit, targets: Lib.Verbs.LaneTarget[], current: Lib.Verbs.LaneTarget | undefined, pre: Lib.Verbs.LaneTarget | undefined, chosen: Lib.Verbs.LaneTarget | undefined): void {
    if (!OwnsLastHit(bot) || LaneClaims.CoreMine(bot) === undefined) return;
    const plain = LanePick.Choose(targets, current, undefined, pre);
    if (plain === undefined || plain.kind !== "deny" || (chosen !== undefined && chosen.creep === plain.creep)) return;
    const sup = LaneClaims.DenyYield(bot, plain);
    if (sup === undefined) return;
    const pid = bot.GetPlayerID();
    LanePick.NoteYield(pid, plain.creep);
    yields[pid] = { sup, t: DotaTime() };
}

function yieldOf(pid: number): number | undefined {
    const y = yields[pid];
    yields[pid] = undefined;
    return y !== undefined && DotaTime() - y.t <= YIELD_REPORT_SECS ? y.sup : undefined;
}

/**
 * The creeps this bot pre-hit (states/pre_hit), newest last, so the ev=lh of a later attempt on one says `ph=1` (last hits per
 * pre-hit). A creep handle stays the same unit until it dies.
 */
const preHits: Record<number, Lib.TaskCreep[] | undefined> = {};
const PRE_HITS_KEPT = 4;

function notePreHit(pid: number, creep: Lib.TaskCreep): void {
    let list = preHits[pid];
    if (list === undefined) {
        list = [];
        preHits[pid] = list;
    }
    list.push(creep);
    if (list.length > PRE_HITS_KEPT) list.shift();
}

function wasPreHit(pid: number, creep: Lib.TaskCreep): boolean {
    for (const c of preHits[pid] ?? []) if (c === creep) return true;
    return false;
}

/**
 * A lane hit the support's body would go for now: what its own scan would pick (same laneTargets query and claims), within
 * the leash of the spot. support_lane reads it to step the body ahead of OHA's own laning steps.
 */
export function HitOffered(bot: Unit): boolean {
    if (!OwnsSupportHits(bot)) return false;
    const spot = Spot(bot);
    if (spot !== undefined && GetUnitToLocationDistance(bot, spot) > LEASH) return false;
    const verbs = Tasks.Verbs();
    if (verbs === undefined) return false;
    return choose(bot, verbs.laneTargets(bot as unknown as Lib.TaskUnit, { within: Settings().LastHitWithin })) !== undefined;
}

function* body(bot: Unit, ctx: Lib.Ctx): Lib.TaskBody {
    const sdk = Settings().Spot === "sdk" || OwnsSpot(bot);
    // 'oha' is slice 1's hold: close to PositionThink's own move, standing still once there. 'sdk' shuffles in
    // 50-150 steps every 0.6-1.5 s (knowledge.md 1.1 idle motion) and follows the wave in 150-unit jumps.
    // A core on our spot (Ours.LaneSpot) stands at the edge of an enemy hero's reach, so its shuffle and follow stay small:
    // lposchk1's 130 scatter and 150 follow left it up to ~280 inside that edge.
    const tight = OwnsSpot(bot);
    const hold: Lib.Verbs.HoldOpts = sdk
        ? { tolerance: 40, repath: 1.05, jitter: 0.85, scatter: tight ? 40 : 130, step: tight ? [30, 60] : [50, 150], follow: tight ? 50 : 150, hold: "state:laning" }
        : { tolerance: 100, repath: 1, jitter: 0.3, scatter: 50, hold: "state:laning" };
    return yield* ctx.laneFarm(() => Spot(bot) as unknown as Lib.Vec | undefined, {
        hold,
        lastHits: () => {
            const spot = Spot(bot);
            LanePick.NoteScan(bot.GetPlayerID(), DotaTime(), spot !== undefined ? GetUnitToLocationDistance(bot, spot) : undefined);
            const owns = OwnsLastHit(bot) || OwnsSupportHits(bot);
            if (owns) LanePick.NoteWait(bot as unknown as Lib.TaskUnit);
            return owns;
        },
        within: Settings().LastHitWithin,
        pick: (targets, current) => {
            const verbs = Tasks.Verbs();
            const pre = verbs !== undefined ? PreHit.Find(bot, verbs) : undefined;
            const chosen = contestPick(bot, choose(bot, targets, current, pre), current);
            noteYield(bot, targets, current, pre, chosen);
            if (chosen !== undefined) noteSeen(bot.GetPlayerID(), chosen.creep);
            // laneFarm asks on every scan, also with nothing offered: an empty scan that picks nothing is not a pick.
            if (chosen === undefined && targets.length === 0) return undefined;
            // A scan that stays on the attempt's creep is not a pick (the offers at the pick stay the attempt's).
            if (current === undefined || chosen === undefined || chosen.creep !== current.creep || chosen.kind !== current.kind) {
                LanePick.NotePick(bot.GetPlayerID(), DotaTime(), targets, chosen);
                if (chosen !== undefined && OwnsSupportHits(bot)) {
                    noteClaim(bot.GetPlayerID(), chosen.creep, LaneClaims.SupportClaim(bot, chosen, Settings().LastHitWithin));
                }
            }
            return chosen;
        },
        label: (l) => {
            // A caller-built `prehit` is a tower pre-hit or an idle swing; the swing is labelled by its kind.
            const ip = idlePicks[bot.GetPlayerID()];
            if (l === "prehit" && ip !== undefined) l = IdleSwing.Of(bot.GetPlayerID(), ip.creep)?.kind ?? l;
            ctx.label(l);
            LanePick.NotePhase(bot.GetPlayerID(), l);
        },
        near: NEAR,
        far: FAR,
        leash: LEASH,
        retarget: true,
        // A support stops waiting on a creep the others will kill before its swing lands (sdp1: 15 of 90 lost denies), so
        // the body hands the frame back instead of holding on (D5): to its hold step on our spot, or to OHA's positioning and harass.
        // A walk-in is released only when its price fails (contestPick refuses the creep), not when its creep drops out of the
        // offers for a scan as its attackers change: drill cwd1 dropped 13 of 28 walk-ins 0.1-0.9 s in that way, none on price.
        dropLost: (cur) => OwnsSupportHits(bot) || Contest.Refused(bot.GetPlayerID(), cur.creep),
        radius: Contest.Applies(bot) ? Contest.RADIUS : undefined,
        onAttempt: (t, res, contested) => {
            const [ol, od, ow] = LanePick.AttemptOffers(bot.GetPlayerID());
            const idle = t.kind === "prehit" ? IdleSwing.Of(bot.GetPlayerID(), t.creep) : undefined;
            if (idle !== undefined) {
                const prior = idle.kind !== "shove" ? IdleSwing.SpentOn(bot.GetPlayerID(), t.creep) ?? 0 : undefined;
                if (res.success && idle.kind !== "shove") IdleSwing.NoteSwing(bot.GetPlayerID(), t.creep);
                Telemetry.Event("idle_swing", [
                    ["pid", bot.GetPlayerID()],
                    ["kind", idle.kind],
                    ["n", prior],
                    ["cx", math.floor(idle.x)],
                    ["cy", math.floor(idle.y)],
                    ["mode", idle.mode],
                    ["result", res.success ? "ok" : "fail"],
                    ["reason", res.reason],
                    ["ranged", t.ranged],
                    ["walk", math.floor(t.walk * 100) / 100],
                    ["hp", math.floor(idle.hp)],
                    ["hf", math.floor(idle.hf * 100) / 100],
                    ["kill", idle.kill === undefined || idle.kill === math.huge ? undefined : math.floor(idle.kill * 100) / 100],
                    ["reach", idle.reach === undefined ? undefined : idle.reach === math.huge ? -1 : math.floor(idle.reach * 100) / 100],
                    ["focus", idle.focus === true ? true : undefined],
                    ["hits", idle.hits],
                    ["cid", Telemetry.CreepId(t.creep as unknown as Unit)],
                    ["dn", IdleSwing.Count(bot, "GetDenies") > idle.denies ? true : undefined],
                    ["lh", IdleSwing.Count(bot, "GetLastHits") > idle.lastHits ? true : undefined],
                    ["contested", contested],
                    ["msg", res.message],
                ]);
                // The note is spent: a later tower pre-hit on the same creep is a prehit, not this swing.
                IdleSwing.Clear(bot.GetPlayerID());
                return;
            }
            if (t.kind === "prehit") {
                const n = PreHit.NoteOf(bot.GetPlayerID(), t.creep);
                if (res.success) notePreHit(bot.GetPlayerID(), t.creep);
                Telemetry.Event("prehit", [
                    ["pid", bot.GetPlayerID()],
                    ["result", res.success ? "ok" : "fail"],
                    ["reason", res.reason],
                    ["ranged", t.ranged],
                    ["walk", math.floor(t.walk * 100) / 100],
                    ["dies", t.dies === math.huge ? -1 : math.floor(t.dies * 100) / 100],
                    ["hp", n?.hp !== undefined ? math.floor(n.hp) : undefined],
                    ["t0", n?.t0 !== undefined ? math.floor(n.t0 * 100) / 100 : undefined],
                    ["lo", n?.lo !== undefined ? math.floor(n.lo) : undefined],
                    ["np", n?.plan !== undefined ? n.plan.swings.length - 1 : undefined],
                    ["tk", n?.plan !== undefined ? math.floor(n.plan.swings[n.plan.swings.length - 1] * 100) / 100 : undefined],
                    ["hk", n?.plan !== undefined ? math.floor(n.plan.hpKill) : undefined],
                    ["mg", n?.plan !== undefined ? math.floor(n.plan.margin) : undefined],
                    ["ol", ol],
                    ["contested", contested],
                ]);
                return;
            }
            const claim = OwnsSupportHits(bot) ? claimOf(bot.GetPlayerID(), t.creep) : undefined;
            const [cx, cy, ca] = placeOf(bot.GetPlayerID(), t.creep);
            const walkIn = Contest.Finish(bot.GetPlayerID(), t.creep);
            const maxHp = math.max(bot.GetMaxHealth(), 1);
            Telemetry.Event("lh", [
                ["pid", bot.GetPlayerID()],
                ["kind", t.kind],
                ["result", res.success ? "ok" : "fail"],
                ["reason", res.reason],
                ["ranged", t.ranged],
                ["eta", math.floor(t.eta * 100) / 100],
                ["contested", contested],
                ["ol", ol],
                ["od", od],
                ["ow", ow],
                ["walk", math.floor(t.walk * 100) / 100],
                ["dies", t.dies === math.huge ? -1 : math.floor(t.dies * 100) / 100],
                ["claim", claim],
                ["cx", cx],
                ["cy", cy],
                ["ca", ca],
                ["ph", t.kind === "lasthit" && wasPreHit(bot.GetPlayerID(), t.creep) ? true : undefined],
                ["pre", t.kind === "deny" ? IdleSwing.SpentOn(bot.GetPlayerID(), t.creep) : undefined],
                ["yd", yieldOf(bot.GetPlayerID())],
                ["cw", walkIn !== undefined ? true : undefined],
                ["cc", walkIn !== undefined ? math.floor(walkIn.price.cost * 1000) / 10 : undefined],
                ["cn", walkIn?.price.heroes],
                ["dh", walkIn !== undefined ? math.floor(((walkIn.hp - bot.GetHealth()) / maxHp) * 1000) / 10 : undefined],
                ["msg", res.message],
            ]);
        },
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
