/**
 * Shadow choice line (Ours.ChoiceShadow, logging only; design approved 22/11/2026): per hero of ours, which mode OHA's own
 * desires would have picked beside the mode Valve holds the hero in, and when they differ, the module of ours that made
 * the difference. OHA's GetDesire bodies cannot be asked twice (latches, smoothing, item swaps, actions), so the only
 * values read are the ones the single real call returned, noted by Chooser.Gate.
 * A frame's values are logged on the next frame's first gate call, beside the active mode Valve chose from them.
 */
import { BotMode, Unit } from "bots/ts_libs/dota";
import * as HDebug from "bots/FunLib/humaniser/debug";
import * as Ours from "bots/FunLib/humaniser/ours";
import * as RetreatState from "bots/FunLib/humaniser/retreat_state";
import * as Telemetry from "bots/FunLib/humaniser/telemetry";

/** The gate's mode name -> the name Valve's active mode logs as (debug.ts ModeName) and the BotMode Intent keys it by. */
const MODES: [string, string, number | undefined][] = [
    ["laning", "laning", BotMode.Laning],
    ["attack", "attack", BotMode.Attack],
    ["retreat", "retreat", BotMode.Retreat],
    ["farm", "farm", BotMode.Farm],
    ["team_roam", "team_roam", BotMode.TeamRoam],
    ["roam", "roam", BotMode.Roam],
    ["rune", "rune", BotMode.Rune],
    ["ward", "ward", BotMode.Ward],
    ["assemble", "assemble", BotMode.Assemble],
    ["assemble_with_humans", "assemble_h", undefined],
    ["defend_tower_top", "defend_top", BotMode.DefendTowerTop],
    ["defend_tower_mid", "defend_mid", BotMode.DefendTowerMid],
    ["defend_tower_bot", "defend_bot", BotMode.DefendTowerBot],
    ["push_tower_top", "push_top", BotMode.PushTowerTop],
    ["push_tower_mid", "push_mid", BotMode.PushTowerMid],
    ["push_tower_bot", "push_bot", BotMode.PushTowerBot],
    ["roshan", "roshan", BotMode.Roshan],
    ["secret_shop", "secret_shop", BotMode.SecretShop],
    ["side_shop", "side_shop", BotMode.SideShop],
    ["outpost", "outpost", undefined],
];

/** judgement: seconds between lines per hero when the active mode does not change. */
const PERIOD = 1;
/** judgement: a mode's note older than this is not this frame's (Valve asks every mode every frame). */
const FRESH = 0.5;

interface Note {
    t: number;
    /** OHA's own value; undefined when not computed. */
    v?: number;
    /** What the gate returned. */
    out: any;
    /** Why OHA's code was not asked (Chooser's Decide branch), `ours` when the inner value is ours. */
    why?: string;
    /** A branch of ours inside the mode's own GetDesire acted in this call (mixOf, read at the call). */
    mix?: boolean;
}

interface Hero {
    frame: number;
    notes: Record<string, Note>;
    act?: string;
    at: number;
    /** Set by MarkMix while laning's body returns from its branch of ours; read and cleared by laning's Note. */
    laneMark: boolean;
}

const heroes: Record<number, Hero> = {};

function heroOf(pid: number): Hero {
    let h = heroes[pid];
    if (h === undefined) {
        h = { frame: -math.huge, notes: {}, at: -math.huge, laneMark: false };
        heroes[pid] = h;
    }
    return h;
}

const BOT_MODE: Record<string, number | undefined> = {};
for (const [mode, , botMode] of MODES) BOT_MODE[mode] = botMode;

/**
 * Whether the inner value of `mode` is our desire, not OHA's (retreat's own episode). Neutral, but RetreatState.Owns is
 * read here earlier in the frame than without the line, so a line its first read logs may come out in another order.
 */
function oursFirst(bot: Unit, mode: string): boolean {
    return mode === "retreat" && RetreatState.Owns(bot);
}

/**
 * Hook from mode_laning_generic's GetDesire (switch on only): its branch of ours (bOwnsThink's last hit at 0.9, a drill's
 * lane-only hold) set the value it is returning.
 */
export function MarkMix(bot: Unit): void {
    if (!On()) return;
    pcall(() => {
        heroOf(bot.GetPlayerID()).laneMark = true;
    });
}

/** Whether a branch of ours inside `mode`'s own GetDesire acted in the call just made (`ran`: OHA's code ran): laning's MarkMix. */
function mixOf(h: Hero, mode: string, ran: boolean): boolean {
    if (mode !== "laning") return false;
    const m = h.laneMark;
    h.laneMark = false;
    return ran && m;
}

/**
 * Called by Chooser.Gate once per mode call, switch on: `inner` is what OHA's code returned (undefined when the gate did
 * not ask it: `why` names the gate's branch), `out` what the gate returns. Everything the line reads is taken here, in the
 * frame of the values.
 */
