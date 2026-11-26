/**
 * The stay at the lane's camp (doctrine D17, the pull's cash-in; slice oha-camp-stay), switch Ours.CampStay, a row of the decider
 * below the creep row. While our lane wave fights the neutrals at the hero's lane's pull camp (`CampRead.FightOf` of
 * `CampRead.SpawnerFor`), the hero stands behind our creeps, so the neutrals' nearest target is a creep, and takes a neutral's last
 * hit when one our creeps are on comes due by the engine's own last-hit timing (`ctx.lastHit`), one attempt at a time. It gives no
 * other hit. Any hero of the lane has the row; no position is checked.
 *
 * Hold: soft while standing, walking to the spot or walking out (`soft` asks `hardNow`); hard from a last-hit attempt's go to its end
 * (`attempt` is the one place that switches it). A change of hold takes effect at the decider's next round.
 *
 * Go rule (rule 5): worth starting (both neutrals and our creeps at the camp and fighting, HP over the bar, the hero beside the camp:
 * its walk to the stand spot at most Beside) and still possible (that walk shorter than our creeps' life at the neutrals' damage now). Held back by `busy` (attack or retreat has the
 * hero), `row` (another task runs), `acting`, `aggro` (a neutral is on the hero), `danger` (the shared read at the stand spot is deadly), or a bar this fight set.
 *
 * Ends, each a read and a named reason on the end line: `creeps` (none of ours left at the camp), `cleared` (no neutral left), `hit`
 * (a neutral attacks the hero: it walks out of the neutrals' reach towards its lane first), `hp`, `danger`, `timeout` (the backstop).
 * After `hit`, `hp` or `timeout` the row does not want that fight again.
 *
 * Opportunity: one per hero and fight, from the first read with both our creeps and neutrals at the camp to the first without. One
 * `ev=choice kind=stay` line each: at the first begin (`go=1`, its aid), else as it closes (`go=0`, the last reason). Switched off, the
 * same read is the shadow (`src=shadow go=0 why=off`). Each begin is one stay: `ev=job job=stay` start and end with a new aid (as
 * rune_detour's later walks of one pass), and each neutral last-hit attempt one `ev=stay_try`.
 */
import type * as Lib from "bots/FunLib/engine/tasks";
import { BotMode, DamageType, Unit, Vector } from "bots/ts_libs/dota";
import * as CampRead from "bots/FunLib/humaniser/camp_read";
import type * as Camps from "bots/FunLib/humaniser/camps";
import * as Decider from "bots/FunLib/humaniser/decider";
import * as Drill from "bots/FunLib/humaniser/drill";
import * as HDebug from "bots/FunLib/humaniser/debug";
import * as Ours from "bots/FunLib/humaniser/ours";
import type { Reads } from "bots/FunLib/humaniser/reads";
import * as SafeGather from "bots/FunLib/humaniser/safe_gather";
import { ForOurs as Tasks } from "bots/FunLib/humaniser/tasks";
import * as Telemetry from "bots/FunLib/humaniser/telemetry";

