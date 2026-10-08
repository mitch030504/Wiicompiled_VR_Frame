#!/usr/bin/env bash
# Builds WiiCompiled VR for the Steam Frame from a release and your own disc, and installs it on the
# Frame. Run it again with --update to update: it fetches the newest release and rebuilds only what
# changed, with the options it was installed with.
#
#   Launcher/steam-frame-install.sh --disc PATH [--frame HOST] [options]
#   Launcher/steam-frame-install.sh --update
#
# Or without downloading anything first:
#
#   curl -fsSL https://raw.githubusercontent.com/mitch030504/Wiicompiled_VR_Frame/openxr-work/Launcher/steam-frame-install.sh \
#       | bash -s -- --disc "/path/to/Mario Kart Wii.wbfs" --frame steamos@<frame-ip>
#
# It runs on an x86_64 or ARM64 Linux PC with podman (or docker), or on the Frame itself. The game
# is built in a Debian ARM64 container, under qemu emulation on x86_64; the first build takes a few
# hours there, mostly compiling Dawn, and later ones reuse it.
#
# Options:
#   --disc PATH       your clean PAL RMCP01 disc: an ISO, WBFS or RVZ image (or WIA, CISO, GCZ, NFS,
#                     TGC), a .zip or .7z holding one, or an extracted disc folder holding sys/ and
#                     files/. Needed for the first build only.
#   --frame HOST      where to install: an SSH destination (steamos@<frame-ip>, or an ~/.ssh/config
#                     host such as Frame Control's "frame"), or "local" when running on the Frame.
#                     Without it the game is only built.
#   --work-dir DIR    where the toolchain, Dawn, the build and the extracted disc live
#                     (default ~/wiicompiled-frame; about 20 GB)
#   --release TAG     the release to build (default: the newest one). Ignored with --source.
#   --source DIR      build this source tree instead of a release (default when the script runs
#                     from inside one)
#   --jobs N          parallel compiles (default: a quarter of the memory in GB; under emulation each
#                     compile needs a lot of it)
#   --frame-disc DIR  where the extracted disc goes on the Frame: absolute, or relative to the
#                     Frame's home (default wiicompiled/disc; with --frame local, the disc folder
#                     the build used)
#   --retro-rewind    also build Retro Rewind and install it beside the base game. Its pack (about
#                     4 GB) comes from Retro Rewind's own update server, as Wheel Wizard and the
#                     Quest app fetch it, and later runs apply only the updates published since.
#   --retro-rewind-pack DIR
#                     use this RetroRewind6 folder instead of downloading one (implies
#                     --retro-rewind); it is copied into the work dir and never changed
#   --update          update an earlier install: its options are reused (any given here win), and
#                     nothing is built when the Frame already has the newest release and Retro
#                     Rewind pack. Follows releases unless it was installed with --source.
#   --check           only say whether an update is available; nothing is changed
#   -h, --help
#
# Installed with --frame local, the game can update itself: Settings > Updates in the game checks
# for a new release, and its Update button runs this script with --update in the background,
# through a systemd user service this script sets up. The tab shows the update's progress while the
# game stays open, and a game closed meanwhile is opened again when the update is done.
set -euo pipefail

# Everything is in main, so bash has read the whole script before running any of it: when it comes
# through curl | bash, a step that reads stdin cannot eat the rest. (Not indented, for the heredocs.)
main() {
# What the error path below reads, set before anything can fail into it.
mode=install
steam_game_id=""
trap 'on_error "$LINENO"' ERR

repo=mitch030504/Wiicompiled_VR_Frame
game_id=WiiCompiled
image=docker.io/library/debian:trixie
container=wiicompiled-frame-build
nodtool_version=v2.0.0-alpha.10
# Where the game keeps its settings, and where an update it starts reports back to it. Resolved as
# the game resolves it (RuntimeConfigFile::ApplicationDataDirectory).
game_data="${XDG_DATA_HOME:-$HOME/.local/share}/$game_id"

say() {
    printf '\n\033[1m==> %s\033[0m\n' "$*"
    status running "$*"
}
note() { printf '    %s\n' "$*"; }
fail() {
    printf '\nsteam-frame-install.sh: error: %s\n' "$*" >&2
    finish_failed "${1%%$'\n'*}"
}
on_error() {
    printf '\nsteam-frame-install.sh: stopped by a failed step (line %s); the output above says why.\n' "$1" >&2
    finish_failed "a step failed (line $1)"
}
finish_failed() {
    trap - ERR
    status failed "$1"
    relaunch
    exit 1
}
usage() { awk 'NR == 1 { next } /^#/ { sub(/^# ?/, ""); print; next } { exit }' "$script_path"; }

# The game's Updates tab reads this: "<state>\t<unix time>\t<text>", state running, available,
# uptodate, done or failed. Written only when the game asked for this run
# (WIICOMPILED_UPDATE_STATUS names the file).
status() {
    local file=${WIICOMPILED_UPDATE_STATUS:-}
    [[ -n "$file" ]] || return 0
    { printf '%s\t%s\t%s\n' "$1" "$(date +%s)" "$2" > "$file.new" && mv -f "$file.new" "$file"; } 2>/dev/null || true
}

# Progress goes to that file rather than to Steam notifications: on the Frame, SteamOS's
# steam_notif_daemon accepts a notify-send and Steam then shows nothing, even when given the
# notification directly with steam -ifrunning (tried on a Frame, 2026-10).
# An update the game started ends by opening the game again if it was closed meanwhile, which is
# how its result gets seen; a game still open shows the result in its Updates tab.
game_running() { pgrep -f "devkit-game/($game_id|RetroRewind)/" >/dev/null 2>&1; }
relaunch() {
    if [[ -n "${install_lock:-}" ]]; then
        flock -u "$install_lock"
        exec {install_lock}>&-
        unset install_lock
    fi
    [[ -n "$steam_game_id" ]] || return 0
    command -v steam >/dev/null 2>&1 || return 0
    if game_running; then return 0; fi
    note "opening $game_id again"
    timeout 60 steam "steam://rungameid/$steam_game_id" >/dev/null 2>&1 || true
}

script_path=${BASH_SOURCE[0]:-}
script_dir=""
if [[ -n "$script_path" && -f "$script_path" ]]; then
    script_dir=$(cd "$(dirname "$script_path")" && pwd)
    script_path="$script_dir/$(basename "$script_path")"
fi

disc=""
frame=""
work_dir="$HOME/wiicompiled-frame"
release=""
source_dir=""
jobs=""
frame_disc=""
retro_rewind=0
retro_pack=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --disc) disc=$2; shift 2 ;;
        --frame) frame=$2; shift 2 ;;
        --work-dir) work_dir=$2; shift 2 ;;
        --release) release=$2; shift 2 ;;
        --source) source_dir=$2; shift 2 ;;
        --jobs) jobs=$2; shift 2 ;;
        --frame-disc) frame_disc=$2; shift 2 ;;
        --retro-rewind) retro_rewind=1; shift ;;
        --retro-rewind-pack) retro_rewind=1; retro_pack=$2; shift 2 ;;
        --update) mode=update; shift ;;
        --check) mode=check; shift ;;
        -h|--help)
            if [[ -n "$script_dir" ]]; then usage; else echo "See the comment at the top of the script."; fi
            exit 0 ;;
        *) fail "unknown argument: $1 (see --help)" ;;
    esac
