/**
 * The priced leave in the game (decision centre pilot step 2 part B; master docs/proposals/decision-centre/step2-3-decider.md s2, s3,
 * s5, s6 and the direction log): the scope, the gather of `LeavePrice.Decide`'s inputs, the incumbent per hero, and one
 * `ev=choice kind=leave` line per decision. Kept apart from the pure `leave_price.ts` so the replay loads only the rule.
 *
 * Priced: only a `threat` answer of the leave rule (kill line from ratio `Safe.BARS.hold` to the bar), and its hit back or join holds
 * (the same band). Hard leaves, no price: a tower on us, the heal rule, burst now, and `lethal` (under the hold ratio: the replay found
 * the tables blind there). Outside the scope or the band `For` answers nothing and the leave rule decides as before.
 */
import { DamageType, Tower, Unit, UnitType } from "bots/ts_libs/dota";
import * as Commit from "bots/FunLib/humaniser/commit";
import * as SpellReady from "bots/FunLib/humaniser/spell_ready";
import * as LeavePrice from "bots/FunLib/humaniser/leave_price";
import * as P from "bots/FunLib/humaniser/dc_prices";
import * as LaneConfig from "bots/FunLib/humaniser/lane_config";
import * as Ours from "bots/FunLib/humaniser/ours";
import * as Telemetry from "bots/FunLib/humaniser/telemetry";
import * as Trade from "bots/FunLib/humaniser/states/trade";
import * as Plays from "bots/FunLib/humaniser/plays/plays";

export const SETTINGS = {
    /** An ally in a running exchange counts when within this of us, and its target too (design s11 "can join"). */
    JoinReach: 1200,
    /** Enemies whose attack target is us count towards `hs` within this (the fit's 1,600). */
    HitReach: 1600,
    /** The callback's hit window for `hs` (s): the fit read one second. */
    HitWindow: 1,
    /** Enemy lane creeps count towards the farm within our attack range plus this. */
    FarmPad: 300,
    /** In scope with no change, a line at most this often per hero (s). */
    LogEvery: 2,
    /** The enemy wave the farm read prices: lane creeps within this of us (the creeps in reach die among them). */
    WaveReach: 1200,
    /** A lane creep, tower or hero engages the wave within its attack range plus both hulls plus this. judgement. */
    EngagePad: 150,
    /** Burst now reads only the enemies within this of us (cheaper than reading every visible enemy's spells). */
    BurstScan: 1600,
    /** The target unseen (or the scope lost) for at most this long keeps the incumbent (s); longer is a real change. */
    LostGrace: 1,
};

const TOWER_IDS = [Tower.Top1, Tower.Top2, Tower.Top3, Tower.Mid1, Tower.Mid2, Tower.Mid3, Tower.Bot1, Tower.Bot2, Tower.Bot3, Tower.Base1, Tower.Base2];

/** What the leave rule (`Retreat.LeaveWhy`) answered, as `For` reads it (no import of the retreat). */
export interface LeaveAnswer {
    why?: string;
    stay?: string;
}

export type ScopeCase = "trade" | "play" | "ally";

/** The gathered inputs, the scope and what the line carries beside them. */
export interface Gathered extends LeavePrice.Inputs {
    sc: ScopeCase;
    tpid: number;
    /** Step 1's hitter count (3 s), beside `hs`. */
    nh?: number;
    /** Visible enemy heroes within REACH of us. */
    ne: number;
    /** The farm read's creeps in reach and those due (FarmRead), and burst now's sum (BurstNow), where read. */
    cn?: number;
    cd?: number;
    bsum?: number;
}

export interface Pick extends LeavePrice.Result {
    g: Gathered;
}

interface HeroState {
    lw?: LeaveAnswer;
    /** What `For` answered for `lw`: a second caller with the same answer in the frame gets the same (smoke dc-step2-smoke2: out of
     *  the band in the grace, LeaveNow got nothing and Desire then the incumbent's stale leave pick, 23 `why=priced` starts with no line). */
    ans?: Pick;
    /** The last decision (the incumbent's pick, which the grace keeps in the band). */
    res?: Pick;
    inc?: LeavePrice.Pick;
    key?: string;
    tpid?: number;
    /** When the scope or band was first lost since the last in-scope decision. */
    lostAt?: number;
    loggedPick?: string;
    loggedAt?: number;
}

