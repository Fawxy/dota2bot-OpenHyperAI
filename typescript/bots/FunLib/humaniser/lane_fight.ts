/**
 * Lane fight facade (task 11): trades and kill setups with imperfect cooldown memory. Tick runs per bot per frame
 * from Humaniser.Tick; ReadFor is the fight read (trade and respect windows); CheckKill is the kill check.
 *
 * The executor runs through mode_team_roam_generic: RoamDesire (its GetDesire) starts and ends trades and commits and
 * posts a FIGHT floor claim on team_roam while one runs; Think (its Think) attacks the target. Tick (every frame)
 * watches the lane partner: a partner's visible commit is the only coordination channel, for bot partners too, since
 * modules may not be shared between a team's bots. A core waits (wait_partner) for its support's commit, a bot calls
 * kills for a human partner, and a commit aborts on a real signal after a skill-scaled re-check.
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
import * as LaneHooks from "bots/FunLib/humaniser/lane_hooks";
import * as Telemetry from "bots/FunLib/humaniser/telemetry";
import * as HDebug from "bots/FunLib/humaniser/debug";

export { LaneFightConfig as Config, AbilityClasses, CooldownMemory, CastWatch, FightRead, KillCheck };

export function IsActive(): boolean {
    return LaneFightConfig.IsActive();
}

export function Tick(bot: Unit): void {
    if (!LaneFightConfig.IsActive() || !LaneFightConfig.AppliesTo(bot) || !LaneConfig.InLaningPhase()) return;
    if (!LaneFightConfig.IsOn("Memory") && !gatesOpen(bot)) return;
    // A bot with no assigned lane (no lane snapshot) has no lane enemies to watch.
    const snap = LaneState.ForBot(bot);
    if (snap === undefined) return;
    if (LaneFightConfig.IsOn("Memory")) CastWatch.Tick(bot);
    const now = DotaTime();
    if (now < 0 || !gatesOpen(bot)) return;
    const s = stateFor(bot);
    // Frame precision for the partner's commit, the follow time, the wait timeout and abort re-checks.
    coordinate(bot, s, snap, now);
    checkEnd(bot, s, now);
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
    // Commit discipline: since when the kill check's margin on the target has been under AbandonMargin, and since when
    // an enemy tower has had the bot as its target.
    lowMarginSince?: number;
    towerAggroSince?: number;
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
    // Partners the running commit's checks count (a re-check uses the same set); the partner a wait is for.
    partners: Unit[];
    // A follow commit went in on margin >= FollowMargin, so its re-check holds it to that, not to a full pass.
    recheckMargin?: number;
    // When each counted partner was last seen going in on the target; none counts as seen before `partnerSince`.
    partnerSeen: Record<number, number>;
    partnerSince: number;
    withPid?: number;
    // A partner's visible commit seen at `seenAt`; the bot follows at `at` (react + SyncDelay later).
    follow?: Follow;
    lastCallAt?: number;
    // Abort: a signal seen at `signalAt` is re-checked at `at` (AbortNotice later).
    abort?: { why: string; signalAt: number; at: number };
    escapeAt?: number;
    startEnemies: number;
    countUp: boolean;
    // The target was under one of its towers at the last check (a commit that started there cleared TowerOverride).
    towerUp: boolean;
    // When the commit last had its target within attack range (ChaseMax runs from here).
    reachAt: number;
    countAt: number;
    // Abilities a start believed down; one cast within MISTAKE_WINDOW of `at` proves the memory wrong.
    bet?: { targetPid: number; at: number; abilities: Record<string, boolean>; done: boolean };
}

interface Follow {
    allyPid: number;
    targetPid: number;
    seenAt: number;
    lastSeen: number;
    at: number;
    delay: number;
    inst: Instance;
}

type KillAction = "commit" | "wait" | "none";

interface KillPlan {
    action: KillAction;
    k?: KillCheck.KillResult;
    partners: Unit[];
    via: string;
}

interface PartnerInfo {
    unit: Unit;
    pid: number;
    human: boolean;
    support: boolean;
}

// A window or kill pass seen again within this gap is the same instance (FightRead's INSTANCE_GAP).
const INSTANCE_GAP = 1;
// End conditions other than HP, death, fog and an unkillable target must hold this long.
const END_GRACE = 0.5;
// Another mode active this long during a phase ends it; Valve's attack mode is "going on someone" and does not.
const MODE_GRACE = 1;
// team_roam drops a target farther than this.
const LEASH = 1800;
// Beyond attack range + both hulls (the engine measures range edge to edge; distances here are centre to centre).
const RANGE_SLACK = 50;
// A trade starts only on a target this far beyond the bot's attack range at most.
const TRADE_REACH = 400;
// The engine's bonus on the active mode's desire.
const ACTIVE_BOOST = 1.1;
// A wait for the partner's commit gives up after this.
const WAIT_TIMEOUT = 3;
const WAIT_HOLD = "lanefight:wait";
// A believed-down ability cast this soon after the start proves the memory wrong.
const MISTAKE_WINDOW = 2;
// A key-class cast counts as on the target when the caster faces within 30 degrees of it, within cast range + 200.
const FACING_COS = math.cos(math.pi / 6);
const CAST_SLACK = 200;
// "Closing": the distance shrank by more than this since the previous sample, taken at most PREV_MAX_AGE ago.
const CLOSE_MIN = 1;
const PREV_MAX_AGE = 0.5;
// Samples closer together than this (two calls in one frame) keep the older one as the comparison point.
const SAMPLE_GAP = 0.02;
// The enemy-count abort signal is read this often.
const COUNT_EVERY = 0.1;
const COUNT_RADIUS = 1200;
// Attacks on the target from within range (within Settings().InRangeWindow) that make a commit.
const IN_RANGE_ATTACKS = 2;
// At follow time the partner must have been seen committing this recently.
const FOLLOW_FRESH = 0.3;
// A counted partner farther than this from the target has left the commit.
const PARTNER_RANGE = 1200;
// A counted partner's attack on the target keeps it seen going in this long: between attacks (about 1.7 s at level 1)
// and while casting it has no attack target.
const PARTNER_RECENT_ATTACK = 1.5;
// A chase: moving at least this fast (units/s; heroes run 280+) and losing ground no faster than CHASE_LOSS.
const CHASE_MIN_SPEED = 150;
const CHASE_LOSS = 40;
// An initiator's partner gets this long to be seen following (its react + SyncDelay, then closing) before AbortNotice
// starts to run.
const INITIATE_GRACE = 1.5;
// A kill check failing with at least this margin logs its reason (lanefight_gate gate=kill:<reason>).
const NEAR_MISS = 0.8;
const FOCUS_SOURCE = "lanefight:commit_focus";
const PARTNER_ABANDON = "partner_abandon";
// lanefight_commit role per start `via`.
const COMMIT_ROLES: Record<string, string> = { initiate: "initiator", follow: "follower", solo: "solo" };
// The errands and laning a commit caps; defend and push stay free, retreat is held separately. The Attack cap only
// reaches the heroes whose attack mode is OHA's Lua override (Valve's C++ attack mode is never resolved), but there it
// keeps that mode (1.0, x1.1 when active) from beating the commit.
const FOCUS_MODES: BotMode[] = [BotMode.Laning, BotMode.Farm, BotMode.Attack, BotMode.Ward, BotMode.Rune, BotMode.SecretShop, BotMode.SideShop, BotMode.Roam];
// Modes a lane fight may start from.
const START_MODES: BotMode[] = [BotMode.Laning, BotMode.TeamRoam, BotMode.Attack];

const fights: Record<number, FightState> = {};
// Per "observer:ally:target" the last two distance samples, for "closing".
const tracks: Record<string, { prev?: Sample; cur?: Sample; lastAttack?: number; attackTimes: number[] }> = {};

function stateFor(bot: Unit): FightState {
    const pid = bot.GetPlayerID();
    let s = fights[pid];
    if (s === undefined) {
        s = {
            phase: "idle",
            startedAt: 0,
            tookOver: false,
            spent: [],
            hits: 0,
            lastAttack: 0,
            streak: 0,
            killDelay: 0,
            instances: {},
            partners: [],
            partnerSeen: {},
            partnerSince: 0,
            startEnemies: 0,
            countUp: false,
            towerUp: false,
            reachAt: 0,
            countAt: -math.huge,
        };
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

function floorOf(bot: Unit, phase: Phase): number {
    const s = LaneFightConfig.Settings();
    if (phase !== "commit") return s.TradeFloor;
    return hpFraction(bot) >= s.CommitHoldHP ? s.CommitFloor : s.CommitLowFloor;
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

function gate(bot: Unit, inst: Instance, reason: string, targetPid?: number, extra?: Telemetry.Fields<"lanefight_gate">): void {
    if (inst.gates[reason] === true) return;
    inst.gates[reason] = true;
    const fields: Telemetry.Fields<"lanefight_gate"> = [
        ["pid", bot.GetPlayerID()],
        ["gate", reason],
    ];
    if (targetPid !== undefined) fields.push(["target", targetPid]);
    if (extra !== undefined) for (const f of extra) fields.push(f);
    Telemetry.Event("lanefight_gate", fields);
}

function priorityLive(bot: Unit): boolean {
    return Intent.PriorityLive(bot) || Orders.GetFor(bot) !== undefined;
}

/** Why a trade (or, with `commit`, a commit or a wait for one) must not start now, else undefined. */
function startBlocked(bot: Unit, commit: boolean): string | undefined {
    const cfg = LaneFightConfig.Settings();
    const mode = bot.GetActiveMode();
    let modeOk = false;
    for (const m of START_MODES) if (m === mode) modeOk = true;
    if (!modeOk) return `mode:${HDebug.ModeName(mode)}`;
    if (hpFraction(bot) < (commit ? cfg.CommitStartHP : cfg.StartHP)) return "low-hp";
    // Retreat is scored before team_roam in each round, so this is this round's retreat desire. With intent off there
    // is no resolved retreat desire to read, so the StartMaxRetreat gate is not enforced.
    const retreat = Intent.Resolved(bot, BotMode.Retreat);
    if (retreat !== undefined && retreat >= cfg.StartMaxRetreat) return "retreat";
    if (CampJobs.Active(bot)) return "camp";
    if (CampJobs.Covering(bot)) return "cover";
    // Task 12's caution suppresses lane trades; kills keep the kill check's own safety rules.
    if (!commit && LaneHooks.TradesSuppressed(bot)) return "caution";
    if (priorityLive(bot)) return "priority";
    return undefined;
}

