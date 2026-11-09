/**
 * Our retreat in lane (master docs/team/slices/retreat.md; design docs/proposals/2026-11-09-fights-and-retreat.md s5.4, slice 2).
 * For a hero our retreat owns (RetreatState.Owns): when it leaves (the threat read against a budget from its purpose, at once
 * on `lethal` or a tower on it, or at the heal floor), where to (the anchor whose straight walk costs least in enemy tower
 * reach, enemy creep acquisition and heroes who can reach it) and when it stops (the exit band for ExitDwell, or the anchor).
 * Every other hero walking in retreat mode gets the plain walk (a mode file with Think replaces Valve's walk for all).
 */
import { Shop, Team, Tower, Unit, UnitType, Vector } from "bots/ts_libs/dota";
import * as Telemetry from "bots/FunLib/humaniser/telemetry";
import * as Threat from "bots/FunLib/humaniser/threat";
import * as WorldFacts from "bots/FunLib/humaniser/world_facts";
import * as RetreatState from "bots/FunLib/humaniser/retreat_state";
import * as Profile from "bots/FunLib/humaniser/profile";
import * as Chooser from "bots/FunLib/humaniser/chooser";
import * as Lane_ from "bots/FunLib/humaniser/lane";
import * as FarmPattern from "bots/FunLib/humaniser/farm_pattern";
import * as Drill from "bots/FunLib/humaniser/drill";
import * as Ours from "bots/FunLib/humaniser/ours";

export const SETTINGS = {
    /** The read's horizon for staying (s): what can hit us before we can step away. judgement. */
    Horizon: 2,
    /** Base budget by purpose. judgement. */
    BudgetFree: 0.5,
    BudgetBusy: 0.6,
    BudgetCommitted: 0.75,
    /** Leave the episode when threat stays under budget - ExitBand for ExitDwell s (explicit hysteresis). judgement. */
    ExitBand: 0.15,
    ExitDwell: 1.5,
    /** Heal floor: HP share under HealFloor with no enemy in reach sends the hero to the fountain until HealUntil. judgement. */
    HealFloor: 0.3,
    HealUntil: 0.8,
    /** Route points every RouteStep along each anchor's straight walk. judgement. */
    RouteStep: 300,
    /** One route cost point per this many units of walk, so a long walk home does not beat a short one on fewer exposed
     *  points alone (drill rtwalk1: the fountain, 13,168 away at cost 2, beat our T1's walk at cost 4). judgement. */
    LenPerCost: 2000,
    /** The desire while an episode runs: above laning's 0.9, below OHA's 1.1 latch. judgement. */
    EpisodeDesire: 0.95,
    /** A forced drill rep holds the retreat mode above every mode the cast could otherwise take. */
    DrillDesire: 1.0,
    /** At the anchor: within this distance. judgement. */
    Arrive: 200,
    /** The stand point behind our tower: this far from it toward our fountain. judgement. */
    TowerStandBack: 350,
    /** The out-of-tower-reach anchor: this far past the targeting tower's reach. judgement. */
    TowerClear: 150,
    /** An ally hero is an anchor within this distance. judgement. */
    AllyAnchorMax: 3000,
    /** An episode not on the heal floor ends `cut` after this long (s). judgement. */
    MaxSecs: 40,
    /** The plain walk goes to the fountain under this HP share, else to our nearest tower behind the hero. judgement. */
    PlainFountainHP: 0.5,
    /** Reads and orders at most this often per hero (s). */
    ReadEvery: 0.1,
    OrderEvery: 0.3,
    /** A forced drill rep starting under this HP share is skipped (healed instead). judgement. */
    DrillMinHP: 0.5,
    /** The cast is at its drill start spot within this distance. */
    DrillSpotArrive: 150,
};

