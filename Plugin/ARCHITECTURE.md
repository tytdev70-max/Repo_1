# Architecture

How the AnimSaves Bulk Uploader is put together, and why each piece is shaped
the way it is.

```
Plugin/
├── MainPlugin.luau                     entry point (a Script, not a module)
├── Modules/
│   ├── Util.luau                       hashing + text encoding + formatting
│   ├── RigScanner.luau                 finds the rig, collects the sequences
│   ├── BinaryCacheService.luau         binary serialisation + dirty detection
│   ├── UploadService.luau              AssetService:CreateAssetAsync
│   ├── RegistrationService.luau        writes asset ids back into the rig
│   └── UIController.luau               the DockWidgetPluginGui
├── build_plugin.py                     folds everything into one paste-able file
├── dist/AnimSavesBulkUploader.luau     the generated single-file build
├── INSTALL.md                          how to install it in Studio
├── API_RESEARCH.md                     the Roblox APIs used, with sources
└── README.md                           short overview + test instructions
```

---

## 1. Dependency graph

```
MainPlugin
   ├── RigScanner ─────────────┐
   ├── BinaryCacheService ── Util
   ├── UploadService ──────────┤   (UploadService only needs Enum + game)
   ├── RegistrationService ────┤
   └── UIController ───────────┘
```

`Util` is the only shared leaf. It has **no Roblox instance dependencies at
all** — no `Instance`, no `game`, no `plugin` — which is what makes it testable
outside Studio. Every other module requires `Util` through
`require(script.Parent.Util)`, i.e. as a sibling ModuleScript.

There are **no circular dependencies**. `UploadService` deliberately does *not*
require `BinaryCacheService` just to learn the `"Clean"` state string; it
duplicates that one literal so the two modules stay independent. If the string
ever changes, both modules must change together — that is the one coupling that
is accepted on purpose, and it is called out in a comment in both files.

---

## 2. The pipeline

```
Selection ──► RigScanner:ScanRig ──► BinaryCacheService:Analyze ──► UI list
                                            │                          │
                                            │                    Upload button
                                            ▼                          ▼
                                    (cache lookup)            UploadService:UploadBatch
                                                                       │
                                                          RegistrationService:Register
                                                                       │
                                                          BinaryCacheService:MarkUploaded
                                                                       ▼
                                                                   Save()
```

### 2.1 `RigScanner` — where the animations are

One rule, applied uniformly:

> `AnimSaves:GetChildren()` filtered by `IsA("KeyframeSequence")`.

That is the whole discovery strategy. It is deliberately *not* branchy:

* `AnimSaves` as a `Model` → its `KeyframeSequence` children.
* `AnimSaves` as an `ObjectValue` → the same thing, plus `.Value` is read as an
  alias for the rig name (some rigs name the container after the rig).
* `AnimSaves` holding sub-folders → recursed up to `MaxContainerDepth`, and each
  sequence is tagged with a `subPath` (`"Locomotion/Walk"`).

Because the rule is the same for every container class, a rig that switches from
a `Model` to an `ObjectValue` does not change behaviour. The regression test for
this (`scan_test.luau`) scans two rigs that differ *only* in the container class
and asserts identical counts, names and ordering.

`DiscoverRigs()` walks `Workspace`, `ServerStorage` and `ReplicatedStorage`
looking for candidates, so the user can pick a rig from the UI instead of the
Explorer. There is still no hardcoded path.

`ScanBudget` caps the total number of instances examined so a pathological rig
cannot hang the plugin; the result carries a `truncated` flag when it trips.

### 2.2 `BinaryCacheService` — deciding what to upload

This is the module that makes the tool worth using. It answers one question per
animation: *has this exact animation already been uploaded?*

#### The digest

`ComputeDigest(sequence)` walks the sequence and streams bytes into **two
independent hash accumulators** — FNV-1a (32-bit) and djb2 (32-bit):

