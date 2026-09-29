# SPH — "Open-Ballistics" Roblox FPS Framework
## Exhaustive System Analysis

**Repository:** `tytdev70-max/Repo_1`
**Branch:** `arena/01a0eade-repo-1` @ `9fc695e` (single squashed commit — no history)
**Language:** Luau (Roblox) — 187 files, 34,739 lines
**Status:** Read-only analysis. Repository working tree unmodified.

---

## 1. Executive Summary

This is a **production-grade, data-driven first-person shooter framework for Roblox**, branded internally as *Open-Ballistics* / `SPH_Assets`. It implements a full tactical-movement + gunplay simulation: crouch/prone stances, stamina-gated sprinting, hip-fire/ADS with variable FOV optics, R6-rig-aware leaning and foot IK, a full auto/manual/semi/burst/bolt-action fire-control model with bolt cycling, chambering, reloading and shell ejection, weapon attachments (optics/underbarrel/muzzle/stock) with modular stat patching, under-barrel grenade launchers (UBGL), grenades, destructible glass and breakable cover, doors with kick/peek/open state machines, ragdoll, explosions with smoke voxel simulation, and distance-based server-authoritative networking.

**Key architectural characteristic:** the codebase is a *de-monolithization*. Every file header explicitly says it preserves "the exact original execution order" of a former single monolithic script. The architecture is therefore **strictly phase-ordered, context-injected, and side-effect-heavy at module scope** — the single most important thing to understand before modifying anything.

**The repository is a code-only export.** It contains no `.rbxl`, no `default.project.json` (no Rojo/Selene/Aftman), and no asset folders. It is **not runnable as-is**; see §9 (External Dependencies).

---

## 2. Deployment Topology

The repo is a file tree that maps onto Roblox instance services. There is no build step — Roblox Studio is the compiler, and `.luau` files become `ModuleScript` / `LocalScript` / `Script` instances by filename convention:

| Filename suffix | Roblox class | Location in place |
|---|---|---|
| `init.server.luau` | Script | `ServerScriptService` |
| `init.local.luau` | LocalScript | `StarterPlayerScripts` / `StarterCharacterScripts` |
| `Replicator.client.luau` | LocalScript | arbitrary |
| `init.luau` (in a folder) | ModuleScript | folder itself becomes the module |
| `<Name>.luau` | ModuleScript | child of its parent folder |

| Repo path | Roblox instance path |
|---|---|
| `Server/` | `ServerScriptService` |
| `Client/StarterPlayerScripts/PlayerClient/` | `StarterPlayer.StarterPlayerScripts.PlayerClient` |
| `Client/StarterCharacterScripts/Client/` | `StarterCharacterScripts` (cloned into the character on spawn) |
| `Modules/Modules/` | `ReplicatedStorage.SPH_Assets.Modules` |
| `HUD/` | `ReplicatedStorage.SPH_Assets.HUD` |

### Entry points (3)

```
ServerScriptService/init.server.luau          59 lines   7 explicit phases
StarterPlayerScripts/PlayerClient/init.local.luau  61 lines   10 numbered phases
StarterCharacterScripts/Client/init.local.luau    142 lines  replication-guard + 3 phases
```

**Critical property:** the `StarterCharacterScripts` LocalScript is **re-cloned into the character on every respawn**, so the entire character-side client (5,410 lines) re-initializes from scratch each life. It re-requires ~57 descendant ModuleScripts.

---

## 3. High-Level Architecture

```
                         ┌───────────────────────────────────────────┐
                         │        ReplicatedStorage.SPH_Assets        │
                         │  ┌──────────┐ ┌────────┐ ┌──────────────┐ │
                         │  │ Modules  │ │ Events │ │  GameConfig  │ │
                         │  │ (88 mod) │ │(remotes│ │  (MISSING)   │ │
                         │  │          │ │ tree)  │ │              │ │
                         │  └────┬─────┘ └───┬────┘ └──────┬───────┘ │
                         │       │           │             │         │
                         │  WeaponModels  Animations   Sounds        │
                         │  GunAttachments  Projectiles  HUD          │
                         │  Viewmodels   RagdollContent               │
                         │  Ammo                                        │
                         └───────┬───────────────────────────────────┘
                                 │
      ┌──────────────────────────┼───────────────────────────┐
      │                          │                           │
┌─────▼──────────┐   ┌───────────▼────────────┐   ┌──────────▼───────────┐
│  SERVER        │   │  SHARED MODULES        │   │  CLIENT              │
│  ServerScript  │◄─►│  (Modules/*)           │◄─►│  PlayerClient        │
│  Service       │   │  • Core/Networking     │   │  (player-lifetime)   │
│  20 files      │   │  • Core/Utility        │   │  CharacterClient     │
│  2,778 lines   │   │  • Core/Math           │   │  (per-life)          │
│                │   │  • Weapons/**          │   │  HUD scripts         │
│  authoritative │   │  • Effects/**          │   │                      │
│  state +       │   │  • Misc/**             │   │  22+55+2 files       │
│  validation    │   │  • Systems/**          │   │  8,977 lines         │
│                │   │  • ThirdParty/**       │   │                      │
└────────────────┘   └────────────────────────┘   └──────────────────────┘
```

### Code distribution

| Subsystem | Files | Lines | % |
|---|---:|---:|---:|
| `Modules/Weapons` | 46 | 13,117 | 37.8% |
| `Client/StarterCharacterScripts` | 55 | 5,410 | 15.6% |
| `Modules/Effects` | 13 | 4,288 | 12.3% |
| `Server` | 20 | 2,778 | 8.0% |
| `Modules/Misc` | 8 | 2,773 | 8.0% |
| `Client/StarterPlayerScripts` | 22 | 2,078 | 6.0% |
| `Modules/Systems` | 7 | 1,510 | 4.3% |
| `HUD` | 2 | 1,489 | 4.3% |
| `Modules/Core` | 11 | 922 | 2.6% |
| `Modules/ThirdParty` | 3 | 374 | 1.1% |

---

## 4. Architectural Patterns

### 4.1 Reference-locator ("ServiceRefs / AssetRefs") pattern
Each of the three script trees has a root locator module that resolves services and assets exactly once and exports them as a flat table. This exists because the monolithic original repeated `game:GetService()` hundreds of times.

- `Server/ServiceRefs.luau`, `Server/AssetRefs.luau`, `Server/EventRefs.luau`
- `.../CoreModules/Boot/ServiceRefs.luau`, `AssetRefs.luau`, `CharacterRefs.luau`
- `PlayerClient/Modules/ServiceRefs.luau`

Each is a **side-effectful module**: `require()`ing it performs `WaitForChild` on the whole asset tree.