/** Valve's fountain spots (as drill.ts); GetShopLocation(team, SHOP_HOME) is logged beside them at load. */
const FOUNTAIN: Record<number, [number, number, number]> = { [Team.Radiant]: [-6619, -6336, 384], [Team.Dire]: [6928, 6372, 392] };
const TOWER_IDS = [Tower.Top1, Tower.Top2, Tower.Top3, Tower.Mid1, Tower.Mid2, Tower.Mid3, Tower.Bot1, Tower.Bot2, Tower.Bot3, Tower.Base1, Tower.Base2];

export type Why = "threat" | "lethal" | "tower" | "heal" | "forced";
type AnchorKind = "tower_edge" | "tower" | "ally" | "fountain";

interface Anchor {
    kind: AnchorKind;
    at: Vector;
    /** For an ally anchor: the ally, whose place is read each think. */
    ally?: Unit;
    cost: number;
    len: number;
}

interface Episode {
    id: number;
    start: number;
    why: Why;
    budget: number;
    anchor: Anchor;
    hp0: number;
    lastHp: number;
    dmgh: number;
    twr: boolean;
    wave: boolean;
    underSince?: number;
}

interface DrillRep {
    rep: number;
    phase: "walk" | "retreat" | "done" | "skip";
    spot: string;
    at?: Vector;
}

interface HeroState {
    ep?: Episode;
    overSince?: number;
    read?: Threat.Read;
    readAt?: number;
    orderAt?: number;
    orderTo?: Vector;
    plainAt?: number;
    drill?: DrillRep;
}

const states: Record<number, HeroState> = {};
let episodes = 0;
let fountainLogged = false;

export function ResetCache(): void {
    for (const k of Object.keys(states)) delete states[k as unknown as number];
    episodes = 0;
    fountainLogged = false;
    RetreatState.ResetCache();
}

function stateOf(bot: Unit): HeroState {
    const pid = bot.GetPlayerID();
    let s = states[pid];
    if (s === undefined) {
        s = {};
        states[pid] = s;
    }
    return s;
}

function dist(a: Vector, b: Vector): number {
    return math.sqrt((a.x - b.x) ** 2 + (a.y - b.y) ** 2);
}

function hpShare(bot: Unit): number {
    return bot.GetHealth() / math.max(1, bot.GetMaxHealth());
}

function enemyOf(team: number): number {
    return team === Team.Radiant ? Team.Dire : Team.Radiant;
}

// A live handle whose GetLocation() came back nil reached dist() in drill rtchase2 (three lua_errors); the cause is unknown,
// so such a unit is skipped rather than read.
function valid(u: Unit | undefined | null): u is Unit {
    return u !== null && u !== undefined && !u.IsNull() && u.IsAlive() && u.GetLocation() !== undefined;
}

const r2 = (x: number): number => math.floor(x * 100 + 0.5) / 100;

export function Fountain(team: number): Vector {
    const [x, y, z] = FOUNTAIN[team];
    return Vector(x, y, z);
}

function logFountain(): void {
    if (fountainLogged) return;
    fountainLogged = true;
    for (const team of [Team.Radiant, Team.Dire]) {
        const shop = GetShopLocation(team, Shop.Home);
        const f = Fountain(team);
        const live = shop !== undefined && shop !== null;
        Telemetry.Event("world_fact", [["team", team], ["fact", "fountain_x"], ["live", live ? math.floor(shop.x) : undefined], ["constant", math.floor(f.x)]]);
        Telemetry.Event("world_fact", [["team", team], ["fact", "fountain_y"], ["live", live ? math.floor(shop.y) : undefined], ["constant", math.floor(f.y)]]);
    }
}

