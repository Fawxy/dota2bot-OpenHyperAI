/**
 * Swing probe (`Overrides.SwingProbe`, probe games only; slice oha-deny-free step 1, user 24/11/2026): can the API say which
 * lane creep an own hero's attack will land on, and when? The lane read (step 2) needs that for every hero of our team in a
 * lane, so the support can skip, join or take a deny; if it cannot be read, the slice stops there.
 *
 * Each frame, once per team VM, every hero of the team (GetTeamMember 1..5) whose attack target is a lane creep and who is
 * winding up (GetAnimActivity ATTACK or ATTACK2, anim cycle before the attack point) starts one record. The prediction is the
 * engine's own formula (engine `windupLeft`/`windupLanding`, UNVERIFIED there): fire at (attack point - anim cycle) x seconds
 * per attack (`pf`), and beside it `pf2`, the attack point as seconds over GetAttackSpeed (the engine's cooldownLeft reading;
 * swingprobe1: `pf` fired 0.25 s early for melee heroes, first seen at anim cycle 0), a ranged hero's hit landing the projectile's flight later (distance less the launch offset, over projectile
 * speed). The record is followed to its truth, read from the game and not from the prediction:
 *   fire   GetLastAttackTime rising (the attack point passed; a melee hit lands then);
 *   land   melee: the fire; ranged: the frame the hero's attack projectile, once seen in the creep's
 *          GetIncomingTrackingProjectiles, is gone;
 *   drop   the target's HP lost from the frame before the landing to the landing frame (others' hits in the same frame
 *          add to it: compare with `dmg`, the hero's attack after the creep's armour);
 *   kill   the hero's last hits or denies rose by the frame after the landing.
 * One `ev=swing_probe` line per record, at its end (`end`: `land`, `cancel` the wind-up stopped unfired, `retarget` the
 * attack target changed before the fire, `gone` the creep died or vanished before the landing, `lost` nothing by GIVE_UP).
 * `wc` (slice oha-engine-windup): records also for the team's towers and up to CREEP_RECORDS of its lane creeps at a time
 * (`kind`, `aid`; their `kill` is 0), and the anim cycle on every frame before the fire, to fit GetAnimCycle mid-wind-up; a
 * record ends `cancel` only when the attack activity stops (not when the cycle passes the attack point).
 * Reads and logs only: no order. Runs under pcall (a probe error is silent: a run is judged by its row counts).
 */
import { Unit, UnitType } from "bots/ts_libs/dota";
import * as Overrides from "bots/FunLib/humaniser/overrides";
import * as Telemetry from "bots/FunLib/humaniser/telemetry";

declare const DAMAGE_TYPE_PHYSICAL: number | undefined;

/** The attack animations (engine lasthit.ts). */
const ACTIVITY_ATTACK = 1503;
const ACTIVITY_ATTACK2 = 1504;
/** Above this attack range a hero attacks with a projectile (engine lasthit.ts). */
const RANGED_ABOVE = 320;
/** A ranged projectile lands this far short of the creep's centre (engine lasthit.ts). */
const CREEP_LAUNCH_OFFSET = 22;
/** Seconds after first sight with no landing: the record ends `lost`. `judgement`: past any hero's wind-up plus flight. */
const GIVE_UP = 3;

/** Reads the probe takes that the typed Unit does not declare. */
interface Swinger {
    IsNull(): boolean;
    IsHero(): boolean;
    IsTower(): boolean;
    IsAlive(): boolean;
    IsIllusion(): boolean;
    GetPlayerID(): number;
    GetLocation(): { x: number; y: number };
    GetAttackTarget(): unknown;
    GetAnimActivity(): number;
    GetAnimCycle(): number;
    GetAttackPoint(): number;
    GetSecondsPerAttack(): number;
    GetAttackSpeed(): number;
    GetAttackRange(): number;
    GetAttackProjectileSpeed(): number;
    GetAttackDamage(): number;
    GetLastAttackTime(): number;
    GetLastHits(): number;
    GetDenies(): number;
}
interface Target {
    IsNull(): boolean;
    IsAlive(): boolean;
    IsCreep(): boolean;
    GetTeam(): number;
    GetUnitName(): string;
    GetHealth(): number;
    GetLocation(): { x: number; y: number };
    GetActualIncomingDamage(dmg: number, kind: number): number;
    GetIncomingTrackingProjectiles(): { caster: unknown; is_attack: boolean; location: { x: number; y: number } }[] | undefined;
}

