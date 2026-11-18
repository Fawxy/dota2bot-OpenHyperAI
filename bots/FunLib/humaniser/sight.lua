--[[ Generated with https://github.com/TypeScriptToLua/TypeScriptToLua ]]
local ____exports = {}
--- IsLocationVisible on a grid over the box (x0r, y0r) to (x1r, y1r), its corner snapped down to `step`, as
-- `x0,y0,nx,ny,step,hex`: bit i of the hex (from the high bit of the first digit) is cell (i % nx, floor(i / nx)) from the
-- south-west corner (x0, y0); the last digit is padded with zeros.
function ____exports.VisionGridBox(x0r, y0r, x1r, y1r, step, z)
    local x0 = math.floor(x0r / step) * step
    local y0 = math.floor(y0r / step) * step
    local nx = math.ceil((x1r - x0) / step) + 1
    local ny = math.ceil((y1r - y0) / step) + 1
    local hex = ""
    local nib = 0
    local bits = 0
    do
        local j = 0
        while j < ny do
            do
                local i = 0
                while i < nx do
                    nib = nib * 2 + (IsLocationVisible(Vector(x0 + i * step, y0 + j * step, z)) and 1 or 0)
                    bits = bits + 1
                    if bits == 4 then
                        hex = hex .. string.format("%x", nib)
                        nib = 0
                        bits = 0
                    end
                    i = i + 1
                end
            end
            j = j + 1
        end
    end
    if bits > 0 then
        hex = hex .. string.format("%x", nib * 2 ^ (4 - bits))
    end
    return (((((((((tostring(x0) .. ",") .. tostring(y0)) .. ",") .. tostring(nx)) .. ",") .. tostring(ny)) .. ",") .. tostring(step)) .. ",") .. hex
end
return ____exports
