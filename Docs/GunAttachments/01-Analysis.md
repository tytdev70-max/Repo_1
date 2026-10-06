# GunAttachments Extraction — Phase 1: System Analysis

> Analysis only. Describes the attachment system **as it existed before extraction**
> (commit `eb90787` + GunGiver fixes). Line numbers refer to that state.

## 1. What "the GunAttachment system" is

| Layer | Location | Role |
|---|---|---|
| **Core** | `Modules/Modules/Weapons/Attachments/AttachmentManager.luau` (991 lines) | Single module with module-level state. Mounts attachment models onto gun models, tracks active attachments, applies stat modifiers, answers queries (muzzle, aim part, grip, laser, flashlight, optic configs). |
| **Content** (not in repo, lives in the place file) | `ReplicatedStorage.SPH_Assets.GunAttachments/<Category>/<Name>/` | Parts + a `Customization` ModuleScript (the attachment config). |
| **Persistence** | `Tool.SavedAttachments` (Folder of `StringValue` category → name) and `Tool@SavedAttachmentsJSON` | Per-tool loadout, written by the server (authoritative) and also by the HUD on the client. |
| **Mount points** (gun-model convention) | `<Gun>/<…>/OpticPart \| GripPart \| MuzzlePart \| StockPart / <AttachmentName>` (an `Attachment`) | One `Attachment` per compatible attachment name under each slot part. |
| **Transport** | `GunEvents.ApplyWeaponAttachments` (RemoteEvent), `GunEvents.GetSelectedAttachments` (BindableFunction), `GunEvents.ReloadWeaponStats` (optional RemoteEvent) | Customization menu → server. |

The laser/flashlight/glare/UBGL/fire-selector modules in the same folder are **weapon
features that consume attachment queries**. They are not part of the attachment core;
they stay in SPH (see Phase 2 scope decision).

## 2. Core module anatomy (`AttachmentManager`)

### 2.1 Module-level state (one copy per Lua VM: one on server, one on client)

| Table | Key → Value | Lifetime / cleanup |
|---|---|---|
| `configCache` | `"Category/Name"` → config table | Forever (fine: configs are static). |
| `activeAttachments` | gunModel → { [category] = `{config, model, attachmentName}` } | Purged on `Destroying`, on `ClearAllAttachments`, or lazily by the heartbeat. |
| `originalStatsCache` | Tool → deep copy of base `WeaponStats` | **Never cleared** (`ClearOriginalStats` is empty) → leak per Tool. |
| `weaponOwnership` | gunModel → Tool | Purged with the model. |
| `activeGripStates` | gunModel → true | Written, never read (dead). |
| `processedTools` | — | Declared, never used (dead). |
| `activeUpdaters` / `updaterCount` / `heartbeatConn` | gunModel → {category=true} | Heartbeat is connected only while ≥1 `OnUpdate` attachment is live. |
| `destroyHooked` | gunModel → Destroying connection | Purged with the model. |

### 2.2 Public functions and who calls them

