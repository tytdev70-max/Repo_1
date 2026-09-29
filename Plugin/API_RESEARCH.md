# API research

The Roblox APIs this plugin relies on, what the documentation actually says, and
how each constraint is honoured in code. Everything below was checked against
the official Creator Documentation and the DevForum threads that motivated the
design.

Links are given so the claims can be re-verified. Where a claim comes from
community experimentation rather than official docs, it says so.

---

## 1. `AssetService:CreateAssetAsync` — the upload path

### What it is

```lua
local AssetService = game:GetService("AssetService")

local result, extra = AssetService:CreateAssetAsync(
	keyframeSequence,              -- Instance
	Enum.AssetType.Animation,      -- Enum.AssetType
	params                         -- table
)
```

A **yielding** method that uploads a `KeyframeSequence` as an animation asset.

### Return value

A tuple. On success:

| Position | Value |
| --- | --- |
| 1 | `Enum.CreateAssetResult.Success` |
| 2 | the new **asset id** (a `number`) |

On failure:

| Position | Value |
| --- | --- |
| 1 | one of `PermissionDenied`, `UploadFailed`, `Unknown`, … |
| 2 | a human-readable diagnostic string |

### The catch that shaped `UploadService`

> If the method cannot be called at all — for example the beta feature is not
> enabled in Studio — it **raises a Lua error** instead of returning an error
> tuple.

That is why every call site is wrapped in `pcall`, and why `IsAvailable()`
exists. Without it, a plugin installed on a Studio build without the beta
feature would appear to work and then throw on the first upload.

`UploadService:UploadOne` therefore treats three outcomes distinctly:

```lua
local ok, result, extra = pcall(function()
	return AssetService:CreateAssetAsync(sequence, Enum.AssetType.Animation, params)
end)

if not ok then
	-- the method itself could not be called (beta feature off, etc.)
	outcome.resultEnum = "Unknown"
	outcome.message = tostring(result)
elseif result == Enum.CreateAssetResult.Success then
	outcome.success = true
	outcome.assetId = tonumber(extra)
else
	outcome.resultEnum = tostring(result)
	outcome.message = tostring(extra)
end
```

### Rate limit

Documented at roughly **30 requests per minute**. The default is therefore
`RequestsPerMinute = 20`, leaving headroom for retries. `WaitForSlot()` enforces
it with a token-bucket-style delay rather than a fixed sleep, so the throttle
stays accurate when individual uploads are slow.

### Retry policy

| `Enum.CreateAssetResult` | Retried? | Why |
| --- | --- | --- |
| `Success` | — | done |
| `UploadFailed`, `Unknown` | **yes** (default 2) | transient; usually worth another attempt |
| `PermissionDenied` | **no** | retrying spams the user with the same popup |
| `AssetNameTooLong`, `InvalidName` | **no** | deterministic; will fail identically |
| `QuotaExceeded` | **no** | needs user action, not a retry |
| `TooManyRequests` | **yes** | that is exactly what the backoff is for |

### Parameters

```lua
local params = {
	Name = sequence.Name,
	Description = options.DescriptionTemplate,
	Creator = {
		CreatorType = Enum.AssetCreatorType.User,   -- or .Group
		CreatorId   = 0,                            -- the group id for group uploads
	},
}
```

`Enum.AssetCreatorType.User` and `Enum.AssetCreatorType.Group` are the two
values that matter. For group uploads `CreatorId` **must** be the group id —
passing 0 with `CreatorType = Group` fails with `PermissionDenied`.

### Never called

These members are deprecated or removed and are deliberately absent:

* `AssetService:PromptCreateAssetAsync`
* `AssetService:PromptPublishAssetAsync`
* `AssetService:CreatePlaceAsync`
* anything in `ClipEditor`

---

## 2. The local-plugin requirement

> `AssetService:CreateAssetAsync` is **unavailable to plugins installed from the
> Creator Store**. It only works from a **local plugin**.

This is the single hardest constraint in the project, and it is why the plugin
ships as a single `.luau` file to be pasted into a Script and saved via
*Save to File…* into the local Plugins folder, rather than published.

