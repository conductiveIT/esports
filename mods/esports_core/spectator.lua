esports_core.spectators = {}  -- name -> {target = "playerName" or nil}

function esports_core.is_spectator(name)
	return not not esports_core.spectators[name]
end

function esports_core.set_spectator(player, enable)
	local target_name = player:get_player_name()
	if enable then
		-- Enable Spectator Mode
		esports_core.spectators[target_name] = {target = nil}
		player:set_properties({visual_size = {x=0, y=0, z=0}})
		esports_core.teams.update_nametag(player)
		player:set_physics_override({gravity = 1.0, speed = 2.0})

		-- Hide HUD for cinematic view
		player:hud_set_flags({hotbar = false, healthbar = false, breathbar = false, chat = false})

		-- Grant privs
		local privs = core.get_player_privs(target_name)
		privs.fly = true
		privs.noclip = true
		privs.fast = true
		core.set_player_privs(target_name, privs)

		-- Clear from any active match team
		if esports_core.teams then
			esports_core.teams.players[target_name] = nil
		end

		esports_core.hud.init_hud(player)
	else
		-- Disable Spectator Mode
		esports_core.spectators[target_name] = nil
		player:set_properties({visual_size = {x=1, y=1, z=1}})
		player:set_nametag_attributes({color = {a=255, r=255, g=255, b=255}})

		-- Restore HUD
		player:hud_set_flags({hotbar = true, healthbar = true, breathbar = true, chat = true})

		-- Remove privs and restore physics
		player:set_physics_override({gravity = 1.0, speed = 1.2, jump = 1.1})
		local privs = core.get_player_privs(target_name)
		privs.fly = nil
		privs.noclip = nil
		privs.fast = nil
		core.set_player_privs(target_name, privs)

		esports_core.hud.init_hud(player)
		if esports_core.broadcaster then
			esports_core.broadcaster.clear_hud(player)
		end
	end
end

-- COMMANDS
core.register_chatcommand("spectate", {
	params = "<name>",
	description = "Toggle spectator mode for a player (Admin only)",
	privs = {server = true},
	func = function(name, param)
		local target_name = param == "" and name or param
		local player = core.get_player_by_name(target_name)
		if not player then return false, "Player not found." end

		if esports_core.spectators[target_name] then
			esports_core.set_spectator(player, false)
			core.chat_send_player(target_name, "Spectator mode disabled.")
			return true, "Spectator mode disabled for " .. target_name
		else
			esports_core.set_spectator(player, true)
			core.chat_send_player(target_name, "Spectator mode enabled! Use /follow <name> or /follow off")
			return true, "Spectator mode enabled for " .. target_name
		end
	end
})

core.register_chatcommand("follow", {
	params = "[target_name] | off",
	description = "Follow a player cinematically (Spectator only). Leave blank for menu.",
	func = function(name, param)
		if not esports_core.spectators[name] then
			return false, "You must be in /spectate mode to use this."
		end

		if param == "off" then
			esports_core.spectators[name].target = nil
			return true, "Stopped following."
		end

		if param == "" then
			esports_core.spectators.show_follow_menu(name)
			return true
		end

		local target = core.get_player_by_name(param)
		if not target then return false, "Target player not found." end
		if target:get_player_name() == name then return false, "Cannot follow yourself." end

		esports_core.spectators[name].target = param
		return true, "Now following " .. param .. " cinematically."
	end
})

local follow_lists = {}  -- name -> {list_of_names}

function esports_core.spectators.show_follow_menu(name)
	local active_players = {}
	local list_items = {}

	-- Filter for players actually in the match (those with a team side assignment)
	if esports_core.teams and esports_core.teams.players then
		for pname, side in pairs(esports_core.teams.players) do
			if core.get_player_by_name(pname) then
				table.insert(active_players, pname)
				table.insert(list_items, pname .. " (" .. side:upper() .. ")")
			end
		end
	end

	follow_lists[name] = active_players

	local fs = "formspec_version[6]size[8,10]" ..
		"background9[0,0;8,10;esports_hud_bar.png;false;10]" ..
		"style_type[button;bgcolor=#333333;textcolor=white;font=bold]" ..
		"style_type[label;textcolor=white;font=bold]" ..
		"label[1,0.5;SPECTATOR: SELECT PLAYER TO FOLLOW]" ..
		"textlist[1,1;6,7;follower_list;" .. table.concat(list_items, ",") .. ";0;false]" ..
		"button[1,8.5;3,0.8;stop_follow;STOP FOLLOWING]" ..
		"button[4,8.5;3,0.8;close;CLOSE]"

	if #list_items == 0 then
		fs = fs:gsub("textlist.-]", "label[1,4;No active players currently in the arena.]")
	end

	core.show_formspec(name, "esports_core:spectate_follow", fs)
end

core.register_on_player_receive_fields(function(player, formname, fields)
	if formname ~= "esports_core:spectate_follow" then return end
	local name = player:get_player_name()

	if fields.stop_follow then
		if esports_core.spectators[name] then
			esports_core.spectators[name].target = nil
		end
		core.close_formspec(name, "esports_core:spectate_follow")
		core.chat_send_player(name, "Stopped following.")
		return
	end

	if fields.follower_list then
		local event = core.explode_textlist_event(fields.follower_list)
		if event.type == "CHG" or event.type == "DCL" then
			local list = follow_lists[name]
			if list and list[event.index] then
				local target = list[event.index]
				if esports_core.spectators[name] then
					esports_core.spectators[name].target = target
					core.chat_send_player(name, "Now following " .. target)
				end
				if event.type == "DCL" then
					core.close_formspec(name, "esports_core:spectate_follow")
				end
			end
		end
	end

	if fields.close or fields.quit then
		core.close_formspec(name, "esports_core:spectate_follow")
	end
end)

-- CHAT SUPPRESSION
core.register_on_chat_message(function(name, message)
	if esports_core.spectators[name] then
		core.chat_send_player(name, "Spectators cannot talk in chat.")
		return true  -- Block message
	end
end)

-- CINEMATIC UPDATE
core.register_globalstep(function(dtime)
	for spec_name, data in pairs(esports_core.spectators) do
		local spectator = core.get_player_by_name(spec_name)
		if spectator then
			if data.target then
				local target = core.get_player_by_name(data.target)
				if target and target:get_hp() > 0 then
					-- If not already attached, perform the high-sync attachment
					if not spectator:get_attach() then
						-- Attach exactly at target center (0,0,0)
						spectator:set_attach(target, "", {x=0, y=0, z=0}, {x=0, y=0, z=0})

						-- Shift the CAMERA (not the body) over the shoulder
						-- Units for eye_offset are nodes * 10.
						-- X=7 (right), Y=15 (height), Z=-25 (back)
						spectator:set_eye_offset({x=7, y=15, z=-25}, {x=7, y=15, z=-25})

						-- Ensure spectator is invisible
						spectator:set_properties({visual_size = {x=0, y=0, z=0}})
					end
				else
					data.target = nil
				end
			else
				-- Not following, clean up attachment and eye offset
				if spectator:get_attach() then
					spectator:set_detach()
					spectator:set_eye_offset({x=0, y=0, z=0}, {x=0, y=0, z=0})
				end
			end
		end
	end
end)

-- Session Cleanup
core.register_on_leaveplayer(function(player)
	esports_core.spectators[player:get_player_name()] = nil
end)