* keyframe times (sorted, so re-ordering keyframes does not look like an edit)
* keyframe names
* per pose: name, weight, easing style, easing direction
* per pose: the 12 `CFrame:GetComponents()` values
* sub-poses, recursively
* marker names and values

Two hashes rather than one because a single 32-bit hash collides with
probability ~1/2³² — small, but a collision would silently skip a real upload.
Pairing two *independent* hashes makes that astronomically unlikely while still
costing only 4 extra bytes per entry.

`Digest` is a streaming accumulator, not a buffer: a 50 MB animation never needs
a 50 MB temporary string. `Util.fnv1a32(bytes, seed)` is composable, which is
what makes incremental hashing possible (proven by the "chunked == whole" test).

#### The states

| State | Meaning | Action |
| --- | --- | --- |
| `New` | no cache entry | upload |
| `Changed` | digest or name-hash mismatch | re-upload |
| `Clean` | digest match **and** asset id known | skip |
| `Incomplete` | digest match, no asset id | upload |

`Clean` requires *both* conditions. An entry whose digest matches but which was
never actually uploaded is `Incomplete`, not `Clean` — that distinction is what
keeps a half-finished run from permanently marking animations as done.

#### The binary format

One blob for the whole rig, ~60–70 bytes per animation:

```
header:  magic "ASUC" (c4)
         version (I1)
         globalFlags (I1)
         entryCount (I4)
         rigName (s2)
         savedAt (I8 or I4I4)
         checksum (I4)
entry × N: name (s2)
         nameHashA, nameHashB (I4 × 2)
         digestA,  digestB  (I4 × 2)
         length (d)          ← double, exact round-trip
         keyframes, poses, markers (I4 × 3)
         priority, flags (I1 × 2)
         assetId, uploadedAt (I8 or I4I4)
```

Four details that matter:

* **`length` is a double (`<d`), not a float32.** Float32 has ~7 significant
  digits; a 1000-second clip stored as float32 drifts by ~10⁻⁵ s and would make
  the reloaded entry differ from the in-memory one. Four extra bytes per entry
  buys exactness.
* **64-bit values are never raw Luau numbers.** Luau numbers are IEEE-754
  doubles — exact only to 2⁵³. Asset ids are packed with the explicitly sized
  `I8` option (probed at load time, with an `I4I4` fallback), and all counts are
  clamped to unsigned 32-bit *before* packing because `string.pack` integral
  options raise on overflow rather than truncating.
* **The checksum is over the header and body together**, so a bit flip anywhere
  is detected. A corrupt blob is discarded, never fatal.
* **The blob is base64url-encoded** because both storage channels are text:
  Plugin settings are persisted as JSON, and `StringValue.Value` is persisted as
  XML. Neither can carry raw bytes. `=` padding is safe in both.
* **The `I4I4` fallback is complete on both sides.** `packWide()` writes a wide
  field either as one `I8` or as two exact `I4` halves, and `WIDE_FIELDS` lists
  every wide field including the header's `savedAt`. Both halves were broken
  before the fallback got its own test — see §7.

#### Storage backends

| Backend | Location | Trade-off |
| --- | --- | --- |
| `Settings` (default) | `plugin:SetSetting` | Keeps the rig clean; survives publishing the rig |
| `StringValue` | a `StringValue` inside the rig | travels with the rig; visible in the Explorer |

