#!/usr/bin/env bash
# Collects what a Steam Frame problem report needs into one .tar.gz on this machine: the game's run
# logs and crash files, Config.toml, the install, SteamVR's logs and OpenXR runtime, the GPU and
# Vulkan driver, and the system's state (SteamOS version, memory, thermals, kernel log, core dumps).
# It only reads on the Frame, apart from a temporary folder it removes again.
#
#   Launcher/frame-diagnostics.sh --frame HOST [options]
#
# Or without downloading anything first:
#
#   curl -fsSL https://raw.githubusercontent.com/mitch030504/Wiicompiled_VR_Frame/openxr-work/Launcher/frame-diagnostics.sh \
#       | bash -s -- --frame steamos@<frame-ip>
#
# Options:
#   --frame HOST      the Frame: an SSH destination (steamos@<frame-ip>, or an ~/.ssh/config host such
#                     as Frame Control's "frame"), or "local" when running on the Frame (default frame)
#   --runs N          how many of the newest run folders to take (default 3; 0 takes them all)
#   --game-dir DIR    where the game is installed, relative to the Frame's home or absolute
#                     (default devkit-game/WiiCompiled)
#   --output DIR      where the bundle goes (default: the current folder)
#   --with-memory     also take the guest memory snapshot (mem1.bin) a crash writes
#   --with-core       also take the newest WiiCompiled core dump, when systemd-coredump kept one (large)
#   -h, --help
#
# The bundle holds summary.txt first: the version, which startup steps the newest run reached, its
# crash files, the end of its log and its last frame-pacing lines. The disc is never copied.
set -euo pipefail

# Everything is in main, so bash has read the whole script before running any of it: when it comes
# through curl | bash, a step that reads stdin cannot eat the rest. (Not indented, for the heredocs.)
main() {
say() { printf '\n\033[1m==> %s\033[0m\n' "$*"; }
note() { printf '    %s\n' "$*"; }
fail() {
    printf '\nframe-diagnostics.sh: error: %s\n' "$*" >&2
    exit 1
}
usage() { awk 'NR == 1 { next } /^#/ { sub(/^# ?/, ""); print; next } { exit }' "$script_path"; }

script_path=${BASH_SOURCE[0]:-}

frame=frame
runs=3
game_dir=devkit-game/WiiCompiled
output_dir=.
with_memory=no
with_core=no

while [[ $# -gt 0 ]]; do
    case "$1" in
        --frame) frame=$2; shift 2 ;;
        --runs) runs=$2; shift 2 ;;
        --game-dir) game_dir=$2; shift 2 ;;
        --output) output_dir=$2; shift 2 ;;
        --with-memory) with_memory=yes; shift ;;
        --with-core) with_core=yes; shift ;;
        -h|--help)
            if [[ -n "$script_path" && -f "$script_path" ]]; then usage; else echo "See the comment at the top of the script."; fi
            exit 0 ;;
        *) fail "unknown argument: $1 (see --help)" ;;
    esac
done
[[ "$runs" =~ ^[0-9]+$ ]] || fail "--runs must be a number"
# The game folder reaches the Frame as one word of an SSH command line.
[[ "$game_dir" =~ ^[A-Za-z0-9._/~-]+$ ]] || fail "--game-dir may only hold letters, digits and . _ / ~ -"
mkdir -p "$output_dir"
output_dir=$(cd "$output_dir" && pwd)

stamp=$(date +%Y%m%d-%H%M%S)
bundle="$output_dir/frame-diagnostics-$stamp.tar.gz"
partial="$bundle.partial"
trap 'rm -f "$partial"' EXIT

if [[ "$frame" == local ]]; then
    say "Collecting on this machine"
    on_frame() { bash -s -- "$@"; }
else
    say "Collecting from $frame over SSH"
    on_frame() { ssh "$frame" bash -s -- "$@"; }
fi

# The collector runs on the Frame and writes the bundle to stdout; its progress goes to stderr.
if ! on_frame "$runs" "$game_dir" "$with_memory" "$with_core" "$stamp" <<<"$collector" >"$partial"; then
    fail "collecting stopped; the output above says why. If SSH could not connect, turn on Developer
    Mode and set a user password on the Frame (Steam Settings > System), then check the address."
