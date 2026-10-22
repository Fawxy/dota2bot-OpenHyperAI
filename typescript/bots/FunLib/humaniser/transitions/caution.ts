/**
 * Lane safety and laning-phase transitions (task 12, Task 5): caution for a laner left alone or facing
 * missing enemies. The level biases retreat over attack, steps the lane position back toward our tower
 * (where OHA owns laning), suppresses trades unless we are stronger, and keeps a cautious core from shoving.
 */
import { BotMode, Lane, Unit, Vector } from "bots/ts_libs/dota";
import * as Intent from "bots/FunLib/humaniser/intent";
import * as LaneConfig from "bots/FunLib/humaniser/lane_config";
import * as LaneHooks from "bots/FunLib/humaniser/lane_hooks";
import * as LaneState from "bots/FunLib/humaniser/lane_state";
import * as LanePlan from "bots/FunLib/humaniser/lane_plan";
import * as LaneMain from "bots/FunLib/humaniser/lane";
import * as Camps from "bots/FunLib/humaniser/camps";
import * as CampJobs from "bots/FunLib/humaniser/camp_jobs";
import * as Counter from "bots/FunLib/humaniser/counterplay";
import * as Orders from "bots/FunLib/humaniser/orders";
import * as Profile from "bots/FunLib/humaniser/profile";
import * as Difficulty from "bots/FunLib/humaniser/difficulty";
import * as HDebug from "bots/FunLib/humaniser/debug";
import * as Telemetry from "bots/FunLib/humaniser/telemetry";
import * as Settings from "bots/FunLib/humaniser/transitions/settings";
import * as Rotation from "bots/FunLib/humaniser/transitions/rotation";
import * as Phase from "bots/FunLib/humaniser/transitions/phase";

export const SOURCE = "transitions:caution";

export interface CautionInput {
    alone: boolean;
    laneEnemies: number;
    missing: number;
    skill: number;
}

export function CautionLevel(i: CautionInput): number {
    const cfg = Settings.Get();
    const base = i.missing > 0 ? 1 : i.alone ? math.min(1, cfg.AloneLevel + cfg.AloneLevelPerEnemy * math.max(0, i.laneEnemies - 1)) : 0;
    return base * Settings.Lerp(cfg.SkillAmount, i.skill);
}

interface State {
    applied: number;
    reported: number;
    target: number;
    targetAt: number;
    delay: number;
    checkAt: number;
    missing: number;
    alone: boolean;
    lane?: Lane;
}

interface Episode {
    active: boolean;
    saidAt: number;
}

interface Forced {
    level: number;
    levelUntil: number;
    point?: Vector;
    pointUntil: number;
}

let states: Record<number, State> = {};
let episodes: Record<string, Episode> = {};
let forced: Record<number, Forced> = {};

export function ResetCache(): void {
    states = {};
    episodes = {};
    forced = {};
}

function forcedOf(bot: Unit): Forced {
    const pid = bot.GetPlayerID();
    let f = forced[pid];
    if (f === undefined) {
        f = { level: 0, levelUntil: -math.huge, pointUntil: -math.huge };
        forced[pid] = f;
    }
    return f;
}

/** Holds the caution level at no less than `level` until `until` (game time); `until` in the past clears it. */
export function ForceLevel(bot: Unit, level: number, until: number): void {
    const f = forcedOf(bot);
    f.level = level;
    f.levelUntil = until;
}

/** Holds the lane position at `point` (where OHA owns laning) until `until`; an undefined point clears it. */
export function ForceSetup(bot: Unit, point: Vector | undefined, until: number): void {
    const f = forcedOf(bot);
    f.point = point;
    f.pointUntil = until;
}

function dist2D(a: Vector, b: Vector): number {
    const dx = a.x - b.x;
    const dy = a.y - b.y;
    return math.sqrt(dx * dx + dy * dy);
}

