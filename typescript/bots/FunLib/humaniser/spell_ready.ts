/**
 * A hero's estimated damage on a target counting only the spells it can cast now (slice burst-cooldowns, `Ours.BurstReady`).
 *
 * Valve's GetEstimatedDamageToTarget(true, ...) honours cooldown and mana for our own heroes but counts every learned spell
 * of an enemy hero as ready: in probe game probe_cd1 (17/11/2026) the true and false estimates differed in 725 of 3,612 rows
 * for our heroes and in none of 2,616 for enemies. The enemy's ability handle hides its cooldown (remaining -1), but its
 * IsFullyCastable follows the owner's (false in 122 of 122 rows while cooling, true in 606 of 606 ready with mana) and
 * GetSpecialValueFloat reads its values. So each learned spell an enemy cannot cast takes its damage back out of the
 * estimate: the value at its SPELL_DAMAGE key (a per-second value over the window) through the target's
 * GetActualIncomingDamage, as Valve's own figure is (our side's estimate drops by 58 for Breathe Fire's 80, 108 for Lucent
 * Beam's 150). The result never falls under the hero's attack damage over the window. The table holds only spells Valve's
 * estimate is measured to count (tools/spell-damage/coverage.js: it leaves out Meat Hook, Earth Spike, Shadowraze and
 * more), so a spell it lacks, or whose value reads 0 (Battle Hunger in probe_cd8), stays counted: never an under-read.
 */
import { DamageType, Unit } from "bots/ts_libs/dota";
import * as Ours from "bots/FunLib/humaniser/ours";
import * as AbilityClasses from "bots/FunLib/humaniser/ability_classes";
import { SPELL_DAMAGE } from "bots/FunLib/humaniser/spell_damage_data";

const SLOTS = 6;

interface AbilityHandle {
    IsNull(): boolean;
    GetName(): string;
    GetLevel(): number;
    IsHidden(): boolean;
    IsFullyCastable(): boolean;
    GetSpecialValueFloat(key: string): number;
}
type Caster = Unit & { GetSecondsPerAttack?(): number };

interface Spent {
    key: string;
    perSecond: boolean;
    type: number;
    value: number;
}

// The spells each enemy cannot cast, read once per frame: Threat.Read asks per enemy in reach for every place it weighs.
let spentAt = -1;
let spentBy: Record<number, Spent[]> = {};

function spentOf(e: Caster): Spent[] {
    const now = DotaTime();
    if (now !== spentAt) {
        spentAt = now;
        spentBy = {};
    }
    const pid = e.GetPlayerID();
    const cached = spentBy[pid];
    if (cached !== undefined) return cached;
    const list: Spent[] = [];
    spentBy[pid] = list;
    if (e.GetAbilityInSlot === undefined) return list;
    for (let slot = 0; slot < SLOTS; slot++) {
        const a = e.GetAbilityInSlot(slot) as unknown as AbilityHandle | null | undefined;
        if (a === undefined || a === null || a.IsNull()) continue;
        const row = SPELL_DAMAGE[a.GetName()];
        if (row === undefined || a.GetLevel() <= 0 || a.IsHidden() || a.IsFullyCastable()) continue;
        const value = a.GetSpecialValueFloat(row[0]);
        if (type(value) === "number" && value > 0) list.push({ key: row[0], perSecond: row[1], type: row[2], value });
    }
    return list;
}

function attackPart(e: Caster, target: Unit, window: number): number {
    const spa = e.GetSecondsPerAttack?.();
    if (spa === undefined || spa <= 0) return 0;
    return target.GetActualIncomingDamage((e.GetAttackDamage() * window) / spa, DamageType.Physical);
}

/** The damage of `e`'s learned spells it cannot cast now, on `target` over `window`: 0 for a hero of our team (its estimate already counts them). */
export function SpentOn(e: Unit, target: Unit, window: number): number {
    // An illusion shares its hero's player id, the cache key, and casts nothing: its estimate stays Valve's.
    if (e.IsIllusion()) return 0;
    const spent = spentOf(e as Caster);
    if (spent.length === 0 || e.GetTeam() === GetTeam()) return 0;
    let total = 0;
    for (const s of spent) total += target.GetActualIncomingDamage(s.perSecond ? s.value * window : s.value, s.type);
    return total;
}

interface CastHandle extends AbilityHandle {
    GetCastRange(): number;
    GetCastPoint(): number;
    GetBehavior(): number;
    GetAbilityDamage(): number;
    GetDamageType?(): number;
}

/** One damage spell a hero can cast now (ReadySpells). */
export interface ReadySpell {
    name: string;
    /** GetCastRange; for a no-target area spell (cast range 0) its `radius` special value, the reach it hits within. */
    range: number;
    /** GetCastPoint, s. */
    cp: number;
    behavior: number;
    /** The SPELL_DAMAGE key's value (per second for a per-second row), else GetAbilityDamage: before the target's resistances. */
    dmg: number;
    /** The SPELL_DAMAGE row's damage type, else the ability's GetDamageType, else magical. */
    dtype: number;
}

