# Requirements Document

## Introduction

The Rune System adds a layer of strategic depth to the tower defense game by allowing players to apply elemental runes to placed turrets. Runes are obtained by killing bosses and stored in the player's inventory. During intermission phases, players can apply runes to turrets to modify their stats and grant elemental effects. Combining different rune types on a single turret can produce synergistic bonuses or detrimental clashes, encouraging thoughtful rune placement. Applied runes persist on turrets until game over, at which point all runes are returned to the player's inventory.

The 10 rune types correspond to the existing resource types: Ember, Frost, Spark, Spore, Shadow, Radiance, Stone, Gale, Arcane, and Void.

## Glossary

- **Rune_Inventory**: The per-player collection of runes, tracked as a count per rune type (ids 1–10). Runes persist across the game session and are returned after game over.
- **Rune_Type**: One of the 10 elemental rune types defined in ResourceData (Ember, Frost, Spark, Spore, Shadow, Radiance, Stone, Gale, Arcane, Void).
- **Turret_Instance**: A placed turret on the game map, identified by a unique instance id, owned by a player.
- **Rune_Slot**: The collection of runes currently applied to a specific Turret_Instance. A turret can hold multiple runes.
- **Rune_Effect**: A stat modifier or elemental ability granted to a Turret_Instance by the runes in its Rune_Slot.
- **Synergy**: A beneficial Rune_Effect produced when compatible Rune_Types are combined on a single Turret_Instance.
- **Clash**: A detrimental Rune_Effect produced when incompatible Rune_Types are combined on a single Turret_Instance.
- **Rune_Combination_Table**: A shared data module defining which pairs of Rune_Types produce Synergies and which produce Clashes, along with the resulting stat multipliers and effects.
- **Intermission_Phase**: The period between waves during which players can apply runes to turrets.
- **Game_Over_State**: The state entered when the base is destroyed or the game ends, triggering rune return.
- **Rune_Manager**: The server-side module responsible for tracking rune inventories, validating rune applications, computing combined effects, and handling rune return on game over.
- **Rune_HUD**: The client-side UI that displays the player's rune inventory and provides controls for applying runes to turrets.
- **Combat_Turret**: A Turret_Instance with a non-nil damage stat (not a support turret like Coin Printer or Medic Station).

## Requirements

### Requirement 1: Rune Drop from Boss Kills

**User Story:** As a player, I want to receive runes when bosses are killed, so that I can collect runes to enhance my turrets.

#### Acceptance Criteria

1. WHEN a boss enemy is killed, THE Rune_Manager SHALL award one Rune_Type to each player in the session, selected using the existing weighted drop table from ResourceData.
2. WHEN a rune is awarded, THE Rune_Manager SHALL increment the corresponding Rune_Type count in the receiving player's Rune_Inventory by one.
3. WHEN a rune is awarded, THE Rune_Manager SHALL notify each receiving player's client of the updated Rune_Inventory via a remote event.
4. THE Rune_Manager SHALL use the same round-based weighted probability distribution defined in ResourceData.getDropWeights to determine which Rune_Type is dropped.

### Requirement 2: Rune Inventory Management

**User Story:** As a player, I want to see my rune inventory, so that I can decide which runes to apply to my turrets.

#### Acceptance Criteria

1. THE Rune_Manager SHALL maintain a Rune_Inventory for each player as a table mapping Rune_Type id (1–10) to a non-negative integer count.
2. WHEN a player joins a game session, THE Rune_Manager SHALL initialize the player's Rune_Inventory with zero counts for all 10 Rune_Types.
3. THE Rune_HUD SHALL display all 10 Rune_Types with their current count from the player's Rune_Inventory.
4. WHEN the Rune_Inventory changes, THE Rune_HUD SHALL update the displayed counts within the same frame.

### Requirement 3: Applying Runes to Turrets

**User Story:** As a player, I want to apply runes to my turrets during intermission, so that I can enhance turret performance.

#### Acceptance Criteria

