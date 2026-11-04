/**
 * Throwaway probe v8 (branch probe/contest-drill, never merged): do GeneratePath answers cross between requests sent in one
 * frame? Every 10 s from 0:30 to 1:30 every hero asks for the path from where it stands to the enemy shrine, as the contest
 * job does. Each answer is logged against every request of its round: whose start its first waypoint is nearest, and
 * whose goal its last is nearest. Raw [HEV] ev=pathprobe lines (not declared; read with grep).
 */
import { Unit, Vector, Team } from "bots/ts_libs/dota";
import * as FR from "bots/FunLib/humaniser/fight_readings";
import * as Rotate from "bots/FunLib/humaniser/states/rotate";
import * as Utils from "bots/FunLib/utils";

const out: (this: void, s: string) => void = (Utils as any).RawPrint ?? print;

declare function GeneratePath(this: void, a: Vector, b: Vector, avoid: unknown[], cb: (this: void, ...args: unknown[]) => void): unknown;

type Req = { pid: number; from: Vector; to: Vector; ret: string };
const rounds: Record<number, Req[]> = {};
const asked: Record<string, boolean> = {};

function hev(rest: string): void {
    out(`[HEV] t=${string.format("%.3f", DotaTime())} ev=pathprobe ${rest}`);
}

function nearest(reqs: Req[], p: Vector, pick: (r: Req) => Vector): [number, number] {
    let best = -1;
    let bestD = math.huge;
    for (const r of reqs) {
        const d = FR.Dist(pick(r), p);
        if (d < bestD) [best, bestD] = [r.pid, d];
    }
    return [best, math.floor(bestD)];
}

export function Run(bot: Unit): void {
    const now = DotaTime();
    if (now < 30 || now > 90) return;
    const round = math.floor((now - 30) / 10);
    const pid = bot.GetPlayerID();
    const k = `${round}:${pid}`;
    if (asked[k] === true) return;
    asked[k] = true;
    const enemy = bot.GetTeam() === Team.Radiant ? Team.Dire : Team.Radiant;
    const reqs = (rounds[round] = rounds[round] ?? []);
    const req: Req = { pid, from: bot.GetLocation(), to: Rotate.ShrineFor(enemy), ret: "?" };
    reqs.push(req);
    const frame = now;
    const [ok, ret] = pcall(() =>
        GeneratePath(req.from, req.to, [], (...args: unknown[]) => {
            const nums = args.filter((a) => type(a) === "number").map((a) => string.format("%.0f", a as number)).join(",");
            const wp = args.find((a) => type(a) === "table") as Vector[] | undefined;
            if (wp === undefined || wp.length === 0) {
                hev(`r=${round} pid=${pid} nowp n=${args.length} nums=${nums}`);
                return;
            }
            const [sp, sd] = nearest(reqs, wp[0], (r) => r.from);
            const [gp, gd] = nearest(reqs, wp[wp.length - 1], (r) => r.to);
            const own0 = math.floor(FR.Dist(wp[0], req.from));
            const ownN = math.floor(FR.Dist(wp[wp.length - 1], req.to));
            hev(
                `r=${round} pid=${pid} n=${wp.length} nums=${nums} ret=${req.ret} lag=${string.format("%.2f", DotaTime() - frame)} own0=${own0} ownN=${ownN} start_pid=${sp} start_d=${sd} goal_pid=${gp} goal_d=${gd} reqs=${reqs.length}`
            );
        })
    );
    req.ret = ok ? tostring(ret) : `err:${string.gsub(tostring(ret), " ", "_")[0]}`;
    hev(`r=${round} pid=${pid} ask from=${math.floor(req.from.x)},${math.floor(req.from.y)} ret=${req.ret} frame=${string.format("%.3f", frame)}`);
}