/**
 * The damage spells `bot` can cast now (learned, shown, IsFullyCastable) with what the chase's catch read needs (kill-chances
 * step 3b): cast range, cast point and damage. A spell with no damage over 0 is left out.
 */
export function ReadySpells(bot: Unit): ReadySpell[] {
    const out: ReadySpell[] = [];
    for (let slot = 0; slot < SLOTS; slot++) {
        const a = bot.GetAbilityInSlot(slot) as unknown as CastHandle | null | undefined;
        if (a === undefined || a === null || a.IsNull()) continue;
        if (a.GetLevel() <= 0 || a.IsHidden() || !a.IsFullyCastable()) continue;
        const name = a.GetName();
        const row = SPELL_DAMAGE[name];
        const dmg = row !== undefined ? a.GetSpecialValueFloat(row[0]) : a.GetAbilityDamage();
        if (type(dmg) !== "number" || !(dmg > 0)) continue;
        let range = a.GetCastRange();
        if (!(range > 0)) {
            const r = a.GetSpecialValueFloat("radius");
            range = type(r) === "number" && r > 0 ? r : 0;
        }
        const dt = row !== undefined ? row[2] : a.GetDamageType !== undefined ? a.GetDamageType() : DamageType.Magical;
        out.push({ name, range, cp: a.GetCastPoint(), behavior: a.GetBehavior(), dmg, dtype: dt > 0 ? dt : DamageType.Magical });
    }
    return out;
}

/**
 * Slice chase-log: the damage spells `bot` can cast now (ReadySpells), as `;`-joined records of name,cast range,cast point
 * (s, two places),behaviour bits (GetBehavior),damage. Logged; the catch read reads the same list.
 */
export function ReadyDamage(bot: Unit): string | undefined {
    const out: string[] = [];
    for (const s of ReadySpells(bot)) {
        const cp = math.floor(s.cp * 100 + 0.5) / 100;
        out.push([s.name, math.floor(s.range), cp, s.behavior, math.floor(s.dmg + 0.5)].join(","));
    }
    return out.length > 0 ? out.join(";") : undefined;
}

/** `e`'s GetEstimatedDamageToTarget on `target` over `window` (all damage types, spells it can cast now); with BurstReady off, Valve's figure. */
export function DamageOn(e: Unit, target: Unit, window: number): number {
    const est = e.GetEstimatedDamageToTarget(true, target, window, DamageType.All);
    if (est <= 0 || !Ours.On("BurstReady")) return est;
    const spent = SpentOn(e, target, window);
    if (spent <= 0) return est;
    return math.max(math.min(est, attackPart(e as Caster, target, window)), est - spent);
}

interface ClassHandle extends AbilityHandle {
    IsPassive(): boolean;
    IsUltimate(): boolean;
    GetAbilityDamage(): number;
}

/**
 * Slice cast-read: an ability's class for the cast read: `u` ultimate, `k` key (a hard disable or spell immunity,
 * AbilityClasses), `d` damage (a SPELL_DAMAGE row or GetAbilityDamage over 0), else `o`. Logged only.
 */
function classOf(a: ClassHandle): string {
    if (a.IsUltimate()) return "u";
    if (AbilityClasses.Classify(a.GetName(), false) === "key") return "k";
    if (SPELL_DAMAGE[a.GetName()] !== undefined) return "d";
    const dmg = a.GetAbilityDamage();
    return type(dmg) === "number" && dmg > 0 ? "d" : "o";
}

/** Slice cast-read: the class (as `rdy`) of `bot`'s ability `name`; undefined for an item or a name the hero lacks. */
export function ClassByName(bot: Unit, name: string | undefined): string | undefined {
    if (name === undefined || string.sub(name, 1, 5) === "item_") return undefined;
    const a = bot.GetAbilityByName(name) as unknown as ClassHandle | null | undefined;
    if (a === undefined || a === null || a.IsNull()) return undefined;
    return classOf(a);
}

/**
 * Slice cast-read: the spells `bot` can cast now (learned, shown, not passive, IsFullyCastable) as `;`-joined
 * `name:class`. Abilities only: lane items are left out. Logged only (ev=snap `rdy`).
 */
export function ReadyList(bot: Unit): string | undefined {
    const out: string[] = [];
    for (let slot = 0; slot < SLOTS; slot++) {
        const a = bot.GetAbilityInSlot(slot) as unknown as ClassHandle | null | undefined;
        if (a === undefined || a === null || a.IsNull()) continue;
        if (a.GetLevel() <= 0 || a.IsHidden() || a.IsPassive() || !a.IsFullyCastable()) continue;
        out.push(`${a.GetName()}:${classOf(a)}`);
    }
    return out.length > 0 ? out.join(";") : undefined;
}
