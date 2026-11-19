--[[ Generated with https://github.com/TypeScriptToLua/TypeScriptToLua ]]
local ____exports = {}
local function by(v1, v2, v3, v4, v5)
    return {
        [1] = v1,
        [2] = v2,
        [3] = v3,
        [4] = v4,
        [5] = v5
    }
end
____exports.PICKS = {
    {
        kind = "lasthit",
        rank = by(
            10,
            10,
            10,
            10,
            10
        ),
        claim = by(
            "all",
            "all",
            "all",
            "unclaimed",
            "unclaimed"
        ),
        retarget = true
    },
    {
        kind = "pre_hit",
        rank = by(
            20,
            20,
            20,
            nil,
            nil
        ),
        claim = by(
            "all",
            "all",
            "all",
            "none",
            "none"
        ),
        retarget = false
    },
    {
        kind = "deny",
        rank = by(
            30,
            30,
            30,
            30,
            30
        ),
        claim = by(
            "unattempted",
            "unattempted",
            "unattempted",
            "all",
            "all"
        ),
        retarget = false
    },
    {
        kind = "idle_swing",
        rank = by(
            40,
            40,
            40,
            40,
            40
        ),
        claim = by(
            "all",
            "all",
            "all",
            "all",
            "all"
        ),
        retarget = false
    }
}
--- Whether a position (an ally's, read through lane_config PositionOf) is a core. Undefined is not.
function ____exports.IsCore(pos)
    return pos ~= nil and pos >= 1 and pos <= 3
end
function ____exports.RowOf(kind)
    for ____, r in ipairs(____exports.PICKS) do
        if r.kind == kind then
            return r
        end
    end
    return ____exports.PICKS[1]
end
function ____exports.ClaimOf(kind, pos)
    return ____exports.RowOf(kind).claim[pos]
end
--- Whether a wait on a creep of `kind` moves to another of the same kind (PickRow.retarget).
function ____exports.Retargets(kind)
    return ____exports.RowOf(kind).retarget
end
local function build(pos)
    local rows = {}
    for ____, r in ipairs(____exports.PICKS) do
        if r.rank[pos] ~= nil then
            rows[#rows + 1] = r
        end
    end
    table.sort(
        rows,
        function(a, b) return a.rank[pos] < b.rank[pos] end
    )
    local out = {}
    for ____, r in ipairs(rows) do
        out[#out + 1] = r.kind
    end
    return out
end
local ORDERS = {}
for ____, p in ipairs({
    1,
    2,
    3,
    4,
    5
}) do
    ORDERS[p] = build(p)
end
--- The kinds a position takes, best first. An undefined or unknown position takes position 1's order.
function ____exports.Order(pos)
    return pos ~= nil and ORDERS[pos] or nil or ORDERS[1]
end
return ____exports