done
# What --update reuses: the options given, before defaults fill the rest in.
jobs_given=$jobs
source_given=$source_dir

mkdir -p "$work_dir"
work_dir=$(cd "$work_dir" && pwd)

command -v flock >/dev/null || fail "flock is required (install util-linux)."
exec {install_lock}>"$work_dir/.install.lock"
flock -n "$install_lock" || fail "Another install or update is using $work_dir. Wait for it to finish."
command -v python3 >/dev/null || fail "Python 3 is required for installation."

# The game's Update button leaves a request file; the service that runs this script moves it here.
if [[ -n "${WIICOMPILED_UPDATE_REQUEST:-}" && -f "$WIICOMPILED_UPDATE_REQUEST" ]]; then
    steam_game_id=$(sed -n 's/^steam_game_id=\([0-9]*\)$/\1/p' "$WIICOMPILED_UPDATE_REQUEST" | head -n 1)
    rm -f "$WIICOMPILED_UPDATE_REQUEST"
fi

if [[ "$mode" != install && -f "$work_dir/install.conf" ]]; then
    while IFS='=' read -r key value; do
        case "$key" in
            frame) [[ -n "$frame" ]] || frame=$value ;;
            frame_disc) [[ -n "$frame_disc" ]] || frame_disc=$value ;;
            jobs) [[ -n "$jobs" ]] || jobs=$value ;;
            source) [[ -n "$source_dir" ]] || source_dir=$value ;;
            retro_rewind) if [[ "$value" == 1 ]]; then retro_rewind=1; fi ;;
            retro_rewind_pack) [[ -n "$retro_pack" ]] || retro_pack=$value ;;
        esac
    done < "$work_dir/install.conf"
    jobs_given=$jobs
    source_given=$source_dir
fi
frame_files() {
    python3 - "$@" <<'FRAME_FILES_PY'
import filecmp
import json
import os
from pathlib import Path
import re
import shutil
import sys
import tempfile


def atomic_write(path, text):
    path.parent.mkdir(parents=True, exist_ok=True)
    descriptor, temporary = tempfile.mkstemp(prefix=path.name + '.', dir=path.parent)
    try:
        with os.fdopen(descriptor, 'w', encoding='utf-8') as output:
            output.write(text)
            output.flush()
            os.fsync(output.fileno())
        os.replace(temporary, path)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)


def set_path(key, value):
    if key not in ('dvd_root', 'retro_rewind_root'):
        raise ValueError('Unknown runtime path key')
    config = Path.home() / '.local/share/WiiCompiled/Config.toml'
    value = os.path.expanduser(value)
    if not os.path.isabs(value):
        value = str(Path.home() / value)
    lines = config.read_text(encoding='utf-8').splitlines(keepends=True) if config.exists() else []
    # JSON strings use the escaping needed by TOML basic strings for filesystem paths.
    setting = key + ' = ' + json.dumps(value, ensure_ascii=False) + '\n'
    start = next((i for i, line in enumerate(lines) if re.fullmatch(r"\s*\[\s*[\"']?paths[\"']?\s*\]\s*(?:#.*)?", line.strip())), None)
    if start is None:
        lines += ['\n[paths]\n', setting]
    else:
        end = next((i for i in range(start + 1, len(lines)) if lines[i].lstrip().startswith('[')), len(lines))
        matches = [i for i in range(start + 1, end) if re.match(r"\s*[\"']?" + key + r"[\"']?\s*=", lines[i])]
        for i in reversed(matches):
            del lines[i]
        lines.insert(start + 1, setting)
    atomic_write(config, ''.join(line if line.endswith('\n') else line + '\n' for line in lines))


def sync_source(source, destination):
    source, destination = Path(source), Path(destination)
    manifest = destination / '.release-files'
    old = manifest.read_text(encoding='utf-8').splitlines() if manifest.exists() else []
    current = sorted(str(path.relative_to(source)) for path in source.rglob('*') if path.is_file() or path.is_symlink())
    current_set = set(current)
    for name in old:
        relative = Path(name)
        if relative.is_absolute() or '..' in relative.parts or not relative.parts:
            raise ValueError('Invalid release-owned path: ' + name)
        if name not in current_set:
            target = destination / relative
            if target.is_symlink() or target.is_file():
                target.unlink()
    for name in current:
        incoming, target = source / name, destination / name
        target.parent.mkdir(parents=True, exist_ok=True)
        if incoming.is_symlink():
            if target.is_symlink() and os.readlink(target) == os.readlink(incoming):
                continue
            if target.exists() or target.is_symlink():
                target.unlink()
            target.symlink_to(os.readlink(incoming))
        elif target.is_symlink() or not target.is_file() or not filecmp.cmp(incoming, target, shallow=False):
            if target.is_symlink():
                target.unlink()
            shutil.copyfile(incoming, target)
            shutil.copymode(incoming, target)
        else:
            shutil.copymode(incoming, target)
    atomic_write(manifest, '\n'.join(current) + '\n')


if __name__ == '__main__':
    if sys.argv[1] == 'config':
        set_path(*sys.argv[2:])
    elif sys.argv[1] == 'sync':
        sync_source(*sys.argv[2:])
    else:
        raise ValueError('Unknown file operation')
FRAME_FILES_PY
}

