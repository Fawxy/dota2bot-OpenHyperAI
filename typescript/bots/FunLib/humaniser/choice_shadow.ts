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
import * as RetreatState from "bots/FunLib/humaniser/retreat_state";
import * as Telemetry from "bots/FunLib/humaniser/telemetry";
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
    /** Why OHA's code was not asked (Chooser's Decide branch), `ours` when the inner value is ours, `probe` when the probe gave no number. */
    why?: string;
    probed: boolean;
    /** A branch of ours inside the mode's own GetDesire acted in this call (mixOf, read at the call). */
    mix?: boolean;
    /** The Intent claim or stickiness on the value (Intent.Explain's `by`, not raw), read at the call. */
    clm?: string;
}

/** The frame's reads of the drive, taken as its notes come (after Decide), so a line pairs them with its values. */
interface Snap {
    pick?: string;
    host?: string;
    group?: number;
    cand?: string;
}

interface Hero {
    frame: number;
    notes: Record<string, Note>;
    act?: string;
    at: number;
    /** The frame `snap` belongs to. */
    snapFrame: number;
    snap: Snap;
    jobName?: (this: void) => string | undefined;
    /** Set by MarkMix while laning's body returns from its branch of ours; read and cleared by laning's Note. */
    laneMark: boolean;
}

const heroes: Record<number, Hero> = {};

function heroOf(pid: number): Hero {
    let h = heroes[pid];
    if (h === undefined) {
        h = { frame: -math.huge, notes: {}, at: -math.huge, snapFrame: -math.huge, snap: {}, laneMark: false };
        heroes[pid] = h;
    }
    return h;
}

const BOT_MODE: Record<string, number | undefined> = {};
for (const [mode, , botMode] of MODES) BOT_MODE[mode] = botMode;

/**
 * Whether the inner value of `mode` is our desire, not OHA's (retreat's own episode, the trade's attack desire). Neutral,
 * but RetreatState.Owns reaches Phase.LaningHeld here, earlier in the frame than without the line, so its first read's
 * `arb ph=own` line may come out in another order beside the frame's other lines.
 */
