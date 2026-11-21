/**
 * Shadow choice line (Ours.ChoiceShadow, logging only; design approved 22/11/2026): per hero of ours, which mode OHA's own
 * desires would have picked beside the mode Valve holds the hero in, and when they differ, the module of ours that made
 * the difference. OHA's GetDesire bodies cannot be asked twice (latches, smoothing, item swaps, actions), so the only
 * values read are the ones the single real call returned, noted by Chooser.Gate between OHA's code and the drive's After.
 * A frame's values are logged on the next frame's first gate call, beside the active mode Valve chose from them.
 * Ours.ChoiceProbe (diagnostic, default off, never for scored games): roam and team_roam's code runs where the drive would
 * zero it before running it, so the line has their value; the drive's value is still returned (Gate), but the bodies' side
 * effects (item swaps, roam latches, Intent's sample) then happen as they would with OHA in charge.
 */
import { BotMode, Unit } from "bots/ts_libs/dota";
import * as Arbiter from "bots/FunLib/humaniser/arbiter";
import * as HDebug from "bots/FunLib/humaniser/debug";
import * as Intent from "bots/FunLib/humaniser/intent";
import * as Ours from "bots/FunLib/humaniser/ours";
import * as Overrides from "bots/FunLib/humaniser/overrides";
import * as RetreatState from "bots/FunLib/humaniser/retreat_state";
import * as Telemetry from "bots/FunLib/humaniser/telemetry";
import * as CoreLastHit from "bots/FunLib/humaniser/states/core_last_hit";
import * as SupportDeny from "bots/FunLib/humaniser/states/support_deny";
import * as Trade from "bots/FunLib/humaniser/states/trade";

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

/** The modes Ours.ChoiceProbe asks where the drive zeroes them before their code. */
export const PROBED: Record<string, true> = { roam: true, team_roam: true };

/** judgement: seconds between lines per hero when the active mode does not change. */
const PERIOD = 1;
/** judgement: a mode's note older than this is not this frame's (Valve asks every mode every frame). */
const FRESH = 0.5;

interface Note {
    t: number;
    /** OHA's own value (inner's, or the probe's); undefined when not computed. */
    v?: number;
    /** What the gate returned. */
    out: any;
    /** Why OHA's code was not asked (Chooser's Decide branch), or `ours` when the inner value is ours. */
    why?: string;
    probed: boolean;
}

interface Hero {
    frame: number;
    notes: Record<string, Note>;
    act?: string;
    at: number;
}

const heroes: Record<number, Hero> = {};

function heroOf(pid: number): Hero {
    let h = heroes[pid];
    if (h === undefined) {
        h = { frame: -math.huge, notes: {}, at: -math.huge };
        heroes[pid] = h;
    }
    return h;
}

/** Whether the inner value of `mode` is our desire, not OHA's (retreat's own episode, the trade's attack desire). */
function oursFirst(bot: Unit, mode: string): boolean {
    if (mode === "retreat") return RetreatState.Owns(bot);
    if (mode === "attack") return Trade.OwnsFrame(bot);
    return false;
}

/**
 * Called by Chooser.Gate once per mode call, switch on: `inner` is what OHA's code returned (undefined when the gate did
 * not ask it: `why` names the gate's branch), `out` what the gate returns.
 */
export function Note(bot: Unit, mode: string, inner: any, out: any, why: string | undefined, probed: boolean): void {
    pcall(() => {
        const h = heroOf(bot.GetPlayerID());
        const n: Note = { t: DotaTime(), out, probed };
        if (why !== undefined && !probed) n.why = why;
        else if (type(inner) !== "number") n.why = "valve";
        else if (oursFirst(bot, mode)) n.why = "ours";
        else n.v = inner;
        // Our value stands in `out` for ours-first modes; keep it for the candidates' fields.
        h.notes[mode] = n;
    });
}

/** Runs OHA's body for a probed mode; its value or undefined. The caller returns the drive's value whatever this does. */
export function Probe(inner: () => any): any {
    const [ok, v] = pcall(inner);
    return ok ? v : undefined;
}