save_settings() {
    cat > "$work_dir/install.conf" <<EOF
# Written by steam-frame-install.sh after each install: the options --update reuses.
frame=$frame
frame_disc=$frame_disc
jobs=$jobs_given
source=$source_given
retro_rewind=$retro_rewind
retro_rewind_pack=$retro_pack
EOF
}

# ---------------------------------------------------------------------------------------------
# Talking to the Frame, and the versions involved. Up here because --update and --check read them
# before anything is built.
# One SSH connection for every step, so a password is asked for once.
ssh_opts=(-o ControlMaster=auto -o "ControlPath=${XDG_RUNTIME_DIR:-/tmp}/wiicompiled-ssh-%C" -o ControlPersist=600)
on_frame() {
    # Runs a bash script, given on stdin, on the Frame; its arguments follow.
    if [[ "$frame" == local ]]; then
        bash -s -- "$@"
    else
        local arguments
        printf -v arguments ' %q' "$@"
        ssh "${ssh_opts[@]}" "$frame" "bash -s --$arguments"
    fi
}
read_on_frame() {
    # Prints the contents of $1 on the Frame, with its whitespace removed, or nothing.
    on_frame "$1" <<'EOF'
[[ "$1" = /* ]] && f=$1 || f="$HOME/$1"
tr -d '[:space:]' 2>/dev/null < "$f" || true
EOF
}
frame_game_dir="devkit-game/$game_id"

newest_release() {
    curl -fsSL "https://api.github.com/repos/$repo/releases?per_page=1" |
        sed -n 's/.*"tag_name": *"\([^"]*\)".*/\1/p' | head -n 1
}

# Retro Rewind's own versioning, as its update server publishes it.
rr_server=https://update.rwfc.net/RetroRewind/
rr_version_ok() { [[ "$1" =~ ^[0-9]+(\.[0-9]+)+$ ]]; }
rr_newer() {
    # True when version $1 is newer than $2 (dotted numbers, as 6.12.7).
    [[ "$1" != "$2" && "$(printf '%s\n%s\n' "$1" "$2" | sort -V | tail -n 1)" == "$1" ]]
}
rr_fetch() { curl -fsSL --retry 2 "$1"; }
rr_published_version() {
    rr_fetch "${rr_server}RetroRewindVersion.txt" |
        awk 'NF >= 4 && $1 ~ /^[0-9]+(\.[0-9]+)+$/ { print $1 }' | sort -V | tail -n 1
}
# Where the pack sits on the Frame: beside the disc, as the install below puts it.
frame_pack_path_for() {
    local disc=${1#\~/}
    [[ -n "$disc" ]] || disc=wiicompiled/disc
    if [[ "$disc" == */* ]]; then printf '%s/RetroRewind6\n' "$(dirname "$disc")"; else printf 'RetroRewind6\n'; fi
}

# ---------------------------------------------------------------------------------------------
# --update and --check: what the Frame has against what is published. Nothing is built when the
# Frame is already current, so an update that has nothing to do costs one web request.
if [[ "$mode" != install ]]; then
    [[ -n "$frame" ]] || fail "--$mode updates an install made by this script, and there is none in
    $work_dir. Install first (see --help), or pass --work-dir and --frame."
    say "Checking for an update"
    reasons=()
    if [[ -n "$source_dir" ]]; then
        # A source install has no published version to compare against; it rebuilds what changed.
        reasons+=("it was installed from the source tree in $source_dir, which is rebuilt as it is")
    else
        if [[ -z "$release" ]]; then
            release=$(newest_release) ||
                fail "could not reach github.com to ask for the newest release. Check this machine's
    internet connection, then try again."
            [[ -n "$release" ]] || fail "could not find the newest release on github.com/$repo"
        fi
        frame_installed_release=$(read_on_frame "$frame_game_dir/.release-tag") ||
            fail "cannot reach $frame over SSH to ask which release it has."
        if [[ "$frame_installed_release" == "$release" ]]; then
            note "the Frame has release $release"
        elif [[ -z "$frame_installed_release" ]]; then
            reasons+=("the Frame does not say which release it has; release $release would be installed")
        else
            reasons+=("release $release (the Frame has $frame_installed_release)")
        fi
    fi
    if (( retro_rewind )) && [[ -z "$retro_pack" ]]; then
        rr_published=$(rr_published_version) ||
            fail "could not reach Retro Rewind's update server (${rr_server})"
        rr_installed=$(read_on_frame "$(frame_pack_path_for "$frame_disc")/version.txt")
        if ! rr_version_ok "$rr_installed"; then
            reasons+=("the Frame does not say which Retro Rewind pack it has")
        elif rr_newer "$rr_published" "$rr_installed"; then
            reasons+=("Retro Rewind $rr_published (the Frame has $rr_installed)")
        else
            note "the Frame has Retro Rewind $rr_installed"
        fi
    fi

    if (( ${#reasons[@]} == 0 )); then
        say "Up to date"
        status uptodate "Up to date${release:+ (}${release}${release:+)}"
        relaunch
        exit 0
    fi
    note "an update is available:"
    for line in "${reasons[@]}"; do note "  $line"; done
    if [[ "$mode" == check ]]; then
        status available "${reasons[0]}"
        exit 0
    fi
    status running "Starting the update${release:+ to }$release"
fi

host_arch=$(uname -m)
case "$host_arch" in
    x86_64|aarch64) ;;
    *) fail "this machine is $host_arch; the build needs an x86_64 or ARM64 Linux machine" ;;
esac
[[ "$(uname -s)" == Linux ]] || fail "run this on Linux (the build uses a Linux container)"

# ---------------------------------------------------------------------------------------------
say "Checking the container runtime"
runtime=""
for candidate in podman docker; do
    if command -v "$candidate" >/dev/null 2>&1; then runtime=$candidate; break; fi
done
[[ -n "$runtime" ]] || fail "neither podman nor docker is installed.
    Arch, CachyOS:  sudo pacman -S --needed podman qemu-user-static qemu-user-static-binfmt
    Debian, Ubuntu: sudo apt install podman qemu-user-static binfmt-support
    Fedora:         sudo dnf install podman qemu-user-static
    SteamOS (the Frame) already has podman."
note "using $runtime"
for tool in curl tar; do
    command -v "$tool" >/dev/null 2>&1 || fail "'$tool' is not installed"
done

platform_args=()
if [[ "$host_arch" == x86_64 ]]; then
    platform_args=(--platform linux/arm64)
    say "Checking ARM64 emulation"
    seen=$("$runtime" run --rm "${platform_args[@]}" "$image" uname -m 2>&1 | tail -n 1 || true)
    case "$seen" in
        aarch64) note "ARM64 programs run under qemu" ;;
        Linux)
            fail "qemu is registered without the P (preserve argv[0]) flag its build needs, so every
    program loses its first argument (uname -m printed 'Linux'). Register it again with flags POCF;
    the README's 'Other ways to build' shows how." ;;
        *)
            fail "ARM64 programs do not run in containers here ($seen).
    Arch, CachyOS:  sudo pacman -S --needed qemu-user-static qemu-user-static-binfmt
                    sudo systemctl restart systemd-binfmt
    Debian, Ubuntu: sudo apt install qemu-user-static binfmt-support
    Fedora:         sudo dnf install qemu-user-static && sudo systemctl restart systemd-binfmt
    Then run this script again. On hosts whose binfmt_misc is per container (Unraid), see the
    README's 'Other ways to build'." ;;
    esac
fi

if [[ -z "$jobs" ]]; then
    mem_gb=$(( $(awk '/^MemTotal:/{print $2}' /proc/meminfo) / 1024 / 1024 ))
    jobs=$(( mem_gb / 4 ))
    (( jobs < 1 )) && jobs=1
    (( jobs > $(nproc) )) && jobs=$(nproc)
fi
[[ "$jobs" =~ ^[1-9][0-9]*$ ]] || fail "--jobs must be a positive number"
note "$jobs parallel compiles"

# ---------------------------------------------------------------------------------------------
# The source: the tree this script is in, an explicit --source, or a release kept in the work dir.
if [[ -z "$source_dir" && -z "$release" && -n "$script_dir" && -f "$script_dir/../runtime/CMakeLists.txt" ]]; then
    source_dir=$(cd "$script_dir/.." && pwd)
fi
if [[ -n "$source_dir" ]]; then
    source_dir=$(cd "$source_dir" && pwd)
    [[ -f "$source_dir/Launcher/local-build.sh" ]] || fail "$source_dir is not a WiiCompiled VR source tree"
    say "Building the source in $source_dir"
else
    if [[ -z "$release" ]]; then
        release=$(curl -fsSL "https://api.github.com/repos/$repo/releases?per_page=1" |
            sed -n 's/.*"tag_name": *"\([^"]*\)".*/\1/p' | head -n 1)
        [[ -n "$release" ]] || fail "could not find the newest release on github.com/$repo (try --release TAG)"
    fi
    source_dir="$work_dir/source"
    have=$(cat "$source_dir/.release-tag" 2>/dev/null || true)
    if [[ "$have" == "$release" ]]; then
        say "Release $release is already unpacked"
    else
        say "Downloading release $release"
        rm -rf "$work_dir/source-new"
        mkdir -p "$work_dir/source-new" "$source_dir"
        curl -fL --progress-bar "https://github.com/$repo/archive/refs/tags/$release.tar.gz" |
            tar -xz --strip-components=1 -C "$work_dir/source-new" ||
            fail "could not download release $release; the Releases page on github.com/$repo lists them"
        # Old installs have no ownership manifest; recover it from their exact release.
        if [[ ! -f "$source_dir/.release-files" && -n "$have" ]]; then
            curl -fL --progress-bar "https://github.com/$repo/archive/refs/tags/$have.tar.gz" |
                tar -tz | sed -e 's@^[^/]*/@@' -e '/\/$/d' -e '/^$/d' > "$source_dir/.release-files.partial" ||
                fail "could not recover the previous release's file list; keeping the source untouched"
            mv "$source_dir/.release-files.partial" "$source_dir/.release-files"
        fi
        frame_files sync "$work_dir/source-new" "$source_dir"
        rm -rf "$work_dir/source-new"
        printf '%s\n' "$release" > "$source_dir/.release-tag"
    fi
fi

# ---------------------------------------------------------------------------------------------
# The disc: the two files the translation reads, and the extracted disc the game reads at run time.
check_disc_id() {
    # Fails unless the extracted disc in $1 is the release the translation is made for.
    local id
    if [[ ! -f "$1/sys/boot.bin" ]]; then
        note "could not check the disc's game ID: $1/sys/boot.bin is missing"
        return 0
    fi
    id=$(head -c 6 "$1/sys/boot.bin" | tr -dc 'A-Z0-9')
    [[ "$id" == RMCP01 ]] && return 0
    # An extraction of the wrong disc is not kept, so the next run extracts the one it is given.
    [[ "$1" == "$work_dir/disc" ]] && rm -rf "$1"
    case "$id" in
        RMC?01) fail "this is the $id release of Mario Kart Wii. The translation is made for the PAL
    release, RMCP01; other regions' code differs and is not supported." ;;
        *) fail "this disc's game ID is ${id:-unreadable}, not Mario Kart Wii PAL (RMCP01)" ;;
    esac
}

get_nodtool() {
    nodtool="$work_dir/nodtool-$nodtool_version"
    if [[ ! -x "$nodtool" ]]; then
        curl -fL --progress-bar -o "$nodtool.partial" \
            "https://github.com/encounter/nod/releases/download/$nodtool_version/nodtool-linux-$host_arch"
        chmod +x "$nodtool.partial"
        mv "$nodtool.partial" "$nodtool"
    fi
}

archive_kind() {
    # Prints zip or 7z when $1 is such an archive, judged by its first bytes rather than its name.
    case "$(od -An -tx1 -N6 "$1" | tr -d ' \n')" in
        504b0304*|504b0506*|504b0708*) echo zip ;;
        377abcaf271c) echo 7z ;;
        *) return 1 ;;
    esac
}

unpack_archive() {
    # unpack_archive ARCHIVE DEST KIND, with whichever unpacker this machine has.
    local archive=$1 dest=$2 kind=$3 tool
    for tool in 7zz 7z 7za; do
        if command -v "$tool" >/dev/null 2>&1; then
            "$tool" x -y "-o$dest" "$archive" >/dev/null
            return
        fi
    done
    if command -v bsdtar >/dev/null 2>&1; then
        bsdtar -xf "$archive" -C "$dest"
        return
    fi
    if [[ "$kind" == zip ]] && command -v unzip >/dev/null 2>&1; then
        unzip -qo "$archive" -d "$dest"
        return
    fi
    if [[ "$kind" == zip ]] && command -v python3 >/dev/null 2>&1; then
        python3 -m zipfile -e "$archive" "$dest"
        return
    fi
    # Nothing here unpacks it: bsdtar in a container of this machine's own architecture.
    note "no 7-Zip or bsdtar on this machine; unpacking in a container"
    local platform=linux/amd64
    [[ "$host_arch" == aarch64 ]] && platform=linux/arm64
    "$runtime" run --rm --platform "$platform" -e OWNER="$(id -u):$(id -g)" \
        -v "$archive:/archive:ro,z" -v "$dest:/out:z" "$image" bash -c '
            apt-get update -qq && apt-get install -y -qq --no-install-recommends libarchive-tools >/dev/null &&
            bsdtar -xf /archive -C /out && chown -R "$OWNER" /out'
}

find_disc_image() {
    # Prints the disc image nodtool reads under $1, largest first, preferring Mario Kart Wii PAL;
    # another disc is printed if there is no RMCP01, so the ID check names what it is.
    local file id first=""
    while IFS= read -r -d '' file; do
        id=$("$nodtool" --no-color info "$file" 2>/dev/null |
            sed -n 's/^Game ID: *\([A-Z0-9]\{6\}\).*/\1/p' | head -n 1) || true
        [[ -n "$id" ]] || continue
        if [[ "$id" == RMCP01 ]]; then
            printf '%s\n' "$file"
            return 0
        fi
        [[ -n "$first" ]] || first=$file
    done < <(find "$1" -type f -printf '%s\t%p\0' | sort -zrn | cut -zf2-)
    [[ -n "$first" ]] || return 1
    printf '%s\n' "$first"
}

disc_dir="$work_dir/disc"
if [[ -n "$disc" ]]; then
    [[ -e "$disc" ]] || fail "no disc at $disc"
    if [[ -d "$disc" ]]; then
        disc_dir=$(cd "$disc" && pwd)
        # Some tools put the game's partition in a subfolder (DATA/, for example).
        if [[ ! -f "$disc_dir/sys/main.dol" ]]; then
            for candidate in "$disc_dir"/*/; do
                if [[ -f "$candidate/sys/main.dol" && -f "$candidate/files/rel/StaticR.rel" ]]; then
                    disc_dir=${candidate%/}
                    break
                fi
            done
        fi
        [[ -f "$disc_dir/sys/main.dol" && -f "$disc_dir/files/rel/StaticR.rel" ]] ||
            fail "$disc is not an extracted disc: it needs sys/main.dol and files/rel/StaticR.rel"
    elif [[ ! -f "$disc_dir/sys/main.dol" ]]; then
        get_nodtool
        disc_image=$disc
        if kind=$(archive_kind "$disc"); then
            say "Unpacking the $kind archive (a minute or two)"
            rm -rf "$work_dir/archive"
            mkdir -p "$work_dir/archive"
            unpack_archive "$disc" "$work_dir/archive" "$kind" || {
                rm -rf "$work_dir/archive"
                fail "could not unpack $disc (a damaged or password-protected archive?)"
            }
            disc_image=$(find_disc_image "$work_dir/archive") || {
                rm -rf "$work_dir/archive"
                fail "there is no disc image nodtool reads inside $disc. It reads ISO, WBFS, RVZ, WIA,
    CISO, GCZ, NFS and TGC images; an archive inside the archive has to be unpacked by hand."
            }
            note "found ${disc_image#"$work_dir/archive/"} inside"
        fi
        say "Extracting your disc (a minute or two)"
        rm -rf "$disc_dir.partial"
        # nodtool tells the format from the file's contents, whatever it is named.
        "$nodtool" extract -q "$disc_image" "$disc_dir.partial" ||
            fail "nodtool could not read $disc. It reads ISO, WBFS, RVZ, WIA, CISO, GCZ, NFS and TGC
    images, and those inside a .zip or .7z."
        mv "$disc_dir.partial" "$disc_dir"
        rm -rf "$work_dir/archive"
    fi
fi
if [[ ! -f "$disc_dir/sys/main.dol" || ! -f "$disc_dir/files/rel/StaticR.rel" ]]; then
    if [[ -f "$source_dir/Assets/main.dol" && -f "$source_dir/Assets/StaticR.rel" ]]; then
        disc_dir=""
    else
        fail "no disc yet: pass --disc with your disc image or an extracted disc folder"
    fi
fi
if [[ -n "$disc_dir" ]]; then
    check_disc_id "$disc_dir"
    note "disc: $disc_dir"
fi
mkdir -p "$source_dir/Assets"
if [[ -n "$disc_dir" ]]; then
    cp "$disc_dir/sys/main.dol" "$disc_dir/files/rel/StaticR.rel" "$source_dir/Assets/"
fi

# ---------------------------------------------------------------------------------------------
# Retro Rewind: its pack, as its update server publishes it, and the Retro-WFC payload its online
# play runs. Same steps as the Quest app (android/.../RetroRewindPack.kt and GameBuild.kt).
# Its server, versions and comparisons are up with the other version helpers.
rr_pack="$work_dir/RetroRewind6"
rr_payload="$work_dir/retro-wfc/binary/payload.RMCPD00.bin"

rr_unpack_update() {
    # rr_unpack_update URL DEST: downloads a published zip and lays its RetroRewind6/ tree over DEST.
    # Only that tree is kept; the Riivolution XML beside it belongs to a Wii setup.
    local url=${1/http:\/\/update.rwfc.net:8000\//https://update.rwfc.net/} dest=$2
    [[ "$url" == https://* ]] || fail "Retro Rewind's server gave a download that is not https: $url"
    rm -rf "$work_dir/rr-download" "$work_dir/rr-download.zip"
    mkdir -p "$work_dir/rr-download"
    curl -fL --retry 2 --progress-bar -o "$work_dir/rr-download.zip" "$url" ||
        fail "could not download $url"
    unpack_archive "$work_dir/rr-download.zip" "$work_dir/rr-download" zip ||
        fail "could not unpack $url"
    [[ -d "$work_dir/rr-download/RetroRewind6" ]] || fail "$url holds no RetroRewind6 folder"
    mkdir -p "$dest"
    cp -a "$work_dir/rr-download/RetroRewind6/." "$dest/"
    rm -rf "$work_dir/rr-download" "$work_dir/rr-download.zip"
}

if (( retro_rewind )); then
    if [[ -n "$retro_pack" ]]; then
        [[ -f "$retro_pack/Binaries/Code.pul" ]] ||
            fail "$retro_pack is not a RetroRewind6 folder: it needs Binaries/Code.pul"
        say "Copying your Retro Rewind pack"
        rm -rf "$rr_pack.partial"
        cp -a "$retro_pack" "$rr_pack.partial"
        rm -rf "$rr_pack" && mv "$rr_pack.partial" "$rr_pack"
    else
        say "Checking Retro Rewind's published version"
        feed=$(rr_fetch "${rr_server}RetroRewindVersion.txt") ||
            fail "could not reach Retro Rewind's update server (${rr_server})"
        # One update per line: <version> <url> <path> <description>, oldest first.
        updates=$(awk 'NF >= 4 && $1 ~ /^[0-9]+(\.[0-9]+)+$/ { print $1, $2 }' <<<"$feed" | sort -V -k1,1)
        [[ -n "$updates" ]] || fail "Retro Rewind's version list is empty"
        latest=$(tail -n 1 <<<"$updates" | cut -d' ' -f1)
        installed=$(tr -d '[:space:]' 2>/dev/null < "$rr_pack/version.txt" || true)
        rr_version_ok "$installed" && [[ -f "$rr_pack/Binaries/Code.pul" ]] || installed=""
        if [[ -z "$installed" ]]; then
            say "Downloading Retro Rewind (about 4 GB)"
            base=$(rr_fetch "${rr_server}RetroRewindInstall.txt" | tr -d '[:space:]') ||
                fail "Retro Rewind's server did not say where its download is"
            rm -rf "$rr_pack.partial"
            rr_unpack_update "$base" "$rr_pack.partial" </dev/null
            [[ -f "$rr_pack.partial/Binaries/Code.pul" && -f "$rr_pack.partial/version.txt" ]] ||
                fail "Retro Rewind's download did not contain the pack"
            rm -rf "$rr_pack" && mv "$rr_pack.partial" "$rr_pack"
            installed=$(tr -d '[:space:]' < "$rr_pack/version.txt")
        fi
        if rr_newer "$latest" "$installed"; then
            deletions=$(rr_fetch "${rr_server}RetroRewindDelete.txt") ||
                fail "could not read Retro Rewind's deletion list"
            previous=$installed
            while read -r version url; do
                rr_newer "$version" "$previous" || continue
                say "Applying Retro Rewind $version"
                rr_unpack_update "$url" "$rr_pack" </dev/null
                # Each update's deletions follow it, before the next update can put a file back.
                # Only paths inside the pack are touched, and none that climb out of it.
                while read -r dversion dpath; do
                    rr_version_ok "$dversion" || continue
                    rr_newer "$dversion" "$previous" || continue
                    rr_newer "$dversion" "$version" && continue
                    dpath=${dpath//\\//}
                    dpath=${dpath#/}
                    [[ "$dpath" == RetroRewind6/?* && "/$dpath/" != */../* ]] || continue
                    rm -rf "${rr_pack:?}/${dpath#RetroRewind6/}"
                done <<<"$deletions"
                previous=$version
            done <<<"$updates"
            # Written last, so an interrupted update runs again next time.
            printf '%s\n' "$latest" > "$rr_pack/version.txt"
        fi
        note "Retro Rewind $(tr -d '[:space:]' < "$rr_pack/version.txt")"
    fi

    # translate-mod builds the payload into the game; without it, going online jumps into code that
    # was never translated. Fetched on every build, as the Quest app does.
    say "Downloading the Retro-WFC payload for online play"
    mkdir -p "$(dirname "$rr_payload")"
    if curl -fsS --retry 2 --max-filesize 16777216 -H 'Accept-Encoding: identity' \
        -o "$rr_payload.partial" 'https://rwfc.net/api/wfc/payload?g=RMCPD00'; then
        mv "$rr_payload.partial" "$rr_payload"
    elif [[ -f "$rr_payload" ]]; then
        rm -f "$rr_payload.partial"
        note "rwfc.net did not answer; using the payload from the last build"
    else
        fail "Retro Rewind's online play needs the Retro-WFC payload from rwfc.net, which could not be
    downloaded. Check this machine's internet connection, then run the script again."
    fi
fi

# ---------------------------------------------------------------------------------------------
say "Preparing the ARM64 build container"
cat > "$work_dir/container-build.sh" <<'EOF'
#!/usr/bin/env bash
# Written by steam-frame-install.sh and run inside its build container.
set -euo pipefail
if [[ ! -f /var/lib/wiicompiled-build-deps ]]; then
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -qq
    apt-get install -y -qq --no-install-recommends \
        ca-certificates curl git python3 xz-utils unzip file pkg-config g++ binutils libicu-dev \
        zlib1g-dev libvulkan-dev libx11-dev libx11-xcb-dev libxcb1-dev libxext-dev libxrandr-dev \
        libxinerama-dev libxcursor-dev libxi-dev libxss-dev libxtst-dev libxkbcommon-dev \
        libwayland-dev wayland-protocols libdecor-0-dev libegl-dev libgl-dev libgles-dev libdrm-dev \
        libgbm-dev libasound2-dev libpulse-dev libpipewire-0.3-dev libudev-dev libdbus-1-dev \
        libusb-1.0-0-dev >/dev/null
    touch /var/lib/wiicompiled-build-deps
fi
cd /src
Launcher/prepare-portable-tools.sh --arch aarch64 --destination /work/tools
T=/work/tools/toolchain-aarch64/bin
if [[ ! -x /work/dotnet/dotnet ]]; then
    curl -fsSL https://dot.net/v1/dotnet-install.sh | bash -s -- --channel 8.0 --install-dir /work/dotnet
fi
echo "== Dawn (built once; reused until a release changes its patches)"
Launcher/build-dawn-linux.sh --work-dir /work/dawn --cc "$T/clang" --cxx "$T/clang++" \
    --cmake "$T/cmake" --ninja "$T/ninja" --jobs "$JOBS"
echo "== The game"
products=(--output-dir /work/out)
if [[ "$RETRO_REWIND" == 1 ]]; then
    # Both products from one translation: the base game in out/, Retro Rewind in out-retro-rewind/.
    products=(--profile both --output-dir /work/out-retro-rewind --base-output-dir /work/out
        --retro-rewind-package-dir /work/RetroRewind6 --retro-wfc-offline-dir /work/retro-wfc)
fi
Launcher/local-build.sh "${products[@]}" --cc "$T/clang" --cxx "$T/clang++" --fuse-ld lld \
    --cmake "$T/cmake" --ninja "$T/ninja" --dotnet /work/dotnet/dotnet --parallel "$JOBS" \
    --openxr --dawn-package /work/dawn/package --headset steam_frame
EOF
chmod +x "$work_dir/container-build.sh"

# One long-lived container, so its packages are installed once; recreated if its folders changed.
want_mounts="$work_dir=/work;$source_dir=/src;"
if "$runtime" container inspect "$container" >/dev/null 2>&1; then
    mounts=$("$runtime" container inspect -f '{{range .Mounts}}{{.Source}}={{.Destination}};{{end}}' "$container")
    if [[ "$mounts" != *"$work_dir=/work;"* || "$mounts" != *"$source_dir=/src;"* ]]; then
        note "its folders changed; recreating it"
        "$runtime" rm -f "$container" >/dev/null
    fi
fi
if ! "$runtime" container inspect "$container" >/dev/null 2>&1; then
    "$runtime" run -d --name "$container" "${platform_args[@]}" \
        -v "$work_dir:/work:z" -v "$source_dir:/src:z" "$image" sleep infinity >/dev/null
fi
"$runtime" start "$container" >/dev/null
note "container $container (mounts ${want_mounts//;/ })"

build_progress() {
    # Passes the build's output on, and keeps the game's status file at the stage it is on and how
    # far through it ninja is, from the "[done/total]" lines it prints.
    local line stage=Building percent last=-1
    while IFS= read -r line; do
        printf '%s\n' "$line"
        [[ -n "${WIICOMPILED_UPDATE_STATUS:-}" ]] || continue
        if [[ "$line" == "== "* ]]; then
            stage=${line#== }
            stage=${stage%% (*}
            last=-1
            status running "$stage"
        elif [[ "$line" =~ ^\[([0-9]+)/([0-9]+)\] ]] && (( BASH_REMATCH[2] > 0 )); then
            percent=$(( BASH_REMATCH[1] * 100 / BASH_REMATCH[2] ))
            if (( percent != last )); then
                last=$percent
                status running "$stage, $percent% built"
            fi
        fi
    done
}

say "Building (the first time takes hours under emulation; a log is in $work_dir/build.log)"
if ! "$runtime" exec -e JOBS="$jobs" -e RETRO_REWIND="$retro_rewind" "$container" bash /work/container-build.sh 2>&1 |
    tee "$work_dir/build.log" | build_progress; then
    fail "the build stopped; the end of $work_dir/build.log says why. Run the script again to resume.
    A machine that froze ran out of memory: pass a lower --jobs."
fi
[[ -x "$work_dir/out/$game_id" ]] || fail "the build finished without $work_dir/out/$game_id"
note "built $work_dir/out/$game_id"
if (( retro_rewind )); then
    [[ -x "$work_dir/out-retro-rewind/RetroRewind" ]] ||
        fail "the build finished without $work_dir/out-retro-rewind/RetroRewind"
    note "built $work_dir/out-retro-rewind/RetroRewind"
fi

# ---------------------------------------------------------------------------------------------
if [[ -z "$frame" ]]; then
    say "Done"
    note "The game is in $work_dir/out. Run the script again with --frame steamos@<frame-ip> to install it."
    exit 0
fi

say "Installing on the Frame"
# on_frame and the SSH options it uses are up with the version helpers.
copy_to_frame() {
    # copy_to_frame SOURCE DEST: DEST is absolute or relative to the Frame's home. A DEST ending in
    # / is an existing folder SOURCE goes into; otherwise SOURCE is copied to that new name.
    local source=$1 dest=$2
    if [[ "$frame" == local ]]; then
        [[ "$dest" == /* ]] || dest="$HOME/$dest"
        cp -R "$source" "$dest"
    elif [[ "$frame_rsync" == yes ]]; then
        # rsync copies a folder without a trailing slash into DEST rather than as DEST.
        [[ -d "$source" && "$dest" != */ ]] && source="$source/"
        rsync -a -e "ssh ${ssh_opts[*]}" "$source" "$frame:$dest"
    else
        scp -rq "${ssh_opts[@]}" "$source" "$frame:$dest"
    fi
}

