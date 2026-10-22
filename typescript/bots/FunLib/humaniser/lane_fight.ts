/**
 * Lane fight facade (task 11): trades and kill setups with imperfect cooldown memory. Tick runs per bot per frame
 * from Humaniser.Tick; ReadFor is the fight read (trade and respect windows); CheckKill is the kill check.
 *
 * The executor runs through mode_team_roam_generic: RoamDesire (its GetDesire) starts and ends trades and commits and
 * posts a FIGHT floor claim on team_roam while one runs; Think (its Think) attacks the target. Partner sync, kill calls
 * and escape aborts are Task 8's; here a bot commits on its own kill check.
 */
import { BotMode, Unit, Vector } from "bots/ts_libs/dota";
import * as LaneFightConfig from "bots/FunLib/humaniser/lane_fight_config";
import * as LaneConfig from "bots/FunLib/humaniser/lane_config";
import * as LaneState from "bots/FunLib/humaniser/lane_state";
import * as AbilityClasses from "bots/FunLib/humaniser/ability_classes";
import * as CooldownMemory from "bots/FunLib/humaniser/cooldown_memory";
import * as CastWatch from "bots/FunLib/humaniser/cast_watch";
import * as FightRead from "bots/FunLib/humaniser/fight_read";
import * as KillCheck from "bots/FunLib/humaniser/kill_check";
import * as LaneRoles from "bots/FunLib/humaniser/lane_roles";
import * as CampJobs from "bots/FunLib/humaniser/camp_jobs";
import * as Intent from "bots/FunLib/humaniser/intent";
import * as Orders from "bots/FunLib/humaniser/orders";
import * as Profile from "bots/FunLib/humaniser/profile";
import * as Telemetry from "bots/FunLib/humaniser/telemetry";
import * as HDebug from "bots/FunLib/humaniser/debug";

export { LaneFightConfig as Config, AbilityClasses, CooldownMemory, CastWatch, FightRead, KillCheck };

export function IsActive(): boolean {
    return LaneFightConfig.IsActive();
}

export function Tick(bot: Unit): void {
    if (!LaneFightConfig.IsActive() || !LaneFightConfig.AppliesTo(bot) || !LaneConfig.InLaningPhase()) return;
    // A bot with no assigned lane (no lane snapshot) has no lane enemies to watch.
    if (LaneFightConfig.IsOn("Memory") && LaneState.ForBot(bot) !== undefined) CastWatch.Tick(bot);
}

/** The fight read for `bot`; callers act on it. Guarded in index.ts: an error reads as no window. */
export function ReadFor(bot: Unit, now: number): FightRead.Read {
    return FightRead.ReadFor(bot, now);
}

/** The kill check on `target` with `partners`; guarded in index.ts: an error reads as no check. */
export function CheckKill(bot: Unit, partners: (Unit | undefined)[], target: Unit, now: number): KillCheck.KillResult | undefined {
    return KillCheck.Check(bot, partners, target, now);
}

// ------------------------------------------------------------------------------------------------ executor

export type Phase = "idle" | "trade" | "commit" | "wait_partner";

interface Instance {
    seen: number;
    started: boolean;
    gates: Record<string, boolean>;
}

interface FightState {
    phase: Phase;
    target?: Unit;
    targetPid?: number;
    lastLoc?: Vector;
    startedAt: number;
    // TradeDuration runs from the first in-range attack order (or the target seen as the bot's attack target).
    clockAt?: number;
    // team_roam or attack was the active mode at some point in this phase.
    tookOver: boolean;
    // Window instances this phase spends; given back if the phase never took over.
    spent: Instance[];
    retreatSince?: number;
    hits: number;
    lastAttack: number;
    fogSince?: number;
    farSince?: number;
    offModeSince?: number;
    // Hysteresis on the fight read: the window key of consecutive fresh reads.
    lastRead?: FightRead.Read;
    streakKey?: string;
    streak: number;
    // The kill check's first pass on this target, and the reaction delay drawn for it.
    killPid?: number;
    killSince?: number;
    killDelay: number;
    lastMargin?: number;
    lastWindow?: string;
    instances: Record<string, Instance>;
}

