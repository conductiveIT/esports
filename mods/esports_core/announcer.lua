esports_core.announcer = {}

-- Track multi-kill states in-memory (lightweight)
local player_kills = {}   -- name -> {count = 0, last_time = 0}
local player_streaks = {} -- name -> current_streak (persists until death)

function esports_core.announcer.on_kill(killer_name, victim_name)
	local now = os.time()

	-- 1. Track Streaks (for Shut Downs)
	if victim_name and victim_name ~= "" then
		local streak = player_streaks[victim_name] or 0
		if streak >= 3 then
			-- Play Shut Down announcement to all players
			core.chat_send_all(string.format("📣 SHUT DOWN! %s ended %s's %d-kill streak!", 
				esports_core.get_nick(killer_name), esports_core.get_nick(victim_name), streak))
			
			-- Play Shut Down sound (low negative sound)
			core.sound_play("esports_deny", {gain = 1.0})
		end
		-- Reset victim's streak
		player_streaks[victim_name] = nil
	end

	-- 2. Track Killer Kills and Multi-kills
	if killer_name and killer_name ~= "" and killer_name ~= victim_name then
		-- Update total active streak
		player_streaks[killer_name] = (player_streaks[killer_name] or 0) + 1

		-- Update multi-kill session
		local session = player_kills[killer_name]
		if not session or (now - session.last_time) > 5 then
			session = {count = 1, last_time = now}
		else
			session.count = session.count + 1
			session.last_time = now
		end
		player_kills[killer_name] = session

		-- Announce multi-kills
		if session.count == 2 then
			core.chat_send_all(string.format("📣 DOUBLE KILL! %s scored 2 rapid kills!", esports_core.get_nick(killer_name)))
			core.sound_play("esports_pickup", {gain = 1.2})
		elseif session.count >= 3 then
			core.chat_send_all(string.format("📣 TRIPLE KILL! %s scored %d rapid kills!", esports_core.get_nick(killer_name), session.count))
			core.sound_play("esports_pickup", {gain = 1.5})
			core.sound_play("default_cool_item", {gain = 1.0})
		end
	end
end

-- Track match countdown warnings (lightweight)
local last_warning_time = nil
core.register_globalstep(function(dtime)
	local state = esports_core.match.state
	if state == "active" then
		local time_left = esports_core.match.time_left
		if time_left and time_left <= 10 and time_left > 0 then
			if last_warning_time ~= time_left then
				last_warning_time = time_left
				-- Play warning beep sound to all online players
				core.sound_play("default_cool_item", {gain = 0.6})
			end
		end
	end
end)

-- Clean up offline players
core.register_on_leaveplayer(function(player)
	local name = player:get_player_name()
	player_kills[name] = nil
	player_streaks[name] = nil
end)
