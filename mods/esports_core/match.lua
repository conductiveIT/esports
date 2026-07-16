esports_core.match = {}
esports_core.match.state = "waiting"  -- waiting, active, over
esports_core.match.timer = 0
esports_core.match.match_duration = 300
esports_core.match.active_teams = {red = nil, blue = nil}
esports_core.match.player_stats = {}  -- [name] = {kills=0, deaths=0}
esports_core.match.last_attacker = {}  -- [victim] = {name=killer, time=os.time()}
esports_core.match.friendly_fire = true
esports_core.match.melee_damage = true
esports_core.match.is_debug = false
esports_core.match.player_sides = {}  -- [name] = "red" or "blue" (Temporary overrides)
esports_core.match.is_ffa = false
esports_core.match.is_payload = false
esports_core.match.is_domination = false
esports_core.match.paused = false
local paused_physics = {}

function esports_core.match.get_ffa_leader()
	local leader_name = "None"
	local max_kills = -1
	for pname, stats in pairs(esports_core.match.player_stats) do
		local kills = stats.kills or 0
		if kills > max_kills then
			max_kills = kills
			leader_name = pname
		end
	end
	return leader_name, (max_kills >= 0 and max_kills or 0)
end



local dtime_accumulator = 0
local proximity_accumulator = 0
local last_nametags = {}

core.register_on_leaveplayer(function(player)
	last_nametags[player:get_player_name()] = nil
end)

