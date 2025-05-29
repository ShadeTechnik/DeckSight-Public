-- DeckSight OLED - Static Dynamic Refresh Range (40-80Hz)

local deckSight_refresh_rates = {
    40, 41, 42, 43, 44, 45, 46, 47, 48, 49,
    50, 51, 52, 53, 54, 55, 56, 57, 58, 59,
    60, 61, 62, 63, 64, 65, 66, 67, 68, 69,
    70, 71, 72, 73, 74, 75, 76, 77, 78, 79,
    80
}

local deckSight_modegen = function(base_mode, refresh)
    local mode = base_mode

    -- Set fixed resolution for DeckSight OLED (rotated)
    gamescope.modegen.set_resolution(mode, 1080, 1920)

    -- Set porch timings based on actual EDID values (mode, HFP, HSync, HBP)
    gamescope.modegen.set_h_timings(mode, 60, 60, 16)
    gamescope.modegen.set_v_timings(mode, 5, 5, 32)

    -- Recalculate pixel clock and vrefresh based on new timing and refresh
    mode.clock = gamescope.modegen.calc_max_clock(mode, refresh)
    mode.vrefresh = gamescope.modegen.calc_vrefresh(mode)

    return mode
end

-- DeckSight OLED Registration
gamescope.config.known_displays.decksight = {
    pretty_name = "DeckSight OLED",
    dynamic_refresh_rates = deckSight_refresh_rates,
    dynamic_modegen = deckSight_modegen,
    matches = function(display)
        -- Match Vendor and Product (DSO - DeckSight)
        if display.vendor == "DSO" and display.product == 0x0001 then
            return 5000
        end
        return -1
    end
}

debug("Registered DeckSight OLED with corrected EDID porch timings and 40-80Hz dynamic refresh slider")


