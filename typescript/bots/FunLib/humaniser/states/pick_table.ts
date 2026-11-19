/**
 * Which kinds of lane creep target a hero goes for, in what order, and which creeps of each kind are its to take, as one table
 * for all five positions (the pick's counterpart of lane_table). Data only, no bot-side imports, so the picker
 * (states/lane_pick) and the claims (states/lane_claims) can both read it. A later behaviour changes what a position does by
 * editing a cell here, never by testing the position in code.
 *
 * Kill switches stay gates in code and the table says what happens with them on:
 * - Ours.CoreDenyYield gates `unattempted` on denies (off: every deny is taken), in lane_claims DenyYield.
 * - Ours.SupportLastHit (SupportDeny.LastHits) gates `unclaimed` on last hits (off: none is taken), in lane_claims Mine.
 * - States.Laning.LastHit listing a pos 4-5 makes it read position 1's column (laning ClaimPos).
 * - Ours.PreHit and CoreLastHit gate the pre-hit (pre_hit Applies), Ours.PreDeny and a forced shove the idle swing (idle_swing
 *   Applies); Ours.CoreContest gates the walk-in `far` (contest Applies). None changes a cell.
 */
export type Pos = 1 | 2 | 3 | 4 | 5;
export type PickKind = "lasthit" | "pre_hit" | "deny" | "idle_swing";
/** all: every creep of the kind. unclaimed: only one no allied core will take. unattempted: all but one an allied support's body is attempting. */
export type Claim = "all" | "unclaimed" | "unattempted" | "none";

export interface PickRow {
    kind: PickKind;
    /** Place in the position's order; undefined: this position never takes this kind. */
    rank: Record<Pos, number | undefined>;
    /** Which creeps of this kind are the position's to take. */
    claim: Record<Pos, Claim>;
    /** A wait on a creep of this kind is left for another of the same kind that is due now (lane_pick DUE_NOW, SWITCH_GAP). */
    retarget: boolean;
}

function by<T>(v1: T, v2: T, v3: T, v4: T, v5: T): Record<Pos, T> {
    return { 1: v1, 2: v2, 3: v3, 4: v4, 5: v5 };
}

export const PICKS: PickRow[] = [
    { kind: "lasthit", rank: by(10, 10, 10, 10, 10), claim: by("all", "all", "all", "unclaimed", "unclaimed"), retarget: true },
    { kind: "pre_hit", rank: by(20, 20, 20, undefined, undefined), claim: by("all", "all", "all", "none", "none"), retarget: false },
    { kind: "deny", rank: by(30, 30, 30, 30, 30), claim: by("unattempted", "unattempted", "unattempted", "all", "all"), retarget: false },
    { kind: "idle_swing", rank: by(40, 40, 40, 40, 40), claim: by("all", "all", "all", "all", "all"), retarget: false },
];

/** Whether a position (an ally's, read through lane_config PositionOf) is a core. Undefined is not. */
export function IsCore(this: void, pos: number | undefined): boolean {
    return pos !== undefined && pos >= 1 && pos <= 3;
}

export function RowOf(this: void, kind: PickKind): PickRow {
    for (const r of PICKS) if (r.kind === kind) return r;
    return PICKS[0];
}

export function ClaimOf(this: void, kind: PickKind, pos: Pos): Claim {
    return RowOf(kind).claim[pos];
}

/** Whether a wait on a creep of `kind` moves to another of the same kind (PickRow.retarget). */
export function Retargets(this: void, kind: PickKind): boolean {
    return RowOf(kind).retarget;
}

function build(pos: Pos): PickKind[] {
    const rows: PickRow[] = [];
    for (const r of PICKS) if (r.rank[pos] !== undefined) rows.push(r);
    table.sort(rows, (a, b) => (a.rank[pos] as number) < (b.rank[pos] as number));
    const out: PickKind[] = [];
    for (const r of rows) out.push(r.kind);
    return out;
}

const ORDERS: Record<number, PickKind[]> = {};
for (const p of [1, 2, 3, 4, 5] as const) ORDERS[p] = build(p);

/** The kinds a position takes, best first. An undefined or unknown position takes position 1's order. */
export function Order(this: void, pos: number | undefined): PickKind[] {
    return (pos !== undefined ? ORDERS[pos] : undefined) ?? ORDERS[1];
}