export function IsAlone(bot: Unit, s: LaneState.LaneSnapshot): boolean {
    const pid = bot.GetPlayerID();
    const others: LaneState.LaneHero[] = [];
    // Dead laners count here: a dead partner is exactly the case that leaves the bot alone.
    for (const h of s.allies) if (h.assigned && h.pid !== pid) others.push(h);
    if (others.length === 0) return LanePlan.EnemyLaners(bot, s) >= 2;
    if (others.length > 1) return false;
    const p = others[0];
    if (!p.alive) return true;
    const absent = LaneConfig.Settings().Thresholds.CoreAbsentDist;
    const apart = dist2D(p.unit.GetLocation(), bot.GetLocation()) > absent;
    // A duo walking or backing off together is far from the front but not apart.
    if (p.distToFront > absent && apart) return true;
    // A rotation counts once the partner has actually left: from leaveAt it may still be standing in lane on frames
    // the rune mode refused.
    return (apart && Rotation.Active(p.unit) !== undefined) || CampJobs.Active(p.unit);
}

export function Missing(bot: Unit, s: LaneState.LaneSnapshot, alone: boolean): number {
    const cfg = Settings.Get();
    const after = alone ? cfg.AloneMissing : cfg.LaneMissing;
    let n = 0;
    for (const e of LaneState.Enemies(bot, s.lane)) {
        if (e.visible || e.timeSinceSeen <= after || e.timeSinceSeen > cfg.MissingMaxAge || !IsHeroAlive(e.pid)) continue;
        if (dist2D(e.location, s.frontLoc) <= cfg.SpareLaneRadius) n++;
    }
    return n;
}

function stateOf(bot: Unit): State {
    const pid = bot.GetPlayerID();
    let st = states[pid];
    if (st === undefined) {
        st = { applied: 0, reported: 0, alone: false, target: 0, targetAt: -math.huge, delay: 0, checkAt: -math.huge, missing: 0 };
        states[pid] = st;
    }
    return st;
}

function update(bot: Unit, now: number): State {
    const st = stateOf(bot);
    if (now >= st.checkAt) {
        st.checkAt = now + Settings.Get().Refresh;
        const laning = Phase.LaningTransitions(bot);
        const s = laning ? LaneState.ForBot(bot) : undefined;
        let target = 0;
        st.missing = 0;
        st.alone = false;
        st.lane = s?.lane;
        // The end of laning is not something the bot notices late: the level drops at once.
        if (!laning) st.applied = 0;
        if (s !== undefined) {
            const alone = IsAlone(bot, s);
            st.alone = alone;
            st.missing = Missing(bot, s, alone);
            // The skill read builds the bot's profile (random draws), so it is skipped when nothing calls for caution.
            if (alone || st.missing > 0) {
                target = CautionLevel({ alone, laneEnemies: LanePlan.EnemyLaners(bot, s), missing: st.missing, skill: LaneConfig.SkillOf(bot) });
            }
        }
        if (target !== st.target) {
            st.target = target;
            st.targetAt = now;
            st.delay = Profile.SampleDelay(bot, "notice");
        }
    }
    if (st.applied !== st.target && now - st.targetAt >= st.delay) {
        st.applied = st.target;
        HDebug.Log("transitions", `caution pid=${bot.GetPlayerID()} level=${string.format("%.2f", st.applied)} missing=${st.missing}`);
    }
    // Reported on change, including the drop to 0 when laning ends.
    if (st.applied !== st.reported) {
        st.reported = st.applied;
        Telemetry.Event("tr_caution", [
            ["pid", bot.GetPlayerID()],
            ["level", st.applied],
            ["alone", st.alone],
            ["missing", st.missing],
            ["lane", st.lane],
        ]);
    }
    return st;
}

export function Level(bot: Unit): number {
    if (!Phase.LaningTransitions(bot)) return 0;
    const now = DotaTime();
    const applied = Settings.IsOn("Caution") ? update(bot, now).applied : 0;
    const f = forced[bot.GetPlayerID()];
    return f !== undefined && Settings.IsOn("Teleports") && now < f.levelUntil ? math.max(applied, f.level) : applied;
}

function clamp01(v: number): number {
    return v < 0 ? 0 : v > 1 ? 1 : v;
}

