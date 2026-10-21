/**
 * Stacking (task 07, Phase D): who may stack, which camp, the per-minute attempt roll, and the stacked-camp
 * record that the stack pull and the planner read. The stack job itself runs in camp_jobs, which imports this
 * module (never the other way round). Stacked state is observed (neutral counts before the aggro and after the
 * minute) or assumed from the aggro timing when the box was out of sight.
 */
import { BotMode, Unit, Vector } from "bots/ts_libs/dota";
import * as LaneConfig from "bots/FunLib/humaniser/lane_config";
import * as LaneHooks from "bots/FunLib/humaniser/lane_hooks";
import * as Camps from "bots/FunLib/humaniser/camps";
import * as LaneState from "bots/FunLib/humaniser/lane_state";
import * as LaneRoles from "bots/FunLib/humaniser/lane_roles";
import * as LanePlan from "bots/FunLib/humaniser/lane_plan";
import * as Difficulty from "bots/FunLib/humaniser/difficulty";
import * as Orders from "bots/FunLib/humaniser/orders";
import { teamMembers } from "bots/FunLib/humaniser/commands";

interface StackRecord {
    minute: number;
    count: number;
}

let rolls: Record<number, { minute: number; ok: boolean }> = {};
let before: Record<number, number> = {};
let records: Record<number, StackRecord> = {};
let telegraphedAt: Record<number, number> = {};

export function ResetCache(): void {
    rolls = {};
    before = {};
    records = {};
    telegraphedAt = {};
}

function settings(): LaneConfig.LaneSettings {
    return LaneConfig.Settings();
}

function dist2D(a: Vector, b: Vector): number {
    const dx = a.x - b.x;
    const dy = a.y - b.y;
    return math.sqrt(dx * dx + dy * dy);
}

function currentMinute(): number {
    return math.floor(DotaTime() / 60);
}

const IDLE_MODES: Record<number, boolean> = { [BotMode.Laning]: true, [BotMode.Farm]: true, [BotMode.None]: true };

/** The safety half of Eligible; forced (debug) stack jobs check only this. */
export function Safe(bot: Unit, s: LaneState.LaneSnapshot | undefined, enemies: LaneState.LaneEnemy[]): LuaMultiReturn<[boolean, string]> {
    const t = settings().Thresholds;
    if (LaneConfig.InLaningPhase()) {
        if (!LaneRoles.LaneStable(bot, enemies)) return $multi(false, "unstable");
        if (s !== undefined && !LaneRoles.PartnerSafe(bot, s, enemies)) return $multi(false, "partner-unsafe");
        return $multi(true, "ok");
    }
    const maxHP = bot.GetMaxHealth();
    if (maxHP <= 0 || bot.GetHealth() / maxHP <= t.StableMinHP) return $multi(false, "low-hp");
    const loc = bot.GetLocation();
    for (const e of enemies) {
        if (e.visible && dist2D(e.location, loc) <= t.StableEnemyRadius) return $multi(false, "enemy-near");
    }
    return $multi(true, "ok");
}

export function Eligible(bot: Unit, s: LaneState.LaneSnapshot | undefined, enemies: LaneState.LaneEnemy[]): LuaMultiReturn<[boolean, string]> {
    if (!LaneConfig.IsOn("Stack")) return $multi(false, "flag-off");
    const pos = LaneConfig.PositionOf(bot);
    if (pos === undefined || pos < 4 || pos > 5) return $multi(false, "not-support");
    if (LaneConfig.InLaningPhase()) {
        if (s === undefined) return $multi(false, "no-lane");
    } else {
        if (IDLE_MODES[bot.GetActiveMode()] !== true) return $multi(false, "busy-mode");
        if (Orders.GetFor(bot) !== undefined) return $multi(false, "has-order");
    }
    return Safe(bot, s, enemies);
}

/** Where a stack job waits: just outside the box on the exit side, so the walk-off starts away from the camp. */
export function StandPoint(spawner: Camps.Spawner, data: Camps.CampJobData): Vector {
    const exit = data.stack?.exitPath[0];
    const edge = exit !== undefined ? Camps.BoxEdgePoint(spawner, exit, settings().Radii.StandOffset) : undefined;
    return edge ?? Camps.BoxCenter(spawner);
}

function contested(bot: Unit, idx: number, enemies: LaneState.LaneEnemy[], allies: Unit[]): boolean {
    const margin = settings().Radii.BoxMargin;
    for (const e of enemies) if (e.visible && Camps.InBox(idx, e.location, margin)) return true;
    const pid = bot.GetPlayerID();
    for (const a of allies) {
        if (a.GetPlayerID() !== pid && a.IsAlive() && Camps.InBox(idx, a.GetLocation(), margin)) return true;
    }
    return false;
}

function reachable(bot: Unit, data: Camps.CampJobData, minute: number): boolean {
    const spawner = Camps.SpawnerByIdx(data.campIdx);
    if (spawner === undefined || data.stack === undefined) return false;
    const travel = GetUnitToLocationDistance(bot, StandPoint(spawner, data)) / math.max(bot.GetCurrentMovementSpeed(), 1);
    return travel <= settings().Timing.MaxTravel && DotaTime() + travel <= minute * 60 + data.stack.aggroSec;
}

function multiStackOk(bot: Unit, data: Camps.CampJobData): boolean {
    if (StackCount(data.campIdx) < settings().Thresholds.StackMaxCampCount) return true;
    return LaneConfig.SkillOf(bot) > settings().Gates.MultiStackAncients;
}

