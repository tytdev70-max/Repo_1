# Attachment / Gunsmith System — Pre-Change Full-Scope Audit

> Status: **analysis complete**, implementation authorized.
> Scope: every direct and indirect dependency of the Gunsmith / Attachment system.
> No source file had been modified when this document was written.

---

## 1. Component census

| # | Path | Lines | Role | Verdict |
|---|---|---|---|---|
| 1 | `Modules/Modules/Weapons/Attachments/AttachmentManager.luau` | 981 | The entire attachment runtime | **MOVE** |
| 2 | `HUD/CustomizeGunGUI.luau` | 1168 | Gunsmith menu view + 3D preview + input lock | **MOVE** |
| 3 | `Modules/Modules/Weapons/UI/CustomizeGunGUI.luau` | 213 | Menu confirm controller (stat/FOV/spring refresh) | **MOVE** |
| 4 | `Modules/Modules/Weapons/UI/CustomizeGunHandler.luau` | 84 | Proximity-prompt host binding | **MOVE** |

Runtime consumers: **26** files reference `AttachmentManager` / `attachmentManager`.
Further files depend on the *side effects* of those 26 (see §5).

---

## 2. The data model, exactly as implemented

### 2.1 Runtime registry (module-local, keyed by `weaponModel` instance)

```
activeAttachments[weaponModel][category] = { config, model, attachmentName }
configCache["<category>/<name>"]         = require()d Customization module
originalStatsCache[weapon]               = deep copy of base WeaponStats
activeGripStates[weaponModel]            = written, never read  (dead)
weaponOwnership[weaponModel]             = weapon (cross-tool reuse guard)
processedTools                           = declared, never used (dead)
activeUpdaters[weaponModel][category]    = true; shared RunService.Heartbeat
destroyHooked[weaponModel]               = weaponModel.Destroying connection
```

`OnUpdate` is invoked as `config.OnUpdate(nil, nil, deltaTime)` — the first two
args are the module-scope `nil`s from `RunActiveUpdaters`, **not** player/weapon.

### 2.2 Category → mount-part mapping (hardcoded, duplicated 3×)

```
Underbarrel -> "GripPart"     Optics -> "OpticPart"
Muzzle      -> "MuzzlePart"   Stock  -> "StockPart"
default     -> category .. "Part"
```

Duplicated in `AttachmentManager.EquipAttachment`, `HUD/CustomizeGunGUI` (line 61
**and** an inline copy inside `Apply3DViewAttachments`). Adding a category
required editing all three.

### 2.3 Physical rig produced by `EquipAttachment`

1. Validate: non-nil `weapon`/`weaponModel` → ownership → `LoadAttachmentConfig`
   → `config.IsCompatible(weapon.Name)` → replace existing category occupant.
2. Resolve `categoryPart` on the model, then `mountPoint = categoryPart:<attachmentName>`,
   which must be an `Attachment` instance.
3. Destroy any stale `<name>_Equipped` folder; create a new one parented to `categoryPart`.
4. Clone every direct `BasePart`/`MeshPart` child of the source attachment folder.
5. `RootPart` (or first BasePart/MeshPart) becomes the rig root; a `Motor6D` is
   parented to it with `Part0 = mountPoint.Parent`,
   `C0 = mountPoint.CFrame * (config.MountOffset or CFrame.new())`.
6. Every other cloned part gets a `Motor6D` to the root with
   `C0 = originalRoot.CFrame:Inverse() * originalPart.CFrame`.
7. All clones: `CanCollide = false`, `Massless = true`, `Anchored = false`.
8. `config.VisibleParts` → force `Transparency = 0`.
9. `config.HideGunParts` → `Transparency = config.HideTransparency or 1`.
10. Category `Muzzle` → part replacement (below).
11. `config.EnableLaser` → every descendant `Beam.Enabled = false`.
12. Register; run `config.OnUpdate` heartbeat if present; `config.OnEquip(player, weapon, node)`.

### 2.4 Part replacement (muzzle override)

`base = model.Grip or model.Base`; `originalMuzzle = base:FindFirstChild("Muzzle", true)`.
Hide target = `originalMuzzle.Parent` when it is an `Attachment`, else the part itself.

* Stores `OriginalTransparency_Muzzle` on the target and **all descendants**
  (only if not already stored, so nesting is idempotent).
* Hides target + descendants: `Transparency = 1`, `CastShadow = false`.
* Every descendant `ParticleEmitter`/`Light`: stores `OriginalEnabled_Muzzle`, disables.
* If `originalMuzzle` is an `Attachment`: `Visible = false`, `OverriddenByAttachment = true`.
* If the new node contains a `Muzzle`: `weaponModel:SetAttribute("ActiveCustomMuzzle", name)`.

