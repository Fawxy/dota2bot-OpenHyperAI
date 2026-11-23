/**
 * The hooks OHA's mode files ask about a hero's laning Think and its shrine: who runs mode_laning_generic's Lua Think
 * through the lane table (states/lane_table), and whether the rune job holds the shrine.
 */
import { Unit } from "bots/ts_libs/dota";
import * as Config from "bots/FunLib/humaniser/config";
import * as Drill from "bots/FunLib/humaniser/drill";
import * as LaneConfig from "bots/FunLib/humaniser/lane_config";
import * as Ours from "bots/FunLib/humaniser/ours";
import * as LaneTable from "bots/FunLib/humaniser/states/lane_table";
import * as RuneJob from "bots/FunLib/humaniser/rune_job";

export function IsEnabled(): boolean {
    return Config.IsEnabled();
}

/**
 * Whether this bot runs mode_laning_generic's Lua Think where OHA itself would leave Valve's laning: an ally of a human
 * in a drill game or with `Ours.Sustain` on (the lane-only hold and sustain's walk are rows of that Think). Decided once,
 * at the file's load. Off, and for a team with no human, the answer is OHA's own.
 */
export function MayOwn(bot: Unit): boolean {
    return IsEnabled() && LaneConfig.IsAllyOfHuman(bot) && (Ours.On("Sustain") || Drill.Active() !== undefined);
}

/** mode_rune_generic: OHA's own wisdom logic stands aside while the rune job holds the shrine for this bot. */
export function WisdomOwned(bot: Unit): boolean {
    return RuneJob.ShrineHeld(bot);
}

/** The Lua callbacks of mode_laning_generic's Think that LaneStep walks (states/lane_table Ctx). */
export type LaneCallbacks = Pick<LaneTable.Ctx, "ohaLastHit" | "ohaDeny" | "ohaLocal" | "ohaPosition">;

const laneCtx: Record<number, { cb: LaneCallbacks; ctx: LaneTable.Ctx } | undefined> = {};

/** mode_laning_generic's Think for a bot that owns it: the name of the lane table row that acted (states/lane_table). */
export function LaneStep(bot: Unit, cb: LaneCallbacks): string {
    const pid = bot.GetPlayerID();
    let c = laneCtx[pid];
    if (c === undefined || c.cb !== cb) {
        c = {
            cb,
            ctx: {
                enabled: IsEnabled,
                ohaLastHit: cb.ohaLastHit,
                ohaDeny: cb.ohaDeny,
                ohaLocal: cb.ohaLocal,
                ohaPosition: cb.ohaPosition,
            },
        };
        laneCtx[pid] = c;
    }
    return LaneTable.Walk(bot, c.ctx);
}