function usableUnit(u: Unit | null | undefined): u is Unit {
    return u !== undefined && u !== null && !u.IsNull() && u.IsAlive() && u.CanBeSeen() && u.GetLocation() !== undefined;
}

function memberByPid(_team: number, pid: number): Unit | undefined {
    for (let i = 1; i <= LaneState.TEAM_SLOTS; i++) {
        const u = GetTeamMember(i);
        if (u !== null && u !== undefined && !u.IsNull() && u.GetPlayerID() === pid) return u;
    }
    return undefined;
}

function isSupport(u: Unit): boolean {
    const pos = LaneConfig.PositionOf(u);
    return pos === 4 || pos === 5;
}

function partnerOf(bot: Unit, snap: LaneState.LaneSnapshot): PartnerInfo | undefined {
    const p = LaneRoles.Partner(bot, snap);
    if (p === undefined || !p.alive) return undefined;
    const unit = p.unit !== undefined && p.unit !== null && !p.unit.IsNull() ? p.unit : memberByPid(bot.GetTeam(), p.pid);
    if (!usableUnit(unit)) return undefined;
    return { unit, pid: p.pid, human: !IsPlayerBot(p.pid), support: isSupport(unit) };
}

/** A learned disable that is castable now: a key-class ability that is not an escape. */
function holdsReadyKey(u: Unit): boolean {
    for (let i = 0; i < 6; i++) {
        const a = u.GetAbilityInSlot(i);
        if (a === null || a === undefined || a.IsNull() || a.IsHidden() || a.GetLevel() < 1) continue;
        const name = a.GetName();
        if (AbilityClasses.Classify(name, a.IsUltimate()) === "key" && !AbilityClasses.IsEscape(name) && a.IsFullyCastable()) return true;
    }
    return false;
}