fi
gzip -t "$partial" 2>/dev/null || fail "the Frame sent back something that is not a bundle; the output above says why"
mv "$partial" "$bundle"

say "Done"
note "$bundle ($(du -h "$bundle" | cut -f1))"
summary=$(tar -xzOf "$bundle" "frame-diagnostics-$stamp/summary.txt" 2>/dev/null || true)
if [[ -n "$summary" ]]; then
    # The crash files' heads stay in the bundle; the rest is printed.
    printf '\n%s\n' "$summary" | awk '/^--- crash_/ { exit } { print "    " $0 }'
fi
note ""
note "Logs can hold your user name and paths; look through the bundle before posting it publicly."
}

# ---------------------------------------------------------------------------------------------
# Runs on the Frame: bash -s -- RUNS GAME_DIR WITH_MEMORY WITH_CORE STAMP
read -r -d '' collector <<'COLLECTOR' || true
set -uo pipefail
runs=$1 game_dir=$2 with_memory=$3 with_core=$4 stamp=$5
log() { printf '    %s\n' "$*" >&2; }
[[ "$game_dir" == /* ]] || game_dir="$HOME/${game_dir#\~/}"

tmp=$(mktemp -d "${TMPDIR:-/tmp}/frame-diagnostics.XXXXXX") || exit 1
trap 'rm -rf "$tmp"' EXIT
root="$tmp/frame-diagnostics-$stamp"
mkdir -p "$root"/{system,gpu,game,steamvr}

# run FILE COMMAND...: the command's output in FILE under a header naming it; a missing tool or a
# hung one is noted rather than stopping the collection.
run() {
    local file=$root/$1; shift
    {
        printf '$ %s\n' "$*"
        if ! command -v "$1" >/dev/null 2>&1; then
            echo "(not installed)"
        else
            timeout 30 "$@" 2>&1
            local status=$?
            (( status == 0 )) || echo "(exit status $status)"
        fi
        echo
    } >>"$file"
}
# grab SOURCE DEST: a copy of a file or folder, if it exists.
grab() {
    [[ -e "$1" ]] || return 0
    mkdir -p "$(dirname "$2")"
    cp -R "$1" "$2" 2>/dev/null || log "could not copy $1"
}
# grab_tail SOURCE DEST: the last 4 MB of a log that can grow without bound.
grab_tail() {
    [[ -f "$1" ]] || return 0
    mkdir -p "$(dirname "$2")"
    tail -c 4194304 "$1" >"$2" 2>/dev/null || log "could not copy $1"
}

# --- System -------------------------------------------------------------------------------------
log "system"
run system/os.txt cat /etc/os-release
run system/os.txt uname -a
run system/os.txt uptime
run system/os.txt date --iso-8601=seconds
run system/hardware.txt lscpu
run system/hardware.txt free -m
run system/hardware.txt cat /proc/meminfo
run system/hardware.txt cat /proc/pressure/memory
run system/storage.txt df -h "$HOME" /tmp /run/media
run system/storage.txt lsblk -o NAME,SIZE,FSTYPE,MOUNTPOINTS,LABEL
run system/storage.txt findmnt -t ext4,btrfs,exfat,vfat,f2fs
{
    echo "zone type temp(milli-C)"
    for zone in /sys/class/thermal/thermal_zone*; do
        [[ -r "$zone/temp" ]] && echo "${zone##*/} $(cat "$zone/type" 2>/dev/null) $(cat "$zone/temp" 2>/dev/null)"
    done
    echo
    echo "cpu cur/min/max(kHz) governor"
    for cpu in /sys/devices/system/cpu/cpu[0-9]*/cpufreq; do
        [[ -r "$cpu/scaling_cur_freq" ]] || continue
        echo "$(basename "$(dirname "$cpu")") $(cat "$cpu/scaling_cur_freq")/$(cat "$cpu/scaling_min_freq")/$(cat "$cpu/scaling_max_freq") $(cat "$cpu/scaling_governor" 2>/dev/null)"
    done
    echo
    for supply in /sys/class/power_supply/*; do
        [[ -r "$supply/uevent" ]] && { echo "${supply##*/}:"; sed 's/^/  /' "$supply/uevent"; }
    done
} >"$root/system/thermal-power.txt" 2>&1
run system/sensors.txt sensors
run system/processes.txt ps -eo pid,ppid,etime,pcpu,pmem,rss,args --sort=-pcpu
# The kernel log holds GPU hangs and out-of-memory kills; the previous boot's covers a crash that
# took the headset down with it.
run system/kernel-this-boot.txt journalctl -k -b 0 --no-pager -n 5000
run system/kernel-previous-boot.txt journalctl -k -b -1 --no-pager -n 5000
run system/kernel-dmesg.txt dmesg
run system/user-journal.txt journalctl --user -b 0 --no-pager -n 3000
run system/coredumps.txt coredumpctl list --no-pager --since=-7d
run system/coredumps.txt coredumpctl info --no-pager WiiCompiled

