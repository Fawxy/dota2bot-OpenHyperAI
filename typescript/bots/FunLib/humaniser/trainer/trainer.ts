/**
 * Last-hit trainer (task 14): practice feedback for the human. Everything here runs only after "!trainer on"
 * and never issues orders. Chat replies are queued per team and spoken by the team's lowest-PID bot.
 */
import { GameState, Unit } from "bots/ts_libs/dota";
import * as Config from "bots/FunLib/humaniser/config";
import * as HDebug from "bots/FunLib/humaniser/debug";
import * as Settings from "bots/FunLib/humaniser/trainer/settings";
import { CreepKind, GetTrainerHelpers, HeroLabel, SetTrainerHelpers, T, TrainerHelpers } from "bots/FunLib/humaniser/trainer/api";
import { SpikeTick } from "bots/FunLib/humaniser/trainer/spike";
import { Heroes, NearbyUnits, Towers } from "bots/FunLib/humaniser/trainer/incoming";
import { EffectiveDamage, Predict, Prediction, Smoother } from "bots/FunLib/humaniser/trainer/predict";
import { CreepObs, Judge, JudgeEvent, Killer, SubjectObs, Verdict, VerdictKind } from "bots/FunLib/humaniser/trainer/judge";
import { Attribute, Counters, HeroRef, IsDeathLikely, SelectCreeps } from "bots/FunLib/humaniser/trainer/watch";
import { Stats } from "bots/FunLib/humaniser/trainer/stats";
import { SummaryText, VerdictLine, VerdictLines } from "bots/FunLib/humaniser/trainer/draw";

const REPLY_INTERVAL = 0.5;
const REPLY_CAP = 8;
const USAGE = "usage: !trainer on|off|stats|reset|bar on|off|chat off|misses|all|denies on|off";

const MAX_BARS = 2;
/**
 * Last frame's bars keep their place unless another window closes this much sooner. A throttled prediction's
 * startClose can trail a fresh one by up to a WatchInterval, which would otherwise swap the bars every frame.
 */
const BAR_STICKINESS = 0.2;
const CANDIDATE_RADIUS = 800;
const DENY_HP_FRACTION = 0.6;
const HERO_FIGHT_SECONDS = 2;
const HARASS_SECONDS = 2;
const ATTACK_ACTIVITIES: Record<number, boolean> = { [1503]: true, [1504]: true };
const VERDICT_LINES_KEPT = 3;
const CHAT_INTERVAL = 2;
const MISS_KINDS: Partial<Record<VerdictKind, boolean>> = { EARLY: true, LATE: true, MISS: true, MISSED_EASY: true };
/** A last-hit or deny counter that rose this long before a death is still matched to it. */
const COUNTER_MATCH_SECONDS = 0.15;
const HISTORY_SECONDS = 0.5;

interface Tracked {
    creep: Unit;
    kind: CreepKind;
    isDeny: boolean;
    hp: number;
    maxHp: number;
    effDmg: number;
    dist: number;
    towerTargeting: boolean;
}

/** A counter rise already matched to one death, so a second death in the match window can't claim it. */
interface Credit {
    t: number;
    counter: "lastHits" | "denies";
    pid: number;
}

interface SubjectState {
    judge: Judge;
    stats: Stats;
    smoothers: Record<string, Smoother>;
    lastHeroAttackAt: number;
    verdictLines: VerdictLine[];
    summary?: { lines: string[]; at: number };
    cache: Record<string, Prediction>;
    predictedAt: Record<string, number>;
    barIds: string[];
    watchedIds: string[];
    bars: Prediction[];
    predictions: Prediction[];
    tracked: Record<string, Tracked>;
    credits: Credit[];
}

interface TeamState {
    on: boolean;
    bar: boolean;
    chat: "off" | "misses" | "all";
    denies: boolean;
    spike: boolean;
    replies: string[];
    lastReplyAt: number;
    subjects: Record<number, SubjectState>;
    checkpointsDone: Record<number, boolean>;
    wasLaning: boolean | undefined;
    selfTestStarted: boolean;
    lastChatAt: number;
    history: { t: number; counters: Counters }[];
}

const teams: Record<number, TeamState> = {};
const warned: Record<number, Record<number, boolean>> = {};

export function SetHelpers(h: TrainerHelpers): void {
    SetTrainerHelpers(h);
}

export function GetHelpers(): TrainerHelpers | undefined {
    return GetTrainerHelpers();
}

