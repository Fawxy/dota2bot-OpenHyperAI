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
import * as Telemetry from "bots/FunLib/humaniser/telemetry";
import * as Settings from "bots/FunLib/humaniser/transitions/settings";
import * as Runes from "bots/FunLib/humaniser/transitions/runes";
import * as Busy from "bots/FunLib/humaniser/transitions/busy";
import * as Phase from "bots/FunLib/humaniser/transitions/phase";

declare function GetRuneSpawnLocation(this: void, rune: number): Vector;
declare function GetRuneStatus(this: void, rune: number): number;
declare const RUNE_STATUS_AVAILABLE: number;

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
    spareAt?: number;
}

const entries: Record<number, Entry> = {};
const holdState: Record<number, string> = {};

export function ResetCache(): void {
    for (const [k] of pairs(entries)) delete entries[k as number];
    for (const [k] of pairs(holdState)) delete holdState[k as number];
}

function dist2D(a: Vector, b: Vector): number {
    const dx = a.x - b.x;
    const dy = a.y - b.y;
    return math.sqrt(dx * dx + dy * dy);
}

/** Only bot supports decide or rotate; a human support's plans are unknown, so they are never guessed. */
function isSupport(bot: Unit): boolean {
    const pos = LaneConfig.PositionOf(bot);
    return (pos === 4 || pos === 5) && bot.IsBot();
}

function teammate(_bot: Unit, pos: number, botsOnly: boolean): Unit | undefined {
    for (let i = 1; i <= LaneState.TEAM_SLOTS; i++) {
        const m = GetTeamMember(i);
        if (m !== undefined && m !== null && m.IsAlive() && LaneConfig.PositionOf(m) === pos && (!botsOnly || m.IsBot())) return m;
    }
    return undefined;
}

/** Enemies visible, or seen within ContestSeenWithin, inside `radius` (ContestRadius) of the spot. Perception goes through LaneState. */
function enemiesNear(bot: Unit, spot: Vector, radius = Settings.Get().ContestRadius): number {
    const cfg = Settings.Get();
    let n = 0;
    for (const e of LaneState.Enemies(bot, bot.GetAssignedLane())) {
        if (!e.visible && e.timeSinceSeen > cfg.ContestSeenWithin) continue;
        if (dist2D(e.location, spot) <= radius) n++;
    }
    return n;
}

function log(bot: Unit, d: RotationDecision, enemies?: number, us?: number): void {
    const extra = enemies !== undefined ? ` enemies=${enemies} ours=${us}` : "";
    HDebug.Log(
        "transitions",
        `rotate pid=${bot.GetPlayerID()} spawn=${d.spawn} go=${tostring(d.go)} side=${d.side ?? "-"} leaveAt=${
            d.leaveAt !== undefined ? string.format("%.1f", d.leaveAt) : "-"
        } reason=${d.reason}${extra}`
    );
    Telemetry.Event("tr_rotate", [
        ["pid", bot.GetPlayerID()],
        ["spawn", d.spawn],
        ["go", d.go],
        ["side", d.side],
        ["leaveAt", d.leaveAt],
        ["reason", d.reason],
        ["enemies", enemies],
        ["ours", us],
    ]);
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
    if (!Phase.LaningTransitions(bot)) {
        const off: RotationDecision = { spawn, go: false, reason: "phase" };
        entries[pid] = { decision: off, arriveAt: -math.huge, announced: true, checkAt: math.huge };
        log(bot, off);
        return off;
    }

    // The pos 5 reads the pos 4's decision, so the pos 4 decides (and draws its rolls) first. A human pos 4 counts as absent.
    const p4 = LaneConfig.PositionOf(bot) === 5 ? teammate(bot, 4, true) : undefined;
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
    if (!Settings.IsOn("Rotation") || !bot.IsBot()) return undefined;
    const e = entries[bot.GetPlayerID()];
    if (e === undefined || !e.decision.go) return undefined;
    const now = DotaTime();
    const d = e.decision;
    const cfg = Settings.Get();
    if (d.leaveAt === undefined || now < d.leaveAt) return undefined;
    if (now <= d.spawn + cfg.RotateLinger) return d;
    const rune = runeAt(d.side);
    return rune !== undefined && now <= d.spawn + cfg.RuneHoldMax && GetRuneStatus(rune) === RUNE_STATUS_AVAILABLE ? d : undefined;
}

/** The power rune id at a side (named by the spot's y, as Runes.NearestPowerSpot does). */
function runeAt(side: "top" | "bot" | undefined): number | undefined {
    for (const rune of [Rune.Power1, Rune.Power2]) {
        if ((GetRuneSpawnLocation(rune).y > 0 ? "top" : "bot") === side) return rune;
    }
    return undefined;
}

/** The power rune id at the active decision's side. */
export function RuneTarget(bot: Unit): number | undefined {
    const d = Active(bot);
    return d !== undefined ? runeAt(d.side) : undefined;
}

/**
 * Whether a rotating support at its spawned rune leaves it on the ground for our mid (who is coming while within
 * ContestMidRadius of the spot). It takes the rune once an enemy hero is near, once our mid is still not coming
 * RuneHoldGrace s after the spawn, or at RuneHoldMax.
 */
