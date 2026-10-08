The fourth beta of WiiCompiled VR for the Steam Frame focuses on safer installs and updates.
It preserves working disc data when extraction fails, fixes moving an installation to a different
path, and makes release updates remove obsolete source files without deleting disc data or build
caches.

**This release is source only.** Build the game from your own clean PAL `RMCP01` disc. No compiled
game or disc assets are included.

## Fixed

- Linux setup extracts and validates disc data in staging before replacing the working copy.
  Failed validation or cancellation leaves the previous disc data intact, and cancellation stops
  the extraction process before its scratch directory is removed.
- Frame installations keep remote paths with spaces and shell characters as single arguments.
- Changing the disc or Retro Rewind location updates the corresponding `Config.toml` setting
  while preserving other settings.
- Release updates remove files owned by the previous release that no longer exist in the new
  one. Disc assets, generated output and build caches remain in place.
- A work-directory lock prevents overlapping manual installs and in-game updates.
- Linux and Frame Retro Rewind builds verify the Retro-WFC payload signature before translation.
  Android already performed this verification.
- Android folder replacements keep recovery copies until the full import commits. Interrupted
  imports can roll back disc data, the mod pack and the compiled library together. Play is blocked
  while a replacement journal is pending, and setup recovers it before another task starts.

## Updating from frame-beta-3

Fetch the new installer so this update uses the fixes:

```bash
curl -fsSL https://raw.githubusercontent.com/mitch030504/Wiicompiled_VR_Frame/openxr-work/Launcher/steam-frame-install.sh \
    | bash -s -- --update
```

Add `--work-dir DIR` if the original install used a different work directory. The installer now
requires Python 3 and `flock` from util-linux on the build machine. Both are normally available on
the Frame.

The first update of an older installation downloads its previous release's archive once to recover
which source files it owned. This extra download prevents cleanup from deleting user data or build
caches. Later updates reuse the saved file list.

## Validation

- 664 .NET tests passed locally using .NET 10 major-version roll-forward; CI uses .NET 8.
- Seven Android directory-transaction tests and six Frame installer regression checks passed.
- Linux setup built successfully, and installer shell syntax checks passed.
- New Linux CI checks cover extraction failure, cancellation, recovery and Frame file operations.

A full APK build and real-headset installation were not tested for this release.

## Known issues

The VR rendering issues from frame-beta-3 remain: doubled images in races and on the HUD, weaker
right-eye foveation tracking, and unrecommended frame interpolation. The Android Steam Frame flavour
still does not show a picture in Lepton; use the native build.

Recommended settings remain `render_scale = 1.25`, `foveation = "medium"`, `repeat_frames = true`,
`frame_interpolation_fps = 0`, and `resolution_multiplier = 2`, with SteamVR at 120 Hz.
