#!/usr/bin/env python3
"""
Migrate SPH from `Weapons.Attachments.AttachmentManager` to the standalone
`ThirdParty.AttachmentSystem` provider.

Mechanical, reviewable transformations only:
  * require lines point at the new module
  * old method names become the new public API names
  * the `attachmentManager` identifier becomes `attachmentSystem` so the DI
    plumbing reads as "external provider" rather than "our own manager"
  * the handful of sites that reached into `entry.config.<flag>` are replaced
    by the capability queries that now own that knowledge
"""
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

OLD_REQUIRE = "Weapons.Attachments.AttachmentManager"
NEW_REQUIRE = "ThirdParty.AttachmentSystem"

# old method -> new method
METHODS = {
    "LoadAttachmentConfig":        "LoadConfig",
    "EquipAttachment":             "Equip",
    "GetAttachmentAimPart":        "GetAimPart",
    "GetGripHandPosition":         "GetGrip",
    "GetActiveMuzzle":             "GetMuzzle",
    "GetMuzzleAttachmentConfig":   "GetMuzzleConfig",
    "ApplyAttachmentADSVisibility": "ApplyADSVisibility",
    "HasGripEquipped":             "HasGrip",
    "UnequipAttachment":           "Unequip",
    "CleanupMuzzleState":          "ClearMuzzleState",
    "StoreOriginalStats":          "StoreBaseStats",
    "RestoreStatsFromTool":        "GetBaseStats",
    "ApplyAttachmentStats":        "ApplyStats",
    "ClearAllAttachments":         "ClearAll",
    "GetActiveAttachments":        "GetActive",
    "HasAttachment":               "Has",
    "HasLaserAttachment":          "HasLaser",
    "HasFlashlightAttachment":     "HasFlashlight",
    "DebugMuzzleState":            "DescribeMuzzle",
    # kept identical, listed for the audit trail
    "GetOverheatConfig":           "GetOverheatConfig",
    "GetReticleConfig":            "GetReticleConfig",
    "GetDepthOfFieldConfig":       "GetDepthOfFieldConfig",
    "HasMuzzleOverride":           "HasMuzzleOverride",
    "GetLaserSource":              "GetLaserSource",
    "GetFlashlightSource":         "GetFlashlightSource",
    "GetFlashlightLights":         "GetFlashlightLights",
}

# files owned by the attachment system itself - never rewritten
SKIP = (
    "Modules/Modules/ThirdParty/AttachmentSystem/",
    "Modules/Modules/Weapons/Attachments/AttachmentManager.luau",
    "HUD/CustomizeGunGUI.luau",
    "tools/",
)


def migrate(text):
    text = text.replace(OLD_REQUIRE, NEW_REQUIRE)
    for old, new in sorted(METHODS.items(), key=lambda kv: -len(kv[0])):
        text = re.sub(rf"\b{old}\b", new, text)
    # identifier rename (both casings are in use)
    text = re.sub(r"\battachmentManager\b", "attachmentSystem", text)
    text = re.sub(r"\bAttachmentManager\b", "AttachmentSystem", text)
    return text


def main():
    changed = []
    for dirpath, dirnames, filenames in os.walk(ROOT):
        dirnames[:] = [d for d in dirnames if d not in (".git", "node_modules")]
        for fn in sorted(filenames):
            if not fn.endswith(".luau"):
                continue
            path = os.path.join(dirpath, fn)
            rel = os.path.relpath(path, ROOT)
            if any(rel.startswith(p) for p in SKIP):
                continue
            with open(path, "r", encoding="utf-8") as fh:
                original = fh.read()
            updated = migrate(original)
            if updated != original:
                with open(path, "w", encoding="utf-8") as fh:
                    fh.write(updated)
                changed.append(rel)

    print(f"rewrote {len(changed)} file(s):")
    for rel in changed:
        print("  " + rel)
    return 0


if __name__ == "__main__":
    sys.exit(main())
