--[[ Generated with https://github.com/TypeScriptToLua/TypeScriptToLua ]]
local ____exports = {}
local courierOf, noteCourier, n0, courierSeen
local ____dota = require(GetScriptDirectory().."/ts_libs/dota/index")
local UnitType = ____dota.UnitType
local Sustain = require(GetScriptDirectory().."/FunLib/humaniser/sustain")
local Telemetry = require(GetScriptDirectory().."/FunLib/humaniser/telemetry")
local Threat = require(GetScriptDirectory().."/FunLib/humaniser/threat")
local Safe = require(GetScriptDirectory().."/FunLib/humaniser/safe")
local SafeGather = require(GetScriptDirectory().."/FunLib/humaniser/safe_gather")
local Retreat = require(GetScriptDirectory().."/FunLib/humaniser/retreat")
local CampJobs = require(GetScriptDirectory().."/FunLib/humaniser/camp_jobs")
local Laning = require(GetScriptDirectory().."/FunLib/humaniser/states/laning")
function courierOf(bot)
    do
        local n = 0
        while n <= 4 do
            local c = GetCourier(n)
            if c ~= nil and c ~= nil and c:GetPlayerID() == bot:GetPlayerID() then
                return c
            end
            n = n + 1
        end
    end
    return nil
end
function noteCourier(bot)
    local c = courierOf(bot)
    if c == nil then
        return
    end
    local st = GetCourierState(c)
    local pid = bot:GetPlayerID()
    if courierSeen[pid] == st then
        return
    end
    courierSeen[pid] = st
    Telemetry.Event(
        "sustain_courier",
        {
            {"pid", pid},
            {"st", st},
            {"dead", st == COURIER_STATE_DEAD and 1 or 0},
            {
                "d",
                n0(GetUnitToUnitDistance(bot, c))
            }
        }
    )
end
--- `breaks`: salve and clarity end on damage from a hero (their descriptions; regen_obs `early` ends agree); a tango does not.
-- The bottle's is not confirmed: true is the cautious reading (a use only with no hero hitting or in reach) until a rig says.
____exports.ITEMS = {
    item_tango = {
        hp = {"health_regen", "buff_duration"},
        dur = "buff_duration",
        mod = "modifier_tango_heal",
        breaks = false,
        tree = true,
        refill = false,
        share = true,
        shop = true
    },
    item_tango_single = {
        hp = {"health_regen", "buff_duration"},
        dur = "buff_duration",
        mod = "modifier_tango_heal",
        breaks = false,
        tree = true,
        refill = false,
        share = false,
        shop = false
    },
    item_flask = {
        hp = {"health_regen", "buff_duration"},
        dur = "buff_duration",
        mod = "modifier_flask_healing",
        breaks = true,
        tree = false,
        refill = false,
        share = false,
        shop = true
    },
    item_clarity = {
        mp = {"mana_regen", "buff_duration"},
        dur = "buff_duration",
        mod = "modifier_clarity_potion",
        breaks = true,
        tree = false,
        refill = false,
        share = false,
        shop = true
    },
    item_bottle = {
        hp = "health_restore",
        mp = "mana_restore",
        dur = "restore_time",
        mod = "modifier_bottle_regeneration",
        breaks = true,
        tree = false,
        refill = true,
        share = false,
        shop = false
    },
    item_faerie_fire = {
        hp = "hp_restore",
        breaks = false,
        tree = false,
        refill = false,
        share = false,
        shop = true
    },
    item_enchanted_mango = {
        mp = "replenish_amount",
        breaks = false,
        tree = false,
        refill = false,
        share = false,
        shop = true
    },
    item_magic_stick = {
        hp = "restore_per_charge",
        mp = "restore_per_charge",
        perCharge = true,
        breaks = false,
        tree = false,
        refill = false,
        share = false,
        shop = false
    },
    item_magic_wand = {
        hp = "restore_per_charge",
        mp = "restore_per_charge",
        perCharge = true,
        breaks = false,
        tree = false,
        refill = false,
        share = false,
        shop = false
    }
}
____exports.SETTINGS = {
    TreeScan = 1200,
    TangoRange = 165,
    AllyRadius = 800,
    SafeEvery = 1,
    DecideEvery = 0.5,
    CutEvery = 2,
    Until = 720
}
--- Per item name: the most charges seen (what a purchase holds), and what one charge restores per second (a running buff).
local learned = {}
--- Per hero: the charges of each item held at the last read, for a purchase's size.
local heldCharges = {}
local itemLogged = {}
local function val(it, key)
    if key == nil then
        return 0
    end
    if type(key) == "string" then
        return it:GetSpecialValueFloat(key) or 0
    end
    return (it:GetSpecialValueFloat(key[1]) or 0) * (it:GetSpecialValueFloat(key[2]) or 0)
end
local function r1(v)
    return math.floor(v * 10 + 0.5) / 10
end
--- One decimal as record text, with no trailing ".0" on whole numbers (the test runner's Lua 5.3 prints 112 as "112.0", the game's Lua as "112").
local function t1(v)
    return string.format(
        "%.10g",
        r1(v)
    )
end
--- One item in a slot as the decision's Item, or undefined when it is not a heal or mana item.
local function readItem(slot, item)
    local name = item:GetName()
    local spec = ____exports.ITEMS[name]
    if spec == nil then
        return nil
    end
    local it = item
    local charges = item:GetCurrentCharges() or 0
    local hp = val(it, spec.hp)
    local mp = val(it, spec.mp)
    local hpRead = hp
    local mpRead = mp
    local dur = spec.dur ~= nil and (it:GetSpecialValueFloat(spec.dur) or 0) or 0
    local uses = charges
    if spec.perCharge then
        hp = hp * charges
        mp = mp * charges
        uses = charges > 0 and 1 or 0
    elseif name == "item_tango_single" or charges == 0 and not spec.refill then
        uses = 1
    end
    local ____learned_0, ____name_1 = learned, name
    if ____learned_0[____name_1] == nil then
        ____learned_0[____name_1] = {
            pack = 0,
            hp = 0,
            mp = 0,
            hpRate = 0,
            mpRate = 0
        }
    end
    local l = learned[name]
    if not spec.perCharge then
        l.hp = hp
        l.mp = mp
        if dur > 0 then
            l.hpRate = hp / dur
            l.mpRate = mp / dur
        end
    end
    if not itemLogged[name] then
        itemLogged[name] = true
        Telemetry.Event(
            "sustain_item",
            {
                {"name", name},
                {
                    "hp",
                    r1(hpRead)
                },
                {
                    "mp",
                    r1(mpRead)
                },
                {
                    "dur",
                    r1(dur)
                },
                {"ch", charges}
            }
        )
    end
    local ready = slot <= 5 and item:IsFullyCastable()
    return {
        slot = slot,
        name = (string.gsub(name, "^item_", "")),
        charges = uses,
        hp = hp,
        mp = mp,
        dur = dur,
        breaks = spec.breaks,
        tree = spec.tree,
        refill = spec.refill,
        share = spec.share,
        ready = ready
    }
end
--- The heal and mana items in slots 0-8 (the backpack counts: a swap brings one out).
function ____exports.Items(bot)
    local out = {}
    local now = {}
    do
        local s = 0
        while s <= 8 do
            do
                local __continue15
                repeat
                    local item = bot:GetItemInSlot(s)
                    if item == nil or item == nil then
                        __continue15 = true
                        break
                    end
                    local it = readItem(s, item)
                    if it == nil then
                        __continue15 = true
                        break
                    end
                    out[#out + 1] = it
                    local name = item:GetName()
                    now[name] = (now[name] or 0) + (item:GetCurrentCharges() or 0)
                    __continue15 = true
                until true
                if not __continue15 then
                    break
                end
            end
            s = s + 1
        end
    end
    local ____heldCharges_3, ____temp_4 = heldCharges, bot:GetPlayerID()
    if ____heldCharges_3[____temp_4] == nil then
        ____heldCharges_3[____temp_4] = {}
    end
    local before = heldCharges[bot:GetPlayerID()]
    for name, n in pairs(now) do
        local rise = n - (before[name] or 0)
        local l = learned[name]
        if l ~= nil and rise > 0 and (l.pack == 0 or rise < l.pack) then
            l.pack = rise
        end
    end
    heldCharges[bot:GetPlayerID()] = now
    return out
end
--- HP and mana the regen buffs on the bot still restore: the buff's time left times the rate read from the item.
local function regenLeft(bot)
    local hp = 0
    local mp = 0
    local done = {}
    for name, spec in pairs(____exports.ITEMS) do
        do
            local __continue21
            repeat
                if spec.mod == nil or done[spec.mod] or not bot:HasModifier(spec.mod) then
                    __continue21 = true
                    break
                end
                local l = learned[name]
                if l == nil or l.hpRate + l.mpRate == 0 then
                    __continue21 = true
                    break
                end
                done[spec.mod] = true
                local left = bot:GetModifierRemainingDuration(bot:GetModifierByName(spec.mod))
                hp = hp + left * l.hpRate
                mp = mp + left * l.mpRate
                __continue21 = true
            until true
            if not __continue21 then
                break
            end
        end
    end
    return {hp, mp}
end
local function valid(u)
    return u ~= nil and u ~= nil and not u:IsNull() and u:IsAlive()
end
local function dist(a, b)
    return math.sqrt((a.x - b.x) ^ 2 + (a.y - b.y) ^ 2)
end
--- Per hero: the tree the last read chose (its id, for the executor's order), with when it was read.
local trees = {}
--- The tree the last Gather chose for this hero, if any: the executor's target.
function ____exports.TreeOf(bot)
    local t = trees[bot:GetPlayerID()]
    return t ~= nil and ({id = t.id, loc = t.loc}) or nil
end
--- The nearest visible, passable tree, read only with a tree item held: the seconds to walk into the item's cast range of
-- it, and whether that walk is safe: the safe-here read over the walk (the trip gates' horizon) is not `deadly`. A walk
-- needs no read with the tree already in range. Re-read at most every SafeEvery per hero (a read walks every enemy).
local function treeOf(bot, items, now)
    local pid = bot:GetPlayerID()
    local slot
    for ____, it in ipairs(items) do
        if it.tree and it.charges > 0 and (slot == nil or it.ready == true) then
            slot = it.slot
        end
    end
    if slot == nil then
        trees[pid] = nil
        return nil
    end
    local c = trees[pid]
    if c ~= nil and now - c.at < ____exports.SETTINGS.SafeEvery then
        return c.tree
    end
    local best
    local bestLoc
    local bestD = math.huge
    for ____, tree in ipairs(bot:GetNearbyTrees(____exports.SETTINGS.TreeScan) or ({})) do
        do
            local __continue33
            repeat
                local loc = GetTreeLocation(tree)
                if not IsLocationVisible(loc) or not IsLocationPassable(loc) then
                    __continue33 = true
                    break
                end
                local d = GetUnitToLocationDistance(bot, loc)
                if d < bestD then
                    bestD = d
                    best = tree
                    bestLoc = loc
                end
                __continue33 = true
            until true
            if not __continue33 then
                break
            end
        end
    end
    if best == nil or bestLoc == nil then
        trees[pid] = nil
        return nil
    end
    local item = bot:GetItemInSlot(slot)
    local range = item ~= nil and item ~= nil and item:GetCastRange() or 0
    local walk = math.max(0, bestD - (range > 0 and range or ____exports.SETTINGS.TangoRange)) / math.max(
        100,
        bot:GetCurrentMovementSpeed()
    )
    local safe = true
    if walk > 0 then
        local r = Threat.Read(
            bot,
            bot:GetLocation(),
            bestLoc,
            Threat.SETTINGS.GateHorizon
        )
        safe = Safe.Decide(SafeGather.FromRead(bot, r, {away = false, held = false, hold = false})).level ~= "deadly"
    end
    local tree = {walk = walk, safe = safe}
    trees[pid] = {at = now, id = best, loc = bestLoc, tree = tree}
    return tree
end
--- The safe-here read here, from the one stay read Gather makes: what the reachers can deal, whether one is hitting us, and the visible ones in reach.
local function safeHere(bot, r)
    local i = SafeGather.FromRead(bot, r, {away = false, held = false, hold = false})
    local a = Safe.Decide(i)
    local hitting = false
    local reach = 0
    for ____, x in ipairs(i.reach) do
        if x.hitting then
            hitting = true
        end
        if x.unseen ~= true then
            reach = reach + 1
        end
    end
    return {{kill = a.kill, hitting = hitting, reach = reach}, a.level == "deadly"}
end
local safeCache = {}
local function safeSpot(bot, now)
    local c = safeCache[bot:GetPlayerID()]
    if c ~= nil and now - c.at < ____exports.SETTINGS.SafeEvery then
        return c.spot
    end
    local a = Retreat.SafeSpot(bot)
    local spot = a ~= nil and ({x = a.at.x, y = a.at.y, walk = a.secs}) or nil
    safeCache[bot:GetPlayerID()] = {at = now, spot = spot}
    return spot
end
--- The courier free and alive: seconds for it to fetch a purchase from the fountain and bring it to the bot.
local function courierEta(bot, c, fountain)
    if c == nil then
        return nil
    end
    local st = GetCourierState(c)
    if st ~= COURIER_STATE_IDLE and st ~= COURIER_STATE_AT_BASE then
        return nil
    end
    local v = math.max(
        100,
        c:GetCurrentMovementSpeed()
    )
    return {eta = (dist(
        c:GetLocation(),
        fountain
    ) + dist(
        fountain,
        bot:GetLocation()
    )) / v}
end
--- The lane regen the fountain sells now: price from GetItemCost, what one purchase restores from an item of ours read before.
local function shopOf()
    local out = {}
    for name, spec in pairs(____exports.ITEMS) do
        do
            local __continue53
            repeat
                local l = learned[name]
                if not spec.shop or l == nil or GetItemStockCount(name) <= 0 then
                    __continue53 = true
                    break
                end
                local n = math.max(1, l.pack)
                out[#out + 1] = {
                    name = (string.gsub(name, "^item_", "")),
                    cost = GetItemCost(name),
                    hp = l.hp * n,
                    mp = l.mp * n
                }
                __continue53 = true
            until true
            if not __continue53 then
                break
            end
        end
    end
    return out
end
--- Heal items an ally holds (uses of an item restoring HP over time).
local function healsOf(a)
    local n = 0
    do
        local s = 0
        while s <= 8 do
            do
                local __continue56
                repeat
                    local item = a:GetItemInSlot(s)
                    if item == nil or item == nil then
                        __continue56 = true
                        break
                    end
                    local spec = ____exports.ITEMS[item:GetName()]
                    if spec ~= nil and spec.hp ~= nil and spec.dur ~= nil then
                        n = n + math.max(
                            1,
                            item:GetCurrentCharges() or 0
                        )
                    end
                    __continue56 = true
                until true
                if not __continue56 then
                    break
                end
            end
            s = s + 1
        end
    end
    return n
end
--- The inputs of one frame, read from the game once. `run` is the executor's running answer (none in shadow).
function ____exports.Gather(bot, run)
    local now = DotaTime()
    local here = bot:GetLocation()
    local hp = bot:GetHealth()
    local stay = Threat.Read(
        bot,
        here,
        here,
        Threat.SETTINGS.StayHorizon,
        {engagedWindow = Threat.SETTINGS.StayEngaged}
    )
    local items = ____exports.Items(bot)
    local safe, deadlyHere = unpack(safeHere(bot, stay))
    local t = treeOf(bot, items, now)
    local tree = t ~= nil and t.walk > 0 and deadlyHere and ({walk = t.walk, safe = false}) or t
    local rl, ml = unpack(regenLeft(bot))
    local fountain = Retreat.Fountain(bot:GetTeam())
    local speed = math.max(
        100,
        bot:GetCurrentMovementSpeed()
    )
    local allies = {}
    for ____, a in ipairs(GetUnitList(UnitType.AlliedHeroes) or ({})) do
        do
            local __continue60
            repeat
                if not valid(a) or a == bot or a:IsIllusion() or GetUnitToUnitDistance(bot, a) > ____exports.SETTINGS.AllyRadius then
                    __continue60 = true
                    break
                end
                allies[#allies + 1] = {
                    pid = a:GetPlayerID(),
                    missing = a:GetMaxHealth() - a:GetHealth(),
                    heals = healsOf(a)
                }
                __continue60 = true
            until true
            if not __continue60 then
                break
            end
        end
    end
    local ____now_7 = now
    local ____hp_8 = hp
    local ____temp_9 = bot:GetMaxHealth()
    local ____temp_10 = bot:GetMana()
    local ____temp_11 = bot:GetMaxMana()
    local ____items_12 = items
    local ____tree_13 = tree
    local ____temp_6
    if tree ~= nil then
        ____temp_6 = Laning.NextDue(bot)
    else
        ____temp_6 = nil
    end
    return {
        now = ____now_7,
        hp = ____hp_8,
        hpMax = ____temp_9,
        mp = ____temp_10,
        mpMax = ____temp_11,
        items = ____items_12,
        tree = ____tree_13,
        nextDue = ____temp_6,
        hitRecently = bot:WasRecentlyDamagedByAnyHero(2),
        safe = safe,
        regenLeft = rl,
        manaLeft = ml,
        safeSpot = safeSpot(bot, now),
        gold = bot:GetGold(),
        courier = courierEta(
            bot,
            courierOf(bot),
            fountain
        ),
        shop = shopOf(),
        home = 2 * dist(here, fountain) / speed,
        idle = CampJobs.Active(bot),
        atFountain = bot:HasModifier("modifier_fountain_aura_buff"),
        allies = allies,
        run = run
    }
end
n0 = function(v) return math.floor(v + 0.5) end
local function b01(b)
    return b and 1 or 0
end
--- Items as `slot,name,uses,hp,mp,dur,breaks,tree,refill,share,ready` joined by `;`.
function ____exports.ItemsText(items)
    local out = {}
    for ____, it in ipairs(items) do
        out[#out + 1] = table.concat(
            {
                it.slot,
                it.name,
                it.charges,
                t1(it.hp),
                t1(it.mp),
                t1(it.dur),
                b01(it.breaks),
                b01(it.tree),
                b01(it.refill),
                b01(it.share),
                b01(it.ready ~= false)
            },
            ","
        )
    end
    return table.concat(out, ";")
end
--- The `ev=cut kind=sustain` fields for these inputs and answer (tools/hlog/sustain_diff.js reads them back into Inputs).
function ____exports.CutFields(pid, i, a)
    local shop = {}
    for ____, o in ipairs(i.shop) do
        shop[#shop + 1] = table.concat(
            {
                o.name,
                o.cost,
                t1(o.hp),
                t1(o.mp)
            },
            ","
        )
    end
    local al = {}
    for ____, x in ipairs(i.allies) do
        al[#al + 1] = table.concat(
            {
                x.pid,
                n0(x.missing),
                x.heals
            },
            ","
        )
    end
    return {
        {"pid", pid},
        {"kind", "sustain"},
        {
            "hpa",
            n0(i.hp)
        },
        {
            "hpm",
            n0(i.hpMax)
        },
        {
            "mpa",
            n0(i.mp)
        },
        {
            "mpm",
            n0(i.mpMax)
        },
        {
            "it",
            #i.items > 0 and ____exports.ItemsText(i.items) or nil
        },
        {
            "tr",
            i.tree ~= nil and (t1(i.tree.walk) .. ",") .. tostring(b01(i.tree.safe)) or nil
        },
        {
            "nd",
            i.nextDue ~= nil and r1(i.nextDue) or nil
        },
        {
            "hr",
            b01(i.hitRecently)
        },
        {
            "kill",
            n0(i.safe.kill)
        },
        {
            "sh",
            b01(i.safe.hitting)
        },
        {"rc", i.safe.reach},
        {
            "rl",
            n0(i.regenLeft)
        },
        {
            "ml",
            n0(i.manaLeft)
        },
        {
            "ss",
            i.safeSpot ~= nil and (((tostring(n0(i.safeSpot.x)) .. ",") .. tostring(n0(i.safeSpot.y))) .. ",") .. t1(i.safeSpot.walk) or nil
        },
        {
            "gd",
            n0(i.gold)
        },
        {
            "co",
            i.courier ~= nil and r1(i.courier.eta) or nil
        },
        {
            "shp",
            #shop > 0 and table.concat(shop, ";") or nil
        },
        {
            "ho",
            r1(i.home)
        },
        {
            "idl",
            b01(i.idle)
        },
        {
            "af",
            b01(i.atFountain)
        },
        {
            "als",
            #al > 0 and table.concat(al, ";") or nil
        },
        {"ak", a.kind},
        {"anm", a.name},
        {"ato", a.to},
        {"why", a.reason},
        {"ed", a.ended}
    }
end
local cutState = {}
--- The cut line for one decision: on a changed answer, else every CutEvery. `acted`: sustain_act.ts carries it out.
function ____exports.Cut(bot, i, a, acted)
    if not Telemetry.IsEnabled() or Telemetry.Get().Cut ~= true then
        return
    end
    local pid = bot:GetPlayerID()
    local now = DotaTime()
    local ____cutState_14, ____pid_15 = cutState, pid
    if ____cutState_14[____pid_15] == nil then
        ____cutState_14[____pid_15] = {at = -math.huge, decidedAt = -math.huge}
    end
    local st = cutState[pid]
    local key = (((((a.kind .. ":") .. tostring(a.name)) .. ":") .. a.reason) .. ":") .. tostring(a.ended)
    if key == st.key and now - st.at < ____exports.SETTINGS.CutEvery then
        return
    end
    st.key = key
    st.at = now
    local f = ____exports.CutFields(pid, i, a)
    if acted then
        f[#f + 1] = {"act", 1}
    end
    Telemetry.Event("cut", f)
end
--- Shadow: every hero in the laning stage, both teams, that sustain_act.ts does not carry out (index.ts asks); the answer is logged, never carried out.
function ____exports.Tick(bot)
    if not Telemetry.IsEnabled() or Telemetry.Get().Cut ~= true or not bot:IsAlive() then
        return
    end
    local now = DotaTime()
    if now < 0 or now > ____exports.SETTINGS.Until then
        return
    end
    local pid = bot:GetPlayerID()
    local ____cutState_17, ____pid_18 = cutState, pid
    if ____cutState_17[____pid_18] == nil then
        ____cutState_17[____pid_18] = {at = -math.huge, decidedAt = -math.huge}
    end
    local st = cutState[pid]
    if now - st.decidedAt < ____exports.SETTINGS.DecideEvery then
        return
    end
    st.decidedAt = now
    noteCourier(bot)
    local i = ____exports.Gather(bot)
    ____exports.Cut(
        bot,
        i,
        Sustain.Decide(i),
        false
    )
end
--- The courier telemetry for a hero sustain_act.ts carries (its Tick is not asked).
function ____exports.NoteCourier(bot)
    noteCourier(bot)
end
courierSeen = {}
--- OHA's lane regen purchase rules call this beside each regen purchase (`item_purchase_generic.lua`).
function ____exports.Bought(bot, name, why)
    if not Telemetry.IsEnabled() then
        return
    end
    Telemetry.Event(
        "sustain_buy",
        {
            {
                "pid",
                bot:GetPlayerID()
            },
            {"item", name},
            {"why", why},
            {
                "gold",
                bot:GetGold()
            },
            {
                "hp",
                bot:GetMaxHealth() > 0 and r1(bot:GetHealth() / bot:GetMaxHealth() * 100) or -1
            },
            {
                "mp",
                bot:GetMaxMana() > 0 and r1(bot:GetMana() / bot:GetMaxMana() * 100) or -1
            }
        }
    )
end
____exports._test = {learned = learned, cutState = cutState, trees = trees}
return ____exports
