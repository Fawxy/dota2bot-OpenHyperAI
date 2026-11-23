/**
 * Fixture cuts (rework step 8, docs/proposals/2026-11-13-rework.md s8): the API state one decision reads, logged in the frame
 * it decides, so a banked moment replays offline. tools/hlog/cut.js turns a line into a fixture world; the decision's driver
 * under tests/humaniser/fixture_drivers/ serves that world back to the real code. One `ev=cut` line per decision sample,
 * `kind` naming the decision; one `ev=cut_towers` line per team the first time it cuts (tower places do not move).
 *
 * `leave` (retreat's LeaveWhy, beside the answer it logs as `dec`): the world of the bot's own place that `SafeGather.At` reads:
 * visible enemy heroes with their damage over the short and long windows, our team's last sighting of each unseen one, towers,
 * our vision around the bot (only while an enemy is unseen) and the lane creeps of both teams near it (on ev=cut_creeps
 * `kind=leave`, the same frame); plus what the rule read past it: the answer's `lv`, `why`, `kill` and `ra`, and a tower's damage
 * on the bot (`dt`). Lists are `;`-joined records of `,`-joined numbers in the order the field's comment gives; a target is `b`
 * (this bot), `h<pid>`, `u<CreepId>` or `-`.
 *
 * `gate` (SafeGather.TripGate: the start gate of a trip, the walk from `fm` to `pl`): the same machinery over a walk instead of the
 * bot's lane. Visible heroes and allies within CUT_R of the walk's box (a hero reaches the walk within the 4 s horizon from
 * 3,000 at most), the unseen heroes, and IsLocationVisible at the walk points Threat reads (`vw`, one bit per point, no grid). Logged
 * beside the gate's own ev=threat line, which is what the replay is compared with. `he`, `hu`, `ha`, `ta` and `b` keep the
 * leave's record formats.
 */
import { DamageType, Team, Tower, Unit, UnitType, Vector } from "bots/ts_libs/dota";
import * as Telemetry from "bots/FunLib/humaniser/telemetry";
import * as Threat from "bots/FunLib/humaniser/threat";
import * as SpellReady from "bots/FunLib/humaniser/spell_ready";
import * as RetreatState from "bots/FunLib/humaniser/retreat_state";
import * as LanePush from "bots/FunLib/humaniser/lane_push";
import * as Sight from "bots/FunLib/humaniser/sight";
import type * as Safe from "bots/FunLib/humaniser/safe";
import { SETTINGS as SafeGatherSettings } from "bots/FunLib/humaniser/safe_gather";

/** `b`'s last number: the safe read's `pressed` for this hero (the kill bar turns on it), so a cut between an enemy's swings replays at the bar the game used. */
/** `b`'s number after it: a physical hit's share that lands on this hero, per mille (the tower row of `Ours.TowerRead` reads our armour). */
function armourNow(bot: Unit): number {
    return f(bot.GetActualIncomingDamage(1000, DamageType.Physical));
}

function pressedNow(bot: Unit): number {
    return bot.WasRecentlyDamagedByAnyHero(SafeGatherSettings.PressWindow) ? 1 : 0;
}

/** Units further than this from the places a cut reads are left out (a hero reaches a walk within the 4 s horizon from 3,000 at most). */
const CUT_R = 3000;

function near(l: Vector, a: Vector, b: Vector): boolean {
    return (math.abs(l.x - a.x) <= CUT_R && math.abs(l.y - a.y) <= CUT_R) || (math.abs(l.x - b.x) <= CUT_R && math.abs(l.y - b.y) <= CUT_R);
}
/** The vision grid's cell size, and how far past the bot and its front it reaches (Threat's walk points). */
const GRID_STEP = 250;
const GRID_PAD = 1600;
const MAX_PLAYER_ID = 23;
/** Threat's TOWER_IDS order; `ta` bit i is this list's i-th tower. */
export const TOWER_IDS = [Tower.Top1, Tower.Top2, Tower.Top3, Tower.Mid1, Tower.Mid2, Tower.Mid3, Tower.Bot1, Tower.Bot2, Tower.Bot3, Tower.Base1, Tower.Base2];

