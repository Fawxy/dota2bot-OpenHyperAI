/**
 * Lane controller, slice 2a (design `docs/proposals/2026-11-06-lane-controller.md` s5.1-s5.3, s5.1c; slice file
 * `docs/team/slices/lane-controller.md`): once per wave per team and lane, one reading of where the clash will sit against the
 * lane's target point, the mode from the ruleset R1-R6, the wave intent, the levers that could close the gap with each one's
 * predicted effect, and the set it would choose. Shadow only: nothing reads the decision yet (slice 2b wires the levers to
 * it), so this module changes no bot action. One `ev=lane_ctl kind=wave` line per decision and one `kind=chk` line Horizon s
 * later with the clash then, which scores the prediction (hlog view `lane_ctl`).
 *
 * The pull's effect is the fight model's (lane_push WaveGoneFrom: this wave gone) against the plain forecast, scaled by
 * PullScale: on 17 banked games (138 diverted pulls) the unscaled model overshoots the move by about 1.6x at 30-45 s after
 * the slot; scaled by 0.61 it had the lowest error of every arm at +30 and +45 s (median 788 and 761 against 1,014-2,020 for
 * no change, a fixed size and the raw model; `docs/proposals/lane-forecast/pulleffect.js`).
 */
import { Lane, Team, Unit, UnitType, Vector } from "bots/ts_libs/dota";
import * as LaneConfig from "bots/FunLib/humaniser/lane_config";
import * as LanePush from "bots/FunLib/humaniser/lane_push";
import { LanePath } from "bots/FunLib/humaniser/lane_push_data";
import * as Ours from "bots/FunLib/humaniser/ours";
import * as RuneJob from "bots/FunLib/humaniser/rune_job";
import * as StackJob from "bots/FunLib/humaniser/stack_job";
import * as Telemetry from "bots/FunLib/humaniser/telemetry";

declare function RealTime(this: void): number;

export type Mode = "safe" | "shove";
export type Intent = "back" | "hold" | "forward" | "reset";

/** All `judgement` unless marked. */
export const SETTINGS = {
    /** Second of the 30 s wave cycle the decision is read at (our wave has just spawned, before any pull slot). */
    ReadAt: 2,
    From: 60,
    Until: 720,
    /** The prediction's horizon: the next meeting after this wave's pull (scored offline at slot + 30..45 s). */
    Horizon: 45,
    /** `need` within Band of the target is `hold` (PullJob WantPast, so the shadow intent asks for a pull where today's
     *  trigger does). */
    Band: 150,
    /** pulleffect.js least-squares k for diverted pulls at slot + 30 and + 45 s (0.61, 0.64; 17 games). */
    PullScale: 0.6,
    /** Fixed lever sizes, along the lane towards our T1 (EC-078 gives the direction only; slice 2b measures them). */
    PreDenySize: 300,
    FeedSize: 300,
    /** A hero within this of the clash point counts in lane. */
    InLane: 2000,
    /** R2: a support departure (a rune trip or a stack) leaving within this many seconds makes this wave the reset wave;
     *  a departure leaves DepartLead s before its event second. */
    DepartWithin: 60,
    DepartLead: 25,
    /** R6: the core below this HP share, or this many enemy heroes within CoreThreatR of it with no support in lane. */
    CoreLowHp: 0.4,
    CoreThreat: 2,
    CoreThreatR: 1200,
    /** R5: their laners are the enemy heroes seen within EnemyLaneR of the clash in the last EnemyMemory s; all of them dead
     *  or seen farther than EnemyAway from it. */
    EnemyLaneR: 2500,
    EnemyMemory: 90,
    EnemyAway: 3000,
    /** `shove` targets their T1's range edge: this far short of their T1 along the lane. */
    TowerRange: 700,
};

export interface Lever {
    name: string;
    /** Predicted change of the clash at the horizon, along the lane from our side (negative: towards our T1). */
    effect: number;
    /** Order of danger, least first. */
    danger: number;
    who: string;
    /** Why it cannot be used, undefined when it can. */
    why?: string;
}

export interface Choice {
    levers: Lever[];
    /** The chosen set leaves the clash this far past the target (positive: towards their T1). */
    left: number;
    /** No set reached the band without overshooting it. */
    short: boolean;
}

/** Levers that cannot be taken together (a pull resets our wave, a shove spends it). */
function clash(a: Lever, b: Lever): boolean {
    return (a.name === "pull" && b.name === "shove") || (a.name === "shove" && b.name === "pull");
}

/**
 * The fewest, then least dangerous, usable levers whose summed effect takes `need` (the clash past the target) into
 * [-band, band]; when none does, the set that comes nearest without passing -band (design s5.3, user 06/11/2026). Up to
 * three levers; an empty set when `need` is already inside the band.
 */
