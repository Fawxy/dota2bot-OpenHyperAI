/**
 * Cast watching (task 11): feeds the cooldown memory from enemy casts the observer can see. Polls each visible lane
 * enemy every PollInterval for an active ability, infers a blink from a jump between two polls (instant casts have no
 * cast point to poll), and optionally listens to cast callbacks, kept only while the caster is in the observer's
 * visible list. Only enemies from LaneState.Enemies (perception-filtered, cached) are read; no unit scans here.
 */
import { Team, Unit } from "bots/ts_libs/dota";
import * as LaneFightConfig from "bots/FunLib/humaniser/lane_fight_config";
import * as LaneConfig from "bots/FunLib/humaniser/lane_config";
import * as LaneState from "bots/FunLib/humaniser/lane_state";
import * as LaneRoles from "bots/FunLib/humaniser/lane_roles";
import * as CooldownMemory from "bots/FunLib/humaniser/cooldown_memory";
import * as AbilityClasses from "bots/FunLib/humaniser/ability_classes";
import * as Perception from "bots/FunLib/humaniser/perception";
import * as Profile from "bots/FunLib/humaniser/profile";
import * as Telemetry from "bots/FunLib/humaniser/telemetry";

export interface AbilityInfo {
    name: string;
    slot: number;
    learned: boolean;
    ult: boolean;
    cooldown: number;
    level: number;
    item: boolean;
}

export interface Recorded {
    enemyPid: number;
    ability: string;
    at: number;
}

interface Watch {
    nextPoll: number;
    // Last poll each (enemy, ability) was seen being cast; a cast unseen for EventGap is a new cast.
    seen: Record<string, number>;
    lastLoc: Record<number, { x: number; y: number; at: number }>;
    noCdLogged: Record<string, boolean>;
    callbacks: Record<number, boolean>;
    last?: Recorded;
    lastSeen?: Recorded;
    stats: Stats;
}

// Counts since the last lanefight_watch summary; tells "saw nothing" apart from "the API answers nothing" in game.
interface Stats {
    since: number;
    polls: number;
    visible: number;
    casts: number;
    recorded: number;
    jumps: number;
}

// Ability and item handles from the engine; methods are optional because items lack some of them.
interface Handle {
    IsNull?(): boolean;
    GetName?(): string;
    GetLevel?(): number;
    GetCooldown?(): number;
    IsUltimate?(): boolean;
    IsHidden?(): boolean;
}

const SLOTS = 6;
const SUMMARY_EVERY = 30;
const ABILITY_CACHE = 5;
// Two polls count as consecutive up to this many poll intervals apart (bot frames do not land exactly on 0.1 s).
const JUMP_POLLS = 2.5;

const watches: Record<number, Watch> = {};
const abilityCache: Record<number, { at: number; list: AbilityInfo[] }> = {};

function freshStats(now: number): Stats {
    return { since: now, polls: 0, visible: 0, casts: 0, recorded: 0, jumps: 0 };
}

function watchFor(pid: number): Watch {
    let w = watches[pid];
    if (w === undefined) {
        w = { nextPoll: -math.huge, seen: {}, lastLoc: {}, noCdLogged: {}, callbacks: {}, stats: freshStats(DotaTime()) };
        watches[pid] = w;
    }
    return w;
}

function isNullHandle(h: Handle | Unit | null | undefined): boolean {
    return h === undefined || h === null || (h.IsNull !== undefined && h.IsNull() === true);
}

function usable(u: Unit | undefined): u is Unit {
    if (isNullHandle(u)) return false;
    const unit = u as Unit;
    if (!unit.IsAlive() || !unit.CanBeSeen() || unit.IsIllusion() || unit.GetLocation() === undefined) return false;
    const suspicious = LaneConfig.Helpers().IsSuspiciousIllusion;
    return suspicious === undefined || !suspicious(unit);
}

/** Ultimate: 1 at hero level 6, 2 at 12, 3 at 18. Basic ability: min(4, ceil(heroLevel / 2)). */
export function LevelEstimate(heroLevel: number, isUlt: boolean): number {
    if (isUlt) return heroLevel >= 18 ? 3 : heroLevel >= 12 ? 2 : heroLevel >= 6 ? 1 : 0;
    return math.max(0, math.min(4, math.ceil(heroLevel / 2)));
}

/**
 * The one cooldown source: the handle's current-level `GetCooldown()`. The bot API takes no level (the level form is
 * server VScript, 0-based), so `level` is only for Task 4b's generated-table fallback, keyed by name and level.
 * 0 means unknown.
 */
export function CooldownOf(h: Handle | null | undefined, _name: string, _level: number): number {
    if (isNullHandle(h) || h!.GetCooldown === undefined) return 0;
    const handle = h as Handle & { GetCooldown(): number };
    const [ok, cd] = pcall(() => handle.GetCooldown());
    return ok && type(cd) === "number" && (cd as number) > 0 ? (cd as number) : 0;
}

function handleLevel(h: Handle): number {
    if (h.GetLevel === undefined) return 0;
    const level = h.GetLevel!();
    return type(level) === "number" ? level : 0;
}

