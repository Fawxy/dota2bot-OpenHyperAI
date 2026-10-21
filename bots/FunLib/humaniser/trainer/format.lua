--[[ Generated with https://github.com/TypeScriptToLua/TypeScriptToLua ]]
local ____exports = {}
local function Round2(x)
    return math.floor(math.abs(x) * 100 + 0.5) / 100
end
--- Two decimals with trailing zeros trimmed: 0.10 -> "0.1", 1.00 -> "1".
function ____exports.Sec(x)
    local text = string.format(
        "%.2f",
        Round2(x)
    )
    return (string.gsub((string.gsub(text, "0+$", "")), "%.$", ""))
end
--- Like Sec, with an explicit sign. A value that rounds to zero is positive.
function ____exports.Signed(x)
    local negative = x < 0 and Round2(x) > 0
    return (negative and "-" or "+") .. ____exports.Sec(x)
end
return ____exports
