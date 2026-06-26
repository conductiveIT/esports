tdm_core.hud = {}
tdm_core.hud.player_huds = {}
tdm_core.hud.kill_feed_events = {} -- Global list of recent kills {killer, k_col, victim, v_col, icon, age}
tdm_core.hud.spectator_feed_huds = {} -- pname -> { {id1, id2, id3}, ... }

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
    
    -- Scoreboard Logos (Dynamic Team Logos)
    local r_team_active = tdm_core.teams.active_team_names.red
    local b_team_active = tdm_core.teams.active_team_names.blue
    
    huds.logo_red = player:hud_add({
        hud_elem_type = "image",
        position = {x = 0.44, y = 0.05},
        scale = {x = 0.05, y = 0.05},
        alignment = {x = 0, y = 0},
        text = tdm_core.get_team_logo(r_team_active, "tdm_logo_red.png"),
    })
    
    huds.logo_blue = player:hud_add({
        hud_elem_type = "image",
        position = {x = 0.56, y = 0.05},
        scale = {x = 0.05, y = 0.05},
        alignment = {x = 0, y = 0},
        text = tdm_core.get_team_logo(b_team_active, "tdm_logo_blue.png"),
    })

    -- Match Timer (Top Center, below scores)
    huds.timer = player:hud_add({
        hud_elem_type = "text",
        position = {x = 0.5, y = 0.1},
        alignment = {x = 0, y = 0},
        number = 0xFFFF00, -- Gold
        text = "05:00",
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
            number = 0xFFFFFF,
        })
        
        -- Initial update
        tdm_core.hud.update_ammo(player)
    end
    
    -- CTF STATUS HUD (Top left area)
    if tdm_core.match.is_ctf then
        huds.ctf_status = player:hud_add({
            hud_elem_type = "text",
            position = {x = 0.05, y = 0.15},
            alignment = {x = 1, y = 0},
            number = 0xFFFF00,
            text = "RED FLAG: HOME\nBLUE FLAG: HOME",
        })

        huds.carrier_alert = player:hud_add({
            hud_elem_type = "text",
            position = {x = 0.5, y = 0.4},
            alignment = {x = 0, y = 0},
            number = 0xFF4444, -- Bright Red/Orange Alert
            text = "", -- Hidden by default
            scale = {x = 2, y = 2},
        })
    end
    
    -- Scoreboard HUD (Center or Top-Left)
    huds.scoreboard = player:hud_add({
        hud_elem_type = "text",
        position = {x = 0.5, y = 0.2},
        alignment = {x = 0, y = 0},
        number = 0xFFFF00, -- Gold color for standings
        text = "", -- Hidden by default for players
        scale = 1.5,
    })
    
    -- Periodic update immediately
    tdm_core.hud.update_scoreboard()
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
            local r_logo = tdm_core.get_team_logo(r_name, "tdm_logo_red.png")
            local b_logo = tdm_core.get_team_logo(b_name, "tdm_logo_blue.png")
            
            player:hud_change(huds.logo_red, "text", r_logo)
            player:hud_change(huds.logo_blue, "text", b_logo)
        end
    end
    
    -- Update CTF HUD if needed
    if tdm_core.match.is_ctf then
        local r_state = tdm_core.ctf.states.red:upper()
        local b_state = tdm_core.ctf.states.blue:upper()
        
        local r_carrier = tdm_core.ctf.get_carrier("red")
        local b_carrier = tdm_core.ctf.get_carrier("blue")
        
        if r_carrier then r_state = "TAKEN BY " .. r_carrier end
        if b_carrier then b_state = "TAKEN BY " .. b_carrier end
        
        local status_text = "RED FLAG: " .. r_state .. "\nBLUE FLAG: " .. b_state
        
        for _, p in ipairs(core.get_connected_players()) do
            local pname = p:get_player_name()
            local huds = tdm_core.hud.player_huds[pname]
            if huds and huds.ctf_status then
                p:hud_change(huds.ctf_status, "text", status_text)
                
                -- Carrier Alert (Specific to the player holding a flag)
                local has_flag = p:get_meta():get_int("has_flag") == 1
                if has_flag then
                    p:hud_change(huds.carrier_alert, "text", ">>> YOU HAVE THE FLAG <<<\nRETURN TO BASE!")
                else
                    p:hud_change(huds.carrier_alert, "text", "")
                end
            end
        end
    end