### 4.2 Context / service-locator injection (the dominant pattern)
Because the weapon modules form a dense, mutually-referential graph, direct `require` between them would create cycles. The codebase instead uses a **two-phase bootstrap**:

1. `ModuleInits/SystemModuleInits.luau` calls `SomeMod.Init({ dep1 = x, dep2 = y, ... })` on ~20 modules.
2. `ModuleInits/WeaponContextInit.luau` calls `WeaponContext.set({ ~110 entries })`.
3. Each client weapon module declares its dependencies as `local`s at module scope and resolves them in its own `init()`:

```lua
-- WeaponInput.luau
local BindAiming, ChamberAnim, ...            -- forward-declared
local function HandleInput(...) ... end       -- closes over the nil locals

function WeaponInput.init()
    local ctx = WeaponContext.get()
    BindAiming = ctx.BindAiming
    ...
end
```

**Consequence:** any function invoked before `init()` runs sees `nil` in these slots. This is the single largest implicit constraint in the client weapon system.

### 4.3 Central mutable state tables
Three "god state" tables, deliberately centralized to break cycles:

| Store | Scope | Key fields |
|---|---|---|
| `Weapons/Core/WeaponState.luau` (`vars`) | client weapon session | ~140 fields: `equipped`, `wepStats`, `gunModel`, `aiming`, `sprinting`, `reloading`, `loadedAnims`, `fpSights`, `sightIndex`, springs' targets, LPVO/grip state, walk-cycle phase |
| `Server/ServerState.luau` | server | per-player lean/aim/grip/ADS maps, grenade throw pendings, shell-eject cooldowns, LPVO arm targets (weak-keyed), workspace folder refs, drop table |
| `Movement/.../SharedState.luau` | client movement | `movementVector`, `strafing`, `stance`, `stamina`, `isExhausted`, `localLeanRefs`, `otherLeanRefs` |

`vars` is returned **by reference** (`WeaponState.get()`), so every module mutates the same table. `WeaponState.reset()` clears and re-defaults **in place** to preserve identity.

### 4.4 `WeaponBindings` — a static facade
`Weapons/Client/Input/WeaponBindings.luau` (91 lines) flattens 8 client weapon modules into one ~50-symbol namespace, capturing function references at require time:

```lua
return {
    GetThirdPersonGunModel = weaponActions.GetThirdPersonGunModel,
    PlayAnimation          = weaponAnimation.PlayAnimation,
    ToggleAiming           = weaponAiming.ToggleAiming,
    ... 45 more
}
```
Everything in the character client talks to `WeaponBindings.*` rather than to the sub-modules. Because references are snapshotted at require time, a module that reassigns one of its exported functions after `WeaponBindings` loads would leave the facade holding a stale function.

### 4.5 `ClientBridge` — keyed, self-replacing listener registry
`Core/Networking/ClientBridge.luau` exists because ByteNet listeners live in the packet module, not the subscribing script; on respawn a stale character script's listener would keep firing. `ClientBridge.bind(key, packet, cb)` **unbinds the previous listener for that key first**, so a generation that fails to clean up cannot stack duplicate callbacks. Used by `FootIK`, `ClientBridgeBindings`, `RemoteLeanHandler`.

### 4.6 Weak-keyed registries
Used to avoid leaks on instance-keyed maps: `ServerState.lpvoLockedArms`, `lpvoPreGripTarget`, `ModelQueryCache.entries`, `PierceMod.bulletPhysicsCache` / `weaponStatsCache`, `HitFX.woundDeathBound`, `KillFeedModule.EntryLookupCache`.

### 4.7 Event-driven, tag-driven world interaction
`CollectionService` tags act as the data-driven contract for world geometry:
- `SPH_NoCollide` — excluded from raycasts (server + client)
- `SPH_Collide` — re-enabled
- `SPH_Destructible` — objects with an `HP` attribute that break under fire
- `SPH_Door` — door models picked up by `DoorSetup` (added/removed signals)
- `BreakableGlass`, `SPH_NoMuffle` — glass / audio exclusions

---

## 5. Module-by-Module Breakdown

### 5.1 `Server/` — authoritative layer (2,778 lines)

| Module | Lines | Responsibility |
|---|---:|---|
| `init.server.luau` | 59 | 7-phase ordered bootstrap |
| `ServiceRefs` / `AssetRefs` / `EventRefs` | 84 | service, asset and remote resolution |
| `Constants` | 98 | collision groups/pairs, thresholds, falloff sound tiers |
| `ServerState` | 30 | all mutable server state |
| `CollisionSetup` | 29 | registers 6+1 collision groups, 20 non-colliding pairs |
| `WorkspaceSetup` | 31 | creates `workspace.SPH_Workspace/{Projectiles,Cache,SmokeCache,Shells,Drops}` |
| `NetworkHandlers` | 937 | **all 24 inbound packet handlers** — the server's API surface |
| `PlayerFireSystem` | 118 | fire validation, ammo deduction, suppressor detection, `ReplicateFire` |
| `GunSetupSystem` | 259 | `SetupGun` / `EquipGun` / `EquipGrenadeServerModel` / `IsGunLoaded` |
| `GunDropSystem` | 203 | `SpawnGun`, `MakePickUpAble`, `DropGun`, despawn/eviction ring buffer |
| `HolsterSystem` | 190 | back-mounted weapon models, scope-reticle reparenting to hidden store |
| `CharacterRigSystem` | 42 | builds the third-person `WeaponRig` on the character |
| `ArmLerpSystem` | 84 | **on-demand** Heartbeat lerping of arm `Motor6D.C0` for grip/LPVO |
| `ServerHelpers` | 253 | CFrame validation, arm-motor resolution, server grip solve, replication broadcast |
| `PlayerLifecycle` | 178 | `PlayerAdded/Removing`, `CharacterAdded`, `Humanoid.Died` |
| `DoorSetup` / `ProximityPromptHandlers` | 51 / 128 | door tag subscription; AmmoBox / GunGiver prompts |
| `RagdollEventHandler` | 35 | manual ragdoll toggle relay |

**Server design note:** the server renders a full third-person gun model (`GunSetupSystem.EquipGun`) purely so that arm grips and bolt positions replicate correctly. The server never simulates ballistics — the client raycasts and reports, the server validates and applies damage.

### 5.2 `Modules/Core/` (922 lines) — infrastructure

