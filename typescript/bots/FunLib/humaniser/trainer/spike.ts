/**
 * Throwaway probe for the Phase 0 spike: what the bot API reports for a human hero, and whether
 * the countdown bar and DebugDrawText are visible and smooth. Reached only through "!trainer spike" with Debug on.
 */
import { Unit, UnitType } from "bots/ts_libs/dota";
import * as HDebug from "bots/FunLib/humaniser/debug";
import * as Settings from "bots/FunLib/humaniser/trainer/settings";
import { GetTrainerHelpers, T } from "bots/FunLib/humaniser/trainer/api";
import { Bars } from "bots/FunLib/humaniser/trainer/draw";
import { Prediction } from "bots/FunLib/humaniser/trainer/predict";

const LOG_INTERVAL = 0.5;
const LOOP_SECONDS = 2.5;
const MOCK_LEAD = 1.5;
const MOCK_WINDOW = 0.4;
const NEAR_CREEP = 900;

let lastLogAt = -math.huge;
let lastCallAt: number | undefined;

function read(fn: () => any): string {
    const [ok, value] = pcall(fn);
    return ok ? tostring(value) : `ERR(${tostring(value)})`;
}

function nearestCreep(subject: Unit): Unit | undefined {
    let best: Unit | undefined;
    let bestDist = NEAR_CREEP;
    for (const creep of GetUnitList(UnitType.EnemyCreeps)) {
        if (creep === null || creep === undefined || !creep.IsAlive()) continue;
        const d = GetUnitToUnitDistance(subject, creep);
        if (d <= bestDist) {
            best = creep;
            bestDist = d;
        }
    }
    return best;
}

/** A mock countdown on a loop: 1.5 s of lead, then a 0.4 s window, then 0.6 s after it closes. */
function drawBars(subject: Unit, creep: Unit, now: number): void {
    const loopStart = now - (now % LOOP_SECONDS);
    const open = loopStart + MOCK_LEAD;
    const mock = { creep, isDeny: false, uncertain: false, startOpen: open, startClose: open + MOCK_WINDOW } as Prediction;
    Bars(subject, [mock], now);
}

function logReadings(subject: Unit, target: Unit | null | undefined, gap: number): void {
    const s = T(subject);
    const parts = [
        `target=${target !== null && target !== undefined ? target.GetUnitName() : "-"}`,
        `lastAttack=${read(() => s.GetLastAttackTime())}`,
        `anim=${read(() => s.GetAnimActivity())}`,
        `cycle=${read(() => s.GetAnimCycle())}`,
        `point=${read(() => s.GetAttackPoint())}`,
        `as=${read(() => s.GetAttackSpeed())}`,
        `spa=${read(() => s.GetSecondsPerAttack())}`,
        `dmg=${read(() => s.GetAttackDamage())}`,
        `lh=${read(() => s.GetLastHits())}`,
        `dn=${read(() => s.GetDenies())}`,
    ];
    const helpers = GetTrainerHelpers();
    if (target !== null && target !== undefined && helpers !== undefined) {
        parts.push(`proDelay=${read(() => helpers.GetAttackProDelayTime(subject, target))}`);
    }
    parts.push(`frameGap=${string.format("%.3f", gap)}`);
    HDebug.Log("trainer", "spike", ...parts);
}

export function SpikeTick(_bot: Unit, subject: Unit): void {
    const now = GameTime();
    const gap = lastCallAt === undefined ? 0 : now - lastCallAt;
    lastCallAt = now;

    if (now - lastLogAt >= LOG_INTERVAL) {
        lastLogAt = now;
        logReadings(subject, subject.GetAttackTarget(), gap);
    }

    const creep = nearestCreep(subject);
    if (creep !== undefined) drawBars(subject, creep, now);

    const cfg = Settings.Get();
    DebugDrawText(cfg.TextX, cfg.TextY, "ASCII - test", 255, 255, 255);
    DebugDrawText(cfg.TextX, cfg.TextY + 14, "unicode – − test", 255, 255, 255);
}
