/**
 * Hero job chooser (slice job-chooser, design docs/proposals/2026-11-02-job-chooser-design.md): whether a job may start or
 * must stop, which mode hosts it, and every contact with OHA. OHA's files call only this module, never a job; a job says
 * when it wants to run, how it does the work and when it is finished.
 * Jobs: StackJob, RuneJob (slice rune-rotation), PullJob (slice support-lane), PullFarm (slice support-pull-farm) and CoreCamp (slice core-next-gold), ranked per hero by priority; a running job is never interrupted by another.
 */
import { BotMode, Unit } from "bots/ts_libs/dota";
import * as Ours from "bots/FunLib/humaniser/ours";
import * as Overrides from "bots/FunLib/humaniser/overrides";
import * as CoreCamp from "bots/FunLib/humaniser/core_camp";
import * as PullFarm from "bots/FunLib/humaniser/pull_farm";
import * as PullJob from "bots/FunLib/humaniser/pull_job";
import * as RuneJob from "bots/FunLib/humaniser/rune_job";
import * as StackJob from "bots/FunLib/humaniser/stack_job";
import * as Drill from "bots/FunLib/humaniser/drill";
import * as Arbiter from "bots/FunLib/humaniser/arbiter";

// All judgement; values moved unchanged from StackJob.
export const SETTINGS = {
    /** Above OHA's ward (0.83) and laning, below a serious retreat (0.94-1.1); s4 validation game. */
    JobDesire: 0.92,
    /** A drill's idle-statue cast with no job (BOT_MODE_DESIRE_ABSOLUTE x 1.2, the bench's in mode_farm_generic). */
    BenchDesire: 1.2,
    MinHpFraction: 0.5,
    /** Lane opponents stand 450-1,200 from a laning pos5 (s4 validation game): only one in reach blocks the start. */
    EnemyRadius: 600,
    HitWithin: 3,
};

/** The mode that hosts a running job. */
export const HOST = "farm";
export const HOST_MODE = BotMode.Farm;

/**
 * OHA's modes that may still take the hero during a job: mode name (the file's, without `mode_` and `_generic`) to what
 * removes the entry. Designed to end up empty. Names, not BOT_MODE numbers: BotMode has no assemble-with-humans entry, and
 * a name cannot be nil. Attack: only the 9 heroes OHA overrides have a wrapped attack mode.
 */
export const EXCEPTIONS: Record<string, string> = {
    // With Ours.Retreat on, our retreat owns a laning hero's retreat and ends a running job itself (slice retreat); the entry
    // stays for heroes it does not own.
    retreat: "our own retreat after laning",
    assemble: "our own human interface",
    assemble_with_humans: "our own human interface",
    attack: "our own fights, or a Valve fix",
};

/** One job the chooser hosts: when it wants the hero, how it steps, how it ends. */
interface Job {
    name: string;
    /** Rank against the hero's other jobs; undefined when the job never applies to it. */
    Priority(this: void, bot: Unit): number | undefined;
    /** Running, or a trigger still open: lower-ranked jobs do not start. */
    Claims(this: void, bot: Unit): boolean;
    Wants(this: void, bot: Unit, blocked: (bot: Unit) => string | undefined, host: number): boolean;
    Running(this: void, bot: Unit): boolean;
    Step(this: void, bot: Unit, host: number): boolean;
    End(this: void, bot: Unit, why: string): void;
    NoteHit(this: void, bot: Unit): void;
    NoteIdleHeld(this: void, bot: Unit): void;
}

const STACK: Job = {
    name: "stack",
    Priority: (bot) => (StackJob.Applies(bot) ? SETTINGS.JobDesire : undefined),
    Claims: (bot) => StackJob.Pending(bot),
    Wants: (bot, blocked, host) => StackJob.Wants(bot, blocked, host),
    Running: (bot) => StackJob.Running(bot),
    Step: (bot, host) => StackJob.Step(bot, host),
    End: (bot, why) => StackJob.End(bot, why),
    NoteHit: (bot) => StackJob.NoteHit(bot),
    NoteIdleHeld: (bot) => StackJob.NoteIdleHeld(bot),
};

