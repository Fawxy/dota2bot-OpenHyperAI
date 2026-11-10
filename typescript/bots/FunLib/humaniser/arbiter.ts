/**
 * Shadow arbiter (slice arbiter-shadow, design docs/proposals/2026-11-11-arbiter.md s2-s4): per owned hero, one pick among
 * candidates by doctrine group, logged as ev=arb beside the mode Valve holds the hero in. It changes no desire and no
 * behaviour: Candidates reads state only (no cache is refreshed), and Shadow's result is not used by the gate.
 */
import { BotMode, Unit } from "bots/ts_libs/dota";
import * as CampJobs from "bots/FunLib/humaniser/camp_jobs";
import * as CoreTrade from "bots/FunLib/humaniser/states/core_trade";
import * as Drill from "bots/FunLib/humaniser/drill";
import * as HDebug from "bots/FunLib/humaniser/debug";
import * as LaneConfig from "bots/FunLib/humaniser/lane_config";
import * as LaneControl from "bots/FunLib/humaniser/lane_control";
import * as LanePick from "bots/FunLib/humaniser/states/lane_pick";
import * as LaneFight from "bots/FunLib/humaniser/lane_fight";
import * as Ours from "bots/FunLib/humaniser/ours";
import * as RetreatState from "bots/FunLib/humaniser/retreat_state";
import * as RuneJob from "bots/FunLib/humaniser/rune_job";
import * as Telemetry from "bots/FunLib/humaniser/telemetry";
import * as MidRunes from "bots/FunLib/humaniser/transitions/mid_runes";
import * as Phase from "bots/FunLib/humaniser/transitions/phase";

/**
 * Doctrine groups: 1 stay alive, 2 pair, 3 farm, 4 wave, 5 pressure, 6 jobs; lower wins. The lane is the base, below every
 * interrupt candidate, and `oha` below it; both log their rank as text in `grp`.
 */
export const OHA = "oha";
export const BASE_GROUP = 7;
const OHA_GROUP = 8;

export interface Candidate {
    name: string;
    group: number;
    /** The Valve mode (debug.ts ModeName) that would carry it out; none for `oha`. */
    host?: string;
    applies: boolean;
}

/** The lowest group number that applies wins; a tie inside it keeps the previous pick, else the first in list order. */
export function Pick(candidates: Candidate[], previous?: string): Candidate | undefined {
    let best: Candidate | undefined;
    let prev: Candidate | undefined;
    for (const c of candidates) {
        if (!c.applies) continue;
        if (c.name === previous) prev = c;
        if (best === undefined || c.group < best.group) best = c;
    }
    if (best === undefined) return undefined;
    if (prev !== undefined && prev.group <= best.group) return prev;
    return best;
}

/** Whether `who` (a lever's taker: both, core, sup or a pid) names this hero. */
function leverNames(who: string, pid: number, pos: number | undefined): boolean {
    if (who === "both" || who === `${pid}`) return true;
    if (pos === undefined) return false;
    return who === (pos >= 4 ? "sup" : "core");
}

/** The live lever of the lane controller that names this hero, if any. */
export function LeverOf(bot: Unit): string | undefined {
    const d = LaneControl.Current(bot.GetTeam(), bot.GetAssignedLane());
    if (d === undefined) return undefined;
    const pid = bot.GetPlayerID();
    const pos = LaneConfig.PositionOf(bot);
    for (let i = 0; i < d.levers.length; i++) {
        if (d.levers[i] !== "hold" && leverNames(d.who[i], pid, pos)) return d.levers[i];
    }
    return undefined;
}

/** A hero of ours the arbiter reasons about: a bot in its laning phase (as last read by its own callers) that no drill holds. */
function owned(bot: Unit): boolean {
    return Phase.LaningTransitionsSeen(bot) === true && !Drill.Held(bot);
}

/** The lane picker's body is in a last-hit attempt right now: its stored phase label, fresh within a second of its last scan. */
function lastHitNow(bot: Unit): boolean {
    const d = LanePick.Describe(bot.GetPlayerID(), DotaTime());
    if (d === undefined || !d.startsWith("ph=lasthit ")) return false;
    const [age] = string.match(d, "sc=([%d%.]+)");
    return age !== undefined && tonumber(age)! <= 1;
}

function retreatCandidate(bot: Unit): Candidate {
    return { name: "retreat", group: 1, host: "retreat", applies: RetreatState.Running(bot) };
}