const towersLogged: Record<number, boolean> = {};

function f(n: number | undefined): number {
    return n === undefined ? -1 : math.floor(n + 0.5);
}

function live(u: Unit | undefined | null): u is Unit {
    return u !== undefined && u !== null && !u.IsNull() && u.IsAlive() && u.GetLocation() !== undefined;
}

function targetOf(u: Unit, bot: Unit): string {
    const t = u.GetAttackTarget();
    if (t === undefined || t === null || t.IsNull()) return "-";
    if (t === bot) return "b";
    if (t.IsHero() && !t.IsIllusion()) return `h${t.GetPlayerID()}`;
    return `u${Telemetry.CreepId(t)}`;
}

function creeps(kind: UnitType, bot: Unit, at: Vector, front: Vector): string {
    const out: string[] = [];
    for (const c of GetUnitList(kind) ?? []) {
        if (!live(c) || !LanePush.IsLaneCreep(c.GetUnitName())) continue;
        const l = c.GetLocation();
        if (!near(l, at, front)) continue;
        const ranged = string.find(c.GetUnitName(), "ranged", 1, true)[0] !== undefined ? 1 : 0;
        out.push([Telemetry.CreepId(c), f(l.x), f(l.y), f(c.GetHealth()), f(c.GetMaxHealth()), ranged, targetOf(c, bot), f(c.GetBoundingRadius())].join(","));
    }
    return out.join(";");
}

function escapeReady(bot: Unit): boolean {
    for (const name of Threat.SETTINGS.EscapeItems) {
        const slot = bot.FindItemSlot(name);
        if (slot < 0 || slot > 5) continue;
        const item = bot.GetItemInSlot(slot);
        if (item !== null && item !== undefined && item.IsFullyCastable()) return true;
    }
    return false;
}

/**
 * IsLocationVisible on a grid over the box around `at` and `front` (GRID_PAD past both), as `x0,y0,nx,ny,step,hex`:
 * bit i of the hex is cell (i % nx, floor(i / nx)) from the south-west corner (x0, y0).
 */
function visionGrid(at: Vector, front: Vector): string {
    return Sight.VisionGridBox(
        math.min(at.x, front.x) - GRID_PAD,
        math.min(at.y, front.y) - GRID_PAD,
        math.max(at.x, front.x) + GRID_PAD,
        math.max(at.y, front.y) + GRID_PAD,
        GRID_STEP,
        at.z,
    );
}

function logTowers(team: number): void {
    if (towersLogged[team]) return;
    towersLogged[team] = true;
    const out: string[] = [];
    for (let i = 0; i < TOWER_IDS.length; i++) {
        const tw = GetTower(team, TOWER_IDS[i]);
        if (!live(tw)) continue;
        const l = tw.GetLocation();
        const spa = (tw as Unit & { GetSecondsPerAttack?(): number }).GetSecondsPerAttack?.() ?? 1;
        out.push([i, f(l.x), f(l.y), f(tw.GetAttackRange()), f(tw.GetBoundingRadius()), f(tw.GetAttackDamage()), math.floor(spa * 100 + 0.5) / 100].join(","));
    }
    Telemetry.Event("cut_towers", [
        ["team", team],
        ["tw", out.join(";")],
    ]);
}

/** The towers standing, as a hex mask over TOWER_IDS, and the attack targets of those within CUT_R of `at`. */
function towersNow(team: number, bot: Unit, at: Vector, front: Vector, out: string[]): string {
    let mask = 0;
    for (let i = 0; i < TOWER_IDS.length; i++) {
        const tw = GetTower(team, TOWER_IDS[i]);
        if (!live(tw)) continue;
        mask += 2 ** i;
        const l = tw.GetLocation();
        if (near(l, at, front)) out.push([team, i, targetOf(tw, bot)].join(","));
    }
    return string.format("%x", mask);
}

interface Units {
    he: string[];
    hu: string[];
    ha: string[];
}