// A window or kill pass seen again within this gap is the same instance (FightRead's INSTANCE_GAP).
const INSTANCE_GAP = 1;
// End conditions other than HP, death, fog and an unkillable target must hold this long.
const END_GRACE = 0.5;
// Another mode active this long during a phase ends it; Valve's attack mode is "going on someone" and does not.
const MODE_GRACE = 1;
// team_roam drops a target farther than this.
const LEASH = 1800;
const RANGE_SLACK = 50;
// A trade starts only on a target this far beyond the bot's attack range at most.
const TRADE_REACH = 400;
// The engine's bonus on the active mode's desire.
const ACTIVE_BOOST = 1.1;
const FOCUS_SOURCE = "lanefight:commit_focus";
// The errands and laning a commit caps; attack, defend and push stay free, retreat is held separately.
const FOCUS_MODES: BotMode[] = [BotMode.Laning, BotMode.Ward, BotMode.Rune, BotMode.SecretShop, BotMode.SideShop, BotMode.Roam];
// Modes a lane fight may start from.
const START_MODES: BotMode[] = [BotMode.Laning, BotMode.TeamRoam, BotMode.Attack];

const fights: Record<number, FightState> = {};

function stateFor(bot: Unit): FightState {
    const pid = bot.GetPlayerID();
    let s = fights[pid];
    if (s === undefined) {
        s = { phase: "idle", startedAt: 0, tookOver: false, spent: [], hits: 0, lastAttack: 0, streak: 0, killDelay: 0, instances: {} };
        fights[pid] = s;
    }
    return s;
}

function gatesOpen(bot: Unit): boolean {
    if (!LaneFightConfig.IsActive() || !LaneFightConfig.AppliesTo(bot) || !LaneConfig.InLaningPhase()) return false;
    return LaneFightConfig.IsOn("Trade") || LaneFightConfig.IsOn("Kill");
}

function hpFraction(u: Unit): number {
    const max = u.GetMaxHealth();
    return max > 0 ? u.GetHealth() / max : 0;
}

function floorOf(phase: Phase): number {
    const s = LaneFightConfig.Settings();
    return phase === "commit" ? s.CommitFloor : s.TradeFloor;
}

function touch(s: FightState, key: string, now: number): Instance {
    let inst = s.instances[key];
    if (inst === undefined || now - inst.seen > INSTANCE_GAP) {
        inst = { seen: now, started: false, gates: {} };
        s.instances[key] = inst;
    }
    inst.seen = now;
    return inst;
}

function gate(bot: Unit, inst: Instance, reason: string): void {
    if (inst.gates[reason] === true) return;
    inst.gates[reason] = true;
    Telemetry.Event("lanefight_gate", [
        ["pid", bot.GetPlayerID()],
        ["gate", reason],
    ]);
}

function priorityLive(bot: Unit): boolean {
    return Intent.PriorityLive(bot) || Orders.GetFor(bot) !== undefined;
}

/** Why a trade or commit must not start now, else undefined. */
function startBlocked(bot: Unit): string | undefined {
    const cfg = LaneFightConfig.Settings();
    const mode = bot.GetActiveMode();
    let modeOk = false;
    for (const m of START_MODES) if (m === mode) modeOk = true;
    if (!modeOk) return `mode:${HDebug.ModeName(mode)}`;
    if (hpFraction(bot) < cfg.StartHP) return "low-hp";
    // Retreat is scored before team_roam in each round, so this is this round's retreat desire. With intent off there
    // is no resolved retreat desire to read, so the StartMaxRetreat gate is not enforced.
    const retreat = Intent.Resolved(bot, BotMode.Retreat);
    if (retreat !== undefined && retreat >= cfg.StartMaxRetreat) return "retreat";
    if (CampJobs.Active(bot)) return "camp";
    if (CampJobs.Covering(bot)) return "cover";
    if (priorityLive(bot)) return "priority";
    return undefined;
}

function partnerUnits(bot: Unit, snap: LaneState.LaneSnapshot): Unit[] {
    const partner = LaneRoles.Partner(bot, snap);
    return partner !== undefined && partner.unit !== undefined && !partner.unit.IsNull() ? [partner.unit] : [];
}

function focusCap(): number {
    const cfg = LaneFightConfig.Settings();
    return cfg.CommitFloor / ACTIVE_BOOST - cfg.CommitFocusMargin;
}

/**
 * The phase's floor on team_roam. A commit also caps laning and the errands (as 07's camp jobs do), and retreat while
 * HP is at least CommitHoldHP: retreat's laning-phase creep-damage branch bids 0.8-0.9 at healthy HP. SURVIVAL and
 * HUMAN_ORDER sit on higher tiers, and StopHP ends the phase.
 */