core.register_globalstep(function(dtime)
	proximity_accumulator = proximity_accumulator + dtime
	if proximity_accumulator >= 0.1 then
		proximity_accumulator = 0
		local all_players = core.get_connected_players()
		for _, p in ipairs(all_players) do
			local pname = p:get_player_name()

			-- Hidden completely if spectator
			if esports_core.is_spectator(pname) then
				local last = last_nametags[pname]
				if not last or last.a ~= 0 then
					p:set_nametag_attributes({color = {a=0, r=0, g=0, b=0}})
					last_nametags[pname] = {text = "", a = 0, r = 0, g = 0, b = 0}
				end
			else
				local show_name = false
				local match_active = (esports_core.match.state == "active" or esports_core.match.state == "countdown")

				if not match_active then
					-- Lobby mode: Always show names for players
					show_name = true
				else
					-- Active match: Show names only if another combatant is within 15 meters (Tactical Proximity)
					local p_pos = p:get_pos()
					for _, other in ipairs(all_players) do
						local other_name = other:get_player_name()
						if other_name ~= pname and not esports_core.is_spectator(other_name) then
							local o_pos = other:get_pos()
							local dx = p_pos.x - o_pos.x
							local dy = p_pos.y - o_pos.y
							local dz = p_pos.z - o_pos.z
							-- Optimized: inline squared distance check avoids math.sqrt and function call overhead
							if (dx*dx + dy*dy + dz*dz) < 225 then
								show_name = true
								break
							end
						end
					end
				end

				-- Apply team color, alpha, and dynamic health text
				local team = esports_core.teams.get_player_team(pname)
				local hp = p:get_hp()
				local is_alive = hp > 0
				local a = (show_name and is_alive) and 255 or 0
				local r, g, b = 200, 200, 200
				if team == "red" then r, g, b = 255, 50, 50
				elseif team == "blue" then r, g, b = 50, 50, 255
				elseif team == "ffa" then r, g, b = 255, 200, 50 end

				local tag_text = string.format("%s (%d HP)", esports_core.get_nick(pname), hp)

				local last = last_nametags[pname]
				local needs_update = false
				if not last then
					needs_update = true
				elseif last.a ~= a then
					needs_update = true
				elseif a == 255 then
					-- Only send text/color updates if the nametag is actually visible
					if last.text ~= tag_text or last.r ~= r or last.g ~= g or last.b ~= b then
						needs_update = true
					end
				end

				if needs_update then
					p:set_nametag_attributes({
						text = tag_text,
						color = {a = a, r = r, g = g, b = b}
					})
					last_nametags[pname] = {text = tag_text, a = a, r = r, g = g, b = b}
				end
			end
		end
	end

	dtime_accumulator = dtime_accumulator + dtime
	if dtime_accumulator < 1 then return end
	dtime_accumulator = dtime_accumulator - 1

	if esports_core.match.paused then
		esports_core.hud.update_timer("MATCH PAUSED (Admin)", true)
		return
	end

	local players = core.get_connected_players()
	local num_players = #players

	-- Void death check
	for _, p in ipairs(players) do
		local pname = p:get_player_name()
		if p:get_pos().y < -10 and not esports_core.is_spectator(pname) then
			p:set_hp(0)  -- Instant elimination
		end
	end

	if esports_core.match.state == "waiting" then
		esports_core.hud.update_timer("Waiting for Admin...")

	elseif esports_core.match.state == "countdown" then
		esports_core.match.timer = esports_core.match.timer - 1

		local r_name = esports_core.match.active_teams.red
		local b_name = esports_core.match.active_teams.blue

		for _, p in ipairs(players) do
			if not esports_core.is_spectator(p:get_player_name()) then
				p:set_physics_override({speed = 0, jump = 0, gravity = 0})
				esports_core.hud.show_intro(p, esports_core.match.timer, r_name, b_name)
			end
		end

		if esports_core.match.timer <= 0 then
			esports_core.match.state = "active"
			esports_core.match.timer = esports_core.match.match_duration
			for _, p in ipairs(players) do
				local pname = p:get_player_name()
				local is_participant = esports_core.match.get_player_match_side(pname)

				if is_participant or core.check_player_privs(pname, {server = true}) then
					 p:set_physics_override({speed = 1.2, jump = 1.1, gravity = 1.0})
				end
				esports_core.hud.hide_intro(p)
			end
			core.chat_send_all("MATCH STARTED!")
		end

	elseif esports_core.match.state == "active" then
		esports_core.match.timer = esports_core.match.timer - 1

		if esports_core.match.is_koth then
			esports_core.koth.update(1.0)
		elseif esports_core.match.is_payload then
			esports_core.payload.update(1.0)
		elseif esports_core.match.is_domination then
			esports_core.dom.update(1.0)
		elseif esports_core.match.is_spleef then
			-- Void fall check for Spleef & Survival Points
			for _, p in ipairs(core.get_connected_players()) do
				local pname = p:get_player_name()
				if not esports_core.is_spectator(pname) then
					local pos = p:get_pos()
					local is_at_lobby_spawn = (math.abs(pos.x) < 0.1 and math.abs(pos.y - 1.5) < 0.1 and math.abs(pos.z) < 0.1)
					if pos.y <= 2 and pos.y > -100 and not is_at_lobby_spawn then
						if not esports_core.match.temp_spectators then
							esports_core.match.temp_spectators = {}
						end
						esports_core.match.temp_spectators[pname] = true
						p:set_hp(0)  -- Eliminate player
					end

					-- Increment survival time if not eliminated
					if not (esports_core.match.temp_spectators and esports_core.match.temp_spectators[pname]) then
						if not esports_core.match.player_stats[pname] then
							esports_core.match.player_stats[pname] = {kills = 0, deaths = 0, captures = 0, spleef_survival = 0, spleef_blocks = 0}
						end
						if not esports_core.match.player_stats[pname].spleef_survival then
							esports_core.match.player_stats[pname].spleef_survival = 0
						end
						esports_core.match.player_stats[pname].spleef_survival = esports_core.match.player_stats[pname].spleef_survival + 1
					end
				end
			end

			-- Check Spleef win condition
			local red_survivors = {}
			local blue_survivors = {}
			for _, p in ipairs(core.get_connected_players()) do
				local pname = p:get_player_name()
				if not esports_core.is_spectator(pname) and p:get_hp() > 0 and not (esports_core.match.temp_spectators and esports_core.match.temp_spectators[pname]) then
					local side = esports_core.match.get_player_match_side(pname)
					if side == "red" then
						table.insert(red_survivors, pname)
					elseif side == "blue" then
						table.insert(blue_survivors, pname)
					end
				end
			end

			local red_alive = #red_survivors
			local blue_alive = #blue_survivors

			if red_alive == 0 and blue_alive == 0 then
				esports_core.match.timer = 0
			elseif red_alive == 0 then
				esports_core.teams.scores.blue = 1
				esports_core.teams.scores.red = 0
				esports_core.match.timer = 0
				core.chat_send_all(">> SPLEEF: All Red team members eliminated! BLUE TEAM WINS!")
				for _, pname in ipairs(blue_survivors) do
					if not esports_core.match.player_stats[pname] then
						esports_core.match.player_stats[pname] = {kills = 0, deaths = 0, captures = 0, spleef_survival = 0, spleef_blocks = 0}
					end
					esports_core.match.player_stats[pname].spleef_winner = true
				end
			elseif blue_alive == 0 then
				esports_core.teams.scores.red = 1
				esports_core.teams.scores.blue = 0
				esports_core.match.timer = 0
				core.chat_send_all(">> SPLEEF: All Blue team members eliminated! RED TEAM WINS!")
				for _, pname in ipairs(red_survivors) do
					if not esports_core.match.player_stats[pname] then
						esports_core.match.player_stats[pname] = {kills = 0, deaths = 0, captures = 0, spleef_survival = 0, spleef_blocks = 0}
					end
					esports_core.match.player_stats[pname].spleef_winner = true
				end
			end
		end

		local mins = math.floor(esports_core.match.timer / 60)
		local secs = esports_core.match.timer % 60
		local is_critical = esports_core.match.timer < 30
		esports_core.hud.update_timer(string.format("Time Remaining: %02d:%02d", mins, secs), is_critical)

		if esports_core.match.timer <= 0 then
			if esports_core.match.is_payload then
				-- Timer ran out, Defenders (Blue) win!
				esports_core.teams.scores.blue = 100
				esports_core.teams.scores.red = 0
				core.chat_send_all(">> PAYLOAD: Time limit reached! BLUE TEAM WINS!")
			elseif esports_core.match.is_spleef then
				-- Timer ran out, count survivors!
				local red_survivors = {}
				local blue_survivors = {}
				for _, p in ipairs(core.get_connected_players()) do
					local pname = p:get_player_name()
					if not esports_core.is_spectator(pname) and p:get_hp() > 0 and not (esports_core.match.temp_spectators and esports_core.match.temp_spectators[pname]) then
						local side = esports_core.match.get_player_match_side(pname)
						if side == "red" then
							table.insert(red_survivors, pname)
						elseif side == "blue" then
							table.insert(blue_survivors, pname)
						end
					end
				end

				if #red_survivors > #blue_survivors then
					esports_core.teams.scores.red = 1
					esports_core.teams.scores.blue = 0
					core.chat_send_all(">> SPLEEF: Time limit reached! RED TEAM WINS (more survivors)!")
					for _, pname in ipairs(red_survivors) do
						if not esports_core.match.player_stats[pname] then
							esports_core.match.player_stats[pname] = {kills = 0, deaths = 0, captures = 0, spleef_survival = 0, spleef_blocks = 0}
						end
						esports_core.match.player_stats[pname].spleef_winner = true
					end
				elseif #blue_survivors > #red_survivors then
					esports_core.teams.scores.blue = 1
					esports_core.teams.scores.red = 0
					core.chat_send_all(">> SPLEEF: Time limit reached! BLUE TEAM WINS (more survivors)!")
					for _, pname in ipairs(blue_survivors) do
						if not esports_core.match.player_stats[pname] then
							esports_core.match.player_stats[pname] = {kills = 0, deaths = 0, captures = 0, spleef_survival = 0, spleef_blocks = 0}
						end
						esports_core.match.player_stats[pname].spleef_winner = true
					end
				else
					esports_core.teams.scores.red = 0
					esports_core.teams.scores.blue = 0
					core.chat_send_all(">> SPLEEF: Time limit reached! DRAW (equal survivors)!")
				end
			end
			esports_core.match.state = "over"
			esports_core.match.timer = 0  -- Reset for safety watchdog

			if esports_core.match.is_ffa then
				local ffa_leader, ffa_kills = esports_core.match.get_ffa_leader()
				local winner_name = "Match Draw"
				local win_color = "white"

				if ffa_leader ~= "None" then
					winner_name = esports_core.get_nick(ffa_leader) .. " Victory"
					win_color = "gold"
				end

				local mvp = {name = ffa_leader, kills = ffa_kills}

				local players_list = {}
				for _, p in ipairs(core.get_connected_players()) do
					local pname = p:get_player_name()
					local stats = esports_core.match.player_stats[pname] or {kills=0, deaths=0, captures=0}
					if not esports_core.is_spectator(pname) then
						table.insert(players_list, {name=pname, k=stats.kills, d=stats.deaths, c=0})
					end
					p:set_physics_override({speed = 0, jump = 0})
				end

				table.sort(players_list, function(a, b) return a.k > b.k end)

				local red_list = {}
				local blue_list = {}
				for idx, p in ipairs(players_list) do
					if idx % 2 == 1 then
						table.insert(red_list, p)
					else
						table.insert(blue_list, p)
					end
				end

				local outro_data = {
					title = winner_name:upper(),
					color = win_color,
					mvp = mvp.name,
					mvp_kills = mvp.kills,
					is_ctf = false,
					win_team = nil,
					red_team = "LEADERBOARD (A)",
					blue_team = "LEADERBOARD (B)",
					red_roster = red_list,
					blue_roster = blue_list
				}

				for _, player in ipairs(core.get_connected_players()) do
					esports_core.hud.show_outro(player, outro_data)
				end

				core.chat_send_all(">> MATCH OVER! " .. winner_name:upper())
				return
			end

			local r_name = esports_core.match.active_teams.red
			local b_name = esports_core.match.active_teams.blue
			local winner_name = "Match Draw"
			local win_color = "white"
			local win_team_id = nil

			if esports_core.teams.scores.red > esports_core.teams.scores.blue then
				winner_name = (r_name or "Red Team") .. " Victory"
				win_color = "red"
				win_team_id = r_name
				if esports_league and r_name and b_name and not esports_core.match.is_pve then
					esports_league.teams[r_name].wins = (esports_league.teams[r_name].wins or 0) + 1
					esports_league.teams[b_name].losses = (esports_league.teams[b_name].losses or 0) + 1
				end
			elseif esports_core.teams.scores.blue > esports_core.teams.scores.red then
				winner_name = (b_name or "Blue Team") .. " Victory"
				win_color = "blue"
				win_team_id = b_name
				if esports_league and r_name and b_name and not esports_core.match.is_pve then
					esports_league.teams[b_name].wins = (esports_league.teams[b_name].wins or 0) + 1
					esports_league.teams[r_name].losses = (esports_league.teams[r_name].losses or 0) + 1
				end
			end

			-- Update Standings kills/deaths statistics
			if esports_league and r_name and b_name and not esports_core.match.is_pve then
				local red_score = esports_core.teams.scores.red
				local blue_score = esports_core.teams.scores.blue

				esports_league.teams[r_name].kills_scored = (esports_league.teams[r_name].kills_scored or 0) + red_score
				esports_league.teams[r_name].deaths_conceded = (esports_league.teams[r_name].deaths_conceded or 0) + blue_score
				esports_league.teams[b_name].kills_scored = (esports_league.teams[b_name].kills_scored or 0) + blue_score
				esports_league.teams[b_name].deaths_conceded = (esports_league.teams[b_name].deaths_conceded or 0) + red_score

				-- Process Scheduled Match Context
				local ctx = esports_core.match.scheduled_context
				if ctx then
					if ctx.type == "regular_season" then
						local round = ctx.round
						local idx = ctx.index
						local fixture = esports_league.fixtures[round] and esports_league.fixtures[round][idx]
						if fixture then
							fixture.status = "completed"
							fixture.score.home = red_score
							fixture.score.away = blue_score
						end
					elseif ctx.type == "playoff_semifinal" then
						local idx = ctx.index
						local sf = esports_league.playoffs.semifinals[idx]
						if sf then
							sf.status = "completed"
							sf.score1 = red_score
							sf.score2 = blue_score
							if sf.score1 > sf.score2 then
								sf.winner = sf.team1
							elseif sf.score2 > sf.score1 then
								sf.winner = sf.team2
							else
								sf.winner = sf.team1
							end

							-- Advance to final if both semifinals are completed
							local sf1 = esports_league.playoffs.semifinals[1]
							local sf2 = esports_league.playoffs.semifinals[2]
							if sf1.status == "completed" and sf2.status == "completed" then
								esports_league.playoffs.finals.team1 = sf1.winner
								esports_league.playoffs.finals.team2 = sf2.winner
								esports_league.playoffs.finals.status = "pending"
							end
						end
					elseif ctx.type == "playoff_final" then
						local fn = esports_league.playoffs.finals
						if fn then
							fn.status = "completed"
							fn.score1 = red_score
							fn.score2 = blue_score
							if fn.score1 > fn.score2 then
								fn.winner = fn.team1
							elseif fn.score2 > fn.score1 then
								fn.winner = fn.team2
							else
								fn.winner = fn.team1
							end
							core.chat_send_all(">> CHAMPIONS: Team '" .. fn.winner .. "' has won the Grand Finals!")
						end
					end
					esports_core.match.scheduled_context = nil
				end
				esports_league.save()
			end

			-- GATHER SCOREBOARD DATA & MVP
			local red_list = {}
			local blue_list = {}
			local mvp = {name = "No One", kills = 0}

			for _, p in ipairs(core.get_connected_players()) do
				local pname = p:get_player_name()
				local stats = esports_core.match.player_stats[pname] or {kills=0, deaths=0, captures=0, hill_time=0, escort_time=0, dom_points=0, spleef_survival=0, spleef_blocks=0}
				local p_team = esports_core.teams.get_player_team(pname)

				if p_team == "red" then
					table.insert(red_list, {name=pname, k=stats.kills, d=stats.deaths, c=stats.captures, h=(stats.hill_time or 0), e=(stats.escort_time or 0), d_pts=(stats.dom_points or 0), s_surv=(stats.spleef_survival or 0), s_blks=(stats.spleef_blocks or 0)})
				elseif p_team == "blue" then
					table.insert(blue_list, {name=pname, k=stats.kills, d=stats.deaths, c=stats.captures, h=(stats.hill_time or 0), e=(stats.escort_time or 0), d_pts=(stats.dom_points or 0), s_surv=(stats.spleef_survival or 0), s_blks=(stats.spleef_blocks or 0)})
				end

				-- Save stats to persistent database (PVP ONLY!)
				if esports_league and not esports_core.match.is_pve and not esports_core.match.is_ffa then
					if stats.hill_time and stats.hill_time > 0 then
						if not esports_league.player_stats[pname] then
							esports_league.player_stats[pname] = {kills = 0, deaths = 0, captures = 0, hill_time = 0, escort_time = 0, dom_points = 0}
						end
						esports_league.player_stats[pname].hill_time = (esports_league.player_stats[pname].hill_time or 0) + stats.hill_time
					end
					if stats.escort_time and stats.escort_time > 0 then
						if not esports_league.player_stats[pname] then
							esports_league.player_stats[pname] = {kills = 0, deaths = 0, captures = 0, hill_time = 0, escort_time = 0, dom_points = 0}
						end
						esports_league.player_stats[pname].escort_time = (esports_league.player_stats[pname].escort_time or 0) + stats.escort_time
					end
					if stats.dom_points and stats.dom_points > 0 then
						if not esports_league.player_stats[pname] then
							esports_league.player_stats[pname] = {kills = 0, deaths = 0, captures = 0, hill_time = 0, escort_time = 0, dom_points = 0}
						end
						esports_league.player_stats[pname].dom_points = (esports_league.player_stats[pname].dom_points or 0) + stats.dom_points
					end
				end

				-- Determine MVP (Humans only) - prioritized by captures in CTF, hill time in KOTH, escort time in Payload, dom points in Domination
				local score = stats.kills
				if esports_core.match.is_ctf then
					score = (stats.captures * 10) + stats.kills
				elseif esports_core.match.is_koth then
					score = math.floor((stats.hill_time or 0) / 10) + stats.kills
				elseif esports_core.match.is_payload then
					score = math.floor((stats.escort_time or 0) / 10) + stats.kills
				elseif esports_core.match.is_domination then
					score = math.floor((stats.dom_points or 0) / 10) + stats.kills
				elseif esports_core.match.is_spleef then
					-- Points: 1 pt per sec survived + 2 pts per block broken + 50 bonus pts if winner
					local surv_pts = stats.spleef_survival or 0
					local block_pts = (stats.spleef_blocks or 0) * 2
					local win_pts = stats.spleef_winner and 50 or 0
					score = surv_pts + block_pts + win_pts
				end

				if score > mvp.kills and not esports_core.is_spectator(pname) then
					mvp = {name=pname, kills=score}
				end

				-- Freeze players for Outro
				p:set_physics_override({speed = 0, jump = 0})
			end

			-- Spleef MVP Hard Override: Guarantee the last player standing (winner) is MVP
			if esports_core.match.is_spleef then
				for pname, stats in pairs(esports_core.match.player_stats) do
					if stats.spleef_winner and not esports_core.is_spectator(pname) then
						local surv_pts = stats.spleef_survival or 0
						local block_pts = (stats.spleef_blocks or 0) * 2
						local win_pts = 50
						mvp = {name = pname, kills = surv_pts + block_pts + win_pts}
						break
					end
				end
			end

			-- Record completed match to History log
			if esports_league and r_name and b_name and not esports_core.match.is_pve then
				local match_type = "Team Deathmatch"
				if esports_core.match.is_ctf then
					match_type = "Capture The Flag"
				elseif esports_core.match.is_koth then
					match_type = "King of the Hill"
				elseif esports_core.match.is_payload then
					match_type = "Payload"
				elseif esports_core.match.is_domination then
					match_type = "Domination"
				elseif esports_core.match.is_spleef then
					match_type = "Spleef"
				elseif esports_core.match.is_tagctf then
					match_type = "Tag CTF"
				elseif esports_core.match.is_ffa then
					match_type = "Free For All"
				end

				table.insert(esports_league.history, {
					time = os.time(),
					home = r_name,
					away = b_name,
					home_score = esports_core.teams.scores.red,
					away_score = esports_core.teams.scores.blue,
					mvp = mvp.name,
					match_type = match_type
				})
				esports_league.save()
			end

			-- SORT BY PERFORMANCE (Captures if CTF, Hill Time if KOTH, Escort Time if Payload, Dom Points if Domination, otherwise Kills)
			local sort_fn = function(a, b)
				if esports_core.match.is_ctf then
					if a.c ~= b.c then return a.c > b.c end
				elseif esports_core.match.is_koth then
					if a.h ~= b.h then return a.h > b.h end
				elseif esports_core.match.is_payload then
					if a.e ~= b.e then return a.e > b.e end
				elseif esports_core.match.is_domination then
					if a.d_pts ~= b.d_pts then return a.d_pts > b.d_pts end
				elseif esports_core.match.is_spleef then
					local score_a = (a.s_surv or 0) + (a.s_blks or 0) * 2
					local score_b = (b.s_surv or 0) + (b.s_blks or 0) * 2
					if score_a ~= score_b then return score_a > score_b end
				end
				return a.k > b.k
			end
			table.sort(red_list, sort_fn)
			table.sort(blue_list, sort_fn)

			-- PERSIST OUTRO HUD
			local outro_data = {
				title = winner_name:upper(),
				color = win_color,
				mvp = mvp.name,
				mvp_kills = mvp.kills,
				is_ctf = esports_core.match.is_ctf,
				is_koth = esports_core.match.is_koth,
				is_payload = esports_core.match.is_payload,
				is_domination = esports_core.match.is_domination,
				is_spleef = esports_core.match.is_spleef,
				win_team = win_team_id,
				red_team = r_name,
				blue_team = b_name,
				red_roster = red_list,
				blue_roster = blue_list
			}

			-- Restore temporary spectators before showing outro so init_hud does not wipe it
			if esports_core.match.temp_spectators then
				for pname, _ in pairs(esports_core.match.temp_spectators) do
					local p = core.get_player_by_name(pname)
					if p then
						esports_core.set_spectator(p, false)
					end
				end
				esports_core.match.temp_spectators = nil
			end

			for _, player in ipairs(core.get_connected_players()) do
				esports_core.hud.show_outro(player, outro_data)
			end

			core.chat_send_all(">> MATCH OVER! " .. winner_name:upper())

			-- Clear all PVE bots when match ends
			if esports_core.match.is_pve then
				esports_core.bots.clear_all()
			end

			-- Reset Arena to default lobby layout at the end of the match
			if esports_mapgen and esports_mapgen.reset_island then
				esports_mapgen.reset_island("lobby")
			end

			-- Teleport all players back to the lobby center spawn and lock them
			for _, p in ipairs(core.get_connected_players()) do
				p:set_pos({x=0, y=1.5, z=0})
				esports_core.reset_to_lobby(p)
			end

			-- Immediately clear participants to lock back to lobby
			esports_core.match.active_teams = {red = nil, blue = nil}
			esports_core.match.player_sides = {}
		end

	elseif esports_core.match.state == "over" then
		esports_core.match.timer = esports_core.match.timer - 1
		-- Safety Reset: Automatically return to lobby after 2 minutes of idle viewing
		if esports_core.match.timer <= -120 then
			esports_core.match.state = "waiting"
			esports_core.match.active_teams = {red = nil, blue = nil}

			for _, player in ipairs(core.get_connected_players()) do
				esports_core.hud.hide_outro(player)
				esports_core.lobby.show(player)
				esports_core.reset_to_lobby(player)
			end

			core.chat_send_all("Idle timeout: Returning to lobby.")
		end
	end
end)