interface Swing {
    h: Swinger;
    /** `hero`, `creep` (a lane creep of ours) or `tower` (ours). */
    kind: string;
    c: Target;
    cid: number;
    own: number;
    ranged: boolean;
    t0: number;
    cyc: number;
    pt: number;
    spa: number;
    pf: number;
    pl: number;
    aspd: number;
    pf2: number;
    fl: number;
    lat0: number;
    lh0: number;
    dn0: number;
    hp0: number;
    hpPrev: number;
    dmg: number;
    fire?: number;
    seen?: number;
    same?: number;
    proj: boolean;
    land?: number;
    drop?: number;
    endWhy?: string;
    to?: string;
    /** Seconds after first sight of the end (any end). */
    age?: number;
    /** Predicted landing from the projectile's own position on its first frame, seconds after first sight. */
    pl3?: number;
    /** HP at the landing frame, for the next frame's loss. */
    hpLand?: number;
    /** HP lost over the landing frame and the next. */
    drop2?: number;
    /** Ranged, after the fire: per frame `1` the projectile listed at the creep, `0` not (cut at 40 frames). */
    pres: string;
    /** Absent frames in a row after it was seen. */
    absent: number;
    /** The landing by the first absent frame (the earlier rule), seconds after first sight. */
    land1?: number;
    /** After the fire: the largest one-frame HP loss and its time, seconds after first sight. */
    big: number;
    bigAt?: number;
    gap: number;
    last: number;
    /** Before the fire, per frame (the first included) `dt:cycle`, `;`-joined, `x` appended off the attack activity (30 frames at most). */
    wc: string;
    /** Frames in `wc`. */
    wn: number;
}

/** Live records by attacker handle. */
let active = new LuaTable<Swinger, Swing>();
/** At most this many live lane-creep records per team (creeps swing about once a second each; heroes and towers uncapped). */
const CREEP_RECORDS = 3;
let frameAt: number | undefined;

export function ResetCache(): void {
    active = new LuaTable<Swinger, Swing>();
    frameAt = undefined;
}

function dist(a: { x: number; y: number }, b: { x: number; y: number }): number {
    const dx = a.x - b.x;
    const dy = a.y - b.y;
    return math.sqrt(dx * dx + dy * dy);
}

function isLaneCreep(u: unknown): u is Target {
    if (u === undefined || u === null) return false;
    const c = u as Target;
    if (c.IsNull() || !c.IsAlive() || !c.IsCreep()) return false;
    const team = c.GetTeam();
    if (team !== 2 && team !== 3) return false;
    const name = c.GetUnitName();
    return string.find(name, "creep_goodguys", 1, true)[0] !== undefined || string.find(name, "creep_badguys", 1, true)[0] !== undefined
        || string.find(name, "siege", 1, true)[0] !== undefined;
}

/** Seconds of wind-up left, or undefined when not winding up (engine windupLeft). */
function windupLeft(h: Swinger): number | undefined {
    const act = h.GetAnimActivity();
    if (act !== ACTIVITY_ATTACK && act !== ACTIVITY_ATTACK2) return undefined;
    const cyc = h.GetAnimCycle();
    const pt = h.GetAttackPoint();
    if (cyc >= pt) return undefined;
    return (pt - cyc) * h.GetSecondsPerAttack();
}

/** In an attack animation (the cancel test: the anim cycle is not read, so a cycle past the point does not end a record). */
function attacking(h: Swinger): boolean {
    const act = h.GetAnimActivity();
    return act === ACTIVITY_ATTACK || act === ACTIVITY_ATTACK2;
}

/** What a retarget went to: `creep` another lane creep, `hero`, `none`, `other`. */
function targetKind(u: unknown): string {
    if (u === undefined || u === null) return "none";
    if (isLaneCreep(u)) return "creep";
    const [ok, hero] = pcall(() => (u as { IsHero(): boolean }).IsHero());
    return ok && hero === true ? "hero" : "other";
}

/** The hero's attack projectile at the creep: seconds to its landing from its own position (engine flightsAt), else undefined. */
function projectileEta(c: Target, h: Swinger): number | undefined {
    for (const p of c.GetIncomingTrackingProjectiles() ?? []) {
        if (p.is_attack === true && p.caster === h) return dist(p.location, c.GetLocation()) / math.max(1, h.GetAttackProjectileSpeed());
    }
    return undefined;
}

