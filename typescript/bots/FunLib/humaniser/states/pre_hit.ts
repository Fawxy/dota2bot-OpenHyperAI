/**
 * Ours.PreHit (slice pre-hit, `docs/team/slices/pre-hit.md` in the master repo): a core hits an enemy lane creep our tower is
 * attacking so that the tower then leaves it in the core's kill range. Under a tower the one-swing `lastHit` verb cannot win a
 * creep whose HP steps from above our hit to below zero in one tower hit. Two questions on the engine's `hpForecast`: will the
 * creep's HP ever sit in our kill range long enough for a swing to land there? If not, would one hit of ours now (low and
 * high damage roll alike) make such a window by the time our next swing can land? Pre-hit only on "no", then "yes". The
 * swing is laneFarm's `prehit` (one `attackAndConfirm`); the normal last-hit pick then takes the creep. A pre-hit never spends
 * the swing a last hit on another creep needs: none may come due before our attack is ready again (user 04/11/2026).
 */
import type * as Lib from "bots/FunLib/engine/tasks";
import { DamageType, Unit } from "bots/ts_libs/dota";
import * as Ours from "bots/FunLib/humaniser/ours";
import * as CoreLastHit from "bots/FunLib/humaniser/states/core_last_hit";
import * as LanePick from "bots/FunLib/humaniser/states/lane_pick";

/** Seconds of forecast: a pre-hit's landing plus one attack cycle (about 1.4-1.7 s early) plus the window after it. `judgement`. */
export const HORIZON = 3.5;
/** Forecast sampling step in seconds (under a frame at 30 fps is not needed: windows are judged against WINDOW_MIN). */
export const STEP = 0.05;
/**
 * The shortest kill window a swing is trusted to land in: about one body step (0.167 s in game) plus a little for the timing
 * the verb still gets wrong. `judgement`.
 */
export const WINDOW_MIN = 0.2;
/** Own towers within this of the bot are read for their attack target (tower range 700 plus the reach of a short walk). */
const TOWER_RADIUS = 1200;

/**
 * From `from` on (seconds from now), the forecast HP with an optional extra hit: `window` when it stays in (0, mine] for at
 * least WINDOW_MIN before it dies, `dead` when it reaches 0 with no such run, `open` when it is still above 0 at the horizon
 * with none (the forecast cannot say).
 */
export type Window = "window" | "dead" | "open";

export interface Extra {
    t: number;
    d: number;
}

export function WindowFrom(
    this: void,
    hpAt: (this: void, t: number) => number,
    horizon: number,
    mine: number,
    from: number,
    extra?: Extra,
): Window {
    let runStart: number | undefined;
    for (let t = from; t <= horizon + 1e-9; t += STEP) {
        const hp = hpAt(t) - (extra !== undefined && t >= extra.t ? extra.d : 0);
        if (hp <= 0) return runStart !== undefined && t - runStart >= WINDOW_MIN ? "window" : "dead";
        if (hp <= mine) {
            if (runStart === undefined) runStart = t;
            if (t - runStart >= WINDOW_MIN) return "window";
        } else runStart = undefined;
    }
    return "open";
}

/** Why a pre-hit was or was not chosen, for the snapshot's `lf` (`pr=`) and ev=prehit (`why`). */
export type Verdict = "go" | "window" | "open" | "kills" | "no-after" | "lh" | "phase" | "far";

/**
 * The two questions, on a forecast: `t0` our earliest landing (walk plus own hit time), `period` our attack cycle, `lo`/`hi`
 * our damage after armour at the low and high roll. The kill range is the low roll's (as the last-hit verb's `mine`).
 */
export function Decide(
    this: void,
    hpAt: (this: void, t: number) => number,
    horizon: number,
    t0: number,
    period: number,
    lo: number,
    hi: number,
): Verdict {
    const now = WindowFrom(hpAt, horizon, lo, t0);
    if (now === "window") return "window";
    if (now === "open") return "open";
    // A hit that would kill at t0 is a last hit, the last-hit verb's to take (it is also inside the window above at the low roll).
    if (hpAt(t0) <= hi) return "kills";
    for (const d of [lo, hi]) {
        if (WindowFrom(hpAt, horizon, lo, t0 + period, { t: t0, d }) !== "window") return "no-after";
    }
    return "go";
}

