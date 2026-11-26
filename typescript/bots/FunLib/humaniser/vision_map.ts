/**
 * Map dump (`Overrides.VisionMap`, probe games only; master proposal docs/proposals/2026-11-18-vision-tool.md step M): the
 * inputs of a sight model that the API gives once, for `tools/hlog/sight.js`. The Radiant VM writes, one batch a frame
 * from its first tick (about 355 frames; it keys on GameTime changing, so a drill's clock reset does no harm):
 *   kind=start  the box (`bx0`..`by1`, from GetWorldBounds, else FALLBACK_HALF; `src` api | fallback) and `step`;
 *   kind=h      one row of the grid: `y`, `x0`, `n`, `hex`, one digit a cell from x0 east: GetHeightLevel (0 to 7),
 *               plus 8 when IsLocationPassable;
 *   kind=t      the next TREE_BATCH tree indices: `xy`, "i:x:y" joined by ";" for each index GetTreeLocation answers;
 *   kind=end    `rows`, `trees` (the count of trees logged);
 *   kind=camp   once the spawner list is in: `xy`, "idx:team:type:x:y:minx:miny:maxx:maxy" joined by ";" for each neutral camp
 *               (GetNeutralSpawners: the place and the spawn box).
 * Tree indices are read until TREE_GAP indices in a row answer nothing (nil or (0, 0)). Reads and logs only; it changes no order. The
 * tick runs under pcall (index.ts), so a run is judged by its row counts.
 */
import { Team, Unit } from "bots/ts_libs/dota";
import * as Overrides from "bots/FunLib/humaniser/overrides";
import * as Telemetry from "bots/FunLib/humaniser/telemetry";
import * as Camps from "bots/FunLib/humaniser/camps";

declare const GetWorldBounds: ((this: void) => number[]) | undefined;

/** The grid step: 64 is the gridnav cell. */
const STEP = 64;
/** The box when GetWorldBounds is missing: the 7.33+ map's playable area lies inside it. `judgement`. */
const FALLBACK_HALF = 10240;
const TREE_BATCH = 100;
const TREE_GAP = 400;

type Phase = "start" | "h" | "t" | "end" | "done";

let phase: Phase = "start";
let frameAt: number | undefined;
let box = { x0: -FALLBACK_HALF, y0: -FALLBACK_HALF, x1: FALLBACK_HALF, y1: FALLBACK_HALF };
let rowY = 0;
let rows = 0;
let treeAt = 0;
let treeMiss = 0;
let trees = 0;
let campsLogged = false;

function camps(): void {
    const list = Camps.Spawners();
    if (list.length === 0) return;
    const parts: string[] = [];
    const f = math.floor;
    for (const s of list) {
        parts.push(`${s.idx}:${s.team}:${s.type}:${f(s.location.x)}:${f(s.location.y)}:${f(s.min.x)}:${f(s.min.y)}:${f(s.max.x)}:${f(s.max.y)}`);
    }
    Telemetry.Event("vmap", [["kind", "camp"], ["xy", parts.join(";")]]);
    campsLogged = true;
}

function bounds(): [typeof box, string] {
    if (GetWorldBounds === undefined) return [box, "fallback"];
    const [ok, raw] = pcall(GetWorldBounds);
    if (!ok || type(raw) !== "table") return [box, "fallback"];
    // Typed, so the indices compile 1-based.
    const b = raw as number[];
    if (type(b[0]) !== "number" || type(b[3]) !== "number") return [box, "fallback"];
    return [{ x0: b[0], y0: b[1], x1: b[2], y1: b[3] }, "api"];
}

function cell(x: number, y: number): number {
    const v = Vector(x, y, 0);
    const [okH, h] = pcall(GetHeightLevel, v);
    const [okP, p] = pcall(IsLocationPassable, v);
    const level = okH && type(h) === "number" ? math.max(0, math.min(7, math.floor(h as number))) : 0;
    return level + (okP && p === true ? 8 : 0);
}

function row(): void {
    const x0 = math.floor(box.x0 / STEP) * STEP;
    const n = math.floor((box.x1 - x0) / STEP) + 1;
    let hex = "";
    for (let i = 0; i < n; i++) hex += string.format("%x", cell(x0 + i * STEP, rowY));
    Telemetry.Event("vmap", [["kind", "h"], ["y", rowY], ["x0", x0], ["n", n], ["hex", hex]]);
    rows++;
    rowY += STEP;
}

function treeBatch(): void {
    const parts: string[] = [];
    for (let k = 0; k < TREE_BATCH && treeMiss < TREE_GAP; k++, treeAt++) {
        const [ok, loc] = pcall(GetTreeLocation, treeAt);
        // An index with no tree answers (0, 0) (visionmap1: indices 2,476 to 137,799), not nil.
        if (!ok || loc === undefined || loc === null || (loc.x === 0 && loc.y === 0)) {
            treeMiss++;
            continue;
        }
        treeMiss = 0;
        trees++;
        parts.push(`${treeAt}:${math.floor(loc.x)}:${math.floor(loc.y)}`);
    }
    if (parts.length > 0) Telemetry.Event("vmap", [["kind", "t"], ["xy", parts.join(";")]]);
}

export function Tick(bot: Unit): void {
    if ((phase === "done" && campsLogged) || bot.GetTeam() !== Team.Radiant || Overrides.Get("VisionMap") !== true) return;
    const now = GameTime();
    if (now === frameAt) return;
    frameAt = now;
    if (!campsLogged) camps();
    if (phase === "done") return;
    if (phase === "start") {
        const [b, src] = bounds();
        box = b;
        rowY = math.floor(box.y0 / STEP) * STEP;
        Telemetry.Event("vmap", [["kind", "start"], ["bx0", box.x0], ["by0", box.y0], ["bx1", box.x1], ["by1", box.y1], ["step", STEP], ["src", src]]);
        phase = "h";
    } else if (phase === "h") {
        row();
        if (rowY > box.y1) phase = "t";
    } else if (phase === "t") {
        treeBatch();
        if (treeMiss >= TREE_GAP) phase = "end";
    } else {
        Telemetry.Event("vmap", [["kind", "end"], ["rows", rows], ["trees", trees]]);
        phase = "done";
    }
}
