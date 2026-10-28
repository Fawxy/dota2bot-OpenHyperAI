/**
 * Behaviour states: what a bot is trying to do over the next tens of seconds (lane, pull, stack, ...). Each bot
 * has at most one. Scorers pick it with human commitment rules (stickiness, minimum dwell, jobs held until they
 * end, cooldown after a failed job); an owned state's body runs as a task on its host mode, restarted after
 * interrupts. Unowned states are only chosen and reported (shadow). Knows nothing about any game but the runner.
 */
import { get as getAdapter } from "./adapter";
import * as Tasks from "./runner";
import { TaskFactory } from "./runner";
import { Result, TaskUnit } from "./types";

/** A posture holds while chosen and never ends by itself; a job has a goal and ends ok or with a reason. */
export type StateKind = "posture" | "job";

export interface StateSpec {
    name: string;
    kind: StateKind;
    /** Mode id the body runs under. */
    host: number;
    tier?: string;
    /** Claim floor for the host mode. Default 0: the state only acts when the host's own arbitration picks it. */
    floor?: number;
    /** Seconds away from the host before the task is preempted. Default 3 for postures, 0 for jobs. */
    preemptAfter?: number;
    /** Seconds without a Step before the task is preempted. Default math.huge (the preempt rule bounds it). */
    stallAfter?: number;
    /** Score in [0, 1], or undefined when the state does not apply now. Errors count as undefined. */
    score(this: void, bot: TaskUnit): number | undefined;
    body: TaskFactory;
    /** Passed to the task: a returned string ends it `interrupted` with that message (e.g. a job's safety checks). */
    guard?: (this: void) => string | undefined;
    /** Called once per task end (any reason, including preempts that the layer restarts), after the layer's own. */
    onEnd?: (this: void, result: Result, info: { label?: string; steps: number }) => void;
}

export interface StatesConfig {
    /** Seconds between selections. */
    interval: number;
    /** Bonus the current state gets over rivals. */
    sticky: number;
    /** Seconds a posture is held before another posture may take over. */
    minDwell: number;
    /** Raw score a rival needs to break a running owned job. */
    jobBreak: number;
    /** Seconds a failed job cannot be chosen again. */
    cooldown: number;
    /** Seconds after a task ended before it is restarted outside its host mode (or after an error). */
    restart: number;
}

const config: StatesConfig = { interval: 0.25, sticky: 0.1, minDwell: 3, jobBreak: 0.9, cooldown: 5, restart: 1 };

export function configure(c: Partial<StatesConfig>): void {
    for (const [k, v] of pairs(c)) (config as any)[k] = v;
}

interface LastEnd {
    at: number;
    reason: Result["reason"];
}

interface BotStates {
    specs: StateSpec[];
    current?: StateSpec;
    since: number;
    score?: number;
    owned: boolean;
    lastSelect?: number;
    forceSelect: boolean;
    cooldownUntil: Record<string, number | undefined>;
    lastEnd?: LastEnd;
    jobEnded: boolean;
    cancelling: boolean;
    starts: number;
}

const bots: Record<number, BotStates | undefined> = {};
let ownedFn: (this: void, bot: TaskUnit, state: string) => boolean = () => false;

/** Which states the SDK runs for which bot; read at every selection, so it may change during the game. */
export function SetOwned(fn: (this: void, bot: TaskUnit, state: string) => boolean): void {
    ownedFn = fn;
}

function taskName(spec: StateSpec): string {
    return "state:" + spec.name;
}

function emit(name: string, fields: [string, unknown][]): void {
    const a = getAdapter();
    if (a === undefined) return;
    if (a.event !== undefined) {
        a.event(name, fields);
        return;
    }
    const parts = ["ev=" + name];
    for (const [k, v] of fields) if (v !== undefined) parts.push(k + "=" + tostring(v));
    a.log("states", parts.join(" "));
}

/** Registers (or replaces) a bot's states. The current state is kept if a spec of that name remains. */
export function define(bot: TaskUnit, specs: StateSpec[]): void {
    const id = bot.GetPlayerID();
    const s = bots[id];
    if (s === undefined) {
        bots[id] = { specs, since: 0, owned: false, forceSelect: true, cooldownUntil: {}, jobEnded: false, cancelling: false, starts: 0 };
        return;
    }
    s.specs = specs;
    if (s.current !== undefined) {
        const name = s.current.name;
        s.current = specs.find((sp) => sp.name === name);
    }
}

