/**
 * Throwaway probe (branch probe/genpath, never merged): what Valve's GeneratePath returns for the shrine contest's walk, and
 * whether it honours avoidance zones passed as Vector(x, y, radius) or as AddAvoidanceZone handles. Prints raw [HEV]
 * ev=pathprobe lines (not declared; read with grep).
 */
import { Unit, Vector, Team, Rune } from "bots/ts_libs/dota";
import * as FR from "bots/FunLib/humaniser/fight_readings";
import * as Rotate from "bots/FunLib/humaniser/states/rotate";

declare function GeneratePath(this: void, a: Vector, b: Vector, avoid: unknown[], cb: (this: void, d: number, wp: Vector[]) => void): void;
declare function AddAvoidanceZone(this: void, v: Vector, dur?: number): unknown;
declare function GetRuneSpawnLocation(this: void, rune: number): Vector;
declare function IsLocationPassable(this: void, loc: Vector): boolean;

const done: Record<number, boolean> = {};

function segDist(a: Vector, b: Vector, p: Vector): number {
    const dx = b.x - a.x;
    const dy = b.y - a.y;
    const l2 = dx * dx + dy * dy;
    const k = l2 > 0 ? math.max(0, math.min(1, ((p.x - a.x) * dx + (p.y - a.y) * dy) / l2)) : 0;
    const cx = a.x + k * dx - p.x;
    const cy = a.y + k * dy - p.y;
    return math.sqrt(cx * cx + cy * cy);
}

function report(team: number, from: string, variant: string, start: Vector, towers: Vector[], d: number, wp: Vector[]): void {
    let min = math.huge;
    let which = -1;
    let a = start;
    for (const p of [...wp]) {
        for (let i = 0; i < towers.length; i++) {
            const s = segDist(a, p, towers[i]);
            if (s < min) [min, which] = [s, i];
        }
        a = p;
    }
    const pts = wp.map((p) => `${math.floor(p.x)},${math.floor(p.y)}`).join(";");
    const tw = which >= 0 ? `${math.floor(towers[which].x)},${math.floor(towers[which].y)}` : "-";
    print(`[HEV] t=${string.format("%.3f", DotaTime())} ev=pathprobe team=${team} from=${from} v=${variant} d=${math.floor(d)} n=${wp.length} min=${math.floor(min)} tw=${tw} wp=${pts}`);
}

export function Run(bot: Unit): void {
    const team = bot.GetTeam();
    if (done[team] === true || DotaTime() < 30) return;
    done[team] = true;
    const enemy = team === Team.Radiant ? Team.Dire : Team.Radiant;
    const to = Rotate.ShrineFor(enemy);
    const towers = FR.TowerSpots(enemy);
    const lane = team === Team.Dire ? Vector(-5800, 5000, 0) : Vector(5800, -5000, 0);
    const starts: [string, Vector][] = [
        ["lane", lane],
        ["rune0", GetRuneSpawnLocation(Rune.Power1)],
        ["rune1", GetRuneSpawnLocation(Rune.Power2)],
        ["bot", bot.GetLocation()],
    ];
    const vecs = towers.map((t) => Vector(t.x, t.y, 1000));
    const handles = towers.map((t) => AddAvoidanceZone(Vector(t.x, t.y, 1000), 30));
    print(`[HEV] t=${string.format("%.3f", DotaTime())} ev=pathprobe team=${team} towers=${towers.map((t) => `${math.floor(t.x)},${math.floor(t.y)}`).join(";")} to=${math.floor(to.x)},${math.floor(to.y)} pass=${IsLocationPassable(to) ? 1 : 0}`);
    for (const [name, start] of starts) {
        for (const [v, avoid] of [["none", []], ["vec", vecs], ["handle", handles]] as [string, unknown[]][]) {
            const [ok, err] = pcall(() => GeneratePath(start, to, avoid, (d, wp) => report(team, name, v, start, towers, d, wp ?? [])));
            if (!ok) print(`[HEV] t=${string.format("%.3f", DotaTime())} ev=pathprobe team=${team} from=${name} v=${v} err=${string.gsub(tostring(err), " ", "_")[0]}`);
        }
    }
}
