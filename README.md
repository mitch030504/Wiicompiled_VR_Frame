<img width="4190" height="2464" alt="Mario Kart WiiCompiled VR logo (logo by Inkwreck)" src="docs/images/wiicompiled-vr-logo.png" />

# WiiCompiled VR for the Steam Frame

<p align="center">
  <img alt="Steam Frame, SteamOS ARM64" src="https://img.shields.io/badge/Steam%20Frame-SteamOS%20%C2%B7%20ARM64-1A9FFF?logo=steam&amp;logoColor=white">
  <a href="https://github.com/mitch030504/Wiicompiled_VR_Frame/releases"><img alt="Status: beta" src="https://img.shields.io/badge/status-beta-FF9F0A"></a>
  <a href="https://github.com/iChris4/Wiicompiled_VR"><img alt="Fork of WiiCompiled OpenXR VR" src="https://img.shields.io/badge/fork%20of-WiiCompiled%20OpenXR%20VR-8B5CF6"></a>
  <a href="LICENSE"><img alt="License: GPLv3" src="https://img.shields.io/badge/license-GPLv3-2EA44F?logo=gnu&amp;logoColor=white"></a>
</p>

Mario Kart Wii in VR on Valve's Steam Frame, running natively on SteamOS. It is built on
[WiiCompiled](https://github.com/patchzyy/Wiicompiled), the static recompilation of Mario Kart Wii
to native code, and its VR fork [WiiCompiled OpenXR VR](https://github.com/iChris4/Wiicompiled_VR).
Nothing is emulated: your own disc is translated to C++, compiled for the Frame's ARM64 processor,
and drawn through SteamVR.

> [!IMPORTANT]
> This project contains no Nintendo code, assets or game data. You need your own dump of the PAL
> disc. The game is built from it on your own machine, and nothing is uploaded or shared.

> [!WARNING]
> **Beta.** It plays on the Steam Frame at the panels' full 2160x2160 per eye, at 120 Hz, with the
> Frame's controllers and foveation that follows your eyes. Some images still double in races and
> on the HUD (see [Known issues](#known-issues)).

**Contents:** [Quick start](#quick-start) · [Updating](#updating) ·
[Recommended settings](#recommended-settings) · [Controls](#controls) ·
[Known issues](#known-issues) · [Troubleshooting](#troubleshooting) ·
[Other ways to build](#other-ways-to-build) · [How it works](#how-it-works) · [FAQ](#faq) ·
[Credits](#credits)

---

## Quick start

One script takes you from your disc to the game in your Steam library. It downloads the newest
[release](https://github.com/mitch030504/Wiicompiled_VR_Frame/releases) (currently `frame-beta-3`),
extracts your disc, builds the game in an ARM64 container, installs it on the Frame and adds it to
Steam. Releases hold only source code: the game is always built from your own disc.

### Where to build

You can run the script on a Linux PC or on the Frame itself:

| | On a Linux PC | On the Frame |
| --- | --- | --- |
| First build | A few hours on an x86_64 PC (ARM64 is emulated), mostly building Dawn | Slower, and the Frame needs to stay on its charger |
| Updates | Run from the PC | Also from the **Updates** tab inside the game |
| Install option | `--frame steamos@<frame-ip>` | `--frame local` |

Later builds reuse what the first one built, so updates usually take minutes.

### You need

- a Steam Frame with Developer Mode on (Steam Settings → System → Enable Developer Mode, then set a
  user password);
- your own clean PAL `RMCP01` disc of Mario Kart Wii, as an ISO, WBFS, RVZ, WIA, CISO, GCZ or NFS
  image, inside a `.zip` or `.7z` if you like, or as an extracted folder;
- about 20 GB free where the build goes (`~/wiicompiled-frame`, or another folder with
  `--work-dir`);
- to build on a PC: Linux on x86_64 or ARM64 with 16 GB of memory or more, on the same network as
  the Frame.

> [!NOTE]
> Nobody here will tell you where to get the game, and links to game files are not tolerated.

### 1. Set up the container (PC only)

The build runs in a Debian ARM64 container. On an x86_64 PC, set up podman with ARM64 emulation:

```bash
sudo pacman -S --needed podman qemu-user-static qemu-user-static-binfmt   # Arch, CachyOS
sudo systemctl restart systemd-binfmt
podman run --rm --platform linux/arm64 docker.io/library/debian:trixie uname -m
```

The last command must print `aarch64`. On Debian or Ubuntu, install `podman qemu-user-static
binfmt-support` instead. If podman complains about subordinate ids, run
`sudo usermod --add-subuids 100000-165535 --add-subgids 100000-165535 $USER` and log in again.
Docker works in place of podman. An ARM64 PC needs only podman or Docker, and the Frame already
has podman.

### 2. Run the installer

From a PC, with your disc image and the Frame's address:

```bash
curl -fsSL https://raw.githubusercontent.com/mitch030504/Wiicompiled_VR_Frame/openxr-work/Launcher/steam-frame-install.sh \
    | bash -s -- --disc "/path/to/Mario Kart Wii.wbfs" --frame steamos@<frame-ip>
```

Or on the Frame, over SSH (`ssh steamos@<frame-ip>`) or in a Desktop Mode terminal:

```bash
curl -fsSL https://raw.githubusercontent.com/mitch030504/Wiicompiled_VR_Frame/openxr-work/Launcher/steam-frame-install.sh \
    | bash -s -- --disc "/path/to/Mario Kart Wii.wbfs" --frame local
```

The script checks that the disc is PAL `RMCP01` before building, and stops on any other. If it
stops for any reason, the same command picks up where it left off. From a PC, it asks for the
Frame's password when it gets there. Steam must be running on the Frame for the last step, adding
the game to the library.

Useful options (`--help` lists them all):

| Option | What it does |
| --- | --- |
| `--retro-rewind` | Also builds [Retro Rewind](https://wiki.tockdom.com/wiki/Retro_Rewind) and adds it to Steam as **RetroRewind**. Its pack (about 4 GB) comes from Retro Rewind's own update server, as Wheel Wizard fetches it, along with the Retro-WFC payload online play needs. It shares WiiCompiled's settings. |
| `--retro-rewind-pack DIR` | Uses a RetroRewind6 folder you already have instead of downloading one. |
| `--work-dir DIR` | Where the build lives instead of `~/wiicompiled-frame`, such as a folder on the Frame's SD card. |
| `--jobs N` | How many files compile at once. It defaults to a quarter of your memory in GB; lower it, to `--jobs 2` for example, if the machine freezes. |
| `--frame frame` | With [Frame Control](https://github.com/saphid/frame-control) set up, its SSH key answers to `frame`, so no password is asked. |
| `--release TAG` | Builds a given release instead of the newest. |

Leaving out `--frame` only builds the game, into `out` in the work dir.

On the Frame the game goes to `~/devkit-game/WiiCompiled/`. Installed from a PC, the disc goes to
`~/wiicompiled/disc`; with `--frame local` it stays in the work dir. Adding the game to Steam uses
Valve's devkit tools in `~/devkit-utils`, which Frame Control and Valve's Devkit Client put there;
without them, the script says how to add it yourself.

### 3. Play

Start **WiiCompiled** from your library in the headset. Press the left shoulder button for the
settings panel, and set the [recommended settings](#recommended-settings) on its **VR** tab.

## Updating

### From the machine you installed from

```bash
curl -fsSL https://raw.githubusercontent.com/mitch030504/Wiicompiled_VR_Frame/openxr-work/Launcher/steam-frame-install.sh \
    | bash -s -- --update
```

`--update` reuses the options you installed with, which the install saved in `install.conf` in the
work dir. Add `--work-dir` if you used one; any option you pass wins over the saved one. It
downloads the newest release, rebuilds only what changed and replaces the game on the Frame. When
the Frame already has the newest release (and the newest Retro Rewind pack, if you use it), it says
so and builds nothing. `--check` only says whether an update is available.

An install made with `--frame local` keeps a copy of the script in its work dir, so on the Frame
`~/wiicompiled-frame/steam-frame-install.sh --update` works too.

### From inside the game

An install made on the Frame with `--frame local` adds an **Updates** tab to the settings panel. It
shows the release you are running; **Check for updates** looks for a new one, and **Update now**
builds it in the background while you keep playing (the game can stutter while it compiles). The
tab shows each step and how far the build is, and tells you when to restart the game. If you close
the game meanwhile, the update carries on and opens the game again when it is done. Keep the Frame
on its charger while it runs.

The update runs as the systemd user service `wiicompiled-update.service`, at low priority so the
game comes first. Installed from a PC, the tab says to update from the PC instead. Progress is not
shown as Steam notifications, because Steam on the Frame does not display them.

### Coming from frame-beta-2 or earlier

Older installs saved no options for `--update` to reuse. Update once with the full install command
from [step 2](#2-run-the-installer) (you can leave out `--disc`); from then on `--update` works. To
get the in-game Updates tab, make that install on the Frame with `--frame local`.

## Recommended settings

All of these are on the settings panel's **VR** tab and in `~/.local/share/WiiCompiled/Config.toml`
on the Frame. Quit the game before editing the file, since the game saves its settings to it.

| Setting | Value | Why |
| --- | --- | --- |
| `[vr] render_scale` | `1.25` | 1.25 times SteamVR's recommended 1728x1728 is the panels' native 2160x2160, which the Frame renders in 9 to 11 ms a frame with medium foveation. |
| `[vr] foveation` | `medium` (default) | `off` shades every pixel and costs the most. See [Known issues](#known-issues) if images double. |
| `[vr] repeat_frames` | `true` (default) | Without it SteamVR halves the game's rate and fills in refreshes itself. |
| `[vr] frame_interpolation_fps` | `0` (default) | In-between frames need 120 eye pairs a second, which made things worse on the Frame. |
| `[vr] adaptive_resolution` | `false` (default) | Experimental and not yet tried in a race on the Frame. When on, races drop to as little as 70% of `render_scale` while frames fall behind 60 FPS, and climb back once they keep up. |
| `[video] resolution_multiplier` | `2` | The game's own frame, which the eyes are made from. 4x is far too heavy for the Frame's GPU. |

Keep SteamVR at 120 Hz. Motion Smoothing makes no difference to this game.

## Controls

The Frame's controllers have their own bindings, so the left D-pad works:

| Frame controller | Wii Remote mode | Gamepad mode |
| --- | --- | --- |
| Right A | A | South (A) |
| Right B | C (look behind) | East (B) |
| Right trigger | B | Right trigger |
| Right stick up / down | 1 / 2 | Right stick |
| Left View | + (pause) | Start |
| Left shoulder | Settings panel | North (Y) |
| Left D-pad | Wii Remote D-pad | D-pad |
| Left stick, left trigger | Nunchuk stick, Z | Left stick, left trigger |
| Grips, stick clicks, motion, aim | as on Quest Touch ([`OPENXR.md`](OPENXR.md), Controllers) | as on Touch |
| Right X, Y, menu and shoulder | unbound | unbound |

## Known issues

- **Doubled images** in races and on the HUD, worst while racing and sometimes in one eye only.
  Foveation is the main suspect: the Frame's graphics driver draws the outer areas at lower
  resolution and scales them up, and each eye's foveation follows its own gaze. Try foveation
  **Off** if it bothers you, and report whether it helped.
- **Foveation follows the right eye less well** than the left. Eyes converging on near things (the
  HUD screen, the cockpit) are not yet corrected for.
- **VR frame interpolation** is not recommended on the Frame.
- **The Quest app's Steam Frame version** shows no picture in the Frame's Android layer (see
  [How it works](#how-it-works)). Use this native build.

## Troubleshooting

**Collect everything at once.** From a PC, run
`Launcher/frame-diagnostics.sh --frame steamos@<frame-ip>` from the source
(`~/wiicompiled-frame/source` after an install). It gathers the newest runs' logs and crash files,
`Config.toml`, SteamVR's logs, the GPU driver and the system's state into one `.tar.gz`, and its
`summary.txt` says how far the newest run got through the startup steps below.

**Logs.** Each run gets a folder under `~/.local/share/WiiCompiled/Logs/` on the Frame, with
`console.log` and, after a crash, `crash_sigsegv.txt`. A working start logs, in order:

1. `OpenXR initialized: runtime 'SteamVR/OpenXR'`;
2. `Dawn will create its device through the runtime`;
3. `Fragment density maps: enabled`;
4. `OpenXR Vulkan swapchains ready ... same-queue native eye copies`;
5. `display refresh rate 120 Hz requested`, then `OpenXR session state -> FOCUSED`;
6. `OpenXR interaction profiles: left /interaction_profiles/valve/frame_controller_valve`;
7. `OpenXR eye gaze: available`, then `tracking`.

The first one missing says where it stopped. `Linux Vulkan OpenXR requires a Dawn built with
Aurora's patches` means the game was built by hand without `--dawn-package`.

**Smoothness.** With `[diagnostics] openxr_logging = true` in `Config.toml`, the log gets a pacing
line every second. On the Frame:

```bash
cd ~/.local/share/WiiCompiled/Logs && grep -h "xr-diag\] 1.0" "$(ls -t | head -1)/console.log" | tail -5
```

A smooth race reads `predicted-rate=120.0Hz`, `new=60 repeat=60` and `late=0`. Fewer than 60 `new`
frames means the GPU is over budget: lower `render_scale` or `resolution_multiplier`.

**Crashes.** `console.log` names the crashed thread and gives a backtrace as `module+offset`. On the
build machine, `addr2line -f -C -e ~/wiicompiled-frame/source/native-build/WiiCompiled 0x<offset>`
turns an offset in `WiiCompiled` into a function name.

**Builds.** The log is `build.log` in the work dir, and its end says why a build stopped. A build
that freezes the machine has run out of memory: run it again with a lower `--jobs`.

**In-game updates.** The Updates tab shows the step that failed. The full output is in the Frame's
journal, `journalctl --user -u wiicompiled-update.service`, and the build's in `build.log` in the
work dir.

### Reporting problems

Open an [issue](https://github.com/mitch030504/Wiicompiled_VR_Frame/issues) saying what you did and
what you saw (which eye, where in the picture, racing or in menus). Attach the diagnostics archive,
or at least the run's `console.log`; for a build problem, the end of `build.log`. Problems that also
happen on a PC or a Quest belong upstream, in
[WiiCompiled OpenXR VR](https://github.com/iChris4/Wiicompiled_VR).

## Other ways to build

### On a server

The script runs with Docker as well as podman, and much faster with more cores and memory. A
machine that can't reach the Frame builds without `--frame`; give it more compiles at once if it has
the memory, such as `--jobs 8` for 32 GB:

```bash
curl -fsSL https://raw.githubusercontent.com/mitch030504/Wiicompiled_VR_Frame/openxr-work/Launcher/steam-frame-install.sh \
    | bash -s -- --disc "/path/to/Mario Kart Wii.wbfs" --jobs 8
```

Run it in `tmux` or `screen` so a closed SSH session doesn't stop it. Then copy
`~/wiicompiled-frame/out` and `~/wiicompiled-frame/disc` to the Frame as in
[By hand, step 3](#3-install-on-the-frame).

On some hosts, such as Unraid 7 with kernel 6.18, `binfmt_misc` registrations are per container:
`tonistiigi/binfmt --install arm64` reports success, but Debian answers `exec format error`.
Register qemu on the host instead, with the `P` flag the tonistiigi build of qemu expects (without
it every program loses its first argument, and `uname -m` prints `Linux`):

```bash
docker create --name qemu-src tonistiigi/binfmt
docker cp qemu-src:/usr/bin/qemu-aarch64 /usr/local/bin/qemu-aarch64
docker rm qemu-src
echo ':qemu-aarch64:M::\x7fELF\x02\x01\x01\x00\x00\x00\x00\x00\x00\x00\x00\x00\x02\x00\xb7\x00:\xff\xff\xff\xff\xff\xff\xff\x00\xff\xff\xff\xff\xff\xff\xff\xff\xfe\xff\xff\xff:/usr/local/bin/qemu-aarch64:POCF' > /proc/sys/fs/binfmt_misc/register
docker run --rm --platform linux/arm64 debian:trixie uname -m   # aarch64
```

Unraid keeps `/usr/local/bin` in memory, so repeat this after a reboot.

### By hand

These are the steps the install script runs, for when you want to see or change one. Set up the
container as in [Quick start](#1-set-up-the-container-pc-only) first. The commands use
`frame-beta-3`; put the newest release's tag in its place.

#### 1. Download the release and extract your disc

```bash
mkdir -p ~/wiicompiled/Wiicompiled_VR_Frame; cd ~/wiicompiled
curl -fL https://github.com/mitch030504/Wiicompiled_VR_Frame/archive/refs/tags/frame-beta-3.tar.gz \
    | tar -xz --strip-components=1 -C Wiicompiled_VR_Frame
curl -fL -o nodtool https://github.com/encounter/nod/releases/download/v2.0.0-alpha.10/nodtool-linux-x86_64
chmod +x nodtool
./nodtool extract "/path/to/Mario Kart Wii.wbfs" disc-extract
mkdir -p Wiicompiled_VR_Frame/Assets
cp disc-extract/sys/main.dol disc-extract/files/rel/StaticR.rel Wiicompiled_VR_Frame/Assets/
```

`disc-extract` must hold `sys/` and `files/` directly. Keep it: the game reads it while it runs. On
an ARM64 machine, download `nodtool-linux-aarch64` instead.

#### 2. Build, inside an ARM64 container

```bash
podman run -it --name wiicompiled-frame --platform linux/arm64 -v ~/wiicompiled:/work docker.io/library/debian:trixie bash
```

Then, at the container's prompt:

```bash
apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates curl git python3 xz-utils unzip file pkg-config g++ binutils libicu-dev zlib1g-dev \
    libvulkan-dev libx11-dev libx11-xcb-dev libxcb1-dev libxext-dev libxrandr-dev libxinerama-dev \
    libxcursor-dev libxi-dev libxss-dev libxtst-dev libxkbcommon-dev libwayland-dev wayland-protocols \
    libdecor-0-dev libegl-dev libgl-dev libgles-dev libdrm-dev libgbm-dev libasound2-dev libpulse-dev \
    libpipewire-0.3-dev libudev-dev libdbus-1-dev libusb-1.0-0-dev
cd /work/Wiicompiled_VR_Frame
Launcher/prepare-portable-tools.sh --arch aarch64 --destination /work/tools   # clang 22, CMake, Ninja
T=/work/tools/toolchain-aarch64/bin
curl -fsSL https://dot.net/v1/dotnet-install.sh | bash -s -- --channel 8.0 --install-dir /work/dotnet
Launcher/build-dawn-linux.sh --work-dir /work/dawn --cc $T/clang --cxx $T/clang++ \
    --cmake $T/cmake --ninja $T/ninja --jobs 4 2>&1 | tee -a /work/dawn.log
Launcher/local-build.sh --output-dir /work/out --cc $T/clang --cxx $T/clang++ --fuse-ld lld \
    --cmake $T/cmake --ninja $T/ninja --dotnet /work/dotnet/dotnet --parallel 4 \
    --openxr --dawn-package /work/dawn/package --headset steam_frame 2>&1 | tee -a /work/game.log
exit
```

- Dawn is done when it prints `Patched Dawn for Linux ready`, the game when it prints
  `MKWCBUILD:OUTPUT=/work/out`.
- `--jobs 4` and `--parallel 4` suit 16 GB of memory, since compiles take more memory under
  emulation. Use 8 with 32 GB.
- If it stops, `podman start -ai wiicompiled-frame` gets you back in. Run
  `cd /work/Wiicompiled_VR_Frame; T=/work/tools/toolchain-aarch64/bin`, then the step that stopped:
  both scripts resume.
- On the Frame or another ARM64 machine, start the container without `--platform linux/arm64`.

#### 3. Install on the Frame

With [Frame Control](https://github.com/saphid/frame-control), drag `~/wiicompiled/out` onto
**Send to Frame**, name it `WiiCompiled` and keep **Launches** on `WiiCompiled`. That adds it to
your Steam library, in `~/devkit-game/WiiCompiled/` on the Frame.

Then copy the disc over and tell the game where it is (Frame Control's SSH key answers to `frame`;
use `steamos@<frame-ip>` otherwise):

```bash
ssh frame mkdir -p wiicompiled
scp -r ~/wiicompiled/disc-extract frame:wiicompiled/disc
ssh frame 'mkdir -p ~/.local/share/WiiCompiled && printf "[paths]\ndvd_root = \"/home/steamos/wiicompiled/disc\"\n" > ~/.local/share/WiiCompiled/Config.toml'
```

The last line replaces `Config.toml`, so run it on a first install only. Without Frame Control,
`scp -r ~/wiicompiled/out frame:wiicompiled/` and start `~/wiicompiled/out/WiiCompiled` from a
terminal in the Frame's Desktop Mode, with SteamVR running.

#### Updating by hand

Copy the new release's changed files over the old source, rebuild, and replace only the executable.
`rsync -c` copies just the files whose content changed and stamps them with the current time, so
the build recompiles exactly those; unpacking straight over the source would keep each file's
older commit date, and changes could be skipped. Your `Assets/` and build folders stay.

```bash
cd ~/wiicompiled
mkdir -p release-new
curl -fL https://github.com/mitch030504/Wiicompiled_VR_Frame/archive/refs/tags/frame-beta-3.tar.gz \
    | tar -xz --strip-components=1 -C release-new
rsync -rcE release-new/ Wiicompiled_VR_Frame/
rm -rf release-new
podman start -ai wiicompiled-frame
# in the container: cd /work/Wiicompiled_VR_Frame; T=/work/tools/toolchain-aarch64/bin, then the
# build-dawn-linux.sh and local-build.sh lines from step 2, then exit. Dawn is only rebuilt when the
# release changed its patches (the release notes say so).
scp ~/wiicompiled/out/WiiCompiled frame:devkit-game/WiiCompiled/WiiCompiled.new
ssh frame 'cd ~/devkit-game/WiiCompiled && chmod 755 WiiCompiled.new && mv -f WiiCompiled.new WiiCompiled'
```

Copying under a new name and moving it into place works even while the game is open.

## How it works

- **One GPU device.** SteamVR's OpenXR runtime creates the Vulkan device that Dawn (the WebGPU
  layer under Aurora, the game's renderer) draws with, through Aurora's patches to Dawn
  (`aurora-main/patches/dawn`). Each eye is copied into SteamVR's swapchain on Dawn's own queue, so
  nothing has to be shared between devices. This is the PC's Vulkan backend
  (`runtime/src/vr/openxr_vulkan_win32.cpp`) compiled for Linux. Dawn is linked in statically,
  which is why the patched Dawn is built once on your machine (`Launcher/build-dawn-linux.sh`).
- **Headset only.** The game draws no desktop window, and is compiled for the Frame's Cortex-X4
  cores (`-mcpu=cortex-x4`).
- **Tuned for ARM64.** The Frame's kernel uses 4 KiB memory pages, so the Steam Frame build skips
  the page-size check on every translated memory access; it checks once at startup and refuses to
  start if the size is ever different. Audio mixing uses NEON.
- **Every refresh from the game.** The game draws 60 frames a second. Given only those, SteamVR
  ran it at half rate and filled every other refresh itself, even with Motion Smoothing off. With
  `[vr] repeat_frames`, the pacing thread waits for the next frame until 1.5 ms before SteamVR's
  next wake, then submits the last frame again with the head pose it was drawn for, and SteamVR
  turns it to the current pose.
- **Eye-tracked foveation.** `XR_EXT_eye_gaze_interaction` gives the gaze, and Aurora picks a
  fragment density map centred on it, snapped to cells of about 3 degrees
  (`aurora-main/lib/gfx/foveation.hpp`), keeping up to 128 per eye. Each map has its own memory
  block, since sharing blocks crashed the game when a race restarted.
- **120 Hz.** `[vr] refresh_rate` (120 on the Frame by default, `0` keeps the headset's own) is
  requested through `XR_FB_display_refresh_rate`. SteamVR only offers the rate set in its own
  settings.
- **The Android version.** The Quest app has a `steamFrame` flavour
  (`android/Build-Quest.ps1 -Headset frame`) for the Frame's Android layer, Lepton. It starts in VR
  there but shows no picture: the Android backend passes each eye between two GPU devices, and
  Lepton's graphics driver supports none of the ways to share images between them. The native build
  uses one device, which is why it is the one to play. [`docs/quest-port.md`](docs/quest-port.md)
  covers the Android build.

[`OPENXR.md`](OPENXR.md) documents every VR setting and the renderer in full.

## What comes from where

This fork keeps everything [WiiCompiled OpenXR VR](https://github.com/iChris4/Wiicompiled_VR) has:
menus on a virtual screen and races in stereo, a first-person cockpit with a steering wheel you can
grab and turn, the settings panel in the headset, and Retro Rewind as its own translated game. The
physics are identical to the original game, proven by ghosts that sync across the Wii, Dolphin and
WiiCompiled.

On top of that it adds the SteamOS build, the install, update and diagnostics scripts and the
Frame-specific rendering, and it carries fixes taken from WiiCompiled itself and from other forks:
Linux TLS for online play, faster disc reads, safer settings saves, NEON audio mixing and more.
[`CREDITS.md`](CREDITS.md) lists each with its author.

The PC (Windows) and Meta Quest builds are still in the source and unchanged; see
[`OPENXR.md`](OPENXR.md) and [`docs/quest-port.md`](docs/quest-port.md). To play on those, use
upstream's [WheelWizard VR](https://github.com/iChris4/WheelWizard_VR/releases/latest) rather than
this fork.

WiiCompiled, WiiCompiled OpenXR VR, Wheel Wizard, Retro Rewind and this fork are developed
independently, each with its own rules. Check each project's own README and CONTRIBUTING files.

## FAQ

**Is this an emulator?**
No. Everything is compiled to native ARM64 code before you press play. Nothing emulates a Wii
processor or GPU while you play.

**Can I download a ready-built game?**
No. The game is built from your own disc, and anything built from it can't be shared. The build
is a one-time cost on your machine, and updates only rebuild what changed.

**Which version of the game works?**
Clean PAL `RMCP01` only. Other regions and modified discs are rejected.

**Why not install the Quest app on the Frame?**
The Frame runs Android apps in Lepton, whose graphics driver can't pass images between the two GPU
devices the Android version uses, so it shows nothing. The native build uses one device.

**Can it run on other Linux ARM64 devices?**
Untested. Build by hand without `--headset steam_frame` and with `--cpu` for your processor to get a
generic Linux VR build; it needs an OpenXR runtime with `XR_KHR_vulkan_enable2`. Unlike the Steam
Frame build, it also works with memory pages larger than 4 KiB.

## Credits

This fork stands on other people's work: WiiCompiled by patchzyy, WiiCompiled OpenXR VR by iChris4,
the steering wheel and hand steering by heurazy, and fixes from heurazy's Wiicompiled_VR-PLUS,
Chris Sotraidis's KartPad, DarthMDev, BlackAndBlue95's Strikers-WiiCompiled, rooklz and nx-mod's
wiicompiled-nx. [`CREDITS.md`](CREDITS.md) says what came from whom, along with the tools and
references used: [aurora](https://github.com/encounter/aurora),
[Dawn](https://dawn.googlesource.com/dawn), [OpenXR](https://www.khronos.org/openxr/),
[Dolphin](https://github.com/dolphin-emu/dolphin), [DolphinXR](https://github.com/iChris4/dolphinXR),
[nod](https://github.com/encounter/nod), [Retro Rewind](https://wiki.tockdom.com/wiki/Retro_Rewind),
[Wheel Wizard](https://github.com/TeamWheelWizard/WheelWizard) and
[Frame Control](https://github.com/saphid/frame-control). The logo is by Inkwreck.

Bundled third-party components and their licenses are in
[`THIRD-PARTY-NOTICES.md`](THIRD-PARTY-NOTICES.md).

## AI usage

AI coding tools were used to develop WiiCompiled and this fork. Translated output is checked
against real hardware behaviour, and physics accuracy is proven by ghosts that sync across the Wii,
Dolphin and WiiCompiled.

## License

WiiCompiled is free software: you can redistribute it and/or modify it under the terms of the
[GNU General Public License, version 3](LICENSE) as published by the Free Software Foundation.

WiiCompiled is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without
even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU
General Public License for more details.

Any mkwii distribution making use of WiiCompiled must be licensed under GPL v3.0.

Not affiliated with, endorsed by, or associated with Nintendo. Mario Kart Wii is a trademark of
Nintendo. No Nintendo intellectual property is contained in, distributed with, or obtainable
through this project.