# --- GPU and Vulkan -----------------------------------------------------------------------------
log "GPU and Vulkan"
run gpu/vulkaninfo-summary.txt vulkaninfo --summary
run gpu/vulkaninfo.txt vulkaninfo
run gpu/eglinfo.txt eglinfo -B
{
    for card in /sys/class/drm/card*; do
        [[ -e "$card/device/uevent" && "$card" != *-* ]] || continue
        echo "${card##*/}:"; sed 's/^/  /' "$card/device/uevent"
        for f in "$card"/device/devfreq/*/{cur_freq,max_freq,governor}; do
            [[ -r "$f" ]] && echo "  ${f#"$card"/device/}: $(cat "$f")"
        done
    done
    for f in /sys/kernel/debug/dri/*/name; do [[ -r "$f" ]] && cat "$f"; done
} >"$root/gpu/drm.txt" 2>&1
for dir in /usr/share/vulkan/{icd.d,implicit_layer.d,explicit_layer.d} /etc/vulkan/{icd.d,implicit_layer.d} \
    "$HOME/.local/share/vulkan/implicit_layer.d"; do
    [[ -d "$dir" ]] && { echo "== $dir"; ls -l "$dir"; }
done >"$root/gpu/vulkan-manifests.txt" 2>&1

# --- The game -----------------------------------------------------------------------------------
log "the game in $game_dir"
# Where the game keeps Config.toml and Logs: UserData beside a portable.txt at or above the
# executable (four levels up at most), otherwise $XDG_DATA_HOME/WiiCompiled.
data_dir=${XDG_DATA_HOME:-$HOME/.local/share}/WiiCompiled
search=$game_dir
for _ in 0 1 2 3 4; do
    if [[ -f "$search/portable.txt" ]]; then data_dir=$search/UserData; break; fi
    [[ "$search" == / ]] && break
    search=$(dirname "$search")
done
{
    echo "game dir: $game_dir"
    echo "data dir: $data_dir"
    echo
    ls -la "$game_dir" 2>&1
    echo
    if [[ -f "$game_dir/WiiCompiled" ]]; then
        file "$game_dir/WiiCompiled" 2>&1
        sha256sum "$game_dir/WiiCompiled" 2>&1
        stat -c 'modified %y' "$game_dir/WiiCompiled" 2>&1
        echo
        echo "libraries it loads:"
        ldd "$game_dir/WiiCompiled" 2>&1
    else
        echo "(no WiiCompiled executable here)"
    fi
    echo
    ls -la "$data_dir" 2>&1
} >"$root/game/install.txt"
grab "$game_dir/build-fingerprint.json" "$root/game/build-fingerprint.json"
grab "$data_dir/Config.toml" "$root/game/Config.toml"
grab "$data_dir/gamecontrollerdb.txt" "$root/game/gamecontrollerdb.txt"
grab_tail "$data_dir/wii_accel_trace.csv" "$root/game/wii_accel_trace.csv"
grab_tail "$HOME/wiicompiled-frame/build.log" "$root/game/build.log"

