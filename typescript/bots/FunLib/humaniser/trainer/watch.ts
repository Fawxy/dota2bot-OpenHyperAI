import { Unit } from "bots/ts_libs/dota";
import { Prediction } from "bots/FunLib/humaniser/trainer/predict";
import { CreepObs, Killer } from "bots/FunLib/humaniser/trainer/judge";

const SELECT_RADIUS = 800;
const DEATH_RADIUS = 1200;
const DEATH_HP_FRACTION = 0.3;

export interface Candidate {
    creep: Unit;
    isDeny: boolean;
    prediction?: Prediction;
}

/** Bars go to the subject's attack target, then the creeps whose windows close soonest; the next ones are only watched. */
export function SelectCreeps(subject: Unit, candidates: Candidate[], maxBars: number, maxWatched: number): { bars: Unit[]; watched: Unit[] } {
    const usable: { creep: Unit; close: number; order: number }[] = [];
    for (const c of candidates) {
        if (c.prediction === undefined || !c.creep.IsAlive()) continue;
        if (GetUnitToLocationDistance(subject, c.creep.GetLocation()) > SELECT_RADIUS) continue;
        usable.push({ creep: c.creep, close: c.prediction.startClose, order: usable.length });
    }
    table.sort(usable, (a, b) => (a.close !== b.close ? a.close < b.close : a.order < b.order));

    const target = subject.GetAttackTarget();
    const ranked: Unit[] = [];
    for (const u of usable) if (u.creep === target) ranked.push(u.creep);
    for (const u of usable) if (u.creep !== target) ranked.push(u.creep);

    const bars: Unit[] = [];
    const watched: Unit[] = [];
    for (let i = 0; i < ranked.length; i++) {
        if (i < maxBars) bars.push(ranked[i]);
        else if (i < maxBars + maxWatched) watched.push(ranked[i]);
    }
    return { bars, watched };
}

export interface Counters {
    lastHits: Record<number, number>;
    denies: Record<number, number>;
}

export interface HeroRef {
    pid: number;
    ally: boolean;
    name: string;
}

function Rose(counts: "lastHits" | "denies", pid: number, before: Counters, after: Counters): boolean {
    return (after[counts][pid] ?? 0) > (before[counts][pid] ?? 0);
}

export function Attribute(creep: CreepObs, subjectPid: number, before: Counters, after: Counters, heroes: HeroRef[], towerTargeting: boolean): Killer {
    // Our own creep can only be denied; the enemy's can only be last-hit.
    const counter = creep.isDeny ? "denies" : "lastHits";
    if (Rose(counter, subjectPid, before, after)) return { kind: "subject" };

    for (const h of heroes) {
        if (h.ally && h.pid !== subjectPid && Rose(counter, h.pid, before, after)) return { kind: "ally", name: h.name };
    }
    for (const h of heroes) {
        if (!h.ally && Rose(counter, h.pid, before, after)) return { kind: "enemyHero", name: h.name };
    }
    return towerTargeting ? { kind: "tower" } : { kind: "creep" };
}

/** A creep whose handle went invalid counts as dead only if it was in reach and low enough for one hit; otherwise it left vision. */
export function IsDeathLikely(lastHp: number, maxHp: number, effDmg: number, dist: number): boolean {
    return dist <= DEATH_RADIUS && lastHp <= math.max(effDmg, DEATH_HP_FRACTION * maxHp);
}
