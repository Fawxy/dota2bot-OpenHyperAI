/**
 * What a hero does on a laning frame, as one ordered table walked by one function for all five positions. The combiner for
 * mode_laning_generic's Think (OWNERSHIP.md): the first row that wants the frame and whose run issues an order ends it. A row
 * whose run returns false falls through to the next, as the old step chain did.
 *
 * `rank[pos]` is the row's place in that position's order (undefined: never runs for it). A later behaviour changes an order
 * by editing the numbers here, never by testing the position in code. Ranks are spaced by ten so a row can be slotted between.
 */
import { Unit } from "bots/ts_libs/dota";
import * as Laning from "bots/FunLib/humaniser/states/laning";
import * as WaveHold from "bots/FunLib/humaniser/states/wave_hold";
import * as CoreLastHit from "bots/FunLib/humaniser/states/core_last_hit";
import * as LaneAggro from "bots/FunLib/humaniser/lane_aggro";
import * as LaneConfig from "bots/FunLib/humaniser/lane_config";
import * as Drill from "bots/FunLib/humaniser/drill";
import * as Overrides from "bots/FunLib/humaniser/overrides";
import * as Telemetry from "bots/FunLib/humaniser/telemetry";

type Pred = (this: void) => boolean;

/** What lives in Lua or in states/index.ts, handed over so this file imports neither (an import cycle). */
export interface Ctx {
    /** States.IsEnabled(): off, every row of ours stands aside and only the host rows (`oha_*`, `etiquette`) run. */
    enabled: Pred;
    /** Whether the laning body runs for this bot now (state current, owned, running). */
    bodyRunning: Pred;
    /** The body's phase label (walk, hold, lasthit, deny), when it runs. */
    bodyLabel: (this: void) => string | undefined;
    /** Steps the laning body this frame; true when it acted. */
    stepBody: Pred;
    /** The body is in a last-hit or deny swing (States.BodyBusy). */
    bodyBusy: Pred;
    /** The body runs and owns a core's last hits and denies (States.BodyLastHits). */
    bodyLastHits: Pred;
    /** The body runs and owns the support's lane hits (States.BodySupportHits) and, with the claims, their last hits. */
    bodySupportHits: Pred;
    bodySupportLastHits: Pred;
    /** The host's steps (mode_laning_generic.lua): true when the step acted. */
    etiquette: Pred;
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
    /** Runs only under LaneOnly: the row is left out of the other orders. */
    drillOnly?: boolean;
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

const supports = [4, 5];
const cores = [1, 2, 3];
const all = [1, 2, 3, 4, 5];

/** The engine body's last-hit or deny swing in progress must not be overridden by the rows below (slice 4). */
const bodyHit: Row = {
    name: "body_hit",
    rank: ranks(10, ...all),
    drill: true,
    wants: (_bot, ctx) => ctx.bodyBusy(),
    run: (_bot, ctx) => ctx.stepBody(),
};

/**
 * User rule 02/11/2026: the support's lane hits before anything else (denies, and since slice support-lane-hits the last hits
 * its claims give it). Wants the frame while the body is in an attempt or would start one now; its scan picks the creep.
 */
const supportHit: Row = {
    name: "support_hit",
    rank: ranks(20, ...supports),
    drill: true,
    wants: (bot, ctx) => {
        if (!ctx.enabled() || !Laning.OwnsSupportHits(bot) || !ctx.bodyRunning()) return false;
        const label = ctx.bodyLabel();
        return label === "deny" || label === "lasthit" || Laning.HitOffered(bot);
    },
    run: (_bot, ctx) => ctx.stepBody(),
};

/**
 * Slice lane-aggro: with its lane core away a support draws creeps itself (feed, drag); after its lane hits, before the hold,
 * and only while the body runs (so never inside another state's frame).
 */
const supportAggro: Row = {
    name: "support_aggro",
    rank: ranks(30, ...supports),
    drill: true,
    wants: (bot, ctx) => ctx.enabled() && Laning.OwnsSupportHits(bot) && ctx.bodyRunning() && (LaneAggro.Owns(bot) || LaneAggro.Pending(bot)),
    run: (bot) => LaneAggro.Step(bot),
};

/**
 * Slice support-spot: with no lane hit to take, the body holds the support on our lane spot (states/lane_spot, role support)
 * instead of OHA's harass and PositionThink. Harass is not a lane row: it runs in our attack mode (states/trade), which
 * outbids laning while a harass is on.
 */
const supportHold: Row = {
    name: "support_hold",
    rank: ranks(40, ...supports),
    drill: true,
    wants: (bot, ctx) => ctx.enabled() && Laning.OwnsSupportHits(bot) && Laning.OwnsSpot(bot) && ctx.bodyRunning(),
    run: (_bot, ctx) => ctx.stepBody(),
};

/**
 * A drill's lane-only core with the wave hold (drill entry `laneHold`): the hold and the draw it started; no other lane aggro
 * draw starts (StepOpen steps only an open one).
 */
const drillHold: Row = {
    name: "drill_hold",
    rank: ranks(50, ...cores),
    drill: true,
    drillOnly: true,
    wants: (bot, ctx) => ctx.enabled() && Drill.LaneHold(bot) && ctx.bodyLastHits(),
    run: (bot) => {
        WaveHold.Act(bot);
        return LaneAggro.StepOpen(bot);
    },
};

/** A drill's lane-only core with lane aggro (drill entry `laneAggro`): lane aggro's draws, as `aggro` outside drills. */
const drillAggro: Row = {
    name: "drill_aggro",
    rank: ranks(60, ...cores),
    drill: true,
    drillOnly: true,
    wants: (bot, ctx) => ctx.enabled() && Drill.LaneAggro(bot) && ctx.bodyLastHits(),
    run: (bot) => LaneAggro.Step(bot),
};

/**
 * Slice lane-aggro: a core's draw (lane_aggro feed, drag) while the laning body runs for it, after the body's running swing and
 * before OHA's techniques. A support draws through `support_aggro` instead.
 */
const aggro: Row = {
    name: "aggro",
    scans: true,
    rank: ranks(70, ...cores),
    drill: false,
    wants: (_bot, ctx) => ctx.enabled(),
    run: (bot, ctx) => {
        // While a draw gives the orders, this Think returns before the body is stepped, so the engine ends the body's task
        // (stalled, never_started) until the state restarts it; a core's open draw is stepped regardless or it ends `stale`
        // (awchk1). Only the open one: no new draw starts with the body off, and a support's draw stays support_aggro's.
        if (!ctx.bodyLastHits()) return CoreLastHit.Applies(bot) && LaneAggro.StepOpen(bot);
        // Ours.CoreHold: the wave hold's read (Tick) set the spot's `hold` input; here it starts the `back` draw it wants, which
        // the step below acts.
        WaveHold.Act(bot);
        return LaneAggro.Step(bot);
    },
};

/** Ours.LeaveCoreCreep: a swing or auto-attack on a creep a core can take is cancelled by the move. */
const etiquette: Row = {
    name: "etiquette",
    host: true,
    scans: true,
    rank: ranks(80, ...all),
    drill: false,
    wants: () => true,
    run: (_bot, ctx) => ctx.etiquette(),
};

/**
 * With etiquette on, a last hit near a protected human is only allowed when the human will miss it, so taking it before a deny
 * is intended. Where the body owns last hits (team slice 4) it takes them and the denies itself.
 */
const ohaLastHit: Row = {
    name: "oha_lh",
    host: true,
    scans: true,
    rank: ranks(90, ...all),
    drill: true,
    // Ours.SupportLastHit: the support's body takes the last hits its claims give it (states/lane_claims), so OHA's do not run.
    wants: (_bot, ctx) => !ctx.bodyLastHits() && !ctx.bodySupportLastHits(),
    run: (_bot, ctx) => ctx.ohaLastHit(),
};

const ohaDeny: Row = {
    name: "oha_deny",
    host: true,
    scans: true,
    rank: ranks(100, ...all),
    drill: true,
    wants: (_bot, ctx) => !ctx.bodyLastHits() && !ctx.bodySupportHits(),
    run: (_bot, ctx) => ctx.ohaDeny(),
};

/** Holds still for a creep OHA's last hit chose to wait on; acts only on a frame `oha_lh` set that wait. */
const ohaHold: Row = {
    name: "oha_hold",
    host: true,
    scans: true,
    rank: ranks(110, ...all),
    drill: true,
    wants: (_bot, ctx) => !ctx.bodyLastHits(),
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

/**
 * The body's step for a frame no row above took. A support whose body owns its lane hits but not its harass keeps OHA's
 * positioning: the body's hold would cancel its Valve attacks on heroes (docs/team/research/core-time-diagnosis.md).
 */
const body: Row = {
    name: "body",
    scans: true,
    rank: ranks(130, ...all),
    drill: true,
    wants: (_bot, ctx) => !ctx.bodySupportHits(),
    run: (_bot, ctx) => ctx.stepBody(),
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

export const ROWS: Row[] = [bodyHit, supportHit, supportAggro, supportHold, drillHold, drillAggro, aggro, etiquette, ohaLastHit, ohaDeny, ohaHold, ohaLocal, body, ohaPos];

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
        if (r.rank[pos] === undefined || (laneOnly && !r.drill) || (!laneOnly && r.drillOnly === true)) continue;
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
