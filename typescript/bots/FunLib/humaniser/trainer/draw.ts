/** Trainer screen text. Drawn directly, not through HDebug, so it shows with Debug off. Draws last one frame. */
import * as Settings from "bots/FunLib/humaniser/trainer/settings";
import { VerdictKind } from "bots/FunLib/humaniser/trainer/judge";
import { CreepKind, DrawLine } from "bots/FunLib/humaniser/trainer/api";
import { Prediction } from "bots/FunLib/humaniser/trainer/predict";
import { Unit } from "bots/ts_libs/dota";

const LINE_HEIGHT = 14;
const MAX_LINES = 3;
const LINE_SECONDS = 6;
const SUMMARY_OFFSET = 50;
const SUMMARY_SECONDS = 15;

export interface VerdictLine {
    text: string;
    kind: VerdictKind;
    at: number;
}

function colour(kind: VerdictKind): [number, number, number] {
    if (kind === "PERFECT") return [0, 255, 0];
    if (kind === "OK") return [255, 255, 255];
    if (kind === "CANCELLED") return [160, 160, 160];
    return [255, 140, 0];
}

export function VerdictLines(lines: VerdictLine[], now: number): void {
    const cfg = Settings.Get();
    const fresh = lines.filter((l) => now - l.at < LINE_SECONDS);
    const first = math.max(fresh.length - MAX_LINES, 0);
    for (let i = first; i < fresh.length; i++) {
        const [r, g, b] = colour(fresh[i].kind);
        DebugDrawText(cfg.TextX, cfg.TextY + LINE_HEIGHT * (i - first), fresh[i].text, r, g, b);
    }
}

export function SummaryText(lines: string[], shownAt: number, now: number): void {
    if (now - shownAt >= SUMMARY_SECONDS) return;
    const cfg = Settings.Get();
    for (let i = 0; i < lines.length; i++) {
        DebugDrawText(cfg.TextX, cfg.TextY + SUMMARY_OFFSET + LINE_HEIGHT * i, lines[i], 255, 255, 255);
    }
}

const BAR_Z = 180;
const BAR_WIDTH = 200;
const TICK_HEIGHT = 16;
const MARKER_HEIGHT = 32;
const BAR_MAX_DISTANCE = 1200;
/** Units per second. The swing line sits LINE_OFFSET from the left, so the bar shows 0.75 s of window behind it and 1.75 s of countdown ahead. */
const SCALE = 80;
const LINE_OFFSET = 60;
const GREY: [number, number, number] = [128, 128, 128];
const WHITE: [number, number, number] = [255, 255, 255];
const BLUE: [number, number, number] = [80, 160, 255];
const YELLOW: [number, number, number] = [255, 255, 0];
const RED: [number, number, number] = [255, 60, 60];

const STATE_OFFSET = 150;
/** Inside this many seconds before the window opens, the word switches from WAIT to READY. */
const READY_LEAD = 0.3;

/** One word for what the bar is showing now, so the bar can be checked against plain text. */
export function BarState(p: Prediction, now: number): string {
    if (now < p.startOpen - READY_LEAD) return "WAIT";
    if (now < p.startOpen) return "READY";
    if (now <= p.startClose) return p.isDeny ? "DENY" : "ATTACK";
    return "LATE";
}

function windowColour(p: Prediction): [number, number, number] {
    if (p.isDeny) return [0, 255, 255];
    if (p.uncertain) return [255, 191, 0];
    return [0, 255, 0];
}

/**
 * Countdown bar over each predicted creep. The white swing line never moves; the window is drawn
 * from that line leftwards, its length the window's duration. The tall marker is now, sliding left
 * at real-time speed: it crosses the line as the window opens and leaves the zone as it closes.
 */
export function Bars(subject: Unit, preds: Prediction[], now: number, swingStart?: number): void {
    if (!subject.IsAlive()) return;
    const target = subject.GetAttackTarget();
    const targetId = target === undefined || target === null ? undefined : tostring(target);
    const cfg = Settings.Get();
    let row = 0;
    for (const p of preds) {
        const creep = p.creep;
        if (!creep.IsAlive() || GetUnitToUnitDistance(subject, creep) > BAR_MAX_DISTANCE) continue;
        const loc = creep.GetLocation();
        const left = loc.x - BAR_WIDTH / 2;
        const right = left + BAR_WIDTH;
        const line = left + LINE_OFFSET;
        const z = loc.z + BAR_Z;
        const y = loc.y;
        const clamp = (x: number) => math.max(left, math.min(right, x));
        const xAt = (t: number) => clamp(line + (p.startOpen - t) * SCALE);
        const hline = (from: number, to: number, c: [number, number, number], dz: number) =>
            DrawLine(Vector(from, y, z + dz), Vector(to, y, z + dz), c[0], c[1], c[2]);
        const tick = (x: number, c: [number, number, number], height = TICK_HEIGHT) =>
            DrawLine(Vector(x, y, z), Vector(x, y, z + height), c[0], c[1], c[2]);
        const colour = windowColour(p);

        hline(left, right, GREY, TICK_HEIGHT / 2);
        const windowEnd = clamp(line - (p.startClose - p.startOpen) * SCALE);
        if (windowEnd < line) {
            hline(windowEnd, line, colour, TICK_HEIGHT / 2 + 2);
            tick(windowEnd, colour);
        }
        tick(line, WHITE);
        const marker = now < p.startOpen ? YELLOW : now <= p.startClose ? colour : RED;
        tick(xAt(now), marker, MARKER_HEIGHT);
        const state = BarState(p, now);
        const [r, g, b] = state === "READY" ? WHITE : marker;
        DebugDrawText(cfg.TextX, cfg.TextY + STATE_OFFSET + LINE_HEIGHT * row, `${CreepKind(creep)}: ${state}`, r, g, b);
        row++;
        if (swingStart !== undefined && targetId === tostring(creep)) tick(xAt(swingStart), BLUE);
    }
}
