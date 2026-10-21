/**
 * Duo-lane partnership rules (task 07, "coordinate, don't collide"): roles, the single-actor aggro
 * window, camp-job ownership, partner safety and covering an absent core. Every cross-bot answer is
 * derived from observed state (positions, creep targets, positions in the draft) so it agrees even when
 * each bot has its own module instance; the in-module claims are only a fast path.
 */
import { Unit, Vector } from "bots/ts_libs/dota";
import * as LaneConfig from "bots/FunLib/humaniser/lane_config";
import * as LaneState from "bots/FunLib/humaniser/lane_state";
import * as HDebug from "bots/FunLib/humaniser/debug";

export type LaneRole = "core" | "support" | "solo";

interface Claim {
    pid: number;
    at: number;
}

interface Cover {
    absent: boolean;
    cover: boolean;
}

let claims: Record<string, Claim> = {};
let lastDraw: Record<number, number> = {};
let needSince: Record<number, number> = {};
let covers: Record<number, Cover> = {};
let doubleDraws: Record<number, { stamp: number; ok: boolean }> = {};
/** Partner HP over the last Timing.PartnerHPWindow, by partner pid, sampled whenever a support reads its partner. */
let hpSamples: Record<number, { at: number; hp: number }[]> = {};
/** When the dive condition began, by the reading support's pid. */
let diveSince: Record<number, number> = {};

export function ResetCache(): void {
    claims = {};
    lastDraw = {};
    needSince = {};
    covers = {};
    doubleDraws = {};
    hpSamples = {};
    diveSince = {};
}

function dist2D(a: Vector, b: Vector): number {
    const dx = a.x - b.x;
    const dy = a.y - b.y;
    return math.sqrt(dx * dx + dy * dy);
}

function positionOf(h: LaneState.LaneHero): number {
    return h.position ?? 0;
}

function selfIn(bot: Unit, s: LaneState.LaneSnapshot): LaneState.LaneHero | undefined {
    const pid = bot.GetPlayerID();
    for (const h of s.allies) if (h.pid === pid) return h;
    return undefined;
}

function others(bot: Unit, s: LaneState.LaneSnapshot): LaneState.LaneHero[] {
    const pid = bot.GetPlayerID();
    const result: LaneState.LaneHero[] = [];
    for (const h of s.allies) if (h.alive && h.assigned && h.pid !== pid) result.push(h);
    return result;
}

/** Lowest-position core of the lane, ties by lower pid. `includeDead` serves CoreAbsent only. */
function coreOf(s: LaneState.LaneSnapshot, includeDead: boolean, exclude?: number): LaneState.LaneHero | undefined {
    let best: LaneState.LaneHero | undefined;
    for (const h of s.allies) {
        if (!h.assigned || h.pid === exclude || (!h.alive && !includeDead)) continue;
        const pos = h.position;
        if (pos === undefined || pos < 1 || pos > 3) continue;
        if (best === undefined || pos < best.position! || (pos === best.position && h.pid < best.pid)) best = h;
    }
    return best;
}

export function RoleIn(bot: Unit, s: LaneState.LaneSnapshot): LaneRole {
    if (others(bot, s).length === 0) return "solo";
    const own = selfIn(bot, s)?.position ?? LaneConfig.PositionOf(bot);
    return own !== undefined && own >= 4 ? "support" : "core";
}

export function Partner(bot: Unit, s: LaneState.LaneSnapshot): LaneState.LaneHero | undefined {
    const role = RoleIn(bot, s);
    if (role === "solo") return undefined;
    if (role === "support") return coreOf(s, false, bot.GetPlayerID());
    let best: LaneState.LaneHero | undefined;
    for (const h of others(bot, s)) {
        if (positionOf(h) < 4) continue;
        if (best === undefined || positionOf(h) > positionOf(best) || (positionOf(h) === positionOf(best) && h.pid < best.pid)) best = h;
    }
    return best;
}

function isEnemyLaneCreep(target: Unit | null | undefined, ownTeam: number): target is Unit {
    return target !== null && target !== undefined && target.GetTeam() !== ownTeam && LaneState.IsLaneCreepName(target.GetUnitName());
}

export function CoreBusy(core: LaneState.LaneHero, _now: number): boolean {
    if (!core.alive) return false;
    const cfg = LaneConfig.Settings().Thresholds;
    if (core.hp < cfg.CoreBusyHP) return true;
    const target = core.unit.GetAttackTarget();
    return isEnemyLaneCreep(target, core.unit.GetTeam()) && target.GetHealth() <= core.unit.GetAttackDamage() * cfg.CoreBusyDamageMult;
}

/** Records when this bot's need for an aggro draw began; keeps the first stamp until ClearNeed. */
export function NoteNeed(bot: Unit, now: number): void {
    const pid = bot.GetPlayerID();
    if (needSince[pid] === undefined) needSince[pid] = now;
}

