# GunAttachments Extraction — Phase 2: Migration & Safety Plan

## 1. Scope decision

**Extracted (becomes the standalone package):** everything in `AttachmentManager` —
content loading, config validation, slot definitions, mounting/welding, part hiding,
muzzle override, active-attachment registry, ownership, OnUpdate scheduling, stats
pipeline, loadout persistence on Tools, and all queries.

**Stays in SPH (consumers of the package):** `LaserSightMod`, `FlashlightBeamMod`,
`GlareMod`, `WeaponLighting`, `UBGL*`, `FireSelectorMod`, the customization menus, and
networking. They are weapon features and UI; they *ask* the attachment system questions.

## 2. Target dependency direction

```
 BEFORE                                         AFTER
 ┌──────────────┐                               ┌────────────────────────────┐
 │ SPH consumers│──► AttachmentManager ──►      │ SPH consumers              │
 └──────────────┘     │  SPH_Assets (hard path) │  (server + client)         │
                      │  WeaponLighting (SPH)   └──────────┬─────────────────┘
                      │  CurrentCamera viewmodel           ▼
                                                ┌────────────────────────────┐
                                                │ SPHAttachments (adapter)   │  ← the ONLY place that
                                                │  - content folder          │    knows both worlds
                                                │  - SPH hooks               │
                                                └──────────┬─────────────────┘
                                                           ▼
                                                ┌────────────────────────────┐
                                                │ ThirdParty/GunAttachments  │  zero SPH requires
                                                └────────────────────────────┘
 AttachmentManager.luau → kept as a deprecated shim forwarding to SPHAttachments.
```

## 3. Components: rewrite / wrap / replace

| Component | Action |
|---|---|
| `AttachmentManager.luau` | **Replace** with 1-file shim: every old function forwards to the shared `SPHAttachments` system. Keeps unknown/external callers (place-file scripts) working. |
| New `ThirdParty/GunAttachments/` | **Rewrite** of the core logic as a package (see Phase 3). |
| New `Weapons/Attachments/SPHAttachments.luau` | **New** adapter: builds the single system instance per VM with SPH configuration and hooks. |
| 5 copy-pasted loadout loops (GunSetup, GunDrop, Holster, NetworkHandlers, WeaponViewmodel) | **Replace** with `system:ApplyLoadout(model, tool, owner)` / `system:SetLoadout(...)`. |
| Apply handler in NetworkHandlers | **Rewrite** with `system:SanitizeLoadout` + accept both payload shapes (fixes R1). |
| Suppressor lookups (PlayerFireSystem, WeaponAnimation) | **Replace** with `system:LoadoutHasFlag(tool, "EnableSilencer")`. |
| Duplicated slot-part mapping in the HUD 3D preview | **Replace** with `system:GetSlotPartName(slot)` and `system:LoadConfig`. |
| All other call sites | **Re-point** from `attachmentManager.X` to the new method names via the adapter (mechanical). |
| `Constants.ATTACHMENT_CATEGORIES` | Kept for compatibility, but validation now goes through the package (`IsValidSlot`). |

## 4. API surface SPH needs (derived from Phase 1 §2.2)

Lifecycle: `ResetModel`, `ClearModel`, `Equip`, `Unequip`, `ApplyLoadout`.
Queries: `GetActive`, `GetRecord`, `Has`, `GetSlotConfig`, `GetConfigField`, `AnyActiveFlag`,
`GetAimPart`, `GetGripData`, `HasHandGrip`, `GetActiveMuzzle`, `GetLaserSource`,
`GetFlashlightSource`, `ApplyADSVisibility`, `CleanupMuzzleState`.
Stats: `SetBaseStats`, `GetBaseStats`, `ComputeStats`.
Loadout: `GetLoadout`, `SetLoadout`, `SanitizeLoadout`, `LoadoutHasFlag`.
Content: `LoadConfig`, `GetSlotPartName`, `IsValidSlot`.
Events: `Equipped`, `Unequipped`, `Cleared` signals.

## 5. Compatibility layers

1. **AttachmentManager shim** — exact old names and argument orders, forwards 1:1.
   `GetActiveAttachments` keeps returning records shaped `{config, model, attachmentName}`.
2. **Instance/attribute protocol unchanged** (`_Equipped` folders, `ActiveCustomMuzzle`,
   `*_Muzzle` attributes, `SavedAttachments` folder, `OriginalStats` JSON snapshot).
3. **Config callbacks** invoked with the original signatures (`OnUnequip(nil, nil, node)` etc.).
4. **Server payload**: both `(selected)` and `(tool, selected)` accepted.

## 6. Risk mitigation

| Risk | Mitigation |
|---|---|
| Behaviour drift in mounting | Port mounting code line-for-line first; improvements limited to clearly safe ones (no yield, cleanup of empty folder, restore original transparency). |
| Consumers missed in migration | Shim keeps every old entry point alive; grep gate: no `require(...AttachmentManager)` left in repo code except the shim. |
| Cross-VM duplication | One system instance per VM, created lazily by `SPHAttachments.Get()`; module cache guarantees singleton. |
| Bad content config | All config callbacks pcall'd; `IsCompatible` missing ⇒ treated as compatible-with-warning instead of erroring (strictly more tolerant). |
| Can't run Roblox here | Package split into pure-logic modules testable with the Luau CLI (stats, loadout, registry, slots, scheduler) + mock-Instance tests for mounting/queries; every changed file compiled with `luau-compile`; static gates via grep. Final validation in Studio checklist (§8). |
| Stat-order change (R4) | Deterministic slot order chosen to match the *most common* old iteration — but documented as an intentional fix. |

## 7. Step-by-step roadmap

1. Write the package (`ThirdParty/GunAttachments`) — no SPH file touched. SPH unaffected.
2. Unit-test the package in isolation (Luau CLI + mocks).
3. Add `SPHAttachments` adapter — still unused. SPH unaffected.
4. Turn `AttachmentManager` into the shim → **all SPH now runs on the new core** with zero call-site changes. (Safe checkpoint: revertible by restoring one file.)
5. Migrate server call sites (GunSetup, GunDrop, Holster, NetworkHandlers, ServerHelpers, PlayerFireSystem, AssetRefs).
6. Migrate client call sites (equip, viewmodel, fire, aiming, frame, lifecycle, input, mobile, laser, camera, scope, animation, customization UIs).
7. Grep gates + compile gates. Docs.
8. Studio validation checklist (to be run by the developer):
   - Equip each weapon class with and without saved attachments (FP + TP model).
   - Customize: optic/grip/muzzle/stock swap; confirm stats (walkspeed/FOV/recoil) update.
   - Suppressor: local + remote fire sounds use silenced variants.
   - Laser/flashlight toggle before & after customizing; remote players see them.
   - Drop & pick up a customized gun; holster model shows attachments.
   - Foregrip hand IK on server replication; LPVO lever ring; scope parallax optic.
   - Respawn → GunGiver → equip (regression for the earlier fix).
