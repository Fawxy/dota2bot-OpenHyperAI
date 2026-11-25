/**
 * Which trips a hero's chooser (chooser.ts) may take, in what order, as one table for all five positions. Data only, no
 * bot-side imports, so every job module can import it without a cycle. A later
 * behaviour changes what a position does by editing a cell here, never by testing the position in code.
 *
 * Kill switches and non-position conditions stay gates in code and the table says what happens with them on:
 * - Ours.DoubleStack gates position 4's stack (stack_job Applies); the cell is the rank once it is on.
 * - The pull is the decider's row, not a chooser job: its row here says only which positions pull (one puller per lane is
 *   chosen in pull_job). Ours.RuneRotation and the other job switches gate their jobs in code. None changes a cell.
 * - The creep offer (creep_offer, a logging shadow for now) is no chooser job: its row says only which positions it reads.
 * - A job's own situation (a claim open, a window due) decides whether it wants the hero now; the table only orders the
 *   jobs that apply.
 */
export type Pos = 1 | 2 | 3 | 4 | 5;
/** The chooser's job names; logs and other modules read them. */
export type TripKind = "stack" | "rune" | "pull" | "creep";

export interface TripRow {
    kind: TripKind;
    /** Place in the position's order, lower wins; undefined: this position never does this trip. */
    rank: Record<Pos, number | undefined>;
}

function by<T>(v1: T, v2: T, v3: T, v4: T, v5: T): Record<Pos, T> {
    return { 1: v1, 2: v2, 3: v3, 4: v4, 5: v5 };
}

export const TRIPS: TripRow[] = [
    { kind: "pull", rank: by(undefined, undefined, undefined, 30, 30) },
    { kind: "rune", rank: by(undefined, undefined, undefined, 15, 50) },
    { kind: "stack", rank: by(undefined, undefined, undefined, 20, 20) },
    { kind: "creep", rank: by(60, 60, 60, undefined, undefined) },
];

function rowOf(kind: TripKind): TripRow | undefined {
    for (const r of TRIPS) if (r.kind === kind) return r;
    return undefined;
}

function isPos(pos: number | undefined): pos is Pos {
    return pos !== undefined && pos >= 1 && pos <= 5 && pos === math.floor(pos);
}

/** The trip's place for a position; undefined: never, or no position. */
export function RankOf(this: void, kind: TripKind, pos: number | undefined): number | undefined {
    const row = rowOf(kind);
    if (row === undefined || !isPos(pos)) return undefined;
    return row.rank[pos];
}

export function Does(this: void, kind: TripKind, pos: number | undefined): boolean {
    return RankOf(kind, pos) !== undefined;
}

/** The trips a position does, best first. */
export function Order(this: void, pos: number | undefined): TripKind[] {
    const rows: [TripKind, number][] = [];
    for (const r of TRIPS) {
        const rank = RankOf(r.kind, pos);
        if (rank !== undefined) rows.push([r.kind, rank]);
    }
    table.sort(rows, (a, b) => a[1] < b[1]);
    const out: TripKind[] = [];
    for (const r of rows) out.push(r[0]);
    return out;
}
