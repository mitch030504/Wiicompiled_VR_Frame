The second beta of WiiCompiled VR for the Steam Frame: Mario Kart Wii, statically recompiled to
native ARM64 code, running in VR on SteamOS through SteamVR. This one is about installing: one
command now takes you from your disc to the game in your Steam library.

**This release is source only.** The game is always built from your own clean PAL `RMCP01` disc,
and nothing built from it may be distributed, so there is no ready-built game here.

## Install in one command

Set up ARM64 emulation on an x86_64 Linux PC (the README's
[Quick start](https://github.com/mitch030504/Wiicompiled_VR_Frame#quick-start), step 1), then:

```bash
curl -fsSL https://raw.githubusercontent.com/mitch030504/Wiicompiled_VR_Frame/openxr-work/Launcher/steam-frame-install.sh \
    | bash -s -- --disc "/path/to/Mario Kart Wii.wbfs" --frame steamos@<frame-ip>
```

`Launcher/steam-frame-install.sh` (also in this release's source) does the rest:

- downloads the newest release and builds it in an ARM64 container (podman or docker), with as many
  compiles at once as your memory allows;
- takes your disc as an ISO, WBFS or RVZ image (WIA, CISO, GCZ and NFS too), inside a `.zip` or
  `.7z` if you like, or as an extracted folder. It checks the disc is PAL `RMCP01` before building;
- copies the game and the disc to the Frame over SSH, points the game at the disc, and adds it to
  your Steam library (through Valve's devkit tools, which Frame Control puts on the Frame);
- updates: run the same command again and only what changed is rebuilt and replaced.

With [Frame Control](https://github.com/saphid/frame-control) set up, `--frame frame` works.
`--frame local` builds and installs on the Frame itself; leaving `--frame` out only builds.
`--help` lists every option.

## Also new

- The README is now the one guide, opening with the Quick start; the manual steps remain under
  "Building by hand". `docs/steam-frame.md` is gone (it stays readable at the `frame-beta-1` tag).

## Updating from frame-beta-1

Nothing in the game or in Dawn changed, so a working frame-beta-1 install needs no rebuild. To move
to the installer anyway, run the command above: it keeps its own work folder
(`~/wiicompiled-frame`) and builds from scratch there the first time, then installs over your
existing `~/devkit-game/WiiCompiled/`. A disc already at `~/wiicompiled/disc` on the Frame and an
existing `dvd_root` setting are left as they are.

## Known issues

Unchanged from frame-beta-1:

- Images double in races and on the HUD, sometimes in the right eye only. Foveation is the main
  suspect; try foveation Off if it bothers you, and report the result.
- Foveation follows the right eye less well than the left.
- VR frame interpolation is not recommended on the Frame.
- The Android (`steamFrame`) flavour cannot show a picture in Lepton; use the native build.

The installer is new and was tested with synthetic discs and stand-ins for the container and the
Frame; reports of how it does on real machines are welcome.

## Recommended settings

`render_scale = 1.25`, `foveation = "medium"`, `repeat_frames = true`, `frame_interpolation_fps = 0`
under `[vr]`, and `resolution_multiplier = 2` under `[video]`. SteamVR at 120 Hz.

Reports with the run log from `~/.local/share/WiiCompiled/Logs/` (and, for the installer,
`~/wiicompiled-frame/build.log`) are welcome as issues.