on_frame <<<'true' || fail "cannot reach $frame over SSH. Turn on Developer Mode and set a user password on the
    Frame (Steam Settings > System), then check the address."
frame_rsync=no
if [[ "$frame" != local ]] && command -v rsync >/dev/null 2>&1 &&
    [[ "$(on_frame <<<'command -v rsync >/dev/null && echo yes || true')" == yes ]]; then
    frame_rsync=yes
fi

install_game() {
    # install_game ID OUT: the built game in OUT goes to ~/devkit-game/ID on the Frame.
    local id=$1 out=$2 dir="devkit-game/$1"
    on_frame "$dir" <<'EOF'
mkdir -p "$HOME/$1"
EOF
    note "copying $id to ~/$dir"
    (cd "$out" && find . -mindepth 1 -maxdepth 1 ! -name "$id" -print0) |
        while IFS= read -r -d '' item; do copy_to_frame "$out/${item#./}" "$dir/"; done
    # The executable goes in under a new name and is moved into place: that works while it runs.
    copy_to_frame "$out/$id" "$dir/$id.new"
    on_frame "$dir" "$id" <<'EOF'
cd "$HOME/$1" && mv -f "$2.new" "$2" && chmod -R u=rwX,go=rX . && chmod 755 "$2"
EOF
    # Which release is on the Frame, for --check and the game's Updates tab. A source build has no
    # release to name, and the stamp is removed so neither claims a release this is not.
    on_frame "$dir" "$release" <<'EOF'
cd "$HOME/$1" && if [[ -n "$2" ]]; then printf '%s\n' "$2" > .release-tag; else rm -f .release-tag; fi
EOF
}
install_game "$game_id" "$work_dir/out"
if (( retro_rewind )); then install_game RetroRewind "$work_dir/out-retro-rewind"; fi