export function Choose(need: number, band: number, levers: Lever[]): Choice {
    if (math.abs(need) <= band) return { levers: [], left: need, short: false };
    const ok = levers.filter((l) => l.why === undefined && (need > 0 ? l.effect < 0 : l.effect > 0));
    let best: Choice | undefined;
    let bestKey: [number, number, number] | undefined;
    const sets: Lever[][] = [];
    const grow = (from: number, set: Lever[]) => {
        for (let i = from; i < ok.length; i++) {
            const next = [...set, ok[i]];
            sets.push(next);
            if (next.length < 3) grow(i + 1, next);
        }
    };
    grow(0, []);
    for (const set of sets) {
        let bad = false;
        for (let i = 0; i < set.length && !bad; i++) for (let j = i + 1; j < set.length; j++) if (clash(set[i], set[j])) bad = true;
        if (bad) continue;
        let left = need;
        let danger = 0;
        for (const l of set) {
            left += l.effect;
            danger += l.danger;
        }
        const over = need > 0 ? left < -band : left > band;
        if (over) continue;
        const inside = math.abs(left) <= band;
        // inside first, then fewer levers, then less danger; outside, nearer the band first
        const key: [number, number, number] = inside ? [0, set.length, danger] : [1, math.abs(left), danger];
        if (bestKey === undefined || key[0] < bestKey[0] || (key[0] === bestKey[0] && (key[1] < bestKey[1] || (key[1] === bestKey[1] && key[2] < bestKey[2])))) {
            bestKey = key;
            best = { levers: set, left, short: !inside };
        }
    }
    return best ?? { levers: [], left: need, short: true };
}

export function IntentOf(need: number, band: number, reset: boolean): Intent {
    if (reset && need > -band) return "reset";
    return need > band ? "back" : need < -band ? "forward" : "hold";
}

// ------------------------------------------------------------------------------------------------- the game's view

interface Laner {
    unit: Unit;
    pid: number;
    pos: number;
    bot: boolean;
    present: boolean;
}

interface LaneMemory {
    /** Enemy pid -> last second it was seen near the clash. */
    enemies: Record<number, number>;
    wave?: number;
    /** Decided waves whose check is still to log, oldest first. */
    chks: number[];
}

const memory: Record<string, LaneMemory> = {};

export function ResetCache(): void {
    for (const k in memory) delete memory[k];
}

function memoryOf(team: number, lane: Lane): LaneMemory {
    const key = `${team}:${lane}`;
    let m = memory[key];
    if (m === undefined) {
        m = { enemies: {}, chks: [] };
        memory[key] = m;
    }
    return m;
}

function dist(a: Vector, x: number, y: number): number {
    return math.sqrt((a.x - x) ** 2 + (a.y - y) ** 2);
}

/** The calling script's team's heroes assigned to `lane` (GetTeamMember, not GetTeamPlayers: practice mode). */
function lanersOf(lane: Lane, cx: number, cy: number): Laner[] {
    const out: Laner[] = [];
    for (let i = 1; i <= 5; i++) {
        const u = GetTeamMember(i);
        if (u === undefined || u === null || u.IsNull() || u.GetAssignedLane() !== lane) continue;
        const pos = LaneConfig.PositionOf(u) ?? 0;
        out.push({ unit: u, pid: u.GetPlayerID(), pos, bot: u.IsBot(), present: u.IsAlive() && dist(u.GetLocation(), cx, cy) <= SETTINGS.InLane });
    }
    return out;
}

/** Seconds until the support's next departure (rune trip or stack slot) leaves, or undefined with none in reach. */
export function NextDeparture(pos: number, now: number): number | undefined {
    let best: number | undefined;
    const consider = (eventAt: number) => {
        const leave = eventAt - SETTINGS.DepartLead;
        if (leave >= now && (best === undefined || leave - now < best)) best = leave - now;
    };
    for (const [, at] of RuneJob.SETTINGS.Trips[pos] ?? []) consider(at);
    if (pos === 4 || pos === 5) for (const m of StackJob.Minutes()) consider(m * 60 + 52);
    return best;
}

