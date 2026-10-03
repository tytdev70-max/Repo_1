# Phase 5: Reintegration Report

**Status:** SPH now uses the standalone GunAttachments package for everything. The old `AttachmentManager` is now a deprecated compatibility shim, and no SPH code uses it.

Related docs: [01 Analysis](01-Analysis.md) · [02 Migration plan](02-MigrationPlan.md) · [03 Design](03-Design.md) · [Package API (README)](../../Modules/Modules/ThirdParty/GunAttachments/README.md)

---

## 1. Final architecture

```
 SPH code (server, client, HUD)
        │  require
        ▼
 Weapons/Attachments/SPHAttachments.luau     ← the ONLY file that knows both sides
        │  GunAttachments.new({ SPH options + hooks })
        ▼
 ThirdParty/GunAttachments/   (standalone package: no SPH requires, no SPH names)

 Weapons/Attachments/AttachmentManager.luau  ← DEPRECATED shim → SPHAttachments
                                               (kept only for third-party scripts)
```

How the dependencies run:
- Dependencies go one way only: SPH → adapter → package.
- The package has no `require` that points outside its own folder. This is checked by the test runner.
- `SPHAttachments` gives one shared system per Luau VM: one on the server and one per client.
- Its SPH-specific settings are:
  - **Content root:** `ReplicatedStorage.SPH_Assets.GunAttachments`. It is found lazily, so requiring the module never blocks.
  - **`allowUnknownSlots = false`:** this matches the old server whitelist.
  - **`resolveModel` hook:** on the client, if no model is passed, the camera viewmodel gun is used.
  - **`onSnapshotRestored` hook:** re-adds the `Flashlight`/`Laser` WeaponLighting tables, which can't be stored in JSON.

## 2. What changed, file by file

### Server
| File | Before | After |
|---|---|---|
| `AssetRefs` | `attachmentManager` | `Attachments` (SPHAttachments) |
| `GunSetupSystem`, `HolsterSystem`, `GunDropSystem` | Manual Clear plus an `EquipAttachment` loop over `SavedAttachments` | `Attachments:ApplyLoadout(model, tool, owner)`. Dropped guns use owner `nil`. |
| `ServerHelpers` | Read the manager's internal tables | `GetRecord`, `GetConfigField(..,"LPVOZoom")`, `GetGripData` |
| `PlayerFireSystem` | Required each muzzle `Customization` by hand | `Attachments:LoadoutHasFlag(tool, "EnableSilencer", "Muzzle")` |
| `NetworkHandlers` | Apply handler: whitelist, rebuild, folder write | Accepts both payload shapes `(loadout)` and `(tool, loadout)`. Rejects a tool that isn't the one equipped. Runs `SanitizeLoadout`, skips the rebuild if nothing changed, then `ApplyLoadout` and `SetLoadout`. Muzzle, overheat and light lookups use the API. |

### Client
| File | Change |
|---|---|
| `SystemModuleInits` | Requires SPHAttachments. Removed the 8 injected `attachmentManager` deps; `SystemModuleInits.Attachments` replaces `.attachmentManager`. |
| WeaponAiming, WeaponInput, WeaponLifecycle, WeaponFrame, BulletHandler, ArmPositionMod, CameraViewmodelMod, MobileSupportMod, LaserSightMod, WeaponFireMod, ScopeParallax `Activate` | Each now requires `SPHAttachments` directly instead of reading `deps.attachmentManager`. Calls were mapped one-to-one (table below). |
| `WeaponEquipMod` | Mapped calls. Replaced the `SavedAttachments` check with `HasLoadout`. Removed the debug-only `DebugMuzzleState`. |
| `WeaponViewmodel` | `ApplySavedAttachmentsToViewmodel` is now `ApplyLoadout(gunModel, tool, player)`. |
| `WeaponAnimation` | A suppressor check that required content by hand is now `LoadoutHasFlag`. |
| `AimingSystemMod` | The legacy manager parameter is now ignored. ADS visibility always goes through the system, with the same `aimTime/20` tween. |
| `Weapons/UI/CustomizeGunGUI` | Local apply = `SanitizeLoadout` + `ApplyLoadout`, the same validation the server runs. |
| `HUD/CustomizeGunGUI` | Reading and writing the loadout go through `GetLoadout`/`SetLoadout`. The 3D preview uses `GetSlotPartName` and `GetContentFolder`. Browsing the content folder for the UI columns is unchanged. |

