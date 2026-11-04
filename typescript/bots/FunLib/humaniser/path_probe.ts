/**
 * Throwaway probe (branch probe/genpath, never merged): what Valve's GeneratePath returns for the shrine contest's walk, and
 * whether it honours avoidance zones passed as Vector(x, y, radius) or as AddAvoidanceZone handles. Prints raw [HEV]
 * ev=pathprobe lines (not declared; read with grep).
 */
import { Unit, Vector, Team } from "bots/ts_libs/dota";
import * as FR from "bots/FunLib/humaniser/fight_readings";
import * as Rotate from "bots/FunLib/humaniser/states/rotate";
import * as Utils from "bots/FunLib/utils";
import * as RuneJob from "bots/FunLib/humaniser/rune_job";

// OHA's global print drops output unless Utils.DebugMode (aba_global_overrides); probes v2 and v3 printed nothing.
const out: (this: void, s: string) => void = (Utils as any).RawPrint ?? print;

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
    out(`[HEV] t=${string.format("%.3f", DotaTime())} ev=pathprobe team=${team} from=${from} v=${variant} d=${math.floor(d)} n=${wp.length} min=${math.floor(min)} tw=${tw} wp=${pts}`);
}

function hev(rest: string): void {
    out(`[HEV] t=${string.format("%.3f", DotaTime())} ev=pathprobe ${rest}`);
}

function guard<T>(step: string, f: () => T): T | undefined {
    const [ok, v] = pcall(f);
    if (!ok) {
        hev(`step=${step} err=${string.gsub(tostring(v), " ", "_")[0]}`);
        return undefined;
    }
    return v as T;
}

// v7: v6's starts at 6:30 (rspchk4's contest leave time), raw min and the slice's Thin + Clearance per path.
const queue: (() => void)[] = [];
export function Run(bot: Unit): void {
    const next = queue.shift();
    if (next !== undefined) next();
    const team = bot.GetTeam();
    if (done[team] === true || DotaTime() < 390) return;
    done[team] = true;
    const enemy = team === Team.Radiant ? Team.Dire : Team.Radiant;
    const to = Rotate.ShrineFor(enemy);
    const towers = FR.TowerSpots(enemy);
    const starts: [string, Vector][] =
        team === Team.Radiant
            ? [["safe", Vector(4025, -6225, 0)], ["lane", Vector(5004, -4874, 0)]]
            : [["safe", Vector(-4002, 5473, 0)], ["lane", Vector(-4601, 4782, 0)]];
    const vecs = towers.map((t) => Vector(t.x, t.y, 1100));
    const handles = towers.map((t) => guard("zone", () => AddAvoidanceZone(Vector(t.x, t.y, 1100), 120)));
    hev(`team=${team} step=zones h=${handles.map((h) => tostring(h)).join(",")}`);
    for (const [name, start] of starts) {
        for (const [v, avoid] of [["none", []], ["vec", vecs], ["handle", handles.filter((h) => h !== undefined)]] as [string, unknown[]][]) {
            queue.push(() =>
                guard(`gen:${name}:${v}`, () =>
                    GeneratePath(start, to, avoid, ((...args: unknown[]) => {
                        const wp = args.find((x) => type(x) === "table") as Vector[] | undefined;
                        const d = args.find((x) => type(x) === "number") as number | undefined;
                        if (wp !== undefined) {
                            guard(`cb:${name}:${v}`, () => report(team, name, v, start, towers, d ?? -1, wp));
                            const th = RuneJob.Thin(wp, to);
                            hev(`team=${team} from=${name} v=${v} thin=${th.length} tclr=${math.floor(RuneJob.Clearance(start, [...th, to], towers))} pts=${th.map((q) => `${math.floor(q.x)},${math.floor(q.y)}`).join(";")}`);
                        } else hev(`team=${team} from=${name} v=${v} nowp n=${args.length}`);
                    }) as any)
                )
            );
        }
    }
}