function claim(bot: Unit, phase: Phase): boolean {
    const posted = Intent.Claim(bot, { source: `lanefight:${phase}`, tier: "FIGHT", mode: BotMode.TeamRoam, floor: floorOf(phase) });
    if (!posted || phase !== "commit") return posted;
    const cap = focusCap();
    for (const mode of FOCUS_MODES) Intent.Claim(bot, { source: FOCUS_SOURCE, tier: "FIGHT", mode, cap });
    if (hpFraction(bot) >= LaneFightConfig.Settings().CommitHoldHP) Intent.Claim(bot, { source: FOCUS_SOURCE, tier: "FIGHT", mode: BotMode.Retreat, cap });
    else Intent.Release(bot, FOCUS_SOURCE, BotMode.Retreat);
    return posted;
}

function start(bot: Unit, s: FightState, phase: Phase, target: Unit, inst: Instance, now: number, detail: [string, any]): void {
    inst.started = true;
    s.spent = [inst];
    s.tookOver = false;
    s.clockAt = undefined;
    s.retreatSince = undefined;
    s.phase = phase;
    s.target = target;
    s.targetPid = target.GetPlayerID();
    s.lastLoc = target.GetLocation();
    s.startedAt = now;
    s.hits = 0;
    s.lastAttack = bot.GetLastAttackTime();
    s.fogSince = undefined;
    s.farSince = undefined;
    // The bot is usually in laning when the floor is first posted; team_roam takes over at the next round.
    s.offModeSince = now;
    claim(bot, phase);
    Telemetry.Event("lanefight_start", [["pid", bot.GetPlayerID()], ["phase", phase], ["target", s.targetPid], detail]);
    HDebug.Log("lanefight", `start pid=${bot.GetPlayerID()} phase=${phase} target=${s.targetPid}`);
}

function end(bot: Unit, s: FightState, reason: string): void {
    const phase = s.phase;
    if (phase === "idle") return;
    Intent.ReleaseSource(bot, `lanefight:${phase}`);
    Intent.ReleaseSource(bot, FOCUS_SOURCE);
    // A claim that never won the takeover did not use the window.
    if (!s.tookOver) for (const inst of s.spent) inst.started = false;
    s.spent = [];
    // A restart needs the window on two fresh reads again.
    s.streak = 0;
    s.streakKey = undefined;
    s.phase = "idle";
    s.target = undefined;
    s.targetPid = undefined;
    bot.SetTarget(undefined as any);
    Telemetry.Event("lanefight_end", [
        ["pid", bot.GetPlayerID()],
        ["phase", phase],
        ["reason", reason],
        ["hits", s.hits],
    ]);
    HDebug.Log("lanefight", `end pid=${bot.GetPlayerID()} phase=${phase} reason=${reason}`);
}

function lastHits(bot: Unit, s: FightState): void {
    const at = bot.GetLastAttackTime();
    if (at <= s.lastAttack) return;
    s.lastAttack = at;
    if (attackingTarget(bot, s)) s.hits++;
}

function attackingTarget(bot: Unit, s: FightState): boolean {
    const t = bot.GetAttackTarget() as Unit | undefined;
    return t !== undefined && !t.IsNull() && t.IsHero() && t.GetPlayerID() === s.targetPid;
}

/** The lane-enemy entry for the target, from the perception-filtered cached list. */
function targetEntry(bot: Unit, s: FightState): LaneState.LaneEnemy | undefined {
    for (const e of LaneState.Enemies(bot, bot.GetAssignedLane())) if (e.pid === s.targetPid) return e;
    return undefined;
}

function seenTarget(bot: Unit, s: FightState): Unit | undefined {
    const e = targetEntry(bot, s);
    const u = e?.visible === true ? e.unit : undefined;
    if (u === undefined || u.IsNull() || !u.CanBeSeen() || u.GetLocation() === undefined) return undefined;
    return u;
}

