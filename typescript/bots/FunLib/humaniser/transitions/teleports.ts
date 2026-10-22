/**
 * Lane safety and laning-phase transitions (task 12, Task 6): reaction to enemy teleports landing on our lane.
 * A low-skill bot backs off (caution level 1); a skilled bot that is stronger sets up where the TP lands.
 * GetIncomingTeleports only lists TPs the team can see, so what it returns is all a bot may know.
 */
import { Lane, Tower, Unit, Vector } from "bots/ts_libs/dota";
import * as LaneConfig from "bots/FunLib/humaniser/lane_config";
import * as LaneState from "bots/FunLib/humaniser/lane_state";
import * as Camps from "bots/FunLib/humaniser/camps";
import * as Profile from "bots/FunLib/humaniser/profile";
import * as HDebug from "bots/FunLib/humaniser/debug";
import * as Telemetry from "bots/FunLib/humaniser/telemetry";
import * as Settings from "bots/FunLib/humaniser/transitions/settings";
import * as Busy from "bots/FunLib/humaniser/transitions/busy";
import * as Caution from "bots/FunLib/humaniser/transitions/caution";
import * as Phase from "bots/FunLib/humaniser/transitions/phase";

export interface EnemyTp {
    pid: number;
    location: Vector;
    /** Seconds left when the TP was first seen, so seenAt + remaining is when it lands. */
    remaining: number;
    seenAt: number;
}

interface TeamRead {
    at: number;
    list: EnemyTp[];
}

interface Reaction {
    key: string;
    noticeAt: number;
    /** Locked when the notice delay ends; only ever downgraded from setup to back. */
    mode?: "back" | "setup";
}

const ENEMY_T1: Record<number, number> = { [Lane.Top]: Tower.Top1, [Lane.Mid]: Tower.Mid1, [Lane.Bot]: Tower.Bot1 };

let reads: Record<number, TeamRead> = {};
let known: Record<number, EnemyTp> = {};
let reactions: Record<number, Reaction> = {};
let checkAt: Record<number, number> = {};

export function ResetCache(): void {
    reads = {};
    known = {};
    reactions = {};
    checkAt = {};
}

function dist2D(a: Vector, b: Vector): number {
    const dx = a.x - b.x;
    const dy = a.y - b.y;
    return math.sqrt(dx * dx + dy * dy);
}

function clamp01(v: number): number {
    return v < 0 ? 0 : v > 1 ? 1 : v;
}

/** Enemy TPs for `team`, read from the game at most once per TpRefresh. */
export function EnemyTps(team: number): EnemyTp[] {
    const now = DotaTime();
    const cached = reads[team];
    if (cached !== undefined && now - cached.at < Settings.Get().TpRefresh) return cached.list;
    const enemyIds = new LuaSet<number>();
    for (const pid of GetTeamPlayers(team === 2 ? 3 : 2)) enemyIds.add(pid);
    const list: EnemyTp[] = [];
    const present = new LuaSet<number>();
    for (const t of GetIncomingTeleports()) {
        if (t === undefined || t === null || t.location === undefined || t.location === null || !enemyIds.has(t.playerid)) continue;
        present.add(t.playerid);
        let tp = known[t.playerid];
        // A TP that lands later than the one tracked, or somewhere else, is a new cast.
        if (tp === undefined || now + t.time_remaining > tp.seenAt + tp.remaining + 1 || dist2D(t.location, tp.location) > 1) {
            tp = { pid: t.playerid, location: t.location, remaining: t.time_remaining, seenAt: now };
            known[t.playerid] = tp;
            HDebug.Log("transitions", `tp pid=${tp.pid} to=${math.floor(tp.location.x)},${math.floor(tp.location.y)} remaining=${string.format("%.1f", tp.remaining)}`);
            Telemetry.Event("tr_tp", [
                ["team", team],
                ["enemy", tp.pid],
                ["x", math.floor(tp.location.x)],
                ["y", math.floor(tp.location.y)],
                ["remaining", tp.remaining],
            ]);
        }
        list.push(tp);
    }
    for (const [pid] of pairs(known)) if (!present.has(pid) && enemyIds.has(pid)) delete known[pid];
    reads[team] = { at: now, list };
    return list;
}

function ourTower(s: LaneState.LaneSnapshot): Vector {
    return GetLocationAlongLane(s.lane, clamp01(Camps.ToAbsAmount(s.team, s.ourTowerAmount)));
}

