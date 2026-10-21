import { CreepKind } from "bots/FunLib/humaniser/trainer/api";
import { Prediction } from "bots/FunLib/humaniser/trainer/predict";
import { Sec, Signed } from "bots/FunLib/humaniser/trainer/format";

const RESOLVE_AFTER = 2.5;
const MISS_GRACE = 0.3;
const EARLY_WINDOW = 0.2;
const EARLY_DROP_FRACTION = 0.6;
const MIN_EARLY = 0.01;
const EASY_RADIUS = 800;
const WIDEST_MEMORY = 2;
const WIDEST_LOOKAHEAD = 2;
const SAME_SWING_SLACK = 0.1;

export interface SubjectObs {
    now: number;
    alive: boolean;
    eligible: boolean;
    harassed: boolean;
    target?: string;
    anim: "swing" | "followthrough" | "none";
    swingStart?: number;
    lastHits: number;
    denies: number;
}

export interface Killer {
    kind: "subject" | "ally" | "enemyHero" | "tower" | "creep";
    name?: string;
}

export interface CreepObs {
    id: string;
    kind: CreepKind;
    isDeny: boolean;
    alive: boolean;
    hp: number;
    dist: number;
    prediction?: Prediction;
    killer?: Killer;
}

export type VerdictKind = "PERFECT" | "OK" | "EARLY" | "LATE" | "CANCELLED" | "MISS" | "MISSED_EASY";

export interface Verdict {
    kind: VerdictKind;
    at: number;
    creepId: string;
    creepKind: CreepKind;
    isDeny: boolean;
    harassed: boolean;
    swung: boolean;
    offset?: number;
    window?: number;
    predictedLand?: number;
    landedAt?: number;
    reason: string;
}

type Closed = Verdict | "silent";

export type JudgeEvent = { type: "verdict"; v: Verdict } | { type: "outcome"; creepId: string; subjectGotIt: boolean };

interface Attempt {
    creepId: string;
    creepKind: CreepKind;
    isDeny: boolean;
    harassed: boolean;
    prediction: Prediction;
    swingStart: number;
    startedAt: number;
    predictedLand: number;
    hp: number;
    /** HP last seen before the early-detection window opens. */
    baselineHp: number;
    swinging: boolean;
}

export class Judge {
    private attempts: Attempt[] = [];
    private attempted: Record<string, boolean> = {};
    private reported: Record<string, boolean> = {};
    private prevAnim: string = "none";
    private prevTarget: string | undefined = undefined;
    private widest: Record<string, { t: number; w: number }[]> = {};
    private handled: Record<string, boolean> = {};

    constructor(readonly easyWindow: number) {}

    Step(s: SubjectObs, creeps: CreepObs[]): JudgeEvent[] {
        const events: JudgeEvent[] = [];
        const byId: Record<string, CreepObs> = {};
        for (const c of creeps) byId[c.id] = c;

        this.recordWindows(s.now, creeps);
        this.resolveOpen(s, byId, events);
        this.detectEasyMisses(s, creeps, events);
        this.trackSwing(s, byId, events);
        this.emitOutcomes(creeps, events);

        this.prevAnim = s.anim;
        this.prevTarget = s.target;
        return events;
    }

    private resolveOpen(s: SubjectObs, byId: Record<string, CreepObs>, events: JudgeEvent[]) {
        const open: Attempt[] = [];
        const group: Record<string, Attempt[]> = {};
        for (const a of this.attempts) {
            if (group[a.creepId] === undefined) group[a.creepId] = [];
            group[a.creepId].push(a);
        }

        for (const a of this.attempts) {
            const c = byId[a.creepId];
            const closed = c === undefined ? this.forced(s, a) : this.resolve(s, a, c, group[a.creepId]);
            if (closed === undefined) {
                open.push(a);
            } else if (closed !== "silent") {
                events.push({ type: "verdict", v: closed });
            }
        }
        this.attempts = open;
    }

