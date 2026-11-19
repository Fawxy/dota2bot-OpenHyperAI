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
import * as PickTable from "bots/FunLib/humaniser/states/pick_table";
import * as PreHit from "bots/FunLib/humaniser/states/pre_hit";
import * as IdleSwing from "bots/FunLib/humaniser/states/idle_swing";
import * as Tasks from "bots/FunLib/humaniser/tasks";
import * as Contest from "bots/FunLib/humaniser/states/contest";
import * as SafeGather from "bots/FunLib/humaniser/safe_gather";
import type * as Safe from "bots/FunLib/humaniser/safe";

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
    return pos !== undefined && !PickTable.IsCore(pos) ? "support" : "core";
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
 * Ours.LaneSpot: this bot stands on our spot whatever States.Laning.Spot says: cores under Ours.CoreLastHit, and supports whose
 * lane hits are ours (Ours.SupportDeny; their attacks on heroes run in our attack mode, Ours.Trade, so the body's hold no longer
 * cancels them).
 */
export function OwnsSpot(bot: Unit): boolean {
    if (!Ours.On("LaneSpot")) return false;
    return CoreLastHit.Applies(bot) || OwnsSupportHits(bot);
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

/** The named inputs LaneSpot.Compute takes for this bot (the fixture cut logs them). */
export function SpotInputs(bot: Unit): LuaMultiReturn<[LaneSpot.Role, Unit | undefined, Vector | undefined]> {
    const pid = bot.GetPlayerID();
    return $multi(RoleOf(bot), fedCreep[pid], holdPoint[pid]);
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
 * no core will take (states/lane_claims). Stepped only by the lane table's `support_*` rows, so OHA's positioning and harass keep the
 * other frames.
 */
export function OwnsSupportHits(bot: Unit): boolean {
    return !OwnsLastHit(bot) && SupportDeny.Applies(bot);
}

/**
 * The column of the pick table this laner reads: its own position's, or position 1's for a pos 4-5 listed in
 * States.Laning.LastHit (OwnsLastHit), which takes a core's last hits and denies.
 */
export function ClaimPos(bot: Unit): PickTable.Pos {
    const pos = LaneConfig.PositionOf(bot);
    if (pos === undefined || pos < 1 || pos > 5) return 1;
    if (!PickTable.IsCore(pos) && OwnsLastHit(bot)) return 1;
    return pos as PickTable.Pos;
}

/** Per bot and game time, the safe read's answer for each creep asked (true: deadly) and for the hero's own place: the pick, the
 *  deny check, the support's hit row and the idle swing ask about the same creeps in one frame. */
interface SafeFrame {
    t: number;
    creeps: LuaTable<Lib.TaskCreep, boolean>;
    here?: boolean;
}
const safeFrames: Record<number, SafeFrame | undefined> = {};

function safeFrame(pid: number): SafeFrame {
    const now = DotaTime();
    let f = safeFrames[pid];
    if (f === undefined || f.t !== now) {
        f = { t: now, creeps: new LuaTable() };
        safeFrames[pid] = f;
    }
    return f;
}

function askDeadly(bot: Unit, place: Vector, held: boolean): boolean {
    const [ok, ans] = pcall(SafeGather.At, bot, place, { held });
    if (!ok) {
        Telemetry.Failed("PickSafe", ans);
        return false;
    }
    return (ans as Safe.Answer).level === "deadly";
}

/** Whether the safe read calls the place where `bot` would hit this creep deadly. A fault in the read allows the creep. */
function deadlyAt(bot: Unit, t: Lib.Verbs.LaneTarget): boolean {
    const f = safeFrame(bot.GetPlayerID());
    const known = f.creeps.get(t.creep);
    if (known !== undefined) return known;
    let deadly: boolean;
    if (t.walk <= 0) {
        // Every creep already in range is hit from where the hero stands: one ask answers them all.
        if (f.here === undefined) f.here = askDeadly(bot, bot.GetLocation(), true);
        deadly = f.here;
    } else deadly = askDeadly(bot, Contest.StandPoint(bot.GetLocation(), t.creep.GetLocation() as unknown as Vector, bot.GetAttackRange()), false);
    f.creeps.set(t.creep, deadly);
    return deadly;
}

function safeRefusedNow(pid: number, creep: Lib.TaskCreep): boolean {
    const f = safeFrames[pid];
    return f !== undefined && f.t === DotaTime() && f.creeps.get(creep) === true;
}

/** How many of the offered creeps the safe read refused this frame (the pick cut's `sd`). */
function safeDropped(pid: number, targets: Lib.Verbs.LaneTarget[]): number {
    const f = safeFrames[pid];
    if (f === undefined || f.t !== DotaTime()) return 0;
    let n = 0;
    for (const t of targets) if (f.creeps.get(t.creep) === true) n++;
    return n;
}

/**
 * The creeps this laner may take: its column of the pick table (LaneClaims.Mine, undefined for all of them) and, under
 * Ours.PickSafe, not those whose hit place is deadly. The safe read is asked only for creeps the claim lets through.
 */
function claimsFor(bot: Unit): ((this: void, t: Lib.Verbs.LaneTarget) => boolean) | undefined {
    const base = !OwnsLastHit(bot) && !OwnsSupportHits(bot) ? undefined : LaneClaims.Mine(bot, ClaimPos(bot), Settings().LastHitWithin);
    if (!Ours.On("PickSafe")) return base;
    return (t) => (base === undefined || base(t)) && !deadlyAt(bot, t);
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
        // A walk-in under way is priced as contestPick prices it (with the slack), so the pick does not drop or log it.
        const price = Contest.PriceFor(bot, t, Contest.Running(pid, t.creep) !== undefined);
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

type Mine = (this: void, t: Lib.Verbs.LaneTarget) => boolean;

/** What the pick's `mine` answered for each target it asked about, kept while the body's pick is cut (ev=cut kind=pick). */
const askedTargets: Lib.Verbs.LaneTarget[] = [];
const askedOk: boolean[] = [];
let askedCount = 0;
let askedInner: Mine | undefined;

function recordMine(this: void, t: Lib.Verbs.LaneTarget): boolean {
    const ok = (askedInner as Mine)(t);
    askedTargets[askedCount] = t;
    askedOk[askedCount] = ok;
    askedCount++;
    return ok;
}

function choose(bot: Unit, targets: Lib.Verbs.LaneTarget[], current?: Lib.Verbs.LaneTarget, pre?: Lib.Verbs.LaneTarget, cut = false): Lib.Verbs.LaneTarget | undefined {
    const pid = bot.GetPlayerID();
    const claims = claimsFor(bot);
    const far = farFor(bot);
    // A creep whose walk-in the price released is not picked again: from nearer, the plain reach rule would take it unpriced.
    let mine: Mine | undefined = far === undefined ? claims : (t) => !Contest.Refused(pid, t.creep) && (claims === undefined || claims(t));
    const cutting = cut && Telemetry.IsEnabled() && Telemetry.Get().Cut === true;
    if (cutting) {
        askedCount = 0;
        if (mine !== undefined) {
            askedInner = mine;
            mine = recordMine;
        }
    }
    const order = PickTable.Order(ClaimPos(bot));
    let idle: Lib.Verbs.LaneTarget | undefined;
    let idleAsked = false;
    const chosen = LanePick.Choose(
        targets,
        current,
        mine,
        pre,
        () => {
            const verbs = Tasks.Verbs();
            idleAsked = true;
            idle = verbs !== undefined ? IdleSwing.Find(bot, verbs, mine) : undefined;
            return idle;
        },
        far,
        order,
    );
    idlePicks[pid] = idle !== undefined && chosen === idle ? idle : undefined;
    // laneFarm asks on every scan, also with nothing offered: an empty scan that picks nothing is not a pick.
    if (cutting && (chosen !== undefined || targets.length > 0)) {
        const [ok, err] = pcall(cutPick, bot, targets, current, pre, chosen, far !== undefined, idleAsked, idle, order, safeDropped(pid, targets));
        if (!ok) Telemetry.Failed("Laning.CutPick", err);
    }
    return chosen;
}

const PICK_CUT_EVERY = 5;
const pickCuts: Record<number, { creep?: Lib.TaskCreep; kind?: string; ans?: string; sd?: boolean; at: number } | undefined> = {};

const r6 = (v: number): number => (v === math.huge ? -1 : math.floor(v * 1000000 + 0.5) / 1000000);

function offerIndex(targets: Lib.Verbs.LaneTarget[], creep: Lib.TaskCreep): number {
    for (let i = 0; i < targets.length; i++) if (targets[i].creep === creep) return i + 1;
    return -1;
}

function askedMine(t: Lib.Verbs.LaneTarget): boolean {
    for (let i = 0; i < askedCount; i++) if (askedTargets[i] === t) return askedOk[i];
    return true;
}

/** `ev=cut kind=pick`: the inputs of LanePick.Choose as the body's pick gave them, and its answer, when it changes and else every PICK_CUT_EVERY s. */
function cutPick(
    bot: Unit,
    targets: Lib.Verbs.LaneTarget[],
    current: Lib.Verbs.LaneTarget | undefined,
    pre: Lib.Verbs.LaneTarget | undefined,
    chosen: Lib.Verbs.LaneTarget | undefined,
    hasFar: boolean,
    idleAsked: boolean,
    idle: Lib.Verbs.LaneTarget | undefined,
    order: PickTable.PickKind[],
    dropped: number,
): void {
    const pid = bot.GetPlayerID();
    const now = DotaTime();
    const ak = chosen !== undefined ? chosen.kind : "none";
    // A pre-hit and an idle swing on one creep share the verb kind, so the answer's source is compared too.
    const src = chosen === undefined ? "none" : chosen === pre ? "pre" : chosen === idle ? "idle" : "offer";
    const st = (pickCuts[pid] = pickCuts[pid] ?? { at: 0 });
    const sdOn = dropped > 0;
    if (st.kind === ak && st.ans === src && st.creep === chosen?.creep && (st.sd ?? false) === sdOn && now >= st.at && now - st.at < PICK_CUT_EVERY) return;
    st.kind = ak;
    st.ans = src;
    st.sd = sdOn;
    st.creep = chosen?.creep;
    st.at = now;
    const tg: string[] = [];
    for (let i = 0; i < targets.length; i++) {
        const t = targets[i];
        tg.push([i + 1, t.kind, r6(t.eta), r6(t.due), r6(t.walk), r6(t.dies), t.ranged ? 1 : 0, askedMine(t) ? 1 : 0].join(","));
    }
    let far: string | undefined;
    if (hasFar) {
        const asked: string[] = [];
        for (const fp of farPrices[pid] ?? []) asked.push(`${offerIndex(targets, fp.creep)},${fp.price.ok ? 1 : 0}`);
        far = asked.length > 0 ? asked.join(";") : "-";
    }
    let idleText: string | undefined;
    if (idleAsked) {
        idleText =
            idle === undefined
                ? "0"
                : [offerIndex(targets, idle.creep), idle.kind, r6(idle.eta), r6(idle.due), r6(idle.walk), r6(idle.dies), idle.ranged ? 1 : 0].join(",");
    }
    let ans = "none";
    if (chosen !== undefined) {
        if (chosen === pre) ans = "pre";
        else if (chosen === idle) ans = "idle";
        else ans = tostring(targets.indexOf(chosen) + 1);
    }
    Telemetry.Event("cut", [
        ["pid", pid],
        ["kind", "pick"],
        ["pos", ClaimPos(bot)],
        ["ord", order.join(",")],
        ["tg", tg.join(";")],
        ["cur", current !== undefined ? offerIndex(targets, current.creep) : undefined],
        ["pre", pre !== undefined ? [offerIndex(targets, pre.creep), r6(pre.eta), r6(pre.walk), r6(pre.dies)].join(",") : undefined],
        ["far", far],
        ["idle", idleText],
        ["ans", ans],
        ["ak", ak],
        ["sd", sdOn ? dropped : undefined],
    ]);
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
    const plain = LanePick.Choose(targets, current, undefined, pre, undefined, undefined, PickTable.Order(ClaimPos(bot)));
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
 * the leash of the spot. the lane table's `support_hit` row reads it to step the body ahead of OHA's own laning steps.
 */
export function HitOffered(bot: Unit): boolean {
    if (!OwnsSupportHits(bot)) return false;
    const spot = Spot(bot);
    if (spot !== undefined && GetUnitToLocationDistance(bot, spot) > LEASH) return false;
    const verbs = Tasks.Verbs();
    if (verbs === undefined) return false;
    const t0 = Telemetry.DeepT0();
    const targets = verbs.laneTargets(bot as unknown as Lib.TaskUnit, { within: Settings().LastHitWithin });
    const t1 = Telemetry.DeepT0();
    if (t0 !== undefined) Telemetry.DeepAdd("laning.HitOffered:targets", t0);
    const offered = choose(bot, targets) !== undefined;
    if (t1 !== undefined) Telemetry.DeepAdd("laning.HitOffered:choose", t1);
    return offered;
}

/**
 * Slice trade-free round 2: a deny this laner's body would be offered now (laneTargets' denies within LastHitWithin, the reach
 * rule and the body's claims), for a bot whose lane hits are ours. Harass's third question reads it: a due deny outbids a
 * trade. A support's body takes a hit only within LEASH of its spot (HitOffered, the `support_hit` row), so beyond it no deny
 * is due (review of round 2). Reads facts only (no pick, no skill roll); once per bot per game time, as Gather and keepWhy
 * ask it several times a frame.
 */
const denyDueAt: Record<number, { t: number; due: boolean } | undefined> = {};
export function DenyDue(bot: Unit): boolean {
    const pid = bot.GetPlayerID();
    const now = DotaTime();
    const memo = denyDueAt[pid];
    if (memo !== undefined && memo.t === now) return memo.due;
    const due = denyDue(bot);
    denyDueAt[pid] = { t: now, due };
    return due;
}

function denyDue(bot: Unit): boolean {
    const core = OwnsLastHit(bot);
    if (!core && !OwnsSupportHits(bot)) return false;
    if (!core) {
        const spot = Spot(bot);
        if (spot !== undefined && GetUnitToLocationDistance(bot, spot) > LEASH) return false;
    }
    const verbs = Tasks.Verbs();
    if (verbs === undefined) return false;
    const claims = claimsFor(bot);
    for (const t of verbs.laneTargets(bot as unknown as Lib.TaskUnit, { within: Settings().LastHitWithin, lastHit: false })) {
        if (t.kind === "deny" && LanePick.Reachable(t) && (claims === undefined || claims(t))) return true;
    }
    return false;
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
            const chosen = contestPick(bot, choose(bot, targets, current, pre, true), current);
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
        // offers for a scan as its attackers change (its due time jumps); that would throw most long walks away early.
        dropLost: (cur) => OwnsSupportHits(bot) || Contest.Refused(bot.GetPlayerID(), cur.creep) || safeRefusedNow(bot.GetPlayerID(), cur.creep),
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
        score: () => (Phase.LaningHeld(bot) ? 0.5 : undefined),
        body: (ctx) => body(bot, ctx),
    };
}
