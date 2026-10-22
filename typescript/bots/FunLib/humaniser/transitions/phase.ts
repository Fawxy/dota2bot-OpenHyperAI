/**
 * Lane safety and laning-phase transitions (task 12, Task 8): per-bot end of laning and the lost-lane response.
 * IsLaningFor says whether a bot is still laning (its tower fell, a support left for a smoke gank, a core with a
 * farm item has a quiet jungle). A bot whose lane is lost (deaths, last hits, levels) farms or roams instead; with a
 * human partner the bot suggests it and only leaves once the human answers or stays away.
 */
import { BotMode, Lane, Tower, Unit, Vector } from "bots/ts_libs/dota";
import * as Intent from "bots/FunLib/humaniser/intent";
import * as LaneConfig from "bots/FunLib/humaniser/lane_config";
import * as LaneState from "bots/FunLib/humaniser/lane_state";
import * as LaneRoles from "bots/FunLib/humaniser/lane_roles";
import * as Camps from "bots/FunLib/humaniser/camps";
import * as Commands from "bots/FunLib/humaniser/commands";
import * as Orders from "bots/FunLib/humaniser/orders";
import * as Pings from "bots/FunLib/humaniser/pings";
import * as Difficulty from "bots/FunLib/humaniser/difficulty";
import * as Trainer from "bots/FunLib/humaniser/trainer/trainer";
import * as Settings from "bots/FunLib/humaniser/transitions/settings";

export const SOURCE_PHASE = "transitions:phase";
export const SOURCE_LOST = "transitions:lostlane";

export const FARM_ITEMS = ["item_maelstrom", "item_battle_fury", "item_radiance", "item_hand_of_midas", "item_mjollnir"];

const T1: Record<number, number> = { [Lane.Top]: Tower.Top1, [Lane.Mid]: Tower.Mid1, [Lane.Bot]: Tower.Bot1 };

export interface LaneRecord {
    deaths: number[];
    lastHits: { at: number; total: number }[];
}

interface PhaseState {
    record: LaneRecord;
    wasAlive?: boolean;
    wasLaning: boolean;
    checkAt: number;
    levelSeen: Record<number, number>;
    phaseEnded: boolean;
    lostResp: boolean;
    // Once the lost-lane response starts it holds for the rest of the bot's laning: jungle last hits and levels
    // would otherwise read as recovery and send the bot back to the lane it lost.
    lostLatched: boolean;
    cap?: string;
    suggestedAt?: number;
    orderBase?: number;
    capStarted: boolean;
    absentSince?: number;
    jungleSaid: boolean;
}

let states: Record<number, PhaseState> = {};
let laningReads: Record<number, { at: number; value: boolean }> = {};

export function ResetCache(): void {
    states = {};
    laningReads = {};
}

function stateOf(bot: Unit): PhaseState {
    const pid = bot.GetPlayerID();
    let st = states[pid];
    if (st === undefined) {
        st = { record: { deaths: [], lastHits: [] }, checkAt: -math.huge, wasLaning: false, levelSeen: {}, phaseEnded: false, lostResp: false, lostLatched: false, capStarted: false, jungleSaid: false };
        states[pid] = st;
    }
    return st;
}

export function Record(bot: Unit): LaneRecord {
    return stateOf(bot).record;
}

function dist2D(a: Vector, b: Vector): number {
    const dx = a.x - b.x;
    const dy = a.y - b.y;
    return math.sqrt(dx * dx + dy * dy);
}

function towerDown(team: number, lane: Lane): boolean {
    const id = T1[lane];
    if (id === undefined) return false;
    const t = GetTower(team, id);
    return t === undefined || t === null || !t.IsAlive();
}

function hasFarmItem(bot: Unit): boolean {
    for (const name of FARM_ITEMS) {
        const slot = bot.FindItemSlot(name);
        if (slot !== undefined && slot >= 0 && slot <= 8) return true;
    }
    return false;
}

/** No enemy hero seen recently near our nearest jungle camp. With no camp known the jungle is not safe. */
function jungleSafe(bot: Unit): boolean {
    const cfg = Settings.Get();
    const team = bot.GetTeam();
    const loc = bot.GetLocation();
    let camp: Vector | undefined;
    let best = math.huge;
    for (const sp of Camps.Spawners()) {
        if (sp.team !== team) continue;
        const c = Camps.BoxCenter(sp);
        const d = dist2D(c, loc);
        if (d < best) {
            best = d;
            camp = c;
        }
    }
    if (camp === undefined) return false;
    for (const e of LaneState.Enemies(bot, bot.GetAssignedLane())) {
        if ((e.visible || e.timeSinceSeen <= cfg.JungleSeenWindow) && dist2D(e.location, camp) <= cfg.JungleCampRadius) return false;
    }
    return true;
}