/** An enemy tower attacking `bot` now, or one hit it in the last half second. */
export function TowerOnUs(bot: Unit): Unit | undefined {
    const enemy = enemyOf(bot.GetTeam());
    let near: Unit | undefined;
    let nearD = math.huge;
    for (const id of TOWER_IDS) {
        const tw = GetTower(enemy, id);
        if (!valid(tw)) continue;
        if (tw.GetAttackTarget() === bot) return tw;
        const d = GetUnitToUnitDistance(bot, tw);
        if (d < nearD) {
            near = tw;
            nearD = d;
        }
    }
    // The damage flag outlasts the hit by 0.5 s: past the reach's edge it would restart an episode that has just ended there.
    if (near === undefined || nearD > WorldFacts.TowerReach(near, Threat.SETTINGS.TowerReach) + bot.GetBoundingRadius()) return undefined;
    return bot.WasRecentlyDamagedByTower(0.5) ? near : undefined;
}

/** Busy (a pull, stack, camp or pull farm job, or a last hit on a creep in hand), committed (a rune walk), else free. */
function purposeOf(bot: Unit): [string, number] {
    const s = SETTINGS;
    const job = Chooser.RunningJobName(bot);
    if (job === "rune") return ["committed", s.BudgetCommitted];
    if (job !== undefined || Lane_.CampJobDesire(bot) > 0) return ["busy", s.BudgetBusy];
    const target = bot.GetAttackTarget();
    if (valid(target) && target.IsCreep()) return ["busy", s.BudgetBusy];
    return ["free", s.BudgetFree];
}

function readOf(bot: Unit, st: HeroState, now: number): Threat.Read {
    if (st.read !== undefined && st.readAt !== undefined && now - st.readAt < SETTINGS.ReadEvery) return st.read;
    const here = bot.GetLocation();
    st.read = Threat.Read(bot, here, here, SETTINGS.Horizon);
    st.readAt = now;
    return st.read;
}

// ---------------------------------------------------------------------------------------------------------------- route

interface PointCost {
    tower: boolean;
    wave: boolean;
    heroes: number;
}

/** The cost of standing at `p` when we reach it `t` seconds from now: enemy tower reach, enemy creep acquisition, heroes who can be in range by then. */
function pointCost(bot: Unit, p: Vector, t: number, towers: Unit[], creeps: Unit[], heroes: Unit[]): PointCost {
    let tower = false;
    for (const tw of towers) if (dist(tw.GetLocation(), p) <= WorldFacts.TowerReach(tw, Threat.SETTINGS.TowerReach)) tower = true;
    let wave = false;
    const br = bot.GetBoundingRadius();
    for (const c of creeps) if (dist(c.GetLocation(), p) <= c.GetAcquisitionRange() + c.GetBoundingRadius() + br) wave = true;
    let n = 0;
    for (const e of heroes) {
        const run = e.GetCurrentMovementSpeed() * t + e.GetAttackRange() + e.GetBoundingRadius() + br;
        if (dist(e.GetLocation(), p) <= run) n++;
    }
    return { tower, wave, heroes: n };
}

function enemyUnits(bot: Unit): [Unit[], Unit[], Unit[]] {
    const enemy = enemyOf(bot.GetTeam());
    const towers: Unit[] = [];
    for (const id of TOWER_IDS) {
        const tw = GetTower(enemy, id);
        if (valid(tw)) towers.push(tw);
    }
    const creeps = (bot.GetNearbyLaneCreeps(1600, true) ?? []).filter((c) => valid(c));
    const heroes = (GetUnitList(UnitType.EnemyHeroes) ?? []).filter((e) => valid(e) && !e.IsIllusion() && e.CanBeSeen());
    return [towers, creeps, heroes];
}

/** The straight walk from `from` to `to`, its points every RouteStep (the start excluded) scored and summed. */
function routeCost(bot: Unit, from: Vector, to: Vector, units: [Unit[], Unit[], Unit[]]): number {
    const d = dist(from, to);
    const n = math.max(1, math.ceil(d / SETTINGS.RouteStep));
    const speed = math.max(100, bot.GetCurrentMovementSpeed());
    let cost = 0;
    for (let i = 1; i <= n; i++) {
        const p = Vector(from.x + ((to.x - from.x) * i) / n, from.y + ((to.y - from.y) * i) / n, to.z);
        const c = pointCost(bot, p, (d * i) / n / speed, units[0], units[1], units[2]);
        cost += (c.tower ? 1 : 0) + (c.wave ? 1 : 0) + c.heroes;
    }
    return cost;
}