const RUNE: Job = {
    name: "rune",
    Priority: (bot) => RuneJob.Priority(bot),
    Claims: (bot) => RuneJob.Claims(bot),
    Wants: (bot, blocked, host) => RuneJob.Wants(bot, blocked, host),
    Running: (bot) => RuneJob.Running(bot),
    Step: (bot, host) => RuneJob.Step(bot, host),
    End: (bot, why) => RuneJob.End(bot, why),
    NoteHit: (bot) => RuneJob.NoteHit(bot),
    NoteIdleHeld: (bot) => RuneJob.NoteIdleHeld(bot),
};

const PULL: Job = {
    name: "pull",
    Priority: (bot) => PullJob.Priority(bot),
    Claims: (bot) => PullJob.Claims(bot),
    Wants: (bot, blocked, host) => PullJob.Wants(bot, blocked, host),
    Running: (bot) => PullJob.Running(bot),
    Step: (bot, host) => PullJob.Step(bot, host),
    End: (bot, why) => PullJob.End(bot, why),
    NoteHit: (bot) => PullJob.NoteHit(bot),
    NoteIdleHeld: (bot) => PullJob.NoteIdleHeld(bot),
};

const CAMP: Job = {
    name: "camp",
    Priority: (bot) => CoreCamp.Priority(bot),
    Claims: (bot) => CoreCamp.Claims(bot),
    Wants: (bot, blocked, host) => CoreCamp.Wants(bot, blocked, host),
    Running: (bot) => CoreCamp.Running(bot),
    Step: (bot, host) => CoreCamp.Step(bot, host),
    End: (bot, why) => CoreCamp.End(bot, why),
    NoteHit: (bot) => CoreCamp.NoteHit(bot),
    NoteIdleHeld: (bot) => CoreCamp.NoteIdleHeld(bot),
};

const PULLFARM: Job = {
    name: "pullfarm",
    Priority: (bot) => PullFarm.Priority(bot),
    Claims: (bot) => PullFarm.Claims(bot),
    Wants: (bot, blocked, host) => PullFarm.Wants(bot, blocked, host),
    Running: (bot) => PullFarm.Running(bot),
    Step: (bot, host) => PullFarm.Step(bot, host),
    End: (bot, why) => PullFarm.End(bot, why),
    NoteHit: (bot) => PullFarm.NoteHit(bot),
    NoteIdleHeld: (bot) => PullFarm.NoteIdleHeld(bot),
};

const JOBS: Job[] = [STACK, RUNE, PULL, PULLFARM, CAMP];

/** The jobs that apply to this hero, highest priority first (a tie keeps JOBS order). */
function ranked(bot: Unit): Job[] {
    const out: [Job, number][] = [];
    // A drill's idle-statue cast runs only its forced job (humaniser/drill.ts ForcedJob).
    const only = Drill.ForcedJob(bot);
    for (const j of JOBS) {
        if (only !== undefined && j.name !== only) continue;
        const p = j.Priority(bot);
        if (p !== undefined) out.push([j, p]);
    }
    for (let i = 1; i < out.length; i++) {
        for (let k = i; k > 0 && out[k][1] > out[k - 1][1]; k--) [out[k], out[k - 1]] = [out[k - 1], out[k]];
    }
    return out.map((e) => e[0]);
}

function runningJob(bot: Unit): Job | undefined {
    for (const j of JOBS) if (j.Running(bot)) return j;
    return undefined;
}

/** The name of the job running for this hero, or undefined (slice retreat reads it as the hero's purpose). */
export function RunningJobName(bot: Unit): string | undefined {
    return runningJob(bot)?.name;
}

/** Any of our jobs runs for this hero. */
export function Running(bot: Unit): boolean {
    return runningJob(bot) !== undefined;
}

/**
 * The host's desire, switch on. Retreat at 0.92 or above wins through Valve's arbitration without help; below that no desire
 * value separates danger from a healthy hero (slice file, "Retreat"), so the job ends when a hero hit it just now and HP is
 * under MinHpFraction. Neutrals alone never count. A benched hero stays with the host file's own bench. Jobs are asked in
 * rank order; a start waits while a higher-ranked job claims the hero (`why=<job>` in the waiting job's skip line).
 */