export function IsLaningFor(bot: Unit): boolean {
    if (!LaneConfig.InLaningPhase()) return false;
    const cfg = Settings.Get();
    const team = bot.GetTeam();
    const lane = bot.GetAssignedLane();
    if (towerDown(team, lane) || towerDown(team === 2 ? 3 : 2, lane)) return false;
    const pos = LaneConfig.PositionOf(bot);
    const now = DotaTime();
    if (pos !== undefined && pos >= 4) {
        if (bot.GetLevel() > cfg.SupportLevel && now >= cfg.SupportFrom && now <= cfg.SupportTo) {
            if (Commands.HasSmoke(bot) || Orders.GetAccepted(bot, "ATTACK") !== undefined || Orders.GetAccepted(bot, "SMOKE") !== undefined) return false;
        }
    } else if (pos !== undefined && hasFarmItem(bot) && jungleSafe(bot)) {
        return false;
    }
    return true;
}

/**
 * Whether the laning-phase transitions (caution and its callout, the TP reaction, support rotations) apply to this
 * bot: IsLaningFor with the Phase flag on, the global laning phase otherwise. Never for the trainer self-test bot.
 * Read at most once per Refresh, since the caution probes ask every frame.
 */
export function LaningTransitions(bot: Unit): boolean {
    const pid = bot.GetPlayerID();
    const now = DotaTime();
    const r = laningReads[pid];
    if (r !== undefined && now >= r.at && now - r.at < Settings.Get().Refresh) return r.value;
    const value = !Trainer.IsSelfTestBot(bot) && (Settings.IsOn("Phase") ? IsLaningFor(bot) : LaneConfig.InLaningPhase());
    laningReads[pid] = { at: now, value };
    return value;
}

export interface LostInput {
    deathsInWindow: number;
    lhPerMin: number;
    expectedLhPerMin: number;
    levelGap: number;
}

export function LaneLostPure(i: LostInput): LuaMultiReturn<[boolean, string]> {
    const cfg = Settings.Get();
    if (i.deathsInWindow >= cfg.LostDeaths) return $multi(true, "deaths");
    if (i.expectedLhPerMin > 0 && i.lhPerMin / i.expectedLhPerMin < cfg.LostLHRatio) return $multi(true, "lasthits");
    if (i.levelGap >= cfg.LostLevelGap) return $multi(true, "levels");
    return $multi(false, "");
}

function lastHits(bot: Unit): number {
    return (bot as Unit & { GetLastHits(): number }).GetLastHits();
}

function pruneRecord(r: LaneRecord, now: number): void {
    const from = now - Settings.Get().LostWindow;
    r.deaths = r.deaths.filter(t => t >= from);
    r.lastHits = r.lastHits.filter(h => h.at >= from);
}

/**
 * Highest lane opponent level minus ours, from visible units or the last level seen; 0 when none is known. Only
 * cores are judged on levels: a support is often two levels under the enemy cores in an even lane.
 */
function levelGapOf(bot: Unit, st: PhaseState, s: LaneState.LaneSnapshot | undefined): number {
    const pos = LaneConfig.PositionOf(bot);
    if (s === undefined || pos === undefined || pos > 3) return 0;
    const radius = Settings.Get().SpareLaneRadius;
    let top = 0;
    for (const e of LaneState.Enemies(bot, s.lane)) {
        if (dist2D(e.location, s.frontLoc) > radius) continue;
        const level = e.visible && e.unit !== undefined ? e.unit.GetLevel() : st.levelSeen[e.pid];
        if (level !== undefined && level > top) top = level;
    }
    return top > 0 ? top - bot.GetLevel() : 0;
}

export function LaneLost(bot: Unit): LuaMultiReturn<[boolean, string]> {
    const cfg = Settings.Get();
    const st = stateOf(bot);
    const now = DotaTime();
    pruneRecord(st.record, now);
    const pos = LaneConfig.PositionOf(bot);
    // Only cores are judged on last hits (a support is not expected to take them), and only once the samples span
    // LostMinSpan; with no expected rate the pure check skips the rule.
    let rate = 0;
    let expected = 0;
    const first = st.record.lastHits[0];
    if (pos !== undefined && pos <= 3 && first !== undefined && now - first.at >= cfg.LostMinSpan) {
        expected = Settings.Lerp(cfg.ExpectedLHPerMin, LaneConfig.SkillOf(bot));
        rate = ((lastHits(bot) - first.total) / (now - first.at)) * 60;
    }
    return LaneLostPure({
        deathsInWindow: st.record.deaths.length,
        lhPerMin: rate,
        expectedLhPerMin: expected,
        levelGap: levelGapOf(bot, st, LaneState.ForBot(bot)),
    });
}

function partnerOf(bot: Unit): LaneState.LaneHero | undefined {
    const s = LaneState.ForBot(bot);
    return s !== undefined ? LaneRoles.Partner(bot, s) : undefined;
}