# The Frame's disc folder, absolute or relative to its home.
if [[ -z "$frame_disc" ]]; then
    if [[ "$frame" == local && -n "$disc_dir" ]]; then frame_disc=$disc_dir; else frame_disc=wiicompiled/disc; fi
fi
frame_disc_path=${frame_disc#\~/}
has_disc=$(on_frame "$frame_disc_path" <<'EOF'
[[ "$1" = /* ]] && d=$1 || d="$HOME/$1"
[[ -f "$d/sys/main.dol" ]] && echo yes || true
EOF
)
if [[ "$has_disc" != yes ]]; then
    [[ -n "$disc_dir" ]] || fail "the Frame has no disc at $frame_disc yet: pass --disc"
    note "copying the extracted disc to $frame_disc (a few GB)"
    on_frame "$frame_disc_path" <<'EOF'
[[ "$1" = /* ]] && d=$1 || d="$HOME/$1"
mkdir -p "$(dirname "$d")" && rm -rf "$d.partial"
EOF
    copy_to_frame "$disc_dir" "$frame_disc_path.partial"
    on_frame "$frame_disc_path" <<'EOF'
[[ "$1" = /* ]] && d=$1 || d="$HOME/$1"
rm -rf "$d" && mv "$d.partial" "$d"
EOF
fi

if (( retro_rewind )); then
    # The pack goes beside the disc; copied again only when its version changed.
    frame_pack_path=$(frame_pack_path_for "$frame_disc_path")
    frame_pack_version=$(read_on_frame "$frame_pack_path/version.txt")
    local_pack_version=$(tr -d '[:space:]' 2>/dev/null < "$rr_pack/version.txt" || true)
    if [[ -z "$frame_pack_version" || "$frame_pack_version" != "$local_pack_version" ]]; then
        note "copying the Retro Rewind pack to $frame_pack_path (about 4 GB)"
        on_frame "$frame_pack_path" <<'EOF'
[[ "$1" = /* ]] && d=$1 || d="$HOME/$1"
mkdir -p "$(dirname "$d")" && rm -rf "$d.partial"
EOF
        copy_to_frame "$rr_pack" "$frame_pack_path.partial"
        on_frame "$frame_pack_path" <<'EOF'
[[ "$1" = /* ]] && d=$1 || d="$HOME/$1"
rm -rf "$d" && mv "$d.partial" "$d"
EOF
    fi
fi

set_frame_path() {
    { declare -f frame_files; printf '%s\n' 'frame_files "$@"'; } | on_frame config "$1" "$2"
}

if (( retro_rewind )); then
    note "pointing Retro Rewind at its pack"
    set_frame_path retro_rewind_root "$frame_pack_path"
fi
note "pointing the game at the disc"
set_frame_path dvd_root "$frame_disc_path"

# Steam's library: through Valve's devkit tools when Frame Control or the Devkit Client put them on
# the Frame, as a Steam Linux Runtime ARM64 title (Steam starts an ARM64 program natively).
# Registering again is harmless and refreshes the entry, as Valve's Devkit Client does each upload.
register_game() {
    # register_game ID OUT: adds ~/devkit-game/ID to Steam's library, or says how to.
    local id=$1 out=$2 dir="devkit-game/$1" registered
registered=$(on_frame "$dir" "$id" <<'EOF'
if [[ ! -f "$HOME/devkit-utils/steam-client-create-shortcut" ]]; then echo no-tools; exit 0; fi
parms=$(printf '{"gameid": "%s", "directory": "%s", "argv": ["%s"], "env": {}, "settings": {"steam_play": "0", "compat_tool": "SteamLinuxRuntime_4-arm64"}, "clear_settings": true, "force_appid": "", "lepton_args": ""}' "$2" "$HOME/$1" "$2")
reply=$(python3 "$HOME/devkit-utils/steam-client-create-shortcut" --parms "$parms" 2>/dev/null | tail -n 1)
case "$reply" in *'"success"'*) echo added ;; *) echo "failed $reply" ;; esac
EOF
)
case "$registered" in
    added) note "$id is in your Steam library" ;;
    no-tools|failed*)
        [[ "$registered" == failed* ]] && note "Steam did not take the shortcut: ${registered#failed }"
        note "Add $id to your Steam library once: in Frame Control, Send to Frame the folder"
        note "  $out (name it $id), or on the Frame in Desktop Mode, Steam >"
        note "  Add a Non-Steam Game > ~/$dir/$id. Later runs of this script keep it updated." ;;
esac
}
register_game "$game_id" "$work_dir/out"
if (( retro_rewind )); then register_game RetroRewind "$work_dir/out-retro-rewind"; fi

# ---------------------------------------------------------------------------------------------
# Updating from inside the game. Only an install on the Frame itself can do it, since that is the
# only one with the build here; installed from a PC, the game's Updates tab says to update there.
if [[ "$frame" == local ]]; then
    note "setting up the game's Update button"
    update_script="$work_dir/steam-frame-install.sh"
    # A copy, so an update never runs from the source tree it is about to overwrite.
    cp -f "$source_dir/Launcher/steam-frame-install.sh" "$update_script"
    chmod +x "$update_script"
    mkdir -p "$game_data" "$HOME/.config/systemd/user"
    cat > "$game_data/update.conf" <<EOF
# Written by steam-frame-install.sh: what the game's Updates tab runs. Remove this file to take the
# Update button away, and the tab goes back to saying how to update from a PC.
script=$update_script
work_dir=$work_dir
service=wiicompiled-update.service
EOF
    # Its own service, so the update outlives the game that started it: Steam stops the game's own
    # process group when the game closes.
    cat > "$HOME/.config/systemd/user/wiicompiled-update.service" <<EOF
[Unit]
Description=WiiCompiled VR update

[Service]
Type=oneshot
Environment=WIICOMPILED_UPDATE_STATUS=$game_data/update-status
Environment=WIICOMPILED_UPDATE_REQUEST=$game_data/update-request
# Below the game in line for the processor and the storage, so it can keep running meanwhile.
Nice=19
IOSchedulingClass=idle
ExecStart=$update_script --update --work-dir "$work_dir"
EOF
    systemctl --user daemon-reload >/dev/null 2>&1 ||
        note "(systemd did not reload, so the Update button will not work until the Frame restarts)"
fi

save_settings

say "Done"
status done "Updated${release:+ to }${release}"
if [[ "$mode" == update ]]; then
    note "Updated${release:+ to }$release."
else
    note "Start $game_id from your library in the headset. Settings: left shoulder button, VR tab."
fi
if (( retro_rewind )); then note "RetroRewind is beside it, and shares its settings."; fi
relaunch
}

main "$@" </dev/null
