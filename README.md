# Luanti eSports

This is a fast-paced hitscan Team Deathmatch base game for Luanti with building and storm mechanics.

> [!IMPORTANT]
> This game is currently in **active development** and in a **beta state**. Features, APIs, and mechanics are subject to change.

Note: this was built using Antigravity with Gemini 3 Pro. If you don't want to use AI generated content then this is not the mod for you.

## How to Install & Play

1. **Copy to Games Directory**
   Move this entire folder (`Luanti Deathmatch`) into your Luanti `games` directory.
   - On Windows: `Luanti/games/`
   - On Mac/Linux: `~/.minetest/games/` or `~/.luanti/games/`

2. **Start a Local Server**
   To test the game properly:
   - Open Luanti.
   - Go to the **Start Game** tab and select **Luanti eSports** from the bottom game list.
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

### Player Commands
*   `/spectate [player_name]`: Toggles spectator mode for yourself or another player. Spectators are invisible, can't take damage, have no inventory, and have flight/noclip privileges enabled (Admin only).
*   `/follow [player_name] | off`: Follow a player cinematically while in spectator mode. Leave blank to open the follow menu, or use `off` to stop following.
*   `/skin reset | #RRGGBB`: Tints your character skin with a hex color code, or resets it to the default (Admin only).

### League & Team Administration
*   `/team create <name> | invite <player> | join | leave | logo <eagle/lion/dragon/skull> | list`: Manage your TDM League team.
   - `create <name>`: Create a new team. Admins do not auto-join created teams.
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
*   `/leaguedelete <team_name>`: Permanently remove a team and its members from the league (Admin only).

### Lobby & GUI
*   `/lobby`: Opens the Main Menu.
   - **Standings**: Sorted by Wins, Round Differential (Kills Scored - Deaths Conceded), and total Kills. Features team leader settings and join requests.
   - **Schedule**: View round fixtures and launch scheduled matches (Admin only).
   - **History**: Persistent log displaying completed scores and MVPs.
   - **Playoffs**: Visual single-elimination tree tracking Semifinals and Finals.