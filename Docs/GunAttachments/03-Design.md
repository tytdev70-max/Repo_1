# GunAttachments Extraction — Phase 3: Standalone Module Design

## 1. Principles

* **Zero SPH knowledge.** The package never requires anything outside itself and never
  hard-codes `SPH_Assets`, viewmodel paths, or SPH modules. Everything game-specific is an
  *option* or a *hook*.
* **Instance-based systems.** `GunAttachments.new(options)` returns an independent `System`.
  Multiple systems can coexist (e.g. a separate one for a shop preview). No module-level state.
* **Lazy Roblox access.** No `WaitForChild`, no service calls at require time → requiring never
  yields and the package is testable outside Roblox (services are injectable).
* **Behaviour-compatible.** Default options reproduce the old SPH conventions exactly.
* **Read-only exposure.** Queries return records/copies, never the internal tables.

## 2. Package layout (`Modules/Modules/ThirdParty/GunAttachments/`)

| File | Responsibility | Roblox APIs |
|---|---|---|
| `init.luau` | Public entry: `new`, `Defaults`, `Version`, re-exports `Stats`/`Loadout` helpers | — |
| `Types.luau` | Exported Luau types (Options, AttachmentConfig, Record, Loadout, …) | — |
| `Defaults.luau` | Default options (slot table, names, attributes) + `merge` | — |
| `Util.luau` | `deepCopy`, `safeCall`, logger, `findDescendant` | — |
| `Signal.luau` | Minimal connect/fire/disconnect signal | — |
| `Slots.luau` | Slot table: validation, ordering, mount-part names | — |
| `Registry.luau` | Content lookup (`contentRoot/<Slot>/<Name>/<ConfigModule>`), require + cache, config normalisation | `require` |
| `Stats.luau` | Base-stats store (strong keys, released on Tool.Destroying), deterministic modifier pipeline, JSON snapshots | HttpService (injected) |
| `Loadout.luau` | Tool loadout read/write/sanitise (`SavedAttachments` folder + JSON attribute) | Instance |
| `Mounting.luau` | Clone content, weld with Motor6D, show/hide parts, original-transparency bookkeeping | Instance, CFrame |
| `Muzzle.luau` | Original-muzzle override / restore / pre-hide protocol | Instance |
| `Scheduler.luau` | Per-record `OnUpdate` driven by an injectable heartbeat signal | RunService (injected) |
| `System.luau` | The `System` class: registry of active attachments, lifecycle, queries, signals | — |

## 3. Options

```lua
GunAttachments.new({
    contentRoot      = Instance | () -> Instance?,   -- folder with <Slot>/<Name>/  (required for mounting)
    configModuleName = "Customization",
    slots = {                                         -- order = stats application order
        { name = "Optics",      mountPart = "OpticPart",  order = 1 },
        { name = "Underbarrel", mountPart = "GripPart",   order = 2 },
        { name = "Muzzle",      mountPart = "MuzzlePart", order = 3, overridesMuzzle = true },
        { name = "Stock",       mountPart = "StockPart",  order = 4 },
    },
    allowUnknownSlots = false,          -- if true, unknown slot "X" mounts on "XPart" (old fallback)
    modelRootNames    = { "Grip", "Base" },
    nodeSuffix        = "_Equipped",
    loadout = { folderName = "SavedAttachments", jsonAttribute = "SavedAttachmentsJSON", maxNameLength = 64 },
    stats   = { writeSnapshots = true, originalAttribute = "OriginalStats", modifiedAttribute = "ModifiedStats" },
    hooks = {
        resolveModel      = function(tool) -> Model?,          -- used by ComputeStats(tool) without model
        onSnapshotRestored = function(tool, stats) -> (),       -- patch non-JSON fields after decode
        isCompatible      = function(config, tool, slot, name) -> boolean?,  -- override/extend
        filterLoadout     = function(tool, loadout) -> Loadout, -- server-side policy (e.g. unlocks)
    },
    services = { heartbeat = RBXScriptSignal, tween = fn, http = HttpService },  -- injectable
    log = { warn = fn, debug = fn? },   -- default warn prefixed "[GunAttachments]"
})
```