The settings key is derived from the rig name (`AnimSavesCache_v1_<hash>`),
which is how one cache holds many rigs. The key is checked to be JSON-safe
*by byte value* in the tests — not by pattern escaping — because a `"` or `\`
or a `.` in the rig name is exactly what would break a JSON key.

`EnforceLimits()` caps the cache at `MaxEntries` (10 000) and `MaxBlobBytes`
(1 MiB) by evicting the oldest quarter, so the cache cannot grow without bound
on a pathological rig.

`YieldEvery` makes `Analyze` yield periodically so Studio keeps painting.

### 2.3 `UploadService` — the actual upload

`AssetService:CreateAssetAsync(keyframeSequence, Enum.AssetType.Animation, params)`.

That is the entire upload path. **ClipEditor is never touched** — no rig
selection dialog, no Animation Editor UI, no "three dots → publish". The user
only ever sees Roblox's own permission popup.

What the module adds on top:

* **Throttling** to 20 requests/minute (the API is documented at ~30), enforced
  by `WaitForSlot()`.
* **Retries** (default 2) with a 5-second delay, for transient
  `UploadFailed` / `Unknown` / raised errors. `PermissionDenied` is *not*
  retried — retrying a permission error just spams the user.
* **pcall around the whole call**, because if the beta feature is off the method
  raises instead of returning an error tuple.
* **Cancellation** between items, and a `DryRun()` that walks the identical code
  path without calling the API.
* **`IsAvailable()`** so the UI can grey out the button *before* the user
  starts a 400-upload run.

`UploadBatch` yields between items (`InterItemDelay`) so the Studio UI keeps
painting during a long run.

### 2.4 `RegistrationService` — writing results back

Each successful upload writes a `StringValue` into `UploadedAnimations` inside
the rig:

```
rig (Model)
└── UploadedAnimations (Folder)
    ├── Idle (StringValue)  Value = 13123456789
    └── Walk (StringValue)  Value = 13123456790