/**
 * Our standing towers that are not ahead of the hero: no nearer the enemy fountain than it, less TowerStandBack. Not our own
 * fountain's distance: in the safe lane our T1 is farther from our fountain than our pull camp (drill rtwalk1).
 */
function ownTowersBehind(bot: Unit): Unit[] {
    const team = bot.GetTeam();
    const ef = Fountain(enemyOf(team));
    const mine = dist(bot.GetLocation(), ef);
    const out: Unit[] = [];
    for (const id of TOWER_IDS) {
        const tw = GetTower(team, id);
        if (valid(tw) && dist(tw.GetLocation(), ef) > mine - SETTINGS.TowerStandBack) out.push(tw);
    }
    return out;
}

function towards(a: Vector, b: Vector, by: number): Vector {
    const d = math.max(1, dist(a, b));
    return Vector(a.x + ((b.x - a.x) * by) / d, a.y + ((b.y - a.y) * by) / d, a.z);
}

function standPoint(tower: Unit, team: number): Vector {
    const p = towards(tower.GetLocation(), Fountain(team), SETTINGS.TowerStandBack);
    return IsLocationPassable(p) ? p : tower.GetLocation();
}

/** The anchors (design 5.4): out of a targeting tower's reach, our nearest tower behind us, the nearest ally hero, the fountain. */
function anchorsOf(bot: Unit, why: Why): Anchor[] {
    const team = bot.GetTeam();
    const here = bot.GetLocation();
    const f = Fountain(team);
    const out: Anchor[] = [{ kind: "fountain", at: f, cost: 0, len: dist(here, f) }];
    if (why === "heal") return out;
    const tw = TowerOnUs(bot);
    if (tw !== undefined) {
        const reach = WorldFacts.TowerReach(tw, Threat.SETTINGS.TowerReach) + SETTINGS.TowerClear;
        const away = dist(tw.GetLocation(), here) < 1 ? f : here;
        const p = towards(tw.GetLocation(), away, reach);
        if (IsLocationPassable(p)) out.push({ kind: "tower_edge", at: p, cost: 0, len: dist(here, p) });
    }
    let nearT: Unit | undefined;
    let nearD = math.huge;
    for (const t of ownTowersBehind(bot)) {
        const d = GetUnitToUnitDistance(bot, t);
        if (d < nearD) {
            nearT = t;
            nearD = d;
        }
    }
    if (nearT !== undefined) {
        const p = standPoint(nearT, team);
        out.push({ kind: "tower", at: p, cost: 0, len: dist(here, p) });
    }
    let ally: Unit | undefined;
    let allyD = SETTINGS.AllyAnchorMax;
    for (const a of GetUnitList(UnitType.AlliedHeroes) ?? []) {
        if (!valid(a) || a === bot || a.IsIllusion() || RetreatState.Running(a)) continue;
        const d = GetUnitToUnitDistance(bot, a);
        if (d < allyD) {
            ally = a;
            allyD = d;
        }
    }
    if (ally !== undefined) out.push({ kind: "ally", at: ally.GetLocation(), ally, cost: 0, len: allyD });
    return out;
}

/** The least-cost anchor (exposed route points plus the walk's length, LenPerCost; ties to the shorter) and the next-best's cost. */
function chooseAnchor(bot: Unit, why: Why): [Anchor, number | undefined] {
    const units = enemyUnits(bot);
    const here = bot.GetLocation();
    const list = anchorsOf(bot, why);
    for (const a of list) a.cost = math.floor((routeCost(bot, here, a.at, units) + a.len / SETTINGS.LenPerCost) * 10 + 0.5) / 10;
    list.sort((a, b) => (a.cost !== b.cost ? a.cost - b.cost : a.len - b.len));
    return [list[0], list[1]?.cost];
}

