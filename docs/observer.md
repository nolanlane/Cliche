# Observer

The Observer is a physical pursuer. Its first encounter begins after a 7–10 second
settling period, followed by a short manifestation. Nearby, reachable positions in
the player's sightline are preferred. It stands long enough to be recognized,
creeps closer, holds a 1.8 second warning pose, and commits to pursuit.

Sprint to gain distance. Turn corners and quiet your footsteps to lose it:
it searches the last position it saw, and can hear sprinting within 12 metres.
Breaking visual contact for 5.5 seconds without being heard ends the chase.
Low crawl ducts exclude its body. A successful escape gives 14–30 seconds of
recovery, depending on escalation. Looking at it delays the initial approach
but does not cancel an active pursuit.

Capture requires physical contact within 1.05 metres, visible body samples, and
a clear capsule sweep. Being caught ends the run. Press **R** to restart.
It cannot grab through a wall or teleport into the camera.

## Model and movement

`assets/observer/observer.glb` is a continuous dark-skinned mesh with a 26-bone
skeleton: recessed eye sockets, a long skull, restrained rib and tendon relief,
elongated arms, and individually curved fingers. The suit, tie, glowing pale head,
and disconnected primitives have been removed.

The imported sculpt is uniformly fitted to approximately 2.27 metres. It ducks
under low lintels. This matters because the current authored reception ceiling
is 2.32 metres, despite the older 2.8 metre constant in the level script.

`scripts/observer_visual.gd` preserves imported bone rest rotations. Its leg solver
plants each foot during the support part of a step; stride timing follows actual
distance travelled. The torso moves less than the legs, the two arms trail
unevenly, fingers flex slightly, and the head holds a direction before correcting.
The faster chase gait lengthens the stride instead of accelerating an idle loop.

`scripts/observer_navigation.gd` builds a reusable floor graph from actual level
collision in small time slices. Each edge and movement step sweeps the creature's
capsule. It routes around walls, crosses low doorways, and handles the sump ramps.
`scripts/observer_audio.gd` generates positional breathing and dragging footfalls.

## Editing and verification

The reproducible Blender sculpt/rig source is `tools/build_observer.py`. Run:

```sh
blender --background --python /absolute/path/to/Cliche/tools/build_observer.py
```

This exports the game GLB and saves an editable Blender file under
`tools/observer_source/`. That source folder is excluded from Godot's importer.

```sh
godot --headless --path . --script tests/observer_behavior_audit.gd
godot --headless --path . --script tests/observer_pose_audit.gd
godot --path . --script tests/observer_visual_review.gd
```

The behavior audit covers natural appearances across six seeds, warning time,
idle-player capture, a 40-point route through reception doors, blocked grabs
across thin walls, loss of contact, and the crawlspace refuge. The pose audit
checks floor height and planted-foot sliding at idle, stalking, and chase speeds.
Reports and rendered evidence live in `artifacts/observer-overhaul/`.

For live inspection, call `debug_observer_scenario("natural")`, `"portrait"`,
or `"chase"` on the game root. The portrait scenario intentionally holds the
director; use `"natural"` afterward to restore gameplay.
