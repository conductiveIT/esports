# Luanti eSports

This is a fast-paced hitscan Team Deathmatch base game for Luanti with building and storm mechanics.

Note: this was built using Antigravity with Gemini 3 Pro.  If you don't want to use AI generated content then this is not the mod for you.

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
   - **Storm**: A perimeter storm closes in over time during an active match. If you are too far from the center, you take periodic damage.

## Commands

### Match Management
*   `/match <red_team_name> <blue_team_name>`: Starts a competitive match between two registered league teams. This initializes the countdown and the storm.
*   `/matchdebug <red_team_name> <blue_team_name>`: Starts a debug match with all standard weapons (Assault Rifle, Shotgun) and ammo provided immediately.
*   `/botmatch <team_name> <bot_count> [difficulty]`: Starts a PVE match for a team against a specified number of AI bots. Difficulty can be `easy`, `medium`, or `hard`.

### Player Commands
*   `/spectate`: Toggles spectator mode. Spectators are invisible, can't take damage, and have no inventory.
*   `/follow <player_name>`: While in spectator mode, smoothly follow another player's perspective.
*   `/skin <1-3>`: Instantly change your player character's skin.

### League & Team Administration
*   `/team list`: List all registered teams and their members.
*   `/league`: Display the current league standings.
*   `/leaguesetleader <team_name> <player_name>`: Change the owner/leader of a team (Admin only).
*   `/leaguedelete <team_name>`: Permanently remove a team from the league records (Admin only).

### Lobby & GUI
*   `/lobby`: Opens the Main Menu. 
    - **Admins** can manage matchmaking, PVE settings, and league registration here.
    - **Players** are automatically directed to the Leaderboard.
œœ