/**
 * The enemy heroes in sight and our other heroes at the places `keep` takes (the decision's own area), and every unseen enemy
 * with a sighting. `he`'s two damage figures are SpellReady.DamageOn over `short` and `long` seconds, the windows the
 * decision's Threat.Read counts a hero over (3 and 6 for the gate, 2 and 6 for the leave).
 */
function units(bot: Unit, keep: (this: void, l: Vector) => boolean, short: number, long: number): Units {
    const enemyTeam = bot.GetTeam() === Team.Radiant ? Team.Dire : Team.Radiant;
    const visible: Record<number, boolean> = {};
    const he: string[] = [];
    for (const e of GetUnitList(UnitType.EnemyHeroes) ?? []) {
        if (!live(e) || !e.CanBeSeen()) continue;
        const l = e.GetLocation();
        const ill = e.IsIllusion();
        if (!ill) visible[e.GetPlayerID()] = true;
        if (!keep(l)) continue;
        const e3 = SpellReady.DamageOn(e, bot, short);
        const e6 = SpellReady.DamageOn(e, bot, long);
        const atk = e.GetAttackTarget() === bot ? 1 : 0;
        const eng = bot.WasRecentlyDamagedByHero(e, Threat.SETTINGS.EngagedRecent) ? 1 : 0;
        // pid,x,y,hp,range,hull,speed,atk,eng,e3,e6,illusion
        he.push([e.GetPlayerID(), f(l.x), f(l.y), f(e.GetHealth()), f(e.GetAttackRange()), f(e.GetBoundingRadius()), f(e.GetCurrentMovementSpeed()), atk, eng, f(e3), f(e6), ill ? 1 : 0].join(","));
    }
    const hu: string[] = [];
    for (let p = 0; p <= MAX_PLAYER_ID; p++) {
        if (GetTeamForPlayer(p) !== enemyTeam || visible[p] === true || !IsHeroAlive(p)) continue;
        const info = GetHeroLastSeenInfo(p)[0];
        if (info === undefined) continue;
        // pid,x,y,seconds unseen,last read speed (-1 none)
        hu.push([p, f(info.location.x), f(info.location.y), math.floor(info.time_since_seen * 10 + 0.5) / 10, f(Threat.SeenSpeed(p))].join(","));
    }
    const ha: string[] = [];
    for (const a of GetUnitList(UnitType.AlliedHeroes) ?? []) {
        if (!live(a) || a === bot || a.IsIllusion()) continue;
        if (!keep(a.GetLocation())) continue;
        const l = a.GetLocation();
        // pid,x,y,range,hull,speed,in our retreat
        ha.push([a.GetPlayerID(), f(l.x), f(l.y), f(a.GetAttackRange()), f(a.GetBoundingRadius()), f(a.GetCurrentMovementSpeed()), RetreatState.Running(a) ? 1 : 0].join(","));
    }
    return { he, hu, ha };
}

export interface LeaveInputs {
    r: Threat.Read;
    /** What the game decided: `lethal`, `tower`, `heal`, `threat` (leave) or `under` (stay). */
    dec: string;
    purp: string;
    /** The safe-here answer the rule read (SafeGather.At, held, at the bot's place). */
    a: Safe.Answer;
    /** The damage windows of the read: `he`'s e3 and e6. */
    short: number;
    long: number;
}

