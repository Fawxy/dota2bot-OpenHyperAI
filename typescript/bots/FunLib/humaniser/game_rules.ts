/**
 * The single source of the game's own timers (rules, not tuning knobs): rune spawns, the lane wave cycle and the neutral
 * camp respawn cycle. No Valve function returns any of them (API searched: GetRuneStatus, GetRuneTimeSinceSeen,
 * GetNeutralSpawners, GetNearbyLaneCreeps, DotaTime), so each is a rule with its source named here. Camp stack/pull seeds
 * are fitted per camp and stay in `camps_data`; tuning knobs stay in `lane_config`. Imports nothing.
 */
export type RuneKind = "power" | "water" | "bounty" | "wisdom";

// Checked against the Valve datafeed (patchnoteslist and patchnotes for 7.41 through 7.41f, latest 7.41f, 15/09/2026):
// no spawn-timing changes since 7.41, so these are the 7.41f rules. Bounty every 240 s since 7.38 (datafeed 7.38).
export const RUNE_RULES: Record<RuneKind, { first: number; every: number; last?: number }> = {
    power: { first: 360, every: 120 },
    water: { first: 120, every: 120, last: 240 },
    bounty: { first: 0, every: 240 },
    wisdom: { first: 420, every: 420 },
};

/**
 * Lane creep waves spawn every 30 s. Long-standing rule: the datafeed patch notes 7.38 to 7.41f record no change to wave or
 * neutral spawn timing (scan 08/11/2026), but they carry no base value either, so the 30 s is not read from the feed.
 */
export const WAVE_EVERY = 30;

/** Neutral camps first spawn at 1:00 game time, then refill every minute (Liquipedia "Neutral Creeps" page as cited before this module, not re-read 08/11/2026; no patch change 7.38 to 7.41f). */
export const NEUTRAL_FIRST = 60;
export const NEUTRAL_EVERY = 60;
