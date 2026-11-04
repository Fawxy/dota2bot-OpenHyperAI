/**
 * Fight readings (slice rune-spawn; shared with row "Core in lane"'s fight combiner, which asked for them as a module of
 * their own, 04/11/2026): plain readings of a place and its heroes from the API, with no judgement in them. Positional,
 * not lane-bound (fight_read's LaneCounts reads the lane snapshot instead).
 */
import { Tower, Unit, UnitType, Vector } from "bots/ts_libs/dota";

const TOWER_IDS = [Tower.Top1, Tower.Top2, Tower.Top3, Tower.Mid1, Tower.Mid2, Tower.Mid3, Tower.Bot1, Tower.Bot2, Tower.Bot3];

const POWER_RUNE_MODIFIERS = [
    "modifier_rune_doubledamage",
    "modifier_rune_haste",
    "modifier_rune_invis",
    "modifier_rune_regen",
    "modifier_rune_arcane",
    "modifier_rune_shield",
];

/** A handle Dota still backs: an enemy hero's goes null once it leaves our vision (rspchk1 t=375: IsAlive on it raised).
 *  Test fakes without IsNull count as backed. */
export function Backed(u: Unit | undefined | null): u is Unit {
    return u !== undefined && u !== null && !((u as any).IsNull !== undefined && u.IsNull());
}

export function Alive(u: Unit | undefined | null): u is Unit {
    return Backed(u) && u.IsAlive();
}

export function Dist(a: Vector, b: Vector): number {
    return math.sqrt((a.x - b.x) ** 2 + (a.y - b.y) ** 2);
}

export function HpFraction(u: Unit): number {
    const max = u.GetMaxHealth();
    return max > 0 ? u.GetHealth() / max : 0;
}

export function ManaFraction(u: Unit): number {
    const max = u.GetMaxMana();
    return max > 0 ? u.GetMana() / max : 1;
}

export function HoldsPowerRune(u: Unit): boolean {
    for (const m of POWER_RUNE_MODIFIERS) if (u.HasModifier(m)) return true;
    return false;
}

/** `team`'s standing towers' locations. */
export function TowerSpots(team: number): Vector[] {
    const out: Vector[] = [];
    for (const id of TOWER_IDS) {
        const tower = GetTower(team, id);
        if (tower !== null && tower !== undefined && tower.IsAlive()) out.push(tower.GetLocation());
    }
    return out;
}

/** Distance from `loc` to `team`'s nearest standing tower (math.huge with none). */
export function TowerDistance(team: number, loc: Vector): number {
    let best = math.huge;
    for (const id of TOWER_IDS) {
        const tower = GetTower(team, id);
        if (tower === null || tower === undefined || !tower.IsAlive()) continue;
        best = math.min(best, Dist(loc, tower.GetLocation()));
    }
    return best;
}

/** Our living heroes (GetTeamMember, not GetTeamPlayers) within `radius` of `at`; `always` are counted wherever they are. */
export function AlliesNear(at: Vector, radius: number, always: Unit[] = []): Unit[] {
    const out: Unit[] = always.filter((u) => Alive(u));
    for (let i = 1; i <= 5; i++) {
        const m = GetTeamMember(i);
        if (Alive(m) && !out.includes(m) && Dist(m.GetLocation(), at) <= radius) out.push(m);
    }
    return out;
}

/** Enemy heroes (no illusions) within `radius` of `at` from the API's enemy list; `always` are counted wherever they are. */
export function EnemiesNear(at: Vector, radius: number, always: Unit[] = []): Unit[] {
    const out: Unit[] = always.filter((u) => Alive(u));
    for (const e of GetUnitList(UnitType.EnemyHeroes)) {
        if (Alive(e) && !e.IsIllusion() && !out.includes(e) && Dist(e.GetLocation(), at) <= radius) out.push(e);
    }
    return out;
}

export function AverageLevel(units: Unit[]): number {
    return units.length > 0 ? units.reduce((a, u) => a + u.GetLevel(), 0) / units.length : 0;
}
