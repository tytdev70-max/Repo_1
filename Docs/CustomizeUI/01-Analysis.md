# Customize UI: Phase 1, Analysis of the Legacy Controller

Subject: `HUD/CustomizeGunGUI.luau`, a 1141-line LocalScript, together with every script that interacts with it. Nothing was changed during this phase.

## 1. What the controller is
It is a single LocalScript that does seven unrelated jobs and shares about 40 upvalues between them:

| # | Responsibility | Approx. lines |
|---|---|---|
| 1 | Finding or cloning the `CustomizeGunGUI` ScreenGui and looking up template paths | 15–45 |
| 2 | 3D preview: viewport, orbit camera, ray/box near-clip, attachment cloning | 90–420 |
| 3 | Session side effects: input sinking, WalkSpeed, inventory/hotbar suppression, Backpack CoreGui, mouse lock override, blur, prompts | 430–600 |
| 4 | Button visuals: select, deselect and hover tweens, plus sounds | 600–700 |
| 5 | Binding the template's pre-built buttons to slots (columns) | 700–800 |
| 6 | Open/close state machine and external events | 800–1000 |
| 7 | Confirm (local write and remote call) and character lifecycle | 1000–1141 |

## 2. How it opens
```
ProximityPrompt "ProxPart" ─► CustomizeGunHandler.onTriggered
   (only if an SPH tool is equipped and the menu is closed)
   └► openCustomizeGUI()   (registered through CustomizeGunHandler.BindCallbacks)
        ├ if already open: forceCloseAndReset(), then task.wait(0.2)
        ├ gui.Enabled = true, DisplayOrder = 1000, prompts disabled
        ├ wait one frame, then check the same or a compatible SPH tool is still equipped (otherwise abort)
        ├ blockInputs()   (CAS sink on movement and hotbar keys, WalkSpeed = 0)
        └ setupEvent:Fire(tool)   ─► setup handler: buttons, saved picks, 3D view
gui.Enabled changing to true ─► onGuiEnabledChanged: mouse override every PreRender, inventory enforcement every Heartbeat, blur on
```

## 3. How it manages slots, and the restrictions that come with it
- **Slots are hard-coded:**
  - `COLUMN_CATEGORIES = {Optics, Underbarrel, Muzzle, Stock}`.
  - A second map hard-codes the mount parts (`OpticPart`, `GripPart`, `MuzzlePart`, `StockPart`).
  - The 3D preview hard-codes the same map a third time.
- **Slots are assigned by position:**
  - The *n*th Frame named `column` gets the *n*th category.
  - A fifth column would be ignored, and fewer columns silently drop slots.
- **The list of attachments comes from the template, not from the content:**
  - Buttons must already exist in the ScreenGui. The name comes from `padding.itemname.Text`, with the first TextLabel's name as a fallback.
  - A new attachment in `GunAttachments/` does not show up until someone builds a button for it by hand.
- **The only per-gun restriction:**
  - A button is shown only if the *viewmodel* gun (`Camera.WeaponRig.Weapon.<Model>`) has `<MountPart>/<AttachmentName>` as an `Attachment`.
  - `IsCompatible` is ignored, so the UI can offer attachments the server will refuse.
  - If the viewmodel is missing, every button is hidden.
- **No capacity or conflict rules.** There is one selection per slot, and clicking the selected item again clears the slot.
- **Saved picks without a button** stay in `selectedAttachments` and are sent again on confirm (kept as is).

## 4. How it talks to weapon data
| Channel | Direction | Detail |
|---|---|---|
| `tool.SavedAttachments` (after Phase 5: `Attachments:GetLoadout/SetLoadout`) | read on setup, written on confirm | The client write is an optimistic local copy |
| `ApplyWeaponAttachments` RemoteEvent | client → server | `FireServer(tool, loadout)` |
| `PreviewAttachments` folder on the tool | destroyed on confirm | Leftover from an older version; nothing creates it any more |
| `Attachments:LoadConfig` / `GetContentFolder` / `GetSlotPartName` | read | Used by the 3D preview |
| `ReplicatedStorage.SPH_Assets.WeaponModels/<tool.Name>` | read | Source model for the preview |

