# Installing the AnimSaves Bulk Uploader

The plugin is distributed as a **single `.luau` file** you paste into a Roblox
Studio `Script` and save as a **local plugin**. It has no dependencies, no
external modules and no build step on your machine.

There are exactly two requirements:

1. The Script must be installed as a **local plugin**, not from the Creator
   Store.
2. Your Studio account must have the **asset creation** permission (you are
   logged in, and not restricted by place privacy settings).

Both are explained below.

---

## 1. Get the plugin file

Either use the prebuilt file that ships with this repository:

```
Plugin/dist/AnimSavesBulkUploader.luau
```

…or regenerate it from the authored sources (Python 3.8+, no packages needed):

```bash
python3 Plugin/build_plugin.py
```

The build is deterministic. `Plugin/dist/AnimSavesBulkUploader.luau` is checked
in, so `python3 Plugin/build_plugin.py --check` will tell you whether the
sources have drifted from the shipped build.

**Do not edit the generated file.** Edit `Plugin/Modules/*.luau` or
`Plugin/MainPlugin.luau` and rebuild.

---

## 2. Paste it into a Script

1. Open Roblox Studio with any place.
2. In the Explorer, right-click **ServerScriptService** (or anywhere else — it
   genuinely does not matter) → **Insert Object…** → **Script**.
3. Delete the default `print("Hello world!")` body.
4. Select all (`Ctrl`/`Cmd` + `A`) and paste the **entire contents** of
   `AnimSavesBulkUploader.luau`.
5. Rename the Script to `AnimSavesBulkUploader` so you can find it again.

> The Script must be a **Script**, not a `LocalScript` and not a
> `ModuleScript`. The plugin calls `assert(plugin, …)` at the top and will fail
> loudly if it is installed as anything else.

---

## 3. Save it as a local plugin

1. Right-click the Script in the Explorer.
2. Choose **Save to File…**
3. Save it as `AnimSavesBulkUploader.rbxmx` into your local Plugins folder:

   | OS | Path |
   | --- | --- |
   | Windows | `%LOCALAPPDATA%\Roblox\Plugins` |
   | macOS | `~/Documents/Roblox/Plugins` |

   Create the `Plugins` folder if it does not exist yet.

4. **Restart Roblox Studio.** Plugins are only enumerated at startup.
5. Open any place. You should now see an **ANIM** button in the Plugins tab of
   the ribbon.

You can now delete the Script you used for the paste — the plugin lives in the
`.rbxmx`.

### Updating later

Repeat steps 2–4 with the new `.rbxmx`. Because the binary cache is stored in
**Plugin settings**, it survives the update; you will not re-upload everything.

---

## 4. Enable the upload API

`AssetService:CreateAssetAsync` ships as a **beta feature**. If it is not
enabled, the plugin will still load, but the upload button reports:

```
Upload path unavailable: AssetService could not be acquired.
```

To turn it on:

1. **File → Beta Features…** (Studio → Settings → Beta Features on macOS).
2. Enable **CreateAssetAsync Luau API**.
3. Restart Studio.

If the toggle is not present, your Studio build already includes it.

### You must be logged in

`plugin:GetStudioUserId()` must be non-zero. If Studio is running signed out,
uploads fail with `PermissionDenied`. The plugin warns about this at startup.

---

## 5. Your first upload

1. **Select a rig** in the Explorer. The rig is any `Model` (or `Folder`) that
   contains a child named **`AnimSaves`**.
2. Click the **ANIM** button.
3. The list fills with every `KeyframeSequence` found, each marked **New**,
   **Changed**, **Clean** or **Incomplete**.
4. Pick your filters (or leave them alone) and press **Upload**.

### What `AnimSaves` can look like

The scanner applies one unified rule — *`AnimSaves:GetChildren()` filtered by
`IsA("KeyframeSequence")`* — so these all work identically:

| `AnimSaves` class | Contents |
| --- | --- |
| `Model` | `KeyframeSequence` children directly |
| `ObjectValue` | `KeyframeSequence` children directly (`.Value` is read as an alias for the rig name) |
| `Folder` / `Model` | nested sub-folders, each holding sequences (recorded with a `subPath`) |

No hardcoded rig paths are used anywhere. The rig comes from Studio's
Selection, or from the picker in the plugin's own UI.

### Where results are written

Every successful upload writes a `StringValue` named after the animation into a
`UploadedAnimations` folder **inside the rig**:

```
Workspace
└── MyRig (Model)
    ├── AnimSaves (Model)
    │   ├── Idle   (KeyframeSequence)
    │   └── Walk   (KeyframeSequence)
    └── UploadedAnimations (Folder)      ← created by the plugin
        ├── Idle (StringValue, Value = 13123456789)
        └── Walk (StringValue, Value = 13123456790)
```

Re-uploading an animation **updates** the existing `StringValue` instead of
creating a duplicate.

---

## 6. Options

The options panel is inside the widget (top-right of the header).

| Option | Values | Effect |
| --- | --- | --- |
| Cache backend | `Settings` / `StringValue` | Where the binary cache blob is stored. `Settings` keeps the rig clean; `StringValue` travels with the rig when you publish it. |
| Hash mode | `Deep` / `Fast` | `Deep` hashes pose CFrames, easing and names (catches any edit). `Fast` hashes keyframe times and counts only (much cheaper on very large rigs). |
| Creator type | `User` / `Group` | Who owns the uploaded asset. Group uploads require a Group Id. |
| Skip clean | on / off | Skip animations whose digest and asset id both match the cache. |
| Auto re-upload | on / off | Treat `Clean` entries as eligible for re-upload. |

---

## Troubleshooting

| Symptom | Cause | Fix |
| --- | --- | --- |
| `must run inside a Studio plugin` | The Script is not a plugin | Install it via *Save to File…* into the Plugins folder |
| `Upload path unavailable: AssetService could not be acquired.` | Beta feature off | Enable **CreateAssetAsync Luau API** and restart Studio |
| `PermissionDenied` on every upload | Signed out, or place privacy blocks asset creation | Log in to Studio; check place permissions |
| `No 'AnimSaves' container found inside 'X'.` | The selected instance has no `AnimSaves` child | Select the rig itself, not the `AnimSaves` folder |
| The list is empty | Selection is stale | Click the rig in the Explorer again |
| Everything shows `Changed` after an edit | Working as intended | The structural digest detected the edit |
| Everything shows `Clean` after a Studio restart | The cache was restored | That is the point — nothing is re-uploaded |
| The button does nothing | The widget is hidden | Click ANIM again to toggle it |

---

## Uninstalling

Delete `AnimSavesBulkUploader.rbxmx` from your Plugins folder and restart
Studio. The `UploadedAnimations` folders inside your rigs are **not** removed —
delete those manually if you do not want them. The cache blob is removed with
the plugin.