    private resolve(s: SubjectObs, a: Attempt, c: CreepObs, onCreep: Attempt[]): Closed | undefined {
        if (!c.alive) {
            return c.killer === undefined ? this.forced(s, a) : this.resolveDeath(s, a, c, c.killer, onCreep);
        }

        const dropWindowStart = a.predictedLand - EARLY_WINDOW;
        if (s.now < dropWindowStart) {
            a.baselineHp = c.hp;
        } else if (s.now <= a.predictedLand + EARLY_WINDOW && a.baselineHp - c.hp >= EARLY_DROP_FRACTION * a.prediction.effDmg) {
            return this.early(s, a);
        }

        if (s.now > a.predictedLand + MISS_GRACE) {
            return this.verdict("MISS", s, a, "missed - evasion/uphill?");
        }
        return this.forced(s, a);
    }

    private forced(s: SubjectObs, a: Attempt): Verdict | undefined {
        if (s.now - a.startedAt < RESOLVE_AFTER) return undefined;
        return this.verdict("MISS", s, a, "missed - no result after 2.5s");
    }

    private early(s: SubjectObs, a: Attempt): Verdict {
        const by = math.max(a.prediction.startOpen - a.swingStart, MIN_EARLY);
        const reason = `early by ${Sec(by)}s - creep had ${Round(a.hp)} HP, you deal ${Round(a.prediction.effDmg)}`;
        return this.verdict("EARLY", s, a, reason, a.swingStart - a.prediction.ideal, s.now);
    }

    private resolveDeath(s: SubjectObs, a: Attempt, c: CreepObs, killer: Killer, onCreep: Attempt[]): Closed {
        if (killer.kind === "subject") {
            const credited = this.creditedAttempt(s, onCreep);
            if (a === credited) return this.credit(s, a);
            // Attempts after the credited one are the same kill seen twice; earlier ones landed without killing.
            return onCreep.indexOf(a) < onCreep.indexOf(credited) ? this.early(s, a) : "silent";
        }

        // One death gets one verdict: only the newest attempt on the creep is graded.
        if (a !== onCreep[onCreep.length - 1]) return "silent";
        const offset = a.swingStart - a.prediction.ideal;
        if (s.now < a.predictedLand) {
            const easy = this.easyMiss(s, c, killer, a);
            if (easy !== undefined) return easy;
            return this.verdict("LATE", s, a, `late by ${Sec(a.predictedLand - s.now)}s - ${Taker(killer)}`, offset, s.now);
        }
        return this.verdict("MISS", s, a, `missed - ${Taker(killer)}`);
    }

    /**
     * A fast ranged attacker can have two swings in flight, and the first one lands the killing blow.
     * The older attempt gets the credit when its projectile was due no more than SAME_SWING_SLACK ago.
     */
    private creditedAttempt(s: SubjectObs, onCreep: Attempt[]): Attempt {
        const latest = onCreep[onCreep.length - 1];
        if (onCreep.length < 2) return latest;
        const older = onCreep[onCreep.length - 2];
        return s.now - older.predictedLand <= SAME_SWING_SLACK ? older : latest;
    }

    private credit(s: SubjectObs, a: Attempt): Verdict {
        const offset = a.swingStart - a.prediction.ideal;
        const p = a.prediction;
        if (a.swingStart >= p.startOpen && a.swingStart < p.startClose) {
            return this.verdict("PERFECT", s, a, `perfect (${Signed(offset)}s)`, offset, s.now);
        }
        const early = a.swingStart < p.startOpen;
        const distance = early ? p.startOpen - a.swingStart : a.swingStart - p.startClose;
        return this.verdict("OK", s, a, `got it (window said ${Sec(distance)}s ${early ? "early" : "late"})`, offset, s.now);
    }

    private recordWindows(now: number, creeps: CreepObs[]) {
        for (const c of creeps) {
            const p = c.prediction;
            if (!c.alive || p === undefined || p.startClose <= now) continue;
            const w = math.min(p.startClose, now + WIDEST_LOOKAHEAD) - math.max(p.startOpen, now);
            if (this.widest[c.id] === undefined) this.widest[c.id] = [];
            this.widest[c.id].push({ t: now, w });
        }
        for (const id of Object.keys(this.widest)) {
            const samples = this.widest[id];
            while (samples.length > 0 && now - samples[0].t > WIDEST_MEMORY) table.remove(samples, 1);
            if (samples.length === 0) delete this.widest[id];
        }
    }

    private widestFor(id: string): number {
        let best = 0;
        for (const sample of this.widest[id] ?? []) best = math.max(best, sample.w);
        return best;
    }

