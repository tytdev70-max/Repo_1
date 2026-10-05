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

## Using and redesigning the Studio GUI (`ui = "template"`, the default)
By default the menu uses the `CustomizeGunGUI` ScreenGui made in Studio (`SPH_Assets.HUD.GunGUIs.CustomizeGunGUI`). `View/Template.luau` finds the elements below by name, so you can change sizes, colours, fonts, images and layouts freely.

**Names to keep:**
```
CustomizeGunGUI (ScreenGui)  + the CustomizeGunGUI LocalScript inside it
├─ Hover / Select / Deselect                 Sounds (optional)
├─ AttachmentsFrame.Padding.AttachmentsColumn   container of the columns
│   └─ <column>                              one per slot
│       ├─ columnheading.title               TextLabel (optional) - slot label
│       └─ display.items                     ScrollingFrame/Frame - the items
│           └─ <item>                        Frame (the clickable card)
│               └─ padding                   Frame
│                   ├─ itemname              TextLabel - attachment folder name
│                   └─ icon                  ImageLabel (optional)
└─ MainDisplayFrame
    ├─ content.ConfirmButton                 GuiButton (required)
    ├─ content.CloseButton                   GuiButton (optional)
    ├─ content.BlankFrame.GunName            TextLabel (optional)
    └─ 3DView.3DVPF                          ViewportFrame (optional) - 3D preview
Optional, anywhere: RevertButton, ClearAllButton (GuiButtons), Summary, Status (TextLabels)
```

**How a column finds its slot:**
- If the column has a `Slot` string attribute, it uses that (for example `Magazine`).
- Otherwise, if the column is named after the slot, it uses its name.
- Columns still named `column` take Optics, Underbarrel, Muzzle and Stock in `LayoutOrder` order.

**How an item finds its attachment:**
- If the item has an `Attachment` attribute, it uses that.
- Otherwise it uses the `itemname` text, which must match the folder name in `GunAttachments/<Slot>/`.
- Items the equipped gun can't take are hidden.

**Missing columns and items:**
- An attachment with no designed item gets a copy of the first item.
- A slot with no column gets a copy of the first column.
- To control how they look, design them yourself.

**Selection look:**
- Selected items turn `template.selectedColor` and grow by `template.selectedScale`.
- Right-clicking an item clears its slot.

## Saved loadouts (presets)

Players can save the current picks under a name, per gun type (Tool name), and apply them later.

* **Settings:** `Modules/Weapons/Presets/PresetSettings.luau`. Includes `enabled`, `dataStoreName`, `maxPresetsPerGun` (nil = no limit), `maxNameLength`, `autosaveInterval` and `maxRequestsPerSecond`. The menu side can be turned off with `Config.presets.enabled = false`.
* **Server:** `Server/Server/LoadoutPresets.luau` stores presets in a DataStore (key `player_<UserId>`). Players use it through the RemoteFunction `GunEvents.LoadoutPresets`, whose actions are `list`, `save`, `rename` and `delete`. In Studio, data is only kept between sessions with *Game Settings > Security > Enable Studio Access to API Services*.
* **Save** stores the picks; it does not change the gun. **Load** puts a preset in the menu without applying it. **Apply** equips it (through the normal `ApplyWeaponAttachments` + `SanitizeLoadout` path) and makes it the gun type's **active** preset.
* **Active preset:** new copies of that gun get the active preset automatically. Already-equipped guns pick it up on the next equip.
* **When the active preset is cleared** (the presets themselves stay saved):
  * the gun carrying it is dropped;
  * it is lost on death;
  * it leaves with the player (only when `dropOnLeave` is on);
  * a normal Confirm changes that gun's attachments.
* Controller API: `SavePreset(name?)`, `LoadPreset(name)`, `ApplyPreset(name)`, `RenamePreset(old,new)`, `DeletePreset(name)`, `RefreshPresets()`, `GetPresets()`, and the `PresetsChanged` signal.

### GUI elements (all optional, found by name anywhere in the ScreenGui)

| Name | Class | Purpose |
|---|---|---|
| `PresetNameBox` | TextBox | Name for Save and Rename (empty Save = "Loadout N") |
| `SavePresetButton` | GuiButton | Save the current picks |
| `LoadoutsButton` | GuiButton | Show or hide `LoadoutsFrame` (opening refreshes the list) |
| `LoadoutsFrame` | GuiObject | The Loadouts screen (hidden at the start of every session) |
| `LoadoutsCloseButton` | GuiButton | Hide `LoadoutsFrame` |
| `PresetCount` | TextLabel | "3 loadouts" or "3 / 10 loadouts" |
| `PresetsEmpty` | GuiObject | Shown when the list is empty; TextLabel shows the message or error |
| `PresetList` | container | Holds one copy of `PresetTemplate` per preset (add a UIListLayout) |
| `PresetTemplate` | GuiObject | Hidden prototype; children below are found at any depth |
| ↳ `PresetName` | TextLabel | Preset name |
| ↳ `PresetAttachments` | TextLabel | "Red Dot, Suppressor" |
| ↳ `ActiveBadge` | GuiObject | Visible on the active preset |
| ↳ `CarriedBadge` | GuiObject | Visible if this gun has the preset right now |
| ↳ `ApplyButton` | GuiButton | Apply now |
| ↳ `LoadButton` | GuiButton | Load into the menu only |
| ↳ `RenameButton` | GuiButton | Rename to the `PresetNameBox` text |
| ↳ `DeleteButton` | GuiButton | Click twice within 3 seconds (the text shows "Sure?") |

Messages are in `Config.text` (the `preset*` strings and `presetErrors`). If you leave out an element, its feature simply doesn't appear. The generated fallback view has no presets UI.