/** `t` is the hero `target`, not an illusion of it (an illusion carries its player ID). */
function isHeroTarget(t: Unit | null | undefined, target: Unit | undefined, targetPid: number | undefined): boolean {
    if (t === null || t === undefined || t.IsNull() || !t.IsHero()) return false;
    if (target !== undefined && t === target) return true;
    return t.GetPlayerID() === targetPid && !t.IsIllusion();
}

function skillOf(bot: Unit): number {
    return Profile.Get(bot).skill;
}

export interface Sample {
    dist: number;
    at: number;
    loc?: Vector;
    // Attacks the ally landed on the target within InRangeWindow before this sample.
    attacks?: number;
}

/**
 * The ally's visible commit on `target`: it attacks the target while closing on it, or keeps attacking it from within
 * its attack range (IN_RANGE_ATTACKS within InRangeWindow: one harass hit is not a commit), or it is casting a
 * key-class ability or an ultimate at it. The bot API rarely exposes a cast's target, so "at it" is: facing within 30
 * degrees of the target and within the ability's cast range + 200. `prev` is the sample taken before this one.
 */
export function IsCommitting(ally: Unit, target: Unit, prev: Sample | undefined): boolean {
    if (!usableUnit(ally) || !usableUnit(target)) return false;
    const dist = GetUnitToUnitDistance(ally, target);
    if (isHeroTarget(ally.GetAttackTarget(), target, target.GetPlayerID())) {
        if (inAttackRange(ally, target, dist) && (prev?.attacks ?? 0) >= IN_RANGE_ATTACKS) return true;
        if (prev !== undefined && DotaTime() - prev.at <= PREV_MAX_AGE && dist < prev.dist - CLOSE_MIN) return true;
    }
    return castingAt(ally, target, dist);
}

function castingAt(ally: Unit, target: Unit, dist: number): boolean {
    if (!ally.IsCastingAbility()) return false;
    const a = ally.GetCurrentActiveAbility();
    if (a === null || a === undefined || a.IsNull()) return false;
    if (AbilityClasses.Classify(a.GetName(), a.IsUltimate()) === "other") return false;
    if (dist > a.GetCastRange() + CAST_SLACK) return false;
    if (dist < 1) return true;
    const f = (ally.GetFacing() * math.pi) / 180;
    const from = ally.GetLocation();
    const to = target.GetLocation();
    return ((to.x - from.x) * math.cos(f) + (to.y - from.y) * math.sin(f)) / dist >= FACING_COS;
}

/**
 * The previous ally-target sample; records the current one. Attacks are counted when the ally's last attack time
 * advances while the target is its attack target, timed by when they are seen (attack times are on the game clock).
 */
function sampleDistance(bot: Unit, ally: Unit, target: Unit, now: number): Sample | undefined {
    const key = `${bot.GetPlayerID()}:${ally.GetPlayerID()}:${target.GetPlayerID()}`;
    let t = tracks[key];
    if (t === undefined) {
        t = { attackTimes: [] };
        tracks[key] = t;
    }
    if (t.cur !== undefined && now < t.cur.at) {
        t.cur = undefined;
        t.attackTimes = [];
    }
    const last = ally.GetLastAttackTime();
    if (t.lastAttack === undefined || last < t.lastAttack) t.lastAttack = last;
    else if (last > t.lastAttack) {
        t.lastAttack = last;
        if (isHeroTarget(ally.GetAttackTarget(), target, target.GetPlayerID())) t.attackTimes.push(now);
    }
    const recent: number[] = [];
    const window = LaneFightConfig.Settings().InRangeWindow;
    for (const a of t.attackTimes) if (now - a <= window) recent.push(a);
    t.attackTimes = recent;
    if (t.cur === undefined || now - t.cur.at >= SAMPLE_GAP) {
        t.prev = t.cur;
        t.cur = { dist: GetUnitToUnitDistance(ally, target), at: now, loc: ally.GetLocation() };
    }
    t.cur.attacks = recent.length;
    if (t.prev !== undefined) t.prev.attacks = recent.length;
    return t.prev;
}

/**
 * A partner's commit worth following: IN_RANGE_ATTACKS landed, or a key or ultimate cast at the target. Walking in on
 * the target while attacking is how a harass hit looks too, so it is followed only by a bot already waiting for this
 * partner, on whichever lane enemy the partner picked (the follow's margin check still decides).
 */
function followable(s: FightState, ally: Unit, target: Unit, prev: Sample | undefined): boolean {
    if (s.phase === "wait_partner" && s.withPid === ally.GetPlayerID()) return true;
    if ((prev?.attacks ?? 0) >= IN_RANGE_ATTACKS) return true;
    return castingAt(ally, target, GetUnitToUnitDistance(ally, target));
}

/**
 * The visible lane enemy the partner is committing on in a way worth following (`followable`), if any. While the bot
 * commits, a partner its checks count is marked seen when it commits on the target or keeps attacking it from within
 * range (a commit under way, past the second-attack test that tells a start from a harass hit).
 */
function partnerCommitTarget(bot: Unit, s: FightState, ally: Unit, now: number): Unit | undefined {
    let found: Unit | undefined;
    const counted = s.phase === "commit" && countsPartner(s, ally.GetPlayerID());
    for (const e of LaneState.Enemies(bot, bot.GetAssignedLane())) {
        if (e === undefined || !e.visible || !usableUnit(e.unit)) continue;
        const prev = sampleDistance(bot, ally, e.unit, now);
        const committing = IsCommitting(ally, e.unit, prev);
        if (found === undefined && committing && followable(s, ally, e.unit, prev)) found = e.unit;
        if (counted && e.pid === s.targetPid) {
            const hit = lastAttackOn(bot, ally, e.unit);
            if (committing || attackingInRange(ally, e.unit) || (hit !== undefined && now - hit <= PARTNER_RECENT_ATTACK) || chasing(ally, e.unit, prev, now))
                s.partnerSeen[ally.GetPlayerID()] = now;
        }
    }
    return found;
}

function countsPartner(s: FightState, pid: number): boolean {
    for (const u of s.partners) if (!u.IsNull() && u.GetPlayerID() === pid) return true;
    return false;
}

function attackingInRange(ally: Unit, target: Unit): boolean {
    return isHeroTarget(ally.GetAttackTarget(), target, target.GetPlayerID()) && inAttackRange(ally, target, GetUnitToUnitDistance(ally, target));
}