// Prefer the engine flag; slot 5 stands in only where a handle has no IsUltimate.
function isUltimate(h: Handle, slot: number, item: boolean): boolean {
    if (item) return false;
    if (h.IsUltimate !== undefined) return h.IsUltimate!() === true;
    return slot === 5;
}

function describe(h: Handle, name: string, slot: number, heroLevel: number, item: boolean, cast: boolean): AbilityInfo {
    const ult = isUltimate(h, slot, item);
    const read = handleLevel(h);
    let level = read > 0 ? read : item ? 1 : LevelEstimate(heroLevel, ult);
    // Seeing it cast proves it is learned whatever the estimate says.
    if (cast && level < 1) level = 1;
    return { name, slot, learned: level > 0, ult, cooldown: level > 0 ? CooldownOf(h, name, level) : 0, level, item };
}

function isItemName(name: string): boolean {
    return string.sub(name, 1, 5) === "item_";
}

function nameOf(h: Handle | null | undefined): string | undefined {
    if (isNullHandle(h) || h!.GetName === undefined) return undefined;
    const name = h!.GetName();
    return type(name) === "string" && name !== "" ? name : undefined;
}

/** Learned and unlearned abilities in slots 0-5 and items in inventory slots 0-5 (item = true), cached per enemy pid. */
export function AbilitiesOf(enemy: Unit): AbilityInfo[] {
    if (isNullHandle(enemy)) return [];
    const epid = enemy.GetPlayerID();
    const now = DotaTime();
    const cached = abilityCache[epid];
    if (cached !== undefined && now - cached.at < ABILITY_CACHE) return cached.list;
    const heroLevel = enemy.GetLevel();
    const list: AbilityInfo[] = [];
    for (let i = 0; i < SLOTS; i++) {
        const a = enemy.GetAbilityInSlot(i) as Handle | null;
        const name = nameOf(a);
        if (name === undefined || name === "generic_hidden" || (a!.IsHidden !== undefined && a!.IsHidden() === true)) continue;
        list.push(describe(a!, name, i, heroLevel, false, false));
    }
    for (let i = 0; i < SLOTS; i++) {
        const it = enemy.GetItemInSlot(i) as Handle | null;
        const name = nameOf(it);
        if (name !== undefined) list.push(describe(it!, name, i, heroLevel, true, false));
    }
    abilityCache[epid] = { at: now, list };
    return list;
}

function slotOf(enemy: Unit, name: string): number {
    for (const a of AbilitiesOf(enemy)) if (a.name === name) return a.slot;
    return -1;
}

function contains(name: string, part: string): boolean {
    return string.find(name, part, 1, true)[0] !== undefined;
}

// Blink-class: an escape that relocates instantly, identified by name (hero blinks and every blink item).
function blinkAbility(enemy: Unit): AbilityInfo | undefined {
    for (const a of AbilitiesOf(enemy)) {
        if (a.learned && AbilityClasses.IsEscape(a.name) && contains(a.name, "blink")) return a;
    }
    return undefined;
}

export function LastRecorded(observerPid: number): Recorded | undefined {
    const w = watches[observerPid];
    return w === undefined ? undefined : w.last;
}

/** The last visible cast this observer saw, remembered or not (a human sees an escape even if its cooldown slips). */
export function LastSeenCast(observerPid: number): Recorded | undefined {
    const w = watches[observerPid];
    return w === undefined ? undefined : w.lastSeen;
}

function shareToPartner(bot: Unit, enemyPid: number, ability: string): void {
    const s = LaneState.ForBot(bot);
    if (s === undefined) return;
    const partner = LaneRoles.Partner(bot, s);
    if (partner === undefined || !partner.isBot || !partner.alive || isNullHandle(partner.unit)) return;
    CooldownMemory.Share(bot.GetPlayerID(), [partner.pid], enemyPid, ability, Profile.Get(partner.unit).skill);
}

function noteCast(bot: Unit, w: Watch, enemyPid: number, info: AbilityInfo, now: number, src: string): void {
    const key = `${enemyPid}:${info.name}`;
    const prev = w.seen[key];
    w.seen[key] = now;
    if (prev !== undefined && now - prev <= Perception.Settings().EventGap) return;
    const pid = bot.GetPlayerID();
    w.stats.casts++;
    w.lastSeen = { enemyPid, ability: info.name, at: now };
    if (info.cooldown <= 0) {
        if (w.noCdLogged[key] === true) return;
        w.noCdLogged[key] = true;
        Telemetry.Event("lanefight_mem", [
            ["pid", pid],
            ["enemy", enemyPid],
            ["ability", info.name],
            ["remembered", 0],
            ["reason", "no_cd"],
        ]);
        return;
    }
    const cls = AbilityClasses.Classify(info.name, info.ult);
    const remembered = CooldownMemory.Record(pid, enemyPid, info.name, cls, info.cooldown, Profile.Get(bot).skill, now);
    Telemetry.Event("lanefight_mem", [
        ["pid", pid],
        ["enemy", enemyPid],
        ["ability", info.name],
        ["cls", cls],
        ["cd", info.cooldown],
        ["remembered", remembered ? 1 : 0],
        ["src", src],
    ]);
    if (!remembered) return;
    w.stats.recorded++;
    w.last = { enemyPid, ability: info.name, at: now };
    if (LaneFightConfig.Settings().ShareMemory === true) shareToPartner(bot, enemyPid, info.name);
}

