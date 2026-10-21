import { CreepKind } from "bots/FunLib/humaniser/trainer/api";
import { Prediction } from "bots/FunLib/humaniser/trainer/predict";
import { Sec, Signed } from "bots/FunLib/humaniser/trainer/format";

const RESOLVE_AFTER = 2.5;
const MISS_GRACE = 0.3;
const EARLY_WINDOW = 0.2;
const EARLY_DROP_FRACTION = 0.6;
const MIN_EARLY = 0.01;

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

    constructor(readonly easyWindow: number) {}

    Step(s: SubjectObs, creeps: CreepObs[]): JudgeEvent[] {
        const events: JudgeEvent[] = [];
        const byId: Record<string, CreepObs> = {};
        for (const c of creeps) byId[c.id] = c;

        this.resolveOpen(s, byId, events);
        this.trackSwing(s, byId, events);
        this.emitOutcomes(creeps, events);

        this.prevAnim = s.anim;
        this.prevTarget = s.target;
        return events;
    }

    private resolveOpen(s: SubjectObs, byId: Record<string, CreepObs>, events: JudgeEvent[]) {
        const open: Attempt[] = [];
        let lastForCreep: Record<string, Attempt> = {};
        for (const a of this.attempts) lastForCreep[a.creepId] = a;

        for (const a of this.attempts) {
            const c = byId[a.creepId];
            const verdict = c === undefined ? this.forced(s, a) : this.resolve(s, a, c, lastForCreep[a.creepId] === a);
            if (verdict === undefined) {
                open.push(a);
            } else {
                events.push({ type: "verdict", v: verdict });
            }
        }
        this.attempts = open;
    }

    private resolve(s: SubjectObs, a: Attempt, c: CreepObs, isLatest: boolean): Verdict | undefined {
        if (!c.alive) {
            return c.killer === undefined ? this.forced(s, a) : this.resolveDeath(s, a, c.killer, isLatest);
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

    private resolveDeath(s: SubjectObs, a: Attempt, killer: Killer, isLatest: boolean): Verdict {
        const offset = a.swingStart - a.prediction.ideal;
        if (killer.kind === "subject") {
            // An older swing on the same creep landed without killing it.
            if (!isLatest) return this.early(s, a);
            const p = a.prediction;
            if (a.swingStart >= p.startOpen && a.swingStart < p.startClose) {
                return this.verdict("PERFECT", s, a, `perfect (${Signed(offset)}s)`, offset, s.now);
            }
            const early = a.swingStart < p.startOpen;
            const distance = early ? p.startOpen - a.swingStart : a.swingStart - p.startClose;
            return this.verdict("OK", s, a, `got it (window said ${Sec(distance)}s ${early ? "early" : "late"})`, offset, s.now);
        }

        const taker = Taker(killer);
        if (s.now < a.predictedLand) {
            return this.verdict("LATE", s, a, `late by ${Sec(a.predictedLand - s.now)}s - ${taker}`, offset, s.now);
        }
        return this.verdict("MISS", s, a, `missed - ${taker}`);
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