core.register_on_punchplayer(function(player, hitter, time_from_last_punch, tool_capabilities, dir, damage)
	if not player or not hitter then return end
	local pname = player:get_player_name()
	if esports_core.is_spectator(pname) or (esports_core.is_in_lobby and esports_core.is_in_lobby(pname)) then return true end
	if hitter and hitter:is_player() then
		local hname = hitter:get_player_name()
		if esports_core.is_spectator(hname) or (esports_core.is_in_lobby and esports_core.is_in_lobby(hname)) then
			return true  -- Block damage/punch
		end
	end
	if esports_core.match.paused then
		return true -- Block damage when paused
	end

	if esports_core.match.state == "active" then
		-- Melee Damage Toggle Check
		if not esports_core.match.melee_damage and hitter:is_player() then
			local is_gun = (tool_capabilities and tool_capabilities.damage_groups and tool_capabilities.damage_groups.is_gun == 1)
			if not is_gun then
				return true -- Block player melee damage
			end
		end

		if esports_core.match.is_tagctf then
			if hitter:is_player() then
				local victim = player:get_player_name()
				local attacker = hitter:get_player_name()
				local v_side = esports_core.match.get_player_match_side(victim)
				local a_side = esports_core.match.get_player_match_side(attacker)
				if v_side and a_side and v_side ~= a_side then
					-- Tagged!
					local tag_pos = player:get_pos()
					esports_core.ctf.drop(player)
					player:set_pos(esports_core.get_safe_spawn_pos(v_side))
					esports_core.match.add_kill(attacker)
					esports_core.match.add_death(victim)
					core.chat_send_all(">> " .. esports_core.get_nick(victim) .. " was tagged by " .. esports_core.get_nick(attacker) .. "!")
					core.sound_play("esports_pickup", {pos = tag_pos, gain = 1.0})
				end
			end
			return true  -- Block physical damage
		elseif esports_core.match.is_spleef then
			return true  -- Block physical damage in Spleef
		end

		-- Friendly Fire Check for Melee/Punches
		if not esports_core.match.friendly_fire and hitter:is_player() then
			local victim = player:get_player_name()
			local attacker = hitter:get_player_name()
			local v_team = esports_core.teams.get_player_team(victim)
			local a_team = esports_core.teams.get_player_team(attacker)
			if v_team and a_team and v_team == a_team then
				return true  -- Block physical damage/punches between teammates
			end
		end
	end

	local victim = player:get_player_name()
	local attacker = nil
	local is_bot = false

	if hitter:is_player() then
		attacker = hitter:get_player_name()
	end

	if not attacker or attacker == "" then
		local ent = hitter:get_luaentity()
		if ent and ent.name == "esports_core:bot" then
			attacker = "Sentry"
			is_bot = true
		end
	end

	if not victim or not attacker or attacker == "" or victim == attacker then return end

	local weapon = "pickaxe"
	if hitter:is_player() then
		local item = hitter:get_wielded_item():get_name()
		if item:find("rifle") then weapon = "rifle"
		elseif item:find("shotgun") then weapon = "shotgun" end
	else
		weapon = "rifle"
	end

	esports_core.match.last_attacker[victim] = {
		name = attacker,
		time = os.time(),
		weapon = weapon
	}
end)

