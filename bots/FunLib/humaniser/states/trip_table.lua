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
____exports.TRIPS = {
    {
        kind = "pull",
        rank = by(
            nil,
            nil,
            30,
            30,
            30
        ),
        lifted = by(
            nil,
            nil,
            10,
            10,
            10
        )
    },
    {
        kind = "rune",
        rank = by(
            nil,
            nil,
            nil,
            15,
            50
        )
    },
    {
        kind = "stack",
        rank = by(
            nil,
            nil,
            nil,
            20,
            20
        )
    },
    {
        kind = "pullfarm",
        rank = by(
            nil,
            nil,
            40,
            40,
            40
        )
    },
    {
        kind = "camp",
        rank = by(
            60,
            60,
            60,
            nil,
            nil
        )
    }
}
local function rowOf(kind)
    for ____, r in ipairs(____exports.TRIPS) do
        if r.kind == kind then
            return r
        end
    end
    return nil
end
local function isPos(pos)
    return pos ~= nil and pos >= 1 and pos <= 5 and pos == math.floor(pos)
end
--- The trip's place for a position (the lifted column when `lifted` and the row has one); undefined: never, or no position.
function ____exports.RankOf(kind, pos, lifted)
    local row = rowOf(kind)
    if row == nil or not isPos(pos) then
        return nil
    end
    if lifted == true and row.lifted ~= nil then
        return row.lifted[pos]
    end
    return row.rank[pos]
end
function ____exports.Does(kind, pos)
    return ____exports.RankOf(kind, pos) ~= nil
end
--- The trips a position does, best first; `lifted` says per kind whether its lifted column applies.
function ____exports.Order(pos, lifted)
    local rows = {}
    for ____, r in ipairs(____exports.TRIPS) do
        local rank = ____exports.RankOf(
            r.kind,
            pos,
            lifted(r.kind)
        )
        if rank ~= nil then
            rows[#rows + 1] = {r.kind, rank}
        end
    end
    table.sort(
        rows,
        function(a, b) return a[2] < b[2] end
    )
    local out = {}
    for ____, r in ipairs(rows) do
        out[#out + 1] = r[1]
    end
    return out
end
return ____exports
