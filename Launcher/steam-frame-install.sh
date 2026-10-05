#!/usr/bin/env bash
# Builds WiiCompiled VR for the Steam Frame from a release and your own disc, and installs it on the
# Frame. Run it again to update: it fetches the newest release and rebuilds only what changed.
#
#   Launcher/steam-frame-install.sh --disc PATH [--frame HOST] [options]
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
#   --disc PATH       your clean PAL RMCP01 disc: an image nodtool reads (ISO, WBFS, RVZ, ...) or an
#                     extracted disc folder holding sys/ and files/. Needed for the first build only.
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
#   -h, --help
set -euo pipefail

# Everything is in main, so bash has read the whole script before running any of it: when it comes
# through curl | bash, a step that reads stdin cannot eat the rest. (Not indented, for the heredocs.)
main() {
trap 'printf "\nsteam-frame-install.sh: stopped by a failed step (line %s); the output above says why.\n" "$LINENO" >&2' ERR

repo=mitch030504/Wiicompiled_VR_Frame
game_id=WiiCompiled
image=docker.io/library/debian:trixie
container=wiicompiled-frame-build
nodtool_version=v2.0.0-alpha.10

say() { printf '\n\033[1m==> %s\033[0m\n' "$*"; }
note() { printf '    %s\n' "$*"; }
fail() {
    printf '\nsteam-frame-install.sh: error: %s\n' "$*" >&2
    exit 1
}
usage() { awk 'NR == 1 { next } /^#/ { sub(/^# ?/, ""); print; next } { exit }' "$script_path"; }

script_path=${BASH_SOURCE[0]:-}
script_dir=""
if [[ -n "$script_path" && -f "$script_path" ]]; then
    script_dir=$(cd "$(dirname "$script_path")" && pwd)
fi

disc=""
frame=""
work_dir="$HOME/wiicompiled-frame"
release=""
source_dir=""
jobs=""
frame_disc=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --disc) disc=$2; shift 2 ;;
        --frame) frame=$2; shift 2 ;;
        --work-dir) work_dir=$2; shift 2 ;;
        --release) release=$2; shift 2 ;;
        --source) source_dir=$2; shift 2 ;;
        --jobs) jobs=$2; shift 2 ;;
        --frame-disc) frame_disc=$2; shift 2 ;;
        -h|--help)
            if [[ -n "$script_dir" ]]; then usage; else echo "See the comment at the top of the script."; fi
            exit 0 ;;
        *) fail "unknown argument: $1 (see --help)" ;;
    esac
done

mkdir -p "$work_dir"
work_dir=$(cd "$work_dir" && pwd)
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
        # Only files whose content changed are copied, stamped with the current time, so the build
        # recompiles exactly those; the release's own file dates can be older than the last build.
        if command -v rsync >/dev/null 2>&1; then
            rsync -rcE "$work_dir/source-new/" "$source_dir/"
        else
            (cd "$work_dir/source-new" && find . -type f -print0) |
                while IFS= read -r -d '' file; do
                    if ! cmp -s "$work_dir/source-new/$file" "$source_dir/$file"; then
                        mkdir -p "$source_dir/$(dirname "$file")"
                        cp "$work_dir/source-new/$file" "$source_dir/$file"
                        touch "$source_dir/$file"
                    fi
                done
        fi
        rm -rf "$work_dir/source-new"
        printf '%s\n' "$release" > "$source_dir/.release-tag"
    fi
fi

# ---------------------------------------------------------------------------------------------
# The disc: the two files the translation reads, and the extracted disc the game reads at run time.
disc_dir="$work_dir/disc"
if [[ -n "$disc" ]]; then
    [[ -e "$disc" ]] || fail "no disc at $disc"
    if [[ -d "$disc" ]]; then
        disc_dir=$(cd "$disc" && pwd)
    elif [[ ! -f "$disc_dir/sys/main.dol" ]]; then
        say "Extracting your disc"
        nodtool="$work_dir/nodtool-$nodtool_version"
        if [[ ! -x "$nodtool" ]]; then
            curl -fL -o "$nodtool.partial" \
                "https://github.com/encounter/nod/releases/download/$nodtool_version/nodtool-linux-$host_arch"
            chmod +x "$nodtool.partial"
            mv "$nodtool.partial" "$nodtool"
        fi
        rm -rf "$disc_dir.partial"
        "$nodtool" extract "$disc" "$disc_dir.partial"
        mv "$disc_dir.partial" "$disc_dir"
    fi
fi
if [[ ! -f "$disc_dir/sys/main.dol" || ! -f "$disc_dir/files/rel/StaticR.rel" ]]; then
    if [[ -f "$source_dir/Assets/main.dol" && -f "$source_dir/Assets/StaticR.rel" ]]; then
        disc_dir=""
    else
        fail "no disc yet: pass --disc with your disc image or an extracted disc folder"
    fi