export function Note(bot: Unit, mode: string, inner: any, out: any, why: string | undefined): void {
    pcall(() => {
        const h = heroOf(bot.GetPlayerID());
        const n: Note = { t: DotaTime(), out };
        if (why !== undefined) n.why = why;
        else if (type(inner) !== "number") n.why = "valve";
        else if (oursFirst(bot, mode)) n.why = "ours";
        else n.v = inner;
        // Our value stands in `out` for ours-first modes; keep it for the candidates' fields.
        if (mixOf(h, mode, why === undefined)) n.mix = true;
        h.notes[mode] = n;
    });
}

function whyModule(why: string): string {
    if (why === "hold:job") return "JobChooser:Hold(job)";
    if (why === "hold:retreat") return "Retreat:Hold(episode)";
    if (why === "host") return "JobChooser:host";
    if (why === "drill") return "Drill:InLaneDenies";
    if (why === "rig") return "Drill:RigDesire";
    return why;
}

const EPS = 1e-6;

function emit(bot: Unit, h: Hero, act: string): void {
    const pid = bot.GetPlayerID();
    const fields: [string, any][] = [["pid", pid], ["kind", "shadow"], ["win", act]];
    let top: string | undefined;
    // A mode at 0 picks nothing: OHA's top needs a positive desire.
    let tv = 0;
    const gate: string[] = [];
    const mix: string[] = [];
    const byName: Record<string, Note | undefined> = {};
    for (const [mode, name] of MODES) {
        const n0 = h.notes[mode];
        const n = n0 !== undefined && h.frame - n0.t <= FRESH ? n0 : undefined;
        byName[name] = n;
        let val: any;
        if (n === undefined) val = "-valve";
        else if (n.v === undefined) val = `-${n.why === "hold:job" || n.why === "hold:retreat" ? "hold" : n.why === "host" ? "ours" : n.why}`;
        else val = n.v;
        fields.push([`d_${name}`, val]);
        if (n !== undefined && n.mix === true) mix.push(name);
        if (n !== undefined && n.v !== undefined) {
            if (n.v > tv + EPS) {
                tv = n.v;
                top = name;
            }
        }
        // The `d_` reasons already say which modes the gate set before their code; this lists the computed ones it moved.
        if (n !== undefined && n.v !== undefined && type(n.out) === "number" && math.abs(n.out - n.v) > EPS) gate.push(`${name}:${string.format("%.2f", n.out)}`);
    }
    let how: string | undefined;
    let by: string | undefined;
    if (top !== undefined && top !== act) {
        const W = byName[act];
        if (W === undefined) {
            how = "valve";
            by = `Valve:${act}`;
        } else if (W.v === undefined && W.why !== undefined && W.why !== "valve") {
            how = "outbid";
            by = W.why === "ours" ? (act === "retreat" ? "Retreat:Desire" : act) : whyModule(W.why);
        } else {
            // A branch of ours inside win's own body (`mix`) is already in win's desire, which is under top's: it cannot
            // have made the difference, so the line falls to Valve's arbitration.
            how = "valve";
            by = "Valve:arbitration";
        }
    }
    fields.push(["top", top], ["tv", top !== undefined ? tv : undefined], ["how", how], ["by", by]);
    fields.push(["mix", mix.length > 0 ? mix.join(",") : undefined]);
    fields.push(["gate", gate.length > 0 ? gate.join(",") : undefined]);
    const r = byName["retreat"];
    if (r !== undefined && r.why === "ours" && type(r.out) === "number") fields.push(["rdes", r.out]);
    // The chooser's host desire: farm is its only host (Chooser HOST).
    const f = byName["farm"];
    if (f !== undefined && f.v === undefined && f.why === "host" && type(f.out) === "number") fields.push(["hdes", f.out]);
    Telemetry.EventUntyped("choice", fields);
}

/**
 * Called first in every gate call, switch on: on a hero's first call of a new frame the last frame's notes are complete,
 * and the active mode is Valve's choice from them; a line goes out on a change of that mode or every PERIOD.
 */
export function Frame(bot: Unit): void {
    pcall(() => {
        const h = heroOf(bot.GetPlayerID());
        const now = DotaTime();
        if (h.frame === now) return;
        const prev = h.frame;
        if (prev !== -math.huge && Telemetry.IsEnabled()) {
            const act = HDebug.ModeName(bot.GetActiveMode());
            if (act !== h.act || now - h.at >= PERIOD) {
                emit(bot, h, act);
                h.act = act;
                h.at = now;
            }
        }
        h.frame = now;
    });
    // The new frame's notes replace the old ones as they come; a mode not asked this frame goes stale (FRESH).
}

/** Tests: forget every hero. */
export function Reset(): void {
    for (const [k] of pairs(heroes)) heroes[k] = undefined as any;
}

/** Whether the line needs the gate's notes. */
export function On(): boolean {
    return Ours.On("ChoiceShadow");
}