/** The branches of ours inside a mode file's own GetDesire (the line marks the mode's value as mixed). */
function mixed(bot: Unit): string[] {
    const out: string[] = [];
    if (CoreLastHit.Applies(bot) || SupportDeny.Applies(bot) || Overrides.LaneOnly(bot)) out.push("laning");
    if (Trade.OwnsFights(bot)) out.push("team_roam");
    if (Arbiter.DeniesOhaRune(bot)) out.push("rune");
    return out;
}

const MIX_MODULE: Record<string, string> = {
    laning: "CoreLastHit:bOwnsThink",
    team_roam: "Trade:bLaneFightsOurs",
    rune: "ArbiterDrive:DeniesOhaRune",
};

/** The source of an Intent claim on the mode's value (Intent.Explain's `by`), when not raw. */
function claimOf(bot: Unit, botMode: number | undefined): string | undefined {
    if (botMode === undefined) return undefined;
    const e = Intent.Explain(bot, botMode);
    const [src] = string.match(e, " by (.+)$");
    return src !== undefined && src !== "raw" ? src : undefined;
}

function whyModule(why: string, pick: string | undefined): string {
    if (why === "drive") return `ArbiterDrive:DriveDecide(${pick ?? "?"})`;
    if (why === "hold:job") return "JobChooser:Hold(job)";
    if (why === "hold:retreat") return "Retreat:Hold(episode)";
    if (why === "host") return "JobChooser:host";
    if (why === "drill") return "Drill:InLaneDenies";
    if (why === "rig") return "Drill:RigDesire";
    return why;
}

const EPS = 1e-6;