export const SETTINGS = {
    /**
     * HP share under which the hero does not start a stay and a stay ends: the pull's bail reserve (PullJob SETTINGS.BailReserve,
     * 0.25). A copy: a row imports no other row, and moving the value into the camp read would change the pull's file.
     */
    HpBar: 0.25,
    /**
     * judgement (the old stay's STAY_LH_WITHIN): a neutral our creeps are on is due when its forecast HP, this many seconds past the
     * moment the hero's hit could land (walk into reach plus the engine's own hit time), is within one hit. Longer starts the verb
     * on more neutrals in time, but holds the hero hard waiting on a neutral that may die to our creeps first.
     */
    Within: 1,
    /** judgement (the old stay's STAY_LH_SLACK): the attempt waits this long past that horizon before the verb times out. */
    WaitSlack: 0.5,
    /**
     * judgement (the old stay's BEHIND_*): how far behind our creeps' centre the hero stands, its attack range less BehindShort,
     * within BehindMin to BehindMax: our creeps stay within its reach and a neutral reaches it only past them. Nearer cuts the walk
     * to a due neutral; farther keeps the hero out of a neutral's acquisition when the creeps' line shifts.
     */
    BehindShort: 250,
    BehindMin: 150,
    BehindMax: 400,
    /** judgement (the old stay's STAY_ARRIVE): within this of the stand spot the hero gives no move. */
    Arrive: 60,
    /**
     * judgement: a last-hit attempt starts only while the hero is within this of the stand spot, so the stay stands first and a
     * neutral's walk-in is from behind our creeps. Rig drill oha-camp-stay 1: begun 11 s away, the walk term made a neutral due at
     * once and the hero walked hard at it through the camp (an attempt ended 2,126 short). Larger starts more attempts on the way
     * in; smaller waits on the spot's drift as our creeps move.
     */
    AtSpot: 200,
    /** judgement (the old stay's STAY_REORDER): a move to the spot is repeated at most this often while walking. */
    Reorder: 0.5,
    /**
     * judgement: the stay is a hero's already beside the camp (the definition: "a hero of ours is beside it"): wanted only while the
     * straight walk to the stand spot is at most this (s). From the go lines of rigs drill oha-camp-stay 1 and 2 (pull-stack-row,
     * lineup B): the pullers' walks 1.2 to 3.3 s (1.2, 2.0, 2.4, 2.4, 2.7, 2.8, 1.8, 3.3); the cores' walks from their lane 5.4 to
     * 11.4 s (5.4, 6.8, 7.7, 7.9, 9.1, 9.7, 10.2, 11.4), and 1.2 and 1.7 s only for a core already at the camp from its own earlier
     * stay there. Higher lets a hero leave its lane for the camp (the opposite rule's case; a core near also has the engine's filter
     * refuse the support's attempts, `etiquette`); lower drops a puller that shed or bailed a little farther out.
     */
    Beside: 4,
    /** The backstop from a fight's first stay (s): the old stay's StayMax (the old pull farm's MaxFarm; a camp's clear was 7 to 26 s). */
    Max: 35,
    /** judgement: the walk out ends this far past every neutral's reach of the hero (a neutral turning back covers ground). */
    OutMargin: 150,
    /** judgement: the walk out's backstop (s); it then ends `hit` wherever it stands. */
    OutFor: 4,
    /** judgement: the danger read inside a stay is asked at most this often (s); a deadly answer comes up to that late. */
    DangerEvery: 0.5,
};

/** The task's host: the decider's (farm). */
const HOST = BotMode.Farm;

/** One fight at the camp, as one hero sees it (the opportunity). */
interface Opp {
    /** When the hero's first read saw it (the line's `slot`). */
    slot: number;
    camp: number;
    want: boolean;
    why?: string;
    logged?: boolean;
    /** The most of our creeps and neutrals seen at the camp in it, and the walk and our creeps' life at the latest read. */
    nc: number;
    nn: number;
    walk: number;
    life: number;
    /** When its first stay began: the backstop counts from there. */
    first?: number;
    /** A stay of this fight ended `hit`, `hp` or `timeout`: no new one. */
    barred?: string;
}

/** One read of the fight for one hero. */
interface Read {
    sp: Camps.Spawner;
    f: CampRead.CampFight;
    stand: Vector;
    walk: number;
}

interface Stay {
    aid: number;
    sp: Camps.Spawner;
    slot: number;
    t0: number;
    hp0: number;
    deadline: number;
    tried: number;
    landed: number;
    /** From an attempt's go to its end (`attempt`). */
    hard: boolean;
    /** Neutrals the verb could not run on (`etiquette`, `unsupported`): left to our creeps. */
    skip: Unit[];
    dangerAt: number;
}