/** The leave decision's inputs this frame, with the answer the game gave. Reads only: nothing the decision uses changes. */
export function Leave(bot: Unit, i: LeaveInputs): void {
    const pid = bot.GetPlayerID();
    const team = bot.GetTeam();
    const enemyTeam = team === Team.Radiant ? Team.Dire : Team.Radiant;
    const at = bot.GetLocation();
    logTowers(team);
    logTowers(enemyTeam);
    const { he, hu, ha } = units(bot, (l) => near(l, at, at), i.short, i.long);
    const nearTowers: string[] = [];
    const ta = `${towersNow(team, bot, at, at, nearTowers)},${towersNow(enemyTeam, bot, at, at, nearTowers)}`;
    Telemetry.Event("cut", [
        ["pid", pid],
        ["kind", "leave"],
        ["b", [f(at.x), f(at.y), f(bot.GetHealth()), f(bot.GetMaxHealth()), f(bot.GetAttackRange()), f(bot.GetBoundingRadius()), f(bot.GetCurrentMovementSpeed()), escapeReady(bot) ? 1 : 0, pressedNow(bot), armourNow(bot)].join(",")],
        ["he", he.join(";")],
        ["hu", hu.length > 0 ? hu.join(";") : undefined],
        ["ha", ha.length > 0 ? ha.join(";") : undefined],
        ["ta", ta],
        ["tt", nearTowers.join(";")],
        ["vis", hu.length > 0 ? visionGrid(at, at) : undefined],
        ["dec", i.dec],
        ["purp", i.purp],
        ["lv", i.a.level],
        ["why", i.a.reason],
        ["kill", f(i.a.kill)],
        ["ra", i.a.kill > 0 ? math.floor(i.a.ratio * 100 + 0.5) / 100 : undefined],
        ["dt", bot.WasRecentlyDamagedByTower(0.5) ? 1 : 0],
    ]);
    Telemetry.Event("cut_creeps", [
        ["pid", pid],
        ["kind", "leave"],
        ["ce", creeps(UnitType.EnemyCreeps, bot, at, at)],
        ["ca", creeps(UnitType.AlliedCreeps, bot, at, at)],
    ]);
}

/** Within CUT_R of the box that holds the walk `a` to `b`. */
function nearWalk(l: Vector, a: Vector, b: Vector): boolean {
    return (
        l.x >= math.min(a.x, b.x) - CUT_R &&
        l.x <= math.max(a.x, b.x) + CUT_R &&
        l.y >= math.min(a.y, b.y) - CUT_R &&
        l.y <= math.max(a.y, b.y) + CUT_R
    );
}

/** IsLocationVisible at each of Threat's walk points, as `n,hex`: n steps (n + 1 points), bit i (from the high bit of the first digit) the i-th point. */
function walkVision(from: Vector, place: Vector): string {
    let hex = "";
    let nib = 0;
    let bits = 0;
    const points = Threat.WalkPoints(from, place);
    for (const p of points) {
        nib = nib * 2 + (IsLocationVisible(p) ? 1 : 0);
        bits++;
        if (bits === 4) {
            hex += string.format("%x", nib);
            nib = 0;
            bits = 0;
        }
    }
    if (bits > 0) hex += string.format("%x", nib * 2 ** (4 - bits));
    return `${points.length - 1},${hex}`;
}

/** The inputs of one SafeGather.TripGate decision, logged right after the gate's ev=threat line (same frame, same Read). */
export function Gate(bot: Unit, from: Vector, place: Vector, consumer: string): void {
    if (!Telemetry.IsEnabled() || Telemetry.Get().Cut !== true) return;
    const pid = bot.GetPlayerID();
    const team = bot.GetTeam();
    const enemyTeam = team === Team.Radiant ? Team.Dire : Team.Radiant;
    const at = bot.GetLocation();
    logTowers(team);
    logTowers(enemyTeam);

    const { he, hu, ha } = units(bot, (l) => nearWalk(l, from, place), 3, 6);
    const unused: string[] = [];
    const ta = `${towersNow(team, bot, at, at, unused)},${towersNow(enemyTeam, bot, at, at, unused)}`;
    Telemetry.Event("cut", [
        ["pid", pid],
        ["kind", "gate"],
        ["who", consumer],
        ["b", [f(at.x), f(at.y), f(bot.GetHealth()), f(bot.GetMaxHealth()), f(bot.GetAttackRange()), f(bot.GetBoundingRadius()), f(bot.GetCurrentMovementSpeed()), escapeReady(bot) ? 1 : 0, pressedNow(bot), armourNow(bot)].join(",")],
        ["fm", `${f(from.x)},${f(from.y)}`],
        ["pl", `${f(place.x)},${f(place.y)}`],
        ["he", he.join(";")],
        ["hu", hu.length > 0 ? hu.join(";") : undefined],
        ["ha", ha.length > 0 ? ha.join(";") : undefined],
        ["ta", ta],
        ["vw", hu.length > 0 ? walkVision(from, place) : undefined],
    ]);
}

Threat.SetGateCut(Gate);