/** Same rule as commands.ts's lowestBotPID; not imported from there (commands.ts imports this module). */
export function TrainerBotPID(team: number): number | undefined {
    let best: number | undefined;
    for (const pid of GetTeamPlayers(team)) {
        if (IsPlayerBot(pid) && (best === undefined || pid < best)) best = pid;
    }
    return best;
}

function stateFor(team: number): TeamState {
    let s = teams[team];
    if (s === undefined) {
        const cfg = Settings.Get();
        s = {
            on: false,
            bar: cfg.Bar,
            chat: cfg.Chat,
            denies: cfg.Denies,
            spike: false,
            replies: [],
            lastReplyAt: -math.huge,
            subjects: {},
            checkpointsDone: {},
            wasLaning: undefined,
            selfTestStarted: false,
            lastChatAt: -math.huge,
            history: [],
        };
        teams[team] = s;
    }
    return s;
}

function newSubject(): SubjectState {
    return {
        judge: new Judge(Settings.Get().EasyWindow),
        stats: new Stats(),
        smoothers: {},
        lastHeroAttackAt: -math.huge,
        verdictLines: [],
        cache: {},
        predictedAt: {},
        barIds: [],
        watchedIds: [],
        bars: [],
        predictions: [],
        tracked: {},
        credits: [],
    };
}

function subjectState(s: TeamState, pid: number): SubjectState {
    let st = s.subjects[pid];
    if (st === undefined) {
        st = newSubject();
        s.subjects[pid] = st;
    }
    return st;
}

function queueReply(s: TeamState, line: string): void {
    if (s.replies.length >= REPLY_CAP) return;
    s.replies.push(line);
}

function onOff(s: TeamState): string {
    return s.on ? "on" : "off";
}

function status(s: TeamState): string {
    return `trainer ${onOff(s)} - bar ${s.bar ? "on" : "off"} - chat ${s.chat} - denies ${s.denies ? "on" : "off"}`;
}

function parseOnOff(word: string | undefined): boolean | undefined {
    if (word === "on") return true;
    if (word === "off") return false;
    return undefined;
}

function switchOn(s: TeamState): void {
    s.on = true;
    s.subjects = {};
    s.history = [];
    s.wasLaning = undefined;
    s.checkpointsDone = {};
    const dota = DotaTime();
    for (const c of Settings.Get().Checkpoints) {
        if (c <= dota) s.checkpointsDone[c] = true;
    }
}

function switchOff(s: TeamState): void {
    s.on = false;
    for (const [, st] of pairs(s.subjects)) {
        st.verdictLines = [];
        st.summary = undefined;
        st.bars = [];
        st.predictions = [];
    }
}

function humanPID(team: number): number | undefined {
    let best: number | undefined;
    for (const pid of GetTeamPlayers(team)) {
        if (!IsPlayerBot(pid) && (best === undefined || pid < best)) best = pid;
    }
    return best;
}

function summaryLines(s: TeamState, st: SubjectState): string[] {
    return st.stats.Lines({ outcomeOnly: Settings.Get().OutcomeOnly, denies: s.denies });
}

export function OnCommand(team: number, _pid: number, args: string[]): void {
    if (!Settings.IsEnabled()) return;
    const s = stateFor(team);
    const sub = args[0];
    const reply = (line: string) => queueReply(s, line);
    if (sub === undefined) {
        reply(status(s));
    } else if (sub === "on" || sub === "off") {
        if (sub === "on") switchOn(s);
        else switchOff(s);
        reply(status(s));
    } else if (sub === "bar" || sub === "denies") {
        const value = parseOnOff(args[1]);
        if (value === undefined) reply(USAGE);
        else {
            if (sub === "bar") s.bar = value;
            else s.denies = value;
            reply(status(s));
        }
    } else if (sub === "chat") {
        const mode = args[1];
        if (mode === "off" || mode === "misses" || mode === "all") {
            s.chat = mode;
            reply(status(s));
        } else reply(USAGE);
    } else if (sub === "stats") {
        if (args[1] === "selftest") {
            const botPid = TrainerBotPID(team);
            const st = botPid === undefined ? undefined : s.subjects[botPid];
            reply((st?.stats ?? new Stats()).SelfTestLine());
        } else {
            const pid = humanPID(team);
            const st = pid === undefined ? newSubject() : subjectState(s, pid);
            for (const line of summaryLines(s, st)) reply(line);
        }
    } else if (sub === "reset") {
        for (const [, st] of pairs(s.subjects)) {
            st.stats.Reset();
            st.judge = new Judge(Settings.Get().EasyWindow);
        }
        reply("trainer stats reset");
    } else if (sub === "spike" && Config.Get().Debug === true) {
        s.spike = !s.spike;
        HDebug.Log("trainer", "spike", s.spike ? "on" : "off");
    } else {
        reply(USAGE);
    }
}