### 2.5 `GetActiveMuzzle` resolution order (replicated 3× across SPH)

1. active `Muzzle` category entry → its `Muzzle` child
2. `ActiveCustomMuzzle` attribute → scan descendants for `<name>_Equipped` → its `Muzzle`
3. `model.Grip.Muzzle` (non-recursive `FindFirstChild`)

### 2.6 Stat patching

```
StoreOriginalStats(weapon, baseStats):
    originalStatsCache[weapon] = deepCopy(baseStats)
    weapon:SetAttribute("OriginalStats", HttpService:JSONEncode(baseStats))   -- UNGUARDED

ApplyAttachmentStats(weapon, weaponModel):
    base = RestoreStatsFromTool(weapon)      -- cache, else JSONDecode("OriginalStats")
    modified = deepCopy(base)
    if not weaponModel then weaponModel = <CurrentCamera> -> Model -> "Weapon" -> first Model
    if weaponModel is owned by another weapon -> return unmodified
    for each active entry with config.ApplyStats: modified = config.ApplyStats(modified)
    weapon:SetAttribute("ModifiedStats", HttpService:JSONEncode(modified))     -- UNGUARDED
    return modified
```

`deepCopy` is a hand-rolled `pairs` recursion that does **not** preserve metatables
or shared sub-tables and recurses without a cycle guard.

### 2.7 Persistence surface (all plain Instances, read/written directly by SPH)

| Location | Kind | Read by |
|---|---|---|
| `Tool.SavedAttachments` (`<category>` = `StringValue`) | Folder | 9 SPH files |
| `Tool` attribute `OriginalStats` | JSON string | `AttachmentManager` only |
| `Tool` attribute `ModifiedStats` | JSON string | SPH server |
| `Tool` attribute `SavedAttachmentsJSON` | JSON string | **written by menu, read by nothing** |
| `weaponModel` attribute `ActiveCustomMuzzle` | string | `GetActiveMuzzle` |
| `weaponModel` attribute `OriginalTransparency_Muzzle` | number | teardown |
| `weaponModel` attribute `OriginalEnabled_Muzzle` | bool | teardown |
| `weaponModel` attribute `MuzzlePreHidden` | bool | `PreHideOriginalMuzzle` (dead) |
| `weaponModel` attribute `OverriddenByAttachment` | bool | write-only |
| Attachment `Beams`/`Lights` | instances | replication |

---

## 3. The Gunsmith menu, end to end

### 3.1 CRITICAL FINDING — the menu is currently dormant

`HUD/CustomizeGunGUI.luau` is **required by nothing in this repository**:

```
$ grep -rn "CustomizeGunGUI" --include=*.luau .   # excluding the file itself
  → only Weathers/UI/CustomizeGunGUI (a different file), WeaponInput,
    WeaponFireMod (both only `playerGui:FindFirstChild("CustomizeGunGUI")`),
    and SystemModuleInits requiring Weathers.UI.CustomizeGunGUI
```

Consequences in the checked-in tree:

* The proximity prompt is **never bound** — `CustomizeGunHandler.BindCallbacks`
  is only called from the orphan view file.
* The `GunEvents.GetSelectedAttachments` `BindableFunction.OnInvoke` is
  **never assigned** — so the confirm handler in
  `Weapons/UI/CustomizeGunGUI.luau` hits `warn("[Customization] GetSelectedAttachments
  function not found!")` and returns without doing anything.
* `SPH_Events.Find` returns nil → confirm is a no-op.

The controller (`Weapons/UI/CustomizeGunGUI.luau`) only *binds a click handler to an
existing ScreenGui*; it never opens the menu. The menu is opened solely by the orphan
view file. **The Gunsmith is therefore non-functional in this snapshot.**

This must be preserved as-is: the extraction may not silently switch the gunsmith on.

### 3.2 Open flow (as written in the orphan)

`CustomizeGunHandler.BindCallbacks(open, isOpen)` →
`ProxPromptHandler` prompt trigger → `openCustomizeGUI()`:

1. resolve equipped tool (character → `FindFirstChildWhichIsA("Tool")` with `SPH_Weapon`)
2. toggle-close if already open, `task.wait(0.2)`
3. `isMenuOpen = true`, `customizeGUI.Enabled = true`, `DisplayOrder = 1000`, disable prompt
4. `task.wait()` then re-validate the same tool is still equipped
5. `blockInputs()` — `ContextActionService:BindAction("BlockAllInputs", Sink, …)`
   over 30 keycodes **and** `humanoid.WalkSpeed = 0`