const states: Record<number, HeroState | undefined> = {};

export function ResetCache(): void {
    for (const k of Object.keys(states)) delete states[k as unknown as number];
}

/** The incumbent is forgotten (an episode started or ended outside the decider's sight, in shadow). */
export function Forget(bot: Unit): void {
    states[bot.GetPlayerID()] = undefined;
}

/**
 * An episode ended under Act: the incumbent stays (the margin), but the last pick no longer answers in the grace, so no stale leave
 * starts the next episode, and the next decision writes its line (a start always has its `ev=choice`).
 */
export function Ended(bot: Unit): void {
    const st = states[bot.GetPlayerID()];
    if (st === undefined) return;
    st.res = undefined;
    st.ans = undefined;
    st.lw = undefined;
    st.loggedPick = undefined;
}

/** The pick acts (`Ours.PricedLeaveAct`, which needs `Ours.PricedLeave`). */
export function Acts(): boolean {
    return Ours.On("PricedLeave") && Ours.On("PricedLeaveAct");
}

function seen(u: Unit | undefined | null): u is Unit {
    return u !== null && u !== undefined && !u.IsNull() && u.IsAlive() && u.CanBeSeen() && u.GetLocation() !== undefined;
}

/** The scope (s2), in order: our own exchange's target, our play's target, an ally's exchange target within JoinReach of us. */
export function ScopeOf(bot: Unit): { sc: ScopeCase; t: Unit } | undefined {
    if (Trade.Running(bot)) {
        const t = Trade.EpisodeOf(bot.GetPlayerID())?.target;
        if (seen(t)) return { sc: "trade", t };
    }
    const play = Plays.Of(bot);
    if (play !== undefined && seen(play.target)) return { sc: "play", t: play.target };
    for (const a of GetUnitList(UnitType.AlliedHeroes) ?? []) {
        if (!seen(a) || a === bot || a.IsIllusion() || GetUnitToUnitDistance(bot, a) > SETTINGS.JoinReach || !Trade.Running(a)) continue;
        const t = Trade.EpisodeOf(a.GetPlayerID())?.target;
        if (seen(t) && GetUnitToUnitDistance(bot, t) <= SETTINGS.JoinReach) return { sc: "ally", t };
    }
    return undefined;
}

function creepKind(name: string): string {
    if (string.find(name, "siege", 1, true)[0] !== undefined) return "siege";
    if (string.find(name, "ranged", 1, true)[0] !== undefined) return "ranged";
    if (string.find(name, "flag", 1, true)[0] !== undefined) return "flag";
    return "melee";
}

const spa = (u: Unit): number => math.max(0.2, (u as Unit & { GetSecondsPerAttack?(): number }).GetSecondsPerAttack?.() ?? 1.7);

/**
 * Pure: which of a wave's creeps die within `h` seconds under `dps` (their effective HP, after armour), lowest first: the k lowest
 * whose summed HP the wave's damage over the horizon covers. A per-creep "its current attackers kill it" read missed nearly every
 * death (smoke dc-step2: cg 0 on 18 of 19 lines), as lane creeps switch targets and focus the low ones.
 */
export function Due(ehp: number[], dps: number, h: number): boolean[] {
    const order: number[] = [];
    for (let i = 0; i < ehp.length; i++) order.push(i);
    order.sort((a, b) => ehp[a] - ehp[b]);
    const out: boolean[] = [];
    for (let i = 0; i < ehp.length; i++) out.push(false);
    let left = dps * h;
    for (const i of order) {
        if (ehp[i] > left) break;
        left -= ehp[i];
        out[i] = true;
    }
    return out;
}

