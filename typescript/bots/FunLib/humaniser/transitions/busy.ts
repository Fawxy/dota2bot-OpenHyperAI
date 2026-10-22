/**
 * Lane safety and laning-phase transitions (task 12): "is this bot busy" and "can its lane spare it".
 * Both have a pure truth-table core and a thin adapter that reads the live state. Rotations (task 4)
 * are gated on these; later tasks read them too.
 */
import { BotMode, Unit, Vector } from "bots/ts_libs/dota";
import * as LaneState from "bots/FunLib/humaniser/lane_state";
import * as LaneRoles from "bots/FunLib/humaniser/lane_roles";
import * as LanePlan from "bots/FunLib/humaniser/lane_plan";
import * as LaneHooks from "bots/FunLib/humaniser/lane_hooks";
import * as CampJobs from "bots/FunLib/humaniser/camp_jobs";
import * as Orders from "bots/FunLib/humaniser/orders";
import * as Pings from "bots/FunLib/humaniser/pings";
import * as Settings from "bots/FunLib/humaniser/transitions/settings";

export interface BusyInput {
    order: boolean;
    campJob: boolean;
    fighting: boolean;
    retreating: boolean;
    /** Fractions of max. */
    hp: number;
    mana: number;
    dead: boolean;
    /** Absolute game time of respawn, when dead. */
    respawnAfter?: number;
    /** Absolute game time by which the bot must be available. */
    windowEnd: number;
    carrying: boolean;
    humanPingOnLane: boolean;
}

export function IsBusyPure(i: BusyInput): LuaMultiReturn<[boolean, string]> {
    const cfg = Settings.Get();
    if (i.order) return $multi(true, "order");
    if (i.campJob) return $multi(true, "job");
    if (i.fighting) return $multi(true, "fight");
    if (i.retreating) return $multi(true, "retreat");
    // A dead bot reads as 0 hp and mana, so death is judged before them.
    if (i.dead && (i.respawnAfter === undefined || i.respawnAfter > i.windowEnd)) return $multi(true, "dead");
    if (!i.dead && i.hp < cfg.BusyHP) return $multi(true, "hp");
    if (!i.dead && i.mana < cfg.BusyMana) return $multi(true, "mana");
    if (i.carrying) return $multi(true, "item");
    if (i.humanPingOnLane) return $multi(true, "ping");
    return $multi(false, "");
}

export interface SpareEnemy {
    visible: boolean;
    sinceSeen: number;
    inKillPosition: boolean;
}

export interface SpareInput {
    eqPos: number;
    plan: LanePlan.LanePlan;
    coreHealthy: boolean;
    partnerHP: number;
    partnerCreepAggro: number;
    enemies: SpareEnemy[];
    enemyTpIncoming: boolean;
    humanAskedStay: boolean;
    strict: boolean;
    enemyNearPartner: boolean;
}

export function LaneCanSparePure(i: SpareInput): LuaMultiReturn<[boolean, string]> {
    const cfg = Settings.Get();
    if (i.humanAskedStay) return $multi(false, "asked to stay");
    if (i.partnerHP < (i.strict ? cfg.Pos5PartnerHP : cfg.SparePartnerHP)) return $multi(false, "partner hp");
    if (i.eqPos < cfg.SpareEq && !(i.plan === "FREEZE" && i.coreHealthy)) return $multi(false, "lane pushed");
    if (i.partnerCreepAggro >= cfg.SpareCreepAggro) return $multi(false, "creep aggro");
    if (i.enemyTpIncoming) return $multi(false, "enemy tp");
    if (i.strict && i.enemyNearPartner) return $multi(false, "enemy near");
    for (const e of i.enemies) {
        if (e.inKillPosition) return $multi(false, "kill position");
        // A laner out of sight for long may be rotating or about to gank.
        if (!e.visible && e.sinceSeen > cfg.SpareSeenWithin) return $multi(false, "enemy missing");
    }
    return $multi(true, "ok");
}

let tpProbe: ((this: void, bot: Unit) => boolean) | undefined;

/** Task 6 registers the enemy-teleport reader here. */
export function SetTpProbe(fn: (this: void, bot: Unit) => boolean): void {
    tpProbe = fn;
}

function dist2D(a: Vector, b: Vector): number {
    const dx = a.x - b.x;
    const dy = a.y - b.y;
    return math.sqrt(dx * dx + dy * dy);
}

