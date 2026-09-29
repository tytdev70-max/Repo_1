# AttachmentSystem

A standalone, host-agnostic weapon-attachment system for Roblox. Formerly the
`AttachmentManager` + gunsmith code embedded in SPH; now a self-contained
provider that SPH consumes through a public API.

**Location:** `ReplicatedStorage.SPH_Assets.Modules.ThirdParty.AttachmentSystem`
**Entry point:** `require(...AttachmentSystem)` (`init.luau`)
**Lines:** ~4,600 across 13 files

---

## Design contract

1. **No blocking at require time.** No module performs a `WaitForChild` at
   module scope. The asset root is resolved lazily on first use, so requiring
   this package can never stall another script's startup. (The old
   `AttachmentManager` did `ReplicatedStorage:WaitForChild("SPH_Assets")` plus
   `:WaitForChild("GunAttachments")` at module scope, from 12 different
   consumers.)
2. **Nothing reaches inside.** SPH calls methods; it never reads an attachment's
   `config`, never walks the asset folder, never builds a `<name>_Equipped`
   node itself.
3. **Host names are configuration, not code.** Every SPH-specific string lives
   in `Config.luau` and can be overridden via `Configure()`.
4. **Safe when unconfigured.** If no attachment root is found, every query
   returns its empty/nil result and `Equip` returns false. The system is inert
   rather than broken.
5. **The gunsmith is opt-in.** Requiring the package constructs no UI.

---

## Architecture

```
init.luau                 public API — the ONLY file a host requires
├── Config.luau           categories, mount map, naming, storage keys, limits
├── ConfigLoader.luau     definition discovery, caching, compatibility
├── Registry.luau         per-model live state, ownership, OnUpdate heartbeats
├── Mounter.luau          clone + Motor6D rig, part replacement, teardown
├── StatModifier.luau     deep copy + ApplyStats pipeline
├── Storage.luau          Tool ⇄ loadout / stat snapshots
├── Queries.luau          every read-only question a host asks
├── Visuals.luau          ADS fade, reticle visibility, muzzle markers
└── Gunsmith.luau         menu orchestration (lazy)
    ├── Gunsmith/View.luau       columns, button states, selection
    ├── Gunsmith/Preview3D.luau  rotating 3D preview
    └── Gunsmith/InputLock.luau  input blocking / menu suppression
```

### Data flow

```
Tool.SavedAttachments ──► Storage.GetSaved ──► ApplyLoadout
                                                  │
                        ConfigLoader.Load ────────┤ (definition + IsCompatible)
                                                  ▼
                                          Mounter.ComputeLayout
                                                  │
                                    ┌─────────────┴──────────────┐
                            (welded=true)                 (welded=false)
                                    ▼                            ▼
                          live Motor6D rig             3D preview (positioned)
                                    │
                                    ▼
                              Registry.Set ──► StatModifier.Apply ──► wepStats
```

---

## Public API

### Setup
| Method | Purpose |
|---|---|
| `Configure(opts)` | Override any host-specific name or folder |
| `IsReady()` / `GetRoot()` | Whether an attachment root resolved (never yields) |

### Definitions
| Method | Returns |
|---|---|
| `LoadConfig(name, category)` | the attachment's `Customization` module |
| `IsValidRequest(name, category)` | structural validation |
| `IsCompatible(name, category, weaponName)` | weapon compatibility |
| `ListAvailable(category)` | all defined attachments |
| `ListAvailableFor(model, category, weaponName)` | those this weapon can take |
| `BuildCatalogue(model, weaponName)` | full menu catalogue |

### Lifecycle
| Method | Purpose |
|---|---|
| `PrepareForEquip(model)` | reset a model to a clean state |
| `Equip(player, weapon, model, name, category)` | fit one attachment → `boolean` |
| `Unequip(model, category)` | remove one |
| `ClearAll(model)` | remove all and release state |
| `ApplyLoadout(player, weapon, model, loadout)` | fit a whole map → `fitted, failed` |
| `ApplySavedLoadout(player, weapon, model)` | fit what the tool has saved |

