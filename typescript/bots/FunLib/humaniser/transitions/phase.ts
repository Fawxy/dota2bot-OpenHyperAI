/**
 * Lane safety and laning-phase transitions (task 12, Task 8): per-bot end of laning.
 * IsLaningFor says whether a bot is still laning (its tower fell, a support left for a smoke gank, a core with a
 * farm item has a quiet jungle).
 */
import { BotMode, Lane, Tower, Unit, Vector } from "bots/ts_libs/dota";
import * as Intent from "bots/FunLib/humaniser/intent";
import * as LaneConfig from "bots/FunLib/humaniser/lane_config";
import * as LaneState from "bots/FunLib/humaniser/lane_state";
import * as Camps from "bots/FunLib/humaniser/camps";
import * as Commands from "bots/FunLib/humaniser/commands";
import * as Orders from "bots/FunLib/humaniser/orders";
import * as Difficulty from "bots/FunLib/humaniser/difficulty";
import * as Trainer from "bots/FunLib/humaniser/trainer/trainer";
import * as Settings from "bots/FunLib/humaniser/transitions/settings";
import * as Telemetry from "bots/FunLib/humaniser/telemetry";
import * as Config from "bots/FunLib/humaniser/config";

export const SOURCE_PHASE = "transitions:phase";

export const FARM_ITEMS = ["item_maelstrom", "item_battle_fury", "item_radiance", "item_hand_of_midas", "item_mjollnir"];

const T1: Record<number, number> = { [Lane.Top]: Tower.Top1, [Lane.Mid]: Tower.Mid1, [Lane.Bot]: Tower.Bot1 };

interface PhaseState {
    wasLaning: boolean;
    checkAt: number;
    phaseEnded: boolean;
    // Last reported laning state, for tr_laning on change.
    laningWhy?: string;
    cap?: string;
    jungleSaid: boolean;
}

let states: Record<number, PhaseState> = {};
let laningReads: Record<number, { at: number; value: boolean }> = {};
let held: Record<number, { on: boolean; ended?: string; checkAt: number }> = {};

export function ResetCache(): void {
    states = {};
    laningReads = {};
    held = {};
}