export interface Farm {
    /** Gold (before conversion) of the creeps in reach due to die within the horizon. */
    gold: number;
    /** Enemy lane creeps in reach (our attack range + FarmPad, the fit's and replay's reach). */
    cn: number;
    /** Of them, due to die. */
    cd: number;
}

function towersOf(team: number): Unit[] {
    const out: Unit[] = [];
    for (const id of TOWER_IDS) {
        const tw = GetTower(team, id);
        if (tw !== null && tw !== undefined && !tw.IsNull() && tw.IsAlive()) out.push(tw);
    }
    return out;
}

/**
 * The farm read the fit and the replay priced (step0-price-fit.md "Farm in reach"; replay.js): enemy lane creeps within our attack
 * range + FarmPad that die within the horizon, by anyone, at the last-hit price by kind; `Farm` takes the conversion. Due: the
 * enemy wave within WaveReach of us, under the damage of our lane creeps and towers engaging it (within their range + hulls +
 * EngagePad of one of its creeps) and our heroes attacking a creep, lowest HP first (`Due`).
 */
export function FarmRead(bot: Unit): Farm {
    const reach = bot.GetAttackRange() + SETTINGS.FarmPad;
    const wave: Unit[] = [];
    for (const c of bot.GetNearbyLaneCreeps(SETTINGS.WaveReach, true) ?? []) if (seen(c)) wave.push(c);
    const out: Farm = { gold: 0, cn: 0, cd: 0 };
    if (wave.length === 0) return out;
    const inReach: boolean[] = [];
    for (const c of wave) {
        const r = GetUnitToUnitDistance(bot, c) <= reach;
        inReach.push(r);
        if (r) out.cn++;
    }
    if (out.cn === 0) return out;
    let dps = 0;
    const engages = (u: Unit): boolean => {
        const r = u.GetAttackRange() + u.GetBoundingRadius() + SETTINGS.EngagePad;
        for (const c of wave) if (GetUnitToUnitDistance(u, c) <= r + c.GetBoundingRadius()) return true;
        return false;
    };
    const attackers: Unit[] = [];
    for (const c of bot.GetNearbyLaneCreeps(SETTINGS.WaveReach, false) ?? []) if (seen(c)) attackers.push(c);
    for (const tw of towersOf(bot.GetTeam())) if (GetUnitToUnitDistance(bot, tw) <= SETTINGS.WaveReach + 700) attackers.push(tw);
    for (const u of attackers) if (engages(u)) dps += u.GetAttackDamage() / spa(u);
    for (const a of GetUnitList(UnitType.AlliedHeroes) ?? []) {
        if (!seen(a) || a.IsIllusion() || GetUnitToUnitDistance(bot, a) > SETTINGS.WaveReach) continue;
        const t = a.GetAttackTarget();
        if (t !== null && t !== undefined && !t.IsNull() && !t.IsHero() && engages(a)) dps += a.GetAttackDamage() / spa(a);
    }
    const ehp: number[] = [];
    for (const c of wave) ehp.push(c.GetHealth() / math.max(0.05, c.GetActualIncomingDamage(100, DamageType.Physical) / 100));
    const due = Due(ehp, dps, P.HORIZON);
    for (let i = 0; i < wave.length; i++) {
        if (!inReach[i] || !due[i]) continue;
        out.cd++;
        out.gold += P.LASTHIT_BY_KIND[creepKind(wave[i].GetUnitName())] ?? P.LASTHIT;
    }
    return out;
}

/**
 * Burst now (a hard leave): the ready spells and one attack of the enemies in reach land on us before we react, and their sum
 * reaches our HP. A spell counts only when castable (learned, shown, off cooldown: IsFullyCastable, which follows an enemy's own
 * cooldown and mana; its mana cost read too) and we are within its cast range (or radius) plus both hulls plus what the enemy closes
 * in `Commit.SETTINGS.ReactWindow`; the attack likewise within its attack range. Enemies beyond BurstScan are not read. Smoke
 * dc-step2: every `why=priced` start was a burst leave over a hit back (Valve's estimate counts every spell at any distance).
 */
