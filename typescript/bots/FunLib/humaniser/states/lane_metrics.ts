/**
 * Per-bot laning metrics the hlog analyser cannot derive from snapshots (request H3): HP lost to hero damage.
 * A frame's HP drop counts as hero damage when only heroes damaged the bot recently, half when creeps or a
 * tower did too (attribution in the bot API is by source type only, not by amount).
 */
import { Unit } from "bots/ts_libs/dota";

interface Track {
    hp: number;
    heroLost: number;
    at: number;
}
const tracks: Record<number, Track | undefined> = {};
/** Seconds back the damage source is looked up; widened at high timescales where frames are further apart. */
const WINDOW = 0.3;

export function Tick(bot: Unit): void {
    const pid = bot.GetPlayerID();
    const hp = bot.GetHealth();
    const now = DotaTime();
    let t = tracks[pid];
    if (t === undefined) {
        t = { hp, heroLost: 0, at: now };
        tracks[pid] = t;
        return;
    }
    const drop = t.hp - hp;
    const w = math.min(2, math.max(WINDOW, 1.5 * (now - t.at)));
    t.hp = hp;
    t.at = now;
    if (drop <= 0 || !bot.IsAlive() || !bot.WasRecentlyDamagedByAnyHero(w)) return;
    const mixed = bot.WasRecentlyDamagedByCreep(w) || bot.WasRecentlyDamagedByTower(w);
    t.heroLost += mixed ? drop / 2 : drop;
}

/** HP lost to heroes so far this game. */
export function HeroLost(bot: Unit): number {
    return math.floor(tracks[bot.GetPlayerID()]?.heroLost ?? 0);
}