function anchorPoint(a: Anchor): Vector {
    return a.ally !== undefined && valid(a.ally) ? a.ally.GetLocation() : a.at;
}

// ---------------------------------------------------------------------------------------------------------------- episodes

function start(bot: Unit, st: HeroState, why: Why, r: Threat.Read, budget: number, purp: string, spot?: string, rep?: number): void {
    const now = DotaTime();
    const [anchor, alt] = chooseAnchor(bot, why);
    episodes++;
    const hp = hpShare(bot);
    st.ep = { id: episodes, start: now, why, budget, anchor, hp0: hp, lastHp: bot.GetHealth(), dmgh: 0, twr: false, wave: false };
    st.overSince = undefined;
    RetreatState.SetRunning(bot, true);
    // Our retreat ends a running job with a cause (retreat left Chooser.EXCEPTIONS' role of taking the hero mid-job).
    Chooser.Abort(bot, "retreat");
    Lane_.CampJobAbort(bot, "retreat");
    FarmPattern.Abort(bot, "retreat");
    const here = bot.GetLocation();
    Telemetry.Event("retreat", [
        ["ph", "start"],
        ["pid", bot.GetPlayerID()],
        ["kind", "ours"],
        ["ep", st.ep.id],
        ["why", why],
        ["hp", r2(hp)],
        ["thr", r2(r.threat)],
        ["band", r.band],
        ["reach", r.reach.length],
        ["burst", r2(r.burst)],
        ["tower", r.tower],
        ["esc", r.reach.length > 0 ? r.escape : undefined],
        ["budget", r2(budget)],
        ["purp", purp],
        ["anchor", anchor.kind],
        ["cost", anchor.cost],
        ["alt", alt],
        ["dist", math.floor(anchor.len)],
        ["spot", spot],
        ["rep", rep],
        ["x", math.floor(here.x)],
        ["y", math.floor(here.y)],
    ]);
}

function end(bot: Unit, st: HeroState, res: string): void {
    const ep = st.ep;
    if (ep === undefined) return;
    st.ep = undefined;
    st.orderTo = undefined;
    RetreatState.SetRunning(bot, false);
    const max = math.max(1, bot.GetMaxHealth());
    Telemetry.Event("retreat", [
        ["ph", "end"],
        ["pid", bot.GetPlayerID()],
        ["kind", "ours"],
        ["ep", ep.id],
        ["why", ep.why],
        ["anchor", ep.anchor.kind],
        ["res", res],
        ["secs", r2(DotaTime() - ep.start)],
        ["hpl", r2(math.max(0, ep.hp0 - (bot.IsAlive() ? hpShare(bot) : 0)))],
        ["twr", ep.twr],
        ["wave", ep.wave],
        ["dmgh", r2(ep.dmgh / max)],
    ]);
    if (st.drill !== undefined && st.drill.phase === "retreat") st.drill.phase = "done";
}

