/**
 * The priced leave in the game (decision centre pilot step 2 part B; master docs/proposals/decision-centre/step2-3-decider.md s2, s3,
 * s5, s6 and the direction log): the scope, the gather of `LeavePrice.Decide`'s inputs, the incumbent per hero, and one
 * `ev=choice kind=leave` line per decision. Kept apart from the pure `leave_price.ts` so the replay loads only the rule.
 *
 * Priced: only a `threat` answer of the leave rule (kill line from ratio `Safe.BARS.hold` to the bar), and its hit back or join holds
 * (the same band). Hard leaves, no price: a tower on us, the heal rule, burst now, and `lethal` (under the hold ratio: the replay found
 * the tables blind there). Outside the scope or the band `For` answers nothing and the leave rule decides as before.
 */
import { Tower, Unit, UnitType } from "bots/ts_libs/dota";
import * as Commit from "bots/FunLib/humaniser/commit";
import * as LeavePrice from "bots/FunLib/humaniser/leave_price";
import * as P from "bots/FunLib/humaniser/dc_prices";
import * as LaneConfig from "bots/FunLib/humaniser/lane_config";
import * as Ours from "bots/FunLib/humaniser/ours";
import * as Telemetry from "bots/FunLib/humaniser/telemetry";
import * as Trade from "bots/FunLib/humaniser/states/trade";
import * as Plays from "bots/FunLib/humaniser/plays/plays";

export const SETTINGS = {
    /** An ally in a running exchange counts when within this of us, and its target too (design s11 "can join"). */
    JoinReach: 1200,
    /** Enemies whose attack target is us count towards `hs` within this (the fit's 1,600). */
    HitReach: 1600,
    /** The callback's hit window for `hs` (s): the fit read one second. */
    HitWindow: 1,
    /** Enemy lane creeps count towards the farm within our attack range plus this. */
    FarmPad: 300,
    /** In scope with no change, a line at most this often per hero (s). */
    LogEvery: 2,
};

const TOWER_IDS = [Tower.Top1, Tower.Top2, Tower.Top3, Tower.Mid1, Tower.Mid2, Tower.Mid3, Tower.Bot1, Tower.Bot2, Tower.Bot3, Tower.Base1, Tower.Base2];

/** What the leave rule (`Retreat.LeaveWhy`) answered, as `For` reads it (no import of the retreat). */
export interface LeaveAnswer {
    why?: string;
    stay?: string;
}

export type ScopeCase = "trade" | "play" | "ally";

/** The gathered inputs, the scope and what the line carries beside them. */
export interface Gathered extends LeavePrice.Inputs {
    sc: ScopeCase;
    tpid: number;
    /** Step 1's hitter count (3 s), beside `hs`. */
    nh?: number;
    /** Visible enemy heroes within REACH of us. */
    ne: number;
}

export interface Pick extends LeavePrice.Result {
    g: Gathered;
}

interface HeroState {
    lw?: LeaveAnswer;
    res?: Pick;
    inc?: LeavePrice.Pick;
    key?: string;
    loggedPick?: string;
    loggedAt?: number;
}

const states: Record<number, HeroState | undefined> = {};

export function ResetCache(): void {
    for (const k of Object.keys(states)) delete states[k as unknown as number];
}

/** The incumbent is forgotten (an episode started or ended outside the decider's sight, in shadow). */
export function Forget(bot: Unit): void {
    states[bot.GetPlayerID()] = undefined;
}

/** The pick acts (`Ours.PricedLeaveAct`, which needs `Ours.PricedLeave`). */
export function Acts(): boolean {
    return Ours.On("PricedLeave") && Ours.On("PricedLeaveAct");
}

function seen(u: Unit | undefined | null): u is Unit {
    return u !== null && u !== undefined && !u.IsNull() && u.IsAlive() && u.CanBeSeen() && u.GetLocation() !== undefined;
}

/** The scope (s2), in order: our own exchange's target, our play's target, an ally's exchange target within JoinReach of us. */
export function ScopeOf(bot: Unit): { sc: ScopeCase; t: Unit } | undefined {
    if (Trade.Running(bot)) {
        const t = Trade.EpisodeOf(bot.GetPlayerID())?.target;
        if (seen(t)) return { sc: "trade", t };
    }
    const play = Plays.Of(bot);
    if (play !== undefined && seen(play.target)) return { sc: "play", t: play.target };
    for (const a of GetUnitList(UnitType.AlliedHeroes) ?? []) {
        if (!seen(a) || a === bot || a.IsIllusion() || GetUnitToUnitDistance(bot, a) > SETTINGS.JoinReach || !Trade.Running(a)) continue;
        const t = Trade.EpisodeOf(a.GetPlayerID())?.target;
        if (seen(t) && GetUnitToUnitDistance(bot, t) <= SETTINGS.JoinReach) return { sc: "ally", t };
    }
    return undefined;
}

