# Agent Notes

PetFly — a virtual pet fruit fly whose behaviour is driven by real *Drosophila*
neuroanatomy from Virtual Fly Brain. See `README.md` for the full picture.

## Conventions

- **GDScript, not C#.** The project has no `.csproj`; the `[dotnet]` block in
  `project.godot` is Godot's default and is unused.
- **Scenes are built in code.** `scenes/Main.tscn` is a single node running
  `scripts/game.gd`; the terrarium, fly, HUD and overlays all construct
  themselves. Keep it that way — it keeps geometry and layout reviewable in one
  place instead of split across binary-ish `.tscn` files.
- **Typed GDScript.** `:=` inference fails on anything reached through an
  untyped `Variant` (e.g. `game.sim.rejections`), so annotate explicitly there.
- **`class_name` needs a rescan.** After adding a new `class_name`, run
  `Summer.exe --headless --path . --import` before any `--script` run, or the
  identifier will not resolve.

## Gotchas that already cost time

- Controls in a `CanvasLayer` are **not** sized by anchors alone. The HUD uses
  real containers (`MarginContainer` → `VBoxContainer` → `HBoxContainer`);
  `set_anchors_and_offsets_preset(..., PRESET_MODE_MINSIZE)` silently produced
  zero-size panels.
- `CPUParticles3D.color_ramp` takes a `Gradient`, not a `GradientTexture1D`.
- Do **not** pipe `2>&1` from `Summer.exe` in Windows PowerShell. It wraps
  stderr in `ErrorRecord`s and trips `$ErrorActionPreference = "Stop"` even on
  a clean exit — Summer writes an informational snapshot notice to stderr.
- The headless editor's filesystem is a boot-time snapshot. Run one
  `--headless --import` per batch of file writes.
- Velopack writes `releases.win.json` **compact**. Never match it by string.

## Testing

Headless suites live in `tests/`, and use `tests/check.gd` rather than
`assert()` — Godot's `assert` does not halt here, so an assert-based test would
report success after failing.

```powershell
$s = "$env:LOCALAPPDATA\SummerEngine\current\Summer.exe"
& $s --headless --path . --script res://tests/sim_test.gd
```

`tools/screenshot.gd` renders any screen to PNG, but must run **without**
`--headless` — the headless display server rasterises nothing.

## Simulation

`scripts/sim.gd` is a faithful port of a validated model; the constants are
tuned so the sleep profile matches published fly data. `tests/sim_test.gd`
pins the numbers (9.3 h sleep/fly day, starvation halving it). Change the
constants only with those numbers in mind.