function stateOf(bot: Unit): PhaseState {
    const pid = bot.GetPlayerID();
    let st = states[pid];
    if (st === undefined) {
        st = { checkAt: -math.huge, wasLaning: false, phaseEnded: false, jungleSaid: false };
        states[pid] = st;
    }
    return st;
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

/** Why the bot is no longer laning ("phase", "tower", "smoke", "farm"), or undefined while it still is. */
function notLaningWhy(bot: Unit): string | undefined {
    if (!LaneConfig.InLaningPhase()) return "phase";
    const cfg = Settings.Get();
    const team = bot.GetTeam();
    const lane = bot.GetAssignedLane();
    if (towerDown(team, lane) || towerDown(team === 2 ? 3 : 2, lane)) return "tower";
    const pos = LaneConfig.PositionOf(bot);
    const now = Config.Now();
    if (pos !== undefined && pos >= 4) {
        if (bot.GetLevel() > cfg.SupportLevel && now >= cfg.SupportFrom && now <= cfg.SupportTo) {
            if (Commands.HasSmoke(bot) || Orders.GetAccepted(bot, "ATTACK") !== undefined || Orders.GetAccepted(bot, "SMOKE") !== undefined) return "smoke";
        }
    } else if (pos !== undefined && hasFarmItem(bot) && jungleSafe(bot)) {
        return "farm";
    }
    return undefined;
}

export function IsLaningFor(bot: Unit): boolean {
    return notLaningWhy(bot) === undefined;
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

/**
 * The value LaningTransitions last stored for this hero, without reading or storing anything; undefined when none was
 * stored in the last two seconds. For a caller that must not move the cache's clock (the shadow arbiter).
 */
export function LaningTransitionsSeen(bot: Unit): boolean | undefined {
    const r = laningReads[bot.GetPlayerID()];
    const now = DotaTime();
    return r !== undefined && now >= r.at && now - r.at <= 2 ? r.value : undefined;
}

/** judgement: seconds between end checks of a held hero (LaningHeld). */
const HELD_CHECK = 1;

/** Why a held hero's laning ends (rework step 7): the clock exit (until D23), a tier-1 of its lane lost (ours or theirs). */
function heldEndWhy(bot: Unit): string | undefined {
    if (!LaneConfig.InLaningPhase()) return "clock";
    const team = bot.GetTeam();
    const lane = bot.GetAssignedLane();
    if (towerDown(team, lane) || towerDown(team === 2 ? 3 : 2, lane)) return "tower";
    return undefined;
}

/**
 * Rework step 7 (`Ours.ArbiterDrive`, asked by the arbiter and our retreat): the hero is held from its first laning read
 * (LaningTransitions true) to an end event (heldEndWhy), and never again after it. Other not-laning reasons (a support's
 * smoke, a core's farm item) do not end it, and no read goes stale. The start and the end log `ev=arb` with `ph`.
 */
export function LaningHeld(bot: Unit): boolean {
    const pid = bot.GetPlayerID();
    const now = DotaTime();
    let h = held[pid];
    if (h === undefined) {
        h = { on: false, checkAt: -math.huge };
        held[pid] = h;
    }
    if (h.ended !== undefined) return false;
    if (!h.on) {
        if (!LaningTransitions(bot)) return false;
        h.on = true;
        h.checkAt = now + HELD_CHECK;
        Telemetry.Event("arb", [["pid", pid], ["ph", "own"]]);
        return true;
    }
    if (now < h.checkAt) return true;
    h.checkAt = now + HELD_CHECK;
    const why = heldEndWhy(bot);
    if (why === undefined) return true;
    h.on = false;
    h.ended = why;
    Telemetry.Event("arb", [["pid", pid], ["ph", "end"], ["why", why]]);
    return false;
}

function sample(bot: Unit, st: PhaseState): void {
    const why = notLaningWhy(bot);
    st.wasLaning = why === undefined;
    if (why !== st.laningWhy) {
        st.laningWhy = why;
        Telemetry.Event("tr_laning", [["pid", bot.GetPlayerID()], ["laning", why === undefined], ["why", why]]);
    }
}

function evaluate(bot: Unit, st: PhaseState): void {
    st.phaseEnded = false;
    st.cap = undefined;
    if (!LaneConfig.InLaningPhase()) return;
    if (st.wasLaning) {
        st.jungleSaid = false;
        return;
    }
    st.phaseEnded = true;
    st.cap = SOURCE_PHASE;
    const pos = LaneConfig.PositionOf(bot);
    if (!st.jungleSaid && pos !== undefined && pos <= 3 && Difficulty.IsAllyOfHuman(bot)) {
        st.jungleSaid = Orders.Say(bot, "say_going_jungle", Settings.Get().SuggestCooldown);
    }
}

export function Tick(bot: Unit): void {
    if (!Settings.IsOn("Phase")) {
        Intent.Release(bot, SOURCE_PHASE, BotMode.Laning);
        return;
    }
    const st = stateOf(bot);
    const now = DotaTime();
    if (now >= st.checkAt) {
        st.checkAt = now + Settings.Get().Refresh;
        sample(bot, st);
        evaluate(bot, st);
    }
    if (st.cap === SOURCE_PHASE) Intent.Claim(bot, { source: SOURCE_PHASE, tier: "TRANSITION", mode: BotMode.Laning, cap: Settings.Get().LaningCap });
    else Intent.Release(bot, SOURCE_PHASE, BotMode.Laning);
}

/** Farm-mode hook: a core whose laning has ended may farm. */
export function FarmAllowedInLaning(bot: Unit): boolean {
    const pos = LaneConfig.PositionOf(bot);
    if (pos === undefined || pos > 3) return false;
    const st = states[bot.GetPlayerID()];
    if (st === undefined) return false;
    return Settings.IsOn("Phase") && st.phaseEnded;
}
