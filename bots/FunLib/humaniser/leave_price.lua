--[[ Generated with https://github.com/TypeScriptToLua/TypeScriptToLua ]]
local ____exports = {}
local P = require(GetScriptDirectory().."/FunLib/humaniser/dc_prices")
____exports.SETTINGS = {Margin = 30, CreepRate = 4 / 30}
local function hpBin(hp)
    return math.max(
        0,
        math.min(
            4,
            math.floor(hp / 20)
        )
    )
end
--- P(T dies within the horizon) with `n` of our heroes in reach of it (0: none).
function ____exports.PKill(thp, n)
    if n <= 0 then
        return 0
    end
    return P.KILL_STAY.p[hpBin(thp) * 2 + (n >= 2 and 1 or 0) + 1]
end
--- P(we die) on a stay: our HP bin x hitting state (0 near, 1 poked, 2+ committed).
function ____exports.PDeathStay(hp, hs)
    return P.DEATH_STAY.p[hpBin(hp) * 3 + math.min(
        2,
        math.max(0, hs)
    ) + 1]
end
--- P(we die) on a leave: our HP bin x (committed or not) x walk bin (< 1,500, to 3,000, beyond).
function ____exports.PDeathLeave(hp, hs, w)
    local wb = w < 1500 and 0 or (w <= 3000 and 1 or 2)
    return P.DEATH_LEAVE.p[hpBin(hp) * 6 + (hs >= 2 and 3 or 0) + wb + 1]
end
local function conv(pos)
    return P.CONVERSION[math.max(
        1,
        math.min(5, pos)
    )]
end
--- Farm in reach on a stay: the conversion times the creeps' gold.
function ____exports.Farm(pos, cg)
    return conv(pos) * cg
end
--- Farm lost to the walk back on a leave: the round trip beyond the horizon at the lane's creep rate.
function ____exports.Walk(pos, w, ms, lam)
    local back = math.max(
        0,
        2 * w / math.max(ms, 100) - P.HORIZON
    )
    return conv(pos) * P.LASTHIT * lam * back
end
--- Stay or leave. Hard leaves first (tower, heal, burst), with no price. Else stay = P_k(T, n) K + F - P_ds D, leave = P_k(T, n - 1) K
-- - W - P_dl D, d = stay - leave; an incumbent stay keeps staying while d > -M, an incumbent leave stays only when d > M, no
-- incumbent picks the larger. M is `SETTINGS.Margin`, 0 on a real change (`i.rel`).
function ____exports.Decide(i, inc)
    local rel = i.rel == true and 1 or 0
    local hard = i.tower == true and "tower" or (i.heal == true and "heal" or (i.burst == true and "burst" or nil))
    if hard ~= nil then
        return {
            pick = "leave",
            hard = hard,
            inc = inc,
            rel = rel,
            M = 0
        }
    end
    local M = rel == 1 and 0 or ____exports.SETTINGS.Margin
    local pks = ____exports.PKill(i.thp, i.n)
    local pkl = ____exports.PKill(i.thp, i.n - 1)
    local pds = ____exports.PDeathStay(i.hp, i.hs)
    local pdl = ____exports.PDeathLeave(i.hp, i.hs, i.w)
    local F = ____exports.Farm(i.pos, i.cg)
    local W = ____exports.Walk(i.pos, i.w, i.ms, i.lam or ____exports.SETTINGS.CreepRate)
    local stay = pks * P.KILL + F - pds * P.DEATH
    local leave = pkl * P.KILL - W - pdl * P.DEATH
    local d = stay - leave
    local pick
    if inc == "stay" then
        pick = d > -M and "stay" or "leave"
    elseif inc == "leave" then
        pick = d > M and "stay" or "leave"
    else
        pick = d > 0 and "stay" or "leave"
    end
    return {
        pick = pick,
        inc = inc,
        rel = rel,
        M = M,
        stay = stay,
        leave = leave,
        d = d,
        pks = pks,
        pkl = pkl,
        pds = pds,
        pdl = pdl,
        F = F,
        W = W
    }
end
return ____exports
