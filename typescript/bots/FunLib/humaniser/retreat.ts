/**
 * Our retreat in lane (master docs/team/slices/retreat.md; design docs/proposals/2026-11-09-fights-and-retreat.md s5.4, slice 2).
 * For a hero our retreat owns (RetreatState.Owns): when it leaves (the threat read against a budget from its purpose, at once
 * on `lethal` or a tower on it, or at the heal floor), where to (the anchor whose straight walk costs least in enemy tower
 * reach, enemy creep acquisition and heroes who can reach it) and when it stops (the exit band for ExitDwell, or the anchor).
 * Every other hero walking in retreat mode gets the plain walk (a mode file with Think replaces Valve's walk for all).
 */
import { BotMode, Lane, Shop, Team, Tower, Unit, UnitType, Vector } from "bots/ts_libs/dota";
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
import * as LaneFightConfig from "bots/FunLib/humaniser/lane_fight_config";
import * as ItemUse from "bots/FunLib/humaniser/item_use";

export const SETTINGS = {
    /** The read's horizon for staying (s): what can hit us before we can step away. judgement. */
    Horizon: 2,
    /**
     * Seconds a hero already hitting us is counted over (`Threat.Read` `opts.engagedWindow`), the same value and reason as the lane
     * spot's LANE_ENGAGED_WINDOW: he keeps hitting while we stay. The exit read is the same call, so an episode does not end `safe`
     * while he still hits us. At 2.6% of max HP a second one engaged melee hero reads 0.25 + 0.078 / HP: over the free budget 0.5
     * from about 31% HP, and 0.33 at full HP (a lone harasser at full HP starts nothing). judgement.
     */
    EngagedWindow: 6,
    /**
     * RetreatOdds: a fight the heroes in reach do not outnumber is held (no `threat` leave) only while their burst, as the read
     * counts it (an engaged hero over EngagedWindow), is under this share of our current HP: D1's "their burst can kill me".
     * 0.5 left nearly every forced 2v2 (drill retreat-even 3-4: two engaged heroes pass half our HP over 6 s). judgement.
     */
    EvenBurst: 1,
    /** RetreatOdds: and only at this HP share or more, the D24 view's "not in danger" bar: under it the hero, which does not
     *  hit back yet, would only absorb the damage (a melee hero hitting us at 25% HP still sends us home). judgement. */
    EvenHp: 0.5,
    /** Base budget by purpose. judgement. */
    BudgetFree: 0.5,
    BudgetBusy: 0.6,
    BudgetCommitted: 0.75,
    /**
     * Leave the episode when threat stays under budget - ExitBand for ExitDwell s (explicit hysteresis) while a hero is still in
     * reach; with nobody in reach, at once under the band. judgement.
     */
    ExitBand: 0.15,
    ExitDwell: 1.5,
    /** Heal floor: HP share under HealFloor with no enemy in reach sends the hero to the fountain until HealUntil. judgement. */
    HealFloor: 0.3,
    HealUntil: 0.8,
    /**
     * HealStop (D3): a heal episode also ends `healed` at this HP share with nobody in reach, while our lane front is nearer
     * than our fountain. The D3 view's bar: a retreat run at 50% HP+ with nobody near is a violation after 10 s. judgement.
     */
    HealBack: 0.5,
    /** Route points every RouteStep along each anchor's straight walk. judgement. */
    RouteStep: 300,
    /**
     * One route cost point per this many seconds of walk at our current speed, so a long walk home does not beat a short one on
     * fewer exposed points alone (drill rtwalk1: the fountain, 13,168 away at cost 2, beat our T1's walk at cost 4). Walk time
     * not length, so a slowed hero prices its walk (about 1,650 units a point at 330 a second, a little stronger than the 2,000 it replaced). judgement.
     */
    SecsPerCost: 5,
    /**
     * Items that heal HP when used on ourselves (tango, salve, faerie fire; slots 0-5, the backpack cannot be cast). Holding one
     * takes RegenCredit off our tower anchor (not the enemy tower's edge)'s cost: the tower is cover while it runs and its aura regenerates allies (a primary
     * source, user 10/11/2026; the amount is not read here). Reading only: the use is the Regen slice's. judgement.
     */
    RegenItems: ["item_tango", "item_tango_single", "item_flask", "item_faerie_fire"],
    RegenCredit: 1,
    /**
     * HealItems (slice heal-items, D6 stop-gap): at a heal start the first of these sets, all held, that restores HP to HealBack
     * is used and the hero waits at our tower; none does, or our fountain is the nearer: the walk home with the items kept.
     * Cheapest first, two items at most, never two tangoes (a recast refreshes the buff, it does not stack); faerie fire, a
     * fight's burst, only with no salve held (user 11/11/2026 asked for boundaries). judgement.
     */
    HealSets: [["tango_single"], ["tango"], ["salve"], ["fire"], ["salve", "tango"], ["tango", "fire"]] as HealItem[][],
    /** A tango is in a set only with a tree this near (camp supply's TangoTree). judgement. */
    HealTree: 300,
    /** After a use, no other order until its buff shows or this long has passed (a tango walks to its tree first). judgement. */
    HealUseWait: 1.5,
    /**
     * The read's horizon (s) for using items: a salve's 13 s breaks on a hero's hit, so a hero who can reach us within the gates'
     * horizon (Threat GateHorizon, about 1,400 for a melee) holds them, not only one in the stay read's 2 s (rig on2, on3
     * `stays`: the attacker standing 700 off read out of reach, and the salve was drunk). judgement.
     */
    HealItemHorizon: Threat.SETTINGS.GateHorizon,
    /**
     * A hero out of sight for no more than Threat MissingAfter is in neither the read's reach (it reads visible heroes) nor its
     * missing belief (after MissingAfter); for items it counts from its last sighting: MissingSpeed over the time since plus
     * HealItemHorizon, plus this for its attack range and both hulls (a melee's 150 and two 24s). judgement.
     */
    HealItemUnseenMargin: 200,
    /** The desire while an episode runs; the chooser's gate holds every other mode but the human's orders at 0 meanwhile. judgement. */
    EpisodeDesire: 0.95,
    /** A forced drill rep holds the retreat mode above every mode the cast could otherwise take. */
    DrillDesire: 1.0,
    /** At the anchor: within this distance. judgement. */
    Arrive: 200,
    /** The stand point behind our tower: this far from it toward our fountain. judgement. */
    TowerStandBack: 350,
    /** The out-of-tower-reach anchor: this far past the targeting tower's reach plus Arrive. judgement. */
    TowerClear: 50,
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
type HealItem = "tango_single" | "tango" | "salve" | "fire";
const HEAL_ITEM: Record<HealItem, { name: string; modifier?: string }> = {
    tango_single: { name: "item_tango_single", modifier: "modifier_tango_heal" },
    tango: { name: "item_tango", modifier: "modifier_tango_heal" },
    salve: { name: "item_flask", modifier: "modifier_flask_healing" },
    fire: { name: "item_faerie_fire" },
};
type AnchorKind = "tower_edge" | "tower" | "ally" | "fountain";

interface Anchor {
    kind: AnchorKind;
    at: Vector;
    /** For an ally anchor: the ally, whose place is read each think. */
    ally?: Unit;
    cost: number;
    len: number;
    /** Exposed route points (tower, wave and heroes along the walk) and the walk's seconds, as priced. */
    exp?: number;
    secs?: number;
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
    /** HealItems: the items still to use, the wait after the last use, and whether the wait at our tower is on. */
    uses?: HealItem[];
    useUntil?: number;
    useMod?: string;
    useHp?: number;
    tree?: number;
    itemHeal?: boolean;
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
    /** An over-budget read held only by the numbers (RetreatOdds) has been logged as ph=stay since the read last fell under. */
    stayLogged?: boolean;
    read?: Threat.Read;
    readAt?: number;
    orderAt?: number;
    orderTo?: Vector;
    plainAt?: number;
    drill?: DrillRep;
    band?: string;
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

/** An enemy tower whose reach holds `bot` and that is attacking it now or hit it in the last half second. */
export function TowerOnUs(bot: Unit): Unit | undefined {
    const enemy = enemyOf(bot.GetTeam());
    const br = bot.GetBoundingRadius();
    for (const id of TOWER_IDS) {
        const tw = GetTower(enemy, id);
        if (!valid(tw)) continue;
        // Both signals outlast the reach: a tower keeps us as its target and the damage flag lasts 0.5 s after we step out,
        // which restarted an episode that had just ended at the reach's edge (drills rtchase3, rtchase4).
        if (GetUnitToUnitDistance(bot, tw) > WorldFacts.TowerReach(tw, Threat.SETTINGS.TowerReach) + br) continue;
        if (tw.GetAttackTarget() === bot || bot.WasRecentlyDamagedByTower(0.5)) return tw;
    }
    return undefined;
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
    st.read = Threat.Read(bot, here, here, SETTINGS.Horizon, { engagedWindow: SETTINGS.EngagedWindow });
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
        // Past Arrive as well: arriving within Arrive of the edge point must already be out of the reach (rtchase3 chained there).
        const reach = WorldFacts.TowerReach(tw, Threat.SETTINGS.TowerReach) + SETTINGS.Arrive + SETTINGS.TowerClear;
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

/** Whether our lane front of the hero's lane is nearer than our fountain: going back costs less walk than going on. */
function laneNearer(bot: Unit, here: Vector): boolean {
    const front = GetLaneFrontLocation(bot.GetTeam(), bot.GetAssignedLane() as Lane, 0);
    return front !== undefined && dist(here, front) < dist(here, Fountain(bot.GetTeam()));
}

/** Whether a healing item is held in the inventory (slots 0-5). */
function regenHeld(bot: Unit): boolean {
    for (const name of SETTINGS.RegenItems) {
        const slot = bot.FindItemSlot(name);
        if (slot >= 0 && slot <= 5) return true;
    }
    return false;
}

/**
 * The least-cost anchor (exposed route points plus the walk's seconds per SecsPerCost, less RegenCredit on a tower anchor while
 * a healing item is held; ties to the shorter), the next-best's cost, the least exposure on any anchor (the route around) and
 * whether regen is held.
 */
function chooseAnchor(bot: Unit, why: Why): [Anchor, number | undefined, number, boolean] {
    const units = enemyUnits(bot);
    const here = bot.GetLocation();
    const list = anchorsOf(bot, why);
    const regen = regenHeld(bot);
    const speed = math.max(100, bot.GetCurrentMovementSpeed());
    let minExp = math.huge;
    for (const a of list) {
        a.exp = routeCost(bot, here, a.at, units);
        a.secs = a.len / speed;
        minExp = math.min(minExp, a.exp);
        const credit = regen && a.kind === "tower" ? SETTINGS.RegenCredit : 0;
        a.cost = math.floor((a.exp + a.secs / SETTINGS.SecsPerCost - credit) * 10 + 0.5) / 10;
    }
    list.sort((a, b) => (a.cost !== b.cost ? a.cost - b.cost : a.len - b.len));
    return [list[0], list[1]?.cost, minExp, regen];
}

function anchorPoint(a: Anchor): Vector {
    return a.ally !== undefined && valid(a.ally) ? a.ally.GetLocation() : a.at;
}

// ------------------------------------------------------------------------------------------------------------- heal items

/**
 * HealItems: the first set in HealSets whose items are all usable now (a tango with a tree near, faerie fire with no salve, no
 * buff already running for an item) and restore HP to HealBack; on one, the anchor becomes our nearest tower behind us.
 */
/**
 * Enemy heroes who can reach `bot` within HealItemHorizon, seen or just out of sight: items wait for none. Also the nearest
 * enemy hero's last sighting (distance, seconds since), for the log.
 */
function itemReach(bot: Unit): LuaMultiReturn<[number, number | undefined, number | undefined]> {
    const s = SETTINGS;
    const t = Threat.SETTINGS;
    const here = bot.GetLocation();
    const read = Threat.Read(bot, here, here, s.HealItemHorizon);
    let n = read.reach.length;
    let near: number | undefined;
    let tss: number | undefined;
    for (let pid = 0; pid <= 23; pid++) {
        const team = GetTeamForPlayer(pid);
        if (team === bot.GetTeam() || (team !== Team.Radiant && team !== Team.Dire) || !IsHeroAlive(pid)) continue;
        const info = GetHeroLastSeenInfo(pid)[0];
        if (info === undefined) continue;
        const d = dist(info.location, here);
        if (near === undefined || d < near) {
            near = d;
            tss = info.time_since_seen;
        }
        if (read.reach.includes(pid) || info.time_since_seen <= 0.1 || info.time_since_seen > t.MissingAfter) continue;
        if (d <= t.MissingSpeed * (info.time_since_seen + s.HealItemHorizon) + s.HealItemUnseenMargin) n++;
    }
    return $multi(n, near, tss);
}

function planItems(bot: Unit, ep: Episode): void {
    const s = SETTINGS;
    const max = math.max(1, bot.GetMaxHealth());
    const need = math.ceil(s.HealBack * max - bot.GetHealth());
    const here = bot.GetLocation();
    const salveHeld = ItemUse.Usable(bot, HEAL_ITEM.salve.name) !== undefined;
    const tree = ItemUse.TangoTree(bot, s.HealTree);
    const got: Partial<Record<HealItem, number>> = {};
    for (const k of Object.keys(HEAL_ITEM) as HealItem[]) {
        const it = ItemUse.Usable(bot, HEAL_ITEM[k].name);
        if (it === undefined) continue;
        const mod = HEAL_ITEM[k].modifier;
        if (mod !== undefined && bot.HasModifier(mod)) continue;
        if ((k === "tango" || k === "tango_single") && tree === undefined) continue;
        if (k === "fire" && salveHeld) continue;
        got[k] = ItemUse.HpRestore(it);
    }
    let set: HealItem[] | undefined;
    let restore = 0;
    for (const cand of s.HealSets) {
        // "tango" in a pair stands for either tango, the single first.
        const items = cand.map((k): HealItem => (cand.length > 1 && k === "tango" && got.tango_single !== undefined ? "tango_single" : k));
        if (!items.every((k) => got[k] !== undefined)) continue;
        const sum = items.reduce((a, k) => a + (got[k] ?? 0), 0);
        if (sum >= need) {
            set = items;
            restore = sum;
            break;
        }
    }
    const tower = nearestTowerBehind(bot);
    const [reachN, near, tss] = itemReach(bot);
    const skip = !laneNearer(bot, here) ? "fountain" : reachN > 0 ? "reach" : Object.keys(got).length === 0 ? "none" : set === undefined ? "short" : tower === undefined ? "no-tower" : undefined;
    Telemetry.Event("retreat", [
        ["ph", "items"],
        ["pid", bot.GetPlayerID()],
        ["ep", ep.id],
        ["need", need],
        ["held", (Object.keys(got) as HealItem[]).join(",") || "-"],
        ["set", skip === undefined && set !== undefined ? set.join(",") : "-"],
        ["got", math.floor(restore)],
        ["tree", tree !== undefined],
        ["skip", skip ?? "-"],
        ["ed", near !== undefined ? math.floor(near) : -1],
        ["ets", tss !== undefined ? r2(tss) : -1],
    ]);
    if (skip !== undefined || set === undefined || tower === undefined) return;
    // A tango first, while its tree is the one found here; the others are immediate.
    ep.uses = set.slice().sort((a, b) => (b.startsWith("tango") ? 1 : 0) - (a.startsWith("tango") ? 1 : 0));
    ep.tree = tree;
    ep.itemHeal = true;
    const p = standPoint(tower, bot.GetTeam());
    ep.anchor = { kind: "tower", at: p, cost: ep.anchor.cost, len: dist(here, p) };
}

/** HealItems: the wait at our tower ends, and the walk home resumes, when a hero reaches us or the items are spent without a `healed` end. */
function itemHealOn(bot: Unit, ep: Episode, r: Threat.Read, now: number): void {
    const spent = (ep.uses === undefined || ep.uses.length === 0) && (ep.useUntil === undefined || now >= ep.useUntil)
        && !bot.HasModifier("modifier_tango_heal") && !bot.HasModifier("modifier_flask_healing");
    const [reachN] = itemReach(bot);
    const why = r.reach.length > 0 || reachN > 0 ? "reach" : spent ? "spent" : undefined;
    if (why === undefined) return;
    ep.itemHeal = false;
    ep.uses = undefined;
    const f = Fountain(bot.GetTeam());
    ep.anchor = { kind: "fountain", at: f, cost: ep.anchor.cost, len: dist(bot.GetLocation(), f) };
    Telemetry.Event("retreat", [["ph", "items_off"], ["pid", bot.GetPlayerID()], ["ep", ep.id], ["skip", why], ["hp", r2(hpShare(bot))]]);
}

/** HealItems, from Think: the next use, or true while the last one's wait holds every other order. */
function useItems(bot: Unit, st: HeroState, ep: Episode, now: number): boolean {
    if (ep.useUntil !== undefined) {
        const shown = ep.useMod !== undefined ? bot.HasModifier(ep.useMod) : bot.GetHealth() > (ep.useHp ?? 0);
        if (now < ep.useUntil && !shown) return true;
        ep.useUntil = undefined;
    }
    const k = ep.uses?.shift();
    if (k === undefined) return false;
    const item = ItemUse.Usable(bot, HEAL_ITEM[k].name);
    Telemetry.Event("retreat", [["ph", "use"], ["pid", bot.GetPlayerID()], ["ep", ep.id], ["set", k], ["skip", item === undefined ? "gone" : "-"], ["hp", r2(hpShare(bot))]]);
    if (item === undefined) return false;
    ep.useUntil = now + SETTINGS.HealUseWait;
    ep.useMod = HEAL_ITEM[k].modifier;
    ep.useHp = bot.GetHealth();
    st.orderTo = undefined;
    if (k === "fire") ItemUse.UseNoTarget(bot, item);
    else if (k === "salve") ItemUse.UseOnSelf(bot, item);
    else if (ep.tree !== undefined) ItemUse.UseOnTree(bot, item, ep.tree);
    return true;
}

function nearestTowerBehind(bot: Unit): Unit | undefined {
    let best: Unit | undefined;
    let bestD = math.huge;
    for (const t of ownTowersBehind(bot)) {
        const d = GetUnitToUnitDistance(bot, t);
        if (d < bestD) {
            best = t;
            bestD = d;
        }
    }
    return best;
}

// ---------------------------------------------------------------------------------------------------------------- episodes

function start(bot: Unit, st: HeroState, why: Why, r: Threat.Read, budget: number, purp: string, spot?: string, rep?: number): void {
    const now = DotaTime();
    const [anchor, alt, minExp, regen] = chooseAnchor(bot, why);
    episodes++;
    const hp = hpShare(bot);
    st.ep = { id: episodes, start: now, why, budget, anchor, hp0: hp, lastHp: bot.GetHealth(), dmgh: 0, twr: false, wave: false };
    st.overSince = undefined;
    if (why === "heal" && Ours.On("HealItems") && Ours.On("HealStop")) planItems(bot, st.ep);
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
        ["al", r.allies],
        ["burst", r2(r.burst)],
        ["eng", r.eng.length],
        ["unp", unpaid(bot, r)],
        ["tower", r.tower],
        ["esc", r.reach.length > 0 ? r.escape : undefined],
        ["budget", r2(budget)],
        ["purp", purp],
        ["anchor", anchor.kind],
        ["cost", anchor.cost],
        ["alt", alt],
        ["exp", anchor.exp],
        ["minexp", minExp],
        ["regen", regen],
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
    if (ep.why === "heal") {
        if (at && hpShare(bot) >= s.HealUntil) return "anchor";
        if (Ours.On("HealStop") && hpShare(bot) >= s.HealBack && r.reach.length === 0 && r.threat < ep.budget - s.ExitBand && laneNearer(bot, here)) return "healed";
        if (ep.itemHeal === true) itemHealOn(bot, ep, r, now);
        return undefined;
    }
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
    // D2: nobody can reach us, so the danger has gone and the episode stops here, wherever the walk is. The dwell is for a read
    // that dips under the band while a hero is still in reach (h2hretreat1: the dwell after the last chaser left reach was most
    // of D2's high-HP retreat seconds).
    if (r.reach.length === 0) return "gone";
    ep.underSince = ep.underSince ?? now;
    return now - ep.underSince >= s.ExitDwell ? "safe" : undefined;
}

/**
 * RetreatOdds (D24): the heroes hitting us (the read's `eng`) with none of our lane creeps within creep aggro of them. Our
 * creeps turn on an enemy hero that attacks us within that radius, so one standing outside it hits us for free: the hold
 * never wins anything there, since our hero does not hit back (h2hevenfight1: held seconds hit an enemy hero 3-8% of the time).
 */
function unpaid(bot: Unit, r: Threat.Read): number {
    if (r.eng.length === 0) return 0;
    const radius = LaneFightConfig.Settings().CreepAggroRadius;
    const ours = (bot.GetNearbyLaneCreeps(1600, false) ?? []).filter((c) => valid(c) && c.IsAlive());
    let n = 0;
    for (const h of bot.GetNearbyHeroes(1600, true, BotMode.None) ?? []) {
        if (!valid(h) || !r.eng.includes(h.GetPlayerID())) continue;
        const at = h.GetLocation();
        if (!ours.some((c) => dist(c.GetLocation(), at) <= radius)) n++;
    }
    return n;
}

/** The leave rule: lethal, a tower on us or the heal floor at once; over budget for `Profile.ThreatHold`. */
function leaveWhy(bot: Unit, st: HeroState, r: Threat.Read, budget: number, now: number): Why | undefined {
    if (r.band === "lethal") return "lethal";
    if (TowerOnUs(bot) !== undefined) return "tower";
    if (hpShare(bot) < SETTINGS.HealFloor && r.reach.length === 0) return "heal";
    if (r.threat <= budget) {
        st.overSince = undefined;
        st.stayLogged = undefined;
        return undefined;
    }
    // D1 leaves when more enemy heroes than we have can reach us (the hero itself counts on our side). A fight they do not
    // outnumber is D24's while we are not in danger of dying: their burst under EvenBurst of our HP, our HP at EvenHp or more.
    // The read's allies are the heroes not in retreat who can reach us within its horizon.
    const even = r.reach.length <= r.allies + 1 && r.burst < SETTINGS.EvenBurst && hpShare(bot) >= SETTINGS.EvenHp;
    if (Ours.On("RetreatOdds") && even && unpaid(bot, r) === 0) {
        st.overSince = undefined;
        if (st.stayLogged !== true) {
            st.stayLogged = true;
            Telemetry.Event("retreat", [
                ["ph", "stay"], ["pid", bot.GetPlayerID()], ["thr", r2(r.threat)], ["band", r.band], ["reach", r.reach.length],
                ["al", r.allies], ["burst", r2(r.burst)], ["eng", r.eng.length], ["budget", r2(budget)], ["hp", r2(hpShare(bot))],
            ]);
        }
        return undefined;
    }
    st.overSince = st.overSince ?? now;
    return now - st.overSince >= Profile.ThreatHold(bot) ? "threat" : undefined;
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
    if (r.band !== st.band) {
        st.band = r.band;
        Telemetry.Event("retreat", [
            ["ph", "read"], ["pid", bot.GetPlayerID()], ["band", r.band], ["thr", r2(r.threat)], ["reach", r.reach.length],
            ["burst", r2(r.burst)], ["eng", r.eng.length], ["tower", r.tower], ["esc", r.escape], ["budget", budget], ["hp", r2(hpShare(bot))],
            ["crp", bot.WasRecentlyDamagedByCreep(1)],
        ]);
    }
    // retreat-heal: the chase drops the cast to the drill's HP before any leave, so the heal walk is forced.
    if (Drill.RetreatHeld(bot, hpShare(bot))) return 0;
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
        if (st.ep.itemHeal === true && useItems(bot, st, st.ep, now)) return;
        moveTo(bot, st, anchorPoint(st.ep.anchor), now);
        return;
    }
    // A hero we do not own walks to the fountain, as Valve's walk does: OHA also retreats for mana near base (botMP < 0.4) and
    // holds until it refills, which a tower stand point never does (review 10/11/2026 of 1eacd10e, high).
    const [kind, p]: [string, Vector] = RetreatState.Owns(bot) ? plainTarget(bot) : ["fountain", Fountain(bot.GetTeam())];
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

/**
 * HealItems: OHA's item code (ItemUsageComplement, roam's tango) leaves our heal items alone on a hero our retreat owns while
 * a heal episode runs, or under the heal floor (where one starts; faerie fire only with nobody in reach): the heal start's plan decides their
 * use, and a walk home keeps them. hi1: OHA drank the planned salve the frame our episode started (rep 2), and in the second
 * between a `gone` end and the heal start (rep 5). In a fight OHA's salve and faerie fire stay. Reads the cached read only.
 */
export function HoldsItem(bot: Unit, name: string): boolean {
    if (!Ours.On("HealItems") || !Ours.On("HealStop") || !RetreatState.Owns(bot)) return false;
    if (!(Object.keys(HEAL_ITEM) as HealItem[]).some((k) => HEAL_ITEM[k].name === name)) return false;
    const st = states[bot.GetPlayerID()];
    if (st?.ep !== undefined) return st.ep.why === "heal";
    if (hpShare(bot) >= SETTINGS.HealFloor) return false;
    // OHA drinks a salve with no enemy within 900, before our read lets nobody reach us within its horizon (hi2 rep 1: 0.3 s
    // ahead of the heal start); its salve and tango never fire in a fight, so they are held under the floor whatever the reach.
    // Faerie fire, a fight's burst, only once nobody can reach us.
    if (name !== HEAL_ITEM.fire.name) return true;
    return st?.read !== undefined && st.read.reach.length === 0;
}

/** mode_farm_generic: none of ShouldRun's runs apply to a hero our retreat owns. */
export function Owns(bot: Unit): boolean {
    return RetreatState.Owns(bot);
}