| Module | Lines | Contract |
|---|---:|---|
| `Networking/SPH_Network` | 329 | **48 ByteNet packet definitions** (the wire protocol) |
| `Networking/SPH_ClientPacketRefs` | 43 | 26 camelCase aliases over `Network.packets` |
| `Networking/SPH_Events` | 69 | `Get/GetOrCreate/Find/WaitFor` over `SPH_Assets/Events/*` |
| `Networking/ClientBridge` | 39 | keyed listener registry |
| `Networking/NetworkRangeUtil` | 22 | `GetPlayersInRange` |
| `Networking/MaterialCodec` | 14 | `Enum.Material` ⇄ `uint16` |
| `Networking/ReplicationThrottle` | 41 | interval + delta-threshold send gate |
| `Utility/ConnectionManager` | 25 | bulk-disconnect bag (per-equip cleanup) |
| `Utility/PartCache` | ~200 | pooling for bullet/voxel parts; auto-expands ×10 |
| `Math/SpringModule` | 63 | fixed-timestep (1/60) 8-iteration spring with interpolation |

### 5.3 `Modules/Weapons/` (13,117 lines — 38% of the codebase)

**Core** — `WeaponContext` (service locator), `WeaponState` (god state), `WeldMod`, `DamageFalloff`, `ModelQueryCache`.