## 4. Public API (`System`)

### Content
| Method | Description |
|---|---|
| `LoadConfig(slot, name) → config?` | Cached, pcall-required, normalised |
| `GetSlotPartName(slot) → string?` | Mount part name for a slot |
| `IsValidSlot(slot) → boolean` / `GetSlots() → {SlotDef}` | |

### Lifecycle (per gun model)
| Method | Description |
|---|---|
| `Equip(model, tool, slot, name, owner?) → (ok, reason?)` | Mount; `owner` is passed to `OnEquip` as the player |
| `Unequip(model, slot)` | |
| `ResetModel(model)` | Unequip all + purge stray nodes, keep model tracked (old `PrepareForEquip`) |
| `ClearModel(model)` | Unequip all + forget model (old `ClearAllAttachments`) |
| `ApplyLoadout(model, tool, owner?, loadout?) → {[slot]: ok}` | Reset then equip every entry (default: tool's saved loadout) |

### Queries
`GetActive(model) → {[slot]: Record}` (copy), `GetRecord(model, slot)`, `Has(model, slot)`,
`GetSlotConfig(model, slot)`, `GetConfigField(model, slot, field)`, `AnyActiveFlag(model, field)`,
`GetAimPart(model, sightIndex)`, `GetGripData(model)`, `HasHandGrip(model)`,
`GetActiveMuzzle(model)`, `GetLaserSource(model)`, `GetFlashlightSource(model)`,
`ApplyADSVisibility(model, aiming, aimTime?)`, `CleanupMuzzleState(model)`, `PreHideOriginalMuzzle(model)`.

`Record = { slot, attachmentName, config, model (= node Folder), node, tool }`. The `model`
field name is kept for compatibility with existing consumers.

### Stats
| Method | Description |
|---|---|
| `SetBaseStats(tool, stats)` | Deep-copies; optional JSON snapshot |
| `GetBaseStats(tool) → stats?` | Cache → snapshot decode (+ `onSnapshotRestored`) |
| `ComputeStats(tool, model?) → stats?` | Copy of base with every active `ApplyStats` applied **in slot order** |

### Loadout (persistence on the Tool)
`GetLoadout(tool) → {[slot]: name}`, `SetLoadout(tool, loadout)`,
`SanitizeLoadout(raw) → Loadout` (type/slot/length checks + `filterLoadout`),
`LoadoutHasFlag(tool, field) → boolean` (config lookup without needing a mounted model).

### Signals
`Equipped(model, record)`, `Unequipped(model, slot, name)`, `ModelCleared(model)`.

### Teardown
`Destroy()` — clears all models, disconnects scheduler and destroy hooks.

## 5. Static helpers (no system needed)
`GunAttachments.Stats.deepCopy`, `GunAttachments.Loadout.sanitize(raw, slots, maxLen)`.

## 6. Behavioural contract vs. old manager

| Aspect | Old | New |
|---|---|---|
| Equip yield | `task.wait(0.05)` | No yield (Destroy is synchronous) |
| Failure after node creation | Empty folder left | Node removed |
| Missing `IsCompatible` | Error | Treated as compatible (+ warning once) |
| `HideGunParts` restore | Transparency 0 | Original transparency (remembered at hide time) |
| Stats order | `pairs` order | Slot `order` (deterministic) |
| Base-stats cache | Strong, leaks | Strong (weak Instance keys are unreliable in Roblox); released on `Tool.Destroying` |
| Camera fallback | Hard-coded | `hooks.resolveModel` (SPH adapter provides the old behaviour) |
| Everything else | — | Identical (precedence, attributes, names, callback signatures) |

## 7. SPH integration shape
```lua
-- Weapons/Attachments/SPHAttachments.luau
local GunAttachments = require(Modules.ThirdParty.GunAttachments)
return GunAttachments.new({ contentRoot = function() return SPH_Assets:FindFirstChild("GunAttachments") end,
                            hooks = { resolveModel = viewmodelFromCamera, onSnapshotRestored = reinjectLighting } })
```
`SPHAttachments.Get()` returns the per-VM singleton; consumers call the new API on it.
