esports_core.dom = {}
esports_core.dom.points = {
	A = {name = "A", center = nil, owner = "none", cap_progress = 0, placed_ring = nil, label_ent = nil},
	B = {name = "B", center = nil, owner = "none", cap_progress = 0, placed_ring = nil, label_ent = nil},
	C = {name = "C", center = nil, owner = "none", cap_progress = 0, placed_ring = nil, label_ent = nil}
}
esports_core.dom.radius = 6

function esports_core.dom.reset()
	for _, pt in pairs(esports_core.dom.points) do
		if pt.placed_ring and pt.placed_ring:get_luaentity() then
			pt.placed_ring:remove()
		end
		pt.placed_ring = nil

		if pt.label_ent and pt.label_ent:get_luaentity() then
			pt.label_ent:remove()
		end
		pt.label_ent = nil
		pt.owner = "none"
		pt.cap_progress = 0
	end
end

function esports_core.dom.setup()
	esports_core.dom.reset()

	local layout = esports_core.match.current_map_layout or "circular"

	if layout == "circular" then
		-- Triangle Layout
		esports_core.dom.points.A.center = {x = 40 * scale, y = 1.0, z = -15 * scale}
		esports_core.dom.points.B.center = {x = 0, y = 1.0, z = 15 * scale}
		esports_core.dom.points.C.center = {x = -40 * scale, y = 1.0, z = -15 * scale}
	elseif layout == "choke_point" then
		-- Linear central bridge layout
		esports_core.dom.points.A.center = {x = 35 * scale, y = 1.0, z = 0}
		esports_core.dom.points.B.center = {x = 0, y = 1.0, z = 0}
		esports_core.dom.points.C.center = {x = -35 * scale, y = 1.0, z = 0}
	elseif layout == "three_lanes" then
		-- One point per lane
		esports_core.dom.points.A.center = {x = 0, y = 1.0, z = -25 * scale} -- Bottom Lane
		esports_core.dom.points.B.center = {x = 0, y = 1.0, z = 0}           -- Middle Lane
		esports_core.dom.points.C.center = {x = 0, y = 1.0, z = 25 * scale}  -- Top Lane
	elseif layout == "split_center" then
		-- Point B in center, A & C on left/right approach bridges
		esports_core.dom.points.A.center = {x = 35 * scale, y = 1.0, z = 0}
		esports_core.dom.points.B.center = {x = 0, y = 1.0, z = 0}
		esports_core.dom.points.C.center = {x = -35 * scale, y = 1.0, z = 0}
	end

	for id, pt in pairs(esports_core.dom.points) do
		pt.owner = "none"
		pt.cap_progress = 0

		-- 1. Clear blocks around the point
		local center = pt.center
		local rad = esports_core.dom.radius
		for x = center.x - rad, center.x + rad do
			for z = center.z - rad, center.z + rad do
				local dist = math.sqrt((x - center.x)^2 + (z - center.z)^2)
				if dist <= rad then
					for y = 1, 4 do
						local p = {x = x, y = y, z = z}
						local name = core.get_node(p).name
						if name ~= "air" and name ~= "ignore" then
							core.remove_node(p)
						end
					end
				end
			end
		end

		-- 2. Spawn ring entity
		local ring_pos = {x = center.x, y = 0.55, z = center.z}
		pt.placed_ring = core.add_entity(ring_pos, "esports_core:dom_ring")
		if pt.placed_ring then
			pt.placed_ring:set_properties({
				visual_size = {x = rad * 2, y = 0.1, z = rad * 2},
				textures = {"esports_hud_bar.png^[colorize:#FFFFFF:150"}
			})
		end

		-- 3. Spawn label entity
		local label_pos = {x = center.x, y = 2.0, z = center.z}
		pt.label_ent = core.add_entity(label_pos, "esports_core:dom_label")
		if pt.label_ent then
			pt.label_ent:set_properties({
				nametag = "POINT " .. id,
				nametag_color = {a = 255, r = 255, g = 255, b = 255}
			})
		end
	end

	core.chat_send_all(">> DOMINATION: Capture and hold Points A, B, and C!")
end

