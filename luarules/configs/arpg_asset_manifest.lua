-- Native Recoil/BAR Lua asset manifest for Wreckage Protocol (Item 5b)
-- Maps modular chassis attachments, zone bosses, HUD crests, and announcer voice callouts
-- to native VFS paths under bitmaps/arpg_icons/ and sounds/arpg_vo/.

local ArpgAssetManifest = {
    part_icons = {
        mod_lazarus_rez_attachment = "bitmaps/arpg_icons/arpg_part_mod_lazarus_rez_attachment.png",
        salvage_core_mk1           = "bitmaps/arpg_icons/arpg_part_salvage_core_mk1.png",
        magnet_tractor_array       = "bitmaps/arpg_icons/arpg_part_magnet_tractor_array.png",
        void_harpoon_rig           = "bitmaps/arpg_icons/arpg_part_void_harpoon_rig.png",
        thermal_lance_arm          = "bitmaps/arpg_icons/arpg_part_thermal_lance_arm.png",
        reactive_carapace_plating  = "bitmaps/arpg_icons/arpg_part_reactive_carapace_plating.png",
    },
    boss_icons = {
        rust_colossus   = "bitmaps/arpg_icons/arpg_boss_rust_colossus.png",
        slag_leviathan  = "bitmaps/arpg_icons/arpg_boss_slag_leviathan.png",
        lazarus_archon  = "bitmaps/arpg_icons/arpg_boss_lazarus_archon.png",
        cryo_harbinger  = "bitmaps/arpg_icons/arpg_boss_cryo_harbinger.png",
        void_sovereign  = "bitmaps/arpg_icons/arpg_boss_void_sovereign.png",
    },
    hud_icons = {
        scrap_and_power_crest = "bitmaps/arpg_icons/arpg_hud_scrap_and_power_crest.png",
    },
    voice_callouts = {
        wreckage_protocol_init = "sounds/arpg_vo/arpg_wreckage_protocol_init.wav",
        lazarus_array_online   = "sounds/arpg_vo/arpg_lazarus_array_online.wav",
        wreck_fork_prompt      = "sounds/arpg_vo/arpg_wreck_fork_prompt.wav",
        unit_raised            = "sounds/arpg_vo/arpg_unit_raised.wav",
        power_budget_critical  = "sounds/arpg_vo/arpg_power_budget_critical.wav",
        zone_boss_detected     = "sounds/arpg_vo/arpg_zone_boss_detected.wav",
        part_attached          = "sounds/arpg_vo/arpg_part_attached.wav",
        sector_cleared         = "sounds/arpg_vo/arpg_sector_cleared.wav",
    },
}

return ArpgAssetManifest
