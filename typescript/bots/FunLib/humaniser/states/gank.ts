/**
 * `gank` state (team slice 11): planned rotations onto an enemy core in another lane, for the pos 4 (from level 2,
 * 1:30) and the mid (from level 5, 5:30), before 12:00. research/knowledge.md section 3: a gank goes only when the
 * three filters pass (our wave can be left, the target has setup on it or is low, we can be back within about a
 * wave), the target scores well (low HP, overextended on our half, an ally near it; minus its tower and its friends),
 * the bot approaches through a flank point off the lane line and pings the lane about 3 s before arriving. Targets
 * and commits scale with skill: a low-skill bot takes worse targets, walks straight down the lane and pings nothing.
 * research/replays.md: mid gets a rotation kill before 10:00 in 32% of pub games (first ~7:50), pos 4/5 18-22%.
 * The body is the SDK's `gank` verb; the host mode is roam (upstream OHA's own roam ganks stay as they are).
 */
import type * as Lib from "bots/FunLib/engine/tasks";
import { BotMode, Lane, Unit, UnitType, Vector } from "bots/ts_libs/dota";
import * as CampJobs from "bots/FunLib/humaniser/camp_jobs";
import * as Difficulty from "bots/FunLib/humaniser/difficulty";
import * as LaneConfig from "bots/FunLib/humaniser/lane_config";
import * as LaneHooks from "bots/FunLib/humaniser/lane_hooks";
import * as LaneState from "bots/FunLib/humaniser/lane_state";
import * as Orders from "bots/FunLib/humaniser/orders";
import * as Tasks from "bots/FunLib/humaniser/tasks";
import * as Telemetry from "bots/FunLib/humaniser/telemetry";
import * as Busy from "bots/FunLib/humaniser/transitions/busy";

export const NAME = "gank";

export const SETTINGS = {
    /** Score of a committed gank: above laning (0.5 + stickiness), below the job break. */
    Score: 0.75,
    /** Position -> earliest time and level. */
    From: { [2]: 330, [4]: 90 } as Record<number, number>,
    MinLevel: { [2]: 5, [4]: 2 } as Record<number, number>,
    Until: 720,
    MinHP: 0.6,
    MinMana: 0.4,
    /** Seconds between a bot's attempts, and attempts per bot before Until. */
    Cooldown: 60,
    MaxAttempts: 3,
    /** Exit filter: straight-line ETA (x PathFactor) at most this; a side-lane move costs about one wave. */
    MaxEta: 25,
    PathFactor: 1.2,
    /** Target score needed, lerped from skill 0 to 1: high skill waits for better targets. */
    Threshold: [1.0, 1.8],
    /** Chance to commit to a passing target, per target and Bucket seconds, lerped from skill. */
    Commit: [0.25, 0.55],
    Bucket: 20,
    /** From this skill up the approach goes through a flank point off the lane line, and the lane is pinged. */
    FlankSkill: 0.5,
    FlankOffset: 700,
    FlankAt: 0.6,
    TelegraphLead: 3,
    AllyRadius: 1400,
    EnemyRadius: 1200,
    TowerRadius: 900,
    /** Mid's wave filter: no enemy lane creep this close (the wave is shoved). */
    WaveRadius: 1200,
    LaneWidth: 1500,
    AbortHP: 0.4,
};

interface Attempt {
    pid: number;
    lane: Lane;
    score: number;
    left: number;
    engaged?: number;
    ended?: string;
}

const attempts: Record<number, Attempt | undefined> = {};
const counts: Record<number, number | undefined> = {};
const lastEnd: Record<number, number | undefined> = {};
const rolls: Record<string, boolean | undefined> = {};

export function ResetCache(): void {
    for (const t of [attempts, counts, lastEnd]) for (const [k] of pairs(t)) (t as any)[k] = undefined;
    for (const [k] of pairs(rolls)) rolls[k as string] = undefined;
}

const ENGAGE_FOR = 8;

/** The latest a body may still be engaging (its deadline plus engageFor), plus slack: past it the attempt is over. */
function maxAway(): number {
    return SETTINGS.MaxEta * 1.5 + 20 + ENGAGE_FOR + 5;
}