core.register_on_dieplayer(function(player, reason)
	-- This handles scoring
	if esports_core.match.state == "active" and not esports_core.match.is_ctf and not esports_core.match.is_payload and not esports_core.match.is_domination then
		local p_team = esports_core.teams.get_player_team(player:get_player_name())
		-- Simple scoring: if you die, the other team gets a point (TDM ONLY)
		if p_team == "red" then
			esports_core.teams.scores.blue = esports_core.teams.scores.blue + 1
		elseif p_team == "blue" then
			esports_core.teams.scores.red = esports_core.teams.scores.red + 1
		end
		esports_core.hud.update_scores()
	end

	-- Broadcast kill message
	local victim = player:get_player_name()
	esports_core.match.add_death(victim)

	if esports_core.match.is_spleef then
		if not esports_core.match.temp_spectators then
			esports_core.match.temp_spectators = {}
		end
		esports_core.match.temp_spectators[victim] = true
	end

	local killer_name = nil
	local k_team = nil
	local weapon = "skull"

	if reason.puncher then
		if reason.puncher:is_player() then
			killer_name = reason.puncher:get_player_name()
			local item = reason.puncher:get_wielded_item():get_name()
			if item:find("rifle") then weapon = "rifle"
			elseif item:find("shotgun") then weapon = "shotgun"
			elseif item:find("pickaxe") then weapon = "pickaxe" end
		else
			local ent = reason.puncher:get_luaentity()
			if ent and ent.name == "esports_core:bot" then
				killer_name = "Sentry"
				weapon = "rifle"
			end
		end
	elseif esports_core.match.last_attacker[victim] then
		local last = esports_core.match.last_attacker[victim]
		local now = os.time()
		if now - last.time <= 10 then
			killer_name = last.name
			weapon = last.weapon or "skull"
		end
	end

	if killer_name and killer_name ~= "" then
		k_team = esports_core.match.get_player_match_side(killer_name)
	end

	local v_team = esports_core.match.get_player_match_side(victim)
	esports_core.hud.add_kill_event((killer_name and killer_name ~= "") and killer_name or "Environment", k_team, victim, v_team, weapon)
	if esports_core.announcer then
		esports_core.announcer.on_kill(killer_name, victim)
	end

	if killer_name and killer_name ~= "" then
		esports_core.match.add_kill(killer_name)
		core.chat_send_all(">> " .. esports_core.get_nick(victim) .. " was eliminated by " .. esports_core.get_nick(killer_name) .. "!")
	else
		core.chat_send_all(">> " .. esports_core.get_nick(victim) .. " was eliminated!")
	end

	-- Clear attacker state
	esports_core.match.last_attacker[victim] = nil

	-- Hide player model immediately on death and revert skin
	player:set_properties({visual_size = {x=0, y=0, z=0}})
	esports_core.skins.apply(player, nil)
end)

-- Helper stats functions
-- Helper stats functions
function esports_core.match.add_kill(name)
	if not esports_core.match.player_stats[name] then
		esports_core.match.player_stats[name] = {kills = 0, deaths = 0, captures = 0}
	end
	esports_core.match.player_stats[name].kills = esports_core.match.player_stats[name].kills + 1

	-- Force HUD update for active viewers
	if esports_core.hud.update_scoreboard then
		esports_core.hud.update_scoreboard()
	end

	-- Persist to league (PVP ONLY, NO FFA!)
	if not esports_core.match.is_pve and not esports_core.match.is_ffa then
		if esports_league and esports_league.player_stats then
			if not esports_league.player_stats[name] then
				esports_league.player_stats[name] = {kills = 0, deaths = 0, captures = 0}
			end
			esports_league.player_stats[name].kills = (esports_league.player_stats[name].kills or 0) + 1
			esports_league.save()
		end
	end
end

function esports_core.match.add_death(name)
	if not esports_core.match.player_stats[name] then
		esports_core.match.player_stats[name] = {kills = 0, deaths = 0, captures = 0}
	end
	esports_core.match.player_stats[name].deaths = esports_core.match.player_stats[name].deaths + 1

	-- Force HUD update for active viewers
	if esports_core.hud.update_scoreboard then
		esports_core.hud.update_scoreboard()
	end

	-- Persist to league (PVP ONLY, NO FFA!)
	if not esports_core.match.is_pve and not esports_core.match.is_ffa then
		if esports_league and esports_league.player_stats then
			if not esports_league.player_stats[name] then
				esports_league.player_stats[name] = {kills = 0, deaths = 0, captures = 0}
			end
			esports_league.player_stats[name].deaths = (esports_league.player_stats[name].deaths or 0) + 1
			esports_league.save()
		end
	end
end

function esports_core.match.add_capture(name)
	if not esports_core.match.player_stats[name] then
		esports_core.match.player_stats[name] = {kills = 0, deaths = 0, captures = 0}
	end
	esports_core.match.player_stats[name].captures = esports_core.match.player_stats[name].captures + 1

	if esports_core.hud.update_scoreboard then
		esports_core.hud.update_scoreboard()
	end

	-- Persist to league (PVP ONLY!)
	if not esports_core.match.is_pve then
		if esports_league and esports_league.player_stats then
			if not esports_league.player_stats[name] then
				esports_league.player_stats[name] = {kills = 0, deaths = 0, captures = 0}
			end
			esports_league.player_stats[name].captures = (esports_league.player_stats[name].captures or 0) + 1
			esports_league.save()
		end
	end
end


function esports_core.match.add_spleef_block(name)
	if not esports_core.match.player_stats[name] then
		esports_core.match.player_stats[name] = {kills = 0, deaths = 0, captures = 0, spleef_survival = 0, spleef_blocks = 0}
	end
	if not esports_core.match.player_stats[name].spleef_blocks then
		esports_core.match.player_stats[name].spleef_blocks = 0
	end
	esports_core.match.player_stats[name].spleef_blocks = esports_core.match.player_stats[name].spleef_blocks + 1

	if esports_core.hud.update_scoreboard then
		esports_core.hud.update_scoreboard()
	end
end



-- Helper to check if a coordinate mathematically lands on the selected island layout
function esports_core.is_coordinate_on_island(x, z)
	local layout = esports_core.match.current_map_layout or "circular"
	local scale = esports_core.match.current_map_scale or 1.0
	local z2 = z * z

	if layout == "circular" then
		local max_r = 100 * scale
		return (x*x + z2 <= max_r * max_r)
	elseif layout == "choke_point" then
		local base_r = 30 * scale
		local base_r2 = base_r * base_r
		local dist_red2 = (x - 80*scale)*(x - 80*scale) + z2
		local dist_blue2 = (x + 80*scale)*(x + 80*scale) + z2
		local is_bridge = (x >= -60*scale and x <= 60*scale) and (z >= -8*scale and z <= 8*scale)
		return (dist_red2 <= base_r2) or (dist_blue2 <= base_r2) or is_bridge
	elseif layout == "three_lanes" then
		local base_r = 30 * scale
		local base_r2 = base_r * base_r
		local dist_red2 = (x - 80*scale)*(x - 80*scale) + z2
		local dist_blue2 = (x + 80*scale)*(x + 80*scale) + z2

		local mid_bridge = (x >= -60*scale and x <= 60*scale) and (z >= -5*scale and z <= 5*scale)
		local top_bridge = (x >= -60*scale and x <= 60*scale) and (z >= 25*scale - 4*scale and z <= 25*scale + 4*scale)
		local btm_bridge = (x >= -60*scale and x <= 60*scale) and (z >= -25*scale - 4*scale and z <= -25*scale + 4*scale)
		return (dist_red2 <= base_r2) or (dist_blue2 <= base_r2) or mid_bridge or top_bridge or btm_bridge
	elseif layout == "split_center" then
		local base_r = 25 * scale
		local base_r2 = base_r * base_r
		local dist_red2 = (x - 80*scale)*(x - 80*scale) + z2
		local dist_blue2 = (x + 80*scale)*(x + 80*scale) + z2

		local center_r = 25 * scale
		local center_r2 = center_r * center_r
		local dist_center2 = x*x + z2

		local left_bridge = (x >= -60*scale and x <= -20*scale) and (z >= -4*scale and z <= 4*scale)
		local right_bridge = (x >= 20*scale and x <= 60*scale) and (z >= -4*scale and z <= 4*scale)
		return (dist_red2 <= base_r2) or (dist_blue2 <= base_r2) or (dist_center2 <= center_r2) or left_bridge or right_bridge
	end
	return false
end

