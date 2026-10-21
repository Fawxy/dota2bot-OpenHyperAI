/** Trainer screen text. Drawn directly, not through HDebug, so it shows with Debug off. Draws last one frame. */
import * as Settings from "bots/FunLib/humaniser/trainer/settings";
import { VerdictKind } from "bots/FunLib/humaniser/trainer/judge";
import { DrawLine } from "bots/FunLib/humaniser/trainer/api";
import { HORIZON, Prediction, STEP } from "bots/FunLib/humaniser/trainer/predict";
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
const BAR_WIDTH = 160;
const TICK_HEIGHT = 16;
const BAR_MAX_DISTANCE = 1200;
const GREY: [number, number, number] = [128, 128, 128];
const WHITE: [number, number, number] = [255, 255, 255];
const BLUE: [number, number, number] = [80, 160, 255];

function windowColour(p: Prediction): [number, number, number] {
    if (p.isDeny) return [0, 255, 255];
    if (p.uncertain) return [255, 191, 0];
    return [0, 255, 0];
}

/** Live timing bars over each predicted creep: the start window on a 2 s axis ("time"), or the creep's HP axis with the landing marker ("hp"). */
export function Bars(subject: Unit, preds: Prediction[], style: "time" | "hp", now: number, swingStart?: number): void {
    if (!subject.IsAlive()) return;
    const target = subject.GetAttackTarget();
    const targetId = target === undefined || target === null ? undefined : tostring(target);
    for (const p of preds) {
        const creep = p.creep;
        if (!creep.IsAlive() || GetUnitToUnitDistance(subject, creep) > BAR_MAX_DISTANCE) continue;
        const loc = creep.GetLocation();
        const left = loc.x - BAR_WIDTH / 2;
        const z = loc.z + BAR_Z;
        const y = loc.y;
        const hline = (from: number, to: number, c: [number, number, number], dz: number) =>
            DrawLine(Vector(from, y, z + dz), Vector(to, y, z + dz), c[0], c[1], c[2]);
        const tick = (x: number, c: [number, number, number]) =>
            DrawLine(Vector(x, y, z), Vector(x, y, z + TICK_HEIGHT), c[0], c[1], c[2]);
        const colour = windowColour(p);

        if (style === "time") {
            const xAt = (t: number) => left + BAR_WIDTH * math.max(0, math.min(1, (t - now) / HORIZON));
            hline(left, left + BAR_WIDTH, GREY, TICK_HEIGHT / 2);
            const open = xAt(p.startOpen);
            const close = xAt(p.startClose);
            if (close > open) {
                hline(open, close, colour, TICK_HEIGHT / 2 + 2);
                tick(open, colour);
                tick(close, colour);
            }
            tick(left, WHITE);
            if (swingStart !== undefined && targetId === tostring(creep)) tick(xAt(swingStart), BLUE);
        } else {
            const maxHp = creep.GetMaxHealth();
            const xHp = (hp: number) => left + BAR_WIDTH * math.max(0, math.min(1, hp / maxHp));
            hline(left, xHp(p.hp), GREY, TICK_HEIGHT / 2);
            tick(xHp(p.effDmg), WHITE);
            const index = math.min(math.floor(p.delay / STEP + 0.5), p.curve.length - 1);
            tick(xHp(p.curve[index]), colour);
        }
    }
}
