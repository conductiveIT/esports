tdm_core.hud = {}
tdm_core.hud.player_huds = {}

tdm_core.hud.init_hud = function(player)
    local player_name = player:get_player_name()
    
    -- Clean up existing HUD if it exists to prevent duplication
    if tdm_core.hud.player_huds[player_name] then
        for _, id in pairs(tdm_core.hud.player_huds[player_name]) do
            player:hud_remove(id)
        end
    end
    
    tdm_core.hud.player_huds[player_name] = {}
    local huds = tdm_core.hud.player_huds[player_name]

    
    -- Score HUD
    huds.scores = player:hud_add({
        hud_elem_type = "text",
        position = {x = 0.5, y = 0.05},
        alignment = {x = 0, y = 0},
        number = 0xFFFFFF,
        text = "Red 0 - 0 Blue",
    })
    
    -- Scoreboard Logos
    huds.logo_red = player:hud_add({
        hud_elem_type = "image",
        position = {x = 0.44, y = 0.05},
        scale = {x = 0.05, y = 0.05},
        alignment = {x = 0, y = 0},
        text = "tdm_logo_red.png",
    })
    
    huds.logo_blue = player:hud_add({
        hud_elem_type = "image",
        position = {x = 0.56, y = 0.05},
        scale = {x = 0.05, y = 0.05},
        alignment = {x = 0, y = 0},
        text = "tdm_logo_blue.png",
    })
    
    -- Team assignment indicator (Only for combatants)
    if not tdm_core.is_spectator(player_name) then
        local team = tdm_core.teams.get_player_team(player_name)
        local color = 0xFF0000
        if team == "blue" then color = 0x0000FF end
        huds.team = player:hud_add({
            hud_elem_type = "text",
            position = {x = 0.05, y = 0.95},
            offset = {x = 0, y = 0},
            text = "Team: " .. (team or "None"),
            alignment = {x = 1, y = 0},
            scale = {x = 100, y = 100},
            number = color,
        })
        
        -- Ammo HUD (Bottom Right)
        huds.ammo = player:hud_add({
            hud_elem_type = "text",
            position = {x = 0.95, y = 0.95},
            offset = {x = 0, y = 0},
            text = "Rifle: 0 | Shotgun: 0",
            alignment = {x = -1, y = 0},
            scale = {x = 100, y = 100},
            number = 0xFFFFFF,
        })
        
        -- Initial update
        tdm_core.hud.update_ammo(player)
    end
end

tdm_core.hud.update_scores = function()
    local r_name = tdm_core.teams.active_team_names.red
    local b_name = tdm_core.teams.active_team_names.blue
    local score_text = string.format("%s %d - %d %s", r_name, tdm_core.teams.scores.red, tdm_core.teams.scores.blue, b_name)
    
    for _, player in ipairs(core.get_connected_players()) do
        local huds = tdm_core.hud.player_huds[player:get_player_name()]
        if huds and huds.scores then
            player:hud_change(huds.scores, "text", score_text)
            
            -- Resolve Logos
            local r_logo = "tdm_logo_red.png"
            local b_logo = "tdm_logo_blue.png"
            
            if tdm_league and tdm_league.teams[r_name] and tdm_league.teams[r_name].logo_id then
                r_logo = "tdm_logo_lib_" .. tdm_league.teams[r_name].logo_id .. ".png"
            end
            if tdm_league and tdm_league.teams[b_name] and tdm_league.teams[b_name].logo_id then
                b_logo = "tdm_logo_lib_" .. tdm_league.teams[b_name].logo_id .. ".png"
            end
            
            player:hud_change(huds.logo_red, "text", r_logo)
            player:hud_change(huds.logo_blue, "text", b_logo)
        end
    end
end