6. `setupEvent:Fire(tool)`

`setupEvent` handler:
* `cleanupActiveButtons()`, `currentWeapon = tool`, `selectedAttachments = {}`
* `setupAllColumns()` — for each of 4 columns, walk the template's existing item
  frames, read the name from `padding.itemname.Text` (or the first TextLabel
  child), and **enable the row only if the live weapon has a matching `Attachment`**
  at `Grip → <categoryPartName> → <name>`. Non-compatible rows are hidden.
* rehydrate from `tool.SavedAttachments` via `applyAttachment` + `selectVisual`
* `Setup3DView(tool)`

### 3.3 Selection model

`selectedAttachments[category] = attachmentName` — a flat map, one entry per category.
`activeButtons` / `selectedButtonsByCategory` / `columnButtons` are pure view state.
Selecting a second part in a category replaces the first (`UnequipAttachment` on the old).

### 3.4 Confirm flow

1. build `attachments` map, dropping empties
2. rewrite `tool.SavedAttachments` (`StringValue` per category)
3. `tool:SetAttribute("SavedAttachmentsJSON", HttpService:JSONEncode(attachments))`
4. `GunEvents.ApplyWeaponAttachments:FireServer(tool, attachments)` — **two args**
5. *(controller)* `SPH_Events.Find("GunEvents","GetSelectedAttachments"):Invoke()`
6. `ApplyWeaponAttachments:FireServer(selectedAttachments)` — **one arg**
7. `ClearAllAttachments(gunModel)`; re-`EquipAttachment` per entry
8. `collectAndManageSights`, `UpdateMobileButtonVisibility`
9. laser: `GetLaserSource` on FP **and** TP model, `glareMod.SetLaserModelActive`
   with a colour read from a `Color` `ObjectValue` child; force a
   `playerToggleAttachment.send({AttachmentType = 1, …})` off/on pulse after 0.2 s
10. flashlight: `GetFlashlightSource` + `vars.flashFX.mod.SetEnabled` + glare; pulse `{AttachmentType = 0}`
11. `StoreOriginalStats` + `ApplyAttachmentStats`, then re-apply walk speed,
    `SprintSpeedMultiplier`, aim FOV, recoil + gun-recoil spring damping/speed
12. `aimingSystemMod.UpdateADSVisual(...)`
13. `customizeGUI.Enabled = false`

### 3.5 `ReloadWeaponStats` (client)

`GunEvents.ReloadWeaponStats.OnClientEvent(weapon)` → if it is the equipped weapon:
re-store base stats, re-apply attachment stats, update mobile buttons, walk speed,
sprint multiplier, aim FOV. **No SPH file ever fires this event.**

### 3.6 The 3D preview duplicates the mounting maths

`Apply3DViewAttachments` re-implements `EquipAttachment` step-for-step (root part
resolution, `MountOffset`, `originalRoot.CFrame:Inverse() * child.CFrame`,
`HideGunParts`, `HideTransparency`) into a `WorldModel` with anchored clones and no
`Motor6D` at all. It is a second, drifting copy of the canonical rig maths.

---

## 4. Confirmed defects in the current implementation

| # | Defect | Location | Effect |
|---|---|---|---|
| D1 | `HttpService:JSONEncode` is called unguarded on `WeaponStats` | `StoreOriginalStats`, `ApplyAttachmentStats` | **Throws** for any weapon whose stats contain a `CFrame` — and `wepStats.boltDist` / `wepStats.projectileOrientation` are read as CFrames in `GunSetupSystem` and `BulletHandler`. Stats persistence is therefore weapon-dependent and can hard-error. |
| D2 | `UnequipAttachment` restores `HideGunParts` to `Transparency = 0` | teardown | Wipes genuine per-part transparency; a genuinely translucent barrel/stock becomes opaque forever after one swap. |
| D3 | `restoreTarget:GetAttribute("MuzzlePreHidden")` gates the whole muzzle restore | teardown | If `PreHideOriginalMuzzle` ran (it is dead code, but the attribute is also settable externally) the **entire** muzzle restore is skipped — base muzzle stays invisible. |
| D4 | `originalStatsCache` is never cleared (`ClearOriginalStats` is an empty function) | stats | Unbounded growth across dropped/spawned tools. |
| D5 | `attachmentCount` computed and never used; `processedTools` declared and never used; `activeGripStates` written and never read | several | Dead state, misleading. |
| D6 | `task.wait(0.05)` inside `EquipAttachment` when replacing an existing node | equip | A blocking yield inside an equip path, and it is not needed — `Destroy()` is immediate. |
| D7 | `SaveAttachmentsJSON` written, never read; `OverriddenByAttachment` written, never read | menu / mounter | Dead contract surface. |
| D8 | `GetFlashlightSource` checks the base `Grip.Flashlight` **before** attachments | query | A weapon with a rail flashlight AND an underbarrel light resolves to the wrong one. |
| D9 | Server suppresses by re-walking `tool.SavedAttachments` → `assets.GunAttachments` → `require(Customization).EnableSilencer` | `PlayerFireSystem`, `WeaponAnimation.PlayRepSound`, `WeaponFireMod` | Attachment logic duplicated into SPH **3×**, and a server `require()` of client-facing asset modules. |
| D10 | `weaponOwnership` blocks stat application for a legitimately re-owned model | `ApplyAttachmentStats` | Returns *unmodified* stats silently. |
| D11 | `RestoreStatsFromTool` can return a table that `ApplyStats` mutates in place | stats | A config mutating its input corrupts the cache. |

