-- mods/esports_core/sprint.lua
-- Sprint & Stamina System for Luanti Deathmatch Core
-- High-performance, zero-lag architecture:
--   1. Throttled update rate (20 Hz matching server step).
--   2. Event-driven physics override (only sent on state transitions).
--   3. Dirty-checked HUD synchronization (zero network traffic when idle/full).

esports_core.sprint = {}
esports_core.sprint.players = {}

-- Balance & Tuning Constants
local MAX_STAMINA = 100
local SPRINT_SPEED_MULT = 1.4          -- Base 1.2 * 1.4 = 1.68
local EXHAUSTED_SPEED_MULT = 0.75      -- Penalty: 25% slower walk speed while exhausted (0.9 m/s)
local NORMAL_JUMP = 1.1                -- Standard snappy jump height
local EXHAUSTED_JUMP = 0.9             -- Reduced jump height while exhausted
local DRAIN_RATE = 22                 -- Stamina points drained per second (~4.5s sprint)
local JUMP_COST = 8                   -- Stamina drained instantly per jump while sprinting
local REGEN_RATE = 25                 -- Stamina points regenerated per second (0 to 100 in 4s)
local REGEN_DELAY = 1.0               -- Seconds of rest required before regeneration begins
local EXHAUSTED_THRESHOLD = 25        -- Stamina required to recover from exhaustion
local FLAG_CARRIER_DRAIN_MULT = 1.5   -- CTF flag carriers expend more stamina sprinting
local TICK_STEP = 0.05                -- 20 Hz tick interval

function esports_core.sprint.init_player(player)
	if not player or not player:is_player() then return end
	local pname = player:get_player_name()
	local cdef = esports_core.skins and esports_core.skins.get_player_class and esports_core.skins.get_player_class(player)
	local max_stm = cdef and cdef.max_stamina or MAX_STAMINA
	esports_core.sprint.players[pname] = {
		stamina = max_stm,
		max_stamina = max_stm,
		is_sprinting = false,
		exhausted = false,
		rest_timer = 0,
		last_jump = false,
		last_speed = cdef and cdef.base_speed or 1.2,
		last_jump_phys = NORMAL_JUMP,
		last_sneak = true,
		last_ctrl_sneak = false,
		last_hud_pct = -1,
		last_hud_tier = "",
		last_hud_text = "",
	}
end

function esports_core.sprint.reset_player(player)
	if not player or not player:is_player() then return end
	local pname = player:get_player_name()
	local pdata = esports_core.sprint.players[pname]
	if not pdata then
		esports_core.sprint.init_player(player)
		pdata = esports_core.sprint.players[pname]
	end

	local cdef = esports_core.skins and esports_core.skins.get_player_class and esports_core.skins.get_player_class(player)
	local max_stm = cdef and cdef.max_stamina or MAX_STAMINA
	pdata.max_stamina = max_stm
	pdata.stamina = max_stm
	pdata.is_sprinting = false
	pdata.exhausted = false
	pdata.rest_timer = 0
	pdata.last_jump = false

	local base = esports_core.sprint.get_base_speed(player, pname)
	local jump = (base <= 0) and 0 or NORMAL_JUMP
	local sneak = (base > 0)
	pdata.last_speed = base
	pdata.last_jump_phys = jump
	pdata.last_sneak = sneak
	player:set_physics_override({speed = base, sneak = sneak, jump = jump, gravity = 1.0})

	esports_core.sprint.update_hud(player, pdata, true)
end

function esports_core.sprint.get_base_speed(player, pname)
	if not player or not player:is_player() then return 0 end
	pname = pname or player:get_player_name()

	-- Spectators fly freely
	if esports_core.is_spectator(pname) then
		return 2.0
	end

	-- Check lobby or countdown / pause freeze
	if esports_core.is_in_lobby(player) then
		return 0
	end

	if esports_core.match and (esports_core.match.state == "countdown" or esports_core.match.state == "paused") then
		return 0
	end

	local cdef = esports_core.skins and esports_core.skins.get_player_class and esports_core.skins.get_player_class(player)
	local class_base = cdef and cdef.base_speed or 1.2
	local class_flag_speed = cdef and cdef.flag_speed or 0.9

	-- CTF Flag Carrier speed penalty
	local is_flag_carrier = false
	if player:get_meta():get_int("has_flag") == 1 then
		is_flag_carrier = true
	elseif esports_core.ctf and esports_core.ctf.carriers then
		if esports_core.ctf.carriers.red == pname or esports_core.ctf.carriers.blue == pname then
			is_flag_carrier = true
		end
	end

	if is_flag_carrier then
		return class_flag_speed
	end

	return class_base
end

function esports_core.sprint.is_sprinting(pname)
	local pdata = esports_core.sprint.players[pname]
	return pdata and pdata.is_sprinting or false
end

function esports_core.sprint.get_stamina(pname)
	local pdata = esports_core.sprint.players[pname]
	return pdata and pdata.stamina or MAX_STAMINA