export function ClearNeed(bot: Unit): void {
    delete needSince[bot.GetPlayerID()];
}

function claimKey(s: LaneState.LaneSnapshot): string {
    return `${s.team}:${s.lane}`;
}

export function MayDrawAggro(bot: Unit, s: LaneState.LaneSnapshot): LuaMultiReturn<[boolean, string]> {
    const cfg = LaneConfig.Settings();
    const pid = bot.GetPlayerID();
    const now = DotaTime();
    const window = cfg.Timing.AggroWindow;

    // The double-draw mistake is rolled once per ally draw, not per call. Creeps chasing the ally keep refreshing
    // its stamp, so stamps closer together than the window count as the same draw.
    let stamp: number | undefined;
    for (const [other, at] of pairs(s.lastAllyAggroAt)) {
        if (other !== pid && now - (at as number) < window && (stamp === undefined || (at as number) > stamp)) stamp = at as number;
    }
    const claim = claims[claimKey(s)];
    if (claim !== undefined && claim.pid !== pid && now - claim.at < window && (stamp === undefined || claim.at > stamp)) stamp = claim.at;
    if (stamp !== undefined) {
        let dd = doubleDraws[pid];
        if (dd === undefined || stamp - dd.stamp >= window) {
            dd = { stamp, ok: LaneConfig.Roll(LaneConfig.Curve("DoubleDraw", LaneConfig.SkillOf(bot))) };
            doubleDraws[pid] = dd;
            if (dd.ok) HDebug.Log("lane", `pid=${pid} mistake: double-draw`);
        } else if (stamp > dd.stamp) {
            dd.stamp = stamp;
        }
        if (dd.ok) return $multi(true, "mistake: double-draw");
        return $multi(false, "wait: ally-aggro");
    }

    const own = lastDraw[pid];
    if (own !== undefined && now - own < cfg.Timing.AggroCooldown) return $multi(false, "wait: cooldown");

    const self = selfIn(bot, s);
    if (RoleIn(bot, s) === "core" && self !== undefined) {
        const partner = Partner(bot, s);
        if (partner !== undefined && partner.isBot && partner.alive && partner.distToFront <= cfg.Thresholds.SupportNearFront) {
            if (CoreBusy(self, now)) return $multi(false, "yield: support");
            if (needSince[pid] === undefined) needSince[pid] = now;
            if (now - needSince[pid] < cfg.Timing.CoreYieldStagger) return $multi(false, "yield: stagger");
        }
    }
    return $multi(true, "ok");
}

export function NoteAggroDraw(bot: Unit, s: LaneState.LaneSnapshot): void {
    const pid = bot.GetPlayerID();
    const now = DotaTime();
    claims[claimKey(s)] = { pid, at: now };
    lastDraw[pid] = now;
}

export function CampJobOwner(s: LaneState.LaneSnapshot): number | undefined {
    let best: LaneState.LaneHero | undefined;
    for (const h of s.allies) {
        if (!h.alive) continue;
        if (!h.isBot) {
            if (positionOf(h) >= 4) return undefined;
            continue;
        }
        if (!h.assigned) continue;
        if (best === undefined || positionOf(h) > positionOf(best) || (positionOf(h) === positionOf(best) && h.pid < best.pid)) best = h;
    }
    return best?.pid;
}

function visibleWithin(enemies: LaneState.LaneEnemy[], loc: Vector, radius: number): number {
    let n = 0;
    for (const e of enemies) if (e.visible && dist2D(e.location, loc) <= radius) n++;
    return n;
}

/** Start gate: the support does not leave while the partner is low or the enemy laners stand within PartnerDangerRadius. */
export function PartnerSafe(bot: Unit, s: LaneState.LaneSnapshot, enemies: LaneState.LaneEnemy[]): boolean {
    const partner = Partner(bot, s);
    if (partner === undefined) return true;
    const cfg = LaneConfig.Settings().Thresholds;
    if (partner.hp < cfg.PartnerMinHP) return false;
    return visibleWithin(enemies, partner.unit.GetLocation(), cfg.PartnerDangerRadius) < cfg.PartnerDangerEnemies;
}

export interface PartnerReading {
    pid: number;
    hp: number;
    /** Visible enemies within Thresholds.PartnerDangerRadius (the start gate's count). */
    near: number;
    /** Visible enemies within Radii.PartnerDive. */
    close: number;
    /** HP fraction the partner lost over the last Timing.PartnerHPWindow. */
    loss: number;
}