---

## 5. Dependency map

### 5.1 Direct `AttachmentManager` consumers (26 files)

| Consumer | Methods used |
|---|---|
| `Weapons/Equip/WeaponEquipMod` | `StoreOriginalStats`, `ApplyAttachmentStats`, `ClearAllAttachments`, `PrepareForEquip`, `GetActiveAttachments`, `DebugMuzzleState` |
| `Weapons/UI/CustomizeGunGUI` | `ClearAllAttachments`, `EquipAttachment`, `StoreOriginalStats`, `ApplyAttachmentStats`, `GetLaserSource`, `GetFlashlightSource` |
| `Weapons/UI/CustomizeGunHandler` | *(requires `HUD.CustomizeGunGUI`)* |
| `HUD/CustomizeGunGUI` | `LoadAttachmentConfig` |
| `Weapons/Client/Viewmodel/WeaponViewmodel` | `GetActiveAttachments`, `ClearAllAttachments`, `EquipAttachment` |
| `Weapons/Client/Viewmodel/WeaponFrame` | `GetReticleConfig`, `GetAttachmentAimPart` |
| `Weapons/Client/Viewmodel/WeaponLifecycle` | `ClearAllAttachments` |
| `Weapons/Client/Viewmodel/WeaponAnimation` | suppressor lookup (D9) |
| `Weapons/Client/Input/WeaponInput` | `GetFlashlightLights`, `GetLaserSource` |
| `Weapons/Aiming/AimingSystemMod` | `ApplyAttachmentADSVisibility`, `GetDepthOfFieldConfig`, `GetActiveAttachments` |
| `Weapons/Aiming/ArmPositionMod` | `GetActiveAttachments`, `HasGripEquipped`, `GetGripHandPosition` |
| `Weapons/Aiming/CameraViewmodelMod` | `GetFlashlightLights` |
| `Weapons/Fire/WeaponFireMod` | `GetActiveAttachments` (reads `.config.EnableSilencer`) |
| `Weapons/Fire/BulletHandler` | `GetActiveMuzzle`, `GetOverheatConfig` |
| `Weapons/UI/MobileSupportMod` | `HasLaserAttachment`, `GetFlashlightSource` |
| `Client/.../ScopeParallax/Main/Activate` | `GetAttachmentAimPart`, `GetActiveAttachments` |
| `Client/.../SystemModuleInits` | passes `attachmentManager` through DI to ~10 modules |

### 5.2 Indirect (side-effect) dependents — not in the 26

`Server/GunSetupSystem` (suppression at spawn), `Server/HolsterSystem` +
`Server/GunDropSystem` (re-apply on persist), `Server/NetworkHandlers`
(apply-attachments remote, LPVO/flashlight/laser replication),
`Server/ServerHelpers` (`opticsAttachment.config.LPVOZoom`),
`Server/PlayerFireSystem` (suppression), `Weapons/Equip/WeaponInputServer`.

### 5.3 Hard SPH couplings to sever

1. `ReplicatedStorage:WaitForChild("SPH_Assets")` at **module scope**, plus
   `assets:WaitForChild("GunAttachments")` — runs on every consumer's first require.
2. The 3× duplicated category table.
3. `Tool.SavedAttachments` folder name + `<category>` `StringValue` convention.
4. `Tool` attribute names `OriginalStats` / `ModifiedStats` / `SavedAttachmentsJSON`.
5. `weaponModel` attribute `ActiveCustomMuzzle` and the `Original*_Muzzle` attributes.
6. `<name>_Equipped` folder naming, depended on by `GetActiveMuzzle`, `PrepareForEquip`,
   `ClearAllAttachments` and the 3D preview.
