# esports

This is a fast-paced hitscan team combat base game for Luanti with building, storm mechanics, and full league management.

> [!IMPORTANT]
> This game is currently in **active development** and in a **beta state**. Features, APIs, and mechanics are subject to change.
> Note: this was built using Antigravity with Gemini 3 Pro. If you don't want to use AI generated content then this is not the mod for you.

## Key Features

### Game Modes
- **Team Deathmatch (TDM)**: Fast-paced hitscan combat where teams build, loot, and fight to reach the highest elimination score.
- **Capture the Flag (CTF)**: Objective-based mode where teams defend their home base flag stand while attempting to carry the enemy flag to victory.
- **Free For All (FFA)**: Solo deathmatch mode. Every player for themselves with randomized island spawns and friendly fire always enabled. Matches require no team registrations and have no impact on team standings or league history/player stats.
- **PvE Bot Practice**: Solo or cooperative training matches playing against difficulty-scaled AI sentries who navigate, loot, and shoot or melee through structural blockades.

### League Management System
- **Automated Round-Robin Scheduler**: Circles through all registered teams to dynamically build a complete regular season fixture schedule (supporting BYEs for odd team counts).
- **Standings & Tie-Breakers**: Real-time leaderboards sorted by Wins, then Round Differential (Kills Scored - Deaths Conceded), then total kills.
- **Match History Logging**: Persistent scrolling scroll log recording date, scores, home/away setups, and match MVP awards.
- **Single-Elimination Playoffs**: Automated seeding of the top 4 teams into a tournament bracket (Semifinals -> Grand Finals) to crown the season Champion.
- **Offseason Archiving**: Clean reset commands that serialize the finished season standings to history archives and prepare the league for a new cycle.

### Competitive & Spectator Features
- **Broadcaster HUD Overlay**: Spectators automatically see a live feed showing active players' status, weapons, HP, and followed target details.
- **Tactical Ping & Radio**: Teammates can place temporary 3D HUD markers visible only to their team (`⚠️ DANGER`, `🛡️ DEFEND`, `📍 MOVE HERE`).
- **Tactical Radar HUD Widget**: Active combatants get a top-right radar widget tracking teammate positions and current objective items (Flags, Hills, Cart, Domination Points) with distances and yaw-relative directional arrows (⬆, ↗, ➡, ↘, ⬇, ↙, ⬅, ↖) optimized for lag-free performance on 20+ player servers.
- **Aim Trainer Practice Range**: A private practice zone accessible via `/practice` with pop-up target entities, statistics tracking, and custom weapon warmups.
- **Audio Announcer**: Dynamic sounds and announcements for **Double Kill**, **Triple Kill**, **Shut Down**, and match countdown beeps.



## How to Install & Play

1. **Copy to Games Directory**
   Move this entire folder into your Luanti `games` directory.
   - On Windows: `Luanti/games/`
   - On Mac/Linux: `~/.minetest/games/` or `~/.luanti/games/`

2. **Start a Local Server**
   To test the game properly:
   - Open Luanti.
   - Go to the **Start Game** tab and select **esports** from the bottom game list.
   - Uncheck "Host Server" to just test in singleplayer to verify you spawn, get items, etc, OR you can launch the game and connect to your own local server with multiple windows.
   - When generating a world, make sure the Mapgen is set to "Singlenode" (this should be the default from `game.conf`).

3. **Mechanics Overview**
   - **HUD**: Shows your team color, the match status, and team scores. 
   - **Match State**: The game requires 2 players to start a 5-minute match. During warmup, scores are reset.
   - **Weapons**: Assault Rifle and Pump Shotgun are hitscan and use raycasting. Use left-click to shoot.
   - **Building**: Select a Wall or Ramp Blueprint and left-click the terrain to instantly place a piece.
   - **Bots**: Sentries scan their paths for player-built obstacles (`player_built` group) and stop to shoot or punch through them before proceeding.
   - **Storm**: A perimeter storm closes in over time during an active match. If you are too far from the center, you take periodic damage.

## Commands

