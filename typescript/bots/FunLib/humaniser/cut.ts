/**
 * Fixture cuts (rework step 8, docs/proposals/2026-11-13-rework.md s8): the API state one decision reads, logged in the frame
 * it decides, so a banked moment replays offline. tools/hlog/cut.js turns a line into a fixture world; the decision's driver
 * under tests/humaniser/fixture_drivers/ serves that world back to the real code. One `ev=cut` line per decision sample,
 * `kind` naming the decision; one `ev=cut_towers` line per team the first time it cuts (tower places do not move).
 *
 * `spot` (LaneSpot.Compute and the Threat.Read it makes): what neither ev=snap nor ev=lane_pos holds. Visible enemy heroes
 * with GetEstimatedDamageToTarget over Read's two windows, our team's last sighting of each unseen one, our vision around the
 * bot (only while an enemy is unseen), the lane creeps of both teams near the bot and the lane fronts. Lists are `;`-joined
 * records of `,`-joined numbers in the order the field's comment gives (lane creeps on ev=cut_creeps, the same frame); a target is `b` (this bot), `h<pid>`, `u<CreepId>`
 * or `-`.
 */
import { DamageType, Team, Tower, Unit, UnitType, Vector } from "bots/ts_libs/dota";
import * as Telemetry from "bots/FunLib/humaniser/telemetry";
import * as Threat from "bots/FunLib/humaniser/threat";
import * as RetreatState from "bots/FunLib/humaniser/retreat_state";
import * as LanePush from "bots/FunLib/humaniser/lane_push";
import * as Laning from "bots/FunLib/humaniser/states/laning";

/**
 * Units further than this from both the bot and its lane front are left out: Compute queries 1,600 from the bot, but a bot
 * walking back to lane reads its walk to a spot by the front (smoke 1: 5 of 60 cuts lost a hero 3,500 from the bot).
 */
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
 * IsLocationVisible on a grid over the box around the bot and its lane front (GRID_PAD past both), as `x0,y0,nx,ny,step,hex`:
 * bit i of the hex is cell (i % nx, floor(i / nx)) from the south-west corner (x0, y0).
 */
function visionGrid(at: Vector, front: Vector): string {
    const x0 = math.floor((math.min(at.x, front.x) - GRID_PAD) / GRID_STEP) * GRID_STEP;
    const y0 = math.floor((math.min(at.y, front.y) - GRID_PAD) / GRID_STEP) * GRID_STEP;
    const nx = math.ceil((math.max(at.x, front.x) + GRID_PAD - x0) / GRID_STEP) + 1;
    const ny = math.ceil((math.max(at.y, front.y) + GRID_PAD - y0) / GRID_STEP) + 1;
    let hex = "";
    let nib = 0;
    let bits = 0;
    for (let j = 0; j < ny; j++) {
        for (let i = 0; i < nx; i++) {
            nib = nib * 2 + (IsLocationVisible(Vector(x0 + i * GRID_STEP, y0 + j * GRID_STEP, at.z)) ? 1 : 0);
            bits++;
            if (bits === 4) {
                hex += string.format("%x", nib);
                nib = 0;
                bits = 0;
            }
        }
    }
    if (bits > 0) hex += string.format("%x", nib * 2 ** (4 - bits));
    return `${x0},${y0},${nx},${ny},${GRID_STEP},${hex}`;
}

function logTowers(team: number): void {
    if (towersLogged[team]) return;
    towersLogged[team] = true;
    const out: string[] = [];
    for (let i = 0; i < TOWER_IDS.length; i++) {
        const tw = GetTower(team, TOWER_IDS[i]);
        if (!live(tw)) continue;
        const l = tw.GetLocation();
        out.push([i, f(l.x), f(l.y), f(tw.GetAttackRange()), f(tw.GetBoundingRadius())].join(","));
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

/** The spot's inputs this frame, beside its ev=lane_pos line. */
export function Spot(bot: Unit): void {
    const pid = bot.GetPlayerID();
    const team = bot.GetTeam();
    const enemyTeam = team === Team.Radiant ? Team.Dire : Team.Radiant;
    const lane = bot.GetAssignedLane();
    const at = bot.GetLocation();
    const [role, fed, hold] = Laning.SpotInputs(bot);
    logTowers(team);
    logTowers(enemyTeam);

    const front = GetLaneFrontLocation(team, lane, 0);
    const back = GetLaneFrontLocation(team, lane, -400);
    const visible: Record<number, boolean> = {};
    const he: string[] = [];
    for (const e of GetUnitList(UnitType.EnemyHeroes) ?? []) {
        if (!live(e) || !e.CanBeSeen()) continue;
        const l = e.GetLocation();
        const ill = e.IsIllusion();
        if (!ill) visible[e.GetPlayerID()] = true;
        if (!near(l, at, front)) continue;
        const e3 = e.GetEstimatedDamageToTarget(true, bot, 3, DamageType.All);
        const e6 = e.GetEstimatedDamageToTarget(true, bot, 6, DamageType.All);
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
        if (!near(a.GetLocation(), at, front)) continue;
        const l = a.GetLocation();
        // pid,x,y,range,hull,speed,in our retreat
        ha.push([a.GetPlayerID(), f(l.x), f(l.y), f(a.GetAttackRange()), f(a.GetBoundingRadius()), f(a.GetCurrentMovementSpeed()), RetreatState.Running(a) ? 1 : 0].join(","));
    }
    const nearTowers: string[] = [];
    const ta = `${towersNow(team, bot, at, front, nearTowers)},${towersNow(enemyTeam, bot, at, front, nearTowers)}`;
    Telemetry.Event("cut", [
        ["pid", pid],
        ["kind", "spot"],
        ["role", role],
        ["lane", lane],
        ["b", [f(at.x), f(at.y), f(bot.GetHealth()), f(bot.GetMaxHealth()), f(bot.GetAttackRange()), f(bot.GetBoundingRadius()), f(bot.GetCurrentMovementSpeed()), escapeReady(bot) ? 1 : 0].join(",")],
        ["fr", [f(front.x), f(front.y), f(back.x), f(back.y)].join(",")],
        ["fed", live(fed) ? Telemetry.CreepId(fed) : undefined],
        ["hold", hold !== undefined ? `${f(hold.x)},${f(hold.y)}` : undefined],
        ["he", he.join(";")],
        ["hu", hu.length > 0 ? hu.join(";") : undefined],
        ["ha", ha.length > 0 ? ha.join(";") : undefined],
        ["ta", ta],
        ["tt", nearTowers.join(";")],
        ["vis", hu.length > 0 ? visionGrid(at, front) : undefined],
    ]);
    // Its own line: with both waves near, one line would pass the length Dota's console prints whole.
    Telemetry.Event("cut_creeps", [
        ["pid", pid],
        ["ce", creeps(UnitType.EnemyCreeps, bot, at, front)],
        ["ca", creeps(UnitType.AlliedCreeps, bot, at, front)],
    ]);
}