function lerp(r: number[], t: number): number {
    return r[0] + (r[1] - r[0]) * t;
}

function d2(a: Vector, b: Vector): number {
    return math.sqrt((a.x - b.x) ** 2 + (a.y - b.y) ** 2);
}

function laneOf(loc: Vector): Lane | undefined {
    let best: Lane | undefined;
    let bestD = SETTINGS.LaneWidth;
    for (const lane of [Lane.Top, Lane.Mid, Lane.Bot]) {
        const d = GetAmountAlongLane(lane, loc).distance;
        if (d < bestD) {
            bestD = d;
            best = lane;
        }
    }
    return best;
}

const heroCache: Record<string, { at: number; list: Unit[] } | undefined> = {};

/** GetUnitList per list once per frame (pre-flight M2: the scorer, commit check and target fn scan every frame). */
function heroes(list: UnitType): Unit[] {
    const now = DotaTime();
    // The lists are relative to the calling team.
    const key = `${GetTeam()}:${list}`;
    const c = heroCache[key];
    if (c !== undefined && c.at === now) return c.list;
    const fresh = GetUnitList(list);
    heroCache[key] = { at: now, list: fresh };
    return fresh;
}

function heroesNear(list: UnitType, loc: Vector, radius: number, except?: Unit): number {
    let n = 0;
    for (const u of heroes(list)) {
        if (u !== except && u.IsAlive() && !u.IsIllusion() && d2(u.GetLocation(), loc) <= radius) n++;
    }
    return n;
}

function visibleUnit(pid: number): Unit | undefined {
    for (const u of heroes(UnitType.EnemyHeroes)) if (u.GetPlayerID() === pid && !u.IsIllusion() && u.CanBeSeen() && u.IsAlive()) return u;
    return undefined;
}

function towerNear(target: Unit): boolean {
    return (target.GetNearbyTowers(SETTINGS.TowerRadius, false) ?? []).length > 0;
}

export interface Pick {
    pid: number;
    unit: Unit;
    lane: Lane;
    score: number;
    eta: number;
}

/** knowledge.md 3.3: the best visible enemy core in another lane, with its score; undefined when none qualifies. */
export function BestTarget(bot: Unit): Pick | undefined {
    const s = SETTINGS;
    const own = bot.GetAssignedLane();
    const speed = math.max(1, bot.GetCurrentMovementSpeed());
    let best: Pick | undefined;
    for (const e of LaneState.Enemies(bot, own)) {
        const u = e.visible ? e.unit : undefined;
        if (u === undefined || (e.position !== undefined && e.position > 3)) continue;
        const loc = u.GetLocation();
        const lane = laneOf(loc);
        if (lane === undefined || lane === own) continue;
        const eta = (d2(bot.GetLocation(), loc) * s.PathFactor) / speed;
        if (eta > s.MaxEta) continue;
        const hp = u.GetHealth() / math.max(1, u.GetMaxHealth());
        const setup = heroesNear(UnitType.AlliedHeroes, loc, s.AllyRadius, bot) > 0;
        // knowledge.md 3.2 setup filter: someone of ours to follow up with, or a target low enough to kill alone.
        if (!setup && hp >= 0.5) continue;
        let score = (1 - hp) * 2;
        if (GetAmountAlongLane(lane, loc).amount < 0.5) score += 1;
        if (setup) score += 1;
        score -= heroesNear(UnitType.EnemyHeroes, loc, s.EnemyRadius, u);
        if (towerNear(u)) score -= 2;
        if (best === undefined || score > best.score) best = { pid: e.pid, unit: u, lane, score, eta };
    }
    return best;
}

