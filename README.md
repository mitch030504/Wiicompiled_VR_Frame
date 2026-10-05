<img width="4190" height="2464" alt="Mario Kart WiiCompiled VR logo (logo by Inkwreck)" src="docs/images/wiicompiled-vr-logo.png" />

# WiiCompiled VR for the Steam Frame

<p align="center">
  <img alt="Steam Frame, SteamOS ARM64" src="https://img.shields.io/badge/Steam%20Frame-SteamOS%20%C2%B7%20ARM64-1A9FFF?logo=steam&amp;logoColor=white">
  <a href="https://github.com/mitch030504/Wiicompiled_VR_Frame/releases"><img alt="Status: beta" src="https://img.shields.io/badge/status-beta-FF9F0A"></a>
  <a href="https://github.com/iChris4/Wiicompiled_VR"><img alt="Fork of WiiCompiled OpenXR VR" src="https://img.shields.io/badge/fork%20of-WiiCompiled%20OpenXR%20VR-8B5CF6"></a>
  <a href="LICENSE"><img alt="License: GPLv3" src="https://img.shields.io/badge/license-GPLv3-2EA44F?logo=gnu&amp;logoColor=white"></a>
</p>

Mario Kart Wii in VR on Valve's Steam Frame, running natively on SteamOS: a fork of
[WiiCompiled OpenXR VR](https://github.com/iChris4/Wiicompiled_VR) (itself built on
[WiiCompiled](https://github.com/patchzyy/Wiicompiled)), the static recompilation of Mario Kart Wii
to native code. There is no emulator, interpreter or JIT at runtime: your own disc is translated to
C++ and compiled for the Frame's ARM64 CPU, and it renders through SteamVR's OpenXR runtime.

> [!IMPORTANT]
> There is no Nintendo code, no assets and no game data anywhere in this project. You need your
> own legally dumped copy of the PAL version of the game; the translation runs on your machine
> against your disc image, and nothing is uploaded.

> [!WARNING]
> **Beta.** It runs on a Steam Frame: SteamVR, both eyes at the panels' 2160x2160, the Frame's
> controllers, 120 Hz with every game frame shown, and foveation that follows your eyes. It is not
> finished: images still double in races and on the HUD, and the foveation tracks the right eye
> less well than the left (see [Known issues](#known-issues)). Reports with the run log move it
> forward (see [Reporting problems](#reporting-problems)).

---

## Quick start

This is the whole way from your disc to playing in the headset. An install script does the work: it
downloads the newest [release](https://github.com/mitch030504/Wiicompiled_VR_Frame/releases),
extracts your disc, builds the game in an ARM64 container on your PC, copies it and the disc to the
Frame, and adds it to your Steam library. Releases are source only: the game is always built from
your own disc, so there is nothing ready-built to download. The first build takes a few hours, most
of it compiling Dawn under emulation; later builds reuse it.

**You need:**
- a Steam Frame with Developer Mode on (Steam Settings → System → Enable Developer Mode, then set a
  user password), on the same network as your PC;
- your own clean PAL `RMCP01` disc of Mario Kart Wii: an ISO, WBFS or RVZ image (WIA, CISO, GCZ
  and NFS work too), as is or in a `.zip` or `.7z`, or a folder you extracted it to;
- an x86_64 Linux PC with about 20 GB free and 16 GB of memory or more.

The PC commands below work in bash, zsh and fish.

> [!NOTE]
> Nobody here will tell you where to get the game. Dumping your own disc is on you, and links to
> game files won't be provided or tolerated. For the same reason there is no ready-built game to
> download: releases hold the source, and the game is always built from your own disc.

### 1. Set up ARM64 emulation on the PC

```bash
sudo pacman -S --needed podman qemu-user-static qemu-user-static-binfmt   # Arch, CachyOS
sudo systemctl restart systemd-binfmt
podman run --rm --platform linux/arm64 docker.io/library/debian:trixie uname -m
```

The last command must print `aarch64`. On Debian or Ubuntu install `podman qemu-user-static
binfmt-support` instead. If podman complains about subordinate ids, run
`sudo usermod --add-subuids 100000-165535 --add-subgids 100000-165535 $USER` and log in again.
Docker works too, in place of podman.

### 2. Run the installer

With the path to your disc image and your Frame's address:

```bash
curl -fsSL https://raw.githubusercontent.com/mitch030504/Wiicompiled_VR_Frame/openxr-work/Launcher/steam-frame-install.sh \
    | bash -s -- --disc "/path/to/Mario Kart Wii.wbfs" --frame steamos@<frame-ip>
```

- `--disc` takes the image whatever its name or extension; the format is read from the file
  itself. A `.zip` or `.7z` is unpacked first (with 7-Zip, bsdtar or unzip if you have one, in a
  container otherwise), and the disc image inside it is found and used. It checks the game ID
  before building and stops on any disc other than PAL `RMCP01`.
- It asks for the Frame's password when it gets there. If you use
  [Frame Control](https://github.com/saphid/frame-control), pass `--frame frame` instead: its SSH
  key answers to that name.
- Everything it builds lives in `~/wiicompiled-frame` (`--work-dir` to change that): the toolchain,
  Dawn, the source, the extracted disc and the build log, `build.log`.
- It runs as many compiles at once as fit in memory (a quarter of your memory in GB). If the machine
  still freezes, run it again with a lower `--jobs`, such as `--jobs 2`.
- If it stops for any reason, the same command picks up where it left off.
- On the Frame, the game goes to `~/devkit-game/WiiCompiled/` and the disc to `~/wiicompiled/disc`.
  It is added to your Steam library through Valve's devkit tools in `~/devkit-utils`, which Frame
  Control and Valve's Devkit Client put there. Without them, the script says how to add it once
  yourself. Steam must be running on the Frame for this step.
- Add `--retro-rewind` to also build [Retro Rewind](https://wiki.tockdom.com/wiki/Retro_Rewind).
  The script downloads its pack (about 4 GB) from Retro Rewind's own update server, as Wheel Wizard
  does, and later runs apply only the updates published since. It also fetches the Retro-WFC
  payload online play needs. On the Frame, Retro Rewind goes to `~/devkit-game/RetroRewind/` and
  its pack to `~/wiicompiled/RetroRewind6`, and it shares WiiCompiled's settings.
  `--retro-rewind-pack DIR` uses a RetroRewind6 folder you already have instead.
- `--help` lists every option. From a downloaded release, run `Launcher/steam-frame-install.sh`
  with the same options: it then builds that release's source.

### 3. Play

Start **WiiCompiled** from the library in the headset. Open the settings panel with the left
shoulder button, go to the **VR** tab and set the [recommended settings](#recommended-settings).

### Updating

Run the same command again; you can leave out `--disc`. The script downloads the newest release,
puts only the files that changed over the old source, rebuilds what they touch, and replaces the
game on the Frame. Dawn is only rebuilt when a release changes its patches (the release notes say
so), so an update usually takes minutes. `--release <tag>` builds a given release instead.

## Recommended settings

All of these are in the headset's settings panel (left shoulder button, **VR** tab) and in
`~/.local/share/WiiCompiled/Config.toml`. Quit the game before editing the file; it writes its
settings back when it closes.

| Setting | Value | Why |
| --- | --- | --- |
| `[vr] render_scale` | `1.25` | Scales SteamVR's recommended eye size, 1728x1728 on the Frame: 1.25 is the panels' native 2160x2160, which the Frame renders in 9 to 11 ms a frame with medium foveation. |
| `[vr] foveation` | `medium` | `off` shades every pixel and costs the most. See [Known issues](#known-issues) if images double. |
| `[vr] repeat_frames` | `true` (default) | Without it SteamVR halves the game's rate and fills refreshes itself. |
| `[vr] frame_interpolation_fps` | `0` | Rendering in-between frames needs 120 eye pairs a second, which made things worse on the Frame. |
| `[video] resolution_multiplier` | `2` | The game's own frame, which the eyes are made from. 4x is far too heavy for the Frame's GPU. |

Keep SteamVR's refresh rate at 120 Hz. Motion Smoothing makes no difference to this game.

## Controls

The Frame's controllers are bound through their own profile, so the left D-pad works:

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

- **Doubled images** in races and on the HUD, worst while racing, sometimes in the right eye only.
  Both eyes get the same frames, so a doubling in one eye points at foveation: the Frame's driver
  (Turnip) draws a foveated screen tile at lower resolution and scales it back up, and each eye's
  density maps change with its gaze. Try foveation **Off** if it bothers you, and report whether it
  helped.
- **Foveation follows the right eye less well** than the left. Convergence on near content (the HUD
  screen at 2 m, the cockpit) is not yet corrected for.
- **VR frame interpolation** is not recommended on the Frame.
- **The Quest app's `steamFrame` flavour** cannot show a picture in the Frame's Android layer
  ([below](#the-android-flavour)). Use the native build.

## Troubleshooting

**Logs.** Each run gets a folder under `~/.local/share/WiiCompiled/Logs/` on the Frame, holding
`console.log` and, after a crash, `crash_sigsegv.txt`. A working start logs, in order:

1. `OpenXR initialized: runtime 'SteamVR/OpenXR'`;
2. `Dawn will create its device through the runtime`;
3. `Fragment density maps: enabled`;
4. `OpenXR Vulkan swapchains ready ... same-queue native eye copies`;
5. `display refresh rate 120 Hz requested`, then `OpenXR session state -> FOCUSED`;
6. `OpenXR interaction profiles: left /interaction_profiles/valve/frame_controller_valve`;
7. `OpenXR eye gaze: available`, then `tracking`.

The first one missing says where it stopped. `Linux Vulkan OpenXR requires a Dawn built with
Aurora's patches` means the game was built without `--dawn-package`.

**Smoothness.** With `[diagnostics] openxr_logging = true`, the log gets a pacing line every second:

```bash
ssh frame 'cd ~/.local/share/WiiCompiled/Logs && d=$(ls -t | head -1) && grep -h "xr-diag\] 1.0" "$d/console.log" | tail -5'
```

A healthy race reads `predicted-rate=120.0Hz`, `new=60 repeat=60` and `late=0`. Fewer than 60 `new`
frames means the GPU is over budget: lower `render_scale` or `resolution_multiplier`.

**Crashes.** `console.log` then names the faulting thread and gives its pc and a backtrace as
`module+offset`. On the build machine,
`addr2line -f -C -e ~/wiicompiled-frame/source/native-build/WiiCompiled 0x<offset>` turns an offset
in `WiiCompiled` into a function: the executable is not stripped. (Built by hand, the executable is
in `~/wiicompiled/Wiicompiled_VR_Frame/native-build/`.)

**Building.** The install script's log is `~/wiicompiled-frame/build.log`; its end says why a build
stopped. A build that freezes the machine has run out of memory: lower `--jobs` (or, by hand,
`--parallel`). A missing CMake package means installing its `-dev` package in the container and
running the same command again.

## Building by hand

These are the steps the install script runs, for when you want to see or change each one. Set up
emulation as in [Quick start](#quick-start) step 1 first.

### 1. Download the release and extract your disc

Take the newest release from the [Releases](https://github.com/mitch030504/Wiicompiled_VR_Frame/releases)
page; the commands use `frame-beta-1`, so put the newest release's tag in its place:

```bash
mkdir -p ~/wiicompiled/Wiicompiled_VR_Frame; cd ~/wiicompiled
curl -fL https://github.com/mitch030504/Wiicompiled_VR_Frame/archive/refs/tags/frame-beta-1.tar.gz \
    | tar -xz --strip-components=1 -C Wiicompiled_VR_Frame
curl -fL -o nodtool https://github.com/encounter/nod/releases/download/v2.0.0-alpha.10/nodtool-linux-x86_64
chmod +x nodtool
./nodtool extract "/path/to/Mario Kart Wii.wbfs" disc-extract
mkdir -p Wiicompiled_VR_Frame/Assets
cp disc-extract/sys/main.dol disc-extract/files/rel/StaticR.rel Wiicompiled_VR_Frame/Assets/
```

`disc-extract` must hold `sys/` and `files/` directly; keep it, the game reads it when it runs.

### 2. Build, inside an ARM64 container

```bash
podman run -it --name wiicompiled-frame --platform linux/arm64 -v ~/wiicompiled:/work docker.io/library/debian:trixie bash
```

Then, in the container's bash prompt:

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
- `--jobs 4` and `--parallel 4` suit 16 GB of memory. Compiles take more memory under emulation, and
  16 at once froze a 16 GB laptop. Use 8 with 32 GB.
- If it stops, `podman start -ai wiicompiled-frame` gets you back in. Run `cd /work/Wiicompiled_VR_Frame;
  T=/work/tools/toolchain-aarch64/bin`, then the step that stopped: both scripts resume.

### 3. Install on the Frame

The easiest way is [Frame Control](https://github.com/saphid/frame-control): set up its connection
to the Frame, then drag `~/wiicompiled/out` onto **Send to Frame**. Name it `WiiCompiled` and keep
**Launches** on `WiiCompiled`. It adds the game to your Steam library, in `~/devkit-game/WiiCompiled/`
on the Frame.

Then copy the disc over and, on a first install, tell the game where it is (Frame Control's SSH
key answers to `frame`; use `steamos@<frame-ip>` otherwise):

```bash
ssh frame mkdir -p wiicompiled
scp -r ~/wiicompiled/disc-extract frame:wiicompiled/disc
ssh frame 'mkdir -p ~/.local/share/WiiCompiled && printf "[paths]\ndvd_root = \"/home/steamos/wiicompiled/disc\"\n" > ~/.local/share/WiiCompiled/Config.toml'
```

Without Frame Control, `scp -r ~/wiicompiled/out frame:wiicompiled/` and start
`~/wiicompiled/out/WiiCompiled` from a terminal in the Frame's Desktop Mode, with SteamVR running.

### Updating by hand

When a new release comes out, put its changed files over the old source, rebuild, and replace only
the executable. `rsync -c` copies just the files whose content changed and stamps them with the
current time, so the build recompiles exactly those. Unpacking over the source would restore each
file's commit date, which can be older than the last build, and changes would be skipped. Your
`Assets/` and build folders stay. Install `rsync` if your system lacks it, and put the new release's
tag in place of `frame-beta-2`:

```bash
cd ~/wiicompiled
mkdir -p release-new
curl -fL https://github.com/mitch030504/Wiicompiled_VR_Frame/archive/refs/tags/frame-beta-2.tar.gz \
    | tar -xz --strip-components=1 -C release-new
rsync -rcE release-new/ Wiicompiled_VR_Frame/
rm -rf release-new
podman start -ai wiicompiled-frame
# in the container: cd /work/Wiicompiled_VR_Frame; T=/work/tools/toolchain-aarch64/bin, then the
# build-dawn-linux.sh and local-build.sh lines from step 2, then exit. Dawn only rebuilds when the
# release changed its patches (the release notes say so); otherwise both finish quickly.
scp ~/wiicompiled/out/WiiCompiled frame:devkit-game/WiiCompiled/WiiCompiled.new
ssh frame 'cd ~/devkit-game/WiiCompiled && chmod 755 WiiCompiled.new && mv -f WiiCompiled.new WiiCompiled'
```

The executable is copied under a new name and moved into place, which works even while an old copy
is open.

## Other ways to build

**On the Frame itself.** SteamOS's root file system is read-only, but it ships podman, and the
install script runs there too. Over SSH (`ssh steamos@<frame-ip>`), or in a Desktop Mode terminal:

```bash
curl -fsSL https://raw.githubusercontent.com/mitch030504/Wiicompiled_VR_Frame/openxr-work/Launcher/steam-frame-install.sh \
    | bash -s -- --disc "/path/to/Mario Kart Wii.wbfs" --frame local
```

It is native ARM64, so no emulation, but the Frame has less memory and cooling than a PC; keep it
on its charger. The game then reads the disc straight from `~/wiicompiled-frame/disc`. By hand, the
steps under [Building by hand](#building-by-hand) work the same in a container started without
`--platform linux/arm64`, with `nodtool-linux-aarch64` in place of `nodtool-linux-x86_64`.

**On a stronger machine** (a server, for example). The script works with Docker as well as podman,
and runs much faster with more cores and memory. A machine that cannot reach the Frame builds
without `--frame`; give it more compiles at once if it has the memory, `--jobs 8` for 32 GB:

```bash
curl -fsSL https://raw.githubusercontent.com/mitch030504/Wiicompiled_VR_Frame/openxr-work/Launcher/steam-frame-install.sh \
    | bash -s -- --disc "/path/to/Mario Kart Wii.wbfs" --jobs 8
```

Run it in `tmux` or `screen` so a closed SSH session does not stop it. Copy `~/wiicompiled-frame/out`
and `~/wiicompiled-frame/disc` back to the PC, send `out` to the Frame with Frame Control and copy
the disc over as in [Install on the Frame](#3-install-on-the-frame).

On some hosts, for example Unraid 7 with kernel 6.18, `binfmt_misc` registrations are per container.
`tonistiigi/binfmt --install arm64` then reports success, but Debian answers `exec format error`.
Register qemu on the host instead, with the `P` flag the tonistiigi build of qemu expects. Without it,
every program loses its first argument, and `uname -m` prints `Linux`:

```bash
docker create --name qemu-src tonistiigi/binfmt
docker cp qemu-src:/usr/bin/qemu-aarch64 /usr/local/bin/qemu-aarch64
docker rm qemu-src
echo ':qemu-aarch64:M::\x7fELF\x02\x01\x01\x00\x00\x00\x00\x00\x00\x00\x00\x00\x02\x00\xb7\x00:\xff\xff\xff\xff\xff\xff\xff\x00\xff\xff\xff\xff\xff\xff\xff\xff\xfe\xff\xff\xff:/usr/local/bin/qemu-aarch64:POCF' > /proc/sys/fs/binfmt_misc/register
docker run --rm --platform linux/arm64 debian:trixie uname -m   # aarch64
```

Unraid keeps `/usr/local/bin` in memory, so repeat this after a reboot.

## How it works

- **Same-device rendering.** SteamVR's OpenXR runtime creates the Vulkan instance and device that
  Dawn (Aurora's WebGPU layer) renders with, through Aurora's patches to Dawn
  (`aurora-main/patches/dawn`). Each eye is copied into SteamVR's swapchain on Dawn's own queue, so
  nothing is shared between GPU devices. This is the PC's Vulkan backend
  (`runtime/src/vr/openxr_vulkan_win32.cpp`), compiled for Linux. Dawn links statically, so the
  patched Dawn is built once (`Launcher/build-dawn-linux.sh`). Its `aurora-dawn.json` declares the
  Vulkan hook and density map ABIs that Aurora compiles against.
- **Headset only.** The game neither shows nor finishes rendering a desktop window, and is compiled
  for the Frame's Cortex-X4 cores (`-mcpu=cortex-x4`, overridable with `--cpu`).
- **Every refresh from the game.** The game draws 60 frames a second. When it handed SteamVR only
  those, SteamVR ran it at half rate and made up every other refresh itself, even with Motion
  Smoothing off. With `[vr] repeat_frames`, the pacing thread waits for the next frame until 1.5 ms
  before SteamVR's next wake, then resubmits the last frame at the pose it was rendered for.
  SteamVR turns that to the current head pose.
- **Eye-tracked foveation.** `XR_EXT_eye_gaze_interaction` gives the gaze, which
  `runtime/include/vr/eye_gaze.h` turns into each eye's view. Aurora picks a fragment density map
  centred on the gaze, snapped to cells of about 3 degrees (`aurora-main/lib/gfx/foveation.hpp`),
  and keeps up to 128 per eye. Each map has a memory block of its own: Turnip reads a map through a
  host mapping, and Dawn's buffer uploads unmap the shared blocks they sub-allocate from. That
  crashed the game when a race restarted, until each map got its own block.
- **120 Hz.** `[vr] refresh_rate` (default 120 on the Frame, `0` keeps the headset's own) is asked of
  SteamVR through `XR_FB_display_refresh_rate`. SteamVR only offers the rate set in its own settings.

### The Android flavour

The Quest app also has a `steamFrame` flavour (`android/Build-Quest.ps1 -Headset frame`), for the
Frame's Android layer, Lepton. It builds and starts in VR there, but cannot show a picture. The
Android backend hands each eye from Dawn's device to its own OpenXR device through
`VK_ANDROID_external_memory_android_hardware_buffer` and sync fds, and Lepton's Turnip has neither,
nor `VK_KHR_external_memory_fd`. The native build needs no sharing, which is why it is the one to
play. [`docs/quest-port.md`](docs/quest-port.md) covers the Android build.

## Reporting problems

Open an issue on this repository with:
- what you did and what you saw (which eye, where in the picture, racing or menus);
- the run's `console.log` (and `crash_sigsegv.txt` after a crash) from
  `~/.local/share/WiiCompiled/Logs/` on the Frame;
- or, for a build problem, the last lines of the failing step.

Problems that also happen on a PC or a Quest belong upstream, in
[WiiCompiled OpenXR VR](https://github.com/iChris4/Wiicompiled_VR).

## From upstream

The fork keeps everything [WiiCompiled OpenXR VR](https://github.com/iChris4/Wiicompiled_VR) does;
its README covers it in full. In the headset that means:

- Menus and unsupported scenes on a head-locked virtual screen, and races in immersive stereo.
- A first-person cockpit whose steering wheel or handlebar turns with your steering, and hand
  steering by heurazy: grab the wheel with the tracked controllers and turn it.
- The settings panel in the headset (render scale, foveation, refresh rate, controls), saved to
  `Config.toml` on the spot.
- Physics identical to the original game, proven by ghosts that sync across Wii, Dolphin and
  WiiCompiled.
- [Retro Rewind](https://wiki.tockdom.com/wiki/Retro_Rewind) as its own statically translated
  profile.

The PC (Windows D3D12 and Vulkan) and Meta Quest builds are still here and unchanged; see
[`OPENXR.md`](OPENXR.md) and [`docs/quest-port.md`](docs/quest-port.md). For those, use upstream's
[WheelWizard VR](https://github.com/iChris4/WheelWizard_VR/releases/latest) instead of this fork.

## A note on related projects

WiiCompiled, WiiCompiled OpenXR VR, Wheel Wizard, Retro Rewind and this fork are developed
**independently**, each with its **own** rules. What applies here does not automatically apply
there, and vice versa. Check each project's own CONTRIBUTING and README files.

## FAQ

**Is this an emulator?**
No. Everything is compiled to native ARM64 code before you press play. At runtime nothing emulates
a Wii CPU or GPU.

**Do you provide the game, or a ready-built binary?**
No. Nothing in this repo contains Nintendo code or assets, and the translated game is never
shipped: it is built from your own disc, a one-time cost on your machine.

**Which game version works?**
Clean PAL `RMCP01`. Other regions and modified executables are **rejected**.

**Why not install the Quest APK on the Frame?**
The Frame runs it in Lepton, whose graphics driver cannot share images between the two GPU devices
the Android backend uses, so it shows nothing. The native build uses one device and needs no
sharing.

**Can it run on other SteamOS or Linux ARM64 devices?**
Leave out `--headset steam_frame` and pass `--cpu` for your CPU to get a generic Linux VR build;
it needs an OpenXR runtime with `XR_KHR_vulkan_enable2`. Untested.

## AI usage
AI coding tools were used during development of this project. 
All translated output is verified against real hardware behavior and most importantly, physics accuracy is proven synced across Wii, Dolphin, and WiiCompiled (see FAQ). 

## Credits
- **inkwreck** - making the logo
- **[aurora](https://github.com/encounter/aurora)** - the GX rendering/windowing backend this
  project's whole graphics layer sits on. MIT licensed.
- **[Dawn](https://dawn.googlesource.com/dawn)** - Google's WebGPU implementation, powering
  aurora's Direct3D, Vulkan and OpenGL backends.
- **[OpenXR](https://www.khronos.org/openxr/)** - the Khronos cross-platform API used by the
  experimental VR renderer.
- **[WiiCompiled OpenXR VR](https://github.com/iChris4/Wiicompiled_VR)** by iChris4 and
  **[WiiCompiled](https://github.com/patchzyy/Wiicompiled)** by patchzyy - the projects this fork
  is built on.
- **heurazy** - the VR cockpit's turning steering wheel and hand steering, ported from
  **[mario-kart-wii-VR-port](https://github.com/heurazy/mario-kart-wii-VR-port)** (GPL-3.0).
- **[Dolphin Emulator](https://github.com/dolphin-emu/dolphin)** - an invaluable reference for Wii
  hardware behavior during development, plus the source of the free DSP coefficient ROM and the
  unmodified default WiiConnect24 bootstrap tree bundled with the runtime.
- **[Retro Rewind](https://wiki.tockdom.com/wiki/Retro_Rewind)** by ZPL and team - the mod
  distribution this project supports.
- **[Wheel Wizard](https://github.com/TeamWheelWizard/WheelWizard)** - the mod manager this
  project integrates with as a launch backend.
- **[nod](https://github.com/encounter/nod)** - nodtool, the disc image extractor.
- **[DolphinXR](https://github.com/iChris4/dolphinXR)** - the Steam Frame controller profile's
  input paths.
- **[Frame Control](https://github.com/saphid/frame-control)** by saphid - installing the game into
  the Frame's Steam library, and its notes on how the Frame's software fits together.
- Everyone in the static recompilation community.

Bundled third-party components and their licenses live in
[`THIRD-PARTY-NOTICES.md`](THIRD-PARTY-NOTICES.md).


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