/** Pull camp of our lane, then camps near our cores (by core position), then our ancients (nearest first). */
export function ChooseCamp(bot: Unit, s: LaneState.LaneSnapshot | undefined, minute: number): Camps.CampJobData | undefined {
    const team = bot.GetTeam();
    const enemies = LaneState.Enemies(bot, s?.lane ?? bot.GetAssignedLane());
    const allies = teamMembers(team);
    const ok = (data: Camps.CampJobData) => !contested(bot, data.campIdx, enemies, allies) && reachable(bot, data, minute);

    if (s !== undefined && LaneConfig.InLaningPhase()) {
        for (const data of Camps.PullCampsFor(s.team, s.lane)) if (ok(data)) return data;
    }

    const camps = Camps.Resolve();
    const cores: { pos: number; unit: Unit }[] = [];
    for (const a of allies) {
        const pos = LaneConfig.PositionOf(a);
        if (pos !== undefined && pos >= 1 && pos <= 3 && a.IsAlive()) cores.push({ pos, unit: a });
    }
    cores.sort((a, b) => (a.pos !== b.pos ? a.pos - b.pos : a.unit.GetPlayerID() - b.unit.GetPlayerID()));
    const radius = settings().Radii.StackCoreCamp;
    for (const core of cores) {
        const loc = core.unit.GetLocation();
        let best: Camps.CampJobData | undefined;
        let bestDist = math.huge;
        for (const data of camps) {
            if (data.team !== team || data.type === "ancient") continue;
            const spawner = Camps.SpawnerByIdx(data.campIdx);
            if (spawner === undefined) continue;
            const d = dist2D(Camps.BoxCenter(spawner), loc);
            if (d <= radius && d < bestDist && ok(data)) {
                best = data;
                bestDist = d;
            }
        }
        if (best !== undefined) return best;
    }

    let best: Camps.CampJobData | undefined;
    let bestDist = math.huge;
    for (const data of camps) {
        if (data.team !== team || data.type !== "ancient") continue;
        const spawner = Camps.SpawnerByIdx(data.campIdx);
        if (spawner === undefined) continue;
        const d = GetUnitToLocationDistance(bot, Camps.BoxCenter(spawner));
        if (d < bestDist && multiStackOk(bot, data) && ok(data)) {
            best = data;
            bestDist = d;
        }
    }
    return best;
}

function attemptRoll(bot: Unit, minute: number): boolean {
    const pid = bot.GetPlayerID();
    const r = rolls[pid];
    if (r !== undefined && r.minute === minute) return r.ok;
    const ok = LaneConfig.Roll(LaneConfig.Curve("StackAttempt", LaneConfig.SkillOf(bot)));
    rolls[pid] = { minute, ok };
    return ok;
}

/** Eligibility, then one attempt roll per minute (a `!stack` order skips the roll, not the safety checks). */
export function WantsStack(bot: Unit, minute: number): Camps.CampJobData | undefined {
    if (!LaneConfig.IsOn("Stack")) return undefined;
    const s = LaneState.ForBot(bot);
    const enemies = LaneState.Enemies(bot, s?.lane ?? bot.GetAssignedLane());
    const [eligible] = Eligible(bot, s, enemies);
    if (!eligible) return undefined;
    const requested = s !== undefined && LanePlan.View(bot, s).stackRequested;
    if (!requested && !attemptRoll(bot, minute)) return undefined;
    return ChooseCamp(bot, s, minute);
}

export function NoteStackAttempt(campIdx: number, _minute: number, countBefore: number): void {
    before[campIdx] = countBefore;
    // An empty box means the camp was farmed: whatever was stacked there is gone.
    if (countBefore === 0) ClearStack(campIdx);
}

/** `countAfter` undefined: the box was not visible; `assumed` then decides (aggro timing in the safe band). */
export function NoteStackOutcome(campIdx: number, minute: number, countAfter: number | undefined, assumed: boolean = false): void {
    const prior = before[campIdx];
    delete before[campIdx];
    const stacked = countAfter !== undefined ? prior !== undefined && countAfter > prior : assumed;
    // A failed attempt leaves an earlier stack in place: those neutrals are still there.
    if (!stacked) return;
    const prev = records[campIdx];
    const count = prev !== undefined && prev.minute === minute - 1 ? prev.count + 1 : 1;
    records[campIdx] = { minute, count };
}

export function IsStacked(campIdx: number): boolean {
    const rec = records[campIdx];
    return rec !== undefined && rec.minute >= currentMinute() - 1;
}

export function StackCount(campIdx: number): number {
    return IsStacked(campIdx) ? records[campIdx].count : 0;
}

export function ClearStack(campIdx: number): void {
    delete records[campIdx];
}

/** "stacked big camp" for allies of humans, at most once per StackTelegraphCooldown per bot. */
export function Telegraph(bot: Unit, type: Camps.CampType): void {
    if (type !== "large" && type !== "ancient") return;
    if (!LaneConfig.IsOn("Telegraph") || !Difficulty.IsAllyOfHuman(bot)) return;
    const pid = bot.GetPlayerID();
    const cooldown = settings().Timing.StackTelegraphCooldown;
    const last = telegraphedAt[pid];
    if (last !== undefined && GameTime() - last < cooldown) return;
    if (Orders.Say(bot, "say_lane_stacked_big", cooldown)) telegraphedAt[pid] = GameTime();
}

export function RegisterProbes(): void {
    LaneHooks.SetStackedProbe(IsStacked);
}

RegisterProbes();