/** Why the bot may not start a gank now, else undefined (the cheap checks first). */
export function Gate(bot: Unit, now: number): string | undefined {
    const s = SETTINGS;
    const pos = LaneConfig.PositionOf(bot) ?? 0;
    const pid = bot.GetPlayerID();
    if (s.From[pos] === undefined) return "role";
    if (now < s.From[pos] || now > s.Until) return "window";
    if (bot.GetLevel() < s.MinLevel[pos]) return "level";
    if ((counts[pid] ?? 0) >= s.MaxAttempts) return "attempts";
    if (now - (lastEnd[pid] ?? -math.huge) < s.Cooldown) return "cooldown";
    if (!bot.IsAlive() || bot.GetHealth() / math.max(1, bot.GetMaxHealth()) < s.MinHP) return "hp";
    if (bot.GetMana() / math.max(1, bot.GetMaxMana()) < s.MinMana) return "mana";
    if (Orders.GetFor(bot) !== undefined) return "order";
    if (CampJobs.Active(bot) || LaneHooks.RotationDecided(bot) || LaneHooks.IsFightCommitting(bot)) return "busy";
    if (Busy.IsBusy(bot, now + s.MaxEta)[0]) return "busy";
    // knowledge.md 3.2 wave filter: a support needs a lane that can spare it; the mid shoves first.
    if (pos === 4 && !Busy.LaneCanSpare(bot, false)[0]) return "lane";
    if (pos === 2 && (bot.GetNearbyLaneCreeps(s.WaveRadius, true) ?? []).length > 0) return "wave";
    return undefined;
}

function rollFor(bot: Unit, pick: Pick, now: number): boolean {
    const key = `${bot.GetPlayerID()}:${pick.pid}:${math.floor(now / SETTINGS.Bucket)}`;
    if (rolls[key] === undefined) rolls[key] = LaneConfig.Roll(lerp(SETTINGS.Commit, LaneConfig.SkillOf(bot)));
    return rolls[key] === true;
}

const pending: Record<number, Pick | undefined> = {};

function score(bot: Unit): number | undefined {
    const pid = bot.GetPlayerID();
    const a = attempts[pid];
    const now = DotaTime();
    if (a !== undefined && a.ended === undefined) {
        // Kept by a preempt or a death past any chance of the gank: over, so the layer can leave the state.
        if (now - a.left <= maxAway()) return SETTINGS.Score;
        ended(bot, { success: false, reason: "timeout", message: "expired" }, { steps: 0 });
        return undefined;
    }
    if (Gate(bot, now) !== undefined) return undefined;
    const pick = BestTarget(bot);
    if (pick === undefined || pick.score < lerp(SETTINGS.Threshold, LaneConfig.SkillOf(bot))) return undefined;
    if (!rollFor(bot, pick, now)) return undefined;
    pending[pid] = pick;
    return SETTINGS.Score;
}

/** A point off the lane line on the way to the target: from the side away from the lane (through trees and fog). */
export function FlankPoint(from: Vector, target: Vector, lane: Lane): Vector {
    const s = SETTINGS;
    const dx = target.x - from.x;
    const dy = target.y - from.y;
    const len = math.max(1, math.sqrt(dx * dx + dy * dy));
    const mid = Vector(from.x + dx * s.FlankAt, from.y + dy * s.FlankAt, target.z);
    const px = (-dy / len) * s.FlankOffset;
    const py = (dx / len) * s.FlankOffset;
    const a = Vector(mid.x + px, mid.y + py, mid.z);
    const b = Vector(mid.x - px, mid.y - py, mid.z);
    return GetAmountAlongLane(lane, a).distance >= GetAmountAlongLane(lane, b).distance ? a : b;
}

function abortWhy(bot: Unit, target: () => Unit | undefined): string | undefined {
    const s = SETTINGS;
    if (bot.GetHealth() / math.max(1, bot.GetMaxHealth()) < s.AbortHP) return "low-hp";
    const here = bot.GetLocation();
    if (heroesNear(UnitType.EnemyHeroes, here, s.EnemyRadius) > heroesNear(UnitType.AlliedHeroes, here, s.EnemyRadius)) return "outnumbered";
    const t = target();
    if (t !== undefined && towerNear(t) && d2(here, t.GetLocation()) > bot.GetAttackRange() + 200) return "tower";
    return undefined;
}

