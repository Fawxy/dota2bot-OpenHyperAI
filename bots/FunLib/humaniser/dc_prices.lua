--[[ Generated with https://github.com/TypeScriptToLua/TypeScriptToLua ]]
local ____exports = {}
--- sha256 (first 16 hex) of the prices.json this was generated from; tools/dc/dc.test.js checks it.
____exports.SOURCE_HASH = "ec10009281a35eb8"
--- Reach (units, centre to centre) the tables were fitted at, and their horizon (s).
____exports.REACH = 800
____exports.HORIZON = 8
--- A kill on the team net-worth difference (gold, not divided by our heroes in reach).
____exports.KILL = 384
--- A death on the team net-worth difference (gold, as a positive cost).
____exports.DEATH = 304
--- A last hit's mean gold, and by creep kind.
____exports.LASTHIT = 44.5
____exports.LASTHIT_BY_KIND = {melee = 37.5, ranged = 48.3, flag = 80.9, siege = 66.2}
--- Last-hit conversion (last hits over creeps in reach that died) by position 1 to 5.
____exports.CONVERSION = {
    0.524,
    0.531,
    0.514,
    0.332,
    0.309
}
--- P(target dies within 12 s): target HP bin x our heroes within reach of it (1, 2+).
____exports.KILL_STAY = {axes = {hp = {
    "0-20",
    "20-40",
    "40-60",
    "60-80",
    "80-100"
}, heroes = {"1", "2+"}}, p = {
    0.4961,
    0.7201,
    0.2103,
    0.422,
    0.1092,
    0.2443,
    0.0584,
    0.1287,
    0.027,
    0.0702
}}
--- P(we die within 10 s | stay): our HP bin x enemies hitting us (near 0, poked 1, committed 2+).
____exports.DEATH_STAY = {axes = {hp = {
    "0-20",
    "20-40",
    "40-60",
    "60-80",
    "80-100"
}, state = {"near", "poked", "committed"}}, p = {
    0.5842,
    0.8376,
    0.9318,
    0.1839,
    0.423,
    0.7778,
    0.084,
    0.164,
    0.3897,
    0.0335,
    0.0786,
    0.2364,
    0.0159,
    0.0344,
    0.0833
}}
--- P(we die within 10 s | leave): our HP bin x hitting (poked-or-near, committed) x walk to our nearest standing tower.
____exports.DEATH_LEAVE = {axes = {hp = {
    "0-20",
    "20-40",
    "40-60",
    "60-80",
    "80-100"
}, state = {"poked-or-near", "committed"}, walk = {"<1500", "1500-3000", ">3000"}}, p = {
    0.1173,
    0.2117,
    0.2397,
    0.1292,
    0.264,
    0.2397,
    0.0739,
    0.1838,
    0.1628,
    0.0739,
    0.264,
    0.1628,
    0.038,
    0.0803,
    0.0757,
    0.0674,
    0.264,
    0.1376,
    0.0315,
    0.0388,
    0.0757,
    0.0346,
    0.1667,
    0.0841,
    0.0128,
    0.0212,
    0.0093,
    0.0128,
    0.0271,
    0.0363
}}
return ____exports