/** R5: their laners are known: every enemy hero seen near the lane lately is dead or seen far from the clash. */
function enemiesAway(m: LaneMemory, now: number, cx: number, cy: number): boolean {
    const visible: Record<number, Unit> = {};
    for (const e of GetUnitList(UnitType.EnemyHeroes) ?? []) {
        if (e === null || e === undefined || e.IsIllusion() || !e.CanBeSeen()) continue;
        visible[e.GetPlayerID()] = e;
        if (dist(e.GetLocation(), cx, cy) <= SETTINGS.EnemyLaneR) m.enemies[e.GetPlayerID()] = now;
    }
    let any = false;
    for (const k in m.enemies) {
        const pid = tonumber(k)!;
        if (now - m.enemies[pid] > SETTINGS.EnemyMemory) {
            delete m.enemies[pid];
            continue;
        }
        any = true;
        if (!IsHeroAlive(pid)) continue;
        const e = visible[pid];
        if (e === undefined || dist(e.GetLocation(), cx, cy) <= SETTINGS.EnemyAway) return false;
    }
    return any;
}

function coreThreat(core: Laner, supportIn: boolean): boolean {
    const u = core.unit;
    if (u.GetHealth() / math.max(1, u.GetMaxHealth()) < SETTINGS.CoreLowHp) return true;
    if (supportIn) return false;
    const near = u.GetNearbyHeroes(SETTINGS.CoreThreatR, true, 0) ?? [];
    return near.length >= SETTINGS.CoreThreat;
}

function ownAt(samples: LanePush.Sample[] | undefined, path: LanePath | undefined, team: number, t: number): number | undefined {
    if (samples === undefined || path === undefined) return undefined;
    const c = LanePush.ClashAt(samples, t);
    if (c === undefined) return undefined;
    const [t1, dir] = LanePush.OwnT1(path, team);
    return dir * (c - t1);
}

function round(x: number | undefined): number | undefined {
    return x === undefined ? undefined : math.floor(x + 0.5);
}

