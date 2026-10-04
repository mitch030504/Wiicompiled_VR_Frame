#!/usr/bin/env bash
# Builds the pinned Dawn for desktop Linux with Aurora's patches (aurora-main/patches/dawn): the
# Vulkan hooks through which the OpenXR runtime creates Dawn's own instance and device (the
# same-device OpenXR backend, runtime/src/vr/openxr_vulkan_win32.cpp) and fragment density maps for
# foveated rendering. The stock prebuilt package has neither. This is the Linux counterpart of
# android/Build-QuestDawn.ps1, for the Steam Frame's native SteamOS build (docs/steam-frame.md).
#
#   Launcher/build-dawn-linux.sh [--work-dir DIR] [--cc PATH --cxx PATH] [--cmake PATH]
#                                [--ninja PATH] [--python PATH] [--jobs N] [--force]
#
# It builds for the machine it runs on (the Frame's aarch64, in a container there). Pass the same
# --cc/--cxx as Launcher/local-build.sh gets: the archive is static and carries C++ objects, so it
# must be built against the same C++ standard library as the game.
#
# The result is an install tree in the stock package's layout under WORK_DIR/package, with an
# aurora-dawn.json declaring the two ABIs (AuroraVulkanAbi, AuroraFdmAbi) that
# aurora-main/cmake/AuroraDawnProvider.cmake reads. local-build.sh --dawn-package takes it. A later
# run with the same inputs reuses it.
#
# Prerequisites: git, python3, curl, tar, CMake 3.25+, Ninja, a C/C++ compiler, and the X11, XCB and
# Wayland development headers Dawn's Vulkan surfaces need. The first build compiles all of Dawn and
# Tint and takes a while.
set -euo pipefail

fail() {
    echo "build-dawn-linux.sh: error: $*" >&2
    exit 1
}

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
repo=$(cd "$script_dir/.." && pwd)
work_dir="$repo/.scratch/linux-dawn"
cc_bin=${CC:-cc}
cxx_bin=${CXX:-c++}
cmake_bin=cmake
ninja_bin=ninja
python_bin=python3
jobs=$(nproc)
force=0

while [[ $# -gt 0 ]]; do
    case "$1" in
        --work-dir) work_dir=$2; shift 2 ;;
        --cc) cc_bin=$2; shift 2 ;;
        --cxx) cxx_bin=$2; shift 2 ;;
        --cmake) cmake_bin=$2; shift 2 ;;
        --ninja) ninja_bin=$2; shift 2 ;;
        --python) python_bin=$2; shift 2 ;;
        --jobs) jobs=$2; shift 2 ;;
        --force) force=1; shift ;;
        -h|--help) sed -n '2,24p' "$0"; exit 0 ;;
        *) fail "unknown argument: $1" ;;
    esac
done

for tool in "$cc_bin" "$cxx_bin" "$cmake_bin" "$ninja_bin" "$python_bin" git curl tar sha256sum; do
    command -v "$tool" >/dev/null 2>&1 || fail "required tool '$tool' was not found"
done
mkdir -p "$work_dir"
work_dir=$(cd "$work_dir" && pwd)
cc_path=$(command -v "$cc_bin")
cxx_path=$(command -v "$cxx_bin")

# The revision the stock packages, the Windows Vulkan DLL (Launcher/Build-DawnVulkan.ps1) and the
# Quest's Dawn (android/Build-QuestDawn.ps1) are built from.
revision=13abc3bc8ea2d3c2050f9e77a12d012108ceee24
archive_hash=713bea5b92d4f6c5175752fd7cbf1c3c5ce36598ff5dd98685d8a1216614ebba
flags=(
    -DCMAKE_BUILD_TYPE=Release
    -DCMAKE_POSITION_INDEPENDENT_CODE=ON
    -DDAWN_FETCH_DEPENDENCIES=ON
    -DDAWN_BUILD_MONOLITHIC_LIBRARY=STATIC
    -DBUILD_SHARED_LIBS=OFF
    -DDAWN_ENABLE_INSTALL=ON
    -DDAWN_BUILD_SAMPLES=OFF
    -DDAWN_BUILD_TESTS=OFF
    -DDAWN_BUILD_BENCHMARKS=OFF
    -DDAWN_USE_GLFW=OFF
    -DDAWN_USE_WAYLAND=ON
    -DDAWN_ENABLE_DESKTOP_GL=OFF
    -DDAWN_ENABLE_OPENGLES=OFF
    -DTINT_BUILD_TESTS=OFF
    -DTINT_BUILD_CMD_TOOLS=OFF
    -DTINT_BUILD_IR_BINARY=OFF
    -DDAWN_BUILD_PROTOBUF=OFF
)

