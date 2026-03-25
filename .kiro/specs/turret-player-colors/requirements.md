# Requirements Document

## Introduction

In a 2-player session, both players can place turrets on the shared grid, but there is currently no visual way to tell which player owns which turret. This feature assigns each player a distinct color and applies it to their placed turrets (both combat and support types), so ownership is immediately visible at a glance.

## Glossary

- **Color_Palette**: A predefined ordered list of two distinct colors used to visually distinguish Player 1 from Player 2.
- **Player_Color**: The color assigned to a specific player from the Color_Palette based on their join order in the session.
- **Turret_Model**: The 3D model representing a placed turret in the workspace, composed of Base, Body, and other parts.
- **Color_Indicator**: A visible part on the Turret_Model that displays the owning player's Player_Color.
- **Turret_Manager**: The server module responsible for placing, upgrading, and updating turrets.
- **Turret_HUD**: The client-side UI module that handles turret placement preview, loadout buttons, and upgrade panels.
- **Owner_Label**: A text element on the turret's BillboardGui that shows the owning player's name.

## Requirements

### Requirement 1: Player Color Assignment

**User Story:** As a player, I want to be assigned a unique color when the game session starts, so that my turrets are visually distinct from my teammate's turrets.

#### Acceptance Criteria

1. WHEN a game session starts with 2 players, THE Turret_Manager SHALL assign each player a distinct Player_Color from the Color_Palette based on join order.
2. THE Color_Palette SHALL contain exactly 2 visually distinct colors that are easily distinguishable against the game environment.
3. WHEN a player is assigned a Player_Color, THE Turret_Manager SHALL retain that assignment for the entire duration of the game session.
4. IF a game session starts with only 1 player, THEN THE Turret_Manager SHALL assign the first color from the Color_Palette to that player.

### Requirement 2: Turret Color Application

**User Story:** As a player, I want my placed turrets to display my assigned color, so that I can identify my turrets on the map.

#### Acceptance Criteria

1. WHEN a turret is placed, THE Turret_Manager SHALL apply the owning player's Player_Color to the Color_Indicator part of the Turret_Model.
2. THE Color_Indicator SHALL be applied to the Body part of combat turrets and the Body part of support turrets.
3. WHEN a turret is upgraded, THE Turret_Manager SHALL preserve the owning player's Player_Color on the Turret_Model.
4. THE Turret_Model SHALL store the owning player's Player_Color as a model attribute named "OwnerColor" so that clients can read it.

### Requirement 3: Owner Name Display

**User Story:** As a player, I want to see the owner's name on each turret, so that I know exactly who placed it.

#### Acceptance Criteria

1. WHEN a turret is placed, THE Turret_Manager SHALL add an Owner_Label to the turret's BillboardGui displaying the owning player's display name.
2. THE Owner_Label SHALL use the owning player's Player_Color as its text color.
3. WHEN a turret's BillboardGui is updated during upgrade, THE Turret_Manager SHALL preserve the Owner_Label text and color.

### Requirement 4: Placement Preview Color

**User Story:** As a player, I want the turret placement ghost preview to show my assigned color, so that I can see what my turret will look like before placing it.

#### Acceptance Criteria

1. WHILE a player is in placement mode, THE Turret_HUD SHALL tint the ghost preview model with the local player's Player_Color.
2. THE Turret_HUD SHALL retrieve the local player's Player_Color from a model attribute or remote event sent by the server at session start.

### Requirement 5: Color Broadcast to Clients

**User Story:** As a player, I want to see the correct colors on all turrets placed by any player, so that the color system works in multiplayer.

#### Acceptance Criteria

1. WHEN a game session starts, THE Turret_Manager SHALL broadcast each player's Player_Color assignment to all connected clients via a remote event.
2. WHEN a turret is placed, THE Turret_Manager SHALL include the owning player's Player_Color in the TurretPlaced broadcast so all clients can apply the color locally.
3. THE Turret_HUD SHALL store the received player-to-color mapping and use it to identify turret ownership visually.
