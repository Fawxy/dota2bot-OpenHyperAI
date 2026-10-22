/**
 * Fight read (task 11): per bot, whether there is a trade window on a lane enemy, a reason to respect the enemy, and
 * whether the bot noticed. Decide() holds the rules over plain inputs; ReadFor gathers them from the cooldown memory,
 * the lane snapshot and the perception-filtered lane enemy list (no unit scans here).
 */
import { Lane, Team, Tower, Unit, Vector } from "bots/ts_libs/dota";
import * as LaneFightConfig from "bots/FunLib/humaniser/lane_fight_config";
import * as LaneConfig from "bots/FunLib/humaniser/lane_config";
import * as LaneState from "bots/FunLib/humaniser/lane_state";
import * as CooldownMemory from "bots/FunLib/humaniser/cooldown_memory";
import * as CastWatch from "bots/FunLib/humaniser/cast_watch";
import * as AbilityClasses from "bots/FunLib/humaniser/ability_classes";
import * as Harass from "bots/FunLib/humaniser/harass";
import * as Profile from "bots/FunLib/humaniser/profile";
import * as Telemetry from "bots/FunLib/humaniser/telemetry";

export type Window = "spell" | "lasthit" | "level" | "position";
export type Respect = "their_spike" | "their_ult" | "outnumbered";
export interface Read {
    target?: Unit;
    window?: Window;
    respect?: Respect;
    noticed: boolean;
}

export interface Inputs {
    target: boolean;
    keyThreatsDown: number;
    lastHit: boolean;
    spike: "ours" | "theirs" | undefined;
    // Distance the target stands past its own creep front towards our base; negative when behind it.
    aheadOfFront: number;
    nearOurTower: boolean;
    theirUltReady: boolean;
    enemiesNear: number;
    ourLaners: number;
}

const TARGET_RANGE = 1200;
const TOWER_RANGE = 700;
const LANE_RADIUS = 2500;
const MISSING_COUNTS = 10;
const ULT_LEVEL = 6;
// A window instance survives gaps shorter than this; a longer one makes the next sighting a new instance.
const INSTANCE_GAP = 1;
const SPIKE_LEVELS = [6, 2];
const TOWER_IDS: Record<number, number[]> = {
    [Lane.Top]: [Tower.Top1, Tower.Top2, Tower.Top3],
    [Lane.Mid]: [Tower.Mid1, Tower.Mid2, Tower.Mid3],
    [Lane.Bot]: [Tower.Bot1, Tower.Bot2, Tower.Bot3],
};

interface Spike {
    // undefined when both sides reached the level on the same read: nobody had the spike.
    side?: "ours" | "theirs";
    at: number;
    until: number;
}

interface SpikeTrack {
    ours: Record<number, number>;
    theirs: Record<number, number>;
    spikes: Record<number, Spike>;
}

interface Instance {
    lastApplied: number;
    noticed?: boolean;
}

const spikeTracks: Record<string, SpikeTrack> = {};
const readCache: Record<number, { at: number; read: Read }> = {};
const instances: Record<number, Record<string, Instance>> = {};

function dist2D(a: Vector, b: Vector): number {
    const dx = a.x - b.x;
    const dy = a.y - b.y;
    return math.sqrt(dx * dx + dy * dy);
}

function enemyTeamOf(team: number): number {
    return team === Team.Radiant ? Team.Dire : Team.Radiant;
}

export function RespectFrom(i: Inputs): Respect | undefined {
    if (i.spike === "theirs") return "their_spike";
    if (i.theirUltReady) return "their_ult";
    if (i.enemiesNear > i.ourLaners) return "outnumbered";
    return undefined;
}

/** Every window that applies, in the order they are checked; the first wins. */
export function WindowsFrom(i: Inputs): Window[] {
    const list: Window[] = [];
    if (!i.target) return list;
    const s = LaneFightConfig.Settings();
    if (i.keyThreatsDown > s.KeyThreatsWindow) list.push("spell");
    if (i.lastHit) list.push("lasthit");
    if (i.spike === "ours") list.push("level");
    if (i.aheadOfFront > s.OutOfPosition || i.nearOurTower) list.push("position");
    return list;
}

export function Decide(i: Inputs): { window?: Window; respect?: Respect } {
    const respect = RespectFrom(i);
    if (respect !== undefined) return { respect };
    return { window: WindowsFrom(i)[0] };
}

