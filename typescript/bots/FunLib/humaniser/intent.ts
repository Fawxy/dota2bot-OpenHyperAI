/**
 * Intent arbitration (task 09): the one place that decides how humaniser features change mode desires.
 *
 * Features post claims (floor / cap / scale on a mode, at a priority tier) instead of editing desires.
 * Every OHA GetDesire() passes its result through Resolve(), which applies the claims in a fixed order,
 * adds a short stickiness bonus to the active mode, and records the result for the overlay.
 * Tick() watches mode switches (thrash limiter) and bots frozen inside a mode (stuck detector, OHA #167).
 *
 * All state is per bot (keyed by player ID) and only ever touches that bot's own claims, so this works
 * whether or not required modules are shared between a team's bots. Meepo and Arc Warden's tempest double
 * share a player ID between units, so they are left out: their desires pass through unresolved.
 */
import { BotMode, GameState, Team, Unit, Vector } from "bots/ts_libs/dota";
import * as Config from "bots/FunLib/humaniser/config";
import * as HDebug from "bots/FunLib/humaniser/debug";
import * as Telemetry from "bots/FunLib/humaniser/telemetry";
import * as Utils from "bots/FunLib/utils";

declare const BOT_ACTION_TYPE_IDLE: number;
declare const BOT_ACTION_TYPE_NONE: number;

export type Tier = "SURVIVAL" | "HUMAN_ORDER" | "FIGHT" | "LANE_PLAN" | "CAMP_JOB" | "TRANSITION" | "MOOD";

const TIER_RANK: Record<Tier, number> = {
    MOOD: 1,
    TRANSITION: 2,
    CAMP_JOB: 3,
    LANE_PLAN: 4,
    FIGHT: 5,
    HUMAN_ORDER: 6,
    SURVIVAL: 7,
};

export interface Claim {
    /** Feature and reason, e.g. "orders:ROSHAN", "lane:pull", "mood:tilt". Also the deterministic tie-break. */
    source: string;
    tier: Tier;
    mode: BotMode | "ANY";
    /** Modes an "ANY" claim leaves alone. */
    except?: BotMode[];
    floor?: number;
    cap?: number;
    scale?: number;
    /** GameTime() expiry. Without it the claim lives for ClaimTTL, so it must be re-posted while it applies. */
    until?: number;
    /** HUMAN_ORDER only: the human accepted the risk, so SURVIVAL claims on this mode are ignored. */
    allowRisk?: boolean;
    /** Only clamp a mode whose desire a claim floor has lifted above its (scaled) raw desire. */
    onlyLifted?: boolean;
}

interface StoredClaim extends Claim {
    expires: number;
}

interface ModeSample {
    raw: number;
    resolved: number;
    time: number;
    by: string;
}

interface BotState {
    claims: Record<string, StoredClaim>;
    // Last time a SURVIVAL or HUMAN_ORDER claim was posted; while recent, stickiness is off for this bot.
    priorityAt: number;
    samples: Record<number, ModeSample>;
    mode?: number;
    modeSince: number;
    switchTimes: number[];
    switchCount: number;
    thrashUntil: number;
    thrashMode?: number;
    thrashEpisodes: number;
    stillAnchor?: Vector;
    stillSince: number;
    idleSince?: number;
    stuckEpisode: boolean;
    stuckByMode: Record<number, number>;
    conflicts: Record<string, number>;
    lastConflict: Record<number, string>;
    summaryCheckAt: number;
    summaryPrinted: boolean;
}

/** Bot API methods used here that ts_libs does not declare yet. */
interface ActorBot {
    GetCurrentActionType(): number;
    NumQueuedActions(): number;
    IsUsingAbility(): boolean;
    IsCastingAbility(): boolean;
    IsStunned(): boolean;
    IsHexed(): boolean;
    DistanceFromFountain(): number;
}

