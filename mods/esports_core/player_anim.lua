esports_core.anim = {}
esports_core.anim.players = {}  -- track current animation state: "stand", "walk", "mine"

local ANIM_STAND = {x=0, y=79}
local ANIM_WALK = {x=168, y=187}
local ANIM_MINE = {x=189, y=198}
local ANIM_WALK_MINE = {x=200, y=219}

local anim_timer = 0
core.register_globalstep(function(dtime)
	anim_timer = anim_timer + dtime
	if anim_timer < 0.1 then return end
	anim_timer = 0
	for _, player in ipairs(core.get_connected_players()) do
		local p_name = player:get_player_name()
		local controls = player:get_player_control()
		local vel = player:get_velocity()

		local speed = math.sqrt((vel.x * vel.x) + (vel.z * vel.z))

		local is_walking = speed > 0.5 or controls.up or controls.down or controls.left or controls.right
		local is_mining = controls.LMB  -- left mouse button down

		local new_anim = "stand"
		local anim_frames = ANIM_STAND
		local anim_speed = 30

		if is_walking and is_mining then
			new_anim = "walk_mine"
			anim_frames = ANIM_WALK_MINE
		elseif is_walking then
			new_anim = "walk"
			anim_frames = ANIM_WALK
		elseif is_mining then
			new_anim = "mine"
			anim_frames = ANIM_MINE
		end

		local current_anim = esports_core.anim.players[p_name]

		if current_anim ~= new_anim then
			esports_core.anim.players[p_name] = new_anim
			player:set_animation(anim_frames, anim_speed, 0, true)
		end
	end
end)

core.register_on_leaveplayer(function(player)
	esports_core.anim.players[player:get_player_name()] = nil
end)
