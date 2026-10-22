/**
 * Lane safety and laning-phase transitions (task 12, Task 4): support power-rune rotations.
 *
 * Between DecideFrom and DecideTo seconds before a power spawn, each pos 4 / pos 5 decides once whether
 * to leave lane for the power spot nearest it (the skill roll and the jitter are drawn once per spawn).
 * While the decision is active the rune mode is pointed at that spot (RuneTarget) and lifted by a floor
 * claim; the rune mode yields the claim on any frame its own gates refuse, as it does for the mid (3b).
 */
import { BotMode, Rune, Unit, Vector } from "bots/ts_libs/dota";
import * as Intent from "bots/FunLib/humaniser/intent";
import * as LaneConfig from "bots/FunLib/humaniser/lane_config";
import * as LaneHooks from "bots/FunLib/humaniser/lane_hooks";
import * as LaneState from "bots/FunLib/humaniser/lane_state";
import * as Orders from "bots/FunLib/humaniser/orders";
import * as Difficulty from "bots/FunLib/humaniser/difficulty";
import * as HDebug from "bots/FunLib/humaniser/debug";
import * as Settings from "bots/FunLib/humaniser/transitions/settings";
import * as Runes from "bots/FunLib/humaniser/transitions/runes";
import * as Busy from "bots/FunLib/humaniser/transitions/busy";

declare function GetRuneSpawnLocation(this: void, rune: number): Vector;

export const SOURCE = "transitions:rotate";

export interface RotationDecision {
    spawn: number;
    go: boolean;
    spot?: Vector;
    side?: "top" | "bot";
    leaveAt?: number;
    reason: string;
}

interface Entry {
    decision: RotationDecision;
    arriveAt: number;
    announced: boolean;
    checkAt: number;
}

const entries: Record<number, Entry> = {};

export function ResetCache(): void {
    for (const [k] of pairs(entries)) delete entries[k as number];
}

function dist2D(a: Vector, b: Vector): number {
    const dx = a.x - b.x;
    const dy = a.y - b.y;
    return math.sqrt(dx * dx + dy * dy);
}

function isSupport(bot: Unit): boolean {
    const pos = LaneConfig.PositionOf(bot);
    return pos === 4 || pos === 5;
}

function teammate(bot: Unit, pos: number): Unit | undefined {
    const n = GetTeamPlayers(bot.GetTeam()).length;
    for (let i = 1; i <= n; i++) {
        const m = GetTeamMember(i);
        if (m !== undefined && m !== null && m.IsAlive() && LaneConfig.PositionOf(m) === pos) return m;
    }
    return undefined;
}

/** Enemies visible, or seen within ContestSeenWithin, inside ContestRadius of the spot. Perception goes through LaneState. */
function enemiesNear(bot: Unit, spot: Vector): number {
    const cfg = Settings.Get();
    let n = 0;
    for (const e of LaneState.Enemies(bot, bot.GetAssignedLane())) {
        if (!e.visible && e.timeSinceSeen > cfg.ContestSeenWithin) continue;
        if (dist2D(e.location, spot) <= cfg.ContestRadius) n++;
    }
    return n;
}

function log(bot: Unit, d: RotationDecision, extra = ""): void {
    HDebug.Log(
        "transitions",
        `rotate pid=${bot.GetPlayerID()} spawn=${d.spawn} go=${tostring(d.go)} side=${d.side ?? "-"} leaveAt=${
            d.leaveAt !== undefined ? string.format("%.1f", d.leaveAt) : "-"
        } reason=${d.reason}${extra}`
    );
}

export function Decide(bot: Unit, now: number): RotationDecision {
    const cfg = Settings.Get();
    const pid = bot.GetPlayerID();
    const spawn = Runes.NextSpawn("power", now);
    const cached = entries[pid];
    if (cached !== undefined && cached.decision.spawn === spawn) return cached.decision;
    if (!Settings.IsOn("Rotation")) return { spawn, go: false, reason: "off" };
    if (!isSupport(bot)) return { spawn, go: false, reason: "role" };
    if (spawn < Runes.RUNE_RULES.power.first || now < spawn - cfg.DecideFrom || now > spawn - cfg.DecideTo) {
        return { spawn, go: false, reason: "window" };
    }

    // The pos 5 reads the pos 4's decision, so the pos 4 decides (and draws its rolls) first.
    const p4 = LaneConfig.PositionOf(bot) === 5 ? teammate(bot, 4) : undefined;
    const d4 = p4 !== undefined ? Decide(p4, now) : undefined;

    const skill = LaneConfig.SkillOf(bot);
    const rolled = LaneConfig.Roll(Settings.Lerp(cfg.RotateChance, skill));
    const jitter = LaneConfig.Gauss() * Settings.Lerp(cfg.ArriveSigma, skill);
    const mistake = LaneConfig.Roll(Settings.Lerp(cfg.MistakeChance, skill));

    const loc = bot.GetLocation();
    const [spot, side] = Runes.NearestPowerSpot(loc);
    const travel = (dist2D(loc, spot) * cfg.PathFactor) / math.max(bot.GetCurrentMovementSpeed(), 1);
    const leaveAt = spawn - cfg.ArriveLead - travel + jitter;
    const d: RotationDecision = { spawn, go: false, spot, side, leaveAt, reason: "ok" };

    const strict = LaneConfig.PositionOf(bot) === 5;
    const [busy, busyWhy] = Busy.IsBusy(bot, spawn);
    const [spare, spareWhy] = Busy.LaneCanSpare(bot, strict);
    if (busy) d.reason = busyWhy;
    else if (leaveAt < now - cfg.LateSlack) d.reason = "late";
    else if (!spare && !mistake) d.reason = spareWhy;
    else if (!rolled) d.reason = "roll";
    else if (p4 !== undefined) {
        const p4Busy = Busy.IsBusy(p4, spawn)[0];
        const contested = enemiesNear(bot, spot) >= cfg.Pos5ContestEnemies;
        if (d4 !== undefined && d4.go && !contested) d.reason = "pos4 going";
        else if (!p4Busy && dist2D(loc, spot) > dist2D(p4.GetLocation(), spot)) d.reason = "pos4 closer";
        else d.go = true;
    } else d.go = true;
    if (d.go && !spare) d.reason = "mistake";

    entries[pid] = { decision: d, arriveAt: leaveAt + travel, announced: false, checkAt: -math.huge };
    log(bot, d);
    return d;
}