function frac(cur: number, max: number): number {
    return max > 0 ? cur / max : 1;
}

function isFightMode(mode: number): boolean {
    return (
        mode === BotMode.Attack ||
        mode === BotMode.Roam ||
        mode === BotMode.TeamRoam ||
        mode === BotMode.DefendTowerTop ||
        mode === BotMode.DefendTowerMid ||
        mode === BotMode.DefendTowerBot ||
        mode === BotMode.DefendAlly
    );
}

export function IsBusy(bot: Unit, windowEnd: number): LuaMultiReturn<[boolean, string]> {
    const cfg = Settings.Get();
    const alive = bot.IsAlive();
    const mode = bot.GetActiveMode();
    const team = bot.GetTeam();
    return IsBusyPure({
        order: Orders.GetFor(bot) !== undefined,
        campJob: CampJobs.Active(bot) || CampJobs.UpcomingWithin(bot, cfg.BusyJobLead),
        fighting: isFightMode(mode) || LaneHooks.IsBusyByProbe(bot),
        retreating: mode === BotMode.Retreat,
        hp: alive ? frac(bot.GetHealth(), bot.GetMaxHealth()) : 0,
        mana: alive ? frac(bot.GetMana(), bot.GetMaxMana()) : 0,
        dead: !alive,
        respawnAfter: alive ? undefined : DotaTime() + bot.GetRespawnTime(),
        windowEnd,
        // Placeholder until task 13.
        carrying: false,
        humanPingOnLane: Pings.HumanPingNear(team, GetLaneFrontLocation(team, bot.GetAssignedLane(), 0), cfg.LanePingRadius, cfg.HumanPingWindow),
    });
}

export function LaneCanSpare(bot: Unit, strict: boolean): LuaMultiReturn<[boolean, string]> {
    const cfg = Settings.Get();
    const s = LaneState.ForBot(bot);
    if (s === undefined) return $multi(false, "no lane");
    const partner = LaneRoles.Partner(bot, s);
    if (partner === undefined) return $multi(false, "solo");
    const enemies = LaneState.Enemies(bot, s.lane);
    const reading = LaneRoles.ReadPartner(bot, s, enemies);
    if (reading === undefined) return $multi(false, "solo");

    const partnerLoc = partner.unit.GetLocation();
    const partnerLow = reading.hp < cfg.SpareKillHP;
    const spareEnemies: SpareEnemy[] = [];
    let near = false;
    for (const e of enemies) {
        if (dist2D(e.location, s.frontLoc) > cfg.SpareLaneRadius) continue;
        let kill = false;
        if (e.visible && e.unit !== undefined) {
            const d = dist2D(e.location, partnerLoc);
            kill = partnerLow && d <= e.unit.GetAttackRange() + cfg.SpareKillMargin;
            if (d <= cfg.Pos5EnemyRadius) near = true;
        }
        spareEnemies.push({ visible: e.visible, sinceSeen: e.timeSinceSeen, inKillPosition: kill });
    }

    let aggro = 0;
    for (const creep of s.enemy.units) {
        const target = creep.GetAttackTarget();
        if (target !== undefined && target !== null && target.IsHero() && target.GetPlayerID() === partner.pid) aggro++;
    }

    const coreHP = LaneRoles.RoleIn(bot, s) === "support" ? reading.hp : frac(bot.GetHealth(), bot.GetMaxHealth());
    const asked =
        Orders.GetAcceptedForLane(bot, "LANE_NOPULL", s.lane) !== undefined ||
        Orders.GetAcceptedForLane(bot, "LANE_HANDSOFF", s.lane) !== undefined ||
        Pings.HumanPingNear(s.team, s.frontLoc, cfg.LanePingRadius, cfg.HumanPingWindow);

    return LaneCanSparePure({
        eqPos: s.eqPos,
        plan: LanePlan.View(bot, s).plan,
        coreHealthy: coreHP >= cfg.SparePartnerHP,
        partnerHP: reading.hp,
        partnerCreepAggro: aggro,
        enemies: spareEnemies,
        enemyTpIncoming: tpProbe !== undefined && tpProbe(bot),
        humanAskedStay: asked,
        strict,
        enemyNearPartner: near,
    });
}
