/**
 * Imperfect memory of enemy cooldowns (task 11). Each observer remembers only some casts it saw, with an error on
 * the cooldown length, and forgets an estimate over a window once it should have expired. Pure model: all times are
 * passed in as `now`; the only engine call is RandomFloat.
 */
import * as LaneFightConfig from "bots/FunLib/humaniser/lane_fight_config";

export interface Entry {
    seenAt: number;
    estReadyAt: number;
    cls: "ult" | "key" | "other";
    shared: boolean;
    // Deadline after which the entry no longer counts as remembered; fixed at record time from the observer's skill.
    forgetAt: number;
}

const memory: Record<number, Record<number, Record<string, Entry>>> = {};

function roll(chance: number): boolean {
    return RandomFloat(0, 1) < chance;
}

function rememberChance(cls: Entry["cls"], skill: number): number {
    if (cls === "ult") return LaneFightConfig.Curve("RememberUlt", skill);
    if (cls === "key") return LaneFightConfig.Curve("RememberKey", skill);
    return LaneFightConfig.Curve("RememberOther", skill);
}

function store(observerPid: number, enemyPid: number, ability: string, entry: Entry): void {
    if (memory[observerPid] === undefined) memory[observerPid] = {};
    if (memory[observerPid][enemyPid] === undefined) memory[observerPid][enemyPid] = {};
    memory[observerPid][enemyPid][ability] = entry;
}

function find(observerPid: number, enemyPid: number, ability: string): Entry | undefined {
    const byEnemy = memory[observerPid];
    if (byEnemy === undefined) return undefined;
    const byAbility = byEnemy[enemyPid];
    return byAbility === undefined ? undefined : byAbility[ability];
}

export function Record(
    observerPid: number,
    enemyPid: number,
    ability: string,
    cls: Entry["cls"],
    cooldown: number,
    skill: number,
    now: number,
): boolean {
    if (!roll(rememberChance(cls, skill))) {
        const byEnemy = memory[observerPid];
        if (byEnemy !== undefined && byEnemy[enemyPid] !== undefined) byEnemy[enemyPid][ability] = undefined as any;
        return false;
    }
    const x = LaneFightConfig.Curve("TimingError", skill);
    const estReadyAt = now + cooldown * (1 + RandomFloat(-x, x));
    store(observerPid, enemyPid, ability, {
        seenAt: now,
        estReadyAt,
        cls,
        shared: false,
        forgetAt: estReadyAt + LaneFightConfig.Curve("ForgetWindow", skill),
    });
    return true;
}

export function Share(fromPid: number, toPids: number[], enemyPid: number, ability: string, skill: number): void {
    const entry = find(fromPid, enemyPid, ability);
    if (entry === undefined) return;
    const loss = LaneFightConfig.Curve("ShareLoss", skill);
    for (const pid of toPids) {
        if (pid === fromPid) continue;
        const existing = find(pid, enemyPid, ability);
        if (existing !== undefined && existing.seenAt >= entry.seenAt) continue;
        if (roll(loss)) continue;
        store(pid, enemyPid, ability, {
            seenAt: entry.seenAt,
            estReadyAt: entry.estReadyAt,
            cls: entry.cls,
            shared: true,
            forgetAt: entry.estReadyAt + LaneFightConfig.Curve("ForgetWindow", skill),
        });
    }
}

export function ProbablyReady(
    observerPid: number,
    enemyPid: number,
    ability: string,
    learned: boolean,
    now: number,
    _skill: number,
): LuaMultiReturn<[boolean, number]> {
    if (!learned) return $multi(false, 1);
    const entry = find(observerPid, enemyPid, ability);
    if (entry === undefined) return $multi(true, 0);
    if (now < entry.estReadyAt) return $multi(false, 1);
    const window = entry.forgetAt - entry.estReadyAt;
    const confidence = window > 0 ? math.max(0, 1 - (now - entry.estReadyAt) / window) : 0;
    return $multi(true, confidence);
}

export function KeyThreatsDown(
    observerPid: number,
    enemyPid: number,
    keyAbilities: string[],
    now: number,
    skill: number,
): number {
    if (keyAbilities.length === 0) return 0;
    let down = 0;
    for (const ability of keyAbilities) {
        const [ready] = ProbablyReady(observerPid, enemyPid, ability, true, now, skill);
        if (!ready) down++;
    }
    return down / keyAbilities.length;
}

export function Count(observerPid: number, now: number): number {
    const byEnemy = memory[observerPid];
    if (byEnemy === undefined) return 0;
    let n = 0;
    for (const [, byAbility] of pairs(byEnemy)) {
        for (const [, entry] of pairs(byAbility)) {
            if (now < entry.forgetAt) n++;
        }
    }
    return n;
}

export function Reset(): void {
    for (const [k] of pairs(memory)) memory[k as number] = undefined as any;
}