export function BurstNow(bot: Unit): { burst: boolean; sum: number } {
    const win = Commit.SETTINGS.ReactWindow;
    let sum = 0;
    for (const e of GetUnitList(UnitType.EnemyHeroes) ?? []) {
        if (!seen(e) || e.IsIllusion()) continue;
        const d = GetUnitToUnitDistance(bot, e);
        if (d > SETTINGS.BurstScan) continue;
        const pad = bot.GetBoundingRadius() + e.GetBoundingRadius() + e.GetCurrentMovementSpeed() * win;
        const mana = e.GetMana();
        for (const s of SpellReady.ReadySpells(e)) {
            if (s.mana !== undefined && s.mana > mana) continue;
            if (s.cd !== undefined && s.cd > 0) continue;
            if (d > s.range + pad) continue;
            sum += bot.GetActualIncomingDamage(s.dmg, s.dtype);
        }
        if (d <= e.GetAttackRange() + pad) sum += bot.GetActualIncomingDamage(e.GetAttackDamage(), DamageType.Physical);
    }
    return { burst: sum >= bot.GetHealth(), sum };
}

function walk(bot: Unit): number {
    let best = math.huge;
    for (const tw of towersOf(bot.GetTeam())) best = math.min(best, GetUnitToUnitDistance(bot, tw));
    return best === math.huge ? 10000 : best;
}

/** The decider's inputs at the fit's reach (s3); undefined outside the scope. */
export function Gather(bot: Unit, lw: LeaveAnswer): Gathered | undefined {
    const s = ScopeOf(bot);
    if (s === undefined) return undefined;
    const pid = bot.GetPlayerID();
    const by: Record<number, boolean> = {};
    let hs = 0;
    let ne = 0;
    for (const e of GetUnitList(UnitType.EnemyHeroes) ?? []) {
        if (!seen(e) || e.IsIllusion()) continue;
        const d = GetUnitToUnitDistance(bot, e);
        if (d <= P.REACH) ne++;
        if (d <= SETTINGS.HitReach && e.GetAttackTarget() === bot && by[e.GetPlayerID()] !== true) {
            by[e.GetPlayerID()] = true;
            hs++;
        }
    }
    for (const epid of Commit.HitterIds(pid, SETTINGS.HitWindow)) {
        if (by[epid] === true) continue;
        by[epid] = true;
        hs++;
    }
    let n = 1;
    for (const a of GetUnitList(UnitType.AlliedHeroes) ?? []) {
        if (!seen(a) || a === bot || a.IsIllusion()) continue;
        if (GetUnitToUnitDistance(a, s.t) <= P.REACH) n++;
    }
    const hp = (100 * bot.GetHealth()) / math.max(1, bot.GetMaxHealth());
    const g: Gathered = {
        sc: s.sc,
        tpid: s.t.GetPlayerID(),
        nh: Commit.Nh(pid),
        ne,
        hp,
        hs,
        thp: (100 * s.t.GetHealth()) / math.max(1, s.t.GetMaxHealth()),
        n,
        w: walk(bot),
        ms: bot.GetCurrentMovementSpeed(),
        pos: LaneConfig.PositionOf(bot) ?? 3,
        cg: 0,
        tower: lw.why === "tower",
        heal: lw.why === "heal",
        lethal: lw.why === "lethal",
    };
    // Burst now and the farm only where a price is asked (their reads loop over units).
    if (!g.tower && !g.heal && !g.lethal) {
        const b = BurstNow(bot);
        g.burst = b.burst;
        g.bsum = b.sum;
        if (!g.burst) {
            const f = FarmRead(bot);
            g.cg = f.gold;
            g.cn = f.cn;
            g.cd = f.cd;
        }
    }
    return g;
}

const r1 = (x: number | undefined): number | undefined => (x === undefined ? undefined : math.floor(x * 10 + 0.5) / 10);
const r3 = (x: number | undefined): number | undefined => (x === undefined ? undefined : math.floor(x * 1000 + 0.5) / 1000);

