/**
 * Whether a core could clear a neutral camp by right-clicks and keep ArriveHP: the clear model of the deleted core camp trip
 * (core_camp.ts, bot repo tag pre-lane-body-cut), kept for its one live reader, the stack job's pos5 double gate
 * (StackJob DoubleNeedsCarry). The trip's learned pace and HP rate are gone with it: no trip runs, so they stayed at their
 * start (1) and the price is the model's own.
 */
import { DamageType, Unit, UnitType, Vector } from "bots/ts_libs/dota";
import * as Camps from "bots/FunLib/humaniser/camps";

export const SETTINGS = {
    /** Neutrals this far from the box centre are the camp's. */
    CampRadius: 700,
    /** The clear's HP cost as a fraction of max HP at HPRefLevel, times HPLevelStep per level above it (within HPLevelScale),
     *  plus StackedClearMul per stack: the price of a camp never seen. Fitted on the trip's banked clears (core_camp.ts). */
    ClearHP: { small: 0.12, medium: 0.2, large: 0.35, ancient: 0.6 } as Record<string, number>,
    HPRefLevel: 6,
    HPLevelStep: 0.8,
    HPLevelScale: [0.6, 3.2] as [number, number],
    StackedClearMul: 0.8,
    ArriveHP: 0.4,
    /** Seconds between kills (retarget and walk), and the seconds per attack assumed when the API gives none (`judgement`). */
    SwitchSec: 0.6,
    DefaultSPA: 1.7,
};

type Attacker = Unit & { GetSecondsPerAttack?(): number };

/** One neutral: HP, the share of a physical hit it takes after armour, its attack damage and seconds per attack. */
interface Neutral {
    hp: number;
    take: number;
    dmg: number;
    spa: number;
    /** At full HP when read. */
    full: boolean;
}

/** Each camp's neutrals as last seen untouched, by team then camp. */
const lastSeen: Record<number, Record<number, Neutral[]>> = {};

export function ResetCache(): void {
    for (const [k] of pairs(lastSeen)) delete lastSeen[k as number];
}

function clamp(v: number, r: number[]): number {
    return math.max(r[0], math.min(r[1], v));
}

function dist(a: Vector, b: Vector): number {
    return math.sqrt((a.x - b.x) ** 2 + (a.y - b.y) ** 2);
}

function spaOf(u: Unit): number {
    const spa = (u as Attacker).GetSecondsPerAttack?.();
    return spa !== undefined && spa > 0 ? spa : SETTINGS.DefaultSPA;
}

function priorClearHP(type: Camps.CampType, level: number, stacks: number): number {
    const s = SETTINGS;
    const scale = clamp(s.HPLevelStep ** (level - s.HPRefLevel), s.HPLevelScale);
    return (s.ClearHP[type] ?? s.ClearHP.medium) * scale * (1 + s.StackedClearMul * stacks);
}

/**
 * The fraction of its max HP `bot` loses clearing `camp`. The neutrals die one at a time in the order that loses the least HP
 * (most damage a second per second of kill time first); each hits until it dies; SwitchSec between kills; the core's regen
 * offsets the loss. Spells and cleave are not in it.
 */
function clearHP(bot: Unit, camp: Neutral[]): number {
    const hit = bot.GetAttackDamage() / spaOf(bot);
    const foes: { kill: number; dps: number }[] = [];
    for (const n of camp) {
        foes.push({
            kill: n.hp / math.max(hit * n.take, 1) + SETTINGS.SwitchSec,
            dps: bot.GetActualIncomingDamage(n.dmg, DamageType.Physical) / math.max(n.spa, 0.1),
        });
    }
    foes.sort((a, b) => b.dps / b.kill - a.dps / a.kill);
    let t = 0;
    let taken = 0;
    for (const f of foes) {
        t += f.kill;
        taken += f.dps * t;
    }
    return math.max(0, taken - bot.GetHealthRegen() * t) / math.max(bot.GetMaxHealth(), 1);
}

/**
 * The camp's live neutrals (the API returns none in fog). Kept as its make-up only when untouched (every one at full HP),
 * and never replaced by fewer: a read of a half-cleared or half-seen camp would price it at what is left.
 */
function liveNeutrals(team: number, idx: number, center: Vector): Neutral[] {
    const live: Neutral[] = [];
    let untouched = true;
    for (const u of GetUnitList(UnitType.NeutralCreeps) ?? []) {
        if (u === null || u === undefined || !u.IsAlive()) continue;
        const at = u.GetLocation();
        if (at === null || at === undefined || dist(at, center) > SETTINGS.CampRadius) continue;
        const full = u.GetHealth() >= u.GetMaxHealth();
        live.push({ hp: u.GetHealth(), take: u.GetActualIncomingDamage(100, DamageType.Physical) / 100, dmg: u.GetAttackDamage(), spa: spaOf(u), full });
        if (!full) untouched = false;
    }
    const old = lastSeen[team]?.[idx];
    if (live.length > 0 && untouched && (old === undefined || live.length >= old.length)) {
        lastSeen[team] = lastSeen[team] ?? {};
        lastSeen[team][idx] = live;
    }
    return live;
}

/** The clear's HP fraction: from the live neutrals, else the last untouched sighting scaled by `stacks`, else the type's table. */
function clearPrice(bot: Unit, spawner: Camps.Spawner, stacks: number): number {
    const live = liveNeutrals(bot.GetTeam(), spawner.idx, Camps.BoxCenter(spawner));
    const seen = lastSeen[bot.GetTeam()]?.[spawner.idx];
    // Fewer neutrals than its untouched make-up, all at full HP, is a half-seen camp, not a smaller one.
    const partial = seen !== undefined && live.length < seen.length && live.every((n) => n.full);
    if (live.length > 0 && !partial) return clearHP(bot, live);
    if (seen !== undefined) return clearHP(bot, seen) * (1 + SETTINGS.StackedClearMul * stacks);
    return priorClearHP(spawner.type, bot.GetLevel(), stacks);
}

/** Whether `core` could clear camp `idx` holding `stacks` stacks and keep ArriveHP of its max HP from full. */
export function CanClear(core: Unit, idx: number, stacks: number): boolean {
    const spawner = Camps.SpawnerByIdx(idx);
    if (spawner === undefined) return false;
    return 1 - clearPrice(core, spawner, stacks) >= SETTINGS.ArriveHP;
}
