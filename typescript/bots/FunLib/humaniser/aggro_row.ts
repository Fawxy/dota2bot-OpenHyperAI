/**
 * The draw (protective aggro; no-creep-unpaid proposal s6b, doctrine D15), a decider row below the creep row, switch Ours.LaneAggro.
 * A core (`aggro_offer` MayOffer: the trip table's `aggro` row) beside our ranged creep while their lane creeps fight ours gives one
 * attack order on the nearest enemy hero our team sees and walks back to the hand-over spot, 250 behind our ranged creep away from the
 * clash, so the creeps it drew take that creep when the draw lets go. The deny is stock's or the deny row's: nothing here locks the creep.
 *
 * The go rule is the offer read's checks (`AggroOffer.Checks`), asked on a fresh read (`ReadNow`) at the go and again after the walk-in.
 * Phases and holds (ARCHITECTURE rules 8 to 10):
 * 1. `walk`, soft: to the draw spot (at most `MaxWalk` of walk, the read's own bound). Valve's attack, item, evasive, defend-ally and
 *    retreat may take the hero; the runner then ends the task `preempted` and a later round asks the go rule afresh. Before the order the
 *    phase looks at whether an action of the hero's is under way and does not order over it (rule 9).
 * 2. The order, the commit point: `Action_AttackUnit(target, once)`, then the hold is hard (`hs=hard` from the next round, `phase=order`
 *    on the job line). No swing of its own and no release order: a release turns the nearest chaser back onto the hero (measured).
 * 3. `back`, hard: a straight walk to the hand-over spot, once the attack is the hero's current action (at most `OrderCap`) and
 *    `OrderGap` after the order. A creep is drawn when it names the hero as its attack target or closes on it (`closed`: a chasing creep
 *    names it only once it swings). `missed nodraw` when none is drawn by `Switch` (creeps switch 0.4 to 0.8 s after the order); `ok`
 *    once the draw's measured let-go time for the kinds drawn has passed (`letGo`) and no drawn creep names the hero; `timeout` at
 *    `Backstop` (a logged backstop). The hero is then the next row's: stock's laning, the creep row, the deny row.
 *
 * The hand-over: a drawn creep that comes due mid-walk is the creep row's, which sits above; its begin replaces this task (the runner's
 * `cancelled replaced`, `cut=replaced` on the end line). The attempt lives in this row's memo, not its task: while the memo is open (an
 * order went and the task was replaced or preempted), the order is under `Backstop` old, a creep was drawn, and the draw has not let go
 * (`letGo`, or a creep still names the hero), `wants` offers the walk back again (`phase=resume`, the same `aid`) unless the danger
 * read at the hero's place is deadly.
 *
 * Lines: the offer read's `ev=choice kind=aggro src=own` (aggro_offer.ts: `go` 1 with the `aid` on the opportunity the row started on);
 * `ev=job job=aggro` start, order, resume and end.
 */
import type * as Lib from "bots/FunLib/engine/tasks";
import { BotMode, Unit } from "bots/ts_libs/dota";
import * as AggroOffer from "bots/FunLib/humaniser/aggro_offer";
import * as Decider from "bots/FunLib/humaniser/decider";
import type { Reads } from "bots/FunLib/humaniser/reads";
import * as Drill from "bots/FunLib/humaniser/drill";
import * as HDebug from "bots/FunLib/humaniser/debug";
import * as LaneConfig from "bots/FunLib/humaniser/lane_config";
import * as LaneRead from "bots/FunLib/humaniser/lane_read";
import * as SafeGather from "bots/FunLib/humaniser/safe_gather";
import { ForOurs as Tasks } from "bots/FunLib/humaniser/tasks";
import * as Telemetry from "bots/FunLib/humaniser/telemetry";

