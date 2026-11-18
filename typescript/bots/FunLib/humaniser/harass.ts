/**
 * The enemy last-hit attempt read: which of our creeps an enemy hero is about to kill (fight_read's `lastHit` input).
 */
import { DamageType, Unit, Vector } from "bots/ts_libs/dota";
import * as LaneConfig from "bots/FunLib/humaniser/lane_config";

function dist2D(a: Vector, b: Vector): number {
    const dx = a.x - b.x;
    const dy = a.y - b.y;
    return math.sqrt(dx * dx + dy * dy);
}

export function IsLastHitAttempt(enemy: Unit, ourCreeps: Unit[]): Unit | undefined {
    const h = LaneConfig.Helpers();
    const dmg = enemy.GetAttackDamage();
    const target = enemy.GetAttackTarget();
    if (target !== null && target !== undefined && h.WillKillTarget !== undefined && h.GetAttackProDelayTime !== undefined) {
        for (const creep of ourCreeps ?? []) {
            if (creep === target && creep.IsAlive() && h.WillKillTarget(creep, dmg, DamageType.Physical, h.GetAttackProDelayTime(enemy, creep))) return creep;
        }
    }
    const cfg = LaneConfig.Settings();
    const here = enemy.GetLocation();
    const ahead = enemy.GetExtrapolatedLocation(cfg.Radii.ApproachExtrapolate);
    let best: Unit | undefined;
    let bestDist = math.huge;
    for (const creep of ourCreeps ?? []) {
        if (!creep.IsAlive() || creep.GetHealth() > dmg) continue;
        const loc = creep.GetLocation();
        const d = dist2D(here, loc);
        if (dist2D(ahead, loc) <= d - cfg.Thresholds.ApproachEpsilon && d < bestDist) {
            best = creep;
            bestDist = d;
        }
    }
    return best;
}
