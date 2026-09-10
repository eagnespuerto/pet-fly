# PetFly

A virtual pet fruit fly with a real *Drosophila* brain, built on **Summer Engine** (Godot 4.7).

You feed it, put its lights on and off, and watch it sleep. What makes it more
than a Tamagotchi is that its hunger and sleep run on actual fly biology, and the
circuits driving that behaviour are real neuron populations from
[Virtual Fly Brain](https://virtualflybrain.org).

![PetFly by day](docs/shot_day.png)

## Install

Run **`PetFly-win-Setup.exe`**. It installs per-user (no admin prompt), adds
Desktop and Start Menu shortcuts, and registers an uninstaller in Add/Remove
Programs. `PetFly-win-Portable.zip` is the same game with no installer.

Both are produced by `tools/build.ps1` into `dist/`.

## Running from source

```powershell
& "$env:LOCALAPPDATA\SummerEngine\current\Summer.exe" --path .
```

## Controls

| Key | Action |
|---|---|
| `1`–`5` | offer food (banana, sucrose, yeast, water, quinine) |
| `L` | toggle lights — shifts the fly's clock to ZT0 or ZT12 |
| `R` | rouse a sleeping fly (it will be grumpy) |
| `B` | brain panel |
| `M` | swap between the four fly models |
| `C` | credits |
| `H` | help |
| `Esc` | close overlay, or quit |
| drag / wheel | orbit and zoom the camera |

## How the sleep model works

Sleep is not a countdown timer. It uses the two-process model that real fly
sleep research uses, and each process maps onto a circuit the game pulls from
VFB:

- **Process C — circadian drive**, from the pacemaker (clock) neurons.
  *Drosophila* is crepuscular: activity peaks at lights-on and lights-off, with
  a midday siesta and consolidated night sleep.
- **Process S — sleep pressure**, gated by the dorsal fan-shaped body (dFB)
  tangential neurons. It builds while awake and discharges during sleep.

The fly sleeps when C + S crosses a threshold and wakes when it drops below a
lower one. Simulated over three fly days with food available, this reproduces a
published fly sleep profile:

```
ZT   %asleep
05       8%  ###
06      46%  ##################
07      58%  #######################   <- midday siesta
08      26%  ##########
12       0%                            <- evening activity peak
14      89%  ###################################
15-20  100%  ########################################  <- night sleep
22       7%  ##
```

~9.3 h of sleep per fly day, against ~10–12 h in real flies.

**Starvation suppresses sleep.** A hungry fly stays awake to forage, exactly as
real flies do — starving the pet drops it from 8.1 h to 2.2 h of sleep per day.
So feed it.

## The world

![Night](docs/shot_night.png)

- **Grass** — 22,000 procedurally generated blades on a `MultiMesh`, bending in
  a two-frequency wind entirely in the vertex shader
  (`assets/shaders/grass.gdshader`). It dims and turns blue at night along with
  the sky.
- **Sky and light** — a procedural sky, sun arc, colour and ambient level all
  driven by Zeitgeber Time, so the vial visibly moves through dawn, day, dusk
  and night.
- **Feeding** — food is a real rigid body. It drops through the mouth of the
  vial under Jolt physics, squashes on impact, throws a splash of droplets, then
  soaks into the dish while the dish's blob grows.
- **The fly** — the four bundled models are unrigged static meshes, so the body
  is animated procedurally: velocity-driven banking and pitch, hover bob,
  takeoff and landing flares, walking gait, grooming (real flies groom
  constantly), sleep breathing, and translucent wing cards that beat fast enough
  to read as blur. Eight states, all reachable — the smoke test asserts it.

## The brain panel

![Brain panel](docs/shot_brain.png)

Eight real circuits, each wired to something the pet does:

| Circuit | VFB root term | Drives |
|---|---|---|
| Sweet taste | `FBbt_00049614` | hunger |
| Bitter taste | `FBbt_00049613` | food rejection |
| Water sensing | `FBbt_00058155` | thirst |
| Circadian clock | `FBbt_00100163` | the day/night rhythm |
| Sleep homeostat | `FBbt_00049537` | sleep pressure |
| Dopaminergic reward | `FBbt_00005131` | mood |
| Mushroom body | `FBbt_00003686` | learning |
| Ellipsoid body | `FBbt_00003649` | locomotion |

Bars show how strongly each circuit is engaged right now, read straight off the
simulation. Click a circuit for its real neuron classes with descriptions and
citations; **OPEN IN VFB** opens that neuron's report page.

**REFRESH LIVE** re-queries virtualflybrain.org for that circuit while the game
is running, and caches the result to `user://vfb_live.json`.

## Time and saves

1 real second = 1 fly minute, so a full fly day passes in 24 real minutes. `ZT`
is Zeitgeber Time: ZT0 is lights on, ZT12 is lights off.

The pet keeps living while the game is closed, up to 16 fly hours, then picks up
where it left off. Neglect makes it ail but never kills it — health bottoms out
at 8% and recovers in about two fly days of proper feeding.

Saves live in `%APPDATA%\Godot\app_userdata\PetFly\pet.json` (written
atomically, via a temp file and rename).

## Building and releasing

```powershell
pwsh tools\build.ps1                 # export + package
pwsh tools\build.ps1 -Version 1.1.0  # release a new version
```

This exports the project with Summer Engine, then packages with
[Velopack](https://velopack.io) — the same installer/updater framework Summer
Engine itself ships with. It produces, in `dist/`:

| Artifact | Purpose |
|---|---|
| `PetFly-win-Setup.exe` | the installer |
| `PetFly-win-Portable.zip` | no-install build |
| `PetFly-<ver>-full.nupkg` | the update package |
| `releases.win.json` | the feed the game checks |

Velopack CLI is required once: `dotnet tool install -g vpk`.

### Enabling in-game updates

Updates are **off by default**, because a release feed needs somewhere to live
and this repo does not assume a host. To turn them on:

1. Publish the contents of `dist/` to any static URL.
2. Set that URL in `project.godot`:

   ```ini
   config/update_feed="https://example.com/petfly/"
   ```

3. Ship a build. From then on, PetFly checks the feed at startup, shows an
   **UPDATE TO x.y.z** button when a newer version exists, downloads the
   `.nupkg`, and hands it to Velopack's `Update.exe` to install and relaunch.

With no feed set, the check is skipped silently. Update checks are also skipped
for portable and from-source runs, which have nothing to update in place.

## Architecture

```
scripts/
  game.gd          main controller, camera, input, wiring
  sim.gd           metabolism and the two-process sleep model
  vfb.gd           VFB data: bundled snapshot + live Cypher/Solr queries
  terrarium.gd     vial, plinth, soil, circadian sky and lighting
  grass.gd         procedural MultiMesh lawn
  fly.gd           model loading, behaviour state machine, animation
  food_pellet.gd   physics-driven food with splash and dissolve
  hud.gd           vitals, food bar, brain panel, overlays
  ui_kit.gd        widgets built from the Kenney UI pack
  save_manager.gd  atomic save/load
  updater.gd       Velopack feed check, download, hand-off
tools/
  build.ps1        export + package
  screenshot.gd    render any screen to PNG
tests/
  sim_test.gd      sleep profile, starvation, bitter veto, health floor
  game_smoke.gd    boots the real scene and drives every interaction
  updater_test.gd  version compare + feed parsing against a real feed
  check.gd         assertion helper that actually fails the run
```

### Two paths to VFB data

- **Bundled** (`assets/data/vfb_brain.json`) — 8 circuits, 267 neuron classes,
  80 individual reconstructions, harvested with the `vfb_connect` Python API.
  Loads instantly, works offline.
- **Live** — the game queries VFB's public Neo4j (Cypher) and Solr endpoints
  over HTTPS via `HTTPRequest`, on Godot's async request path, so it never
  blocks a frame.

The Python harvester that produced the bundle lives in the previous
implementation of this project (`../flypet/tools/harvest_vfb.py`). It is a
build-time tool only; the game itself has no Python dependency.

## Tests

```powershell
$s = "$env:LOCALAPPDATA\SummerEngine\current\Summer.exe"
& $s --headless --path . --script res://tests/sim_test.gd
& $s --headless --path . --script res://tests/game_smoke.gd
& $s --headless --path . --script res://tests/updater_test.gd
```

Each suite prints a pass/fail count and sets the exit code.

## Credits

Fly models from Poly Pizza (one CC0, three CC-BY 3.0), UI from the Kenney UI
Pack (CC0), brain data from Virtual Fly Brain. Full attribution in
[CREDITS.md](CREDITS.md) and on the in-game credits screen (`C`).
