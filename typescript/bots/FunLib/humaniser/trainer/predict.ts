import { DamageType, Unit } from "bots/ts_libs/dota";
import { GetTrainerHelpers, MainSlotType, T } from "bots/FunLib/humaniser/trainer/api";
import { Hit, Hits } from "bots/FunLib/humaniser/trainer/incoming";

export const STEP = 0.05;
export const HORIZON = 2.0;
const SAMPLES = math.floor(HORIZON / STEP + 0.5) + 1;
const EPSILON = 1e-6;

const SMOOTH_FRAMES = 3;
const HISTORY_SECONDS = 0.5;
const JUMP_AGE = 0.3;
const JUMP_SIZE = 0.15;
const MIN_WINDOW = 0.1;
const SHORT_WINDOW_LEAD = 0.05;

export interface Window {
    open: number;
    close: number;
}

export interface Prediction {
    creep: Unit;
    isDeny: boolean;
    startOpen: number;
    startClose: number;
    ideal: number;
    uncertain: boolean;
    delay: number;
    effDmg: number;
    hp: number;
    curve: number[];
    at: number;
}

/** curve[i] is the creep's HP at i * STEP seconds from now. Hits landing on the same sample merge into one drop. */
export function BuildCurve(hp: number, regen: number, hits: Hit[]): number[] {
    const curve: number[] = [];
    let applied = 0;
    let lost = 0;
    for (let i = 0; i < SAMPLES; i++) {
        const t = i * STEP;
        while (applied < hits.length && hits[applied].at <= t + EPSILON) {
            lost += hits[applied].damage;
            applied++;
        }
        curve.push(hp + regen * t - lost);
    }
    return curve;
}

/** Start times, relative to now, at which the subject's attack lands after the creep is low enough but before anyone else kills it. */
export function KillWindow(curve: number[], effDmg: number, delay: number, startFloor?: number): Window | undefined {
    let tOther = HORIZON + STEP;
    let tLandMin: number | undefined;
    for (let i = 0; i < curve.length; i++) {
        const t = i * STEP;
        if (tLandMin === undefined && curve[i] <= effDmg) tLandMin = t;
        if (curve[i] <= 0) {
            tOther = t;
            break;
        }
    }
    if (tLandMin === undefined || tLandMin >= tOther) return undefined;
    const open = math.max(tLandMin - delay, startFloor ?? -math.huge);
    const close = tOther - delay;
    if (open >= close) return undefined;
    return { open, close };
}

interface Sample {
    t: number;
    open: number;
    close: number;
}

export class Smoother {
    private history: Sample[] = [];

    Push(now: number, open: number, close: number): { open: number; close: number; uncertain: boolean } {
        this.history.push({ t: now, open, close });
        while (this.history.length > 1 && now - this.history[0].t > HISTORY_SECONDS) {
            table.remove(this.history, 1);
        }

        const count = math.min(SMOOTH_FRAMES, this.history.length);
        let openSum = 0;
        let closeSum = 0;
        for (let i = this.history.length - count; i < this.history.length; i++) {
            openSum += this.history[i].open;
            closeSum += this.history[i].close;
        }

        let uncertain = false;
        for (const s of this.history) {
            if (now - s.t >= JUMP_AGE && math.abs(open - s.open) > JUMP_SIZE) uncertain = true;
        }
        return { open: openSum / count, close: closeSum / count, uncertain };
    }
}

export function EffectiveDamage(subject: Unit, creep: Unit, isDeny: boolean): number {
    const unit = T(subject);
    let dmg = unit.GetAttackDamage();
    if (!isDeny && unit.GetItemSlotType(unit.FindItemSlot("item_quelling_blade")) === MainSlotType()) {
        const ranged = unit.GetAttackRange() > 310 || unit.GetUnitName() === "npc_dota_hero_templar_assassin";
        dmg += ranged ? 4 : 8;
    }
    return creep.GetActualIncomingDamage(dmg, DamageType.Physical);
}

function denyFloor(curve: number[], maxHp: number): number | undefined {
    for (let i = 0; i < curve.length; i++) {
        if (curve[i] < maxHp / 2) return i * STEP;
    }
    return undefined;
}

export function Predict(subject: Unit, creep: Unit, isDeny: boolean, now: number, smoother: Smoother): Prediction | undefined {
    const helpers = GetTrainerHelpers();
    if (helpers === undefined) return undefined;

    const hp = creep.GetHealth();
    const curve = BuildCurve(hp, creep.GetHealthRegen(), Hits(creep, subject, HORIZON));
    const effDmg = EffectiveDamage(subject, creep, isDeny);
    const delay = helpers.GetAttackProDelayTime(subject, creep);

    let floor: number | undefined;
    if (isDeny) {
        floor = denyFloor(curve, creep.GetMaxHealth());
        if (floor === undefined) return undefined;
    }

    const window = KillWindow(curve, effDmg, delay, floor);
    if (window === undefined) return undefined;

    const smoothed = smoother.Push(now, now + window.open, now + window.close);
    const ideal =
        smoothed.close - smoothed.open < MIN_WINDOW
            ? smoothed.open + SHORT_WINDOW_LEAD
            : (smoothed.open + smoothed.close) / 2;
    return {
        creep,
        isDeny,
        startOpen: smoothed.open,
        startClose: smoothed.close,
        ideal,
        uncertain: smoothed.uncertain,
        delay,
        effDmg,
        hp,
        curve,
        at: now,
    };
}