**Client** (the local player's gun):
- `WeaponClient.luau` — ordered init of 8 sub-modules
- `Input/WeaponInput` (609) — the input state machine (see §7.2)
- `Input/WeaponBindings` (91) — facade
- `Lifecycle/WeaponLifecycle` (447) — `Unequip`: a ~250-line teardown that resets ~60 state fields
- `Animation/WeaponAnimation` (651) — animation lookup/load/play with an LRU-ish 3-entry `animCache`
- `Aiming/WeaponAiming` — ADS, hold stances, DoF, FOV tween
- `Viewmodel/WeaponViewmodel` (333), `Viewmodel/WeaponFrame` (546) — rig posing, sight reticle `SurfaceGui` management
- `Actions/WeaponActions` (203), `Actions/WeaponSequences` (322) — bolt/chamber/reload/equip/inspect sequences

**Aiming** (per-frame camera driver):
- `CameraViewmodelMod` (671) — **the single largest per-frame consumer**; camera offset, bob, lean, breathing, wall-clip, prone, FP/TP blend
- `AimingSystemMod` (336), `ArmPositionMod` (574), `ProceduralWalkCycle`, `AimVignetteMod`, `ReticleMotionBlurMod`, `HeadPoseReplicationMod`

**Fire**:
- `BulletHandler` (1,074) — FastCast caster, tracer/motion-blur/suppression, fire FX, bolt movement, auto-fire sound pooling
- `WeaponFireMod` (632) — the fire state machine + overheat model
- `Hitscan` (108) — iterative raycast with ignore-list penetration (used by turrets/UBGL)
- `PierceMod` (381), `ShellEjection` (201), `MagEjection` (337), `WeaponPushbackMod`

**Attachments** — `AttachmentManager` (980) is the runtime rig for attachments: clones parts, builds `Motor6D` trees, patches weapon stats via `ApplyStats`, manages grip-hand positioning, muzzle override, laser/flashlight discovery, ADS transparency, and per-weapon `OnUpdate` heartbeat registration.

**UI** — `CustomizeGunGUI`/`Handler` (attachment menu), `MagCheckDisplay`, `FireModeCheckDisplay`, `MobileSupportMod` (touch buttons), `SystemMessages`.

**Also:** `UBGLHandlerMod` (client launcher) / `UBGLSystemMod` (server launcher) — under-barrel grenade launchers as a *weapon sub-mode*.

### 5.4 `Modules/Effects/` (4,288 lines)
- `Blood/HitFX` (1,222) — per-material decals, `SurfaceGui` wounds, headshots, `WorldToGui` projection
- `Environment/FractureGlass` (391) + `GlassShatterMod` (156) — client-predicted networked glass with server restore
- `Environment/SmokeVoxelMod` (669) — **client-only** voxel smoke simulation with bullet disturbance
- `Explosions/ExplosionFX` (540) — server-side radial damage, LOS checks, flash falloff, destructible interaction
- `Explosions/FlashbangEffectMod` (486) — screen flash, ring audio, muffle
- `Rendering/Visualisation_Manager` — bullet motion-blur trails

### 5.5 `Modules/Misc/` (2,773 lines)
- `DoorSystem/` — `DoorController` (573) is a full OO class: kick (with break-down into physics debris), peek, open/close, health, prompts, sound; driven by `DoorConfig`
- `Grenades/` — `GrenadeHandler` (567, server: spawn, physics, fuse, bounce) + `GrenadeClient` (555, client: viewmodel, throw, detachable cosmetics)
- `KillFeed`, `LensFlare`, `LoadingScreen`

### 5.6 `Modules/Systems/` (1,510 lines)
- `HitResolutionMod` (212) — **server-authoritative damage**: dedup, team check, falloff, leaderboard, glass, destructibles, bullet impulse
- `PlayerDeathMod`, `RagdollServerMod` (488) + `CameraManager`, `DayNightCycle` (257), `AssetPreloader`, `HearingMuffleMod`

### 5.7 `Client/StarterCharacterScripts/` (5,410 lines)
`CoreModules/Boot` (10 ref modules) → `CoreModules/ModuleInits` (3 orchestrators) → `CoreModules/Handlers` (10), plus `Movement/CharacterMovement` (17 files: stance/sprint/stamina/lean/foot-IK/render loop), `ScopeSystems/ScopeParallax` (per-weapon scope patchers: `Default`, `7chon`, `Spearhead`), `Visibility`, `IndoorReverb`, `FallDamage`.

### 5.8 `Client/StarterPlayerScripts/` (2,078 lines)
Player-lifetime systems: 6 replication listeners (`Fire`, `Hit`, `GripHand`, `Flashlight`, `MagGrab`, `BodyAnim`), `ExplosionFX`, `DoorShake`, `KillFeed`, `Footsteps`, `ProximityPrompt`, `LoadingHandler`, `LensFlare`, `CameraShakeController`, `JumpCameraOffset`, `RingAudio`.

### 5.9 `HUD/` (1,489 lines)
`MainUI.luau` (321) — ammo/magazine HUD. `CustomizeGunGUI.luau` (1,168) — the attachment customization menu (a parallel, much larger re-implementation of `Modules/Weapons/UI/CustomizeGunGUI.luau`).

---

## 6. Network Protocol — Complete Map

48 packets defined in `SPH_Network.luau`, all over the **ByteNetMax** serializer. Direction and consumers:

### Client → Server (24 `*Request` packets, all listened in `Server/NetworkHandlers.luau`)

| Packet | Payload | Server effect |
|---|---|---|
| `SwitchWeaponRequest` | `optional(inst)` | destroy TP model, `GunSetupSystem.EquipGun`, disable shoulders |
| `PlayerFire` | `struct{CFrame, {Vector3}}` | `PlayerFireSystem.PlayerFire` — ammo/bolt state, then `ReplicateFire` |
| `ReloadRequest` | nothing | full mag reload respecting `magType` 1–4 + `infiniteAmmo` |
| `PlayerChamberRequest` / `RepBoltOpenRequest` | nothing | bolt cycle state |
| `MoveBoltRequest` | `struct{CFrame, uint16}` | → `ReplicateBolt` to range |
| `SwitchFireModeRequest` | `uint8` | validated against `wepStats.fireSwitch` |
| `BulletHit` | 13-field struct | `HitResolutionMod.HandleBulletHit` — **the damage path** |
| `FallDamageRequest` | `float32` | `TakeDamage` + tiered sound |
| `PlayerLeanRequest` | `int8` | → `ReplicateLean` |
| `PlayerFootIKRequest` | `struct{bool,f32,f32,Vec3,Vec3}` | → `ReplicateFootIK` |
| `PlayerAimStateRequest` | `struct{bool,uint8}` | → `AimStateReplicate`; also clears LPVO locks |
| `PlayerAimRequest`, `WeaponPushbackRequest` | `bool`/`float32` | stored / replicated |
| `ReplicateGripHandRequest` | `struct{opt CFrame,string}` | server re-solves grip, lerps, broadcasts |
| `ReplicateLPVORingRequest` | `struct{CFrame,opt CFrame,string}` | 3-state (Enter/Update/Exit) arm-motor ownership |
| `ReplicateChamberSmokeRequest` / `ReplicateOverheatRequest` | `f32`/`bool` | particle effects on TP model |
| `ReplicateMagEjectRequest` | `struct{string,CFrame,{string},auto}` | server-spawned magazine drop (0.4s rate-limit) |
| `PlayerBeginGrenadeThrow` / `PlayerThrowGrenade` / `RequestGrenadeCosmeticDetach` | various | 2-phase throw with pending-tool validation; origin clamped to ≤6 studs from HRP |
| `PlayerFireUBGL` / `UBGLReload` | `struct{CFrame,Vec3}` / nothing | `UBGLSystemMod` |
| `PierceGlassRequest` | `struct{inst,Vec3}` | server shatter |
| `ShellEjectRequest`, `MagGrabRequest` | nothing | broadcast triggers |
| `PartVisibilityRequest` | `struct{string,bool}` | applies + `PartVisibilityReplicate` |
| `PlayerToggleAttachmentRequest` | `struct{uint8,bool}` | `0`=flashlight, `1`=laser → `ToggleAttachmentReplicate` |
| `PlayerDropGunRequest` | nothing | `GunDropSystem.DropGun` |
| `PlaySoundRequest` | `struct{string,bool,bool}` | plays a named `Sound` on the TP grip |
| `BodyAnimRequest` | `CFrame` | → `BodyAnimCommand` |
| `FootstepRequest` | `struct{uint16,inst,f32}` | → `FootstepReplicate` |

### Server → Client (13 replicate packets)

| Packet | Consumers |
|---|---|
| `ReplicateFire` / `ReplicateFireUBGL` | `PlayerClient/Modules/FireReplication` |
| `ReplicateHit` | `PlayerClient/Modules/HitReplication` |
| `GripHandReplicate` | `PlayerClient/Modules/GripHandReplication` |
| `BodyAnimCommand` / `ReplicateLean` | `PlayerClient/Modules/BodyAnimReplication` |
| `ReplicateBolt` / `PartVisibilityReplicate` / `ShellEjectReplicate` | `ClientBridgeBindings` (via `ClientBridge`) |
| `AimStateReplicate` / `WeaponPushbackReplicate` | `ClientBridgeBindings` → `AimingSystemMod` |
| `ReplicateFootIK` | `FootIK` (via `ClientBridge`) |
| `ReplicateMagGrab` | `PlayerClient/Modules/MagGrabReplication` |
| `ToggleAttachmentReplicate` | `PlayerClient/Modules/FlashlightReplication` + `LaserSightMod` |
| `FootstepReplicate` | `PlayerClient/FootstepHandler/Footsteps` |

**AOI model:** `NetworkRangeUtil.GetPlayersInRange(pos, range, except)` is an O(n) full-player scan over `Players:GetPlayers()`. Two distances: `config.fireEffectDistance` (FX/lean/pushback) and `config.animDistance` (body/foot IK). There is **no spatial hash and no interest-management caching**.

**RPCs outside ByteNet** (plain `RemoteEvent` / `BindableEvent` / `BindableFunction` in `SPH_Assets/Events`):
`CombatEvents/{NPC_HitEvent, Suppression}`, `EnvironmentEvents/{SPH_GlassRestored, RenderGlass}`, `GunEvents/{SPH_ShowHolster, SetupCustomizeGUI, CleanupCustomizeGUI, GetSelectedAttachments, ApplyWeaponAttachments, DropGun, ToggleViewmodelSprint}`, `DeathEvents/{RagdollEvent, UnragdollEvent, KillFeed}`, `MovementEvents/PlayCharacterSound`, `ExplosionEvents/{ExplosionFXRemote, SmokeCloudFinishedRequest}`, `DoorEvents/DoorCameraShakeEvent`, and `SPH_PromptConfig` on proximity prompts.

---

## 7. Runtime Behavior & Lifecycle

### 7.1 Server boot (7 phases, order is load-bearing)
```
1. require ServiceRefs → AssetRefs → Constants → ServerState → EventRefs
2. RagdollServerMod.Init()                      -- earliest, needs collision groups
3. CollisionSetup.init() ; WorkspaceSetup.init()
4. require ArmLerpSystem, ServerHelpers, HolsterSystem, CharacterRigSystem,
          GunSetupSystem, GunDropSystem, PlayerFireSystem
5. RagdollEventHandler.init() ; DoorSetup.init()  -- DoorSetup also starts DayNightCycle
6. SoundService.RespectFilteringEnabled = true
   magEjection.setup() ; SPH_NoCollide tag collection ; AssetPreloader.PreloadAllAnimations
   HolsterSystem.init()
7. PlayerLifecycle.init() ; NetworkHandlers.init() ; ProximityPromptHandlers.init()
```

### 7.2 Client boot — three concurrent trees

**(a) `PlayerClient` (StarterPlayerScripts, player-lifetime, 10 phases)**
```
1 ServiceRefs  2 CollisionSetup  3 preload HitFX/ShellEjection/BulletHandler
4 HearingMuffleMod.Init()  5 CameraShakeController (starts at module scope)
6 JumpCameraOffset  7 ChildModuleLoader (spawns 4 children)  8 6 replication Inits
9 ExplosionFX, DoorShake  10 KillFeedHandler
```

**(b) Character client** — guards against partial replication:
```lua
local REQUIRED_DESCENDANTS = { 57 paths }
local REPLICATION_TIMEOUT = 20  -- shared deadline, not per-path
waitForDescendants(script, REQUIRED_DESCENDANTS, REPLICATION_TIMEOUT)
```
Then: `require` all 10 Boot modules → `CoreModuleInits.init()`, `SystemModuleInits.init()`, `WeaponContextInit.init()` → 10 `Handler.init()` calls.

**(c) `CoreModuleInits` spawns 7 subsystems via `task.spawn`** — CharacterMovement, LandJump, FallDamage, FirstPersonVisibility, RigUpdater, ScopeParallax, IndoorAudioReverb. These are **asynchronous**; they can and do interleave with equip logic.

### 7.3 The three per-frame loops

| Loop | Owner | Work |
|---|---|---|
| `Heartbeat` | `UpdateLoops` | `WeaponFireMod.Update` (fire loop + overheat) |
| `RenderStepped` | `UpdateLoops` | `CameraViewmodelMod.Update` (viewmodel/camera) |
| `RenderStepped` | `CharacterMovement/RenderLoop` | lean, foot IK, stamina, walk speed, sprint anim, move state |
| `Heartbeat` | `RemoteLeanHandler` | remote-player lean lerp |
| `Heartbeat` | `AttachmentManager` | *only while attachments with `OnUpdate` are equipped* |
| `Heartbeat` | `ArmLerpSystem` (server) | *only while grip/LPVO arm targets exist* |
| `RenderStepped` | `GripHandReplication`, `FlashlightReplication`, `SmokeVoxelMod`, `FlashbangEffectMod`, `FirstPersonVisibility`, `MiscHandlers` | remote-player visuals |
| `RenderStepped` ×2 | `SmokeVoxelMod` | voxel expansion + puff update |

The pattern of **lazily started, self-terminating Heartbeats** (`ArmLerpSystem`, `AttachmentManager`) is good engineering — they disconnect when their work set empties.

### 7.4 Equip / Unequip — the central state machine

**Equip** (driven by `character.ChildAdded` → `WeaponEquipMod.EquipWeapon`):
`Character ChildAdded(Tool)` → clone viewmodel gun + TP gun → weld → apply saved attachments → set `vars.equipped/wepStats/gunModel/gunAmmo` → load animations → `switchWeapon.send(tool)` → server `EquipGun` → bind inputs.

**Unequip** (`WeaponLifecycle.Unequip`, ~250 lines) is the riskiest function in the codebase. It:
disconnects `equipConnections`, resets 3 throttles, stops every animation track on both animators, destroys the gun model, hides the FP rig at `storageCFrame` (1,000,000 studs), resets ~60 `vars` fields, evicts the animation cache (LRU, 3 entries, destroying evicted `AnimationTrack`s), sends `switchWeapon.send(nil)`, toggles laser/flashlight **off through the server**, destroys reticle motion-blur handles, resets the backpack GUI, and finally hands off to `vars.queuedTool`.

**Generation counter:** `vars.equipGeneration` is captured at fire time and re-checked after `task.wait` in the fire loop, so a weapon swapped mid-fire-interval cannot fire a stale round.

### 7.5 Fire pipeline (the critical path)

```
[Heartbeat] WeaponFireMod.UpdateFireLoop
  ├─ 20+ boolean guards (equipped, !dead, holdingM1, cycled, !sprinting, !reloading,
  │    !chambering, !inspecting, CameraType==Custom, !magCheck, !fireModeCheck,
  │    !menuOpen, !unequipping, !dropping, !ubgl, canFire, !blocked, holdStance==0,
  │    isLoaded(), curFireMode>0, !preFire-pending, !equipping, !firstPerson||thirdPersonFiring)
  ├─ play fire animation; apply recoil to 3 springs (camera / gun / rotational)
  ├─ BulletHandler.FireFX (muzzle particles, flash, sound, backblast)
  ├─ per pellet: resolve origin (wall-check in FP, back-ray in TP), apply spread
  ├─ BulletHandler.FireBullet → FastCast:Fire
  └─ playerFire.send({MuzzleCFrame, Directions})
        └─[Server] PlayerFireSystem: validate, deduct ammo, bolt state,
                    suppressor detect, ReplicateFire → nearby clients
[FastCast RayHit per segment] → hitFX.HitEffect + BulletHit.send(hit data)
        └─[Server] HitResolutionMod.HandleBulletHit:
             dedup(UserId_BulletId_HitIndex, 5s) → team check → falloff →
             leaderboard → TakeDamage | glass | destructibles | bullet impulse
             → ReplicateHit to nearby clients (visual only)
```

The **shooter** applies no damage. The **server** applies all damage. But the shooter chooses the ray — so this is "server-authoritative damage, client-authoritative ballistics."

### 7.6 Arm/grip/LPVO conflict resolution
The hardest concurrency in the codebase: one `Motor6D.C0` is contended between three systems (grip position, LPVO ring, animation). Resolution:
- Arm motors are `AnimBase` children; each caches `OriginalC0_Rest` at rig creation.
- `lpvoLockedArms[motor]` marks LPVO as the owner; grip packets are then diverted to `lpvoPreGripTarget`.
- `playerArmIgnoreUntil[player] = os.clock() + 0.35` suppresses grip packets for 350 ms after a weapon switch.
- `ARM_PACKET_IGNORE_DURATION` + `IsValidCFrame(cf, 25)` + `GRIP_TARGET_EPSILON` (0.05) bound all incoming CFrames.
- On ADS exit / unequip / attachment change, `ResetPlayerGunReplicationState` / `RefreshPlayerArmReplication` sweep every motor and restore `OriginalC0_*`.

### 7.7 Respawn / teardown
`CharacterAdded` (server) → reset replication state → build `WeaponRig` → `Humanoid.Died` → `PlayerDeathMod.HandleDeath` (drop grenade, destroy tools, detach cosmetics, killfeed, ragdoll) → client character script re-clones and re-runs §7.2(b). `ClientBridge` key rebinding is what makes this safe.

---

## 8. External Contracts

### 8.1 Missing code dependencies (would fail at `require`)
| Dependency | Required by | Status |
|---|---|---|
| `SPH_Assets.Modules.ThirdParty.ByteNetMax` | `SPH_Network` (→ everything networked) | **absent** |
| `SPH_Assets.Modules.ThirdParty.FastCast` | `BulletHandler` (→ all ballistics) | **absent** — deleted in commit `9fc695e` |

`Modules/ThirdParty/` contains only `CameraShaker` (374 lines, vendored).

### 8.2 Missing data/config dependencies
| Dependency | Required by |
|---|---|
| `SPH_Assets.GameConfig` (ModuleScript) | **every module** — ~180 config keys |
| `SPH_Assets.WeaponModels` (incl. `HolsterModels`) | server + client equip |
| `SPH_Assets.Viewmodels` (`{Default,<Team>}/WeaponRig`, `R6_Arms`) | `ViewMod.RigModel` |
| `SPH_Assets.Animations` (incl. `Movement`, per-weapon `animFolder`s) | `WeaponAnimation`, `DoorController` |
| `SPH_Assets.Sounds` (`Fire`, `GunDrop`, `Misc`, `FallDamage`, `GlassBreak`, `WalkSounds`, `Death`, `RagdollSounds`) | audio |
| `SPH_Assets.Projectiles` | grenades, fake bullets |
| `SPH_Assets.GunAttachments/{Optics,Underbarrel,Muzzle,Stock}/<name>/Customization` | `AttachmentManager` |
| `SPH_Assets.HUD.GunGUIs.SPH_UI`, `.CustomizeGunGUI`, `HUD.DeathUIs.DeathScreen` | UI |
| `SPH_Assets.Events/**` (≈20 remotes) | networking |
| `SPH_Assets.RagdollContent` | `RagdollServerMod` (hard `WaitForChild`) |
| `SPH_Assets.Ammo` | referenced |
| `BulletHandler.Bullet` (Part template w/ `BeamLong`, `PointLight`, `BulletSmoke`, `DistanceEffect`, `FakeBullet`) | `BulletHandler` (`script.Bullet:Clone()`) |
| `HitFX.BulletHoleDecals` | `HitFX` (`script.BulletHoleDecals`) |

### 8.3 `GameConfig` key surface (reconstructed, ~180 keys)
Highest-signal groups:
- **Network/FOV:** `fireEffectDistance`(10×), `animDistance`, `maxHitDistance`, `maxBulletDistance`, `bulletAcceleration`, `meterMultiplier`, `maxBullets`, `tracerStartDistance`, `arcadeBullets`, `suppressionEffects`, `teamSuppression`, `useBulletForce`, `defaultFOV`, `zoomSensitivityReduction`
- **Movement:** `walkSpeed`, `sprintSpeed`, `crouchSpeed`, `proneSpeed`, `stanceChangeTime`(15×), `proneEnabled`(8×), `canCrouch`, `canProne`, `canLean`, `canSprintWhileStrafing`, `strafeSpeedMultiplier`, `movementInputPriority`(5×)
- **Stamina:** `maxStamina`, `staminaDrainRate`, `staminaRegenRate`, `staminaRegenDelay`, `staminaSlowdownThreshold`, `staminaRecoveryThreshold`
- **Input bindings:** `gunInputPriority`(18×), `fireGun`, `dropKey`, `keyReload`, `keyChamber`, `keyInspect`, `sightSwitch`, `freeLook`, `holdUp/holdPatrol/holdDown`, `switchFireMode`, `toggleLaser/Flashlight/UBGL`, `toggleAiming`, `holdForScrollZoom`, `keySprint`, `lowerStance`, `raiseStance`, `leanLeft`, `leanRight`
- **Lean/IK:** 17 `movementLean*` keys, `leanAngleDegrees`, `leanLerpRate`, `footIKEnabled`, `footIKRayLength`, `footIKReplicationRate/Threshold`, `replicateMovementLeaning`
- **World:** `glassShatter`, `glassRespawnTime`, `dayNightCycle`, `dayNightPresets`, `dayLengthSeconds`, `ragdolls`, `ragdollAllowManualToggle`, `ragdollCameraFollowOwnDeath`, `destructibleDespawnTime`, `explosionRaycast`, `explosionFalloffExponent`
- **Loot:** `gunDropping`, `dropOnLeave`, `dropKey`, `dropGunAnchorTime`, `dropDespawnTime`, `maxDroppedGuns`, `pickupDistance`, `pickupKey`, `despawnEmptyAmmoBoxes`, `ammoBoxDespawnTime`
- **Meta:** `leaderboard`, `deathScreen`, `lockFirstPerson`, `mobileSupport`, `blurEffects`, `thirdPersonFiring`, `fireWithFreelook`, `canReloadWhileAiming`, `offCenterAiming`, `firstPersonBody`, `lowHealthEffects`, `ammoBoxDespawnTime`

### 8.4 `WeaponStats` (per-Tool `Tool.SPH_Weapon.WeaponStats`) — the primary content API
~150 fields, highest-frequency: `projectile`(60×), `grenade`(43), `LPVOZoom`(39), `UBGL`(37), `fireAnim`(25), `openBolt`(22), `operationType`/`magType`(20 each), `aimFovMax/Min`, `bulletHolder`, `weaponType`, `boltDist`, `aimTime`, `shotgun`, `serverOffset`, `magCheck`, `fireFov`, `ammoType`, `rigParts`, `preFire`, `muzzleVelocity`, `magazineCapacity`, `fireRate`, `damage` (per-body-part table + `.Other`), `damageFalloff`, `recoil`/`gunRecoil`/`rotationalRecoil`, `fireSwitch`, `overHeating`, `fireMoveParts`, `holster`, `disableAutoRigging`, `tracers`/`tracerTiming`/`tracerColor`, `explosiveAmmo`/`explosionRadius`/`explosionEffect`, `ammoType`.

### 8.5 Instance-name conventions (implicit, undocumented contract)
`WeaponRig/{AnimBase/{GunMotor, AnimBase_Grip, BaseWeld, law, raw}, Weapon}` · `gunModel.Grip` (universal mount point) · `Grip/{Muzzle, Laser, Flashlight, Chamber, Chamber/…, InnerSpotLight, OuterSpotLight, Fire, AutoFire, SilencedFire, SilencedAutoFire, Echo, AutoTail, SilencedAutoTail, Click, AimUp, AimDown, Button, SlideRelease}` · `gunModel/{AimPart, AimPart2, Mag, Base}` · `Tool/{SPH_Weapon/WeaponStats, Ammo/{MagAmmo, ArcadeAmmoPool}, Chambered, BoltReady, FireMode, SavedAttachments, UBGLAmmo}` · category mounts `/{OpticPart, GripPart, MuzzlePart, StockPart}/<AttachmentName>` · doors `/{DoorModel/{Main, Hinge1, Hinge2, MainDoor, Kickable, Health}}`.

---

## 9. Failure Points, Bottlenecks, and Implicit Assumptions

### 9.1 Critical — initialization-order deadlock on the server

`init.server.luau` requires `AssetRefs` (line 7) **before** `EventRefs` (line 11).

```
require(AssetRefs)  ──►  require(HitResolutionMod)
                              └─ line 22 (MODULE SCOPE):
                                 SPH_Events.Get("CombatEvents","NPC_HitEvent")
                                   └─ getFolder:  eventsRoot:WaitForChild("CombatEvents", 30)   [30s cap]
                                   └─ folder:WaitForChild("NPC_HitEvent", nil)                 [INFINITE]
```

`EventRefs` — the only code that would `GetOrCreate("CombatEvents","NPC_HitEvent")` — is never reached. **If that BindableEvent is not pre-authored in the `.rbxl`, the server hangs permanently at startup.** The `GetOrCreate` self-healing path is unreachable for this specific event.

The same shape exists on the client: `PlayerClient/init.local.luau` phase 3 does `require(BulletHandler)`, whose module scope runs `SPH_Events.Get("CombatEvents","Suppression")` — an **infinite** wait on an event that **nothing in the repo ever creates**. If `Suppression` is missing, the whole PlayerClient bootstrap deadlocks.

Mitigation already present elsewhere: `Client/StarterCharacterScripts/Client/init.local.luau` has an explicit 57-path replication guard with a 20 s deadline — but the shared modules have no equivalent.

### 9.2 Other correctness risks

| # | Finding | Location |
|---|---|---|
| 1 | **Stray `print` in a per-frame loop** — `print(SharedState.stamina)` executes every RenderStep while sprinting | `CharacterMovement/Stamina.luau:89` |
| 2 | **Type annotation lies** — `ReplicateBolt.Direction` is a `CFrame`; annotated `Vector3?` | `ClientBridgeBindings.luau` |
| 3 | **Duplicated lean implementation** — `ReplicateLean` has two independent client consumers: `RemoteLeanHandler` lerps `RootJoint.C0` + hip `C0` (R6-only, uses `config.leanAngleDegrees`); `BodyAnimReplication` tweens `RootJoint.C1` with a **hardcoded `17`** degrees. Two sources of truth for the same feature. | `ClientBridgeBindings`/`BodyAnimReplication` |
| 4 | **Collision constants duplicated** — `COLLISION_GROUPS` + 20 non-colliding pairs exist twice, once in `Server/Constants.luau` and once in `PlayerClient/Modules/CollisionSetup.luau`; they must be edited in lockstep | both |
| 5 | **13 `print()` calls in server/UI code**, several inside the `ApplyWeaponAttachments` hot path, plus a `HttpService.JSONEncode` purely to log | `NetworkHandlers:858-886`, `GunSetupSystem:195`, `GunDropSystem:138`, `CustomizeGunGUI` |
| 6 | **`ClearOriginalStats` is an empty function** — dead API on `AttachmentManager` | `AttachmentManager.luau` |
| 7 | **Empty `if` body** — `local muzzleConfig = ...; if muzzleConfig then end` | `BulletHandler.FireFX` |
| 8 | **`DebugMuzzleState` computes four locals and discards them** | `AttachmentManager` |
| 9 | **Tween played twice** — `tweenOut:Play()` called on consecutive lines | `WeaponFireMod` fire-blur block |
| 10 | **`processedShots` dedup key is a string concat** on every bullet hit, with a 5 s `task.delay` per entry — allocation + scheduler pressure under sustained fire | `HitResolutionMod` |
| 11 | **Client-authoritative ballistics** — the shooter supplies hit position/normal/instance/material; the server only range/team/ownership-checks. A modified client can forge hits. | whole fire pipeline |
| 12 | **`ClearPlayerShots` does an O(n) scan with `string.match` per key** | `HitResolutionMod` |
| 13 | **Unbounded `dropTable` `table.remove(dropTable, 1)`** — O(n) shift, and `task.delay` closures capture `dropModel` keeping dropped guns alive after eviction | `GunDropSystem` |
| 14 | **`ServerState.dropTable` is never cleared per round** | `GunDropSystem` |
| 15 | **Six parallel copies of the collision-pair table plus a `pcall`-per-pair** in the client copy | `CollisionSetup` |
| 16 | **`GetPlayersInRange` is O(players) per replicate** and is called from many per-shot paths | `NetworkRangeUtil` |
| 17 | **Mag-eject rate limit uses `tick()` while other cooldowns use `os.clock()`** — inconsistent time bases | `NetworkHandlers` |

### 9.3 Code duplication (measured, 12-line normalized windows)

| Duplication | Copies | Notes |
|---|---:|---|
| `BulletHandler.PlaySFX` | **2 × ~150 lines** | The `SilencedAutoFire` and `AutoFire` branches differ only by sound-name prefix (`SilencedAutoFire`/`AutoFire`, `SilencedAutoTail`/`AutoTail`). Parameterizing the prefix collapses ~300 lines to ~150. |
| `WeaponInput.HandleInput` preFire | 2 × ~30 lines | Identical pre-fire animation block appears in the `if` and the `elseif` arms. |
| `HitFX` `SurfaceGui` construction | 3 | Repeated per hit-effect variant. |
| `Client/init.local.luau` | 43 | The `REQUIRED_DESCENDANTS` list and the `require()` block must be manually kept in sync — the file's own comment says so. |
| `CollisionSetup` vs `Constants` | 20 | See #4 above. |
| `ClientBridgeBindings.getOtherPlayerGunModel` | 2 | Intentionally re-implemented; the comment says "to avoid circular requires." A shared helper would be cleaner. |

**~1,500 duplicated lines in the largest groups alone.**

### 9.4 Performance hot spots

1. **`CameraViewmodelMod.Update` (671 lines)** runs every RenderStep and is the single largest per-frame function. It already mitigates with cached `RaycastParams`, a cached head lookup, `ModelQueryCache`, and `SPH_Workspace` exclusion.
2. **`RenderLoop` (CharacterMovement)** does 2 raycasts per frame for foot IK plus a water check on every landing.
3. **`BulletHandler.PlaySFX`** allocates a fresh `Part` host + `Sound` clone **per shot**, parented to `workspace`, disposed by `Debris`. Under full-auto with many players this is the highest-churn path in the codebase. The auto-fire path at least pools by `UserId`.
4. **`GetDescendants()` × 122 call sites** — mitigated in the three hottest paths by `ModelQueryCache`, but still present elsewhere (e.g. `WeaponEquipMod`, `GunSetupSystem`, `AttachmentManager`).
5. **Per-frame `FindFirstChild`** — 756 call sites total.
6. **`AttachmentManager` `OnUpdate`** dispatch calls `pcall(config.OnUpdate, nil, nil, dt)` with `self=nil`, which forces every attachment's updater to be written as a static function.

### 9.5 Implicit assumptions (not enforced anywhere)

1. **All remotes, weapon models, animations, sounds, configs and `ThirdParty.ByteNetMax`/`FastCast` must already exist in the `.rbxl`.** The repo is code-only; there is no installer, project file, or asset manifest.
2. **R6 is the assumed rig.** `ViewMod.RigModel` picks `R6_Arms` for non-R15. `CharacterMovement/RemoteLeanHandler` and several joint lookups are R6-only (`Torso`, `Left Hip`, `Right Hip`) even though `CharacterRefs` detects R15.
3. **`Vars` (~140 fields) is a flat mutable singleton.** Any module that forgets to reset a field leaks state across weapon switches; `Unequip` compensates by brute-force reset.
4. **`weaponFireMod.Update` and `cameraViewmodelMod.Update` are driven only by `UpdateLoops`.** If `UpdateLoops.init()` never runs, the gun silently never fires.
5. **ByteNet `.listen/.send` semantics are trusted** — e.g. `packet.listen(cb)` returns a disconnect function (relied on by `ClientBridge`).
6. **Every gun model has a `Grip`, a `Muzzle`, and `fireMoveParts` entries that exist as `Motor6D`s** — violations fail silently (`if m6d then`).
7. **`config.maxStamina`, `config.strafeSpeedMultiplier`, etc. are non-nil** — most accessors guard with `or default`, but not all.
8. **The animation cache LRU (3 entries) destroys `AnimationTrack`s on eviction** — a gun swapped rapidly 4× can evict a still-referenced track.
9. **`AttachmentManager` state is keyed by `weaponModel` instance** and relies on `Destroying` hooks plus weak keys for cleanup.

---

## 10. Strengths

1. **Explicit, documented phase ordering.** Every entry point names its phases and explains *why* the order matters. The 20 s replication guard with a 57-path manifest and a shared deadline is unusually disciplined.
2. **Clean cycle-breaking.** `WeaponContext` + `Init(deps)` + `WeaponBindings` facade is a coherent, if verbose, answer to Luau's lack of DI. Nothing requires a circular import at runtime.
3. **`ModelQueryCache` is genuinely excellent** — weak-keyed, nil-caching via a frozen sentinel, `DescendantAdded/Removing` invalidation, dead-parent revalidation, and hit/miss statistics. The header comment documents exactly what it does *not* catch (renames).
4. **Defense in depth on client→server input.** CFrame NaN/∞ rejection, `MAX_ARM_C0_DISTANCE`, `ArmC0` ownership locking, packet-ignore windows, epsilon dedup, fire-mode whitelist, grenade throw origin clamping to ≤6 studs, pending-tool validation on the 2-phase throw, and 5 s shot dedup.
5. **Self-terminating event loops.** `ArmLerpSystem` and `AttachmentManager` start Heartbeats on demand and disconnect when their work set empties.
6. **Server-authoritative damage with client-predicted visuals.** Correct trust boundary for damage; visuals replicated to a distance-culled audience.
7. **Graceful degradation on missing assets** — most `FindFirstChild` chains `warn` with actionable messages ("did you forget to move it into the folder?") and fall back rather than erroring.
8. **Resource discipline** — 173 `pcall`s around genuinely unsafe operations, `Debris` everywhere, `PartCache` pooling for bullets/voxels, `ConnectionManager` for equip-scoped teardown.
9. **Genuine simulation depth** — bolt cycling with real Motor6D travel, chamber-state machine, shell ejection, auto-fire sound pooling with tail variants, 6 collision groups, destructible HP attributes, voxel smoke disturbed by bullet segments.

## 11. Improvement Opportunities (ranked; not yet applied)

**High**
1. Fix the `NPC_HitEvent` / `Suppression` bootstrap deadlock — give `SPH_Events.Get` a bounded default timeout and/or move `EventRefs` above `AssetRefs` in `init.server.luau`.
2. Remove `Stamina.luau:89` `print`.
3. Collapse the 2 × 150-line `PlaySFX` duplication behind a sound-name-prefix parameter.

**Medium**
4. Deduplicate the collision-group tables into one shared `Modules/Core` constant used by both server and client.
5. Unify the lean implementation (pick one `ReplicateLean` consumer; source the 17° from config).
6. Replace the manual `REQUIRED_DESCENDANTS` list with a single traversal.
7. Strip the 13 `print()` calls and the per-attachment `JSONEncode` log in `NetworkHandlers`.
8. Add spatial partitioning or memoized AOI to `NetworkRangeUtil`; it is on every replicate path.

**Low**
9. Hoist/reuse `RaycastParams` and cached lookups in `RenderLoop` and `WeaponEquipMod`; replace remaining hot `GetDescendants()` with `ModelQueryCache`.
10. Pool the per-shot `Part`+`Sound` hosts in `PlaySFX`.
11. Remove dead code: `ClearOriginalStats`, `DebugMuzzleState`, the empty `if` in `FireFX`, the duplicate `tweenOut:Play()`.
12. Standardize on one time base (`os.clock` vs `tick`).
13. Make the `wepStats` contract explicit — a typed schema/validator at `require(tool.SPH_Weapon.WeaponStats)` time would convert dozens of silent `nil` paths into one actionable error.

---

## 12. Conclusion

`SPH` is a mature, deeply-featured FPS framework whose architecture is dominated by one decision: **preserving the exact execution order of a former monolith while splitting it into 187 files.** That decision is visible everywhere — in the phase-numbered entry points, the `Init(deps)` context-injection style, the `WeaponBindings` facade, the centralized `vars`/`ServerState`/`SharedState` tables, and the explicit "identical logic / to avoid circular requires" comments.

The trade-off is a codebase that is highly *ordered* but weakly *typed* and weakly *isolated*: ~140 shared mutable state fields, ~180 loosely-typed config keys, ~150 loosely-typed weapon-stat keys, and a fully implicit instance-name contract. Correctness today depends on the ordering being preserved and on assets existing in the place; the sharpest edges are the module-scope `WaitForChild` calls that can deadlock bootstrap, and the silent-`nil` failure mode of the `WeaponStats` contract.

The engineering *inside* each subsystem — `ModelQueryCache`, the self-terminating heartbeats, the arm-motor conflict protocol, the replication-guard bootstrap, the anti-exploit input validation — is notably above average for the platform.

---

**Repository remains unmodified. Standing by for instructions.**