function spikeTrack(team: number, lane: Lane): SpikeTrack {
    const key = `${team}:${lane}`;
    let t = spikeTracks[key];
    if (t === undefined) {
        t = { ours: {}, theirs: {}, spikes: {} };
        spikeTracks[key] = t;
    }
    return t;
}

/** Records the first time each side's highest laner level reached 2 and 6; the side that got there first spikes. */
export function ObserveLevels(team: number, lane: Lane, ourMax: number, theirMax: number, now: number): void {
    if (now < 0) return;
    const t = spikeTrack(team, lane);
    for (const level of SPIKE_LEVELS) {
        if (t.ours[level] === undefined && ourMax >= level) t.ours[level] = now;
        if (t.theirs[level] === undefined && theirMax >= level) t.theirs[level] = now;
        if (t.spikes[level] !== undefined) continue;
        const ours = t.ours[level];
        const theirs = t.theirs[level];
        if (ours === undefined && theirs === undefined) continue;
        if (ours !== undefined && theirs !== undefined && ours === theirs) {
            t.spikes[level] = { at: now, until: now };
            continue;
        }
        const s = LaneFightConfig.Settings();
        const side = theirs === undefined || (ours !== undefined && ours < theirs) ? "ours" : "theirs";
        const at = side === "ours" ? ours! : theirs!;
        t.spikes[level] = { side, at, until: at + RandomFloat(s.LevelSpikeMin, s.LevelSpikeMax) };
    }
}

/** The side with a live level spike on (team, lane), from team's point of view; it ends early once the other side catches up. */
export function LevelSpike(team: number, lane: Lane, now: number): "ours" | "theirs" | undefined {
    if (now < 0) return undefined;
    const t = spikeTracks[`${team}:${lane}`];
    if (t === undefined) return undefined;
    for (const level of SPIKE_LEVELS) {
        const spike = t.spikes[level];
        if (spike === undefined || spike.side === undefined || now < spike.at || now >= spike.until) continue;
        // The other side reaching the level too ends the spike (an if, not a ternary: the branch value can be nil).
        let caughtUp = t.ours[level];
        if (spike.side === "ours") caughtUp = t.theirs[level];
        if (caughtUp !== undefined && caughtUp <= now) continue;
        return spike.side;
    }
    return undefined;
}

function usable(u: Unit | undefined): u is Unit {
    if (u === undefined || u === null || u.IsNull()) return false;
    if (!u.IsAlive() || !u.CanBeSeen() || u.IsIllusion() || u.GetLocation() === undefined) return false;
    const suspicious = LaneConfig.Helpers().IsSuspiciousIllusion;
    return suspicious === undefined || !suspicious(u);
}

function nearestTower(team: number, lane: Lane): Unit | undefined {
    for (const id of TOWER_IDS[lane] ?? []) {
        const tower = GetTower(team, id);
        if (tower !== null && tower !== undefined && tower.IsAlive()) return tower;
    }
    return undefined;
}

// Both amounts come from locations in one frame (team's), whichever team's script is reading.
function aheadOfFront(team: number, lane: Lane, loc: Vector): number {
    const front = GetLaneFrontLocation(enemyTeamOf(team), lane, 0);
    const d = dist2D(loc, front);
    return LaneState.TeamAmountAt(team, lane, loc) < LaneState.TeamAmountAt(team, lane, front) ? d : -d;
}

function keyAbilities(enemy: Unit): string[] {
    const names: string[] = [];
    for (const a of CastWatch.AbilitiesOf(enemy)) {
        if (a.learned && AbilityClasses.Classify(a.name, a.ult) === "key") names.push(a.name);
    }
    return names;
}

function ultReady(pid: number, enemy: Unit, enemyPid: number, now: number, skill: number): boolean {
    if (GetHeroLevel(enemyPid) < ULT_LEVEL) return false;
    for (const a of CastWatch.AbilitiesOf(enemy)) {
        if (!a.ult || a.item || !a.learned) continue;
        const [ready] = CooldownMemory.ProbablyReady(pid, enemyPid, a.name, true, now, skill);
        if (ready) return true;
    }
    return false;
}

function instanceFor(pid: number, key: string, now: number): Instance {
    let byKey = instances[pid];
    if (byKey === undefined) {
        byKey = {};
        instances[pid] = byKey;
    }
    let inst = byKey[key];
    if (inst === undefined || now - inst.lastApplied > INSTANCE_GAP) {
        inst = { lastApplied: now };
        byKey[key] = inst;
    }
    inst.lastApplied = now;
    return inst;
}