/**
 * Out of range the engine reports no attack target, and a partner running after a target as fast as it flees is not
 * closing: it counts as going in while it moves towards the target without falling behind faster than CHASE_LOSS.
 * How long a chase may last is the bot's own ChaseMax.
 */
function chasing(ally: Unit, target: Unit, prev: Sample | undefined, now: number): boolean {
    if (prev === undefined || prev.loc === undefined || now - prev.at > PREV_MAX_AGE || now <= prev.at) return false;
    const from = prev.loc;
    const at = ally.GetLocation();
    const moved = math.sqrt((at.x - from.x) ** 2 + (at.y - from.y) ** 2);
    if (moved < CHASE_MIN_SPEED * (now - prev.at)) return false;
    const dist = GetUnitToUnitDistance(ally, target);
    if (dist > PARTNER_RANGE || dist > prev.dist + CHASE_LOSS * (now - prev.at)) return false;
    const to = target.GetLocation();
    const toDist = math.sqrt((to.x - at.x) ** 2 + (to.y - at.y) ** 2);
    if (toDist < 1) return true;
    return ((at.x - from.x) * (to.x - at.x) + (at.y - from.y) * (to.y - at.y)) / (moved * toDist) >= FACING_COS;
}

function inAttackRange(attacker: Unit, target: Unit, dist: number): boolean {
    return dist <= attacker.GetAttackRange() + attacker.GetBoundingRadius() + target.GetBoundingRadius() + RANGE_SLACK;
}

/** When the bot last saw `ally` land an attack on `target`, from the attack samples. */
function lastAttackOn(bot: Unit, ally: Unit, target: Unit): number | undefined {
    const times = tracks[`${bot.GetPlayerID()}:${ally.GetPlayerID()}:${target.GetPlayerID()}`]?.attackTimes;
    return times !== undefined && times.length > 0 ? times[times.length - 1] : undefined;
}

function focusCap(bot: Unit): number {
    return floorOf(bot, "commit") / ACTIVE_BOOST - LaneFightConfig.Settings().CommitFocusMargin;
}

/**
 * The phase's floor on team_roam. A commit also caps laning and the errands (as 07's camp jobs do), and retreat while
 * HP is at least CommitHoldHP: retreat's laning-phase creep-damage branch bids 0.8-0.9 at healthy HP. SURVIVAL and
 * HUMAN_ORDER sit on higher tiers, and StopHP ends the phase.
 */
function claim(bot: Unit, phase: Phase): boolean {
    const posted = Intent.Claim(bot, { source: `lanefight:${phase}`, tier: "FIGHT", mode: BotMode.TeamRoam, floor: floorOf(bot, phase) });
    if (!posted || phase !== "commit") return posted;
    const cap = focusCap(bot);
    for (const mode of FOCUS_MODES) Intent.Claim(bot, { source: FOCUS_SOURCE, tier: "FIGHT", mode, cap });
    // Under an enemy tower's fire retreat is never held: Valve's retreat reads the tower threat and must be able to win.
    if (hpFraction(bot) >= LaneFightConfig.Settings().CommitHoldHP && !LaneState.EnemyTowerTargeting(bot))
        Intent.Claim(bot, { source: FOCUS_SOURCE, tier: "FIGHT", mode: BotMode.Retreat, cap });
    else Intent.Release(bot, FOCUS_SOURCE, BotMode.Retreat);
    return posted;
}

/**
 * Abilities of `target` the bot's memory says are down that this start relies on: the key abilities behind a spell
 * window, and for a commit the escapes too (the kill check passed because they were believed down).
 */
function believedDown(bot: Unit, target: Unit, spell: boolean, escapes: boolean, now: number): Record<string, boolean> {
    const out: Record<string, boolean> = {};
    const pid = bot.GetPlayerID();
    const tpid = target.GetPlayerID();
    for (const a of CastWatch.AbilitiesOf(target)) {
        if (!a.learned) continue;
        const wanted = (spell && AbilityClasses.Classify(a.name, a.ult) === "key") || (escapes && AbilityClasses.IsEscape(a.name));
        if (!wanted) continue;
        const [ready] = CooldownMemory.ProbablyReady(pid, tpid, a.name, true, now, skillOf(bot));
        if (!ready) out[a.name] = true;
    }
    return out;
}

interface StartOpts {
    partners: Unit[];
    // The start relied on a spell window on this target (this round's read).
    spell: boolean;
    recheckMargin?: number;
    // The partners are not in yet (an initiator): INITIATE_GRACE before their absence counts.
    initiating?: boolean;
}

function start(bot: Unit, s: FightState, phase: Phase, target: Unit, inst: Instance, now: number, detail: Telemetry.Fields<"lanefight_start">, opts: StartOpts): void {
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
    s.partners = opts.partners;
    s.partnerSeen = {};
    s.partnerSince = opts.initiating === true ? now + INITIATE_GRACE : now;
    s.recheckMargin = opts.recheckMargin;
    s.abort = undefined;
    s.countUp = false;
    s.towerUp = KillCheck.TowerCovers(target.GetTeam(), target.GetLocation());
    s.reachAt = now;
    s.countAt = -math.huge;
    s.startEnemies = 0;
    const snap = LaneState.ForBot(bot);
    if (phase === "commit" && snap !== undefined) s.startEnemies = FightRead.LaneCounts(bot, snap, COUNT_RADIUS).enemies;
    if (phase !== "wait_partner") {
        const abilities = believedDown(bot, target, opts.spell, phase === "commit", now);
        const old = s.bet;
        // A trade upgraded to a commit within the window keeps the trade's bet (and its start time) and adds to it.
        if (old !== undefined && !old.done && old.targetPid === s.targetPid && now - old.at <= MISTAKE_WINDOW) {
            for (const [name] of pairs(abilities)) old.abilities[name] = true;
        } else {
            const [first] = next(abilities);
            s.bet = first !== undefined ? { targetPid: s.targetPid, at: now, abilities, done: false } : undefined;
        }
    }
    // The bot is usually in laning when the floor is first posted; team_roam takes over at the next round.
    s.offModeSince = now;
    if (phase !== "wait_partner") claim(bot, phase);
    const fields: Telemetry.Fields<"lanefight_start"> = [["pid", bot.GetPlayerID()], ["phase", phase], ["target", s.targetPid]];
    for (const d of detail) fields.push(d);
    Telemetry.Event("lanefight_start", fields);
    if (phase === "commit") {
        let margin: any;
        let via: any;
        for (const [k, v] of detail) {
            if (k === "margin") margin = v;
            else if (k === "via") via = v;
        }
        Telemetry.Event("lanefight_commit", [
            ["pid", bot.GetPlayerID()],
            ["target", s.targetPid],
            ["margin", margin],
            ["role", COMMIT_ROLES[via] ?? via],
        ]);
    }
    HDebug.Log("lanefight", `start pid=${bot.GetPlayerID()} phase=${phase} target=${s.targetPid}`);
}

