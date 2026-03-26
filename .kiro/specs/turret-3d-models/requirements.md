# Requirements Document

## Introduction

This feature defines unique 3D models for each of the 8 turret types in the tower defense game. Models follow a visual progression system where higher-tier (more expensive) turrets have increasingly impressive and elaborate designs. Combat turrets progress from simple mechanical designs to complex, visually stunning constructs, while support turrets have distinct utility-focused aesthetics.

## Glossary

- **Turret_Model**: A 3D Model instance in Roblox representing a turret's visual appearance, stored in ReplicatedStorage
- **Model_Loader**: The system responsible for retrieving and instantiating turret models when placed
- **Visual_Tier**: A classification of visual complexity (Basic, Standard, Advanced, Elite, Legendary) corresponding to turret cost
- **Combat_Turret**: A turret that deals damage to enemies (Scout, Marksman, Rapid, Cannon, Frost, Tesla)
- **Support_Turret**: A turret that provides utility effects rather than damage (Coin Printer, Medic Station)
- **Base_Part**: The primary Part within a turret model that serves as the attachment point for placement
- **Barrel_Part**: The Part within a combat turret model that rotates to aim at enemies
- **Effect_Attachment**: An Attachment point on the model where visual effects (particles, beams) originate

## Requirements

### Requirement 1: Turret Model Storage Structure

**User Story:** As a developer, I want all turret models organized in a consistent location, so that the game can reliably load the correct model for each turret type.

#### Acceptance Criteria

1. THE Model_Loader SHALL store all Turret_Model instances under ReplicatedStorage.TurretModels
2. THE Model_Loader SHALL name each Turret_Model using the format "{TurretName}" matching TurretData names exactly
3. WHEN a turret is placed, THE Model_Loader SHALL clone the corresponding Turret_Model from ReplicatedStorage

### Requirement 2: Model Structure Consistency

**User Story:** As a developer, I want all turret models to follow a consistent internal structure, so that placement and animation systems work uniformly.

#### Acceptance Criteria

1. THE Turret_Model SHALL contain a Base_Part named "Base" as the PrimaryPart
2. FOR Combat_Turret models, THE Turret_Model SHALL contain a Barrel_Part named "Barrel" for aiming
3. THE Turret_Model SHALL contain an Effect_Attachment named "MuzzlePoint" on the Barrel_Part for projectile origin
4. FOR Support_Turret models, THE Turret_Model SHALL contain an Effect_Attachment named "EffectPoint" for visual feedback
5. THE Base_Part SHALL have CanCollide set to true and Anchored set to true when placed

### Requirement 3: Scout Turret Model (Basic Tier)

**User Story:** As a player, I want the free starter turret to look simple and functional, so that I understand it's the entry-level option.

#### Acceptance Criteria

1. THE Scout_Turret model SHALL use a simple cylindrical base with a single rectangular barrel
2. THE Scout_Turret model SHALL use muted gray/metal colors with minimal detail
3. THE Scout_Turret model SHALL have a total part count of 10 or fewer parts
4. THE Scout_Turret model SHALL have approximate dimensions of 4x4x6 studs (width x depth x height)

### Requirement 4: Marksman Turret Model (Standard Tier)

**User Story:** As a player, I want the sniper turret to look precise and long-ranged, so that its role is visually clear.

#### Acceptance Criteria

1. THE Marksman_Turret model SHALL feature an elongated barrel with a scope attachment
2. THE Marksman_Turret model SHALL use dark metallic colors with bronze/copper accents
3. THE Marksman_Turret model SHALL include a tripod-style base suggesting stability
4. THE Marksman_Turret model SHALL have a total part count of 15 or fewer parts

### Requirement 5: Rapid Turret Model (Advanced Tier)

**User Story:** As a player, I want the fast-firing turret to look aggressive and mechanical, so that its high fire rate is visually communicated.

#### Acceptance Criteria

1. THE Rapid_Turret model SHALL feature multiple barrel segments suggesting rapid fire capability
2. THE Rapid_Turret model SHALL include visible ammunition feeds or belt details
3. THE Rapid_Turret model SHALL use industrial red and gunmetal color scheme
4. THE Rapid_Turret model SHALL have a total part count of 20 or fewer parts

### Requirement 6: Cannon Turret Model (Elite Tier)

