# Requirements Document

## Introduction

A pre-defined turret system that runs alongside the existing resource-combo tower system. Players earn session coins by killing enemies during gameplay, spend session coins to place and upgrade turrets on the map, and upon game over the kill-earned coins are banked as persistent coins. Persistent coins are used in the lobby shop to buy new turret types or upgrade turrets. Players equip a loadout of 3 turrets before entering a game. The first basic turret is unlocked by default for all players. Players receive starting session coins at the beginning of each game so they can afford their first turret placement.

## Glossary

- **Turret_System**: The server-side module managing turret definitions, ownership, loadouts, placement, targeting, shooting, and upgrades.
- **Turret_Shop**: The lobby UI and server logic that lets players browse, preview, and purchase turret types using persistent coins.
- **Turret_Loadout**: The set of exactly 3 turret types a player selects before entering a game session.
- **Turret_Type**: A pre-defined turret blueprint with fixed base stats (damage, range, fire rate), a shop purchase price (persistent coins), and a placement cost (session coins). Not combo-based.
- **Session_Coins**: Temporary coins earned by killing enemies during a game session. Used for in-game turret placement and upgrades. Reset at the start of each game session.
- **Persistent_Coins**: Permanent currency banked after game over from Session_Coins earned via kills. Stored per player and used in the lobby Turret_Shop for buying new turrets or upgrading.
- **Coin_Balance**: The combined coin tracking for a player, consisting of both Session_Coins (in-game) and Persistent_Coins (lobby). Managed via the existing EconomyManager module.
- **Turret_Instance**: A placed turret on the map during a game session, created from a Turret_Type in the player's loadout.
- **Turret_Upgrade**: An improvement applied to a Turret_Instance during a game session, increasing its stats in exchange for session coins.
- **Loadout_Selector**: The lobby UI panel where players choose which 3 unlocked turrets to bring into a game.
- **Turret_Placer**: The client-side module handling turret placement preview and grid-slot selection during gameplay.
- **Kill_Earnings**: The running total of Session_Coins a player has earned from enemy kills during the current game session, tracked separately for banking on game over.

## Requirements

### Requirement 1: Turret Type Definitions

**User Story:** As a developer, I want a shared data module defining all turret types with their stats and prices, so that both client and server reference consistent turret data.

#### Acceptance Criteria

1. THE Turret_System SHALL define each Turret_Type with the following properties: id, name, description, damage, range, fireRate, shopPrice (in Persistent_Coins), placementCost (in Session_Coins), and upgradeMultipliers.
2. THE Turret_System SHALL include a default turret named "Scout Turret" with low damage (5), short range (12), moderate fire rate (1.0), a shopPrice of 0 Persistent_Coins, and a placementCost of 50 Session_Coins.
3. THE Turret_System SHALL define at least 5 additional Turret_Types with increasing stats, increasing shopPrice values, and distinct placementCost values per turret type.
4. THE Turret_System SHALL expose a function to retrieve a Turret_Type by its id.

### Requirement 2: Dual Coin Economy

**User Story:** As a player, I want to earn session coins during gameplay and bank them as persistent coins after game over, so that I can purchase and upgrade turrets in the lobby shop.

#### Acceptance Criteria

1. WHEN a game session starts, THE Turret_System SHALL initialize each player's Session_Coins to a starting amount of 100 coins.
2. WHEN an enemy is killed, THE Turret_System SHALL award Session_Coins to each player in the game session equal to the enemy's existing reward value.
3. WHEN an enemy is killed, THE Turret_System SHALL add the enemy's reward value to each player's Kill_Earnings total for the current session.
4. WHEN a player spends Session_Coins on turret placement or in-game upgrade, THE Turret_System SHALL deduct the cost from the player's Session_Coins balance.
5. IF a player attempts to spend more Session_Coins than the player's current Session_Coins balance, THEN THE Turret_System SHALL reject the transaction and return an error message.
6. WHEN a game session ends (game over), THE Turret_System SHALL add each player's Kill_Earnings total to the player's Persistent_Coins balance.
7. WHEN a game session ends, THE Turret_System SHALL display each player's Kill_Earnings banked as Persistent_Coins on the results screen.
8. THE Turret_System SHALL store each player's Persistent_Coins balance using the existing EconomyManager module so the balance persists across game sessions.
9. WHEN a player spends Persistent_Coins on a turret purchase in the Turret_Shop, THE Turret_System SHALL deduct the shopPrice from the player's Persistent_Coins balance.
10. IF a player attempts to spend more Persistent_Coins than the player's current Persistent_Coins balance, THEN THE Turret_System SHALL reject the transaction and return an error message.

### Requirement 3: Turret Shop in Lobby

**User Story:** As a player, I want a shop in the lobby where I can browse and buy turret types using persistent coins, so that I can expand my available turrets.

#### Acceptance Criteria

