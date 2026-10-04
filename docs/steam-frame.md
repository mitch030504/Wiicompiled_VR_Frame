# WiiCompiled VR on the Steam Frame

Valve's Steam Frame runs SteamOS on a Snapdragon 8 Gen 3 (Cortex-X4, A720 and A520 cores, Adreno 750),
with 2160x2160 panels per eye at 72 to 144 Hz, eye tracking, and SteamVR as its OpenXR runtime. A game
can run on it two ways, and this project has both:

- **Natively on SteamOS** (Linux ARM64), with SteamVR's own OpenXR runtime. This is the Frame's build:
  [The native SteamOS build](#the-native-steamos-build) says how to make and run it.
- **As an Android app in Lepton**, SteamOS's Android layer, as a third flavour of the Quest app
  (`steamFrame`). It is built, but it cannot show a picture there: Lepton's Vulkan driver has no
  external memory or sync fd extensions, and the Quest backend's two-device eye handoff needs them
  (see [What the Frame reported](#what-the-frame-reported)).

Most of what this document describes is shared by both: the Frame controller profile, the 120 Hz
request, eye-tracked foveation and the Frame's defaults. The native build gets them through
`MKW_HEADSET=steam_frame` (`MKW_HEADSET_STEAM_FRAME`), as the Android flavour does.

**Status: not yet run on a Steam Frame.** The native build's VR code compiles and the unit tests
pass; building it on the Frame and the device checks are still to do.

## The native SteamOS build

The backend is the PC's same-device Vulkan backend (`openxr_vulkan_win32.cpp`, on Linux too): the
OpenXR runtime creates Dawn's own Vulkan instance and device through Aurora's patches to Dawn, and
each eye is copied into SteamVR's swapchain on Dawn's queue, so nothing is shared between devices.
On Linux, Dawn links statically, so the patched Dawn is built once on the build machine
(`Launcher/build-dawn-linux.sh`); `aurora-dawn.json` in its package declares the Vulkan hook and
density map ABIs, and only against such a package does Aurora compile the bridge
(`AURORA_DAWN_VULKAN_HOOKS`) and the density maps (`AURORA_DAWN_FDM`). Against a stock Dawn the
build still links, and VR falls back to the desktop.

What the Frame build changes, beyond the Android flavour's settings:

- `-mcpu=cortex-x4` (`MKW_LINUX_CPU`, which `--cpu` overrides).
- `AuroraConfig::xrHeadsetOnly`: Aurora neither presents the desktop window nor renders it past the
  last pass the eyes sample, as on Android (4 to 6 ms of a 12 ms GPU frame on a Quest 3).
- Fragment density maps are asked for on Linux as on the Quest; `AURORA_FDM=0` or `1` overrides the
  settings, as `debug.wiicompiled.fdm` does there.
- Controller motion uses `XR_KHR_convert_timespec_time` when SteamVR offers it.

### Building it on the Frame

SteamOS's root file system is read-only, so the build runs in a Debian container on the Frame,
started with the `podman` SteamOS already ships. Over SSH (`ssh steamos@<frame-ip>`):

```bash
mkdir -p ~/wiicompiled && cd ~/wiicompiled
git clone https://github.com/mitch030504/Wiicompiled_VR_Frame.git
podman run -it --name wiicompiled-build -v ~/wiicompiled:/work:Z docker.io/library/debian:trixie bash
```

Inside the container (`podman start -ai wiicompiled-build` gets back into it later):

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
Launcher/build-dawn-linux.sh --work-dir /work/dawn --cc $T/clang --cxx $T/clang++ --cmake $T/cmake --ninja $T/ninja
```

Then the game. `local-build.sh` translates your own disc, so it needs `main.dol` and `StaticR.rel` from
your extracted PAL `RMCP01` disc in `Assets/` (the extracted disc's `sys/main.dol` and
`files/rel/StaticR.rel`; `translator/README.md` explains):

```bash
mkdir -p Assets && cp <DATA>/sys/main.dol <DATA>/files/rel/StaticR.rel Assets/
Launcher/local-build.sh --output-dir /work/out --cc $T/clang --cxx $T/clang++ --fuse-ld lld \
    --cmake $T/cmake --ninja $T/ninja --dotnet /work/dotnet/dotnet \
    --openxr --dawn-package /work/dawn/package --headset steam_frame
```

The game lands in `~/wiicompiled/out` on the Frame. Debian trixie's C library is not newer than
SteamOS's, so the binary runs on SteamOS outside the container. If CMake reports a missing package,
install its `-dev` package in the container and run the same command again; both scripts resume
where they stopped.

### Building it on a Linux PC

The same container runs on an x86_64 Linux PC as an emulated ARM64 one, which spares the Frame's
storage and battery; the result is copied over. Emulation makes it several times slower: the
first Dawn build takes hours. On the PC (these commands also work in fish):

```bash
sudo pacman -S --needed podman qemu-user-static qemu-user-static-binfmt   # Arch, CachyOS
sudo systemctl restart systemd-binfmt
podman run --rm --platform linux/arm64 docker.io/library/debian:trixie uname -m   # prints aarch64
```

Other distributions name the packages differently (on Debian and Ubuntu: `podman
qemu-user-static binfmt-support`). If rootless podman complains about subordinate ids, run
`sudo usermod --add-subuids 100000-165535 --add-subgids 100000-165535 $USER` and log in again.

Extract your disc image with [nodtool](https://github.com/encounter/nod), the extractor the
installer uses, and put the two files the build reads into `Assets/`:

```bash
mkdir -p ~/wiicompiled; cd ~/wiicompiled
git clone https://github.com/mitch030504/Wiicompiled_VR_Frame.git
curl -fL -o nodtool https://github.com/encounter/nod/releases/download/v2.0.0-alpha.10/nodtool-linux-x86_64
chmod +x nodtool
./nodtool extract "/path/to/Mario Kart Wii.wbfs" disc-extract
mkdir -p Wiicompiled_VR_Frame/Assets
cp disc-extract/sys/main.dol disc-extract/files/rel/StaticR.rel Wiicompiled_VR_Frame/Assets/
podman run -it --name wiicompiled-frame --platform linux/arm64 -v ~/wiicompiled:/work docker.io/library/debian:trixie bash
```

Inside the container, run the commands of [Building it on the Frame](#building-it-on-the-frame)
from `apt-get` on, skipping the `cp` into `Assets/`, which is done. `podman start -ai
wiicompiled-frame` gets back into it; set `T` again before resuming. Then copy the game and the
extracted disc to the Frame:

```bash
ssh steamos@<frame-ip> mkdir -p wiicompiled
scp -r ~/wiicompiled/out steamos@<frame-ip>:wiicompiled/
scp -r ~/wiicompiled/disc-extract steamos@<frame-ip>:wiicompiled/disc
```

### Running it

The game reads its `Config.toml` from `~/.local/share/WiiCompiled/` on SteamOS (it is created on the first start): set
`[paths] dvd_root` there to your extracted disc (the directory holding `sys/` and `files/`;
`/home/steamos/wiicompiled/disc` when it was copied as above). Start
SteamVR on the Frame, then start `~/wiicompiled/out/WiiCompiled`, from Desktop Mode or as a
non-Steam game added to the library. The run log is in `Logs/` next to `Config.toml`; it should show,
in order:

1. `OpenXR runtime offers N extensions: ...`, and `OpenXR initialized: runtime 'SteamVR/OpenXR'`;
2. `OpenXR Vulkan requirements: ... Dawn will create its device through the runtime`;
3. `Fragment density maps: enabled` (the patched Dawn and Turnip's density maps);
4. `OpenXR Vulkan swapchains ready ... same-queue native eye copies`;
5. `display refresh rate 120 Hz requested`, the session reaching `FOCUSED`, and
   `OpenXR interaction profiles: left /interaction_profiles/valve/frame_controller_valve`;
6. `OpenXR eye gaze: available`, then `tracking`.

`Linux Vulkan OpenXR requires a Dawn built with Aurora's patches` means the build used a stock Dawn:
check that `--dawn-package` pointed at `build-dawn-linux.sh`'s `package` directory.

## The Android flavour in Lepton

Everything from here to [Building and installing](#building-and-installing) is the `steamFrame`
flavour of the Quest app. Its controller, refresh rate and foveation work is shared with the native
build; its launch and manifest are Lepton's.

### What the flavour changes

| | Quest flavours | `steamFrame` |
| --- | --- | --- |
| CPU target (`kit.json` `androidCpu`) | `cortex-a77` (`kryo` on Quest 1) | `cortex-x4` |
| `MKW_HEADSET` | empty | `steam_frame` (defines `MKW_HEADSET_STEAM_FRAME`) |
| Library entry | `LauncherActivity` (Quest 1: `QuestActivity`) | `FrameEntryActivity` |
| Horizon OS manifest entries | present | removed |
| `[vr] refresh_rate` default | `0` (the headset's own) | `120` |
| `[vr] passthrough` | default on (`XR_FB_passthrough`) | not asked for, default off, setting hidden |
| `[vr] eye_tracked_foveation` default | off | on |
| `[vr] repeat_frames` default | off | on |

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
for one refresh and others for two, which judders. The Frame starts at 120.

Render-first pacing (`docs/quest-port.md`) submits a frame once the game has sealed one, 60 times a
second. On the Frame, SteamVR answered that by running the app at half rate (the pacing summary read
`predicted-rate=60.0Hz`) and filling every other refresh itself, even with Motion Smoothing off, which
doubled the HUD and the menu screen while the head turned. `[vr] repeat_frames` (default on for the
Frame, off elsewhere, live in the headset panel's VR tab) therefore submits the retained layer, with
the poses it was rendered for, on every refresh the next eyes are not ready for: the pacing thread
waits for them until 1.5 ms before the runtime's next wake (a period after the last xrWaitFrame
returned) and otherwise spends that refresh on a keep-alive cycle, which xrWaitFrame paces. The
summary should then read `predicted-rate=120.0Hz`, about 60 `keepalive` a second and 60 `new`
layers. A first version waited only a millisecond, so every packet also spent a refresh on a repeat
it did not need, the next packet missed the game's next frame, and `new` fell to about 35 a second.

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
   cell's density map with the level's rings centred on the gaze (`gfx/foveation.hpp`). Both rings
   are 8 degrees wider than the fixed map's: the full-density region has to cover where a saccade
   lands until the next game frame's map is bound, the tracker's error, and Turnip shading a whole
   render-pass bin at one density.

Each eye keeps up to 128 maps, one per cell looked at, so a glance back reuses its map instead of
uploading a new one. Each map has a memory block of its own: Turnip reads a map through a host
mapping of its memory, and Dawn's buffer uploads unmap the shared blocks they sub-allocate from. A new map is bound once its upload has completed, and until then the eye keeps
the map it had. A blink, lost tracking or the setting turned off returns to the map centred on the
forward direction, which is byte-identical to the fixed foveation map. Maps stay immutable, and the
Dawn patch lets a view be rebound to another map.

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
| Vulkan driver | Turnip, Mesa 26.3.0-devel, Vulkan 1.4.362: `VK_EXT_fragment_density_map` (non-subsampled images, not dynamic), `VK_EXT_fragment_density_map_offset` and `VK_QCOM_fragment_density_map_offset`, `VK_KHR_external_{memory,semaphore,fence}_fd`, `VK_EXT_external_memory_dma_buf`, `VK_EXT_queue_family_foreign`, `VK_KHR_dynamic_rendering`; Valve's `fdm_injection` and `rpo` Vulkan layers | `ro.hardware.vulkan=freedreno`: the same Mesa 26.3.0-devel Turnip built for Android (`vulkan.pastel.so` is also present, not selected). `/dev/kgsl-3d0` is the DRM render node |
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
- **Foveation.** The host's Turnip has density maps for non-subsampled images through dynamic
  rendering, what the Dawn patch needs, and both density map offset extensions, which would let
  eye-tracked foveation shift one map instead of switching maps.
- **No buffer sharing between devices in Lepton.** The Vulkan Hardware Capability Viewer (4.03,
  the last release for Android 11), run inside Lepton, reports Turnip `26.2.99` (Vulkan 1.4.362,
  display name "Valve Lepton") with `VK_EXT_fragment_density_map`, both density map offset
  extensions, `VK_VALVE_fragment_density_map_layered`, `VK_KHR_timeline_semaphore` and the
  maintenance extensions, but **no** `VK_ANDROID_external_memory_android_hardware_buffer`,
  `VK_KHR_external_memory_fd`, `VK_KHR_external_semaphore_fd` or `VK_KHR_external_fence_fd`. The
  Quest backend (`openxr_vulkan.cpp`) hands each eye from Dawn's device to its own OpenXR device
  through exactly those, so it cannot present under Lepton. What can: binding Dawn's own device to
  the session, as the Windows Vulkan backend (`openxr_vulkan_win32.cpp`) does, so the eyes are
  copied into the swapchain on Dawn's queue with no sharing at all. That backend is also the core
  of a native SteamOS build ([above](#the-native-steamos-build)).
- **Finding the runtime.** An app inside Lepton reaches SteamVR's OpenXR runtime through the system
  runtime file, not a broker. The Khronos loader the game links statically (`DYNAMIC_LOADER OFF`)
  tries the runtime brokers first, then reads `/{product,odm,oem,vendor,system}/etc/openxr/1/active_runtime.json`,
  so no app change is needed; the manifest's broker queries are simply unused here. Walkabout Mini
  Golf, an Android VR game, runs in the same Lepton.
- **Valve's foveation layer.** `XrApiLayer_VALVE_fdm_injection` is implicit, so it wraps every
  Android OpenXR app. By its name it adds fragment density maps to apps' own render passes. This
  game draws its eyes on Dawn's device and only copies them into the swapchain on the OpenXR
  device, so the layer has no render pass of the game's to change; the game's own maps
  (eye-tracked foveation, above) do that. If the layer gets in the way,
  `DISABLE_VULKAN_FDM_INJECTION_LAYER` turns it off (its manifest loads
  `libVkLayer_VALVE_fdm_injection.so`; the runtime itself is
  `/data/steamvr/runtime/bin/androidarm64/vrclient.so`).

### SteamVR's Android OpenXR extensions

Walkabout Mini Golf, a Unity game in the same Lepton, logs what the runtime offers (`adb logcat -d |
grep -F '[XR]'`). Its extensions:

```
XR_EXT_active_action_set_priority XR_EXT_debug_utils XR_EXT_dpad_binding XR_EXT_eye_gaze_interaction
XR_EXT_frame_composition_report XR_EXT_frame_synthesis XR_EXT_hand_interaction XR_EXT_hand_joints_motion_range
XR_EXT_hand_tracking XR_EXT_hand_tracking_data_source XR_EXT_hp_mixed_reality_controller
XR_EXT_interaction_profile_battery_state_display XR_EXT_interaction_render_model XR_EXT_local_floor
XR_EXT_palm_pose XR_EXT_performance_settings XR_EXT_render_model XR_EXT_user_presence XR_EXT_uuid
XR_EXT_view_configuration_views_change XR_FB_display_refresh_rate XR_FB_foveation
XR_FB_foveation_configuration XR_FB_foveation_vulkan XR_FB_space_warp XR_FB_swapchain_update_state
XR_HTC_vive_cosmos_controller_interaction XR_HTC_vive_focus3_controller_interaction
XR_HTC_vive_wrist_tracker_interaction XR_HTCX_vive_tracker_interaction XR_KHR_android_create_instance
XR_KHR_binding_modification XR_KHR_composition_layer_depth XR_KHR_generic_controller XR_KHR_locate_spaces
XR_KHR_opengl_enable XR_KHR_opengl_es_enable XR_KHR_visibility_mask XR_KHR_vulkan_enable
XR_KHR_vulkan_enable2 XR_META_foveation_eye_tracked XR_META_performance_metrics
XR_META_recommended_layer_resolution XR_META_vulkan_swapchain_create_info XR_MND_headless
XR_MNDX_egl_enable XR_VALVE_analog_threshold XR_VALVE_app_space_delta_pose
XR_VALVE_frame_controller_interaction XR_VALVE_timing_utils
```

Environment blend modes `OPAQUE` and `ALPHA_BLEND`; reference spaces `LOCAL`, `STAGE` and `VIEW`.
What this build asks for and gets:

| Extension | Offered | What it means here |
| --- | --- | --- |
| `XR_KHR_android_create_instance`, `XR_KHR_vulkan_enable2` | yes | The Android backend's instance and Vulkan binding |
| `XR_VALVE_frame_controller_interaction` | yes | The Frame controller profile and its D-pad |
| `XR_FB_display_refresh_rate` | yes | `[vr] refresh_rate` (120 Hz) can be requested |
| `XR_EXT_eye_gaze_interaction` | yes | Eye-tracked foveation |
| `XR_EXT_performance_settings` | yes | `performance_level` |
| `XR_EXT_hand_tracking`, `XR_EXT_hand_tracking_data_source` | yes | Tracked hands; `XR_FB_hand_tracking_mesh` and `_aim` are not offered, so the cockpit draws its procedural gloves and bare hands get no pinch gestures |
| `XR_KHR_convert_timespec_time` | **no** | VR frame interpolation is unavailable, and controller motion is sampled at the frame's display time rather than the current time |
| `XR_KHR_android_thread_settings` | no | Thread hints are skipped (logged as refused) |
| `XR_FB_passthrough` | no | As expected; the build does not ask for it |

Later candidates the runtime offers: `ALPHA_BLEND` could bring back the room around the menu screen
without `XR_FB_passthrough`, `XR_KHR_visibility_mask` would skip the pixels the lenses never show,
and `XR_FB_foveation` with `XR_META_foveation_eye_tracked` only shapes render passes into the
runtime's swapchain images, which this game's eyes reach by copy, so it does not apply.

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