export const SETTINGS = {
    /** Seconds from the order to the walk back's first move: the probe walked off 0.1 s after and drew as with none (8 of 8). */
    OrderGap: 0.1,
    /** The most seconds the walk back waits for the attack to be the hero's current action (judgement: two or three bot thinks at 8x). */
    OrderCap: 0.3,
    /** Seconds after the order before "no drawn creep on the hero" ends the draw: they switch 0.4 to 0.8 s after it (measured, about 70). */
    Switch: 1.0,
    /** Seconds from the order at which the draw lets go: melee about 2.3, ranged about 2.85 (measured, engine-physics "The draw"). */
    LetGoMelee: 2.3,
    LetGoRanged: 2.85,
    /** The logged backstop (s from the order): the draw lets go at about 2.3 s (melee) and 2.85 (ranged), measured; s6b's 3.5. */
    Backstop: 3.5,
    /** The walk-in's tolerance (world units) and its cap past the read's walk (s; judgement). */
    Tolerance: 50,
    WalkSlack: 0.5,
    /** Seconds the row yields after an attempt ends before a new one may start (as the rune detour's Rest: the decider's FRESH). */
    Rest: 0.5,
    /** Diagnosis: a drawn creep that closed on the hero by this much, or came within Touch of it, chased it (judgement: a creep's swing range is about 100 plus hulls). */
    Closed: 150,
    Touch: 200,
};

/** The task's host: the decider's (farm). */
const HOST = BotMode.Farm;

declare const BOT_ACTION_TYPE_ATTACK: number;

/** The modes a draw may start from: a hero laning, farming or idle (judgement: any other is a higher rule's, as the rune detour's). */
const FROM: Record<number, boolean> = { [BotMode.None]: true, [BotMode.Laning]: true, [BotMode.Farm]: true };

interface Attempt {
    aid: number;
    t0: number;
    cid: number;
    ranged: Unit;
    target: Unit;
    drawn: Unit[];
    hand: AggroOffer.Vec;
    phase: "walk" | "back";
    orderAt?: number;
    /** The most drawn creeps on the hero at one step, and when none were on it any more after one had been (s from the order). */
    peak: number;
    letAt?: number;
    resumes: number;
    hp0: number;
    /** Diagnosis (round 0's nodraw): the hero's attack target read as the order's target at a step after it; each drawn creep's distance to the hero at the order and its least since. */
    heroOn?: boolean;
    /** Seconds from the order to the first step where the hero's current action was the attack; undefined until then. */
    took?: number;
    /** The draw's let-go (s from the order) for the kinds drawn, read at the order. */
    letGoAt?: number;
    d0?: number[];
    dmin?: number[];
}

/** pid -> the attempt whose task runs. */
const running: Record<number, Attempt | undefined> = {};
/** pid -> the last attempt while it can resume (an order went, the task was replaced or preempted). */
const memo: Record<number, Attempt | undefined> = {};
const endedAt: Record<number, number | undefined> = {};
/** pid -> what `wants` decided this round, for `begin`: a fresh start's read, or the attempt to resume. */
const pending: Record<number, { snap?: AggroOffer.Snap; resume?: Attempt } | undefined> = {};

export function ResetCache(): void {
    for (const t of [running, memo, endedAt, pending] as Record<number, unknown>[]) for (const [k] of pairs(t)) t[k as number] = undefined;
}

export function On(bot: Unit): boolean {
    return AggroOffer.RowOn() && AggroOffer.MayOffer(bot) && !Drill.Held(bot) && LaneConfig.InLaningPhase();
}

function dist(a: AggroOffer.Vec, b: AggroOffer.Vec): number {
    return math.sqrt((a.x - b.x) * (a.x - b.x) + (a.y - b.y) * (a.y - b.y));
}

function r1(x: number): number {
    return math.floor(x * 10 + 0.5) / 10;
}

/** Drawn creeps alive with the hero as their attack target, and of them those on our ranged creep (the hand-over's count). */
function onHero(bot: Unit, a: Attempt): number {
    let n = 0;
    for (const c of a.drawn) if (!c.IsNull() && c.IsAlive() && c.GetAttackTarget() === bot) n++;
    return n;
}

function onRanged(a: Attempt): number {
    if (a.ranged.IsNull() || !a.ranged.IsAlive()) return 0;
    let n = 0;
    for (const c of a.drawn) if (!c.IsNull() && c.IsAlive() && c.GetAttackTarget() === a.ranged) n++;
    return n;
}

function jobLine(bot: Unit, a: Attempt, phase: string, why: string, extra: Telemetry.Fields<"job"> = []): void {
    const fields: Telemetry.Fields<"job"> = [
        ["pid", bot.GetPlayerID()],
        ["job", "aggro"],
        ["aid", a.aid],
        ["phase", phase],
        ["why", why],
        ["host", HOST],
        ["cid", a.cid],
    ];
    for (const f of extra) fields.push(f);
    Telemetry.Event("job", fields);
}

