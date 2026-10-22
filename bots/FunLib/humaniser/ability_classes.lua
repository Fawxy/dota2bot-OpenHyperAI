--[[ Generated with https://github.com/TypeScriptToLua/TypeScriptToLua ]]
-- Lua Library inline imports
local __TS__StringSplit
do
    local sub = string.sub
    local find = string.find
    function __TS__StringSplit(source, separator, limit)
        if limit == nil then
            limit = 4294967295
        end
        if limit == 0 then
            return {}
        end
        local result = {}
        local resultIndex = 1
        if separator == nil or separator == "" then
            for i = 1, #source do
                result[resultIndex] = sub(source, i, i)
                resultIndex = resultIndex + 1
            end
        else
            local currentPos = 1
            while resultIndex <= limit do
                local startPos, endPos = find(source, separator, currentPos, true)
                if not startPos then
                    break
                end
                result[resultIndex] = sub(source, currentPos, startPos - 1)
                resultIndex = resultIndex + 1
                currentPos = endPos + 1
            end
            if resultIndex <= limit then
                result[resultIndex] = sub(source, currentPos)
            end
        end
        return result
    end
end
-- End of Lua Library inline imports
local ____exports = {}
--- Ability classes for lane fight memory (task 11). An ability is an ultimate (the engine flag), a key ability or other.
-- Key abilities are hard disables (stun, root, hex, silence, sleep, fear, taunt, cyclone or banish), things that matter
-- to a kill (spell immunity), and the listed items. Escapes are the subset where the target breaks contact or becomes
-- untargetable to us: blinks, leaps, invisibility, teleports. Slows, knockbacks, disarms and damage reduction count for neither.
-- One line per hero with a BotLib file, built from its ability names ("hero: key names|escape names", every escape is
-- also key); the names come from the hero_*.lua files and FunLib/spell_list.lua.
local HEROES = {
    "abyssal_underlord: abyssal_underlord_pit_of_malice|",
    "alchemist: alchemist_unstable_concoction alchemist_unstable_concoction_throw|",
    "ancient_apparition: ancient_apparition_cold_feet|",
    "antimage: |antimage_blink",
    "axe: axe_berserkers_call|",
    "bane: bane_nightmare bane_fiends_grip|",
    "batrider: batrider_flaming_lasso|",
    "bounty_hunter: |bounty_hunter_wind_walk",
    "centaur: centaur_hoof_stomp|centaur_stampede",
    "chaos_knight: chaos_knight_chaos_bolt|",
    "clinkz: |clinkz_wind_walk",
    "crystal_maiden: crystal_maiden_frostbite|",
    "dark_seer: dark_seer_vacuum|dark_seer_surge",
    "dark_willow: dark_willow_bramble_maze dark_willow_cursed_crown dark_willow_terrorize|",
    "dawnbreaker: dawnbreaker_celestial_hammer|dawnbreaker_celestial_hammer",
    "death_prophet: death_prophet_silence|",
    "disruptor: disruptor_static_storm|",
    "doom_bringer: doom_bringer_doom|",
    "dragon_knight: dragon_knight_dragon_tail|",
    "drow_ranger: drow_ranger_wave_of_silence|",
    "earth_spirit: earth_spirit_rolling_boulder earth_spirit_geomagnetic_grip|",
    "earthshaker: earthshaker_fissure|",
    "elder_titan: elder_titan_echo_stomp|",
    "ember_spirit: ember_spirit_searing_chains|ember_spirit_fire_remnant",
    "enigma: enigma_malefice enigma_black_hole|",
    "faceless_void: faceless_void_chronosphere|faceless_void_time_walk",
    "furion: furion_sprout|",
    "grimstroke: grimstroke_ink_creature grimstroke_spirit_walk|",
    "gyrocopter: gyrocopter_homing_missile|",
    "hoodwink: hoodwink_bushwhack|hoodwink_scurry",
    "invoker: invoker_tornado invoker_cold_snap|invoker_ghost_walk",
    "jakiro: jakiro_ice_path|",
    "juggernaut: juggernaut_blade_fury|",
    "kez: |kez_grappling_claw",
    "kunkka: kunkka_torrent kunkka_x_marks_the_spot|",
    "legion_commander: legion_commander_duel|",
    "leshrac: leshrac_split_earth|",
    "lich: lich_sinister_gaze|",
    "life_stealer: life_stealer_rage|",
    "lina: lina_light_strike_array|",
    "lion: lion_impale lion_voodoo|",
    "lone_druid: lone_druid_savage_roar|",
    "lone_druid_bear: lone_druid_savage_roar_bear|",
    "magnataur: magnataur_skewer magnataur_reverse_polarity|",
    "marci: marci_grapple|marci_companion_run",
    "mars: mars_spear|",
    "meepo: meepo_earthbind|meepo_poof",
    "mirana: mirana_arrow|mirana_leap mirana_invis",
    "monkey_king: monkey_king_boundless_strike|monkey_king_tree_dance",
    "morphling: morphling_adaptive_strike_str morphling_adaptive_strike_agi|morphling_waveform",
    "muerta: muerta_the_calling|",
    "naga_siren: naga_siren_ensnare naga_siren_song_of_the_siren|",
    "night_stalker: night_stalker_crippling_fear|",
    "nyx_assassin: nyx_assassin_impale nyx_assassin_spiked_carapace|nyx_assassin_vendetta",
    "obsidian_destroyer: obsidian_destroyer_astral_imprisonment|",
    "ogre_magi: ogre_magi_fireblast ogre_magi_unrefined_fireblast|",
    "oracle: oracle_fortunes_end|",
    "pangolier: pangolier_gyroshell|",
    "phantom_assassin: |phantom_assassin_phantom_strike",
    "phantom_lancer: |phantom_lancer_doppelwalk",
    "phoenix: |phoenix_icarus_dive",
    "primal_beast: primal_beast_onslaught|",
    "puck: puck_dream_coil puck_waning_rift|puck_ethereal_jaunt puck_phase_shift",
    "pudge: pudge_meat_hook pudge_dismember|",
    "queenofpain: |queenofpain_blink",
    "rattletrap: rattletrap_power_cogs rattletrap_hookshot|",
    "riki: riki_smoke_screen|riki_blink_strike",
    "ringmaster: ringmaster_tame_the_beasts|",
    "rubick: rubick_telekinesis|",
    "sand_king: sandking_burrowstrike|",
    "shadow_demon: shadow_demon_disruption|",
    "shadow_shaman: shadow_shaman_voodoo shadow_shaman_shackles|",
    "shredder: |shredder_timber_chain",
    "silencer: silencer_last_word silencer_global_silence|",
    "skeleton_king: skeleton_king_hellfire_blast|",
    "skywrath_mage: skywrath_mage_ancient_seal|",
    "slardar: slardar_slithereen_crush|",
    "slark: |slark_pounce slark_shadow_dance",
    "snapfire: snapfire_firesnap_cookie|",
    "spirit_breaker: spirit_breaker_charge_of_darkness spirit_breaker_nether_strike|",
    "storm_spirit: storm_spirit_electric_vortex|storm_spirit_ball_lightning",
    "sven: sven_storm_bolt|",
    "terrorblade: terrorblade_terror_wave|",
    "tidehunter: tidehunter_ravage|",
    "tiny: tiny_avalanche tiny_toss|",
    "treant: treant_overgrowth|",
    "tusk: tusk_snowball tusk_launch_snowball|",
    "vengefulspirit: vengefulspirit_magic_missile vengefulspirit_nether_swap|",
    "visage: |visage_silent_as_the_grave",
    "void_spirit: void_spirit_aether_remnant|void_spirit_astral_step void_spirit_dissimilate",
    "warlock: warlock_rain_of_chaos|",
    "weaver: |weaver_shukuchi",
    "windrunner: windrunner_shackleshot|",
    "winter_wyvern: winter_wyvern_winters_curse|",
    "wisp: |wisp_relocate",
    "witch_doctor: witch_doctor_paralyzing_cask|",
    "zuus: |zuus_heavenly_jump",
    "items: item_force_staff item_hurricane_pike item_cyclone item_wind_waker item_sheepstick item_abyssal_blade item_orchid item_bloodthorn item_rod_of_atos item_gungir item_black_king_bar|item_blink item_swift_blink item_arcane_blink item_overwhelming_blink item_force_staff item_hurricane_pike item_cyclone item_wind_waker item_glimmer_cape item_black_king_bar item_shadow_blade item_silver_edge"
}
local KEY = {}
local ESCAPE = {}
for ____, line in ipairs(HEROES) do
    local ____, rest = unpack(__TS__StringSplit(line, ": "))
    local keys, escapes = unpack(__TS__StringSplit(rest, "|"))
    for ____, name in ipairs(__TS__StringSplit(keys, " ")) do
        if name ~= "" then
            KEY[name] = true
        end
    end
    for ____, name in ipairs(__TS__StringSplit(escapes, " ")) do
        do
            local __continue6
            repeat
                if name == "" then
                    __continue6 = true
                    break
                end
                KEY[name] = true
                ESCAPE[name] = true
                __continue6 = true
            until true
            if not __continue6 then
                break
            end
        end
    end
end
function ____exports.IsEscape(name)
    return ESCAPE[name] == true
end
function ____exports.Classify(name, isUltimate)
    if isUltimate then
        return "ult"
    end
    return KEY[name] == true and "key" or "other"
end
return ____exports