1. WHILE the game is in Intermission_Phase, THE Rune_HUD SHALL enable the rune application controls for the player.
2. WHEN a player selects a Turret_Instance and a Rune_Type to apply, THE Rune_Manager SHALL validate that the player owns the Turret_Instance.
3. WHEN a player requests to apply a rune, THE Rune_Manager SHALL validate that the player's Rune_Inventory contains at least one of the requested Rune_Type.
4. WHEN validation succeeds, THE Rune_Manager SHALL decrement the Rune_Type count in the player's Rune_Inventory by one and add the Rune_Type to the Turret_Instance's Rune_Slot.
5. IF the player does not own the Turret_Instance, THEN THE Rune_Manager SHALL reject the request and return an error message "Not your turret".
6. IF the player's Rune_Inventory has zero count of the requested Rune_Type, THEN THE Rune_Manager SHALL reject the request and return an error message "No runes of this type available".
7. WHEN a rune is applied to a Combat_Turret, THE Rune_Manager SHALL only allow application during the Intermission_Phase.
8. IF a rune application request is made outside the Intermission_Phase, THEN THE Rune_Manager SHALL reject the request and return an error message "Runes can only be applied during intermission".

### Requirement 4: Rune Combination Effects

**User Story:** As a player, I want combining different runes on a turret to produce interesting effects, so that I can experiment with rune strategies.

#### Acceptance Criteria

1. THE Rune_Combination_Table SHALL define for each pair of Rune_Types whether the combination produces a Synergy, a Clash, or a neutral effect.
2. WHEN a rune is added to a Turret_Instance's Rune_Slot, THE Rune_Manager SHALL recompute the combined Rune_Effect by evaluating all pairwise combinations of runes in the Rune_Slot against the Rune_Combination_Table.
3. WHEN a Synergy is detected, THE Rune_Manager SHALL apply a positive stat multiplier (greater than 1.0) to the Turret_Instance's damage, range, or fireRate as defined in the Rune_Combination_Table.
4. WHEN a Clash is detected, THE Rune_Manager SHALL apply a negative stat multiplier (less than 1.0) to the Turret_Instance's damage, range, or fireRate as defined in the Rune_Combination_Table.
5. THE Rune_Manager SHALL compute the final turret stats as: base_stat × upgrade_multiplier × product_of_all_rune_multipliers.
6. WHEN a Turret_Instance has only one Rune_Type in its Rune_Slot (no combinations), THE Rune_Manager SHALL apply the single-rune elemental effect defined for that Rune_Type without any Synergy or Clash modifiers.
7. THE Rune_Combination_Table SHALL be a shared module accessible by both server and client for effect preview.

### Requirement 5: Single-Rune Elemental Effects

**User Story:** As a player, I want each rune type to grant a distinct elemental effect to my turret, so that runes feel meaningful on their own.

#### Acceptance Criteria

1. WHEN an Ember rune is the sole rune on a Turret_Instance, THE Rune_Manager SHALL apply a 1.15x damage multiplier to the Turret_Instance.
2. WHEN a Frost rune is the sole rune on a Turret_Instance, THE Rune_Manager SHALL apply a slow effect (0.7x enemy speed for 2 seconds) to enemies hit by the Turret_Instance.
3. WHEN a Spark rune is the sole rune on a Turret_Instance, THE Rune_Manager SHALL apply a 1.2x fireRate multiplier to the Turret_Instance.
4. WHEN a Spore rune is the sole rune on a Turret_Instance, THE Rune_Manager SHALL apply a poison effect dealing 3 damage per second for 4 seconds to enemies hit by the Turret_Instance.
5. WHEN a Shadow rune is the sole rune on a Turret_Instance, THE Rune_Manager SHALL apply a 1.1x damage multiplier and a 10% chance per hit to deal double damage.
6. WHEN a Radiance rune is the sole rune on a Turret_Instance, THE Rune_Manager SHALL apply a 1.1x range multiplier and a 1.05x damage multiplier to the Turret_Instance.
7. WHEN a Stone rune is the sole rune on a Turret_Instance, THE Rune_Manager SHALL apply a 1.25x range multiplier to the Turret_Instance.
8. WHEN a Gale rune is the sole rune on a Turret_Instance, THE Rune_Manager SHALL apply a 1.15x fireRate multiplier and a 1.05x range multiplier to the Turret_Instance.
9. WHEN an Arcane rune is the sole rune on a Turret_Instance, THE Rune_Manager SHALL apply a 1.2x damage multiplier and a 1.1x fireRate multiplier to the Turret_Instance.
10. WHEN a Void rune is the sole rune on a Turret_Instance, THE Rune_Manager SHALL apply a 1.3x damage multiplier and a 0.9x fireRate multiplier to the Turret_Instance.