const opps: Record<number, Opp | undefined> = {};
const running: Record<number, Stay | undefined> = {};
/** pid -> the read `wants` decided to start on this round, for `begin`. */
const pending: Record<number, Read | undefined> = {};

export function ResetCache(): void {
    for (const t of [opps, running, pending] as Record<number, unknown>[]) for (const [k] of pairs(t)) t[k as number] = undefined;
}

export function On(): boolean {
    return Ours.On("CampStay");
}

function dist(a: Vector, b: Vector): number {
    return math.sqrt((a.x - b.x) * (a.x - b.x) + (a.y - b.y) * (a.y - b.y));
}

function centre(list: Unit[]): Vector {
    let x = 0;
    let y = 0;
    let z = 0;
    for (const u of list) {
        const l = u.GetLocation();
        x += l.x;
        y += l.y;
        z += l.z ?? 0;
    }
    return Vector(x / list.length, y / list.length, z / list.length);
}

/** The stand's distance behind our creeps' centre for this hero (SETTINGS BehindShort, BehindMin, BehindMax). */
export function BehindBack(bot: Unit): number {
    return math.min(SETTINGS.BehindMax, math.max(SETTINGS.BehindMin, bot.GetAttackRange() - SETTINGS.BehindShort));
}

/**
 * The stand spot (the old stay's behindPoint): past our creeps' centre on the far side from the neutrals' centre, `BehindBack` from
 * it. Undefined with none of ours; with the two centres on one point, away through where the hero stands.
 */
export function StandSpot(bot: Unit, ours: Unit[], neutrals: Unit[], origin: Vector): Vector | undefined {
    if (ours.length === 0) return undefined;
    const oc = centre(ours);
    const nc = neutrals.length > 0 ? centre(neutrals) : origin;
    let dx = oc.x - nc.x;
    let dy = oc.y - nc.y;
    let l = math.sqrt(dx * dx + dy * dy);
    if (l < 1) {
        const at = bot.GetLocation();
        dx = at.x - oc.x;
        dy = at.y - oc.y;
        l = math.sqrt(dx * dx + dy * dy);
        if (l < 1) return oc;
    }
    const d = BehindBack(bot);
    return Vector(oc.x + (dx / l) * d, oc.y + (dy / l) * d, oc.z);
}

function hpShare(bot: Unit): number {
    return bot.GetHealth() / math.max(1, bot.GetMaxHealth());
}

/** OHA's own action holds the hero (the pull's and the creep row's check: a queued order, a cast or channel). */
function acting(bot: Unit): boolean {
    return bot.NumQueuedActions() > 0 || bot.IsChanneling() || bot.IsUsingAbility() || bot.IsCastingAbility();
}

function onHero(bot: Unit, f: CampRead.CampFight): boolean {
    for (const n of f.neutrals) if (n.GetAttackTarget() === bot) return true;
    return false;
}

/**
 * The fight read for `bot`: opens, updates or closes its opportunity. Returns the read while the opportunity is open, else
 * undefined. A closing opportunity whose line has not gone out writes it with `src`.
 */
function observe(bot: Unit, read: Reads["camp"], src: string): Read | undefined {
    const pid = bot.GetPlayerID();
    const sp = read.SpawnerFor(bot);
    const f = sp !== undefined && bot.IsAlive() ? read.FightOf(sp) : undefined;
    const open = sp !== undefined && f !== undefined && f.ours.length > 0 && f.neutrals.length > 0;
    let p = opps[pid];
    if (p !== undefined && (!open || p.camp !== sp!.idx)) {
        if (p.logged !== true) choiceLine(bot, p, false, src === "shadow" ? "off" : p.why ?? "idle", src);
        opps[pid] = undefined;
        p = undefined;
    }
    if (!open) return undefined;
    const stand = StandSpot(bot, f!.ours, f!.neutrals, sp!.location)!;
    const walk = dist(bot.GetLocation(), stand) / math.max(100, bot.GetCurrentMovementSpeed());
    if (p === undefined) {
        p = { slot: DotaTime(), camp: sp!.idx, want: false, nc: 0, nn: 0, walk, life: f!.life };
        opps[pid] = p;
    }
    p.nc = math.max(p.nc, f!.ours.length);
    p.nn = math.max(p.nn, f!.neutrals.length);
    p.walk = walk;
    p.life = f!.life;
    return { sp: sp!, f: f!, stand, walk };
}