function end(bot: Unit, s: FightState, reason: string): void {
    const phase = s.phase;
    if (phase === "idle") return;
    Intent.ReleaseSource(bot, `lanefight:${phase}`);
    Intent.ReleaseSource(bot, FOCUS_SOURCE);
    // A claim that never won the takeover did not use the window. A wait never takes over and spends its kill pass:
    // giving it back would restart the wait at once.
    if (!s.tookOver && phase !== "wait_partner") for (const inst of s.spent) inst.started = false;
    s.spent = [];
    // A restart needs the window on two fresh reads again.
    s.streak = 0;
    s.streakKey = undefined;
    s.phase = "idle";
    s.target = undefined;
    s.targetPid = undefined;
    s.withPid = undefined;
    s.abort = undefined;
    if (phase !== "wait_partner") bot.SetTarget(undefined as any);
    Telemetry.Event("lanefight_end", [
        ["pid", bot.GetPlayerID()],
        ["phase", phase],
        ["reason", reason],
        ["hits", s.hits],
        ["took", s.tookOver ? 1 : 0],
    ]);
    HDebug.Log("lanefight", `end pid=${bot.GetPlayerID()} phase=${phase} reason=${reason}`);
}

/** lanefight_mistake once when an ability the start believed down is cast within MISTAKE_WINDOW of it. */
function checkMistake(bot: Unit, s: FightState, now: number): void {
    const bet = s.bet;
    if (bet === undefined || bet.done) return;
    const seen = CastWatch.LastSeenCast(bot.GetPlayerID());
    if (seen !== undefined && seen.enemyPid === bet.targetPid && seen.at >= bet.at && seen.at - bet.at <= MISTAKE_WINDOW && bet.abilities[seen.ability] === true) {
        bet.done = true;
        Telemetry.Event("lanefight_mistake", [
            ["pid", bot.GetPlayerID()],
            ["kind", "bad_memory"],
            ["ability", seen.ability],
            ["target", bet.targetPid],
            ["after", seen.at - bet.at],
        ]);
        return;
    }
    // Kept a little past the window: a cast seen late (rounds only, no Tick) is judged by its own time.
    if (now - bet.at > MISTAKE_WINDOW + INSTANCE_GAP) s.bet = undefined;
}

interface Abandon {
    ally: Unit;
    why: "gone" | "far" | "unseen";
    since: number;
}

/**
 * A partner the commit's checks count is dead, farther than PARTNER_RANGE from the target, or not seen going in for
 * PartnerLapse.
 */
function partnerAbandoned(s: FightState, target: Unit | undefined, now: number): Abandon | undefined {
    const lapse = LaneFightConfig.Settings().PartnerLapse;
    for (const u of s.partners) {
        if (!usableUnit(u)) return { ally: u, why: "gone", since: 0 };
        const last = math.max(s.partnerSince, s.partnerSeen[u.GetPlayerID()] ?? -math.huge);
        if (target !== undefined && GetUnitToUnitDistance(u, target) > PARTNER_RANGE) return { ally: u, why: "far", since: now - last };
        if (now - last >= lapse) return { ally: u, why: "unseen", since: now - last };
    }
    return undefined;
}

/** What the abandoning partner was visibly doing, to tell a partner that backed off from one the checks missed. */
function logAbandon(bot: Unit, s: FightState, target: Unit, a: Abandon): void {
    const fields: Telemetry.Fields<"lanefight_abandon"> = [
        ["pid", bot.GetPlayerID()],
        ["why", a.why],
        ["since", a.since],
        ["mode", HDebug.ModeName(bot.GetActiveMode())],
    ];
    if (a.why !== "gone") {
        const atk = a.ally.GetAttackTarget();
        const named = atk === null || atk === undefined || atk.IsNull() ? "-" : isHeroTarget(atk, target, s.targetPid) ? "target" : atk.GetUnitName();
        fields.push(
            ["ally", a.ally.GetPlayerID()],
            ["amode", HDebug.ModeName(a.ally.GetActiveMode())],
            ["atk", named],
            ["dist", GetUnitToUnitDistance(a.ally, target)],
            ["range", a.ally.GetAttackRange()],
            ["lastatk", GameTime() - a.ally.GetLastAttackTime()],
        );
    }
    Telemetry.Event("lanefight_abandon", fields);
}

/**
 * A real abort signal on a running commit: the target cast an escape, a counted partner abandoned it, or the enemies
 * in lane now outnumber us.
 */
function abortSignal(bot: Unit, s: FightState, target: Unit | undefined, now: number): string | undefined {
    const seen = CastWatch.LastSeenCast(bot.GetPlayerID());
    if (seen !== undefined && seen.enemyPid === s.targetPid && seen.at >= s.startedAt && seen.at !== s.escapeAt && AbilityClasses.IsEscape(seen.ability)) {
        s.escapeAt = seen.at;
        return "escape";
    }
    if (s.partners.length > 0 && target !== undefined) {
        const a = partnerAbandoned(s, target, now);
        if (a !== undefined) {
            logAbandon(bot, s, target, a);
            return PARTNER_ABANDON;
        }
    }
    if (now - s.countAt < COUNT_EVERY) return undefined;
    s.countAt = now;
    if (target !== undefined) {
        const under = KillCheck.TowerCovers(target.GetTeam(), target.GetLocation());
        const entered = under && !s.towerUp;
        s.towerUp = under;
        if (entered) return "tower";
    }
    const snap = LaneState.ForBot(bot);
    if (snap === undefined) return undefined;
    const c = FightRead.LaneCounts(bot, snap, COUNT_RADIUS);
    const up = c.enemies > c.allies && c.enemies > s.startEnemies;
    const rose = up && !s.countUp;
    s.countUp = up;
    return rose ? "outnumbered" : undefined;
}