function hostDesire(bot: Unit): number | undefined {
    if (StackJob.Benched(bot)) return undefined;
    const cur = runningJob(bot);
    if (cur !== undefined) {
        // The waiting jobs still see their triggers, so a trigger that passes during this job is skipped naming it.
        for (const j of ranked(bot)) if (j !== cur) j.Wants(bot, () => cur.name, HOST_MODE);
        if (!cur.Wants(bot, MayStart, HOST_MODE)) return undefined;
        if (hit(bot)) {
            cur.NoteHit(bot);
            if (bot.GetHealth() < bot.GetMaxHealth() * SETTINGS.MinHpFraction) {
                cur.End(bot, "retreat");
                return undefined;
            }
        }
        return SETTINGS.JobDesire;
    }
    const jobs = ranked(bot);
    for (let i = 0; i < jobs.length; i++) {
        const blocked = (b: Unit): string | undefined => {
            const why = MayStart(b);
            if (why !== undefined) return why;
            for (let k = 0; k < i; k++) if (jobs[k].Claims(b)) return jobs[k].name;
            return undefined;
        };
        if (jobs[i].Wants(bot, blocked, HOST_MODE)) return SETTINGS.JobDesire;
    }
    // A drill's idle-statue cast with no job to run stands as a statue: the bench's desire (mode_farm_generic), its step in
    // the host's Think (Bench).
    if (Drill.IdleStatue(bot)) return SETTINGS.BenchDesire;
    return undefined;
}

/** While our retreat's episode runs, only the retreat mode (the hold's host) and the human's order modes, listed here, may hold the hero: OHA's modes post
 *  up to 2.88, and roam's tango branch (1.00) took it five times in 8 s at 10-15% HP with the enemy in reach (rtwatch1). */
const EPISODE_MODES: Record<string, true> = { assemble: true, assemble_with_humans: true };

/** OHA's modes that keep their own desire beside the host's while the arbiter's hold of that name runs. */
const ADMITTED: Record<string, Record<string, unknown>> = { retreat: EPISODE_MODES, job: EXCEPTIONS };

/**
 * A number replaces OHA's desire for `mode`; undefined lets OHA's code run. Under the arbiter's hold the host mode runs
 * and every mode the hold does not admit gets 0. A job hosted in the rune mode (the mid's 6:00 trip) leaves the chooser's
 * host at 0: gating the rune mode handed the mid to the attack mode 9 of 10 trips (rspchk1), and OHA's farm desire must
 * not take it either.
 */
export function Decide(bot: Unit, mode: string): number | undefined {
    const jobs = Ours.On("JobChooser");
    const hold = Arbiter.Hold(bot, jobs ? RunningJobName(bot) : undefined);
    if (hold === undefined) return jobs && mode === HOST ? hostDesire(bot) : undefined;
    if (mode === hold.host) return mode === HOST ? hostDesire(bot) : undefined;
    return ADMITTED[hold.name][mode] !== undefined ? undefined : 0;
}

/** Wraps a mode file's GetDesire. 0, never nil: nil falls through to Valve's built-in desire for that mode. */
export function Gate(bot: Unit, mode: string, inner: () => any): () => any {
    return () => {
        Arbiter.Shadow(bot, () => runningJob(bot)?.name);
        const v = Decide(bot, mode);
        return v !== undefined ? v : inner();
    };
}

/**
 * Wraps the host file's Think, switch on: the job steps without entering OHA's code, so its defend-ping and run aborts cannot
 * fire. No step while the bot cannot act, as OHA's Think does first: StackJob's StallAfter depends on that skip.
 */
export function HostThink(bot: Unit, mode: string, inner: () => any, cannotAct: (bot: Unit) => boolean): () => any {
    return () => {
        if (mode !== HOST || !Ours.On("JobChooser") || StackJob.Benched(bot)) return inner();
        if (cannotAct(bot)) return undefined;
        return (runningJob(bot) ?? STACK).Step(bot, HOST_MODE) ? undefined : inner();
    };
}

/** Hero damage just now, checked every frame of a running job (1x probe s4p7: the pos5 was hit at 61% on the walk, kept
 *  going and died at the camp to two heroes). Not an enemy hero in reach: lane opponents walk within 600 of a laning pos5,
 *  and that check ended 4 jobs 1-6 s after their start (probe s4p8). Not HP or mode: the camp's neutrals hit the bot by
 *  design, and the mode is ours. */
function hit(bot: Unit): boolean {
    return bot.WasRecentlyDamagedByAnyHero(SETTINGS.HitWithin);
}

/** Why the hero may not leave now (the lane is under attack), else undefined: low HP, an enemy hero in reach, hit by a
 *  hero just now, or fighting or retreating. */