-- Helper to find a safe ground position within the storm and on the island
function esports_core.get_safe_spawn_pos(pname_or_side, ignore_proximity)
	local side = pname_or_side
	local my_name = nil
	if side and side ~= "red" and side ~= "blue" then
		my_name = pname_or_side
		side = esports_core.match.get_player_match_side(my_name)
	end

	-- Prune stale recent spawns (older than 3.0 seconds)
	local now = os.clock()
	if not esports_core.recent_spawns then
		esports_core.recent_spawns = {}
	end
	for i = #esports_core.recent_spawns, 1, -1 do
		if now - esports_core.recent_spawns[i].time > 3.0 then
			table.remove(esports_core.recent_spawns, i)
		end
	end

	if esports_core.match.is_spleef then
		local lvls = esports_core.match.spleef_levels or 1
		local spawn_y = 5.5 + (lvls - 1) * 4

		local attempts = 0
		local final_pos
		while attempts < 50 do
			local candidate
			if side == "red" then
				candidate = {x = -20 + math.random(5), y = spawn_y, z = -20 + math.random(40)}
			elseif side == "blue" then
				candidate = {x = 20 - math.random(5), y = spawn_y, z = -20 + math.random(40)}
			else
				candidate = {x = math.random(-20, 20), y = spawn_y, z = math.random(-20, 20)}
			end

			-- Collision check: Ensure we do not spawn inside another player or bot
			-- Relax collision distance if struggling
			local col_dist = (attempts > 40) and 1.0 or 2.0
			local too_close = false
			local nearby = core.get_objects_inside_radius(candidate, col_dist)
			for _, obj in ipairs(nearby) do
				if obj:is_player() then
					local other_name = obj:get_player_name()
					if other_name ~= my_name and not esports_core.is_spectator(other_name) then
						too_close = true
						break
					end
				else
					local ent = obj:get_luaentity()
					if ent and ent.name == "esports_core:bot" then
						too_close = true
						break
					end
				end
			end

			-- Check recently chosen spawn positions
			if not too_close then
				for _, rs in ipairs(esports_core.recent_spawns) do
					if vector.distance(candidate, rs.pos) < col_dist then
						too_close = true
						break
					end
				end
			end

			if not too_close then
				final_pos = candidate
				break
			end
			attempts = attempts + 1
		end

		if not final_pos then
			-- Fallback
			if side == "red" then
				final_pos = {x = -20 + math.random(5), y = spawn_y, z = -20 + math.random(40)}
			elseif side == "blue" then
				final_pos = {x = 20 - math.random(5), y = spawn_y, z = -20 + math.random(40)}
			else
				final_pos = {x = math.random(-20, 20), y = spawn_y, z = math.random(-20, 20)}
			end
		end

		table.insert(esports_core.recent_spawns, {pos = final_pos, time = now})
		return final_pos
	end

	local storm_center = esports_storm.center
	local storm_radius = esports_storm.current_radius
	local scale = esports_core.match.current_map_scale or 1.0

	local is_base_spawn = ((esports_core.match.is_ctf or esports_core.match.is_payload or esports_core.match.is_domination) and side and esports_core.ctf.bases[side])

	local attempts = 0
	while attempts < 50 do
		local target_x, target_z

		if is_base_spawn then
			-- CTF: Spawn TIGHTLY near own flag stand, scaled to map size
			local base = esports_core.ctf.bases[side]
			local offset_range = 20 * scale
			target_x = base.x + (math.random() * offset_range - offset_range / 2)
			target_z = base.z + (math.random() * offset_range - offset_range / 2)
		else
			-- TDM / Standard: Randomly on island
			local max_r = 95 * scale
			local angle = math.random() * math.pi * 2
			local dist = math.random() * math.min(storm_radius * 0.8, max_r)
			target_x = storm_center.x + math.cos(angle) * dist
			target_z = storm_center.z + math.sin(angle) * dist
		end

		-- Always verify that coordinates are on the island
		if esports_core.is_coordinate_on_island(target_x, target_z) then
			-- Anti-Camp: Check for nearby hostiles (Players and Bots)
			local enemy_nearby = false
			if not ignore_proximity then
				-- Dynamically reduce safety margins if we are struggling to find a spot (small storm/map)
				local relaxation = 1.0
				if attempts > 30 then
					relaxation = 0.0 -- Ignore hostile proximity checks entirely, only enforce collision checks
				elseif attempts > 15 then
					relaxation = 0.5 -- Halve safety distances
				end

				if relaxation > 0 then
					local safety_dist_enemy = (is_base_spawn and 12 or 30) * relaxation
					local safety_dist_team = (is_base_spawn and 4 or 20) * relaxation

					-- Check Player positions
					for _, alt_p in ipairs(core.get_connected_players()) do
						local other_name = alt_p:get_player_name()
						if other_name ~= my_name and not esports_core.is_spectator(other_name) then
							local other_pos = alt_p:get_pos()
							local d = vector.distance({x=target_x, y=0, z=target_z}, {x=other_pos.x, y=0, z=other_pos.z})

							local other_side = esports_core.match.get_player_match_side(other_name)
							local is_enemy = (side and other_side and side ~= other_side)
							local thresh = is_enemy and safety_dist_enemy or safety_dist_team

							if d < thresh then
								enemy_nearby = true
								break
							end
						end
					end

					-- Check Bot positions (using object scan)
					if not enemy_nearby then
						local nearby_objects = core.get_objects_inside_radius({x=target_x, y=0, z=target_z}, safety_dist_enemy)
						for _, obj in ipairs(nearby_objects) do
							local ent = obj:get_luaentity()
							if ent and ent.name == "esports_core:bot" then
								local other_pos = obj:get_pos()
								local d_bot = vector.distance({x=target_x, y=0, z=target_z}, {x=other_pos.x, y=0, z=other_pos.z})

								-- If we are a player on blue, bots (red) are enemies
								if side == "blue" and d_bot < safety_dist_enemy then
									 enemy_nearby = true
									 break
								end
								-- If we are a bot or a player on red, bots are teammates - check small radius
								if (not side or side == "red") and d_bot < safety_dist_team then
									enemy_nearby = true
									break
								end
							end
						end
					end
				end
			end

			-- ALWAYS avoid spawning directly inside any other player/bot/recent spawn (min 2.0 meters)
			-- But relax to 1.0 meters if we are really struggling (attempts > 40)
			local col_dist = (attempts > 40) and 1.0 or 2.0
			local too_close = false
			local candidate_pos = {x = target_x, y = 1.5, z = target_z}
			local nearby = core.get_objects_inside_radius(candidate_pos, col_dist)
			for _, obj in ipairs(nearby) do
				if obj:is_player() then
					local other_name = obj:get_player_name()
					if other_name ~= my_name and not esports_core.is_spectator(other_name) then
						too_close = true
						break
					end
				else
					local ent = obj:get_luaentity()
					if ent and ent.name == "esports_core:bot" then
						too_close = true
						break
					end
				end
			end

			-- Check recently chosen spawn positions
			if not too_close then
				for _, rs in ipairs(esports_core.recent_spawns) do
					if vector.distance(candidate_pos, rs.pos) < col_dist then
						too_close = true
						break
					end
				end
			end

			if not enemy_nearby and not too_close then
				-- Emerge the area around target spawn to load terrain chunks
				core.emerge_area(
					{x = math.floor(target_x - 10), y = -15, z = math.floor(target_z - 10)},
					{x = math.floor(target_x + 10), y = 5, z = math.floor(target_z + 10)}
				)
				table.insert(esports_core.recent_spawns, {pos = candidate_pos, time = now})
				return candidate_pos
			end
		end
		attempts = attempts + 1
	end

	-- LAST RESORT: Forced Deployment at Base (if CTF)
	if is_base_spawn then
		local base = esports_core.ctf.bases[side]
		local offset_range = 6 * scale
		local final_pos = {x=base.x + (math.random() * offset_range - offset_range / 2), y=base.y + 1.5, z=base.z + (math.random() * offset_range - offset_range / 2)}
		table.insert(esports_core.recent_spawns, {pos = final_pos, time = now})
		return final_pos
	end

	-- Emerge fallback region near storm center
	core.emerge_area(
		{x = math.floor(storm_center.x - 10), y = -15, z = math.floor(storm_center.z - 10)},
		{x = math.floor(storm_center.x + 10), y = 5, z = math.floor(storm_center.z + 10)}
	)
	local final_pos = {x = storm_center.x + (math.random() * 4 - 2), y = 1.5, z = storm_center.z + (math.random() * 4 - 2)}
	table.insert(esports_core.recent_spawns, {pos = final_pos, time = now})
	return final_pos
end

