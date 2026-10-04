# WiiCompiled VR on the Steam Frame

Valve's Steam Frame runs SteamOS on a Snapdragon 8 Gen 3 (Cortex-X4, A720 and A520 cores, Adreno 750),
with 2160x2160 panels per eye at 72 to 144 Hz, eye tracking, and SteamVR as its OpenXR runtime. It runs
Android apps through Lepton, SteamOS's Android layer, where SteamVR provides an Android OpenXR runtime
(OpenXR 1.0, through the Khronos loader's runtime broker). The Steam Frame build is therefore a third
flavour of the Quest app, `steamFrame`: everything in `docs/quest-port.md` below the app shell (the
Vulkan backend, the game kit, `.wcgame` packages, the on-headset build) applies unchanged, and this
document covers what differs.

A native SteamOS ARM64 build is a separate, later piece of work: Linux has no OpenXR graphics backend
yet (see [A native SteamOS build](#a-native-steamos-build)).

**Status: not yet run on a Steam Frame.** Everything below compiles and is unit-tested, but the
device checks at the end are still to do.

## What the flavour changes

| | Quest flavours | `steamFrame` |
| --- | --- | --- |
| CPU target (`kit.json` `androidCpu`) | `cortex-a77` (`kryo` on Quest 1) | `cortex-x4` |
| `MKW_ANDROID_HEADSET` | `quest` | `steam_frame` (defines `MKW_HEADSET_STEAM_FRAME`) |
| Library entry | `LauncherActivity` (Quest 1: `QuestActivity`) | `FrameEntryActivity` |
| Horizon OS manifest entries | present | removed |
| `[vr] refresh_rate` default | `0` (the headset's own) | `120` |
| `[vr] passthrough` | default on (`XR_FB_passthrough`) | not asked for, default off, setting hidden |
| `[vr] eye_tracked_foveation` default | off | on |

The application ID stays `org.wiicompiled.quest`, so the storage paths in `docs/quest-port.md` hold
as they are. The kit's CPU string differs from the Quest ones, which gives the Frame its own kit
fingerprint: a game built for a Quest is refused on the Frame and the other way round, by the same
checks that keep Quest 1 and modern Quest games apart.

**CPU.** Every core of the 8 Gen 3 implements ARMv9.2, so the products target the Cortex-X4 with
its whole feature set. That includes SVE and SVE2, which clang auto-vectorises with (a simple loop
compiled with `-O3` used SVE registers ten times). Phones with this chip do not expose SVE, but the
Frame's kernel does: `/proc/cpuinfo` lists `sve`, `sve2`, `svei8mm`, `svebf16` and the SVE2 crypto
extensions, on SteamOS and inside Lepton alike. A build for a device without SVE would need
`cortex-x4+nosve`. The flavour-to-CPU map lives once in
`android/app/build.gradle.kts` (`headsetCpus`), which the kit export also reads now instead of
guessing from the variant name.

**Launch under Lepton.** Lepton starts the one real activity that is both `MAIN` and `LAUNCHER`, and
runs the app in VR when that activity carries a VR category; it ignores `activity-alias` entries.
Quest builds put `LAUNCHER` on the 2D panel (or, on Quest 1, add an alias), so neither works there.
`src/steamFrame/AndroidManifest.xml` makes `FrameEntryActivity` the only `MAIN`/`LAUNCHER` activity,
with `org.khronos.openxr.intent.category.IMMERSIVE_HMD` and `com.oculus.intent.category.VR`. It
shows nothing: it always opens the setup panel (`LauncherActivity`), and when the selected game can
start as it is (game files, a game built for this kit, Retro Rewind's pack, and no enabled mods
still to copy into the pack), it opens `QuestActivity` on top of it. The headset therefore goes
straight into VR, and quitting the game returns to the panel for setup, imports and mods.
`adb logcat -s WiiCompiledLauncher` shows which way it went.

The manifest also removes Horizon OS's own entries (`com.oculus.supportedDevices`, `focusaware`,
`trade_cpu_for_gpu_amount`, the passthrough feature and the hand tracking permissions and feature)
and keeps the Khronos broker queries and the `OPENXR_SYSTEM` permission, which any Android OpenXR
runtime needs.

## Controllers

With `XR_VALVE_frame_controller_interaction` the runtime offers the Frame controller's own profile,
`/interaction_profiles/valve/frame_controller_valve`. Without it SteamVR presents the controllers as
Touch controllers, which loses the left D-pad. `openxr_input.cpp` suggests it after Touch and the
simple controller. Each hand has a thumbstick, trigger, grip and shoulder button. The right hand has
A, B, X, Y and a menu button; the left hand has a D-pad and a View button. Binding paths follow
DolphinXR's port (iChris4/dolphinXR#9). Windows asks for the same extension, so a Frame streaming
from a PC through SteamVR gets the D-pad too.

| Frame controller | Wii Remote mode | Gamepad mode |
| --- | --- | --- |
| Right A | A | South (A) |
| Right B | C (look behind) | East (B) |
| Right trigger | B | Right trigger |
| Right stick up / down | 1 / 2 | Right stick |
| Left View | + (pause) | Start |
| Left shoulder | Settings panel (Touch's left Y) | North (Y) |
| Left D-pad | Wii Remote D-pad | D-pad |
| Left stick, left trigger | Nunchuk stick, Z | Left stick, left trigger |
| Grips, stick clicks, motion, aim | as on Touch (`OPENXR.md`, Controllers) | as on Touch |
| Right X, Y, menu and shoulder | unbound | unbound |

The four D-pad actions are new and also reach the virtual gamepad's D-pad; Touch leaves them unbound,
so nothing changes on a Quest.

## Refresh rate

`[vr] refresh_rate` (Hz, `0` = the headset's own rate) is asked of the runtime through
`XR_FB_display_refresh_rate` each time the session starts running and whenever the setting changes.
The request uses the runtime's own value within half a hertz of the setting (runtimes report 119.98
for 120). Setting it back to `0` restores the rate the session started at. The game renders 60 frames
a second, so at 120 Hz each frame shows for exactly two refreshes. At 72 or 90 Hz some frames show
for one refresh and others for two, which judders. The Frame starts at 120. Render-first pacing
(`docs/quest-port.md`) already waits for each sealed game frame, so on the Frame the pacing summary
should read about 60 `skipped-slots` a second with no `late` cycles.

Lepton may decline the request (frame-control found SteamVR keeping its own rate there). The session
log then says `display refresh rate 120 Hz refused` with the rates it offers, and nothing else
changes. The setting is in the headset panel and in the launcher (VR → Headset); other headsets
offer it as well, at their own default of `0`.

## Eye-tracked foveation

`[vr] eye_tracked_foveation` (default on for the Frame) moves the foveation level's full-density
region to where the player looks:

1. At launch the runtime asks for `XR_EXT_eye_gaze_interaction`. If the system reports an eye tracker,
   `OpenXRInput` binds the gaze pose (`/user/eyes_ext/input/gaze_ext/pose`) and locates it for each
   packet's display time, in the space the eye views are located in.
2. `vr/eye_gaze.h` turns the gaze into tangents of each eye's own view, which may be canted.
   `AuroraStereoFrame` carries them as `gaze` and `gazeValid`, appended after its existing fields.
3. Aurora snaps the gaze to a cell of two map texels (64 pixels, about 3 degrees) and builds that
   cell's density map with the level's rings centred on the gaze (`gfx/foveation.hpp`).

Each eye keeps up to 32 maps, one per cell looked at, so a glance back reuses its map instead of
uploading a new one. A new map is bound once its upload has completed, and until then the eye keeps
the map it had. A blink, lost tracking or the setting turned off returns to the map centred on the
forward direction, which is byte-identical to the fixed foveation map. No change to the Dawn patch
was needed: maps stay immutable, and the patch already lets a view be rebound to another map.

The session log reports `OpenXR eye gaze: available` (or that the runtime has no eye tracker),
`OpenXR eye gaze: tracking` at the first tracked sample, and `eye foveation medium following the
gaze` for each eye's first gaze map. Foveation pays only when an eye is pixel-bound
(`OPENXR.md`, Foveated rendering), which the Frame's larger eyes make more likely.

If the Frame's driver offers `VK_QCOM_fragment_density_map_offset` or
`VK_EXT_fragment_density_map_offset`, shifting one map per pass would replace switching between
maps. That needs the Dawn patch to create the eye textures with the offset flag, so it waits for
the device's extension list.

## Building and installing

On the Windows build host described in `docs/quest-port.md`:

```powershell
powershell -ExecutionPolicy Bypass -File android/Build-Quest.ps1 -Headset frame               # the steamFrame APK; checks kit.json says cortex-x4
powershell -ExecutionPolicy Bypass -File android/Build-QuestGame.ps1 -Headset frame -Product base -Data <DATA>   # a .wcgame for the Frame's kit
```

The APK lands in `android/app/build/outputs/apk/steamFrame/<configuration>`. WheelWizard VR's
"Build for Quest" builds a Frame game unchanged once it is given the Frame APK (Setup takes the
headset from the APK's kit). WheelWizard itself still needs a Steam Frame choice that fetches that
APK from the release, published as `…-SteamFrame.apk`.

Lepton opens an adb port (5555 and up) for each running Android instance, reachable over the
network. With an Android app running on the Frame, `adb connect <frame-ip>:5555` reaches it from the
build PC. How the APK reaches the Steam library (adb into a Lepton instance, frame-control, or
Steam's own sideloading) is to be confirmed on the device.

## What the Frame reported

Read on 2026-10-04 from a Steam Frame running SteamOS (`holo`), kernel 6.18.0, with the commands
below:

| Reading | SteamOS | Lepton |
| --- | --- | --- |
| Page size | 4096 | 4096 |
| CPU | 8 cores; `sve sve2 svei8mm svebf16 sveaes svepmull svebitperm svesha3 svesm4 i8mm bf16 bti paca pacg ...` | the same |
| Android | — | 11 (API 30, LineageOS), `ro.product.model` Lepton, device `lepton_arm64_only`, platform `waydroid`, `ro.steam.running_in_app_container=true` |
| Vulkan driver | — | `ro.hardware.vulkan=freedreno`: Mesa's Turnip, not Qualcomm's driver |
| OpenXR runtime | SteamVR, `bin/linuxarm64/vrclient.so` (`~/.config/openxr/1/active_runtime.json`); SteamOS ships the SDK headers, `libopenxr_loader.a` and `openxr.pc` | `/vendor/etc/openxr/1/active_runtime.json`, from the host's `/usr/share/guestos/android/vendor/etc/openxr`; no runtime broker package |
| Implicit OpenXR layers | `XrApiLayer_VALVE_fdm_injection` (also listed as explicit) | `XrApiLayer_VALVE_fdm_injection` |

What follows from them:

- **Fast memory path.** 4 KB pages keep the translated code's flat memory path. A 16 KB kernel
  would have sent it through the checked path.
- **CPU target.** The Frame exposes SVE, so the build targets the whole `cortex-x4` (above).
- **Android version.** API 30 meets the app's minimum of 29.
- **Driver workarounds.** Lepton is a Waydroid container, and its Vulkan driver is Turnip. The
  Adreno workarounds in `docs/quest-port.md` were found on Qualcomm's own driver. The vertex padding
  stays on (it is correct either way); `debug.wiicompiled.vtxpad 0` can check whether Turnip needs it.
- **Open:** whether Turnip in Lepton imports AHardwareBuffers and sync fds is in the `vkjson`
  extension list, still to read.
- **Finding the runtime.** An app inside Lepton reaches SteamVR's OpenXR runtime through the system
  runtime file, not a broker. The Khronos loader the game links statically (`DYNAMIC_LOADER OFF`)
  tries the runtime brokers first, then reads `/{product,odm,oem,vendor,system}/etc/openxr/1/active_runtime.json`,
  so no app change is needed; the manifest's broker queries are simply unused here. Walkabout Mini
  Golf, an Android VR game, runs in the same Lepton.
- **Valve's foveation layer.** `XrApiLayer_VALVE_fdm_injection` is implicit, so it wraps every
  Android OpenXR app. By its name it adds fragment density maps to apps' own render passes. This
  game draws its eyes on Dawn's device and only copies them into the swapchain on the OpenXR
  device, so the layer has no render pass of the game's to change; the game's own maps
  (eye-tracked foveation, above) do that. If the layer gets in the way, its JSON names the
  environment variable that disables it.

## Device checklist

Information to collect first, from any PC over Lepton's adb port (the commands work in bash, zsh and
fish; in PowerShell only the adb lines do), with an Android app running on the Frame:

```sh
adb connect <frame-ip>:5555
adb -s <frame-ip>:5555 shell 'getprop ro.build.version.release; getprop ro.build.version.sdk; getprop ro.product.manufacturer; getprop ro.product.model; getprop ro.product.device; getprop ro.hardware.vulkan; getprop ro.board.platform'
adb -s <frame-ip>:5555 shell 'uname -a; getconf PAGE_SIZE; grep -m1 Features /proc/cpuinfo; grep -c processor /proc/cpuinfo'
adb -s <frame-ip>:5555 shell cmd gpu vkjson > frame-vkjson.json
adb -s <frame-ip>:5555 shell "pm list packages | grep -i -E 'xr|valve|steam|khronos|openxr'"
# The parts of frame-vkjson.json that matter:
grep -oE '"(deviceName|driverName|driverInfo|apiVersion|driverVersion)": *[^,]*' frame-vkjson.json | sort -u
grep -oE '"extensionName": *"[^"]*"' frame-vkjson.json | grep -iE 'hardware_buffer|external_semaphore|external_fence|external_memory|fragment_density|shading_rate|dynamic_rendering' | sort -u
```

and on the Frame itself (Desktop Mode, Konsole):

```bash
uname -a; getconf PAGESIZE; grep -m1 Features /proc/cpuinfo; head -5 /etc/os-release
cat ~/.config/openxr/1/active_runtime.json 2>/dev/null; ls /usr/share/openxr/1/ /etc/xdg/openxr/1/ 2>/dev/null
```

What each answers:

- `vkjson`: whether Lepton's Vulkan driver has what the Android bridge needs:
  - `VK_ANDROID_external_memory_android_hardware_buffer`;
  - `VK_KHR_external_semaphore_fd` and `VK_KHR_external_fence_fd` with sync fd handles.

  Without these the APK route cannot present at all, and the native route becomes the way. It also
  shows `VK_EXT_fragment_density_map` (foveation), the density map offset extensions, and which
  driver Lepton uses.
- The CPU features line: no `sve`, as the CPU target assumes.
- The page size: on a 16 KB-page kernel the runtime finds out at launch and routes translated memory
  accesses through the checked path (`guest_flat_memory.h`, `RequiresCheckedAccess`), which works but
  is slower. That is worth knowing before measuring.
- The Android version: the app needs API 29 (Android 10) or newer.

Then, on the first launch, the session log (`Logs/<product>_<stamp>_pid<pid>/console.log` next to
`DATA`) and `adb logcat -s SDL WiiCompiledQuest WiiCompiledLauncher` should show, in order:

1. `OpenXR Android loader initialized`;
2. `OpenXR runtime offers N extensions: ...`, the whole list SteamVR's Android runtime has;
3. `OpenXR initialized: runtime '...'` with SteamVR's name;
4. the negotiated Vulkan binding, then `OpenXR Vulkan swapchains ready`;
5. `display refresh rate 120 Hz requested` (or `refused`, with the rates on offer);
6. the session reaching `FOCUSED`;
7. `OpenXR interaction profiles: left /interaction_profiles/valve/frame_controller_valve, right ...`;
8. `OpenXR eye gaze: available`, then `tracking`;
9. `presentation=virtual-screen` for the menus, and `first immersive packet consumed` on race entry.

Then, in the game:

- the D-pad does tricks, the left shoulder opens the settings panel, and View pauses;
- `debug.wiicompiled.fpslog 1` on a race start shows the pacing summary and the GPU time per pass
  with foveation off, fixed and following the gaze;
- `render_scale` starts at 0.8, the Quest's value. The runtime's recommended eye size (logged at
  startup) and those measurements decide whether the Frame keeps it.

A black headset with a working mirror points at the AHardwareBuffer copy, as on the Quest
(`docs/quest-port.md`, Validation status).

Open questions only the device can answer:

- Whether Lepton's driver supports the AHardwareBuffer and sync fd bridge.
- Whether Lepton shows the 2D setup panel while the app runs in VR mode. If it does not, the game
  still starts directly once a `.wcgame` with the game files has been imported, but importing needs
  the panel.
- Whether SteamVR grants 120 Hz.
- Whether the gaze needs an Android permission under Lepton.
- Whether "Build on this headset" can run its toolchain through `/system/bin/linker64` inside
  Lepton. A game built on the PC does not depend on it.

## A native SteamOS build

Valve recommends native Linux ARM64 builds for the Frame, and one would avoid Lepton and the
two-device copy. The pieces:

- **Backend.** The Windows Vulkan backend (`openxr_vulkan_win32.cpp`), where OpenXR creates Dawn's
  own device and eyes are copied on Dawn's queue, ports almost as it is. Only its `_WIN32` guards are
  platform-specific.
- **Interop.** Aurora's `vulkan_win32_interop.cpp` finds the patched Dawn's exports with
  `GetModuleHandleW`. A static Linux Dawn would reference them directly, and `aurora_core.cmake`
  compiles that file on Windows only.
- **Dawn.** A linux-aarch64 Dawn built with `aurora-main/patches/dawn` (the hook ABI and density
  maps), as `android/Build-QuestDawn.ps1` already does for Android.
- **`openxr_integration.cpp`.** It needs a Linux branch asking for `XR_KHR_vulkan_enable2` and
  `XR_KHR_convert_timespec_time`. Today its `#else` is Android's and requires
  `XR_KHR_android_create_instance`.
- **Controller timing.** `openxr_input.cpp` needs a `__linux__` branch for the input clock.
- **CPU target.** An `MKW_LINUX_CPU` knob in place of `-mcpu=native`, for cross-builds.
- **Android-gated fixes.** The Adreno vertex padding, `headset_owns_display` and the
  `last_pass_feeding_replay` saving are gated on `__ANDROID__`. They would follow the GPU or the
  headset instead.
- **Packaging.** SteamOS packaging, and a way to build the player's game for it.
