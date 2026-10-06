# Luanti Esports

A fast-paced hitscan team combat base game and esports platform for [Luanti](https://www.luanti.org/) (formerly Minetest) featuring instant building, storm mechanics, procedural arena layouts, sprint stamina, full league tournament management, and spectator broadcasting.

> [!IMPORTANT]
> This game is currently in **active development** (v0.8.0). Features, APIs, and mechanics are actively maintained and subject to refinement.
> Note: Built using Antigravity with Gemini Pro.

---

## Table of Contents
1. [Key Features](#key-features)
2. [Game Modes](#game-modes)
3. [Combat & Movement Mechanics](#combat--movement-mechanics)
4. [Tactical Classes & Skins](#tactical-classes--skins)
5. [Arenas & Procedural Generation](#arenas--procedural-generation)
6. [Competitive & Spectator Features](#competitive--spectator-features)
7. [League Management & Tournament System](#league-management--tournament-system)
8. [External Utilities & Companion Tools](#external-utilities--companion-tools)
9. [Installation & Setup](#installation--setup)
10. [Server Configuration & Performance](#server-configuration--performance)
11. [Commands Reference](#commands-reference)

---

## Key Features

- **8 Diverse Match Modes**: From classic hitscan Team Deathmatch and CTF to King of the Hill, Payload escort, Domination, Spleef, and solo Free For All.
- **PvE Bot Sentries**: Train against difficulty-scaled AI sentries that navigate, fire raycast rifles, scavenge loot crates, and shoot through player-built blockades.
- **Tactical Sprint & Stamina**: Fluid movement mechanics with dynamic stamina HUD, sprint-jumping costs, exhaustion penalties, and CTF carrier weight.
- **Dynamic Procedural Arenas**: Multiple layout topologies (Circular, Choke Point, Three Lanes, Split Center) and scale multipliers with automatic post-match lobby restoration.
- **Instant Blueprints & Destructive Cover**: Rapid tactical building of walls and ramps with hit-point tracking and damage modeling.
- **Spectator Broadcast Suite**: Real-time spectator HUD overlays, cinematic follow cameras, team radar widgets, and 3D ping waypoints.
- **Integrated League Platform**: In-game round-robin fixture generator, standings leaderboards, tie-breaker logic, match history archives, and 4-team playoff brackets.
- **External Companion Tooling**: Xbox gamepad mappers (Python and PowerShell), SQLite league stats exporter, and responsive web dashboards.

---

## Game Modes

### 1. Team Deathmatch (TDM)
Fast-paced hitscan combat where two registered league teams build, scavenge weapons from supply crates, and compete for the highest elimination score within the match timer.

### 2. Capture the Flag (CTF & Tag CTF)
Objective-based team combat. In traditional CTF, teams defend their home flag stand while infiltrating enemy territory to retrieve the opposing flag. In Tag CTF, teams compete over a single neutral flag. Flag carriers incur a tactical movement and stamina penalty and cannot wield guns while carrying.

### 3. King of the Hill (KOTH)
Teams battle for control over a designated hill ring that periodically relocates across the island. Teams earn control seconds when uncontested; contested hills pause score accumulation until one side secures dominance.

### 4. Payload
An asymmetric escort game mode. Red team escorts an armored payload cart through the arena toward the Blue team's base by maintaining close proximity. Blue defenders stall progression and contest the payload radius to run down the clock.

### 5. Domination (DOM)
A tactical multi-zone control mode featuring three capture rings (**A**, **B**, **C**) adapted dynamically to the arena layout. Standing within uncontested capture rings captures them for your team, generating points over time.

### 6. Spleef
Arena elimination mode featuring destructible floor layers (configurable 1, 2, or 3 vertical layers). Equipped with harvesting pickaxes, players demolish ground blocks beneath opponents to drop them into the void.
- **Scoring System**: +1 survival point per second alive, +2 points per block broken, and +50 bonus points for match victory.
- **Last Player Standing**: Guarantees match win and MVP status for the sole surviving combatant.

### 7. Free For All (FFA)
Solo deathmatch where every player fights for themselves. Features randomized perimeter spawns, forced friendly fire, and isolated match stats that do not modify league team standings.

### 8. PvE Bot Practice
Solo or cooperative match mode against difficulty-scaled AI sentries that replace the opposing roster:
- **Difficulty Tiers**:
  - `Easy`: 70 HP, 1.5s fire rate, wide spread, 6 damage.
  - `Medium`: 170 HP, 0.8s fire rate, moderate spread, 12 damage.
  - `Hard`: 340 HP, 0.4s fire rate, tight spread, 18 damage, rapid movement.
- **Bot Class Archetypes**:
  - `Standard`: Balanced medium-range combatant (20–30m engagement).
  - `Sniper`: Extreme range overwatch (40–60m), 3x bullet damage, pinpoint raycasts.
  - `Rusher`: Aggressive close-quarters flanker (5–12m), 1.4x sprint speed.
- **Tactical AI**: Sentries identify and demolish player-built obstacles (`player_built` group) blocking their paths and seek out supply crates when out of ammunition. Dynamic nametags display live bot health.

---

## Combat & Movement Mechanics

### Tactical Sprint & Stamina
- **Sprint Trigger**: Move forward (`W` / Up) while holding **Shift** (Sneak key). Provides a **1.4x speed multiplier** (base 1.2 &rarr; 1.68).
- **Stamina Bar HUD**: Clean 100-point dynamic stamina widget above the health bar with real-time color tiers:
  - 🔵 **Vibrant Cyan** (&gt;40%): Optimal stamina.
  - 🟡 **Gold / Amber** (20%–40%): Moderate exertion.
  - 🔴 **Red** (&lt;20%): Low stamina warning.
  - ⚠️ **Exhausted** (0%): Sprinting locked out until stamina regenerates past 25%.
- **Sprint Jumping**: Jumping while sprinting expends a burst of 8 stamina points.
- **CTF Flag Carrier Weight**: Carrying a flag reduces base speed to 0.9x and increases sprint stamina drain by 1.5x.
- **Visuals**: Dynamic ground dust particles and dedicated sprint animations (`sprint`, `sprint_mine`).

### Hitscan Weapons & Combat
- **Assault Rifle**: High fire-rate hitscan rifle with raycast projectile traces, bullet spread, and medium range.
- **Pump Shotgun**: High-damage close-quarters weapon firing multiple hitscan pellets in a tactical spread pattern.
- **Harvesting Pickaxe**: High block-damage tool specialized for rapid structural demolition and Spleef arenas.
- **Ammo Stash**: Dedicated `ammo` inventory compartment that automatically stashes picked-up ammunition without cluttering hotbar slots. Duplicate weapon pickups are automatically converted into bonus ammunition.
- **Structure Demolition**: All weapons and pickaxes damage blocks in the `player_built` group and supply crates (`esports_loot:box`).

### Instant Building System
- Instant wall and ramp construction using blueprints.
- Built structures carry designated hit points (50 HP standard) and can be shot through or pickaxed down by both players and bots.

### Perimeter Storm Barrier
- A glowing cylindrical storm contracts inward during active matches.
- Players stranded outside the storm boundary take periodic damage (4 HP/sec).
- High-performance implementation using inlined squared-distance math and optimized particle spacing.

### Controls Quick Guide
| Action | Key / Input | Notes |
| :--- | :--- | :--- |
| **Move** | `W`, `A`, `S`, `D` | Standard movement |
| **Tactical Sprint** | `W` + **Shift** (Sneak) | 1.4x–1.5x speed multiplier, consumes stamina |
| **Sprint Jump** | **Space** (while sprinting) | Tactical leap, expends burst stamina (6–10 stm) |
| **Fire / Mine / Build** | **Left Mouse Button (LMB)** | Raycast hitscan shooting, pickaxe harvesting, or instant blueprint placing |
| **Live Scoreboard** | **Zoom (`Z`)** or **Aux1 (`E`)** | Hold or toggle full-match overlay scoreboard |
| **Main Menu / Lobby** | `/lobby` or `/l` | Opens character locker, standings, schedule, and playoffs |
| **Personal Stats** | `/stats` or `/score` | Prints live match performance metrics directly in chat |
| **Review Last Outro** | `/lastmatch` | Re-opens previous match post-game summary screen |

---

## Tactical Classes & Skins

Players can select their field outfit from the **Locker** (`/lobby`), which doubles as a **tactical class selector**. Each outfit grants a distinct playstyle with unique Health, Sprint Speed, Stamina capacity, and gameplay perks:

| Skin | Class Archetype | Tactical Role | Health | Sprint | Stamina | Jump Cost | Regen Delay | Special Tactical Perk |
| :--- | :--- | :--- | :---: | :---: | :---: | :---: | :---: | :--- |
| **Tactical Sam**<br>`character.png` | **Operator**<br>(All-Rounder) | Balanced frontline specialist | **100 HP** | 1.40x | 100 | 8 stm | 1.0s | Reliable baseline stats across all game modes. |
| **Elite Soldier**<br>`skin_1.png` | **Juggernaut**<br>(Tank / Anchor) | Point holding, Payload escort, Hill defense | **120 HP** | 1.30x | 100 | 10 stm | 1.2s | **+20 Max HP** & **+50% Demolition damage** (destroys cover faster). |
| **Ghost Recon**<br>`skin_2.png` | **Marksman**<br>(Precision / Scout) | Long-range pickoffs & reconnaissance | **90 HP** | 1.40x | 100 | 8 stm | **0.4s** | **Rapid Stamina Recovery** (0.4s delay) & **&minus;25% Bullet Spread** (pinpoint accuracy). |
| **Infiltrator**<br>`skin_3.png` | **Rusher**<br>(Flanker / Runner) | Flag retrieval, Domination back-caps, flanking | **85 HP** | **1.50x** | **120** | **6 stm** | 0.8s | **120 Stamina**, **1.5x Sprint Speed**, low jump cost, and **Swift Flag Running** (near-zero CTF carry speed penalty). |

> [!TIP]
> **Competitive League Purity Toggle**: Administrators can toggle class stat modifiers on or off at any time using `/classes on` / `/classes off` or via the **Skin Class Stats** checkbox in the Admin Lobby tab. When disabled, all outfits function as 100% cosmetic skins with identical baseline attributes (100 HP, 1.4x sprint).

---

## Arenas & Procedural Generation

The game operates exclusively on the **Singlenode** (void) mapgen, procedurally spawning battle arenas:

- **Topological Layouts**:
  - `Circular` (Classic): Open arena with circular storm and distributed cover.
  - `Choke Point`: Central narrow bridge flanked by deep chasms, forcing direct engagements.
  - `Three Lanes`: MOBA-inspired three-lane structure separating teams into discrete skirmish paths.
  - `Split Center`: Central island hub connected by dual elevated approach bridges.
- **Map Scaling**:
  - `Small`: 0.375x scale — ideal for 1v1 and fast skirmishes.
  - `Medium`: 0.75x scale — balanced for standard team play.
  - `Large`: 1.0x scale — maximum combat area for large team battles.
- **Automated Lifecycle**: When a match concludes or is stopped by an administrator, the arena resets to the default lobby layout and all players are safely teleported back to center spawn.

---

## Competitive & Spectator Features

### Aim Trainer Practice Range
- Accessible to any player via `/practice`.
- Generates an isolated shooting range at coordinate offsets with moving target entities.
- Tracks shots fired, targets hit, and live accuracy percentage. Target entities adapt lateral movement speed as hit streaks increase.
- **Match Interlock**: When an administrator starts a competitive match, players inside the practice range are automatically returned to the lobby.

### Spectator Mode & Broadcaster Overlay
- Full spectator privileges (`/spectate`) with fly and noclip capabilities, complete invisibility, and punch immunity.
- Cinematic player follow camera (`/follow <player_name>`).
- Broadcaster overlay presenting real-time player health, equipped weapons, and active camera targets.

### Tactical Radar HUD
- Integrated compass/radar widget in the top-right corner of active combatants.
- Displays teammate locations and live objective targets (Flags, KOTH hill, Payload cart, Domination points) with yaw-relative directional arrows (⬆, ↗, ➡, ↘, ⬇, ↙, ⬅, ↖) and distance meters.

### Match Outro & Personal Stats
- End-of-match cinematic stats screen with MVP awards and team score breakdowns.
- **Accidental Close Protection**: Includes a 3-second safety lockout to prevent players from accidentally closing the victory screen during heated combat clicks.
- Re-open last match stats at any time using `/lastmatch` or via the **View Last Match Stats** button in the Main Lobby.
- Check live in-game match performance via `/stats` or `/score`.

### Team Branding & Identity
- Dynamic team logo resolution: Automatically detects and displays `<team_name>_logo.png` from the textures directory.
- Nickname management (`/nick`) supporting custom display names across chat, scoreboard, and 3D floating nametags.

---

## League Management & Tournament System

Luanti Esports features a tournament engine operated through GUI or chat commands:

- **Automated Round-Robin Scheduling**: Dynamic fixture generation supporting even and odd team numbers (with automated BYE handling).
- **Standings & Tie-Breakers**: Leaderboards sorted by:
  1. Total Wins
  2. Round Differential (Eliminations Scored &minus; Deaths Conceded)
  3. Total Eliminations Scored
- **Persistent Match History**: Records date, scores, home/away lineups, and match MVP awards in persistent storage.
- **Single-Elimination Playoffs**: Automatically seeds the top 4 teams into a tournament bracket (Semifinals &rarr; Grand Finals) to crown the season champion.
- **Season Archiving**: Commands to archive final season standings to permanent history and reset league records for a new competitive cycle.

---

## External Utilities & Companion Tools

The repository includes several companion scripts:

- **Xbox Controller Mappers**:
  - `run_controller.py`: High-performance Python script using `ctypes` and native `XInput` / `user32` calls to map Xbox thumbsticks, triggers, and buttons directly into mouse and keyboard input for Luanti.
  - `run_controller.ps1`: Zero-dependency PowerShell script compiling C# in memory to achieve native XInput controller mapping on Windows.
- **Static League Stats Generator (`generate_static_stats.py`)**:
  - Python utility that connects directly to Luanti's `mod_storage.sqlite`, parses and deserializes compressed Lua tables, and renders static dashboards (`league_stats.html` / `league_stats.aspx`).
- **Intro Portal Exporter (`website/intro/update_teams.py`)**:
  - Extracts registered teams and player nicknames from SQLite storage into clean JSON for web portals.

---

## Installation & Setup

### 1. Game Installation
Clone or copy this repository into your Luanti `games` directory:
- **Windows**: `%APPDATA%\Luanti\games\esports` or `<Luanti_Install_Dir>\games\esports`
- **macOS**: `~/Library/Application Support/luanti/games/esports` or `~/.luanti/games/esports`
- **Linux**: `~/.luanti/games/esports` or `~/.minetest/games/esports`

### 2. Creating a World
1. Launch Luanti.
2. Select the **Start Game** tab.
3. Select **esports** from the game list at the bottom.
4. Click **New World**. Ensure the Mapgen is set to **Singlenode** (defined automatically in `game.conf`).
5. Launch the world in Singleplayer or check **Host Server** to host multiplayer.

---

## Server Configuration & Performance

For smooth multiplayer matches with 20+ players, use the optimized settings provided in `example server.conf`:

```conf
# Networking & Packet Throughput
max_packets_per_iteration = 8192
max_simultaneous_block_sends_per_client = 128
max_simultaneous_block_sends_server_total = 1024
congestion_control_min_rate = 128
congestion_control_max_rate = 2000
congestion_control_aim_rtt = 0.2
emergequeue_limit_total = 2048
emergequeue_limit_diskonly = 1024
emergequeue_limit_generate = 512

# PvP & CPU Performance Tuning
active_block_range = 2
server_map_save_interval = 15.3
sqlite_synchronous = 0
num_emerge_threads = 4
disable_anticheat = true
item_entity_ttl = 30

# Logging Optimization
debug_log_level = warning
```

---

## Commands Reference

### Match Management (Admin)
| Command | Arguments | Description |
| :--- | :--- | :--- |
| `/match` | `<team1> <team2> [duration] [on/off] [day/night] [melee_on/melee_off]` | Start a competitive TDM match between registered teams. `on` enables friendly fire. |
| `/matchdebug` | `<team1> <team2> [on/off] [day/night] [melee_on/melee_off]` | Instantly starts a debug match with full weapons and ammo provided. |
| `/botmatch` | `<team> <count> [easy/medium/hard] [day/night]` | Start a PvE match for a team against AI sentries. |
| `/kothmatch` | `<team1> <team2> [duration] [day/night] [map_size]` | Start a King of the Hill match. |
| `/payloadmatch` | `<team1> <team2> [duration] [day/night] [map_size]` | Start a Payload escort match. |
| `/dommatch` | `<team1> <team2> [duration] [day/night] [map_size]` | Start a Domination 3-zone control match. |
| `/ffamatch` | `[duration] [day/night] [map_size]` | Start a solo Free For All match with forced friendly fire. |
| `/classes` | `[on/off]` | Toggle or inspect skin class stat modifiers (`on` for class stats, `off` for cosmetic only). |
| `/pause` | *None* | Pause the active match and freeze player physics. |
| `/resume` | *None* | Resume a paused match and restore physics. |

### Player & Training Commands
| Command | Arguments | Description |
| :--- | :--- | :--- |
| `/lobby` or `/l` | *None* | Open the main lobby interface or return from the practice range. |
| `/practice` | *None* | Teleport to the Aim Trainer practice range. |
| `/stats` or `/score` | *None* | View your live performance and combat statistics for the current match. |
| `/lastmatch` | *None* | Display the post-game summary screen from the most recent match. |
| `/ping` | `danger` \| `defend` \| `move` | Place a 3D tactical ping visible to teammates (6-second duration). |
| `/nick` | `[player] <nickname>` \| `reset` | Set your display name across nametag, scoreboard, and chat (Admin can target others). |
| `/skin` | `reset` \| `#RRGGBB` | Tint your character skin with a hex color code (Admin only). |
| `/spectate` | `[player_name]` | Toggle spectator ghost mode (Admin only). |
| `/follow` | `[player_name]` \| `off` | Cinematically follow an active combatant while spectating. |

### Team & League Administration
| Command | Arguments | Description |
| :--- | :--- | :--- |
| `/team create` | `<name> <3_letter_tag>` | Register a new team with a unique 3-letter tag. |
| `/team invite` | `<player>` | Invite a player to your team (team leader only). |
| `/team join` | *None* | Accept a team invitation. |
| `/team leave` | *None* | Leave your current team. |
| `/team logo` | `<eagle/lion/dragon/skull>` | Select a default team logo banner. |
| `/team list` | *None* | List all registered teams, leaders, and standings points. |
| `/league` | `[generate_schedule \| start_playoffs \| archive_season \| reset_all]` | Execute season operations and schedule matches (Admin only). |
| `/leaderboard` | *None* | Display global player leaderboards by Net Kill Differential and Flag Captures. |
| `/leaguesetleader` | `<team_name> <player_name>` | Assign a leader/owner to a team (Admin only). |
| `/leagueunsetleader`| `<team_name>` | Remove the current leader of a team (Admin only). |
| `/leaguerename` | `<old_name> <new_name>` | Rename a team across all league records, rosters, and match histories (Admin only). |
| `/leaguesettag` | `<team_name> <tag>` | Update a team's 3-letter abbreviation tag (Admin only). |
| `/leaguedelete` | `<team_name>` | Permanently delete a team and clear its members (Admin only). |

### Lobby GUI Tabs (`/lobby`)
- **Main**: Quick stats, active match status, live player overview, and **View Last Match Stats** button.
- **Standings**: Real-time team leaderboard with wins, round differential, total kills, and leader controls.
- **Schedule**: Regular season round fixtures with one-click match launchers (Admin only).
- **History**: Chronological log of finished matches, scores, and MVPs.
- **Playoffs**: Visual single-elimination tournament bracket tracking Semifinals and Grand Finals.
- **Locker**: Character outfits & tactical class selector with live stat previews (HP, Speed, Stamina, Perks), color tints, and interactive nickname editor.
- **Admin**: Bot match configurations, game mode rules, skin class stats toggle, nickname permission toggles, and live server controls.