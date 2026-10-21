/**
 * Throwaway probe for the Phase 0 spike: what the bot API reports for a human hero, and whether
 * DebugDrawLine/DebugDrawText are visible and smooth. Reached only through "!trainer spike" with Debug on.
 */
import { Unit, UnitType } from "bots/ts_libs/dota";
import * as HDebug from "bots/FunLib/humaniser/debug";
import * as Settings from "bots/FunLib/humaniser/trainer/settings";
import { DrawLine, GetTrainerHelpers, T } from "bots/FunLib/humaniser/trainer/api";

const LOG_INTERVAL = 0.5;
const BAR_WIDTH = 160;
const BAR_HEIGHT_ABOVE = 180;
const TICK_HEIGHT = 16;
const HP_BAR_OFFSET = 40;
const WINDOW_WIDTH = 40;
const LOOP_SECONDS = 2;
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

function hLine(x0: number, x1: number, y: number, z: number, r: number, g: number, b: number): void {
    DrawLine(Vector(x0, y, z), Vector(x1, y, z), r, g, b);
}

function vTick(x: number, y: number, z: number, height: number, r: number, g: number, b: number): void {
    DrawLine(Vector(x, y, z - height / 2), Vector(x, y, z + height / 2), r, g, b);
}

function drawBars(creep: Unit, now: number): void {
    const loc = creep.GetLocation();
    const left = loc.x - BAR_WIDTH / 2;
    const right = loc.x + BAR_WIDTH / 2;
    const z = loc.z + BAR_HEIGHT_ABOVE;
    const phase = (now % LOOP_SECONDS) / LOOP_SECONDS;

    hLine(left, right, loc.y, z, 128, 128, 128);
    vTick(left, loc.y, z, TICK_HEIGHT, 255, 255, 255);
    vTick(right, loc.y, z, TICK_HEIGHT, 128, 128, 128);
    const centre = right - phase * BAR_WIDTH;
    const winLeft = math.max(left, centre - WINDOW_WIDTH / 2);
    const winRight = math.min(right, centre + WINDOW_WIDTH / 2);
    if (winRight > winLeft) {
        hLine(winLeft, winRight, loc.y, z, 0, 255, 0);
        vTick(winLeft, loc.y, z, TICK_HEIGHT, 0, 255, 0);
        vTick(winRight, loc.y, z, TICK_HEIGHT, 0, 255, 0);
    }

    const hpZ = z + HP_BAR_OFFSET;
    hLine(left, right, loc.y, hpZ, 128, 128, 128);
    hLine(left, left + (1 - phase) * BAR_WIDTH, loc.y, hpZ, 0, 255, 0);
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
    if (creep !== undefined) drawBars(creep, now);

    const cfg = Settings.Get();
    DebugDrawText(cfg.TextX, cfg.TextY, "ASCII - test", 255, 255, 255);
    DebugDrawText(cfg.TextX, cfg.TextY + 14, "unicode – − test", 255, 255, 255);
}