/** Worth starting and still possible (rule 5), the same in both arms: undefined when wanted, else why not. */
function worth(bot: Unit, r: Read): string | undefined {
    if (!r.f.engaged) return "idle";
    if (hpShare(bot) < SETTINGS.HpBar) return "hp";
    if (r.walk > SETTINGS.Beside) return "away";
    if (r.walk >= r.f.life) return "far";
    return undefined;
}

/** What holds a wanted stay back now, else undefined. */
function block(bot: Unit, p: Opp, r: Read): string | undefined {
    if (p.barred !== undefined) return p.barred;
    // The fight's backstop has run out: a stay begun now ends at its first step.
    if (p.first !== undefined && DotaTime() >= p.first + SETTINGS.Max) return "timeout";
    const mode = bot.GetActiveMode();
    if (mode === BotMode.Attack || mode === BotMode.Retreat) return "busy";
    // Starting a task replaces the hero's running one (the runner's `replaced`); this row is last, so any running task is another's.
    if (Tasks.Running(bot) !== undefined) return "row";
    if (acting(bot)) return "acting";
    // A neutral still on the hero (the puller as its pull ends): a stay begun now would end `hit` at once and bar the fight; it
    // starts once the neutral has turned to our creeps.
    if (onHero(bot, r.f)) return "aggro";
    if (SafeGather.At(bot, r.stand, { who: "stay" }).level === "deadly") return "danger";
    return undefined;
}

function r1(x: number): number {
    return math.floor(x * 10 + 0.5) / 10;
}

function lifeField(life: number): number {
    return life === math.huge ? -1 : r1(life);
}

function choiceLine(bot: Unit, p: Opp, go: boolean, why: string | undefined, src: string, aid?: number): void {
    Telemetry.Event("choice", [
        ["pid", bot.GetPlayerID()],
        ["kind", "stay"],
        ["aid", aid],
        ["go", go ? 1 : 0],
        ["want", p.want ? 1 : 0],
        ["why", why],
        ["src", src],
        ["lane", bot.GetAssignedLane()],
        ["slot", r1(p.slot)],
        ["camp", p.camp],
        ["nc", p.nc],
        ["nn", p.nn],
        ["walk", r1(p.walk)],
        ["lf", lifeField(p.life)],
    ]);
}

function jobLine(bot: Unit, st: Stay, phase: string, why: string, cut?: string): void {
    const end = phase === "end";
    Telemetry.Event("job", [
        ["pid", bot.GetPlayerID()],
        ["job", "stay"],
        ["aid", st.aid],
        ["tgt", end ? undefined : `camp:${st.sp.idx}`],
        ["phase", phase],
        ["why", why],
        ["host", HOST],
        ["cut", cut],
        ["ss", end ? r1(DotaTime() - st.t0) : undefined],
        ["hp0", end ? st.hp0 : undefined],
        ["hp1", end ? math.floor(bot.IsAlive() ? bot.GetHealth() : 0) : undefined],
        ["lt", end ? st.tried : undefined],
        ["lk", end ? st.landed : undefined],
    ]);
}

/** A unit name less `npc_dota_neutral_` (the old stay's try line's `u`). */
function shortName(name: string): string {
    const pre = "npc_dota_neutral_";
    return string.sub(name, 1, pre.length) === pre ? string.sub(name, pre.length + 1) : name;
}

