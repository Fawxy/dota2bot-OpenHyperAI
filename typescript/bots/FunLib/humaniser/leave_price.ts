/**
 * The priced leave (decision centre pilot steps 2 and 3, `Ours.PricedLeave`; master docs/proposals/decision-centre/step2-3-decider.md
 * s5): in scope (an exchange, a play or an ally's exchange on a target T), stay or leave by the price of each over the next `HORIZON`
 * seconds, from the fitted prices and tables in `dc_prices.ts`. PURE so far: `Decide` takes plain values and returns the pick with the
 * fields of its `ev=choice kind=leave` line. Gathering the inputs, the incumbent per hero and the wiring into the retreat come later.
 */
import * as P from "bots/FunLib/humaniser/dc_prices";

export const SETTINGS = {
    /**
     * The incumbent margin (gold): an incumbent stay keeps staying while stay - leave > -Margin, an incumbent leave turns to stay only
     * when stay - leave > Margin. A tenth of a death price. judgement.
     */
    Margin: 30,
    /** Creeps a second dying in a lane when the lane read has no live wave count (four a 30 s wave). */
    CreepRate: 4 / 30,
};

export type Pick = "stay" | "leave";

/** What `Decide` reads, as plain values (the gatherer reads the game; nothing here does). */
export interface Inputs {
    /** Our HP, percent of max. */
    hp: number;
    /** Enemy heroes hitting us: attack target us within 1,600, plus those whose damage hit us in the last 1 s, each once. */
    hs: number;
    /** The target's HP, percent of max. */
    thp: number;
    /** Our alive heroes within `REACH` of the target, us included. */
    n: number;
    /** Walk to our nearest standing tower (units). */
    w: number;
    /** Our current move speed. */
    ms: number;
    /** Our position 1 to 5 (the conversion's row). */
    pos: number;
    /** Gold (before conversion) of the enemy lane creeps within our attack range + 300 that die within the horizon. */
    cg: number;
    /** Creeps a second dying in our lane (`SETTINGS.CreepRate` when unknown). */
    lam?: number;
    /** Hard leaves: a tower on us, the heal rule, burst now. */
    tower?: boolean;
    heal?: boolean;
    burst?: boolean;
    /** A real change this frame (n or the enemies in reach changed, `hs` changed bin, T died or was lost, the scope changed, an exchange or play started or ended): the margin is 0. */
    rel?: boolean;
}

/** The pick and every value of the `ev=choice kind=leave` line. Prices are absent on a hard leave. */
export interface Result {
    pick: Pick;
    /** `tower`, `heal` or `burst` on a hard leave. */
    hard?: string;
    inc?: Pick;
    rel: number;
    /** The margin used. */
    M: number;
    stay?: number;
    leave?: number;
    /** stay - leave. */
    d?: number;
    /** P(kill) on stay (n heroes) and on leave (n - 1). */
    pks?: number;
    pkl?: number;
    /** P(death) on stay and on leave. */
    pds?: number;
    pdl?: number;
    /** Farm in reach on stay (missed on leave; counted once), and the walk back's lost farm on leave. */
    F?: number;
    W?: number;
}

const hpBin = (hp: number): number => Math.max(0, Math.min(4, Math.floor(hp / 20)));

/** P(T dies within the horizon) with `n` of our heroes in reach of it (0: none). */
export function PKill(thp: number, n: number): number {
    if (n <= 0) return 0;
    return P.KILL_STAY.p[hpBin(thp) * 2 + (n >= 2 ? 1 : 0)];
}

/** P(we die) on a stay: our HP bin x hitting state (0 near, 1 poked, 2+ committed). */
export function PDeathStay(hp: number, hs: number): number {
    return P.DEATH_STAY.p[hpBin(hp) * 3 + Math.min(2, Math.max(0, hs))];
}

/** P(we die) on a leave: our HP bin x (committed or not) x walk bin (< 1,500, to 3,000, beyond). */
export function PDeathLeave(hp: number, hs: number, w: number): number {
    const wb = w < 1500 ? 0 : w <= 3000 ? 1 : 2;
    return P.DEATH_LEAVE.p[hpBin(hp) * 6 + (hs >= 2 ? 3 : 0) + wb];
}

const conv = (pos: number): number => P.CONVERSION[Math.max(1, Math.min(5, pos)) - 1];

/** Farm in reach on a stay: the conversion times the creeps' gold. */
export function Farm(pos: number, cg: number): number {
    return conv(pos) * cg;
}

/** Farm lost to the walk back on a leave: the round trip beyond the horizon at the lane's creep rate. */
export function Walk(pos: number, w: number, ms: number, lam: number): number {
    const back = Math.max(0, (2 * w) / Math.max(ms, 100) - P.HORIZON);
    return conv(pos) * P.LASTHIT * lam * back;
}

/**
 * Stay or leave. Hard leaves first (tower, heal, burst), with no price. Else stay = P_k(T, n) K + F - P_ds D, leave = P_k(T, n - 1) K
 * - W - P_dl D, d = stay - leave; an incumbent stay keeps staying while d > -M, an incumbent leave stays only when d > M, no
 * incumbent picks the larger. M is `SETTINGS.Margin`, 0 on a real change (`i.rel`).
 */
export function Decide(i: Inputs, inc?: Pick): Result {
    const rel = i.rel === true ? 1 : 0;
    const hard = i.tower === true ? "tower" : i.heal === true ? "heal" : i.burst === true ? "burst" : undefined;
    if (hard !== undefined) return { pick: "leave", hard, inc, rel, M: 0 };
    const M = rel === 1 ? 0 : SETTINGS.Margin;
    const pks = PKill(i.thp, i.n);
    const pkl = PKill(i.thp, i.n - 1);
    const pds = PDeathStay(i.hp, i.hs);
    const pdl = PDeathLeave(i.hp, i.hs, i.w);
    const F = Farm(i.pos, i.cg);
    const W = Walk(i.pos, i.w, i.ms, i.lam ?? SETTINGS.CreepRate);
    const stay = pks * P.KILL + F - pds * P.DEATH;
    const leave = pkl * P.KILL - W - pdl * P.DEATH;
    const d = stay - leave;
    let pick: Pick;
    if (inc === "stay") pick = d > -M ? "stay" : "leave";
    else if (inc === "leave") pick = d > M ? "stay" : "leave";
    else pick = d > 0 ? "stay" : "leave";
    return { pick, inc, rel, M, stay, leave, d, pks, pkl, pds, pdl, F, W };
}
