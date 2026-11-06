--[[ Generated with https://github.com/TypeScriptToLua/TypeScriptToLua ]]
-- Lua Library inline imports
local function __TS__CountVarargs(...)
    return select("#", ...)
end

local function __TS__SparseArrayNew(...)
    local sparseArray = {...}
    sparseArray.sparseLength = __TS__CountVarargs(...)
    return sparseArray
end

local function __TS__SparseArrayPush(sparseArray, ...)
    local args = {...}
    local argsLen = __TS__CountVarargs(...)
    local listLen = sparseArray.sparseLength
    for i = 1, argsLen do
        sparseArray[listLen + i] = args[i]
    end
    sparseArray.sparseLength = listLen + argsLen
end

local function __TS__SparseArraySpread(sparseArray)
    local _unpack = unpack or table.unpack
    return _unpack(sparseArray, 1, sparseArray.sparseLength)
end

local function __TS__ArraySort(self, compareFn)
    if compareFn ~= nil then
        table.sort(
            self,
            function(a, b) return compareFn(nil, a, b) < 0 end
        )
    else
        table.sort(self)
    end
    return self
end
-- End of Lua Library inline imports
local ____exports = {}
--- All `judgement` (slice file, Decisions).
____exports.SETTINGS = {FitMargin = 5, CacheFor = 1}
local cache = {}
function ____exports.ResetCache()
    for k in pairs(cache) do
        cache[k] = nil
    end
end
--- The hero's entries still ahead of it or running at `now`, by leave time.
function ____exports.Of(bot, now)
    local pid = bot:GetPlayerID()
    local c = cache[pid]
    if c ~= nil and now >= c.at and now - c.at < ____exports.SETTINGS.CacheFor then
        return c.entries
    end
    local StackJob = require(GetScriptDirectory().."/FunLib/humaniser/stack_job")
    local RuneJob = require(GetScriptDirectory().."/FunLib/humaniser/rune_job")
    local ____array_0 = __TS__SparseArrayNew(unpack(StackJob.CalendarEntries(bot, now)))
    __TS__SparseArrayPush(
        ____array_0,
        unpack(RuneJob.CalendarEntries(bot, now))
    )
    local entries = {__TS__SparseArraySpread(____array_0)}
    __TS__ArraySort(
        entries,
        function(____, a, b) return a.leave - b.leave end
    )
    cache[pid] = {at = now, entries = entries}
    return entries
end
--- Seconds from `now` to the first leave at or after it, or undefined with none.
function ____exports.NextLeave(entries, now)
    local best
    for ____, e in ipairs(entries) do
        if not e.running and e.leave >= now and (best == nil or e.leave - now < best) then
            best = e.leave - now
        end
    end
    return best
end
--- Whether a job from `start` to `end` (a pull) can run: `free` when no entry claims the hero in that time, `fits` when the
-- entries that do all still leave FitMargin after `end` (their claim has begun but their walk has not), else `clash` with
-- the first entry that does not (a running job always clashes).
function ____exports.FitOf(entries, start, ____end)
    local fits
    for ____, e in ipairs(entries) do
        do
            local __continue12
            repeat
                if e.claim > ____end or e.back <= start then
                    __continue12 = true
                    break
                end
                if e.running or e.leave < ____end + ____exports.SETTINGS.FitMargin then
                    return "clash", e
                end
                fits = fits or e
                __continue12 = true
            until true
            if not __continue12 then
                break
            end
        end
    end
    if fits ~= nil then
        return "fits", fits
    end
    return "free", nil
end
return ____exports