Consequences:

* `MainPlugin.luau` asserts it is running as a plugin
  (`assert(plugin, "…")`) rather than silently doing nothing.
* `INSTALL.md` leads with the local-plugin step.
* `IsAvailable()` is surfaced in the UI so the user finds out before a
  400-upload run, not during it.

Source: Creator Documentation, *Plugins → Local Plugins*.

---

## 3. `KeyframeSequence` traversal

The animation data model:

```
KeyframeSequence
├── Keyframe            (Time, Name)
│   ├── Pose            (Name, Weight, EasingStyle, EasingDirection, CFrame)
│   │   └── Pose        (sub-poses, recursive)
│   └── Marker          (Name, Value)
```

| Member | Notes |
| --- | --- |
| `KeyframeSequence:GetKeyframes()` | returns `{Keyframe}` — order is **not** guaranteed to be sorted by `Time` |
| `Keyframe:GetPoses()` | returns `{Pose}` |
| `Pose:GetSubPoses()` | returns `{Pose}` — recursive |
| `Keyframe:GetMarkers()` | returns `{Marker}` |
| `Pose.CFrame` | a `CFrame`; only `CFrame:GetComponents()` is read |
| `Pose.EasingStyle` | an `Enum` item |
| `KeyframeSequence.Loop` | a `boolean` |

### The ordering problem

`GetKeyframes()` does not promise sorted output. Two consequences:

1. **The digest sorts keyframe times before hashing them**, so re-ordering
   keyframes in the Animation Editor does not register as an edit. Only actual
   changes do.
2. **`RigScanner` sorts entries itself** (`_sortEntries`, by
   `Util.sortKey`), so the UI list is stable across scans.

### Reading CFrame safely

`CFrame:GetComponents()` returns 12 numbers. They are hashed as text with a
fixed number of decimal places (`string.format("%.6f", v)`) rather than as raw
doubles, because floating-point noise would otherwise make every digest change
between sessions.

---

## 4. `string.pack` / `string.unpack`

Luau's `string.pack` with format options:

| Option | Meaning | Used for |
| --- | --- | --- |
| `<` | little-endian | every field |
| `c4` | exactly 4 bytes | the `"ASUC"` magic |
| `I1` | unsigned 8-bit | version, globalFlags, priority, flags |
| `I4` | unsigned 32-bit | counts, checksums, hash halves |
| `I8` | unsigned 64-bit | assetId, uploadedAt |
| `d` | double (8 bytes) | clip length |
| `s2` | 2-byte length prefix + data | names, rig name |

### Three things that are easy to get wrong

**1. Integral options raise on overflow.** `string.pack("<I4", 2^32)` errors
rather than truncating. Every count is therefore clamped to unsigned 32-bit
*before* packing (`clampU32`), with an explicit NaN/negative guard.

**2. `I8` is probed, not assumed.** It exists on every current Roblox client,
but the probe costs nothing:

```lua
local function supportsInt64(): boolean
	local ok, result = pcall(function()
		local packed = string.pack("<I8", 1)
		return #packed == 8 and string.unpack("<I8", packed) == 1
	end)
	return ok and result == true
end
```

If it ever disappears, the format falls back to `"<I4I4"` — the value split into
two exact 32-bit halves, which is safe on any Luau build.

**3. Luau numbers are doubles.** Exact only to 2⁵³. Asset ids fit comfortably,
but a 64-bit value must never be produced by arithmetic that overflows a double.
`Util.mulMod32` exists precisely because `a * b` on two 32-bit values silently
loses precision; it splits both operands into 16-bit halves, multiplies the
halves, and recombines mod 2³². It is verified exact against 10 cases computed
independently with JS `BigInt`.

---

## 5. `Enum` members used