/** Whether an open attempt may take the hero back for its walk (s6b's resume). */
function resumable(bot: Unit, a: Attempt, now: number): boolean {
    if (a.orderAt === undefined || now - a.orderAt >= SETTINGS.Backstop || !bot.IsAlive()) return false;
    // Still drawn: a creep chased or named the hero, and the draw has not let go by its measured time, or a creep still names the hero.
    if (!(a.peak > 0 || closed(a) > 0)) return false;
    if (now - a.orderAt >= letGo(a) && onHero(bot, a) === 0) return false;
    return SafeGather.At(bot, bot.GetLocation(), { remember: false }).level !== "deadly";
}

/** One step's diagnosis reads: whether the hero's attack target is the order's, and each drawn creep's distance to the hero. */
function watch(bot: Unit, a: Attempt): void {
    const tg = bot.GetAttackTarget();
    if (tg !== null && tg !== undefined && tg === a.target) a.heroOn = true;
    const me = bot.GetLocation();
    a.d0 ??= [];
    a.dmin ??= [];
    for (let i = 0; i < a.drawn.length; i++) {
        const c = a.drawn[i];
        if (c.IsNull() || !c.IsAlive()) continue;
        const at = c.GetLocation();
        if (at === null || at === undefined) continue;
        const d = dist(me, at);
        if (a.d0[i] === undefined) a.d0[i] = d;
        if (a.dmin[i] === undefined || d < a.dmin[i]) a.dmin[i] = d;
    }
}

/** Drawn creeps that closed on the hero by `Closed` or more since the order (they chased it, whatever their attack target read). */
function closed(a: Attempt): number {
    let n = 0;
    if (a.d0 === undefined || a.dmin === undefined) return 0;
    for (let i = 0; i < a.drawn.length; i++) {
        const d0 = a.d0[i];
        const dm = a.dmin[i];
        if (d0 !== undefined && dm !== undefined && (d0 - dm >= SETTINGS.Closed || dm <= SETTINGS.Touch)) n++;
    }
    return n;
}

/** Seconds from the order at which the draw lets go of the kinds drawn: ranged when one is among them, else melee (measured). Read at the order, while every drawn creep is alive. */
function letGoOf(drawn: Unit[]): number {
    for (const c of drawn) if (!c.IsNull() && c.IsAlive() && LaneRead.CreepKind(c.GetUnitName()) === "r") return SETTINGS.LetGoRanged;
    return SETTINGS.LetGoMelee;
}

function letGo(a: Attempt): number {
    return a.letGoAt ?? SETTINGS.LetGoMelee;
}

/** The walk back to the hand-over spot until the draw lets go; the attempt's phase is `back` and its order has gone. */
function* back(ctx: Lib.Ctx, bot: Unit, a: Attempt): Lib.TaskBody {
    const orderAt = a.orderAt!;
    // A bot-API order goes through the hero's action queue: nothing new is ordered until the attack is the hero's current action
    // (round 0: walking off 0.1 s after drew nothing in 65 of 102; the probe's 0.1 s was a server order, applied at once), or OrderCap.
    while (a.took === undefined && ctx.now() < orderAt + SETTINGS.OrderCap) {
        watch(bot, a);
        if ((bot as unknown as { GetCurrentActionType(): number }).GetCurrentActionType() === BOT_ACTION_TYPE_ATTACK) a.took = ctx.now() - orderAt;
        yield;
    }
    while (ctx.now() < orderAt + SETTINGS.OrderGap) {
        watch(bot, a);
        yield;
    }
    while (true) {
        if (!bot.IsAlive()) return ctx.fail("dead");
        watch(bot, a);
        const t = ctx.now() - orderAt;
        const n = onHero(bot, a);
        if (n > a.peak) a.peak = n;
        // A chasing creep names the hero as its attack target only once it swings (rig r2: 25 of 52 draws that pulled creeps ended at
        // 1.0 s with none named), so the draw's let-go is read from its measured time for the kinds drawn, and then no creep on the hero.
        const drew = a.peak > 0 || closed(a) > 0;
        if (t >= SETTINGS.Switch && !drew) {
            a.letAt = t;
            return ctx.fail("missed", "nodraw");
        }
        if (drew && t >= letGo(a) && n === 0) {
            a.letAt = t;
            return ctx.ok();
        }
        if (t >= SETTINGS.Backstop) return ctx.fail("timeout");
        const me = bot.GetLocation();
        if (dist(me, a.hand) > SETTINGS.Tolerance) bot.Action_MoveToLocation(Vector(a.hand.x, a.hand.y, me.z));
        yield;
    }
}