export const DEFAULTS = {
    Enable: true,
    // Claims posted without `until` stay valid this long. The engine evaluates modes in its own order and
    // Tick runs from ItemUsageThink, so a claim must outlive the frame it was posted in to reach every mode.
    ClaimTTL: 0.2,
    // Combined effect of all scale claims (mood, mistakes) is clamped to 1 ± ScaleClamp.
    ScaleClamp: 0.3,
    Sticky: { Bonus: 0.06, MinDwell: 1.0, Decay: 1.0 },
    Thrash: { Window: 5, MaxSwitches: 4, Bonus: 0.12, Duration: 3 },
    Stuck: {
        Enable: true,
        After: 1.5,
        StillRadius: 50,
        // "idle_and_still": no action queued AND not moving. "idle_or_still" (the handoff's rule) also flags
        // bots that stand still on purpose, such as a laner waiting for a last hit.
        Match: "idle_and_still" as "idle_and_still" | "idle_or_still",
        MinDesire: 0.1,
        Drop: 0.15,
        Duration: 2,
        BaseRadius: 2600,
    },
    // Low HP and retreat wants out: every other mode is capped just below retreat (SURVIVAL tier).
    Survival: { Enable: true, HP: 0.25, MinRetreat: 0.5, Margin: 0.05 },
    Summary: true,
};

export type IntentConfig = typeof DEFAULTS;

const SAMPLE_FRESH = 0.5;
const SUMMARY_CHECK_INTERVAL = 1;

function merge(defaults: any, overrides: any): any {
    if (overrides === undefined || overrides === null || type(overrides) !== "table") return defaults;
    const result: any = {};
    for (const [k, v] of pairs(defaults)) result[k] = v;
    for (const [k, v] of pairs(overrides)) {
        const d = defaults[k];
        result[k] = d !== undefined && type(d) === "table" && type(v) === "table" ? merge(d, v) : v;
    }
    return result;
}

let cached: IntentConfig | undefined;
export function Get(): IntentConfig {
    if (cached === undefined) cached = merge(DEFAULTS, Config.Get().Intent) as IntentConfig;
    return cached;
}

export function IsActive(): boolean {
    return Config.IsFeatureEnabled("Intent");
}

const states: Record<number, BotState> = {};

function stateFor(bot: Unit): BotState {
    const pid = bot.GetPlayerID();
    let s = states[pid];
    if (s === undefined) {
        s = {
            claims: {},
            priorityAt: -math.huge,
            samples: {},
            modeSince: 0,
            switchTimes: [],
            switchCount: 0,
            thrashUntil: -math.huge,
            thrashEpisodes: 0,
            stillSince: 0,
            stuckEpisode: false,
            stuckByMode: {},
            conflicts: {},
            lastConflict: {},
            summaryCheckAt: -math.huge,
            summaryPrinted: false,
        };
        states[pid] = s;
    }
    return s;
}

function sharesPlayerID(bot: Unit): boolean {
    return bot.GetUnitName() === "npc_dota_hero_meepo" || bot.HasModifier("modifier_arc_warden_tempest_double");
}

export function Claim(bot: Unit, claim: Claim): void {
    if (!IsActive() || sharesPlayerID(bot)) return;
    const s = stateFor(bot);
    const now = GameTime();
    const stored: StoredClaim = { ...claim, expires: claim.until ?? now + Get().ClaimTTL };
    s.claims[`${claim.source}|${tostring(claim.mode)}`] = stored;
    if (claim.tier === "SURVIVAL" || claim.tier === "HUMAN_ORDER") s.priorityAt = now;
}

export function Release(bot: Unit, source: string, mode: BotMode | "ANY"): void {
    const s = states[bot.GetPlayerID()];
    if (s !== undefined) s.claims[`${source}|${tostring(mode)}`] = undefined as any;
}

function applies(claim: StoredClaim, mode: number): boolean {
    if (claim.mode === mode) return true;
    if (claim.mode !== "ANY") return false;
    if (claim.except !== undefined) for (const m of claim.except) if (m === mode) return false;
    return true;
}

function compareClaims(a: StoredClaim, b: StoredClaim): number {
    const ta = TIER_RANK[a.tier];
    const tb = TIER_RANK[b.tier];
    if (ta !== tb) return ta - tb;
    if (a.expires !== b.expires) return a.expires - b.expires;
    if (a.source !== b.source) return a.source < b.source ? -1 : 1;
    // Same source on "ANY" and on a specific mode: the specific one is applied last.
    return a.mode === "ANY" ? (b.mode === "ANY" ? 0 : -1) : b.mode === "ANY" ? 1 : 0;
}