function creepKind(name: string): string {
    if (string.find(name, "siege", 1, true)[0] !== undefined) return "siege";
    if (string.find(name, "ranged", 1, true)[0] !== undefined) return "ranged";
    if (string.find(name, "flag", 1, true)[0] !== undefined) return "flag";
    return "melee";
}

const spa = (u: Unit): number => math.max(0.2, (u as Unit & { GetSecondsPerAttack?(): number }).GetSecondsPerAttack?.() ?? 1.7);

/** Gold (unconverted) of the enemy lane creeps within our attack range + FarmPad that our units' attacks kill within the horizon. */
function farmGold(bot: Unit): number {
    const creeps = bot.GetNearbyLaneCreeps(math.min(1600, bot.GetAttackRange() + SETTINGS.FarmPad), true) ?? [];
    if (creeps.length === 0) return 0;
    const ours: Unit[] = [];
    for (const c of bot.GetNearbyLaneCreeps(1600, false) ?? []) if (seen(c)) ours.push(c);
    for (const a of GetUnitList(UnitType.AlliedHeroes) ?? []) if (seen(a) && !a.IsIllusion() && GetUnitToUnitDistance(bot, a) <= 1600) ours.push(a);
    let gold = 0;
    for (const c of creeps) {
        if (!seen(c)) continue;
        let dps = 0;
        for (const u of ours) if (u.GetAttackTarget() === c) dps += u.GetAttackDamage() / spa(u);
        if (c.GetHealth() <= P.HORIZON * dps) gold += P.LASTHIT_BY_KIND[creepKind(c.GetUnitName())] ?? P.LASTHIT;
    }
    return gold;
}

function walk(bot: Unit): number {
    let best = math.huge;
    for (const id of TOWER_IDS) {
        const tw = GetTower(bot.GetTeam(), id);
        if (tw !== null && tw !== undefined && !tw.IsNull() && tw.IsAlive()) best = math.min(best, GetUnitToUnitDistance(bot, tw));
    }
    return best === math.huge ? 10000 : best;
}

/** The decider's inputs at the fit's reach (s3); undefined outside the scope. */
export function Gather(bot: Unit, lw: LeaveAnswer): Gathered | undefined {
    const s = ScopeOf(bot);
    if (s === undefined) return undefined;
    const pid = bot.GetPlayerID();
    const by: Record<number, boolean> = {};
    let hs = 0;
    let ne = 0;
    for (const e of GetUnitList(UnitType.EnemyHeroes) ?? []) {
        if (!seen(e) || e.IsIllusion()) continue;
        const d = GetUnitToUnitDistance(bot, e);
        if (d <= P.REACH) ne++;
        if (d <= SETTINGS.HitReach && e.GetAttackTarget() === bot && by[e.GetPlayerID()] !== true) {
            by[e.GetPlayerID()] = true;
            hs++;
        }
    }
    for (const epid of Commit.HitterIds(pid, SETTINGS.HitWindow)) {
        if (by[epid] === true) continue;
        by[epid] = true;
        hs++;
    }
    let n = 1;
    for (const a of GetUnitList(UnitType.AlliedHeroes) ?? []) {
        if (!seen(a) || a === bot || a.IsIllusion()) continue;
        if (GetUnitToUnitDistance(a, s.t) <= P.REACH) n++;
    }
    const hp = (100 * bot.GetHealth()) / math.max(1, bot.GetMaxHealth());
    const g: Gathered = {
        sc: s.sc,
        tpid: s.t.GetPlayerID(),
        nh: Commit.Nh(pid),
        ne,
        hp,
        hs,
        thp: (100 * s.t.GetHealth()) / math.max(1, s.t.GetMaxHealth()),
        n,
        w: walk(bot),
        ms: bot.GetCurrentMovementSpeed(),
        pos: LaneConfig.PositionOf(bot) ?? 3,
        cg: 0,
        tower: lw.why === "tower",
        heal: lw.why === "heal",
        lethal: lw.why === "lethal",
    };
    // Burst now and the farm only where a price is asked (their reads loop over units).
    if (!g.tower && !g.heal && !g.lethal) {
        // Only enemies within REACH: BurstNow sums every visible enemy, and Valve's estimate ignores distance (smoke dc-step2:
        // 17 burst leaves, some over a hit back with the summed enemies far apart).
        const b = Commit.BurstNow(bot).by;
        let sum = 0;
        for (const e of GetUnitList(UnitType.EnemyHeroes) ?? []) {
            const x = seen(e) && !e.IsIllusion() && GetUnitToUnitDistance(bot, e) <= P.REACH ? b[e.GetPlayerID()] : undefined;
            if (x !== undefined) sum += x.spell + x.attack;
        }
        g.burst = sum >= bot.GetHealth();
        if (!g.burst) g.cg = farmGold(bot);
    }
    return g;
}

