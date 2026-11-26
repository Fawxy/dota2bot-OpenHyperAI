/**
 * The reads a row's `wants` is passed (`wants(bot, reads)`, decider.ts). A read holds a fact of the lane, the camp or the team that
 * more than one row asks; it is computed when first asked and a scan is kept for its frame, so every row in a frame gets one
 * answer. A new shared read is a module like `camp_read.ts` and one member here; a row imports no other row's file for a fact.
 */
import * as CampRead from "bots/FunLib/humaniser/camp_read";

export interface Reads {
    camp: typeof CampRead;
}

export const READS: Reads = { camp: CampRead };