/** The partner's live state; also records its HP for `loss`, so call it every frame the reading matters. */
export function ReadPartner(bot: Unit, s: LaneState.LaneSnapshot, enemies: LaneState.LaneEnemy[]): PartnerReading | undefined {
    const partner = Partner(bot, s);
    if (partner === undefined) return undefined;
    const cfg = LaneConfig.Settings();
    const now = DotaTime();
    const maxHP = partner.unit.GetMaxHealth();
    const hp = maxHP > 0 ? partner.unit.GetHealth() / maxHP : 0;
    const kept: { at: number; hp: number }[] = [];
    let peak = hp;
    for (const sample of hpSamples[partner.pid] ?? []) {
        if (now - sample.at > cfg.Timing.PartnerHPWindow || sample.at > now) continue;
        kept.push(sample);
        if (sample.hp > peak) peak = sample.hp;
    }
    kept.push({ at: now, hp });
    hpSamples[partner.pid] = kept;
    const loc = partner.unit.GetLocation();
    return {
        pid: partner.pid,
        hp,
        near: visibleWithin(enemies, loc, cfg.Thresholds.PartnerDangerRadius),
        close: visibleWithin(enemies, loc, cfg.Radii.PartnerDive),
        loss: peak - hp,
    };
}

/**
 * Continue gate for a job already under way. In a two-lane the enemy laners stand around PartnerDangerRadius of the
 * core most of the time, so the start gate's count flips every few frames; once committed the support only turns back
 * when the partner is low (below PartnerBailHP, under the start gate's PartnerMinHP for hysteresis) or is being dived:
 * an enemy within PartnerDive while the partner keeps losing HP, for PartnerBailConfirm (the support's reaction).
 */
export function PartnerHolding(bot: Unit, s: LaneState.LaneSnapshot, enemies: LaneState.LaneEnemy[]): LuaMultiReturn<[boolean, string]> {
    const pid = bot.GetPlayerID();
    const r = ReadPartner(bot, s, enemies);
    const cfg = LaneConfig.Settings();
    if (r === undefined) {
        delete diveSince[pid];
        return $multi(true, "ok");
    }
    if (r.hp < cfg.Thresholds.PartnerBailHP) return $multi(false, "partner low-hp");
    if (r.close < 1 || r.loss < cfg.Thresholds.PartnerDiveLoss) {
        delete diveSince[pid];
        return $multi(true, "ok");
    }
    const now = DotaTime();
    const since = diveSince[pid] ?? now;
    diveSince[pid] = since;
    if (now - since < cfg.Timing.PartnerBailConfirm) return $multi(true, "ok");
    return $multi(false, "partner dived");
}

export function LaneStable(bot: Unit, enemies: LaneState.LaneEnemy[]): boolean {
    const cfg = LaneConfig.Settings().Thresholds;
    const maxHP = bot.GetMaxHealth();
    if (maxHP <= 0 || bot.GetHealth() / maxHP <= cfg.StableMinHP) return false;
    const loc = bot.GetLocation();
    for (const e of enemies) {
        if (!e.visible && e.timeSinceSeen > cfg.StableSeenWithin) continue;
        if (dist2D(e.location, loc) <= cfg.StableEnemyRadius) return false;
    }
    return true;
}

/** `committed`: the job is already running, so the partner check is PartnerHolding instead of the start gate. */
export function MayRunCampJob(bot: Unit, s: LaneState.LaneSnapshot, enemies: LaneState.LaneEnemy[], committed = false): LuaMultiReturn<[boolean, string]> {
    if (CampJobOwner(s) !== bot.GetPlayerID()) return $multi(false, "not-owner");
    if (!LaneConfig.InLaningPhase()) return $multi(false, "not-laning");
    if (RoleIn(bot, s) === "solo") {
        if (LaneConfig.SkillOf(bot) <= LaneConfig.Settings().Gates.SoloCampJob) return $multi(false, "solo: skill");
        if (!LaneStable(bot, enemies)) return $multi(false, "solo: unstable");
    } else if (committed) {
        return PartnerHolding(bot, s, enemies);
    } else if (!PartnerSafe(bot, s, enemies)) {
        return $multi(false, "partner unsafe");
    }
    return $multi(true, "ok");
}

export function CoreAbsent(s: LaneState.LaneSnapshot): boolean {
    const core = coreOf(s, true);
    if (core === undefined) return false;
    return !core.alive || core.distToFront > LaneConfig.Settings().Thresholds.CoreAbsentDist;
}

export function CoverAbsentCore(bot: Unit, s: LaneState.LaneSnapshot, _now: number): boolean {
    const pid = bot.GetPlayerID();
    let c = covers[pid];
    if (c === undefined) {
        c = { absent: false, cover: false };
        covers[pid] = c;
    }
    if (!CoreAbsent(s)) {
        c.absent = false;
        c.cover = false;
        return false;
    }
    if (!c.absent) {
        c.absent = true;
        c.cover = LaneConfig.Roll(LaneConfig.Curve("CoverAbsentCore", LaneConfig.SkillOf(bot)));
    }
    return c.cover;
}