/** The leave rule's answer in the priced band (a threat leave or its holds), or a hard leave. */
function inBand(lw: LeaveAnswer): boolean {
    return lw.why === "threat" || lw.why === "tower" || lw.why === "heal" || lw.why === "lethal" || lw.stay === "join" || lw.stay === "hitback";
}

function log(bot: Unit, st: HeroState, r: Pick, act: boolean, now: number): void {
    const tag = r.hard ?? r.pick;
    if (st.loggedPick === tag && r.rel === 0 && st.loggedAt !== undefined && now - st.loggedAt < SETTINGS.LogEvery) return;
    st.loggedPick = tag;
    st.loggedAt = now;
    const g = r.g;
    Telemetry.Event("choice", [
        ["pid", bot.GetPlayerID()],
        ["kind", "leave"],
        ["pick", r.pick],
        ["act", act ? 1 : 0],
        ["hard", r.hard],
        ["inc", r.inc],
        ["rel", r.rel],
        ["mg", r.M],
        ["sc", g.sc],
        ["tpid", g.tpid],
        ["lw", st.lw?.why ?? st.lw?.stay],
        ["hp", r1(g.hp)],
        ["hs", g.hs],
        ["nh", g.nh],
        ["ne", g.ne],
        ["thp", r1(g.thp)],
        ["n", g.n],
        ["w", math.floor(g.w)],
        ["spd", math.floor(g.ms)],
        ["pos", g.pos],
        ["cg", r1(g.cg)],
        ["cin", g.cn],
        ["cdue", g.cd],
        ["bsum", g.bsum === undefined ? undefined : math.floor(g.bsum)],
        ["sv", r1(r.stay)],
        ["lv", r1(r.leave)],
        ["d", r1(r.d)],
        ["pks", r3(r.pks)],
        ["pkl", r3(r.pkl)],
        ["pds", r3(r.pds)],
        ["pdl", r3(r.pdl)],
        ["fm", r1(r.F)],
        ["wk", r1(r.W)],
    ]);
}

/**
 * The priced pick for this hero given the leave rule's answer `lw`, decided once per answer (the retreat refreshes it with its read,
 * at most every `Retreat.SETTINGS.ReadEvery`): whichever caller asks first in the frame decides and the other reads it. Undefined
 * outside the scope or the band, which forgets the incumbent. The first incumbent is the leave rule's answer. Logs the line.
 */
export function For(bot: Unit, lw: LeaveAnswer): Pick | undefined {
    const pid = bot.GetPlayerID();
    let st = states[pid];
    if (st !== undefined && st.lw === lw) return st.ans;
    const now = DotaTime();
    const band = inBand(lw);
    const g = band ? Gather(bot, lw) : undefined;
    if (g === undefined) {
        // Out of scope or band for at most LostGrace with the target alive (unseen for a read, the band flickering): the incumbent
        // stays, and in the band its pick stands. The target's death or a longer loss forgets it.
        if (st !== undefined && st.inc !== undefined && st.tpid !== undefined && IsHeroAlive(st.tpid)) {
            st.lostAt = st.lostAt ?? now;
            if (now - st.lostAt <= SETTINGS.LostGrace) {
                st.lw = lw;
                st.ans = band ? st.res : undefined;
                return st.ans;
            }
        }
        states[pid] = { lw };
        return undefined;
    }
    if (st === undefined || st.inc === undefined) st = { inc: lw.why !== undefined ? "leave" : "stay" };
    st.lw = lw;
    st.lostAt = undefined;
    st.tpid = g.tpid;
    // A real change (margin 0): the scope case, the target, or our heroes in reach of it. Not `hs` or the enemies in reach: they
    // flicker read to read (smoke dc-step2) and the prices already read them.
    const key = `${g.sc}|${g.tpid}|${math.min(g.n, 2)}`;
    g.rel = st.key !== undefined && st.key !== key;
    st.key = key;
    const r: Pick = { ...LeavePrice.Decide(g, st.inc), g };
    st.inc = r.pick;
    st.res = r;
    st.ans = r;
    states[pid] = st;
    log(bot, st, r, Acts(), DotaTime());
    return r;
}