function sample(bot: Unit, st: PhaseState, now: number): void {
    const cfg = Settings.Get();
    const alive = bot.IsAlive();
    // A death while the bot was off-lane (farming, ganking) says nothing about the lane.
    if (st.wasAlive === true && !alive && st.wasLaning) st.record.deaths.push(now);
    st.wasAlive = alive;
    st.wasLaning = IsLaningFor(bot);
    if (alive && now >= cfg.LostLHFrom) {
        const last = st.record.lastHits[st.record.lastHits.length - 1];
        if (last === undefined || now - last.at >= cfg.LHSampleGap) st.record.lastHits.push({ at: now, total: lastHits(bot) });
        const s = LaneState.ForBot(bot);
        if (s !== undefined) {
            for (const e of LaneState.Enemies(bot, s.lane)) if (e.visible && e.unit !== undefined) st.levelSeen[e.pid] = e.unit.GetLevel();
        }
    }
    pruneRecord(st.record, now);
}

/** Advances the human-partner flow; true while the bot should keep laning because it still waits on the human. */
function humanWaiting(bot: Unit, st: PhaseState, now: number): boolean {
    const partner = partnerOf(bot);
    if (partner === undefined || partner.isBot) return false;
    if (st.capStarted) return false;
    const cfg = Settings.Get();
    if (st.suggestedAt !== undefined) {
        const base = st.orderBase;
        const order = Orders.GetFor(bot);
        const absent = !partner.alive || partner.distToFront > LaneConfig.Settings().Thresholds.CoreAbsentDist;
        if (absent) {
            if (st.absentSince === undefined) st.absentSince = now;
        } else {
            st.absentSince = undefined;
        }
        if (
            Pings.HumanPingNear(bot.GetTeam(), bot.GetLocation(), cfg.LostPingRadius, now - st.suggestedAt) ||
            (order !== undefined && order.id !== base) ||
            (st.absentSince !== undefined && now - st.absentSince >= cfg.AbsentHold)
        ) {
            st.capStarted = true;
            return false;
        }
    }
    if ((st.suggestedAt === undefined || now - st.suggestedAt >= cfg.SuggestCooldown) && Orders.Say(bot, "say_lane_lost_roam", cfg.SuggestCooldown)) {
        st.suggestedAt = now;
        st.orderBase = Orders.GetFor(bot)?.id;
        st.absentSince = undefined;
    }
    return true;
}

function evaluate(bot: Unit, st: PhaseState, now: number): void {
    st.phaseEnded = false;
    st.lostResp = false;
    st.cap = undefined;
    // The latch outlives a farm-item "not laning" read (jungle last hits would look like recovery); only
    // the end of laning itself or a fallen T1 in this lane clears it.
    const team = bot.GetTeam();
    const lane = bot.GetAssignedLane();
    if (!LaneConfig.InLaningPhase() || towerDown(team, lane) || towerDown(team === 2 ? 3 : 2, lane)) st.lostLatched = false;
    if (!LaneConfig.InLaningPhase()) return;
    if (Settings.IsOn("Phase") && !st.wasLaning) {
        st.phaseEnded = true;
        st.cap = SOURCE_PHASE;
    }
    let lost = false;
    if (Settings.IsOn("LostLane")) lost = st.lostLatched || LaneLost(bot)[0];
    if (!lost) {
        st.capStarted = false;
        st.absentSince = undefined;
    } else if (st.lostLatched || !humanWaiting(bot, st, now)) {
        st.lostResp = true;
        st.lostLatched = true;
        st.cap = st.cap ?? SOURCE_LOST;
    }
    if (!st.phaseEnded && !st.lostResp) {
        st.jungleSaid = false;
        return;
    }
    const pos = LaneConfig.PositionOf(bot);
    if (!st.jungleSaid && pos !== undefined && pos <= 3 && Difficulty.IsAllyOfHuman(bot)) {
        st.jungleSaid = Orders.Say(bot, "say_going_jungle", Settings.Get().SuggestCooldown);
    }
}

export function Tick(bot: Unit): void {
    if (!Settings.IsOn("Phase") && !Settings.IsOn("LostLane")) {
        Intent.Release(bot, SOURCE_PHASE, BotMode.Laning);
        Intent.Release(bot, SOURCE_LOST, BotMode.Laning);
        return;
    }
    const st = stateOf(bot);
    const now = DotaTime();
    if (now >= st.checkAt) {
        st.checkAt = now + Settings.Get().Refresh;
        sample(bot, st, now);
        evaluate(bot, st, now);
    }
    const cap = Settings.Get().LaningCap;
    for (const source of [SOURCE_PHASE, SOURCE_LOST]) {
        if (st.cap === source) Intent.Claim(bot, { source, tier: "TRANSITION", mode: BotMode.Laning, cap });
        else Intent.Release(bot, source, BotMode.Laning);
    }
}

/** Farm-mode hook: a core whose laning has ended (or whose lane is lost, with no human left waiting) may farm. */
export function FarmAllowedInLaning(bot: Unit): boolean {
    const pos = LaneConfig.PositionOf(bot);
    if (pos === undefined || pos > 3) return false;
    const st = states[bot.GetPlayerID()];
    if (st === undefined) return false;
    return (Settings.IsOn("Phase") && st.phaseEnded) || (Settings.IsOn("LostLane") && st.lostResp);
}