| Function | Behaviour (must be preserved) | Callers |
|---|---|---|
| `LoadAttachmentConfig(name, category)` | `require(GunAttachments[category][name].Customization)` (pcall), cached | HUD CustomizeGunGUI (3D preview) |
| `PrepareForEquip(model)` | Unequip all, destroy every `*_Equipped` Folder, reset to `{}` | Server: GunSetupSystem, GunDropSystem, HolsterSystem. Client: WeaponEquipMod |
| `EquipAttachment(player, tool, model, name, category)` → bool | See §3 | Server: GunSetup, GunDrop (player = nil), Holster, NetworkHandlers. Client: WeaponViewmodel, Module CustomizeGunGUI |
| `UnequipAttachment(model, category)` | `OnUnequip(nil,nil,node)`, restore `HideGunParts` to 0, restore muzzle, destroy node, unregister updater | internal |
| `ClearAllAttachments(model)` | Like Prepare but sets state to `nil`, clears ownership and `ActiveCustomMuzzle` | Server ×4, client ×3 |
| `GetActiveAttachments(model)` → table (never nil) | Raw internal table; consumers read `.config`, `.model` | ServerHelpers ×2, AimingSystemMod, ArmPositionMod, WeaponFireMod, WeaponViewmodel ×2, WeaponEquipMod, ScopeParallax/Activate |
| `HasAttachment(model, category)` | | WeaponFireMod |
| `GetAttachmentAimPart(model, sightIndex)` | Optics node `AimPart<i>` (i>1) else `AimPart` (recursive) | WeaponFrame, ScopeParallax |
| `GetGripHandPosition(model, toolName)` | Underbarrel with `EnableHandPositioning` → `{gripWorldCFrame, handToPosition="Left Arm", transitionSpeed=15, matchRotation=true}` | ServerHelpers, ArmPositionMod |
| `HasGripEquipped(model)` | | ArmPositionMod ×2 |
| `GetActiveMuzzle(model)` | attachment `Muzzle` → `ActiveCustomMuzzle` attribute lookup → `Grip.Muzzle` (non-recursive) | NetworkHandlers, WeaponFireMod, BulletHandler ×2 |
| `GetMuzzleAttachmentConfig` / `GetOverheatConfig` / `GetReticleConfig` / `GetDepthOfFieldConfig` | slot config / sub-tables | BulletHandler, WeaponFireMod ×2, NetworkHandlers, WeaponFrame, AimingSystemMod |
| `ApplyAttachmentADSVisibility(model, aiming, wepStats)` | Tweens `TransparentOnADS`, `VisibleOnADS`, `LPVOZoom.leverRingName` (tween = aimTime/20, same delay) | AimingSystemMod |
| `HasLaserAttachment` / `GetLaserSource` | laser: attachment(`EnableLaser`) → `Grip.Laser` → any descendant `Laser` Attachment | LaserSightMod, WeaponInput, MobileSupport, CustomizeGunGUI, NetworkHandlers |
| `GetFlashlightSource` | **Different precedence**: `Grip.Flashlight` → attachment(`EnableFlashlight`) → any descendant | CameraViewmodelMod ×6, WeaponInput, WeaponLifecycle, MobileSupport, CustomizeGunGUI, NetworkHandlers |
| `CleanupMuzzleState(model)` | Clear `MuzzlePreHidden` + `ActiveCustomMuzzle` | WeaponLifecycle |
| `StoreOriginalStats(tool, stats)` | Deep copy to cache + JSON snapshot attribute `OriginalStats` | WeaponEquipMod ×2, Module CustomizeGunGUI ×2 |
| `RestoreStatsFromTool(tool)` | Cache, else decode `OriginalStats` JSON + re-inject `Flashlight`/`Laser` via `WeaponLighting.GetStatsForSource` | internal |
| `ApplyAttachmentStats(tool, model?)` | Deep-copy base; if `model` nil → **find viewmodel in `workspace.CurrentCamera`**; apply each `config.ApplyStats` (pairs order); write `ModifiedStats` JSON | WeaponEquipMod ×2, Module CustomizeGunGUI ×2 |
| `DebugMuzzleState` | No-op | WeaponEquipMod |
| Never called | `PreHideOriginalMuzzle`, `HasMuzzleOverride`, `HasFlashlightAttachment`, `GetFlashlightLights`, `ClearOriginalStats` | — |

## 3. EquipAttachment — detailed control flow

