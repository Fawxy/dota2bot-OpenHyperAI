/**
 * Swing probe (`Overrides.SwingProbe`, probe games only; slice oha-deny-free step 1, user 24/11/2026): can the API say which
 * lane creep an own hero's attack will land on, and when? The lane read (step 2) needs that for every hero of our team in a
 * lane, so the support can skip, join or take a deny; if it cannot be read, the slice stops there.
 *
 * Each frame, once per team VM, every hero of the team (GetTeamMember 1..5) whose attack target is a lane creep and who is
 * winding up (GetAnimActivity ATTACK or ATTACK2, anim cycle before the attack point) starts one record. The prediction is the
 * engine's own formula (engine `windupLeft`/`windupLanding`, UNVERIFIED there): fire at (attack point - anim cycle) x seconds
 * per attack, a ranged hero's hit landing the projectile's flight later (distance less the launch offset, over projectile
 * speed). The record is followed to its truth, read from the game and not from the prediction:
 *   fire   GetLastAttackTime rising (the attack point passed; a melee hit lands then);
 *   land   melee: the fire; ranged: the frame the hero's attack projectile, once seen in the creep's
 *          GetIncomingTrackingProjectiles, is gone;
 *   drop   the target's HP lost from the frame before the landing to the landing frame (others' hits in the same frame
 *          add to it: compare with `dmg`, the hero's attack after the creep's armour);
 *   kill   the hero's last hits or denies rose by the frame after the landing.
 * One `ev=swing_probe` line per record, at its end (`end`: `land`, `cancel` the wind-up stopped unfired, `retarget` the
 * attack target changed before the fire, `gone` the creep died or vanished before the landing, `lost` nothing by GIVE_UP).
 * Reads and logs only: no order. Runs under pcall (a probe error is silent: a run is judged by its row counts).
 */
import { Unit } from "bots/ts_libs/dota";
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
    IsAlive(): boolean;
    IsIllusion(): boolean;
    GetPlayerID(): number;
    GetLocation(): { x: number; y: number };
    GetAttackTarget(): unknown;
    GetAnimActivity(): number;
    GetAnimCycle(): number;
    GetAttackPoint(): number;
    GetSecondsPerAttack(): number;
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
    GetIncomingTrackingProjectiles(): { caster: unknown; is_attack: boolean }[] | undefined;
}

interface Swing {
    h: Swinger;
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
    gap: number;
    last: number;
}

const active: Record<number, Swing | undefined> = {};
let frameAt: number | undefined;

export function ResetCache(): void {
    for (const [k] of pairs(active)) active[k as number] = undefined;
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

function hasProjectile(c: Target, h: Swinger): boolean {
    for (const p of c.GetIncomingTrackingProjectiles() ?? []) if (p.is_attack === true && p.caster === h) return true;
    return false;
}

function gone(c: Target): boolean {
    return c.IsNull() || !c.IsAlive();
}

function start(h: Swinger, c: Target, team: number, now: number): Swing | undefined {
    const left = windupLeft(h);
    if (left === undefined) return undefined;
    const ranged = h.GetAttackRange() > RANGED_ABOVE && h.GetAttackProjectileSpeed() > 0;
    const flight = ranged ? math.max(0, dist(h.GetLocation(), c.GetLocation()) - CREEP_LAUNCH_OFFSET) / h.GetAttackProjectileSpeed() : 0;
    const hp = c.GetHealth();
    return {
        h, c, cid: Telemetry.CreepId(c as unknown as Unit), own: c.GetTeam() === team ? 1 : 0, ranged, t0: now,
        cyc: h.GetAnimCycle(), pt: h.GetAttackPoint(), spa: h.GetSecondsPerAttack(), pf: left, pl: left + flight,
        lat0: h.GetLastAttackTime(), lh0: h.GetLastHits(), dn0: h.GetDenies(), hp0: hp, hpPrev: hp,
        dmg: c.GetActualIncomingDamage(h.GetAttackDamage(), DAMAGE_TYPE_PHYSICAL ?? 1), proj: false, gap: 0, last: now,
    };
}

function r3(x: number | undefined): number {
    return x === undefined ? -1 : math.floor(x * 1000 + 0.5) / 1000;
}

function emit(s: Swing): void {
    const kill = s.h.GetLastHits() > s.lh0 || s.h.GetDenies() > s.dn0 ? 1 : 0;
    Telemetry.Event("swing_probe", [
        ["pid", s.h.GetPlayerID()],
        ["cid", s.cid],
        ["own", s.own],
        ["rng", s.ranged ? 1 : 0],
        ["cyc", r3(s.cyc)],
        ["pt", r3(s.pt)],
        ["spa", r3(s.spa)],
        ["pf", r3(s.pf)],
        ["pl", r3(s.pl)],
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
        ["gap", r3(s.gap)],
    ]);
}

/** One frame of a live record: true when it has ended (its line goes out the frame after the landing, for the counters). */
function follow(s: Swing, now: number): boolean {
    s.gap = math.max(s.gap, now - s.last);
    s.last = now;
    if (s.endWhy !== undefined) {
        emit(s);
        return true;
    }
    const isGone = gone(s.c);
    const hp = isGone ? 0 : s.c.GetHealth();
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
        else if (s.h.GetAttackTarget() !== s.c) s.endWhy = "retarget";
        else if (windupLeft(s.h) === undefined) s.endWhy = "cancel";
    } else if (s.ranged) {
        const flying = !isGone && hasProjectile(s.c, s.h);
        if (flying) s.proj = true;
        else if (s.proj || isGone) {
            s.land = now - s.t0;
            s.drop = s.hpPrev - hp;
            s.endWhy = isGone && !s.proj ? "gone" : "land";
        }
    }
    if (s.endWhy === undefined && now - s.t0 > GIVE_UP) s.endWhy = "lost";
    s.hpPrev = hp;
    return false;
}

/** The probe's frame: every hero of the bot's team, once per team VM per frame. */
function frame(bot: Unit): void {
    const now = DotaTime();
    if (frameAt === now) return;
    frameAt = now;
    const team = bot.GetTeam();
    for (let i = 1; i <= 5; i++) {
        const u = GetTeamMember(i) as unknown as Swinger | undefined;
        if (u === undefined || u === null || u.IsNull() || u.IsIllusion()) continue;
        const pid = u.GetPlayerID();
        const s = active[pid];
        if (s !== undefined) {
            if (follow(s, now)) active[pid] = undefined;
            else continue;
        }
        if (!u.IsAlive()) continue;
        const t = u.GetAttackTarget();
        if (!isLaneCreep(t)) continue;
        active[pid] = start(u, t, team, now);
    }
}

export function Tick(bot: Unit): void {
    if (Overrides.Get("SwingProbe") !== true) return;
    pcall(frame, bot);
}