/**
 * The commit's abort: a signal is noticed and re-checked AbortNotice later (late at low skill). A re-check that still
 * passes lets the commit go on. A partner abandon re-checks solo, and a commit that goes on is solo from then on; a
 * partner back in by the re-check cancels it. While the target is unseen the partner cannot be seen going in on it, so
 * FogGrace decides: no abandon is raised or re-checked, and the partner's clock restarts when the target reappears.
 */
function abortReason(bot: Unit, s: FightState, target: Unit | undefined, now: number): string | undefined {
    if (target === undefined) for (const u of s.partners) if (!u.IsNull()) s.partnerSeen[u.GetPlayerID()] = now;
    if (s.abort === undefined) {
        const why = abortSignal(bot, s, target, now);
        if (why === undefined) return undefined;
        s.abort = { why, signalAt: now, at: now + LaneFightConfig.Curve("AbortNotice", skillOf(bot)) };
        HDebug.Log("lanefight", `abort-signal pid=${bot.GetPlayerID()} reason=${why}`);
    }
    const a = s.abort;
    if (now < a.at) return undefined;
    s.abort = undefined;
    const abandon = a.why === PARTNER_ABANDON;
    if (abandon && (target === undefined || partnerAbandoned(s, target, now) === undefined)) return undefined;
    const solo = abandon || (s.partners.length > 0 && target !== undefined && partnerAbandoned(s, target, now) !== undefined);
    const partners = solo ? [] : s.partners;
    const k = target !== undefined ? KillCheck.Check(bot, partners, target, now, true) : undefined;
    // A follow re-check holds to FollowMargin, but a dive still needs the full kill check: the tower rule and surviving
    // the tower's and creeps' damage.
    const pass =
        k !== undefined &&
        (!solo && s.recheckMargin !== undefined && a.why !== "tower" ? k.margin >= s.recheckMargin : k.pass) &&
        !(a.why === "tower" && k.margin < LaneFightConfig.Settings().TowerOverride);
    if (pass && solo) {
        s.partners = [];
        s.recheckMargin = undefined;
    }
    Telemetry.Event("lanefight_recheck", [
        ["pid", bot.GetPlayerID()],
        ["reason", a.why],
        ["pass", pass ? 1 : 0],
        ["margin", k?.margin ?? 0],
        ["after", now - a.signalAt],
    ]);
    if (pass) return undefined;
    Telemetry.Event("lanefight_abort", [
        ["pid", bot.GetPlayerID()],
        ["phase", s.phase],
        ["reason", a.why],
    ]);
    return a.why;
}

function lastHits(bot: Unit, s: FightState): void {
    const at = bot.GetLastAttackTime();
    if (at <= s.lastAttack) return;
    s.lastAttack = at;
    if (attackingTarget(bot, s)) s.hits++;
}