end

function esports_core.sprint.update_physics(player, pname)
	if not player or not player:is_player() then return end
	pname = pname or player:get_player_name()
	local pdata = esports_core.sprint.players[pname]
	if not pdata then return end

	local base = esports_core.sprint.get_base_speed(player, pname)
	if base <= 0 then
		pdata.is_sprinting = false
		if (pdata.last_speed or 0) ~= 0 or (pdata.last_jump_phys or 0) ~= 0 then
			player:set_physics_override({speed = 0, jump = 0, sneak = false, gravity = 1.0})
			pdata.last_speed = 0
			pdata.last_jump_phys = 0
			pdata.last_sneak = false
		end
		return
	end

	local cdef = esports_core.skins and esports_core.skins.get_player_class and esports_core.skins.get_player_class(player)
	local sprint_mult = cdef and cdef.sprint_mult or SPRINT_SPEED_MULT

	local target_speed = base
	local target_jump = NORMAL_JUMP
	local allow_sneak = true
	if pdata.is_sprinting then
		target_speed = base * sprint_mult
		target_jump = NORMAL_JUMP
		allow_sneak = true
	elseif pdata.exhausted then
		target_speed = base * EXHAUSTED_SPEED_MULT
		target_jump = EXHAUSTED_JUMP
		allow_sneak = true
	end

	-- Performance Optimization: Only send physics packet on change
	local speed_changed = math.abs((pdata.last_speed or 1.2) - target_speed) > 0.01
	local jump_changed = math.abs((pdata.last_jump_phys or NORMAL_JUMP) - target_jump) > 0.01
	local sneak_changed = (pdata.last_sneak ~= allow_sneak)
	if speed_changed or jump_changed or sneak_changed then
		player:set_physics_override({speed = target_speed, jump = target_jump, sneak = allow_sneak})
		pdata.last_speed = target_speed
		pdata.last_jump_phys = target_jump
		pdata.last_sneak = allow_sneak
	end
end

function esports_core.sprint.update_hud(player, pdata, force)
	if not player or not player:is_player() then return end
	local pname = player:get_player_name()
	pdata = pdata or esports_core.sprint.players[pname]
	if not pdata then return end

	local huds = esports_core.hud.player_huds[pname]
	if not huds or not huds.stamina_fill then return end

	local cdef = esports_core.skins and esports_core.skins.get_player_class and esports_core.skins.get_player_class(player)
	local max_stm = pdata.max_stamina or (cdef and cdef.max_stamina) or MAX_STAMINA

	local pct = math.floor((pdata.stamina / max_stm) * 100 + 0.5)
	local tier = "high"
	if pdata.exhausted then
		tier = "exhausted"
	elseif pct <= 20 then
		tier = "low"
	elseif pct <= 40 then
		tier = "mid"
	end

	local label = string.format("STAMINA %d%%", pct)
	local text_color = 0x00E5FF  -- Vibrant Cyan
	local fill_color = "#00E5FF:255"

	if tier == "exhausted" then
		label = string.format("EXHAUSTED (%d%%)", pct)
		text_color = 0xFF3333
		fill_color = "#FF3333:255"
	elseif tier == "low" then
		label = string.format("STAMINA %d%%", pct)
		text_color = 0xFF4444
		fill_color = "#FF4444:255"
	elseif tier == "mid" then
		label = string.format("STAMINA %d%%", pct)
		text_color = 0xFFB700
		fill_color = "#FFB700:255"
	end

	local fill_ratio = math.max(0.001, math.min(1.0, pdata.stamina / max_stm))
	local pct_changed = (pct ~= pdata.last_hud_pct)
	local tier_changed = (tier ~= pdata.last_hud_tier)
	local label_changed = (label ~= pdata.last_hud_text)

	-- DIRTY CHECK: If nothing changed visually, do NOT send network packets
	if not force and not pct_changed and not tier_changed and not label_changed then
		return
	end

	pdata.last_hud_pct = pct
	pdata.last_hud_tier = tier
	pdata.last_hud_text = label

	-- 1. Scale Fill Bar
	player:hud_change(huds.stamina_fill, "scale", {x = fill_ratio, y = 1})

	-- 2. Colorize Fill Bar when entering different tiers
	if tier_changed or force then
		player:hud_change(huds.stamina_fill, "text", "esports_stamina_fill.png^[colorize:" .. fill_color)
	end

	-- 3. Update Text Label & Color
	if huds.stamina_text then
		if label_changed or force then
			player:hud_change(huds.stamina_text, "text", label)
		end
		if tier_changed or force then
			player:hud_change(huds.stamina_text, "number", text_color)
		end
	end
end

-- Server Update Loop (20 Hz)
local tick_acc = 0
local dust_acc = 0