function stickyBonus(s: BotState, mode: number, now: number): number {
    const cfg = Get();
    let bonus = 0;
    const dwell = now - s.modeSince;
    if (dwell <= cfg.Sticky.MinDwell) bonus = cfg.Sticky.Bonus;
    else if (cfg.Sticky.Decay > 0 && dwell < cfg.Sticky.MinDwell + cfg.Sticky.Decay) {
        bonus = cfg.Sticky.Bonus * (1 - (dwell - cfg.Sticky.MinDwell) / cfg.Sticky.Decay);
    }
    if (now < s.thrashUntil && s.thrashMode === mode) bonus = math.max(bonus, cfg.Thrash.Bonus);
    return bonus;
}

function noteConflict(s: BotState, mode: number, key: string): void {
    if (s.lastConflict[mode] === key) return;
    s.lastConflict[mode] = key;
    s.conflicts[key] = (s.conflicts[key] ?? 0) + 1;
}

/**
 * Applies this bot's claims to a mode's raw desire. Call at the end of every GetDesire().
 * Non-numbers (nil = use Valve's desire) pass through untouched.
 */
export function Resolve(bot: Unit, mode: number, raw: any): any {
    // mode is nil when a BOT_MODE_* global is missing in this game build (BOT_MODE_OUTPOST is unverified).
    if (type(raw) !== "number" || mode === undefined || !IsActive() || sharesPlayerID(bot)) return raw;
    const cfg = Get();
    const now = GameTime();
    const s = stateFor(bot);

    let ordered: StoredClaim[] | undefined;
    let scale = 1;
    let riskAllowed = false;
    let capped = false;
    for (const [key, claim] of pairs(s.claims)) {
        if (claim.expires < now) {
            s.claims[key] = undefined as any;
        } else if (applies(claim, mode)) {
            if (claim.scale !== undefined) scale *= claim.scale;
            if (claim.tier === "HUMAN_ORDER" && claim.allowRisk === true) riskAllowed = true;
            if (claim.cap !== undefined) capped = true;
            if (claim.floor !== undefined || claim.cap !== undefined) {
                if (ordered === undefined) ordered = [];
                ordered.push(claim);
            }
        }
    }

    const scaled = raw * math.min(math.max(scale, 1 - cfg.ScaleClamp), 1 + cfg.ScaleClamp);
    let desire = scaled;
    let by = desire !== raw ? "scale" : "raw";
    let setter: string | undefined;
    let conflicted = false;
    if (ordered !== undefined) {
        if (ordered.length > 1) ordered.sort((a, b) => compareClaims(a, b));
        for (const claim of ordered) {
            if (claim.tier === "SURVIVAL" && riskAllowed) continue;
            if (claim.onlyLifted === true && desire <= scaled) continue;
            let value = desire;
            if (claim.floor !== undefined && value < claim.floor) value = claim.floor;
            if (claim.cap !== undefined && value > claim.cap) value = claim.cap;
            if (value !== desire) {
                if (setter !== undefined && setter !== claim.source) {
                    noteConflict(s, mode, `${claim.source}>${setter}`);
                    conflicted = true;
                }
                setter = claim.source;
                by = claim.source;
                desire = value;
            }
        }
    }

    if (!conflicted) s.lastConflict[mode] = undefined as any;

    // No bonus over a mode's own caps, while an order or survival claim is live, or against a retreat that is
    // already as strong: stickiness must never be what keeps a bot in a fight it wants out of.
    const retreat = s.samples[BotMode.Retreat];
    const retreatContends = mode !== BotMode.Retreat && retreat !== undefined && now - retreat.time <= SAMPLE_FRESH && retreat.resolved >= desire;
    if (mode === s.mode && desire > 0 && !capped && !retreatContends && now - s.priorityAt > cfg.ClaimTTL) {
        const bonus = stickyBonus(s, mode, now);
        if (bonus > 0) {
            desire += bonus;
            by = `${by}+sticky`;
        }
    }
    desire = math.max(desire, 0);

    if (mode === BotMode.Retreat && cfg.Survival.Enable && desire >= cfg.Survival.MinRetreat) {
        if (bot.GetHealth() / bot.GetMaxHealth() < cfg.Survival.HP) {
            Claim(bot, {
                source: "intent:survival",
                tier: "SURVIVAL",
                mode: "ANY",
                except: [BotMode.Retreat],
                cap: desire - cfg.Survival.Margin,
                onlyLifted: true,
            });
        }
    }

    const sample = s.samples[mode];
    if (sample === undefined) s.samples[mode] = { raw, resolved: desire, time: now, by };
    else {
        sample.raw = raw;
        sample.resolved = desire;
        sample.time = now;
        sample.by = by;
    }
    HDebug.RecordDesire(bot, mode, desire);
    return desire;
}

