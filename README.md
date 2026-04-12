# Luanti eSports

This is a fast-paced hitscan Team Deathmatch base game for Luanti with building and storm mechanics.

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

## Next Steps

Currently, the game uses solid-color placeholder textures (via Luanti texture modifiers). To improve the game visually:
- Replace `textures/tdm_weapons_assault_rifle.png`, etc., with actual pixel art.
- Replace sounds (`tdm_shoot_assault_rifle.ogg`, `tdm_build.ogg`) by creating a `sounds` folder in the respective mods.