function attackingTarget(bot: Unit, s: FightState): boolean {
    return isHeroTarget(bot.GetAttackTarget(), s.target, s.targetPid);
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
    if ((s.phase === "trade" && !LaneFightConfig.IsOn("Trade")) || (s.phase !== "trade" && !LaneFightConfig.IsOn("Kill"))) return "flag-off";
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
        const d = GetUnitToUnitDistance(bot, target);
        if (d > LEASH) {
            s.farSince = s.farSince ?? now;
            if (now - s.farSince > END_GRACE) return "far";
        } else s.farSince = undefined;
        if (inAttackRange(bot, target, d)) s.reachAt = now;
        else if (s.phase === "commit" && now - s.reachAt > cfg.ChaseMax) return "chase";
    } else {
        if (s.targetPid === undefined || !IsHeroAlive(s.targetPid)) return "target-dead";
        s.fogSince = s.fogSince ?? now;
        if (now - s.fogSince > cfg.FogGrace) return "fog";
    }

    // A wait posts no floor and keeps laning, so the mode and retreat rules below do not apply to it.
    if (s.phase === "wait_partner") {
        if (s.withPid === undefined || !IsHeroAlive(s.withPid)) return "partner_gone";
        return now - s.startedAt >= WAIT_TIMEOUT ? "partner_timeout" : undefined;
    }
    if (s.phase === "commit") {
        const abort = abortReason(bot, s, target, now);
        if (abort !== undefined) return abort;
        // A kill that stopped working (the stun missed, the target regenerated) is let go, not chased to CommitMax.
        // Checked on the commit's own target and partners (cached for KillCheckEvery): the fight read may name no target.
        const k = target !== undefined ? KillCheck.Check(bot, s.partners, target, now) : undefined;
        if (k !== undefined && k.margin < cfg.AbandonMargin) {
            s.lowMarginSince = s.lowMarginSince ?? now;
            if (now - s.lowMarginSince > cfg.AbandonAfter) return "margin";
        } else s.lowMarginSince = undefined;
        if (LaneState.EnemyTowerTargeting(bot)) {
            s.towerAggroSince = s.towerAggroSince ?? now;
            if (now - s.towerAggroSince > END_GRACE) return "tower-aggro";
        } else s.towerAggroSince = undefined;
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
    if (hpFraction(bot) < cfg.CommitHoldHP && retreat !== undefined && retreat >= floorOf(bot, s.phase)) {
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
    checkMistake(bot, s, now);
    if (s.phase === "idle") return;
    lastHits(bot, s);
    const reason = endReason(bot, s, now);
    if (reason !== undefined) end(bot, s, reason);
}

function heroName(u: Unit): string {
    const h = LaneConfig.Helpers().HeroDisplayName;
    const name = h !== undefined ? h(u) : undefined;
    return name ?? string.gsub(u.GetUnitName(), "npc_dota_hero_", "")[0];
}

/** "go on <hero>" in team chat plus a ping on the target, at most once per CallCooldown. */
function callKill(bot: Unit, s: FightState, target: Unit, now: number): void {
    if (!LaneFightConfig.IsOn("CallKills")) return;
    const cd = LaneFightConfig.Settings().CallCooldown;
    if (s.lastCallAt !== undefined && now >= s.lastCallAt && now - s.lastCallAt < cd) return;
    s.lastCallAt = now;
    const said = Orders.Say(bot, "say_lanefight_go", cd, [heroName(target)]);
    const pinged = Orders.Ping(bot, target.GetLocation());
    Telemetry.Event("lanefight_call", [
        ["pid", bot.GetPlayerID()],
        ["target", target.GetPlayerID()],
        ["said", said ? 1 : 0],
        ["pinged", pinged ? 1 : 0],
    ]);
}

/**
 * What the bot does on a kill pass against `target`. With a human partner it calls the kill and waits for the human,
 * or goes alone only when overwhelming without the human's burst above SoloSkill. A support with a ready disable
 * initiates; a core whose bot support holds one waits for it; a laner with neither commits on a solo check. A solo
 * pass can lean on a partner who is not attacking (the outnumber rule counts the partner), so "alone" checks pass [].
 */
function planKill(bot: Unit, p: PartnerInfo | undefined, target: Unit, now: number): KillPlan {
    if (p !== undefined && p.human) {
        const partners = [p.unit];
        const k = KillCheck.Check(bot, partners, target, now);
        if (k === undefined || !k.pass) return { action: "none", k, partners, via: "call" };
        if (skillOf(bot) > LaneFightConfig.Settings().SoloSkill) {
            const solo = KillCheck.Check(bot, [], target, now);
            if (solo !== undefined && solo.pass && solo.overwhelming) return { action: "commit", k: solo, partners: [], via: "solo" };
        }
        return { action: "wait", k, partners, via: "call" };
    }
    const support = isSupport(bot);
    if (support && holdsReadyKey(bot)) {
        const partners = p !== undefined && fitToCommit(p.unit) ? [p.unit] : [];
        const k = KillCheck.Check(bot, partners, target, now);
        return { action: k !== undefined && k.pass ? "commit" : "none", k, partners, via: "initiate" };
    }
    if (p !== undefined && p.support && holdsReadyKey(p.unit) && fitToCommit(p.unit)) {
        const partners = [p.unit];
        const k = KillCheck.Check(bot, partners, target, now);
        return { action: k !== undefined && k.pass ? "wait" : "none", k, partners, via: "partner" };
    }
    // A support without a ready disable lets its core start and follows the core's commit. Two supports without one
    // each go on their own solo check.
    if (support && p !== undefined && !p.support) return { action: "none", k: KillCheck.Check(bot, [p.unit], target, now), partners: [p.unit], via: "follow" };
    const k = KillCheck.Check(bot, [], target, now);
    return { action: k !== undefined && k.pass ? "commit" : "none", k, partners: [], via: "solo" };
}

/**
 * A partner whose HP lets it commit (CommitStartHP, the gate it applies to itself). A partner below it will not go in,
 * so a plan that counts it commits alone.
 */
function fitToCommit(u: Unit): boolean {
    return hpFraction(u) >= LaneFightConfig.Settings().CommitStartHP;
}

function visibleEnemy(bot: Unit, pid: number): Unit | undefined {
    for (const e of LaneState.Enemies(bot, bot.GetAssignedLane())) {
        if (e !== undefined && e.pid === pid && e.visible && usableUnit(e.unit)) return e.unit;
    }
    return undefined;
}

/**
 * Every frame (Tick) and every round (RoamDesire): the wait's Hold, the bad-memory check, and the follow. The
 * partner's visible commit, first seen at `seenAt`, is followed at seenAt + react + SyncDelay if the bot's own margin
 * with the partner is at least FollowMargin; bot and human partners alike.
 */
function coordinate(bot: Unit, s: FightState, snap: LaneState.LaneSnapshot, now: number): void {
    if (s.phase === "wait_partner") Intent.Hold(bot, WAIT_HOLD);
    checkMistake(bot, s, now);
    const p = LaneFightConfig.IsOn("Kill") ? partnerOf(bot, snap) : undefined;
    if (p === undefined) {
        s.follow = undefined;
        return;
    }
    const seen = partnerCommitTarget(bot, s, p.unit, now);
    if (seen !== undefined) {
        const tpid = seen.GetPlayerID();
        const inst = touch(s, `follow:${p.pid}:${tpid}`, now);
        if (!inst.started && (s.follow === undefined || s.follow.targetPid !== tpid || s.follow.allyPid !== p.pid)) {
            const delay = Profile.SampleDelay(bot, "react") + LaneFightConfig.Curve("SyncDelay", skillOf(bot));
            s.follow = { allyPid: p.pid, targetPid: tpid, seenAt: now, lastSeen: now, at: now + delay, delay, inst };
            HDebug.Log("lanefight", `partner-commit pid=${bot.GetPlayerID()} ally=${p.pid} target=${tpid} follow-in=${delay}`);
        }
        if (s.follow !== undefined && s.follow.targetPid === tpid && s.follow.allyPid === p.pid) s.follow.lastSeen = now;
    }
    const f = s.follow;
    if (f === undefined) return;
    // A follow that cannot start within INSTANCE_GAP of its time is dropped; a partner still going in is seen again.
    if (f.allyPid !== p.pid) {
        s.follow = undefined;
        return;
    }
    if (now > f.at + INSTANCE_GAP) {
        if (now - f.lastSeen > FOLLOW_FRESH) gate(bot, f.inst, "partner_backed_off");
        s.follow = undefined;
        return;
    }
    if (now < f.at) return;
    // The partner must still be going in: a hit and a step back is not a commit to follow.
    if (now - f.lastSeen > FOLLOW_FRESH) return;
    if (s.phase === "commit") {
        f.inst.started = true;
        s.follow = undefined;
        return;
    }
    const target = visibleEnemy(bot, f.targetPid);
    if (target === undefined) return;
    const k = KillCheck.Check(bot, [p.unit], target, now);
    if (k === undefined || k.margin < LaneFightConfig.Settings().FollowMargin) {
        const extra: Telemetry.Fields<"lanefight_gate"> = [["margin", k?.margin ?? 0]];
        if (k?.reason !== undefined && k.reason !== "burst") extra.push(["why", k.reason]);
        gate(bot, f.inst, "follow-margin", f.targetPid, extra);
        return;
    }
    const blocked = startBlocked(bot, true);
    if (blocked !== undefined) {
        gate(bot, f.inst, blocked);
        return;
    }
    s.follow = undefined;
    if (s.phase !== "idle") end(bot, s, "commit");
    const read = FightRead.ReadFor(bot, now);
    const spell = read.window === "spell" && read.target !== undefined && read.target.GetPlayerID() === f.targetPid;
    start(bot, s, "commit", target, f.inst, now, [["margin", k.margin], ["via", "follow"], ["with", p.pid], ["sync", f.delay]], {
        partners: [p.unit],
        spell,
        recheckMargin: LaneFightConfig.Settings().FollowMargin,
    });
}

/** Laning's desire this round, with the engine's x1.1 when it is the active mode, at or above the trade floor. */
function laningOutbids(bot: Unit): boolean {
    const laning = Intent.Resolved(bot, BotMode.Laning);
    if (laning === undefined) return false;
    const boost = bot.GetActiveMode() === BotMode.Laning ? ACTIVE_BOOST : 1;
    return laning * boost >= LaneFightConfig.Settings().TradeFloor;
}

/**
 * Reads the fight and starts a trade or commit, or upgrades a trade to a commit, when the gates allow. Respect blocks
 * trades only: from level 6 an ult never seen cast reads as ready, so it would block every kill; the kill check's own
 * escape, tower, outnumbered and counter rules decide kills.
 */
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

    const windowKey = read.respect === undefined && read.window !== undefined && read.noticed ? `trade:${read.window}:${tpid}` : undefined;
    if (fresh) {
        s.streak = windowKey !== undefined && windowKey === s.streakKey ? s.streak + 1 : windowKey !== undefined ? 1 : 0;
        s.streakKey = windowKey;
    }

    // Planned during a commit too: a pass that holds keeps its kill instance alive, so it is not restarted at the end.
    if (LaneFightConfig.IsOn("Kill")) considerKill(bot, s, snap, read, target, windowKey, now);

    if (read.respect !== undefined) {
        if (s.phase === "idle") gate(bot, touch(s, `respect:${read.respect}:${tpid}`, now), `respect:${read.respect}`);
        return;
    }
    if (windowKey === undefined || !LaneFightConfig.IsOn("Trade")) return;
    const inst = touch(s, windowKey, now);
    if (s.phase !== "idle" || inst.started || s.streak < 2) return;
    // The read is cached for WindowReadEvery: range is measured on the target as the bot sees it now.
    let blocked = startBlocked(bot, false);
    const seen = blocked === undefined ? visibleEnemy(bot, tpid) : undefined;
    if (blocked === undefined && seen === undefined) blocked = "unseen";
    if (blocked === undefined && GetUnitToUnitDistance(bot, seen!) > bot.GetAttackRange() + TRADE_REACH) blocked = "range";
    // A trade has no focus caps: laning bidding at the floor would win the next round and abort it.
    if (blocked === undefined && laningOutbids(bot)) blocked = "laning";
    if (blocked !== undefined) gate(bot, inst, blocked);
    else start(bot, s, "trade", seen!, inst, now, [["window", read.window]], { partners: [], spell: read.window === "spell" });
}

