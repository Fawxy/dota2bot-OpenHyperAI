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
import * as Overrides from "bots/FunLib/humaniser/overrides";
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

/**
 * A hero of ours the arbiter reasons about, one no drill holds: with `Ours.ArbiterDrive`, from its first laning read to an
 * end event (Phase.LaningHeld), and never a drill's lane-only hero (its laning holds it at 1.2, only the thing under test
 * acts); off, a bot in its laning phase as last read by its own callers (no cache clock moves).
 */
export function Owned(bot: Unit): boolean {
    if (Drill.Held(bot)) return false;
    if (Ours.On("ArbiterDrive")) return !Overrides.LaneOnly(bot) && Phase.LaningHeld(bot);
    return Phase.LaningTransitionsSeen(bot) === true;
}
const owned = Owned;

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

// --- The drive (rework step 7, Ours.ArbiterDrive): the pick holds every owned laner. ---

export const SETTINGS = {
    /**
     * The laning mode's desire while the lane is the pick. Over the Valve built-in mode that took a hero no file wanted
     * (fix6, 12/11/2026: mode 28 at 0.475, which no mode file gates); under a trade's opening desire (core_trade
     * DESIRE_TRADE 0.6), so a trade the borrowed attack mode opens takes the hero; an admitted mode (wards, runes no plan of
     * ours covers) wins when OHA's own desire for it is higher. Laning's own last-hit desire (0.9, our body's branch under
     * bOwnsThink, OWNERSHIP H2) stands when higher. `judgement`.
     */
    LaneDesire: 0.55,
};

const drivePrev: Record<number, string | undefined> = {};
const driveAt: Record<number, number | undefined> = {};
const drivePick: Record<number, Candidate | undefined> = {};

/** Whether the drive holds this hero now: the switch on and the hero owned. */
export function Drives(bot: Unit): boolean {
    return Ours.On("ArbiterDrive") && owned(bot);
}

/**
 * The pick the gate enforces for an owned hero under the drive, computed once per hero per frame (the gate asks from all 20
 * mode files) and remembered for the next frame's tie. `chooserJob` is the chooser's running job.
 */
export function Drive(bot: Unit, chooserJob: string | undefined): Candidate {
    const pid = bot.GetPlayerID();
    const now = DotaTime();
    const cached = drivePick[pid];
    if (cached !== undefined && driveAt[pid] === now) return cached;
    const cands = Candidates(bot, chooserJob);
    const p = Pick(cands, drivePrev[pid]) ?? cands[cands.length - 1];
    drivePick[pid] = p;
    driveAt[pid] = now;
    drivePrev[pid] = p.name;
    return p;
}

/**
 * The lane and our trade share the hero by their own desires, whatever the pick (OWNERSHIP H2: a trade yields to a last
 * hit, a kill or fight does not, `CoreTrade.LastHitYields`): the lane's last-hit lift does not end a running trade, and a
 * trade does not hold laning at 0. Review 13/11/2026: the pick alone swapped them, since the lift reads the laning body's
 * scan, which goes stale once attack holds the hero.
 */
function laneAndTrade(p: Candidate): boolean {
    return p.name === "lane" || p.name === "trade";
}

/** Fight modes borrowed from OHA: what says our fight read wants them now (the attack mode's trade, team roam's trade or commit). */
const BORROWED: Record<string, (this: void, bot: Unit) => boolean> = {
    attack: (bot) => CoreTrade.Running(bot),
    team_roam: (bot) => {
        const p = LaneFight.CurrentPhase(bot);
        return p === "trade" || p === "commit";
    },
};

/** OHA's modes that run their own desire beside the lane base (the inventory's admitted rows); each is a job-group activity. */
const ADMITTED_AT_BASE: Record<string, true> = { ward: true, rune: true };

/** Human interface and our own retreat: run their own code whatever the pick (retreat's desire is ours, Retreat.Desire). */
const ALWAYS: Record<string, true> = { retreat: true, assemble: true, assemble_with_humans: true };

/**
 * The drive's rule for `mode` against pick `p`, before OHA's code runs: a number replaces the mode's desire, undefined runs
 * the mode's own code (then After). `farmHost` is the chooser's host desire (a job may start from the lane base).
 * - always: retreat (ours), assemble, assemble_with_humans; the retreat pick keeps only these.
 * - the pick's host runs (farm: the chooser's host desire, its own code for an older-path camp job).
 * - laning under a trade pick and attack under any lane pick run (laneAndTrade).
 * - borrowed attack and team roam run below a group-5 pick, kept by After only while our fight read wants them.
 * - farm below a group-6 pick: a chooser job may start, OHA's farm desire is denied.
 * - admitted ward and rune beside the lane base.
 * - everything else 0: laning when not the host, roam, defend, push, roshan, outpost and the shops.
 */
export function DriveDecide(_bot: Unit, mode: string, p: Candidate, farmHost: (this: void) => number | undefined): number | undefined {
    if (ALWAYS[mode] === true) return undefined;
    if (p.name === "retreat") return 0;
    if (mode === p.host) return mode === "farm" ? farmHost() : undefined;
    if (mode === "laning" && p.name === "trade") return undefined;
    if (mode === "attack" && p.name === "lane") return undefined;
    if (BORROWED[mode] !== undefined) return p.group > 5 ? undefined : 0;
    if (mode === "farm") return p.group > 6 ? farmHost() ?? 0 : 0;
    if (ADMITTED_AT_BASE[mode] === true && p.group >= BASE_GROUP) return undefined;
    return 0;
}

/**
 * After OHA's code for `mode` returned `desire` under the drive: the lane host's desire replaces laning's, and a borrowed
 * fight mode that is not the pick's host keeps its desire only while our fight read wants it (the read is asked after the
 * mode's own GetDesire, which opens a trade or a fight).
 */
export function DriveAfter(bot: Unit, mode: string, p: Candidate, desire: any): any {
    if (mode === "laning" && p.name === "lane") return type(desire) === "number" && desire > SETTINGS.LaneDesire ? desire : SETTINGS.LaneDesire;
    if (mode === "laning" && laneAndTrade(p)) return desire;
    const borrowed = BORROWED[mode];
    if (borrowed !== undefined && mode !== p.host) return borrowed(bot) ? desire : 0;
    return desire;
}

/** ability_item_usage's "go complete items" TP to the fountain is denied for a hero the drive holds (user 13/11/2026). */
export function DeniesItemsTp(bot: Unit): boolean {
    return Drives(bot);
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
    // Under the drive the line names the pick the gate enforces.
    const picked = Drives(bot) ? Drive(bot, jobName) : Pick(cands, l?.pick) ?? cands[cands.length - 1];
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