/** Per think while an episode runs: the walk's exposure, then the stop rule. Returns the result when it ends. */
function step(bot: Unit, st: HeroState, r: Threat.Read, now: number): string | undefined {
    const ep = st.ep!;
    const s = SETTINGS;
    const hp = bot.GetHealth();
    if (hp < ep.lastHp && bot.WasRecentlyDamagedByAnyHero(0.3)) ep.dmgh += ep.lastHp - hp;
    ep.lastHp = hp;
    const here = bot.GetLocation();
    const [towers, creeps] = enemyUnits(bot);
    const c = pointCost(bot, here, 0, towers, creeps, []);
    if (c.tower) ep.twr = true;
    if (c.wave) ep.wave = true;

    const forced = ep.why === "forced";
    if (!forced && !RetreatState.Owns(bot)) return "cut";
    const at = dist(here, anchorPoint(ep.anchor)) <= s.Arrive;
    if (ep.why === "heal") return at && hpShare(bot) >= s.HealUntil ? "anchor" : undefined;
    if (at) {
        if (forced || r.threat < ep.budget) return "anchor";
        // Still over budget at a stop short of home: on to the fountain.
        if (ep.anchor.kind !== "fountain") {
            const f = Fountain(bot.GetTeam());
            ep.anchor = { kind: "fountain", at: f, cost: ep.anchor.cost, len: dist(here, f) };
        }
    }
    if (now - ep.start > s.MaxSecs) return "cut";
    if (forced || TowerOnUs(bot) !== undefined || r.threat >= ep.budget - s.ExitBand) {
        ep.underSince = undefined;
        return undefined;
    }
    ep.underSince = ep.underSince ?? now;
    return now - ep.underSince >= s.ExitDwell ? "safe" : undefined;
}

/** The leave rule: lethal, a tower on us or the heal floor at once; over budget for the hero's reaction time. */
function leaveWhy(bot: Unit, st: HeroState, r: Threat.Read, budget: number, now: number): Why | undefined {
    if (r.band === "lethal") return "lethal";
    if (TowerOnUs(bot) !== undefined) return "tower";
    if (hpShare(bot) < SETTINGS.HealFloor && r.reach.length === 0) return "heal";
    if (r.threat <= budget) {
        st.overSince = undefined;
        return undefined;
    }
    st.overSince = st.overSince ?? now;
    return now - st.overSince >= Profile.Get(bot).reactBase ? "threat" : undefined;
}

// ---------------------------------------------------------------------------------------------------------------- drill

/** The retreat-walk drill's cast: walk to the rep's start spot, then the forced episode, then stand. Undefined when not in it. */
function drillDesire(bot: Unit, st: HeroState, now: number): number | undefined {
    if (Drill.ForcedAt("retreat", now) === undefined || Drill.RoleOf(bot) !== "cast") return undefined;
    const rep = Drill.RepAt(now);
    if (rep === 0) return undefined;
    if (st.drill === undefined || st.drill.rep !== rep) {
        if (st.ep !== undefined) end(bot, st, "cut");
        const spot = Drill.CastSpot(rep) ?? "front";
        const skip = hpShare(bot) < SETTINGS.DrillMinHP;
        st.drill = { rep, phase: skip ? "skip" : "walk", spot, at: skip ? Fountain(bot.GetTeam()) : Drill.CastSpotPoint(bot, spot) };
        if (skip) Telemetry.Event("retreat", [["ph", "skip"], ["pid", bot.GetPlayerID()], ["rep", rep], ["spot", spot], ["hp", r2(hpShare(bot))]]);
    }
    const d = st.drill;
    if (d.phase === "walk" && (d.at === undefined || GetUnitToLocationDistance(bot, d.at) <= SETTINGS.DrillSpotArrive)) {
        d.phase = "retreat";
        start(bot, st, "forced", readOf(bot, st, now), SETTINGS.BudgetFree, "free", d.spot, rep);
    }
    if (d.phase === "retreat" && st.ep !== undefined) {
        const res = step(bot, st, readOf(bot, st, now), now);
        if (res !== undefined) end(bot, st, res);
    }
    return SETTINGS.DrillDesire;
}

// ---------------------------------------------------------------------------------------------------------------- hooks

/** With the switch on: Think is assigned at load (mode_retreat_generic). */
export function On(): boolean {
    return Ours.On("Retreat");
}