## 5. Hidden dependencies (the important part)
| # | Dependency | Who relies on it | Consequence for a redesign |
|---|---|---|---|
| H1 | **A second listener on the same Confirm button.** `Weapons/UI/CustomizeGunGUI.Init` (run per character from `SystemModuleInits`) finds `PlayerGui.CustomizeGunGUI.MainDisplayFrame.content.ConfirmButton` by path, pulls the selection through `GetSelectedAttachments`, sends `FireServer(loadout)` a *second* time, then rebuilds the viewmodel: `ApplyLoadout`, sights, laser/flashlight, stats, WalkSpeed, sprint multiplier, ADS FOV, recoil springs, ADS visuals. It ends with `gui.Enabled = false`. | Viewmodel and stats refresh | Moving or renaming the button would quietly stop the viewmodel from updating. This needs to become an explicit event. |
| H2 | `GetSelectedAttachments` BindableFunction returns the *live* table | H1 | Must stay available |
| H3 | **`SetupCustomizeGUI` is fired on every equip**, by `WeaponEquipMod` and `MiscHandlers`, even when the menu is closed | The legacy setup handler rebuilds all buttons and the whole 3D view on every weapon switch, even with the menu closed | The new controller should only rebuild while the menu is open |
| H4 | **`CleanupCustomizeGUI` is fired on every unequip** by `WeaponLifecycle` | Closes the menu | Keep: unequip closes the menu without saving |
| H5 | **Open/closed state is read from the ScreenGui itself:** `PlayerGui:FindFirstChild("CustomizeGunGUI").Enabled` | `WeaponInput` drops weapon input; `WeaponFireMod` blocks firing | There must be **exactly one** ScreenGui named `CustomizeGunGUI`, and its `Enabled` must equal "menu open" |
| H6 | Anything that sets `gui.Enabled = false` closes the menu (an Enabled watcher) | H1 relies on it | Keep the watcher |
| H7 | `CustomizeGunHandler.BindCallbacks(open, isOpen)`, `SetPromptsEnabled`, `Refresh` | Prompt text and enabled state | Keep the same calls |
| H8 | Character attributes `BackpackDisabled` and `IsUnequippingForArmHiding` | Decide whether the inventory and backpack may be restored on close | Keep the same rules |
| H9 | `Lighting.GUIBlur` (optional), and the sounds `Hover`, `Select` and `Deselect` inside the ScreenGui (optional) | Visuals | Reuse them if present |
| H10 | The script may live **inside** the ScreenGui (`script.Parent`), in which case it re-runs whenever the GUI resets on spawn | Startup | Starting must be safe to repeat, and must replace the previous instance |
| H11 | Server apply handler: accepts `(tool, loadout)` or `(loadout)`, runs `SanitizeLoadout` (slot whitelist = package slot list), and skips unchanged loadouts | Saving | New slots work on the server as soon as they are in the slot list |

## 6. Bugs and weaknesses found (fixed in the rebuild)
1. Every equip rebuilds the entire hidden menu and 3D view (H3).
2. The loadout is sent twice per confirm (H1 plus the HUD); only the server dedupe saved this.
3. `onCharacterAdded` adds `ChildAdded`/`ChildRemoved` connections on every spawn and never removes them, so they leak.
4. `stopInventoryEnforce` calls `task.wait(0.1)` from inside event handlers and close paths, which slows every close path down.
5. The 3D preview compares the class against BasePart *then* MeshPart. This works, but the root resolution differs from the package's.
6. `selectVisual` changes AnchorPoint and Position on template frames and depends on `cleanupActiveButtons` to undo it.
7. Template-driven content: a new attachment needs a hand-made button, and a new slot needs a new column *and* edits in three places in the code.
8. `hasWeaponEquipped` and `openCustomizeGUI` are accidental globals.

## 7. Limits outside the UI that cap capacity
- **Slots:** the package slot list (in `SPHAttachments`) is the server whitelist, so a slot that isn't listed can't be saved.
- **Dual sights:**
  - `GetAimPart` only reads the *first* slot with the optic role.
  - `WeaponInput` only allows switching sights if the base gun has `AimPart2`.
  - So a second optic could be mounted but never aimed through.
- **Extra muzzle categories:**
  - `GetActiveMuzzle` reads only the first slot with the muzzle role.
  - Unequipping any muzzle-overriding slot restores the original muzzle even while another one is still mounted.
  - The silencer checks are tied to the slot name `"Muzzle"` (server fire, animation, client fire).
- **Magazines:** generic mounting and `ApplyStats` already work for any slot.
