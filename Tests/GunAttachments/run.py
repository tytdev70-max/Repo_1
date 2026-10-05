#!/usr/bin/env python3
"""Runs the GunAttachments isolation tests with the Luau CLI.

Roblox-style `require(script.X)` / `require(script.Parent.X)` calls are rewritten to
Luau require-by-string so the package runs unmodified outside Roblox.

Usage:  python3 Tests/GunAttachments/run.py [path/to/luau] [path/to/luau-analyze]
"""
import os, re, shutil, subprocess, sys, tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(HERE, "..", ".."))
PKG = os.path.join(REPO, "Modules", "Modules", "ThirdParty", "GunAttachments")

luau = sys.argv[1] if len(sys.argv) > 1 else shutil.which("luau") or "luau"
analyze = sys.argv[2] if len(sys.argv) > 2 else shutil.which("luau-analyze")

build = tempfile.mkdtemp(prefix="ga_test_")
out_pkg = os.path.join(build, "GunAttachments")
os.makedirs(out_pkg)

for name in os.listdir(PKG):
    if not name.endswith(".luau"):
        continue
    src = open(os.path.join(PKG, name)).read()
    if name == "init.luau":
        src = re.sub(r"require\(script\.(\w+)\)", r'require("@self/\1")', src)
    else:
        src = re.sub(r"require\(script\.Parent\.(\w+)\)", r'require("./\1")', src)
    if "require(script" in src:
        sys.exit(f"unrewritten require in {name}")
    open(os.path.join(out_pkg, name), "w").write(src)

for name in ("mocks.luau", "spec.luau", "spec_shim.luau", "spec_extended.luau", "spec_template.luau", "spec_presets.luau", "spec_presets_ui.luau", "gui_globals.luau", "SPHAttachmentsMock.luau"):
    shutil.copy(os.path.join(HERE, name), os.path.join(build, name))

# Pure modules of the Customize UI (no Roblox dependencies).
CUSTOMIZE = os.path.join(REPO, "Modules", "Modules", "Weapons", "UI", "Customize")
out_customize = os.path.join(build, "Customize")
os.makedirs(out_customize)
for name in ("Signal.luau", "Selection.luau", "Catalog.luau", "Config.luau"):
    src = open(os.path.join(CUSTOMIZE, name)).read()
    src = re.sub(r"require\(script\.Parent\.(\w+)\)", r'require("./\1")', src)
    if "require(script" in src:
        sys.exit(f"unrewritten require in Customize/{name}")
    open(os.path.join(out_customize, name), "w").write(src)

# Preset rules (pure).
os.makedirs(os.path.join(build, "Presets"))
PRESETS = os.path.join(REPO, "Modules", "Modules", "Weapons", "Presets")
shutil.copy(os.path.join(PRESETS, "PresetBook.luau"), os.path.join(build, "Presets", "PresetBook.luau"))

# The template view uses Roblox GUI globals; inject them from gui_globals.luau.
os.makedirs(os.path.join(out_customize, "View"))
src = open(os.path.join(CUSTOMIZE, "View", "Template.luau")).read()
names = ["game", "Instance", "TweenInfo", "Enum", "UDim2", "Vector2", "Color3", "task", "warn", "typeof"]
header = 'local __G = require("../../gui_globals")\n' + "".join(f"local {n} = __G.{n}\n" for n in names)
src = src.replace("--!nonstrict\n", "--!nonstrict\n" + header, 1)
open(os.path.join(out_customize, "View", "Template.luau"), "w").write(src)

# The controller (requires rewritten, Roblox globals injected the same way).
src = open(os.path.join(CUSTOMIZE, "Controller.luau")).read()
src = re.sub(r"require\(script\.Parent\.(\w+)\)", r'require("./\1")', src)
header = 'local __G = require("../gui_globals")\n' + "".join(f"local {n} = __G.{n}\n" for n in names)
src = src.replace("--!nonstrict\n", "--!nonstrict\n" + header, 1)
if "require(script" in src:
    sys.exit("unrewritten require in Customize/Controller")
open(os.path.join(out_customize, "Controller.luau"), "w").write(src)

# The deprecated SPH shim, re-pointed at the mock-backed SPHAttachments stand-in.
shim = open(os.path.join(REPO, "Modules", "Modules", "Weapons", "Attachments", "AttachmentManager.luau")).read()
shim = shim.replace("require(script.Parent.SPHAttachments)", 'require("./SPHAttachmentsMock")')
if "require(script" in shim:
    sys.exit("unrewritten require in AttachmentManager shim")
open(os.path.join(build, "AttachmentManager.luau"), "w").write(shim)

if analyze:
    # Parse/type sanity of the package itself (Roblox globals are unknown here, so only
    # syntax errors and non-global diagnostics are treated as failures).
    result = subprocess.run([analyze, out_pkg], capture_output=True, text=True)
    problems = [l for l in (result.stdout + result.stderr).splitlines()
                if l.strip() and "SyntaxError" in l]
    if problems:
        print("\n".join(problems))
        sys.exit("luau-analyze reported syntax errors")
    print("luau-analyze: no syntax errors")

code = 0
for spec in ("spec.luau", "spec_shim.luau", "spec_extended.luau", "spec_template.luau", "spec_presets.luau", "spec_presets_ui.luau"):
    proc = subprocess.run([luau, spec], cwd=build, capture_output=True, text=True)
    sys.stdout.write(proc.stdout)
    sys.stderr.write(proc.stderr)
    code = code or proc.returncode
sys.exit(code)