end

-- Broadcast Feed API
function tdm_core.hud.add_kill_event(killer, k_team, victim, v_team, weapon)
    local k_col = 0xFFFFFF
    if k_team == "red" then k_col = 0xFFAAAA
    elseif k_team == "blue" then k_col = 0xAAAAFF end
    
    local v_col = 0xFFFFFF
    if v_team == "red" then v_col = 0xFFAAAA
    elseif v_team == "blue" then v_col = 0xAAAAFF end
    
    local icon = "tdm_feed_skull.png"
    if weapon == "rifle" then icon = "tdm_feed_rifle.png"
    elseif weapon == "shotgun" then icon = "tdm_feed_shotgun.png"
    elseif weapon == "pickaxe" then icon = "tdm_feed_pickaxe.png" end

    table.insert(tdm_core.hud.kill_feed_events, 1, {
        killer = killer or "Unknown",
        k_col = k_col,
        victim = victim or "Unknown",
        v_col = v_col,
        icon = icon,
        age = 5.0
    })
    
    -- Limit to 5 events
    if #tdm_core.hud.kill_feed_events > 5 then
        table.remove(tdm_core.hud.kill_feed_events)
    end
    
    tdm_core.hud.refresh_spectator_feeds()
end

function tdm_core.hud.refresh_spectator_feeds()
    for _, player in ipairs(core.get_connected_players()) do
        local name = player:get_player_name()
        if tdm_core.is_spectator(name) then
            tdm_core.hud.draw_kill_feed(player)
        else
            -- Ensure active players don't have feed artifacts
            tdm_core.hud.clear_kill_feed(player)
        end
    end
end

function tdm_core.hud.clear_kill_feed(player)
    local name = player:get_player_name()
    local huds = tdm_core.hud.spectator_feed_huds[name]
    if huds then
        for _, ids in ipairs(huds) do
            for _, id in ipairs(ids) do player:hud_remove(id) end
        end
        tdm_core.hud.spectator_feed_huds[name] = nil
    end
end

function tdm_core.hud.draw_kill_feed(player)
    local name = player:get_player_name()
    tdm_core.hud.clear_kill_feed(player)
    
    local huds_list = {}
    local y_start = 0.15
    local y_step = 0.03
    
    for i, event in ipairs(tdm_core.hud.kill_feed_events) do
        local y_pos = y_start + (i-1) * y_step
        
        local ids = {}
        -- Killer
        table.insert(ids, player:hud_add({
            hud_elem_type = "text",
            position = {x = 0.90, y = y_pos},
            text = event.killer,
            number = event.k_col,
            alignment = {x = -1, y = 0},
            scale = 1.0,
        }))
        -- Icon
        table.insert(ids, player:hud_add({
            hud_elem_type = "image",
            position = {x = 0.92, y = y_pos},
            text = event.icon,
            scale = {x = 0.4, y = 0.4}, -- Reduced scale for a sleek look
            alignment = {x = 0, y = 0},
        }))
        -- Victim
        table.insert(ids, player:hud_add({
            hud_elem_type = "text",
            position = {x = 0.95, y = y_pos},
            text = event.victim,
            number = event.v_col,
            alignment = {x = 1, y = 0},
            scale = 1.0,
        }))
        
        table.insert(huds_list, ids)
    end
    
    tdm_core.hud.spectator_feed_huds[name] = huds_list
end

-- Cleanup loop
local feed_timer = 0
core.register_globalstep(function(dtime)
    feed_timer = feed_timer + dtime
    if feed_timer < 0.2 then return end
    feed_timer = 0
    
    local changed = false
    local new_list = {}
    for i, event in ipairs(tdm_core.hud.kill_feed_events) do
        event.age = event.age - 0.2
        if event.age > 0 then
            table.insert(new_list, event)
        else
            changed = true
        end
    end
    
    if changed then
        tdm_core.hud.kill_feed_events = new_list
        tdm_core.hud.refresh_spectator_feeds()
    end
end)

