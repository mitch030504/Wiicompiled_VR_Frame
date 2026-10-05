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
# SteamOS's system is read-only and replaced by every update, so nothing here installs into it or
# needs root on the Frame: the game, the disc, its settings and the Steam shortcut all live in the
# home folder (~/devkit-game/WiiCompiled, ~/wiicompiled/disc, ~/.local/share/WiiCompiled), where
# they survive SteamOS updates.
#
# Options:
#   --disc PATH       your clean PAL RMCP01 disc: an ISO, WBFS or RVZ image (or WIA, CISO, GCZ, NFS,
#                     TGC), a .zip or .7z holding one, or an extracted disc folder holding sys/ and
#                     files/. Needed for the first build only.
#   --frame HOST      where to install: an SSH destination (steamos@<frame-ip>, or an ~/.ssh/config
#                     host such as Frame Control's "frame"), or "local" when running on the Frame.
#                     Without it the game is only built.
#   --work-dir DIR    where the toolchain, Dawn, the build and the extracted disc live
#                     (default ~/wiicompiled-frame; about 10 GB, plus 5 for an extracted disc)
#   --release TAG     the release to build (default: the newest one). Ignored with --source.
#   --source DIR      build this source tree instead of a release (default when the script runs
#                     from inside one)
#   --jobs N          parallel compiles (default: a quarter of the memory in GB; under emulation each
#                     compile needs a lot of it)
#   --frame-disc DIR  where the extracted disc goes on the Frame: relative to the Frame's home, or
#                     an absolute path somewhere writable (the home folder or a mounted card; the
#                     rest of SteamOS is read-only). Default wiicompiled/disc; with --frame local,
#                     the disc folder the build used.
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
elapsed() { printf '%dh %02dm' $((SECONDS / 3600)) $((SECONDS % 3600 / 60)); }
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
SECONDS=0
progress=(-sS)
[[ -t 2 ]] && progress=(--progress-bar)
host_arch=$(uname -m)
case "$host_arch" in
    x86_64|aarch64) ;;
    *) fail "this machine is $host_arch; the build needs an x86_64 or ARM64 Linux machine" ;;
esac
[[ "$(uname -s)" == Linux ]] || fail "run this on Linux (the build uses a Linux container)"
# SteamOS (the Frame, or a Steam Deck used as the build machine): its system is read-only and
# replaced by updates, so a missing tool cannot be installed into it, and the advice differs.
os_id=$( (. /etc/os-release 2>/dev/null && printf '%s' "${ID:-}") || true)
if [[ "$frame" == local && "$host_arch" != aarch64 ]]; then
    fail "--frame local installs on the machine the script runs on, which is $host_arch, not the Frame.
    Run it on the Frame, or give --frame the Frame's SSH address (steamos@<frame-ip>)."
fi

# ---------------------------------------------------------------------------------------------
say "Checking the container runtime"
runtime=""
for candidate in podman docker; do
    if command -v "$candidate" >/dev/null 2>&1; then runtime=$candidate; break; fi
done
if [[ -z "$runtime" && "$os_id" == steamos ]]; then
    fail "this SteamOS has neither podman nor docker. Its system is read-only and every update
    replaces it, so don't install them with pacman. Build on a Linux PC instead and install from
    there: run this script on the PC with --frame steamos@<frame-ip>."
fi
[[ -n "$runtime" ]] || fail "neither podman nor docker is installed.
    Arch, CachyOS:  sudo pacman -S --needed podman qemu-user-static qemu-user-static-binfmt
    Debian, Ubuntu: sudo apt install podman qemu-user-static binfmt-support
    Fedora:         sudo dnf install podman qemu-user-static
    Bazzite, Silverblue and other image-based systems have podman already; add qemu-user-static
    the way the system layers packages (rpm-ostree install qemu-user-static)."
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
            [[ "$os_id" != steamos ]] || fail "ARM64 programs do not run in containers here ($seen),
    and SteamOS's read-only system cannot add qemu. Build on the Frame itself (--frame local) or
    on another Linux PC."
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