/** The old stay's try line (`ev=stay_try`), with the stay's aid and the neutral's cid. */
function tryLine(bot: Unit, st: Stay, n: Unit, r: Lib.Result, hp: number, hits: number, t0: number): void {
    Telemetry.Event("stay_try", [
        ["pid", bot.GetPlayerID()],
        ["aid", st.aid],
        ["slot", r1(st.slot)],
        ["k", "lasthit"],
        ["cid", Telemetry.CreepId(n)],
        ["u", shortName(n.GetUnitName())],
        ["ok", r.success ? 1 : 0],
        ["why", r.reason],
        ["m", r.message],
        ["hp", math.floor(hp + 0.5)],
        ["hh", r1(hits)],
        ["dt", r1(DotaTime() - t0)],
    ]);
}

/**
 * The reference arm's denominator: where the row is off, the same fight read and one line per opportunity (`src=shadow go=0
 * why=off`), `want` set when the stay was worth starting and possible at some read. Reads and logs; nothing is ordered.
 */
export function Shadow(bot: Unit): void {
    if (!Telemetry.IsEnabled() || On() || Drill.Held(bot)) return;
    const r = observe(bot, CampRead, "shadow");
    if (r === undefined) return;
    if (worth(bot, r) === undefined) opps[bot.GetPlayerID()]!.want = true;
}

function rowWants(bot: Unit, reads: Reads): Decider.Offer | undefined {
    const pid = bot.GetPlayerID();
    pending[pid] = undefined;
    if (!On() || Drill.Held(bot)) return undefined;
    Tasks.Tick(bot);
    const st = running[pid];
    if (st !== undefined) return { tgt: `camp:${st.sp.idx}` };
    if (Tasks.Jobs() === undefined) return undefined;
    const r = observe(bot, reads.camp, "own");
    if (r === undefined) return undefined;
    const p = opps[pid]!;
    const no = worth(bot, r);
    if (no !== undefined) {
        p.why = no;
        return undefined;
    }
    p.want = true;
    const why = block(bot, p, r);
    if (why !== undefined) {
        p.why = why;
        return undefined;
    }
    pending[pid] = r;
    return { tgt: `camp:${r.sp.idx}`, by: r.f.life === math.huge ? undefined : DotaTime() + r.f.life - r.walk };
}

/** The hold now: soft unless a last-hit attempt runs. */
function rowSoft(bot: Unit): boolean {
    return running[bot.GetPlayerID()]?.hard !== true;
}

/** The engine's last-hit timing for one neutral: the horizon and the forecast HP then, against one hit of the hero on it. */
interface Due {
    n: Unit;
    h: number;
    ahead: number;
    hit: number;
}

/**
 * The neutral our creeps are on that comes due soonest, if one does: its forecast HP (the engine's `hpForecast`) at the walk into
 * the engine's attack reach plus its own hit time plus Within is within one hit of the hero after armour (as the old stay read it;
 * the verb then times the swing on its own belief).
 */
function dueNeutral(bot: Unit, st: Stay, f: CampRead.CampFight): Due | undefined {
    const V = Tasks.Verbs()!;
    const tb = bot as unknown as Lib.TaskUnit;
    const speed = math.max(100, bot.GetCurrentMovementSpeed());
    let best: Due | undefined;
    for (const n of f.worked) {
        if (st.skip.includes(n)) continue;
        const c = n as unknown as Lib.TaskCreep;
        const walk = math.max(0, GetUnitToUnitDistance(bot, n) - V.attackReach(tb, c)) / speed;
        const h = walk + V.ownHitTime(tb, c) + SETTINGS.Within;
        const ahead = V.forecastHp(V.hpForecast(tb, c, h), h);
        const hit = math.max(1, n.GetActualIncomingDamage(bot.GetAttackDamage(), DamageType.Physical));
        if (ahead <= hit && (best === undefined || ahead < best.ahead)) best = { n, h, ahead, hit };
    }
    return best;
}

