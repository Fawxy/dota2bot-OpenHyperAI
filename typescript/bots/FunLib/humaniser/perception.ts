/**
 * Perception (task 03): human-like notice and reaction delays for the observing bot, GetBot().
 *
 * Part A, notice delay: enemy heroes returned by GetNearbyHeroes / GetUnitList are hidden from the
 * observer until a sampled notice delay has passed since they became visible (see FilterNearbyEnemies,
 * FilterUnitList, wired in aba_global_overrides.lua).
 * Part B, reaction delay: casts, tracking projectiles and channels become "known" to the observer a
 * sampled react delay after it first saw them (IsCastKnown, GetIncomingTrackingProjectiles,
 * FilterChanneling), used by the reactive predicates in jmz_func.lua.
 *
 * Works whether or not required modules are shared between a team's bots: all state is per observer
 * (keyed by player ID) and per target in weak-keyed tables keyed by handle. Nothing is written onto
 * unit handles. With modules shared, an observer may also use what a teammate noticed (TeammateCallout);
 * without sharing that exception never fires.
 */
import { Ability, Unit } from "bots/ts_libs/dota";
import * as Config from "bots/FunLib/humaniser/config";
import * as HDebug from "bots/FunLib/humaniser/debug";
import * as Profile from "bots/FunLib/humaniser/profile";
import * as Telemetry from "bots/FunLib/humaniser/telemetry";

/** Merged under Customize.Humaniser.Perception; its Enable key is the kill switch, read via Config. */
export const DEFAULTS = {
    /** A noticed hero seen again within this many seconds is re-acquired instantly (jukes, fog flicker). */
    Permanence: 2.0,
    /** Heroes this close to the observer are noticed immediately. */
    InstantRange: 300,
    /** A hero that damaged the observer within this window is noticed immediately. */
    InstantDamageWindow: 0.3,
    /** A hero a teammate noticed at least this long ago is noticed immediately (stands in for a callout). */
    TeammateCallout: 1.0,
    /** A cast unseen for this long is a new event next time it is seen (a cast's end is never observed). */
    EventGap: 0.5,
    /** A channel or projectile identity not checked for this long is forgotten; otherwise it lasts until seen absent. */
    IdentityTimeout: 2.0,
    /** At or above this skill, a bot that knows about a human's targeted cast early waits for the optimal window. */
    WaitForWindowSkill: 0.7,
    /** Apply the react delay to enemy IsChanneling() (channel interrupts). */
    Channel: true,
    /** How often the observer refreshes lastSeen for tracked heroes and updates the overlay. */
    RefreshInterval: 0.25,
};

export type PerceptionSettings = typeof DEFAULTS;

interface Sighting {
    firstVisible: number;
    noticeAt: number;
    lastSeen: number;
    noticed: boolean;
    noticedAt: number;
    frame: number;
    visible: boolean;
}

interface ReactEvent {
    name: string;
    firstSeen: number;
    knownAt: number;
    lastSeen: number;
    logged: boolean;
}

interface ProjectileCache {
    frame: number;
    ids: LuaTable<any, Record<string, ReactEvent>>;
    result: TrackingProjectile[];
}

interface TrackingProjectile {
    caster?: Unit;
    ability?: Ability;
    is_attack: boolean;
}

interface Observer {
    pid: number;
    team: number;
    bot: Unit;
    sightings: LuaTable<Unit, Sighting>;
    casts: LuaTable<Unit, ReactEvent>;
    channels: LuaTable<Unit, ReactEvent>;
    projectiles: LuaTable<Unit, ProjectileCache>;
    refreshAt: number;
    lastNoticeDelay: number;
    lastReactDelay: number;
}

/** Engine methods the shared ts_libs typings lack. */
interface PerceivedUnit extends Unit {
    WasRecentlyDamagedByHero(hero: Unit, interval: number): boolean;
    GetIncomingTrackingProjectiles(): TrackingProjectile[];
}

// Stands in for a nil caster so caster-less projectiles still get an identity.
const NO_CASTER = {};

const observers: Record<number, Observer> = {};
let settings: PerceptionSettings | undefined;