# Room for the build. A first one (the toolchain, Dawn's source and build, the game's build) takes
# about 10 GB (measured on a Frame: 8.3 GB with the disc); later ones reuse Dawn. Extracting a disc image takes about 5 GB more, plus the
# archive's size while one is unpacked. Running out halfway is worse than stopping here.
need_gb=10
[[ -f "$work_dir/dawn/package/aurora-dawn.json" ]] && need_gb=3
if [[ -n "$disc" && -f "$disc" && ! -f "$work_dir/disc/sys/main.dol" ]]; then
    need_gb=$(( need_gb + 5 + $(du -k "$disc" | cut -f1) / 1024 / 1024 ))
fi
free_gb=$(( $(df -Pk "$work_dir" | awk 'NR == 2 { print $4 }') / 1024 / 1024 ))
if (( free_gb < need_gb )); then
    fail "$work_dir has $free_gb GB free; this run needs about $need_gb GB. Free some space, or put
    the work folder on a bigger drive with --work-dir (on the Frame, a mounted card such as
    --work-dir /run/media/${USER:-$(id -un)}/<card>/wiicompiled-frame)."
fi
note "$free_gb GB free in $work_dir"

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
        curl -fL "${progress[@]}" "https://github.com/$repo/archive/refs/tags/$release.tar.gz" |
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
        curl -fL "${progress[@]}" -o "$nodtool.partial" \
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

if [[ -n "${platform_args[*]}" ]]; then
    say "Building (a first build takes hours under emulation; a log is in $work_dir/build.log)"
else
    say "Building (a first build takes a while, most of it Dawn; a log is in $work_dir/build.log)"
fi
# .NET's first-run banner, telemetry and developer certificate are no use in a build container.
if ! "$runtime" exec -e JOBS="$jobs" -e DOTNET_CLI_TELEMETRY_OPTOUT=1 -e DOTNET_NOLOGO=1 \
    -e DOTNET_SKIP_FIRST_TIME_EXPERIENCE=1 -e DOTNET_GENERATE_ASPNET_CERTIFICATE=false \
    "$container" bash /work/container-build.sh 2>&1 | tee "$work_dir/build.log"; then
    fail "the build stopped; the end of $work_dir/build.log says why. Run the script again to resume.
    A machine that froze ran out of memory: pass a lower --jobs."
fi
[[ -x "$work_dir/out/$game_id" ]] || fail "the build finished without $work_dir/out/$game_id"
note "built $work_dir/out/$game_id ($(elapsed) so far)"

# ---------------------------------------------------------------------------------------------
if [[ -z "$frame" ]]; then
    say "Done in $(elapsed)"
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
    # The folder must be writable, and have room for the disc (prints its free space in KB).
    frame_free_kb=$(on_frame "$frame_disc_path" <<'EOF'
[[ "$1" = /* ]] && d=$1 || d="$HOME/$1"
mkdir -p "$(dirname "$d")" 2>/dev/null && [[ -w "$(dirname "$d")" ]] && rm -rf "$d.partial" &&
    df -Pk "$(dirname "$d")" | awk 'NR == 2 { print $4 }'
EOF
    ) || fail "cannot write $frame_disc on the Frame. SteamOS's system is read-only: pick a folder in
    the home folder (the default, wiicompiled/disc) or on a mounted card."
    disc_kb=$(du -sk "$disc_dir" | cut -f1)
    if (( frame_free_kb < disc_kb + 1024 * 1024 )); then
        fail "the Frame has $(( frame_free_kb / 1024 / 1024 )) GB free where the disc goes and the disc
    needs $(( disc_kb / 1024 / 1024 + 1 )) GB. Free some space, or put it on a mounted card with
    --frame-disc /run/media/<user>/<card>/wiicompiled-disc."
    fi
    note "copying the extracted disc to $frame_disc (a few GB)"
    copy_to_frame "$disc_dir" "$frame_disc_path.partial"
    on_frame "$frame_disc_path" <<'EOF'
[[ "$1" = /* ]] && d=$1 || d="$HOME/$1"
rm -rf "$d" && mv "$d.partial" "$d"
EOF
fi

note "pointing the game at the disc"
on_frame "$frame_disc_path" <<'EOF'
[[ "$1" = /* ]] && d=$1 || d="$HOME/$1"
config="${XDG_DATA_HOME:-$HOME/.local/share}/WiiCompiled/Config.toml"
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

say "Done in $(elapsed)"
note "Start $game_id from your library in the headset. Settings: left shoulder button, VR tab."
}

main "$@" </dev/null
