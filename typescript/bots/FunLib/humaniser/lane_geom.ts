/**
 * Lane geometry shared by lane_state and lane_read. No imports from humaniser modules, so telemetry can load lane_read
 * without a require cycle through lane_state (which logs ev=lane_eq through telemetry).
 * Amounts are along the lane in any one frame: EqPos is unchanged by which way the frame runs.
 */

function clamp(v: number, lo: number, hi: number): number {
    return v < lo ? lo : v > hi ? hi : v;
}

export function EqPos(meetAmount: number, ourTower: number, theirTower: number): number {
    const span = theirTower - ourTower;
    if (span === 0) return 0;
    return clamp((2 * (meetAmount - ourTower)) / span - 1, -1, 1);
}

/** A front behind its own side's tower has no wave in lane (it reads that side's base), so the other front is the meet. */
export function MeetAmount(ourFront: number, enemyFront: number, ourTower: number, theirTower: number): number {
    const span = theirTower - ourTower;
    const oursOut = (ourFront - ourTower) * span < 0;
    const theirsOut = (enemyFront - theirTower) * span > 0;
    if (oursOut && !theirsOut) return enemyFront;
    if (theirsOut && !oursOut) return ourFront;
    return (ourFront + enemyFront) / 2;
}