/** Where the enemy's T1 in this lane stands, if it still does. Towers are always visible. */
function enemyT1(bot: Unit, s: LaneState.LaneSnapshot): Vector | undefined {
    const id = ENEMY_T1[s.lane];
    if (id === undefined) return undefined;
    const tower = GetTower(bot.GetTeam() === 2 ? 3 : 2, id);
    return tower !== null && tower.IsAlive() ? tower.GetLocation() : undefined;
}

/** The soonest-landing enemy TP aimed at the enemy's T1 in this lane (a TP lands on its own buildings) or the lane front. */
export function IncomingToLane(bot: Unit, s: LaneState.LaneSnapshot): EnemyTp | undefined {
    const radius = Settings.Get().TpRadius;
    const tower = enemyT1(bot, s);
    let best: EnemyTp | undefined;
    for (const tp of EnemyTps(bot.GetTeam())) {
        if ((tower === undefined || dist2D(tp.location, tower) > radius) && dist2D(tp.location, s.frontLoc) > radius) continue;
        if (best === undefined || tp.seenAt + tp.remaining < best.seenAt + best.remaining) best = tp;
    }
    return best;
}

export function Response(bot: Unit, _tp: EnemyTp): "back" | "setup" {
    const cfg = Settings.Get();
    if (LaneConfig.SkillOf(bot) <= cfg.TpSetupSkill) return "back";
    const stronger = LaneConfig.Helpers().WeAreStronger;
    return stronger !== undefined && stronger(bot, cfg.TpStrongerRadius) ? "setup" : "back";
}

function setupPoint(bot: Unit, s: LaneState.LaneSnapshot, tp: EnemyTp): Vector {
    const cfg = Settings.Get();
    const tower = ourTower(s);
    const d = dist2D(tp.location, tower);
    if (d <= 0) return tp.location;
    const ux = (tower.x - tp.location.x) / d;
    const uy = (tower.y - tp.location.y) / d;
    let step = math.min(d, cfg.TpSetupDistance);
    const foe = enemyT1(bot, s);
    if (foe !== undefined) {
        const wx = tp.location.x - foe.x;
        const wy = tp.location.y - foe.y;
        const b = wx * ux + wy * uy;
        const disc = b * b - (wx * wx + wy * wy) + cfg.TpTowerClear * cfg.TpTowerClear;
        // The line from the TP toward our tower leaves the tower's clearance circle at the larger root.
        if (disc >= 0) step = math.max(step, math.min(d, -b + math.sqrt(disc)));
    }
    return Vector(tp.location.x + ux * step, tp.location.y + uy * step, tp.location.z);
}

export function Tick(bot: Unit): void {
    if (!Settings.IsOn("Teleports")) return;
    const now = DotaTime();
    const pid = bot.GetPlayerID();
    if (now < (checkAt[pid] ?? -math.huge)) return;
    checkAt[pid] = now + Settings.Get().Refresh;
    if (!Phase.LaningTransitions(bot)) {
        if (reactions[pid] !== undefined) {
            delete reactions[pid];
            Caution.ForceLevel(bot, 0, -math.huge);
            Caution.ForceSetup(bot, undefined, -math.huge);
        }
        return;
    }
    const s = LaneState.ForBot(bot);
    const tp = s !== undefined ? IncomingToLane(bot, s) : undefined;
    if (s === undefined || tp === undefined) return;

    const key = `${tp.pid}:${tp.seenAt}`;
    let r = reactions[pid];
    if (r === undefined || r.key !== key) {
        r = { key, noticeAt: now + Profile.SampleDelay(bot, "notice") };
        reactions[pid] = r;
    }
    if (now < r.noticeAt) return;

    const until = tp.seenAt + tp.remaining + Settings.Get().TpLinger;
    const response = Response(bot, tp);
    if (r.mode === undefined || (r.mode === "setup" && response === "back")) {
        r.mode = response;
        Telemetry.Event("tr_tp_react", [
            ["pid", pid],
            ["enemy", tp.pid],
            ["mode", response],
            ["lane", s.lane],
            ["until", until],
        ]);
    }
    if (r.mode === "setup") {
        Caution.ForceLevel(bot, 0, -math.huge);
        Caution.ForceSetup(bot, setupPoint(bot, s, tp), until);
    } else {
        Caution.ForceSetup(bot, undefined, -math.huge);
        Caution.ForceLevel(bot, 1, until);
    }
}

export function RegisterProbes(): void {
    Busy.SetTpProbe(bot => {
        if (!Settings.IsOn("Teleports")) return false;
        const s = LaneState.ForBot(bot);
        return s !== undefined && IncomingToLane(bot, s) !== undefined;
    });
}

RegisterProbes();