function emit(bot: Unit, h: Hero, act: string, now: number, job: string | undefined): void {
    const pid = bot.GetPlayerID();
    // The pick the drive enforced last frame (Drive itself would recompute for this frame).
    const pick = Arbiter.Drives(bot) ? Arbiter.LastPick(bot) : undefined;
    const fields: [string, any][] = [["pid", pid], ["kind", "shadow"], ["win", act]];
    const mix = mixed(bot);
    const mixSet: Record<string, true> = {};
    for (const m of mix) mixSet[m] = true;
    let top: string | undefined;
    let tv = -math.huge;
    let inc = 0;
    const gate: string[] = [];
    const probed: string[] = [];
    const claims: string[] = [];
    const byName: Record<string, Note | undefined> = {};
    const claimByName: Record<string, string | undefined> = {};
    for (const [mode, name, botMode] of MODES) {
        const n0 = h.notes[mode];
        const n = n0 !== undefined && h.frame - n0.t <= FRESH ? n0 : undefined;
        byName[name] = n;
        let val: any;
        if (n === undefined) val = "-valve";
        else if (n.v === undefined) val = `-${n.why === "hold:job" || n.why === "hold:retreat" ? "hold" : n.why === "host" ? "ours" : n.why}`;
        else val = n.v;
        fields.push([`d_${name}`, val]);
        if (n === undefined || n.v === undefined) {
            inc = 1;
        } else {
            if (n.v > tv + EPS) {
                tv = n.v;
                top = name;
            }
            if (n.probed) probed.push(name);
            if (!n.probed) {
                const c = claimOf(bot, botMode);
                if (c !== undefined) {
                    claims.push(`${name}=${c}`);
                    claimByName[name] = c;
                }
            }
        }
        // The `d_` reasons already say which modes the gate set before their code; this lists the computed ones it moved.
        if (n !== undefined && n.v !== undefined && type(n.out) === "number" && math.abs(n.out - n.v) > EPS) gate.push(`${name}:${string.format("%.2f", n.out)}`);
    }
    let how: string | undefined;
    let by: string | undefined;
    if (top !== undefined && top !== act) {
        const T = byName[top]!;
        const W = byName[act];
        const wOut = W !== undefined && type(W.out) === "number" ? (W.out as number) : undefined;
        if (type(T.out) === "number" && T.out < T.v! - EPS && (wOut === undefined || T.v! > wOut + EPS)) {
            how = "zeroed";
            by = T.probed ? whyModule("drive", pick?.name) : `ArbiterDrive:DriveAfter borrowed(${pick?.name ?? "?"})`;
        } else if (W === undefined) {
            how = "valve";
            by = `Valve:${act}`;
        } else if (W.v === undefined && W.why !== undefined && W.why !== "valve") {
            how = "outbid";
            by = W.why === "ours" ? (act === "retreat" ? "Retreat:Desire" : act === "attack" ? "Trade:Desire" : act) : whyModule(W.why, pick?.name);
        } else if (W.v !== undefined && wOut !== undefined && wOut > W.v + EPS) {
            how = "held";
            by = act === "laning" ? "ArbiterDrive:DriveAfter lane_floor" : `ArbiterDrive:DriveAfter(${act})`;
        } else if (claimByName[act] !== undefined) {
            how = "outbid";
            by = `Intent:${claimByName[act]}`;
        } else if (mixSet[act] === true) {
            how = "outbid";
            by = MIX_MODULE[act] ?? act;
        } else {
            how = "valve";
            by = "Valve:arbitration";
        }
    }
    fields.push(["top", top], ["tv", top !== undefined ? tv : undefined], ["inc", inc], ["how", how], ["by", by]);
    fields.push(["mix", mix.length > 0 ? mix.join(",") : undefined]);
    fields.push(["clm", claims.length > 0 ? claims.join(",") : undefined]);
    fields.push(["pr", probed.length > 0 ? probed.join(",") : undefined]);
    fields.push(["gate", gate.length > 0 ? gate.join(",") : undefined]);
    // Our candidates: the drive's pick and the ones that apply (read only: the drive asks them every frame), and our desires.
    if (pick !== undefined) {
        fields.push(["pick", pick.name]);
        const cands: string[] = [];
        for (const c of Arbiter.Candidates(bot, job)) if (c.applies) cands.push(`${c.name}:${c.group}`);
        fields.push(["cand", cands.join(",")]);
        fields.push(["lfl", pick.name === "lane" ? Arbiter.SETTINGS.LaneDesire : undefined]);
    }
    const r = byName["retreat"];
    if (r !== undefined && r.why === "ours" && type(r.out) === "number") fields.push(["rdes", r.out]);
    const a = byName["attack"];
    if (a !== undefined && a.why === "ours" && type(a.out) === "number") fields.push(["tdes", a.out]);
    const f = byName["farm"];
    if (f !== undefined && f.v === undefined && (f.why === "drive" || f.why === "host") && type(f.out) === "number") fields.push(["hdes", f.out]);
    Telemetry.EventUntyped("choice", fields);
    h.act = act;
    h.at = now;
}

/**
 * Called first in every gate call, switch on: on a hero's first call of a new frame the last frame's notes are complete,
 * and the active mode is Valve's choice from them; a line goes out on a change of that mode or every PERIOD.
 */
export function Frame(bot: Unit, jobName: (this: void) => string | undefined): void {
    pcall(() => {
        const h = heroOf(bot.GetPlayerID());
        const now = DotaTime();
        if (h.frame === now) return;
        const prev = h.frame;
        if (prev !== -math.huge && Telemetry.IsEnabled()) {
            const act = HDebug.ModeName(bot.GetActiveMode());
            if (act !== h.act || now - h.at >= PERIOD) emit(bot, h, act, now, jobName());
        }
        h.frame = now;
    });
    // The new frame's notes replace the old ones as they come; a mode not asked this frame goes stale (FRESH).
}

/** Tests: forget every hero. */
export function Reset(): void {
    for (const [k] of pairs(heroes)) heroes[k] = undefined as any;
}

/** Whether the line or the probe needs the gate's notes (both need ChoiceShadow). */
export function On(): boolean {
    return Ours.On("ChoiceShadow");
}