/** Humans on the team by lowest PID. GetTeamMember answers for the calling bot's team, hence the team check. */
function humans(team: number): Unit[] {
    const result: Unit[] = [];
    const players = GetTeamPlayers(team);
    for (let i = 1; i <= players.length; i++) {
        const member = GetTeamMember(i);
        if (member === null || member === undefined || member.GetTeam() !== team) continue;
        if (!IsPlayerBot(member.GetPlayerID())) result.push(member);
    }
    table.sort(result, (a, b) => a.GetPlayerID() < b.GetPlayerID());
    return result;
}

function trainerBotUnit(team: number): Unit | undefined {
    const pid = TrainerBotPID(team);
    const players = GetTeamPlayers(team);
    for (let i = 1; i <= players.length; i++) {
        const member = GetTeamMember(i);
        if (member !== null && member !== undefined && member.GetTeam() === team && member.GetPlayerID() === pid) return member;
    }
    return undefined;
}

function subjectsFor(team: number, trainerBot: Unit | undefined): Unit[] {
    const found = humans(team);
    const subjects: Unit[] = [];
    if (found.length > 0) subjects.push(found[0]);
    for (let i = 1; i < found.length; i++) {
        const pid = found[i].GetPlayerID();
        if (warned[team] === undefined) warned[team] = {};
        if (warned[team][pid] !== true) {
            warned[team][pid] = true;
            HDebug.Log("trainer", `[WARN] trainer coaches one player; ignoring pid ${pid}`);
        }
    }
    if (Settings.Get().SelfTest && trainerBot !== undefined) subjects.push(trainerBot);
    return subjects;
}

/** The human, then the self-test bot when SelfTest is on. */
export function GetSubjects(team: number): Unit[] {
    if (!Settings.IsEnabled()) return [];
    return subjectsFor(team, trainerBotUnit(team));
}

/** The human's bar predictions for the current frame. */
export function Predictions(team: number): Prediction[] {
    const s = teams[team];
    const pid = humanPID(team);
    if (s === undefined || pid === undefined) return [];
    return s.subjects[pid]?.bars ?? [];
}

/** One subject's bar and watched predictions for the current frame. */
export function SubjectPredictions(team: number, pid: number): Prediction[] {
    return teams[team]?.subjects[pid]?.predictions ?? [];
}

interface Candidate {
    id: string;
    creep: Unit;
    isDeny: boolean;
}

function creepId(u: Unit): string {
    return tostring(u);
}

function isLaneCreep(u: Unit): boolean {
    if (u.IsHero() || T(u).IsTower()) return false;
    const name = u.GetUnitName();
    return string.find(name, "npc_dota_creep_", 1, true)[0] !== undefined || string.find(name, "siege", 1, true)[0] !== undefined;
}

function candidatesFor(subject: Unit, denies: boolean): Candidate[] {
    const result: Candidate[] = [];
    for (const u of NearbyUnits(subject.GetLocation(), CANDIDATE_RADIUS)) {
        if (!isLaneCreep(u) || !u.CanBeSeen()) continue;
        const ally = u.GetTeam() === subject.GetTeam();
        if (ally && !(denies && u.GetHealth() < DENY_HP_FRACTION * u.GetMaxHealth())) continue;
        result.push({ id: creepId(u), creep: u, isDeny: ally });
    }
    return result;
}

function predictOne(st: SubjectState, subject: Unit, c: Candidate, now: number): void {
    let smoother = st.smoothers[c.id];
    if (smoother === undefined) {
        smoother = new Smoother();
        st.smoothers[c.id] = smoother;
    }
    st.predictedAt[c.id] = now;
    const p = Predict(subject, c.creep, c.isDeny, now, smoother);
    if (p === undefined) delete st.cache[c.id];
    else st.cache[c.id] = p;
}

/**
 * At most MAX_BARS + MaxWatched predictions per frame: the attack target and last frame's bars every frame,
 * then the stalest other candidates once their prediction is WatchInterval old, current watched creeps first.
 */