function tdm_core.hud.show_intro(player, time, r_name, b_name)
    local pname = player:get_player_name()
    local huds = tdm_core.hud.player_huds[pname]
    if not huds then return end
    
    -- Resolve Logos
    local r_logo = "tdm_logo_red.png"
    local b_logo = "tdm_logo_blue.png"
    if tdm_league and tdm_league.teams[r_name] and tdm_league.teams[r_name].logo_id then
        r_logo = "tdm_logo_lib_" .. tdm_league.teams[r_name].logo_id .. ".png"
    end
    if tdm_league and tdm_league.teams[b_name] and tdm_league.teams[b_name].logo_id then
        b_logo = "tdm_logo_lib_" .. tdm_league.teams[b_name].logo_id .. ".png"
    end

    -- Create elements if they don't exist
    if not huds.intro_vs then
        -- Branding Bars for Contrast
        huds.intro_bar_red = player:hud_add({
            hud_elem_type = "image",
            position = {x = 0.3, y = 0.65},
            text = "tdm_hud_bar.png",
            scale = {x = 1.5, y = 1.5},
            alignment = {x = 0, y = 0},
        })
        huds.intro_bar_blue = player:hud_add({
            hud_elem_type = "image",
            position = {x = 0.7, y = 0.65},
            text = "tdm_hud_bar.png",
            scale = {x = 1.5, y = 1.5},
            alignment = {x = 0, y = 0},
        })

        -- VS Graphic
        huds.intro_vs = player:hud_add({
            hud_elem_type = "image",
            position = {x = 0.5, y = 0.45},
            text = "tdm_hud_vs.png",
            scale = {x = 0.25, y = 0.25},
            alignment = {x = 0, y = 0},
        })

        huds.intro_logo_red = player:hud_add({
            hud_elem_type = "image",
            position = {x = 0.3, y = 0.4},
            text = r_logo,
            scale = {x = 0.3, y = 0.3},
            alignment = {x = 0, y = 0},
        })
        huds.intro_logo_blue = player:hud_add({
            hud_elem_type = "image",
            position = {x = 0.7, y = 0.4},
            text = b_logo,
            scale = {x = 0.3, y = 0.3},
            alignment = {x = 0, y = 0},
        })

        huds.intro_team_red = player:hud_add({
            hud_elem_type = "text",
            position = {x = 0.3, y = 0.65},
            text = (r_name or "Phoenix"):upper(),
            number = 0xFF5555,
            alignment = {x = 0, y = 0},
        })
        huds.intro_team_blue = player:hud_add({
            hud_elem_type = "text",
            position = {x = 0.7, y = 0.65},
            text = (b_name or "Wolf"):upper(),
            number = 0x5555FF,
            alignment = {x = 0, y = 0},
        })

        -- Pure Image-Based Countdown (Native Assets)
        huds.intro_timer_img = player:hud_add({
            hud_elem_type = "image",
            position = {x = 0.5, y = 0.75},
            text = "tdm_hud_5.png",
            scale = {x = 0.35, y = 0.35},
            alignment = {x = 0, y = 0},
        })
    end

    -- UPDATE HUD STATE
    if time >= 1 and time <= 5 then
        player:hud_change(huds.intro_timer_img, "text", "tdm_hud_" .. time .. ".png")
    elseif time == 0 then
        player:hud_change(huds.intro_timer_img, "text", "tdm_hud_go.png")
    end
end

function tdm_core.hud.hide_intro(player)
    local pname = player:get_player_name()
    local huds = tdm_core.hud.player_huds[pname]
    if not huds then return end
    
    local keys = {"intro_bar_red", "intro_bar_blue", "intro_vs", "intro_logo_red", "intro_logo_blue", "intro_team_red", "intro_team_blue", "intro_timer_img"}
    for _, key in ipairs(keys) do
        if huds[key] then
            player:hud_remove(huds[key])
            huds[key] = nil
        end
    end
end

tdm_core.hud.update_timer = function(text)
    for _, player in ipairs(core.get_connected_players()) do
        local huds = tdm_core.hud.player_huds[player:get_player_name()]
        if huds and huds.timer then
            player:hud_change(huds.timer, "text", text)
        end
    end
end

tdm_core.hud.update_ammo = function(player)
    local inv = player:get_inventory()
    local rifle_count = 0
    local shotgun_count = 0
    
    -- Check hidden ammo list
    local ammo_list = inv:get_list("ammo")
    if ammo_list then
        for _, stack in ipairs(ammo_list) do
            local name = stack:get_name()
            if name == "tdm_weapons:rifle_ammo" then
                rifle_count = rifle_count + stack:get_count()
            elseif name == "tdm_weapons:shotgun_ammo" then
                shotgun_count = shotgun_count + stack:get_count()
            end
        end
    end
    
    -- Check main list too just in case (e.g. legacy or pickaxe drops)
    local main_list = inv:get_list("main")
    if main_list then
        for _, stack in ipairs(main_list) do
            local name = stack:get_name()
            if name == "tdm_weapons:rifle_ammo" then
                rifle_count = rifle_count + stack:get_count()
            elseif name == "tdm_weapons:shotgun_ammo" then
                shotgun_count = shotgun_count + stack:get_count()
            end
        end
    end
    
    local text = string.format("Rifle: %d | Shotgun: %d", rifle_count, shotgun_count)
    local huds = tdm_core.hud.player_huds[player:get_player_name()]
    if huds and huds.ammo then
        player:hud_change(huds.ammo, "text", text)
    end
end