function oursFirst(bot: Unit, mode: string): boolean {
    if (mode === "retreat") return RetreatState.Owns(bot);
    if (mode === "attack") return Trade.OwnsFrame(bot);
    return false;
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

/**
 * Whether a branch of ours inside `mode`'s own GetDesire acted in the call just made (`ran`: OHA's code ran): laning's
 * MarkMix; team_roam: Trade's fights skip OHA's fight branches; rune: DeniesOhaRune denies OHA's trips.
 */
function mixOf(bot: Unit, h: Hero, mode: string, ran: boolean): boolean {
    if (mode === "laning") {
        const m = h.laneMark;
        h.laneMark = false;
        return ran && m;
    }
    if (!ran) return false;
    if (mode === "team_roam") return Trade.OwnsFights(bot);
    if (mode === "rune") return Arbiter.DeniesOhaRune(bot);
    return false;
}

/** The source of an Intent claim on the mode's value (Intent.Explain's `by`), when not raw. */
function claimOf(bot: Unit, botMode: number | undefined): string | undefined {
    if (botMode === undefined) return undefined;
    const e = Intent.Explain(bot, botMode);
    const [src] = string.match(e, " by (.+)$");
    return src !== undefined && src !== "raw" ? src : undefined;
}

/** The drive's pick once Decide has computed it this frame, and the candidates that apply beside it (read only). */
function snapshot(bot: Unit, h: Hero): void {
    if (h.snapFrame !== h.frame) {
        h.snapFrame = h.frame;
        h.snap = {};
    }
    if (h.snap.pick !== undefined || !Arbiter.Drives(bot)) return;
    const p = Arbiter.PickThisFrame(bot);
    if (p === undefined) return;
    const cands: string[] = [];
    for (const c of Arbiter.Candidates(bot, h.jobName !== undefined ? h.jobName() : undefined)) if (c.applies) cands.push(`${c.name}:${c.group}`);
    h.snap = { pick: p.name, host: p.host, group: p.group, cand: cands.join(",") };
}

/**
 * Called by Chooser.Gate once per mode call, switch on: `inner` is what OHA's code returned (undefined when the gate did
 * not ask it: `why` names the gate's branch), `out` what the gate returns. Everything the line reads is taken here, in the
 * frame of the values.
 */
export function Note(bot: Unit, mode: string, inner: any, out: any, why: string | undefined, probed: boolean): void {
    pcall(() => {
        const h = heroOf(bot.GetPlayerID());
        snapshot(bot, h);
        const n: Note = { t: DotaTime(), out, probed };
        if (probed && type(inner) !== "number") n.why = "probe";
        else if (why !== undefined && !probed) n.why = why;
        else if (type(inner) !== "number") n.why = "valve";
        else if (oursFirst(bot, mode)) n.why = "ours";
        else n.v = inner;
        // Our value stands in `out` for ours-first modes; keep it for the candidates' fields.
        if (mixOf(bot, h, mode, why === undefined || probed)) n.mix = true;
        if (n.v !== undefined && !probed) n.clm = claimOf(bot, BOT_MODE[mode]);
        h.notes[mode] = n;
    });
}

/** Runs OHA's body for a probed mode; its value or undefined. The caller returns the drive's value whatever this does. */
export function Probe(inner: () => any): any {
    const [ok, v] = pcall(inner);
    return ok ? v : undefined;
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

function emit(bot: Unit, h: Hero, act: string): void {
    const pid = bot.GetPlayerID();
    // The frame's own reads (Note's snapshot), not the new frame's.
    const snap: Snap = h.snapFrame === h.frame ? h.snap : {};
    const pick = snap.pick;
    const fields: [string, any][] = [["pid", pid], ["kind", "shadow"], ["win", act]];
    let top: string | undefined;
    // A mode at 0 picks nothing: OHA's top needs a positive desire.
    let tv = 0;
    const gate: string[] = [];
    const probed: string[] = [];
    const claims: string[] = [];
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
            if (n.probed) probed.push(name);
            if (n.clm !== undefined) claims.push(`${name}=${n.clm}`);
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
            by = T.probed ? whyModule("drive", pick) : `ArbiterDrive:DriveAfter borrowed(${pick ?? "?"})`;
        } else if (W === undefined) {
            how = "valve";
            by = `Valve:${act}`;
        } else if (W.v === undefined && W.why !== undefined && W.why !== "valve" && W.why !== "probe") {
            how = "outbid";
            by = W.why === "ours" ? (act === "retreat" ? "Retreat:Desire" : act === "attack" ? "Trade:Desire" : act) : whyModule(W.why, pick);
        } else if (W.v !== undefined && wOut !== undefined && wOut > W.v + EPS) {
            how = "held";
            by = act === "laning" ? "ArbiterDrive:DriveAfter lane_floor" : `ArbiterDrive:DriveAfter(${act})`;
        } else if (W.clm !== undefined) {
            how = "outbid";
            by = `Intent:${W.clm}`;
        } else {
            // A branch of ours inside win's own body (`mix`) is already in win's desire, which is under top's: it cannot
            // have made the difference, so the line falls to Valve's arbitration.
            how = "valve";
            by = "Valve:arbitration";
        }
    }
    fields.push(["top", top], ["tv", top !== undefined ? tv : undefined], ["how", how], ["by", by]);
    fields.push(["mix", mix.length > 0 ? mix.join(",") : undefined]);
    fields.push(["clm", claims.length > 0 ? claims.join(",") : undefined]);
    fields.push(["pr", probed.length > 0 ? probed.join(",") : undefined]);
    fields.push(["gate", gate.length > 0 ? gate.join(",") : undefined]);
    // The drive's pick and the candidates that apply, as the frame's notes found them.
    if (pick !== undefined) {
        fields.push(["pick", pick]);
        fields.push(["cand", snap.cand]);
        fields.push(["lfl", pick === "lane" ? Arbiter.SETTINGS.LaneDesire : undefined]);
    }
    const r = byName["retreat"];
    if (r !== undefined && r.why === "ours" && type(r.out) === "number") fields.push(["rdes", r.out]);
    const a = byName["attack"];
    if (a !== undefined && a.why === "ours" && type(a.out) === "number") fields.push(["tdes", a.out]);
    // The chooser's host desire: farm is its only host (Chooser HOST), on the hold path or as the drive's pick's host
    // (DriveDecide: a job hosted in farm, or the OHA pick's farmHost); a farm the drive zeroes for another pick is not it.
    const f = byName["farm"];
    const farmHost =
        f !== undefined && f.v === undefined && (f.why === "host" || (f.why === "drive" && pick !== undefined && (snap.host === "farm" || (snap.group ?? 0) > 6)));
    if (farmHost && type(f!.out) === "number") fields.push(["hdes", f!.out]);
    Telemetry.EventUntyped("choice", fields);
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
            if (act !== h.act || now - h.at >= PERIOD) {
                emit(bot, h, act);
                h.act = act;
                h.at = now;
            }
        }
        h.frame = now;
        h.jobName = jobName;
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