function gather(bot: Unit, snap: LaneState.LaneSnapshot, now: number): { inputs: Inputs; target?: Unit } {
    const pid = bot.GetPlayerID();
    const team = bot.GetTeam();
    const lane = snap.lane;
    const skill = Profile.Get(bot).skill;
    const botLoc = bot.GetLocation();

    let ourLaners = 0;
    let ourMax = 0;
    for (const h of snap.allies) {
        if (!h.assigned) continue;
        if (h.alive) ourLaners++;
        ourMax = math.max(ourMax, GetHeroLevel(h.pid));
    }

    let target: Unit | undefined;
    let targetDist = math.huge;
    let enemiesNear = 0;
    let theirMax = 0;
    let theirUltReady = false;
    for (const e of LaneState.Enemies(bot, lane)) {
        if (e === undefined || e.location === undefined) continue;
        const unit = e.visible && usable(e.unit) ? e.unit : undefined;
        const loc = unit !== undefined ? unit.GetLocation() : e.location;
        if (dist2D(loc, snap.frontLoc) > LANE_RADIUS) continue;
        theirMax = math.max(theirMax, GetHeroLevel(e.pid));
        if (unit === undefined) {
            if (!e.visible && e.timeSinceSeen <= MISSING_COUNTS) enemiesNear++;
            continue;
        }
        enemiesNear++;
        if (!theirUltReady && ultReady(pid, unit, e.pid, now, skill)) theirUltReady = true;
        const d = dist2D(botLoc, loc);
        if (d <= TARGET_RANGE && d < targetDist) {
            target = unit;
            targetDist = d;
        }
    }

    ObserveLevels(team, lane, ourMax, theirMax, now);
    const inputs: Inputs = {
        target: target !== undefined,
        keyThreatsDown: 0,
        lastHit: false,
        spike: LevelSpike(team, lane, now),
        aheadOfFront: -math.huge,
        nearOurTower: false,
        theirUltReady,
        enemiesNear,
        ourLaners,
    };
    if (target !== undefined) {
        const loc = target.GetLocation();
        inputs.keyThreatsDown = CooldownMemory.KeyThreatsDown(pid, target.GetPlayerID(), keyAbilities(target), now, skill);
        inputs.lastHit = Harass.IsLastHitAttempt(target, snap.ally.units) !== undefined;
        inputs.aheadOfFront = aheadOfFront(team, lane, loc);
        const tower = nearestTower(team, lane);
        inputs.nearOurTower = tower !== undefined && dist2D(loc, tower.GetLocation()) <= TOWER_RANGE;
    }
    return { inputs, target };
}

function compute(bot: Unit, now: number): Read {
    if (now < 0 || !LaneFightConfig.IsActive()) return { noticed: false };
    const snap = LaneState.ForBot(bot);
    if (snap === undefined) return { noticed: false };
    const { inputs, target } = gather(bot, snap, now);
    const respect = RespectFrom(inputs);
    if (respect !== undefined || target === undefined) return { target, respect, noticed: false };
    const windows = WindowsFrom(inputs);
    if (windows.length === 0) return { target, noticed: false };

    const pid = bot.GetPlayerID();
    const targetPid = target.GetPlayerID();
    let winner: Instance | undefined;
    for (const w of windows) {
        const inst = instanceFor(pid, `${w}:${targetPid}`, now);
        if (winner === undefined) winner = inst;
    }
    const window = windows[0];
    if (winner!.noticed === undefined) {
        winner!.noticed = RandomFloat(0, 1) < LaneFightConfig.Curve("Notice", Profile.Get(bot).skill);
        Telemetry.Event("lanefight_window", [
            ["pid", pid],
            ["window", window],
            ["target", targetPid],
            ["noticed", winner!.noticed ? 1 : 0],
        ]);
    }
    return { target, window, noticed: winner!.noticed! };
}

/** Cached per pid for WindowReadEvery. */
export function ReadFor(bot: Unit, now: number): Read {
    const pid = bot.GetPlayerID();
    const cached = readCache[pid];
    if (cached !== undefined && now >= cached.at && now - cached.at < LaneFightConfig.Settings().WindowReadEvery) return cached.read;
    const read = compute(bot, now);
    readCache[pid] = { at: now, read };
    return read;
}
