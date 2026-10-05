# Customize UI: Phase 3, Implementation and Integration Report

## What changed
| Area | File(s) | Change |
|---|---|---|
| New subsystem | `Modules/Weapons/UI/Customize/*` | 11 modules plus a README (see the README for each module's role) |
| Entry point | `HUD/CustomizeGunGUI.luau` | 1141 lines reduced to about 40: finds or creates the ScreenGui and calls `CustomizeUI.start{...}` |
| Viewmodel refresh | `Weapons/UI/CustomizeGunGUI.luau` | Listens to `GunEvents.CustomizeConfirmed` instead of the template button found by path. Its duplicate `FireServer` and the template cloning are gone. Re-running `Init` on each respawn no longer adds duplicate connections. |
| Slot capacity | `Weapons/Attachments/SPHAttachments.luau` | Explicit slot list: the 4 original slots unchanged, plus `Barrel`, `Magazine`, `SecondaryOptic`. Rules options added. |
| Package | `ThirdParty/GunAttachments/{Rules,System,Slots,Defaults,Types}.luau` | New `Rules` module (capacity and conflicts, enforced in `SanitizeLoadout`). Several slots may share a role (sights, muzzle point, muzzle override). New API: `ListContent`, `CanEquip`, `CheckSelection`, `GetCapacity`, `GetSights`, `GetSightCount`. |
| Dual sights | `Weapons/Client/Input/WeaponInput.luau` | Sight switching also cycles through mounted optics' sights. The old gun-`AimPart2` rule still applies when the optics provide one sight or none. |
| Extra muzzle categories | `Server/PlayerFireSystem`, `Weapons/Fire/WeaponFireMod`, `Weapons/Client/Animation/WeaponAnimation` | Silencer checks look at any slot, not only the slot named `Muzzle`. `WeaponEquipMod` already did this. |

## Behaviour parity (legacy → new)
| Legacy behaviour | New |
|---|---|
| Opens from the prompt, only with an SPH tool equipped; re-checks after one frame | Same (`Controller:Open`) |
| Reopening while open force-closes first (with a 0.2s wait) | Same; the wait is configurable (`behaviour.reopenDelay`, default 0) |
| CAS sink on the same 28 keys; WalkSpeed 0 and restored afterwards | Same keys, now configurable |
| Mouse freed every PreRender; inventory/hotbar/Backpack hidden every Heartbeat; blur | Same |
| Restore only when neither `BackpackDisabled` nor `IsUnequippingForArmHiding` is set; otherwise the mouse icon stays hidden | Same rule |
| Unequip cleanup re-enables the Backpack CoreGui unconditionally | Same (release mode `"cleanup"`) |
| Respawn/death: force reset with the mouse at Default and visible | Same (mode `"force"`), but only while the menu is actually open |
| Clicking the selected item clears the slot; picking another replaces it | Same (`Selection:Toggle`); there is also an explicit **None** card and a **Clear** button |
| Saved picks without a button are kept and re-sent | Same (selection loads the full saved loadout) |
| An option is offered only if the viewmodel gun has `<MountPart>/<Name>` | Same check through `CanEquip`, plus `IsCompatible`. Falls back to the clean source model if the viewmodel is missing (legacy showed nothing). |
| Confirm writes a local copy, destroys `PreviewAttachments`, sends `(tool, loadout)` | Same, plus the loadout is sanitized first. It is sent **once** (legacy sent twice). |
| 3D preview: same camera, bounds, near-clip and zoom maths | Ported unchanged; mounting works for any slot and stacks like the real mounting |

## Fixes over the legacy controller
1. The hidden menu is no longer rebuilt (buttons and 3D view) on every weapon equip.
2. The loadout is no longer sent twice per confirm.
3. Per-character connections are cleaned up on respawn instead of leaking.
4. No `task.wait` inside close paths; the inventory restore is a cancellable delay.
5. The viewmodel refresh no longer depends on a button path, and it runs *after* the environment restores WalkSpeed. Previously the restore overwrote the new stats' walk speed.
6. New attachments and slots appear automatically; options the server would refuse are hidden, or shown greyed with a reason.
7. No accidental globals; every piece can be replaced or tested.

## Validation
| Check | Result |
|---|---|
| `Tests/GunAttachments/run.py`: package spec / shim spec / **extended spec (new)** | 30/30, 5/5, 20/20 |
| Extended spec covers | capacity (attribute and global), conflicts (both directions, slot order), `CheckSelection`, `ListContent`, **`CanEquip` agrees with `Equip` for every slot×option**, single-optic parity, dual sights, stacked muzzles, magazine stats, Selection, Catalog, Config |
| Mutation checks (muzzle restore, one-sided conflicts, catalog ignoring `CanEquip`) | All caught |
| `luau-compile` on every changed or new `.luau` file | 0 errors |
| `luau-analyze` unknown-global diff versus HEAD, plus a full analysis of the pure modules | No new unknown names (only the Roblox `script` global in the HUD entry); pure modules clean |
| Search for legacy template paths (`MainDisplayFrame`, `AttachmentsFrame`, `ConfirmButton`, …) outside the new code | None |

## In-Studio checklist
1. Open the menu from the customize table prompt. Check that movement, hotbar and firing are blocked, the mouse is free, and the blur shows.
2. Slots show only those the gun supports. Pick, swap, clear (with both None and Clear), and revert. Check the 3D preview updates live and that drag and wheel work.
3. Confirm: the first-person gun, the third-person gun (other client), stats (ADS FOV, recoil, walk speed) and laser/flashlight all update. Re-opening shows the saved picks.
4. Close with ✕ and with Escape. Unequip while the menu is open: it closes without saving. Die while it is open: the controls come back.
5. Add a `MaxAttachments = 2` attribute to a Tool. The footer shows `n / 2`, a third pick is refused, and the server keeps only 2.
6. Optional, with content: a gun with `SecondaryOpticPart` plus a canted optic lets you switch sights between the two optics. A `BarrelPart` plus a barrel attachment, with a suppressor on top, should be suppressed.
7. Mobile: the layout scales, and the touch drag rotates the preview.
