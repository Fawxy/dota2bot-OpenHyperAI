/**
 * Per-bot laning metrics the hlog analyser cannot derive from snapshots (request H3): HP lost to hero damage.
 * A frame's HP drop counts as hero damage when only heroes damaged the bot recently, half when creeps or a
 * tower did too (attribution in the bot API is by source type only, not by amount).
 */
import { Unit } from "bots/ts_libs/dota";

interface Track {
    hp: number;
    heroLost: number;
}
const tracks: Record<number, Track | undefined> = {};
const WINDOW = 0.3;

export function Tick(bot: Unit): void {
    const pid = bot.GetPlayerID();
    const hp = bot.GetHealth();
    let t = tracks[pid];
    if (t === undefined) {
        t = { hp, heroLost: 0 };
        tracks[pid] = t;
        return;
    }
    const drop = t.hp - hp;
    t.hp = hp;
    if (drop <= 0 || !bot.IsAlive() || !bot.WasRecentlyDamagedByAnyHero(WINDOW)) return;
    const mixed = bot.WasRecentlyDamagedByCreep(WINDOW) || bot.WasRecentlyDamagedByTower(WINDOW);
    t.heroLost += mixed ? drop / 2 : drop;
}

/** HP lost to heroes so far this game. */
export function HeroLost(bot: Unit): number {
    return math.floor(tracks[bot.GetPlayerID()]?.heroLost ?? 0);
}