# The disc the config points at: is it there, whole, and the right release? Never copied.
dvd_root=$(sed -n 's/^[[:space:]]*dvd_root[[:space:]]*=[[:space:]]*"\(.*\)".*/\1/p' "$data_dir/Config.toml" 2>/dev/null | head -n 1)
{
    echo "dvd_root: ${dvd_root:-(not set in Config.toml)}"
    if [[ -n "$dvd_root" ]]; then
        if [[ -d "$dvd_root" ]]; then
            for f in sys/boot.bin sys/main.dol files/rel/StaticR.rel; do
                [[ -f "$dvd_root/$f" ]] && echo "$f: present" || echo "$f: MISSING"
            done
            [[ -f "$dvd_root/sys/boot.bin" ]] && echo "game ID: $(head -c 6 "$dvd_root/sys/boot.bin" | tr -dc 'A-Z0-9') (RMCP01 expected)"
            echo "size: $(du -sh "$dvd_root" 2>/dev/null | cut -f1)"
            findmnt -T "$dvd_root" 2>&1
        else
            echo "MISSING: the folder does not exist (an SD card that is not mounted?)"
        fi
    fi
} >"$root/game/disc.txt"

# The newest run folders (Logs/<product>_<epochSeconds>_pid<pid>/), console.log and crash files.
logs_dir=$data_dir/Logs
mapfile -t run_dirs < <(ls -1dt "$logs_dir"/*/ 2>/dev/null | sed 's:/$::')
(( runs > 0 && ${#run_dirs[@]} > runs )) && run_dirs=("${run_dirs[@]:0:runs}")
log "${#run_dirs[@]} run folder(s) from $logs_dir"
ls -lt "$logs_dir" >"$root/game/all-runs.txt" 2>&1
for dir in "${run_dirs[@]}"; do
    dest=$root/game/Logs/${dir##*/}
    mkdir -p "$dest"
    for f in "$dir"/*; do
        [[ -f "$f" ]] || continue
        [[ "${f##*/}" == mem1.bin && "$with_memory" != yes ]] && continue
        cp "$f" "$dest/" 2>/dev/null || log "could not copy $f"
    done
done

if [[ "$with_core" == yes ]] && command -v coredumpctl >/dev/null 2>&1; then
    log "the newest core dump"
    timeout 120 coredumpctl dump --no-pager -o "$root/system/WiiCompiled.core" WiiCompiled >/dev/null 2>&1 ||
        log "no core dump was available"
fi

# --- SteamVR and OpenXR -------------------------------------------------------------------------
log "SteamVR and OpenXR"
steam_dir=""
for candidate in "$HOME/.local/share/Steam" "$HOME/.steam/steam" "$HOME/.steam/root"; do
    [[ -d "$candidate/logs" ]] && { steam_dir=$(readlink -f "$candidate"); break; }
done
if [[ -n "$steam_dir" ]]; then
    for f in "$steam_dir"/logs/vr*.txt "$steam_dir"/logs/compat_log.txt "$steam_dir"/logs/console_log.txt \
        "$steam_dir"/logs/content_log.txt; do
        [[ -f "$f" ]] && grab_tail "$f" "$root/steamvr/logs/${f##*/}"
    done
    grab "$steam_dir/config/steamvr.vrsettings" "$root/steamvr/steamvr.vrsettings"
    ls -la "$steam_dir/logs" >"$root/steamvr/logs-listing.txt" 2>&1
else
    echo "no Steam folder with logs found" >"$root/steamvr/logs-listing.txt"
fi
for f in "${XDG_CONFIG_HOME:-$HOME/.config}/openxr/1/active_runtime.json" /etc/xdg/openxr/1/active_runtime.json \
    /usr/share/openxr/1/active_runtime.json; do
    [[ -f "$f" ]] && { echo "== $f"; cat "$f"; echo; }
done >"$root/steamvr/openxr-runtime.txt" 2>&1
pgrep -a 'vrserver|vrcompositor|vrmonitor|WiiCompiled' >"$root/steamvr/vr-processes.txt" 2>&1 ||
    echo "none running" >>"$root/steamvr/vr-processes.txt"