function weakKeys<K extends AnyNotNil, V>(): LuaTable<K, V> {
    return setmetatable(new LuaTable<K, V>(), { __mode: "k" });
}

export function Settings(): PerceptionSettings {
    if (settings === undefined) {
        const merged: any = {};
        for (const [k, v] of pairs(DEFAULTS)) merged[k] = v;
        const overrides = Config.Get().Perception;
        if (overrides !== undefined && type(overrides) === "table") {
            for (const [k, v] of pairs(overrides)) merged[k] = v;
        }
        settings = merged as PerceptionSettings;
    }
    return settings;
}

export function IsActive(): boolean {
    return Config.IsFeatureEnabled("Perception");
}

function currentObserver(): Observer | undefined {
    const bot = GetBot();
    if (bot === undefined || bot === null) return undefined;
    const pid = bot.GetPlayerID();
    let obs = observers[pid];
    if (obs === undefined) {
        obs = {
            pid,
            team: bot.GetTeam(),
            bot,
            sightings: weakKeys(),
            casts: weakKeys(),
            channels: weakKeys(),
            projectiles: weakKeys(),
            refreshAt: -1000,
            lastNoticeDelay: 0,
            lastReactDelay: 0,
        };
        observers[pid] = obs;
    }
    obs.bot = bot;
    return obs;
}

function format2(x: number): string {
    return string.format("%.2f", x);
}

/**
 * Keeps lastSeen current for heroes still in our team's vision but outside the radius of recent queries,
 * so a hero in continuous view never loses object permanence. Also feeds the overlay.
 */
function refresh(obs: Observer, now: number): void {
    const cfg = Settings();
    if (now - obs.refreshAt < cfg.RefreshInterval) return;
    obs.refreshAt = now;
    let hidden = 0;
    let noticed = 0;
    for (const [hero, s] of obs.sightings) {
        if (hero.IsNull()) {
            obs.sightings.delete(hero);
        } else if (now - s.lastSeen < cfg.Permanence) {
            if (s.lastSeen < now && hero.IsAlive() && hero.CanBeSeen()) s.lastSeen = now;
            if (s.noticed) noticed++;
            else hidden++;
        }
    }
    if (!HDebug.IsEnabled()) return;
    let pending = 0;
    for (const [, e] of obs.casts) {
        if (now < e.knownAt) pending++;
    }
    HDebug.Text(obs.bot, "percept", `hidden=${hidden} noticed=${noticed} lastNotice=${format2(obs.lastNoticeDelay)}`);
    HDebug.Text(obs.bot, "react", `pendingCasts=${pending} lastReact=${format2(obs.lastReactDelay)}`);
}

function teammateNoticed(obs: Observer, hero: Unit, now: number, cfg: PerceptionSettings): boolean {
    for (const [, other] of pairs(observers)) {
        if (other.pid !== obs.pid && other.team === obs.team) {
            const s = other.sightings.get(hero);
            if (s !== undefined && s.noticed && now - s.noticedAt >= cfg.TeammateCallout && now - s.lastSeen < cfg.Permanence) return true;
        }
    }
    return false;
}

function immediateReason(obs: Observer, hero: Unit, now: number, cfg: PerceptionSettings): string | undefined {
    if ((obs.bot as PerceivedUnit).WasRecentlyDamagedByHero(hero, cfg.InstantDamageWindow)) return "damaged";
    if (GetUnitToUnitDistance(obs.bot, hero) <= cfg.InstantRange) return "close";
    if (teammateNoticed(obs, hero, now, cfg)) return "teammate";
    return undefined;
}