**User Story:** As a player, I want the heavy damage turret to look powerful and imposing, so that its devastating firepower is visually apparent.

#### Acceptance Criteria

1. THE Cannon_Turret model SHALL feature an oversized barrel with reinforced housing
2. THE Cannon_Turret model SHALL include a heavy armored base with visible plating
3. THE Cannon_Turret model SHALL use military olive/dark green with brass fittings
4. THE Cannon_Turret model SHALL have approximate dimensions of 6x6x8 studs (larger than standard turrets)
5. THE Cannon_Turret model SHALL have a total part count of 25 or fewer parts

### Requirement 7: Frost Turret Model (Elite Tier)

**User Story:** As a player, I want the ice turret to look cold and magical, so that its slowing effect is visually communicated.

#### Acceptance Criteria

1. THE Frost_Turret model SHALL feature crystalline/ice-themed geometry on the barrel and base
2. THE Frost_Turret model SHALL use ice blue and white color palette with transparency effects
3. THE Frost_Turret model SHALL include a ParticleEmitter producing subtle frost/snow particles when idle
4. THE Frost_Turret model SHALL have Neon material accents suggesting magical energy
5. THE Frost_Turret model SHALL have a total part count of 25 or fewer parts

### Requirement 8: Tesla Turret Model (Legendary Tier)

**User Story:** As a player, I want the endgame electric turret to look spectacular and powerful, so that its status as the ultimate combat turret is clear.

#### Acceptance Criteria

1. THE Tesla_Turret model SHALL feature a Tesla coil design with multiple conductor rings
2. THE Tesla_Turret model SHALL include animated electricity effects using Beams or ParticleEmitters
3. THE Tesla_Turret model SHALL use electric blue and chrome/silver color scheme with Neon material
4. THE Tesla_Turret model SHALL include a PointLight with blue color that pulses subtly
5. THE Tesla_Turret model SHALL have the most elaborate design with up to 35 parts
6. THE Tesla_Turret model SHALL include crackling electricity particle effects when idle

### Requirement 9: Coin Printer Model (Support Utility)

**User Story:** As a player, I want the money-generating turret to look like a functional machine, so that its economic purpose is clear.

#### Acceptance Criteria

1. THE Coin_Printer model SHALL feature a mechanical box design with visible gears or mechanisms
2. THE Coin_Printer model SHALL include a coin slot or output chute visual element
3. THE Coin_Printer model SHALL use gold and bronze colors to suggest wealth/coins
4. THE Coin_Printer model SHALL include a SurfaceGui displaying a coin icon or dollar symbol
5. THE Coin_Printer model SHALL have a total part count of 20 or fewer parts

### Requirement 10: Medic Station Model (Support Utility)

**User Story:** As a player, I want the healing turret to look medical and supportive, so that its healing purpose is clear.

#### Acceptance Criteria

1. THE Medic_Station model SHALL feature a medical cross symbol prominently displayed
2. THE Medic_Station model SHALL use white and red color scheme consistent with medical imagery
3. THE Medic_Station model SHALL include a subtle green healing particle effect when active
4. THE Medic_Station model SHALL have a dome or pod-like shape suggesting protection
5. THE Medic_Station model SHALL have a total part count of 15 or fewer parts

### Requirement 11: Model Loading Integration

**User Story:** As a developer, I want the TurretManager to automatically use the correct model for each turret, so that placement works seamlessly.

#### Acceptance Criteria

1. WHEN a turret is placed, THE TurretManager SHALL retrieve the model from ReplicatedStorage.TurretModels by turret name
2. IF a Turret_Model is not found for a turret type, THEN THE TurretManager SHALL log a warning and use a default placeholder model
3. THE TurretManager SHALL set the model's PrimaryPart CFrame to the placement position
4. THE TurretManager SHALL parent the cloned model to Workspace.Turrets

### Requirement 12: Visual Tier Progression

**User Story:** As a player, I want to visually see that more expensive turrets look more impressive, so that progression feels rewarding.

#### Acceptance Criteria

1. THE Turret_Model visual complexity SHALL increase with turret shop price
2. THE Scout_Turret (0 coins) SHALL have the simplest visual design
3. THE Tesla_Turret (10,000,000 coins) SHALL have the most elaborate visual design
4. WHILE comparing any two Combat_Turret models, THE higher-priced turret SHALL have equal or greater part count and visual detail