function considerKill(
    bot: Unit,
    s: FightState,
    snap: LaneState.LaneSnapshot,
    read: FightRead.Read,
    target: Unit,
    windowKey: string | undefined,
    now: number,
): void {
    const tpid = target.GetPlayerID();
    const p = partnerOf(bot, snap);
    const plan = planKill(bot, p, target, now);
    s.lastMargin = plan.k?.margin;
    if (plan.action === "none") {
        s.killSince = undefined;
        const k = plan.k;
        if (k !== undefined && !k.pass && k.margin >= NEAR_MISS && k.reason !== undefined && s.phase !== "commit") {
            const miss = touch(s, `killfail:${tpid}`, now);
            const [logged] = next(miss.gates);
            if (logged === undefined) gate(bot, miss, `kill:${k.reason}`, tpid);
        }
        return;
    }
    if (s.killSince === undefined || s.killPid !== tpid) {
        s.killSince = now;
        s.killPid = tpid;
        s.killDelay = Profile.SampleDelay(bot, "react");
    }
    const inst = touch(s, `kill:${tpid}`, now);
    // A trade upgrades to a commit; a wait starts only from idle (a trading bot is already in, and follows).
    const ready = now - s.killSince >= s.killDelay && !inst.started && s.phase !== "commit" && (plan.action === "commit" || s.phase === "idle");
    if (!ready) return;
    const blocked = startBlocked(bot, true);
    if (blocked !== undefined) gate(bot, inst, blocked);
    else if (plan.action === "commit") {
        if (s.phase !== "idle") end(bot, s, "commit");
        start(bot, s, "commit", target, inst, now, [["margin", plan.k!.margin], ["via", plan.via]], {
            partners: plan.partners,
            spell: read.window === "spell",
            initiating: plan.via === "initiate",
        });
        // A commit spends the trade window on the same target too.
        if (windowKey !== undefined) {
            const w = touch(s, windowKey, now);
            w.started = true;
            s.spent.push(w);
        }
    } else if (p !== undefined) {
        if (p.human) callKill(bot, s, target, now);
        s.withPid = p.pid;
        start(bot, s, "wait_partner", target, inst, now, [["margin", plan.k!.margin], ["with", p.pid], ["human", p.human ? 1 : 0]], {
            partners: plan.partners,
            spell: false,
        });
    }
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
    coordinate(bot, st, snap, now);
    considerStart(bot, st, snap, now);
    if (st.phase !== "trade" && st.phase !== "commit") return raw;
    if (claim(bot, st.phase)) return raw;
    return math.max(raw, floorOf(bot, st.phase));
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
    } else if (s.phase === "commit") {
        // The engine walks into range with the attack target set: a partner sees the commit as an attack while closing.
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

/** "window=<type|none> kill=<margin|-> mem=<n> phase=<p>": the overlay's `fight` line. */
export function Describe(bot: Unit): string {
    const s = fights[bot.GetPlayerID()];
    const margin = s?.lastMargin !== undefined ? string.format("%.2f", s.lastMargin) : "-";
    return `window=${s?.lastWindow ?? "none"} kill=${margin} mem=${CooldownMemory.Count(bot.GetPlayerID(), DotaTime())} phase=${s?.phase ?? "idle"}`;
}

export function RegisterProbes(): void {
    LaneHooks.SetFightProbe((bot) => LaneFightConfig.IsActive() && CurrentPhase(bot) === "commit");
}

RegisterProbes();