export function HoldsRune(bot: Unit, rune: number): boolean {
    const d = Active(bot);
    if (d === undefined || d.spot === undefined || runeAt(d.side) !== rune) return false;
    const cfg = Settings.Get();
    const now = DotaTime();
    const mid = teammate(bot, 2, false);
    const midComing = mid !== undefined && dist2D(mid.GetLocation(), d.spot) <= cfg.ContestMidRadius;
    let take: string | undefined;
    if (now >= d.spawn + cfg.RuneHoldMax) take = "max";
    else if (enemiesNear(bot, d.spot, cfg.RuneHoldEnemyRadius) > 0) take = "enemy";
    else if (now >= d.spawn + cfg.RuneHoldGrace && !midComing) take = "late";
    const state = take ?? "hold";
    const pid = bot.GetPlayerID();
    if (holdState[pid] !== `${d.spawn}:${state}`) {
        holdState[pid] = `${d.spawn}:${state}`;
        Telemetry.Event("tr_rune_hold", [
            ["pid", pid],
            ["spawn", d.spawn],
            ["state", take === undefined ? "hold" : "take"],
            ["reason", take],
            ["mid", mid !== undefined ? math.floor(dist2D(mid.GetLocation(), d.spot)) : undefined],
        ]);
    }
    return take === undefined;
}

/** For our mid: contest the rune harder when a rotating support is with it or at the spot. */
export function MidRuneDesire(bot: Unit): number {
    if (!Settings.IsOn("Rotation") || LaneConfig.PositionOf(bot) !== 2) return 0;
    const cfg = Settings.Get();
    const now = DotaTime();
    for (const pos of [4, 5]) {
        const support = teammate(bot, pos, true);
        const d = support !== undefined ? Active(support) : undefined;
        if (support === undefined || d === undefined || d.spot === undefined) continue;
        // Active covers the support holding a spawned rune for us past RotateLinger.
        if (now < d.spawn - cfg.MidContestFrom) continue;
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

/**
 * Our heroes at or heading for the spot: the support, our mid within ContestMidRadius, another bot support
 * rotating there, and any other human ally standing within ContestRadius of it now (by position only).
 */
function ours(bot: Unit, d: RotationDecision): number {
    const cfg = Settings.Get();
    if (d.spot === undefined) return 1;
    let n = 1;
    const mid = teammate(bot, 2, false);
    if (mid !== undefined && dist2D(mid.GetLocation(), d.spot) <= cfg.ContestMidRadius) n++;
    const other = teammate(bot, LaneConfig.PositionOf(bot) === 4 ? 5 : 4, true);
    const od = other !== undefined ? entries[other.GetPlayerID()] : undefined;
    if (od !== undefined && od.decision.go && od.decision.spawn === d.spawn && od.decision.side === d.side) n++;
    for (let i = 1; i <= LaneState.TEAM_SLOTS; i++) {
        const m = GetTeamMember(i);
        if (m === undefined || m === null || m === mid || m === bot || m.IsBot() || !m.IsAlive()) continue;
        if (dist2D(m.GetLocation(), d.spot) <= cfg.ContestRadius) n++;
    }
    return n;
}

export function Tick(bot: Unit): void {
    if (!Settings.IsOn("Rotation") || !isSupport(bot)) return;
    const cfg = Settings.Get();
    const now = DotaTime();
    Decide(bot, now);
    const e = entries[bot.GetPlayerID()];
    if (e !== undefined && e.decision.go && !Phase.LaningTransitions(bot)) {
        e.decision.go = false;
        e.decision.reason = "phase";
        Intent.Release(bot, SOURCE, BotMode.Rune);
        log(bot, e.decision);
        return;
    }
    if (e !== undefined && e.decision.go && now <= e.decision.spawn + cfg.RotateLinger) {
        const d = e.decision;
        if (!e.announced) {
            e.announced = true;
            say(bot, "say_rune_coming_mid");
        }
        // The lane can turn unsafe between the decision and the first steps out (a kill threat, an enemy TP). A
        // mistake rotation went knowing the lane could not spare it, so it is not re-checked.
        if (d.reason !== "mistake" && d.leaveAt !== undefined && now < d.leaveAt + cfg.RecheckUntilWalk && now >= (e.spareAt ?? -math.huge)) {
            e.spareAt = now + cfg.Refresh;
            const [spare, why] = Busy.LaneCanSpare(bot, LaneConfig.PositionOf(bot) === 5);
            if (!spare) {
                d.go = false;
                d.reason = why;
                Intent.Release(bot, SOURCE, BotMode.Rune);
                log(bot, d);
                say(bot, "say_rune_lost");
                return;
            }
        }
        if (now >= e.checkAt && now >= e.arriveAt - cfg.ContestFrom && d.spot !== undefined) {
            e.checkAt = now + cfg.Refresh;
            const enemies = enemiesNear(bot, d.spot);
            const us = ours(bot, d);
            if (enemies > us) {
                d.go = false;
                d.reason = "contested";
                Intent.Release(bot, SOURCE, BotMode.Rune);
                log(bot, d, enemies, us);
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
    LaneHooks.SetRotationDecidedProbe(bot => Target(bot) !== undefined);
}

RegisterProbes();
