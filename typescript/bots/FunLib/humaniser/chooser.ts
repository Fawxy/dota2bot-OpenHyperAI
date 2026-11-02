/**
 * Hero job chooser (slice job-chooser, design docs/proposals/2026-11-02-job-chooser-design.md): whether a job may start or
 * must stop, which mode hosts it, and every contact with OHA. OHA's files call only this module, never a job; a job says
 * when it wants to run, how it does the work and when it is finished.
 * CANDIDATE(JobChooser): one job so far (StackJob); rune rotation is the second consumer.
 */
import { BotMode, Unit } from "bots/ts_libs/dota";
import * as Ours from "bots/FunLib/humaniser/ours";
import * as StackJob from "bots/FunLib/humaniser/stack_job";

// All judgement; values moved unchanged from StackJob.
export const SETTINGS = {
    /** Above OHA's ward (0.83) and laning, below a serious retreat (0.94-1.1); s4 validation game. */
    JobDesire: 0.92,
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
    retreat: "our own retreat",
    assemble: "our own human interface",
    assemble_with_humans: "our own human interface",
    attack: "our own fights, or a Valve fix",
};

/**
 * The host's desire, switch on. Retreat at 0.92 or above wins through Valve's arbitration without help; below that no desire
 * value separates danger from a healthy hero (slice file, "Retreat"), so the job ends when a hero hit it just now and HP is
 * under MinHpFraction. Neutrals alone never count. A benched hero stays with the host file's own bench.
 */
function hostDesire(bot: Unit): number | undefined {
    if (StackJob.Benched(bot) || !StackJob.Wants(bot, MayStart, HOST_MODE)) return undefined;
    if (StackJob.Running(bot) && hit(bot)) {
        StackJob.NoteHit(bot);
        if (bot.GetHealth() < bot.GetMaxHealth() * SETTINGS.MinHpFraction) {
            StackJob.End(bot, "retreat");
            return undefined;
        }
    }
    return SETTINGS.JobDesire;
}

/** A number replaces OHA's desire for `mode`; undefined lets OHA's code run. */
export function Decide(bot: Unit, mode: string): number | undefined {
    if (!Ours.On("JobChooser")) return undefined;
    if (mode === HOST) return hostDesire(bot);
    if (!StackJob.Running(bot) || EXCEPTIONS[mode] !== undefined) return undefined;
    return 0;
}

/** Wraps a mode file's GetDesire. 0, never nil: nil falls through to Valve's built-in desire for that mode. */
export function Gate(bot: Unit, mode: string, inner: () => any): () => any {
    return () => {
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
        return StackJob.Step(bot, HOST_MODE) ? undefined : inner();
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
    StackJob.End(bot, why);
}

/**
 * mode_farm_generic's ShouldRun: neutrals hitting the hero during its job are not a reason to run; the job's exit is its
 * retreat. OHA's creep clause (level < 5, hit by a creep, HP < 0.7) cancelled 5 of 9 attempts after the hit (probe s4p4).
 */
export function HoldsRun(bot: Unit): boolean {
    return StackJob.Running(bot);
}

/**
 * ability_item_usage: spells and items wait while the job runs, as camp_jobs' HoldsCasts does for camp jobs. OHA's farm
 * branches cast on the camp: witch doctor's cask landed at :42-:47, before the hit, and once after it, and the stunned
 * neutrals walked back into the box (user replay and s4solo2); a TP scroll on the walk stalled the job (s4solo2 5:4x).
 * An enemy hero in reach lifts it so the bot can fight or save itself. Benched heroes (Overrides.Solo) never cast.
 */
export function HoldsCasts(bot: Unit): boolean {
    if (StackJob.Benched(bot)) return true;
    if (!StackJob.Running(bot)) return false;
    return (bot.GetNearbyHeroes(SETTINGS.EnemyRadius, true, BotMode.None) ?? []).length === 0;
}

/**
 * jmz_func CheckBotIdleState (called from team_roam's GetDesire whatever mode is active): a bot in farm mode that moved
 * under 100 in 3 s gets ClearActions and an attack-move to its lane front. A stack job stands still at its stand point by
 * design, and when the check fell inside the 2 s after the hit order it replaced the attack: all 4 slice 4 `no-aggro` misses
 * (attack-move from the order to the miss, s4 A_on_1 5:55 and 7:53, s4r3 C_on_3 7:54, s4x1 A_on_1 5:55). True while the job
 * runs, counted on the attempt.
 */
export function HoldsIdle(bot: Unit): boolean {
    if (!StackJob.Running(bot)) return false;
    StackJob.NoteIdleHeld(bot);
    return true;
}

/** Overrides.Solo (test harness): a benched hero holds farm mode and sits in its fountain. */
export function Benched(bot: Unit): boolean {
    return StackJob.Benched(bot);
}

export function Bench(bot: Unit): boolean {
    return StackJob.Bench(bot);
}