```
EquipAttachment(player, tool, model, name, category)
 ├─ same name already in slot → return true
 ├─ ownership(model) ≠ tool → PrepareForEquip(model)        (model reused by another tool)
 ├─ ownership = tool; hook model.Destroying → Purge
 ├─ config = LoadAttachmentConfig; IsCompatible(tool.Name) must be true   ← REQUIRED function, errors if missing
 ├─ different attachment in slot → UnequipAttachment
 ├─ slotPart = model:FindFirstChild(SLOT_PART[category], true)            Underbarrel→GripPart, Optics→OpticPart,
 │                                                                         Muzzle→MuzzlePart, Stock→StockPart, else <cat>Part
 ├─ mount = slotPart[name] must be an Attachment
 ├─ old "<name>_Equipped" → Destroy + task.wait(0.05)                     ← YIELDS
 ├─ node = Folder "<name>_Equipped" under slotPart
 ├─ root = config.RootPart or first BasePart in content folder
 ├─ clone every BasePart child → node (CanCollide=false, Anchored=false, Massless=true)
 ├─ Motor6D root: Part0 = mount.Parent, C0 = mount.CFrame * MountOffset
 ├─ Motor6D each other part to root, C0 = rootCF⁻¹ * partCF (authored layout)
 ├─ VisibleParts → Transparency 0 ; HideGunParts → HideTransparency (1)
 ├─ category == "Muzzle": hide original Grip/Base Muzzle host part + descendants (stores
 │   OriginalTransparency_Muzzle / OriginalEnabled_Muzzle attrs, Attachment.Visible=false,
 │   OverriddenByAttachment=true); if node has "Muzzle" → model@ActiveCustomMuzzle = name
 ├─ EnableLaser → disable all Beams in node
 ├─ record {config, model=node, attachmentName}
 ├─ OnUpdate → register heartbeat updater
 └─ OnEquip(player, tool, node) in pcall → return true
```
Early `return false` paths after the Folder is created leave **an empty `_Equipped` folder**
behind (e.g. content folder missing).

## 4. Attachment config schema (inferred from every read site)

| Field | Type | Read by |
|---|---|---|
| `IsCompatible(weaponName) → bool` | **required** fn | Equip |
| `RootPart` | string? | Equip, HUD preview |
| `MountOffset` | CFrame? | Equip, HUD preview |
| `VisibleParts`, `HideGunParts` | {string}? | Equip/Unequip |
| `HideTransparency` | number? (1) | Equip |
| `TransparentOnADS`, `VisibleOnADS` | {string}? | ADS visibility |
| `ApplyStats(stats) → stats` | fn? | stats pipeline |
| `OnEquip(player, tool, node)`, `OnUnequip(nil, nil, node)`, `OnUpdate(nil, nil, dt)` | fn? | lifecycle |
| `EnableLaser`, `EnableFlashlight`, `EnableSilencer`, `SilencerVolumeMultiplier` | flags | Equip, WeaponEquipMod, WeaponFireMod, PlayerFireSystem, WeaponAnimation |
| `EnableHandPositioning`, `HandGripPart`, `HandToPosition`, `HandTransitionSpeed`, `HandMatchRotation` | grip | GetGripHandPosition |
| `overHeating` | table | GetOverheatConfig |
| `ReticleConfig`, `DepthOfField`, `LPVOZoom` | tables | optics queries, ServerHelpers, ArmPositionMod |

The callback signatures (`nil, nil` placeholders included) are a **frozen contract**: the
`Customization` modules are content in the place file and cannot be edited from here.

## 5. Data & control flows

### 5.1 Customize → apply (two parallel paths)
```
[HUD/CustomizeGunGUI (LocalScript)]                      [Weapons/UI/CustomizeGunGUI (module)]
 selection → 3D preview (duplicated mount math)            ConfirmButton click:
 ConfirmButton click:                                        GetSelectedAttachments:Invoke()  ← reads HUD selection
   writes Tool.SavedAttachments locally (client only)        FireServer(selected)             ← correct shape
   FireServer(tool, attachments)  ← WRONG SHAPE              ClearAll + Equip on viewmodel
                                                             re-toggle laser/flashlight, StoreOriginalStats,
                                                             ApplyAttachmentStats → walkspeed/FOV/springs
                         ▼
[Server NetworkHandlers: ApplyWeaponAttachments(player, selected)]
   typeof(selected) ~= "table" → return   (drops the HUD call silently)
   ClearAll(TP model) → rebuild Tool.SavedAttachments → Equip each (whitelist ATTACHMENT_CATEGORIES, ≤64 chars)
   RefreshPlayerArmReplication
```