/** "<mode> <desire> by <winning claim source>", for the overlay and logs. */
export function Explain(bot: Unit, mode: number): string {
    const s = states[bot.GetPlayerID()];
    const sample = s?.samples[mode];
    if (sample === undefined || GameTime() - sample.time > SAMPLE_FRESH) return `${HDebug.ModeName(mode)} (valve)`;
    return `${HDebug.ModeName(mode)} ${string.format("%.2f", sample.resolved)} by ${sample.by}`;
}

function competingModes(s: BotState, now: number): string {
    const fresh: [number, number][] = [];
    for (const [mode, sample] of pairs(s.samples)) {
        if (now - sample.time <= SAMPLE_FRESH) fresh.push([mode, sample.resolved]);
    }
    fresh.sort((a, b) => b[1] - a[1]);
    const parts: string[] = [];
    for (let i = 0; i < fresh.length && i < 4; i++) parts.push(`${HDebug.ModeName(fresh[i][0])}=${string.format("%.2f", fresh[i][1])}`);
    return parts.join(" ");
}

/** The freshest resolved desires, highest first, e.g. "farm=0.62 laning=0.40". */
export function Competing(bot: Unit): string {
    const s = states[bot.GetPlayerID()];
    return s !== undefined ? competingModes(s, GameTime()) : "";
}

function onModeSwitch(bot: Unit, s: BotState, mode: number, now: number): void {
    const first = s.mode === undefined;
    s.mode = mode;
    s.modeSince = now;
    s.stuckEpisode = false;
    if (first) return;

    const cfg = Get().Thrash;
    s.switchCount++;
    s.switchTimes.push(now);
    while (s.switchTimes.length > 0 && s.switchTimes[0] < now - cfg.Window) s.switchTimes.shift();
    if (s.switchTimes.length > cfg.MaxSwitches && now >= s.thrashUntil) {
        s.thrashUntil = now + cfg.Duration;
        s.thrashMode = mode;
        s.thrashEpisodes++;
        HDebug.Log("intent", `thrash pid=${bot.GetPlayerID()} switches=${s.switchTimes.length}/${cfg.Window}s now=${HDebug.ModeName(mode)} ${competingModes(s, now)}`);
        Telemetry.Event("thrash", [
            ["pid", bot.GetPlayerID()],
            ["switches", s.switchTimes.length],
            ["window", cfg.Window],
            ["mode", HDebug.ModeName(mode)],
            ["competing", competingModes(s, now)],
        ]);
    }
}

function isIdle(bot: ActorBot): boolean {
    const action = bot.GetCurrentActionType();
    return (action === BOT_ACTION_TYPE_IDLE || action === BOT_ACTION_TYPE_NONE) && bot.NumQueuedActions() === 0;
}

function isBusyOrSafe(bot: Unit & ActorBot, cfg: IntentConfig["Stuck"]): boolean {
    return bot.IsChanneling() || bot.IsUsingAbility() || bot.IsCastingAbility() || bot.IsStunned() || bot.IsHexed() || bot.DistanceFromFountain() < cfg.BaseRadius;
}