/** Why the running phase must end now, else undefined. */
function endReason(bot: Unit, s: FightState, now: number): string | undefined {
    const cfg = LaneFightConfig.Settings();
    if (!bot.IsAlive()) return "dead";
    if (hpFraction(bot) < cfg.StopHP) return "low-hp";
    if ((s.phase === "trade" && !LaneFightConfig.IsOn("Trade")) || (s.phase === "commit" && !LaneFightConfig.IsOn("Kill"))) return "flag-off";
    // An order or survival claim outranks the floor within team_roam only; the engine's x1.1 on the active mode can
    // still carry team_roam past an order on another mode, so the phase gives way.
    if (priorityLive(bot)) return "priority";

    const target = seenTarget(bot, s);
    if (target !== undefined) {
        s.target = target;
        s.lastLoc = target.GetLocation();
        s.fogSince = undefined;
        if (!target.IsAlive()) return "target-dead";
        const h = LaneConfig.Helpers();
        if (target.IsIllusion() || (h.IsSuspiciousIllusion !== undefined && h.IsSuspiciousIllusion(target))) return "illusion";
        if (h.CannotBeKilled !== undefined && h.CannotBeKilled(bot, target)) return "unkillable";
        if (target.IsMagicImmune()) return "magic_immune";
        if (GetUnitToUnitDistance(bot, target) > LEASH) {
            s.farSince = s.farSince ?? now;
            if (now - s.farSince > END_GRACE) return "far";
        } else s.farSince = undefined;
    } else {
        if (s.targetPid === undefined || !IsHeroAlive(s.targetPid)) return "target-dead";
        s.fogSince = s.fogSince ?? now;
        if (now - s.fogSince > cfg.FogGrace) return "fog";
    }

    if (s.phase === "trade") {
        if (s.hits >= cfg.TradeHits) return "hits";
        // Valve's attack mode on the target counts as the trade under way.
        if (s.clockAt === undefined && attackingTarget(bot, s)) s.clockAt = now;
        if (s.clockAt !== undefined && now - s.clockAt >= cfg.TradeDuration) return "duration";
        if (s.clockAt === undefined && now - s.startedAt >= cfg.TradeDuration) return "reach";
    } else if (s.phase === "commit" && now - s.startedAt >= cfg.CommitMax) return "commit-max";

    // Below CommitHoldHP a retreat bidding at the floor wants out; the engine's x1.1 on team_roam would keep it in.
    const retreat = Intent.Resolved(bot, BotMode.Retreat);
    if (hpFraction(bot) < cfg.CommitHoldHP && retreat !== undefined && retreat >= floorOf(s.phase)) {
        s.retreatSince = s.retreatSince ?? now;
        if (now - s.retreatSince > END_GRACE) return "retreat";
    } else s.retreatSince = undefined;

    const mode = bot.GetActiveMode();
    if (mode === BotMode.TeamRoam || mode === BotMode.Attack) {
        s.offModeSince = undefined;
        s.tookOver = true;
    } else {
        s.offModeSince = s.offModeSince ?? now;
        if (now - s.offModeSince > MODE_GRACE) {
            const reason = `mode:${HDebug.ModeName(mode)}`;
            Telemetry.Event("lanefight_abort", [
                ["pid", bot.GetPlayerID()],
                ["phase", s.phase],
                ["reason", reason],
            ]);
            return reason;
        }
    }
    return undefined;
}

function checkEnd(bot: Unit, s: FightState, now: number): void {
    if (s.phase === "idle") return;
    lastHits(bot, s);
    const reason = endReason(bot, s, now);
    if (reason !== undefined) end(bot, s, reason);
}

/** Reads the fight and starts a trade or commit, or upgrades a trade to a commit, when the gates allow. */
function considerStart(bot: Unit, s: FightState, snap: LaneState.LaneSnapshot, now: number): void {
    const read = FightRead.ReadFor(bot, now);
    const fresh = read !== s.lastRead;
    s.lastRead = read;
    s.lastWindow = read.window;
    const target = read.target;
    if (target === undefined) {
        s.streak = 0;
        s.streakKey = undefined;
        s.killSince = undefined;
        return;
    }
    const tpid = target.GetPlayerID();
    if (read.respect !== undefined) {
        s.streak = 0;
        s.streakKey = undefined;
        s.killSince = undefined;
        if (s.phase === "idle") gate(bot, touch(s, `respect:${read.respect}:${tpid}`, now), `respect:${read.respect}`);
        return;
    }

    const windowKey = read.window !== undefined && read.noticed ? `trade:${read.window}:${tpid}` : undefined;
    if (fresh) {
        s.streak = windowKey !== undefined && windowKey === s.streakKey ? s.streak + 1 : windowKey !== undefined ? 1 : 0;
        s.streakKey = windowKey;
    }

    let commitReady = false;
    if (LaneFightConfig.IsOn("Kill")) {
        const k = KillCheck.Check(bot, partnerUnits(bot, snap), target, now);
        s.lastMargin = k?.margin;
        if (k !== undefined && k.pass) {
            if (s.killSince === undefined || s.killPid !== tpid) {
                s.killSince = now;
                s.killPid = tpid;
                s.killDelay = Profile.SampleDelay(bot, "react");
            }
            const inst = touch(s, `kill:${tpid}`, now);
            commitReady = now - s.killSince >= s.killDelay && !inst.started;
            if (commitReady && s.phase !== "commit") {
                const blocked = startBlocked(bot);
                if (blocked !== undefined) gate(bot, inst, blocked);
                else {
                    if (s.phase === "trade") end(bot, s, "commit");
                    start(bot, s, "commit", target, inst, now, ["margin", k.margin]);
                    // A commit spends the trade window on the same target too.
                    if (windowKey !== undefined) {
                        const w = touch(s, windowKey, now);
                        w.started = true;
                        s.spent.push(w);
                    }
                }
            }
        } else s.killSince = undefined;
    }

    if (windowKey === undefined || !LaneFightConfig.IsOn("Trade")) return;
    const inst = touch(s, windowKey, now);
    if (s.phase !== "idle" || inst.started || s.streak < 2) return;
    const blocked = GetUnitToUnitDistance(bot, target) > bot.GetAttackRange() + TRADE_REACH ? "range" : startBlocked(bot);
    if (blocked !== undefined) gate(bot, inst, blocked);
    else start(bot, s, "trade", target, inst, now, ["window", read.window]);
}