function refreshPredictions(st: SubjectState, subject: Unit, cands: Candidate[], target: Unit | undefined, now: number): void {
    const cfg = Settings.Get();
    const byId: Record<string, Candidate> = {};
    for (const c of cands) byId[c.id] = c;

    const priority: string[] = [];
    if (target !== undefined && byId[creepId(target)] !== undefined) priority.push(creepId(target));
    for (const id of st.barIds) {
        if (byId[id] !== undefined && priority.indexOf(id) < 0) priority.push(id);
    }
    const done: Record<string, boolean> = {};
    for (let i = 0; i < math.min(priority.length, MAX_BARS); i++) {
        predictOne(st, subject, byId[priority[i]], now);
        done[priority[i]] = true;
    }

    const watched: Record<string, boolean> = {};
    for (const id of st.watchedIds) watched[id] = true;
    const rest = cands.filter((c) => !done[c.id] && now - (st.predictedAt[c.id] ?? -math.huge) >= cfg.WatchInterval);
    table.sort(rest, (a, b) => {
        if ((watched[a.id] === true) !== (watched[b.id] === true)) return watched[a.id] === true;
        return (st.predictedAt[a.id] ?? -math.huge) < (st.predictedAt[b.id] ?? -math.huge);
    });
    for (let i = 0; i < math.min(rest.length, cfg.MaxWatched); i++) predictOne(st, subject, rest[i], now);
}

function prune(st: SubjectState, cands: Candidate[]): void {
    const keep: Record<string, boolean> = {};
    for (const c of cands) keep[c.id] = true;
    for (const id of Object.keys(st.tracked)) keep[id] = true;
    for (const id of Object.keys(st.cache)) if (!keep[id]) delete st.cache[id];
    for (const id of Object.keys(st.smoothers)) if (!keep[id]) delete st.smoothers[id];
    for (const id of Object.keys(st.predictedAt)) if (!keep[id]) delete st.predictedAt[id];
}

/** Ids of the creeps some tower is attacking this frame. */
function towerTargets(): Record<string, boolean> {
    const targets: Record<string, boolean> = {};
    for (const tower of Towers()) {
        const target = tower.GetAttackTarget();
        if (target !== null && target !== undefined) targets[creepId(target)] = true;
    }
    return targets;
}

/** What every subject reads this frame. */
interface Frame {
    now: number;
    counters: Counters;
    heroes: HeroSeen[];
    towerTargets: Record<string, boolean>;
}

interface HeroSeen {
    pid: number;
    team: number;
    name: string;
}

function snapshot(heroes: Unit[]): { counters: Counters; seen: HeroSeen[] } {
    const counters: Counters = { lastHits: {}, denies: {} };
    const seen: HeroSeen[] = [];
    for (const h of heroes) {
        const pid = h.GetPlayerID();
        if (counters.lastHits[pid] !== undefined) continue;
        counters.lastHits[pid] = T(h).GetLastHits();
        counters.denies[pid] = T(h).GetDenies();
        seen.push({ pid, team: h.GetTeam(), name: HeroLabel(h) });
    }
    return { counters, seen };
}

/** Counters from just before the match window, with rises already matched to other deaths added back. */
function countersBefore(s: TeamState, st: SubjectState, now: number, current: Counters): Counters {
    let snap = s.history[0];
    for (const h of s.history) {
        if (h.t <= now - COUNTER_MATCH_SECONDS) snap = h;
    }
    if (snap === undefined) return current;
    const before: Counters = { lastHits: {}, denies: {} };
    for (const [pid, v] of pairs(snap.counters.lastHits)) before.lastHits[pid] = v;
    for (const [pid, v] of pairs(snap.counters.denies)) before.denies[pid] = v;
    for (const c of st.credits) {
        if (c.t > snap.t) before[c.counter][c.pid] = (before[c.counter][c.pid] ?? 0) + 1;
    }
    return before;
}

function attribute(s: TeamState, st: SubjectState, subject: Unit, t: Tracked, obs: CreepObs, now: number, current: Counters, refs: HeroRef[]): Killer {
    const killer = Attribute(obs, subject.GetPlayerID(), countersBefore(s, st, now, current), current, refs, t.towerTargeting);
    let pid: number | undefined;
    if (killer.kind === "subject") pid = subject.GetPlayerID();
    else if (killer.kind === "ally" || killer.kind === "enemyHero") {
        const ally = killer.kind === "ally";
        for (const r of refs) if (r.ally === ally && r.name === killer.name) pid = r.pid;
    }
    if (pid !== undefined) st.credits.push({ t: now, counter: t.isDeny ? "denies" : "lastHits", pid });
    return killer;
}