-- Resets a player to a clean match state
function esports_core.reset_player(player, provide_weapons)
	local pname = player:get_player_name()
	local inv = player:get_inventory()

	-- Clear CTF state
	player:get_meta():set_int("has_flag", 0)
	if provide_weapons then
		player:get_meta():set_int("needs_weapon_from_crate", 0)
	else
		player:get_meta():set_int("needs_weapon_from_crate", 1)
	end

	-- Wipe Inventories
	inv:set_list("main", {})
	inv:set_list("ammo", {})

	-- Clear Combat State
	if esports_weapons then
		esports_weapons.cooldowns[pname] = 0
	end

	-- Reset HP and Physics (Combat Mode)
	player:set_properties({
		hp_max = 100,
		visual_size = {x=1, y=1, z=1},  -- Restore model size
		eye_height = 1.625,
		interact_distance = 10,  -- Combat reach
	})
	player:set_hp(100)
	player:set_physics_override({
		speed = 1.2,  -- Combat Speed
		jump = 1.1,
		gravity = 1.0
	})
	player:set_armor_groups({fleshy = 100})

	-- Revoke survival-breaking privileges (flight etc)
	local privs = core.get_player_privs(pname)
	if privs.fly or privs.noclip or privs.fast then
		privs.fly = nil
		privs.noclip = nil
		privs.fast = nil
		core.set_player_privs(pname, privs)
	end

	-- Give Utility Kit
	if not esports_core.match.is_spleef then
		inv:set_stack("main", 2, ItemStack("esports_building:blueprint_wall"))
		inv:set_stack("main", 3, ItemStack("esports_building:blueprint_ramp"))
	end

	-- Give Weapons (Debug or Staging)
	if provide_weapons then
		inv:add_item("main", "esports_weapons:assault_rifle")
		inv:add_item("main", "esports_weapons:shotgun")
		inv:add_item("ammo", "esports_weapons:rifle_ammo 100")
		inv:add_item("ammo", "esports_weapons:shotgun_ammo 50")
	end

	-- Update HUD
	esports_core.hud.update_ammo(player)
	esports_core.teams.update_nametag(player)

	-- Apply team skin automatically
	local side = esports_core.match.get_player_match_side(pname)
	if side == "red" then
		esports_core.skins.apply(player, "#ff0000")
	elseif side == "blue" then
		esports_core.skins.apply(player, "#0000ff")
	else
		esports_core.skins.apply(player, nil)  -- Reset to default
	end
end

-- Returns "red", "blue", or nil based on whether the player is in an active match team
function esports_core.match.get_player_match_side(name)
	if esports_core.is_spectator(name) then
		return nil
	end

	-- Check for temporary PVE/Join overrides first
	if esports_core.match.player_sides and esports_core.match.player_sides[name] then
		return esports_core.match.player_sides[name]
	end

	-- Strictly gate side detection to running matches
	if esports_core.match.state ~= "active" and esports_core.match.state ~= "countdown" then
		return nil
	end

	if not esports_core.match.active_teams then
		return nil
	end

	local p_team = esports_league.player_to_team[name]
	if not p_team then return nil end

	if p_team == esports_core.match.active_teams.red then
		return "red"
	elseif p_team == esports_core.match.active_teams.blue then
		return "blue"
	end

	return nil
end

-- Dynamically adds a player to the ongoing match if they are now on one of the competing teams
function esports_core.match.join_player_to_ongoing(player)
	local pname = player:get_player_name()
	local side = esports_core.match.get_player_match_side(pname)
	local match_active = (esports_core.match.state == "active" or esports_core.match.state == "countdown")

	if not match_active or not side or esports_core.is_spectator(pname) then
		return
	end

	-- Add to teams players list and match sides tracker
	esports_core.match.player_sides[pname] = side
	esports_core.teams.players[pname] = side
	esports_core.teams.update_nametag(player)

	-- Initialize player stats if not present
	if not esports_core.match.player_stats[pname] then
		esports_core.match.player_stats[pname] = {kills = 0, deaths = 0, captures = 0}
	end

	-- Full Match Setup (Inventory, Physics, HUD)
	esports_core.reset_player(player, esports_core.match.is_debug)

	-- Teleport to a safe spawn position for their team
	local target_pos = esports_core.get_safe_spawn_pos(side, true)
	player:set_pos(target_pos)

	-- If the match is still in countdown or paused, freeze their physics
	if esports_core.match.state == "countdown" or esports_core.match.paused then
		player:set_physics_override({speed = 0, jump = 0, gravity = 0})
	end

	esports_core.hud.init_hud(player)

	-- Close lobby and hide blackout
	if esports_core.lobby and esports_core.lobby.blackout_hide then
		esports_core.lobby.blackout_hide(player)
	end
	core.close_formspec(pname, "esports_core:lobby")

	core.chat_send_player(pname, "LUANTI ESPORTS: Welcome to the match! Team " .. side:upper() .. " is in combat!")
	core.chat_send_all("LUANTI ESPORTS: " .. pname .. " has joined team " .. side:upper() .. " mid-match!")
end

core.register_on_joinplayer(function(player)
	local pname = player:get_player_name()

	-- Initial HUD Setup
	esports_core.hud.init_hud(player)

	-- Side Detection (Moved to top level scope)
	local side = esports_core.match.get_player_match_side(pname)
	local match_active = (esports_core.match.state == "active" or esports_core.match.state == "countdown")

	-- Detect mid-game join for participants
	if match_active then
		if esports_core.match.is_spleef and esports_core.match.temp_spectators and esports_core.match.temp_spectators[pname] then
			esports_core.set_spectator(player, true)
			local lvls = esports_core.match.spleef_levels or 1
			local spec_y = 5 + lvls * 4
			player:set_pos({x=0, y=spec_y, z=0})
			core.chat_send_player(pname, "LUANTI ESPORTS: You have already been eliminated in this Spleef match.")
			return
		end

		if side and not esports_core.is_spectator(pname) then
			-- Rejoin fight immediately
			esports_core.teams.players[pname] = side
			esports_core.teams.update_nametag(player)
			esports_core.reset_player(player, false)
			player:set_pos(esports_core.get_safe_spawn_pos(pname))
			if esports_core.match.paused then
				player:set_physics_override({speed = 0, jump = 0, gravity = 0})
			end
			core.chat_send_player(pname, "LUANTI ESPORTS: Welcome back. Team " .. side:upper() .. " is in combat!")
			return  -- Skip Lobby
		end
	end

	-- Regular join (Lobby flow)
	if esports_core.is_spectator(pname) then
		local inv = player:get_inventory()
		inv:set_list("main", {})
		inv:set_list("ammo", {})
	else
		esports_core.reset_player(player, false)
	end

	player:set_pos(esports_core.get_safe_spawn_pos(pname))

	-- Lobby Ghost Mode: Invisible, Invulnerable, and Frozen
	if not side or not match_active then
		player:set_properties({
			hp_max = 100,
			visual_size = {x=1, y=1, z=1},  -- Full size for light calculation
			textures = {"character.png^[alpha:0"},  -- 100% transparent
			eye_height = 1.625,
			interact_distance = 0,  -- Cannot hit anything in lobby
		})
		player:set_hp(100)
		player:set_armor_groups({immortal = 1})

		-- Admins can still move, but are hidden/protected
		if not core.check_player_privs(pname, {server=true}) then
			player:set_physics_override({speed = 0, jump = 0, gravity = 1})
		else
			-- Admin Movement Baseline
			player:set_physics_override({speed = 1.2, jump = 1.1, gravity = 1})
		end
	end

	-- Show Lobby (Immediate)
	core.after(0, function()
		if core.get_player_by_name(pname) then
			esports_core.lobby.show(player)
		end
	end)
end)

core.register_on_respawnplayer(function(player)
	if esports_core.match.state == "active" then
		local pname = player:get_player_name()

		if esports_core.match.is_spleef then
			if not esports_core.match.temp_spectators then
				esports_core.match.temp_spectators = {}
			end
			esports_core.match.temp_spectators[pname] = true
			esports_core.set_spectator(player, true)
			local lvls = esports_core.match.spleef_levels or 1
			local spec_y = 5 + lvls * 4
			player:set_pos({x=0, y=spec_y, z=0})
			return true
		end

		-- Ensure invisible during repositioning
		player:set_properties({visual_size = {x=0, y=0, z=0}})
		player:set_pos(esports_core.get_safe_spawn_pos(pname))

		-- Respawn Invulnerability (3 seconds)
		player:set_armor_groups({immortal = 1})
		core.after(3, function()
			if player:is_player() then
				player:set_armor_groups({fleshy = 100})
				core.chat_send_player(pname, "Shield deactivated! You are now vulnerable.")
			end
		end)

		-- Clean Slate Reset
		esports_core.reset_player(player, esports_core.match.is_debug)

		-- Temporary physics freeze to prevent falling through unloaded chunks
		player:set_physics_override({speed = 0, jump = 0, gravity = 0})
		core.after(0.8, function()
			if player:is_player() then
				player:set_physics_override({speed = 1.2, jump = 1.1, gravity = 1.0})
			end
		end)

		-- Reveal player after brief delay to prevent "teleport glitching"
		core.after(0.2, function()
			if player:is_player() then
				local side = esports_core.match.get_player_match_side(pname)
				esports_core.skins.apply(player, side)
			end
		end)
	else
		-- Respawn player in lobby center to prevent void death loop
		player:set_pos({x=0, y=1.5, z=0})
		esports_core.reset_player(player, false)
		player:set_physics_override({speed = 0, jump = 0, gravity = 1})
	end
	return true
end)

esports_core.match.current_map_scale = 1.0

