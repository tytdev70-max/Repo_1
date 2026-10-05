# Customize UI: Phase 2, Design

## Goals
1. One clean, modular subsystem replaces the 1141-line controller.
2. **Data-driven capacity:** slots come from the attachment system's slot list, and options come from the content folder. Adding a slot or an attachment needs no UI code.
3. Full control from outside over layout, theme, rules and behaviour, or a completely custom view.
4. Every hidden dependency from the analysis (H1–H11) keeps working.

## Module layout: `Modules/Weapons/UI/Customize/`
```
init.luau          CustomizeUI.start(options)  : public entry (restartable), returns Controller
Config.luau        defaults + deep merge (theme, layout, slot labels, rules, behaviour)
Signal.luau        tiny signal
Selection.luau     PURE selection model: select/toggle/clear/revert, dirty, capacity, conflicts
Catalog.luau       PURE-ish: which slots and options a weapon offers (uses the attachment system)
Environment.luau   session side effects (input, WalkSpeed, inventory, mouse, blur, prompts)
Preview.luau       3D viewport: orbit camera, near-clip guard, mounts any slot
View/Theme.luau    colours, fonts, tweens
View/Components.luau  reusable UI pieces (panel, label, button, slot tab, option card)
View/init.luau     the default view: builds the layout and exposes the view interface
Bridge.luau        ALL SPH wiring: handler callbacks, events, remote, character lifecycle
Controller.luau    orchestration and state machine (Closed → Open → Closed)
```
Dependencies only point downward:
- Controller → {Selection, Catalog, Environment, Preview, View}.
- Bridge → Controller.
- Nothing in the subsystem requires the HUD script.
- `Selection` and `Catalog` have no Roblox dependencies, so they are unit-tested in the CLI.

## Data flow
```
open(tool)
  Catalog.build(tool, gunModel)   → slots[] { name, label, options[] {name,label,icon,available,reason} }
  Selection.new(slots, rules):Load(Attachments:GetLoadout(tool))
  View:SetCatalog / SetSelection; Preview:Show(tool, selection)
user clicks option → Selection:Toggle(slot, name) → Changed → View + Preview update
confirm → loadout = Attachments:SanitizeLoadout(selection)   (same rules as the server)
        → Attachments:SetLoadout(tool, loadout)  (optimistic local copy, as before)
        → ApplyWeaponAttachments:FireServer(tool, loadout)   (ONCE)
        → GunEvents.CustomizeConfirmed:Fire(tool, loadout)   (replaces the hidden button hook H1)
        → close
```

## Capacity and rules (enforced by the server too)
The attachment package gets an optional `rules` stage, run inside `SanitizeLoadout`, so the server applies exactly what the UI shows:
- **Capacity:** `rules.maxAttachments` (global), overridden per weapon by the tool attribute `MaxAttachments`. If the limit is exceeded, entries are kept in slot order and the rest are dropped.
- **Conflicts:** an attachment config may declare `ConflictsWith = { "Underbarrel", "Muzzle/Suppressor" }`. Entries are accepted in slot order, and anything that conflicts with an already-accepted entry is dropped.
- **`Attachments:CheckSelection(tool, loadout, slot, name)`** reports what a pick would displace, so the UI can resolve it the way the user expects: the newest pick wins and replaces the conflicting ones, or is blocked when the limit is full.

Both rules are off by default (no attribute, no `ConflictsWith`), so existing behaviour is unchanged.

## Slot capacity: new SPH slots
The slot list in `SPHAttachments` is the single source of truth. It controls the server whitelist, mounting, stats order and UI columns.

| Slot | Mount part | Role | Purpose |
|---|---|---|---|
| Optics | OpticPart | optic | unchanged |
| Underbarrel | GripPart | grip | unchanged |
| Muzzle | MuzzlePart | muzzle, overridesMuzzle | unchanged |
| Stock | StockPart | – | unchanged |
| **Barrel** | BarrelPart | muzzle, overridesMuzzle | extended muzzle category (barrel extensions, compensators) |
| **Magazine** | MagazinePart | – | magazines (stats such as capacity through `ApplyStats`) |
| **SecondaryOptic** | SecondaryOpticPart | optic | dual sights (canted or piggyback) |

A slot only appears in the UI for a weapon that has its mount part *and* at least one attachment that fits it, so weapons without new mount points look exactly as before.

### Package support for more than one slot per role (backward compatible)
- **Sights:** `GetAimPart(model, i)` walks the aim parts of *all* optic-role slots in slot order (`AimPart`, `AimPart2`, … for each one). With one optic equipped the behaviour is identical to before. `GetSightCount(model)` is added.
- **Sight switching:** `WeaponInput` allows switching if the gun has `AimPart2` (old rule) **or** the mounted optics provide more than one sight.
- **Muzzle point:** the highest-order muzzle-role attachment that has a `Muzzle` point wins (the device at the end of the stack). With one muzzle it is identical to before.
- **Muzzle override:** unequipping one overriding slot only restores the original muzzle if no other overriding slot is still mounted. Otherwise `ActiveCustomMuzzle` is pointed at the remaining one.
- **Silencer checks:** they look at any slot (`LoadoutHasFlag(tool, "EnableSilencer")` / `AnyActiveFlag`). Only muzzle content declares that flag, so existing content behaves the same.

## The new design (default view)
```
┌──────────────────────────────────────────────────────────────────────────┐
│ CUSTOMIZE · M4A1                                                    [✕]  │
├──────────────┬───────────────────────────────────┬───────────────────────┤
│ SLOTS        │                                   │ OPTICS          Clear │
│ ▌Optics      │                                   │ ┌──────┐ ┌──────┐     │
│  Red Dot     │          3D PREVIEW               │ │ None │ │RedDot│ ... │
│  Underbarrel │      drag = rotate, wheel = zoom  │ └──────┘ └──────┘     │
│  —           │                                   │ (scrolling grid,      │
│  Magazine    │                                   │  any number of items) │
│  ... (scroll)│                                   │                       │
├──────────────┴───────────────────────────────────┴───────────────────────┤
│ 3 / 6 attachments · unsaved changes            [Revert]      [CONFIRM]   │
└──────────────────────────────────────────────────────────────────────────┘
```
- The slot list on the left scrolls, so any number of slots fits. Each tab shows the current pick.
- The option grid on the right scrolls, so any number of attachments fits. It always starts with a **None** card. Icons come from config `Icon` or the folder attribute `Icon`, and the label from `DisplayName`.
- All sizes are in scale units, so the window works on every resolution and on touch.
- Theme (colours, fonts, corners, tweens) and layout (window size, column widths, grid cell) are options. `options.view` can replace the view entirely, as long as the replacement implements the same view interface (documented in the README).

## Compatibility contract (how H1–H11 are kept)
| Item | How it is kept |
|---|---|
| H1 | The viewmodel module listens to the new `GunEvents.CustomizeConfirmed(tool, loadout)` BindableEvent instead of the button. Its duplicate `FireServer` is removed. |
| H2 | `GetSelectedAttachments` is still answered, with a copy of the selection |
| H3, H4 | Bridge: Setup while open re-targets the menu; Setup while closed is ignored; Cleanup closes |
| H5, H6 | The view renders inside **the** ScreenGui named `CustomizeGunGUI`: the existing one is reused and its legacy frames hidden, or one is created. `Enabled` always equals open, and the Enabled watcher closes the menu. |
| H7 | The same `CustomizeGunHandler` calls |
| H8, H9 | Environment ports the restore rules, blur and sounds exactly |
| H10 | `CustomizeUI.start` destroys any previous controller first |
| H11 | Unchanged; new slots are in the package slot list |
