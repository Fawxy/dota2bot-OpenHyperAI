/**
 * The laning hold (master docs/team/ARCHITECTURE.md, the boundary): LaningHeld is the one answer to "is this hero
 * laning" for every laning behaviour of ours. Per hero, it starts at the hero's first read and ends once.
 */
import { Lane, Tower, Unit } from "bots/ts_libs/dota";
import * as LaneConfig from "bots/FunLib/humaniser/lane_config";
import * as Telemetry from "bots/FunLib/humaniser/telemetry";

const T1: Record<number, number> = { [Lane.Top]: Tower.Top1, [Lane.Mid]: Tower.Mid1, [Lane.Bot]: Tower.Bot1 };

let held: Record<number, { on: boolean; ended?: string; checkAt: number }> = {};

export function ResetCache(): void {
    held = {};
}

function towerDown(team: number, lane: Lane): boolean {
    const id = T1[lane];
    if (id === undefined) return false;
    const t = GetTower(team, id);
    return t === undefined || t === null || !t.IsAlive();
}

/** judgement: seconds between checks of a hero's hold. */
const HELD_CHECK = 1;

/** Why a hero's laning is over: the clock, or a tier-1 of its lane lost (ours or theirs); undefined while it is not. */
function heldEndWhy(bot: Unit): string | undefined {
    // The clock is OHA's (J.IsInLaningPhase): 10:00, extended to 14:00 while net worth is under 8,000. Not ours to tune.
    if (!LaneConfig.InLaningPhase()) return "clock";
    const team = bot.GetTeam();
    const lane = bot.GetAssignedLane();
    if (towerDown(team, lane) || towerDown(team === 2 ? 3 : 2, lane)) return "tower";
    return undefined;
}

/**
 * The hero is held from its first read in its laning to an end event (heldEndWhy), and never again after it. The start
 * and the end log `ev=arb` with `ph`.
 */
export function LaningHeld(bot: Unit): boolean {
    const pid = bot.GetPlayerID();
    const now = DotaTime();
    let h = held[pid];
    if (h === undefined) {
        h = { on: false, checkAt: -math.huge };
        held[pid] = h;
    }
    if (h.ended !== undefined) return false;
    if (now < h.checkAt) return h.on;
    h.checkAt = now + HELD_CHECK;
    if (!h.on) {
        if (heldEndWhy(bot) !== undefined) return false;
        h.on = true;
        Telemetry.Event("arb", [["pid", pid], ["ph", "own"]]);
        return true;
    }
    const why = heldEndWhy(bot);
    if (why === undefined) return true;
    h.on = false;
    h.ended = why;
    Telemetry.Event("arb", [["pid", pid], ["ph", "end"], ["why", why]]);
    return false;
}