/** Why the stay ends now, else undefined. In order: `creeps`, `cleared`, `hit`, `hp`, `danger`, `timeout`. */
function endOf(bot: Unit, st: Stay, f: CampRead.CampFight, stand: Vector | undefined, now: number): string | undefined {
    if (f.ours.length === 0) return "creeps";
    if (f.neutrals.length === 0) return "cleared";
    if (onHero(bot, f)) return "hit";
    if (hpShare(bot) < SETTINGS.HpBar) return "hp";
    if (stand !== undefined && now - st.dangerAt >= SETTINGS.DangerEvery) {
        st.dangerAt = now;
        if (SafeGather.At(bot, stand, { who: "stay" }).level === "deadly") return "danger";
    }
    if (now >= st.deadline) return "timeout";
    return undefined;
}

/**
 * One neutral last-hit attempt, the one place the hold switches: hard from the go to the verb's end. Returns the verb's result.
 */
function* attempt(bot: Unit, st: Stay, d: Due, ctx: Lib.Ctx): Lib.TaskBody {
    const hp = d.n.GetHealth();
    const t0 = DotaTime();
    st.hard = true;
    ctx.label("lasthit");
    const res = yield* ctx.lastHit({ target: d.n as unknown as Lib.TaskCreep, maxWait: d.h + SETTINGS.WaitSlack });
    st.hard = false;
    st.tried++;
    if (res.success) st.landed++;
    if (!res.success && (res.reason === "etiquette" || res.reason === "unsupported")) st.skip.push(d.n);
    tryLine(bot, st, d.n, res, hp, hp / d.hit, t0);
    return res;
}

/** Away from the camp, towards the lane: the lane's nearest point to the hero. */
function lanePoint(bot: Unit): Vector {
    const lane = bot.GetAssignedLane();
    return GetLocationAlongLane(lane, GetAmountAlongLane(lane, bot.GetLocation()).amount);
}

/** Out of every neutral's reach of the hero (the engine's attackReach) by OutMargin, and none attacking it. */
function outOfReach(bot: Unit, f: CampRead.CampFight): boolean {
    const V = Tasks.Verbs()!;
    for (const n of f.neutrals) {
        if (n.GetAttackTarget() === bot) return false;
        if (GetUnitToUnitDistance(bot, n) <= V.attackReach(n as unknown as Lib.TaskUnit, bot as unknown as Lib.TaskCreep) + SETTINGS.OutMargin) return false;
    }
    return true;
}

/** A neutral attacks the hero: it walks towards its lane until out of the neutrals' reach (OutFor at most), then the stay ends `hit`. */
function* walkOut(bot: Unit, st: Stay, ctx: Lib.Ctx): Lib.TaskBody {
    ctx.label("out");
    const t0 = DotaTime();
    let movedAt = -math.huge;
    while (true) {
        if (!bot.IsAlive()) return ctx.fail("dead");
        const now = DotaTime();
        if (now - t0 >= SETTINGS.OutFor || outOfReach(bot, CampRead.FightOf(st.sp))) return { success: true, reason: "ok", message: "hit" } as Lib.Result;
        if (now - movedAt >= SETTINGS.Reorder) {
            bot.Action_MoveToLocation(lanePoint(bot));
            movedAt = now;
        }
        yield;
    }
}