function castInfo(enemy: Unit, h: Handle, name: string): AbilityInfo {
    return describe(h, name, slotOf(enemy, name), enemy.GetLevel(), isItemName(name), true);
}

function pollCast(bot: Unit, w: Watch, enemy: Unit, enemyPid: number, now: number): void {
    if (!enemy.IsCastingAbility() && !enemy.IsUsingAbility()) return;
    const a = enemy.GetCurrentActiveAbility() as Handle | null;
    const name = nameOf(a);
    if (name === undefined) return;
    noteCast(bot, w, enemyPid, castInfo(enemy, a!, name), now, "poll");
}

function checkJump(bot: Unit, w: Watch, enemy: Unit, enemyPid: number, now: number): void {
    const loc = enemy.GetLocation();
    const prev = w.lastLoc[enemyPid];
    w.lastLoc[enemyPid] = { x: loc.x, y: loc.y, at: now };
    if (prev === undefined || now - prev.at > LaneFightConfig.Settings().PollInterval * JUMP_POLLS) return;
    const dx = loc.x - prev.x;
    const dy = loc.y - prev.y;
    if (math.sqrt(dx * dx + dy * dy) <= LaneFightConfig.Settings().BlinkJump) return;
    w.stats.jumps++;
    const blink = blinkAbility(enemy);
    if (blink !== undefined) noteCast(bot, w, enemyPid, blink, now, "jump");
}

function visibleEnemy(bot: Unit, enemyPid: number): Unit | undefined {
    for (const e of LaneState.Enemies(bot, bot.GetAssignedLane())) {
        if (e !== undefined && e.pid === enemyPid && e.visible && usable(e.unit)) return e.unit;
    }
    return undefined;
}

function onCastEvent(bot: Unit, enemyPid: number, event: any): void {
    if (!LaneFightConfig.IsOn("Memory") || !LaneFightConfig.Settings().UseCastCallback) return;
    const now = DotaTime();
    if (now < 0 || !LaneConfig.InLaningPhase() || isNullHandle(bot)) return;
    const caster = visibleEnemy(bot, enemyPid);
    if (caster === undefined || type(event) !== "table") return;
    // The player's summons and controlled units cast under the same player ID; only the hero's own casts count.
    if (event.unit !== undefined && event.unit !== null && event.unit !== caster) return;
    const a = event.ability;
    const name = type(a) === "string" ? (a as string) : nameOf(a as Handle);
    if (name === undefined) return;
    let info: AbilityInfo | undefined;
    if (type(a) === "string") {
        for (const x of AbilitiesOf(caster)) if (x.name === name) info = x;
    } else {
        info = castInfo(caster, a as Handle, name);
    }
    if (info !== undefined) noteCast(bot, watchFor(bot.GetPlayerID()), enemyPid, info, now, "callback");
}

function installCallbacks(bot: Unit, w: Watch): void {
    const enemyTeam = bot.GetTeam() === Team.Radiant ? Team.Dire : Team.Radiant;
    for (const enemyPid of GetTeamPlayers(enemyTeam)) {
        if (w.callbacks[enemyPid] === true) continue;
        w.callbacks[enemyPid] = true;
        const handler = (event: any): void => onCastEvent(bot, enemyPid, event);
        InstallCastCallback(enemyPid, Telemetry.GuardsEnabled() ? Telemetry.Guard("CastWatch.OnCast", handler) : handler);
    }
}

function summarise(bot: Unit, w: Watch, now: number): void {
    const st = w.stats;
    if (now - st.since < SUMMARY_EVERY) return;
    Telemetry.Event("lanefight_watch", [
        ["pid", bot.GetPlayerID()],
        ["polls", st.polls],
        ["visible", st.visible],
        ["casts", st.casts],
        ["recorded", st.recorded],
        ["jumps", st.jumps],
    ]);
    w.stats = freshStats(now);
}

export function Tick(bot: Unit): void {
    const now = DotaTime();
    if (now < 0) return;
    const w = watchFor(bot.GetPlayerID());
    if (now < w.nextPoll) return;
    const s = LaneFightConfig.Settings();
    w.nextPoll = now + s.PollInterval - 1e-6;
    if (s.UseCastCallback === true) installCallbacks(bot, w);
    const visible: Record<number, boolean> = {};
    for (const e of LaneState.Enemies(bot, bot.GetAssignedLane())) {
        if (e === undefined || !e.visible || !usable(e.unit)) continue;
        visible[e.pid] = true;
        w.stats.visible++;
        pollCast(bot, w, e.unit, e.pid, now);
        checkJump(bot, w, e.unit, e.pid, now);
    }
    w.stats.polls++;
    summarise(bot, w, now);
    // A hero out of sight for a poll may come back anywhere; that is not a jump.
    for (const [pid] of pairs(w.lastLoc)) if (visible[pid as number] !== true) w.lastLoc[pid as number] = undefined as any;
}