/**
 * mode_team_roam_generic GetDesire, after CapForLanePush. While a trade or commit runs it posts the FIGHT floor on
 * team_roam and returns `raw`; the claim lifts it in Intent.Resolve. Without intent it returns max(raw, floor).
 * `avoiding` is team_roam's IsAvoidingAbilityZone: its escape runs instead of the fight, so the phase ends.
 */
export function RoamDesire(bot: Unit, raw: number, avoiding?: boolean): number {
    if (type(raw) !== "number") return raw;
    const s = fights[bot.GetPlayerID()];
    if (!gatesOpen(bot)) {
        if (s !== undefined) end(bot, s, "off");
        return raw;
    }
    if (avoiding === true) {
        if (s !== undefined) end(bot, s, "avoid");
        return raw;
    }
    const snap = LaneState.ForBot(bot);
    if (snap === undefined || DotaTime() < 0) {
        if (s !== undefined) end(bot, s, "off");
        return raw;
    }
    const st = s ?? stateFor(bot);
    const now = DotaTime();
    checkEnd(bot, st, now);
    considerStart(bot, st, snap, now);
    if (st.phase !== "trade" && st.phase !== "commit") return raw;
    if (claim(bot, st.phase)) return raw;
    return math.max(raw, floorOf(st.phase));
}

/**
 * mode_team_roam_generic Think, right after ItemOpsThink and before its last-hit branch: true when the fight owns
 * this frame (the bot attacks its target, or walks to it or to where it was last seen).
 */
export function Think(bot: Unit): boolean {
    const s = fights[bot.GetPlayerID()];
    if (s === undefined || s.phase === "idle") return false;
    if (!gatesOpen(bot)) {
        end(bot, s, "off");
        return false;
    }
    checkEnd(bot, s, DotaTime());
    if (s.phase !== "trade" && s.phase !== "commit") return false;
    const target = seenTarget(bot, s);
    if (target === undefined) {
        if (s.lastLoc === undefined) return false;
        claim(bot, s.phase);
        bot.Action_MoveToLocation(s.lastLoc);
        return true;
    }
    claim(bot, s.phase);
    bot.SetTarget(target);
    if (GetUnitToUnitDistance(bot, target) <= bot.GetAttackRange() + RANGE_SLACK) {
        if (s.clockAt === undefined) s.clockAt = DotaTime();
        bot.Action_AttackUnit(target, false);
    } else bot.Action_MoveToLocation(target.GetLocation());
    return true;
}

/** The trade or commit target, while one runs. */
export function Target(bot: Unit): Unit | undefined {
    const s = fights[bot.GetPlayerID()];
    return s !== undefined && (s.phase === "trade" || s.phase === "commit") ? s.target : undefined;
}

export function CurrentPhase(bot: Unit): Phase {
    return fights[bot.GetPlayerID()]?.phase ?? "idle";
}

/** "fight: window=<type|none> kill=<margin|-> mem=<n> phase=<p>" for the overlay. */
export function Describe(bot: Unit): string {
    const s = fights[bot.GetPlayerID()];
    const margin = s?.lastMargin !== undefined ? string.format("%.2f", s.lastMargin) : "-";
    return `fight: window=${s?.lastWindow ?? "none"} kill=${margin} mem=${CooldownMemory.Count(bot.GetPlayerID(), DotaTime())} phase=${s?.phase ?? "idle"}`;
}