function tdm_core.hud.update_timer(player, time_left, state)
end

function tdm_core.hud.show_intro(player, time, r_name, b_name)
    local pname = player:get_player_name()
    local huds = tdm_core.hud.player_huds[pname]
    if not huds then return end
    
    -- Resolve Logos
    local r_logo = tdm_core.get_team_logo(r_name, "tdm_logo_red.png")
    local b_logo = tdm_core.get_team_logo(b_name, "tdm_logo_blue.png")

    -- Create elements if they don't exist
    if not huds.intro_vs then
        -- Branding Bars for Contrast (Responsive)
        huds.intro_bar_red = player:hud_add({
            hud_elem_type = "image",
            position = {x = 0.3, y = 0.65},
            text = "tdm_hud_bar.png",
            scale = {x = -50, y = -10},
            alignment = {x = 0, y = 0},
        })
        huds.intro_bar_blue = player:hud_add({
            hud_elem_type = "image",
            position = {x = 0.7, y = 0.65},
            text = "tdm_hud_bar.png",
            scale = {x = -50, y = -10},
            alignment = {x = 0, y = 0},
        })

        -- VS Graphic (Responsive)
        huds.intro_vs = player:hud_add({
            hud_elem_type = "image",
            position = {x = 0.5, y = 0.45},
            text = "tdm_hud_vs.png",
            scale = {x = -35, y = -35},
            alignment = {x = 0, y = 0},
        })

        huds.intro_logo_red = player:hud_add({
            hud_elem_type = "image",
            position = {x = 0.3, y = 0.4},
            text = r_logo,
            scale = {x = -25, y = -25},
            alignment = {x = 0, y = 0},
        })
        huds.intro_logo_blue = player:hud_add({
            hud_elem_type = "image",
            position = {x = 0.7, y = 0.4},
            text = b_logo,
            scale = {x = -25, y = -25},
            alignment = {x = 0, y = 0},
        })

        huds.intro_team_red = player:hud_add({
            hud_elem_type = "text",
            position = {x = 0.3, y = 0.65},
            text = (r_name or "Phoenix"):upper(),
            number = 0xFF5555,
            alignment = {x = 0, y = 0},
            scale = 3,
        })
        huds.intro_team_blue = player:hud_add({
            hud_elem_type = "text",
            position = {x = 0.7, y = 0.65},
            text = (b_name or "Wolf"):upper(),
            number = 0x5555FF,
            alignment = {x = 0, y = 0},
            scale = 3,
        })

        -- Pure Image-Based Countdown (Responsive)
        huds.intro_timer_img = player:hud_add({
            hud_elem_type = "image",
            position = {x = 0.5, y = 0.75},
            text = "tdm_hud_5.png",
            scale = {x = -25, y = -25},
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
    
    -- Corrected keys to match actual intro elements
    local keys = {
        "intro_vs", "intro_bar_red", "intro_bar_blue", 
        "intro_team_red", "intro_team_blue", 
        "intro_logo_red", "intro_logo_blue", 
        "intro_timer_img"
    }
    for _, k in ipairs(keys) do
        if huds[k] then
            player:hud_remove(huds[k])
            huds[k] = nil
        end
    end
end

function tdm_core.hud.show_outro(player, data)
    local pname = player:get_player_name()
    local huds = tdm_core.hud.player_huds[pname]
    if not huds then return end
    
    -- Clean previous state
    tdm_core.hud.hide_outro(player)
    
    local title_color = 0xFFFFFF
    if data.color == "red" then title_color = 0xFF4444
    elseif data.color == "blue" then title_color = 0x4444FF end

    -- 1. Full-Screen Backdrop
    huds.outro_bg = player:hud_add({
        hud_elem_type = "image",
        position = {x = 0.5, y = 0.5},
        text = "tdm_hud_bar.png^[colorize:#000000ee",
        scale = {x = -2000, y = -2000},
        alignment = {x = 0, y = 0},
    })
    
    -- 2. Winner Header
    huds.outro_title = player:hud_add({
        hud_elem_type = "text",
        position = {x = 0.5, y = 0.15},
        text = data.title,
        number = title_color,
        scale = 3,
        alignment = {x = 0, y = 0},
    })
    
    -- 3. Dynamic Winner Logo (Resized to 75% for cleaner layout)
    local win_logo = tdm_core.get_team_logo(data.win_team, "tdm_logo_library_dragon.png")
    huds.outro_logo = player:hud_add({
        hud_elem_type = "image",
        position = {x = 0.5, y = 0.35},
        text = win_logo,
        scale = {x = 2.25, y = 2.25},
        alignment = {x = 0, y = 0},
    })
    
    -- 3.5 Interactive Return Button (Manual Transition) - Anchored Bottom
    core.show_formspec(pname, "tdm_core:outro_return", 
        "size[8,2]position[0.5,0.85]anchor[0.5,0.5]bgcolor[#00000000;false]" ..
        "style[return_lobby;bgcolor=#555555;textcolor=gold;font=bold;font_size=24]" ..
        "button[0,0;8,1.5;return_lobby;RETURN TO LOBBY]")
    
    -- 4. MVP Highlight (Gold Text)
    local mvp_label = data.is_ctf and "POINTS" or "KILLS"
    local mvp_txt = "MVP: " .. data.mvp .. " (" .. data.mvp_kills .. " " .. mvp_label .. ")"
    huds.outro_mvp = player:hud_add({
        hud_elem_type = "text",
        position = {x = 0.5, y = 0.50},
        text = mvp_txt,
        number = 0xFFD700,
        scale = 1.5,
        alignment = {x = 0, y = 0},
    })
    
    -- 5. Detailed Scores (Two Columns)
    local red_scores = "RED TEAM STANDINGS\n"
    if data.is_ctf then
        red_scores = red_scores .. "PLAYER               | C | K | D\n" .. string.rep("-", 38) .. "\n"
    else
        red_scores = red_scores .. "PLAYER               | K | D\n" .. string.rep("-", 30) .. "\n"
    end
    
    for _, p in ipairs(data.red_roster) do
        if data.is_ctf then
            red_scores = red_scores .. string.format("%-20s |%2d |%2d |%2d\n", p.name:sub(1,15), p.c, p.k, p.d)
        else
            red_scores = red_scores .. string.format("%-20s |%2d |%2d\n", p.name:sub(1,15), p.k, p.d)
        end
    end
    
    huds.outro_red = player:hud_add({
        hud_elem_type = "text",
        position = {x = 0.35, y = 0.65}, -- Moved to middle
        text = red_scores,
        number = 0xFFAAAA,
        scale = 1.5,
        alignment = {x = 0, y = 0},
    })
    
    local blue_scores = "BLUE TEAM STANDINGS\n"
    if data.is_ctf then
        blue_scores = blue_scores .. "PLAYER               | C | K | D\n" .. string.rep("-", 38) .. "\n"
    else
        blue_scores = blue_scores .. "PLAYER               | K | D\n" .. string.rep("-", 30) .. "\n"
    end
    
    for _, p in ipairs(data.blue_roster) do
        if data.is_ctf then
            blue_scores = blue_scores .. string.format("%-20s |%2d |%2d |%2d\n", p.name:sub(1,15), p.c, p.k, p.d)
        else
            blue_scores = blue_scores .. string.format("%-20s |%2d |%2d\n", p.name:sub(1,15), p.k, p.d)
        end
    end
    
    huds.outro_blue = player:hud_add({
        hud_elem_type = "text",
        position = {x = 0.65, y = 0.65}, -- Moved to middle
        text = blue_scores,
        number = 0xAAAAFF,
        scale = 1.5,
        alignment = {x = 0, y = 0},
    })
end

function tdm_core.hud.hide_outro(player)
    local pname = player:get_player_name()
    local huds = tdm_core.hud.player_huds[pname]
    if not huds then return end
    
    local keys = {"outro_bg", "outro_title", "outro_logo", "outro_mvp", "outro_red", "outro_blue"}
    for _, k in ipairs(keys) do
        if huds[k] then
            player:hud_remove(huds[k])
            huds[k] = nil
        end
    end
    
    -- Explicitly close the return button formspec
    core.close_formspec(pname, "tdm_core:outro_return")
end

tdm_core.hud.update_timer = function(text, is_critical)
    for _, player in ipairs(core.get_connected_players()) do
        local pname = player:get_player_name()
        local huds = tdm_core.hud.player_huds[pname]
        if huds and huds.timer then
            player:hud_change(huds.timer, "text", text)
            if is_critical then
                player:hud_change(huds.timer, "number", 0xFF4444) -- Red
                player:hud_change(huds.timer, "scale", {x=2.5, y=2.5}) -- Large
            else
                player:hud_change(huds.timer, "number", 0xFFFF00) -- Gold
                player:hud_change(huds.timer, "scale", {x=1.2, y=1.2}) -- Normal
            end
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

-- NEW STATS HUD LOGIC
local player_scoreboard_visible = {} -- [pname] = bool

tdm_core.hud.update_scoreboard = function()
    local stats = tdm_core.match.player_stats or {}
    local sorted = {}
    local is_ctf = tdm_core.match.is_ctf
    
    for name, data in pairs(stats) do
        table.insert(sorted, {name = name, kills = data.kills, deaths = data.deaths, captures = data.captures or 0})
    end
    
    -- Dynamic Sort: Captures > Kills > Deaths (less is better)
    table.sort(sorted, function(a, b)
        if is_ctf then
            if a.captures ~= b.captures then return a.captures > b.captures end
        end
        if a.kills ~= b.kills then return a.kills > b.kills end
        return a.deaths < b.deaths
    end)
    
    -- Render Text
    local header = is_ctf and "PLAYER               | CAP | KIL | DEA\n" or "PLAYER               | KILLS | DEATHS\n"
    local separator = string.rep("-", is_ctf and 38 or 35) .. "\n"
    local final_text = "MATCH STANDINGS\n" .. header .. separator
    
    for i, p in ipairs(sorted) do
        if i > 8 then break end -- Show top 8
        local row
        if is_ctf then
            row = string.format("%-20s | %3d | %3d | %3d\n", p.name:sub(1,15), p.captures, p.kills, p.deaths)
        else
            row = string.format("%-20s | %5d | %7d\n", p.name:sub(1,15), p.kills, p.deaths)
        end
        final_text = final_text .. row
    end
    
    for _, player in ipairs(core.get_connected_players()) do
        local name = player:get_player_name()
        local huds = tdm_core.hud.player_huds[name]
        if huds and huds.scoreboard then
            -- Update for spectators and any player currently holding the toggle key
            if tdm_core.is_spectator(name) or player_scoreboard_visible[name] then
                player:hud_change(huds.scoreboard, "text", final_text)
            end
        end
    end
    
    return final_text
end



tdm_core.hud.toggle_scoreboard = function(player, visible)
    local name = player:get_player_name()
    if player_scoreboard_visible[name] == visible then return end
    player_scoreboard_visible[name] = visible
    
    local huds = tdm_core.hud.player_huds[name]
    if huds and huds.scoreboard then
        local text = ""
        if visible then
            text = tdm_core.hud.update_scoreboard()
        end
        player:hud_change(huds.scoreboard, "text", text)
        -- Also show/hide background bar? No, text matches branding bars enough.
    end
end

-- Input Update Loop (Event-driven scoreboard toggle)
core.register_globalstep(function(dtime)
    for _, player in ipairs(core.get_connected_players()) do
        local name = player:get_player_name()
        if not tdm_core.is_spectator(name) then
            local controls = player:get_player_control()
            tdm_core.hud.toggle_scoreboard(player, controls.aux1)
        end
    end
end)

core.register_on_player_receive_fields(function(player, formname, fields)
    if formname == "tdm_core:outro_return" and fields.return_lobby then
        tdm_core.hud.hide_outro(player)
        tdm_core.lobby.show(player)
        -- Ensure lobby physics are reset
        if not core.check_player_privs(player:get_player_name(), {server=true}) then
            player:set_physics_override({speed = 0, jump = 0})
        end
        return true
    end
end)