function gone(c: Target): boolean {
    return c.IsNull() || !c.IsAlive();
}

function start(h: Swinger, kind: string, c: Target, team: number, now: number): Swing | undefined {
    const left = windupLeft(h);
    if (left === undefined) return undefined;
    const ranged = h.GetAttackRange() > RANGED_ABOVE && h.GetAttackProjectileSpeed() > 0;
    const flight = ranged ? math.max(0, dist(h.GetLocation(), c.GetLocation()) - CREEP_LAUNCH_OFFSET) / h.GetAttackProjectileSpeed() : 0;
    const hp = c.GetHealth();
    return {
        h, kind, c, cid: Telemetry.CreepId(c as unknown as Unit), own: c.GetTeam() === team ? 1 : 0, ranged, t0: now,
        cyc: h.GetAnimCycle(), pt: h.GetAttackPoint(), spa: h.GetSecondsPerAttack(), pf: left, pl: left + flight,
        aspd: h.GetAttackSpeed(), pf2: (h.GetAttackPoint() / math.max(0.01, h.GetAttackSpeed())) * (1 - h.GetAnimCycle()), fl: flight,
        lat0: h.GetLastAttackTime(), lh0: kind === "hero" ? h.GetLastHits() : 0, dn0: kind === "hero" ? h.GetDenies() : 0, hp0: hp, hpPrev: hp,
        dmg: c.GetActualIncomingDamage(h.GetAttackDamage(), DAMAGE_TYPE_PHYSICAL ?? 1), proj: false, gap: 0, last: now,
        pres: "", absent: 0, big: 0, wc: string.format("0:%.3f", h.GetAnimCycle()), wn: 1,
    };
}

function r3(x: number | undefined): number {
    return x === undefined ? -1 : math.floor(x * 1000 + 0.5) / 1000;
}

function emit(s: Swing): void {
    const kill = s.kind === "hero" && (s.h.GetLastHits() > s.lh0 || s.h.GetDenies() > s.dn0) ? 1 : 0;
    Telemetry.Event("swing_probe", [
        ["pid", s.kind === "hero" ? s.h.GetPlayerID() : undefined],
        ["kind", s.kind],
        ["aid", s.kind === "hero" ? undefined : Telemetry.CreepId(s.h as unknown as Unit)],
        ["cid", s.cid],
        ["own", s.own],
        ["rng", s.ranged ? 1 : 0],
        ["cyc", r3(s.cyc)],
        ["pt", r3(s.pt)],
        ["spa", r3(s.spa)],
        ["pf", r3(s.pf)],
        ["pl", r3(s.pl)],
        ["aspd", r3(s.aspd)],
        ["pf2", r3(s.pf2)],
        ["fl", r3(s.fl)],
        ["fire", r3(s.fire)],
        ["seen", r3(s.seen)],
        ["land", r3(s.land)],
        ["same", s.same ?? -1],
        ["proj", s.proj ? 1 : 0],
        ["hp0", math.floor(s.hp0)],
        ["drop", s.drop === undefined ? -1 : math.floor(s.drop)],
        ["dmg", math.floor(s.dmg)],
        ["kill", kill],
        ["end", s.endWhy],
        ["to", s.to],
        ["gap", r3(s.gap)],
        ["age", r3(s.age)],
        ["pl3", r3(s.pl3)],
        ["drop2", s.drop2 === undefined ? -1 : math.floor(s.drop2)],
        ["pres", s.ranged ? s.pres : undefined],
        ["big", math.floor(s.big)],
        ["bigat", r3(s.bigAt)],
        ["wc", s.wc],
    ]);
}