### Match Management
*   `/match <team1> <team2> [duration] [off] [day/night]`: Starts a competitive match between two registered league teams. Optional parameters include match duration in seconds, `off` to disable friendly fire, and `day` or `night` to control match time (Admin only).
*   `/matchdebug <team1> <team2> [off] [day/night]`: Starts a debug match instantly with all standard weapons and ammo provided immediately. Optional parameters include `off` to disable friendly fire, and `day` or `night` to control match time (Admin only).
*   `/botmatch <team> <bot_count> [easy/medium/hard] [day/night]`: Starts a PVE match for a team against a specified number of AI bots. Bots replace the opposing team. Optional parameters include difficulty and `day` or `night` match time (Admin only).
*   `/ffamatch [duration] [day/night] [map_size]`: Starts a Free For All (Solo Deathmatch) match. Friendly fire is forced on, spawns are randomized, and statistics do not affect teams or league standings (Admin only).

### Player Commands
*   `/spectate [player_name]`: Toggles spectator mode for yourself or another player. Spectators are invisible, can't take damage, have no inventory, and have flight/noclip privileges enabled (Admin only).
*   `/follow [player_name] | off`: Follow a player cinematically while in spectator mode. Leave blank to open the follow menu, or use `off` to stop following.
*   `/skin reset | #RRGGBB`: Tints your character skin with a hex color code, or resets it to the default (Admin only).
*   `/nick [player_name] <nickname>`: Change your floating nametag, chat display name, and scoreboard name (alpha-numeric only, max 15 characters). Admins can target other players. Use `reset` or `clear` to restore the default name.
*   `/ping [danger|defend|move]`: Place a 3D tactical ping waypoint visible to all online teammates (lasts 6 seconds).
*   `/practice`: Teleport to the practice range (Aim Trainer) to practice shooting targets. Type `/lobby` to return to spawn.

### League & Team Administration
*   `/team create <name> <3_letter_tag> | invite <player> | join | leave | logo <eagle/lion/dragon/skull> | list`: Manage your TDM League team.
   - `create <name> <3_letter_tag>`: Create a new team with a unique 3-letter alphanumeric tag. Admins do not auto-join.
   - `invite <player>`: Invite a player to your team (leader only).
   - `join`: Join the team that invited you.
   - `leave`: Leave your current team.
   - `logo <eagle/lion/dragon/skull>`: Set your team's logo (leader only).
   - `list`: List all active teams, leaders, and standings points.
*   `/league [generate_schedule | start_playoffs | archive_season | reset_all]`: View standings or perform season operations (Admin only):
   - `generate_schedule`: Automatically schedule all regular season matches (Circle Method).
   - `start_playoffs`: Seed the top 4 teams and start the Semifinals.
   - `archive_season`: Log the champion and reset stats for the offseason.
   - `reset_all`: Fully clear all team records and fixtures.
*   `/leaderboard`: Display the global player leaderboard based on Net Kill Differential and Flag Capture Bonus.
*   `/leaguesetleader <team_name> <player_name>`: Assign a player as the leader/owner of a team (Admin only).
*   `/leagueunsetleader <team_name>`: Remove the current leader of a team, leaving it unset (Admin only).
*   `/leaguerename <old_name> <new_name>`: Rename a team, updating all league records, roster mappings, and match history (Admin only).
*   `/leaguesettag <team_name> <tag>`: Change/set a team's unique 3-letter tag (Admin only).
*   `/leaguedelete <team_name>`: Permanently remove a team and its members from the league (Admin only).

### Lobby & GUI
*   `/lobby`: Opens the Main Menu.
   - **Standings**: Sorted by Wins, Round Differential (Kills Scored - Deaths Conceded), and total Kills. Features team leader settings and join requests.
   - **Schedule**: View round fixtures and launch scheduled matches (Admin only).
   - **History**: Persistent log displaying completed scores and MVPs.
   - **Playoffs**: Visual single-elimination tree tracking Semifinals and Finals.
   - **Locker**: Choose character outfits and skins. Also includes the nickname editor interface for players to change their display names.
   - **Admin**: Configure bot match properties, view game rules, toggle the nickname system permissions for non-admins, and inspect/reset active player nickname mappings (Admin only).