/** mode_retreat_generic GetDesire: our desire for a hero we own (EpisodeDesire while an episode runs, else 0); undefined lets OHA's desire run. */
export function Desire(bot: Unit): number | undefined {
    const st = stateOf(bot);
    const now = DotaTime();
    logFountain();
    const drill = drillDesire(bot, st, now);
    if (drill !== undefined) return drill;
    if (!RetreatState.Owns(bot)) {
        if (st.ep !== undefined) end(bot, st, "cut");
        return undefined;
    }
    if (!bot.IsAlive()) {
        if (st.ep !== undefined) end(bot, st, "died");
        st.overSince = undefined;
        return 0;
    }
    const r = readOf(bot, st, now);
    if (st.ep !== undefined) {
        const res = step(bot, st, r, now);
        if (res === undefined) return SETTINGS.EpisodeDesire;
        end(bot, st, res);
        return 0;
    }
    const [purp, budget] = purposeOf(bot);
    const why = leaveWhy(bot, st, r, budget, now);
    if (why === undefined) return 0;
    start(bot, st, why, r, budget, purp);
    return SETTINGS.EpisodeDesire;
}

/** Per frame (index Tick): a death ends the episode even when GetDesire is not asked while dead. */
export function Tick(bot: Unit): void {
    const st = states[bot.GetPlayerID()];
    if (st?.ep !== undefined && !bot.IsAlive()) end(bot, st, "died");
}

function moveTo(bot: Unit, st: HeroState, p: Vector, now: number): void {
    if (st.orderTo !== undefined && st.orderAt !== undefined && dist(st.orderTo, p) < 50 && now - st.orderAt < SETTINGS.OrderEvery) return;
    st.orderTo = p;
    st.orderAt = now;
    bot.Action_MoveToLocation(p);
}

/** The plain walk: the fountain under PlainFountainHP, else our nearest tower behind the hero, else the fountain. */
function plainTarget(bot: Unit): [string, Vector] {
    const team = bot.GetTeam();
    if (hpShare(bot) < SETTINGS.PlainFountainHP) return ["fountain", Fountain(team)];
    let best: Unit | undefined;
    let bestD = math.huge;
    for (const t of ownTowersBehind(bot)) {
        const d = GetUnitToUnitDistance(bot, t);
        if (d < bestD) {
            best = t;
            bestD = d;
        }
    }
    return best !== undefined ? ["tower", standPoint(best, team)] : ["fountain", Fountain(team)];
}

/** mode_retreat_generic Think (assigned at load with the switch on): our episode's walk, a drill rep's walk, or the plain walk. */
export function Think(bot: Unit): void {
    const st = stateOf(bot);
    const now = DotaTime();
    const d = st.drill;
    if (d !== undefined && Drill.ForcedAt("retreat", now) !== undefined && st.ep === undefined) {
        if ((d.phase === "walk" || d.phase === "skip") && d.at !== undefined) moveTo(bot, st, d.at, now);
        // Between its episode and the next rep the cast takes the plain walk, out of the enemy's reach (rtwalk1: left at the
        // tower's edge it started rep 2 at 0.36 HP).
        else moveTo(bot, st, plainTarget(bot)[1], now);
        return;
    }
    if (st.ep !== undefined) {
        moveTo(bot, st, anchorPoint(st.ep.anchor), now);
        return;
    }
    const [kind, p] = plainTarget(bot);
    if (st.plainAt === undefined || now - st.plainAt > 1) {
        Telemetry.Event("retreat", [["ph", "start"], ["pid", bot.GetPlayerID()], ["kind", "plain"], ["anchor", kind], ["hp", r2(hpShare(bot))], ["x", math.floor(p.x)], ["y", math.floor(p.y)]]);
    }
    st.plainAt = now;
    moveTo(bot, st, p, now);
}

/** The lane-only drill harness steps aside for our retreat while an episode runs (mode_laning_generic). */
export function Running(bot: Unit): boolean {
    return RetreatState.Running(bot);
}

/** mode_farm_generic: none of ShouldRun's runs apply to a hero our retreat owns. */
export function Owns(bot: Unit): boolean {
    return RetreatState.Owns(bot);
}