### 5.2 Loadout re-application (same loop copy-pasted 5×)
`Tool.SavedAttachments` → `EquipAttachment` per StringValue in:
GunSetupSystem.EquipGun (TP model), GunDropSystem.SpawnGun (drop model, player=nil),
HolsterSystem (holster model), NetworkHandlers (apply), WeaponViewmodel.ApplySavedAttachmentsToViewmodel (client VM).

### 5.3 Stats
```
Equip (client): wepStats = require(WeaponStats)   (shared cached table)
  StoreOriginalStats(tool, wepStats) → ApplyAttachmentStats(tool, nil)   (model from camera)
  ... viewmodel built ...
  if SavedAttachments: StoreOriginalStats again → ApplyAttachmentStats(tool, gun)
```
Results are deep copies, so `ApplyStats` cannot corrupt the shared module table. Order of
`ApplyStats` is `pairs` order: **non-deterministic** when two attachments touch the same field.

### 5.4 Suppression lookups that bypass the manager (duplicated)
`PlayerFireSystem` (server) and `WeaponAnimation.PlayRepSound` (client) read
`SavedAttachments.Muzzle` and `require` the Customization module directly to check `EnableSilencer`.

## 6. Hidden coupling & implicit assumptions

1. **Asset path hard-coded** at require time: `ReplicatedStorage.SPH_Assets.GunAttachments` (`WaitForChild`, infinite yield if absent).
2. **SPH module dependency**: `require(script.Parent.WeaponLighting)` (only for JSON-snapshot restore).
3. **Viewmodel discovery**: `workspace.CurrentCamera:FindFirstChildWhichIsA("Model").Weapon:FindFirstChildWhichIsA("Model")`.
4. **Gun model conventions**: `Grip`/`Base` root, `Grip.Muzzle`, `Grip.Laser`, `Grip.Flashlight`, slot part names, `AimPart[n]`.
5. **Instance-name protocol**: `<name>_Equipped` folders are treated as attachment nodes (and destroyed by prefix match anywhere in the model).
6. **Attribute protocol**: `ActiveCustomMuzzle`, `OriginalTransparency_Muzzle`, `OriginalEnabled_Muzzle`, `MuzzlePreHidden`, `OverriddenByAttachment`, `OriginalStats`, `ModifiedStats`, `SavedAttachmentsJSON`.
7. **Raw-state exposure**: `GetActiveAttachments` returns the internal table; mutation by consumers would corrupt state.
8. **Per-VM state**: server and client each own an independent registry; nothing synchronizes them except `SavedAttachments`.
9. **R6 arm names** (`"Left Arm"`) as grip defaults.
10. **Category whitelist duplicated**: server `Constants.ATTACHMENT_CATEGORIES`, slot→part mapping duplicated in HUD preview.

## 7. Risks / breakpoints found

| # | Issue | Impact |
|---|---|---|
| R1 | HUD `FireServer(tool, attachments)` shape mismatch | Server ignores it; only works because the module handler fires a second, correct call |
| R2 | `task.wait(0.05)` inside Equip | Equip yields; loops over loadouts interleave with other code |
| R3 | `originalStatsCache` never cleared | Memory leak per Tool |
| R4 | Non-deterministic `ApplyStats` order | Stat results can differ between server/client/sessions |
| R5 | Empty `_Equipped` folder left on failure paths | Clutter; later prefix-purge hides it |
| R6 | `IsCompatible` missing → hard error (not pcall'd) | One bad config breaks equip |
| R7 | `HideGunParts` restore forces Transparency 0 (not original) | Parts authored semi-transparent are changed |
| R8 | Raw table exposure (`GetActiveAttachments`) | Accidental mutation |
| R9 | Camera-based model fallback in stats | Wrong model if camera has other Models |
| R10 | `WaitForChild("GunAttachments")` at require | Requiring module blocks forever if folder missing |

## 8. Requirements the replacement must meet

* Identical observable behaviour for every function in §2.2 (including precedence quirks of laser vs flashlight and muzzle fallbacks).
* Same instance/attribute protocol (§6.5/6.6): other scripts and the content rely on it.
* Same config schema and callback signatures (§4).
* Works in both server and client VMs independently.
* No yield on `require`.
* SPH remains functional at every migration step.
