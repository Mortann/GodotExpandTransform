#!/usr/bin/env python3
"""Run real Godot scripts and editor integration tests in an isolated project."""
import argparse
import os
from pathlib import Path
import shutil
import subprocess
import tempfile

parser = argparse.ArgumentParser()
parser.add_argument("--godot", required=True, help="Godot 4.7.2 executable")
parser.add_argument("--gui", action="store_true", help="Use the available display for the editor test")
parser.add_argument("--suite", choices=["all", "editor"], default="all")
args = parser.parse_args()
godot = str(Path(args.godot).resolve())
source = Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory(prefix="blender-controls-tests-") as scratch:
    root = Path(scratch)
    project = root / "project"
    shutil.copytree(source, project, ignore=shutil.ignore_patterns(".godot", "__pycache__"))
    env = dict(os.environ)
    for key, folder in [("XDG_DATA_HOME", "data"), ("XDG_CONFIG_HOME", "config"), ("XDG_CACHE_HOME", "cache")]:
        env[key] = str(root / folder)
    config = project / "project.godot"
    config.write_text(config.read_text().replace('"res://addons/blender_controls/plugin.cfg")', '"res://addons/blender_controls/plugin.cfg", "res://tests/harness/plugin.cfg")'))
    commands = [
        ["--headless", "--path", str(project), "--script", "tests/test_transform_math.gd"],
        ["--headless", "--path", str(project), "--script", "tests/test_snap_picker.gd"],
        [*(["--display-driver", "x11"] if args.gui else ["--headless"]), "--editor", "--path", str(project), "--quit-after", "600"],
    ]
    for command in (commands[-1:] if args.suite == "editor" else commands):
        result = subprocess.run([godot, *command], env=env, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=180)
        print(result.stdout, flush=True)
        if result.returncode or "SCRIPT ERROR" in result.stdout or "EDITOR TEST:" in result.stdout or ("--editor" in command and "EDITOR_TESTS:" not in result.stdout):
            raise SystemExit(result.returncode or 1)
