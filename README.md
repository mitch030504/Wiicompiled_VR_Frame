<img width="4190" height="2464" alt="Mario Kart WiiCompiled VR logo (logo by Inkwreck)" src="docs/images/wiicompiled-vr-logo.png" />

# WiiCompiled VR for the Steam Frame

<p align="center">
  <img alt="Steam Frame, SteamOS ARM64" src="https://img.shields.io/badge/Steam%20Frame-SteamOS%20%C2%B7%20ARM64-1A9FFF?logo=steam&amp;logoColor=white">
  <img alt="Status: untested on the headset" src="https://img.shields.io/badge/status-untested%20on%20the%20headset-FF9F0A">
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
> **Not yet run on a Steam Frame.** The Frame build compiles and its unit tests pass, but nobody
> has played it on the headset yet. Expect it to fail in ways only the device shows; reports with
> the run log are what moves it forward (see [Reporting problems](#reporting-problems)).

---

## What this fork adds

Everything below is in [`docs/steam-frame.md`](docs/steam-frame.md), with the reasoning and the
readings it is based on.

- **A native SteamOS build.** The game links SteamVR's OpenXR runtime directly and lets it create
  the GPU device it renders with, so each eye is copied straight into the headset's swapchain with
  no second device and no sharing between them. It runs fullscreen in the headset only; there is
  no desktop window to draw.
- **Built for the Frame's Snapdragon 8 Gen 3**: compiled with `-mcpu=cortex-x4`.
- **The Frame's controllers.** Its own interaction profile is bound, so beside what the Quest Touch
  layout already does, the left D-pad is the Wii Remote's D-pad (tricks, menus), the left View
  button pauses and the left shoulder opens the settings panel.
- **120 Hz.** The headset is asked for 120 Hz, exactly two display refreshes per game frame at the
  game's 60 FPS, so motion is even. `[vr] refresh_rate` changes it.
- **Eye-tracked foveation.** Variable-resolution rendering whose sharp centre follows your gaze
  through the Frame's eye tracking, instead of staying fixed straight ahead. `[vr] foveation` sets
  the strength and `[vr] eye_tracked_foveation` turns the tracking off.
- **Standalone defaults**: 0.8 render scale, the game's own object culling and medium foveation,
  as on the Quest, sized for a mobile GPU driving 2160x2160 per eye.
- **Build tooling.** `Launcher/build-dawn-linux.sh` builds the patched Dawn (Aurora's WebGPU
  layer) the VR backend needs, and `Launcher/local-build.sh` gained `--openxr`, `--dawn-package`,
  `--headset steam_frame` and `--cpu`.

The Steam Frame also runs Android apps through its Lepton layer, and the Quest app gained a
`steamFrame` flavour for it, but it cannot show a picture there: Lepton's graphics driver lacks
the memory-sharing extensions the Android backend needs. The native build is the way to play.

## Requirements

- A Steam Frame with SteamVR, reachable over SSH (`ssh steamos@<frame-ip>`).
- A clean, unmodified **PAL `RMCP01`** disc image of Mario Kart Wii, dumped by you. ISO, GCM,
  GCZ, CISO, WBFS, WIA and RVZ can all be extracted. Other regions and patched executables are
  rejected.
- Somewhere to build. Either:
  - **an x86_64 Linux PC** with podman and qemu: it builds in an emulated ARM64 container, which is
    slow (the first build takes hours) but spares the Frame; or
  - **the Frame itself**, in a podman container there.
- Several GB of free disk space for the toolchain, Dawn and the game.

> [!NOTE]
> Nobody here will tell you where to get the game. Dumping your own disc is on you, and links to
> game files won't be provided or tolerated.

## Building and installing

The commands are in [`docs/steam-frame.md`](docs/steam-frame.md): [Building it on a Linux
PC](docs/steam-frame.md#building-it-on-a-linux-pc) or [Building it on the
Frame](docs/steam-frame.md#building-it-on-the-frame). In short:

1. Extract your disc with [nodtool](https://github.com/encounter/nod) and copy `sys/main.dol` and
   `files/rel/StaticR.rel` into `Assets/`.
2. Start a Debian trixie ARM64 container and install the build packages, the bundled clang 22,
   CMake and Ninja (`Launcher/prepare-portable-tools.sh --arch aarch64`), and .NET 8.
3. Build the patched Dawn: `Launcher/build-dawn-linux.sh`.
4. Build the game: `Launcher/local-build.sh ... --openxr --dawn-package <dawn>/package --headset steam_frame`.
5. Copy the output and the extracted disc to the Frame, set `[paths] dvd_root` in
   `~/.local/share/WiiCompiled/Config.toml`, start SteamVR, then start `WiiCompiled`.

## Reporting problems

Open an issue on this repository with the run log from `~/.local/share/WiiCompiled/Logs/` on the
Frame, or the last lines of the failing build step. [Running
it](docs/steam-frame.md#running-it) lists the log lines a working start shows, in order; the
first one missing says where it stopped.

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
