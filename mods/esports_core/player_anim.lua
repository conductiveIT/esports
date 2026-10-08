esports_core.anim = {}
esports_core.anim.players = {}        -- track current animation state: "stand", "walk", "mine"
esports_core.anim.wield_entities = {}  -- p_name -> entity ObjectRef
esports_core.anim.wield_items = {}     -- p_name -> last wielded item name

local ANIM_STAND = {x=0, y=79}
local ANIM_WALK = {x=168, y=187}
local ANIM_MINE = {x=189, y=198}
local ANIM_WALK_MINE = {x=200, y=219}

-- 3D Wield Item Entity (attached to Arm_Right bone)
core.register_entity("esports_core:wield_entity", {
	initial_properties = {
		physical = false,
		collisionbox = {0, 0, 0, 0, 0, 0},
		visual = "wielditem",
		visual_size = {x = 0.25, y = 0.25},
		textures = {""},
		is_visible = true,
		backface_culling = false,
		pointable = false,
		glow = 0,
		static_save = false,  -- Never persist temporary visual attachments to map database
	},
	on_step = function(self, dtime)
		if not self.player_name then
			self.object:remove()
			return
		end
		local player = core.get_player_by_name(self.player_name)
		if not player or not player:is_player() then
			self.object:remove()
			return
		end
	end,
})

local anim_timer = 0
core.register_globalstep(function(dtime)
	anim_timer = anim_timer + dtime
	if anim_timer < 0.2 then return end
	anim_timer = 0
	for _, player in ipairs(core.get_connected_players()) do
		local p_name = player:get_player_name()
		local controls = player:get_player_control()
		local vel = player:get_velocity()

		-- Avoid math.sqrt in high-player loops (0.5 * 0.5 = 0.25)
		local speed_sq = (vel.x * vel.x) + (vel.z * vel.z)

		local is_walking = speed_sq > 0.25 or controls.up or controls.down or controls.left or controls.right
		local is_mining = controls.LMB  -- left mouse button down

		local is_sprinting = esports_core.sprint and esports_core.sprint.is_sprinting(p_name)
		local new_anim = "stand"
		local anim_frames = ANIM_STAND
		local anim_speed = 30

		if is_walking and is_mining then
			new_anim = is_sprinting and "sprint_mine" or "walk_mine"
			anim_frames = ANIM_WALK_MINE
			anim_speed = is_sprinting and 42 or 30
		elseif is_walking then
			new_anim = is_sprinting and "sprint" or "walk"
			anim_frames = ANIM_WALK
			anim_speed = is_sprinting and 42 or 30
		elseif is_mining then
			new_anim = "mine"
			anim_frames = ANIM_MINE
		end

		local current_anim = esports_core.anim.players[p_name]

		if current_anim ~= new_anim then
			esports_core.anim.players[p_name] = new_anim
			player:set_animation(anim_frames, anim_speed, 0, true)
		end

		-- 3D Wielded Weapon Visualization (visible to other players in 3rd person)
		local ent_ref = esports_core.anim.wield_entities[p_name]
		local is_spec = esports_core.is_spectator and esports_core.is_spectator(p_name)
		local in_lobby = esports_core.is_in_lobby and esports_core.is_in_lobby(p_name)
		local is_dead = player:get_hp() <= 0

		local ATTACH_POS = {x = 0.2, y = 2.2, z = 3.2}
		local ATTACH_ROT = {x = 36, y = 90, z = 126}
		local ATTACH_VER = 4

		if is_spec or in_lobby or is_dead then
			if ent_ref and ent_ref:get_luaentity() then
				ent_ref:set_properties({textures = {""}, is_visible = false})
			end
			esports_core.anim.wield_items[p_name] = ""
		else
			local wield_item = player:get_wielded_item():get_name()
			-- Ensure entity exists and is attached to right arm bone
			if not ent_ref or not ent_ref:get_luaentity() then
				local obj = core.add_entity(player:get_pos(), "esports_core:wield_entity")
				if obj then
					obj:get_luaentity().player_name = p_name
					obj:get_luaentity()._attach_ver = ATTACH_VER
					obj:set_attach(player, "Arm_Right", ATTACH_POS, ATTACH_ROT)
					esports_core.anim.wield_entities[p_name] = obj
					ent_ref = obj
					esports_core.anim.wield_items[p_name] = nil
				end
			end

			if ent_ref and ent_ref:get_luaentity() then
				local lent = ent_ref:get_luaentity()
				if lent._attach_ver ~= ATTACH_VER then
					lent._attach_ver = ATTACH_VER
					ent_ref:set_attach(player, "Arm_Right", ATTACH_POS, ATTACH_ROT)
				end
				if esports_core.anim.wield_items[p_name] ~= wield_item then
					esports_core.anim.wield_items[p_name] = wield_item
					if wield_item ~= "" then
						ent_ref:set_attach(player, "Arm_Right", ATTACH_POS, ATTACH_ROT)
						ent_ref:set_properties({textures = {wield_item}, is_visible = true})
					else
						ent_ref:set_properties({textures = {""}, is_visible = false})
					end
				end
			end
		end
	end
end)

core.register_on_leaveplayer(function(player)
	local p_name = player:get_player_name()
	esports_core.anim.players[p_name] = nil
	if esports_core.anim.wield_entities[p_name] then
		if esports_core.anim.wield_entities[p_name]:get_luaentity() then
			esports_core.anim.wield_entities[p_name]:remove()
		end
		esports_core.anim.wield_entities[p_name] = nil
	end
	esports_core.anim.wield_items[p_name] = nil
end)

core.register_on_dieplayer(function(player)
	local p_name = player:get_player_name()
	local ent_ref = esports_core.anim.wield_entities[p_name]
	if ent_ref and ent_ref:get_luaentity() then
		ent_ref:set_properties({textures = {""}, is_visible = false})
	end
	esports_core.anim.wield_items[p_name] = ""
end)