export function Forget(bot: TaskUnit): void {
    const s = bots[bot.GetPlayerID()];
    if (s === undefined) return;
    cancelOurs(bot, s, "forgotten");
    bots[bot.GetPlayerID()] = undefined;
}

function ours(bot: TaskUnit, s: BotStates): boolean {
    const t = Tasks.Current(bot);
    return t !== undefined && s.current !== undefined && t.name === taskName(s.current);
}

// The flag is set before Cancel so the onEnd it triggers knows the end was deliberate.
function cancelOurs(bot: TaskUnit, s: BotStates, message: string): void {
    if (!ours(bot, s)) return;
    s.cancelling = true;
    Tasks.Cancel(bot, "cancelled", message);
    s.cancelling = false;
}

type Prior = (this: void, bot: TaskUnit, state: string, raw: number) => number | undefined;
let priorFn: Prior | undefined;

/**
 * A prior on every raw score (e.g. `Phase.Prior()`), applied before stickiness and the job-break check; undefined
 * from it makes the state not applicable. A failing prior is logged and the raw score used. Nil removes it.
 */
export function SetPrior(fn: Prior | undefined): void {
    priorFn = fn;
}

function scoreOf(bot: TaskUnit, spec: StateSpec): number | undefined {
    const [ok, v] = pcall(() => spec.score(bot));
    if (!ok) {
        getAdapter()?.log("states", "score " + spec.name + " error: " + tostring(v));
        return undefined;
    }
    const prior = priorFn;
    if (v === undefined || prior === undefined) return v;
    const [pok, pv] = pcall(() => prior(bot, spec.name, v));
    if (pok) return pv;
    getAdapter()?.log("states", "prior " + spec.name + " error: " + tostring(pv));
    return v;
}

function jobActive(s: BotStates): boolean {
    return s.current !== undefined && s.current.kind === "job" && s.owned && !s.jobEnded;
}

function change(bot: TaskUnit, s: BotStates, next: StateSpec | undefined, score: number | undefined, why: string, now: number): void {
    const prev = s.current;
    cancelOurs(bot, s, "state:" + (next?.name ?? "none"));
    s.current = next;
    s.since = now;
    s.score = score;
    s.owned = next !== undefined && ownedFn(bot, next.name);
    s.jobEnded = false;
    s.lastEnd = undefined;
    emit("state", [
        ["pid", bot.GetPlayerID()],
        ["from", prev?.name ?? "none"],
        ["to", next?.name ?? "none"],
        ["score", score],
        ["owned", s.owned],
        ["why", why],
    ]);
}

function select(bot: TaskUnit, s: BotStates, now: number): void {
    s.lastSelect = now;
    s.forceSelect = false;
    const cur = s.current;
    let best: StateSpec | undefined;
    let bestRaw: number | undefined;
    let bestEff = -Infinity;
    let curRaw: number | undefined;
    for (const spec of s.specs) {
        if ((s.cooldownUntil[spec.name] ?? -Infinity) > now) continue;
        if (spec === cur && s.jobEnded) continue;
        const raw = scoreOf(bot, spec);
        if (raw === undefined) continue;
        if (spec === cur) curRaw = raw;
        const eff = spec === cur ? raw + config.sticky : raw;
        if (eff > bestEff) {
            bestEff = eff;
            best = spec;
            bestRaw = raw;
        }
    }

    if (cur !== undefined && best !== cur) {
        if (jobActive(s)) {
            // A job withdrawn by its scorer while its task is not running (preempted, dead) has nothing left to resume.
            if (curRaw === undefined && !ours(bot, s)) {
                change(bot, s, best, bestRaw, "n/a", now);
                return;
            }
            if (best === undefined || bestRaw! < config.jobBreak) return;
            change(bot, s, best, bestRaw, "break", now);
            return;
        }
        const dwelling = cur.kind === "posture" && curRaw !== undefined && now - s.since < config.minDwell;
        if (dwelling && best !== undefined && best.kind === "posture") return;
        const why = s.jobEnded ? "ended" : curRaw === undefined ? "n/a" : "best";
        change(bot, s, best, bestRaw, why, now);
        return;
    }
    if (cur === undefined) {
        if (best !== undefined) change(bot, s, best, bestRaw, "start", now);
        return;
    }

    s.score = curRaw;
    const owned = ownedFn(bot, cur.name);
    if (owned !== s.owned) {
        if (!owned) cancelOurs(bot, s, "disowned");
        s.owned = owned;
        emit("state", [
            ["pid", bot.GetPlayerID()],
            ["from", cur.name],
            ["to", cur.name],
            ["score", curRaw],
            ["owned", owned],
            ["why", owned ? "own" : "disown"],
        ]);
    }
}

