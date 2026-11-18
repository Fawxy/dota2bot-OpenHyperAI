/**
 * Sight reads shared by telemetry and rigs (proposal docs/proposals/2026-11-18-vision-tool.md in the master repo): what the
 * team sees now, from the API (IsLocationVisible). No model of what it would see from elsewhere lives here yet (step M).
 */

/**
 * IsLocationVisible on a grid over the box (x0r, y0r) to (x1r, y1r), its corner snapped down to `step`, as
 * `x0,y0,nx,ny,step,hex`: bit i of the hex (from the high bit of the first digit) is cell (i % nx, floor(i / nx)) from the
 * south-west corner (x0, y0); the last digit is padded with zeros.
 */
export function VisionGridBox(x0r: number, y0r: number, x1r: number, y1r: number, step: number, z: number): string {
    const x0 = math.floor(x0r / step) * step;
    const y0 = math.floor(y0r / step) * step;
    const nx = math.ceil((x1r - x0) / step) + 1;
    const ny = math.ceil((y1r - y0) / step) + 1;
    let hex = "";
    let nib = 0;
    let bits = 0;
    for (let j = 0; j < ny; j++) {
        for (let i = 0; i < nx; i++) {
            nib = nib * 2 + (IsLocationVisible(Vector(x0 + i * step, y0 + j * step, z)) ? 1 : 0);
            bits++;
            if (bits === 4) {
                hex += string.format("%x", nib);
                nib = 0;
                bits = 0;
            }
        }
    }
    if (bits > 0) hex += string.format("%x", nib * 2 ** (4 - bits));
    return `${x0},${y0},${nx},${ny},${step},${hex}`;
}