export function Applies(bot: Unit): boolean {
    return Ours.On("PreHit") && CoreLastHit.Applies(bot);
}

interface Note {
    verdict: Verdict;
    creep?: Lib.TaskCreep;
    hp?: number;
    t0?: number;
    lo?: number;
}
const notes: Record<number, Note | undefined> = {};

/** The decision's numbers for the ev=prehit of the pre-hit on `creep`, if it was this bot's last one. */
export function NoteOf(pid: number, creep: Lib.TaskCreep): Note | undefined {
    const n = notes[pid];
    return n !== undefined && n.creep === creep ? n : undefined;
}

/**
 * The pre-hit this core would make now, as a `prehit` LaneTarget, or undefined. Candidates: enemy lane creeps an own tower is
 * attacking, within a MAX_WALK walk. `verbs` is the engine bundle's Verbs (hpForecast, ownHitTime, laneTargets).
 */
export function Find(bot: Unit, verbs: typeof Lib.Verbs): Lib.Verbs.LaneTarget | undefined {
    if (!Applies(bot)) return undefined;
    const pid = bot.GetPlayerID();
    const me = bot as unknown as Lib.TaskUnit;
    let best: Lib.Verbs.LaneTarget | undefined;
    let note: Note | undefined;
    for (const tower of bot.GetNearbyTowers(TOWER_RADIUS, false) ?? []) {
        const target = tower.GetAttackTarget();
        if (target === undefined || target === null || !target.IsAlive() || target.GetTeam() === bot.GetTeam()) continue;
        if (!target.IsCreep() || target.IsHero()) continue;
        const creep = target as unknown as Lib.TaskCreep;
        const speed = math.max(100, bot.GetCurrentMovementSpeed());
        const walk = math.max(0, GetUnitToUnitDistance(bot, target) - bot.GetAttackRange()) / speed;
        if (walk > LanePick.MAX_WALK) {
            note = note ?? { verdict: "far" };
            continue;
        }
        const f = verbs.hpForecast(me, creep, HORIZON);
        if (f.unphasedTower) {
            note = { verdict: "phase", creep };
            continue;
        }
        const t0 = walk + verbs.ownHitTime(me, creep);
        const period = me.GetSecondsPerAttack?.() ?? 1.7;
        const variance = me.GetBaseDamageVariance?.() ?? 0;
        const lo = target.GetActualIncomingDamage(bot.GetAttackDamage() - variance, DamageType.Physical);
        const hi = target.GetActualIncomingDamage(bot.GetAttackDamage() + variance, DamageType.Physical);
        const hpAt = (t: number): number => verbs.forecastHp(f, t);
        let verdict = Decide(hpAt, HORIZON, t0, period, lo, hi);
        if (verdict === "go") {
            // Our attack is busy until t0 + period: a last hit on another creep due before then would be lost to it.
            for (const o of verbs.laneTargets(me, { within: t0 + period, deny: false })) {
                if (o.creep !== creep && LanePick.Reachable(o) && o.eta <= t0 + period) verdict = "lh";
            }
        }
        note = { verdict, creep, hp: f.hp, t0, lo };
        if (verdict !== "go") continue;
        let dies = math.huge;
        for (let t = 0; t <= HORIZON; t += STEP) {
            if (hpAt(t) <= 0) {
                dies = t;
                break;
            }
        }
        best = { creep, kind: "prehit", eta: walk, due: 0, walk, dies, ranged: LanePick.IsRanged(creep) };
        break;
    }
    if (note !== undefined) {
        notes[pid] = note;
        LanePick.NoteVerdict(pid, DotaTime(), note.verdict);
    }
    return best;
}