/** A pull lever of the controller lifts the running pull job to group 4; any other job is group 6. */
function jobCandidate(bot: Unit, job: string | undefined, lever: string | undefined): Candidate {
    const host = RuneJob.HostOf(bot) === BotMode.Rune ? "rune" : "farm";
    const pulls = job === "pull" || (job !== undefined && job.endsWith("_pull"));
    return { name: "job", group: lever === "pull" && pulls ? 4 : 6, host, applies: job !== undefined };
}

/**
 * The job is the chooser's running job, else a live camp job of the older camp-job path (`jobName` is then its kind). The
 * controller's lever is no candidate of its own: the in-lane levers are carried out by the laning body, so they ride on
 * `lane` and are logged as the `lever` field.
 */
export function Candidates(bot: Unit, jobName: string | undefined, lever: string | undefined = LeverOf(bot)): Candidate[] {
    if (!owned(bot)) return [{ name: OHA, group: OHA_GROUP, applies: true }];
    const out: Candidate[] = [];
    out.push(retreatCandidate(bot));
    out.push({ name: "trade", group: 5, host: "attack", applies: CoreTrade.Running(bot) });
    out.push({ name: "lane_fight", group: 5, host: "team_roam", applies: LaneFight.CurrentPhase(bot) !== "idle" });
    out.push(jobCandidate(bot, jobName ?? CampJobs.LiveKind(bot), lever));
    out.push({ name: "mid_rune", group: 6, host: "rune", applies: MidRunes.Claiming(bot) });
    // The base: it wins when no interrupt applies, and is group 3 only while a last hit is under way (D11).
    out.push({ name: "lane", group: lastHitNow(bot) ? 3 : BASE_GROUP, host: "laning", applies: true });
    out.push({ name: OHA, group: OHA_GROUP, applies: true });
    return out;
}

/**
 * The candidate the gate enforces now, if any: the hero's modes other than its host and the modes the gate admits for it
 * get desire 0. Only the driven candidates are asked (the retreat episode and the chooser's running job); every other
 * candidate is still shadow only and interrupts nothing. Not limited to laning heroes: an episode or a job is its own
 * claim on the hero (a drill's cast runs jobs while held).
 */
export function Hold(bot: Unit, chooserJob: string | undefined): Candidate | undefined {
    return Pick([retreatCandidate(bot), jobCandidate(bot, chooserJob, undefined)]);
}

interface Last {
    pick: string;
    act: string;
    since: number;
}

const last: Record<number, Last | undefined> = {};
const nextAt: Record<number, number | undefined> = {};

/** judgement: seconds between computes per hero; the gate calls Shadow from all 20 mode files every frame. */
const PERIOD = 0.25;

function compute(bot: Unit, jobName: string | undefined): void {
    const pid = bot.GetPlayerID();
    const now = DotaTime();
    const l = last[pid];
    const lever = LeverOf(bot);
    const cands = Candidates(bot, jobName, lever);
    const job = jobName ?? CampJobs.LiveKind(bot);
    const picked = Pick(cands, l?.pick) ?? cands[cands.length - 1];
    const act = HDebug.ModeName(bot.GetActiveMode());
    if (l !== undefined && l.pick === picked.name && l.act === act) return;
    Telemetry.Event("arb", [
        ["pid", pid],
        ["pick", picked.name],
        ["grp", picked.group < BASE_GROUP ? picked.group : picked.name === OHA ? "oha" : "base"],
        ["host", picked.host],
        ["act", act],
        ["agree", picked.name === OHA || picked.host === act ? 1 : 0],
        ["job", job],
        ["lever", lever],
        ["prev", l?.pick],
        ["dwell", l !== undefined ? now - l.since : undefined],
    ]);
    last[pid] = { pick: picked.name, act, since: now };
}

/**
 * Called from every mode's gate each frame; computes at most once per hero per PERIOD (also after an error) and logs on a
 * change of pick or active mode. Returns nothing, and an error inside it is swallowed so it cannot reach GetDesire.
 */
export function Shadow(bot: Unit, jobName: () => string | undefined): void {
    if (!Telemetry.IsEnabled() || !Ours.On("ArbiterShadow")) return;
    const pid = bot.GetPlayerID();
    const now = DotaTime();
    const due = nextAt[pid];
    if (due !== undefined && now < due && now >= due - PERIOD) return;
    nextAt[pid] = now + PERIOD;
    pcall(() => compute(bot, jobName()));
}
