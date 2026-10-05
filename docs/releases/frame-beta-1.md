The first beta of WiiCompiled VR for the Steam Frame: Mario Kart Wii, statically recompiled to native
ARM64 code, running in VR on SteamOS through SteamVR.

**This release is source only.** The game is always built from your own clean PAL `RMCP01` disc,
and nothing built from it may be distributed, so there is no ready-built game here. Follow
[Building and installing](https://github.com/mitch030504/Wiicompiled_VR_Frame#building-and-installing)
in the README; the full commands are in
[`docs/steam-frame.md`](https://github.com/mitch030504/Wiicompiled_VR_Frame/blob/frame-beta-1/docs/steam-frame.md).

## What works on the Frame

- Starts in VR from the Steam library (installed with Frame Control) with SteamVR's OpenXR runtime.
  The runtime creates the GPU device the game renders with, so the eyes go straight into the
  headset's swapchain.
- Both eyes at the panels' native 2160x2160 (`render_scale = 1.25`), 120 Hz, every game frame
  shown: SteamVR reports 120 Hz with 60 new frames and 60 repeats a second and no late frames.
- The Frame's own controllers: left D-pad as the Wii Remote's D-pad, View to pause, left shoulder
  for the settings panel.
- Fragment density map foveation that follows your eyes through the Frame's eye tracking.

## Fixed during device testing

- A crash on race restart inside the Frame's Vulkan driver: density maps shared memory that Dawn
  unmaps after buffer uploads. Each map now has its own memory block (Dawn patch, so rebuild Dawn).
- SteamVR halving the game's rate and filling every other refresh itself:
  `[vr] repeat_frames` (on by default for the Frame) resubmits the last frame for those refreshes.
- Native crashes on Linux now log the faulting thread, pc and backtrace.
- The eye-tracked foveation region is 8 degrees wider and each eye keeps 128 maps.

## Known issues

- Images double in races and on the HUD, sometimes in the right eye only. Foveation is the main
  suspect; try foveation Off if it bothers you, and report the result.
- Foveation follows the right eye less well than the left.
- VR frame interpolation is not recommended on the Frame.
- The Android (`steamFrame`) flavour cannot show a picture in Lepton; use the native build.

## Recommended settings

`render_scale = 1.25`, `foveation = "medium"`, `repeat_frames = true`, `frame_interpolation_fps = 0`
under `[vr]`, and `resolution_multiplier = 2` under `[video]`. SteamVR at 120 Hz.

Reports with the run log from `~/.local/share/WiiCompiled/Logs/` are welcome as issues.