1. WHEN a player enters the lobby, THE Turret_Shop SHALL display a UI panel listing all Turret_Types with their name, description, stats, shopPrice (in Persistent_Coins), and placementCost (in Session_Coins).
2. THE Turret_Shop SHALL visually distinguish between turrets the player has already unlocked and turrets that are still locked.
3. WHEN a player clicks "Buy" on a locked turret and the player has sufficient Persistent_Coins, THE Turret_Shop SHALL unlock that turret for the player and deduct the shopPrice from the player's Persistent_Coins.
4. IF a player clicks "Buy" on a locked turret and the player has insufficient Persistent_Coins, THEN THE Turret_Shop SHALL display a message indicating the player needs more Persistent_Coins.
5. THE Turret_Shop SHALL mark the "Scout Turret" (id 1) as unlocked by default for every player without requiring a purchase.
6. WHEN a turret is successfully purchased, THE Turret_Shop SHALL update the UI to reflect the newly unlocked turret immediately.
7. THE Turret_Shop SHALL display the player's current Persistent_Coins balance in the shop UI.

### Requirement 4: Turret Loadout Selection

**User Story:** As a player, I want to select 3 turrets from my unlocked turrets to bring into a game, so that I can customize my strategy.

#### Acceptance Criteria

1. THE Loadout_Selector SHALL display all turrets the player has unlocked and allow the player to select exactly 3 for the loadout.
2. WHILE the player has fewer than 3 turrets selected, THE Loadout_Selector SHALL prevent the player from starting a game via the area pads.
3. WHEN the player selects a turret already in the loadout, THE Loadout_Selector SHALL deselect that turret from the loadout.
4. THE Loadout_Selector SHALL persist the player's loadout selection across lobby visits within the same server session.
5. IF the player has only 1 unlocked turret (the default Scout Turret), THEN THE Loadout_Selector SHALL auto-fill all 3 loadout slots with that turret.
6. THE Loadout_Selector SHALL allow the player to swap turrets in the loadout by selecting a different unlocked turret to replace a currently selected one.

### Requirement 5: Turret Placement During Gameplay

**User Story:** As a player, I want to place turrets from my loadout onto the map during a game, so that I can defend against enemies.

#### Acceptance Criteria

1. WHILE a game session is active, THE Turret_Placer SHALL display the player's 3 loadout turrets as placement options in the game HUD, showing each turret's placementCost in Session_Coins.
2. WHEN the player selects a loadout turret and clicks on an unoccupied tower grid slot, THE Turret_System SHALL place a Turret_Instance at that position.
3. WHEN a turret is placed, THE Turret_System SHALL deduct the Turret_Type's placementCost in Session_Coins from the player's Session_Coins balance.
4. IF the player clicks on an occupied grid slot, THEN THE Turret_System SHALL reject the placement and display an error message.
5. IF the player has insufficient Session_Coins for the Turret_Type's placementCost, THEN THE Turret_System SHALL reject the placement and display an error message.
6. THE Turret_Placer SHALL show a ghost preview of the turret model and its range circle while the player is choosing a slot.

### Requirement 6: Turret Targeting and Shooting

**User Story:** As a player, I want placed turrets to automatically target and shoot nearby enemies, so that turrets defend the path.

#### Acceptance Criteria

1. WHILE a Turret_Instance is placed on the map, THE Turret_System SHALL scan for enemies within the turret's range every game tick.
2. WHEN one or more enemies are within range, THE Turret_System SHALL target the closest enemy to the turret.
3. WHEN the turret's fire cooldown has elapsed, THE Turret_System SHALL fire a projectile at the targeted enemy and deal damage equal to the turret's damage stat.
4. WHEN a turret fires, THE Turret_System SHALL display a visual projectile traveling from the turret to the target.
5. THE Turret_System SHALL respect each turret's fireRate stat to determine the interval between shots (shots per second).

### Requirement 7: Turret Upgrades During Gameplay

**User Story:** As a player, I want to upgrade placed turrets during a game to increase their stats, so that I can scale my defenses for later waves.

#### Acceptance Criteria

1. WHEN the player clicks on a placed Turret_Instance, THE Turret_System SHALL display an upgrade panel showing the current level, stats, and the Session_Coins cost to upgrade.
2. THE Turret_System SHALL support up to 3 upgrade levels per Turret_Instance, each increasing damage, range, and fire rate by the Turret_Type's upgradeMultipliers.
3. WHEN the player clicks "Upgrade" and has sufficient Session_Coins, THE Turret_System SHALL increase the turret's level by 1, apply the stat multipliers, and deduct the upgrade cost from the player's Session_Coins balance.
4. IF the player clicks "Upgrade" and has insufficient Session_Coins, THEN THE Turret_System SHALL display a message indicating the player needs more Session_Coins.
5. IF the Turret_Instance is already at maximum level (level 3), THEN THE Turret_System SHALL disable the upgrade button and display "Max Level".
6. THE Turret_System SHALL calculate upgrade cost as: the Turret_Type's placementCost multiplied by the target upgrade level (level 2 costs 2x placementCost, level 3 costs 3x placementCost).

### Requirement 8: Loadout Swapping During Gameplay

**User Story:** As a player, I want to swap which turret type I'm placing during a game, so that I can adapt my strategy to different enemy waves.

#### Acceptance Criteria

1. WHILE a game session is active, THE Turret_Placer SHALL display all 3 loadout turrets as selectable buttons in the HUD.
2. WHEN the player clicks a different loadout turret button, THE Turret_Placer SHALL switch the active placement turret to the selected type.
3. THE Turret_Placer SHALL visually highlight the currently active turret in the loadout HUD.
4. WHEN the player switches the active turret while in placement mode, THE Turret_Placer SHALL update the ghost preview to reflect the newly selected turret's model and range.