function esports_core.match.start(t1, t2, dur_secs, pve_mode, time_mode, bot_count, bot_diff, game_mode, map_size, friendly_fire, melee_damage, map_layout, spleef_levels)
	esports_core.match.spleef_levels = tonumber(spleef_levels) or 1
	-- Freeze all players first to prevent them from falling into the void while the map is generating/resetting
	for _, p in ipairs(core.get_connected_players()) do
		if not esports_core.is_spectator(p:get_player_name()) then
			p:set_physics_override({speed = 0, jump = 0, gravity = 0})
		end
	end

	-- 1. DEEP STATE RESET: Purge all stale data and physical nodes
	esports_core.ctf.reset()
	if esports_core.payload then
		esports_core.payload.reset()
	end
	if esports_core.dom then
		esports_core.dom.reset()
	end
	esports_core.match.player_sides = {}
	esports_core.match.last_attacker = {}
	esports_core.match.player_stats = {}

	-- 2. Map Layout Selection
	local layout = map_layout or "Random"
	if layout == "Random" then
		local layouts = {"circular", "choke_point", "three_lanes", "split_center"}
		layout = layouts[math.random(#layouts)]
	else
		layout = layout:lower():gsub(" ", "_")
		if layout == "classic" then
			layout = "circular"
		elseif layout == "chokepoint" then
			layout = "choke_point"
		end
	end
	esports_core.match.current_map_layout = layout
	core.chat_send_all(">> MATCH: Map layout selected: " .. layout:upper():gsub("_", " "))

	-- 3. Map Scaling
	local scales = {Small = 0.5, Medium = 0.75, Large = 1.0}
	local scale = scales[map_size or "Small"] or 0.5
	esports_core.match.current_map_scale = scale

	-- 3. Apply Scaling to Environment & CTF Data
	esports_storm.current_radius = 100 * scale
	esports_core.ctf.bases.red.x = 80 * scale
	esports_core.ctf.bases.blue.x = -80 * scale

	-- 4. Mode Configuration
	local is_pve = pve_mode
	local is_ffa = (game_mode == "ffa")
	local is_koth = (game_mode == "koth")
	local is_payload = (game_mode == "payload")
	local is_spleef = (game_mode == "spleef")
	local is_ctf = (game_mode == "ctf" or game_mode == "tagctf")
	local is_tagctf = (game_mode == "tagctf")
	local is_domination = (game_mode == "domination")

	esports_core.match.is_pve = is_pve
	esports_core.match.is_ffa = is_ffa
	esports_core.match.is_koth = is_koth
	esports_core.match.is_payload = is_payload
	esports_core.match.is_spleef = is_spleef
	esports_core.match.is_ctf = is_ctf
	esports_core.match.is_tagctf = is_tagctf
	esports_core.match.is_domination = is_domination

	-- Friendly Fire: Forced true for FFA, otherwise follow the toggled value (defaulting to false)
	if is_ffa then
		esports_core.match.friendly_fire = true
	elseif friendly_fire ~= nil then
		esports_core.match.friendly_fire = friendly_fire
	else
		esports_core.match.friendly_fire = false
	end

	-- Melee Damage: Follow the toggled value (defaulting to true)
	if melee_damage ~= nil then
		esports_core.match.melee_damage = melee_damage
	else
		esports_core.match.melee_damage = true
	end
	esports_core.match.temp_spectators = {}

	esports_core.teams.scores = {red = 0, blue = 0}

	-- 5. Physical Objective Deployment
	if esports_core.match.is_ctf then
		esports_core.ctf.spawn_flags()
	end

	-- 6. World Time Logic
	core.settings:set("time_speed", "0")  -- Freeze time
	if time_mode == "night" then
		core.set_timeofday(0)  -- Midnight
	else
		core.set_timeofday(0.5)  -- Noon
	end

	-- 7. Update Team Names for HUD
	if is_pve then
		esports_core.teams.active_team_names.red = "BOTS"
		esports_core.teams.active_team_names.blue = t1
	else
		esports_core.teams.active_team_names.red = t1
		esports_core.teams.active_team_names.blue = t2
	end

	-- Force HUD refresh for everyone
	for _, p in ipairs(core.get_connected_players()) do
		esports_core.hud.init_hud(p)
	end
	esports_core.hud.update_timer("MATCH ACTIVE!")

	local players = core.get_connected_players()
	local t1_online = {}
	local t2_online = {}

	if is_ffa then
		-- FFA: All online non-spectator players participate
		for _, p in ipairs(players) do
			local pname = p:get_player_name()
			if not esports_core.is_spectator(pname) then
				table.insert(t1_online, p)
			end
		end
	elseif is_pve then
		-- PVE: Team 1 is players, Team 2 is Bots
		for _, p in ipairs(players) do
			local pname = p:get_player_name()
			if not esports_core.is_spectator(pname) then
				local pteam = esports_league.player_to_team[pname]
				if pteam == t1 then table.insert(t1_online, p) end
			end
		end
	else
		-- Regular PVP
		for _, p in ipairs(players) do
			local pname = p:get_player_name()
			if not esports_core.is_spectator(pname) then
				local pteam = esports_league.player_to_team[pname]
				if pteam == t1 then table.insert(t1_online, p) end
				if pteam == t2 then table.insert(t2_online, p) end
			end
		end
	end

	if is_ffa then
		if #t1_online < 1 then
			return false, "Need at least 1 player online to start Free For All."
		end
	elseif not is_pve and (#t1_online < 1 or #t2_online < 1) then
		return false, "Each team needs at least 1 player online. (Found: " .. t1 .. ": " .. #t1_online .. ", " .. t2 .. ": " .. #t2_online .. ")"
	end
	if is_pve and #t1_online < 1 then
		return false, "Your team must have at least 1 player online."
	end

	-- Start match (with countdown)
	if is_ffa then
		esports_core.match.active_teams = {red = "FFA", blue = "FFA"}
	elseif is_pve then
		-- PVE SPECIFIC: Team 1 (Players) is always BLUE, Team 2 (Bots) is always RED
		esports_core.match.active_teams = {red = t2, blue = t1}
	else
		esports_core.match.active_teams = {red = t1, blue = t2}
	end
	esports_core.match.state = "countdown"
	esports_core.match.is_debug = false
	esports_core.match.timer = 6
	esports_core.match.match_duration = tonumber(dur_secs) or 300
	esports_core.match.paused = false
	paused_physics = {}

	-- Clear old assignments
	esports_core.teams.players = {}

	-- Assign participants to their respective Red/Blue sides
	if is_pve then
		-- In PvE, Team online 1 (Players) are ALL BLUE
		for _, p in ipairs(t1_online) do
			esports_core.teams.players[p:get_player_name()] = "blue"
			esports_core.teams.update_nametag(p)
		end
	else
		-- In PvP, follow the standard Red/Blue mapping
		for _, p in ipairs(t1_online) do
			esports_core.teams.players[p:get_player_name()] = "red"
			esports_core.teams.update_nametag(p)
		end
		for _, p in ipairs(t2_online) do
			esports_core.teams.players[p:get_player_name()] = "blue"
			esports_core.teams.update_nametag(p)
		end
	end

	-- Reset Arena and CTF State
	if not esports_core.match.is_spleef then
		if esports_mapgen and esports_mapgen.reset_island then
			if layout ~= esports_mapgen.current_layout or scale ~= esports_mapgen.current_scale then
				esports_mapgen.reset_island(layout, scale)
			end
		end
	end

	if esports_core.match.is_ctf then
		esports_core.ctf.reset()
		esports_core.ctf.spawn_flags()
	end

	if esports_core.match.is_spleef then
		if esports_mapgen and esports_mapgen.setup_spleef_arena then
			esports_mapgen.setup_spleef_arena(esports_core.match.spleef_levels)
		end
	end

	if esports_core.match.is_payload then
		esports_core.payload.reset()
		esports_core.payload.spawn_cart()
		esports_core.ctf.spawn_flags()  -- Use flag bases as origin and destination visual markers
	end

	if esports_core.match.is_koth then
		if esports_core.koth.placed_ring and esports_core.koth.placed_ring:get_luaentity() then
			esports_core.koth.placed_ring:remove()
		end
		esports_core.koth.placed_ring = nil
		esports_core.koth.spawn_new_hill()
	end

	if esports_core.match.is_domination then
		esports_core.dom.setup()
	end

	if esports_storm then
		esports_storm.current_radius = 100 * scale
		-- Only randomize storm center in FFA matches on the default circular layout.
		-- Team games and lane/choke layouts must remain perfectly centered for fairness.
		if is_ffa and layout == "circular" and esports_storm.randomize_center then
			esports_storm.randomize_center()
		else
			esports_storm.center = {x=0, y=0, z=0}
		end
	end

	esports_core.teams.scores.red = 0
	esports_core.teams.scores.blue = 0
	esports_core.hud.update_scores()

	-- Teleport Combatants
		for _, p in ipairs(core.get_connected_players()) do
			local pname = p:get_player_name()
			local my_team = esports_league.get_team(pname)

			-- PVE Overdrive: If in PVE, everyone not spectating should join the fight
			if is_pve and not esports_core.is_spectator(pname) and (not my_team or my_team == "NONE") then
				my_team = t1
				-- Temporarily assign them for the duration of this match
				esports_core.match.player_sides[pname] = "red"
			end

			if is_ffa and not esports_core.is_spectator(pname) then
				esports_core.match.player_sides[pname] = "ffa"
				esports_core.teams.players[pname] = "ffa"
				esports_core.match.player_stats[pname] = {kills = 0, deaths = 0, captures = 0}
				esports_core.reset_player(p, esports_core.match.is_debug)
				
				-- Teleport directly to safe spawn position
				local target_pos = esports_core.get_safe_spawn_pos("ffa", true)
				p:set_pos(target_pos)
				p:set_physics_override({speed = 0, jump = 0, gravity = 0})

				esports_core.hud.init_hud(p)

				-- Close lobby and hide blackout after a short delay to allow chunk loading
				core.after(0.5, function()
					local player_obj = core.get_player_by_name(pname)
					if player_obj then
						if esports_core.lobby and esports_core.lobby.blackout_hide then
							esports_core.lobby.blackout_hide(player_obj)
						end
						core.close_formspec(pname, "esports_core:lobby")
					end
				end)
			elseif my_team == t1 or my_team == t2 then
				local side
				if is_pve then
					side = "blue"  -- Everyone online is on the player side
				else
					side = (my_team == t1) and "red" or "blue"
				end
				esports_core.match.player_sides[pname] = side

				-- Full Match Setup (Inventory, Physics, HUD)
				esports_core.reset_player(p, esports_core.match.is_debug)
				
				-- Teleport directly to safe spawn position
				local target_pos = esports_core.get_safe_spawn_pos(side, true)
				p:set_pos(target_pos)
				p:set_physics_override({speed = 0, jump = 0, gravity = 0})

				esports_core.hud.init_hud(p)

				-- Close lobby and hide blackout after a short delay to allow chunk loading
				core.after(0.5, function()
					local player_obj = core.get_player_by_name(pname)
					if player_obj then
						if esports_core.lobby and esports_core.lobby.blackout_hide then
							esports_core.lobby.blackout_hide(player_obj)
						end
						core.close_formspec(pname, "esports_core:lobby")
					end
				end)
			end
		end

	if is_ffa then
		core.chat_send_all("FREE FOR ALL MATCH STARTED! EVERY PLAYER FOR THEMSELVES!")
	elseif is_pve then
		-- Spawn Bots
		esports_core.bots.clear_all()
		core.after(5, function()
			local count = bot_count or 5
			local diff = bot_diff or "medium"
			for i = 1, count do
				-- Tactical Mix: 60% Rusher (Aggressive Pressure), 40% Standard (Balanced)
				local class = math.random() > 0.6 and "standard" or "rusher"
				esports_core.bots.spawn(esports_core.get_safe_spawn_pos("red", true), diff, class)
			end
		end)
		core.chat_send_all("PVE SENTRY PROTOCOL INITIATED. " .. (bot_count or 5) .. " Hostiles Detected.")
	else
		core.chat_send_all("MATCH STARTED: " .. t1 .. " vs " .. t2 .. "!")
	end

	return true, "Match started."
end

core.register_chatcommand("match", {
	params = "<team1> <team2> [duration] [on/off] [day/night] [melee_on/melee_off]",
	description = "Start a league match (Admin only). Options: [on] for FF, [night] for Time, [melee_off] to disable melee.",
	privs = {server = true},
	func = function(name, param)
		local t1, t2, dur, ff, time_mode, melee = param:match("^(%S+)%s+(%S+)%s*(%d*)%s*(%S*)%s*(%S*)%s*(%S*)$")
		if not t1 or not t2 then return false, "Usage: /match <Team1> <Team2> [duration] [on/off] [day/night] [melee_on/melee_off]" end
		local ff_enabled = (ff == "on")
		if ff == "day" or ff == "night" then
			time_mode = ff
			ff_enabled = false
		end
		local melee_enabled = true
		if ff == "melee_off" then
			melee_enabled = false
		elseif time_mode == "melee_off" then
			melee_enabled = false
			time_mode = nil
		elseif melee == "melee_off" then
			melee_enabled = false
		end
		return esports_core.match.start(t1, t2, dur, false, time_mode, nil, nil, "tdm", nil, ff_enabled, melee_enabled)
	end
})

core.register_chatcommand("matchdebug", {
	params = "<team1> <team2> [on/off] [day/night] [melee_on/melee_off]",
	description = "DEBUG: Start a match instantly. Options: [on] for FF, [night] for Time, [melee_off] to disable melee.",
	privs = {server = true},
	func = function(name, param)
		local t1, t2, ff, time_mode, melee = param:match("^(%S+)%s+(%S+)%s*(%S*)%s*(%S*)%s*(%S*)$")
		if not t1 or not t2 then return false, "Usage: /matchdebug <Team1> <Team2> [on/off] [day/night] [melee_on/melee_off]" end
		local ff_enabled = (ff == "on")
		if ff == "day" or ff == "night" then
			time_mode = ff
			ff_enabled = false
		end
		local melee_enabled = true
		if ff == "melee_off" then
			melee_enabled = false
		elseif time_mode == "melee_off" then
			melee_enabled = false
			time_mode = nil
		elseif melee == "melee_off" then
			melee_enabled = false
		end
		-- Debug matches are fast 5 min day or night
		return esports_core.match.start(t1, t2, 300, false, time_mode, nil, nil, "tdm", nil, ff_enabled, melee_enabled)
	end
})

core.register_chatcommand("botmatch", {
	params = "<team> <bot_count> [difficulty] [day/night]",
	description = "Start a PVE match against AI bots. Bots replace the blue team.",
	privs = {server = true},
	func = function(name, param)
		local team, count_str, diff, time_mode = param:match("^(%S+)%s+(%d+)%s*(%S*)%s*(%S*)$")
		if not team or not count_str then return false, "Usage: /botmatch <team> <number> [easy/medium/hard] [day/night]" end
		return esports_core.match.start(team, "BOTS", 300, true, time_mode, tonumber(count_str), diff)
	end
})

core.register_chatcommand("kothmatch", {
	params = "<team1> <team2> [duration] [day/night] [map_size]",
	description = "Start a competitive King of the Hill match (Admin only).",
	privs = {server = true},
	func = function(name, param)
		local t1, t2, dur, time_mode, map_size = param:match("^(%S+)%s+(%S+)%s*(%d*)%s*(%S*)%s*(%S*)$")
		if not t1 or not t2 then return false, "Usage: /kothmatch <Team1> <Team2> [duration] [day/night] [map_size]" end
		esports_core.match.friendly_fire = false
		return esports_core.match.start(t1, t2, dur, false, time_mode, nil, nil, "koth", map_size)
	end
})

core.register_chatcommand("payloadmatch", {
	params = "<team1> <team2> [duration] [day/night] [map_size]",
	description = "Start a competitive Payload match (Admin only).",
	privs = {server = true},
	func = function(name, param)
		local t1, t2, dur, time_mode, map_size = param:match("^(%S+)%s+(%S+)%s*(%d*)%s*(%S*)%s*(%S*)$")
		if not t1 or not t2 then return false, "Usage: /payloadmatch <Team1> <Team2> [duration] [day/night] [map_size]" end
		esports_core.match.friendly_fire = false
		return esports_core.match.start(t1, t2, dur, false, time_mode, nil, nil, "payload", map_size)
	end
})

core.register_chatcommand("dommatch", {
	params = "<team1> <team2> [duration] [day/night] [map_size]",
	description = "Start a competitive Domination match (Admin only).",
	privs = {server = true},
	func = function(name, param)
		local t1, t2, dur, time_mode, map_size = param:match("^(%S+)%s+(%S+)%s*(%d*)%s*(%S*)%s*(%S*)$")
		if not t1 or not t2 then return false, "Usage: /dommatch <Team1> <Team2> [duration] [day/night] [map_size]" end
		esports_core.match.friendly_fire = false
		return esports_core.match.start(t1, t2, dur, false, time_mode, nil, nil, "domination", map_size)
	end
})

core.register_chatcommand("ffamatch", {
	params = "[duration] [day/night] [map_size]",
	description = "Start a Free For All (Solo Deathmatch) match (Admin only).",
	privs = {server = true},
	func = function(name, param)
		local dur, time_mode, map_size = param:match("^(%d*)%s*(%S*)%s*(%S*)$")
		esports_core.match.friendly_fire = true
		return esports_core.match.start(nil, nil, dur, false, time_mode, nil, nil, "ffa", map_size)
	end
})

-- PROTECT SPECTATORS FROM PUNCHES
core.register_on_punchplayer(function(player, hitter, time_from_last_punch, tool_capabilities, dir, damage)
	local pname = player:get_player_name()
	if esports_core.is_spectator(pname) or (esports_core.is_in_lobby and esports_core.is_in_lobby(pname)) then return true end
	if hitter and hitter:is_player() then
		local hname = hitter:get_player_name()
		if esports_core.is_spectator(hname) or (esports_core.is_in_lobby and esports_core.is_in_lobby(hname)) then
			return true  -- Block damage
		end
	end
end)

function esports_core.match.pause()
	if esports_core.match.state ~= "active" and esports_core.match.state ~= "countdown" then
		return false, "Cannot pause: No active match."
	end
	if esports_core.match.paused then
		return false, "Match is already paused."
	end

	esports_core.match.paused = true
	paused_physics = {}

	for _, p in ipairs(core.get_connected_players()) do
		local pname = p:get_player_name()
		if not esports_core.is_spectator(pname) then
			paused_physics[pname] = p:get_physics_override()
			p:set_physics_override({speed = 0, jump = 0, gravity = 0})
		end
	end

	core.chat_send_all("⚠️ MATCH PAUSED BY ADMINISTRATOR!")
	return true, "Match paused."
end

function esports_core.match.resume()
	if not esports_core.match.paused then
		return false, "Match is not paused."
	end

	esports_core.match.paused = false

	for _, p in ipairs(core.get_connected_players()) do
		local pname = p:get_player_name()
		if not esports_core.is_spectator(pname) then
			local phys = paused_physics[pname]
			if phys then
				p:set_physics_override(phys)
			else
				-- Fallback to default match physics
				p:set_physics_override({speed = 1.2, jump = 1.1, gravity = 1.0})
			end
		end
	end
	paused_physics = {}

	core.chat_send_all("▶️ MATCH RESUMED!")
	return true, "Match resumed."
end

core.register_chatcommand("pause", {
	description = "Pause the current match (Admin only)",
	privs = {server = true},
	func = function(name, param)
		return esports_core.match.pause()
	end,
})

core.register_chatcommand("resume", {
	description = "Resume the current match (Admin only)",
	privs = {server = true},
	func = function(name, param)
		return esports_core.match.resume()
	end,
})


