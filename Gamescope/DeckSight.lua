-- DeckSight OLED (80 Hz base; VFP-only DRR downshifts, OLED Deck Style)

local decksight_oled_colorimetry_spec = {
    r = { x = 0.6816, y = 0.3154 },
    g = { x = 0.2402, y = 0.7158 },
    b = { x = 0.1376, y = 0.0458 },
    w = { x = 0.3095, y = 0.3164 }
}

-- colorimetry measured
local decksight_oled_colorimetry_measured = {
    r = { x = 0.6854, y = 0.3158 },
    g = { x = 0.2451, y = 0.7140 },
    b = { x = 0.1376, y = 0.0526 },
    w = { x = 0.3117, y = 0.3197 }
}

local deckSight_refresh_rates = { 80, 75, 70, 65, 60, 55, 50, 45 }

-- Expected 80 Hz base 197800 kHz, H=1080/1128/1160/1240, V base VFP=3 VSW=10 VBP=61
local EXPECTED_CLOCK_KHZ_80 = 197800

-- Precomputed VFPs when base is 80 Hz (your table, extended)
local vfp_for_80 = {
    [80] = 3,
    [75] = 136,
    [70] = 288,
    [65] = 463,
    [60] = 668,
    [55] = 909,
    [50] = 1199,
    [45] = 1554,
}

local function is_base_80(m)
return m.vrefresh == 80 and m.clock == EXPECTED_CLOCK_KHZ_80
end

local deckSight_modegen = function(base_mode, refresh)
if not is_base_80(base_mode) then
    debug(string.format("[DeckSight] Skip DRR: base %0.2f Hz @ %dkHz (expect 80 Hz @ %d kHz)",
                        base_mode.vrefresh or -1, base_mode.clock or -1, EXPECTED_CLOCK_KHZ_80))
    return base_mode
    end

    local vfp = vfp_for_80[refresh]
    if not vfp then return base_mode end

        local mode = base_mode
        gamescope.modegen.adjust_front_porch(mode, vfp)
        mode.vrefresh = gamescope.modegen.calc_vrefresh(mode)
        return mode
        end

        gamescope.config.known_displays.decksight = {
            pretty_name = "DeckSight OLED",
            dynamic_refresh_rates = deckSight_refresh_rates,
            dynamic_modegen = deckSight_modegen,

            colorimetry = decksight_oled_colorimetry_spec, -- choose colorimetry

            hdr = {
                supported = true,
                force_enabled = true,
                    eotf = gamescope.eotf.gamma22,
                    max_content_light_level = 900,
                    max_frame_average_luminance = 700,
                    min_content_light_level = 0,
            },

            matches = function(d)
            if d.vendor == "DSO" and d.product == 0x5001 then
                debug("[DeckSight] matched DSO:5001"); return 5000
                end
                return -1
                end
        }

        debug("Registered DeckSight OLED, don't hurt yourself")