function isNoticed(obs: Observer, hero: Unit, now: number, cfg: PerceptionSettings): boolean {
    let s = obs.sightings.get(hero);
    if (s !== undefined && s.frame === now) return s.visible;
    if (s === undefined) {
        s = { firstVisible: now, noticeAt: now, lastSeen: now, noticed: false, noticedAt: 0, frame: now, visible: false };
        s.noticeAt = now + Profile.SampleDelay(obs.bot, "notice");
        obs.sightings.set(hero, s);
    } else if (now - s.lastSeen >= cfg.Permanence) {
        s.firstVisible = now;
        s.noticeAt = now + Profile.SampleDelay(obs.bot, "notice");
        s.noticed = false;
    }
    s.lastSeen = now;
    s.frame = now;
    if (!s.noticed) {
        const reason = immediateReason(obs, hero, now, cfg) ?? (now >= s.noticeAt ? "delay" : undefined);
        if (reason !== undefined) {
            s.noticed = true;
            s.noticedAt = now;
            obs.lastNoticeDelay = now - s.firstVisible;
            HDebug.Log("perception", `pid=${obs.pid} noticed ${hero.GetUnitName()} after ${format2(obs.lastNoticeDelay)}s (${reason})`);
            Telemetry.Event("notice", [
                ["pid", obs.pid],
                ["target", hero.GetUnitName()],
                ["delay", obs.lastNoticeDelay],
                ["due", s.noticeAt - s.firstVisible],
                ["reason", reason],
            ]);
        }
    }
    s.visible = s.noticed;
    return s.visible;
}

/**
 * Units the team cannot currently see are passed through untouched and get no sighting. The engine can list
 * such a hero with no location (GetUnitToUnitDistance then fails in its override), and a sighting would keep
 * its lastSeen fresh while out of view, giving it a head start on the notice delay and defeating Permanence.
 * Passing it through leaves callers exactly the engine's answer; their own CanBeSeen checks drop it.
 */
function isPerceivable(unit: Unit): boolean {
    return !unit.IsNull() && unit.CanBeSeen() && unit.GetLocation() !== undefined;
}

/** O(n) over the original list; returns the original table untouched when nothing is hidden. */
function filterList(obs: Observer, list: Unit[], heroesOnly: boolean): Unit[] {
    const now = DotaTime();
    const cfg = Settings();
    // Before the empty check: a hero outside every recent query's radius still needs its lastSeen refreshed.
    refresh(obs, now);
    if (list.length === 0) return list;
    let out: Unit[] | undefined;
    for (let i = 0; i < list.length; i++) {
        const unit = list[i];
        const visible = !isPerceivable(unit) || (heroesOnly && !unit.IsHero()) || isNoticed(obs, unit, now, cfg);
        if (!visible) {
            if (out === undefined) {
                out = [];
                for (let j = 0; j < i; j++) out.push(list[j]);
            }
        } else if (out !== undefined) {
            out.push(unit);
        }
    }
    return out ?? list;
}

/** For CDOTA_Bot_Script:GetNearbyHeroes(r, true): filters only when the caller is on our team. */
export function FilterNearbyEnemies(caller: Unit, list: Unit[]): Unit[] {
    if (!IsActive() || caller.GetTeam() !== GetTeam()) return list;
    const obs = currentObserver();
    if (obs === undefined) return list;
    return filterList(obs, list, false);
}

/** For GetUnitList(UNIT_LIST_ENEMY_HEROES) (heroesOnly=false) or UNIT_LIST_ENEMIES (heroesOnly=true). */
export function FilterUnitList(list: Unit[], heroesOnly: boolean): Unit[] {
    if (!IsActive()) return list;
    const obs = currentObserver();
    if (obs === undefined) return list;
    return filterList(obs, list, heroesOnly);
}

function newEvent(obs: Observer, name: string, now: number): ReactEvent {
    return { name, firstSeen: now, knownAt: now + Profile.SampleDelay(obs.bot, "react"), lastSeen: now, logged: false };
}

function markKnown(obs: Observer, e: ReactEvent, now: number, who: string): boolean {
    if (now < e.knownAt) return false;
    if (!e.logged) {
        e.logged = true;
        obs.lastReactDelay = e.knownAt - e.firstSeen;
        if (e.name !== "attack") {
            HDebug.Log("perception", `pid=${obs.pid} react ${who} ${e.name} known after ${format2(obs.lastReactDelay)}s`);
            Telemetry.Event("react", [["pid", obs.pid], ["who", who], ["what", e.name], ["delay", obs.lastReactDelay]]);
        }
    }
    return true;
}

/**
 * True once the observer has watched this cast (caster + ability, from first sighting) for its react delay.
 * Call only while the caster is visibly casting the ability. Always true when perception is off.
 */
