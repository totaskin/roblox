# Turret 3D Model Guide

This guide explains how to structure turret models for proper rotation and targeting behavior.

## Required Models

Create these models in `ReplicatedStorage/TurretModels/`. The model name must match exactly:

| Model Name | Type | Description |
|------------|------|-------------|
| Scout Turret | Combat | Basic balanced turret (free) |
| Marksman Turret | Combat | Long-range sniper |
| Rapid Turret | Combat | Fast-firing shredder |
| Cannon Turret | Combat | Slow, high damage |
| Frost Turret | Combat | Slows enemies |
| Tesla Turret | Combat | Electric arcing bolts |
| Coin Printer | Support | Generates coins (no rotation needed) |
| Medic Station | Support | Heals base (no rotation needed) |

Combat turrets need the full rotating Head structure. Support turrets (Coin Printer, Medic Station) don't rotate, so they just need Base and Body.

## Model Structure

```
TurretModel (Model)
├── Base (Part) ← PrimaryPart, stationary
└── Head (Model) ← Rotates to face enemies
    ├── Body (Model/Part) ← Visual turret body
    └── Barrel (Model/Part) ← Gun barrel
        └── MuzzlePoint (Attachment) ← Where projectiles spawn
```

## Required Components

### Base (Part)
- Set as the model's **PrimaryPart**
- Stays stationary when turret rotates
- Should be at ground level

### Head (Model)
- Contains all parts that rotate to track enemies
- Set its **PrimaryPart** to the center of rotation (usually center of Body)
- The code rotates this entire model to face targets

### Body (Model or Part)
- The main turret body/head visuals
- Place inside Head so it rotates with the turret

### Barrel (Model or Part)
- The gun barrel
- Place inside Head so it rotates with Body
- Can contain a **MuzzlePoint** Attachment for projectile spawn location

### MuzzlePoint (Attachment) - Optional
- Must be inside a BasePart (Part, MeshPart, Wedge, etc.) - NOT directly in a Model
- Marks where projectiles fire from
- If missing, code calculates fire position from barrel tip

**How to add an Attachment:**
1. Select a Part at the barrel tip (inside Barrel model)
2. Right-click → Insert → Insert Object... (or Cmd+I on Mac)
3. Search for "Attachment" and select it
4. Rename to `MuzzlePoint1` (or `MuzzlePoint2` for second barrel)
5. Position the attachment at the exact tip where bullets should spawn

**Dual-Barrel Setup:**
- For turrets with two barrels, add two attachments: `MuzzlePoint1` and `MuzzlePoint2`
- Each attachment must be inside a Part at each barrel tip
- Any name starting with "MuzzlePoint" works (MuzzlePoint, MuzzlePointLeft, etc.)
- The code automatically alternates fire between all MuzzlePoint attachments (1-2-1-2 pattern)

## Setup Steps in Roblox Studio

1. **Create the base structure**
   - Create a Model, name it after your turret (e.g., "Scout Turret")
   - Add a Part for the Base
   - Set Base as PrimaryPart: Right-click Base → "Set as Primary Part"
   - Or: Select the Model, in Properties find PrimaryPart, click the field, then click Base

2. **Create the Head group**
   - Create a Model named "Head" inside your turret
   - Set Head's PrimaryPart to the center part (usually Body's main part)

3. **Add Body and Barrel inside Head**
   - Put all rotating parts inside Head
   - Body = turret head visuals
   - Barrel = gun barrel

4. **Add MuzzlePoint attachment(s)**
   - Select a Part inside Barrel (at the barrel tip) - Attachments must be inside a Part, not a Model
   - Right-click the Part → Insert → Insert Object... (Cmd+I)
   - Search for "Attachment" and select it
   - Rename it to `MuzzlePoint1`
   - Position it at the barrel tip where bullets should spawn
   - For dual barrels: repeat for the second barrel tip Part, name it `MuzzlePoint2`

5. **Set pivot points**
   - Select Head model
   - Press **Cmd+Shift+P** (Mac) or **Ctrl+Shift+P** (Windows) to edit pivot
   - Or: Model tab → Edit Pivot button
   - Drag the pivot gizmo to the rotation center (bottom center of Head, where it sits on Base)
   - Click elsewhere to confirm

6. **Scale and orient**
   - Scale model to appropriate size (use Model:ScaleTo(0.5) for 50%)
   - Ensure turret faces +Z direction (forward) when at rest

## Code Behavior

The TurretManager will:
1. Look for a "Head" child model to rotate
2. If found, rotate Head to face the nearest enemy
3. Fire projectiles from MuzzlePoint (or calculated barrel tip)

## Example Hierarchy

```
Scout Turret (Model, PrimaryPart = Base)
├── Base (Part) - Cylinder, anchored
└── Head (Model, PrimaryPart = BodyCenter)
    ├── BodyCenter (Part) - Hidden, at rotation center
    ├── Body (Model)
    │   ├── Hull (MeshPart)
    │   ├── Armor (MeshPart)
    │   └── Details (MeshPart)
    └── Barrel (Model)
        ├── LeftBarrel (MeshPart)
        │   └── MuzzlePoint1 (Attachment) ← Projectiles fire from here
        ├── RightBarrel (MeshPart)
        │   └── MuzzlePoint2 (Attachment) ← Alternates with MuzzlePoint1
        └── BarrelBase (MeshPart)
```

For single-barrel turrets, just use one MuzzlePoint attachment.

## Troubleshooting

**Turret spawns sideways/upside down:**
- Check that the template model in ReplicatedStorage is oriented correctly
- The code preserves original rotation when spawning

**Parts fly off when rotating:**
- Make sure Body and Barrel are inside Head
- Set Head's PrimaryPart correctly

**Rotation looks wrong:**
- Adjust Head's pivot point to be at the rotation center
- Press **Cmd+Shift+P** (Mac) or **Ctrl+Shift+P** (Windows) to edit pivot
- Or: Model tab → Edit Pivot

**Projectiles spawn in wrong place:**
- Add MuzzlePoint Attachment inside a Part at the barrel tip
- Important: Attachment must be inside a Part, not directly in a Model
- Position the attachment at the exact barrel tip

**MuzzlePoints not found (0 MuzzlePoints in output):**
- Make sure Attachments are inside Parts, not Models
- Check that the model is saved in the .rbxl file (Cmd+S)
- Verify attachment names start with "MuzzlePoint"

**"Model missing PrimaryPart" error:**
- Select your turret Model in Explorer
- Right-click the Base part → "Set as Primary Part"
- Or: Select Model, in Properties find PrimaryPart, click field, then click Base part