function esports_core.dom.update(dtime)
	if esports_core.match.state ~= "active" or not esports_core.match.is_domination then
		return
	end

	local all_players = core.get_connected_players()
	local points_awarded = {red = 0, blue = 0}

	for id, pt in pairs(esports_core.dom.points) do
		local center = pt.center
		if center then
			local red_in_zone = 0
			local blue_in_zone = 0
			local red_names = {}
			local blue_names = {}

			for _, p in ipairs(all_players) do
				local pname = p:get_player_name()
				if not esports_core.is_spectator(pname) and p:get_hp() > 0 then
					local pos = p:get_pos()
					local dist = math.sqrt((pos.x - center.x)^2 + (pos.z - center.z)^2)
					if dist <= esports_core.dom.radius and math.abs(pos.y - center.y) <= 3 then
						local team = esports_core.teams.get_player_team(pname)
						if team == "red" then
							red_in_zone = red_in_zone + 1
							table.insert(red_names, pname)
						elseif team == "blue" then
							blue_in_zone = blue_in_zone + 1
							table.insert(blue_names, pname)
						end
					end
				end
			end

			local next_owner = pt.owner

			if red_in_zone > 0 and blue_in_zone == 0 then
				-- Red capturing or defending
				if pt.owner == "blue" then
					pt.cap_progress = pt.cap_progress - 20
					if pt.cap_progress <= 0 then
						pt.cap_progress = 0
						next_owner = "none"
						core.chat_send_all(">> DOMINATION: Point " .. id .. " has been neutralized by RED!")
					end
				elseif pt.owner == "none" then
					pt.cap_progress = pt.cap_progress + 20
					if pt.cap_progress >= 100 then
						pt.cap_progress = 100
						next_owner = "red"
						core.chat_send_all(">> DOMINATION: Point " .. id .. " has been captured by RED!")
						core.sound_play("esports_pickup", {pos = center, gain = 1.0})
					end
				end

				-- Track player stats
				for _, pname in ipairs(red_names) do
					if not esports_core.match.player_stats[pname] then
						esports_core.match.player_stats[pname] = {kills = 0, deaths = 0, captures = 0, dom_points = 0}
					end
					esports_core.match.player_stats[pname].dom_points = (esports_core.match.player_stats[pname].dom_points or 0) + 1
				end

			elseif blue_in_zone > 0 and red_in_zone == 0 then
				-- Blue capturing or defending
				if pt.owner == "red" then
					pt.cap_progress = pt.cap_progress - 20
					if pt.cap_progress <= 0 then
						pt.cap_progress = 0
						next_owner = "none"
						core.chat_send_all(">> DOMINATION: Point " .. id .. " has been neutralized by BLUE!")
					end
				elseif pt.owner == "none" then
					pt.cap_progress = pt.cap_progress + 20
					if pt.cap_progress >= 100 then
						pt.cap_progress = 100
						next_owner = "blue"
						core.chat_send_all(">> DOMINATION: Point " .. id .. " has been captured by BLUE!")
						core.sound_play("esports_pickup", {pos = center, gain = 1.0})
					end
				end

				-- Track player stats
				for _, pname in ipairs(blue_names) do
					if not esports_core.match.player_stats[pname] then
						esports_core.match.player_stats[pname] = {kills = 0, deaths = 0, captures = 0, dom_points = 0}
					end
					esports_core.match.player_stats[pname].dom_points = (esports_core.match.player_stats[pname].dom_points or 0) + 1
				end
			end

			pt.owner = next_owner

			-- Update visuals
			local texture = "esports_hud_bar.png^[colorize:#FFFFFF:150"
			local label_color = {a = 255, r = 255, g = 255, b = 255}

			if pt.owner == "red" then
				texture = "esports_hud_bar.png^[colorize:#FF3333:200"
				label_color = {a = 255, r = 255, g = 50, b = 50}
				points_awarded.red = points_awarded.red + 1
			elseif pt.owner == "blue" then
				texture = "esports_hud_bar.png^[colorize:#3333FF:200"
				label_color = {a = 255, r = 50, g = 50, b = 255}
				points_awarded.blue = points_awarded.blue + 1
			elseif red_in_zone > 0 and blue_in_zone > 0 then
				texture = "esports_hud_bar.png^[colorize:#FFFF33:200"
				label_color = {a = 255, r = 255, g = 255, b = 50}
			elseif pt.cap_progress > 0 then
				texture = "esports_hud_bar.png^[colorize:#CCCCCC:150"
			end

			if pt.placed_ring and pt.placed_ring:get_luaentity() then
				pt.placed_ring:set_properties({textures = {texture}})
			end

			if pt.label_ent and pt.label_ent:get_luaentity() then
				local progress_text = ""
				if pt.owner == "none" and pt.cap_progress > 0 then
					progress_text = string.format(" (%d%%)", pt.cap_progress)
				end
				pt.label_ent:set_properties({
					nametag = "POINT " .. id .. progress_text,
					nametag_color = label_color
				})
			end
		end
	end

	-- Award scores
	if points_awarded.red > 0 then
		esports_core.teams.scores.red = esports_core.teams.scores.red + points_awarded.red
	end
	if points_awarded.blue > 0 then
		esports_core.teams.scores.blue = esports_core.teams.scores.blue + points_awarded.blue
	end

	if points_awarded.red > 0 or points_awarded.blue > 0 then
		if esports_core.hud and esports_core.hud.update_scores then
			esports_core.hud.update_scores()
		end
	end
end

-- Block building on domination points
core.register_on_placenode(function(pos, newnode, placer, oldnode, itemstack, pointed_thing)
	if not esports_core.match.is_domination then return end
	if not placer or not placer:is_player() then return end

	local pname = placer:get_player_name()
	if core.check_player_privs(pname, {server=true}) or core.check_player_privs(pname, {admin=true}) then
		return
	end

	for id, pt in pairs(esports_core.dom.points) do
		local center = pt.center
		if center then
			local dist = math.sqrt((pos.x - center.x)^2 + (pos.z - center.z)^2)
			if dist <= esports_core.dom.radius and math.abs(pos.y - center.y) <= 3 then
				core.chat_send_player(pname, core.colorize("#FF4444", "STRATEGIC OVERRIDE: Building is prohibited within Domination Point " .. id .. "!"))
				core.set_node(pos, oldnode)
				return true
			end
		end
	end
end)