/** A fresh attempt: the soft walk-in, the go rule again, the order (the commit point), then the walk back. */
function* draw(ctx: Lib.Ctx, bot: Unit, a: Attempt, spot: AggroOffer.Vec, walk: number): Lib.TaskBody {
    if (dist(bot.GetLocation(), spot) > SETTINGS.Tolerance) {
        const me = bot.GetLocation();
        const r = yield* ctx.walkTo(Vector(spot.x, spot.y, me.z), { tolerance: SETTINGS.Tolerance, timeout: walk + SETTINGS.WalkSlack });
        if (!r.success) return r;
    }
    const s = AggroOffer.ReadNow(bot);
    if (s === undefined) return ctx.fail("cancelled", "noclash");
    if (s.fails.length > 0) return ctx.fail("cancelled", s.fails[0]);
    if (s.target === undefined) return ctx.fail("cancelled", "unseen");
    // Rule 9: an action of the hero's already under way is not ordered over.
    if (bot.NumQueuedActions() > 0 || bot.IsChanneling() || bot.IsUsingAbility() || bot.IsCastingAbility()) return ctx.fail("cancelled", "acting");
    a.target = s.target;
    a.drawn = s.drawnUnits;
    a.hand = s.hand;
    a.letGoAt = letGoOf(s.drawnUnits);
    // Diagnosis (round 0's nodraw): the target's distance, whether it took this hero's damage within the cooldown, the nearest drawn creep.
    const me = bot.GetLocation();
    let nd = math.huge;
    for (const c of s.drawnUnits) {
        const at = c.GetLocation();
        if (at !== null && at !== undefined && dist(me, at) < nd) nd = dist(me, at);
    }
    const diag: Telemetry.Fields<"job"> = [
        ["td", math.floor(dist(me, s.target.GetLocation()))],
        ["rh", s.target.WasRecentlyDamagedByHero(bot, AggroOffer.SETTINGS.Cooldown) ? 1 : 0],
        ["nd", nd < math.huge ? math.floor(nd) : undefined],
    ];
    bot.Action_AttackUnit(s.target, true);
    a.orderAt = ctx.now();
    a.phase = "back";
    AggroOffer.NoteHeroHit(bot);
    jobLine(bot, a, "order", "go", [
        ["ot", r1(a.orderAt - a.t0)],
        ["an", s.drawnUnits.length],
        ...diag,
    ]);
    return yield* back(ctx, bot, a);
}

function finish(bot: Unit, res: Lib.Result): void {
    const pid = bot.GetPlayerID();
    const a = running[pid];
    running[pid] = undefined;
    endedAt[pid] = DotaTime();
    if (a === undefined) return;
    const replaced = res.reason === "cancelled" && res.message === "replaced";
    const cut = replaced ? "replaced" : res.reason === "preempted" ? (Decider.LetGo(bot) ? "retreat" : HDebug.ModeName(bot.GetActiveMode())) : undefined;
    // Open for the resume only when another row or mode took the hero after the order.
    memo[pid] = a.orderAt !== undefined && (replaced || res.reason === "preempted") ? a : undefined;
    jobLine(bot, a, "end", res.success ? "ok" : res.reason, [
        ["msg", res.message],
        ["cut", cut],
        ["ot", a.orderAt !== undefined ? r1(a.orderAt - a.t0) : -1],
        ["lt", a.letAt !== undefined ? r1(a.letAt) : a.orderAt !== undefined ? r1(DotaTime() - a.orderAt) : undefined],
        ["an", a.drawn.length],
        ["ah", a.peak],
        ["ar", onRanged(a)],
        ["rs", a.resumes],
        ["ha", a.orderAt !== undefined ? (a.heroOn === true ? 1 : 0) : undefined],
        ["ac", a.orderAt !== undefined ? closed(a) : undefined],
        ["ow", a.orderAt !== undefined ? (a.took !== undefined ? math.floor(a.took * 100 + 0.5) / 100 : -1) : undefined],
        ["hp0", a.hp0],
        ["hp1", math.floor(bot.GetHealth())],
    ]);
}