### How old calls map to the new API
| Legacy | New |
|---|---|
| `EquipAttachment(player, tool, model, name, cat)` | `Attachments:Equip(model, tool, cat, name, player)` |
| `UnequipAttachment(model, cat)` | `:Unequip(model, cat)` |
| `GetActiveAttachments` / `HasAttachment` | `:GetActive` / `:Has` |
| `ClearAllAttachments` / `PrepareForEquip` | `:ClearModel` / `:ResetModel` |
| `StoreOriginalStats` / `ApplyAttachmentStats` / `RestoreStatsFromTool` | `:SetBaseStats` / `:ComputeStats` / `:GetBaseStats` |
| `GetAttachmentAimPart` | `:GetAimPart` |
| `HasGripEquipped` / `GetGripHandPosition` | `:HasHandGrip` / `:GetGripData` |
| `HasLaserAttachment` | `:AnyActiveFlag(m, "EnableLaser")` |
| `GetOverheatConfig` | `:GetConfigField(m, "Muzzle", "overHeating")` |
| `GetReticleConfig` / `GetDepthOfFieldConfig` | `:GetConfigField(m, "Optics", "ReticleConfig" / "DepthOfField")` |
| `GetMuzzleAttachmentConfig` | `:GetSlotConfig(m, "Muzzle")` |
| `LoadAttachmentConfig(name, cat)` | `:LoadConfig(cat, name)` (argument order flipped) |

## 3. Behaviour parity

**Kept exactly the same:**
- `_Equipped` naming and the attribute protocol.
- Record shape `{config, model, attachmentName}`.
- Callback signatures.
- Precedence rules:
  - Laser: attachment, then `Grip.Laser`, then any descendant.
  - Flashlight: `Grip.Flashlight`, then attachment, then any descendant.
  - Muzzle: attachment, then `ActiveCustomMuzzle`, then `Grip.Muzzle`.
- Grip defaults (`Left Arm`, speed 15, matchRotation).
- ADS tween time.
- The server whitelist.
- `SavedAttachmentsJSON`.
- Replacing (destroying and recreating) the `SavedAttachments` folder on write. This matters for replication: client copies, including values the HUD wrote locally, are destroyed with it.
- A strong base-stats cache.

**Changed on purpose (improvements):**
| Area | Old | New |
|---|---|---|
| Apply remote | The HUD sent `(tool, loadout)` but the server read the arguments in the wrong order (R1) | Both payload shapes are accepted, and the tool is checked against the equipped weapon |
| Double confirm | Rebuilt twice | An unchanged loadout skips the rebuild |
| `Equip` | Hard `task.wait(0.05)` | No yield |
| Failed equip | Left an orphan `_Equipped` node | The node is removed |
| Missing `IsCompatible` | Errored | Treated as compatible |
| Hidden parts | Transparency never restored | Restored on unequip and clear |
| Stats order | Followed `pairs` order (could differ between runs) | Always Optics, Underbarrel, Muzzle, Stock |
| Stats cache lifetime | Leaked forever | Released on `Tool.Destroying` |
| Client local apply | No validation | Same `SanitizeLoadout` as the server |

## 4. Validation done
| Check | Result |
|---|---|
| `Tests/GunAttachments/run.py`, package spec | 30/30 pass |
| Shim spec (`spec_shim.luau`, the real shim file pointed at a mock-backed system) | 5/5 pass |
| Mutation checks (broke the package once and the shim's argument order once) | Both caught |
| `luau-compile` on all 44 changed or new `.luau` files | 0 syntax errors; the gate was confirmed to catch a broken file |
| `luau-analyze` "unknown global" diff, HEAD vs. migrated, per file | No new unknown names, so no broken or misspelled references |
| `grep "ttachmentManager"` across Client, HUD, Server and Modules (excluding the shim) | 0 hits |
| Search for direct `SavedAttachments` or content access outside the package | Only the HUD's UI column browsing (on purpose) |
| Search for writes into the now-frozen records | None |
| Require-cycle check (SPHAttachments → WeaponLighting) | WeaponLighting requires only stats modules, so there is no cycle |

Run the tests with: `python3 Tests/GunAttachments/run.py <path-to-luau> [<path-to-luau-analyze>]`

## 5. In-Studio checklist (cannot be automated here)
The CLI tests use Roblox doubles. Please verify these in a Play Solo / 2-player test:
1. Equip each gun with no attachments, then with one in every slot. Check the first-person and third-person models.
2. Open the customize menu, apply, and close. Check that the server copy matches, the 3D preview matches, and re-opening the menu shows the saved picks.
3. Fire with a suppressor: muzzle flash and sound should be suppressed on both client and server.
4. ADS with an optic: the aim part, reticle and depth of field all work, and hidden parts fade.
5. Laser and flashlight on an underbarrel. Toggle them and check that another player sees them replicated.
6. Holster, drop, pick up and respawn: attachments rebuild with the right owner and no orphan `_Equipped` nodes remain.
7. Grip hand positioning on an underbarrel that has `EnableHandPositioning`.
8. Watch the output for `[GunAttachments]` warnings.

## 6. Deprecated shim and cleanup
- **`AttachmentManager.luau`** stays as a thin shim for any outside scripts. `ClearOriginalStats` and `DebugMuzzleState` do nothing. `.System` exposes the new system. Delete the shim once nothing requires it.
- **Harmless unused locals left behind:** `ATTACHMENT_CATEGORIES` and `HttpService` in `NetworkHandlers`, and `assets` in `PlayerFireSystem`.
- **Not in scope, still open from the earlier analysis:**
  - There are two copies of the CustomizeGunGUI code (`HUD/` and `Weapons/UI/`).
  - Duplicate client listeners.