fi
mkdir -p "$source_dir/Assets"
if [[ -n "$disc_dir" ]]; then
    cp "$disc_dir/sys/main.dol" "$disc_dir/files/rel/StaticR.rel" "$source_dir/Assets/"
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
Launcher/local-build.sh --output-dir /work/out --cc "$T/clang" --cxx "$T/clang++" --fuse-ld lld \
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

say "Building (the first time takes hours under emulation; a log is in $work_dir/build.log)"
if ! "$runtime" exec -e JOBS="$jobs" "$container" bash /work/container-build.sh 2>&1 | tee "$work_dir/build.log"; then
    fail "the build stopped; the end of $work_dir/build.log says why. Run the script again to resume.
    A machine that froze ran out of memory: pass a lower --jobs."
fi
[[ -x "$work_dir/out/$game_id" ]] || fail "the build finished without $work_dir/out/$game_id"
note "built $work_dir/out/$game_id"

# ---------------------------------------------------------------------------------------------
if [[ -z "$frame" ]]; then
    say "Done"
    note "The game is in $work_dir/out. Run the script again with --frame steamos@<frame-ip> to install it."
    exit 0
fi

say "Installing on the Frame"
# One SSH connection for every step, so a password is asked for once.
ssh_opts=(-o ControlMaster=auto -o "ControlPath=${XDG_RUNTIME_DIR:-/tmp}/wiicompiled-ssh-%C" -o ControlPersist=600)
on_frame() {
    # Runs a bash script, given on stdin, on the Frame; its arguments follow.
    if [[ "$frame" == local ]]; then bash -s -- "$@"; else ssh "${ssh_opts[@]}" "$frame" bash -s -- "$@"; fi
}
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

game_dir="devkit-game/$game_id"
on_frame "$game_dir" <<'EOF'
mkdir -p "$HOME/$1"
EOF
note "copying the game to ~/$game_dir"
(cd "$work_dir/out" && find . -mindepth 1 -maxdepth 1 ! -name "$game_id" -print0) |
    while IFS= read -r -d '' item; do copy_to_frame "$work_dir/out/${item#./}" "$game_dir/"; done
# The executable goes in under a new name and is moved into place: that works while it runs.
copy_to_frame "$work_dir/out/$game_id" "$game_dir/$game_id.new"
on_frame "$game_dir" "$game_id" <<'EOF'
cd "$HOME/$1" && mv -f "$2.new" "$2" && chmod -R u=rwX,go=rX . && chmod 755 "$2"
EOF

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

note "pointing the game at the disc"
on_frame "$frame_disc_path" <<'EOF'
[[ "$1" = /* ]] && d=$1 || d="$HOME/$1"
config="$HOME/.local/share/WiiCompiled/Config.toml"
mkdir -p "$(dirname "$config")"
if [[ ! -f "$config" ]]; then
    printf '[paths]\ndvd_root = "%s"\n' "$d" > "$config"
elif ! grep -q '^dvd_root *=' "$config"; then
    if grep -q '^\[paths\]' "$config"; then
        sed -i "/^\[paths\]/a dvd_root = \"$d\"" "$config"
    else
        printf '\n[paths]\ndvd_root = "%s"\n' "$d" >> "$config"
    fi
fi
EOF

# Steam's library: through Valve's devkit tools when Frame Control or the Devkit Client put them on
# the Frame, as a Steam Linux Runtime ARM64 title (Steam starts an ARM64 program natively).
# Registering again is harmless and refreshes the entry, as Valve's Devkit Client does each upload.
registered=$(on_frame "$game_dir" "$game_id" <<'EOF'
if [[ ! -f "$HOME/devkit-utils/steam-client-create-shortcut" ]]; then echo no-tools; exit 0; fi
parms=$(printf '{"gameid": "%s", "directory": "%s", "argv": ["%s"], "env": {}, "settings": {"steam_play": "0", "compat_tool": "SteamLinuxRuntime_4-arm64"}, "clear_settings": true, "force_appid": "", "lepton_args": ""}' "$2" "$HOME/$1" "$2")
reply=$(python3 "$HOME/devkit-utils/steam-client-create-shortcut" --parms "$parms" 2>/dev/null | tail -n 1)
case "$reply" in *'"success"'*) echo added ;; *) echo "failed $reply" ;; esac
EOF
)
case "$registered" in
    added) note "it is in your Steam library" ;;
    no-tools|failed*)
        [[ "$registered" == failed* ]] && note "Steam did not take the shortcut: ${registered#failed }"
        note "Add it to your Steam library once: in Frame Control, Send to Frame the folder"
        note "  $work_dir/out (name it $game_id), or on the Frame in Desktop Mode, Steam >"
        note "  Add a Non-Steam Game > ~/$game_dir/$game_id. Later runs of this script keep it updated." ;;
esac

say "Done"
note "Start $game_id from your library in the headset. Settings: left shoulder button, VR tab."
}

main "$@" </dev/null