# --- Summary ------------------------------------------------------------------------------------
newest=${run_dirs[0]:-}
{
    echo "WiiCompiled VR diagnostics, $(date --iso-8601=seconds)"
    echo "SteamOS: $(. /etc/os-release 2>/dev/null; echo "${PRETTY_NAME:-unknown} ${VERSION_ID:-} build ${BUILD_ID:-?}")"
    echo "kernel: $(uname -r)  uptime: $(uptime -p 2>/dev/null)"
    echo "memory: $(free -m 2>/dev/null | awk '/^Mem:/ { print $7 " MB available of " $2 " MB" }')"
    vk=$root/gpu/vulkaninfo-summary.txt
    gpu=$(sed -n 's/^[[:space:]]*deviceName[[:space:]]*=[[:space:]]*//p' "$vk" | head -n 1)
    driver=$(sed -n 's/^[[:space:]]*driverInfo[[:space:]]*=[[:space:]]*//p' "$vk" | head -n 1)
    echo "GPU: ${gpu:-unknown (no vulkaninfo; see gpu/)}${driver:+, driver $driver}"
    echo "game: $([[ -x "$game_dir/WiiCompiled" ]] && echo "installed in $game_dir" || echo "NOT FOUND in $game_dir")"
    echo "disc: $(head -n 1 "$root/game/disc.txt" | sed 's/^dvd_root: //')$(grep -q MISSING "$root/game/disc.txt" && echo '  (PROBLEM: see game/disc.txt)')"
    echo "SteamVR running: $(pgrep -x vrserver >/dev/null 2>&1 && echo yes || echo no)"
    echo "game running: $(pgrep -x WiiCompiled >/dev/null 2>&1 && echo "yes (the newest run's log is still being written)" || echo no)"
    echo
    if [[ -z "$newest" ]]; then
        echo "No run folders in $logs_dir: the game has not started on this Frame (or logs elsewhere)."
    else
        console=$newest/console.log
        echo "newest run: ${newest##*/} ($(stat -c %y "$newest" 2>/dev/null | cut -d. -f1))"
        version=$(head -n 1 "$console" 2>/dev/null | sed 's/^\[runtime\] //')
        # Builds without a build-fingerprint.json beside the executable log no version; its date
        # still tells builds apart.
        [[ "$version" == *"version unknown"* && -f "$game_dir/WiiCompiled" ]] &&
            version="$version (executable built $(stat -c %y "$game_dir/WiiCompiled" | cut -d. -f1))"
        echo "version: $version"
        echo
        echo "startup steps (README, Troubleshooting); the first one missing is where it stopped:"
        while IFS='|' read -r label pattern; do
            if grep -qF -- "$pattern" "$console" 2>/dev/null; then mark="ok     "; else mark="MISSING"; fi
            echo "  $mark $label"
        done <<'STEPS'
OpenXR initialized|OpenXR initialized: runtime
Dawn creates its device through the runtime|Dawn will create its device through the runtime
Fragment density maps enabled|Fragment density maps: enabled
Vulkan swapchains ready|OpenXR Vulkan swapchains ready
Refresh rate requested|display refresh rate
Session focused|OpenXR session state -> FOCUSED
Controller profile bound|OpenXR interaction profiles:
Eye gaze available|OpenXR eye gaze: available
Eye gaze tracking|OpenXR eye gaze: tracking
STEPS
        grep -qF "requires a Dawn built with Aurora's patches" "$console" 2>/dev/null &&
            echo "  NOTE: built without --dawn-package (Dawn lacks Aurora's patches)"
        echo
        crashes=$(cd "$newest" && ls crash_*.txt 2>/dev/null | tr '\n' ' ')
        echo "crash files: ${crashes:-none}"
        echo "lines mentioning error, fail, fatal or warn in console.log: $(grep -ciE 'error|fail|fatal|warn' "$console" 2>/dev/null)"
        echo
        echo "--- last 40 lines of console.log ---"
        tail -n 40 "$console" 2>/dev/null
        echo "--- end of console.log ---"
        echo
        echo "--- last frame-pacing lines ([diagnostics] openxr_logging = true) ---"
        pacing=$(grep -h 'xr-diag\] 1.0' "$console" 2>/dev/null | tail -n 5)
        echo "${pacing:-(none: this run had openxr_logging off)}"
        for f in "$newest"/crash_*.txt; do
            [[ -f "$f" ]] || continue
            echo
            echo "--- ${f##*/} (first 60 lines) ---"
            head -n 60 "$f"
        done
    fi
} >"$root/summary.txt" 2>&1

log "packing"
tar -C "$tmp" -czf - "frame-diagnostics-$stamp"
COLLECTOR

main "$@" </dev/null