core.register_globalstep(function(dtime)
	tick_acc = tick_acc + dtime
	if tick_acc < TICK_STEP then return end
	local dt = tick_acc
	tick_acc = 0

	dust_acc = dust_acc + dt
	local spawn_dust = false
	if dust_acc >= 0.25 then
		dust_acc = 0
		spawn_dust = true
	end

	local players = core.get_connected_players()
	for _, player in ipairs(players) do
		local pname = player:get_player_name()
		local pdata = esports_core.sprint.players[pname]
		if not pdata then
			esports_core.sprint.init_player(player)
			pdata = esports_core.sprint.players[pname]
		end

		if esports_core.is_spectator(pname) then
			pdata.is_sprinting = false
		else
			local base_speed = esports_core.sprint.get_base_speed(player, pname)
			if base_speed <= 0 then
				-- Player is frozen (lobby or countdown/paused)
				pdata.is_sprinting = false
				if (pdata.last_speed or 0) ~= 0 or (pdata.last_jump_phys or 0) ~= 0 then
					pdata.last_speed = 0
					pdata.last_jump_phys = 0
					pdata.last_sneak = false
					player:set_physics_override({speed = 0, jump = 0, sneak = false, gravity = 1.0})
				end
			else
				local cdef = esports_core.skins and esports_core.skins.get_player_class and esports_core.skins.get_player_class(player)
				local max_stm = cdef and cdef.max_stamina or MAX_STAMINA
				local jump_cost = cdef and cdef.jump_cost or JUMP_COST
				local drain_rate = cdef and cdef.drain_rate or DRAIN_RATE
				local flag_drain_mult = cdef and cdef.flag_drain_mult or FLAG_CARRIER_DRAIN_MULT
				local regen_rate = cdef and cdef.regen_rate or REGEN_RATE
				local regen_delay = cdef and cdef.regen_delay or REGEN_DELAY

				pdata.max_stamina = max_stm

				local ctrl = player:get_player_control()
				-- Sprint condition: moving in any direction (W, A, S, D) while holding Shift (sneak) or Aux1 (E)
				local is_moving = ctrl.up or ctrl.down or ctrl.left or ctrl.right
				local wants_sprint = (ctrl.sneak or ctrl.aux1) and is_moving

				-- Jumping while sprinting expends a burst of stamina
				if ctrl.jump and not pdata.last_jump and pdata.is_sprinting then
					pdata.stamina = math.max(0, pdata.stamina - jump_cost)
					pdata.rest_timer = 0
					if pdata.stamina == 0 then
						pdata.exhausted = true
					end
				end
				pdata.last_jump = ctrl.jump

				-- Exhaustion recovery check
				local was_exhausted = pdata.exhausted
				if pdata.exhausted and pdata.stamina >= EXHAUSTED_THRESHOLD then
					pdata.exhausted = false
				end

				local can_sprint = wants_sprint and not pdata.exhausted and pdata.stamina > 0
				local state_changed = (pdata.is_sprinting ~= can_sprint)
				pdata.is_sprinting = can_sprint

				if can_sprint then
					local drain = drain_rate * dt
					if player:get_meta():get_int("has_flag") == 1 then
						drain = drain * flag_drain_mult
					end
					pdata.stamina = math.max(0, pdata.stamina - drain)
					pdata.rest_timer = 0

					if pdata.stamina <= 0 then
						pdata.stamina = 0
						pdata.exhausted = true
						pdata.is_sprinting = false
						state_changed = true
					end

					-- Subtle ground dust particle when sprinting
					if spawn_dust and pdata.is_sprinting then
						local vel = player:get_velocity()
						if vel and math.abs(vel.y) < 0.5 and (vel.x * vel.x + vel.z * vel.z) > 1.0 then
							local pos = player:get_pos()
							core.add_particle({
								pos = {x = pos.x, y = pos.y + 0.1, z = pos.z},
								velocity = {x = (math.random() - 0.5) * 0.4, y = 0.4, z = (math.random() - 0.5) * 0.4},
								acceleration = {x = 0, y = -1.5, z = 0},
								expirationtime = 0.25,
								size = math.random(1, 2),
								texture = "esports_hud_bar.png^[colorize:#CCCCCC:100",
							})
						end
					end
				else
					pdata.rest_timer = pdata.rest_timer + dt
					if pdata.rest_timer >= regen_delay and pdata.stamina < max_stm then
						pdata.stamina = math.min(max_stm, pdata.stamina + (regen_rate * dt))
					end
				end

				-- If sprint or exhaustion state changed, or unfreezing from 0 speed, apply physics override immediately
				local exhaustion_changed = (pdata.exhausted ~= was_exhausted)
				if state_changed or exhaustion_changed or pdata.last_speed == 0 then
					esports_core.sprint.update_physics(player, pname)
				end

				-- Update HUD
				esports_core.sprint.update_hud(player, pdata, false)
			end
		end
	end
end)

core.register_on_joinplayer(function(player)
	esports_core.sprint.init_player(player)
end)

core.register_on_leaveplayer(function(player)
	esports_core.sprint.players[player:get_player_name()] = nil
end)