function* body(bot: Unit, ctx: Lib.Ctx): Lib.TaskBody {
    const pid = bot.GetPlayerID();
    const now = DotaTime();
    let a = attempts[pid];
    if (a === undefined || a.ended !== undefined) {
        const pick = pending[pid];
        if (pick === undefined) return ctx.fail("no_target", "no-pick");
        a = { pid: pick.pid, lane: pick.lane, score: pick.score, left: now };
        attempts[pid] = a;
        counts[pid] = (counts[pid] ?? 0) + 1;
    }
    const attempt = a;
    // Dead heroes drop out of GetUnitList: the last handle seen stands for the target so the verb sees the kill.
    let last: Unit | undefined;
    const target = (): Unit | undefined => {
        const u = visibleUnit(attempt.pid);
        if (u !== undefined) last = u;
        else if (last !== undefined && !IsHeroAlive(attempt.pid)) return last;
        return u;
    };
    const t0 = target();
    if (t0 === undefined) return ctx.fail("interrupted", "escaped");
    const skill = ctx.skill();
    const flank = skill >= SETTINGS.FlankSkill;
    const path = flank ? [FlankPoint(bot.GetLocation(), t0.GetLocation(), attempt.lane) as unknown as Lib.Vec] : [];
    const eta = (GetUnitToUnitDistance(bot, t0) * SETTINGS.PathFactor) / math.max(1, bot.GetCurrentMovementSpeed());
    return yield* Tasks.Jobs()!.gank(
        bot as unknown as Lib.TaskUnit,
        {
            target: () => target() as unknown as Lib.TaskAttacker | undefined,
            path,
            engageRange: math.max(600, bot.GetAttackRange() + 100),
            // A restarted body keeps the first start's limit, so the attempt never outlives its expiry in score().
            deadline: math.min(now + eta * 1.5 + 5, attempt.left + SETTINGS.MaxEta * 1.5 + 20),
            engageFor: ENGAGE_FOR,
            telegraph: flank
                ? {
                      lead: SETTINGS.TelegraphLead,
                      fn: () => {
                          const t = target();
                          if (t === undefined || !Difficulty.IsAllyOfHuman(bot)) return;
                          Orders.Ping(bot, t.GetLocation());
                      },
                  }
                : undefined,
            commit: () => abortWhy(bot, target),
            onEngage: (t) => {
                attempt.engaged = t;
            },
        },
        { label: ctx.label, urgent: ctx.urgent }
    );
}

function ended(bot: Unit, r: Lib.Result, info: { label?: string; steps: number }): void {
    const pid = bot.GetPlayerID();
    const a = attempts[pid];
    // A preempt (retreat, a fight) ends the attempt too: restarting would pull the bot back into a gank it just had to
    // leave (pre-flight M6). The cooldown then keeps it in lane.
    if (a === undefined || a.ended !== undefined) return;
    a.ended = r.success ? r.message ?? "ok" : r.message ?? r.reason;
    const now = DotaTime();
    lastEnd[pid] = now;
    pending[pid] = undefined;
    Telemetry.Event("gank", [
        ["pid", pid],
        ["pos", LaneConfig.PositionOf(bot)],
        ["target", a.pid],
        ["lane", a.lane],
        ["score", string.format("%.2f", a.score)],
        ["result", r.success ? "ok" : "fail"],
        ["msg", a.ended],
        ["label", info.label],
        ["left", a.left],
        ["engaged", a.engaged],
        ["away", now - a.left],
    ]);
}

/** Owned positions run the gank; other bots have no gank state (OHA's upstream roam is not a planned rotation). */
export function Spec(bot: Unit, owned: (this: void, bot: Unit, state: string) => boolean): Lib.StateSpec {
    return {
        name: NAME,
        kind: "job",
        host: BotMode.Roam,
        tier: "TRANSITION",
        floor: SETTINGS.Score,
        preemptAfter: 1,
        score: () => (owned(bot, NAME) ? score(bot) : undefined),
        onEnd: (r, info) => ended(bot, r, info),
        body: (ctx) => body(bot, ctx),
    };
}