### Requirement 6: Rune Persistence Until Game Over

**User Story:** As a player, I want applied runes to stay on turrets for the rest of the game, so that my rune choices have lasting impact.

#### Acceptance Criteria

1. WHEN a rune is applied to a Turret_Instance, THE Rune_Manager SHALL retain the rune in the Turret_Instance's Rune_Slot for the remainder of the game session.
2. THE Rune_Manager SHALL NOT provide any mechanism to remove individual runes from a Turret_Instance during an active game session.
3. WHILE the game session is active, THE Rune_Manager SHALL preserve all Rune_Slot data across wave transitions and intermission phases.

### Requirement 7: Rune Return on Game Over

**User Story:** As a player, I want my runes returned to my inventory when the game ends, so that I do not permanently lose runes.

#### Acceptance Criteria

1. WHEN the game enters Game_Over_State, THE Rune_Manager SHALL iterate over all Turret_Instances and collect all runes from each Rune_Slot.
2. WHEN runes are collected from Turret_Instances, THE Rune_Manager SHALL increment each player's Rune_Inventory by the count of each Rune_Type that was applied to turrets owned by that player.
3. WHEN rune return is complete, THE Rune_Manager SHALL clear all Rune_Slots from all Turret_Instances.
4. WHEN rune return is complete, THE Rune_Manager SHALL notify each player's client of the final Rune_Inventory state.
5. THE Rune_Manager SHALL complete the rune return process before the game session cleanup destroys Turret_Instance data.

### Requirement 8: Rune Application UI

**User Story:** As a player, I want a clear interface to select and apply runes to turrets, so that the rune system is easy to use.

#### Acceptance Criteria

1. WHEN a player clicks on a placed Turret_Instance during Intermission_Phase, THE Rune_HUD SHALL display a rune application panel showing all 10 Rune_Types with their inventory counts.
2. WHEN a Rune_Type button is clicked in the rune application panel, THE Rune_HUD SHALL send an apply-rune request to the server for the selected Turret_Instance and Rune_Type.
3. THE Rune_HUD SHALL display the currently applied runes on the selected Turret_Instance in the rune application panel.
4. THE Rune_HUD SHALL display a preview of the resulting stat changes before the player confirms the rune application.
5. WHEN a Rune_Type has zero count in the player's Rune_Inventory, THE Rune_HUD SHALL display the corresponding button as disabled (greyed out).
6. IF the server rejects a rune application, THEN THE Rune_HUD SHALL display the error message returned by the server for 3 seconds.

### Requirement 9: Rune Visual Feedback on Turrets

**User Story:** As a player, I want to see visual indicators on turrets that have runes applied, so that I can quickly identify enhanced turrets.

#### Acceptance Criteria

1. WHEN a rune is applied to a Turret_Instance, THE Rune_Manager SHALL update the Turret_Instance's model to display a colored glow matching the Rune_Type's color from ResourceData.
2. WHEN multiple runes are applied to a Turret_Instance, THE Rune_Manager SHALL display a blended glow color representing the combination of applied Rune_Types.
3. THE Rune_Manager SHALL update the Turret_Instance's BillboardGui to list the names of applied runes below the turret level label.

### Requirement 10: Rune System Integration with Existing Systems

**User Story:** As a developer, I want the rune system to integrate cleanly with existing turret, economy, and game state systems, so that the codebase remains maintainable.

#### Acceptance Criteria

1. THE Rune_Manager SHALL be implemented as a separate server module (RuneManager.luau) that coordinates with TurretManager, EconomyManager, and GameManager.
2. THE Rune_Combination_Table SHALL be implemented as a shared data module (RuneCombinationData.luau) accessible from both server and client.
3. WHEN the GameManager transitions to Game_Over_State, THE GameManager SHALL invoke the Rune_Manager's rune return function before performing session cleanup.
4. THE Rune_Manager SHALL use the existing remote event infrastructure in the Remotes folder for client-server communication.
5. WHEN a Turret_Instance's stats are modified by runes, THE Rune_Manager SHALL update the model attributes (TurretDamage, TurretRange, TurretFireRate) so the client can read the current effective stats.