function checkStuck(bot: Unit, s: BotState, mode: number, now: number): void {
    const cfg = Get().Stuck;
    if (!cfg.Enable) return;
    const actor = bot as Unit & ActorBot;
    if (GetGameState() !== GameState.GameInProgress || DotaTime() <= 0 || !bot.IsAlive() || mode === BotMode.None) {
        s.stuckEpisode = false;
        s.stillAnchor = undefined;
        s.idleSince = undefined;
        return;
    }

    const loc = bot.GetLocation();
    if (s.stillAnchor === undefined || Utils.GetLocationToLocationDistance(loc, s.stillAnchor) > cfg.StillRadius) {
        s.stillAnchor = loc;
        s.stillSince = now;
    }
    if (!isIdle(actor)) s.idleSince = undefined;
    else if (s.idleSince === undefined) s.idleSince = now;

    if (isBusyOrSafe(actor, cfg)) {
        s.stuckEpisode = false;
        return;
    }

    const idle = s.idleSince !== undefined && now - s.idleSince >= cfg.After;
    const still = now - s.stillSince >= cfg.After;
    const frozen = cfg.Match === "idle_or_still" ? idle || still : idle && still;
    // Judge by the raw desire where we have it: the active desire already includes our own stuck cap.
    const desire = bot.GetActiveModeDesire();
    const sample = s.samples[mode];
    const raw = sample !== undefined && now - sample.time <= SAMPLE_FRESH ? sample.raw : desire;
    if (!frozen || now - s.modeSince < cfg.After || raw < cfg.MinDesire) {
        s.stuckEpisode = false;
        return;
    }

    // Kept alive for the whole episode; it expires Duration after the bot gets going again.
    Claim(bot, { source: "intent:stuck", tier: "LANE_PLAN", mode: mode as BotMode, cap: math.max(raw - cfg.Drop, 0), until: now + cfg.Duration });
    if (s.stuckEpisode) return;
    s.stuckEpisode = true;
    s.stuckByMode[mode] = (s.stuckByMode[mode] ?? 0) + 1;
    HDebug.Log(
        "intent",
        `stuck pid=${bot.GetPlayerID()} mode=${HDebug.ModeName(mode)} desire=${string.format("%.2f", desire)} since=${string.format("%.1f", s.modeSince)}`
    );
    Telemetry.Event("stuck", [
        ["pid", bot.GetPlayerID()],
        ["mode", HDebug.ModeName(mode)],
        ["d", desire],
        ["raw", raw],
        ["inMode", now - s.modeSince],
    ]);
}

function ancientDown(team: Team): boolean {
    const ancient = GetAncient(team);
    return ancient === undefined || ancient === null || !ancient.IsAlive() || ancient.GetHealth() <= 0;
}

function joinCounts(counts: Record<string | number, number>, name: (k: string | number) => string): string {
    const parts: string[] = [];
    for (const [k, n] of pairs(counts)) parts.push(`${name(k)}:${n}`);
    parts.sort();
    return parts.length > 0 ? parts.join(",") : "-";
}

export function SummaryLine(bot: Unit): string {
    const s = stateFor(bot);
    return `[H:intent] summary pid=${bot.GetPlayerID()} ${string.gsub(bot.GetUnitName(), "npc_dota_hero_", "")[0]} switches=${s.switchCount} thrash=${
        s.thrashEpisodes
    } stuck=${joinCounts(s.stuckByMode, k => HDebug.ModeName(tonumber(k)!))} conflicts=${joinCounts(s.conflicts, k => tostring(k))}`;
}

function maybeSummary(bot: Unit, s: BotState, now: number): void {
    if (s.summaryPrinted || !Get().Summary || now - s.summaryCheckAt < SUMMARY_CHECK_INTERVAL) return;
    s.summaryCheckAt = now;
    if (GetGameState() !== GameState.PostGame && !ancientDown(Team.Radiant) && !ancientDown(Team.Dire)) return;
    s.summaryPrinted = true;
    const rawPrint: ((line: string) => void) | undefined = (Utils as any).RawPrint;
    (rawPrint ?? print)(SummaryLine(bot));
}

/** Mode-switch tracking, stuck detection and the end-of-game summary. Runs every frame from Humaniser.Tick. */
export function Tick(bot: Unit): void {
    if (!IsActive() || sharesPlayerID(bot)) return;
    const s = stateFor(bot);
    const now = GameTime();
    const mode = bot.GetActiveMode();
    if (mode !== s.mode) onModeSwitch(bot, s, mode, now);
    checkStuck(bot, s, mode, now);
    maybeSummary(bot, s, now);
}