7. Weapon-model convention `Grip.Muzzle` / `Grip.Laser` / `Grip.Flashlight` / `Grip` / `Base`.
8. `tool.SPH_Weapon.WeaponStats` module path.
9. Event names `SetupCustomizeGUI`, `CleanupCustomizeGUI`,
   `GunEvents.GetSelectedAttachments`, `GunEvents.ApplyWeaponAttachments`,
   `GunEvents.ReloadWeaponStats`, all under `assets.Events.GunEvents`.
10. `playerScripts:WaitForChild("SPH_Player"):WaitForChild("PlayerClient"):WaitForChild("ProxPromptHandler")`
    — a 4-level hardcoded instance path inside `CustomizeGunHandler`.
11. Character attributes `BackpackDisabled` / `IsUnequippingForArmHiding`, and the
    blanket "any ScreenGui whose name contains `inventory`/`hotbar`" suppression.
12. `Lighting:FindFirstChild("GUIBlur")`.
13. `SPH_Events.GetOrCreate` / `.Find` for `GunEvents`.

---

## 6. Target architecture

`Modules/ThirdParty/AttachmentSystem/`

```
init.luau            public API facade + Configure()  ← the ONLY require SPH makes
Config.luau          categories, mount map, storage keys, limits, event names
ConfigLoader.luau    Customization discovery + cache + validation
Registry.luau        per-model state, ownership, OnUpdate heartbeat, destroy hooks
Mounter.luau         clone/Motor6D rig, part replacement, muzzle override, teardown
StatModifier.luau    deep copy, ApplyStats pipeline, safe persistence (fixes D1/D11)
Storage.luau         SavedAttachments ⇄ plain map on a Tool
Queries.luau         muzzle/laser/flashlight/grip/aim/optics/reticle/DoF/overheat/silencer
Visuals.luau         ADS transparency, muzzle cleanup, sight iteration (fixes D8)
Replication.luau     owns its event names + apply/confirm plumbing
Gunsmith.luau        menu orchestration + host callbacks
Gunsmith/View.luau   menu view, ported 1:1
Gunsmith/Preview3D.luau  viewport preview, now reusing Mounter maths
Gunsmith/InputLock.luau  input blocking + inventory suppression (host-provided hooks)
```

Design rules:

* **No `WaitForChild` at module scope anywhere in the package.** The root folder is
  resolved lazily, so requiring the provider can never deadlock another script.
* `Configure(opts)` is optional; the package is inert and safe if never configured.
* All SPH naming lives in `Config.luau` as overridable defaults.
* SPH receives only explicit API calls; it never reaches into internals.
* `WeaponEquipMod` etc. pass the *module table*, not raw fields — so the
  `AimingSystemMod.UpdateADSVisual(..., attachmentManager)` parameter becomes a
  provider handle.
* The 3× suppressor lookup collapses to one call: `AttachmentSystem.isSuppressed(ctx)`.

### Behaviour that must not change

* The gunsmith stays **dormant** unless explicitly started (§3.1).
* All 26 consumers keep working; the migration is call-site rewiring only.
* Menu confirm's dual-`FireServer` arity mismatch is preserved as-is (server must
  keep tolerating both), rather than "fixed" behind the user's back.

---

## 7. Implementation checklist

- [x] analysis of all 4 owned files
- [x] all 26 direct consumers mapped by method
- [x] indirect server/side-effect dependents mapped
- [x] 13 hard SPH couplings enumerated
- [x] 11 latent defects catalogued
- [x] target package layout + API surface designed
- [x] create the 13-file package (~4,600 lines)
- [x] rewire all 26 direct consumers
- [x] rewire indirect server consumers (PlayerFireSystem, GunSetupSystem,
      GunDropSystem, HolsterSystem, NetworkHandlers, ServerHelpers)
- [x] delete the 2 superseded implementation files
      (`Weapons/Attachments/AttachmentManager.luau`, `HUD/CustomizeGunGUI.luau`)
- [x] collapse the 3x duplicated suppressor lookup into `IsSuppressed()`
- [x] collapse the 3x duplicated saved-loadout loop into `ApplySavedLoadout()`
- [x] retire the 4th copy of the category set (`Server/Constants`)
- [x] verify no dangling requires / no `AttachmentManager` references remain
- [x] structural validation of all 198 files (tools/luaucheck.py)