patch_dir="$repo/aurora-main/patches/dawn"
patch_files=(
    "$patch_dir/apply.py"
    "$patch_dir/aurora_vulkan_hooks.h"
    "$patch_dir/aurora_vulkan_interop.inc"
    "$patch_dir/aurora_fdm.h"
    "$patch_dir/aurora_fdm.inc"
    "$repo/aurora-main/include/aurora/dawn_vulkan_abi.h"
    "$repo/aurora-main/include/aurora/dawn_fdm_abi.h"
)
# Hashed with LF line endings and each file's name, as Build-QuestDawn.ps1 does.
patch_hash=$(for file in "${patch_files[@]}"; do
    printf '%s\n' "$(basename "$file")"
    tr -d '\r' < "$file"
done | sha256sum | awk '{print $1}')
compiler_id=$("$cxx_path" --version 2>/dev/null | head -n 1 | tr -d '"\\')
cache_key=$(printf '%s|%s|%s|%s|%s|%s' "$revision" "$archive_hash" "$patch_hash" "$(uname -m)" \
    "$compiler_id" "${flags[*]}" | sha256sum | awk '{print $1}')

package="$work_dir/package"
manifest="$package/aurora-dawn.json"
library="$package/lib/libwebgpu_dawn.a"
[[ -f "$library" ]] || library="$package/lib64/libwebgpu_dawn.a"
if [[ "$force" -eq 0 && -f "$manifest" && -f "$library" ]]; then
    library_hash=$(sha256sum "$library" | awk '{print $1}')
    if grep -q "\"CacheKey\": \"$cache_key\"" "$manifest" &&
        grep -q "\"ArchiveSha256\": \"$library_hash\"" "$manifest"; then
        echo "Patched Dawn for Linux is up to date: $package"
        exit 0
    fi
fi

archive="$work_dir/dawn-source.tar.gz"
if [[ ! -f "$archive" ]]; then
    curl -fL --retry 3 -o "$archive.partial" "https://github.com/google/dawn/archive/$revision.tar.gz"
    mv "$archive.partial" "$archive"
fi
[[ "$(sha256sum "$archive" | awk '{print $1}')" == "$archive_hash" ]] ||
    fail "Dawn source archive does not match the pinned SHA-256; delete $archive and try again"

# The patches are applied to pristine sources: src/ is extracted again whenever the patches changed,
# while third_party/, which DAWN_FETCH_DEPENDENCIES fills, is kept.
source="$work_dir/dawn-$revision"
patch_marker="$source/aurora-patches.sha256"
if [[ ! -f "$patch_marker" || "$(cat "$patch_marker")" != "$patch_hash" ]]; then
    if [[ -d "$source" ]]; then
        rm -rf "$source/src"
        tar -xzf "$archive" -C "$work_dir" "dawn-$revision/src"
    else
        tar -xzf "$archive" -C "$work_dir"
    fi
    "$python_bin" "$patch_dir/apply.py" "$source"
    printf '%s' "$patch_hash" > "$patch_marker"
fi

build="$work_dir/build"
"$cmake_bin" -S "$source" -B "$build" -G Ninja \
    -DCMAKE_MAKE_PROGRAM="$(command -v "$ninja_bin")" \
    -DCMAKE_C_COMPILER="$cc_path" -DCMAKE_CXX_COMPILER="$cxx_path" \
    -DPython3_EXECUTABLE="$(command -v "$python_bin")" \
    "${flags[@]}" -DCMAKE_INSTALL_PREFIX="$package"
"$cmake_bin" --build "$build" --parallel "$jobs"
rm -rf "$package"
"$cmake_bin" --install "$build"
library="$package/lib/libwebgpu_dawn.a"
[[ -f "$library" ]] || library="$package/lib64/libwebgpu_dawn.a"
[[ -f "$library" ]] || fail "Dawn archive missing under $package"
# As the stock package: debug info would only make the archive several times larger.
strip_bin=$(dirname "$cc_path")/llvm-strip
[[ -x "$strip_bin" ]] || strip_bin=strip
"$strip_bin" --strip-debug "$library"

cat > "$manifest" <<EOF
{
  "SourceRevision": "$revision",
  "SourceSha256": "$archive_hash",
  "PatchSha256": "$patch_hash",
  "AuroraVulkanAbi": 1,
  "AuroraFdmAbi": 1,
  "Platform": "linux-$(uname -m)",
  "Compiler": "$compiler_id",
  "Flags": "${flags[*]}",
  "CacheKey": "$cache_key",
  "ArchiveSha256": "$(sha256sum "$library" | awk '{print $1}')"
}
EOF
echo "Patched Dawn for Linux ready: $package"