const r1 = (x: number | undefined): number | undefined => (x === undefined ? undefined : math.floor(x * 10 + 0.5) / 10);
const r3 = (x: number | undefined): number | undefined => (x === undefined ? undefined : math.floor(x * 1000 + 0.5) / 1000);

/** The leave rule's answer in the priced band (a threat leave or its holds), or a hard leave. */
function inBand(lw: LeaveAnswer): boolean {
    return lw.why === "threat" || lw.why === "tower" || lw.why === "heal" || lw.why === "lethal" || lw.stay === "join" || lw.stay === "hitback";
}

function log(bot: Unit, st: HeroState, r: Pick, act: boolean, now: number): void {
    const tag = r.hard ?? r.pick;
    if (st.loggedPick === tag && r.rel === 0 && st.loggedAt !== undefined && now - st.loggedAt < SETTINGS.LogEvery) return;
    st.loggedPick = tag;
    st.loggedAt = now;
    const g = r.g;
    Telemetry.Event("choice", [
        ["pid", bot.GetPlayerID()],
        ["kind", "leave"],
        ["pick", r.pick],
        ["act", act ? 1 : 0],
        ["hard", r.hard],
        ["inc", r.inc],
        ["rel", r.rel],
        ["mg", r.M],
        ["sc", g.sc],
        ["tpid", g.tpid],
        ["lw", st.lw?.why ?? st.lw?.stay],
        ["hp", r1(g.hp)],
        ["hs", g.hs],
        ["nh", g.nh],
        ["ne", g.ne],
        ["thp", r1(g.thp)],
        ["n", g.n],
        ["w", math.floor(g.w)],
        ["spd", math.floor(g.ms)],
        ["pos", g.pos],
        ["cg", r1(g.cg)],
        ["sv", r1(r.stay)],
        ["lv", r1(r.leave)],
        ["d", r1(r.d)],
        ["pks", r3(r.pks)],
        ["pkl", r3(r.pkl)],
        ["pds", r3(r.pds)],
        ["pdl", r3(r.pdl)],
        ["fm", r1(r.F)],
        ["wk", r1(r.W)],
    ]);
}

/**
 * The priced pick for this hero given the leave rule's answer `lw`, decided once per answer (the retreat refreshes it with its read,
 * at most every `Retreat.SETTINGS.ReadEvery`): whichever caller asks first in the frame decides and the other reads it. Undefined
 * outside the scope or the band, which forgets the incumbent. The first incumbent is the leave rule's answer. Logs the line.
 */
export function For(bot: Unit, lw: LeaveAnswer): Pick | undefined {
    const pid = bot.GetPlayerID();
    let st = states[pid];
    if (st !== undefined && st.lw === lw) return st.res;
    const g = inBand(lw) ? Gather(bot, lw) : undefined;
    if (g === undefined) {
        states[pid] = { lw, res: undefined };
        return undefined;
    }
    if (st === undefined || st.inc === undefined) st = { ...(st ?? {}), inc: lw.why !== undefined ? "leave" : "stay" };
    st.lw = lw;
    const key = `${g.sc}|${g.tpid}|${math.min(g.n, 2)}|${g.ne}|${math.min(g.hs, 2)}`;
    g.rel = st.key !== undefined && st.key !== key;
    st.key = key;
    const r: Pick = { ...LeavePrice.Decide(g, st.inc), g };
    st.inc = r.pick;
    st.res = r;
    states[pid] = st;
    log(bot, st, r, Acts(), DotaTime());
    return r;
}
