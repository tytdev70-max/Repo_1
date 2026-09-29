# AnimSaves Bulk Uploader

A Roblox Studio plugin that bulk-uploads every `KeyframeSequence` in a rig to
Roblox as animation assets, in one click, without ever opening the Animation
Editor.

It keeps a compact binary cache of what has already been uploaded, so a second
run over the same rig uploads **nothing**.

---

## What it does

1. **Finds the rig** from Studio's Selection (or the UI's own picker).
2. **Collects every animation** under an `AnimSaves` container.
3. **Asks the cache** whether each one has changed since the last upload.
4. **Uploads only what changed**, throttled and retried, one Roblox permission
   popup for the whole batch.
5. **Writes the asset ids back** into the rig as `StringValue`s under
   `UploadedAnimations`.

## What it deliberately does not do

* It never opens `ClipEditor`, the Animation Editor, or any publish dialog.
* It has no hardcoded rig paths.
* It never re-uploads an animation whose structural digest and asset id both
  match the cache.

---

## Install

See **[INSTALL.md](INSTALL.md)**. In short: paste
`dist/AnimSavesBulkUploader.luau` into a `Script`, *Save to File…* into your
local Plugins folder, restart Studio, and enable the **CreateAssetAsync Luau
API** beta feature.

---

## Layout

```
Plugin/
├── MainPlugin.luau                  entry point (a Script)
├── Modules/
│   ├── Util.luau                    hashing, base64/hex, formatting
│   ├── RigScanner.luau              rig discovery + sequence collection
│   ├── BinaryCacheService.luau      binary serialisation + dirty detection
│   ├── UploadService.luau           AssetService:CreateAssetAsync
│   ├── RegistrationService.luau     asset ids -> StringValues in the rig
│   └── UIController.luau            the DockWidgetPluginGui
├── build_plugin.py                  folds everything into one paste-able file
├── dist/AnimSavesBulkUploader.luau  the generated single-file build
├── INSTALL.md                       installation walkthrough
├── ARCHITECTURE.md                  how it works, and why
├── API_RESEARCH.md                  the Roblox APIs used, with sources
└── README.md                        this file
```

Edit the sources under `Modules/`, never `dist/`.

---

## Building

```bash
python3 Plugin/build_plugin.py            # write Plugin/dist/AnimSavesBulkUploader.luau
python3 Plugin/build_plugin.py --check    # fail if the checked-in build is stale
python3 Plugin/build_plugin.py -o out.luau
```

The build is deterministic and needs only the standard library.

---

## Testing

The plugin is verified by running the **real Luau sources inside a real Luau
VM** (Luau v739 via WASM), not by reading them. One command:

```bash
bash /home/user/luau_tests/run_all.sh
```

That does four things:

1. rebuilds the single-file build and fails if the checked-in copy is stale;
2. syntax- and scope-checks every authored source and the generated build;
3. runs the runtime suite against `Plugin/Modules/*.luau`;
4. runs the same suite against the **folded** build, booted for real under a
   Roblox shim — which also proves the entry point loads.

```
================ 73/73 checks passed ================
```

Run either backend on its own with:

```bash
node /home/user/luau_tests/run.mjs           # Modules/*.luau
node /home/user/luau_tests/run.mjs --folded  # dist/AnimSavesBulkUploader.luau
```

### What is covered

| Area | Checks |
| --- | --- |
| `Util` | base64 over all 256 byte values and every padding path; hex; `TWFu` vector; invalid input raises; hash determinism and 32-bit range; FNV-1a streaming; `mulMod32` exact mod 2³² against `BigInt`-computed values; formatters; `normalizeAssetId` |
| `BinaryCacheService` | 255 synthetic entries (NUL bytes, 200-char names, quotes, backslashes); field-by-field round-trip; corrupt / bad-magic / truncated / empty blobs; all four states; digest mutation → `Changed`; orphan pruning; `MarkDirty`; deterministic re-serialisation; JSON-safe settings key |
| Precision | asset ids `1 … 9007199254740991` survive pack/unpack exactly |
| Scale | 10 000 entries → 634 KB blob, under the 1 MiB cap |
| `RigScanner` | `Model` and `ObjectValue` containers behave identically; `.Value` alias; deterministic sort; sub-folder `subPath` |
| `RegistrationService` | create vs update, no duplicate `StringValue`s, `GetExistingIds`, graceful bad input, `RegisterBatch` tally, `Reconcile` |
| `I4I4` fallback | the same 64-bit ids round-trip with `string.pack`'s `I8` option forced off, at the same 66 B/entry; an `I8` blob is rejected rather than mis-parsed |

### Five bugs this found

All of them passed manual review, because each produced correct output on the
obvious input:

1. **base64 padding.** No `=` padding, so the decoder always emitted 3 bytes per
   group. Every input whose length was not a multiple of 3 gained spurious
   trailing zero bytes. `"Man" → "TWFu"` passed — the simple vectors were all
   multiples of 3.
2. **`length` stored as float32.** ~7 significant digits was not enough; a long
   clip drifted and the reloaded entry stopped comparing equal to the in-memory
   one. Now a double.
3. **The `I4I4` fallback writer did not exist.** The reader handled the
   split-64 layout; the writer passed one argument to a format expecting two,
   which raises. Dead code on every current client, which is why nobody noticed.
4. **`savedAt` was missing from `WIDE_FIELDS`.** `string.unpack("<I4I4", …)`
   returned `(hi, lo, nextPos)` into a single binding, so the cursor became the
   low 32 bits of the timestamp and every following header field was parsed from
   a garbage offset — silent, total cache loss on a Luau build without `I8`.
5. **`sandbox: true` in the harness disabled `require` inside modules**, so the
   cache suite could not run at all. Not a plugin bug, but exactly the kind of
   thing that makes a suite look like it is passing when it is not.

All five are fixed and covered by regression checks.

### Harness layout

The harness lives outside the repo checkout, at `/home/user/luau_tests/`:

| File | Role |
| --- | --- |
| `run.mjs` | the driver — runs every `.luau` test file |
| `run_all.sh` | build + validate + both backends |
| `roblox_shim.luau` | Roblox stand-ins (`Instance`, `Enum`, `game`, `plugin`, `task`, …) |
| `probe.luau` | Luau capability probe |
| `util_test.luau`, `cache_test.luau`, `precision_test.luau`, `scale_test.luau`, `wide_test.luau`, `scan_test.luau` | the suites |
| `require_bridge.luau` | lets the folded backend also see harness-injected modules |
| `dump_logs.luau` | replays the folded build's own startup output |

Test code is kept in `.luau` files, never inlined into JS: Lua byte escapes
(`\195`) and backslashes are mangled by JS string parsing.

---

## Dependencies

None. The plugin uses only the Roblox API and Luau's standard library. The test
harness needs `node` plus `@luau-rs/luau` and `luau-parser` — install both in
**one** command, they evict each other otherwise:

```bash
npm install --no-save @luau-rs/luau luau-parser
```
