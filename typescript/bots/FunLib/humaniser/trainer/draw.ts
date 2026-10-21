/** Trainer screen text. Drawn directly, not through HDebug, so it shows with Debug off. Draws last one frame. */
import * as Settings from "bots/FunLib/humaniser/trainer/settings";
import { VerdictKind } from "bots/FunLib/humaniser/trainer/judge";

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
