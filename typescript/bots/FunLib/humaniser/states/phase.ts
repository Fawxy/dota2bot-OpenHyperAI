/**
 * Team game phase (Customize.Humaniser.Phase, team slice 12) on the SDK's `Phase`: OHA builds the snapshot from
 * scoreboard-fair facts (clock, towers, heroes alive and levels, last-seen enemies near our towers, lane fronts),
 * maps PUSH/DEFEND team orders onto phase orders, and logs `ev=phase` on every change. With `Priors` off (the
 * default, shadow) nothing else reads the phase, so behaviour is unchanged. `Priors` on hands `Phase.Prior()` to
 * `States.SetPrior`, multiplying every state score by the team phase's bias. Enable = false: no ticks, no events.
 */
import type * as Lib from "bots/FunLib/sdk/tasks/tasks";
import { Lane, Tower, Unit } from "bots/ts_libs/dota";
import * as Config from "bots/FunLib/humaniser/config";
import * as Orders from "bots/FunLib/humaniser/orders";
import * as Tasks from "bots/FunLib/humaniser/tasks";

export interface PhaseSettings {
    Enable: boolean;
    /** Apply the phase priors to state scores (behaviour change). Off: shadow, log only. */
    Priors: boolean;
    /** Seconds between snapshot builds per team. */
    Interval: number;
    /** An enemy last seen this recently counts as seen / threatening. */
    SeenWindow: number;
    /** An enemy within this of one of our towers threatens it. */
    ThreatRadius: number;
}

export function Settings(): PhaseSettings {
    return Config.Get().Phase as PhaseSettings;
}

export function IsEnabled(): boolean {
    return Config.IsEnabled() && Settings().Enable === true && Tasks.Enabled();
}

const TOWERS: [number, number][] = [
    [Tower.Top1, 1],
    [Tower.Mid1, 1],
    [Tower.Bot1, 1],
    [Tower.Top2, 2],
    [Tower.Mid2, 2],
    [Tower.Bot2, 2],
    [Tower.Top3, 3],
    [Tower.Mid3, 3],
    [Tower.Bot3, 3],
    [Tower.Base1, 4],
    [Tower.Base2, 4],
];

const ORDER_PHASE: Partial<Record<Orders.OrderType, string>> = { PUSH: "push", DEFEND: "defend" };

function enemyOf(team: number): number {
    return team === 2 ? 3 : 2;
}

function alive(u: Unit | null | undefined): u is Unit {
    return u !== undefined && u !== null && u.IsAlive();
}

function towerCount(team: number): Lib.TowerCount {
    const c = { t1: 0, t2: 0, t3: 0 };
    for (const [id, tier] of TOWERS) {
        if (tier > 3 || !alive(GetTower(team, id))) continue;
        if (tier === 1) c.t1 += 1;
        else if (tier === 2) c.t2 += 1;
        else c.t3 += 1;
    }
    return c;
}

function heroes(team: number): { alive: number; level: number } {
    let n = 0;
    let up = 0;
    let levels = 0;
    for (const pid of GetTeamPlayers(team)) {
        n += 1;
        if (IsHeroAlive(pid)) up += 1;
        levels += GetHeroLevel(pid);
    }
    return { alive: up, level: n > 0 ? levels / n : 0 };
}

function dist2(ax: number, ay: number, bx: number, by: number): number {
    const dx = ax - bx;
    const dy = ay - by;
    return dx * dx + dy * dy;
}

/** Enemies seen within SeenWindow, and the most of them near any one of our towers (with that tower's tier). */
function threat(team: number): { seen: number; heroes: number; tier: number } {
    const cfg = Settings();
    const r2 = cfg.ThreatRadius * cfg.ThreatRadius;
    const spots: { x: number; y: number }[] = [];
    for (const pid of GetTeamPlayers(enemyOf(team))) {
        if (!IsHeroAlive(pid)) continue;
        const info = GetHeroLastSeenInfo(pid);
        const last = info !== undefined ? info[0] : undefined;
        if (last === undefined || last.time_since_seen > cfg.SeenWindow) continue;
        spots.push({ x: last.location.x, y: last.location.y });
    }
    let most = 0;
    let tier = 0;
    for (const [id, t] of TOWERS) {
        const tower = GetTower(team, id);
        if (!alive(tower)) continue;
        const loc = tower.GetLocation();
        let n = 0;
        for (const s of spots) if (dist2(s.x, s.y, loc.x, loc.y) <= r2) n += 1;
        if (n > most || (n === most && n > 0 && t > tier)) {
            most = n;
            tier = t;
        }
    }
    return { seen: spots.length, heroes: most, tier };
}

/**
 * The snapshot for `team`. Net worth is left out: enemy net worth is not something a player reads mid-fight, and
 * the push phase works from heroes alive and lane fronts. Waves map GetLaneFrontAmount (0 at our base, 1 at
 * theirs) to -1..+1, so 0 is about the river, not the T1 midpoint the SDK nominally uses.
 */
export function Snapshot(team: number): Lib.PhaseSnapshot {
    const ours = heroes(team);
    const theirs = heroes(enemyOf(team));
    const th = threat(team);
    const waves: number[] = [];
    for (const lane of [Lane.Top, Lane.Mid, Lane.Bot]) waves.push(2 * GetLaneFrontAmount(team, lane, true) - 1);
    return {
        time: DotaTime(),
        towers: { ours: towerCount(team), theirs: towerCount(enemyOf(team)) },
        alive: { ours: ours.alive, theirs: theirs.alive },
        levels: { ours: ours.level, theirs: theirs.level },
        enemiesSeen: th.seen,
        threat: { heroes: th.heroes, tier: th.tier },
        waves,
    };
}

const appliedOrders: Record<number, Record<number, boolean>> = {};

// Every bot posts the same order ids (the bus is deterministic), so applying each id once per team is enough.
function applyOrders(l: NonNullable<ReturnType<typeof Tasks.Loaded>>, team: number): void {
    let seen = appliedOrders[team];
    if (seen === undefined) {
        seen = {};
        appliedOrders[team] = seen;
    }
    for (const o of Orders.GetActive(team)) {
        const phase = ORDER_PHASE[o.type];
        if (phase === undefined || seen[o.id]) continue;
        seen[o.id] = true;
        // expiresAt is on the bus's GameTime clock.
        l.Phase.Order(team, phase, o.expiresAt - GameTime(), `order:${o.type}:${o.id}`);
    }
}

let installed = false;
let priorsOn = false;

function lib(): ReturnType<typeof Tasks.Loaded> {
    const l = Tasks.Loaded();
    if (l === undefined || l.Phase === undefined) return undefined;
    if (!installed) {
        installed = true;
        l.Phase.configure({ interval: Settings().Interval });
    }
    const want = Settings().Priors === true;
    if (want !== priorsOn) {
        priorsOn = want;
        l.States.SetPrior(want ? l.Phase.Prior() : undefined);
    }
    return l;
}

/** Every frame from Humaniser.Tick, before States.Tick; the SDK builds the snapshot at most every Interval. */
export function Tick(bot: Unit): void {
    if (!IsEnabled()) return;
    const l = lib();
    if (l === undefined) return;
    const team = bot.GetTeam();
    applyOrders(l, team);
    l.Phase.Tick(team, () => Snapshot(team));
}

export function Describe(team: number): string | undefined {
    if (!IsEnabled()) return undefined;
    const cur = Tasks.Loaded()?.Phase.Current(team);
    if (cur === undefined) return "-";
    return `${cur.name}${cur.ordered !== undefined ? ` (${cur.ordered})` : ""}${priorsOn ? "" : " shadow"}`;
}
