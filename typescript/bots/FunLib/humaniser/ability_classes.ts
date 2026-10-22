/**
 * Ability classes for lane fight memory (task 11). An ability is an ultimate (from the engine flag), a key ability
 * (a disable, an escape or one of the listed items) or other. KEY and ESCAPE are curated by hand from the ability
 * names in FunLib/spell_list.lua and the hero_*.lua files, one line per hero: only stuns, roots, hexes, silences,
 * sleeps, fears, taunts, lifts and pulls count as disables; only blinks, leaps, invisibility and untargetability as escapes.
 */

function set(lines: string[]): Record<string, true> {
    const result: Record<string, true> = {};
    for (const line of lines) {
        for (const name of line.split(" ")) {
            if (name !== "") result[name] = true;
        }
    }
    return result;
}

const KEY: Record<string, true> = set([
    "abyssal_underlord_pit_of_malice",
    "alchemist_unstable_concoction alchemist_unstable_concoction_throw",
    "ancient_apparition_cold_feet",
    "axe_berserkers_call",
    "bane_nightmare",
    "batrider_flaming_lasso",
    "centaur_hoof_stomp",
    "chaos_knight_chaos_bolt",
    "crystal_maiden_frostbite",
    "dark_seer_vacuum",
    "dark_willow_bramble_maze dark_willow_cursed_crown",
    "death_prophet_silence",
    "disruptor_static_storm",
    "dragon_knight_dragon_tail",
    "drow_ranger_wave_of_silence",
    "earth_spirit_rolling_boulder earth_spirit_geomagnetic_grip",
    "earthshaker_fissure",
    "elder_titan_echo_stomp",
    "ember_spirit_searing_chains",
    "enigma_malefice",
    "furion_sprout",
    "gyrocopter_homing_missile",
    "hoodwink_bushwhack",
    "invoker_tornado invoker_cold_snap invoker_deafening_blast",
    "jakiro_ice_path",
    "keeper_of_the_light_blinding_light",
    "kunkka_torrent",
    "leshrac_split_earth",
    "lich_sinister_gaze",
    "lina_light_strike_array",
    "lion_impale lion_voodoo",
    "magnataur_skewer magnataur_horn_toss",
    "marci_grapple",
    "mars_spear",
    "meepo_earthbind",
    "mirana_arrow",
    "monkey_king_boundless_strike",
    "muerta_the_calling",
    "naga_siren_ensnare",
    "night_stalker_void night_stalker_crippling_fear",
    "nyx_assassin_impale nyx_assassin_spiked_carapace",
    "obsidian_destroyer_astral_imprisonment",
    "ogre_magi_fireblast ogre_magi_unrefined_fireblast",
    "oracle_fortunes_end",
    "pangolier_gyroshell",
    "primal_beast_onslaught",
    "puck_waning_rift",
    "pudge_meat_hook",
    "rattletrap_power_cogs",
    "riki_smoke_screen",
    "ringmaster_tame_the_beasts",
    "sandking_burrowstrike",
    "shadow_demon_disruption",
    "shadow_shaman_voodoo shadow_shaman_shackles",
    "silencer_last_word",
    "skeleton_king_hellfire_blast",
    "skywrath_mage_ancient_seal",
    "slardar_slithereen_crush",
    "snapfire_firesnap_cookie",
    "spirit_breaker_charge_of_darkness",
    "storm_spirit_electric_vortex",
    "sven_storm_bolt",
    "techies_sticky_bomb",
    "terrorblade_terror_wave",
    "tinker_warp_grenade",
    "tiny_avalanche tiny_toss",
    "treant_natures_grasp",
    "troll_warlord_berserkers_rage",
    "tusk_snowball tusk_launch_snowball",
    "vengefulspirit_magic_missile vengefulspirit_nether_swap",
    "void_spirit_aether_remnant",
    "windrunner_shackleshot",
    "witch_doctor_paralyzing_cask",
    "rubick_telekinesis",
    "lone_druid_savage_roar lone_druid_savage_roar_bear",
    "morphling_adaptive_strike_str morphling_adaptive_strike_agi",
    "item_force_staff item_hurricane_pike item_cyclone item_wind_waker item_sheepstick item_abyssal_blade",
    "item_orchid item_bloodthorn item_rod_of_atos item_gungir",
]);

const ESCAPE: Record<string, true> = set([
    "antimage_blink",
    "bounty_hunter_wind_walk",
    "clinkz_wind_walk",
    "dazzle_shallow_grave",
    "ember_spirit_fire_remnant",
    "faceless_void_time_walk",
    "invoker_ghost_walk",
    "juggernaut_blade_fury",
    "kez_grappling_claw",
    "life_stealer_rage",
    "marci_companion_run",
    "meepo_poof",
    "mirana_leap mirana_invis",
    "monkey_king_tree_dance",
    "nyx_assassin_vendetta",
    "phantom_assassin_phantom_strike",
    "phantom_lancer_doppelwalk",
    "phoenix_icarus_dive",
    "puck_phase_shift",
    "pugna_decrepify",
    "queenofpain_blink",
    "riki_blink_strike",
    "shadow_demon_disruption",
    "shredder_timber_chain",
    "slark_pounce slark_shadow_dance",
    "storm_spirit_ball_lightning",
    "visage_silent_as_the_grave",
    "void_spirit_astral_step void_spirit_dissimilate",
    "weaver_shukuchi",
    "winter_wyvern_cold_embrace",
    "wisp_relocate",
    "zuus_heavenly_jump",
    "morphling_waveform",
    "item_blink item_swift_blink item_arcane_blink item_overwhelming_blink",
    "item_force_staff item_hurricane_pike item_cyclone item_wind_waker item_glimmer_cape item_black_king_bar",
    "item_shadow_blade item_silver_edge",
]);

export function IsEscape(name: string): boolean {
    return ESCAPE[name] === true;
}

export function Classify(name: string, isUltimate: boolean): "ult" | "key" | "other" {
    if (isUltimate) return "ult";
    if (KEY[name] === true || ESCAPE[name] === true) return "key";
    return "other";
}
