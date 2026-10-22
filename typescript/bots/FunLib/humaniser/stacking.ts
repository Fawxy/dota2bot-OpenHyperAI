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
import { DEFAULT_STACK_SEC } from "bots/FunLib/humaniser/camps_data";

interface StackRecord {
    minute: number;
    count: number;
}

let rolls: Record<number, { minute: number; ok: boolean }> = {};
let before: Record<number, number> = {};
let records: Record<number, StackRecord> = {};
let telegraphedAt: Record<number, number> = {};
/**
 * Camps a bot's stack job has claimed, by camp then pid, until that job's walk-off ends (DotaTime). Per pid so a camp
 * both teams have a job on (an off-lane pull camp) keeps each team's claim; only allies' claims block.
 */
let reservations: Record<number, Record<number, number>> = {};

export function ResetCache(): void {
    rolls = {};
    before = {};
    records = {};
    telegraphedAt = {};
    reservations = {};
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

/**
 * 7.41 stack windows (seconds to land the hit) from scripts/creep_pull_timings.txt in pak01_dir.vpk (read 22/10/2026,
 * what the `dota_hud_show_creep_spawn_camp_names` overlay shows), by the camp's spawner origin from maps/dota.vpk:
 * [x, y, stack_start, stack_end]. Camps 1,300+ apart, so WINDOW_MATCH cannot pick the wrong one.
 */
const WINDOWS: number[][] = [
    [-4824, 3915, 54, 56], // evil_1
    [-3911, 4829, 55, 57], // evil_2
    [1224, 4176, 55, 56], // evil_4
    [1064, 2580, 55, 56], // evil_5
    [-852, 4940, 54, 55], // evil_6
    [7928, -120, 55, 56], // evil_7
    [4352, 48, 53, 55], // evil_8
    [3392, -1408, 53, 55], // evil_9
    [-2880, 7376, 54, 56], // evil_11
    [2016, 7896, 55, 57], // evil_12
    [8430, 1263, 55, 56], // evil_13
    [336, 7696, 55, 56], // evil_14
    [-2596, 3850, 55, 56], // evil_15
    [-4208, 8336, 55, 56], // evil_20
    [3978, -5027, 55, 57], // good_1
    [4649, -3699, 52, 54], // good_2
    [186, -5197, 54, 55], // good_4
    [-1454, -3356, 55, 56], // good_5
    [-4013, 992, 53, 55], // good_7
    [-5015, -96, 52, 54], // good_8
    [-1983, -4815, 56, 57], // good_9
    [-720, -7696, 55, 57], // good_11
    [-2415, -8402, 53, 55], // good_12
    [-8313, -553, 55, 56], // good_13
    [2768, -8336, 55, 57], // good_14
    [1922, -3975, 56, 57], // good_15
    [-8023, -1838, 55, 56], // good_16
    [4416, -8432, 55, 56], // good_20
];
const WINDOW_MATCH = 300;

/** Valve's stack window for the camp, or undefined (another map, a moved camp, StackFromValve off). */
export function Window(campIdx: number): LuaMultiReturn<[number | undefined, number | undefined]> {
    const spawner = Camps.SpawnerByIdx(campIdx);
    if (spawner === undefined || settings().Timing.StackFromValve !== true) return $multi(undefined, undefined);
    for (const w of WINDOWS) {
        const dx = w[0] - spawner.location.x;
        const dy = w[1] - spawner.location.y;
        if (dx * dx + dy * dy <= WINDOW_MATCH * WINDOW_MATCH) return $multi(w[2], w[3]);
    }
    return $multi(undefined, undefined);
}

/**
 * The second the stack hit should land: StackWindowAt through Valve's window for a camp on the type's default second,
 * else the data's (a replay or measured stack second is kept). The seeds (small 54.5 to ancient 53.0) were 1-2.5 s
 * early for most 7.41 camps (evil_2/good_1 55-57, evil_1 54-56) and 1.5 s late for good_2/good_8 (52-54).
 */
export function AggroSec(data: Camps.CampJobData): number {
    const sec = data.stack?.aggroSec ?? DEFAULT_STACK_SEC[data.type];
    if (sec !== DEFAULT_STACK_SEC[data.type]) return sec;
    const [from, to] = Window(data.campIdx);
    if (from === undefined || to === undefined) return sec;
    return from + (to - from) * settings().Timing.StackWindowAt;
}

const IDLE_MODES: Record<number, boolean> = { [BotMode.Laning]: true, [BotMode.Farm]: true, [BotMode.None]: true };

/**
 * The safety half of Eligible; forced (debug) stack jobs check only this. `committed`: the stack is already under way,
 * so the partner check is LaneRoles.PartnerHolding instead of the start gate.
 */
export function Safe(bot: Unit, s: LaneState.LaneSnapshot | undefined, enemies: LaneState.LaneEnemy[], committed = false): LuaMultiReturn<[boolean, string]> {
    const t = settings().Thresholds;
    const maxHP = bot.GetMaxHealth();
    if (LaneConfig.InLaningPhase()) {
        // LaneStable is the start gate only: re-checked every frame it flipped on an enemy coming into view and ended
        // walk-offs at :58 (console.9055921786, skywrath on evil_1), letting the camp back into the box before :00.
        if (committed) {
            if (maxHP <= 0 || bot.GetHealth() / maxHP <= t.StableMinHP) return $multi(false, "low-hp");
            if (s !== undefined) return LaneRoles.PartnerHolding(bot, s, enemies);
            return $multi(true, "ok");
        }
        if (!LaneRoles.LaneStable(bot, enemies)) return $multi(false, "unstable");
        if (s !== undefined && !LaneRoles.PartnerSafe(bot, s, enemies)) return $multi(false, "partner-unsafe");
        return $multi(true, "ok");
    }
    return SafeAway(bot, enemies);
}

/** Safety off a laning snapshot: HP and no visible enemy close. After laning, and a core's stack (FarmPattern). */
export function SafeAway(bot: Unit, enemies: LaneState.LaneEnemy[]): LuaMultiReturn<[boolean, string]> {
    const t = settings().Thresholds;
    const maxHP = bot.GetMaxHealth();
    if (maxHP <= 0 || bot.GetHealth() / maxHP <= t.StableMinHP) return $multi(false, "low-hp");
    const loc = bot.GetLocation();
    for (const e of enemies) {
        if (e.visible && dist2D(e.location, loc) <= t.StableEnemyRadius) return $multi(false, "enemy-near");
    }
    return $multi(true, "ok");
}

export function Eligible(bot: Unit, s: LaneState.LaneSnapshot | undefined, enemies: LaneState.LaneEnemy[], committed = false): LuaMultiReturn<[boolean, string]> {
    if (!LaneConfig.IsOn("Stack")) return $multi(false, "flag-off");
    const pos = LaneConfig.PositionOf(bot);
    if (pos === undefined || pos < 4 || pos > 5) return $multi(false, "not-support");
    // A job started under a higher mode (retreat, roam, defend) only wins farm's 0.7 in that mode's dip and ends as mode-end.
    if (IDLE_MODES[bot.GetActiveMode()] !== true) return $multi(false, "busy-mode");
    if (LaneConfig.InLaningPhase()) {
        if (s === undefined) return $multi(false, "no-lane");
    } else if (Orders.GetFor(bot) !== undefined) {
        return $multi(false, "has-order");
    }
    return Safe(bot, s, enemies, committed);
}

/** Where a stack job waits: just outside the box on the exit side, so the walk-off starts away from the camp. */
export function StandPoint(spawner: Camps.Spawner, data: Camps.CampJobData): Vector {
    const exit = data.stack?.exitPath[0];
    return exit !== undefined ? Camps.StandPoint(spawner, exit, settings().Radii.StandOffset) : spawner.location;
}

/** Claims `campIdx` for `pid`'s stack job so allies still choosing a camp skip it, not only once it stands in the box. */
export function Reserve(campIdx: number, pid: number, until: number): void {
    reservations[campIdx] = reservations[campIdx] ?? {};
    reservations[campIdx][pid] = until;
}

export function Release(campIdx: number, pid: number): void {
    if (reservations[campIdx] !== undefined) delete reservations[campIdx][pid];
}

/** Another bot's stack job has claimed the camp (its walk-off has not ended). */
export function ReservedByAlly(campIdx: number, pid: number): boolean {
    for (const [other, until] of pairs(reservations[campIdx] ?? {})) {
        if (other !== pid && DotaTime() < until) return true;
    }
    return false;
}

function contested(bot: Unit, idx: number, enemies: LaneState.LaneEnemy[], allies: Unit[]): boolean {
    const margin = settings().Radii.BoxMargin;
    for (const e of enemies) if (e.visible && Camps.InBox(idx, e.location, margin)) return true;
    const pid = bot.GetPlayerID();
    const claims = reservations[idx] ?? {};
    for (const a of allies) {
        if (a.GetPlayerID() === pid) continue;
        const until = claims[a.GetPlayerID()];
        if (until !== undefined && DotaTime() < until) return true;
        if (a.IsAlive() && Camps.InBox(idx, a.GetLocation(), margin)) return true;
    }
    return false;
}

function reachable(bot: Unit, data: Camps.CampJobData, minute: number): boolean {
    const spawner = Camps.SpawnerByIdx(data.campIdx);
    if (spawner === undefined || data.stack === undefined) return false;
    const travel = GetUnitToLocationDistance(bot, StandPoint(spawner, data)) / math.max(bot.GetCurrentMovementSpeed(), 1);
    return travel <= settings().Timing.MaxTravel && DotaTime() + travel <= minute * 60 + AggroSec(data);
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
            // The enemy camp our off lane pulls is in their jungle: not one to stack for a core.
            if (spawner === undefined || spawner.team !== team) continue;
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
    const view = s !== undefined ? LanePlan.View(bot, s) : undefined;
    // Checked before the roll so a hands-off lane neither burns the minute's roll nor starts a job that aborts at once.
    if (view !== undefined && view.handsOff) return undefined;
    const requested = view !== undefined && view.stackRequested;
    if (!requested && !attemptRoll(bot, minute)) return undefined;
    return ChooseCamp(bot, s, minute);
}

export function NoteStackAttempt(campIdx: number, _minute: number, countBefore: number): void {
    before[campIdx] = countBefore;
    // An empty box means the camp was farmed: whatever was stacked there is gone.
    if (countBefore === 0) ClearStack(campIdx);
}

/**
 * `countAfter` undefined: the box was not visible; `assumed` then decides (aggro timing in the safe band).
 * Returns whether the attempt counts as stacked.
 */
export function NoteStackOutcome(campIdx: number, minute: number, countAfter: number | undefined, assumed: boolean = false): boolean {
    const prior = before[campIdx];
    delete before[campIdx];
    const stacked = countAfter !== undefined ? prior !== undefined && countAfter > prior : assumed;
    // A failed attempt leaves an earlier stack in place: those neutrals are still there.
    if (!stacked) return false;
    const prev = records[campIdx];
    const count = prev !== undefined && prev.minute === minute - 1 ? prev.count + 1 : 1;
    records[campIdx] = { minute, count };
    return true;
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
