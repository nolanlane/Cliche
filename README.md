# Cliche

An atmospheric first-person Level 0 walk built in Godot 4.7. The level is authored in seven editable sector scenes, with warm wallpaper, carpet, suspended ceilings, and fluorescent fixtures. `backrooms_wallpapers.glb` is used as the authored wallpaper-material source.

## Controls

- `WASD` — move
- `Shift` — sprint
- `Ctrl` or `C` — crouch through maintenance spaces
- `Space` — jump
- `F` or right mouse — raise/lower the lighter
- `Mouse` — look
- `Esc` — release the cursor; click to recapture it

Lighter fluid is finite. Explore side rooms and dead ends for refill cans; walking over one collects it automatically.

Open the project in Godot and press Play. The main scene is `main.tscn`.

## Level authoring and validation

Edit the sector scenes in `scenes/sectors/`. Walls, doorways, ceilings, fixtures, and Observer anchors are ordinary saved nodes. The shared floor and outer envelope live in `shell.tscn`; the gameplay director binds authored fixtures and anchors through their existing groups.

With the game stopped, run the physics audit and continuous controller walkthrough:

```sh
godot --headless --path . --script tests/level_geometry_audit.gd
godot --headless --path . --fixed-fps 60 --script tests/level_walkthrough.gd
```

The walkthrough requires the audit output and drives the existing player with movement/crouch input. Representative gameplay captures and verification results are in `artifacts/level-layout/`.