### Queries
| Method | Answers |
|---|---|
| `GetActive(model)` / `Get(model, cat)` / `Has(model, cat)` | registry access |
| `GetMuzzle(model)` | where bullets leave from |
| `HasMuzzleOverride(model)` / `GetMuzzleConfig(model)` | muzzle state |
| `IsSuppressed(modelOrTool)` | silencer fitted |
| `GetSilencerVolumeMultiplier(model)` | fire-volume scale (1 = none) |
| `GetOverheatConfig(model)` | heat-emitting muzzle profile |
| `GetLaserSource(model)` / `HasLaser(model)` / `GetLaserColor(src)` | laser |
| `GetFlashlightSource(model)` / `HasFlashlight(model)` / `GetFlashlightLights(m)` | flashlight |
| `GetGrip(model, weaponName)` / `HasGrip(model)` | support-hand pose |
| `GetAimPart(model, sightIndex)` | camera aim target |
| `GetReticleConfig(model)` / `GetDepthOfFieldConfig(model)` | optic visuals |
| `GetLeverRingPart(model, name)` | LPVO actuator, optic-first |
| `GetLPVOConfig(model, wepStats)` | magnification profile + fallback |
| `ForEachSightSurfaceGui(model, cb)` | iterate reticle GUIs |

### Visuals
| Method | Purpose |
|---|---|
| `ApplyADSVisibility(model, aiming, wepStats)` | fade housings with aim |
| `SetSightVisibility(model, enabled, isTP)` | toggle reticle GUIs |
| `ClearMuzzleState(model)` | drop the muzzle override marker |

### Persistence
| Method | Purpose |
|---|---|
| `GetSaved(weapon)` / `SetSaved(weapon, map)` / `ClearSaved(weapon)` | loadout |
| `StoreBaseStats(weapon, stats)` / `GetBaseStats(weapon)` | baseline stats |
| `ApplyStats(weapon, model)` | effective stats → table |
| `ReapplyStats(weapon, baseStats, model)` | recompute from a new baseline |
| `LoadWeaponStats(weapon)` | read the weapon's stats module |
| `Forget(weapon)` | release cache for a tool |

### Gunsmith
| Method | Purpose |
|---|---|
| `StartGunsmith(hostOptions)` | build the menu (explicit; not automatic) |
| `GetGunsmith()` | the controller, or nil |

### Diagnostics
`Describe(model)`, `DescribeMuzzle(model)`, `Inspect(model)`

---

## Attachment definition format

An attachment is a Folder under `<root>/<Category>/<Name>/` containing its
parts and a `Customization` ModuleScript:

```lua
return {
    RootPart     = "Body",              -- optional; defaults to first BasePart
    MountOffset  = CFrame.new(),        -- optional offset at the mount point
    IsCompatible = function(weaponName) -- optional; omit = universal
        return weaponName ~= "Knife"
    end,

    VisibleParts  = { "Lens" },         -- force Transparency = 0
    HideGunParts  = { "IronSight" },    -- hide these on the gun
    HideTransparency = 1,               -- optional

    -- Capability flags (queried, never read directly by a host)
    EnableLaser      = false,
    EnableFlashlight = false,
    EnableSilencer   = false,
    SilencerVolumeMultiplier = 1,
    EnableHandPositioning = false,
    HandGripPart     = "Grip",
    HandToPosition   = "Left Arm",
    HandTransitionSpeed = 15,
    HandMatchRotation   = true,

    -- Optic visuals
    ReticleConfig = { DynamicScaling = true, BaseScale = 0.3 },
    DepthOfField  = { FarIntensity = 0, FocusDistance = 5, InFocusRadius = 1 },
    TransparentOnADS = { "Housing" },
    VisibleOnADS     = { "Reticle" },
    LPVOZoom = { Enabled = true, leverRingName = "LeverRing" },
    overHeating = { ... },

    -- Stat patching
    ApplyStats = function(stats)
        stats.recoil.speed *= 0.9
        return stats
    end,

    -- Lifecycle hooks
    OnEquip   = function(player, weapon, node) end,
    OnUnequip = function(model, category, node) end,
    OnUpdate  = function(model, category, deltaTime) end,
}
```

### Adding a category

One line in `Config.Categories`, or nothing at all — an unlisted category
automatically maps to `<Category>Part`. Barrels, handguards, dust covers,
underbarrel launchers and laser modules all work without code changes.

---

## Behaviour notes for SPH integrators

- **The gunsmith is dormant by default.** This preserves the state of the
  repository as extracted (`SPH_Assets.HUD.CustomizeGunGUI` was required by
  nothing). Enable it with `CustomizeGunGUI.StartGunsmith()`.
- `OnUpdate` receives `(weaponModel, category, deltaTime)`. The old
  implementation passed `(nil, nil, dt)`.
- `GetFlashlightSource` now checks attachments **before** the weapon's own
  `Grip.Flashlight`, so an underbarrel light wins over a rail light.
- Tearing down an attachment restores covered gun parts to their **recorded**
  transparency, not to 0.
- Stat snapshots are mirrored to attributes only when JSON-encodable; failure
  to mirror never aborts the computation.