```

Re-uploading **updates** the existing `StringValue`; it never creates a
duplicate. That is the single most important invariant in this module, and it is
asserted directly by `scan_test.luau`.

`Reconcile()` cross-checks the cache against what is actually in the folder, so
a cache entry claiming an asset id that the rig does not have is flagged rather
than trusted.

Every method is `pcall`-wrapped and returns a result table with
`action = "created" | "updated" | "failed"` — nothing throws, because a
registration failure must never abort an upload batch that is otherwise
succeeding.

### 2.5 `UIController` — the widget

Built entirely at runtime with `Instance.new`; there is no `.rbxmx` UI asset and
nothing to keep in sync. The widget is a `DockWidgetPluginGui` with a fixed
section-height table (`SECTION_HEIGHT`) that sizes both the sections and the
widget from one source of truth.

Sections, top to bottom: header (32-cell block banner + subtitle), rig panel,
stats strip, filters, the animation list, progress bar, log, footer buttons, and
a collapsible options panel.

The list is virtualised-ish: `_clearRows()` destroys and `_renderRows()`
rebuilds, so 10 000 rows cost 10 000 instances only while they are on screen.

The controller takes its dependencies as a `deps` table (`scanner`, `cache`,
`uploader`, `registration`, `options`, `onRigChanged`) rather than requiring
them, so it never has a hard dependency on the other modules and can be tested
in isolation.

---

## 3. Lifecycle

`MainPlugin.luau` owns everything:

1. **Construction** — builds the five module instances with their option bags.
2. **Toolbar** — one button, id `AnimSavesBulkUploader_Toggle`.
3. **`onStartup`** (in `task.spawn`, so it never blocks Studio):
   * runs `Util.selftestEncodings()` and warns if base64 is broken;
   * asks `UploadService:IsAvailable()` and reports *why* if not;
   * warns if `plugin:GetStudioUserId() == 0`;
   * adopts an already-selected rig if there is one.
4. **Selection** — `ui:ConnectSelection()` watches
   `Selection.SelectionChanged`. Changing rig calls `onRigChanged`, which resets
   the registration session (a new rig means a new folder and a new session).
5. **`plugin.Unloading`** — disconnects the selection, flushes the cache if
   dirty, destroys the widget.

The `options` bag is a single mutable table shared between the UI and the
scan/upload paths. That is deliberate: it avoids an event system for what is
fundamentally a handful of scalars.

---

## 4. Error philosophy

| Situation | Behaviour |
| --- | --- |
| Encoding self-test fails | warn, and fall back to hex |
| Cache blob corrupt | discard it, start clean — never fatal |
| Upload raises | caught, retried, then reported as a failed item |
| Registration fails | reported as `failed`, batch continues |
| No `AnimSaves` container | a clear error in the rig panel |
| Scan budget exceeded | partial results + `truncated` flag |

The one hard failure is `assert(plugin, …)` at the top of `MainPlugin.luau`,
because running outside a plugin is a mistake that cannot be recovered from.

---

## 5. Testing

The plugin is verified by a real Luau VM, not by reading the code. See
`README.md` for the one command that runs everything.

The suite has two backends, and both must be green:

* **`Plugin/Modules/*.luau`** — each module required individually, so a failure
  names the module that broke.
* **`Plugin/dist/AnimSavesBulkUploader.luau`** — the folded single-file build,
  booted for real under a Roblox shim, with its own inline `require` handed to
  the tests. This proves the inlining in `build_plugin.py` did not change
  semantics, and that the entry point actually loads.

73 checks, including:

| Area | What is proven |
| --- | --- |
| `mulMod32` | exact mod 2³² against 10 cases computed with JS `BigInt` |
| FNV-1a | chunked hashing with a seed equals whole-string hashing |
| base64 | round-trip over all 256 byte values, lengths 1..64, every padding path, `TWFu` vector, JSON/XML-safe alphabet, invalid input raises |
| Cache | 255 synthetic entries incl. NUL bytes and 200-char names; field-by-field round-trip; corruption / bad magic / truncation / empty handling; all four states; digest mutation → `Changed`; orphan pruning; `MarkDirty`; deterministic re-serialisation |
| Precision | asset ids `1 … 9007199254740991` survive pack/unpack exactly |
| Scale | 10 000 entries, 634 KB blob, under the 1 MiB cap |
| Scanner | `Model` and `ObjectValue` containers yield identical results; `.Value` alias; deterministic sort; sub-folder `subPath` |
| Registration | create vs update, no duplicates, `GetExistingIds`, graceful bad input, `RegisterBatch` tally, `Reconcile` |
| `I4I4` fallback | the same 64-bit ids round-trip with `string.pack`'s `I8` option forced off, at the same 66 B/entry; an `I8` blob is rejected rather than mis-parsed |

## 7. Bugs the runtime suite found

Five real defects, all fixed, all now covered by regression checks. The pattern
is worth stating plainly: **every one of them passed manual review**, because
each produced correct output on the obvious input.

1. **base64 padding.** The encoder emitted a multiple of 4 characters with no
   `=` padding, so the decoder could not know how many bytes the final group
   encoded and always emitted three. Every input whose length was not a
   multiple of 3 gained spurious trailing zero bytes. `"Man" → "TWFu"` passed,
   which is exactly why it survived review — the simple vectors were all
   multiples of 3.

2. **`length` stored as float32.** Float32 has ~7 significant digits, so a long
   clip drifted by ~10⁻⁵ s and the reloaded entry no longer compared equal to
   the in-memory one. Now a double (`<d`): 4 bytes more per entry, exact.

3. **The `I4I4` fallback writer did not exist.** The reader handled the
   split-64 layout (`hi * 2³² + lo`), but the writer called
   `string.pack("<I4I4", singleValue)` — one argument for a format expecting
   two, which raises. Dead code on every current Roblox client, which is
   precisely why nobody noticed. `packWide()` now implements both layouts.

4. **`savedAt` was missing from `WIDE_FIELDS`.** The split-64 read path keys off
   that table. With `savedAt` absent, `string.unpack("<I4I4", …)` returned
   `(hi, lo, nextPos)` into a single `value` binding, so `nextPos` silently
   became the low 32 bits of the timestamp and every following header field was
   parsed from a garbage offset. The magic check then failed and the whole blob
   was discarded — a silent, total cache loss on any Luau build without `I8`.

5. **`sandbox: true` in the test harness disabled `require` inside modules.**
   Not a plugin bug, but it is why the cache suite could not run at all for
   several iterations, and it is the kind of thing that makes a suite look like
   it is passing when it is not.