| Enum | Members | Purpose |
| --- | --- | --- |
| `Enum.AssetType` | `Animation` | the upload target type |
| `Enum.AssetCreatorType` | `User`, `Group` | upload ownership |
| `Enum.CreateAssetResult` | `Success`, `PermissionDenied`, `UploadFailed`, `Unknown`, `QuotaExceeded`, `TooManyRequests`, `AssetNameTooLong`, `InvalidName` | outcome classification |
| `Enum.InitialDockState` | `Float` (and others) | widget placement |
| `Enum.Font` | `Legacy`, `Arial`, `Gotham`, `Code`, … | UI text |
| `Enum.TextXAlignment` / `Enum.TextYAlignment` | `Left`/`Center`/`Right`, `Top`/`Center`/`Bottom` | UI text alignment |

---

## 6. Storage: why base64url, and why not JSON

Both available storage channels are **text**:

| Channel | Serialised as | Consequence |
| --- | --- | --- |
| `plugin:SetSetting` / `GetSetting` | JSON | values must be valid JSON |
| `StringValue.Value` | XML (the place file) | values must be valid XML text |

A binary blob is neither. So the blob is encoded before it is written.

### Why base64url rather than plain base64 or hex

| Encoding | Size vs raw | JSON-safe | XML-safe | Why not |
| --- | --- | --- | --- | --- |
| plain base64 | +33 % | yes | **no** — `+` and `/` are not XML-safe | breaks in `StringValue` |
| hex | +100 % | yes | yes | doubles the blob for no benefit |
| **base64url** | **+33 %** | **yes** | **yes** | — |

base64url (`[A-Za-z0-9-_]`) avoids `+` and `/`, which are the two characters
that make plain base64 unsafe in XML. `=` padding is safe in both JSON and XML
and is used normally.

### Why not just store a Lua table?

Storing one table per animation in Plugin settings costs far more than 60 bytes
per animation, because the settings store serialises to JSON and every field
name is repeated. With 400 animations that is hundreds of kilobytes of JSON that
must be parsed, diffed and re-serialised on every Studio session. The binary
blob is ~70 bytes per animation, checksummed, and parsed once.

---

## 7. UI: `DockWidgetPluginGui`

Created with the modern yielding API, falling back to the deprecated sync one:

```lua
local ok, widget = pcall(function()
	return plugin:CreateDockWidgetPluginGuiAsync(id, info)
end)
if ok and widget then
	return widget
end
return plugin:CreateDockWidgetPluginGui(id, info)
```

`DockWidgetPluginGuiInfo.new(InitialDockState, initiallyEnabled,
overrideEnabled, defaultWidth, defaultHeight, minWidth, minHeight)`.

The whole UI is built at runtime with `Instance.new` — there is no `.rbxmx` UI
asset to keep in sync with the code, and no risk of a stale widget being
installed alongside new logic.

---

## 8. Things that are *not* used, on purpose

| API | Why not |
| --- | --- |
| `ClipEditor` / the Animation Editor | opens a UI, requires selection, is not scriptable for bulk work |
| `AssetService:PromptCreateAssetAsync` | deprecated; opens a dialog per asset |
| `KeyframeSequenceProvider` | designed for the Animation Editor's save/load flow, not bulk upload |
| `HttpService:JSONEncode` for the cache | 3–5× larger than the binary blob for the same data |
| `DataStoreService` | plugin-side storage is the wrong tool; this is a Studio-time tool, not a live-game one |
| hardcoded rig paths (`Workspace.Rig.AnimSaves`) | breaks the moment a user renames or re-parents anything |

---

## 9. Sources

* Creator Documentation — *AssetService:CreateAssetAsync*
* Creator Documentation — *Plugins → Local Plugins*
* Creator Documentation — *KeyframeSequence*, *Keyframe*, *Pose*, *Marker*
* Creator Documentation — *string.pack / string.unpack (Luau)*
* Creator Documentation — *Enum.AssetCreatorType*, *Enum.CreateAssetResult*
* Creator Documentation — *DockWidgetPluginGui*
* DevForum — "CreateAssetAsync is now available" (beta feature announcement and
  local-plugin-only constraint)
* DevForum — community rate-limit measurements (~30 requests/minute)
