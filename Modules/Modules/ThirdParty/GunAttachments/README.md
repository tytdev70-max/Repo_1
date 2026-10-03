# GunAttachments

Standalone weapon-attachment system for Roblox. Self-contained (no requires outside
this folder), instance-based (no global state), and configured entirely through
options and hooks. Version **1.0.0**.

## Install

Place the `GunAttachments` folder as a ModuleScript (`init.luau`) with its children in
`ReplicatedStorage` (it is used on both server and client).

```lua
local GunAttachments = require(ReplicatedStorage.GunAttachments)
local attachments = GunAttachments.new({
    contentRoot = ReplicatedStorage.Assets.GunAttachments, -- or a function returning it
})
```
Create **one system per Lua VM** (one on the server, one on the client) and share it.
Each system is independent; server and client do not sync with each other. The loadout
saved on the Tool (see below) is what keeps them consistent.

## Content layout

```
<contentRoot>/
  Optics/RedDot/            Folder
      Body                  MeshPart  (root by default: first MeshPart, else first BasePart)
      Lens                  Part      (welded relative to the root as authored)
      AimPart, AimPart2     Parts     (optional, used by GetAimPart)
      Customization         ModuleScript → returns the config table
```

Gun models need a mount part per slot (`OpticPart`, `GripPart`, `MuzzlePart`,
`StockPart` by default). Under it, add one `Attachment` named after **each** compatible
attachment (e.g. `OpticPart/RedDot`). The gun's own muzzle is `Grip/…/Muzzle`.

## Config (the `Customization` module)

```lua
return {
    IsCompatible = function(weaponName) return true end, -- optional (default: compatible)
    RootPart = "Body",                -- optional
    MountOffset = CFrame.new(),       -- optional
    VisibleParts = { "Lens" },        -- forced visible on mount
    HideGunParts = { "IronSight" },   -- hidden on the gun while mounted (restored after)
    HideTransparency = 1,
    TransparentOnADS = { "Body" }, VisibleOnADS = { "Reticle" },
    ApplyStats = function(stats) stats.recoil.speed *= 0.9; return stats end,
    OnEquip = function(owner, tool, node) end,
    OnUnequip = function(_, _, node) end,
    OnUpdate = function(_, _, dt) end,      -- runs on Heartbeat while mounted
    -- free-form fields are allowed and queryable (EnableLaser, EnableSilencer, …)
}
```

## Options

| Option | Default | |
|---|---|---|
| `contentRoot` | — | Instance or `() -> Instance?` |
| `configModuleName` | `"Customization"` | |
| `slots` | Optics/Underbarrel/Muzzle/Stock | `{ name, mountPart, order, role?, overridesMuzzle? }`. `order` is the ApplyStats order. Roles: `optic`, `grip`, `muzzle` |
| `allowUnknownSlots` | `false` | Unknown slot `X` mounts on `XPart` |
| `modelRootNames` | `{"Grip","Base"}` | Gun root part names (first is used for built-in Muzzle/Laser/Flashlight) |
| `nodeSuffix` | `"_Equipped"` | Name suffix of mounted node folders |
| `loadout` | `SavedAttachments`, `SavedAttachmentsJSON`, 64 | Tool persistence names, max name length |
| `stats` | snapshots on, `OriginalStats`/`ModifiedStats` | JSON snapshots on the Tool |
| `hooks.resolveModel(tool)` | — | Model to use when `ComputeStats` gets no model |
| `hooks.onSnapshotRestored(tool, stats)` | — | Patch non-JSON fields after a snapshot decode |
| `hooks.isCompatible(config, tool, slot, name)` | — | Return true/false to override, nil to defer |
| `hooks.filterLoadout(tool, loadout)` | — | Server policy (unlocks, bans) applied in `SanitizeLoadout` |
| `services` | Roblox services | `heartbeat`, `tween(part, t, delay, goals)`, `http`, `newInstance`, `identityCFrame`, `require` (for tests) |
| `log` | `warn` | `false` to silence, or `{ warn = fn, debug = fn }` |

## API

### Content
- `LoadConfig(slot, name) → config?`, `GetContentFolder(slot, name)`
- `GetSlotPartName(slot)`, `IsValidSlot(slot)`, `GetSlots()`, `GetSlotForRole(role)`

### Lifecycle
- `Equip(model, tool, slot, name, owner?) → (ok, reason?)`
- `Unequip(model, slot)`
- `ResetModel(model)`: unequip all and keep the model tracked
- `ClearModel(model)`: unequip all and forget the model
- `ApplyLoadout(model, tool, owner?, loadout?) → { [slot]: ok }`: rebuild from the tool's saved loadout

### Queries
- `GetActive(model) → { [slot]: Record }` (frozen copy). Each Record has `slot, attachmentName, config, node, model (= node), tool`
- `GetRecord`, `Has`, `IsTracked`, `GetOwner`, `GetSlotConfig`, `GetConfigField(model, slot, field)`, `AnyActiveFlag(model, field)`
- `GetAimPart(model, sightIndex)`, `GetGripData(model)`, `HasHandGrip(model)`
- `GetActiveMuzzle(model)`, `GetLaserSource(model)`, `GetFlashlightSource(model)`
- `ApplyADSVisibility(model, aiming, aimTime?)`, `CleanupMuzzleState(model)`, `PreHideOriginalMuzzle(model)`

### Stats
- `SetBaseStats(tool, stats)`: stores a deep copy
- `GetBaseStats(tool)`, `ForgetBaseStats(tool)`
- `ComputeStats(tool, model?) → stats`: base + every mounted `ApplyStats`, in slot order

### Loadout
- `GetLoadout(tool)`, `HasLoadout(tool)`, `SetLoadout(tool, loadout)`
- `SanitizeLoadout(raw, tool?)`: always run this on RemoteEvent input
- `LoadoutHasFlag(tool, field, slot?)`: config flag check without a mounted model

### Signals and teardown
- `Equipped(model, record)`, `Unequipped(model, slot, name)`, `ModelCleared(model)`
- `Destroy()`

## Instance and attribute protocol

Other code can observe these names, so treat them as stable:
- `<MountPart>/<Name>_Equipped`: Folder holding the mounted parts
- `AttachmentMotor_Root_<Name>`, `AttachmentMotor_<Part>`: Motor6Ds
- On the model: `ActiveCustomMuzzle`
- On the muzzle host: `OriginalTransparency_Muzzle`, `OriginalEnabled_Muzzle`, `MuzzlePreHidden`, `OverriddenByAttachment`
- On hidden gun parts: `GunAttachments_OriginalTransparency`
- On the Tool: `SavedAttachments` (Folder of StringValues), `SavedAttachmentsJSON`, `OriginalStats`, `ModifiedStats`

## Tests

`python3 Tests/GunAttachments/run.py <luau> [luau-analyze]` runs the isolation suite
with the Luau CLI and Roblox doubles (`Tests/GunAttachments/mocks.luau`).