function decide(team: number, lane: Lane, now: number, m: LaneMemory): void {
    const clock = (RealTime as unknown) !== undefined ? RealTime : undefined;
    const started = clock?.();
    const s = SETTINGS;
    const path = LanePush.PathOf(lane);
    const r = LanePush.Read(team, lane);
    if (path === undefined || r === undefined) {
        Telemetry.Event("lane_ctl", [["team", team], ["lane", lane], ["kind", "wave"], ["why", r === undefined ? "no_read" : "no_path"]]);
        return;
    }
    const [cx, cy] = LanePush.PointAt(path, r.clash);
    const laners = lanersOf(lane, cx, cy);
    const cores = laners.filter((l) => l.pos >= 1 && l.pos <= 3);
    const sups = laners.filter((l) => l.pos >= 4);
    const coreIn = cores.find((l) => l.present);
    const supIn = sups.find((l) => l.present);
    const supBot = sups.find((l) => l.present && l.bot);
    const dep = supIn !== undefined ? NextDeparture(supIn.pos, now) : undefined;
    // The ruleset (design s5.1), most binding first.
    let rule = "R1";
    let mode: Mode = "safe";
    const away = enemiesAway(m, now, cx, cy);
    if (coreIn !== undefined && coreThreat(coreIn, supIn !== undefined)) rule = "R6";
    else if (away && (coreIn !== undefined || supIn !== undefined)) {
        rule = "R5";
        mode = "shove";
    } else if (supIn !== undefined && dep !== undefined && dep <= s.DepartWithin) rule = "R2";
    else if (coreIn !== undefined && supIn === undefined) rule = "R3";
    // R4 (a core alone with a use for the time) needs the camp trip's shove-then-camp price, not built yet (ROADMAP Core next
    // gold): never chosen in slice 2a.
    const [ourT1, dir] = LanePush.OwnT1(path, team);
    const theirT1 = path.towers.find((tw) => tw.team !== team)!.s;
    const span = dir * (theirT1 - ourT1);
    const tgt = mode === "shove" ? span - s.TowerRange : LanePush.TargetOf(lane);
    // The plain forecast and the lane with this wave pulled, both to the horizon.
    const at = math.floor(now) + s.Horizon;
    const [samples] = LanePush.Forecast(team, lane, s.Horizon + 3);
    const plain = ownAt(samples, path, team, at);
    const ts = math.floor(now / 30) * 30;
    const gone = LanePush.WaveGoneNow(team, lane, ts, at);
    const need = r.own + r.move - tgt;
    const base = plain ?? r.own + r.move;
    const n45 = base - tgt;
    const intent = IntentOf(n45, s.Band, rule === "R2");
    const pe = gone?.own !== undefined && plain !== undefined ? s.PullScale * (gone.own - plain) : undefined;
    const levers: Lever[] = [];
    const anyIn = coreIn !== undefined || supIn !== undefined;
    levers.push({ name: "predeny", effect: -s.PreDenySize, danger: 1, who: coreIn !== undefined && supIn !== undefined ? "both" : coreIn !== undefined ? "core" : "sup", why: !anyIn ? "nobody" : !Ours.On("PreDeny") ? "off" : undefined });
    levers.push({ name: "feed", effect: -s.FeedSize, danger: 2, who: coreIn !== undefined ? "core" : "sup", why: !anyIn ? "nobody" : undefined });
    levers.push({
        name: "pull",
        effect: pe ?? 0,
        danger: 3,
        who: supBot !== undefined ? `${supBot.pid}` : "",
        why: supBot === undefined ? "no_sup" : rule === "R6" ? "r6" : pe === undefined ? "no_clash" : gone !== undefined && gone.pw === 0 ? "no_wave" : undefined,
    });
    levers.push({ name: "shove", effect: s.PreDenySize, danger: 2, who: coreIn !== undefined ? "core" : "sup", why: mode !== "shove" ? "mode" : !anyIn ? "nobody" : undefined });
    // The reset wave (R2) brings the clash back to the target before the support leaves; already inside the band, a
    // pre-deny alone (design s5.5 rule 1). `forward` takes a lever only under `shove`; otherwise the wave is let go.
    let c: Choice;
    if (intent === "reset" && math.abs(n45) <= s.Band) {
        const pd = levers[0];
        c = pd.why === undefined ? { levers: [pd], left: n45 + pd.effect, short: false } : { levers: [], left: n45, short: true };
    } else if (intent === "back" || intent === "reset" || (intent === "forward" && mode === "shove")) c = Choose(n45, s.Band, levers);
    else c = { levers: [], left: n45, short: false };
    const left = c.left;
    // The core's hold catches a pull that would leave the next clash under our tower (design s5.3: a pull and the hold go
    // together).
    const chosen = c.levers.map((l) => l.name);
    const who = c.levers.map((l) => l.who);
    let after = tgt + left;
    if (chosen.includes("pull") && after < s.TowerRange && coreIn !== undefined) {
        chosen.push("hold");
        who.push(`${coreIn.pid}`);
        after = math.max(after, s.TowerRange);
    }
    const rej: string[] = [];
    for (const l of levers) if (l.why !== undefined) rej.push(`${l.name}:${l.why}`);
    const ms = started !== undefined ? math.floor((clock!() - started) * 10000 + 0.5) / 10 : undefined;
    m.chks.push(ts);
    Telemetry.Event("lane_ctl", [
        ["team", team],
        ["lane", lane],
        ["kind", "wave"],
        ["wave", ts],
        ["mode", mode],
        ["rule", rule],
        ["tgt", round(tgt)],
        ["own", round(r.own)],
        ["mv", round(r.move)],
        ["st", r.state],
        ["need", round(need)],
        ["m45", round(plain)],
        ["p45", round(gone?.own)],
        ["pe", round(pe)],
        ["n45", round(n45)],
        ["intent", intent],
        ["lever", chosen.length > 0 ? chosen.join("+") : "none"],
        ["who", who.join("+")],
        ["left", round(after - tgt)],
        ["short", c.short ? true : undefined],
        ["rej", rej.join(";")],
        ["core", coreIn !== undefined ? coreIn.pid : undefined],
        ["sup", supIn !== undefined ? supIn.pid : undefined],
        ["dep", round(dep)],
        ["away", away ? true : undefined],
        ["ms", ms],
    ]);
}

function check(team: number, lane: Lane, wave: number): void {
    const r = LanePush.Read(team, lane);
    Telemetry.Event("lane_ctl", [
        ["team", team],
        ["lane", lane],
        ["kind", "chk"],
        ["wave", wave],
        ["own", round(r?.own)],
        ["mv", round(r?.move)],
        ["st", r?.state],
    ]);
}

/**
 * Called every frame by every hero of the team: the first call in a lane's read second decides that lane's wave (each lane the
 * team has a hero assigned to), and the first call Horizon s after a decision logs its check.
 */
export function Tick(bot: Unit): void {
    if (!Ours.On("LaneControl")) return;
    const now = DotaTime();
    const s = SETTINGS;
    if (now < s.From || now > s.Until + s.Horizon) return;
    const team = bot.GetTeam();
    if (team !== Team.Radiant && team !== Team.Dire) return;
    const lane = bot.GetAssignedLane();
    if (lane !== Lane.Top && lane !== Lane.Mid && lane !== Lane.Bot) return;
    const m = memoryOf(team, lane);
    const wave = math.floor(now / 30) * 30;
    while (m.chks.length > 0 && now >= m.chks[0] + s.ReadAt + s.Horizon) check(team, lane, m.chks.shift()!);
    if (now > s.Until || now - wave < s.ReadAt || m.wave === wave) return;
    m.wave = wave;
    decide(team, lane, now, m);
}