export function Active(bot: Unit): RotationDecision | undefined {
    if (!Settings.IsOn("Rotation")) return undefined;
    const e = entries[bot.GetPlayerID()];
    if (e === undefined || !e.decision.go) return undefined;
    const now = DotaTime();
    const d = e.decision;
    return d.leaveAt !== undefined && now >= d.leaveAt && now <= d.spawn + Settings.Get().RotateLinger ? d : undefined;
}

/** The power rune id at the active decision's side (named by the spot's y, as Runes.NearestPowerSpot does). */
export function RuneTarget(bot: Unit): number | undefined {
    const d = Active(bot);
    if (d === undefined) return undefined;
    for (const rune of [Rune.Power1, Rune.Power2]) {
        if ((GetRuneSpawnLocation(rune).y > 0 ? "top" : "bot") === d.side) return rune;
    }
    return undefined;
}

/** For our mid: contest the rune harder when a rotating support is with it or at the spot. */
export function MidRuneDesire(bot: Unit): number {
    if (!Settings.IsOn("Rotation") || LaneConfig.PositionOf(bot) !== 2) return 0;
    const cfg = Settings.Get();
    const now = DotaTime();
    for (const pos of [4, 5]) {
        const support = teammate(bot, pos);
        const d = support !== undefined ? Active(support) : undefined;
        if (support === undefined || d === undefined || d.spot === undefined) continue;
        if (now < d.spawn - cfg.MidContestFrom || now > d.spawn + cfg.RotateLinger) continue;
        const sLoc = support.GetLocation();
        if (dist2D(sLoc, bot.GetLocation()) <= cfg.MidSupportRadius || dist2D(sLoc, d.spot) <= cfg.MidSupportRadius) return cfg.MidContestDesire;
    }
    return 0;
}

/** The planned (or current) rotation side, for the overlay. */
export function Target(bot: Unit): "top" | "bot" | undefined {
    if (!Settings.IsOn("Rotation")) return undefined;
    const e = entries[bot.GetPlayerID()];
    if (e === undefined || !e.decision.go || DotaTime() > e.decision.spawn + Settings.Get().RotateLinger) return undefined;
    return e.decision.side;
}

function say(bot: Unit, key: string): void {
    if (Difficulty.IsAllyOfHuman(bot)) Orders.Say(bot, key, Settings.Get().ChatCooldown);
}

/** Our heroes at or heading for the spot: the support, our mid within ContestMidRadius, and another support rotating there. */
function ours(bot: Unit, d: RotationDecision): number {
    const cfg = Settings.Get();
    let n = 1;
    const mid = teammate(bot, 2);
    if (mid !== undefined && d.spot !== undefined && dist2D(mid.GetLocation(), d.spot) <= cfg.ContestMidRadius) n++;
    const other = teammate(bot, LaneConfig.PositionOf(bot) === 4 ? 5 : 4);
    const od = other !== undefined ? entries[other.GetPlayerID()] : undefined;
    if (od !== undefined && od.decision.go && od.decision.spawn === d.spawn && od.decision.side === d.side) n++;
    return n;
}

export function Tick(bot: Unit): void {
    if (!Settings.IsOn("Rotation") || !isSupport(bot)) return;
    const cfg = Settings.Get();
    const now = DotaTime();
    Decide(bot, now);
    const e = entries[bot.GetPlayerID()];
    if (e !== undefined && e.decision.go && now <= e.decision.spawn + cfg.RotateLinger) {
        const d = e.decision;
        if (!e.announced) {
            e.announced = true;
            say(bot, "say_rune_coming_mid");
        }
        if (now >= e.checkAt && now >= e.arriveAt - cfg.ContestFrom && d.spot !== undefined) {
            e.checkAt = now + cfg.Refresh;
            const enemies = enemiesNear(bot, d.spot);
            const us = ours(bot, d);
            if (enemies > us) {
                d.go = false;
                d.reason = "contested";
                Intent.Release(bot, SOURCE, BotMode.Rune);
                log(bot, d, ` enemies=${enemies} ours=${us}`);
                say(bot, "say_rune_lost");
                return;
            }
        }
    }

    const a = Active(bot);
    if (a === undefined) return;
    Intent.Claim(bot, { source: SOURCE, tier: "TRANSITION", mode: BotMode.Rune, floor: cfg.RotateFloor });
    if (now < a.spawn && a.spot !== undefined && dist2D(bot.GetLocation(), a.spot) <= cfg.RotateHoldRadius) Intent.Hold(bot, SOURCE);
}

/** The rune mode refused this frame (a safety gate, no power target): the floor must not apply. */
export function Yield(bot: Unit): void {
    Intent.Release(bot, SOURCE, BotMode.Rune);
}

export function RegisterProbes(): void {
    LaneHooks.SetRotationProbe(bot => Active(bot) !== undefined);
}

RegisterProbes();