export function MayStart(bot: Unit): string | undefined {
    if (bot.GetHealth() < bot.GetMaxHealth() * SETTINGS.MinHpFraction) return "low-hp";
    if ((bot.GetNearbyHeroes(SETTINGS.EnemyRadius, true, BotMode.None) ?? []).length > 0) return "enemy-near";
    if (hit(bot)) return "hit";
    const mode = bot.GetActiveMode();
    if (mode === BotMode.Attack || mode === BotMode.Retreat) return "busy";
    return undefined;
}

/** mode_farm_generic GetDesire hook, switch off: the job's desire while it runs or as it starts, else 0 (OHA decides). A hero
 *  hit ends a running job. Switch on, the wrapper has already acted. Goes when the switch is retired. */
export function FarmDesire(bot: Unit): number {
    if (Ours.On("JobChooser") || !StackJob.Wants(bot, MayStart, HOST_MODE)) return 0;
    if (StackJob.Running(bot) && hit(bot)) {
        StackJob.NoteHit(bot);
        StackJob.End(bot, "hit");
        return 0;
    }
    return SETTINGS.JobDesire;
}

/** mode_farm_generic Think hook, switch off: steps the job; false when none runs. Switch on, the wrapper has already acted. */
export function FarmThink(bot: Unit): boolean {
    return !Ours.On("JobChooser") && StackJob.Step(bot, HOST_MODE);
}

/** OHA's farm-mode run (or any host abort) ends the job; its line reports `cancelled:<why>`. */
export function Abort(bot: Unit, why: string): void {
    runningJob(bot)?.End(bot, why);
}

/**
 * mode_farm_generic's ShouldRun: neutrals hitting the hero during its job are not a reason to run; the job's exit is its
 * retreat. OHA's creep clause (level < 5, hit by a creep, HP < 0.7) cancelled 5 of 9 attempts after the hit (probe s4p4).
 */
export function HoldsRun(bot: Unit): boolean {
    return Running(bot);
}

/**
 * ability_item_usage: spells and items wait while the job runs, as camp_jobs' HoldsCasts does for camp jobs. OHA's farm
 * branches cast on the camp: witch doctor's cask landed at :42-:47, before the hit, and once after it, and the stunned
 * neutrals walked back into the box (user replay and s4solo2); a TP scroll on the walk stalled the job (s4solo2 5:4x).
 * An enemy hero in reach lifts it so the bot can fight or save itself. A drill's benched heroes and statues never cast, nor
 * does a lane-only hero (spells on creeps would change the last-hit contest under test); a chaser of an entry with
 * `chaserCasts` does, in a chase rep.
 */
export function HoldsCasts(bot: Unit): boolean {
    if ((StackJob.Benched(bot) && !Drill.Casts(bot)) || Overrides.LaneOnly(bot)) return true;
    if (!Running(bot)) return Drill.IdleStatue(bot);
    return (bot.GetNearbyHeroes(SETTINGS.EnemyRadius, true, BotMode.None) ?? []).length === 0;
}

/**
 * jmz_func CheckBotIdleState (called from team_roam's GetDesire whatever mode is active): a bot in farm mode that moved
 * under 100 in 3 s gets ClearActions and an attack-move to its lane front. A stack job stands still at its stand point by
 * design, and when the check fell inside the 2 s after the hit order it replaced the attack: all 4 slice 4 `no-aggro` misses
 * (attack-move from the order to the miss, s4 A_on_1 5:55 and 7:53, s4r3 C_on_3 7:54, s4x1 A_on_1 5:55). True while the job
 * runs, counted on the attempt, and always for a drill's benched hero or statue (its attack-move would end the statue).
 */
export function HoldsIdle(bot: Unit): boolean {
    // A drill's benched hero waits in its fountain and a statue sways on its spot: both stand still by design.
    if (StackJob.Benched(bot)) return true;
    const cur = runningJob(bot);
    if (cur === undefined) return Drill.IdleStatue(bot);
    cur.NoteIdleHeld(bot);
    return true;
}

/** A drill's benched hero or statue (humaniser/drill.ts) holds farm mode and takes its step there. */
export function Benched(bot: Unit): boolean {
    return StackJob.Benched(bot);
}

export function Bench(bot: Unit): boolean {
    return StackJob.Bench(bot);
}