function towardTower(bot: Unit, loc: Vector, level: number): Vector {
    const s = LaneState.ForBot(bot);
    if (s === undefined) return loc;
    const cfg = Settings.Get();
    const tower = GetLocationAlongLane(s.lane, clamp01(Camps.ToAbsAmount(s.team, s.ourTowerAmount)));
    const d = dist2D(loc, tower);
    if (d <= 0) return loc;
    const step = math.min(d, cfg.OffsetMin + (cfg.OffsetMax - cfg.OffsetMin) * level);
    return Vector(loc.x + ((tower.x - loc.x) / d) * step, loc.y + ((tower.y - loc.y) / d) * step, loc.z);
}

/** Lane position override (plan call 6); returns `loc` itself when caution does not apply. */
export function AdjustPosition(bot: Unit, loc: Vector): Vector {
    const f = forced[bot.GetPlayerID()];
    if (f !== undefined && f.point !== undefined && Settings.IsOn("Teleports") && DotaTime() < f.pointUntil && Phase.LaningTransitions(bot)) return LaneMain.OwnsLaning(bot) ? f.point : loc;
    if (!Settings.IsOn("Caution")) return loc;
    const level = Level(bot);
    if (level <= 0 || !LaneMain.OwnsLaning(bot)) return loc;
    return towardTower(bot, loc, level);
}

export function SuppressTrades(bot: Unit): boolean {
    if (Level(bot) < Settings.Get().SuppressLevel) return false;
    const stronger = LaneConfig.Helpers().WeAreStronger;
    return stronger === undefined || !stronger(bot, Settings.Get().CautionStrongerRadius);
}

const LANE_NAMES: Partial<Record<Lane, string>> = { [Lane.Top]: "top", [Lane.Mid]: "mid", [Lane.Bot]: "bot" };

function midAlreadyCalled(bot: Unit, now: number): boolean {
    const window = Settings.Get().MidMissingSignalWindow;
    for (const sig of Counter.Signals(bot)) if (sig.kind === "mid_missing" && now - sig.at <= window) return true;
    return false;
}

function callout(bot: Unit, st: State, now: number): void {
    if (st.lane === undefined) return;
    const name = LANE_NAMES[st.lane];
    if (name === undefined) return;
    const key = `${bot.GetTeam()}:${st.lane}`;
    let ep = episodes[key];
    if (ep === undefined) {
        ep = { active: false, saidAt: -math.huge };
        episodes[key] = ep;
    }
    if (st.missing === 0) {
        ep.active = false;
        return;
    }
    if (ep.active || !Difficulty.IsAllyOfHuman(bot)) return;
    // An episode that starts inside the cooldown is spent unannounced, not called once the cooldown ends.
    ep.active = true;
    const cooldown = Settings.Get().MissingCooldown;
    if (now - ep.saidAt < cooldown) return;
    if (st.lane === Lane.Mid && midAlreadyCalled(bot, now)) return;
    ep.saidAt = now;
    Orders.Say(bot, `say_ss_${name}`, cooldown);
}

export function Tick(bot: Unit): void {
    if (!Settings.IsOn("Caution") && !Settings.IsOn("Teleports")) return;
    if (!Phase.LaningTransitions(bot)) {
        if (Settings.IsOn("Caution")) update(bot, DotaTime());
        delete forced[bot.GetPlayerID()];
        Intent.ReleaseSource(bot, SOURCE);
        return;
    }
    if (Settings.IsOn("Caution")) {
        const now = DotaTime();
        callout(bot, update(bot, now), now);
    }
    const level = Level(bot);
    if (level <= 0) {
        Intent.ReleaseSource(bot, SOURCE);
        return;
    }
    const cfg = Settings.Get();
    Intent.Claim(bot, { source: SOURCE, tier: "TRANSITION", mode: BotMode.Retreat, scale: 1 + (cfg.RetreatScaleMax - 1) * level });
    Intent.Claim(bot, { source: SOURCE, tier: "TRANSITION", mode: BotMode.Attack, scale: 1 - (1 - cfg.AttackScaleMin) * level });
}

export function RegisterProbes(): void {
    LaneHooks.SetCautionProbe(bot => Level(bot) > 0);
    LaneHooks.SetPositionProbe(AdjustPosition);
    LaneHooks.SetTradeProbe(SuppressTrades);
}

RegisterProbes();