function creepObservations(s: TeamState, st: SubjectState, subject: Unit, frame: Frame, refs: HeroRef[]): CreepObs[] {
    const { now, counters: current } = frame;
    const result: CreepObs[] = [];
    for (const id of Object.keys(st.tracked)) {
        const t = st.tracked[id];
        const c = t.creep;
        let state: "alive" | "dead" | "lost";
        if (c.IsNull()) state = "lost";
        else if (!c.IsAlive()) state = "dead";
        else if (!c.CanBeSeen()) state = "lost";
        else state = "alive";

        if (state === "alive") {
            const p = st.cache[id];
            t.hp = c.GetHealth();
            t.maxHp = c.GetMaxHealth();
            t.dist = GetUnitToUnitDistance(subject, c);
            t.effDmg = p !== undefined ? p.effDmg : EffectiveDamage(subject, c, t.isDeny);
            t.towerTargeting = frame.towerTargets[id] === true;
            result.push({ id, kind: t.kind, isDeny: t.isDeny, alive: true, hp: t.hp, dist: t.dist, prediction: p });
            continue;
        }

        delete st.tracked[id];
        if (state === "lost" && !IsDeathLikely(t.hp, t.maxHp, t.effDmg, t.dist)) continue;
        const obs: CreepObs = { id, kind: t.kind, isDeny: t.isDeny, alive: false, hp: 0, dist: t.dist };
        obs.killer = attribute(s, st, subject, t, obs, now, current, refs);
        result.push(obs);
    }
    while (st.credits.length > 0 && now - st.credits[0].t > HISTORY_SECONDS) table.remove(st.credits, 1);
    return result;
}

function subjectObservation(st: SubjectState, subject: Unit, target: Unit | undefined, now: number): SubjectObs {
    const u = T(subject);
    const alive = subject.IsAlive();
    const inFight = now - st.lastHeroAttackAt <= HERO_FIGHT_SECONDS;
    let anim: SubjectObs["anim"] = "none";
    let swingStart: number | undefined;
    if (ATTACK_ACTIVITIES[u.GetAnimActivity()] === true) {
        const cycle = u.GetAnimCycle();
        anim = cycle < u.GetAttackPoint() ? "swing" : "followthrough";
        swingStart = now - cycle / u.GetAttackSpeed();
    }
    return {
        now,
        alive,
        eligible: alive && !u.IsStunned() && !u.IsHexed() && !u.IsChanneling() && !inFight,
        harassed: u.WasRecentlyDamagedByAnyHero(HARASS_SECONDS),
        target: target !== undefined && !target.IsHero() ? creepId(target) : undefined,
        anim,
        swingStart,
        lastHits: u.GetLastHits(),
        denies: u.GetDenies(),
    };
}

function fmt(x: number | undefined): string {
    return x === undefined ? "-" : string.format("%.2f", x);
}

function onVerdict(s: TeamState, st: SubjectState, subject: Unit, v: Verdict, now: number): void {
    if (IsPlayerBot(subject.GetPlayerID())) {
        HDebug.Log("trainer", `selftest predicted=${fmt(v.predictedLand)} actual=${fmt(v.landedAt)} verdict=${v.kind}`);
        return;
    }
    st.verdictLines.push({ text: v.reason, kind: v.kind, at: now });
    while (st.verdictLines.length > VERDICT_LINES_KEPT) table.remove(st.verdictLines, 1);

    const toChat = !Settings.Get().ScreenText || s.chat === "all" || (s.chat === "misses" && MISS_KINDS[v.kind] === true);
    if (toChat && now - s.lastChatAt >= CHAT_INTERVAL) {
        s.lastChatAt = now;
        queueReply(s, v.reason);
    }
}