/** One frame of a live record: true when it has ended (its line goes out the frame after the landing, for the counters). */
function follow(s: Swing, now: number): boolean {
    s.gap = math.max(s.gap, now - s.last);
    s.last = now;
    if (s.endWhy !== undefined) {
        if (s.drop !== undefined) s.drop2 = s.ranged ? s.drop : s.drop + (s.hpLand ?? 0) - (gone(s.c) ? 0 : s.c.GetHealth());
        emit(s);
        return true;
    }
    const isGone = gone(s.c);
    const hp = isGone ? 0 : s.c.GetHealth();
    if (s.fire === undefined && !isGone && s.wn < 30) {
        const act = s.h.GetAnimActivity();
        const off = act !== ACTIVITY_ATTACK && act !== ACTIVITY_ATTACK2 ? "x" : "";
        s.wc = s.wc + string.format(";%.3f:%.3f%s", now - s.t0, s.h.GetAnimCycle(), off);
        s.wn++;
    }
    if (s.fire === undefined && s.h.GetLastAttackTime() > s.lat0) {
        s.fire = s.h.GetLastAttackTime() - (GameTime() - now) - s.t0;
        s.seen = now - s.t0;
        s.same = s.h.GetAttackTarget() === s.c ? 1 : 0;
        if (!s.ranged) {
            s.land = s.seen;
            s.drop = s.hpPrev - hp;
            s.endWhy = "land";
        }
    } else if (s.fire === undefined) {
        if (isGone) s.endWhy = "gone";
        else if (s.h.GetAttackTarget() !== s.c) {
            s.endWhy = "retarget";
            s.to = targetKind(s.h.GetAttackTarget());
        }
        else if (!attacking(s.h)) s.endWhy = "cancel";
    } else if (s.ranged) {
        const eta = isGone ? undefined : projectileEta(s.c, s.h);
        const flying = eta !== undefined;
        if (s.pres.length < 40) s.pres = s.pres + (flying ? "1" : "0");
        if (s.hpPrev - hp > s.big) {
            s.big = s.hpPrev - hp;
            s.bigAt = now - s.t0;
        }
        if (flying && !s.proj) s.pl3 = now - s.t0 + eta;
        if (flying) {
            s.proj = true;
            s.absent = 0;
        } else if (s.proj) {
            s.absent++;
            if (s.absent === 1) {
                s.land1 = now - s.t0;
                s.hpLand = s.hpPrev;
            }
        }
        // Landed: two absent frames in a row after the projectile was seen (one may be a gap in the list), or the creep gone.
        if (!flying && ((s.proj && s.absent >= 2) || isGone)) {
            s.land = s.absent >= 2 ? (s.land1 ?? now - s.t0) : now - s.t0;
            // From the frame before the first absent one, over both: a hit that shows on either.
            s.drop = (s.absent >= 2 ? (s.hpLand ?? s.hpPrev) : s.hpPrev) - hp;
            s.endWhy = isGone && !s.proj ? "gone" : "land";
        }
    }
    if (s.endWhy === undefined && now - s.t0 > GIVE_UP) s.endWhy = "lost";
    if (s.endWhy !== undefined) {
        s.age = now - s.t0;
        if (s.drop !== undefined && !s.ranged) s.hpLand = hp;
    }
    s.hpPrev = hp;
    return false;
}

/** One attacker's frame: follow its live record, or start one on a wind-up at a lane creep. */
function visit(u: Swinger, kind: string, team: number, now: number, room: boolean): void {
    const s = active.get(u);
    if (s !== undefined) {
        if (follow(s, now)) active.delete(u);
        return;
    }
    if (!room || !u.IsAlive()) return;
    const t = u.GetAttackTarget();
    if (!isLaneCreep(t)) return;
    const r = start(u, kind, t, team, now);
    if (r !== undefined) active.set(u, r);
}

/** The probe's frame: every hero of the bot's team, its towers, and a few of its lane creeps, once per team VM per frame. */
function frame(bot: Unit): void {
    const now = DotaTime();
    if (frameAt === now) return;
    frameAt = now;
    const team = bot.GetTeam();
    for (let i = 1; i <= 5; i++) {
        const u = GetTeamMember(i) as unknown as Swinger | undefined;
        if (u === undefined || u === null || u.IsNull() || u.IsIllusion()) continue;
        visit(u, "hero", team, now, true);
    }
    for (const b of GetUnitList(UnitType.AlliedBuildings) ?? []) {
        const u = b as unknown as Swinger;
        if (!u.IsNull() && u.IsTower()) visit(u, "tower", team, now, true);
    }
    let creeps = 0;
    for (const [, r] of active) if (r.kind === "creep") creeps++;
    for (const c of GetUnitList(UnitType.AlliedCreeps) ?? []) {
        const u = c as unknown as Swinger;
        if (u.IsNull() || !isLaneCreep(u)) continue;
        const had = active.get(u) !== undefined;
        visit(u, "creep", team, now, creeps < CREEP_RECORDS);
        if (!had && active.get(u) !== undefined) creeps++;
    }
}

export function Tick(bot: Unit): void {
    if (Overrides.Get("SwingProbe") !== true) return;
    pcall(frame, bot);
}
