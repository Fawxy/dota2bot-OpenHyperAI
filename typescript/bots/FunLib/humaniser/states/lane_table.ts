/**
 * What a hero does on a laning frame, as one ordered table walked by one function for all five positions. The combiner for
 * mode_laning_generic's Think (OWNERSHIP.md): the first row that wants the frame and whose run issues an order ends it. A row
 * whose run returns false falls through to the next, as the old step chain did.
 *
 * `rank[pos]` is the row's place in that position's order (undefined: never runs for it). A later behaviour changes an order
 * by editing the numbers here, never by testing the position in code. Ranks are spaced by ten so a row can be slotted between.
 */
import { Unit } from "bots/ts_libs/dota";
import * as LaneConfig from "bots/FunLib/humaniser/lane_config";
import * as Overrides from "bots/FunLib/humaniser/overrides";
import * as Telemetry from "bots/FunLib/humaniser/telemetry";
import * as SustainAct from "bots/FunLib/humaniser/sustain_act";

type Pred = (this: void) => boolean;

/** What lives in Lua or in states/index.ts, handed over so this file imports neither (an import cycle). */
export interface Ctx {
    /** States.IsEnabled(): off, every row of ours stands aside and only the host rows (`oha_*`) run. */
    enabled: Pred;
    /** The host's steps (mode_laning_generic.lua): true when the step acted. */
    ohaLastHit: Pred;
    ohaDeny: Pred;
    ohaHold: Pred;
    ohaLocal: Pred;
    ohaPosition: Pred;
}

export interface Row {
    name: string;
    rank: Record<1 | 2 | 3 | 4 | 5, number | undefined>;
    /** Also runs when Overrides.LaneOnly(bot): a drill restricting laning to hits and positioning. */
    drill: boolean;
    /** The row's run is its own scan (it finds a creep or finds none), so giving no order is not news: left out of `skip`. */
    scans?: boolean;
    /** One of mode_laning_generic's own steps: its run is not guarded, so an error in it is raised as the host's, as before. */
    host?: boolean;
    wants: (this: void, bot: Unit, ctx: Ctx) => boolean;
    run: (this: void, bot: Unit, ctx: Ctx) => boolean;
}

function ranks(n: number, ...positions: number[]): Row["rank"] {
    const r: Row["rank"] = { 1: undefined, 2: undefined, 3: undefined, 4: undefined, 5: undefined };
    for (const p of positions) r[p as 1 | 2 | 3 | 4 | 5] = n;
    return r;
}

const all = [1, 2, 3, 4, 5];

/**
 * Sustain step 3 (D6, `Ours.Sustain`): a heal attempt that walks (a tango's tree, a step out to the safe spot, an ally out of
 * cast range) holds the frame until its use starts, so the rows below do not undo the walk.
 */
const sustain: Row = {
    name: "sustain",
    rank: ranks(15, ...all),
    drill: true,
    wants: (bot, ctx) => ctx.enabled() && SustainAct.Walking(bot),
    run: (bot) => SustainAct.Step(bot),
};

const ohaLastHit: Row = {
    name: "oha_lh",
    host: true,
    scans: true,
    rank: ranks(90, ...all),
    drill: true,
    wants: () => true,
    run: (_bot, ctx) => ctx.ohaLastHit(),
};

const ohaDeny: Row = {
    name: "oha_deny",
    host: true,
    scans: true,
    rank: ranks(100, ...all),
    drill: true,
    wants: () => true,
    run: (_bot, ctx) => ctx.ohaDeny(),
};

/** Holds still for a creep OHA's last hit chose to wait on; acts only on a frame `oha_lh` set that wait. */
const ohaHold: Row = {
    name: "oha_hold",
    host: true,
    scans: true,
    rank: ranks(110, ...all),
    drill: true,
    wants: () => true,
    run: (_bot, ctx) => ctx.ohaHold(),
};

/** The optional local override's Think: runs beside the rows and never ends the frame. */
const ohaLocal: Row = {
    name: "oha_local",
    host: true,
    scans: true,
    rank: ranks(120, ...all),
    drill: false,
    wants: () => true,
    run: (_bot, ctx) => {
        ctx.ohaLocal();
        return false;
    },
};

