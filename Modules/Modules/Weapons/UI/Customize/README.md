# CustomizeUI

The modular weapon customization menu for SPH. It replaces the 1141-line `HUD/CustomizeGunGUI` controller.

- **Slots and options are data-driven:** nothing about attachments is hard-coded in the UI.
- **Layout, theme, text and behaviour are configurable.**
- **The whole view can be replaced.**

## Files
| File | Role | Roblox-free / tested |
|---|---|---|
| `init.luau` | `CustomizeUI.start(options)` / `stop()` / `get()` | – |
| `Config.luau` | All options and their defaults; deep-merged | ✔ |
| `Selection.luau` | Selection model: toggle/select/clear/revert, dirty state, rules hook | ✔ |
| `Catalog.luau` | Which slots and options a weapon offers | ✔ |
| `Controller.luau` | State machine and orchestration (SPH-agnostic, dependencies injected) | – |
| `View/` | Default view (procedural layout) plus components | – |
| `Preview.luau` | 3D viewport: orbit, zoom, near-clip guard, mounting for any slot | – |
| `Environment.luau` | Input, WalkSpeed, inventory, mouse, blur and prompt side effects | – |
| `Bridge.luau` | **The only SPH-aware file**: events, remote, prompts, character lifecycle | – |

## Adding attachment capacity (no UI code)
1. **New attachment in an existing slot:** add `SPH_Assets/GunAttachments/<Slot>/<Name>/` (parts plus a `Customization` module). Then put an `Attachment` named `<Name>` under the slot's mount part on each gun that should accept it.
2. **New attachment type (slot):** add a row to `SLOTS` in `Weapons/Attachments/SPHAttachments.luau`:
   ```lua
   { name = "Laser", mountPart = "LaserPart", order = 7 },
   ```
   That one row covers everything:
   - the server whitelist;
   - mounting;
   - stats order;
   - the 3D preview;
   - a new tab in the menu, for guns that have `LaserPart` and fitting content.
3. **Already-defined extra slots:**
   - `Barrel`: muzzle role, an extended muzzle category.
   - `Magazine`.
   - `SecondaryOptic`: optic role, dual sights. Its aim parts follow the primary optic's in the sight-switch cycle.

### Optional per-attachment metadata (config fields or folder attributes)
- `DisplayName`: the card label. Defaults to the folder name.
- `Icon`: an image id shown on the card.
- `Description`: reserved for custom views.
- `ConflictsWith = { "Slot", "Slot/Name" }`: picking it removes conflicting picks (newest pick wins). The server enforces the same rule.

### Capacity
- **Per weapon:** a `MaxAttachments` number attribute on the Tool.
- **Global:** `rules.maxAttachments` in `SPHAttachments`.

The menu shows `n / max`. A pick beyond the limit is refused with a message, and the server applies the same limit in `SanitizeLoadout`.

## Configuring the menu
Configuration lives in `HUD/CustomizeGunGUI` (the LocalScript):
```lua
CustomizeUI.start({
    behaviour = { showUnavailable = true, closeKeys = { "Escape" } },
    slots = {                       -- presentation per slot name
        Magazine = { label = "Mags", order = 0 },
        Stock = { hidden = true },
        Optics = { allowEmpty = false },
    },
    layout = { railWidth = 0.18, panelWidth = 0.34, optionCell = { 0.48, 0, 0, 110 } },
    theme = { accent = { 255, 170, 60 }, font = "Gotham" },
    text = { title = "ARMORY", confirm = "APPLY" },
    preview = { fov = 40, dragSensitivity = 0.35 },
    environment = { blur = false },
    slotFilter = function(tool, slotDef) return slotDef.name ~= "Magazine" or tool:GetAttribute("UsesMags") end,
})
```
Every key and its default is in `Config.luau`. Arrays such as `blockedKeys` replace the default; tables are merged.

## Replacing the view
Pass `view = function(context) return myView end`. `context` is `{ gui, config, sounds }`. The view must implement:
```
Bind(actions)              actions = { selectSlot(slot), pick(slot, name|nil), clear(slot), confirm(), revert(), close() }
SetWeapon(name)            SetCatalog(catalog)       SetActiveSlot(slot|nil)
SetSelection(loadout)      SetSummary({count, capacity?, dirty})
Flash(message, kind?)      PlaySound(kind)           GetViewport() -> ViewportFrame|nil   Destroy()
```
`catalog.slots[i] = { name, label, order, role, allowEmpty, options = { {name, label, icon, description, available, reason} } }`.

## Controller API (`CustomizeUI.get()`)
- **Actions:** `Open()`, `Close(reason)`, `Confirm()`, `Select(slot, name)`, `ClearSlot(slot)`, `Revert()`.
- **Queries:** `IsOpen()`, `GetState()`, `GetTool()`, `GetSelection()`, `GetCatalog()`.
- **Signals:** `Opened(tool)`, `Closed(reason)`, `Confirmed(tool, loadout)`, `SelectionChanged(loadout, change)`.

## SPH contracts that are kept
- **The ScreenGui:** exactly one ScreenGui named `CustomizeGunGUI`, and its `Enabled` equals "menu open". `WeaponInput` and `WeaponFireMod` rely on this. Disabling it from anywhere else closes the menu.
- **Confirm sequence:**
  1. `SanitizeLoadout`.
  2. Optimistic `SetLoadout` (a local copy).
  3. `ApplyWeaponAttachments:FireServer(tool, loadout)`, sent **once**.
  4. Close.
  5. `GunEvents.CustomizeConfirmed(tool, loadout)`, which `Weapons/UI/CustomizeGunGUI` uses to refresh the viewmodel, stats and lights.
- **Weapon events:**
  - `SetupCustomizeGUI` re-targets an open menu and is ignored while the menu is closed.
  - `CleanupCustomizeGUI` closes the menu without saving.
- **Other contracts:**
  - `GetSelectedAttachments` still answers, with a copy of the selection.
  - The `CustomizeGunHandler` prompt callbacks work as before.
  - The respawn/death force-close works as before.