/** The row's `wants`: an offer while an attempt runs, when an open one should resume, or when a fresh read passes the go rule now. */
function rowWants(bot: Unit, _reads: Reads): Decider.Offer | undefined {
    const pid = bot.GetPlayerID();
    pending[pid] = undefined;
    if (!On(bot)) {
        memo[pid] = undefined;
        return undefined;
    }
    Tasks.Tick(bot);
    const a = running[pid];
    if (a !== undefined) return { tgt: `creep:${a.cid}` };
    if (Tasks.Jobs() === undefined) return undefined;
    const now = DotaTime();
    const m = memo[pid];
    if (m !== undefined) {
        if (resumable(bot, m, now)) {
            pending[pid] = { resume: m };
            return { tgt: `creep:${m.cid}`, by: m.orderAt! + SETTINGS.Backstop };
        }
        memo[pid] = undefined;
    }
    const ended = endedAt[pid];
    if (ended !== undefined && now - ended < SETTINGS.Rest) return undefined;
    // Another task (a job no row started) is not this row's to replace; a row above would have answered first.
    if (Tasks.Running(bot) !== undefined || FROM[bot.GetActiveMode()] !== true) return undefined;
    const s = AggroOffer.ReadNow(bot);
    if (s === undefined || s.fails.length > 0 || s.target === undefined) return undefined;
    pending[pid] = { snap: s };
    return { tgt: `creep:${Telemetry.CreepId(s.ranged)}` };
}

/** The row's `begin`: starts the attempt `rowWants` decided (a fresh draw, or the walk back of an open one). */
function rowBegin(bot: Unit): boolean {
    const pid = bot.GetPlayerID();
    const pd = pending[pid];
    pending[pid] = undefined;
    if (pd === undefined) return false;
    const opts = { name: "aggro", host: HOST, preemptAfter: 1, stallAfter: 4, onEnd: (r: Lib.Result) => finish(bot, r) };
    if (pd.resume !== undefined) {
        const m = pd.resume;
        const ok = Tasks.Start(bot, opts, (ctx: Lib.Ctx) => back(ctx, bot, m));
        if (!ok) return false;
        memo[pid] = undefined;
        m.resumes++;
        running[pid] = m;
        jobLine(bot, m, "resume", "drawn", [["ah", onHero(bot, m)]]);
        return true;
    }
    const s = pd.snap!;
    const walk = s.f.walk;
    const a: Attempt = {
        aid: 0,
        t0: DotaTime(),
        cid: Telemetry.CreepId(s.ranged),
        ranged: s.ranged,
        target: s.target!,
        drawn: s.drawnUnits,
        hand: s.hand,
        phase: "walk",
        peak: 0,
        resumes: 0,
        hp0: math.floor(bot.GetHealth()),
    };
    const spot = s.spot;
    const ok = Tasks.Start(bot, opts, (ctx: Lib.Ctx) => draw(ctx, bot, a, spot, walk));
    if (!ok) return false;
    a.aid = Telemetry.NextAid(pid);
    memo[pid] = undefined;
    running[pid] = a;
    AggroOffer.NoteGo(bot, s.ranged, a.aid);
    jobLine(bot, a, "start", "go", [
        ["tgt", `creep:${a.cid}`],
        ["gw", r1(walk)],
        ["an", s.drawn],
        ["k", s.f.k],
    ]);
    return true;
}

/** The row's verb: one frame of the attempt; true once it has ended. */
function rowStep(bot: Unit): boolean {
    Tasks.Step(bot, HOST);
    return running[bot.GetPlayerID()] === undefined;
}

/** Soft while walking in; hard from the order (the commit point). */
function rowSoft(bot: Unit): boolean {
    return running[bot.GetPlayerID()]?.phase === "walk";
}

/** The decider's row (registered in index.ts, below the creep row, so the decider imports no row). */
export const ROW: Decider.Row = { name: "aggro", wants: rowWants, begin: rowBegin, step: rowStep, soft: rowSoft };