/** The verb: stand behind our creeps, a neutral's last hit when one comes due, until an end. */
function* body(bot: Unit, st: Stay, ctx: Lib.Ctx): Lib.TaskBody {
    let movedAt = -math.huge;
    // The first order cancels whatever the hero carried in, and one after each attempt the verb's attack order (it outlives the hit).
    let stop = true;
    while (true) {
        if (!bot.IsAlive()) return ctx.fail("dead");
        const now = DotaTime();
        const f = CampRead.FightOf(st.sp);
        const stand = StandSpot(bot, f.ours, f.neutrals, st.sp.location);
        const end = endOf(bot, st, f, stand, now);
        if (end === "hit") return yield* walkOut(bot, st, ctx);
        if (end === "timeout") return ctx.fail("timeout", "late");
        if (end !== undefined) return { success: true, reason: "ok", message: end } as Lib.Result;
        const d = stand !== undefined && dist(bot.GetLocation(), stand) <= SETTINGS.AtSpot ? dueNeutral(bot, st, f) : undefined;
        if (d !== undefined) {
            yield* attempt(bot, st, d, ctx);
            stop = true;
            continue;
        }
        ctx.label("stand");
        const to = stand!;
        if (dist(bot.GetLocation(), to) > SETTINGS.Arrive) {
            if (now - movedAt >= SETTINGS.Reorder) {
                bot.Action_MoveToLocation(to);
                movedAt = now;
                stop = false;
            }
        } else if (stop) {
            bot.Action_MoveToLocation(to);
            stop = false;
        }
        yield;
    }
}

function cutBy(bot: Unit, r: Lib.Result): string | undefined {
    if (r.success || r.reason !== "preempted") return undefined;
    if (Decider.LetGo(bot) || bot.GetActiveMode() === BotMode.Retreat) return "retreat";
    return HDebug.ModeName(bot.GetActiveMode());
}

/** The end's name: the body's own (`creeps`, `cleared`, `hit`, `hp`, `danger`), `replaced` (a higher row began over it), else the runner's or the verb's reason. */
function endWhy(r: Lib.Result): string {
    if (r.success) return r.message ?? "ok";
    if (r.reason === "cancelled" && r.message === "replaced") return "replaced";
    return r.reason;
}

function finish(bot: Unit, st: Stay, r: Lib.Result): void {
    const pid = bot.GetPlayerID();
    running[pid] = undefined;
    const why = endWhy(r);
    const p = opps[pid];
    if (p !== undefined && p.slot === st.slot && (why === "hit" || why === "hp" || why === "timeout")) p.barred = why;
    jobLine(bot, st, "end", why, cutBy(bot, r));
}

/** The row's `begin`: starts the stay `rowWants` decided this round. */
function rowBegin(bot: Unit): boolean {
    const pid = bot.GetPlayerID();
    const r = pending[pid];
    pending[pid] = undefined;
    const p = opps[pid];
    if (r === undefined || p === undefined) return false;
    const now = DotaTime();
    const st: Stay = {
        aid: 0,
        sp: r.sp,
        slot: p.slot,
        t0: now,
        hp0: math.floor(bot.GetHealth()),
        deadline: (p.first ?? now) + SETTINGS.Max,
        tried: 0,
        landed: 0,
        hard: false,
        skip: [],
        dangerAt: now,
    };
    const ok = Tasks.Start(bot, { name: "stay", host: HOST, preemptAfter: 1, stallAfter: 4, onEnd: (res) => finish(bot, st, res) }, (ctx: Lib.Ctx) => body(bot, st, ctx));
    const aid = ok ? Telemetry.NextAid(pid) : undefined;
    if (p.logged !== true) choiceLine(bot, p, ok, ok ? undefined : "refused", "own", aid);
    p.logged = true;
    if (!ok) return false;
    st.aid = aid!;
    if (p.first === undefined) p.first = now;
    running[pid] = st;
    jobLine(bot, st, "start", "trigger");
    return true;
}

/** The row's verb: one frame of the stay; true once it has ended. */
function rowStep(bot: Unit): boolean {
    Tasks.Step(bot, HOST);
    return running[bot.GetPlayerID()] === undefined;
}

/** The decider's row (registered in index.ts, so the decider imports no row). Soft but in an attempt (`rowSoft`). */
export const ROW: Decider.Row = { name: "stay", wants: rowWants, begin: rowBegin, step: rowStep, soft: rowSoft, neutrals: (bot) => running[bot.GetPlayerID()] !== undefined };