function stepSubject(s: TeamState, subject: Unit, frame: Frame): void {
    const now = frame.now;
    const cfg = Settings.Get();
    const st = subjectState(s, subject.GetPlayerID());
    const rawTarget = subject.GetAttackTarget();
    const target = rawTarget === null || rawTarget === undefined ? undefined : rawTarget;
    if (target !== undefined && target.IsHero()) st.lastHeroAttackAt = now;

    const cands = candidatesFor(subject, s.denies);
    refreshPredictions(st, subject, cands, target, now);
    const wasBar: Record<string, boolean> = {};
    for (const id of st.barIds) wasBar[id] = true;
    const ranked = cands.map((c) => {
        const p = st.cache[c.id];
        const prediction = p !== undefined && wasBar[c.id] === true ? { ...p, startClose: p.startClose - BAR_STICKINESS } : p;
        return { creep: c.creep, isDeny: c.isDeny, prediction };
    });
    const selected = SelectCreeps(subject, ranked, MAX_BARS, cfg.MaxWatched);
    const isDeny: Record<string, boolean> = {};
    for (const c of cands) isDeny[c.id] = c.isDeny;
    st.barIds = selected.bars.map((u) => creepId(u));
    st.watchedIds = selected.watched.map((u) => creepId(u));
    st.bars = st.barIds.map((id) => st.cache[id]);
    st.predictions = [...st.bars, ...st.watchedIds.map((id) => st.cache[id])];
    for (const u of [...selected.bars, ...selected.watched]) {
        const id = creepId(u);
        if (st.tracked[id] === undefined) {
            st.tracked[id] = { creep: u, kind: CreepKind(u), isDeny: isDeny[id], hp: u.GetHealth(), maxHp: u.GetMaxHealth(), effDmg: 0, dist: 0, towerTargeting: false };
        }
    }

    const team = subject.GetTeam();
    const refs: HeroRef[] = frame.heroes.map((h) => ({ pid: h.pid, name: h.name, ally: h.team === team }));
    const creeps = creepObservations(s, st, subject, frame, refs);
    prune(st, cands);

    const events: JudgeEvent[] = st.judge.Step(subjectObservation(st, subject, target, now), creeps);
    for (const e of events) {
        st.stats.Add(e);
        if (e.type === "verdict") onVerdict(s, st, subject, e.v, now);
    }
}

function checkpoints(s: TeamState, human: SubjectState | undefined, now: number): void {
    let post = false;
    const dota = DotaTime();
    for (const c of Settings.Get().Checkpoints) {
        if (s.checkpointsDone[c] !== true && dota >= c) {
            s.checkpointsDone[c] = true;
            post = true;
        }
    }
    const helpers = GetTrainerHelpers();
    if (helpers !== undefined) {
        const laning = helpers.IsInLaningPhase();
        if (s.wasLaning === true && !laning) post = true;
        s.wasLaning = laning;
    }
    if (!post || human === undefined) return;
    const lines = summaryLines(s, human);
    human.summary = { lines, at: now };
    for (const line of lines) queueReply(s, line);
}

function run(bot: Unit, team: number, s: TeamState, now: number): void {
    const subjects = subjectsFor(team, bot);
    const { counters, seen } = snapshot([...Heroes(), ...subjects]);
    const frame: Frame = { now, counters, heroes: seen, towerTargets: towerTargets() };
    for (const subject of subjects) stepSubject(s, subject, frame);

    s.history.push({ t: now, counters });
    while (s.history.length > 1 && now - s.history[0].t > HISTORY_SECONDS) table.remove(s.history, 1);

    const pid = humanPID(team);
    const human = pid !== undefined && subjects.some((u) => u.GetPlayerID() === pid) ? s.subjects[pid] : undefined;
    checkpoints(s, human, now);

    if (Settings.Get().ScreenText && human !== undefined) {
        VerdictLines(human.verdictLines, now);
        if (human.summary !== undefined) SummaryText(human.summary.lines, human.summary.at, now);
    }
}

export function Tick(bot: Unit): void {
    if (!Settings.IsEnabled()) return;
    const team = bot.GetTeam();
    if (bot.GetPlayerID() !== TrainerBotPID(team)) return;
    const cfg = Settings.Get();
    if (teams[team] === undefined && !cfg.SelfTest) return;
    const s = stateFor(team);
    const now = GameTime();
    if (cfg.SelfTest && !s.selfTestStarted && GetGameState() === GameState.GameInProgress) {
        s.selfTestStarted = true;
        switchOn(s);
    }
    if (s.replies.length > 0 && now - s.lastReplyAt >= REPLY_INTERVAL) {
        s.lastReplyAt = now;
        bot.ActionImmediate_Chat(s.replies.shift()!, false);
    }
    if (s.spike) {
        const subject = humans(team)[0];
        if (subject !== undefined) SpikeTick(bot, subject);
    }
    if (s.on) run(bot, team, s, now);
}
