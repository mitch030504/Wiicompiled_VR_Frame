The third beta of WiiCompiled VR for the Steam Frame: Mario Kart Wii, statically recompiled to
native ARM64 code, running in VR on SteamOS through SteamVR. This one brings in fixes from upstream
WiiCompiled and from other WiiCompiled forks, Retro Rewind in the installer, and a diagnostics
script. Thanks to everyone whose work is in it; [`CREDITS.md`](https://github.com/mitch030504/Wiicompiled_VR_Frame/blob/openxr-work/CREDITS.md) lists who wrote
what.

**This release is source only.** The game is always built from your own clean PAL `RMCP01` disc,
and nothing built from it may be distributed, so there is no ready-built game here.

## New

- **Retro Rewind in the installer.** `steam-frame-install.sh --retro-rewind` downloads the Retro
  Rewind pack from its own update server, builds Retro Rewind beside the base game and adds it to
  your Steam library. `--retro-rewind-pack DIR` uses a pack you already have. Online play works on
  Linux now that TLS does (below). From heurazy's Wiicompiled_VR-PLUS.
- **Adaptive resolution** (`[vr] adaptive_resolution`, off by default): lowers the race's eye
  resolution down to 70% while frames fall behind, and raises it again once they keep up.
  Experimental and not yet tried in a race on the Frame. From Wiicompiled_VR-PLUS.
- **Updating, from the PC or from inside the game.** `steam-frame-install.sh --update` reuses the
  options the install was made with and builds nothing when the Frame already has the newest
  release (and Retro Rewind pack); `--check` only reports. An install built on the Frame itself
  (`--frame local`) gets an **Updates** tab in the settings panel: it checks for a new release and
  builds it in the background while the game stays open, showing each step and how far the build
  is. Close the game meanwhile and the update reopens it when done. Steam notifications were tried
  for this and do not show on the Frame.
- **`Launcher/frame-diagnostics.sh`** gathers the logs, crash files, settings, SteamVR logs and
  system state from the Frame into one archive, with a summary of how far startup got. Attach it
  to bug reports.

## Fixed

- A crash while a scene loads (`GXClearVtxDesc`). From Wiicompiled_VR-PLUS.
- TLS on Linux, through Mbed TLS, so online services can connect at all (upstream #144), and a
  timed-out TLS write no longer frees a session the game still holds (DarthMDev).
- Saves on a different drive or the SD card can be moved (upstream #212); the game keeps its local
  Wii identity services while offline, and emptied WiiConnect24 files are refilled, so it no longer
  reports a save error for them (upstream #244, nx-mod).
- `Config.toml` is saved through a temporary file, so a crash mid-save can't empty it
  (BlackAndBlue95).
- Renderer fixes from upstream's KartPad batch (#244): draws no longer read past their own vertices,
  three-byte vertex attributes, GEN_MODE, EFB copies and readback, pipeline cache rows and pipeline
  compile wake-ups. Waiting on the GPU now sleeps instead of holding a CPU core busy.
- Effects no longer vanish while the world is darkened, such as Stormship's lightning
  (BlackAndBlue95).
- Controller player indices and socket errors (upstream #251), and a `bltl` translation (#254).

## Faster

- Disc reads and SZS decompression take bulk copies and keep file handles open per thread
  (KartPad).
- Audio mixing uses NEON (rooklz).
- Translated memory accesses no longer check the page size each time, since the Frame uses 4 KiB
  pages; the game checks once at startup (from nx-mod's finding).

## Updating from frame-beta-2

Run the install command again; you can leave out `--disc`. Dawn's patches did not change, so it is
not rebuilt. Most of the game is, since the translator changed as well as the runtime and renderer,
so expect a longer update than usual. The build now also downloads Mbed TLS. Add `--retro-rewind` to get Retro Rewind too.

frame-beta-2's script has no `--update`, so this one update is the full install command; it saves
its options, and from then on `steam-frame-install.sh --update` is enough. To update from inside
the game later, make this install on the Frame itself with `--frame local`.

## Known issues

Unchanged from frame-beta-2:

- Images double in races and on the HUD, sometimes in the right eye only. Foveation is the main
  suspect; try foveation Off if it bothers you, and report the result.
- Foveation follows the right eye less well than the left.
- VR frame interpolation is not recommended on the Frame.
- The Android (`steamFrame`) flavour cannot show a picture in Lepton; use the native build.

## Recommended settings

`render_scale = 1.25`, `foveation = "medium"`, `repeat_frames = true`, `frame_interpolation_fps = 0`
under `[vr]`, and `resolution_multiplier = 2` under `[video]`. SteamVR at 120 Hz.

Reports with the run log from `~/.local/share/WiiCompiled/Logs/`, or the archive
`frame-diagnostics.sh` makes, are welcome as issues.