export function IsCastKnown(caster: Unit, abilityName: string): boolean {
    if (!IsActive()) return true;
    const obs = currentObserver();
    if (obs === undefined) return true;
    const now = DotaTime();
    let e = obs.casts.get(caster);
    if (e === undefined || e.name !== abilityName || now - e.lastSeen > Settings().EventGap) {
        e = newEvent(obs, abilityName, now);
        obs.casts.set(caster, e);
    }
    e.lastSeen = now;
    return markKnown(obs, e, now, caster.GetUnitName());
}

/** True when a skilled observer should hold a known targeted-spell reaction until the optimal window. */
export function WaitsForOptimalWindow(): boolean {
    const bot = GetBot();
    if (bot === undefined || bot === null) return false;
    return Profile.Get(bot).skill >= Settings().WaitForWindowSkill;
}

/**
 * target:GetIncomingTrackingProjectiles() without enemy projectiles the observer has not yet reacted to.
 * Identity is caster + ability name (or 'attack'); identities absent from a call are dropped.
 * Allied projectiles always pass. Cached per frame and per target.
 */
export function GetIncomingTrackingProjectiles(target: Unit): TrackingProjectile[] {
    const list = (target as PerceivedUnit).GetIncomingTrackingProjectiles();
    if (!IsActive()) return list;
    const obs = currentObserver();
    if (obs === undefined) return list;
    const now = DotaTime();
    let cache = obs.projectiles.get(target);
    if (cache !== undefined && cache.frame === now) return cache.result;
    const prev = cache !== undefined && now - cache.frame <= Settings().IdentityTimeout ? cache.ids : undefined;
    const ids = weakKeys<any, Record<string, ReactEvent>>();
    if (cache === undefined) {
        cache = { frame: now, ids, result: list };
        obs.projectiles.set(target, cache);
    }
    let out: TrackingProjectile[] | undefined;
    for (let i = 0; i < list.length; i++) {
        const p = list[i];
        const caster = p.caster;
        let keep = true;
        if (caster === undefined || caster.GetTeam() !== obs.team) {
            const key = caster ?? NO_CASTER;
            const name = p.is_attack ? "attack" : p.ability !== undefined ? p.ability.GetName() : "unknown";
            let byName = ids.get(key);
            if (byName === undefined) {
                byName = {};
                ids.set(key, byName);
            }
            let e = byName[name] ?? prev?.get(key)?.[name];
            if (e === undefined) e = newEvent(obs, name, now);
            e.lastSeen = now;
            byName[name] = e;
            keep = markKnown(obs, e, now, caster !== undefined ? caster.GetUnitName() : "?");
        }
        if (!keep) {
            if (out === undefined) {
                out = [];
                for (let j = 0; j < i; j++) out.push(list[j]);
            }
        } else if (out !== undefined) {
            out.push(p);
        }
    }
    cache.frame = now;
    cache.ids = ids;
    cache.result = out ?? list;
    return cache.result;
}

/**
 * For CDOTA_Bot_Script:IsChanneling() on enemy units: true only once the observer has seen the channel
 * for its react delay. A channel that follows a cast the observer was already tracking inherits that
 * cast's knownAt, so the wind-up and the channel are not delayed twice.
 */
export function FilterChanneling(unit: Unit, channeling: boolean): boolean {
    if (!IsActive() || Settings().Channel !== true) return channeling;
    const obs = currentObserver();
    if (obs === undefined) return channeling;
    if (!channeling) {
        obs.channels.delete(unit);
        return false;
    }
    const now = DotaTime();
    const cfg = Settings();
    let e = obs.channels.get(unit);
    if (e === undefined || now - e.lastSeen > cfg.IdentityTimeout) {
        e = newEvent(obs, "channel", now);
        const cast = obs.casts.get(unit);
        if (cast !== undefined && now - cast.lastSeen <= cfg.EventGap) {
            e.firstSeen = cast.firstSeen;
            e.knownAt = cast.knownAt;
        }
        obs.channels.set(unit, e);
    }
    e.lastSeen = now;
    return markKnown(obs, e, now, unit.GetUnitName());
}