    private detectEasyMisses(s: SubjectObs, creeps: CreepObs[], events: JudgeEvent[]) {
        for (const c of creeps) {
            if (c.alive || c.killer === undefined || this.handled[c.id]) continue;
            this.handled[c.id] = true;
            if (c.killer.kind !== "subject" && !this.attempted[c.id]) {
                const v = this.easyMiss(s, c, c.killer, undefined);
                if (v !== undefined) events.push({ type: "verdict", v });
            }
            delete this.widest[c.id];
        }
    }

    /** `a` is the creep's LATE attempt, or undefined when the subject never swung at it. */
    private easyMiss(s: SubjectObs, c: CreepObs, killer: Killer, a: Attempt | undefined): Verdict | undefined {
        const window = this.widestFor(c.id);
        if (!s.alive || !s.eligible || c.dist > EASY_RADIUS || window < this.easyWindow) return undefined;

        const what = c.isDeny ? "easy deny" : "easy one";
        let reason = `missed ${what} - ${Sec(window)}s window, `;
        reason += a === undefined ? `${c.kind} creep, no swing` : `you were ${Sec(a.predictedLand - s.now)}s late`;
        if (killer.kind === "ally") reason += ` - ${killer.name ?? "an ally"} took it after you passed`;

        const v: Verdict = {
            kind: "MISSED_EASY",
            at: s.now,
            creepId: c.id,
            creepKind: c.kind,
            isDeny: c.isDeny,
            harassed: s.harassed,
            swung: a !== undefined,
            window,
            reason,
        };
        if (a !== undefined) {
            v.offset = a.swingStart - a.prediction.ideal;
            v.predictedLand = a.predictedLand;
            v.landedAt = s.now;
        }
        return v;
    }

    private verdict(kind: VerdictKind, s: SubjectObs, a: Attempt, reason: string, offset?: number, landedAt?: number): Verdict {
        return {
            kind,
            at: s.now,
            creepId: a.creepId,
            creepKind: a.creepKind,
            isDeny: a.isDeny,
            harassed: a.harassed,
            swung: true,
            offset,
            predictedLand: a.predictedLand,
            landedAt,
            reason,
        };
    }

    private trackSwing(s: SubjectObs, byId: Record<string, CreepObs>, events: JudgeEvent[]) {
        const current = this.swingingAttempt();
        const retargeted = s.anim === "swing" && current !== undefined && current.creepId !== s.target;

        if (current !== undefined) {
            if (s.anim === "followthrough") {
                current.swinging = false;
            } else if (s.anim === "none" || retargeted) {
                this.attempts = this.attempts.filter((a) => a !== current);
                events.push({ type: "verdict", v: this.verdict("CANCELLED", s, current, "cancelled swing") });
            }
        }

        const started = s.anim === "swing" && (this.prevAnim !== "swing" || s.target !== this.prevTarget);
        if (!started || s.target === undefined) return;
        const c = byId[s.target];
        if (c === undefined || !c.alive || c.prediction === undefined) return;

        const swingStart = s.swingStart ?? s.now;
        this.attempted[c.id] = true;
        this.attempts.push({
            creepId: c.id,
            creepKind: c.kind,
            isDeny: c.isDeny,
            harassed: s.harassed,
            prediction: c.prediction,
            swingStart,
            startedAt: s.now,
            predictedLand: swingStart + c.prediction.delay,
            hp: c.hp,
            baselineHp: c.hp,
            swinging: true,
        });
    }

    private swingingAttempt(): Attempt | undefined {
        for (let i = this.attempts.length - 1; i >= 0; i--) {
            if (this.attempts[i].swinging) return this.attempts[i];
        }
        return undefined;
    }

    private emitOutcomes(creeps: CreepObs[], events: JudgeEvent[]) {
        for (const c of creeps) {
            if (c.alive || c.killer === undefined || !this.attempted[c.id] || this.reported[c.id]) continue;
            this.reported[c.id] = true;
            events.push({ type: "outcome", creepId: c.id, subjectGotIt: c.killer.kind === "subject" });
        }
    }
}

function Round(x: number): number {
    return math.floor(x + 0.5);
}

function Taker(killer: Killer): string {
    if (killer.kind === "tower") return "tower took it";
    if (killer.kind === "enemyHero") return `denied by ${killer.name ?? "an enemy hero"}`;
    if (killer.kind === "ally") return `${killer.name ?? "an ally"} took it`;
    return "lane creep took it";
}
