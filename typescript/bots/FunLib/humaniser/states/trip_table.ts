/**
 * Which trips a hero's chooser (chooser.ts) may take, in what order, as one table for all five positions (the trips'
 * counterpart of pick_table). Data only, no bot-side imports, so every job module can import it without a cycle. A later
 * behaviour changes what a position does by editing a cell here, never by testing the position in code.
 *
 * Kill switches and non-position conditions stay gates in code and the table says what happens with them on:
 * - Ours.DoubleStack gates position 4's stack (stack_job Applies); the cell is the rank once it is on.
 * - Ours.CorePull gates the offlane's pull and one puller per lane is chosen (pull_job Applies); Ours.SupportPull,
 *   SupportPullFarm, RuneRotation, CampTrip and the other job switches gate their jobs the same way. None changes a cell.
 * - A job's own situation (a claim open, a window due) decides whether it wants the hero now; the table only orders the
 *   jobs that apply.
 */
import type { Pos } from "bots/FunLib/humaniser/states/pick_table";

export type { Pos };
/** The chooser's job names; logs and other modules read them. */
export type TripKind = "stack" | "rune" | "pull" | "pullfarm" | "camp";

export interface TripRow {
    kind: TripKind;
    /** Place in the position's order, lower wins; undefined: this position never does this trip. */
    rank: Record<Pos, number | undefined>;
    /** The place while the job says its situation lift holds (pull_job Lifted); only the pull has one. */
    lifted?: Record<Pos, number | undefined>;
}

function by<T>(v1: T, v2: T, v3: T, v4: T, v5: T): Record<Pos, T> {
    return { 1: v1, 2: v2, 3: v3, 4: v4, 5: v5 };
}

export const TRIPS: TripRow[] = [
    { kind: "pull", rank: by(undefined, undefined, 30, 30, 30), lifted: by(undefined, undefined, 10, 10, 10) },
    { kind: "rune", rank: by(undefined, undefined, undefined, 15, 50) },
    { kind: "stack", rank: by(undefined, undefined, undefined, 20, 20) },
    { kind: "pullfarm", rank: by(undefined, undefined, 40, 40, 40) },
    { kind: "camp", rank: by(60, 60, 60, undefined, undefined) },
];

function rowOf(kind: TripKind): TripRow | undefined {
    for (const r of TRIPS) if (r.kind === kind) return r;
    return undefined;
}

function isPos(pos: number | undefined): pos is Pos {
    return pos !== undefined && pos >= 1 && pos <= 5 && pos === math.floor(pos);
}

/** The trip's place for a position (the lifted column when `lifted` and the row has one); undefined: never, or no position. */
export function RankOf(this: void, kind: TripKind, pos: number | undefined, lifted?: boolean): number | undefined {
    const row = rowOf(kind);
    if (row === undefined || !isPos(pos)) return undefined;
    if (lifted === true && row.lifted !== undefined) return row.lifted[pos];
    return row.rank[pos];
}

export function Does(this: void, kind: TripKind, pos: number | undefined): boolean {
    return RankOf(kind, pos) !== undefined;
}

/** The trips a position does, best first; `lifted` says per kind whether its lifted column applies. */
export function Order(this: void, pos: number | undefined, lifted: (kind: TripKind) => boolean): TripKind[] {
    const rows: [TripKind, number][] = [];
    for (const r of TRIPS) {
        const rank = RankOf(r.kind, pos, lifted(r.kind));
        if (rank !== undefined) rows.push([r.kind, rank]);
    }
    table.sort(rows, (a, b) => a[1] < b[1]);
    const out: TripKind[] = [];
    for (const r of rows) out.push(r[0]);
    return out;
}
