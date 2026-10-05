# Credits

WiiCompiled VR for the Steam Frame is the work of many people. This fork adds the SteamOS build,
the install and diagnostics scripts and the Frame-specific rendering, but most of what you play
was written elsewhere, and a good part of this fork's own fixes were ported from other people's
projects. This page lists where everything came from.

Every project below is GPL-3.0 licensed like this one unless it says otherwise. Ported commits name
their source repository and commit in their messages, and keep the original author where the
change was taken as is, so `git log` is the full record. Bundled libraries and their licenses are
in [`THIRD-PARTY-NOTICES.md`](THIRD-PARTY-NOTICES.md).

## The projects this fork is built on

- **[WiiCompiled](https://github.com/patchzyy/Wiicompiled)** by patchzyy and its contributors: the
  static recompilation of Mario Kart Wii itself, the translator, the runtime and the Aurora-based
  renderer.
- **[WiiCompiled OpenXR VR](https://github.com/iChris4/Wiicompiled_VR)** by iChris4: the OpenXR VR
  renderer, the Quest app, the headset settings panel, foveation and the first-person cockpit. This
  fork contains all of its `openxr-work` branch up to 2026-10-01.
- **[mario-kart-wii-VR-port](https://github.com/heurazy/mario-kart-wii-VR-port)** by heurazy: the
  cockpit's turning steering wheel, hand steering and USB wheel support, which came in through
  WiiCompiled OpenXR VR.
- **[DolphinXR](https://github.com/iChris4/dolphinXR)**: the OpenXR Wii Remote input design and its
  default button profile, which the controller code (`runtime/src/vr/openxr_input.cpp`) and the
  Steam Frame controller profile's input paths are adapted from.

## Ported into this fork

### From WiiCompiled (upstream)

Cherry-picked or adapted from [patchzyy/Wiicompiled](https://github.com/patchzyy/Wiicompiled) after
this fork's line split from it:

| Change | Author | Upstream |
| --- | --- | --- |
| TLS through mbed TLS on Linux and Android, which online play (Retro Rewind WFC) needs there | dorPXP, with patchzyy | #144 |
| NAND moves across mount points on Linux (saves on a different drive or the SD card) | Daan Vervacke | #212 |
| Controller mapping platform, player index sync, and socket send errors | Michael G ([DarthMDev](https://github.com/DarthMDev)) | #251 |
| `bltl` translation | patchzyy | #254 |
| The KartPad batch: KD and NCD kept while offline, RFL alarm interrupt context, shared LR continuation dispatch, pipeline cache size checks, pipeline waiter wake-ups, packed three-byte vertex reads, draw merging bounds, GEN_MODE decode, EFB copy and readback fixes, graphics startup errors, and the staging buffer wait | patchzyy, adapting Chris Sotraidis's [KartPad](https://github.com/chrissotraidis/wiicompiled) fixes | #244 |

### From other WiiCompiled forks

| Change | Author | Source |
| --- | --- | --- |
| Scene-load crash fix (`GXClearVtxDesc` keeps the position descriptor) | heurazy | [Wiicompiled_VR-PLUS](https://github.com/heurazy/Wiicompiled_VR-PLUS) c2b2500 |
| `[vr] adaptive_resolution` | heurazy | Wiicompiled_VR-PLUS, adapted |
| Building and installing Retro Rewind from its own update server (`steam-frame-install.sh --retro-rewind`) | heurazy | Wiicompiled_VR-PLUS, adapted |
| Faster disc reads: bulk DVD DMA copies, Yaz0 (SZS) decoding through host buffers, per-thread disc file handles | Chris Sotraidis | [KartPad](https://github.com/chrissotraidis/wiicompiled) ec14a0d, 97cdc9a, affabbd |
| No debug labels in the ImGui passes in normal builds (an Adreno driver crash) | Chris Sotraidis | KartPad 420b828, extended to this fork's extra passes |
| A TLS session that failed a write is kept instead of its socket being deleted | Michael G ([DarthMDev](https://github.com/DarthMDev)) | [DarthMDev/Wiicompiled](https://github.com/DarthMDev/Wiicompiled) a2ecc0f, fcf8646 (upstream PR #258) |
| `Config.toml` saved through a temporary file and a rename | BlackAndBlue95 | [Strikers-WiiCompiled](https://github.com/BlackAndBlue95/Strikers-WiiCompiled) 435daf3 |
| No depth writes while the Z compare is off (the Stormship lightning) | BlackAndBlue95 | Strikers-WiiCompiled 369ec99 |
| NEON forms of the AX audio mix kernels | rooklz | [rooklz/Wiicompiled](https://github.com/rooklz/Wiicompiled) 4346362 |
| Emptied WC24 bootstrap files are refilled | nx-mod | [wiicompiled-nx](https://github.com/nx-mod/wiicompiled-nx) d0149e6, adapted |
| Guest memory access checks folded away on 4 KiB-page builds | nx-mod's finding | wiicompiled-nx 18ef16f, done here as a compile-time constant |

## Tools and references

- **[aurora](https://github.com/encounter/aurora)** by Luke Street: the GX rendering and windowing
  backend the whole graphics layer sits on (MIT).
- **[Dawn](https://dawn.googlesource.com/dawn)**: Google's WebGPU implementation, under Aurora.
- **[OpenXR](https://www.khronos.org/openxr/)** by Khronos: the VR API.
- **[Mbed TLS](https://github.com/Mbed-TLS/mbedtls)**: TLS for online play on Linux and Android.
- **[Dolphin Emulator](https://github.com/dolphin-emu/dolphin)**: a reference for Wii hardware
  behaviour, and the source of the DSP coefficient ROM, the WiiConnect24 bootstrap tree and the
  Riivolution parser bundled with the runtime.
- **[nod](https://github.com/encounter/nod)** by Luke Street: `nodtool`, the disc image extractor.
- **[Retro Rewind](https://wiki.tockdom.com/wiki/Retro_Rewind)** by ZPL and team: the mod
  distribution this project supports.
- **[Wheel Wizard](https://github.com/TeamWheelWizard/WheelWizard)**: the mod manager the PC build
  integrates with, and the model for how the install script fetches Retro Rewind.
- **[Frame Control](https://github.com/saphid/frame-control)** by saphid: installing the game into
  the Frame's Steam library, and its notes on how the Frame's software fits together.
- **Inkwreck**: the logo.
- Everyone in the static recompilation community.

If something of yours is in this fork and missing here, or credited wrongly, please open an issue.