/** OHA's PositionThink: the fallback that always acts. */
const ohaPos: Row = {
    name: "oha_pos",
    host: true,
    rank: ranks(140, ...all),
    drill: true,
    wants: () => true,
    run: (_bot, ctx) => ctx.ohaPosition(),
};

export const ROWS: Row[] = [sustain, ohaLastHit, ohaDeny, ohaHold, ohaLocal, ohaPos];

// An error in a row of ours is reported and the row stands aside, so the rows after it (the host's last hit, deny and position)
// still run. A failed `wants` on a host row answers true: ours does not own the frame.
for (const r of ROWS) {
    const host = r.host === true;
    r.wants = Telemetry.Guard(`LaneTable.${r.name}.wants`, r.wants, () => host);
    if (!host) r.run = Telemetry.Guard(`LaneTable.${r.name}.run`, r.run, () => false);
}

function build(pos: 1 | 2 | 3 | 4 | 5, laneOnly: boolean): Row[] {
    const out: Row[] = [];
    for (const r of ROWS) {
        if (r.rank[pos] === undefined || (laneOnly && !r.drill)) continue;
        out.push(r);
    }
    table.sort(out, (a, b) => (a.rank[pos] as number) < (b.rank[pos] as number));
    return out;
}

const ORDERS: Record<string, Row[]> = {};
for (const p of [1, 2, 3, 4, 5] as const) {
    ORDERS[`${p}:0`] = build(p, false);
    ORDERS[`${p}:1`] = build(p, true);
}

/** The rows that run for a position, in order. An undefined or unknown position takes position 1's order. */
export function Order(pos: number, laneOnly: boolean): Row[] {
    return ORDERS[`${pos}:${laneOnly ? 1 : 0}`] ?? ORDERS[`1:${laneOnly ? 1 : 0}`];
}

const CUT_EVERY = 5;
interface CutState {
    row?: string;
    skipped: string[];
    nSkipped: number;
    at: number;
}
const cutState: Record<number, CutState | undefined> = {};
const skipScratch: string[] = [];

function cutDue(st: CutState, row: string, n: number, now: number): boolean {
    if (st.row !== row || st.nSkipped !== n || now < st.at || now - st.at >= CUT_EVERY) return true;
    for (let i = 0; i < n; i++) if (st.skipped[i] !== skipScratch[i]) return true;
    return false;
}

function cut(bot: Unit, pos: number | undefined, laneOnly: boolean, row: string, n: number): void {
    const pid = bot.GetPlayerID();
    const now = DotaTime();
    const st = (cutState[pid] = cutState[pid] ?? { skipped: [], nSkipped: 0, at: 0 });
    if (!cutDue(st, row, n, now)) return;
    st.row = row;
    st.nSkipped = n;
    st.at = now;
    for (let i = 0; i < n; i++) st.skipped[i] = skipScratch[i];
    Telemetry.Event("cut", [
        ["pid", pid],
        ["kind", "lane"],
        ["pos", pos],
        ["row", row],
        ["skip", n > 0 ? table.concat(skipScratch, ",", 1, n) : undefined],
        ["lo", laneOnly ? 1 : 0],
    ]);
}

/** Walks the bot's order and returns the name of the row that acted (the fallback row always does). */
export function Walk(bot: Unit, ctx: Ctx): string {
    const pos = LaneConfig.PositionOf(bot);
    const laneOnly = Overrides.LaneOnly(bot);
    const order = Order(pos ?? 1, laneOnly);
    let n = 0;
    let acted = order[order.length - 1].name;
    for (const r of order) {
        const t0 = Telemetry.DeepT0();
        const wants = r.wants(bot, ctx);
        if (t0 !== undefined) Telemetry.DeepAdd(`lane_table.Walk:${r.name}.wants`, t0);
        if (!wants) continue;
        const t1 = Telemetry.DeepT0();
        const ran = r.run(bot, ctx);
        if (t1 !== undefined) Telemetry.DeepAdd(`lane_table.Walk:${r.name}.run`, t1);
        if (ran) {
            acted = r.name;
            break;
        }
        if (r.scans !== true) skipScratch[n++] = r.name;
    }
    if (Telemetry.IsEnabled() && Telemetry.Get().Cut === true) cut(bot, pos, laneOnly, acted, n);
    return acted;
}