function ended(bot: TaskUnit, s: BotStates, spec: StateSpec, r: Result, info: { label?: string; steps: number }): void {
    emit("state_task", [
        ["pid", bot.GetPlayerID()],
        ["state", spec.name],
        ["result", r.success ? "ok" : "fail"],
        ["reason", r.reason],
        ["msg", r.message],
        ["label", info.label],
        ["steps", info.steps],
    ]);
    if (s.cancelling || s.current !== spec) return;
    const now = getAdapter()!.now();
    s.lastEnd = { at: now, reason: r.reason };
    if (spec.kind === "job" && r.reason !== "preempted" && r.reason !== "dead") {
        s.jobEnded = true;
        s.forceSelect = true;
        if (!r.success) s.cooldownUntil[spec.name] = now + config.cooldown;
    }
}

function maybeStart(bot: TaskUnit, s: BotStates, now: number): void {
    const spec = s.current;
    if (spec === undefined || !s.owned || s.jobEnded || !bot.IsAlive()) return;
    if (Tasks.Current(bot) !== undefined) return;
    const last = s.lastEnd;
    if (last !== undefined) {
        const waited = now - last.at >= config.restart;
        const inHost = bot.GetActiveMode() === spec.host;
        const quickOk = last.reason === "preempted" || last.reason === "dead";
        const canPull = (spec.floor ?? 0) > 0;
        if (!((inHost && (quickOk || waited)) || (waited && canPull))) return;
    }
    const started = Tasks.task(
        bot,
        {
            name: taskName(spec),
            host: spec.host,
            tier: spec.tier,
            floor: spec.floor ?? 0,
            preemptAfter: spec.preemptAfter ?? (spec.kind === "posture" ? 3 : 0),
            stallAfter: spec.stallAfter ?? math.huge,
            guard: spec.guard,
            onEnd: (r, info) => {
                ended(bot, s, spec, r, info);
                spec.onEnd?.(r, info);
            },
        },
        spec.body,
    );
    if (!started) return;
    s.starts += 1;
    emit("state_start", [
        ["pid", bot.GetPlayerID()],
        ["state", spec.name],
        ["n", s.starts],
        ["gap", last !== undefined ? now - last.at : undefined],
        ["after", last?.reason],
    ]);
}

/** Every frame from the host's global tick, before the runner's Tick. Selects at `interval`, starts and restarts. */
export function Tick(bot: TaskUnit): void {
    const a = getAdapter();
    const s = bots[bot.GetPlayerID()];
    if (a === undefined || s === undefined || !a.enabled()) return;
    const now = a.now();
    if (s.forceSelect || s.lastSelect === undefined || now - s.lastSelect >= config.interval) select(bot, s, now);
    maybeStart(bot, s, now);
}

/** From the host mode's Think(): steps the current owned state's task when it runs on `host`; false otherwise. */
export function Step(bot: TaskUnit, host: number): boolean {
    const s = bots[bot.GetPlayerID()];
    if (s === undefined || s.current === undefined || !s.owned || s.current.host !== host || !ours(bot, s)) return false;
    return Tasks.Step(bot, host);
}

export function Current(
    bot: TaskUnit,
): { name: string; kind: StateKind; host: number; since: number; score?: number; owned: boolean; running: boolean; starts: number } | undefined {
    const s = bots[bot.GetPlayerID()];
    if (s === undefined || s.current === undefined) return undefined;
    const c = s.current;
    return { name: c.name, kind: c.kind, host: c.host, since: s.since, score: s.score, owned: s.owned, running: ours(bot, s), starts: s.starts };
}
