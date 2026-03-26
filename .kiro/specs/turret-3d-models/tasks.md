# Implementation Plan: Turret 3D Models

## Overview

This plan implements the code changes needed to support artist-created 3D turret models in TurretManager. The actual 3D models will be created manually in Roblox Studio. Code changes include: adding a model loader with fallback to procedural generation, updating projectile firing to use MuzzlePoint attachments, and creating property-based tests for model structure validation.

## Tasks

- [x] 1. Add model loading infrastructure to TurretManager
  - [x] 1.1 Add loadTurretModel helper function
    - Create function that looks up model in `ReplicatedStorage.TurretModels` by turret name
    - Return cloned model if found, nil if not found
    - Log warning when TurretModels folder or specific model not found
    - _Requirements: 1.1, 1.2, 1.3, 11.1, 11.2_

  - [x] 1.2 Add setupLoadedModel helper function
    - Position model using PrimaryPart CFrame
    - Set standard turret attributes (TurretInstanceId, TurretTypeId, TurretLevel, etc.)
    - Apply owner color to Body part
    - Add BillboardGui and ProximityPrompt (reuse existing logic)
    - Parent model to Workspace.Turrets folder
    - _Requirements: 2.1, 2.5, 11.3, 11.4_

  - [x] 1.3 Refactor buildTurretModel to try loading model first
    - Rename existing procedural code to buildProceduralModel
    - Update buildTurretModel to call loadTurretModel first
    - Fall back to buildProceduralModel if model not found
    - _Requirements: 11.1, 11.2_

- [x] 2. Update projectile firing to use MuzzlePoint attachment
  - [x] 2.1 Update fireProjectile spawn position logic
    - Look for MuzzlePoint attachment on Barrel part
    - Use attachment WorldPosition if found
    - Fall back to existing barrel position calculation if not found
    - _Requirements: 2.2, 2.3_

  - [x] 2.2 Write property test for MuzzlePoint attachment lookup
    - **Property 2: Combat Turret Model Structure**
    - **Validates: Requirements 2.1, 2.2, 2.3**

- [x] 3. Checkpoint - Verify model loading works
  - Ensure all tests pass, ask the user if questions arise.

- [x] 4. Create property-based tests for model structure validation
  - [x] 4.1 Create TurretModelTestHarness with mock model structures
    - Define mock model data for each turret type
    - Include part count validation functions
    - Include structure validation functions
    - _Requirements: 2.1, 3.3, 4.4, 5.4, 6.5, 7.5, 8.5, 9.5, 10.5_

  - [x] 4.2 Write property test for model naming matches TurretData
    - **Property 1: Model Naming Matches TurretData**
    - **Validates: Requirements 1.2**

  - [x] 4.3 Write property test for combat turret model structure
    - **Property 2: Combat Turret Model Structure**
    - Verify Base, Body, Barrel parts and MuzzlePoint attachment
    - **Validates: Requirements 2.1, 2.2, 2.3**

  - [x] 4.4 Write property test for support turret model structure
    - **Property 3: Support Turret Model Structure**
    - Verify Base, Body parts and EffectPoint attachment
    - **Validates: Requirements 2.1, 2.4**

  - [x] 4.5 Write property test for Base part properties
    - **Property 4: Base Part Properties After Placement**
    - **Validates: Requirements 2.5**

  - [x] 4.6 Write property test for model lookup by name
    - **Property 5: Model Lookup By Name**
    - **Validates: Requirements 1.1, 11.1**

  - [x] 4.7 Write property test for part count tier limits
    - **Property 8: Part Count Respects Tier Limits**
    - **Validates: Requirements 3.3, 4.4, 5.4, 6.5, 7.5, 8.5, 9.5, 10.5**

  - [x] 4.8 Write property test for visual complexity progression
    - **Property 9: Visual Complexity Increases With Price**
    - **Validates: Requirements 12.1, 12.4**

- [x] 5. Checkpoint - Verify all property tests pass
  - Ensure all tests pass, ask the user if questions arise.

- [ ] 6. (Manual) Create 3D turret models in Roblox Studio
  - [ ] 6.1 Create Scout Turret model
    - Simple cylindrical base with rectangular barrel
    - Muted gray/metal colors, ≤10 parts
    - Include Base (PrimaryPart), Body, Barrel, MuzzlePoint attachment
    - _Requirements: 3.1, 3.2, 3.3, 3.4_

  - [ ] 6.2 Create Marksman Turret model
    - Elongated barrel with scope, tripod-style base
    - Dark metallic with bronze accents, ≤15 parts
    - _Requirements: 4.1, 4.2, 4.3, 4.4_

  - [ ] 6.3 Create Rapid Turret model
    - Multiple barrel segments, ammunition feed details
    - Industrial red and gunmetal, ≤20 parts
    - _Requirements: 5.1, 5.2, 5.3, 5.4_

  - [ ] 6.4 Create Cannon Turret model
    - Oversized barrel, heavy armored base
    - Military olive/dark green with brass, ≤25 parts
    - _Requirements: 6.1, 6.2, 6.3, 6.4, 6.5_

  - [ ] 6.5 Create Frost Turret model
    - Crystalline/ice geometry, ParticleEmitter for frost
    - Ice blue/white with Neon accents, ≤25 parts
    - _Requirements: 7.1, 7.2, 7.3, 7.4, 7.5_

  - [ ] 6.6 Create Tesla Turret model
    - Tesla coil design with conductor rings
    - Electric blue/chrome with Neon, PointLight, electricity effects, ≤35 parts
    - _Requirements: 8.1, 8.2, 8.3, 8.4, 8.5, 8.6_

  - [ ] 6.7 Create Coin Printer model
    - Mechanical box with gears, coin slot/chute
    - Gold/bronze colors, SurfaceGui with coin icon, ≤20 parts
    - Include EffectPoint attachment instead of MuzzlePoint
    - _Requirements: 9.1, 9.2, 9.3, 9.4, 9.5_

  - [ ] 6.8 Create Medic Station model
    - Medical cross symbol, dome/pod shape
    - White/red colors, green healing particle effect, ≤15 parts
    - Include EffectPoint attachment instead of MuzzlePoint
    - _Requirements: 10.1, 10.2, 10.3, 10.4, 10.5_

  - [ ] 6.9 Create TurretModels folder in ReplicatedStorage
    - Add all 8 turret models to ReplicatedStorage.TurretModels
    - Verify each model name matches TurretData exactly
    - _Requirements: 1.1, 1.2_

- [x] 7. Final checkpoint - Verify integration
  - Ensure all tests pass, ask the user if questions arise.
  - Manually test turret placement loads correct models
  - Verify fallback to procedural generation when models missing

## Notes

- Tasks marked with `*` are optional and can be skipped for faster MVP
- Task 6 (3D model creation) is manual work in Roblox Studio - not automatable by code agent
- Property tests use mock model data since actual models are created manually
- The code changes (Tasks 1-2) enable model loading while preserving existing procedural fallback
